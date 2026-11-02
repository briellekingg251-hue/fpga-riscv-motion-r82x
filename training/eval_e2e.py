"""End-to-end detect -> crop -> pose on the deployment-like COCO subset.

Images whose only keypoint person is upright ('single', 519 val images): the
detector sees the whole letterboxed image, its top-1 box is turned into a pose
crop exactly like a ground-truth box would be, the pose net predicts the joints.
Scored with body-only OKS AP -- directly comparable to PoseNet193 full-single
(body) 0.246 from baseline/eval_posenet.py.

  python eval_e2e.py --det runs/det_s16/best.pt --pose runs/poseB_plain_s16_body12/best.pt
"""
import argparse
import json
import os
from pathlib import Path

import cv2
import numpy as np
import torch
from pycocotools.coco import COCO

import det as D
from data import box_to_center_scale, crop_matrix, decode, to_coco17, to_image
from model import IN_H, IN_W, build
from train import coco_ap
from subsets import write_subset

COCO_DIR = Path(os.environ.get('COCO_DIR', str(Path(__file__).resolve().parents[1] / 'data/coco')))


def load_pose(path, device):
    if Path(path).is_dir():
        m, meta = load_export(path, device, 'pose')
        n = len(meta['keypoints'])
        if n not in (12, 17):
            raise ValueError(f'unsupported keypoint count: {n}')
        return m, 'body12' if n == 12 else 'coco17'
    ck = torch.load(path, map_location=device, weights_only=False)
    a = ck['args']
    if 'in_hw' in a and tuple(a['in_hw']) != (IN_H, IN_W):
        raise ValueError(f'{path} trained at {a["in_hw"]}, but POSE_IN gives {(IN_H, IN_W)}')
    num_kp = 17 if a['kp_set'] == 'coco17' else 12
    m = build(a['arch'], num_kp, a['width'], a['blocks'], a['cfg'], a.get('width_mult', 1.0))
    m.load_state_dict(ck['model'])
    return m.to(device).eval(), a['kp_set']


def load_det(path, device):
    if Path(path).is_dir():
        return load_export(path, device, 'det')[0]
    ck = torch.load(path, map_location=device, weights_only=False)
    m = D.PersonDet(ck['args']['cfg'])
    m.load_state_dict(ck['model'])
    return m.to(device).eval()


def load_export(path, device, kind):
    """Evaluate saved integer parameters through the existing exact IntNet."""
    from export import IntNet
    path = Path(path)
    meta = json.loads((path / 'layers.json').read_text())
    if meta['kind'] != kind or meta['mode'] != 'pow2u':
        raise ValueError(f'expected {kind} pow2u export: {path}')
    with np.load(path / 'params.npz') as params:
        layers = [dict(layer, qw=torch.from_numpy(params[f'w{i}'].copy()).double().to(device),
                       qb=torch.from_numpy(params[f'b{i}'].copy()).double().to(device))
                  for i, layer in enumerate(meta['layers'])]
    n = len(meta.get('keypoints', [])) if kind == 'pose' else 1
    return IntNet(layers, meta['mode'], meta['stride'], n).eval(), meta


def to_tensor(rgb):
    return torch.from_numpy(np.ascontiguousarray(rgb.transpose(2, 0, 1))).float()[None] / 127.5 - 1


@torch.no_grad()
def detect_top1(detm, rgb, device):
    h, w = rgb.shape[:2]
    m = D.frame_matrix(*D.letterbox(h, w))
    x = cv2.warpAffine(rgb, m, (D.DET_W, D.DET_H), flags=cv2.INTER_AREA, borderValue=(0, 0, 0))
    heat, box = detm(to_tensor(x).to(device))
    dets = D.decode_boxes(heat.float(), box.float(), detm.stride, k=1, thresh=0.0)[0]
    if not dets:
        return None
    x0, y0, x1, y1, sc = dets[0]
    inv = cv2.invertAffineTransform(m)
    (ax, ay), (bx, by) = np.array([[x0, y0, 1], [x1, y1, 1]]) @ inv.T
    ax, ay, bx, by = max(ax, 0), max(ay, 0), min(bx, w), min(by, h)
    return [ax, ay, max(bx - ax, 2), max(by - ay, 2)], sc


@torch.no_grad()
def pose_on_box(posem, kp_set, rgb, box, device):
    center, size = box_to_center_scale(box)
    crop = cv2.warpAffine(rgb, crop_matrix(center, size), (IN_W, IN_H), flags=cv2.INTER_LINEAR,
                          borderValue=(0, 0, 0))
    heat, off = posem(to_tensor(crop).to(device))
    pts, score = decode(heat.float(), off.float(), posem.stride)
    xy = to_image(pts[0].cpu().numpy(), center, size)
    return to_coco17(xy, score[0].sigmoid().cpu().numpy(), kp_set)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--det', required=True)
    ap.add_argument('--pose', required=True)
    ap.add_argument('--out', default='runs/e2e')
    args = ap.parse_args()
    device = 'cuda' if torch.cuda.is_available() else 'cpu'
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    detm = load_det(args.det, device)
    posem, kp_set = load_pose(args.pose, device)
    ann = COCO_DIR / 'annotations/person_keypoints_val2017.json'
    gt = COCO(str(write_subset(ann, 'single_body', out)))
    res_det, res_gt, ious = [], [], []
    for a in gt.dataset['annotations']:
        im = gt.imgs[a['image_id']]
        rgb = np.ascontiguousarray(cv2.imread(str(COCO_DIR / 'val2017' / im['file_name']))[:, :, ::-1])
        for box, sink in ((a['bbox'], res_gt), (None, res_det)):
            if box is None:
                hit = detect_top1(detm, rgb, device)
                if hit is None:
                    continue
                box = hit[0]
                g = a['bbox']
                ious.append(D.iou((box[0], box[1], box[0] + box[2], box[1] + box[3]),
                                  (g[0], g[1], g[0] + g[2], g[1] + g[3])))
            xy, p = pose_on_box(posem, kp_set, rgb, box, device)
            sink.append(dict(image_id=a['image_id'], category_id=1, score=float(p[p > 0].mean()),
                             keypoints=np.c_[xy, p].reshape(-1).tolist()))
    summary = dict(det=args.det, pose=args.pose, images=len(gt.dataset['annotations']),
                   det_mean_iou=float(np.mean(ious)), det_hit50=float(np.mean(np.array(ious) >= 0.5)))
    summary['AP_gt_box'], summary['AP50_gt_box'] = coco_ap(gt, res_gt, out / 'e2e_gt.json')
    summary['AP_det_box'], summary['AP50_det_box'] = coco_ap(gt, res_det, out / 'e2e_det.json')
    print(json.dumps(summary, indent=2))
    with open(out / 'summary.jsonl', 'a') as f:
        f.write(json.dumps(summary) + '\n')


if __name__ == '__main__':
    main()
