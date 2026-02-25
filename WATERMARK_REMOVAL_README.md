# 水印去除功能 - 快速参考

## 🚀 快速开始（3 步）

### 开发模式（推荐）

```bash
# 步骤 1: 启动 Python 后端
cd python_backend
python quick_test.bat  # Windows 自动检查依赖和模型

# 步骤 2: 启动 Flutter（新终端）
flutter run

# 步骤 3: 使用功能
# 工具箱 → 图片去水印
```

### 生产模式

```bash
# 步骤 1: 打包引擎（只需一次）
cd python_backend
build_engine.bat  # 自动部署到 Flutter 目录

# 步骤 2: 运行 Flutter
flutter run

# 步骤 3: 使用功能
# 工具箱 → 图片去水印
```

## 📚 完整文档

### 核心文档
- **[最近改进](RECENT_IMPROVEMENTS.md)** - 最新的开发体验优化
- **[开发模式指南](python_backend/DEV_MODE_GUIDE.md)** - 开发调试必读
- **[快速开始](python_backend/QUICKSTART.md)** - 5 分钟上手
- **[部署指南](python_backend/DEPLOYMENT_GUIDE.md)** - 详细部署说明

### 参考文档
- **[使用说明](HOW_TO_USE_WATERMARK_REMOVAL.md)** - 用户和开发者指南
- **[实现总结](WATERMARK_REMOVAL_IMPLEMENTATION.md)** - 架构和技术细节
- **[待办事项](WATERMARK_REMOVAL_TODO.md)** - 测试清单
- **[API 文档](python_backend/README.md)** - 后端 API 说明

## 🔧 常用命令

### Python 后端

```bash
# 下载模型（首次使用）
cd python_backend
python download_model.py

# 启动开发服务
python main.py

# 快速测试（自动检查依赖和模型）
quick_test.bat

# 打包引擎（自动部署到 Flutter）
build_engine.bat  # Windows
./build_engine.sh # Linux/Mac

# 测试引擎健康
python test_engine.py
```

### Flutter 应用

```bash
# 开发运行
flutter run

# 热重载
r

# 热重启
R

# 构建发布版本
flutter build windows --release
```

## 🐛 故障排查

### 问题 1: 找不到引擎文件

**症状**: `❌ 找不到引擎文件: watermark_engine.exe`

**解决方案**（选一个）:
1. **开发模式**: 手动启动 Python 服务
   ```bash
   cd python_backend
   python main.py
   ```

2. **生产模式**: 打包引擎
   ```bash
   cd python_backend
   build_engine.bat
   ```

### 问题 2: 后端服务未运行

**症状**: `❌ 后端服务未运行`

**解决方案**:
1. 检查 Python 服务是否启动
2. 检查端口 8000 是否被占用
3. 运行 `python test_engine.py` 测试连接

### 问题 3: 模型文件缺失

**症状**: `❌ 找不到模型文件: lama_model.onnx`

**解决方案**:
```bash
cd python_backend
python download_model.py
```

### 问题 4: 处理失败

**症状**: 点击"处理当前"后报错

**解决方案**:
1. 确保后端服务正常运行
2. 检查图片格式（支持 JPG、PNG）
3. 查看 Python 终端的错误日志
4. 尝试重新标记水印区域

## 💡 开发技巧

### 修改 Python 代码后

```bash
# 在 Python 终端按 Ctrl+C
# 重新运行
python main.py
# Flutter 会自动重新连接
```

### 修改 Flutter 代码后

```bash
# 在 Flutter 终端按 r（热重载）
# 或按 R（热重启）
```

### 查看实时日志

Python 终端会显示所有请求日志：
```
📥 接收到去水印请求
📐 图片尺寸: (2816, 1536)
🚀 开始 LaMa 推理...
✅ 推理完成
📤 返回处理结果
```

## 🎯 推荐工作流

### 日常开发

```bash
# 终端 1: Python 后端
cd python_backend
python main.py

# 终端 2: Flutter 前端
flutter run

# 修改代码后
# Python: Ctrl+C 重启
# Flutter: 按 r 热重载
```

### 测试发布

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

## 📊 性能参考

- **引擎启动**: 2-5 秒
- **处理速度（CPU）**: 5-10 秒/张（1920x1080）
- **处理速度（GPU）**: 1-2 秒/张（1920x1080）
- **内存占用**: 500MB-1GB

## 🔗 快速链接

| 文档 | 用途 |
|------|------|
| [RECENT_IMPROVEMENTS.md](RECENT_IMPROVEMENTS.md) | 查看最新改进 |
| [DEV_MODE_GUIDE.md](python_backend/DEV_MODE_GUIDE.md) | 学习开发模式 |
| [QUICKSTART.md](python_backend/QUICKSTART.md) | 快速上手 |
| [DEPLOYMENT_GUIDE.md](python_backend/DEPLOYMENT_GUIDE.md) | 部署到生产 |

## ❓ 需要帮助？

1. 查看对应的文档
2. 运行 `python test_engine.py` 测试后端
3. 查看 Python 和 Flutter 的日志输出

---

**提示**: 开发时使用开发模式，发布时使用生产模式。
