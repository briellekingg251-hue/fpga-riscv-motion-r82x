"""Extract every frame of a body video to <frames_root>/<video stem>/fNNNNN.jpg (same layout as v1/v2)."""
import hashlib
import json
import sys
from pathlib import Path

import cv2


def extract(video, root):
    video, root = Path(video), Path(root)
    out = root / video.stem
    out.mkdir(parents=True, exist_ok=True)
    cap = cv2.VideoCapture(str(video))
    fps, n, shape = cap.get(cv2.CAP_PROP_FPS), 0, (0, 0)
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        n += 1
        shape = frame.shape[:2]
        if not cv2.imwrite(str(out / f'f{n:05d}.jpg'), frame):
            raise RuntimeError(f'cannot write frame {n}')
    rec = dict(source_video=str(video), source_sha256=hashlib.sha256(video.read_bytes()).hexdigest(),
               frames=n, fps=fps, height=shape[0], width=shape[1],
               frame_directory=str(out))
    (root / f'{video.stem}_extraction.json').write_text(json.dumps(rec, indent=2))
    print(video.name, n, flush=True)


if __name__ == '__main__':
    for v in sys.argv[2:]:
        extract(v, sys.argv[1])
