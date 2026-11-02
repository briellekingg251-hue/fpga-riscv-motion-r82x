"""Render captured GPU command traces (idx<<32|value hex lines) via the v2 reference model."""
import sys
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests' / 'reference'))
from gpu_v2_model import GpuModel
for arg in sys.argv[1:]:
    path = Path(arg)
    model = GpuModel()
    for line in path.read_text().split():
        v = int(line, 16)
        model.write((v >> 32) & 63, v & 0xFFFFFFFF)
    img = Image.fromarray(model.frame())
    img.resize((img.width * 2, img.height * 2), Image.NEAREST).save(path.with_suffix('.png'))
    print('rendered', path.with_suffix('.png'))
