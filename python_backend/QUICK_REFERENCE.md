# 🚀 快速参考卡片

## 一键命令

### 开发调试
```bash
cd python_backend && build_slim_engine.bat && cd .. && flutter run
```

### 生产发布
```bash
# 步骤 1: 打包引擎
cd python_backend
build_slim_engine.bat

# 步骤 2: 构建 Flutter
cd ..
flutter build windows --release

# 步骤 3: 部署引擎
cd python_backend
deploy_to_release.bat
```

## 文件位置速查

| 文件 | 位置 | 大小 |
|------|------|------|
| Python 源码 | `python_backend/main.py` | - |
| 打包后的引擎 | `python_backend/dist/watermark_engine.exe` | ~1.08 GB |
| LaMa 模型 | `python_backend/lama_model.onnx` | 357 MB |
| Debug 应用 | `build/windows/x64/runner/Debug/xinghe_new.exe` | - |
| Release 应用 | `build/windows/x64/runner/Release/xinghe_new.exe` | - |

## 常见问题速查

| 问题 | 解决方案 |
|------|----------|
| 文件被删除 | 确保在 `python_backend` 目录下运行脚本 |
| Release 目录不存在 | 先运行 `flutter build windows --release` |
| 引擎启动失败 | 检查 `lama_model.onnx` 是否在同一目录 |
| 体积过大 | 检查 `watermark_engine.spec` 的 `excludes` 列表 |

## 安全检查

运行脚本前，确认：
- ✅ 当前目录：`python_backend`
- ✅ 文件存在：`main.py`
- ✅ 模型已下载：`lama_model.onnx`

## 脚本功能

| 脚本 | 功能 | 安全性 |
|------|------|--------|
| `build_slim_engine.bat` | 打包引擎 + 复制到 Debug | ✅ 安全（有目录检查） |
| `deploy_to_release.bat` | 复制到 Release | ✅ 安全（多重检查） |
| `quick_test.bat` | 测试引擎 | ✅ 安全（只读操作） |

## 体积优化

当前配置已排除：
- ❌ PyTorch (>500 MB)
- ❌ Matplotlib (~100 MB)
- ❌ Scipy (~50 MB)
- ❌ Pandas (~50 MB)
- ❌ Qt 框架 (~200 MB)

保留必需：
- ✅ onnxruntime-gpu (226 MB)
- ✅ FastAPI + Uvicorn (~20 MB)
- ✅ OpenCV-headless (~30 MB)
- ✅ NumPy (~20 MB)

## 紧急恢复

如果出现问题：
```bash
# 恢复 Git 文件
git restore .

# 重新构建 Flutter
flutter clean
flutter build windows --release

# 重新打包引擎
cd python_backend
build_slim_engine.bat
deploy_to_release.bat
```
