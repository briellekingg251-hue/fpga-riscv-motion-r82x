"""COCO person subsets matching the deployment scene: one person standing in
front of a fixed camera, seen from the front or side (no top-down / lying /
upside-down poses).

  upright  : >= MIN_KP labelled keypoints incl. a shoulder and a hip, torso
             (shoulder centre -> hip centre) within MAX_TILT deg of vertical
             pointing down, box area >= MIN_AREA
  single   : images whose only keypoint-annotated person is upright
"""
import json
import math
from pathlib import Path

import numpy as np

MIN_KP = 8
MAX_TILT = 30.0
MIN_AREA = 64 * 64
SHOULDERS, HIPS = (5, 6), (11, 12)


def torso_tilt(kp):
    """Degrees between the torso direction and image-down; None if not measurable."""
    kp = np.asarray(kp, np.float32).reshape(17, 3)
    sh = [kp[i, :2] for i in SHOULDERS if kp[i, 2] > 0]
    hp = [kp[i, :2] for i in HIPS if kp[i, 2] > 0]
    if not sh or not hp:
        return None
    dx, dy = np.mean(hp, 0) - np.mean(sh, 0)
    if dx == 0 and dy == 0:
        return None
    return abs(math.degrees(math.atan2(dx, dy)))


def is_upright(ann):
    if ann.get('iscrowd', 0) or ann['num_keypoints'] < MIN_KP or ann['area'] < MIN_AREA:
        return False
    tilt = torso_tilt(ann['keypoints'])
    return tilt is not None and tilt <= MAX_TILT


def strip_head(ann):
    kp = list(ann['keypoints'])
    kp[:15] = [0] * 15
    return dict(ann, keypoints=kp, num_keypoints=sum(1 for v in kp[2::3] if v > 0))


def write_subset(ann_file, name, out_dir):
    """Write a filtered GT json (images + annotations) for COCOeval; returns its path.

    name: 'all' (unchanged), 'upright' (upright persons only, other persons
    dropped), 'single' (images whose only keypoint person is upright); a '_body'
    suffix also removes the 5 head keypoints from the GT so OKS covers the 12
    body joints only (comparable between 17- and 12-keypoint models).
    """
    if name == 'all':
        return Path(ann_file)
    base, body = (name[:-5], True) if name.endswith('_body') else (name, False)
    d = json.load(open(ann_file))
    persons = [a for a in d['annotations'] if a['category_id'] == 1]
    if base == 'all':
        anns = persons
    elif base == 'upright':
        anns = [a for a in persons if is_upright(a)]
    elif base == 'single':
        by_img = {}
        for a in persons:
            if a['num_keypoints'] > 0 or a.get('iscrowd', 0):
                by_img.setdefault(a['image_id'], []).append(a)
        anns = [v[0] for v in by_img.values() if len(v) == 1 and is_upright(v[0])]
    else:
        raise ValueError(name)
    if body:
        anns = [strip_head(a) for a in anns]
    ids = {a['image_id'] for a in anns}
    d['annotations'] = anns
    d['images'] = [im for im in d['images'] if im['id'] in ids]
    out = Path(out_dir) / f'{Path(ann_file).stem}_{name}.json'
    out.parent.mkdir(parents=True, exist_ok=True)
    json.dump(d, open(out, 'w'))
    return out


if __name__ == '__main__':
    ann = 'D:/datasets/coco/annotations/person_keypoints_val2017.json'
    for n in ('upright', 'single', 'upright_body'):
        p = write_subset(ann, n, 'runs/subsets')
        d = json.load(open(p))
        print(n, 'persons', len(d['annotations']), 'images', len(d['images']), '->', p)
