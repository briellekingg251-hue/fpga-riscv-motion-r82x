"""Compile the PA PAL port for our RV32 CPU using Navy's fixed-point path.
No final link or board/game acceptance is implied by this object build.
"""
from pathlib import Path
import json
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import build_fw as cc
def main():
    output=ROOT/'build/pal_navy_rv32';output.mkdir(exist_ok=True)
    engine=ROOT/'third_party/pal-navy';navy=ROOT/'third_party/navy-apps'
    flags=[*cc.CFLAGS,'-std=gnu99','-D_GNU_SOURCE','-D__NAVY__','-DPAL_CLASSIC=1',
           '-fno-strict-aliasing','-I'+str(engine/'include'),
           '-I'+str(navy/'libs/libminiSDL/include'),'-I'+str(navy/'libs/libfixedptc/include')]
    results={}
    for source in sorted((engine/'src').rglob('*.c')):
        if 'sound' in source.parts or source.name=='aviplay.c':continue
        name=str(source.relative_to(engine/'src')).replace('\\','/').replace('/','_')[:-2]
        obj=output/(name+'.o')
        result=subprocess.run([str(cc.GCC),*flags,'-c',str(source),'-o',str(obj)],capture_output=True,text=True)
        (output/(name+'.log')).write_text(result.stdout+result.stderr,encoding='utf-8')
        if result.returncode:print(result.stderr);raise SystemExit(f'PAL Navy RV32 compilation failed: {name}')
        sizes=cc.run([cc.SIZE,obj]).splitlines()[-1].split()
        results[name]={'text':int(sizes[0]),'data':int(sizes[1]),'bss':int(sizes[2])}
    version=subprocess.run(['git','-C',str(engine),'rev-parse','HEAD'],capture_output=True,text=True,check=True).stdout.strip()
    report={'status':'PAL_NAVY_RV32_LOGIC_COMPILE_PASS','isa':'rv32i_zmmul_zicsr','abi':'ilp32',
            'pal_navy_commit':version,'objects':results,
            'totals':{k:sum(v[k] for v in results.values()) for k in ['text','data','bss']},
            'arithmetic':'Navy fixedptc / no FPU required',
            'final_link':'NOT_RUN','board_backend':'NOT_COMPLETE','full_game_cpu_execution':'NOT_RUN'}
    (output/'status.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(report['status'],report['totals'])
if __name__=='__main__':main()
