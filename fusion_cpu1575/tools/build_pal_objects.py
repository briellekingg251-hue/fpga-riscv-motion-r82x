"""Compile upstream PAL logic for the project RV32 ISA. This is not a runnable
game: SDL/board backends, libc syscalls, DDR and final link are separate gates.
"""
from pathlib import Path
import json
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import build_fw as cc
CORE='battle ending fight font game global input itemmenu magicmenu main map palcommon palette play res rngplay scene script text ui uibattle uigame yj1'.split()
def main():
    output=ROOT/'build/pal_rv32';output.mkdir(exist_ok=True)
    engine=ROOT/'third_party/sdlpal';sdl=ROOT/'third_party/SDL2/include'
    flags=[*cc.CFLAGS,'-std=gnu99','-D_GNU_SOURCE','-fno-strict-aliasing','-DUSE_SDL3=0',
           '-DPAL_HAS_GLSL=0','-DPAL_HAS_MP3=0','-DPAL_HAS_OGG=0','-DPAL_HAS_OPUS=0',
           '-DPAL_HAS_NATIVEMIDI=0','-DPAL_HAS_JOYSTICKS=0','-DPAL_HAS_TOUCH=0',
           '-I'+str(ROOT/'fw/pal/include'),'-I'+str(engine),'-I'+str(engine/'sdl_compat'),'-I'+str(sdl)]
    results={}
    for name in CORE:
        obj=output/(name+'.o')
        result=subprocess.run([str(cc.GCC),*flags,'-c',str(engine/(name+'.c')),'-o',str(obj)],capture_output=True,text=True)
        (output/(name+'.log')).write_text(result.stdout+result.stderr,encoding='utf-8')
        if result.returncode:
            print(result.stderr);raise SystemExit(f'RV32 compilation failed: {name}')
        sizes=cc.run([cc.SIZE,obj]).splitlines()[-1].split()
        results[name]={'text':int(sizes[0]),'data':int(sizes[1]),'bss':int(sizes[2])}
    for name in ['pal_touch','pal_sd']:
        cc.run([cc.GCC,*cc.CFLAGS,'-Werror','-Ifw','-c',ROOT/'fw/pal'/f'{name}.c','-o',output/f'{name}.o'])
    version=subprocess.run(['git','-C',str(engine),'rev-parse','HEAD'],capture_output=True,text=True,check=True).stdout.strip()
    report={'status':'RV32_PAL_LOGIC_COMPILE_PASS','isa':'rv32i_zmmul_zicsr','abi':'ilp32',
            'sdlpal_commit':version,'objects':results,
            'totals':{k:sum(v[k] for v in results.values()) for k in ['text','data','bss']},
            'final_link':'NOT_RUN','board_backend':'NOT_COMPLETE','full_game_cpu_execution':'NOT_RUN'}
    (output/'status.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
