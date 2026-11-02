"""Audit native Max Skew XML tables (the .rtr text omits these tables).

The native report's per-group worst-skew result covers its assertion; detailed
rows may be truncated. Keep resolution counts separate from detailed coverage.
"""
from pathlib import Path
import argparse,json,re,xml.etree.ElementTree as ET
R=Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('work');args=a.parse_args()
W=R/args.work;S=W;assert W.resolve().parent==R and S.resolve().parent==R
assert json.loads((W/'sta_receipt.json').read_text())['status']=='PASS'
resolved=json.loads((S/'native_cdc_resolution.json').read_text())
hardware=Path(json.loads((W/'flow_receipt.json').read_text())['hardware'])
assembly=json.loads((hardware/'ASSEMBLY.json').read_text())
extra=4 if assembly.get('dual_display_pose_preview') else 0
view=6 if assembly.get('camera_full_view') else 0
view_bits=38 if view else 0
# R80: camera FIFO Gray pointers, listed just before the view groups.
camg=assembly.get('camera_fifo_cdc') or [];cam=len(camg);cam_bits=sum(g['bits'] for g in camg)
assert resolved['FIFO_buses']==34+extra+view+cam and resolved['FIFO_first_D_bits']==122+3*extra+view_bits+cam_bits and resolved['VIDEO_Gray_first_D_bits']==32 and resolved['AI_Gray_first_D_bits']==128
fdc=hardware/'board_split.fdc';lines=fdc.read_text().splitlines()
group_file=hardware/'CDC_GROUPS.json'
if not group_file.exists():group_file=R/'reference/fusion_parent/physical/cdc_groups.json'
groups=json.loads(group_file.read_text())['groups']
assert len(groups)==36+extra+view+cam
if cam:assert groups[-6-cam:-6]==camg
if view:
 assert groups[-6:]==assembly['camera_view_cdc']
 expected_view=[('view/'+name,src,bits) for name,bits in [('write_fifo',7),('request_fifo',4),('response_fifo',8)] for src in ['wgray','rgray']]
 assert [(g['path'],g['source'],g['bits']) for g in groups[-6:]]==expected_view
expected={}
clocks={'CPU':'cpu_clk','PIX':'pix_clk','DDR':'ddrphy_sysclk','GPU':'gpu_clk','HDMI':'hdmi_clk','AI':'ai_clk'}
for g in groups:
    matches=[i for i,l in enumerate(lines,1) if l.startswith('set_max_skew ') and g['to_regex'] in l]
    assert len(matches)==1,g
    expected[matches[0]]=dict(g)
ai_lines=[(i,l) for i,l in enumerate(lines,1) if l.startswith('set_max_skew ') and 'u_pose/mmio/g1' in l]
assert len(ai_lines)==4
for i,l in ai_lines:
    nums=[int(x) for x in re.search(r'\((\d+(?:\|\d+)+)\)',l)[1].split('|')]
    assert len(nums)==32
    prefixes=[['det_drop_gray','det_dropped'],['pose_drop_gray','pose_dropped'],['captured_gray','captured'],['clock_gray','clock_ms']][min(nums)//32]
    expected[i]={'kind':'AI','bits':32,'indices':nums,'native_packed_clock_aliases':prefixes,'max_skew_ns':float(l.split()[1]),'launch_clock':'ai_clk'}
records=[];active=0
db=W/'report_timing/rtr.db';assert db.is_file()
for event,e in ET.iterparse(db,events=('start','end')):
    if event=='start' and e.tag=='table' and 'path_max_skew' in e.attrib.get('id',''):active+=1
    if event=='end':
        if e.tag=='table' and 'path_max_skew' in e.attrib.get('id',''):
            corner='slow' if '_slow_' in e.attrib['id'] else 'fast';seen=[]
            for row in e.findall('row'):
                summary=[x.text or '' for x in row.findall('data')]
                m=re.fullmatch(r'MaxSkew Path ([0-9.]+)ns, Line Num (\d+)',summary[0]);assert m,summary
                line=int(m[2]);assert line in expected and line not in seen;seen.append(line);g=expected[line]
                required=float(summary[10]);actual=float(summary[11]);slack=float(summary[1])
                assert required==g['max_skew_ns'] and actual<=required and slack>=0,(corner,line,summary)
                details=[];indices=set()
                for branch in row.findall('row'):
                    for path in branch.findall('row'):
                        values=[x.text or '' for x in path.findall('data')]
                        assert len(values)==14 and values[6]==g['launch_clock'],values
                        assert float(values[1])>=0 and float(values[2])==0,'CDC data path must be direct registered launch'
                        if g['kind']=='FIFO':
                            em=re.fullmatch(re.escape(g['path']+'/'+g['destination'])+r'\[(\d+)\]/[^/]+/D',values[5]);assert em,values
                            bit=int(em[1]);assert bit<g['bits'];indices.add(bit)
                            # Packed native FFs can share the displayed CLK name
                            # across adjacent bits; don't infer a bit-to-bit wire
                            # mismatch from that clock-pin alias.
                            assert re.fullmatch(re.escape(g['path']+'/')+'('+g['source']+'|'+g['source'].replace('gray','bin')+r')\[\d+\]/[^/]+/CLK',values[4]),values
                        elif g['kind']=='VIDEO_STATUS':
                            em=re.fullmatch(re.escape(g['path']+'/'+g['destination'])+r'\[(\d+)\]/[^/]+/D',values[5]);assert em,values
                            bit=int(em[1]);assert bit<16;indices.add(bit)
                            aliases=[g['source'],g['source'].replace('_gray','_count')]
                            assert re.fullmatch(r'u_sys/u_gpu/gpu/u_cmd/('+ '|'.join(aliases)+r')\[\d+\]/[^/]+/CLK',values[4]),values
                        else:
                            em=re.fullmatch(r'u_pose/mmio/g1\[(\d+)\]/[^/]+/D',values[5]);assert em,values
                            bit=int(em[1]);assert bit in g['indices'];indices.add(bit)
                            assert re.fullmatch(r'u_pose/ai/('+ '|'.join(g['native_packed_clock_aliases'])+r')\[\d+\]/[^/]+/CLK',values[4]),values
                        assert float(values[10])==required and float(values[11])<=actual+.001,(summary,values)
                        details.append({'startpoint':values[4],'endpoint':values[5],'launch':values[6],'capture':values[7],'data_delay_ns':float(values[9]),'relative_delay_ns':float(values[12]),'relative_CPR_ns':float(values[13])})
                assert details,'Assertion has no native routed path result'
                records.append({'corner':corner,'kind':g['kind'],'FDC_line':line,'expected_resolved_bits':g['bits'],'required_skew_ns':required,'actual_skew_ns':actual,'slack_ns':slack,'detailed_unique_indices':sorted(indices),'details_truncated':len(indices)<g['bits'],'paths':details})
            assert set(seen)==set(expected),(corner,seen)
            active-=1
        if not active:e.clear()
assert len(records)==2*(40+extra+view+cam)
out={'status':'PASS_NATIVE_ROUTED_MAX_SKEW_ASSERTIONS','native_report':str(db),'assertion_groups':40+extra+view+cam,'corners':['slow','fast'],'FIFO_groups':34+extra+view+cam,'FIFO_resolved_first_D_bits':122+3*extra+view_bits+cam_bits,'VIDEO_Gray_resolved_first_D_bits':32,'AI_groups':4,'AI_resolved_first_D_bits':128,'resolution_source':str(S/'native_cdc_resolution.json'),'minimum_assertion_slack_ns':min(r['slack_ns'] for r in records),'all_assertions_active_with_native_routed_paths':True,'detailed_rows_may_be_truncated':True,'scope':'Native routed skew assertions plus exact CCR resolution. Does not sign off reset/metastability/physical HMIC/IO contracts.','groups':records}
(W/'routed_cdc_audit.json').write_text(json.dumps(out,indent=2))
print(out['status'],out['assertion_groups'],'groups/2 corners; min slack',out['minimum_assertion_slack_ns'])
