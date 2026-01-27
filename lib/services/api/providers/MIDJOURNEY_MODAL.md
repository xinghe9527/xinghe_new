# Midjourney Modal 操作指南

## 概述

Modal 是 Midjourney 的补充输入接口，用于处理需要额外信息的特殊场景。

### 使用场景

1. **当任务返回 code: 21** - 系统需要额外输入
2. **局部重绘（Inpaint）** - 修改图片的特定区域
3. **细节修改** - 补充描述或修改提示词

## 工作原理

```
普通任务 → 返回 code: 21 → 调用 Modal 接口 → 提供额外信息 → 继续执行
```

### Code: 21 的含义

当任务返回状态码 `21` 时，表示：
- 系统需要更多信息才能继续
- 可能需要补充 prompt
- 可能需要提供蒙版（用于局部重绘）

## 快速开始

### 基础配置

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

### 示例 1: 处理 Code 21 响应

```dart
// 提交一个任务
final result = await helper.textToImage(
  prompt: 'A landscape',
  mode: MidjourneyMode.fast,
);

// 检查响应码
if (result.data?.code == 21) {
  print('需要补充信息');
  
  // 提交 Modal
  final modalResult = await helper.modal(
    taskId: result.data!.taskId,
    prompt: 'with mountains and a lake',  // 补充描述
  );
  
  if (modalResult.isSuccess) {
    print('Modal 已提交，新任务 ID: ${modalResult.data!.taskId}');
  }
}
```

### 示例 2: 局部重绘（Inpaint）

```dart
import 'dart:convert';
import 'dart:io';

// 1. 准备蒙版图片
// 蒙版是一张黑白图片，白色区域表示要重绘的部分
final maskBytes = await File('mask.png').readAsBytes();
final maskBase64 = base64Encode(maskBytes);

// 2. 提交局部重绘
final result = await helper.inpaint(
  taskId: originalTaskId,
  maskBase64: maskBase64,
  prompt: 'Replace with a blue sky',  // 描述如何重绘该区域
);

if (result.isSuccess) {
  print('局部重绘任务已提交');
  
  // 等待完成
  final status = await helper.pollTaskUntilComplete(
    taskId: result.data!.taskId,
  );
  
  if (status.isSuccess) {
    print('重绘完成: ${status.data!.imageUrl}');
  }
}
```

### 示例 3: Modal 并等待完成

```dart
// 一键提交 Modal 并等待完成
final result = await helper.modalAndWait(
  taskId: originalTaskId,
  prompt: 'Add more details to the background',
  maxWaitMinutes: 5,
);

if (result.isSuccess) {
  print('Modal 完成，图片 URL: ${result.data}');
}
```

### 示例 4: 完整的交互流程

```dart
Future<String?> interactiveGeneration(String initialPrompt) async {
  // 1. 提交初始任务
  final initialResult = await helper.textToImage(
    prompt: initialPrompt,
    mode: MidjourneyMode.fast,
  );

  if (!initialResult.isSuccess) {
    return null;
  }

  var currentTaskId = initialResult.data!.taskId;

  // 2. 检查是否需要 Modal
  while (true) {
    // 等待任务完成或返回 21
    final status = await helper.pollTaskUntilComplete(
      taskId: currentTaskId,
      maxAttempts: 60,
    );

    if (!status.isSuccess) {
      // 检查是否是 code: 21
      if (status.data?.code == 21) {
        print('需要补充信息');
        
        // 获取用户输入（这里模拟）
        final additionalPrompt = await getUserInput();
        
        // 提交 Modal
        final modalResult = await helper.modal(
          taskId: currentTaskId,
          prompt: additionalPrompt,
        );
        
        if (modalResult.isSuccess) {
          currentTaskId = modalResult.data!.taskId;
          continue;  // 继续循环等待新任务
        } else {
          return null;
        }
      } else {
        return null;
      }
    } else {
      // 任务成功完成
      return status.data!.imageUrl;
    }
  }
}

Future<String> getUserInput() async {
  // TODO: 实现用户输入逻辑
  return 'additional details';
}
```

## API 参数说明

### 必需参数

| 参数 | 类型 | 说明 |
|------|------|------|
| `taskId` | String | 原任务 ID |

### 可选参数

| 参数 | 类型 | 说明 | 用途 |
|------|------|------|------|
| `prompt` | String | 补充提示词 | 描述修改内容 |
| `maskBase64` | String | 蒙版 base64 | 指定重绘区域 |

## 局部重绘详解

### 蒙版图片制作

蒙版是一张黑白图片：
- **白色区域**: 要重绘的部分
- **黑色区域**: 保持不变的部分

```dart
// 使用图像编辑库创建蒙版
import 'package:image/image.dart' as img;

Future<String> createMask({
  required String originalImagePath,
  required Rect inpaintArea,
}) async {
  // 1. 加载原图
  final bytes = await File(originalImagePath).readAsBytes();
  final image = img.decodeImage(bytes)!;
  
  // 2. 创建黑色蒙版
  final mask = img.Image(image.width, image.height);
  img.fill(mask, img.getColor(0, 0, 0));  // 填充黑色
  
  // 3. 绘制白色重绘区域
  img.fillRect(
    mask,
    inpaintArea.left.toInt(),
    inpaintArea.top.toInt(),
    inpaintArea.right.toInt(),
    inpaintArea.bottom.toInt(),
    img.getColor(255, 255, 255),  // 白色
  );
  
  // 4. 编码为 Base64
  final maskBytes = img.encodePng(mask);
  return base64Encode(maskBytes);
}

// 使用
final mask = await createMask(
  originalImagePath: 'original.jpg',
  inpaintArea: Rect.fromLTWH(100, 100, 200, 200),  // 重绘区域
);

await helper.inpaint(
  taskId: taskId,
  maskBase64: mask,
  prompt: 'A blue sky with clouds',
);
```

### 在 Flutter 中实现蒙版绘制

```dart
class InpaintMaskPainter extends StatefulWidget {
  final String imagePath;
  final Function(String maskBase64) onMaskCreated;

  const InpaintMaskPainter({
    required this.imagePath,
    required this.onMaskCreated,
  });

  @override
  State<InpaintMaskPainter> createState() => _InpaintMaskPainterState();
}

class _InpaintMaskPainterState extends State<InpaintMaskPainter> {
  final List<Offset> _points = [];
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 显示原图并绘制蒙版
        GestureDetector(
          onPanUpdate: (details) {
            setState(() {
              _points.add(details.localPosition);
            });
          },
          onPanEnd: (details) {
            _points.add(Offset.infinite);
          },
          child: CustomPaint(
            foregroundPainter: MaskPainter(_points),
            child: Image.file(File(widget.imagePath)),
          ),
        ),
        
        // 操作按钮
        Row(
          children: [
            ElevatedButton(
              onPressed: _clearMask,
              child: Text('清除'),
            ),
            ElevatedButton(
              onPressed: _generateMask,
              child: Text('生成蒙版'),
            ),
          ],
        ),
      ],
    );
  }

  void _clearMask() {
    setState(() => _points.clear());
  }

  Future<void> _generateMask() async {
    // 将绘制的路径转换为蒙版图片
    final mask = await _pointsToMask(_points);
    widget.onMaskCreated(mask);
  }

  Future<String> _pointsToMask(List<Offset> points) async {
    // TODO: 实现点集到蒙版图片的转换
    // 1. 创建黑色背景
    // 2. 根据 points 绘制白色区域
    // 3. 转换为 base64
    return 'data:image/png;base64,...';
  }
}

class MaskPainter extends CustomPainter {
  final List<Offset> points;

  MaskPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red.withOpacity(0.5)
      ..strokeWidth = 20.0
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != Offset.infinite && 
          points[i + 1] != Offset.infinite) {
        canvas.drawLine(points[i], points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(MaskPainter oldDelegate) => true;
}
```

## 错误处理

### 检测 Code 21

```dart
Future<void> handleTaskResult(
  ApiResponse<MidjourneyTaskResponse> result,
) async {
  if (!result.isSuccess) {
    print('任务失败: ${result.errorMessage}');
    return;
  }

  final code = result.data!.code;
  
  switch (code) {
    case 1:
      print('任务提交成功');
      break;
      
    case 21:
      print('需要补充信息，调用 Modal 接口');
      await handleModal(result.data!.taskId);
      break;
      
    case 22:
      print('任务排队中');
      break;
      
    case 23:
      print('队列已满');
      break;
      
    case 24:
      print('包含敏感词');
      break;
      
    default:
      print('未知状态码: $code');
  }
}

Future<void> handleModal(String taskId) async {
  // 获取用户输入
  final userInput = await showPromptDialog();
  
  if (userInput != null && userInput.isNotEmpty) {
    final modalResult = await helper.modal(
      taskId: taskId,
      prompt: userInput,
    );
    
    if (modalResult.isSuccess) {
      print('Modal 提交成功');
    }
  }
}
```

### 自动重试机制

```dart
Future<ApiResponse<String>> generateWithModalSupport({
  required String prompt,
  int maxModalRetries = 3,
}) async {
  var currentTaskId = '';
  
  // 提交初始任务
  var result = await helper.textToImage(
    prompt: prompt,
    mode: MidjourneyMode.fast,
  );
  
  if (!result.isSuccess) {
    return ApiResponse.failure('初始任务提交失败');
  }
  
  currentTaskId = result.data!.taskId;
  
  // 处理可能的 Modal 需求
  for (int i = 0; i < maxModalRetries; i++) {
    // 等待任务完成
    final status = await helper.pollTaskUntilComplete(
      taskId: currentTaskId,
    );
    
    // 检查是否需要 Modal
    if (!status.isSuccess && status.data?.code == 21) {
      print('需要 Modal 输入（第 ${i + 1} 次）');
      
      // 自动补充一些通用信息
      final modalResult = await helper.modal(
        taskId: currentTaskId,
        prompt: 'continue with high quality',
      );
      
      if (modalResult.isSuccess) {
        currentTaskId = modalResult.data!.taskId;
        continue;
      } else {
        return ApiResponse.failure('Modal 提交失败');
      }
    } else if (status.isSuccess) {
      // 任务成功完成
      return ApiResponse.success(status.data!.imageUrl ?? '');
    } else {
      // 其他错误
      return ApiResponse.failure(status.errorMessage ?? '任务失败');
    }
  }
  
  return ApiResponse.failure('超过最大 Modal 重试次数');
}
```

## 局部重绘完整流程

### 步骤 1: 生成初始图片

```dart
final imagineResult = await helper.submitAndWait(
  prompt: 'A house with a garden',
  mode: MidjourneyMode.fast,
);

final originalImageUrl = imagineResult.data!;
print('原图: $originalImageUrl');
```

### 步骤 2: 创建蒙版

用户标记要修改的区域，生成蒙版：

```dart
// 用户在 UI 中绘制要修改的区域
// 例如：标记花园部分
final mask = await createInpaintMask(
  originalImage: originalImageUrl,
  userDrawing: userMaskPath,
);
```

### 步骤 3: 提交局部重绘

```dart
final inpaintResult = await helper.inpaint(
  taskId: extractTaskIdFromUrl(originalImageUrl),
  maskBase64: mask,
  prompt: 'A beautiful swimming pool',  // 将花园改为泳池
);

if (inpaintResult.isSuccess) {
  // 等待重绘完成
  final status = await helper.pollTaskUntilComplete(
    taskId: inpaintResult.data!.taskId,
  );
  
  if (status.isSuccess) {
    print('重绘完成: ${status.data!.imageUrl}');
  }
}
```

## Flutter UI 实现

### Modal 输入对话框

```dart
class ModalInputDialog extends StatelessWidget {
  final String taskId;
  final MidjourneyHelper helper;

  const ModalInputDialog({
    required this.taskId,
    required this.helper,
  });

  @override
  Widget build(BuildContext context) {
    final promptController = TextEditingController();

    return AlertDialog(
      title: Text('补充信息'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('任务需要更多信息才能继续'),
          SizedBox(height: 16),
          TextField(
            controller: promptController,
            decoration: InputDecoration(
              labelText: '补充描述',
              hintText: '输入额外的细节描述...',
            ),
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('取消'),
        ),
        ElevatedButton(
          onPressed: () async {
            final prompt = promptController.text.trim();
            
            if (prompt.isEmpty) {
              return;
            }

            // 提交 Modal
            final result = await helper.modal(
              taskId: taskId,
              prompt: prompt,
            );

            if (result.isSuccess) {
              Navigator.pop(context, result.data!.taskId);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('提交失败: ${result.errorMessage}')),
              );
            }
          },
          child: Text('提交'),
        ),
      ],
    );
  }
}

// 使用
Future<void> handleCode21(String taskId) async {
  final newTaskId = await showDialog<String>(
    context: context,
    builder: (context) => ModalInputDialog(
      taskId: taskId,
      helper: _helper,
    ),
  );

  if (newTaskId != null) {
    // 继续处理新任务
    print('新任务 ID: $newTaskId');
  }
}
```

### 局部重绘 UI

```dart
class InpaintWidget extends StatefulWidget {
  final String imageUrl;
  final String taskId;

  const InpaintWidget({
    required this.imageUrl,
    required this.taskId,
  });

  @override
  State<InpaintWidget> createState() => _InpaintWidgetState();
}

class _InpaintWidgetState extends State<InpaintWidget> {
  final _helper = MidjourneyHelper(MidjourneyService(config));
  final _promptController = TextEditingController();
  
  List<Offset> _maskPoints = [];
  bool _isInpainting = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('在图片上绘制要修改的区域'),
        
        // 绘制蒙版
        GestureDetector(
          onPanUpdate: (details) {
            setState(() {
              _maskPoints.add(details.localPosition);
            });
          },
          onPanEnd: (_) {
            _maskPoints.add(Offset.infinite);
          },
          child: CustomPaint(
            foregroundPainter: MaskPainter(_maskPoints),
            child: Image.network(widget.imageUrl),
          ),
        ),
        
        // 输入修改描述
        TextField(
          controller: _promptController,
          decoration: InputDecoration(
            labelText: '修改描述',
            hintText: '描述如何修改标记的区域...',
          ),
        ),
        
        // 操作按钮
        Row(
          children: [
            ElevatedButton(
              onPressed: () {
                setState(() => _maskPoints.clear());
              },
              child: Text('清除蒙版'),
            ),
            ElevatedButton(
              onPressed: _isInpainting ? null : _performInpaint,
              child: Text(_isInpainting ? '处理中...' : '开始重绘'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _performInpaint() async {
    if (_maskPoints.isEmpty) {
      _showMessage('请先绘制蒙版');
      return;
    }

    if (_promptController.text.trim().isEmpty) {
      _showMessage('请输入修改描述');
      return;
    }

    setState(() => _isInpainting = true);

    try {
      // 1. 生成蒙版图片
      final maskBase64 = await _generateMaskImage();
      
      // 2. 提交局部重绘
      final result = await _helper.inpaint(
        taskId: widget.taskId,
        maskBase64: maskBase64,
        prompt: _promptController.text.trim(),
      );
      
      if (result.isSuccess) {
        _showMessage('重绘任务已提交');
        
        // 3. 等待完成
        final status = await _helper.pollTaskUntilComplete(
          taskId: result.data!.taskId,
        );
        
        if (status.isSuccess) {
          _showMessage('重绘完成！');
          // TODO: 显示新图片
        }
      } else {
        _showMessage('提交失败: ${result.errorMessage}');
      }
    } finally {
      setState(() => _isInpainting = false);
    }
  }

  Future<String> _generateMaskImage() async {
    // TODO: 将 _maskPoints 转换为蒙版图片
    // 返回 base64 编码的蒙版
    return 'data:image/png;base64,...';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
```

## 最佳实践

### 1. 自动处理 Code 21

```dart
class MidjourneyTaskManager {
  final MidjourneyHelper helper;
  
  MidjourneyTaskManager(this.helper);
  
  /// 智能任务执行：自动处理 Modal 需求
  Future<String?> smartExecute({
    required String prompt,
    Function(String)? onModalRequired,
  }) async {
    var result = await helper.textToImage(
      prompt: prompt,
      mode: MidjourneyMode.fast,
    );
    
    var taskId = result.data?.taskId;
    
    while (taskId != null) {
      // 等待任务完成
      final status = await helper.pollTaskUntilComplete(taskId: taskId);
      
      if (status.isSuccess) {
        return status.data!.imageUrl;
      }
      
      // 检查是否需要 Modal
      if (status.data?.code == 21) {
        if (onModalRequired != null) {
          // 通知外部获取额外输入
          final additionalPrompt = await onModalRequired(taskId);
          
          if (additionalPrompt != null) {
            final modalResult = await helper.modal(
              taskId: taskId,
              prompt: additionalPrompt,
            );
            
            if (modalResult.isSuccess) {
              taskId = modalResult.data!.taskId;
              continue;
            }
          }
        }
        
        return null;
      } else {
        return null;
      }
    }
    
    return null;
  }
}

// 使用
final manager = MidjourneyTaskManager(helper);

final imageUrl = await manager.smartExecute(
  prompt: 'A landscape',
  onModalRequired: (taskId) async {
    // 显示对话框获取用户输入
    return await showDialog<String>(
      context: context,
      builder: (context) => ModalInputDialog(taskId: taskId),
    );
  },
);
```

### 2. 蒙版模板

预定义常用的蒙版模板：

```dart
class MaskTemplates {
  /// 中心圆形蒙版
  static Future<String> centerCircle({
    required int width,
    required int height,
    double radiusPercent = 0.3,
  }) async {
    final image = img.Image(width, height);
    img.fill(image, img.getColor(0, 0, 0));
    
    final centerX = width / 2;
    final centerY = height / 2;
    final radius = (width * radiusPercent).toInt();
    
    img.fillCircle(
      image,
      centerX.toInt(),
      centerY.toInt(),
      radius,
      img.getColor(255, 255, 255),
    );
    
    final bytes = img.encodePng(image);
    return 'data:image/png;base64,${base64Encode(bytes)}';
  }
  
  /// 矩形区域蒙版
  static Future<String> rectangle({
    required int width,
    required int height,
    required Rect area,
  }) async {
    final image = img.Image(width, height);
    img.fill(image, img.getColor(0, 0, 0));
    
    img.fillRect(
      image,
      area.left.toInt(),
      area.top.toInt(),
      area.right.toInt(),
      area.bottom.toInt(),
      img.getColor(255, 255, 255),
    );
    
    final bytes = img.encodePng(image);
    return 'data:image/png;base64,${base64Encode(bytes)}';
  }
}

// 使用
final centerMask = await MaskTemplates.centerCircle(
  width: 1024,
  height: 1024,
  radiusPercent: 0.4,
);

await helper.inpaint(
  taskId: taskId,
  maskBase64: centerMask,
  prompt: 'A glowing portal',
);
```

## 实用工具

### Modal 状态检测器

```dart
extension MidjourneyResponseExtension on ApiResponse<MidjourneyTaskResponse> {
  bool get needsModal => data?.code == 21;
  
  bool get isQueued => data?.code == 22;
  
  bool get queueFull => data?.code == 23;
  
  bool get hasSensitiveContent => data?.code == 24;
}

// 使用
final result = await helper.textToImage(prompt: 'test');

if (result.needsModal) {
  print('需要调用 Modal');
  await handleModal(result.data!.taskId);
} else if (result.isQueued) {
  print('任务排队中');
}
```

## 注意事项

1. **Code 21 触发条件**：
   - 某些特定操作可能触发
   - 系统需要更多信息
   - 局部重绘必定需要 Modal

2. **蒙版图片要求**：
   - 黑白图片（或灰度）
   - 与原图尺寸相同
   - 白色 = 重绘区域，黑色 = 保持不变

3. **Prompt 要求**：
   - 描述要如何修改标记的区域
   - 越详细越好
   - 使用英文获得更好效果

4. **性能考虑**：
   - Modal 操作会启动新任务
   - 需要额外的等待时间
   - 建议使用 FAST 模式

## 完整示例：局部重绘工作流

```dart
class InpaintWorkflow {
  final MidjourneyHelper helper;
  
  InpaintWorkflow(this.helper);
  
  /// 完整的局部重绘流程
  Future<String?> performInpaint({
    required String originalPrompt,
    required Rect inpaintArea,
    required String inpaintPrompt,
  }) async {
    // 1. 生成初始图片
    print('步骤 1: 生成初始图片');
    final imagineResult = await helper.submitAndWait(
      prompt: originalPrompt,
      mode: MidjourneyMode.fast,
    );
    
    if (!imagineResult.isSuccess) {
      print('初始生成失败');
      return null;
    }
    
    print('初始图片: ${imagineResult.data}');
    
    // 2. 下载图片获取尺寸
    final imageInfo = await getImageInfo(imagineResult.data!);
    
    // 3. 创建蒙版
    print('步骤 2: 创建蒙版');
    final mask = await MaskTemplates.rectangle(
      width: imageInfo.width,
      height: imageInfo.height,
      area: inpaintArea,
    );
    
    // 4. 提交局部重绘
    print('步骤 3: 提交局部重绘');
    final taskId = extractTaskId(imagineResult.data!);
    
    final inpaintResult = await helper.inpaint(
      taskId: taskId,
      maskBase64: mask,
      prompt: inpaintPrompt,
    );
    
    if (!inpaintResult.isSuccess) {
      print('重绘提交失败');
      return null;
    }
    
    // 5. 等待重绘完成
    print('步骤 4: 等待重绘完成');
    final finalStatus = await helper.pollTaskUntilComplete(
      taskId: inpaintResult.data!.taskId,
    );
    
    if (finalStatus.isSuccess) {
      print('✅ 重绘完成');
      return finalStatus.data!.imageUrl;
    }
    
    return null;
  }
  
  Future<({int width, int height})> getImageInfo(String url) async {
    // TODO: 获取图片尺寸
    return (width: 1024, height: 1024);
  }
  
  String extractTaskId(String url) {
    // TODO: 从 URL 中提取任务 ID
    return 'task-id';
  }
}
```

## 常见问题

**Q: 什么时候会遇到 Code 21？**  
A: 当系统需要额外信息时，如局部重绘、某些特殊操作等

**Q: Modal 是必须的吗？**  
A: 只有当任务返回 Code 21 时才需要调用

**Q: 蒙版图片格式有要求吗？**  
A: 建议使用 PNG 格式，黑白或灰度图片

**Q: 可以多次调用 Modal 吗？**  
A: 可以，如果新任务仍返回 Code 21，可以继续调用

**Q: Modal 支持所有任务类型吗？**  
A: 主要用于 Imagine 和相关操作，Blend 通常不需要

## 状态码参考

| Code | 含义 | 处理方式 |
|------|------|----------|
| 1 | 提交成功 | 继续执行 |
| 21 | 需要 Modal | 调用 Modal 接口 |
| 22 | 排队中 | 稍后重试 |
| 23 | 队列满 | 错峰使用 |
| 24 | 敏感词 | 修改内容 |

## 相关文档

- **Midjourney 使用指南**: `MIDJOURNEY_USAGE.md`
- **Action 操作**: `MIDJOURNEY_ACTIONS.md`
- **Blend 融图**: `MIDJOURNEY_BLEND.md`
- **快速参考**: `MIDJOURNEY_QUICK_REFERENCE.md`

---

**Modal 操作让你能够精细控制生成过程！✨**
