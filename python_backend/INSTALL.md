# LaMa 水印去除服务 - 完整安装指南

## 📋 目录
1. [系统要求](#系统要求)
2. [快速安装](#快速安装)
3. [详细步骤](#详细步骤)
4. [验证安装](#验证安装)
5. [常见问题](#常见问题)

---

## 系统要求

### 必需
- Python 3.8 或更高版本
- 8GB RAM（最低）
- 10GB 可用磁盘空间

### 推荐（GPU 加速）
- NVIDIA GPU（支持 CUDA 11.8+）
- 16GB RAM
- CUDA Toolkit 11.8+
- cuDNN 8.x

---

## 快速安装

### Windows 用户
```bash
cd python_backend
pip install -r requirements.txt
start.bat
```

### Linux/Mac 用户
```bash
cd python_backend
pip install -r requirements.txt
chmod +x start.sh
./start.sh
```

启动脚本会自动检测并下载模型（如果不存在）。

---

## 详细步骤

### 步骤 1: 安装 Python 依赖

```bash
cd python_backend
pip install -r requirements.txt
```

**如果只有 CPU（无 GPU）**：
编辑 `requirements.txt`，将：
```
onnxruntime-gpu==1.19.2
```
改为：
```
onnxruntime==1.19.2
```

然后重新安装：
```bash
pip install -r requirements.txt
```

### 步骤 2: 下载 LaMa 模型

#### 方式 A: 自动下载（推荐）
```bash
python download_model.py
```

选择选项 1，自动下载 ONNX 模型（约 200MB）。

#### 方式 B: 手动下载
1. 访问：https://huggingface.co/smartywu/big-lama/resolve/main/big-lama.onnx
2. 下载文件
3. 重命名为：`lama_model.onnx`
4. 放在 `python_backend` 目录下

#### 方式 C: 使用 lama-cleaner
```bash
pip install lama-cleaner
```

lama-cleaner 会在首次运行时自动下载模型。

### 步骤 3: 启动服务

```bash
python main.py
```

你应该看到：
```
INFO:     Started server process
INFO:     Waiting for application startup.
✅ LaMa 模型加载成功: lama_model.onnx
🔧 使用设备: ['CUDAExecutionProvider', 'CPUExecutionProvider']
INFO:     Application startup complete.
INFO:     Uvicorn running on http://127.0.0.1:8000
```

---

## 验证安装

### 方法 1: 浏览器测试
打开浏览器访问：http://127.0.0.1:8000

应该看到：
```json
{
  "status": "running",
  "model_loaded": true,
  "device": ["CUDAExecutionProvider", "CPUExecutionProvider"]
}
```

### 方法 2: 运行测试脚本
```bash
python test_service.py
```

测试脚本会：
1. 检查服务是否运行
2. 测试去水印功能
3. 保存测试结果图片

---

## 常见问题

### Q1: 模型下载失败
**问题**：
```
❌ 下载失败: Connection timeout
```

**解决方案**：
1. 检查网络连接
2. 使用代理或 VPN
3. 手动下载模型（方式 B）

### Q2: CUDA 错误
**问题**：
```
❌ Failed to load library: cudnn64_8.dll
```

**解决方案**：
1. 安装 CUDA Toolkit 11.8+
2. 安装 cuDNN 8.x
3. 或者使用 CPU 版本（修改 requirements.txt）

### Q3: 内存不足
**问题**：
```
❌ MemoryError
```

**解决方案**：
1. 关闭其他程序释放内存
2. 降低图片分辨率
3. 使用 CPU 模式（内存占用更低）

### Q4: 端口被占用
**问题**：
```
❌ Address already in use
```

**解决方案**：
1. 修改 `main.py` 中的端口号：
```python
uvicorn.run(app, host="127.0.0.1", port=8001)  # 改为 8001
```
2. 或者关闭占用 8000 端口的程序

### Q5: 模型加载失败
**问题**：
```
❌ 模型加载失败: [Errno 2] No such file or directory
```

**解决方案**：
1. 确保 `lama_model.onnx` 在 `python_backend` 目录
2. 检查文件名是否正确
3. 重新下载模型

---

## 性能优化建议

### GPU 加速（推荐）
- **速度提升**：5-10倍
- **要求**：NVIDIA GPU + CUDA
- **安装**：`pip install onnxruntime-gpu`

### CPU 模式
- **优点**：兼容性好，无需 GPU
- **缺点**：速度较慢
- **安装**：`pip install onnxruntime`

### 批量处理
如果需要处理大量图片，建议：
1. 使用 GPU 加速
2. 调整图片分辨率（不超过 2048x2048）
3. 使用多进程并行处理

---

## 下一步

安装完成后：
1. 启动 Python 后端：`python main.py`
2. 启动 Flutter 应用
3. 在 Flutter 中使用图片去水印功能

---

## 技术支持

如果遇到问题：
1. 查看日志输出
2. 运行测试脚本：`python test_service.py`
3. 检查 [常见问题](#常见问题) 部分
4. 查看 FastAPI 文档：http://127.0.0.1:8000/docs
