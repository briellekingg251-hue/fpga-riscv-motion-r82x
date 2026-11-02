# 最终视觉模型归档

本目录包含 R82x 视觉链路使用的 D1、P2 模型检查点、INT8 参数和训练配置。

| 路径 | 内容 |
|---|---|
| `p2_pretrain/best.pt`、`p2_pretrain/args.json` | P2 `s16_hx_r96` 的 COCO 预训练权重和参数 |
| `p2_final/last.pt`、`p2_final/args.json` | 微调后的 `p2f_r96_288_ft` 权重和参数；微调加载 `runs/p2f_r96_288/best.pt` |
| `p2_final/params.npz`、`p2_final/layers.json` | P2 `pow2u` INT8 参数与层配置 |
| `d1_final/last.pt` | `d1_ov_teacher` 微调后的权重 |
| `d1_final/params.npz`、`d1_final/layers.json` | D1 `pow2u` INT8 参数与层配置 |
| `d1_pretrain/best.pt` | 历史 `detV2_D1_coco` COCO 预训练检查点；与 D1 微调命令中 `base/D1_coco_best.pt` 的字节身份尚未核实 |
| `records/` | 训练命令和最终模型的 OV5640 评估记录 |

P2 最终模型输出的评估及量化参考为 `last.pt`，不是 `best.pt`。D1 最终量化同样使用 `last.pt`。上表中 `.pt` 为 PyTorch 检查点，只应在可信环境中加载；INT8 部署权重 ROM 已包含于 `hardware/resources/rom/`。

`records/` 中的脚本根据训练参数整理，运行前需配置数据目录、预处理输入和 GPU。COCO 数据及 OV5640 录像、抽帧和标注需自行准备；本地 Windows 环境快照与云端环境记录见 [训练环境说明](../environment/README.md)。历史云端的完整环境和训练数据需另行准备，因此当前归档不证明仅凭仓库即可从零复现训练和相同评估数值。

模型训练环境与数据准备见[训练环境说明](../environment/README.md)。板上实际部署网络与 FPGA 固定 ROM、整机位流的验证以发布清单与板测记录为准，新增检查点不代替整机复测。
