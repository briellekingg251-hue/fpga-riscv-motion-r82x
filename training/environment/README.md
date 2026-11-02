# 训练环境与数据

历史 Windows 快照使用 Python 3.10.4，已记录的包版本见 [requirements-windows.txt](requirements-windows.txt)。该清单仅用于环境参考，不包含运行时或驱动，安装时需根据平台选择兼容的 PyTorch 和 CUDA 版本。

历史云端预检使用 Python 3.12.3、PyTorch 2.12.1+cu130 和 CUDA 13.0；最终训练时的完整依赖与容器镜像未保存。数据、标注及教师模型需自行准备，仓库不能保证从头训练后数值完全一致。
