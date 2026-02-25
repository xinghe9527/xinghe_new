# 正确的构建流程（Flutter + Python 引擎）

## ⚠️ 重要原则

1. **Flutter 和 Python 打包必须分离**：不要让 Python 打包脚本清空 Flutter 的构建目录
2. **先 Flutter 后 Python**：Flutter 构建完成后，再将 Python 引擎复制进去
3. **极限瘦身**：Python 引擎只包含必要依赖，排除所有大型库（torch、matplotlib 等）

## 📋 完整构建流程

### 开发模式（Debug）

```bash
# 步骤 1：构建 Flutter Debug 版本
flutter build windows --debug

# 步骤 2：打包 Python 引擎（极限瘦身版）
cd python_backend
build_slim_engine.bat

# 步骤 3：运行应用
cd ..
.\build\windows\x64\runner\Debug\xinghe_new.exe
```

### 生产模式（Release）

```bash
# 步骤 1：构建 Flutter Release 版本
flutter build windows --release

# 步骤 2：打包 Python 引擎（如果还没打包）
cd python_backend
pyinstaller --clean watermark_engine.spec

# 步骤 3：手动复制引擎到 Release 目录
copy dist\watermark_engine.exe ..\build\windows\x64\runner\Release\
copy lama_model.onnx ..\build\windows\x64\runner\Release\

# 步骤 4：测试 Release 版本
cd ..
.\build\windows\x64\runner\Release\xinghe_new.exe
```

## 🔧 Python 引擎瘦身策略

### 已排除的大型依赖

- `torch` (>2GB)
- `torchvision`
- `torchaudio`
- `matplotlib`
- `scipy`
- `pandas`
- `PyQt5/PyQt6`
- `PySide2/PySide6`
- `tkinter`
- `IPython`
- `jupyter`
- `sympy`

### 保留的核心依赖

- `onnxruntime-gpu` (推理引擎)
- `fastapi` (Web 服务)
- `uvicorn` (ASGI 服务器)
- `numpy` (数值计算)
- `opencv-python-headless` (图像处理，无 GUI)
- `pillow` (图像编解码)

### 预期体积

- **瘦身前**: ~1.7GB
- **瘦身后**: ~300-500MB（取决于 onnxruntime-gpu 版本）

## 📦 目录结构

```
build/windows/x64/runner/
├── Debug/
│   ├── xinghe_new.exe          # Flutter 应用
│   ├── watermark_engine.exe    # Python 引擎
│   ├── lama_model.onnx         # LaMa 模型
│   └── *.dll                   # Flutter 插件 DLL
└── Release/
    ├── xinghe_new.exe
    ├── watermark_engine.exe
    ├── lama_model.onnx
    └── *.dll
```

## 🚨 常见错误

### 错误 1：Release 目录被清空

**原因**：打包脚本错误地清理了 Flutter 构建目录

**解决**：
1. 重新运行 `flutter build windows --release`
2. 确保 Python 打包脚本只清理 `python_backend/dist` 和 `python_backend/build`

### 错误 2：引擎体积过大

**原因**：PyInstaller 包含了不必要的依赖（如 torch）

**解决**：
1. 检查 `watermark_engine.spec` 的 `excludes` 列表
2. 确保已安装 `opencv-python-headless` 而非 `opencv-python`
3. 重新打包

### 错误 3：引擎启动失败

**原因**：缺少必要的依赖或模型文件

**解决**：
1. 确保 `lama_model.onnx` 与 `watermark_engine.exe` 在同一目录
2. 检查是否安装了 `onnxruntime-gpu`
3. 临时启用控制台查看错误信息（spec 文件中 `console=True`）

## 💡 开发技巧

### 快速测试（不重新打包）

如果只修改了 Flutter 代码：
```bash
flutter run -d windows
```

如果只修改了 Python 代码：
```bash
cd python_backend
python main.py  # 手动运行后端
```

### 检查引擎依赖

```bash
cd python_backend\dist
.\watermark_engine.exe  # 查看启动日志
```

### 清理所有构建产物

```bash
# 清理 Flutter
flutter clean

# 清理 Python
cd python_backend
rmdir /s /q dist
rmdir /s /q build
```
