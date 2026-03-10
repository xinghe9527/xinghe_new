# 🛡️ 安全部署指南

## ⚠️ 重要警告

**永远不要在 Flutter 构建之前运行 Python 打包脚本！**

错误的顺序会导致：
- Flutter Release 目录被清空
- 文件被误删
- 构建失败

## ✅ 正确的部署流程

### 方案 A：开发调试（Debug 模式）

```bash
# 1. 打包 Python 引擎（会自动复制到 Debug 目录）
cd python_backend
build_slim_engine.bat

# 2. 运行 Flutter 应用
cd ..
flutter run
```

### 方案 B：生产发布（Release 模式）

```bash
# 1. 先打包 Python 引擎（不会影响 Flutter）
cd python_backend
build_slim_engine.bat

# 2. 回到项目根目录，构建 Flutter Release
cd ..
flutter build windows --release

# 3. 部署引擎到 Release 目录
cd python_backend
deploy_to_release.bat
```

## 📋 脚本说明

### `build_slim_engine.bat`
- 清理 PyInstaller 临时文件（仅 `python_backend\dist` 和 `python_backend\build`）
- 打包 Python 引擎
- 自动复制到 Debug 目录（如果存在）
- **不会**删除 Flutter 的构建目录

### `deploy_to_release.bat`
- 安全地复制引擎和模型到 Release 目录
- 包含多重检查，防止误操作
- 显示部署结果

## 🔍 安全检查清单

在运行脚本前，确保：

- [ ] 当前在 `python_backend` 目录下
- [ ] `main.py` 文件存在（验证目录正确）
- [ ] `lama_model.onnx` 已下载
- [ ] 对于 Release 部署：Flutter 已构建完成

## 📦 最终文件结构

### Debug 目录
```
build/windows/x64/runner/Debug/
├── xinghe_new.exe          (Flutter 应用)
├── watermark_engine.exe    (1.08 GB - Python 引擎)
└── lama_model.onnx         (357 MB - LaMa 模型)
```

### Release 目录
```
build/windows/x64/runner/Release/
├── xinghe_new.exe          (Flutter 应用)
├── watermark_engine.exe    (1.08 GB)
└── lama_model.onnx         (357 MB)
```

## 🚨 如果出现问题

### 问题：文件被误删

**原因**：在错误的目录运行了脚本

**解决**：
1. 检查 Git 状态：`git status`
2. 恢复被删文件：`git restore <file>`
3. 重新构建 Flutter：`flutter build windows --release`

### 问题：Release 目录不存在

**原因**：还没有运行过 `flutter build windows --release`

**解决**：
```bash
cd ..
flutter build windows --release
cd python_backend
deploy_to_release.bat
```

### 问题：引擎体积过大（>1.5GB）

**原因**：PyInstaller 打包了不必要的依赖

**解决**：检查 `watermark_engine.spec` 的 `excludes` 列表是否正确

## 💡 最佳实践

1. **开发阶段**：使用 `build_slim_engine.bat` + `flutter run`
2. **发布阶段**：先 `flutter build`，再 `deploy_to_release.bat`
3. **版本控制**：不要提交 `dist/` 和 `build/` 目录到 Git
4. **备份重要文件**：在运行脚本前，确保重要文件已提交到 Git

## 📞 需要帮助？

如果遇到问题，请检查：
1. 当前工作目录是否正确
2. 所有依赖是否已安装
3. 模型文件是否已下载
4. Flutter 构建是否成功
