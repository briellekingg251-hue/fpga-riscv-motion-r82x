"""Exact native reset exception and preserved serializer release-chain proof."""
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
assert len(shared_clocks) == 1 and port(shared_connection,next(iter(shared_clocks))) == 'serialclk'
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
    assert len(clocks) == 1 and port(connection,next(iter(clocks))) == 'serialclk'
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
                 'shared_stages':3,'local_stages':1,'launch_clock':'serialclk','serializer_reset_driven_by_final_stage':True,
                 'serializer_recovery_removal_exempted':False,
                 'reset_inverter_primitive':inv[0].split()[0]})
(work/'native_hdmi_reset_audit.json').write_text(json.dumps({
    'status':'PASS_EXACT_NATIVE_SERIALIZER_RESET_CHAINS','lanes':rows,
    'native_clear_control_objects':5,'physical_asynchronous_FF_clear_pins':7,
    'CCR_sha256':hashlib.sha256(ccr_file.read_bytes()).hexdigest(),
    'VM_sha256':hashlib.sha256(vm_file.read_bytes()).hexdigest(),
    'physical_serializer_recovery_removal':'PENDING_ROUTED_STA'},indent=2))
print('PASS_EXACT_NATIVE_SERIALIZER_RESET_CHAINS shared source, four simultaneous local releases, five generic clear controls map to seven physical FF C pins; OSERDES checks remain timed')
