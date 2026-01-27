# Midjourney API 快速参考

## 🚀 快速开始

```dart
// 初始化
final config = ApiConfig(
  baseUrl: 'YOUR_BASE_URL',
  apiKey: 'YOUR_API_KEY',
);

final service = MidjourneyService(config);
final helper = MidjourneyHelper(service);
```

## 📋 所有操作速查表

### 基础操作

| 操作 | 方法 | 说明 | 返回 |
|------|------|------|------|
| **Imagine** | `helper.textToImage()` | 文生图 | 任务 ID |
| **Imagine + 垫图** | `helper.imageToImage()` | 图生图 | 任务 ID |
| **Blend** | `helper.blend()` | 融合图片 | 任务 ID |
| **Describe** | `helper.describe()` | 图生文 | 任务 ID |
| **Shorten** | `helper.shorten()` | 优化Prompt | 任务 ID |
| **SwapFace** | `helper.swapFace()` | 换脸 | 任务 ID |
| **Modal** | `helper.modal()` | 补充输入 | 任务 ID |
| **Inpaint** | `helper.inpaint()` | 局部重绘 | 任务 ID |
| **查询状态** | `service.getTaskStatus()` | 查询任务 | 状态信息 |
| **轮询等待** | `helper.pollTaskUntilComplete()` | 等待完成 | 最终状态 |

### Action 操作

| 操作 | 方法 | 说明 | 参数 |
|------|------|------|------|
| **Upscale** | `helper.upscale()` | 放大图片 | taskId, index(1-4) |
| **Variation** | `helper.variation()` | 生成变体 | taskId, index(1-4) |
| **Reroll** | `helper.reroll()` | 重新生成 | taskId |
| **自定义 Action** | `service.submitAction()` | 自定义操作 | taskId, customId |

## 💡 常用代码片段

### 1️⃣ 最简单的文生图

```dart
final result = await helper.submitAndWait(
  prompt: 'A cat',
  mode: MidjourneyMode.fast,
);

print(result.data);  // 图片 URL
```

### 2️⃣ 使用 Prompt 构建器

```dart
final prompt = MidjourneyPromptBuilder()
  .withDescription('Beautiful sunset')
  .withAspectRatio('16:9')
  .withVersion('6')
  .withQuality(2.0)
  .build();

final result = await helper.submitAndWait(prompt: prompt);
```

### 3️⃣ 完整工作流（Imagine → Upscale）

```dart
// Step 1: Imagine
final imagineResult = await helper.textToImage(
  prompt: 'A cat',
  mode: MidjourneyMode.fast,
);

final taskId = imagineResult.data!.taskId;

// Step 2: 等待完成
await helper.pollTaskUntilComplete(taskId: taskId);

// Step 3: Upscale 第 2 张
final upscaleResult = await helper.upscale(
  taskId: taskId,
  index: 2,
  mode: MidjourneyMode.fast,
);

// Step 4: 等待 Upscale 完成
final status = await helper.pollTaskUntilComplete(
  taskId: upscaleResult.data!.taskId,
);

print(status.data!.imageUrl);  // 高清图 URL
```

### 4️⃣ 图生图（垫图）

```dart
final image = base64Encode(await File('ref.jpg').readAsBytes());

final result = await helper.imageToImage(
  prompt: 'Transform to cyberpunk style',
  referenceImages: [image],
  mode: MidjourneyMode.fast,
);
```

### 5️⃣ Blend 融合图片

```dart
// 准备图片
final img1 = base64Encode(await File('photo1.jpg').readAsBytes());
final img2 = base64Encode(await File('photo2.jpg').readAsBytes());
final img3 = base64Encode(await File('photo3.jpg').readAsBytes());

// 融合并等待
final result = await helper.blendAndWait(
  images: [img1, img2, img3],
  dimensions: MidjourneyDimensions.square,  // 1:1
  mode: MidjourneyMode.fast,
);

print(result.data);  // 融合后的图片 URL
```

### 6️⃣ Modal 补充输入

```dart
// 当任务返回 code: 21 时
final result = await helper.textToImage(prompt: 'test');

if (result.data?.code == 21) {
  // 提交 Modal 补充信息
  final modalResult = await helper.modal(
    taskId: result.data!.taskId,
    prompt: 'Add more details',
  );
  
  if (modalResult.isSuccess) {
    print('Modal 已提交');
  }
}
```

### 7️⃣ 局部重绘（Inpaint）

```dart
// 准备蒙版（白色区域 = 重绘区域）
final maskBase64 = await createMask();

// 提交局部重绘
final result = await helper.inpaint(
  taskId: originalTaskId,
  maskBase64: maskBase64,
  prompt: 'A blue sky with clouds',
);

// 等待完成
await helper.pollTaskUntilComplete(taskId: result.data!.taskId);
```

### 8️⃣ Describe 图生文

```dart
// 读取图片
final imageBytes = await File('photo.jpg').readAsBytes();
final imageBase64 = base64Encode(imageBytes);

// 分析并获取描述
final result = await helper.describeAndWait(
  imageBase64: imageBase64,
  mode: MidjourneyMode.fast,
);

if (result.isSuccess) {
  final prompts = result.data!.prompts;
  
  print('生成了 ${prompts.length} 个 prompt:');
  for (final prompt in prompts) {
    print('- $prompt');
  }
  
  // 使用最佳 prompt
  print('最佳: ${result.data!.bestPrompt}');
}
```

### 9️⃣ Shorten 优化 Prompt

```dart
// 冗长的 prompt
final longPrompt = '''
  A very detailed professional photograph of a beautiful cat 
  with soft fluffy white fur sitting on a comfortable cushion
''';

// 优化并获取结果
final result = await helper.shortenAndWait(
  prompt: longPrompt,
  mode: MidjourneyMode.fast,
);

if (result.isSuccess) {
  print('优化建议:');
  for (final p in result.data!.shortenedPrompts) {
    print('- $p');
  }
  
  print('\n最佳: ${result.data!.bestShortened}');
  print('优化率: ${(result.data!.optimizationRatio * 100).toInt()}%');
}
```

## 🎨 Prompt 参数速查

### 格式

```
描述 + 参数
```

### 常用参数

| 参数 | 说明 | 示例 | 默认值 |
|------|------|------|--------|
| `--ar` | 宽高比 | `--ar 16:9` | 1:1 |
| `--v` | 版本 | `--v 6` | 最新版 |
| `--q` | 质量 | `--q 2.0` | 1.0 |
| `--s` | 风格化 | `--s 750` | 100 |
| `--c` | 混乱度 | `--c 50` | 0 |
| `--no` | 排除 | `--no people` | - |
| `--seed` | 种子 | `--seed 123` | 随机 |

### 示例 Prompt

```dart
// 写实照片
'Professional photography of luxury car, studio lighting --ar 16:9 --v 6 --q 2.0'

// 艺术风格
'Cyberpunk city, neon lights, rain --ar 16:9 --s 750 --c 30'

// 动漫风格
'Anime girl, cherry blossom --ar 9:16 --niji 5 --s 850'
```

## 🔢 状态码速查

### 任务提交状态码

| Code | 说明 | 处理方式 |
|------|------|----------|
| `1` | 成功 | 继续轮询 |
| `21` | 需要补充 | 调用 Modal |
| `22` | 排队中 | 稍后重试 |
| `23` | 队列满 | 错峰使用 |
| `24` | 敏感词 | 修改 prompt |

### 任务状态

| Status | 说明 | 操作 |
|--------|------|------|
| `SUBMITTED` | 已提交 | 继续等待 |
| `IN_PROGRESS` | 进行中 | 继续等待 |
| `SUCCESS` | 成功 | 获取结果 |
| `FAILURE` | 失败 | 检查原因 |

## ⚙️ 常量速查

### 生成模式

```dart
MidjourneyMode.relax  // 慢速，免费
MidjourneyMode.fast   // 快速，付费
```

### Bot 类型

```dart
MidjourneyBotType.midjourney  // 标准
MidjourneyBotType.niji        // 动漫
```

### 宽高比

```dart
MidjourneyAspectRatio.square     // 1:1
MidjourneyAspectRatio.landscape  // 16:9
MidjourneyAspectRatio.portrait   // 9:16
MidjourneyAspectRatio.standard   // 4:3
MidjourneyAspectRatio.wide       // 21:9
```

### 版本

```dart
MidjourneyVersion.v6     // 6
MidjourneyVersion.v5     // 5
MidjourneyVersion.niji5  // niji 5
```

### Blend 比例

```dart
MidjourneyDimensions.portrait   // PORTRAIT (2:3)
MidjourneyDimensions.square     // SQUARE (1:1)
MidjourneyDimensions.landscape  // LANDSCAPE (3:2)
```

## 🐛 错误处理模板

```dart
final result = await helper.textToImage(prompt: 'test');

if (result.isSuccess) {
  // 成功
  final taskId = result.data!.taskId;
  print('任务 ID: $taskId');
} else {
  // 失败
  final code = result.data?.code;
  
  if (code == 22) {
    print('排队中，请稍后重试');
  } else if (code == 23) {
    print('队列已满');
  } else if (code == 24) {
    print('Prompt 包含敏感词');
  } else {
    print('错误: ${result.errorMessage}');
  }
}
```

## 📱 Flutter UI 示例

### 基础按钮

```dart
ElevatedButton(
  onPressed: () async {
    final result = await helper.submitAndWait(
      prompt: _promptController.text,
      mode: MidjourneyMode.fast,
    );
    
    if (result.isSuccess) {
      setState(() => _imageUrl = result.data);
    }
  },
  child: Text('生成图片'),
)
```

### 带进度的生成

```dart
Future<void> _generateWithProgress() async {
  setState(() => _isGenerating = true);
  
  final submitResult = await helper.textToImage(prompt: prompt);
  final taskId = submitResult.data!.taskId;
  
  // 定时查询进度
  final timer = Timer.periodic(Duration(seconds: 3), (timer) async {
    final status = await service.getTaskStatus(taskId: taskId);
    
    setState(() {
      _progress = status.data?.progress ?? 0;
    });
    
    if (status.data?.isFinished == true) {
      timer.cancel();
      setState(() {
        _isGenerating = false;
        _imageUrl = status.data!.imageUrl;
      });
    }
  });
}
```

### Action 按钮组

```dart
// U1, U2, U3, U4 按钮
Row(
  children: List.generate(4, (index) {
    return ElevatedButton(
      onPressed: () => _upscale(index + 1),
      child: Text('U${index + 1}'),
    );
  }),
)

// V1, V2, V3, V4 按钮
Row(
  children: List.generate(4, (index) {
    return ElevatedButton(
      onPressed: () => _variation(index + 1),
      child: Text('V${index + 1}'),
    );
  }),
)
```

## 🎯 性能优化

### 1. 请求间隔

```dart
// 避免过快请求
await Future.delayed(Duration(seconds: 2));
```

### 2. 并发控制

```dart
// 限制同时进行的任务数
final _activeTasks = <String>{};

if (_activeTasks.length >= 3) {
  print('已达到并发上限');
  return;
}

_activeTasks.add(taskId);
try {
  await helper.pollTaskUntilComplete(taskId: taskId);
} finally {
  _activeTasks.remove(taskId);
}
```

### 3. 结果缓存

```dart
final _cache = <String, String>{};  // taskId -> imageUrl

Future<String?> getResult(String taskId) async {
  if (_cache.containsKey(taskId)) {
    return _cache[taskId];
  }
  
  final status = await service.getTaskStatus(taskId: taskId);
  
  if (status.data?.imageUrl != null) {
    _cache[taskId] = status.data!.imageUrl!;
    return status.data!.imageUrl;
  }
  
  return null;
}
```

## ⏱️ 时间估算

### 生成时间（参考）

| 操作 | RELAX 模式 | FAST 模式 |
|------|-----------|-----------|
| Imagine | 2-3 分钟 | 30-60 秒 |
| Upscale | 1-2 分钟 | 20-40 秒 |
| Variation | 2-3 分钟 | 30-60 秒 |
| Reroll | 2-3 分钟 | 30-60 秒 |

### 轮询设置建议

```dart
// RELAX 模式
maxAttempts: 60,        // 5 分钟
intervalSeconds: 5,

// FAST 模式
maxAttempts: 30,        // 2.5 分钟
intervalSeconds: 5,
```

## 🔗 相关文档

- **详细使用指南**: `MIDJOURNEY_USAGE.md`
- **Action 操作详解**: `MIDJOURNEY_ACTIONS.md`
- **Blend 融图**: `MIDJOURNEY_BLEND.md`
- **Modal 补充**: `MIDJOURNEY_MODAL.md`
- **Describe 图生文**: `MIDJOURNEY_DESCRIBE.md`
- **Shorten 优化**: `MIDJOURNEY_SHORTEN.md`
- **集成指南**: `MIDJOURNEY_INTEGRATION.md`
- **完整示例**: `examples/midjourney_example.dart`

---

**提示**: 将此文档保存为书签，方便快速查阅！📖
