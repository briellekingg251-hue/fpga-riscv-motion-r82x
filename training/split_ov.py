"""Time-block split of teacher-labelled OV5640 videos into train / held-out test.

Each held-out video is cut into BLOCKS equal time blocks; blocks TEST_BLOCKS (20%) are test.
GUARD frames on each side of every test block are dropped from train (no near-duplicate leakage).
Videos not listed as held-out go entirely to train.

  python split_ov.py FRAMES_ROOT --holdout STEM [STEM ...] --train-only STEM [STEM ...]
Writes <stem>_rtm_body12_{train,test}.json beside the label file and ov_split.json (frame ranges).
"""
import argparse
import json
from pathlib import Path

BLOCKS = 10
TEST_BLOCKS = (2, 7)
GUARD = 16          # ~1 s at 15.6 fps


def block_split(n):
    """-> (test frame ids, train frame ids), 1-based like the label json image ids."""
    edges = [round(i * n / BLOCKS) for i in range(BLOCKS + 1)]
    test, banned = set(), set()
    for b in TEST_BLOCKS:
        lo, hi = edges[b] + 1, edges[b + 1]
        test.update(range(lo, hi + 1))
        banned.update(range(max(1, lo - GUARD), min(n, hi + GUARD) + 1))
    train = set(range(1, n + 1)) - banned
    return test, train


def write_subset(d, ids, out):
    sub = dict(d, images=[im for im in d['images'] if im['id'] in ids],
               annotations=[a for a in d['annotations'] if a['image_id'] in ids])
    json.dump(sub, open(out, 'w'))
    return len(sub['annotations'])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('root')
    ap.add_argument('--holdout', nargs='+', default=[])
    ap.add_argument('--train-only', nargs='+', default=[])
    args = ap.parse_args()
    root, report = Path(args.root), {}
    for stem in args.holdout + args.train_only:
        d = json.load(open(root / f'{stem}_rtm_body12.json'))
        n = len(d['images'])
        if stem in args.holdout:
            test, train = block_split(n)
        else:
            test, train = set(), set(range(1, n + 1))
        rec = dict(frames=n, train_labelled=write_subset(d, train, root / f'{stem}_rtm_body12_train.json'))
        if test:
            rec['test_labelled'] = write_subset(d, test, root / f'{stem}_rtm_body12_test.json')
            edges = [round(i * n / BLOCKS) for i in range(BLOCKS + 1)]
            rec['test_ranges'] = [[edges[b] + 1, edges[b + 1]] for b in TEST_BLOCKS]
        report[stem] = rec
        print(stem, rec, flush=True)
    json.dump(dict(blocks=BLOCKS, test_blocks=TEST_BLOCKS, guard=GUARD, videos=report),
              open(root / 'ov_split.json', 'w'), indent=1)


if __name__ == '__main__':
    main()
