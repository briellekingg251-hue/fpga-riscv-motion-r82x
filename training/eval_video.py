"""PCK of video_track.py predictions against MediaPipe pseudo-labels (body joints).

  python eval_video.py runs/video/<name>.json D:/hand_dataset/P01_S01/video_01_mp_body12.json

A joint is correct when its distance to the label is below t x torso length
(label shoulder centre -> hip centre; stable for front and side views, unlike
shoulder width); reported per joint group for t = 0.2 and 0.5, over frames where
the label exists.  Missing predictions (no person found) count as wrong.
"""
import json
import sys

import numpy as np

GROUPS = {'shoulder': (5, 6), 'elbow': (7, 8), 'wrist': (9, 10), 'hip': (11, 12), 'knee': (13, 14), 'ankle': (15, 16)}


def main(pred_file, label_file):
    pred = {f['file']: f for f in json.load(open(pred_file))['frames']}
    lab = json.load(open(label_file))
    names = {im['id']: im['file_name'] for im in lab['images']}
    res = {g: {0.2: [], 0.5: []} for g in GROUPS}
    errs = {g: [] for g in GROUPS}
    for a in lab['annotations']:
        k = np.array(a['keypoints'], float).reshape(17, 3)
        if not (k[5, 2] and k[6, 2] and k[11, 2] and k[12, 2]):
            continue
        sw = np.linalg.norm((k[5, :2] + k[6, :2]) / 2 - (k[11, :2] + k[12, :2]) / 2)   # torso length
        p = pred.get(names[a['image_id']])
        pk = np.array(p['kps'], float) if p and 'kps' in p else None
        for g, idx in GROUPS.items():
            for j in idx:
                if not k[j, 2]:
                    continue
                d = np.inf if pk is None else np.linalg.norm(pk[j, :2] - k[j, :2]) / sw
                errs[g].append(d)
                for t in (0.2, 0.5):
                    res[g][t].append(d < t)
    out = {g: dict(n=len(v[0.2]), pck02=round(float(np.mean(v[0.2])), 3), pck05=round(float(np.mean(v[0.5])), 3),
                   median_err_torso=round(float(np.median(errs[g])), 3))
           for g, v in res.items() if v[0.2]}
    print(json.dumps(out, indent=1))
    return out


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
