# Midjourney Action 操作指南

## 概述

Midjourney Action 接口用于对已生成的图片执行后续操作，包括：

- **Upscale (U)**: 放大选中的图片
- **Variation (V)**: 生成选中图片的变体
- **Reroll (🔄)**: 重新生成一组新图片

## 基本概念

### 工作流程

```
1. 提交 Imagine 任务 → 生成 4 张预览图
2. 查看结果，选择满意的图片
3. 执行 Action 操作：
   - Upscale: 放大为高清大图
   - Variation: 生成更多相似的变体
   - Reroll: 重新生成 4 张新图
```

### CustomId 说明

每个可执行的操作都有一个唯一的 `customId`，格式如下：

```
MJ::JOB::[action]::[index]::[taskId]
```

- `action`: 操作类型（upsample, variation, reroll 等）
- `index`: 图片索引（1-4），Reroll 为 0
- `taskId`: 原任务 ID

## 快速开始

### 准备工作

```dart
import 'package:xinghe_new/services/api/providers/midjourney_service.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';

final config = ApiConfig(
  baseUrl: 'YOUR_BASE_URL',
  apiKey: 'YOUR_API_KEY',
);

final service = MidjourneyService(config);
final helper = MidjourneyHelper(service);
```

## 使用示例

### 1. 完整的 Upscale 流程

```dart
// 步骤 1: 提交 Imagine 任务
final imagineResult = await helper.textToImage(
  prompt: 'A majestic mountain landscape',
  mode: MidjourneyMode.fast,
);

final taskId = imagineResult.data!.taskId;
print('Imagine 任务 ID: $taskId');

// 步骤 2: 等待生成完成
final imagineStatus = await helper.pollTaskUntilComplete(
  taskId: taskId,
  maxAttempts: 60,
  intervalSeconds: 5,
);

if (imagineStatus.isSuccess) {
  print('4 张预览图生成完成');
  print('预览图 URL: ${imagineStatus.data!.imageUrl}');
  
  // 步骤 3: Upscale 第 2 张图片
  final upscaleResult = await helper.upscale(
    taskId: taskId,
    index: 2,  // 选择第 2 张
    mode: MidjourneyMode.fast,
  );
  
  if (upscaleResult.isSuccess) {
    final upscaleTaskId = upscaleResult.data!.taskId;
    print('Upscale 任务 ID: $upscaleTaskId');
    
    // 步骤 4: 等待 Upscale 完成
    final upscaleStatus = await helper.pollTaskUntilComplete(
      taskId: upscaleTaskId,
    );
    
    if (upscaleStatus.isSuccess) {
      print('✅ Upscale 完成！');
      print('高清图片 URL: ${upscaleStatus.data!.imageUrl}');
    }
  }
}
```

### 2. Variation 操作

```dart
// 假设已有原任务 ID
final originalTaskId = 'existing-task-id';

// 生成第 1 张图的变体
final variationResult = await helper.variation(
  taskId: originalTaskId,
  index: 1,
  mode: MidjourneyMode.fast,
);

if (variationResult.isSuccess) {
  print('Variation 任务已提交: ${variationResult.data!.taskId}');
  
  // 等待完成
  final status = await helper.pollTaskUntilComplete(
    taskId: variationResult.data!.taskId,
  );
  
  if (status.isSuccess) {
    print('变体生成完成: ${status.data!.imageUrl}');
  }
}
```

### 3. Reroll 操作

```dart
// 对已完成的任务重新生成
final rerollResult = await helper.reroll(
  taskId: originalTaskId,
  mode: MidjourneyMode.fast,
);

if (rerollResult.isSuccess) {
  print('Reroll 任务已提交');
  
  // 等待新的 4 张图生成
  final status = await helper.pollTaskUntilComplete(
    taskId: rerollResult.data!.taskId,
  );
  
  if (status.isSuccess) {
    print('重新生成完成: ${status.data!.imageUrl}');
  }
}
```

### 4. 使用原始 customId

```dart
// 从任务状态中获取 customId
final statusResult = await service.getTaskStatus(taskId: taskId);

if (statusResult.isSuccess) {
  final metadata = statusResult.data!.metadata;
  
  // 假设 API 返回的按钮信息中包含 customId
  final buttons = metadata?['buttons'] as List?;
  
  if (buttons != null && buttons.isNotEmpty) {
    final upscaleButton = buttons.firstWhere(
      (btn) => btn['label'] == 'U2',  // Upscale 第 2 张
      orElse: () => null,
    );
    
    if (upscaleButton != null) {
      final customId = upscaleButton['customId'] as String;
      
      // 使用 customId 提交 Action
      final actionResult = await service.submitAction(
        taskId: taskId,
        customId: customId,
        mode: MidjourneyMode.fast,
      );
      
      print('Action 已提交: ${actionResult.data!.taskId}');
    }
  }
}
```

## 操作类型详解

### Upscale (U1-U4)

**作用**: 将选中的预览图放大为高清大图

**使用场景**:
- 确定了满意的构图
- 需要高分辨率输出
- 用于最终展示或打印

**示例**:
```dart
// 放大第 1 张
await helper.upscale(taskId: taskId, index: 1);

// 放大第 2 张
await helper.upscale(taskId: taskId, index: 2);

// 放大第 3 张
await helper.upscale(taskId: taskId, index: 3);

// 放大第 4 张
await helper.upscale(taskId: taskId, index: 4);
```

### Variation (V1-V4)

**作用**: 基于选中的图片生成新的变体

**使用场景**:
- 对某张图片的构图满意，想看更多相似的
- 探索不同的风格变化
- 微调细节

**示例**:
```dart
// 生成第 1 张的变体
await helper.variation(taskId: taskId, index: 1);

// 会生成 4 张新的图片，风格与第 1 张相似
```

### Reroll (🔄)

**作用**: 使用相同的 prompt 重新生成 4 张新图

**使用场景**:
- 对当前 4 张都不满意
- 想看更多可能性
- 探索不同的构图

**示例**:
```dart
await helper.reroll(taskId: taskId);

// 会生成全新的 4 张图片
```

## 在 Flutter 中使用

### 显示操作按钮

```dart
class MidjourneyResultWidget extends StatefulWidget {
  final String taskId;
  final String imageUrl;

  const MidjourneyResultWidget({
    required this.taskId,
    required this.imageUrl,
  });

  @override
  State<MidjourneyResultWidget> createState() => _MidjourneyResultWidgetState();
}

class _MidjourneyResultWidgetState extends State<MidjourneyResultWidget> {
  final _helper = MidjourneyHelper(
    MidjourneyService(ApiConfig(
      baseUrl: 'YOUR_BASE_URL',
      apiKey: 'YOUR_API_KEY',
    )),
  );

  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 显示生成的图片
        Image.network(widget.imageUrl),
        
        const SizedBox(height: 16),
        
        // 操作按钮
        if (!_isProcessing)
          Column(
            children: [
              // Upscale 按钮
              Text('放大选择:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildActionButton('U1', () => _handleUpscale(1)),
                  _buildActionButton('U2', () => _handleUpscale(2)),
                  _buildActionButton('U3', () => _handleUpscale(3)),
                  _buildActionButton('U4', () => _handleUpscale(4)),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Variation 按钮
              Text('生成变体:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildActionButton('V1', () => _handleVariation(1)),
                  _buildActionButton('V2', () => _handleVariation(2)),
                  _buildActionButton('V3', () => _handleVariation(3)),
                  _buildActionButton('V4', () => _handleVariation(4)),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Reroll 按钮
              ElevatedButton.icon(
                onPressed: _handleReroll,
                icon: Icon(Icons.refresh),
                label: Text('重新生成'),
              ),
            ],
          )
        else
          CircularProgressIndicator(),
      ],
    );
  }

  Widget _buildActionButton(String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          minimumSize: Size(50, 40),
        ),
        child: Text(label),
      ),
    );
  }

  Future<void> _handleUpscale(int index) async {
    setState(() => _isProcessing = true);
    
    try {
      final result = await _helper.upscale(
        taskId: widget.taskId,
        index: index,
        mode: MidjourneyMode.fast,
      );
      
      if (result.isSuccess) {
        _showMessage('Upscale 任务已提交');
        
        // 等待完成
        final status = await _helper.pollTaskUntilComplete(
          taskId: result.data!.taskId,
        );
        
        if (status.isSuccess) {
          // 显示放大后的图片
          _showMessage('Upscale 完成！');
          // TODO: 导航到新图片页面
        }
      } else {
        _showMessage('失败: ${result.errorMessage}', isError: true);
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleVariation(int index) async {
    setState(() => _isProcessing = true);
    
    try {
      final result = await _helper.variation(
        taskId: widget.taskId,
        index: index,
        mode: MidjourneyMode.fast,
      );
      
      if (result.isSuccess) {
        _showMessage('Variation 任务已提交');
        // TODO: 处理新任务
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleReroll() async {
    setState(() => _isProcessing = true);
    
    try {
      final result = await _helper.reroll(
        taskId: widget.taskId,
        mode: MidjourneyMode.fast,
      );
      
      if (result.isSuccess) {
        _showMessage('Reroll 任务已提交');
        // TODO: 处理新任务
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }
}
```

## Action 参数说明

### 必需参数

| 参数 | 类型 | 说明 | 示例 |
|------|------|------|------|
| `taskId` | String | 原任务 ID | `"14001934816969359"` |
| `customId` | String | 动作标识 | `"MJ::JOB::upsample::2::..."` |
| `mode` | String | 调用模式 | `"FAST"` 或 `"RELAX"` |

### 可选参数

| 参数 | 类型 | 说明 | 可选值 |
|------|------|------|--------|
| `botType` | String | Bot 类型 | `"mj"`, `"niji"` |
| `state` | String | 自定义参数 | 任意字符串 |
| `notifyhook` | String | 回调地址 | HTTP URL |

## CustomId 格式详解

### Upscale 操作

```
MJ::JOB::upsample::[1-4]::[taskId]
```

- 索引 1-4 对应左上、右上、左下、右下四张图

示例：
```
MJ::JOB::upsample::2::3dbbd469-36af-4a0f-8f02-df6c579e7011
```

### Variation 操作

```
MJ::JOB::variation::[1-4]::[taskId]
```

示例：
```
MJ::JOB::variation::1::3dbbd469-36af-4a0f-8f02-df6c579e7011
```

### Reroll 操作

```
MJ::JOB::reroll::0::[taskId]
```

示例：
```
MJ::JOB::reroll::0::3dbbd469-36af-4a0f-8f02-df6c579e7011
```

## 高级用法

### 1. 批量 Upscale

放大所有 4 张图片：

```dart
Future<List<String>> upscaleAll(String taskId) async {
  final results = <String>[];
  
  for (int i = 1; i <= 4; i++) {
    // 提交 Upscale
    final upscaleResult = await helper.upscale(
      taskId: taskId,
      index: i,
      mode: MidjourneyMode.fast,
    );
    
    if (upscaleResult.isSuccess) {
      // 等待完成
      final status = await helper.pollTaskUntilComplete(
        taskId: upscaleResult.data!.taskId,
      );
      
      if (status.isSuccess && status.data!.imageUrl != null) {
        results.add(status.data!.imageUrl!);
      }
    }
    
    // 避免请求过快
    await Future.delayed(Duration(seconds: 2));
  }
  
  return results;
}
```

### 2. 智能选择最佳图片

```dart
// 使用某种评分机制选择最佳图片
Future<String?> upscaleBestImage(String taskId) async {
  // 假设有一个评分函数
  final scores = await evaluateImages(taskId);  // [0.8, 0.95, 0.7, 0.85]
  
  // 找到最高分的索引
  double maxScore = 0;
  int bestIndex = 1;
  
  for (int i = 0; i < scores.length; i++) {
    if (scores[i] > maxScore) {
      maxScore = scores[i];
      bestIndex = i + 1;
    }
  }
  
  print('选择第 $bestIndex 张图片（得分: $maxScore）');
  
  // Upscale 最佳图片
  final upscaleResult = await helper.upscale(
    taskId: taskId,
    index: bestIndex,
    mode: MidjourneyMode.fast,
  );
  
  if (upscaleResult.isSuccess) {
    final status = await helper.pollTaskUntilComplete(
      taskId: upscaleResult.data!.taskId,
    );
    
    return status.data?.imageUrl;
  }
  
  return null;
}
```

### 3. 级联操作

Imagine → Variation → Upscale 的完整流程：

```dart
Future<String?> cascadeOperations(String prompt) async {
  // 1. Imagine
  print('步骤 1: Imagine');
  final imagineResult = await helper.submitAndWait(
    prompt: prompt,
    mode: MidjourneyMode.fast,
  );
  
  if (!imagineResult.isSuccess) {
    return null;
  }
  
  final taskId1 = imagineResult.data!;
  print('Imagine 完成，选择第 1 张生成变体');
  
  // 2. Variation
  print('步骤 2: Variation');
  final variationResult = await helper.variation(
    taskId: taskId1,
    index: 1,
    mode: MidjourneyMode.fast,
  );
  
  if (!variationResult.isSuccess) {
    return null;
  }
  
  // 等待 Variation 完成
  final variationStatus = await helper.pollTaskUntilComplete(
    taskId: variationResult.data!.taskId,
  );
  
  if (!variationStatus.isSuccess) {
    return null;
  }
  
  final taskId2 = variationResult.data!.taskId;
  print('Variation 完成，选择第 2 张放大');
  
  // 3. Upscale
  print('步骤 3: Upscale');
  final upscaleResult = await helper.upscale(
    taskId: taskId2,
    index: 2,
    mode: MidjourneyMode.fast,
  );
  
  if (upscaleResult.isSuccess) {
    final upscaleStatus = await helper.pollTaskUntilComplete(
      taskId: upscaleResult.data!.taskId,
    );
    
    return upscaleStatus.data?.imageUrl;
  }
  
  return null;
}
```

## Bot 类型说明

### MJ Bot (标准)

```dart
await service.submitAction(
  taskId: taskId,
  customId: customId,
  mode: MidjourneyMode.fast,
  botType: MidjourneyBotType.midjourney,  // 'mj'
);
```

### Niji Bot (动漫风格)

```dart
await service.submitAction(
  taskId: taskId,
  customId: customId,
  mode: MidjourneyMode.fast,
  botType: MidjourneyBotType.niji,  // 'niji'
);
```

## 错误处理

### 常见错误

```dart
final result = await helper.upscale(taskId: taskId, index: 2);

if (!result.isSuccess) {
  final code = result.data?.code;
  
  switch (code) {
    case 22:
      print('任务排队中');
      // 可以选择等待后重试
      break;
      
    case 23:
      print('队列已满');
      // 建议稍后再试
      break;
      
    default:
      print('错误: ${result.errorMessage}');
  }
}
```

### 任务状态验证

在执行 Action 前，确保原任务已完成：

```dart
Future<bool> canPerformAction(String taskId) async {
  final status = await service.getTaskStatus(taskId: taskId);
  
  if (!status.isSuccess) {
    return false;
  }
  
  return status.data!.isSuccess;
}

// 使用
if (await canPerformAction(taskId)) {
  await helper.upscale(taskId: taskId, index: 1);
} else {
  print('原任务尚未完成或失败');
}
```

## 最佳实践

### 1. 等待原任务完成

```dart
// ❌ 错误：立即执行 Action
final imagineResult = await helper.textToImage(prompt: 'test');
await helper.upscale(taskId: imagineResult.data!.taskId, index: 1);

// ✅ 正确：等待原任务完成
final imagineResult = await helper.textToImage(prompt: 'test');
await helper.pollTaskUntilComplete(taskId: imagineResult.data!.taskId);
await helper.upscale(taskId: imagineResult.data!.taskId, index: 1);
```

### 2. 保存任务历史

```dart
class TaskHistory {
  final String originalTaskId;
  final List<String> upscaledTaskIds;
  final List<String> variationTaskIds;

  TaskHistory({
    required this.originalTaskId,
    this.upscaledTaskIds = const [],
    this.variationTaskIds = const [],
  });
}

// 使用
final history = TaskHistory(originalTaskId: taskId);

// 记录 Upscale
final upscaleResult = await helper.upscale(taskId: taskId, index: 1);
history.upscaledTaskIds.add(upscaleResult.data!.taskId);
```

### 3. 显示操作历史

```dart
Widget buildTaskHistory(TaskHistory history) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('原始任务: ${history.originalTaskId}'),
      
      if (history.upscaledTaskIds.isNotEmpty) ...[
        SizedBox(height: 8),
        Text('已放大: ${history.upscaledTaskIds.length} 张'),
        ...history.upscaledTaskIds.map((id) => Text('  - $id')),
      ],
      
      if (history.variationTaskIds.isNotEmpty) ...[
        SizedBox(height: 8),
        Text('已变体: ${history.variationTaskIds.length} 组'),
        ...history.variationTaskIds.map((id) => Text('  - $id')),
      ],
    ],
  );
}
```

## 注意事项

1. **任务依赖**: Action 操作依赖于原任务已完成
2. **CustomId 获取**: 实际使用时应从任务状态中获取准确的 customId
3. **并发限制**: 避免同时提交过多 Action 任务
4. **模式选择**: Upscale 建议使用 FAST 模式以提升用户体验
5. **错误重试**: Action 操作也可能遇到排队，需要实现重试机制

## 完整示例：用户选择工作流

```dart
class MidjourneyWorkflow {
  final MidjourneyHelper helper;
  
  MidjourneyWorkflow(this.helper);
  
  /// 完整的用户工作流
  Future<String?> userWorkflow(String prompt) async {
    // 1. 生成初始 4 张图
    print('🎨 正在生成图片...');
    final imagineResult = await helper.textToImage(
      prompt: prompt,
      mode: MidjourneyMode.fast,
    );
    
    if (!imagineResult.isSuccess) {
      print('❌ 生成失败');
      return null;
    }
    
    // 等待完成
    final taskId = imagineResult.data!.taskId;
    final imagineStatus = await helper.pollTaskUntilComplete(taskId: taskId);
    
    if (!imagineStatus.isSuccess) {
      print('❌ 任务失败');
      return null;
    }
    
    print('✅ 4 张预览图已生成');
    
    // 2. 用户选择（这里模拟选择第 2 张）
    final userChoice = 2;
    print('👆 用户选择了第 $userChoice 张图片');
    
    // 3. 用户决定是 Upscale 还是 Variation
    final userAction = 'upscale'; // 或 'variation'
    
    if (userAction == 'upscale') {
      print('⬆️ 正在放大图片...');
      final upscaleResult = await helper.upscale(
        taskId: taskId,
        index: userChoice,
        mode: MidjourneyMode.fast,
      );
      
      if (upscaleResult.isSuccess) {
        final upscaleStatus = await helper.pollTaskUntilComplete(
          taskId: upscaleResult.data!.taskId,
        );
        
        if (upscaleStatus.isSuccess) {
          print('✅ 放大完成！');
          return upscaleStatus.data!.imageUrl;
        }
      }
    } else if (userAction == 'variation') {
      print('🎲 正在生成变体...');
      final variationResult = await helper.variation(
        taskId: taskId,
        index: userChoice,
        mode: MidjourneyMode.fast,
      );
      
      if (variationResult.isSuccess) {
        // 变体会生成新的 4 张图，用户可以继续选择
        print('✅ 变体生成完成');
        return variationResult.data!.taskId;
      }
    }
    
    return null;
  }
}
```

## API 限制和配额

1. **Action 操作计费**:
   - RELAX 模式: 使用免费额度
   - FAST 模式: 按操作计费

2. **操作次数限制**:
   - 每个任务可以执行多次 Action
   - 建议合理使用，避免浪费

3. **并发限制**:
   - 同一时间不要提交过多 Action
   - 建议串行执行

## 故障排查

### 问题 1: CustomId 无效

**症状**: 提交 Action 失败
**原因**: CustomId 格式错误或不匹配
**解决**: 
- 从任务状态中正确获取 customId
- 检查 customId 格式是否正确

### 问题 2: 原任务未完成

**症状**: Action 提交失败
**原因**: 原任务还在进行中
**解决**: 先等待原任务完成

```dart
// 确保原任务完成
await helper.pollTaskUntilComplete(taskId: originalTaskId);

// 然后执行 Action
await helper.upscale(taskId: originalTaskId, index: 1);
```

## 总结

Action 操作让你可以：

- ✅ **精细控制**: 选择最满意的图片进行后续处理
- ✅ **提升质量**: 通过 Upscale 获得高清大图
- ✅ **探索变化**: 通过 Variation 发现更多可能性
- ✅ **节省成本**: 只放大需要的图片

配合 Imagine 任务使用，可以实现完整的 Midjourney 工作流！
