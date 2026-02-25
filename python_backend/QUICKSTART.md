# 快速开始指南

这是一个 5 分钟快速上手指南，帮助你快速测试和部署水印去除功能。

## 🚀 5 分钟快速开始

### 步骤 1: 下载模型（首次使用）

```bash
cd python_backend
python download_model.py
```

等待下载完成（约 50MB）。

### 步骤 2: 打包引擎

#### Windows 用户

```bash
build_engine.bat
```

#### Linux/Mac 用户

```bash
chmod +x build_engine.sh
./build_engine.sh
```

打包完成后会生成 `watermark_engine.exe`（或 `watermark_engine`）。

### 步骤 3: 测试引擎

```bash
# 启动引擎
watermark_engine.exe  # Windows
./watermark_engine    # Linux/Mac

# 在另一个终端测试
python test_engine.py
```

如果看到 "✅ 引擎运行正常！"，说明成功了！

### 步骤 4: 集成到 Flutter

将以下文件复制到 Flutter 应用的同级目录：

```
your_flutter_app/
├── your_app.exe
├── watermark_engine.exe  ← 复制这个
└── lama_model.onnx       ← 复制这个
```

### 步骤 5: 运行 Flutter 应用

```bash
flutter run
```

应用会自动启动引擎，你可以在工具箱中使用图片去水印功能了！

## 📋 检查清单

在发布应用前，确保：

- [ ] `watermark_engine.exe` 已打包
- [ ] `lama_model.onnx` 已下载
- [ ] 引擎可以独立运行
- [ ] Flutter 应用可以连接到引擎
- [ ] 去水印功能正常工作

## 🔧 常见问题

### Q: 打包失败怎么办？

A: 确保已安装 PyInstaller：
```bash
pip install pyinstaller
```

### Q: 引擎启动失败？

A: 检查：
1. 模型文件是否存在
2. 端口 8000 是否被占用
3. 防火墙是否阻止

### Q: 处理速度慢？

A: 这是正常的，CPU 处理大图片需要时间。如果有 NVIDIA GPU，会自动加速。

## 📚 更多信息

- 详细部署指南: [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
- API 文档: [README.md](README.md)
- 技术架构: 见 DEPLOYMENT_GUIDE.md

## 💡 提示

1. 首次启动引擎需要 2-5 秒加载模型
2. 引擎会在后台静默运行，不会弹出窗口
3. 关闭 Flutter 应用时引擎会自动退出
4. 所有处理都在本地完成，不需要网络

## 🎉 完成！

现在你的应用已经具备了专业的水印去除功能，用户无需安装 Python 或任何额外软件！
