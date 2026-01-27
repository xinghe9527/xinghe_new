# Midjourney API 服务使用指南

## 概述

`MidjourneyService` 提供了对 Midjourney 官方 API 的完整封装，支持：

- **Imagine 任务提交**：文生图和图生图
- **任务状态查询**：实时查询生成进度
- **自动轮询**：等待任务完成
- **Prompt 构建器**：辅助构建标准 Midjourney prompt

## 快速开始

### 1. 创建服务实例

```dart
import 'package:xinghe_new/services/api/providers/midjourney_service.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';

// 创建配置
final config = ApiConfig(
  baseUrl: 'YOUR_BASE_URL',  // 例如: https://api.example.com
  apiKey: 'YOUR_API_KEY',
);

// 创建服务实例
final mjService = MidjourneyService(config);

// 创建辅助类实例（推荐使用）
final helper = MidjourneyHelper(mjService);
```

### 2. 简单文生图

```dart
// 方式 1: 提交任务后立即返回
final result = await helper.textToImage(
  prompt: 'A cat sleeping on a cloud',
  mode: MidjourneyMode.relax,
);

if (result.isSuccess) {
  final taskId = result.data!.taskId;
  print('任务已提交，ID: $taskId');
  
  // 需要手动查询状态
  final status = await mjService.getTaskStatus(taskId: taskId);
}
```

```dart
// 方式 2: 自动等待任务完成（推荐）
final result = await helper.submitAndWait(
  prompt: 'A cat sleeping on a cloud',
  mode: MidjourneyMode.fast,  // 使用快速模式
  maxWaitMinutes: 5,  // 最多等待 5 分钟
);

if (result.isSuccess) {
  final imageUrl = result.data!;
  print('图片生成完成: $imageUrl');
  // 可以直接使用 imageUrl 显示图片
}
```

### 3. 图生图（使用垫图）

```dart
import 'dart:convert';
import 'dart:io';

// 准备参考图片
Future<String> imageToBase64(String filePath) async {
  final bytes = await File(filePath).readAsBytes();
  return base64Encode(bytes);
}

final image1 = await imageToBase64('/path/to/image1.jpg');
final image2 = await imageToBase64('/path/to/image2.jpg');

// 提交图生图任务
final result = await helper.imageToImage(
  prompt: 'Combine these images into a surreal artwork',
  referenceImages: [image1, image2],
  mode: MidjourneyMode.fast,
);

if (result.isSuccess) {
  print('任务已提交: ${result.data!.taskId}');
}
```

### 4. 使用 Prompt 构建器

```dart
// 创建复杂的 prompt
final builder = MidjourneyPromptBuilder();

final prompt = builder
  .withDescription('A futuristic city at sunset')
  .withAspectRatio(MidjourneyAspectRatio.landscape)  // 16:9
  .withVersion(MidjourneyVersion.v6)  // 使用 v6
  .withQuality(2.0)  // 高质量
  .withStylize(750)  // 风格化程度
  .withNegative('blurry, low quality')  // 负面提示词
  .build();

print(prompt);
// 输出: A futuristic city at sunset --ar 16:9 --v 6 --q 2.0 --s 750 --no blurry, low quality

// 提交任务
final result = await helper.textToImage(
  prompt: prompt,
  mode: MidjourneyMode.fast,
);
```

## API 参数说明

### 调用模式 (mode)

| 常量 | 值 | 说明 | 费用 | 速度 |
|------|-----|------|------|------|
| `MidjourneyMode.relax` | RELAX | 慢速模式 | 免费额度 | 较慢 |
| `MidjourneyMode.fast` | FAST | 快速模式 | 计费 | 快速 |

### 任务状态码 (code)

| 状态码 | 说明 |
|--------|------|
| 1 | 提交成功 |
| 22 | 排队中 |
| 23 | 队列已满 |
| 24 | prompt 包含敏感词 |
| 其他 | 错误 |

### 任务状态 (status)

| 状态 | 说明 |
|------|------|
| SUBMITTED | 已提交 |
| IN_PROGRESS | 进行中 |
| SUCCESS | 成功 |
| FAILURE | 失败 |

## Action 操作

### 1. Upscale（放大图片）

生成 4 张图后，可以选择放大其中一张：

```dart
// 第一步：提交 Imagine 任务
final imagineResult = await helper.textToImage(
  prompt: 'Beautiful landscape',
  mode: MidjourneyMode.fast,
);

final originalTaskId = imagineResult.data!.taskId;

// 等待原任务完成
await helper.pollTaskUntilComplete(taskId: originalTaskId);

// 第二步：Upscale 第 2 张图片
final upscaleResult = await helper.upscale(
  taskId: originalTaskId,
  index: 2,  // 放大第 2 张
  mode: MidjourneyMode.fast,
);

// 等待 Upscale 完成
final newTaskId = upscaleResult.data!.taskId;
await helper.pollTaskUntilComplete(taskId: newTaskId);
```

### 2. Variation（生成变体）

对某张图片生成新的变体：

```dart
// 生成第 1 张图的变体
final variationResult = await helper.variation(
  taskId: originalTaskId,
  index: 1,
  mode: MidjourneyMode.fast,
);

final newTaskId = variationResult.data!.taskId;
await helper.pollTaskUntilComplete(taskId: newTaskId);
```

### 3. Reroll（重新生成）

重新生成一组新图片：

```dart
final rerollResult = await helper.reroll(
  taskId: originalTaskId,
  mode: MidjourneyMode.fast,
);

await helper.pollTaskUntilComplete(taskId: rerollResult.data!.taskId);
```

### 4. 使用 customId 直接操作

如果已经从任务状态中获取了 customId：

```dart
// 查询任务获取 customId
final statusResult = await service.getTaskStatus(taskId: taskId);
final customId = statusResult.data!.metadata?['buttons']?[0]?['customId'];

// 使用 customId 执行操作
final result = await service.submitAction(
  taskId: taskId,
  customId: customId,
  mode: MidjourneyMode.fast,
);
```

## 高级功能

### 1. 手动轮询任务状态

```dart
// 提交任务
final submitResult = await helper.textToImage(
  prompt: 'Beautiful landscape',
  mode: MidjourneyMode.fast,
);

final taskId = submitResult.data!.taskId;

// 手动轮询
final statusResult = await helper.pollTaskUntilComplete(
  taskId: taskId,
  maxAttempts: 60,      // 最多轮询 60 次
  intervalSeconds: 5,   // 每 5 秒查询一次
);

if (statusResult.isSuccess) {
  final status = statusResult.data!;
  print('生成完成！');
  print('图片 URL: ${status.imageUrl}');
  print('进度: ${status.progress}%');
}
```

### 2. 使用回调接口

```dart
final result = await mjService.submitImagine(
  prompt: 'A dragon',
  mode: MidjourneyMode.fast,
  notifyHook: 'https://your-server.com/webhook',  // 你的回调地址
);

// 当任务完成时，Midjourney 会调用你的 webhook
// 你需要在服务器端实现接收逻辑
```

### 3. 批量提交任务

```dart
Future<List<String>> submitBatchTasks(List<String> prompts) async {
  final taskIds = <String>[];
  
  for (final prompt in prompts) {
    final result = await helper.textToImage(
      prompt: prompt,
      mode: MidjourneyMode.relax,
    );
    
    if (result.isSuccess) {
      taskIds.add(result.data!.taskId);
    }
  }
  
  return taskIds;
}
```

## Prompt 构建技巧

### 基础结构

```
[主题描述] + [风格] + [细节] + [参数]
```

### 示例

```dart
// 示例 1: 写实风格照片
final prompt = MidjourneyPromptBuilder()
  .withDescription('A professional portrait of a young woman, studio lighting')
  .withAspectRatio('3:4')
  .withVersion(MidjourneyVersion.v6)
  .withQuality(2.0)
  .withStylize(500)
  .build();

// 示例 2: 艺术风格
final prompt = MidjourneyPromptBuilder()
  .withDescription('Cyberpunk city, neon lights, rain')
  .withAspectRatio(MidjourneyAspectRatio.wide)
  .withVersion(MidjourneyVersion.niji5)
  .withChaos(50)
  .withNegative('people, cars')
  .build();

// 示例 3: 简单场景
final prompt = MidjourneyPromptBuilder()
  .withDescription('Mountain landscape at sunrise')
  .withAspectRatio('16:9')
  .withQuality(1.0)
  .build();
```

### 常用参数说明

- `--ar`: 宽高比，例如 `--ar 16:9`
- `--v`: 版本，例如 `--v 6`
- `--q`: 质量，0.25, 0.5, 1.0, 2.0
- `--s`: 风格化，0-1000
- `--c`: 混乱度，0-100
- `--no`: 负面提示词
- `--seed`: 种子值，用于复现

## 在 Flutter Widget 中使用

```dart
class MidjourneyImageGenerator extends StatefulWidget {
  @override
  State<MidjourneyImageGenerator> createState() => 
      _MidjourneyImageGeneratorState();
}

class _MidjourneyImageGeneratorState extends State<MidjourneyImageGenerator> {
  final _helper = MidjourneyHelper(
    MidjourneyService(
      ApiConfig(
        baseUrl: 'YOUR_BASE_URL',
        apiKey: 'YOUR_API_KEY',
      ),
    ),
  );
  
  String? _imageUrl;
  bool _isGenerating = false;
  String? _taskId;
  int? _progress;

  Future<void> _generateImage(String prompt) async {
    setState(() {
      _isGenerating = true;
      _progress = 0;
    });
    
    try {
      // 提交任务
      final submitResult = await _helper.textToImage(
        prompt: prompt,
        mode: MidjourneyMode.fast,
      );
      
      if (!submitResult.isSuccess) {
        _showError(submitResult.errorMessage!);
        return;
      }
      
      setState(() => _taskId = submitResult.data!.taskId);
      
      // 轮询状态
      final statusResult = await _helper.pollTaskUntilComplete(
        taskId: _taskId!,
        maxAttempts: 60,
        intervalSeconds: 5,
      );
      
      if (statusResult.isSuccess) {
        setState(() {
          _imageUrl = statusResult.data!.imageUrl;
          _progress = 100;
        });
      } else {
        _showError(statusResult.errorMessage!);
      }
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_isGenerating)
          Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text('任务 ID: $_taskId'),
              Text('进度: ${_progress ?? 0}%'),
            ],
          ),
        if (_imageUrl != null)
          Image.network(_imageUrl!),
        ElevatedButton(
          onPressed: _isGenerating 
              ? null 
              : () => _generateImage('A beautiful sunset'),
          child: Text(_isGenerating ? '生成中...' : '生成图片'),
        ),
      ],
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
```

## 错误处理

### 响应状态码

```dart
final result = await helper.textToImage(prompt: 'test');

if (!result.isSuccess) {
  // 检查具体错误
  if (result.data?.code == 22) {
    print('任务排队中，请稍后再试');
  } else if (result.data?.code == 23) {
    print('队列已满');
  } else if (result.data?.code == 24) {
    print('提示词包含敏感内容');
  } else {
    print('错误: ${result.errorMessage}');
  }
}
```

### 超时处理

```dart
// 方式 1: 设置较短的等待时间
final result = await helper.submitAndWait(
  prompt: 'Quick test',
  maxWaitMinutes: 2,  // 只等待 2 分钟
);

// 方式 2: 使用 try-catch 捕获超时
try {
  final result = await helper.submitAndWait(
    prompt: 'Test',
  ).timeout(Duration(minutes: 3));
} on TimeoutException {
  print('请求超时');
}
```

## 最佳实践

### 1. 使用快速模式提升体验

```dart
// 对于需要快速响应的场景，使用 FAST 模式
final result = await helper.submitAndWait(
  prompt: 'Beautiful landscape',
  mode: MidjourneyMode.fast,  // 快速模式
);
```

### 2. 实时显示进度

```dart
Future<void> generateWithProgress(String prompt) async {
  final submitResult = await helper.textToImage(prompt: prompt);
  final taskId = submitResult.data!.taskId;
  
  // 定时查询进度
  Timer.periodic(Duration(seconds: 3), (timer) async {
    final status = await mjService.getTaskStatus(taskId: taskId);
    
    if (status.isSuccess) {
      final taskStatus = status.data!;
      
      setState(() {
        _progress = taskStatus.progress ?? 0;
      });
      
      if (taskStatus.isFinished) {
        timer.cancel();
        if (taskStatus.isSuccess) {
          setState(() => _imageUrl = taskStatus.imageUrl);
        }
      }
    }
  });
}
```

### 3. 缓存任务结果

```dart
final _taskCache = <String, String>{};  // taskId -> imageUrl

Future<String?> getOrGenerateImage(String prompt) async {
  // 检查缓存
  final cachedUrl = _taskCache.values.firstWhere(
    (url) => url.isNotEmpty,
    orElse: () => '',
  );
  
  if (cachedUrl.isNotEmpty) {
    return cachedUrl;
  }
  
  // 生成新图片
  final result = await helper.submitAndWait(prompt: prompt);
  
  if (result.isSuccess) {
    final url = result.data!;
    _taskCache[prompt] = url;
    return url;
  }
  
  return null;
}
```

### 4. 优化 Prompt

```dart
// 使用 Prompt 构建器创建高质量 prompt
final builder = MidjourneyPromptBuilder();

// 场景 1: 专业照片
final photoPrompt = builder
  .withDescription('Professional product photography, luxury watch')
  .withAspectRatio('1:1')
  .withVersion('6')
  .withQuality(2.0)
  .withStylize(100)
  .withNegative('sketch, drawing, cartoon')
  .build();

// 场景 2: 动漫风格
builder.reset();  // 重置构建器
final animePrompt = builder
  .withDescription('Anime girl, studio ghibli style')
  .withAspectRatio('9:16')
  .withVersion(MidjourneyVersion.niji5)
  .withStylize(850)
  .build();

// 场景 3: 建筑设计
builder.reset();
final archPrompt = builder
  .withDescription('Modern architecture, minimalist design')
  .withAspectRatio(MidjourneyAspectRatio.wide)
  .withQuality(2.0)
  .withSeed(12345)  // 固定种子值
  .build();
```

## 完整示例

### 示例 1: 基础文生图

```dart
final config = ApiConfig(
  baseUrl: 'https://api.midjourney.com',
  apiKey: 'your-api-key',
);

final helper = MidjourneyHelper(MidjourneyService(config));

// 提交并等待
final result = await helper.submitAndWait(
  prompt: 'A serene Japanese garden',
  mode: MidjourneyMode.relax,
  maxWaitMinutes: 5,
);

if (result.isSuccess) {
  print('图片 URL: ${result.data}');
}
```

### 示例 2: 带垫图的图生图

```dart
// 读取参考图片
final refImage = base64Encode(
  await File('reference.jpg').readAsBytes(),
);

// 提交任务
final submitResult = await helper.imageToImage(
  prompt: 'Transform this into cyberpunk style',
  referenceImages: [refImage],
  mode: MidjourneyMode.fast,
);

final taskId = submitResult.data!.taskId;

// 轮询状态
while (true) {
  await Future.delayed(Duration(seconds: 5));
  
  final status = await mjService.getTaskStatus(taskId: taskId);
  
  if (status.data!.isFinished) {
    if (status.data!.isSuccess) {
      print('完成！URL: ${status.data!.imageUrl}');
    } else {
      print('失败: ${status.data!.failReason}');
    }
    break;
  }
  
  print('进度: ${status.data!.progress}%');
}
```

### 示例 3: 批量生成

```dart
final prompts = [
  'A red apple',
  'A blue ocean',
  'A green forest',
];

// 提交所有任务
final taskIds = <String>[];
for (final prompt in prompts) {
  final result = await helper.textToImage(
    prompt: prompt,
    mode: MidjourneyMode.relax,
  );
  if (result.isSuccess) {
    taskIds.add(result.data!.taskId);
  }
}

// 等待所有任务完成
final results = <String>[];
for (final taskId in taskIds) {
  final status = await helper.pollTaskUntilComplete(taskId: taskId);
  if (status.isSuccess && status.data!.imageUrl != null) {
    results.add(status.data!.imageUrl!);
  }
}

print('生成了 ${results.length} 张图片');
```

## 注意事项

1. **异步特性**：Midjourney 是异步任务系统，需要轮询或使用回调
2. **生成时间**：
   - RELAX 模式：通常 1-3 分钟
   - FAST 模式：通常 30-60 秒
3. **队列限制**：高峰期可能遇到排队（code: 22）
4. **敏感词过滤**：注意 prompt 中的内容（code: 24）
5. **Base64 格式**：垫图需要包含 `data:image/png;base64,` 前缀

## Prompt 编写技巧

### 基础格式

```
[主体] + [描述] + [风格] + [参数]
```

### 优秀示例

```dart
// 写实风格
'Professional photography of a luxury car, studio lighting, 
 high detail, 8k resolution --ar 16:9 --v 6 --q 2.0'

// 艺术风格
'Oil painting of a sunset over mountains, impressionist style, 
 vibrant colors --ar 4:3 --s 750'

// 动漫风格
'Anime character, beautiful girl, sakura background, 
 studio ghibli style --ar 9:16 --niji 5 --s 850'

// 建筑设计
'Modern minimalist house, white concrete, glass windows, 
 architectural visualization --ar 21:9 --v 6 --q 2.0'
```

### 参数组合建议

| 用途 | 推荐参数 |
|------|----------|
| 写实照片 | `--v 6 --q 2.0 --s 100` |
| 艺术创作 | `--v 5 --s 750 --c 30` |
| 动漫风格 | `--niji 5 --s 850` |
| 产品设计 | `--v 6 --q 2.0 --s 50` |

## 故障排查

### 问题 1: 任务一直在队列中

**原因**: 使用 RELAX 模式在高峰期
**解决**: 切换到 FAST 模式或错峰使用

```dart
// 改用快速模式
mode: MidjourneyMode.fast
```

### 问题 2: 提示词被拒绝

**原因**: 包含敏感内容（code: 24）
**解决**: 修改 prompt，移除敏感词

### 问题 3: 轮询超时

**原因**: 任务生成时间过长
**解决**: 增加轮询次数或等待时间

```dart
maxAttempts: 120,        // 增加到 120 次
intervalSeconds: 10,     // 延长间隔
```

## API 限制

1. **并发限制**：
   - RELAX 模式：通常有并发限制
   - FAST 模式：更高的并发配额

2. **速率限制**：
   - 建议每次请求间隔至少 1 秒
   - 避免短时间内大量提交

3. **内容限制**：
   - 遵守服务条款
   - 不要生成违规内容

## 与其他服务对比

| 特性 | Midjourney | Gemini Image |
|------|------------|--------------|
| 生成方式 | 异步任务 | 同步请求 |
| 速度 | 较慢 (1-3分钟) | 较快 (秒级) |
| 质量 | 极高 | 高 |
| 风格控制 | 强大 | 一般 |
| 价格 | 按订阅 | 按 Token |
| 垫图支持 | ✅ | ✅ |

## 技术支持

如有问题，请参考：

- API 文档: Midjourney 官方文档
- 示例代码: `lib/examples/midjourney_example.dart`
- 基类定义: `lib/services/api/base/api_service_base.dart`
