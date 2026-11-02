"""Initialize the explicitly empty *board SD* via UDP, with readback verification.

No host disk handles are opened. The resident bootloader must be in PC INSTALL.
Uses a 64 MiB FAT32 superfloppy; the remainder of a larger card is unused.
"""
from pathlib import Path
import argparse
import hashlib
import ipaddress
import json
import secrets
import socket
import struct
import sys
import time
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
MAGIC = 0x31424453


def windows_interface(local_ip):
    """Resolve the NIC owning the bound IPv4 address without changing host routes."""
    import ctypes
    from ctypes import wintypes
    lookup = ctypes.WinDLL('iphlpapi').GetBestInterface
    lookup.argtypes = [wintypes.ULONG, ctypes.POINTER(wintypes.DWORD)]
    lookup.restype = wintypes.DWORD
    index = wintypes.DWORD()
    address = struct.unpack('<I', socket.inet_aton(local_ip))[0]
    result = lookup(address, ctypes.byref(index))
    if result or not index.value:
        raise OSError(result, 'Cannot resolve the selected Ethernet interface')
    return index.value


def packet(op, session, seq, lba=0, status=0, data=bytes(512)):
    if len(data) != 512:
        raise ValueError('one sector required')
    head = struct.pack('<6I', MAGIC, op, session, seq, lba, status)
    return head + struct.pack('<I', zlib.crc32(head + data)) + data


class Link:
    def __init__(self, local_ip, destination='255.255.255.255', timeout=2.0):
        local_ip = str(ipaddress.IPv4Address(local_ip))
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.interface_index = None
        try:
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            self.sock.bind((local_ip, 8081))
            if sys.platform == 'win32':
                self.interface_index = windows_interface(local_ip)
                # Winsock IP_UNICAST_IF (31) takes an interface index in network byte order.
                # Binding the source address alone did not select the correct broadcast NIC.
                self.sock.setsockopt(socket.IPPROTO_IP, 31, struct.pack('!I', self.interface_index))
        except BaseException:
            self.sock.close()
            raise
        self.destination = (destination, 8081)
        self.timeout, self.session, self.seq = timeout, secrets.randbits(32), 0

    def rpc(self, op, lba=0, data=bytes(512)):
        self.seq = (self.seq + 1) & 0xffffffff
        request = packet(op, self.session, self.seq, lba, data=data)
        for attempt in range(5):
            self.sock.sendto(request, self.destination)
            deadline = time.monotonic() + self.timeout
            while time.monotonic() < deadline:
                self.sock.settimeout(max(0.001, deadline - time.monotonic()))
                try:
                    reply, _ = self.sock.recvfrom(2048)
                except socket.timeout:
                    break
                if len(reply) != 540:
                    continue
                h = struct.unpack_from('<7I', reply)
                if h[:5] != (MAGIC, op | 0x80000000, self.session, self.seq, lba):
                    continue
                if h[6] != zlib.crc32(reply[:24] + reply[28:]):
                    continue
                if h[5]:
                    raise RuntimeError(f'board rejected op={op}, LBA={lba}')
                if op == 2 and reply[28:] != data:
                    raise RuntimeError(f'write acknowledgement differs at LBA={lba}')
                if op == 4 and reply[28:] != self.expected:
                    raise RuntimeError(f'write acknowledgement differs at LBA={lba}')
                return reply[28:]
        raise TimeoutError(f'no verified board reply: op={op}, LBA={lba}; check install mode and cable')


from sd_volume import SECTORS, make_volume  # noqa: E402  (shared with the simulator image)


def nibble_halves(sector):
    """Two 512-byte payloads with every nibble duplicated (n | n << 4)."""
    enc = bytes(v for b in sector for v in ((b & 15) * 17, (b >> 4) * 17))
    return enc[:512], enc[512:]


def write_sector(link, lba, data, nibble):
    if not nibble:
        link.rpc(2, lba, data)
        return
    first, second = nibble_halves(data)
    link.expected = data
    for attempt in range(3):
        link.rpc(3, lba, first)
        try:
            link.rpc(4, lba, second)
            return
        except RuntimeError:
            # A lost op-3 reply after a board-side reset clears the staging;
            # restage and retry the pair.
            if attempt == 2:
                raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--local-ip', required=True, help='IPv4 address of the PC Ethernet adapter')
    parser.add_argument('--destination', default='255.255.255.255')
    parser.add_argument('--source', type=Path, default=ROOT / 'sdcard')
    parser.add_argument('--initialize-empty', action='store_true', help='explicitly authorize replacing the board SD filesystem')
    parser.add_argument('--nibble', action='store_true',
                        help='send sector data nibble-duplicated (ops 3/4) for links that lose mixed-nibble bytes')
    args = parser.parse_args()
    link = Link(args.local_ip, args.destination)
    try:
        capacity, signature, abi = struct.unpack_from('<3I', link.rpc(0))
        if signature != 0x53445031 or abi != 1 or capacity < SECTORS:
            raise RuntimeError(f'unsupported SD: sectors={capacity}, signature={signature:x}, ABI={abi}')
        print(f'Board SD detected: {capacity * 512 / 1024**3:.2f} GiB; ABI={abi}', flush=True)
        probe = {'status': 'BOARD_SD_INFO_PASS', 'capacity_sectors': capacity, 'abi': abi,
                 'signature': f'{signature:08x}', 'local_ip': args.local_ip,
                 'interface_index': link.interface_index, 'destination': args.destination}
        (ROOT / 'build' / 'sd_probe_receipt.json').write_text(json.dumps(probe, indent=2), encoding='utf-8')
        if not args.initialize_empty:
            print('Probe only. No sectors written. Use --initialize-empty for the confirmed empty card.')
            return
        writes, hashes = make_volume(args.source)
        # INFO never touches the card. Check changing payload bits before invalidating
        # its boot sector; capacity-only probes missed a data-dependent link failure.
        patterns = ((bytes([0xff]) * 512, bytes(range(16)) * 32 if args.nibble else bytes(range(256)) * 2,
                     bytes(((i * 37 + 19) & 15) * 17 for i in range(512)) if args.nibble else
                     bytes((i * 37 + 19) & 255 for i in range(512))))
        for pattern in patterns:
            if struct.unpack_from('<3I', link.rpc(0, data=pattern)) != (capacity, signature, abi):
                raise RuntimeError('inconsistent board identity during transport preflight')
        print('Payload transport preflight passed.', flush=True)
        start = time.monotonic()
        # Invalid primary boot signature during provisioning; commit valid sector 0 last.
        write_sector(link, 0, bytes(512), args.nibble)
        order = sorted(k for k in writes if k != 0) + [0]
        digest = hashlib.sha256()
        for i, lba in enumerate(order, 1):
            data = writes[lba]
            write_sector(link, lba, data, args.nibble)
            if link.rpc(1, lba) != data:
                raise RuntimeError(f'independent readback mismatch at LBA={lba}')
            digest.update(struct.pack('<I', lba) + data)
            if i % 100 == 0 or i == len(order):
                print(f'Verified {i}/{len(order)} sectors ({time.monotonic() - start:.1f}s)', flush=True)
        report = {'status': 'BOARD_SD_WRITE_READBACK_PASS', 'capacity_sectors': capacity,
                  'local_ip': args.local_ip, 'interface_index': link.interface_index,
                  'volume_sectors': SECTORS, 'verified_sectors': len(order),
                  'verified_sector_digest': digest.hexdigest(), 'packages': hashes,
                  'elapsed_seconds': time.monotonic() - start}
        path = ROOT / 'build' / 'sd_provision_receipt.json'
        path.write_text(json.dumps(report, indent=2), encoding='utf-8')
        print(f'Completed and verified. Reset the board to select a game. Receipt: {path}')
    finally:
        link.sock.close()


if __name__ == '__main__':
    main()
