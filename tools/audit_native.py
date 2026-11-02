"""Strict native split FIFO and video Gray endpoints + registered launch proof."""
from pathlib import Path
import json,re,sys
R=Path(__file__).resolve().parents[1]
W=R/sys.argv[1]
assert W.resolve().parent==R.resolve()
hardware=Path(json.loads((W/'flow_receipt.json').read_text())['hardware'])
assembly=json.loads((hardware/'ASSEMBLY.json').read_text())
group_file=hardware/'CDC_GROUPS.json'
if not group_file.exists():group_file=R/'reference/fusion_parent/physical/cdc_groups.json'
info=json.loads(group_file.read_text());groups=info['groups']
extra=4 if assembly.get('dual_display_pose_preview') else 0
view=6 if assembly.get('camera_full_view') else 0
view_bits=38 if view else 0
# R80: camera FIFO Gray pointers, listed just before the view groups.
camg=assembly.get('camera_fifo_cdc') or [];cam=len(camg);cam_bits=sum(g['bits'] for g in camg)
if cam:assert groups[-6-cam:-6]==camg
if view:
 assert groups[-6:]==assembly['camera_view_cdc']
 expected=[('view/'+name,src,bits) for name,bits in [('write_fifo',7),('request_fifo',4),('response_fifo',8)] for src in ['wgray','rgray']]
 assert [(g['path'],g['source'],g['bits']) for g in groups[-6:]]==expected
assert len(groups)==36+extra+view+cam
assert sum(g['bits'] for g in groups if g['kind']=='FIFO')==122+3*extra+view_bits+cam_bits
t=(W/'constraint_check/constraint_check.ccr').read_text()
vm=(W/'synthesize/fn_top_syn.vm').read_text()
modules={m[1]:m[0] for m in re.finditer(r'(?ms)^module (\w+)\b.*?endmodule',vm)}
def body(path):
 typ='fn_top'
 for inst in path.split('/'):
  # Native region annotations precede the module instance on the same line.
  m=re.search(r'(?m)^\s*(?:\(\*[^\n]*?\*\)\s*)*(\w+)\s+'+re.escape(inst)+r'\s*\(',modules[typ]);assert m,(typ,inst);typ=m[1];assert typ in modules
 return modules[typ]
def ff(b,net):
 blocks=re.findall(r'(?s)GTP_DFF\w*.*?\);',b)
 q=[x for x in blocks if re.search(r'\.Q\s*\(\s*'+re.escape(net)+r'\s*\)',x)];assert len(q)==1,(net,len(q));return q[0]
def d(b):return re.search(r'\.D\s*\(\s*([^()]+?)\s*\)',b)[1]
records=[]
for g in groups:
 s=t[t.index("I: The pattern '"+g['to_regex']+"'"):]
 m=re.search(r'match (\d+) objects below:\n((?:\s*I: pin [^\n]+\n)+)',s);assert m,g
 pins=re.findall(r'I: pin ([^\n]+)',m[2]);assert len(pins)==g['bits'],(g,pins)
 indices=[]
 for pin in pins:
  m=re.fullmatch(re.escape(g['path']+'/'+g['destination'])+r'(?:\[\d+:0\]/D\[(\d+)\]|\[(\d+)\]/D)',pin);assert m,pin;indices.append(int(m[1] or m[2]))
 assert sorted(indices)==list(range(g['bits']))
 b=body(g['path'])
 for i in range(g['bits']):
  sink=ff(b,f"{g['destination']}[{i}]");actual=d(sink)
  if g['kind']=='FIFO':
   expected=f"{g['source']}[{i}]";alias=g['source'].replace('gray','bin')+f'[{i}]'
   assert actual==expected or (i==g['bits']-1 and actual==alias),(g,actual)
   source=ff(b,actual);sc='wclk' if g['source']=='wgray' else 'rclk';dc='rclk' if sc=='wclk' else 'wclk'
   assert re.search(r'\.CLK\s*\(\s*'+sc+r'\s*\)',source)
   assert re.search(r'\.CLK\s*\(\s*'+dc+r'\s*\)',sink)
  else:
   assert actual=='pix_'+g['source']+f'[{i}]',(g,actual)
   cb=body('u_sys/u_gpu/gpu/u_cmd');sn=g['source']+f'[{i}]'
   try:source=ff(cb,sn)
   except AssertionError:
    assert i==15;source=ff(cb,g['source'].replace('_gray','_count')+f'[{i}]')
   assert re.search(r'\.CLK\s*\(\s*clk\s*\)',source)
   assert re.search(r'\.CLK\s*\(\s*clk\s*\)',sink)
 records.append({'kind':g['kind'],'path':g['path'],'destination':g['destination'],'bits':g['bits'],'pins':pins})
ai_pins=re.findall(r'I: pin (u_pose/mmio/g1[^\n]+)',t);ai=[]
for pin in ai_pins:
 m=re.fullmatch(r'u_pose/mmio/g1(?:\[127:0\]/D\[(\d+)\]|\[(\d+)\]/D)',pin);assert m,pin;ai.append(int(m[1] or m[2]))
assert sorted(ai)==list(range(128))
j={'status':'PASS_SPLIT_NATIVE_CCR_AND_REGISTERED_GRAY','FIFO_buses':34+extra+view+cam,'FIFO_first_D_bits':122+3*extra+view_bits+cam_bits,'VIDEO_Gray_first_D_bits':32,'AI_Gray_first_D_bits':128,'assertion_groups':40+extra+view+cam,'groups':records,'routed_skew':'PENDING'}
(W/'native_cdc_resolution.json').write_text(json.dumps(j,indent=2));print(j['status'],j['assertion_groups'],'assertions; exact registered first-D checked')
