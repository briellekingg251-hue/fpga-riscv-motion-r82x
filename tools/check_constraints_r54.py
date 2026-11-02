"""Gate the parent's physical flow. Known board warnings remain unresolved."""
from pathlib import Path
import sys,re,json,hashlib
w=Path(sys.argv[1]);files=list(w.rglob('*.ccr'))
hardware=Path(json.loads((w/'flow_receipt.json').read_text())['hardware'])
assembly=json.loads((hardware/'ASSEMBLY.json').read_text())
fdc_lines=(hardware/'board_split.fdc').read_text().splitlines()
known_layer8_pe={
    'u_pose/ai/pose_net/layer8/dot/page[0].column['+str(column)+'].tap['+str(tap)+'].cell_pe'
    for column in range(4) for tap in range(9)
}
region_targets=assembly.get('region_targets',{})
if 'view_overlay' in region_targets:
    assert assembly.get('camera_full_view') and region_targets['view_overlay']=='platform_top'
selected_layer8_pe=set(region_targets)&known_layer8_pe
if selected_layer8_pe:
    assert selected_layer8_pe==known_layer8_pe
    pe_regions={region_targets[name] for name in selected_layer8_pe}
    assert pe_regions in ({'platform_top'}, {'platform_left_top'})
    if pe_regions=={'platform_left_top'}:
        assert assembly.get('PE_region')=={'name':'platform_left_top','box':[0,114,81,255]}
        global_regions=[line for line in fdc_lines if line.startswith('define_global_attribute {PAP_REGION} ')]
        assert len(global_regions)==1
        assert global_regions[0].count('platform_left_top(0,114,81,255)[CLMA,CLMS,DRM,APM];')==1
default_region_lines=[i for i,line in enumerate(fdc_lines,1) if line=='define_attribute {i:*} {PAP_REGION} {platform_right}']
assert len(default_region_lines)==1
top_regions={'camera_inst1','clk_hdmi_inst','gpu_pll','hdmi_tx','overlay','pll162',
             'pllvid','preview','u_ai_pll','u_ddr','u_eth_pll','u_pose','u_rgmii','u_sys'}
# R54 copy of check_constraints.py: identical except that the Ethernet top
# instances are absent when ASSEMBLY declares ethernet_removed.
if assembly.get('ethernet_removed'):
    top_regions-={'u_eth_pll','u_rgmii'}
    assert not re.search(r'(?<![A-Za-z0-9_])(?:u_eth_pll|u_rgmii)\s*\(',(hardware/'fn_top.v').read_text())
top_source=(hardware/'fn_top.v').read_text()
if assembly.get('dual_display_pose_preview'):top_regions.add('lcd_pose')
if assembly.get('camera_full_view'):top_regions.update({'view','view_overlay','view_status'})
assert all(re.search(r'\b'+name+r'\s*\(',top_source) for name in top_regions)
def known_missing_drive(line):
    # CCR uses p:port; the resumed PCF console uses bare port. Same exact
    # diagnostic and port allowlist; no timing diagnostic is accepted here.
    return 'ConstraintEditor-2009:' in line and re.search(
        r'(?:p:|ConstraintEditor-2009:\s+)(?:sd_cs_n|sd_sck|sd_mosi|SCL_1|SDA_1|cam_rst_1)(?=\s|[.,])',line) is not None
resumed=None
if not files and (w/'resumed_constraint_inputs.json').exists():
    resumed=json.loads((w/'resumed_constraint_inputs.json').read_text())
    source=Path(resumed['source_work']);pcf=Path(resumed['pcf']);fdc=Path(resumed['fdc'])
    assert hashlib.sha256(pcf.read_bytes()).hexdigest()==resumed['pcf_sha256']
    assert hashlib.sha256(fdc.read_bytes()).hexdigest()==resumed['fdc_sha256']
    assert json.loads((source/'native_constraint_gate.json').read_text())['status']=='NO_NATIVE_ERRORS_KNOWN_BOARD_WARNINGS_INTERNAL_ONLY'
    log=(w/'pnr_console.log').read_text(errors='replace')
    commands=[l for l in pcf.read_text().splitlines() if l.startswith(('def_port ','def_inst_site '))]
    assert commands and all('Executing : '+l+' successfully' in log for l in commands),'Mapped physical attributes were not consumed'
    issues=[l for l in log.splitlines() if re.match(r'\s*[WCE]:',l)]
    unexpected=[l for l in issues if not ('C: ConstraintEditor-2002:' in l and any(x in l for x in ['Port mem_','Port phy_reset_n','Port camera_data_1[1]','Port camera_data_1[2]','Port camera_data_1[4]','Port camera_data_1[5]']) or known_missing_drive(l))]
    if unexpected:
        (w/'native_gate_blockers.json').write_text(json.dumps({'status':'UNRESOLVED_NATIVE_DIAGNOSTICS','acceptance':False,'diagnostics':unexpected,'note':'Hold optimization threshold warnings are not themselves proof of negative hold slack. Read routed STA.'},indent=2))
    assert not unexpected,unexpected
    files=list(source.rglob('*.ccr'))
assert files,'No native constraint-check .ccr; stop before mapping'
report={'status':'UNRESOLVED','files':[str(f) for f in files],'known_board_warnings':[]}
report['region_diagnostics_requiring_native_map_proof']=[]
if resumed:report.update(input_constraint_summary_reused=True,source_work=resumed['source_work'],native_PCF_all_commands_consumed=True)
for f in files:
    t=f.read_text(errors='replace')
    match=re.search(r'Found (\d+) error\(s\), (\d+) critical warning\(s\), (\d+) warning\(s\)',t)
    assert match,'Unrecognized native constraint summary: '+str(f)
    assert int(match[1])==0,'Native constraint errors: '+str(f)
    for line in t.splitlines():
        if not re.match(r'\s*[CW]:',line):continue
        region_names=assembly.get('region_targets',{'u_sys/u_gpu':'platform_top','u_pose/ai/det_net':'platform_top','u_sys/u_cpu':'cpu_region'})
        assert all(name in {'u_sys/u_gpu','u_sys/u_gpu/gpu/u_raster/u_bg','u_pose/ai/det_net','u_pose/ai/pose_net','u_sys/u_cpu','u_sys/u_cpu/soc/soc/improved.core','hdmi_tx','u_pose/ai/crop','view_overlay'} or
                   name in known_layer8_pe or
                   re.fullmatch(r'u_pose/ai/pose_net/layer(?:[0-9]|1[0-4])',name) for name in region_names)
        assert region_names['u_sys/u_cpu']=='cpu_region'
        if assembly.get('CPU_core_subregion'):
            assert region_names['u_sys/u_cpu/soc/soc/improved.core']=='cpu_core_region'
        assert all('define_attribute {i:'+name+'} {PAP_REGION} {'+region+'}' in fdc_lines
                   for name,region in region_names.items())
        region_warning=any(
            ('UserConstraintEditor-4009:' in line and ('i:'+inst+' is not GTP instance, the LOC/REGION constraint maybe not work.') in line) or
            ('ConstraintEditor-4026:' in line and ('PAP_REGION is already defined in i:'+inst+', new value '+region+' will overwrite the current value.') in line)
            for inst,region in region_names.items())
        wildcard_hierarchy_warning=('UserConstraintEditor-4009:' in line and
            ('board_split.fdc(line number: '+str(default_region_lines[0])+')]') in line and
            any(('i:'+inst+' is not GTP instance, the LOC/REGION constraint maybe not work.') in line for inst in top_regions))
        region_warning=region_warning or wildcard_hierarchy_warning
        if region_warning:
            # Small native probe proves this exact overwrite/hierarchy behavior.
            # Full build mapping gate separately requires every CPU leaf to resolve.
            report['region_diagnostics_requiring_native_map_proof'].append(line.strip())
            continue
        # Pin sharing and missing electrical strength/slew are board-review items,
        # explicitly retained for this INTERNAL implementation-only assessment.
        allowed=('ConstraintEditor-2002' in line and any(x in line for x in ['Port mem_','Port phy_reset_n'])) or known_missing_drive(line)
        # Exact configuration-data mux pads, verified in official PK04008
        # pp21-22 and UG040005 p17; mature rate30_1 PCF/PnR uses same pads.
        camera_share = {'camera_data_1[1]':'R23', 'camera_data_1[2]':'T23',
                        'camera_data_1[4]':'P26', 'camera_data_1[5]':'M26'}
        allowed = allowed or any(
            'ConstraintEditor-2002:' in line and
            ('| Port '+port+' has been placed at location '+pin+', whose type is share pin.') in line
            for port,pin in camera_share.items())
        hdmi_share={'tmds_data_p[2]':'N23','tmds_data_n[2]':'N24','tmds_data_p[1]':'P23',
                    'tmds_data_n[1]':'P24','tmds_data_p[0]':'R25','tmds_data_n[0]':'P25'}
        # Same exact configuration/shared pads used by the sealed P2 HDMI board.
        # Retain warnings as board-review items; no clock/STA/CDC error is allowed.
        allowed=allowed or any('ConstraintEditor-2002:' in line and
            ('| Port '+port+' has been placed at location '+pin+', whose type is share pin.') in line
            for port,pin in hdmi_share.items())
        assert allowed,'Unexpected constraint diagnostic: '+line
        report['known_board_warnings'].append(line.strip())
logs=[w/'flow.log',w/'run.log']+list(w.glob('*console.log'))
for f in logs:
    if f.exists():
        issues=[l for l in f.read_text(errors='replace').splitlines() if re.match(r'\s*[WCE]:\s+(DRC-|SDC-|STA-)',l)]
        assert not issues,'Native clock/DRC diagnostics remain; stop: '+str(issues[:10])
report['status']='NO_NATIVE_ERRORS_KNOWN_BOARD_WARNINGS_INTERNAL_ONLY'
(w/'native_constraint_gate.json').write_text(json.dumps(report,indent=2))
print(report['status'],'unresolved board warning count',len(report['known_board_warnings']))
