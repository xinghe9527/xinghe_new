# Midjourney Blend 操作指南

## 概述

Blend 是 Midjourney 的专门融图功能，可以将 2-5 张图片融合成一张新图片。

**与 Imagine 垫图的区别**：
- **Imagine + 垫图**: 使用图片作为参考，结合文本描述生成
- **Blend**: 纯粹融合图片，不需要文本描述

## 快速开始

### 基础用法

```dart
import 'dart:convert';
import 'dart:io';
import 'package:xinghe_new/services/api/providers/midjourney_service.dart';

// 1. 准备图片
final image1 = base64Encode(await File('photo1.jpg').readAsBytes());
final image2 = base64Encode(await File('photo2.jpg').readAsBytes());

// 2. 提交 Blend 任务
final helper = MidjourneyHelper(MidjourneyService(config));

final result = await helper.blend(
  images: [image1, image2],
  dimensions: MidjourneyDimensions.square,  // 1:1
  mode: MidjourneyMode.fast,
);

if (result.isSuccess) {
  print('Blend 任务已提交: ${result.data!.taskId}');
}
```

### 自动等待完成

```dart
// 一键融合并等待完成
final result = await helper.blendAndWait(
  images: [image1, image2, image3],
  dimensions: MidjourneyDimensions.landscape,  // 3:2
  mode: MidjourneyMode.fast,
  maxWaitMinutes: 5,
);

if (result.isSuccess) {
  print('融合完成！图片 URL: ${result.data}');
}
```

## 参数说明

### 必需参数

#### base64Array（图片数组）

- **类型**: `List<String>`
- **数量**: 2-5 张图片
- **格式**: Base64 编码，需包含 data URI 前缀
- **示例**: `['data:image/png;base64,xxx1', 'data:image/png;base64,xxx2']`

```dart
// 正确的格式
final images = [
  'data:image/png;base64,iVBORw0KGgo...',
  'data:image/jpeg;base64,/9j/4AAQSkZJRg...',
];

// 或者使用辅助方法自动添加前缀
final images = [
  base64String1,  // 会自动添加前缀
  base64String2,
];
```

### 可选参数

#### dimensions（输出比例）

| 常量 | 值 | 比例 | 说明 |
|------|-----|------|------|
| `MidjourneyDimensions.portrait` | PORTRAIT | 2:3 | 竖向 |
| `MidjourneyDimensions.square` | SQUARE | 1:1 | 正方形 |
| `MidjourneyDimensions.landscape` | LANDSCAPE | 3:2 | 横向 |

```dart
// 使用常量（推荐）
dimensions: MidjourneyDimensions.square

// 或直接使用字符串
dimensions: 'SQUARE'
```

#### mode（调用模式）

```dart
mode: MidjourneyMode.fast   // 快速模式（推荐）
mode: MidjourneyMode.relax  // 慢速模式
```

#### botType（Bot 类型）

```dart
botType: MidjourneyBotType.midjourney  // 标准风格
botType: MidjourneyBotType.niji        // 动漫风格
```

## 使用示例

### 示例 1: 融合两张照片

```dart
final config = ApiConfig(
  baseUrl: 'YOUR_BASE_URL',
  apiKey: 'YOUR_API_KEY',
);

final helper = MidjourneyHelper(MidjourneyService(config));

// 读取图片
final photo1 = base64Encode(await File('portrait1.jpg').readAsBytes());
final photo2 = base64Encode(await File('portrait2.jpg').readAsBytes());

// 融合
final result = await helper.blendAndWait(
  images: [photo1, photo2],
  dimensions: MidjourneyDimensions.portrait,  // 2:3 竖向
  mode: MidjourneyMode.fast,
);

if (result.isSuccess) {
  print('融合完成: ${result.data}');
}
```

### 示例 2: 融合多张风景照

```dart
// 准备 3 张风景照
final images = <String>[];
for (int i = 1; i <= 3; i++) {
  final bytes = await File('landscape$i.jpg').readAsBytes();
  images.add(base64Encode(bytes));
}

// 融合为横向图片
final result = await helper.blend(
  images: images,
  dimensions: MidjourneyDimensions.landscape,  // 3:2
  mode: MidjourneyMode.fast,
);

// 等待完成
final status = await helper.pollTaskUntilComplete(
  taskId: result.data!.taskId,
);

print('融合结果: ${status.data!.imageUrl}');
```

### 示例 3: 使用 Niji Bot 融合动漫图片

```dart
// 融合动漫风格图片
final result = await service.submitBlend(
  base64Array: [animeImage1, animeImage2],
  dimensions: MidjourneyDimensions.square,
  mode: MidjourneyMode.fast,
  botType: MidjourneyBotType.niji,  // 使用 Niji Bot
);
```

### 示例 4: 批量融合

```dart
final imageSets = [
  ['img1.jpg', 'img2.jpg'],
  ['img3.jpg', 'img4.jpg'],
  ['img5.jpg', 'img6.jpg'],
];

final results = <String>[];

for (final set in imageSets) {
  // 读取图片
  final images = <String>[];
  for (final path in set) {
    final bytes = await File(path).readAsBytes();
    images.add(base64Encode(bytes));
  }
  
  // 融合
  final result = await helper.blendAndWait(
    images: images,
    dimensions: MidjourneyDimensions.square,
    mode: MidjourneyMode.relax,
  );
  
  if (result.isSuccess) {
    results.add(result.data!);
  }
  
  // 避免请求过快
  await Future.delayed(Duration(seconds: 3));
}

print('批量融合完成，成功 ${results.length} 张');
```

## 在 Flutter 中使用

### 基础 Widget

```dart
class BlendImageWidget extends StatefulWidget {
  @override
  State<BlendImageWidget> createState() => _BlendImageWidgetState();
}

class _BlendImageWidgetState extends State<BlendImageWidget> {
  final _helper = MidjourneyHelper(
    MidjourneyService(ApiConfig(
      baseUrl: 'YOUR_BASE_URL',
      apiKey: 'YOUR_API_KEY',
    )),
  );

  List<String> _selectedImages = [];
  String? _blendedImageUrl;
  bool _isBlending = false;
  String _selectedDimensions = MidjourneyDimensions.square;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 选择图片按钮
        ElevatedButton(
          onPressed: _pickImages,
          child: Text('选择图片 (${_selectedImages.length}/5)'),
        ),
        
        // 显示已选图片
        if (_selectedImages.isNotEmpty)
          Wrap(
            spacing: 8,
            children: _selectedImages.map((img) {
              // 显示缩略图
              return Image.memory(
                base64Decode(img.split(',')[1]),
                width: 80,
                height: 80,
                fit: BoxFit.cover,
              );
            }).toList(),
          ),
        
        // 比例选择
        DropdownButton<String>(
          value: _selectedDimensions,
          items: [
            DropdownMenuItem(
              value: MidjourneyDimensions.portrait,
              child: Text('竖向 (2:3)'),
            ),
            DropdownMenuItem(
              value: MidjourneyDimensions.square,
              child: Text('正方形 (1:1)'),
            ),
            DropdownMenuItem(
              value: MidjourneyDimensions.landscape,
              child: Text('横向 (3:2)'),
            ),
          ],
          onChanged: (value) {
            setState(() => _selectedDimensions = value!);
          },
        ),
        
        // 融合按钮
        ElevatedButton(
          onPressed: _selectedImages.length >= 2 && !_isBlending
              ? _blendImages
              : null,
          child: Text(_isBlending ? '融合中...' : '开始融合'),
        ),
        
        // 显示结果
        if (_blendedImageUrl != null)
          Column(
            children: [
              Text('融合结果:'),
              Image.network(_blendedImageUrl!),
            ],
          ),
      ],
    );
  }

  Future<void> _pickImages() async {
    // TODO: 实现图片选择
    // 使用 image_picker 或 file_picker
  }

  Future<void> _blendImages() async {
    if (_selectedImages.length < 2 || _selectedImages.length > 5) {
      _showMessage('请选择 2-5 张图片');
      return;
    }

    setState(() => _isBlending = true);

    try {
      final result = await _helper.blendAndWait(
        images: _selectedImages,
        dimensions: _selectedDimensions,
        mode: MidjourneyMode.fast,
      );

      if (result.isSuccess) {
        setState(() => _blendedImageUrl = result.data);
        _showMessage('融合完成！');
      } else {
        _showMessage('融合失败: ${result.errorMessage}');
      }
    } finally {
      setState(() => _isBlending = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
```

### 带进度的融合

```dart
Future<void> _blendWithProgress() async {
  setState(() => _isBlending = true);
  
  // 1. 提交任务
  final submitResult = await _helper.blend(
    images: _selectedImages,
    dimensions: _selectedDimensions,
    mode: MidjourneyMode.fast,
  );
  
  if (!submitResult.isSuccess) {
    _showMessage('提交失败');
    setState(() => _isBlending = false);
    return;
  }
  
  final taskId = submitResult.data!.taskId;
  
  // 2. 定时查询进度
  final timer = Timer.periodic(Duration(seconds: 3), (timer) async {
    final status = await _helper.service.getTaskStatus(taskId: taskId);
    
    if (status.isSuccess) {
      final taskStatus = status.data!;
      
      setState(() {
        _progress = taskStatus.progress ?? 0;
      });
      
      if (taskStatus.isFinished) {
        timer.cancel();
        setState(() {
          _isBlending = false;
          _blendedImageUrl = taskStatus.imageUrl;
        });
      }
    }
  });
}
```

## 高级用法

### 1. 智能图片预处理

```dart
import 'package:image/image.dart' as img;

/// 预处理图片：调整大小和质量
Future<String> preprocessImage(String filePath) async {
  // 读取图片
  final bytes = await File(filePath).readAsBytes();
  final image = img.decodeImage(bytes);
  
  if (image == null) {
    throw Exception('无法解析图片');
  }
  
  // 调整大小（如果太大）
  final resized = image.width > 1024
      ? img.copyResize(image, width: 1024)
      : image;
  
  // 转换为 JPEG 格式
  final jpeg = img.encodeJpg(resized, quality: 85);
  
  // Base64 编码
  return base64Encode(jpeg);
}

// 使用
final images = <String>[];
for (final path in imagePaths) {
  final processed = await preprocessImage(path);
  images.add(processed);
}

final result = await helper.blend(images: images);
```

### 2. 多风格融合

```dart
/// 尝试不同比例的融合
Future<Map<String, String>> blendMultipleDimensions(
  List<String> images,
) async {
  final results = <String, String>{};
  
  // 尝试三种比例
  for (final dimension in [
    MidjourneyDimensions.portrait,
    MidjourneyDimensions.square,
    MidjourneyDimensions.landscape,
  ]) {
    final result = await helper.blendAndWait(
      images: images,
      dimensions: dimension,
      mode: MidjourneyMode.fast,
    );
    
    if (result.isSuccess) {
      results[dimension] = result.data!;
    }
    
    // 避免请求过快
    await Future.delayed(Duration(seconds: 5));
  }
  
  return results;
}
```

### 3. 渐进式融合

```dart
/// 将多张图片两两融合，再融合结果
Future<String?> progressiveBlend(List<String> images) async {
  if (images.length < 2) {
    return null;
  }
  
  // 第一轮：两两融合
  var current = <String>[];
  
  for (int i = 0; i < images.length; i += 2) {
    if (i + 1 < images.length) {
      final result = await helper.blendAndWait(
        images: [images[i], images[i + 1]],
        dimensions: MidjourneyDimensions.square,
        mode: MidjourneyMode.fast,
      );
      
      if (result.isSuccess) {
        // 下载融合后的图片并转换为 base64
        final blendedImage = await downloadAndEncode(result.data!);
        current.add(blendedImage);
      }
    } else {
      // 奇数张，保留最后一张
      current.add(images[i]);
    }
  }
  
  // 递归融合
  if (current.length > 1) {
    return progressiveBlend(current);
  } else {
    return current.first;
  }
}
```

## 实用场景

### 场景 1: 人物照片融合

```dart
// 融合两张人物照片
final portrait1 = base64Encode(await File('person1.jpg').readAsBytes());
final portrait2 = base64Encode(await File('person2.jpg').readAsBytes());

final result = await helper.blendAndWait(
  images: [portrait1, portrait2],
  dimensions: MidjourneyDimensions.portrait,  // 2:3 适合人像
  mode: MidjourneyMode.fast,
);
```

### 场景 2: 艺术风格混合

```dart
// 融合不同艺术风格的作品
final artwork1 = await loadImage('cubism.jpg');
final artwork2 = await loadImage('impressionism.jpg');
final artwork3 = await loadImage('surrealism.jpg');

final result = await helper.blend(
  images: [artwork1, artwork2, artwork3],
  dimensions: MidjourneyDimensions.landscape,
  mode: MidjourneyMode.fast,
  botType: MidjourneyBotType.midjourney,
);
```

### 场景 3: 纹理融合

```dart
// 融合多个纹理图案
final textures = <String>[];
for (int i = 1; i <= 4; i++) {
  final bytes = await File('texture$i.jpg').readAsBytes();
  textures.add(base64Encode(bytes));
}

final result = await helper.blendAndWait(
  images: textures,
  dimensions: MidjourneyDimensions.square,
  mode: MidjourneyMode.relax,
);
```

## 与其他操作结合

### Blend + Upscale

```dart
// 1. Blend 融合
final blendResult = await helper.blend(
  images: [img1, img2],
  dimensions: MidjourneyDimensions.square,
  mode: MidjourneyMode.fast,
);

final blendTaskId = blendResult.data!.taskId;

// 2. 等待 Blend 完成
await helper.pollTaskUntilComplete(taskId: blendTaskId);

// 3. Upscale 第 1 张
final upscaleResult = await helper.upscale(
  taskId: blendTaskId,
  index: 1,
  mode: MidjourneyMode.fast,
);

// 4. 获取最终高清图
final finalStatus = await helper.pollTaskUntilComplete(
  taskId: upscaleResult.data!.taskId,
);

print('最终图片: ${finalStatus.data!.imageUrl}');
```

### Blend + Variation

```dart
// 1. Blend
final blendResult = await helper.blendAndWait(
  images: [img1, img2, img3],
  dimensions: MidjourneyDimensions.landscape,
);

// 解析 taskId from URL or response
final blendTaskId = extractTaskId(blendResult.data!);

// 2. 生成融合结果的变体
final variationResult = await helper.variation(
  taskId: blendTaskId,
  index: 2,
  mode: MidjourneyMode.fast,
);

print('变体任务: ${variationResult.data!.taskId}');
```

## 错误处理

### 图片数量验证

```dart
Future<ApiResponse<MidjourneyTaskResponse>> safeBlend(
  List<String> images,
) async {
  if (images.length < 2) {
    return ApiResponse.failure('至少需要 2 张图片');
  }
  
  if (images.length > 5) {
    return ApiResponse.failure('最多支持 5 张图片');
  }
  
  return helper.blend(
    images: images,
    dimensions: MidjourneyDimensions.square,
  );
}
```

### 图片格式验证

```dart
bool isValidBase64Image(String base64String) {
  // 检查是否包含 data URI 前缀
  if (!base64String.startsWith('data:image/')) {
    return false;
  }
  
  // 检查是否是支持的格式
  final supportedFormats = ['png', 'jpeg', 'jpg', 'webp'];
  
  return supportedFormats.any((format) => 
    base64String.contains('image/$format')
  );
}

// 使用
final validImages = images.where(isValidBase64Image).toList();

if (validImages.length >= 2) {
  await helper.blend(images: validImages);
}
```

## 最佳实践

### 1. 图片预处理

```dart
// 优化图片大小和质量
Future<List<String>> optimizeImages(List<String> paths) async {
  final optimized = <String>[];
  
  for (final path in paths) {
    final bytes = await File(path).readAsBytes();
    final image = img.decodeImage(bytes);
    
    if (image != null) {
      // 限制最大尺寸
      final resized = image.width > 1024 || image.height > 1024
          ? img.copyResize(
              image,
              width: image.width > 1024 ? 1024 : null,
              height: image.height > 1024 ? 1024 : null,
            )
          : image;
      
      // 转换为 JPEG，减小文件大小
      final jpeg = img.encodeJpg(resized, quality: 85);
      optimized.add(base64Encode(jpeg));
    }
  }
  
  return optimized;
}
```

### 2. 使用合适的比例

```dart
// 根据图片内容选择比例
String selectDimensions(List<String> imagePaths) async {
  // 检查第一张图片的宽高比
  final bytes = await File(imagePaths.first).readAsBytes();
  final image = img.decodeImage(bytes);
  
  if (image == null) {
    return MidjourneyDimensions.square;
  }
  
  final ratio = image.width / image.height;
  
  if (ratio > 1.2) {
    return MidjourneyDimensions.landscape;  // 横向
  } else if (ratio < 0.8) {
    return MidjourneyDimensions.portrait;   // 竖向
  } else {
    return MidjourneyDimensions.square;     // 正方形
  }
}
```

### 3. 添加水印或标记

```dart
Future<void> blendWithWatermark(List<String> images) async {
  // 融合前添加水印或标记
  final processedImages = <String>[];
  
  for (final imgBase64 in images) {
    // 解码
    final bytes = base64Decode(imgBase64);
    final image = img.decodeImage(bytes);
    
    if (image != null) {
      // 添加水印文字
      img.drawString(image, img.arial_24, 10, 10, 'Blend Source');
      
      // 重新编码
      final encoded = base64Encode(img.encodeJpg(image));
      processedImages.add(encoded);
    }
  }
  
  // 融合
  await helper.blend(images: processedImages);
}
```

## 性能考虑

### 图片大小限制

- **建议尺寸**: 不超过 1024x1024
- **最大文件**: Base64 编码后不超过 10MB
- **格式**: JPEG, PNG, WebP

### 请求频率

```dart
class BlendRateLimiter {
  DateTime? _lastBlend;
  final _minInterval = Duration(seconds: 5);
  
  Future<void> waitIfNeeded() async {
    if (_lastBlend != null) {
      final elapsed = DateTime.now().difference(_lastBlend!);
      if (elapsed < _minInterval) {
        await Future.delayed(_minInterval - elapsed);
      }
    }
    _lastBlend = DateTime.now();
  }
}

// 使用
final limiter = BlendRateLimiter();
await limiter.waitIfNeeded();
await helper.blend(images: images);
```

## 故障排查

### 问题 1: 图片过大导致失败

**解决**: 压缩图片

```dart
Future<String> compressImage(String path) async {
  final bytes = await File(path).readAsBytes();
  final image = img.decodeImage(bytes);
  
  // 调整大小
  final resized = img.copyResize(image!, width: 512);
  
  // 降低质量
  final compressed = img.encodeJpg(resized, quality: 70);
  
  return base64Encode(compressed);
}
```

### 问题 2: Base64 格式错误

**解决**: 确保包含正确的前缀

```dart
String ensureDataUri(String base64String) {
  if (base64String.startsWith('data:image/')) {
    return base64String;
  }
  
  // 添加默认前缀
  return 'data:image/jpeg;base64,$base64String';
}
```

## 比较：Blend vs Imagine 垫图

| 特性 | Blend | Imagine + 垫图 |
|------|-------|----------------|
| **用途** | 纯粹融合图片 | 参考图片生成 |
| **文本描述** | ❌ 不需要 | ✅ 需要 |
| **图片数量** | 2-5 张 | 1-多张 |
| **控制力** | 较低 | 较高 |
| **适用场景** | 图片混合、风格融合 | 基于参考的创作 |

### 选择建议

**使用 Blend 当**:
- 想要纯粹融合多张图片
- 不需要额外的文本描述
- 探索图片混合效果

**使用 Imagine + 垫图当**:
- 需要基于参考图片创作
- 想要通过 prompt 控制结果
- 需要更精确的控制

## 完整示例：照片拼贴生成器

```dart
class PhotoCollageGenerator {
  final MidjourneyHelper helper;
  
  PhotoCollageGenerator(this.helper);
  
  /// 从多张照片生成艺术拼贴
  Future<String?> createCollage({
    required List<String> photoPaths,
    String dimensions = MidjourneyDimensions.landscape,
  }) async {
    print('📸 准备 ${photoPaths.length} 张照片...');
    
    // 1. 预处理图片
    final images = <String>[];
    for (final path in photoPaths) {
      try {
        final optimized = await preprocessImage(path);
        images.add(optimized);
      } catch (e) {
        print('⚠️ 图片处理失败: $path - $e');
      }
    }
    
    if (images.length < 2) {
      print('❌ 有效图片不足 2 张');
      return null;
    }
    
    print('✅ ${images.length} 张图片准备完成');
    
    // 2. 提交 Blend
    print('🎨 开始融合...');
    final result = await helper.blendAndWait(
      images: images,
      dimensions: dimensions,
      mode: MidjourneyMode.fast,
      maxWaitMinutes: 5,
    );
    
    if (result.isSuccess) {
      print('✅ 拼贴生成完成！');
      return result.data;
    } else {
      print('❌ 融合失败: ${result.errorMessage}');
      return null;
    }
  }
  
  Future<String> preprocessImage(String path) async {
    final bytes = await File(path).readAsBytes();
    final image = img.decodeImage(bytes)!;
    
    // 标准化大小
    final resized = img.copyResize(
      image,
      width: 768,
      height: 768,
      interpolation: img.Interpolation.average,
    );
    
    // 编码
    final jpeg = img.encodeJpg(resized, quality: 85);
    return base64Encode(jpeg);
  }
}

// 使用
final generator = PhotoCollageGenerator(helper);

final collageUrl = await generator.createCollage(
  photoPaths: [
    'vacation1.jpg',
    'vacation2.jpg',
    'vacation3.jpg',
  ],
  dimensions: MidjourneyDimensions.landscape,
);

if (collageUrl != null) {
  print('拼贴作品: $collageUrl');
}
```

## 技术规格

### API 端点

```
POST /mj/submit/blend
```

### 请求格式

```json
{
  "mode": "FAST",
  "base64Array": [
    "data:image/png;base64,xxx1",
    "data:image/png;base64,xxx2"
  ],
  "dimensions": "SQUARE",
  "botType": "mj",
  "state": "",
  "notifyhook": ""
}
```

### 响应格式

```json
{
  "code": 1,
  "description": "Submit success",
  "result": "1712204995849323"
}
```

## 常见问题

**Q: Blend 最多可以融合几张图片？**  
A: 2-5 张图片

**Q: Blend 和 Imagine 垫图有什么区别？**  
A: Blend 是纯粹的图片融合，不需要 prompt；Imagine 垫图需要 prompt 来引导生成

**Q: Blend 支持哪些比例？**  
A: PORTRAIT (2:3)、SQUARE (1:1)、LANDSCAPE (3:2)

**Q: 可以融合不同尺寸的图片吗？**  
A: 可以，建议预处理为统一尺寸以获得更好效果

**Q: Blend 的生成时间？**  
A: FAST 模式约 30-60 秒，RELAX 模式约 1-3 分钟

## 相关文档

- **Midjourney 使用指南**: `MIDJOURNEY_USAGE.md`
- **Action 操作**: `MIDJOURNEY_ACTIONS.md`
- **快速参考**: `MIDJOURNEY_QUICK_REFERENCE.md`
- **完整示例**: `examples/midjourney_example.dart`

---

**开始创作你的融合艺术作品吧！🎨✨**
