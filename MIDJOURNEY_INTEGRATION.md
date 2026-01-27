# Midjourney API 集成指南

## 📋 概述

本项目已成功集成 Midjourney 官方 API，支持 Imagine 任务提交、状态查询和图像生成。

## ✅ 已完成的工作

### 1. 核心服务实现

创建了 `MidjourneyService` 类 (`lib/services/api/providers/midjourney_service.dart`)：

- ✅ Imagine 任务提交
- ✅ Action 任务提交（Upscale/Variation/Reroll）
- ✅ 任务状态查询
- ✅ 自动轮询功能
- ✅ 文生图支持
- ✅ 图生图支持（垫图）
- ✅ 两种生成模式（RELAX/FAST）
- ✅ 两种 Bot 类型（MJ/Niji）
- ✅ 完善的错误处理

### 2. 辅助工具类

#### MidjourneyHelper
- 简化的任务提交方法
- 自动轮询等待完成
- 便捷的文生图/图生图接口

#### MidjourneyPromptBuilder
- 结构化构建 Prompt
- 支持所有 Midjourney 参数
- 参数验证和格式化

### 3. 数据模型

- `MidjourneyTaskResponse`: 任务提交响应
- `MidjourneyTaskStatus`: 任务状态信息

### 4. 常量定义

- `MidjourneyMode`: 生成模式（RELAX/FAST）
- `MidjourneyAspectRatio`: 常用宽高比
- `MidjourneyVersion`: Midjourney 版本

### 5. 文档和示例

- ✅ 详细使用指南 (`MIDJOURNEY_USAGE.md`)
- ✅ 完整示例代码 (`examples/midjourney_example.dart`)
- ✅ API Factory 更新

## 🚀 快速开始

### 基础配置

```dart
import 'package:xinghe_new/services/api/providers/midjourney_service.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';

final config = ApiConfig(
  baseUrl: 'YOUR_BASE_URL',  // 替换为实际 URL
  apiKey: 'YOUR_API_KEY',    // 替换为实际 Key
);

final mjService = MidjourneyService(config);
final helper = MidjourneyHelper(mjService);
```

### 三种使用方式

#### 方式 1: 提交任务（立即返回）

```dart
final result = await helper.textToImage(
  prompt: 'A cat',
  mode: MidjourneyMode.relax,
);

// 获取任务 ID
final taskId = result.data!.taskId;

// 后续需要手动查询状态
```

#### 方式 2: 提交并等待（推荐）

```dart
final result = await helper.submitAndWait(
  prompt: 'A beautiful landscape',
  mode: MidjourneyMode.fast,
  maxWaitMinutes: 5,
);

// 直接获取图片 URL
final imageUrl = result.data!;
```

#### 方式 3: 手动轮询

```dart
// 1. 提交任务
final submitResult = await helper.textToImage(prompt: 'Test');
final taskId = submitResult.data!.taskId;

// 2. 轮询状态
final statusResult = await helper.pollTaskUntilComplete(
  taskId: taskId,
  maxAttempts: 60,
  intervalSeconds: 5,
);

// 3. 获取结果
final imageUrl = statusResult.data!.imageUrl;
```

### Action 操作（进阶）

#### Upscale（放大图片）

```dart
// 生成 4 张预览图后，放大第 2 张
final upscaleResult = await helper.upscale(
  taskId: originalTaskId,
  index: 2,  // 1-4
  mode: MidjourneyMode.fast,
);

// 等待 Upscale 完成
final status = await helper.pollTaskUntilComplete(
  taskId: upscaleResult.data!.taskId,
);
```

#### Variation（生成变体）

```dart
// 基于第 1 张图生成新变体
final variationResult = await helper.variation(
  taskId: originalTaskId,
  index: 1,
  mode: MidjourneyMode.fast,
);
```

#### Reroll（重新生成）

```dart
// 重新生成新的 4 张图
final rerollResult = await helper.reroll(
  taskId: originalTaskId,
  mode: MidjourneyMode.fast,
);
```

## 📁 文件结构

```
lib/
├── services/
│   └── api/
│       ├── base/
│       │   ├── api_config.dart
│       │   ├── api_response.dart
│       │   └── api_service_base.dart
│       ├── providers/
│       │   ├── midjourney_service.dart        # ✨ Midjourney 服务
│       │   ├── MIDJOURNEY_USAGE.md           # ✨ 使用文档
│       │   ├── gemini_image_service.dart
│       │   ├── openai_service.dart
│       │   └── custom_service.dart
│       └── api_factory.dart                  # ✨ 已更新
└── examples/
    ├── midjourney_example.dart               # ✨ 完整示例
    └── gemini_image_example.dart
```

## 💡 核心特性

### 1. 异步任务系统

Midjourney 采用异步任务机制：

```
提交任务 → 获取任务ID → 轮询状态 → 获取结果
```

### 2. 两种生成模式

| 模式 | 速度 | 费用 | 适用场景 |
|------|------|------|----------|
| RELAX | 慢 (1-3分钟) | 免费额度 | 非紧急需求 |
| FAST | 快 (30-60秒) | 计费 | 需要快速响应 |

### 3. Prompt 构建器

简化复杂 Prompt 的构建：

```dart
final builder = MidjourneyPromptBuilder();

final prompt = builder
  .withDescription('主题描述')
  .withAspectRatio('16:9')
  .withVersion('6')
  .withQuality(2.0)
  .withStylize(750)
  .withNegative('不需要的元素')
  .build();
```

### 4. 状态码说明

| Code | 含义 | 处理方式 |
|------|------|----------|
| 1 | 提交成功 | 继续轮询状态 |
| 22 | 排队中 | 稍后重试 |
| 23 | 队列已满 | 错峰使用或升级 |
| 24 | 敏感词 | 修改 prompt |

## 🎨 使用场景

### 场景 1: 专业照片生成

```dart
final builder = MidjourneyPromptBuilder();

final prompt = builder
  .withDescription('Professional product photography, luxury perfume bottle')
  .withAspectRatio('1:1')
  .withVersion(MidjourneyVersion.v6)
  .withQuality(2.0)
  .withStylize(100)
  .withNegative('cartoon, sketch, low quality')
  .build();

final result = await helper.submitAndWait(
  prompt: prompt,
  mode: MidjourneyMode.fast,
);
```

### 场景 2: 艺术创作

```dart
final prompt = MidjourneyPromptBuilder()
  .withDescription('Surreal landscape, Salvador Dali style')
  .withAspectRatio(MidjourneyAspectRatio.landscape)
  .withVersion(MidjourneyVersion.v5)
  .withChaos(70)
  .withStylize(850)
  .build();

final result = await helper.submitAndWait(
  prompt: prompt,
  mode: MidjourneyMode.relax,
);
```

### 场景 3: 动漫风格

```dart
final prompt = MidjourneyPromptBuilder()
  .withDescription('Anime girl, cherry blossom background')
  .withAspectRatio('9:16')
  .withVersion(MidjourneyVersion.niji5)
  .withStylize(850)
  .build();

final result = await helper.submitAndWait(
  prompt: prompt,
  mode: MidjourneyMode.fast,
);
```

### 场景 4: 图像融合

```dart
// 准备参考图片
final ref1 = base64Encode(await File('image1.jpg').readAsBytes());
final ref2 = base64Encode(await File('image2.jpg').readAsBytes());

// 提交融合任务
final result = await helper.imageToImage(
  prompt: 'Blend into artistic masterpiece',
  referenceImages: [ref1, ref2],
  mode: MidjourneyMode.fast,
);
```

## 🔧 集成到项目

### 在 Drawing Space 中使用

编辑 `lib/features/home/presentation/drawing_space.dart`:

```dart
import 'package:xinghe_new/services/api/providers/midjourney_service.dart';

class DrawingSpace extends StatefulWidget {
  // ... 现有代码 ...
  
  late final MidjourneyHelper _mjHelper;
  
  @override
  void initState() {
    super.initState();
    
    // 初始化 Midjourney 服务
    final config = ApiConfig(
      baseUrl: 'YOUR_BASE_URL',
      apiKey: 'YOUR_API_KEY',
    );
    _mjHelper = MidjourneyHelper(MidjourneyService(config));
  }
  
  // 添加生成方法
  Future<void> _generateWithMidjourney(String prompt) async {
    setState(() => _isGenerating = true);
    
    try {
      final result = await _mjHelper.submitAndWait(
        prompt: prompt,
        mode: MidjourneyMode.fast,
        maxWaitMinutes: 5,
      );
      
      if (result.isSuccess) {
        setState(() {
          _generatedImage = result.data!;
        });
      } else {
        _showError(result.errorMessage!);
      }
    } finally {
      setState(() => _isGenerating = false);
    }
  }
}
```

## 📊 与 Gemini 服务对比

| 特性 | Midjourney | Gemini Image |
|------|------------|--------------|
| **生成方式** | 异步任务 | 同步请求 |
| **响应时间** | 1-3 分钟 | 数秒 |
| **图像质量** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| **风格控制** | 极强 | 一般 |
| **垫图支持** | ✅ | ✅ |
| **计费方式** | 订阅制 | Token 计费 |
| **适用场景** | 艺术创作、高质量图片 | 快速原型、批量生成 |

## 🎯 最佳实践

### 1. 选择合适的模式

```dart
// 开发测试阶段：使用 RELAX 模式
mode: MidjourneyMode.relax

// 生产环境/用户使用：使用 FAST 模式
mode: MidjourneyMode.fast
```

### 2. 优化等待体验

```dart
// 显示实时进度
Timer.periodic(Duration(seconds: 3), (timer) async {
  final status = await mjService.getTaskStatus(taskId: taskId);
  
  setState(() {
    _progress = status.data?.progress ?? 0;
  });
  
  if (status.data?.isFinished == true) {
    timer.cancel();
  }
});
```

### 3. 错误重试机制

```dart
Future<ApiResponse<String>> generateWithRetry({
  required String prompt,
  int maxRetries = 3,
}) async {
  for (int i = 0; i < maxRetries; i++) {
    final result = await helper.submitAndWait(
      prompt: prompt,
      mode: MidjourneyMode.fast,
    );
    
    if (result.isSuccess) {
      return result;
    }
    
    // 如果是队列满，等待后重试
    if (result.errorMessage?.contains('队列') == true) {
      await Future.delayed(Duration(seconds: 30));
      continue;
    }
    
    // 其他错误直接返回
    return result;
  }
  
  return ApiResponse.failure('重试 $maxRetries 次后仍失败');
}
```

### 4. Prompt 优化技巧

```dart
// ❌ 不好的 prompt
'cat'

// ✅ 好的 prompt  
final prompt = MidjourneyPromptBuilder()
  .withDescription('Professional photography of a persian cat, 
                   soft lighting, detailed fur texture')
  .withAspectRatio('4:3')
  .withVersion('6')
  .withQuality(2.0)
  .withStylize(500)
  .build();
```

## 🐛 常见问题

### Q1: 任务一直在排队（code: 22）

**原因**: RELAX 模式在高峰期会排队  
**解决**: 
- 切换到 FAST 模式
- 错峰使用
- 增加等待时间

```dart
mode: MidjourneyMode.fast  // 使用快速模式
```

### Q2: Prompt 被拒绝（code: 24）

**原因**: 包含敏感词汇  
**解决**: 
- 检查并修改 prompt
- 移除可能违规的内容

### Q3: 轮询超时

**原因**: 生成时间超过预期  
**解决**: 增加轮询参数

```dart
await helper.pollTaskUntilComplete(
  taskId: taskId,
  maxAttempts: 120,      // 增加次数
  intervalSeconds: 10,   // 延长间隔
);
```

### Q4: 图片 URL 为空

**原因**: 任务状态异常或 API 响应格式变化  
**解决**: 
- 检查任务状态
- 验证 API 响应格式
- 查看错误日志

## 🔐 安全建议

### 1. API Key 管理

```dart
// ❌ 不要硬编码
final config = ApiConfig(
  apiKey: 'sk-xxxxx',  // 不要这样做
);

// ✅ 使用安全存储
import 'package:xinghe_new/services/api/secure_storage_manager.dart';

final apiKey = await SecureStorageManager().getApiKey('midjourney');
final config = ApiConfig(
  baseUrl: baseUrl,
  apiKey: apiKey!,
);
```

### 2. 请求限流

```dart
class MidjourneyRateLimiter {
  DateTime? _lastRequest;
  final Duration _minInterval = Duration(seconds: 2);

  Future<void> waitIfNeeded() async {
    if (_lastRequest != null) {
      final elapsed = DateTime.now().difference(_lastRequest!);
      if (elapsed < _minInterval) {
        await Future.delayed(_minInterval - elapsed);
      }
    }
    _lastRequest = DateTime.now();
  }
}

// 使用
final limiter = MidjourneyRateLimiter();
await limiter.waitIfNeeded();
final result = await helper.textToImage(prompt: prompt);
```

### 3. 内容过滤

```dart
bool isPromptSafe(String prompt) {
  final sensitiveWords = ['敏感词1', '敏感词2'];
  
  return !sensitiveWords.any((word) => 
    prompt.toLowerCase().contains(word.toLowerCase())
  );
}

// 使用前验证
if (!isPromptSafe(prompt)) {
  showError('Prompt 包含不适当的内容');
  return;
}
```

## 📦 需要的依赖

确保 `pubspec.yaml` 包含：

```yaml
dependencies:
  http: ^1.1.0           # HTTP 请求（必需）
  image_picker: ^1.0.0   # 图片选择（可选）
  path_provider: ^2.0.0  # 文件操作（可选）
```

## 🎯 Prompt 编写指南

### 基础结构

```
[主体] + [细节] + [风格] + [质量] + [参数]
```

### 示例模板

#### 写实照片
```
Professional photography of [subject], [lighting], 
[camera angle], high detail, 8k --ar 16:9 --v 6 --q 2.0
```

#### 艺术风格
```
[Art style] painting of [subject], [color palette], 
[mood] --ar 4:3 --s 750 --v 5
```

#### 动漫风格
```
Anime [character description], [background], 
[style reference] --ar 9:16 --niji 5 --s 850
```

### 参数速查

| 参数 | 格式 | 说明 | 示例 |
|------|------|------|------|
| `--ar` | `--ar W:H` | 宽高比 | `--ar 16:9` |
| `--v` | `--v N` | 版本 | `--v 6` |
| `--q` | `--q N` | 质量 | `--q 2.0` |
| `--s` | `--s N` | 风格化 | `--s 750` |
| `--c` | `--c N` | 混乱度 | `--c 50` |
| `--no` | `--no items` | 排除元素 | `--no people` |
| `--seed` | `--seed N` | 种子值 | `--seed 123` |

## 📈 性能优化

### 1. 并发控制

```dart
final semaphore = Semaphore(3);  // 最多 3 个并发任务

Future<void> generateConcurrently(List<String> prompts) async {
  final futures = prompts.map((prompt) async {
    await semaphore.acquire();
    try {
      return await helper.submitAndWait(prompt: prompt);
    } finally {
      semaphore.release();
    }
  });
  
  await Future.wait(futures);
}
```

### 2. 结果缓存

```dart
final _cache = <String, String>{};  // prompt -> imageUrl

Future<String?> getCachedOrGenerate(String prompt) async {
  if (_cache.containsKey(prompt)) {
    return _cache[prompt];
  }
  
  final result = await helper.submitAndWait(prompt: prompt);
  
  if (result.isSuccess) {
    _cache[prompt] = result.data!;
    return result.data!;
  }
  
  return null;
}
```

## 🔄 与现有服务集成

### API Repository 使用

```dart
import 'package:xinghe_new/services/api/api_repository.dart';

// 通过 Repository 使用
final repository = ApiRepository();

// 添加 Midjourney 配置
await repository.addApiConfig(
  name: 'Midjourney',
  config: ApiConfig(
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
  ),
);

// 使用服务
final service = repository.getService('Midjourney') as MidjourneyService;
final helper = MidjourneyHelper(service);

final result = await helper.submitAndWait(prompt: 'Test');
```

## 📝 完整工作流程示例

```dart
// 1. 初始化
final helper = MidjourneyHelper(
  MidjourneyService(
    ApiConfig(
      baseUrl: 'https://api.midjourney.com',
      apiKey: 'your-key',
    ),
  ),
);

// 2. 构建 Prompt
final builder = MidjourneyPromptBuilder();
final prompt = builder
  .withDescription('Beautiful mountain landscape at sunrise')
  .withAspectRatio('16:9')
  .withVersion('6')
  .withQuality(2.0)
  .withStylize(500)
  .build();

// 3. 提交任务
print('正在提交任务...');
final submitResult = await helper.textToImage(
  prompt: prompt,
  mode: MidjourneyMode.fast,
);

if (!submitResult.isSuccess) {
  print('提交失败: ${submitResult.errorMessage}');
  return;
}

final taskId = submitResult.data!.taskId;
print('任务已提交，ID: $taskId');

// 4. 轮询状态
print('等待生成...');
var attempts = 0;
while (attempts < 60) {
  await Future.delayed(Duration(seconds: 5));
  
  final statusResult = await service.getTaskStatus(taskId: taskId);
  
  if (statusResult.isSuccess) {
    final status = statusResult.data!;
    print('进度: ${status.progress}%');
    
    if (status.isFinished) {
      if (status.isSuccess) {
        print('生成成功！');
        print('图片 URL: ${status.imageUrl}');
        break;
      } else {
        print('生成失败: ${status.failReason}');
        break;
      }
    }
  }
  
  attempts++;
}

if (attempts >= 60) {
  print('任务超时');
}
```

## 🎓 学习资源

### 官方资源
- Midjourney 官方文档
- Discord 社区

### 项目文档
- 使用指南: `lib/services/api/providers/MIDJOURNEY_USAGE.md`
- 示例代码: `lib/examples/midjourney_example.dart`
- API 基类: `lib/services/api/base/api_service_base.dart`

## 🚀 下一步

1. ✅ 替换配置中的 `YOUR_BASE_URL` 和 `YOUR_API_KEY`
2. ✅ 运行示例代码测试功能
3. ✅ 根据需求调整参数
4. ✅ 集成到实际业务中
5. ⬜ 实现图片选择和保存功能
6. ⬜ 添加更多 Midjourney 操作（Upscale, Variation 等）

---

**Midjourney 集成完成！🎨**
