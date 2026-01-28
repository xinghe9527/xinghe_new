# Gemini 3 Pro 图像生成服务使用指南

## 概述

`GeminiProImageService` 是用于调用云雾 API 的 `gemini-3-pro-image-preview` 模型的服务类。该服务支持:

- ✅ 文本生图(Text-to-Image)
- ✅ 图生图(Image-to-Image)
- ✅ 自定义宽高比
- ✅ 可调节清晰度
- ✅ 多图参考生成

## 快速开始

### 1. 创建服务实例

```dart
import 'package:xinghe_new/services/api/base/api_config.dart';
import 'package:xinghe_new/services/api/providers/gemini_pro_image_service.dart';

// 创建 API 配置
final config = ApiConfig(
  provider: 'yunwu',
  apiKey: 'YOUR_API_KEY',  // 替换为您的 API Key
  baseUrl: 'https://yunwu.ai',
  model: 'gemini-3-pro-image-preview',
);

// 创建服务实例
final service = GeminiProImageService(config);
```

### 2. 基础文本生图

```dart
// 简单的文本生图
final result = await service.generateImages(
  prompt: 'A beautiful sunset over the ocean',
);

if (result.isSuccess && result.data != null) {
  for (final image in result.data!) {
    final base64Data = image.base64Data;
    // 使用 base64 数据显示图片
    print('生成了一张图片,大小: ${base64Data?.length ?? 0} bytes');
  }
} else {
  print('生成失败: ${result.error}');
}
```

### 3. 带参数的图片生成

```dart
// 使用自定义宽高比和清晰度
final result = await service.generateImages(
  prompt: 'A cute cat playing with a ball',
  ratio: '16:9',      // 横屏比例
  quality: '2K',      // 中等清晰度
);
```

## 详细功能

### 支持的宽高比

| 比例 | 说明 | 适用场景 |
|------|------|----------|
| `1:1` | 正方形 | 社交媒体头像、图标 |
| `3:4` | 竖版 | 海报、手机壁纸 |
| `4:3` | 横版 | 电脑壁纸、PPT |
| `9:16` | 手机竖屏 | 手机全屏显示、短视频封面 |
| `16:9` | 手机横屏 | 视频封面、横屏显示 |

```dart
// 示例:生成手机竖屏壁纸
final result = await service.generateImages(
  prompt: 'Minimalist mountain landscape wallpaper',
  ratio: '9:16',
  quality: '4K',
);
```

### 支持的图片尺寸

| 尺寸 | 说明 | 适用场景 |
|------|------|----------|
| `1K` | 低分辨率 | 预览、快速生成 |
| `2K` | 中分辨率 | 一般用途、社交媒体 |
| `4K` | 高分辨率 | 打印、专业用途 |

```dart
// 示例:生成高清图片
final result = await service.generateImages(
  prompt: 'Professional product photography',
  quality: '4K',
);
```

### 图生图(参考图片生成)

```dart
// 使用参考图片生成新图片
final result = await service.generateImages(
  prompt: 'Add a llama next to me',
  referenceImages: [
    '/path/to/reference/image.jpg',
    '/path/to/another/image.png',
  ],
  ratio: '1:1',
);
```

**注意**:
- 参考图片会自动转换为 Base64 编码
- 支持的格式: JPG, PNG, GIF, WEBP
- 图片文件必须存在且可读

## 完整示例

### 示例 1: 在 Flutter Widget 中使用

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';
import 'package:xinghe_new/services/api/providers/gemini_pro_image_service.dart';

class ImageGenerationDemo extends StatefulWidget {
  @override
  _ImageGenerationDemoState createState() => _ImageGenerationDemoState();
}

class _ImageGenerationDemoState extends State<ImageGenerationDemo> {
  GeminiProImageService? _service;
  String? _generatedImageBase64;
  bool _isLoading = false;
  
  @override
  void initState() {
    super.initState();
    _initService();
  }
  
  void _initService() {
    final config = ApiConfig(
      provider: 'yunwu',
      apiKey: 'YOUR_API_KEY',
      baseUrl: 'https://yunwu.ai',
      model: 'gemini-3-pro-image-preview',
    );
    _service = GeminiProImageService(config);
  }
  
  Future<void> _generateImage() async {
    if (_service == null) return;
    
    setState(() {
      _isLoading = true;
      _generatedImageBase64 = null;
    });
    
    try {
      final result = await _service!.generateImages(
        prompt: 'A beautiful landscape with mountains and a lake',
        ratio: '16:9',
        quality: '2K',
      );
      
      if (result.isSuccess && result.data != null && result.data!.isNotEmpty) {
        setState(() {
          _generatedImageBase64 = result.data!.first.base64Data;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败: ${result.error}')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Gemini 3 Pro 图片生成')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isLoading)
              CircularProgressIndicator()
            else if (_generatedImageBase64 != null)
              Image.memory(
                base64Decode(_generatedImageBase64!),
                fit: BoxFit.contain,
              )
            else
              Text('点击按钮生成图片'),
            
            SizedBox(height: 20),
            
            ElevatedButton(
              onPressed: _isLoading ? null : _generateImage,
              child: Text('生成图片'),
            ),
          ],
        ),
      ),
    );
  }
}
```

### 示例 2: 批量生成不同比例的图片

```dart
Future<void> generateMultipleRatios() async {
  final service = GeminiProImageService(config);
  
  final ratios = ['1:1', '16:9', '9:16'];
  final prompt = 'A serene Japanese garden';
  
  for (final ratio in ratios) {
    print('生成 $ratio 比例的图片...');
    
    final result = await service.generateImages(
      prompt: prompt,
      ratio: ratio,
      quality: '2K',
    );
    
    if (result.isSuccess && result.data != null) {
      // 保存或显示图片
      print('$ratio 图片生成成功');
    } else {
      print('$ratio 图片生成失败: ${result.error}');
    }
  }
}
```

### 示例 3: 带错误处理的完整流程

```dart
Future<void> generateImageWithErrorHandling({
  required String prompt,
  String? ratio,
  String? quality,
  List<String>? referenceImages,
}) async {
  final service = GeminiProImageService(config);
  
  // 1. 测试连接
  final connectionTest = await service.testConnection();
  if (!connectionTest.isSuccess) {
    print('API 连接失败');
    return;
  }
  
  // 2. 验证参数
  if (ratio != null && !GeminiProImageService.supportedAspectRatios.contains(ratio)) {
    print('不支持的宽高比: $ratio');
    return;
  }
  
  if (quality != null && !GeminiProImageService.supportedImageSizes.contains(quality)) {
    print('不支持的图片尺寸: $quality');
    return;
  }
  
  // 3. 生成图片
  try {
    final result = await service.generateImages(
      prompt: prompt,
      ratio: ratio,
      quality: quality,
      referenceImages: referenceImages,
    );
    
    if (result.isSuccess && result.data != null) {
      for (final image in result.data!) {
        print('生成成功!');
        print('完成原因: ${image.finishReason}');
        print('安全评级: ${image.safetyRatings}');
        print('图片大小: ${image.base64Data?.length ?? 0} bytes');
        
        // 这里可以保存或显示图片
        // saveImageToFile(image.base64Data, 'output.jpg');
      }
    } else {
      print('生成失败: ${result.error}');
    }
  } catch (e) {
    print('发生异常: $e');
  }
}
```

## 响应数据结构

```dart
// 成功响应
ApiResponse<List<ImageResponse>> {
  isSuccess: true,
  data: [
    ImageResponse {
      url: '',  // Gemini 返回 base64,不是 URL
      metadata: {
        'base64Data': '...',  // Base64 编码的图片数据
        'mimeType': 'image/jpeg',
        'finishReason': 'STOP',
        'safetyRatings': [...],
      }
    }
  ],
  error: null,
  statusCode: 200,
}

// 失败响应
ApiResponse<List<ImageResponse>> {
  isSuccess: false,
  data: null,
  error: '错误信息',
  statusCode: 400,
}
```

## 最佳实践

### 1. API Key 安全

```dart
// ❌ 不要硬编码 API Key
final config = ApiConfig(
  apiKey: 'sk-xxxxx',  // 不要这样做!
  // ...
);

// ✅ 使用环境变量或安全存储
import 'package:flutter_dotenv/flutter_dotenv.dart';
final apiKey = dotenv.env['YUNWU_API_KEY'] ?? '';

// 或使用 SecureStorage
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
final storage = FlutterSecureStorage();
final apiKey = await storage.read(key: 'yunwu_api_key');
```

### 2. 错误处理

```dart
// 始终检查结果
final result = await service.generateImages(prompt: prompt);

if (result.isSuccess) {
  // 处理成功情况
} else {
  // 处理错误
  print('Error: ${result.error}');
  print('Status Code: ${result.statusCode}');
}
```

### 3. 图片保存

```dart
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

Future<void> saveGeneratedImage(String base64Data, String filename) async {
  final bytes = base64Decode(base64Data);
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/$filename');
  await file.writeAsBytes(bytes);
  print('图片已保存到: ${file.path}');
}
```

## 注意事项

1. **API Key**: 需要有效的云雾 API Key
2. **Base64 数据**: 返回的是 Base64 编码的图片数据,不是 URL
3. **图片格式**: 通常返回 JPEG 格式
4. **文件大小**: 4K 图片的 Base64 数据可能很大,注意内存使用
5. **参考图片**: 参考图片会被编码为 Base64 包含在请求中,注意请求大小限制
6. **安全评级**: 检查 `safetyRatings` 以确保内容安全

## 故障排除

### 问题 1: 连接失败

```dart
// 检查 baseUrl 是否正确
final config = ApiConfig(
  baseUrl: 'https://yunwu.ai',  // 确保是正确的 URL
  // ...
);
```

### 问题 2: 401 未授权

```dart
// 检查 API Key 是否有效
final connectionTest = await service.testConnection();
print('连接状态: ${connectionTest.isSuccess}');
```

### 问题 3: 图片无法显示

```dart
// 确保 Base64 数据正确解码
try {
  final bytes = base64Decode(base64Data);
  Image.memory(bytes);
} catch (e) {
  print('Base64 解码失败: $e');
}
```

### 问题 4: 参考图片加载失败

```dart
// 检查文件路径是否存在
import 'dart:io';

final file = File(imagePath);
if (!file.existsSync()) {
  print('文件不存在: $imagePath');
}
```

## 相关文档

- [API 基础配置](../base/api_config.dart)
- [API 响应类型](../base/api_response.dart)
- [服务基类](../base/api_service_base.dart)

## 更新日志

- **v1.0.0** (2026-01-26): 初始版本
  - 支持文本生图
  - 支持图生图
  - 支持自定义宽高比和清晰度
