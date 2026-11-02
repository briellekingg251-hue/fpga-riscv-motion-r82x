# 第三方组件与许可

根目录 MIT 许可仅覆盖项目贡献者有权按 MIT 许可发布的自有代码，不覆盖第三方文件或对第三方代码的派生部分。使用和分发时应遵守各组件及其依赖的许可条款。

| 组件 | 路径 | 已记录许可 |
|---|---|---|
| CoreMark | `cpu_standalone/firmware/src/` 中的 CoreMark 文件 | Apache-2.0，见源码版权声明及 [Apache-2.0](Apache-2.0.txt) |
| InfoNES | `firmware/nes/third_party/InfoNES/` | GPL-2.0，见该目录的 `doc/GPL2` 与原始说明 |
| doomgeneric | `games_cpu1575/third_party/doomgeneric/` | GPL-2.0，见该目录的 `LICENSE` 和源码声明 |
| PAL-Navy / SDLPAL | `fusion_cpu1575/third_party/pal-navy/` | GPL-3.0，见该目录的 `LICENSE` 和各文件声明 |
| AdPlug 等 PAL 依赖 | PAL-Navy 的 `src/sound/adplug/` | 见该目录内的 `NOTES/COPYING` 和各文件声明 |

项目中与 GPL 代码结合或派生的移植部分可能受相应 GPL 条款约束，不能仅凭根目录 MIT 文件重新许可。代码中保留的其他版权和许可声明同样适用。

厂商 PDS 生成的受限 IP 和时钟模块、授权不明的 `navy-apps` 快照、横版射击上游代码及素材、商业游戏数据和 ROM 不在本公开仓库内；使用者需自行取得相应授权或合法来源。训练数据、教师模型和原私有运行环境也不包含在仓库内。
