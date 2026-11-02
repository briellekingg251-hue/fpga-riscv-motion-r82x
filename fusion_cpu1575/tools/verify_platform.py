"""Reproducible offline gates. Does not program FPGA or access physical SD."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import argparse
from run_pds import read_timing_summary
ROOT=Path(__file__).resolve().parents[1]
BIN=Path('F:/Codex_workplace/tools/iverilog-sd-portable/ucrt64/bin')
TCC=Path('F:/Codex_workplace/tools/tcc-0.9.27-win64/tcc/tcc.exe')
def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--sd-only',action='store_true')
    parser.add_argument('--candidate',default='work_sd_net_s2')
    args=parser.parse_args()
    evidence=ROOT/'build/verification';evidence.mkdir(exist_ok=True)
    env=os.environ.copy();env['PATH']=str(BIN)+os.pathsep+env['PATH'];env['TMP']=env['TEMP']=str(ROOT/'build')
    results={}
    def run(name,args):
        p=subprocess.run([str(x) for x in args],cwd=ROOT,env=env,capture_output=True,text=True)
        (evidence/(name+'.log')).write_text(p.stdout+p.stderr,encoding='utf-8')
        results[name]='PASS' if p.returncode==0 else 'FAIL'
        print(name,results[name],flush=True)
        if p.returncode:raise RuntimeError(p.stdout+p.stderr)
    try:
        run('sd_protocol_game_startup',[sys.executable,'tests/test_sd_protocol.py'])
        run('timing_summary',[sys.executable,'tests/test_timing_summary.py'])
        run('manual_touch_regression',[sys.executable,'tools/test_touch_fw.py'])
        run('subway_game',[sys.executable,'tests/test_subway_sd.py'])
        run('gpu_v2_render',[sys.executable,'tests/test_gpu_v2_sd.py'])
        run('storage_boot_host',[sys.executable,'tests/run_storage_tests.py'])
        for name in ['sd_spi','sprite_cache']:
            run(name+'_compile',[BIN/'iverilog.exe','-g2012','-s','tb_'+name,'-o',f'build/{name}.vvp',f'tests/tb_{name}.v',f'rtl/storage/fn_{name}.v'])
            run(name,[BIN/'vvp.exe',f'build/{name}.vvp'])
        run('udp',[sys.executable,'tests/test_udp_link.py'])
        run('cardlink_compile',[TCC,'-Ifw','-o','build/cardlink_host.exe','tests/cardlink_host.c','fw/fat32.c'])
        run('cardlink', [ROOT/'build/cardlink_host.exe'])
        run('provision_emulated',[sys.executable,'tests/test_provision.py'])
        run('provision_preflight',[sys.executable,'tests/test_provision_preflight.py'])
        if not args.sd_only:
            run('pal_touch_compile',[TCC,'-Ifw','-o','build/pal_touch_host.exe','tests/pal_touch_host.c','fw/pal/pal_touch.c'])
            run('pal_touch',[ROOT/'build/pal_touch_host.exe'])
            run('pal_save_host',[sys.executable,'tests/test_pal_sd.py'])
            run('pal_cpu_components',[sys.executable,'tests/test_pal_cpu.py'])
            run('pal_navy_rv32_compile',[sys.executable,'tools/build_pal_navy_objects.py'])
        run('system_elaboration',[BIN/'iverilog.exe','-g2012','-s','fn_system','-o','build/system_check.vvp','build/fn_design.v'])
    finally:
        report={'offline_checks':results,'physical_sd_write':'NOT_RUN','game_on_board':'NOT_RUN',
                'pal_full_game_cpu_execution':'NOT_RUN','cpu_ddr_integration':'NOT_COMPLETE',
                'network_candidate_sta':read_timing_summary(ROOT/'pds'/args.candidate/'report_timing/fn_top.rtr'),
                'sources':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                 for top in ['fw','rtl','tools','tests'] for p in (ROOT/top).rglob('*') if p.is_file() and '__pycache__' not in p.parts}}
        (evidence/'status.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
if __name__=='__main__':main()
