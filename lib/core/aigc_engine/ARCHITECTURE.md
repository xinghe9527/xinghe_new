# 🏗️ AIGC 自动化网关架构设计

## 📋 设计原则

### 1. 完全隔离
- ✅ 不修改任何现有 UI 代码
- ✅ 不修改任何现有业务逻辑
- ✅ 独立的命名空间 `lib/core/aigc_engine/`
- ✅ 零侵入式集成

### 2. 高扩展性
- ✅ 新增平台无需修改核心代码
- ✅ 统一的接口设计
- ✅ 灵活的参数传递
- ✅ 支持平台特定功能

### 3. 统一接口
- ✅ 所有平台使用相同的调用方式
- ✅ 一致的数据模型
- ✅ 标准化的错误处理
- ✅ 统一的任务生命周期

---

## 🏛️ 架构层次

```
┌─────────────────────────────────────────────────────────┐
│                   Flutter 应用层                         │
│  • UI 组件                                               │
│  • 业务逻辑                                              │
│  • 状态管理                                              │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│            AIGC 自动化网关（本层）                        │
│  • AutomationApiClient（统一客户端）                     │
│  • AigcTaskResult（数据模型）                            │
│  • BrowserControlResult（窗口控制）                      │
└────────────────┬────────────────────────────────────────┘
                 │ HTTP/JSON
                 ▼
┌─────────────────────────────────────────────────────────┐
│              Python FastAPI 服务器                       │
│  • 任务管理                                              │
│  • 后台调度                                              │
│  • 窗口控制                                              │
└────────────────┬────────────────────────────────────────┘
                 │ Playwright
                 ▼
┌─────────────────────────────────────────────────────────┐
│           浏览器自动化层（Playwright）                    │
│  • Vidu 自动化                                           │
│  • 即梦自动化                                            │
│  • 可灵自动化                                            │
│  • 海螺自动化                                            │
└─────────────────────────────────────────────────────────┘
```

---

## 📦 文件结构

```
lib/core/aigc_engine/
├── automation_api_client.dart  # 核心客户端（本文件）
├── USAGE_GUIDE.md              # 使用指南
├── ARCHITECTURE.md             # 架构设计（本文件）
└── README.md                   # 快速开始
```

---

## 🎯 核心组件

### 1. AutomationApiClient（统一客户端）

**职责**:
- 与 Python FastAPI 服务通信
- 封装 HTTP 请求
- 处理 JSON 序列化/反序列化
- 提供统一的接口

**核心方法**:
```dart
class AutomationApiClient {
  // 统一入口
  Future<AigcTaskResult> submitGenerationTask({
    required String platform,
    required String toolType,
    required Map<String, dynamic> payload,
  });
  
  // 任务查询
  Future<AigcTaskResult> getTaskStatus(String taskId);
  Future<AigcTaskResult> pollTaskStatus({...});
  
  // 任务控制
  Future<void> cancelTask(String taskId);
  
  // 浏览器控制
  Future<BrowserControlResult> showBrowser();
  Future<BrowserControlResult> hideBrowser();
  
  // 健康检查
  Future<bool> checkHealth();
}
```

---

### 2. AigcTaskResult（任务结果模型）

**职责**:
- 封装任务结果数据
- 提供便捷的状态判断
- 统一的数据访问接口

**核心字段**:
```dart
class AigcTaskResult {
  final String taskId;           // 任务 ID
  final String status;           // 状态
  final String? videoUrl;        // ⭐ 云端视频地址
  final String? localVideoPath;  // ⭐ 本地视频路径
  final String? imageUrl;        // 云端图片地址
  final String? localImagePath;  // 本地图片路径
  
  // 便捷属性
  bool get isSuccess;
  bool get isFailed;
  bool get isCompleted;
  String? get mediaUrl;          // 优先云端
  String? get localMediaPath;    // 本地路径
}
```

---

### 3. BrowserControlResult（窗口控制结果）

**职责**:
- 封装窗口控制结果
- 提供操作反馈

**核心字段**:
```dart
class BrowserControlResult {
  final bool success;
  final String message;
  final bool windowFound;
}
```

---

## 🔄 数据流

### 任务提交流程

```
Flutter 应用
    │
    │ 1. 调用 submitGenerationTask()
    ▼
AutomationApiClient
    │
    │ 2. 构建 JSON 请求体
    │    {
    │      "platform": "vidu",
    │      "tool_type": "text2video",
    │      "payload": {"prompt": "..."}
    │    }
    ▼
HTTP POST /api/generate
    │
    │ 3. 发送到 Python FastAPI
    ▼
Python FastAPI 服务器
    │
    │ 4. 创建任务，返回任务 ID
    │    {
    │      "task_id": "task_xxx",
    │      "status": "pending"
    │    }
    ▼
AutomationApiClient
    │
    │ 5. 解析 JSON，创建 AigcTaskResult
    ▼
Flutter 应用
    │
    │ 6. 获得任务 ID，开始轮询
    ▼
```

### 任务轮询流程

```
Flutter 应用
    │
    │ 1. 调用 pollTaskStatus()
    ▼
AutomationApiClient
    │
    │ 2. 循环查询任务状态
    │    每 2 秒查询一次
    ▼
HTTP GET /api/task/{task_id}
    │
    │ 3. 获取最新状态
    │    {
    │      "status": "running",
    │      "message": "正在生成..."
    │    }
    ▼
AutomationApiClient
    │
    │ 4. 回调 onProgress
    ▼
Flutter 应用
    │
    │ 5. 更新 UI 显示进度
    │
    │ 6. 继续轮询直到完成
    ▼
```

### 任务完成流程

```
Python FastAPI 服务器
    │
    │ 1. 任务执行完成
    │    {
    │      "status": "success",
    │      "result": {
    │        "video_url": "https://...",
    │        "local_video_path": "/path/to/video.mp4"
    │      }
    │    }
    ▼
AutomationApiClient
    │
    │ 2. 解析结果，提取媒体地址
    ▼
AigcTaskResult
    │
    │ 3. 封装为结果对象
    │    videoUrl: "https://..."
    │    localVideoPath: "/path/to/video.mp4"
    ▼
Flutter 应用
    │
    │ 4. 获取视频地址
    │    优先使用 videoUrl（云端）
    │    备选 localVideoPath（本地）
    ▼
视频播放器
    │
    │ 5. 播放视频
    ▼
```

---

## 🎨 扩展性设计

### 新增平台（3 种方式）

#### 方式 1: 使用统一入口（推荐）

```dart
// 无需修改任何代码，直接调用
final result = await aigcApiClient.submitGenerationTask(
  platform: 'new_platform',  // 新平台名称
  toolType: 'text2video',
  payload: {
    'prompt': '提示词',
    'custom_param': 'value',  // 平台特定参数
  },
);
```

**优点**:
- ✅ 零代码修改
- ✅ 完全灵活
- ✅ 支持任意参数

**缺点**:
- ❌ 需要手动构建 payload
- ❌ 没有类型检查

---

#### 方式 2: 添加便捷方法

```dart
// 在 automation_api_client.dart 中添加
extension NewPlatformExtension on AutomationApiClient {
  Future<AigcTaskResult> newPlatformText2Video({
    required String prompt,
    String? model,
    int? duration,
  }) async {
    return submitGenerationTask(
      platform: 'new_platform',
      toolType: 'text2video',
      payload: {
        'prompt': prompt,
        if (model != null) 'model': model,
        if (duration != null) 'duration': duration,
      },
    );
  }
}

// 使用
final result = await aigcApiClient.newPlatformText2Video(
  prompt: '提示词',
  model: 'model-v1',
);
```

**优点**:
- ✅ 类型安全
- ✅ 代码提示
- ✅ 参数验证

**缺点**:
- ❌ 需要修改代码
- ❌ 每个平台需要单独添加

---

#### 方式 3: 创建平台专用客户端

```dart
// 创建新文件 lib/core/aigc_engine/platforms/new_platform_client.dart
class NewPlatformClient {
  final AutomationApiClient _client;
  
  NewPlatformClient(this._client);
  
  Future<AigcTaskResult> text2Video({
    required String prompt,
    String? model,
  }) async {
    return _client.submitGenerationTask(
      platform: 'new_platform',
      toolType: 'text2video',
      payload: {
        'prompt': prompt,
        if (model != null) 'model': model,
      },
    );
  }
}

// 使用
final newPlatform = NewPlatformClient(aigcApiClient);
final result = await newPlatform.text2Video(prompt: '提示词');
```

**优点**:
- ✅ 完全隔离
- ✅ 易于维护
- ✅ 可以添加平台特定逻辑

**缺点**:
- ❌ 需要创建新文件
- ❌ 增加代码复杂度

---

## 🔒 隔离性保证

### 1. 独立命名空间

```
lib/core/aigc_engine/  # 独立目录
├── automation_api_client.dart
├── USAGE_GUIDE.md
└── ARCHITECTURE.md
```

### 2. 零依赖现有代码

```dart
// ✅ 只依赖标准库
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

// ❌ 不依赖任何现有业务代码
// import 'package:xinghe_new/features/...';  // 不会出现
```

### 3. 可选集成

```dart
// 现有代码完全不受影响
// 只有需要使用 AIGC 功能时才导入

import 'package:xinghe_new/core/aigc_engine/automation_api_client.dart';
```

---

## 📊 性能考虑

### 1. 单例模式

```dart
// 全局单例，避免重复创建
final AutomationApiClient aigcApiClient = AutomationApiClient();
```

### 2. HTTP 连接复用

```dart
// 使用同一个 HTTP 客户端
final http.Client _client;
```

### 3. 超时控制

```dart
// 所有请求都有超时保护
final Duration timeout;
```

### 4. 资源清理

```dart
// 提供 dispose 方法
void dispose() {
  _client.close();
}
```

---

## 🔐 安全考虑

### 1. 本地通信

```dart
// 只与本地服务通信
static const String _baseUrl = 'http://127.0.0.1:8123';
```

### 2. 参数验证

```dart
// 验证必需参数
if (!payload.containsKey('prompt')) {
  throw ArgumentError('payload 必须包含 prompt 字段');
}
```

### 3. 错误处理

```dart
// 完整的异常捕获
try {
  // ...
} on TimeoutException {
  throw Exception('请求超时');
} catch (e) {
  throw Exception('请求失败: $e');
}
```

---

## 🧪 测试策略

### 1. 单元测试

```dart
// 测试数据模型
test('AigcTaskResult.fromJson', () {
  final json = {...};
  final result = AigcTaskResult.fromJson(json);
  expect(result.taskId, 'task_123');
});
```

### 2. 集成测试

```dart
// 测试 API 调用
test('submitGenerationTask', () async {
  final client = AutomationApiClient();
  final result = await client.viduText2Video(prompt: 'test');
  expect(result.taskId, isNotEmpty);
});
```

### 3. Mock 测试

```dart
// 使用 Mock HTTP 客户端
final mockClient = MockClient((request) async {
  return http.Response('{"task_id": "test"}', 200);
});

final client = AutomationApiClient(client: mockClient);
```

---

## 📈 未来扩展

### 1. 支持更多平台

- ✅ Vidu（已支持）
- ✅ 即梦（已支持）
- ✅ 可灵（已支持）
- ✅ 海螺（已支持）
- 🔜 Runway
- 🔜 Pika
- 🔜 其他平台

### 2. 支持更多工具类型

- ✅ 文生视频（已支持）
- ✅ 图生视频（已支持）
- ✅ 文生图（已支持）
- 🔜 视频编辑
- 🔜 视频延长
- 🔜 视频转场

### 3. 增强功能

- 🔜 任务队列管理
- 🔜 批量任务提交
- 🔜 任务优先级
- 🔜 任务依赖关系
- 🔜 本地缓存
- 🔜 离线模式

### 4. 性能优化

- 🔜 请求合并
- 🔜 结果缓存
- 🔜 连接池
- 🔜 断点续传

---

## 🎉 总结

`AutomationApiClient` 的架构设计实现了：

- ✅ **完全隔离**：不影响现有代码
- ✅ **高扩展性**：新增平台无需修改核心逻辑
- ✅ **统一接口**：所有平台使用相同的调用方式
- ✅ **类型安全**：完整的类型定义和检查
- ✅ **易于使用**：简洁的 API 设计
- ✅ **易于维护**：清晰的代码结构

这是一个面向未来的、可持续发展的 AIGC 自动化基础设施！🚀
