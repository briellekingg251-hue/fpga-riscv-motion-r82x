"""Rebind copied, bit-exact ROM assets to this checkout; no model regeneration."""
from pathlib import Path
import re
def relocate():
    root=Path(__file__).resolve().parents[1]
    for name in ['p2_net_det.sv','p2_net_pose.sv']:
        f=root/'rtl/pose'/name
        text=f.read_text()
        text=re.sub(r'"[^"]*/build/rom/([^"]+)"',lambda m:'"'+(root/'build/rom'/m[1]).as_posix()+'"',text)
        f.write_text(text,newline='\n')
    f=root/'rtl/pose/p2_vision_mmio.sv'
    f.write_text(re.sub(r'\.LUT_FILE\("[^"]+"\)',lambda m:'.LUT_FILE("'+(root/'rtl/pose/p2_oe_lut.mem').as_posix()+'")',f.read_text()),newline='\n')
if __name__=='__main__':relocate()
