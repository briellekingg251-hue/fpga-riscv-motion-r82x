"""Install the SD game volume through the board UART (fw/uartlink.c, fn_uart_link).

The board must be in PC INSTALL mode (empty card, or the menu's PC INSTALL).
Every sector is sent as one CRC-protected frame; the board writes it, reads it
back, compares, and returns the CRC of the read-back data, which is checked
here too.  The boot sector is invalidated first and committed last, exactly
like the UDP installer.  Progress is saved, so --resume continues an
interrupted install of the same package set.

usage: python tools/install_uart.py --port COM15 --initialize-empty [--baud 921600] [--resume]
       python tools/install_uart.py --port COM15 --update

--update rewrites only sectors whose CRC differs on the card, never touches
SAVE*.DAT (player saves and high scores), and refuses to run when the FAT
differs, because then files would have moved and saves would be lost.
"""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import struct
import sys
import time
import zlib
from ctypes import wintypes
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from sd_volume import FAT_SIZE, FATS, RESERVED, SECTORS, make_volume, make_volume_with_owners  # noqa: E402

CPU_HZ = 157500000  # must match fw/soc.h CPU_CLOCK_HZ (157.5 MHz build)
PROGRESS = ROOT / 'build' / 'uart_install_progress.json'


class SerialPort:
    """Minimal Win32 COM port (8N1, no flow control, DTR/RTS off)."""

    class DCB(ctypes.Structure):
        _fields_ = [('DCBlength', wintypes.DWORD), ('BaudRate', wintypes.DWORD), ('flags', wintypes.DWORD),
                    ('wReserved', wintypes.WORD), ('XonLim', wintypes.WORD), ('XoffLim', wintypes.WORD),
                    ('ByteSize', ctypes.c_ubyte), ('Parity', ctypes.c_ubyte), ('StopBits', ctypes.c_ubyte),
                    ('XonChar', ctypes.c_char), ('XoffChar', ctypes.c_char), ('ErrorChar', ctypes.c_char),
                    ('EofChar', ctypes.c_char), ('EvtChar', ctypes.c_char), ('wReserved1', wintypes.WORD)]

    class TIMEOUTS(ctypes.Structure):
        _fields_ = [('ReadIntervalTimeout', wintypes.DWORD), ('ReadTotalTimeoutMultiplier', wintypes.DWORD),
                    ('ReadTotalTimeoutConstant', wintypes.DWORD), ('WriteTotalTimeoutMultiplier', wintypes.DWORD),
                    ('WriteTotalTimeoutConstant', wintypes.DWORD)]

    def __init__(self, port: str, baud: int):
        k = ctypes.WinDLL('kernel32', use_last_error=True)
        self.k = k
        k.CreateFileW.restype = wintypes.HANDLE
        self.h = k.CreateFileW('\\\\.\\' + port, 0xC0000000, 0, None, 3, 0, None)
        if self.h in (None, wintypes.HANDLE(-1).value):
            raise OSError(ctypes.get_last_error(), f'cannot open {port} (close other programs using it)')
        self.set_baud(baud)
        self.timeout(500)

    def set_baud(self, baud: int):
        dcb = self.DCB()
        dcb.DCBlength = ctypes.sizeof(dcb)
        if not self.k.GetCommState(self.h, ctypes.byref(dcb)):
            raise OSError(ctypes.get_last_error(), 'GetCommState')
        dcb.BaudRate, dcb.flags, dcb.ByteSize, dcb.Parity, dcb.StopBits = baud, 1, 8, 0, 0
        if not self.k.SetCommState(self.h, ctypes.byref(dcb)):
            raise OSError(ctypes.get_last_error(), f'SetCommState {baud}')
        self.purge()

    def timeout(self, ms: int):
        t = self.TIMEOUTS(0, 0, ms, 0, 2000)
        self.k.SetCommTimeouts(self.h, ctypes.byref(t))

    def purge(self):
        self.k.PurgeComm(self.h, 0x0F)

    def write(self, data: bytes):
        n = wintypes.DWORD()
        if not self.k.WriteFile(self.h, data, len(data), ctypes.byref(n), None) or n.value != len(data):
            raise OSError(ctypes.get_last_error(), 'WriteFile')

    def read(self, size: int) -> bytes:
        buf = ctypes.create_string_buffer(size)
        n = wintypes.DWORD()
        self.k.ReadFile(self.h, buf, size, ctypes.byref(n), None)
        return buf.raw[:n.value]

    def close(self):
        self.k.CloseHandle(self.h)


class UartLink:
    def __init__(self, port: SerialPort):
        self.port, self.seq = port, 0

    def rpc(self, op: int, lba: int = 0, payload: bytes = bytes(512), attempts: int = 6) -> tuple[int, tuple]:
        body = struct.pack('<BBI', op, 0, lba) + payload.ljust(512, b'\0')
        for _ in range(attempts):
            self.seq = (self.seq + 1) & 255
            body = struct.pack('<BBI', op, self.seq, lba) + body[6:]
            self.port.purge()
            self.port.write(b'PL' + body + struct.pack('<I', zlib.crc32(body)))
            reply = self.port.read(25)
            if len(reply) != 25 or reply[:2] != b'LP':
                continue
            rop, rseq, rlba, status = struct.unpack_from('<BBIB', reply, 2)
            info = struct.unpack_from('<3I', reply, 9)
            if struct.unpack_from('<I', reply, 21)[0] != zlib.crc32(reply[2:21]):
                continue
            if rop != (op | 0x80) or rseq != self.seq or rlba != lba:
                continue
            if status == 2:
                continue  # frame damaged on the way in: resend
            return status, info
        raise TimeoutError(f'no valid reply: op={op} lba={lba}')


def card_crc(link, lba, count):
    link.port.timeout(1500)
    try:
        status, info = link.rpc(3, lba, struct.pack('<I', count))
    finally:
        link.port.timeout(500)
    if status:
        raise RuntimeError(f'board could not read LBA {lba}+{count}')
    return info[0]


def runs(lbas, limit):
    """Split sorted LBAs into runs of consecutive sectors, at most limit long."""
    run = []
    for lba in lbas:
        if run and (lba != run[-1] + 1 or len(run) == limit):
            yield run
            run = []
        run.append(lba)
    if run:
        yield run


def update_card(link, source):
    writes, hashes, owners = make_volume_with_owners(source)
    keep = {lba for lba, owner in owners.items() if owner.rsplit('/', 1)[1].startswith('SAVE')}
    fat = [lba for lba in sorted(writes) if RESERVED <= lba < RESERVED + FAT_SIZE * FATS]
    for run in runs(fat, 64):
        if card_crc(link, run[0], len(run)) != zlib.crc32(b''.join(writes[x] for x in run)):
            raise RuntimeError('FAT differs from the new package layout: files would move and saves would be lost. '
                               'Back up saves first; only --initialize-empty can install this layout.')
    print('FAT layout unchanged; comparing sectors (saves are never written)', flush=True)
    todo = [lba for lba in sorted(writes) if lba not in keep and lba != 0]
    t0, changed, checked = time.monotonic(), 0, 0
    for run in runs(todo, 64):
        expected = zlib.crc32(b''.join(writes[x] for x in run))
        if card_crc(link, run[0], len(run)) != expected:
            for lba in run:
                status, info = link.rpc(1, lba, writes[lba])
                if status or info[0] != zlib.crc32(writes[lba]):
                    raise RuntimeError(f'write/read-back failed at LBA {lba}')
                changed += 1
        checked += len(run)
        if checked % 6400 < len(run):
            print(f'Checked {checked}/{len(todo)} sectors, rewrote {changed} ({time.monotonic() - t0:.0f}s)', flush=True)
    if card_crc(link, 0, 1) != zlib.crc32(writes[0]):
        status, info = link.rpc(1, 0, writes[0])
        if status or info[0] != zlib.crc32(writes[0]):
            raise RuntimeError('boot sector update failed')
        changed += 1
    receipt = {'status': 'BOARD_SD_UART_UPDATE_PASS', 'checked_sectors': len(todo) + 1, 'rewritten_sectors': changed,
               'kept_save_sectors': len(keep), 'packages': hashes, 'elapsed_seconds': time.monotonic() - t0}
    (ROOT / 'build' / 'sd_update_receipt.json').write_text(json.dumps(receipt, indent=2), encoding='utf-8')
    print(f'Update complete: {changed} sectors rewritten and verified, {len(keep)} save sectors untouched.')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--port', default='COM15')
    parser.add_argument('--baud', type=int, default=921600)
    parser.add_argument('--source', type=Path, default=ROOT / 'sdcard')
    parser.add_argument('--initialize-empty', action='store_true',
                        help='explicitly authorize replacing the board SD filesystem')
    parser.add_argument('--resume', action='store_true', help='continue the previous interrupted install')
    parser.add_argument('--update', action='store_true',
                        help='rewrite only changed sectors of an installed card, keeping all SAVE*.DAT files')
    args = parser.parse_args()
    port = SerialPort(args.port, 115200)
    link = UartLink(port)
    try:
        switched = False
        try:
            status, (capacity, signature, abi) = link.rpc(0, attempts=3)
        except TimeoutError:
            # The board may still run at the fast rate from an earlier session.
            port.set_baud(args.baud)
            status, (capacity, signature, abi) = link.rpc(0)
            switched = True
        if status or signature != 0x53445031 or capacity < SECTORS:
            raise RuntimeError(f'unsupported board/card: status={status} capacity={capacity} sig={signature:x}')
        print(f'Board SD detected over UART: {capacity * 512 / 1024**3:.2f} GiB', flush=True)
        if args.baud != 115200 and not switched:
            divider = round(CPU_HZ / args.baud)
            status, _ = link.rpc(2, 0, struct.pack('<I', divider))
            if status:
                raise RuntimeError('board rejected the baud rate')
            time.sleep(0.05)
            port.set_baud(args.baud)
            if link.rpc(0)[1][0] != capacity:
                raise RuntimeError('identity changed after the baud switch')
            print(f'UART switched to {args.baud} baud (board divider {divider})', flush=True)
        if args.update:
            update_card(link, args.source)
            return
        if not args.initialize_empty:
            print('Probe only. No sectors written. Use --initialize-empty for the confirmed empty card.')
            return
        writes, hashes = make_volume(args.source)
        order = sorted(k for k in writes if k != 0) + [0]
        digest_key = hashlib.sha256(b''.join(struct.pack('<I', k) + writes[k] for k in order)).hexdigest()
        start = 0
        if args.resume and PROGRESS.exists():
            saved = json.loads(PROGRESS.read_text())
            if saved.get('volume') == digest_key:
                start = saved['next']
                print(f'Resuming at sector {start}/{len(order)}', flush=True)
        if start == 0:
            if link.rpc(1, 0, bytes(512))[0]:   # invalidate the boot sector first
                raise RuntimeError('board rejected LBA 0')
        t0 = time.monotonic()
        for i in range(start, len(order)):
            lba = order[i]
            status, info = link.rpc(1, lba, writes[lba])
            if status or info[0] != zlib.crc32(writes[lba]):
                raise RuntimeError(f'write/read-back failed at LBA {lba} (status {status})')
            if i % 500 == 0 or i == len(order) - 1:
                PROGRESS.write_text(json.dumps({'volume': digest_key, 'next': i + 1}))
                rate = (i + 1 - start) / max(time.monotonic() - t0, 1e-3)
                print(f'Verified {i + 1}/{len(order)} sectors, {rate:.0f}/s, '
                      f'about {(len(order) - i - 1) / max(rate, 1e-3) / 60:.1f} min left', flush=True)
        receipt = {'status': 'BOARD_SD_UART_WRITE_READBACK_PASS', 'capacity_sectors': capacity,
                   'baud': args.baud, 'volume_sectors': SECTORS, 'verified_sectors': len(order),
                   'volume_digest': digest_key, 'packages': hashes,
                   'elapsed_seconds': time.monotonic() - t0}
        (ROOT / 'build' / 'sd_provision_receipt.json').write_text(json.dumps(receipt, indent=2), encoding='utf-8')
        PROGRESS.unlink(missing_ok=True)
        print('Completed and verified. Reset the board to open the game menu.')
    finally:
        port.close()


if __name__ == '__main__':
    main()
