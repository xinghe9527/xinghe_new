# Gemini 图像生成服务集成指南

## 📋 概述

本项目已成功集成 Gemini 官方图像生成 API，支持文生图和图生图功能。

## ✅ 已完成的工作

### 1. 核心服务实现

创建了 `GeminiImageService` 类 (`lib/services/api/providers/gemini_image_service.dart`)，实现了：

- ✅ 完整的 API 请求封装
- ✅ 文生图功能
- ✅ 图生图功能（融合多张图片）
- ✅ 多种宽高比支持（1:1, 16:9, 9:16, 4:3, 3:4）
- ✅ 三种清晰度选择（1K, 2K, 4K）
- ✅ 安全过滤设置
- ✅ 完善的错误处理

### 2. 辅助工具类

创建了 `GeminiImageHelper` 辅助类，提供：

- 简化的文生图方法
- 简化的图生图方法
- 安全设置快速创建

### 3. 常量定义

- `ImageAspectRatio`: 宽高比常量
- `ImageQuality`: 清晰度常量

### 4. 文档和示例

- ✅ 详细的使用指南 (`GEMINI_IMAGE_USAGE.md`)
- ✅ 完整的示例代码 (`examples/gemini_image_example.dart`)
- ✅ API Factory 更新

## 🚀 快速开始

### 步骤 1: 配置 API

在你的代码中创建 API 配置：

```dart
final config = ApiConfig(
  baseUrl: 'YOUR_BASE_URL',  // 替换为你的 Base URL
  apiKey: 'YOUR_API_KEY',    // 替换为你的 API Key
  model: 'gemini-2.5-flash-image',
);
```

### 步骤 2: 创建服务实例

```dart
// 方法 1: 使用 ApiFactory
final factory = ApiFactory();
final service = factory.createService('gemini-image', config);

// 方法 2: 直接创建
final service = GeminiImageService(config);
final helper = GeminiImageHelper(service);
```

### 步骤 3: 生成图片

```dart
// 文生图
final result = await helper.textToImage(
  prompt: '一只睡觉的猫',
  ratio: ImageAspectRatio.landscape,
  quality: ImageQuality.medium,
);

if (result.isSuccess) {
  final imageUrl = result.data!.first.imageUrl;
  // 在 UI 中显示图片
  Image.network(imageUrl)
}
```

## 📁 文件结构

```
lib/
├── services/
│   └── api/
│       ├── base/
│       │   ├── api_config.dart          # API 配置类
│       │   ├── api_response.dart        # 响应封装
│       │   └── api_service_base.dart    # 服务基类
│       ├── providers/
│       │   ├── gemini_image_service.dart      # ✨ Gemini 图像服务
│       │   ├── GEMINI_IMAGE_USAGE.md          # ✨ 使用文档
│       │   ├── openai_service.dart
│       │   └── custom_service.dart
│       └── api_factory.dart             # ✨ 已更新支持 Gemini
└── examples/
    └── gemini_image_example.dart        # ✨ 完整使用示例
```

## 💡 使用场景

### 场景 1: 文生图

```dart
// 生成风景图
await helper.textToImage(
  prompt: '夕阳下的海滩，椰树摇曳',
  ratio: ImageAspectRatio.landscape,
  quality: ImageQuality.high,
);

// 生成人物肖像
await helper.textToImage(
  prompt: '一位微笑的年轻女性，专业摄影',
  ratio: ImageAspectRatio.portrait34,
  quality: ImageQuality.medium,
);
```

### 场景 2: 图生图（融合）

```dart
// 融合三张照片
final image1 = base64Encode(await File('photo1.jpg').readAsBytes());
final image2 = base64Encode(await File('photo2.jpg').readAsBytes());
final image3 = base64Encode(await File('photo3.jpg').readAsBytes());

await helper.imageToImage(
  prompt: '融合这些照片，创建一个艺术风格的图片',
  referenceImages: [image1, image2, image3],
  ratio: ImageAspectRatio.square,
  quality: ImageQuality.high,
);
```

### 场景 3: 带安全过滤

```dart
final safetySettings = helper.createSafetySettings(
  harmCategory: 'HARM_CATEGORY_DANGEROUS_CONTENT',
  threshold: 'BLOCK_MEDIUM_AND_ABOVE',
);

await service.generateImages(
  prompt: '儿童友好的卡通形象',
  parameters: safetySettings,
);
```

## 🎨 API 参数详解

### 1. 宽高比 (aspectRatio)

| 常量 | 值 | 说明 | 适用场景 |
|------|-----|------|----------|
| `ImageAspectRatio.square` | 1:1 | 正方形 | 头像、图标 |
| `ImageAspectRatio.landscape` | 16:9 | 横向宽屏 | 横幅、海报 |
| `ImageAspectRatio.portrait` | 9:16 | 竖向 | 手机壁纸 |
| `ImageAspectRatio.landscape43` | 4:3 | 横向标准 | 传统照片 |
| `ImageAspectRatio.portrait34` | 3:4 | 竖向标准 | 肖像照 |

### 2. 清晰度 (imageSize)

| 常量 | 值 | 说明 | Token 消耗 |
|------|-----|------|------------|
| `ImageQuality.low` | 1K | 标清 | 较少 |
| `ImageQuality.medium` | 2K | 高清 | 中等 |
| `ImageQuality.high` | 4K | 超清 | 较多 |

### 3. 安全类别

可选的安全类别包括：

- `HARM_CATEGORY_HARASSMENT` - 骚扰
- `HARM_CATEGORY_HATE_SPEECH` - 仇恨言论
- `HARM_CATEGORY_SEXUALLY_EXPLICIT` - 性暴露
- `HARM_CATEGORY_DANGEROUS_CONTENT` - 危险内容

### 4. 过滤阈值

- `BLOCK_NONE` - 不过滤
- `BLOCK_LOW_AND_ABOVE` - 过滤低危及以上
- `BLOCK_MEDIUM_AND_ABOVE` - 过滤中危及以上
- `BLOCK_HIGH_AND_ABOVE` - 仅过滤高危

## 📊 响应数据结构

```dart
class ImageResponse {
  final String imageUrl;      // data:image/jpeg;base64,... 格式
  final String? imageId;      // 响应 ID
  final Map<String, dynamic> metadata;
}

// metadata 包含:
{
  'mimeType': 'image/jpeg',
  'modelVersion': 'gemini-2.5-flash-image-001',
  'createTime': '2024-01-26T12:00:00Z',
  'usageMetadata': {
    'promptTokenCount': 10,
    'candidatesTokenCount': 5000,
    'totalTokenCount': 5010,
  }
}
```

## 🔧 集成到现有功能

### 在 Drawing Space 中使用

编辑 `lib/features/home/presentation/drawing_space.dart`:

```dart
import 'package:xinghe_new/services/api/providers/gemini_image_service.dart';

class DrawingSpace extends StatefulWidget {
  // ... 现有代码 ...
  
  late final GeminiImageHelper _geminiHelper;
  
  @override
  void initState() {
    super.initState();
    
    // 初始化 Gemini 服务
    final config = ApiConfig(
      baseUrl: 'YOUR_BASE_URL',
      apiKey: 'YOUR_API_KEY',
    );
    _geminiHelper = GeminiImageHelper(GeminiImageService(config));
  }
  
  // 添加生成方法
  Future<void> _generateWithGemini(String prompt) async {
    final result = await _geminiHelper.textToImage(
      prompt: prompt,
      ratio: ImageAspectRatio.landscape,
      quality: ImageQuality.medium,
    );
    
    if (result.isSuccess) {
      // 处理生成的图片
      setState(() {
        _generatedImage = result.data!.first.imageUrl;
      });
    }
  }
}
```

## 🐛 错误处理

### 常见错误及解决方案

1. **连接错误**
   ```dart
   ApiResponse.failure('连接错误: ...')
   ```
   - 检查 baseUrl 是否正确
   - 检查网络连接

2. **授权错误**
   ```dart
   statusCode: 401
   ```
   - 检查 API Key 是否正确
   - 检查 Authorization 头格式

3. **参数错误**
   ```dart
   statusCode: 400
   ```
   - 检查 prompt 是否为空
   - 检查宽高比和清晰度参数是否有效

4. **解析错误**
   ```dart
   '解析响应失败: ...'
   ```
   - 检查 API 响应格式是否符合预期
   - 查看原始响应内容进行调试

## 📝 最佳实践

### 1. 添加加载状态

```dart
bool _isGenerating = false;

Future<void> _generate() async {
  setState(() => _isGenerating = true);
  try {
    final result = await _helper.textToImage(...);
    // 处理结果
  } finally {
    setState(() => _isGenerating = false);
  }
}
```

### 2. 缓存生成结果

```dart
final _cache = <String, String>{};

Future<void> _generateWithCache(String prompt) async {
  if (_cache.containsKey(prompt)) {
    setState(() => _imageUrl = _cache[prompt]);
    return;
  }
  
  final result = await _helper.textToImage(prompt: prompt);
  if (result.isSuccess) {
    final url = result.data!.first.imageUrl;
    _cache[prompt] = url;
    setState(() => _imageUrl = url);
  }
}
```

### 3. 批量生成

```dart
Future<List<String>> _generateBatch(List<String> prompts) async {
  final results = <String>[];
  
  for (final prompt in prompts) {
    final result = await _helper.textToImage(prompt: prompt);
    if (result.isSuccess) {
      results.add(result.data!.first.imageUrl);
    }
  }
  
  return results;
}
```

## 🔐 安全建议

1. **不要硬编码 API Key**
   - 使用环境变量或安全存储
   - 参考 `secure_storage_manager.dart`

2. **添加请求限流**
   - 避免短时间内大量请求
   - 实现请求队列机制

3. **验证用户输入**
   - 过滤不当的提示词
   - 限制提示词长度

## 📦 需要的依赖

在 `pubspec.yaml` 中添加（如需要完整功能）：

```yaml
dependencies:
  http: ^1.1.0           # HTTP 请求
  image_picker: ^1.0.0   # 图片选择（可选）
  path_provider: ^2.0.0  # 文件路径（可选）
  file_saver: ^0.2.0     # 文件保存（可选）
```

## 🎯 下一步

1. 替换示例中的 `YOUR_BASE_URL` 和 `YOUR_API_KEY`
2. 运行示例代码测试功能
3. 根据需求调整参数和配置
4. 集成到你的实际业务逻辑中

## 📞 技术支持

如有问题，请参考：

- 使用文档: `lib/services/api/providers/GEMINI_IMAGE_USAGE.md`
- 示例代码: `lib/examples/gemini_image_example.dart`
- API 基类: `lib/services/api/base/api_service_base.dart`

---

**祝你使用愉快！🎨**
