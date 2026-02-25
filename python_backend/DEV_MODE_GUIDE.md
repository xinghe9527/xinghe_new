# 开发模式使用指南

本指南说明如何在开发阶段快速调试水印去除功能，无需每次都打包 EXE。

## 🚀 快速开始（开发模式）

### 方式 1: 手动启动 Python 服务（推荐）

这是最简单的开发方式，适合频繁修改 Python 代码时使用。

#### 步骤 1: 下载模型（首次使用）

```bash
cd python_backend
python download_model.py
```

#### 步骤 2: 启动 Python 后端

打开一个新的终端窗口：

```bash
cd python_backend
python main.py
```

你会看到：

```
INFO:     Started server process [12345]
INFO:     Waiting for application startup.
✅ LaMa 模型加载成功: D:\...\lama_model.onnx
🔧 使用设备: ['CUDAExecutionProvider', 'CPUExecutionProvider']
INFO:     Application startup complete.
INFO:     Uvicorn running on http://127.0.0.1:8000
```

**保持这个终端窗口打开！**

#### 步骤 3: 启动 Flutter 应用

在另一个终端窗口：

```bash
flutter run
```

Flutter 会自动检测到已运行的后端服务，你会看到：

```
🚀 正在启动水印去除引擎...
⚠️ 找不到引擎文件: D:\...\watermark_engine.exe
🔍 尝试连接已运行的后端服务...
✅ 检测到后端服务已运行（开发模式）
```

现在你可以正常使用水印去除功能了！

### 方式 2: 打包后使用（接近生产环境）

如果你想测试接近生产环境的行为：

#### 步骤 1: 打包引擎

```bash
cd python_backend
build_engine.bat  # Windows
./build_engine.sh # Linux/Mac
```

打包脚本会自动：
1. 打包 Python 代码为 EXE
2. 复制 EXE 和模型到 Flutter 的 Debug 目录
3. 复制 EXE 和模型到 Flutter 的 Release 目录

#### 步骤 2: 运行 Flutter

```bash
flutter run
```

Flutter 会自动启动打包好的引擎。

## 🔄 开发工作流

### 修改 Python 代码后

如果你修改了 `main.py` 或其他 Python 文件：

**方式 1（手动启动）**:
1. 在 Python 终端按 `Ctrl+C` 停止服务
2. 重新运行 `python main.py`
3. Flutter 会自动重新连接

**方式 2（打包模式）**:
1. 重新运行 `build_engine.bat`
2. 重启 Flutter 应用

### 修改 Flutter 代码后

直接使用 Flutter 的热重载：
- 按 `r` 热重载
- 按 `R` 热重启

Python 后端不需要重启。

## 🐛 调试技巧

### 查看 Python 日志

如果使用手动启动模式，Python 终端会实时显示所有日志：

```
📥 接收到去水印请求
📐 图片尺寸: (2816, 1536), 遮罩尺寸: (2816, 1536)
🔄 输入形状: image=(1, 3, 1536, 2816), mask=(1, 1, 1536, 2816)
🚀 开始 LaMa 推理...
✅ 推理完成
📤 返回处理结果
```

### 测试后端 API

使用浏览器或 curl 测试：

```bash
# 健康检查
curl http://127.0.0.1:8000/

# 应该返回
{
  "status": "running",
  "model_loaded": true,
  "device": ["CUDAExecutionProvider", "CPUExecutionProvider"]
}
```

### 检查端口占用

如果提示端口被占用：

**Windows**:
```bash
netstat -ano | findstr :8000
taskkill /F /PID <进程ID>
```

**Linux/Mac**:
```bash
lsof -i :8000
kill -9 <进程ID>
```

## 📊 性能对比

| 模式 | 启动时间 | 修改代码后 | 适用场景 |
|------|---------|-----------|---------|
| 手动启动 | 2-3 秒 | 重启 Python | 频繁修改 Python 代码 |
| 打包模式 | 3-5 秒 | 重新打包 | 测试生产环境行为 |

## ⚠️ 注意事项

### 开发模式限制

1. **不会自动清理进程**: 手动启动的 Python 服务需要手动停止（Ctrl+C）
2. **需要 Python 环境**: 开发机器必须安装 Python 和依赖
3. **不隐藏窗口**: Python 终端窗口会一直显示

### 生产模式优势

1. **自动管理**: Flutter 自动启动和清理引擎
2. **无需 Python**: 用户电脑不需要 Python 环境
3. **静默运行**: 没有命令行窗口

## 🎯 推荐工作流

### 日常开发（修改代码）

```bash
# 终端 1: 启动 Python 后端
cd python_backend
python main.py

# 终端 2: 启动 Flutter
flutter run

# 修改代码后
# - Python 代码: Ctrl+C 停止，重新运行 python main.py
# - Flutter 代码: 按 r 热重载
```

### 测试发布版本

```bash
# 1. 打包引擎
cd python_backend
build_engine.bat

# 2. 构建 Flutter
flutter build windows --release

# 3. 测试
cd build/windows/runner/Release
xinghe_new.exe
```

## 💡 常见问题

### Q: 为什么 Flutter 找不到引擎？

A: 这是正常的开发模式行为。只要你手动启动了 Python 服务，Flutter 会自动连接。

### Q: 可以同时运行多个 Flutter 实例吗？

A: 可以，但它们会共享同一个 Python 后端（端口 8000）。

### Q: 如何切换到生产模式？

A: 运行 `build_engine.bat` 打包引擎，然后重启 Flutter。

### Q: 打包后还能用开发模式吗？

A: 可以。如果 EXE 存在，Flutter 会优先使用 EXE。如果你想用开发模式，删除或重命名 EXE 即可。

## 📚 相关文档

- [快速开始](QUICKSTART.md) - 5 分钟上手
- [部署指南](DEPLOYMENT_GUIDE.md) - 详细部署说明
- [API 文档](README.md) - 后端 API 说明

---

**提示**: 开发模式是为了提高开发效率，生产环境请使用打包模式。
