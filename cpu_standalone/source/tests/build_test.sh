#!/bin/bash
# build_test.sh <name.S> [march] -> <name>.hex
set -e
N=${1%.S}; M=${2:-rv32i_zmmul_zbc}
D=$(dirname $0)
riscv-none-elf-gcc -march=$M -mabi=ilp32 -mno-relax -nostdlib -nostartfiles -T $D/../fw_isa/src/link.ld $D/$1 -o $D/$N.elf
python - "$D/$N.elf" "$D/$N.hex" <<'PY'
import sys,struct
raw=open(sys.argv[1],'rb').read(); hd=struct.unpack_from('<16sHHIIIIIHHHHHH',raw)
ram=bytearray(131072)
for i in range(hd[10]):
    k,off,va,pa,sz,msz,fl,al=struct.unpack_from('<IIIIIIII',raw,hd[5]+i*hd[9])
    if k!=1: continue
    b=pa-0x80000000; ram[b:b+sz]=raw[off:off+sz]
open(sys.argv[2],'w').write(''.join('%08x\n'%int.from_bytes(ram[i:i+4],'little') for i in range(0,len(ram),4)))
PY
echo built $N.hex
