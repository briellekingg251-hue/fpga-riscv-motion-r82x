# 复现指南

## 软件环境

需要 Windows、Python 3 和 xPack GNU RISC-V Embedded GCC 15.2.0-1。输出目录必须在仓库之外且不存在。模型训练环境说明见 [training/environment](training/environment/README.md)。

```powershell
$TOOLBIN = '<RISC-V 工具链 bin 目录>'
$WORK = '<仓库外的新工作目录>'
python scripts/rebuild_coremark.py "$WORK/coremark" --toolbin $TOOLBIN
python scripts/rebuild_boot.py "$WORK/boot" --toolbin $TOOLBIN
python scripts/rebuild_game_variants.py "$WORK/games" --toolbin $TOOLBIN
python scripts/rebuild_poseview.py "$WORK/poseview" --toolbin $TOOLBIN
python scripts/rebuild_nes.py "$WORK/nes" --toolbin $TOOLBIN
```

NES 模拟器程序不包含商业游戏 ROM。对应游戏须由用户自行准备。

DOOM 与 PAL 需要自行取得游戏数据。PAL 还需要单独取得并确认可使用 `navy-apps` 相关源码；该依赖不随仓库分发：

```powershell
$WAD = '<合法取得的 DOOM WAD 文件>'
$PAL_DATA = '<合法取得的 PAL DOS 数据目录>'
$NAVY_ROOT = '<合法取得的 navy-apps 源码目录>'
python scripts/rebuild_doom.py "$WORK/doom" --toolbin $TOOLBIN --wad $WAD
python scripts/rebuild_pal.py "$WORK/pal" --toolbin $TOOLBIN --data $PAL_DATA --navy-root $NAVY_ROOT
```

## 硬件工程

使用 PDS 2022.2-SP6.4 和 PG2L200H 支持。用户须在有权使用的厂商工具中自行生成或取得兼容 IP：完整 vendor 目录应包含 DDR、时钟等实例；另生成 `video_pll` 对应源文件。脚本将核对必需的 vendor 文件，并在隔离目录中插入时钟模块：

```powershell
$R82X_WORK = '<仓库外的新硬件工作目录>'
$VENDOR_DIR = '<本地生成的 vendor 目录>'
$VIDEO_PLL = '<本地生成的 video_pll.v>'
python scripts/prepare_compile.py $R82X_WORK --vendor-dir $VENDOR_DIR --video-pll $VIDEO_PLL
pds_shell -file "$R82X_WORK/compile_relocated.tcl" -work_dir $R82X_WORK -project_name fusion
```

厂商 IP 不在仓库中。公开源码对拼接文件中的厂商时钟模块进行了分离，因此新工程不等同于原有位流；完成实现后需独立检查时序、接口和板上功能。独立 CPU 上板工程还需用户自行提供匹配配置的 `cpu_standalone/source/ooo/pds/src/p7_board_pll.v`。

## 数据和模型

COCO、OV5640 录像及标注、教师模型、NES ROM、PAL 数据、DOOM WAD 和横版射击游戏素材均需从合法来源自行取得。最终 D1/P2 检查点和量化参数在 `training/final_models/`，INT8 部署权重 ROM 在 `hardware/resources/rom/`。原训练环境和数据没有完整公开，不保证重训得到完全相同的数值。
