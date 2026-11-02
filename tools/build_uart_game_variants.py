"""Build independent touch/pose SD executables and a DDR-resident dispatcher.
No resident ROM, RTL, card or player save is changed by this tool.
"""
from pathlib import Path
import argparse, hashlib, json, re, struct, sys, zlib
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'fusion_cpu1575/tools'))
import build_fw as cc
FW=ROOT/'variants_cpu1575/fw'

def header(data,sprites,palette,game_id,abi):
    raw=struct.pack('<7I',0x53444731,abi,len(data),zlib.crc32(data),
                    zlib.crc32(sprites),zlib.crc32(palette),game_id)
    return raw+struct.pack('<I',zlib.crc32(raw))

def main():
    a=argparse.ArgumentParser(description=__doc__)
    a.add_argument('--output',type=Path,required=True)
    args=a.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    build=out/'build';build.mkdir()
    common=['pose_ui.c','game_pose_service.c','pose_service.c','pose_mmio_source.c',
            'p2_algo.c','pose_input.c','game_runtime.c','start.S','jump.S','gpu.c',
            'uart.c','game_record.c','fat32.c','sd_spi.c']
    receipt={'status':'BUILT_NOT_DEPLOYED','CPU_Hz':157500000,'resident_ROM_changed':False,
             'shared_game_bin':False,'games':{},'source_sha256':{}}
    def compile_bin(name,sources,linker,defines):
        elf=build/(name+'.elf')
        cc.run([cc.GCC,*cc.CFLAGS,'-Werror',*defines,'-nostdlib','-nostartfiles',
                '-T',FW/linker,'-Wl,--gc-sections','-Wl,--no-warn-rwx-segments',
                f'-Wl,-Map={elf.with_suffix(".map")}', '-o',elf,
                *[FW/s for s in sources],'-lgcc'])
        binary=elf.with_suffix('.bin');cc.run([cc.OBJCOPY,'-O','binary',elf,binary])
        print(name,cc.run([cc.SIZE,elf]).strip(),flush=True)
        for s in sources+[linker,'soc.h','game_control.h']:
            receipt['source_sha256'][s]=hashlib.sha256((FW/s).read_bytes()).hexdigest()
        data=binary.read_bytes()
        if not 0<len(data)<=0x15c00:raise RuntimeError(name+' exceeds resident loader limit')
        return data
    for game,abi,id_,entry in [('FRUIT',1,0x46525549,['main.c','pose_blade_visual.c']),
                               ('SUBWAY',2,0x53554257,['subway_main.c','subway.c','subway_draw.c'])]:
        dst=out/'sdcard/GAMES'/game;dst.mkdir(parents=True)
        original=ROOT/'fusion_cpu1575/sdcard/GAMES'/game
        sprites=(original/'SPRITES.BIN').read_bytes();palette=(original/'PALETTE.BIN').read_bytes()
        (dst/'SPRITES.BIN').write_bytes(sprites);(dst/'PALETTE.BIN').write_bytes(palette)
        bins={}
        for mode in ('TOUCH','POSE'):
            flags=['-DFN_SUBWAY_TILE_ROWS=8']
            if mode=='TOUCH':flags+=['-DFN_POSE_PRODUCTION=0','-DFN_TOUCH_VERSION=1']
            else:flags+=['-DFN_POSE_PRODUCTION=1','-DFN_GPU_POSE_YIELD=1',
                         '-DFN_DUAL_POSE_PIP=1','-DFN_POSE_DEBUG=1']
            data=compile_bin(game.lower()+'_'+mode.lower(),entry+common,'game_link.ld',flags)
            (dst/(mode+'.BIN')).write_bytes(data)
            (dst/(mode+'.MAN')).write_bytes(header(data,sprites,palette,id_,abi))
            bins[mode]={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),
                        'AI_service_compiled':mode=='POSE','debug_UART':mode=='POSE'}
        if bins['TOUCH']['sha256']==bins['POSE']['sha256']:raise RuntimeError('variants identical')
        data=compile_bin(game.lower()+'_dispatch',
                         ['variant_start.S','variant_dispatch.c','uartlink.c','jump.S',
                          'uart.c','fat32.c','sd_spi.c','game_runtime.c'],'variant_link.ld',[f'-DVARIANT_GAME_ID={id_}u'])
        (dst/'GAME.BIN').write_bytes(data)
        (dst/'MANIFEST.BIN').write_bytes(header(data,sprites,palette,id_,abi))
        receipt['games'][game]=bins
    (out/'BUILD.json').write_text(json.dumps(receipt,indent=2)+'\n')
    hashes={p.relative_to(out).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(out.rglob('*')) if p.is_file()}
    (out/'SHA256.json').write_text(json.dumps(hashes,indent=2)+'\n')
    print('BUILT',out,flush=True)
if __name__=='__main__':main()
