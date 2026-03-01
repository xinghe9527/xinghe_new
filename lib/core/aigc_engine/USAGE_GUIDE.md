# 🚀 AIGC 自动化网关使用指南

## 📋 概述

`AutomationApiClient` 是统一的 AIGC 自动化 API 客户端，负责与本地 Python FastAPI 服务通信。

### 核心特性

- ✅ **统一接口**：所有平台使用相同的调用方式
- ✅ **高扩展性**：新增平台无需修改核心逻辑
- ✅ **完全隔离**：不影响现有业务代码
- ✅ **多平台支持**：Vidu、即梦、可灵、海螺
- ✅ **多工具类型**：文生视频、图生视频、文生图
- ✅ **任务轮询**：自动轮询直到任务完成
- ✅ **窗口控制**：显示/隐藏浏览器窗口

---

## 🔧 安装依赖

在 `pubspec.yaml` 中添加：

```yaml
dependencies:
  http: ^1.1.0
```

---

## 📡 基础使用

### 1. 导入客户端

```dart
import 'package:xinghe_new/core/aigc_engine/automation_api_client.dart';
```

### 2. 使用全局单例（推荐）

```dart
// 使用全局单例
final result = await aigcApiClient.viduText2Video(
  prompt: '一个赛博朋克风格的女孩',
);
```

### 3. 创建自定义实例

```dart
// 创建自定义实例
final client = AutomationApiClient(
  timeout: Duration(seconds: 60),
);

final result = await client.viduText2Video(
  prompt: '一个赛博朋克风格的女孩',
);

// 使用完毕后释放资源
client.dispose();
```

---

## 🎯 核心方法

### 1. 提交生成任务（统一入口）

```dart
final result = await aigcApiClient.submitGenerationTask(
  platform: 'vidu',           // 平台：vidu, jimeng, keling, hailuo
  toolType: 'text2video',     // 工具：text2video, img2video, text2image
  payload: {
    'prompt': '一个赛博朋克风格的女孩',
    'model': 'vidu-1.5',      // 可选：模型名称
    'duration': 4,            // 可选：视频时长（秒）
    'aspect_ratio': '16:9',   // 可选：宽高比
  },
);

print('任务 ID: ${result.taskId}');
print('状态: ${result.status}');
```

---

## 🚀 便捷方法（各平台快速调用）

### Vidu 平台

#### 文生视频

```dart
final result = await aigcApiClient.viduText2Video(
  prompt: '一个赛博朋克风格的女孩',
  model: 'vidu-1.5',        // 可选
  duration: 4,              // 可选：4 秒或 8 秒
  aspectRatio: '16:9',      // 可选：16:9 或 9:16
);
```

#### 图生视频

```dart
final result = await aigcApiClient.viduImage2Video(
  imageUrl: 'https://example.com/image.jpg',
  prompt: '让这个女孩跳舞',
  model: 'vidu-1.5',
  duration: 4,
);
```

---

### 即梦平台

```dart
final result = await aigcApiClient.jimengText2Video(
  prompt: '一个古风美女在弹琵琶',
  model: 'jimeng-v2',       // 可选
  duration: 5,              // 可选
);
```

---

### 可灵平台

```dart
final result = await aigcApiClient.kelingText2Video(
  prompt: '一只猫在月球上漫步',
  model: 'keling-pro',      // 可选
  duration: 5,              // 可选
);
```

---

### 海螺平台

```dart
final result = await aigcApiClient.hailuoText2Video(
  prompt: '未来城市的夜景',
  model: 'hailuo-v1',       // 可选
  duration: 6,              // 可选
);
```

---

## 📊 任务状态查询

### 1. 单次查询

```dart
final status = await aigcApiClient.getTaskStatus(taskId);

print('状态: ${status.status}');
print('消息: ${status.message}');

if (status.isSuccess) {
  print('视频地址: ${status.videoUrl}');
  print('本地路径: ${status.localVideoPath}');
}
```

### 2. 轮询查询（推荐）

```dart
// 自动轮询直到任务完成
final finalResult = await aigcApiClient.pollTaskStatus(
  taskId: result.taskId,
  interval: Duration(seconds: 2),    // 轮询间隔
  maxAttempts: 150,                  // 最大尝试次数（5 分钟）
  onProgress: (progress) {
    // 进度回调
    print('当前状态: ${progress.status}');
    print('消息: ${progress.message}');
  },
);

if (finalResult.isSuccess) {
  print('✅ 任务成功！');
  print('视频地址: ${finalResult.videoUrl}');
  print('本地路径: ${finalResult.localVideoPath}');
} else if (finalResult.isFailed) {
  print('❌ 任务失败: ${finalResult.error}');
}
```

---

## 🎬 完整工作流示例

### 示例 1: 基础流程

```dart
import 'package:xinghe_new/core/aigc_engine/automation_api_client.dart';

Future<void> generateVideo() async {
  try {
    // 1. 提交任务
    print('📤 提交任务...');
    final result = await aigcApiClient.viduText2Video(
      prompt: '一个赛博朋克风格的女孩',
    );
    
    print('✅ 任务已提交');
    print('任务 ID: ${result.taskId}');
    
    // 2. 轮询查询状态
    print('⏳ 等待任务完成...');
    final finalResult = await aigcApiClient.pollTaskStatus(
      taskId: result.taskId,
      onProgress: (progress) {
        print('状态: ${progress.status} - ${progress.message}');
      },
    );
    
    // 3. 处理结果
    if (finalResult.isSuccess) {
      print('🎉 视频生成成功！');
      
      // 优先使用云端地址
      if (finalResult.videoUrl != null) {
        print('云端地址: ${finalResult.videoUrl}');
        // 在应用内播放视频
        // Navigator.push(...);
      }
      
      // 备选本地路径
      if (finalResult.localVideoPath != null) {
        print('本地路径: ${finalResult.localVideoPath}');
      }
    } else {
      print('❌ 任务失败: ${finalResult.error}');
    }
    
  } catch (e) {
    print('❌ 错误: $e');
  }
}
```

---

### 示例 2: 在 UI 中使用

```dart
import 'package:flutter/material.dart';
import 'package:xinghe_new/core/aigc_engine/automation_api_client.dart';

class VideoGenerationPage extends StatefulWidget {
  @override
  _VideoGenerationPageState createState() => _VideoGenerationPageState();
}

class _VideoGenerationPageState extends State<VideoGenerationPage> {
  final _promptController = TextEditingController();
  String _status = '等待提交';
  String? _taskId;
  String? _videoUrl;
  bool _isLoading = false;

  Future<void> _generateVideo() async {
    if (_promptController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请输入提示词')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _status = '提交任务中...';
    });

    try {
      // 1. 提交任务
      final result = await aigcApiClient.viduText2Video(
        prompt: _promptController.text,
      );

      setState(() {
        _taskId = result.taskId;
        _status = '任务已提交，等待执行...';
      });

      // 2. 轮询查询状态
      final finalResult = await aigcApiClient.pollTaskStatus(
        taskId: result.taskId,
        onProgress: (progress) {
          setState(() {
            _status = '${progress.status}: ${progress.message}';
          });
        },
      );

      // 3. 处理结果
      if (finalResult.isSuccess) {
        setState(() {
          _status = '✅ 视频生成成功！';
          _videoUrl = finalResult.videoUrl ?? finalResult.localVideoPath;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('视频生成成功！')),
        );
      } else {
        setState(() {
          _status = '❌ 任务失败: ${finalResult.error}';
        });
      }
    } catch (e) {
      setState(() {
        _status = '❌ 错误: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('视频生成')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _promptController,
              decoration: InputDecoration(
                labelText: '提示词',
                hintText: '输入视频描述...',
              ),
              maxLines: 3,
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _generateVideo,
              child: Text(_isLoading ? '生成中...' : '生成视频'),
            ),
            SizedBox(height: 16),
            Text('状态: $_status'),
            if (_taskId != null) Text('任务 ID: $_taskId'),
            if (_videoUrl != null) ...[
              SizedBox(height: 16),
              Text('视频地址: $_videoUrl'),
              ElevatedButton(
                onPressed: () {
                  // 播放视频
                  // Navigator.push(...);
                },
                child: Text('播放视频'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }
}
```

---

## 🖥️ 浏览器窗口控制

### 显示浏览器

```dart
final result = await aigcApiClient.showBrowser();

if (result.success) {
  print('✅ 浏览器已显示');
} else {
  print('❌ ${result.message}');
}
```

### 隐藏浏览器

```dart
final result = await aigcApiClient.hideBrowser();

if (result.success) {
  print('✅ 浏览器已隐藏');
} else {
  print('❌ ${result.message}');
}
```

---

## 🔍 任务管理

### 获取所有任务

```dart
final tasks = await aigcApiClient.getAllTasks();

for (final task in tasks) {
  print('任务 ${task.taskId}: ${task.status}');
}
```

### 取消任务

```dart
await aigcApiClient.cancelTask(taskId);
print('任务已取消');
```

---

## 🏥 健康检查

### 检查服务是否可用

```dart
final isHealthy = await aigcApiClient.checkHealth();

if (isHealthy) {
  print('✅ API 服务正常');
} else {
  print('❌ API 服务不可用，请启动 Python 服务器');
}
```

### 获取服务器信息

```dart
final info = await aigcApiClient.getServerInfo();

print('服务: ${info['service']}');
print('版本: ${info['version']}');
print('状态: ${info['status']}');
```

---

## 📦 数据模型

### AigcTaskResult

```dart
class AigcTaskResult {
  final String taskId;           // 任务 ID
  final String status;           // 状态：pending, running, success, failed
  final String message;          // 消息描述
  final String createdAt;        // 创建时间
  final String? updatedAt;       // 更新时间
  final String? prompt;          // 提示词
  final String? platform;        // 平台名称
  final String? toolType;        // 工具类型
  final String? videoUrl;        // 云端视频地址 ⭐
  final String? localVideoPath;  // 本地视频路径 ⭐
  final String? imageUrl;        // 云端图片地址
  final String? localImagePath;  // 本地图片路径
  final String? error;           // 错误信息
  final Map<String, dynamic>? result;  // 详细结果
  
  // 便捷属性
  bool get isSuccess;      // 是否成功
  bool get isFailed;       // 是否失败
  bool get isRunning;      // 是否运行中
  bool get isPending;      // 是否等待中
  bool get isCompleted;    // 是否已完成
  String? get mediaUrl;    // 获取媒体地址（优先云端）
  String? get localMediaPath;  // 获取本地媒体路径
}
```

---

## 🎯 扩展性设计

### 新增平台（无需修改核心代码）

```dart
// 方式 1: 使用统一入口
final result = await aigcApiClient.submitGenerationTask(
  platform: 'new_platform',  // 新平台名称
  toolType: 'text2video',
  payload: {
    'prompt': '提示词',
    // 平台特定参数
  },
);

// 方式 2: 添加便捷方法（可选）
extension NewPlatformExtension on AutomationApiClient {
  Future<AigcTaskResult> newPlatformText2Video({
    required String prompt,
    String? model,
  }) async {
    return submitGenerationTask(
      platform: 'new_platform',
      toolType: 'text2video',
      payload: {
        'prompt': prompt,
        if (model != null) 'model': model,
      },
    );
  }
}
```

---

## ⚠️ 错误处理

### 常见错误

```dart
try {
  final result = await aigcApiClient.viduText2Video(
    prompt: '提示词',
  );
} on TimeoutException {
  print('❌ 请求超时，请检查网络连接');
} on ArgumentError catch (e) {
  print('❌ 参数错误: $e');
} catch (e) {
  if (e.toString().contains('请检查 Python API 服务是否启动')) {
    print('❌ API 服务未启动');
    print('💡 请运行: python python_backend/web_automation/api_server.py');
  } else {
    print('❌ 未知错误: $e');
  }
}
```

---

## 🔧 配置

### 修改 API 地址

如果 Python 服务器使用了不同的端口，修改 `automation_api_client.dart`：

```dart
class AutomationApiClient {
  // 修改这里的端口
  static const String _baseUrl = 'http://127.0.0.1:8123';
  
  // ...
}
```

### 修改超时时间

```dart
final client = AutomationApiClient(
  timeout: Duration(seconds: 60),  // 自定义超时时间
);
```

---

## 📝 最佳实践

### 1. 使用全局单例

```dart
// ✅ 推荐：使用全局单例
final result = await aigcApiClient.viduText2Video(prompt: '...');

// ❌ 不推荐：每次创建新实例
final client = AutomationApiClient();
final result = await client.viduText2Video(prompt: '...');
client.dispose();
```

### 2. 使用轮询而非单次查询

```dart
// ✅ 推荐：使用轮询
final result = await aigcApiClient.pollTaskStatus(
  taskId: taskId,
  onProgress: (progress) => print(progress.status),
);

// ❌ 不推荐：手动循环查询
while (true) {
  final status = await aigcApiClient.getTaskStatus(taskId);
  if (status.isCompleted) break;
  await Future.delayed(Duration(seconds: 2));
}
```

### 3. 优先使用云端地址

```dart
// ✅ 推荐：优先云端，备选本地
final videoUrl = result.videoUrl ?? result.localVideoPath;

// 或使用便捷属性
final videoUrl = result.mediaUrl;
```

### 4. 启动前检查服务

```dart
// 在应用启动时检查 API 服务
final isHealthy = await aigcApiClient.checkHealth();
if (!isHealthy) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('服务未启动'),
      content: Text('请先启动 Python API 服务器'),
    ),
  );
}
```

---

## 🎉 总结

`AutomationApiClient` 提供了：

- ✅ 统一的 AIGC 自动化接口
- ✅ 多平台支持（Vidu、即梦、可灵、海螺）
- ✅ 多工具类型（文生视频、图生视频、文生图）
- ✅ 完整的任务生命周期管理
- ✅ 浏览器窗口控制
- ✅ 高扩展性设计

现在你可以在 Flutter 应用中轻松调用 AIGC 自动化功能了！🚀
