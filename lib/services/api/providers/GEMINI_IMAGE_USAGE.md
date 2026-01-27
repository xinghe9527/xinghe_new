# Gemini 图像生成服务使用指南

## 概述

`GeminiImageService` 提供了对 Gemini 官方图像生成 API 的完整封装，支持：

- **文生图**：根据文本描述生成图像
- **图生图**：融合多张图片生成新图像
- 多种宽高比和清晰度选择
- 安全过滤设置

## 快速开始

### 1. 创建服务实例

```dart
import 'package:xinghe_new/services/api/providers/gemini_image_service.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';

// 创建配置
final config = ApiConfig(
  baseUrl: 'YOUR_BASE_URL',  // 例如: https://api.example.com
  apiKey: 'YOUR_API_KEY',
  model: 'gemini-2.5-flash-image',
);

// 创建服务实例
final geminiService = GeminiImageService(config);

// 创建辅助类实例（推荐使用）
final helper = GeminiImageHelper(geminiService);
```

### 2. 文生图示例

```dart
// 简单文生图
final result = await helper.textToImage(
  prompt: '一只睡觉的猫',
  ratio: ImageAspectRatio.landscape,  // 16:9
  quality: ImageQuality.low,          // 1K
);

if (result.isSuccess) {
  for (final image in result.data!) {
    print('生成的图片: ${image.imageUrl}');
    // image.imageUrl 是 data:image/jpeg;base64,... 格式
    // 可以直接在 Image.network() 中使用
  }
} else {
  print('生成失败: ${result.errorMessage}');
}
```

### 3. 图生图示例（融合多张图片）

```dart
import 'dart:convert';
import 'dart:io';

// 读取图片并转换为 Base64
Future<String> imageToBase64(String filePath) async {
  final bytes = await File(filePath).readAsBytes();
  return base64Encode(bytes);
}

// 准备参考图片
final image1Base64 = await imageToBase64('/path/to/image1.jpg');
final image2Base64 = await imageToBase64('/path/to/image2.jpg');
final image3Base64 = await imageToBase64('/path/to/image3.jpg');

// 生成融合图像
final result = await helper.imageToImage(
  prompt: '融合三张图片，输出高清图片',
  referenceImages: [image1Base64, image2Base64, image3Base64],
  ratio: ImageAspectRatio.landscape,
  quality: ImageQuality.high,  // 4K
);

if (result.isSuccess) {
  final generatedImage = result.data!.first;
  print('融合后的图片: ${generatedImage.imageUrl}');
}
```

### 4. 使用安全过滤

```dart
// 创建安全设置
final safetySettings = helper.createSafetySettings(
  harmCategory: 'HARM_CATEGORY_DANGEROUS_CONTENT',
  threshold: 'BLOCK_MEDIUM_AND_ABOVE',
);

// 使用原始 service 方法并传入安全设置
final result = await geminiService.generateImages(
  prompt: '一只可爱的小狗',
  ratio: ImageAspectRatio.square,
  quality: ImageQuality.medium,
  parameters: safetySettings,
);
```

## API 参数说明

### 宽高比 (AspectRatio)

使用 `ImageAspectRatio` 类中的常量：

- `ImageAspectRatio.square` - 1:1 (正方形)
- `ImageAspectRatio.landscape` - 16:9 (横向)
- `ImageAspectRatio.portrait` - 9:16 (竖向)
- `ImageAspectRatio.landscape43` - 4:3 (横向)
- `ImageAspectRatio.portrait34` - 3:4 (竖向)

### 图像清晰度 (ImageSize)

使用 `ImageQuality` 类中的常量：

- `ImageQuality.low` - 1K
- `ImageQuality.medium` - 2K
- `ImageQuality.high` - 4K

## 响应数据结构

### ImageResponse

```dart
class ImageResponse {
  final String imageUrl;      // 图片 URL (data:image/jpeg;base64,...)
  final String? imageId;      // 响应 ID
  final Map<String, dynamic> metadata;  // 元数据
}
```

### 元数据包含

- `mimeType`: 图片类型 (image/jpeg)
- `modelVersion`: 使用的模型版本
- `createTime`: 创建时间
- `usageMetadata`: Token 使用情况
  - `promptTokenCount`: 提示词 Token 数
  - `candidatesTokenCount`: 生成内容 Token 数
  - `totalTokenCount`: 总 Token 数

## 在 Flutter Widget 中使用

```dart
class ImageGeneratorWidget extends StatefulWidget {
  @override
  State<ImageGeneratorWidget> createState() => _ImageGeneratorWidgetState();
}

class _ImageGeneratorWidgetState extends State<ImageGeneratorWidget> {
  final _helper = GeminiImageHelper(
    GeminiImageService(
      ApiConfig(
        baseUrl: 'YOUR_BASE_URL',
        apiKey: 'YOUR_API_KEY',
      ),
    ),
  );
  
  String? _generatedImageUrl;
  bool _isGenerating = false;

  Future<void> _generateImage() async {
    setState(() => _isGenerating = true);
    
    try {
      final result = await _helper.textToImage(
        prompt: '一只可爱的猫咪',
        ratio: ImageAspectRatio.square,
        quality: ImageQuality.medium,
      );
      
      if (result.isSuccess && result.data!.isNotEmpty) {
        setState(() {
          _generatedImageUrl = result.data!.first.imageUrl;
        });
      } else {
        _showError(result.errorMessage ?? '生成失败');
      }
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: _isGenerating ? null : _generateImage,
          child: Text(_isGenerating ? '生成中...' : '生成图片'),
        ),
        if (_generatedImageUrl != null)
          Image.network(_generatedImageUrl!),
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

服务会返回 `ApiResponse` 对象，包含：

- `isSuccess`: 是否成功
- `data`: 返回数据（成功时）
- `errorMessage`: 错误消息（失败时）
- `statusCode`: HTTP 状态码

```dart
final result = await helper.textToImage(prompt: '测试');

if (result.isSuccess) {
  // 处理成功情况
  final images = result.data!;
  for (final img in images) {
    print('生成图片: ${img.imageUrl}');
  }
} else {
  // 处理错误情况
  print('错误: ${result.errorMessage}');
  print('状态码: ${result.statusCode}');
}
```

## 注意事项

1. **Base64 编码**：参考图片必须先转换为 Base64 编码格式
2. **图片大小限制**：注意 API 对图片大小的限制
3. **Token 消耗**：图像生成会消耗较多 Token，请注意配额
4. **超时处理**：图像生成可能需要较长时间，建议设置合理的超时时间
5. **图片格式**：生成的图片为 data URL 格式，可直接在 Image.network() 中使用

## 支持的模型

- `gemini-2.5-flash-image` (推荐)
- `gemini-2.0-flash-exp-image`

## 完整示例项目

查看项目中的 `drawing_space.dart` 了解如何在实际应用中集成此服务。
