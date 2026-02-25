# 替代方案：使用 OpenCV 的修复算法

由于 LaMa ONNX 模型下载和转换比较复杂，这里提供一个临时的替代方案，使用 OpenCV 的内置修复算法。

## 方案对比

| 方案 | 优点 | 缺点 |
|------|------|------|
| LaMa ONNX | 效果最好，AI 驱动 | 模型大（200MB），需要下载转换 |
| OpenCV Inpainting | 无需下载，开箱即用 | 效果一般，适合简单水印 |

## 快速实施

### 步骤 1: 修改后端代码

将 `main.py` 中的 LaMa 推理替换为 OpenCV 修复：

```python
# 替换 ONNX 推理部分
import cv2

def inpaint_opencv(image, mask):
    """使用 OpenCV 的修复算法"""
    # 使用 Telea 算法
    result = cv2.inpaint(image, mask, 3, cv2.INPAINT_TELEA)
    return result
```

### 步骤 2: 测试

这样就不需要模型文件了，可以立即测试功能。

## 长期方案：获取真实的 LaMa ONNX 模型

### 方案 A: 使用 lama-cleaner 项目

1. 克隆项目：
   ```bash
   git clone https://github.com/Sanster/lama-cleaner.git
   cd lama-cleaner
   ```

2. 运行一次 lama-cleaner，它会自动下载模型到缓存目录

3. 找到缓存的模型文件（通常在 `~/.cache/lama-cleaner/`）

### 方案 B: 使用 IOPaint (lama-cleaner 的新版本)

IOPaint 是 lama-cleaner 的升级版，提供更好的模型管理：

```bash
pip install iopaint
iopaint start
```

首次运行会自动下载模型。

### 方案 C: 手动转换 checkpoint

如果你已经有 `best.ckpt` 文件：

1. 安装依赖：
   ```bash
   pip install torch torchvision onnx
   ```

2. 克隆 LaMa 原始项目：
   ```bash
   git clone https://github.com/advimman/lama.git
   cd lama
   ```

3. 使用项目提供的转换脚本

## 推荐方案

**对于快速测试**：使用 OpenCV 方案（5 分钟）

**对于生产环境**：
1. 安装 IOPaint: `pip install iopaint`
2. 运行一次让它下载模型
3. 从缓存目录复制 ONNX 模型到我们的项目

## 立即可用的代码

我可以立即修改 `main.py` 使用 OpenCV 方案，这样你现在就能测试完整流程。

需要我现在就修改吗？
