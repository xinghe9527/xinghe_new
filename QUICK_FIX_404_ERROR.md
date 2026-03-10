# 🔧 快速修复：HTTP 404 错误

## 问题描述

错误信息：
```
Exception: 拒交付失败: Exception: 任务拒交失败: HTTP 404 ('detail':'Not Found')
```

## 原因

API 接口路径不匹配：
- Flutter 调用：`/api/generate`
- Python 原有接口：`/api/vidu/generate`

## ✅ 已修复

我已经在 Python API 服务中添加了通用接口 `/api/generate`，支持多平台。

## 🚀 如何使用修复

### 步骤 1：重启 Python API 服务

如果 Python 服务正在运行，需要先停止它：

**Windows**:
1. 在运行 `api_server.py` 的命令行窗口按 `Ctrl + C`
2. 等待服务停止

**然后重新启动**:
```bash
cd python_backend/web_automation
python api_server.py
```

**预期输出**:
```
INFO:     Started server process [xxxxx]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://127.0.0.1:8123
```

### 步骤 2：测试新接口（可选）

在另一个命令行窗口运行测试脚本：

```bash
cd python_backend/web_automation
python test_universal_api.py
```

**预期输出**:
```
✅ 健康检查通过
✅ 通用接口测试通过
✅ 任务已提交
```

### 步骤 3：在 Flutter 应用中测试

1. 确保 Python 服务正在运行
2. 打开 Flutter 应用
3. 进入视频空间
4. 输入提示词
5. 点击生成

**现在应该可以正常工作了！**

## 📊 新接口说明

### 接口地址
```
POST http://127.0.0.1:8123/api/generate
```

### 请求格式
```json
{
  "platform": "vidu",
  "tool_type": "text2video",
  "payload": {
    "prompt": "一个赛博朋克风格的女孩在霓虹灯下行走",
    "model": "vidu-q3"
  }
}
```

### 响应格式
```json
{
  "task_id": "task_20250227_143025_123456",
  "status": "pending",
  "message": "任务已受理，正在后台执行",
  "created_at": "2025-02-27T14:30:25.123456",
  "prompt": "一个赛博朋克风格的女孩在霓虹灯下行走"
}
```

## 🔍 验证修复

### 方法 1：查看 Python 日志

在 Python 服务的命令行窗口，应该看到：

```
✅ 任务已受理: task_20250227_143025_123456
📝 平台: vidu
📝 工具: text2video
📝 提示词: 一个赛博朋克风格的女孩在霓虹灯下行走
```

### 方法 2：查看 Flutter 日志

在 Flutter 控制台，应该看到：

```
✅ Python API 服务连接成功
✅ 开始并发提交 1 个视频任务
✅ 任务 1 提交成功: task_20250227_143025_123456
✅ 所有任务已提交，开始轮询
```

## ⚠️ 常见问题

### 问题 1：还是 404 错误
**原因**：Python 服务没有重启
**解决**：停止并重新启动 Python 服务

### 问题 2：连接超时
**原因**：Python 服务没有启动
**解决**：启动 Python 服务

### 问题 3：端口被占用
**原因**：8123 端口被其他程序占用
**解决**：
```bash
# Windows
netstat -ano | findstr :8123
taskkill /PID <进程ID> /F
```

## 📝 技术细节

### 修改的文件
1. `python_backend/web_automation/api_server.py`
   - 添加了 `UniversalGenerateRequest` 数据模型
   - 添加了 `/api/generate` 接口
   - 更新了 `TaskManager.create_task` 方法

### 兼容性
- 旧接口 `/api/vidu/generate` 仍然可用
- 新接口 `/api/generate` 支持多平台
- Flutter 客户端无需修改

### 支持的平台
- ✅ vidu（已实现）
- ⏳ jimeng（开发中）
- ⏳ keling（开发中）
- ⏳ hailuo（开发中）

### 支持的工具类型
- ✅ text2video（文生视频）
- ⏳ img2video（图生视频）
- ⏳ text2image（文生图片）

## 🎉 总结

修复已完成！只需要：
1. 重启 Python API 服务
2. 在 Flutter 应用中测试

现在应该可以正常生成视频了！
