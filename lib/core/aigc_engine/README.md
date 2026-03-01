# 🚀 AIGC 自动化网关 - 快速开始

## 📋 简介

统一的 AIGC 自动化 API 客户端，用于与本地 Python FastAPI 服务通信。

**支持平台**: Vidu、即梦、可灵、海螺  
**支持功能**: 文生视频、图生视频、文生图

---

## ⚡ 快速开始（3 步）

### 1. 确保 Python API 服务已启动

```bash
python python_backend/web_automation/api_server.py
```

### 2. 在 Flutter 中导入

```dart
import 'package:xinghe_new/core/aigc_engine/automation_api_client.dart';
```

### 3. 调用 API

```dart
// 提交任务
final result = await aigcApiClient.viduText2Video(
  prompt: '一个赛博朋克风格的女孩',
);

print('任务 ID: ${result.taskId}');

// 轮询查询状态
final finalResult = await aigcApiClient.pollTaskStatus(
  taskId: result.taskId,
  onProgress: (progress) {
    print('状态: ${progress.status}');
  },
);

// 获取视频地址
if (finalResult.isSuccess) {
  print('视频地址: ${finalResult.videoUrl}');
  print('本地路径: ${finalResult.localVideoPath}');
}
```

---

## 📚 文档导航

| 文档 | 说明 |
|------|------|
| [README.md](README.md) | 快速开始（本文件）|
| [USAGE_GUIDE.md](USAGE_GUIDE.md) | 详细使用指南 |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 架构设计文档 |

---

## 🎯 核心功能

### 1. 多平台支持

```dart
// Vidu
await aigcApiClient.viduText2Video(prompt: '...');

// 即梦
await aigcApiClient.jimengText2Video(prompt: '...');

// 可灵
await aigcApiClient.kelingText2Video(prompt: '...');

// 海螺
await aigcApiClient.hailuoText2Video(prompt: '...');
```

### 2. 多工具类型

```dart
// 文生视频
await aigcApiClient.viduText2Video(prompt: '...');

// 图生视频
await aigcApiClient.viduImage2Video(
  imageUrl: 'https://...',
  prompt: '...',
);
```

### 3. 任务轮询

```dart
final result = await aigcApiClient.pollTaskStatus(
  taskId: taskId,
  onProgress: (progress) {
    print('进度: ${progress.status}');
  },
);
```

### 4. 浏览器控制

```dart
// 显示浏览器
await aigcApiClient.showBrowser();

// 隐藏浏览器
await aigcApiClient.hideBrowser();
```

---

## 📦 数据模型

### AigcTaskResult

```dart
class AigcTaskResult {
  final String taskId;           // 任务 ID
  final String status;           // 状态
  final String? videoUrl;        // ⭐ 云端视频地址
  final String? localVideoPath;  // ⭐ 本地视频路径
  
  bool get isSuccess;            // 是否成功
  bool get isFailed;             // 是否失败
  bool get isCompleted;          // 是否完成
  String? get mediaUrl;          // 获取媒体地址（优先云端）
}
```

---

## 🎬 完整示例

```dart
import 'package:flutter/material.dart';
import 'package:xinghe_new/core/aigc_engine/automation_api_client.dart';

class VideoGenerationDemo extends StatefulWidget {
  @override
  _VideoGenerationDemoState createState() => _VideoGenerationDemoState();
}

class _VideoGenerationDemoState extends State<VideoGenerationDemo> {
  String _status = '等待提交';
  String? _videoUrl;

  Future<void> _generateVideo() async {
    setState(() => _status = '提交任务中...');

    try {
      // 1. 提交任务
      final result = await aigcApiClient.viduText2Video(
        prompt: '一个赛博朋克风格的女孩',
      );

      setState(() => _status = '任务已提交，等待执行...');

      // 2. 轮询查询状态
      final finalResult = await aigcApiClient.pollTaskStatus(
        taskId: result.taskId,
        onProgress: (progress) {
          setState(() => _status = progress.message);
        },
      );

      // 3. 处理结果
      if (finalResult.isSuccess) {
        setState(() {
          _status = '✅ 视频生成成功！';
          _videoUrl = finalResult.videoUrl ?? finalResult.localVideoPath;
        });
      } else {
        setState(() => _status = '❌ 任务失败: ${finalResult.error}');
      }
    } catch (e) {
      setState(() => _status = '❌ 错误: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('视频生成演示')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('状态: $_status'),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _generateVideo,
              child: Text('生成视频'),
            ),
            if (_videoUrl != null) ...[
              SizedBox(height: 20),
              Text('视频地址: $_videoUrl'),
            ],
          ],
        ),
      ),
    );
  }
}
```

---

## ⚠️ 注意事项

### 1. 确保 Python 服务已启动

```bash
# 检查服务是否运行
curl http://127.0.0.1:8123/health

# 如果未启动，运行
python python_backend/web_automation/api_server.py
```

### 2. 在代码中检查服务

```dart
final isHealthy = await aigcApiClient.checkHealth();
if (!isHealthy) {
  print('❌ API 服务未启动');
  return;
}
```

### 3. 处理错误

```dart
try {
  final result = await aigcApiClient.viduText2Video(prompt: '...');
} catch (e) {
  if (e.toString().contains('请检查 Python API 服务是否启动')) {
    // 提示用户启动服务
  }
}
```

---

## 🔧 配置

### 修改 API 地址

如果 Python 服务器使用了不同的端口，修改 `automation_api_client.dart`：

```dart
class AutomationApiClient {
  static const String _baseUrl = 'http://127.0.0.1:8123';  // 修改这里
}
```

---

## 📞 获取帮助

- **详细使用指南**: [USAGE_GUIDE.md](USAGE_GUIDE.md)
- **架构设计**: [ARCHITECTURE.md](ARCHITECTURE.md)
- **Python API 文档**: `python_backend/web_automation/API_SERVER_GUIDE.md`

---

## ✨ 特性

- ✅ 统一接口设计
- ✅ 多平台支持
- ✅ 类型安全
- ✅ 完整的错误处理
- ✅ 任务轮询
- ✅ 浏览器控制
- ✅ 完全隔离现有代码
- ✅ 高扩展性

---

**版本**: 1.0.0  
**更新时间**: 2026-02-27  
**状态**: ✅ 生产就绪
