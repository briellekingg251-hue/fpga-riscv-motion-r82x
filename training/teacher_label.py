"""Teacher pseudo-labels for OV5640 body videos: rtmlib YOLOX person box + RTMPose-x (COCO17).

Writes <frames_root>/<stem>_rtm_body12.json in the same COCO-style layout as the MediaPipe labels
(keypoints in COCO17 order, only body12 slots 5..16 filled, v=2 if teacher score >= KP_T) plus a
per-annotation 'scores' list and the detector 'bbox' (full person box, like COCO/D1).
Main subject = largest confident box, preferring continuity with the previous frame's box.

  python teacher_label.py FRAMES_ROOT STEM [STEM ...]
"""
import json
import sys
import time
from pathlib import Path

import cv2
import numpy as np

KP_T = 0.3          # teacher keypoint confidence for "labelled"
DET_T = 0.4
MIN_KP = 6          # body12 joints needed to keep a frame


def pick(boxes, prev):
    """Index of the subject box: big boxes win, continuity with prev breaks near-ties."""
    area = (boxes[:, 2] - boxes[:, 0]) * (boxes[:, 3] - boxes[:, 1])
    score = area / area.max()
    if prev is not None:
        c = (boxes[:, :2] + boxes[:, 2:4]) / 2
        pc = (prev[:2] + prev[2:4]) / 2
        diag = np.hypot(prev[2] - prev[0], prev[3] - prev[1])
        score = score - 0.5 * np.minimum(np.linalg.norm(c - pc, axis=1) / max(diag, 1), 1)
    return int(np.argmax(score))


def label(frames_root, stem, det, pose):
    frame_dir = Path(frames_root) / stem
    files = sorted(frame_dir.glob('f*.jpg'))
    images, anns, prev, t0 = [], [], None, time.time()
    for i, f in enumerate(files):
        img = cv2.imread(str(f))
        h, w = img.shape[:2]
        images.append(dict(id=i + 1, file_name=f.name, height=h, width=w))
        boxes = det(img)
        boxes = np.asarray(boxes, np.float32).reshape(-1, 4) if len(boxes) else np.zeros((0, 4), np.float32)
        if len(boxes) == 0:
            prev = None
            continue
        j = pick(boxes, prev)
        box = boxes[j]
        kps, scores = pose(img, bboxes=[box.tolist()])
        kp, sc = np.asarray(kps)[0], np.asarray(scores)[0]
        keypoints = [0.0] * 51
        n = 0
        for k in range(5, 17):
            x, y = float(kp[k, 0]), float(kp[k, 1])
            if sc[k] >= KP_T and 0 <= x < w and 0 <= y < h:
                keypoints[3 * k:3 * k + 3] = [round(x, 2), round(y, 2), 2]
                n += 1
        prev = box
        if n < MIN_KP:
            continue
        x0, y0, x1, y1 = [float(v) for v in box]
        x0, y0, x1, y1 = max(0, x0), max(0, y0), min(w, x1), min(h, y1)
        anns.append(dict(id=i + 1, image_id=i + 1, category_id=1, iscrowd=0, num_keypoints=n, keypoints=keypoints,
                         bbox=[x0, y0, x1 - x0, y1 - y0], area=(x1 - x0) * (y1 - y0),
                         scores=[round(float(s), 3) for s in sc], n_boxes=len(boxes)))
        if i % 500 == 0:
            print(f'{stem} {i}/{len(files)} {len(anns)} labelled {(i + 1) / (time.time() - t0):.1f} fps', flush=True)
    out = Path(frames_root) / f'{stem}_rtm_body12.json'
    json.dump(dict(images=images, annotations=anns, info=dict(teacher='rtmlib Body performance (YOLOX + RTMPose-x)',
                                                               kp_t=KP_T, det_t=DET_T, min_kp=MIN_KP),
                   categories=[dict(id=1, name='person', keypoints=[], skeleton=[])]), open(out, 'w'))
    print(f'{out}: {len(anns)}/{len(files)} frames labelled', flush=True)


def main():
    from rtmlib import Body
    body = Body(mode='performance', backend='onnxruntime', device='cuda')
    det, pose = body.det_model, body.pose_model
    det.score_thr = DET_T                      # rtmlib YOLOX default 0.7
    for stem in sys.argv[2:]:
        label(sys.argv[1], stem, det, pose)


if __name__ == '__main__':
    main()
