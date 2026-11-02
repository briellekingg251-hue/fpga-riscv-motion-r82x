"""Convert rv32sim PPM frames to 2x PNG (as shown on the 1024x600 LCD)."""
import sys
from pathlib import Path
from PIL import Image
for arg in sys.argv[1:]:
    for p in sorted(Path(arg).glob('*.ppm')) if Path(arg).is_dir() else [Path(arg)]:
        im = Image.open(p)
        im.resize((im.width * 2, im.height * 2), Image.NEAREST).save(p.with_suffix('.png'))
        p.unlink()
