# LaMa 水印去除引擎

这是一个基于 LaMa ONNX 模型的水印去除后端服务，可以打包为独立的可执行文件。

## 功能特性

- ✅ 基于 LaMa 深度学习模型的高质量水印去除
- ✅ 支持 GPU 加速（CUDA）和 CPU 推理
- ✅ FastAPI RESTful API 接口
- ✅ 打包为独立 EXE，无需 Python 环境
- ✅ 模型文件外置，便于更新和管理

## 快速开始

### 1. 下载模型文件

首先需要下载 LaMa ONNX 模型：

```bash
cd python_backend
python download_model.py
```

这会下载 `lama_model.onnx` 文件到当前目录。

### 2. 开发环境运行

如果你想在开发环境中测试：

```bash
# 安装依赖
pip install -r requirements.txt

# 启动服务
python main.py
```

服务会在 `http://127.0.0.1:8000` 启动。

### 3. 打包为独立可执行文件

#### Windows

```bash
# 运行打包脚本
build_engine.bat
```

这会生成 `watermark_engine.exe` 文件。

#### Linux/Mac

```bash
# 添加执行权限
chmod +x build_engine.sh

# 运行打包脚本
./build_engine.sh
```

这会生成 `watermark_engine` 可执行文件。

### 4. 部署到 Flutter 应用

将打包好的文件复制到 Flutter 应用的同级目录：

```
your_flutter_app/
├── your_app.exe (或 your_app)
├── watermark_engine.exe (或 watermark_engine)
└── lama_model.onnx
```

Flutter 应用会在启动时自动启动引擎，退出时自动清理。

## API 接口

### 健康检查

```
GET /
```

返回引擎状态和设备信息。

### 去除水印（文件上传）

```
POST /remove_watermark
Content-Type: multipart/form-data

参数:
- image: 原始图片文件
- mask: 遮罩图片文件（白色=需要修复的区域，黑色=保留区域）

返回: 处理后的图片（PNG 格式）
```

### 去除水印（Base64）

```
POST /remove_watermark_base64
Content-Type: application/x-www-form-urlencoded

参数:
- image_base64: 原始图片的 base64 字符串
- mask_base64: 遮罩图片的 base64 字符串

返回: JSON 格式，包含处理后的图片 base64 字符串
```

## 技术栈

- **FastAPI**: 高性能 Web 框架
- **ONNX Runtime**: 跨平台推理引擎
- **OpenCV**: 图像处理
- **PyInstaller**: Python 打包工具

## 文件说明

- `main.py`: FastAPI 服务主文件
- `download_model.py`: 模型下载工具
- `watermark_engine.spec`: PyInstaller 配置文件
- `build_engine.bat`: Windows 打包脚本
- `build_engine.sh`: Linux/Mac 打包脚本
- `requirements.txt`: Python 依赖列表

## 注意事项

1. **模型文件**: `lama_model.onnx` 必须与可执行文件在同一目录
2. **GPU 支持**: 如果有 NVIDIA GPU 和 CUDA，会自动使用 GPU 加速
3. **端口占用**: 默认使用 8000 端口，确保端口未被占用
4. **防火墙**: 确保防火墙允许本地 127.0.0.1:8000 访问

## 故障排查

### 引擎启动失败

1. 检查模型文件是否存在
2. 检查端口 8000 是否被占用
3. 查看 Flutter 应用的调试日志

### 处理速度慢

1. 确认是否使用了 GPU（查看启动日志）
2. 如果只有 CPU，处理大图片会较慢
3. 考虑降低图片分辨率

### 内存占用高

LaMa 模型需要一定的内存，特别是处理大图片时。建议：
- 限制输入图片的最大尺寸
- 批量处理时控制并发数量

## 许可证

本项目使用 MIT 许可证。
