"""Render actual C firmware draw-command captures through the GPU reference."""
from pathlib import Path
from PIL import Image
from gpu_model import GpuModel

ROOT = Path(__file__).resolve().parents[1]
for name in ("title", "play", "paused", "over"):
    path = ROOT / "build" / f"manual_ui_{name}"
    model = GpuModel()
    commands = path.with_suffix(".hex").read_text().split()
    for line in commands:
        value = int(line, 16)
        model.write((value >> 32) & 63, value & 0xFFFFFFFF)
    assert model.swaps == 1
    Image.fromarray(model.frame()).save(path.with_suffix(".png"))
    print(f"Rendered {path.with_suffix('.png')} ({len(commands)} GPU commands)")
