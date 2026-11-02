"""R51 HDMI reset audit: pixel-clock shared release and pixel-falling-edge lane releases.

Same exact exception/chain proof as audit_hdmi_reset.py, but the shared
three-stage release must be clocked by pixelclk and each lane's final release
flip-flop by the inverted pixelclk (falling edge), driving OSERDES RST.
"""
from pathlib import Path
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
work = ROOT / sys.argv[1]
assert work.resolve().parent == ROOT.resolve()
hardware = Path(json.loads((work/'flow_receipt.json').read_text())['hardware'])
assembly = json.loads((hardware/'ASSEMBLY.json').read_text())
assert assembly['HDMI_serial_reset_fix']
assert assembly['HDMI_serial_reset_architecture'] == 'PIXEL_POSEDGE_SHARED_THREE_STAGE_PLUS_FOUR_PIXEL_NEGEDGE_LOCAL_RELEASES'
regex = assembly['HDMI_reset_exception_regex']
fdc = (hardware/'board_split.fdc').read_text()
assert fdc.count('set_false_path -to [get_pins -hierarchical -regexp {'+regex+'}]') == 1
assert [l for l in fdc.splitlines() if l.startswith('set_false_path')] == [
    'set_false_path -to [get_pins -hierarchical -regexp {'+regex+'}]']
ccr_file = work/'constraint_check/constraint_check.ccr'
vm_file = work/'synthesize/fn_top_syn.vm'
t = ccr_file.read_text()
s = t[t.index("I: The pattern '"+regex+"'"):]
m = re.search(r'match (\d+) objects below:\n((?:\s*I: pin [^\n]+\n)+)',s)
assert m and int(m[1]) == 5, 'Reset exception must match one 3-bit shared clear and four scalar local clears'
pins = re.findall(r'I: pin ([^\n]+)',m[2])
assert len(set(pins)) == 5 and all(re.fullmatch(regex,p) for p in pins)
vm = vm_file.read_text()
modules = {m[1]:m[0] for m in re.finditer(r'(?ms)^module (\w+)\b.*?endmodule',vm)}


def instance(b,name):
    m = re.search(r'(?m)^\s*(?:\(\*[^\n]*?\*\)\s*)*(\w+)\s+\\?'+re.escape(name)+r'\s*\((.*?)\);',b,re.S)
    assert m,(name,'missing hierarchy')
    return m[1],m[2]


def body(path):
    typ = 'fn_top'
    for name in path.split('/'):
        typ,_ = instance(modules[typ],name)
    return modules[typ]


def port(block,name):
    m = re.search(r'\.'+name+r'\s*\(\s*([^()]+?)\s*\)',block)
    assert m,(name,block)
    return m[1].strip().lstrip('\\')


def aliases(b,net):
    values = {net}
    pairs = re.findall(r'\bassign\s+(\w+(?:\[\d+\])?)\s*=\s*(\w+(?:\[\d+\])?)\s*;',b)
    for _ in pairs:
        for left,right in pairs:
            if left in values or right in values:
                values.update([left,right])
    return values


rows = []
tx = body('hdmi_tx')
shared_typ,shared_connection = instance(tx,'serial_release')
shared = modules[shared_typ]
shared_ffs = re.findall(r'(?s)GTP_DFF\w*.*?\);',shared)
assert len(shared_ffs) == 3
assert re.findall(r'SDC constraint : \(object (\w+)\)',shared) == ['C']*3, 'Shared data/clock pins must not be exempted'
shared_clocks = {port(f,'CLK') for f in shared_ffs}
assert len(shared_clocks) == 1 and port(shared_connection,next(iter(shared_clocks))) == 'pixelclk'
assert all(f.startswith('GTP_DFF_C') for f in shared_ffs)
assert len({port(f,'C') for f in shared_ffs}) == 1
first = [f for f in shared_ffs if port(f,'D') == "1'b1"]
assert len(first) == 1
chain = first
for _ in range(2):
    following = [f for f in shared_ffs if port(f,'D') in aliases(shared,port(chain[-1],'Q'))]
    assert len(following) == 1
    chain.append(following[0])
assert len(set(chain)) == 3 and 'serial_reset_n' in aliases(shared,port(chain[-1],'Q'))
shared_net = port(shared_connection,'serial_reset_n')
assert [p for p in pins if p.startswith('hdmi_tx/serial_release/')] == ['hdmi_tx/serial_release/ready[2:0]/C']


def hier_port(block, name):
    """Net connected to a (possibly escaped, hierarchical) port name."""
    m = re.search(r'\.\\?' + re.escape(name) + r'\s*\(\s*([^()]+?)\s*\)', block)
    assert m, (name, 'port connection missing')
    return m[1].strip().lstrip('\\')


inverter_lanes, lane_clock_nets = [], {}
for lane in ['clockserializer']+['encoder['+str(i)+'].dataserializer' for i in range(3)]:
    path = 'hdmi_tx/'+lane
    subset = [p for p in pins if p.startswith(path+'/serial_reset/')]
    assert len(subset) == 1
    serial = body(path)
    _,lane_connection = instance(tx,lane)
    assert port(lane_connection,'serial_reset_n') == shared_net
    typ,connection = instance(serial,'serial_reset')
    b = modules[typ]
    ffs = re.findall(r'(?s)GTP_DFF\w*.*?\);',b)
    assert len(ffs) == 1, (path,'one preserved local release required')
    assert re.findall(r'SDC constraint : \(object (\w+)\)',b) == ['C'], 'Local release data/clock pins must not be exempted'
    clocks = {port(f,'CLK') for f in ffs}
    assert len(clocks) == 1
    clock_net = next(iter(clocks))
    # Falling-edge release.  ADS keeps ONE inverter of the lane clock port
    # (connected to pixelclk) in one lane module and exports its output; the
    # other lanes receive that same net through hierarchy ports.  Resolve each
    # lane FF clock to its hdmi_tx-level net and require one shared source.
    clock_inv = [g for g in re.findall(r'(?s)GTP_INV\s+.*?\);',b) if port(g,'Z') == clock_net]
    assert len(clock_inv) <= 1, (path,'ambiguous lane release clock inverter')
    header = b[:b.index(');')]
    if clock_inv:
        assert port(clock_inv[0],'I') == 'clk' and port(connection,'clk') == 'pixelclk', (path,'inverter input is not pixelclk')
        assert re.search(r'\boutput\s+' + re.escape(clock_net) + r'\s*,?', header), (path,'inverted clock not exported')
        inverter_lanes.append(path)
    else:
        assert re.search(r'\binput\s+' + re.escape(clock_net) + r'\s*,?', header), (path,'lane release clock is not a port')
    serdes_net = hier_port(connection, clock_net)
    lane_clock_nets[path] = hier_port(lane_connection, serdes_net)
    assert ffs[0].startswith('GTP_DFF_C')
    port(ffs[0],'C')
    assert port(ffs[0],'D') == 'shared_reset_n'
    assert port(connection,'shared_reset_n') == 'serial_reset_n'
    assert 'lane_reset_n' in aliases(b,port(ffs[0],'Q'))
    final_net = port(connection,'lane_reset_n')
    primitives = re.findall(r'(?s)GTP_OSERDES_E2.*?\);',serial)
    assert len(primitives) == 2
    rst = {port(p,'RST') for p in primitives}
    assert len(rst) == 1 and all(port(p,'OCLK') == 'serialclk' for p in primitives)
    # Native ADS may retain an explicit INV instead of implementing it as LUT1.
    # In both forms prove the exact local release Q -> inversion -> OSERDES RST.
    inv = [b for b in re.findall(r'(?s)GTP_LUT1.*?\);',serial)
           if port(b,'Z') in rst and port(b,'I0') == final_net
           and re.search(r"\.INIT\s*\(\s*2'b01\s*\)",b)]
    inv += [b for b in re.findall(r'(?s)GTP_INV\s+.*?\);',serial)
            if port(b,'Z') in rst and port(b,'I') == final_net]
    assert len(inv) == 1, (path,'exact local release inversion required')
    rows.append({'lane':path,'asynchronous_exception_pins':subset,
                 'shared_stages':3,'local_stages':1,'shared_launch_clock':'pixelclk rising','launch_clock':'pixelclk falling','serializer_reset_driven_by_final_stage':True,
                 'serializer_recovery_removal_exempted':False,
                 'reset_inverter_primitive':inv[0].split()[0]})
assert len(inverter_lanes) == 1, 'Exactly one inverted pixelclk source for the four lane releases'
assert len(set(lane_clock_nets.values())) == 1, ('Lane releases do not share one inverted pixelclk net', lane_clock_nets)
for row in rows:
    row['release_clock_net'] = lane_clock_nets[row['lane']]
    row['release_clock_inverter_lane'] = inverter_lanes[0]
(work/'native_hdmi_reset_audit.json').write_text(json.dumps({
    'status':'PASS_EXACT_NATIVE_SERIALIZER_RESET_CHAINS','lanes':rows,
    'native_clear_control_objects':5,'physical_asynchronous_FF_clear_pins':7,
    'CCR_sha256':hashlib.sha256(ccr_file.read_bytes()).hexdigest(),
    'VM_sha256':hashlib.sha256(vm_file.read_bytes()).hexdigest(),
    'physical_serializer_recovery_removal':'PENDING_ROUTED_STA'},indent=2))
print('PASS_EXACT_NATIVE_SERIALIZER_RESET_CHAINS pixel-clock shared source, four pixel-falling-edge local releases, five generic clear controls map to seven physical FF C pins; OSERDES checks remain timed')
