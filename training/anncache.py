"""Slim, pickled COCO person annotations.

Parsing the 238 MB train2017 keypoint json costs several GB of Python heap that
CPython never returns to Windows; with several trainings on one machine that
exhausted the commit limit.  The slim cache (no polygons) loads in ~1 s and
~0.3 GB.  Build it out-of-process once:  python anncache.py
"""
import json
import os
import pickle
from pathlib import Path

CACHE = Path(os.environ.get('COCO_CACHE', str(Path(__file__).resolve().parents[1] / 'cache')))
KEEP = ('id', 'image_id', 'bbox', 'keypoints', 'num_keypoints', 'area', 'iscrowd')


def build(ann_file):
    d = json.load(open(ann_file))
    return dict(images=[(im['id'], im['file_name'], im['height'], im['width']) for im in d['images']],
                persons=[{k: a.get(k, 0) for k in KEEP} for a in d['annotations'] if a['category_id'] == 1])


def slim_coco(ann_file):
    path = CACHE / (Path(ann_file).stem + '.pkl')
    if not path.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix('.tmp')
        pickle.dump(build(ann_file), open(tmp, 'wb'), protocol=4)
        tmp.replace(path)
    return pickle.load(open(path, 'rb'))


if __name__ == '__main__':
    for split in ('train2017', 'val2017'):
        s = slim_coco(f'D:/datasets/coco/annotations/person_keypoints_{split}.json')
        print(split, len(s['images']), 'images', len(s['persons']), 'persons')
