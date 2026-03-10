# 部署指南：独立引擎打包 + Flutter 静默守护

本指南详细说明如何将 Python 后端打包为独立可执行文件，并集成到 Flutter 应用中。

## 架构概述

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter 应用                          │
│  ┌───────────────────────────────────────────────────┐  │
│  │  WatermarkEngineManager (引擎管理器)              │  │
│  │  - 应用启动时静默启动引擎                         │  │
│  │  - 端口探活检测 (http://127.0.0.1:8000)          │  │
│  │  - 健康检查定时器                                 │  │
│  │  - 应用退出时清理进程                             │  │
│  └───────────────────────────────────────────────────┘  │
│                         ↓ HTTP                           │
│  ┌───────────────────────────────────────────────────┐  │
│  │  WatermarkRemoverService (API 调用)               │  │
│  │  - 发送图片和遮罩到后端                           │  │
│  │  - 接收处理结果                                   │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                         ↓ HTTP
┌─────────────────────────────────────────────────────────┐
│           watermark_engine.exe (独立引擎)               │
│  ┌───────────────────────────────────────────────────┐  │
│  │  FastAPI + Uvicorn                                │  │
│  │  - 监听 127.0.0.1:8000                            │  │
│  │  - 加载 lama_model.onnx                           │  │
│  │  - ONNX Runtime 推理                              │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## 第一步：准备 Python 环境

### 1.1 安装依赖

```bash
cd python_backend
pip install -r requirements.txt
```

### 1.2 下载模型文件

```bash
python download_model.py
```

这会下载 `lama_model.onnx` 文件（约 50MB）。

### 1.3 测试开发环境

```bash
# 启动服务
python main.py

# 在另一个终端测试
python test_engine.py
```

如果看到 "✅ 引擎运行正常！"，说明环境配置成功。

## 第二步：打包独立引擎

### 2.1 Windows 打包

```bash
# 运行打包脚本
build_engine.bat
```

打包完成后会生成：
- `watermark_engine.exe` (约 100-200MB)

### 2.2 Linux/Mac 打包

```bash
# 添加执行权限
chmod +x build_engine.sh

# 运行打包脚本
./build_engine.sh
```

打包完成后会生成：
- `watermark_engine` (约 100-200MB)

### 2.3 验证打包结果

```bash
# Windows
watermark_engine.exe

# Linux/Mac
./watermark_engine
```

然后在浏览器访问 `http://127.0.0.1:8000`，应该看到：

```json
{
  "status": "running",
  "model_loaded": true,
  "device": ["CUDAExecutionProvider", "CPUExecutionProvider"]
}
```

## 第三步：集成到 Flutter 应用

### 3.1 文件结构

将打包好的文件放到 Flutter 应用的同级目录：

```
your_flutter_app/
├── build/
│   └── windows/
│       └── runner/
│           └── Release/
│               ├── your_app.exe          # Flutter 应用
│               ├── watermark_engine.exe  # 水印引擎
│               └── lama_model.onnx       # 模型文件
```

### 3.2 Flutter 代码已集成

以下代码已经集成到项目中：

1. **引擎管理器**: `lib/services/watermark_engine_manager.dart`
   - 静默启动引擎
   - 端口探活检测
   - 健康检查
   - 进程清理

2. **应用初始化**: `lib/main.dart`
   - 在 `main()` 函数中启动引擎
   - 在 `XingheApp` 中监听应用生命周期
   - 应用退出时清理引擎

3. **API 调用**: `lib/services/watermark_remover_service.dart`
   - 调用引擎 API
   - 处理图片和遮罩

### 3.3 测试集成

1. 启动 Flutter 应用
2. 查看控制台日志，应该看到：
   ```
   🚀 正在启动水印去除引擎...
   📂 引擎路径: C:\...\watermark_engine.exe
   🔧 引擎进程已启动 (PID: 12345)
   ⏳ 等待引擎就绪...
   ✅ 引擎已就绪 (耗时: 3 秒)
   ✅ 水印去除引擎已启动
   ```

3. 打开工具箱 → 图片去水印
4. 选择图片并标记水印区域
5. 点击"处理当前"

## 第四步：发布部署

### 4.1 Windows 发布

```bash
# 构建 Flutter 应用
flutter build windows --release

# 复制引擎文件
cd build/windows/runner/Release
copy path\to\watermark_engine.exe .
copy path\to\lama_model.onnx .
```

### 4.2 创建安装包

使用 Inno Setup 或 NSIS 创建安装包时，确保包含：
- `your_app.exe`
- `watermark_engine.exe`
- `lama_model.onnx`
- 其他 Flutter 依赖文件

### 4.3 用户电脑要求

- **无需 Python 环境**：引擎已打包所有依赖
- **无需手动启动**：Flutter 自动管理
- **无需配置**：开箱即用

## 故障排查

### 问题 1: 引擎启动失败

**症状**: 控制台显示 "❌ 引擎启动超时"

**解决方案**:
1. 检查 `watermark_engine.exe` 是否存在
2. 检查 `lama_model.onnx` 是否存在
3. 检查端口 8000 是否被占用
4. 手动运行 `watermark_engine.exe` 查看错误信息

### 问题 2: 模型加载失败

**症状**: 引擎启动但 `model_loaded: false`

**解决方案**:
1. 确认 `lama_model.onnx` 与 `watermark_engine.exe` 在同一目录
2. 检查模型文件是否完整（约 50MB）
3. 重新下载模型文件

### 问题 3: 处理速度慢

**症状**: 处理一张图片需要很长时间

**解决方案**:
1. 检查是否使用了 GPU（查看 `device` 字段）
2. 如果只有 CPU，处理大图片会较慢（正常现象）
3. 考虑降低图片分辨率

### 问题 4: 引擎进程残留

**症状**: 关闭应用后引擎进程仍在运行

**解决方案**:
1. 检查 Flutter 应用是否正常退出
2. 手动结束进程：`taskkill /F /IM watermark_engine.exe`
3. 检查应用生命周期监听是否正常

## 性能优化

### GPU 加速

如果用户有 NVIDIA GPU：
1. 引擎会自动使用 CUDA 加速
2. 处理速度提升 5-10 倍
3. 无需额外配置

### 内存优化

1. 限制输入图片最大尺寸（如 4096x4096）
2. 批量处理时控制并发数量
3. 处理完成后及时释放内存

### 启动优化

1. 引擎启动需要 2-5 秒（加载模型）
2. 可以在应用启动画面期间完成
3. 使用健康检查确保引擎就绪

## 安全考虑

1. **本地运行**: 引擎只监听 127.0.0.1，不暴露到外网
2. **进程隔离**: 引擎作为独立进程运行，崩溃不影响主应用
3. **自动清理**: 应用退出时自动清理引擎进程
4. **无网络请求**: 所有处理都在本地完成

## 更新维护

### 更新模型

1. 下载新的 `lama_model.onnx`
2. 替换旧文件
3. 重启应用

### 更新引擎

1. 重新打包 Python 后端
2. 替换 `watermark_engine.exe`
3. 重启应用

### 版本兼容性

- 引擎版本向后兼容
- API 接口保持稳定
- 模型文件可独立更新

## 总结

通过这个架构，我们实现了：

✅ **用户友好**: 无需安装 Python，开箱即用  
✅ **自动管理**: Flutter 自动启动和清理引擎  
✅ **高性能**: 支持 GPU 加速，处理速度快  
✅ **可维护**: 模型和引擎可独立更新  
✅ **安全可靠**: 本地运行，进程隔离  

这是一个商业级的解决方案，适合面向普通用户的桌面应用。
