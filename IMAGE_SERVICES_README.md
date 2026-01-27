# 图像生成服务集成总览

本项目已集成多个主流图像生成 API 服务，提供统一的接口和丰富的功能。

## 🎨 已集成的服务

### 1. Gemini Image (Google)

**特点**: 快速、同步、支持多模态

```dart
final helper = GeminiImageHelper(GeminiImageService(config));

// 文生图
final result = await helper.textToImage(
  prompt: '一只睡觉的猫',
  ratio: ImageAspectRatio.landscape,
  quality: ImageQuality.medium,
);

// 图生图
final result = await helper.imageToImage(
  prompt: '融合三张图片',
  referenceImages: [img1, img2, img3],
  ratio: ImageAspectRatio.square,
  quality: ImageQuality.high,
);
```

📚 **文档**:
- 使用指南: [`lib/services/api/providers/GEMINI_IMAGE_USAGE.md`](lib/services/api/providers/GEMINI_IMAGE_USAGE.md)
- 集成指南: [`GEMINI_IMAGE_INTEGRATION.md`](GEMINI_IMAGE_INTEGRATION.md)
- 示例代码: [`lib/examples/gemini_image_example.dart`](lib/examples/gemini_image_example.dart)

---

### 2. Midjourney

**特点**: 高质量、艺术风格、强大的参数控制

```dart
final helper = MidjourneyHelper(MidjourneyService(config));

// 文生图（提交并等待）
final result = await helper.submitAndWait(
  prompt: 'Beautiful landscape --ar 16:9 --v 6 --q 2.0',
  mode: MidjourneyMode.fast,
);

// 使用 Prompt 构建器
final prompt = MidjourneyPromptBuilder()
  .withDescription('Cyberpunk city')
  .withAspectRatio('16:9')
  .withVersion('6')
  .withQuality(2.0)
  .withStylize(750)
  .build();

final result = await helper.submitAndWait(prompt: prompt);

// Action 操作
// Upscale: 放大第 2 张图片
await helper.upscale(taskId: taskId, index: 2);

// Variation: 生成第 1 张的变体
await helper.variation(taskId: taskId, index: 1);

// Reroll: 重新生成
await helper.reroll(taskId: taskId);

// Blend: 融合图片
await helper.blendAndWait(
  images: [img1, img2, img3],
  dimensions: MidjourneyDimensions.square,
);
```

📚 **文档**:
- 使用指南: [`lib/services/api/providers/MIDJOURNEY_USAGE.md`](lib/services/api/providers/MIDJOURNEY_USAGE.md)
- Action 操作: [`lib/services/api/providers/MIDJOURNEY_ACTIONS.md`](lib/services/api/providers/MIDJOURNEY_ACTIONS.md)
- Blend 融图: [`lib/services/api/providers/MIDJOURNEY_BLEND.md`](lib/services/api/providers/MIDJOURNEY_BLEND.md)
- Modal 补充: [`lib/services/api/providers/MIDJOURNEY_MODAL.md`](lib/services/api/providers/MIDJOURNEY_MODAL.md)
- Describe 图生文: [`lib/services/api/providers/MIDJOURNEY_DESCRIBE.md`](lib/services/api/providers/MIDJOURNEY_DESCRIBE.md)
- Shorten 优化: [`lib/services/api/providers/MIDJOURNEY_SHORTEN.md`](lib/services/api/providers/MIDJOURNEY_SHORTEN.md)
- SwapFace 换脸: [`lib/services/api/providers/MIDJOURNEY_SWAPFACE.md`](lib/services/api/providers/MIDJOURNEY_SWAPFACE.md)
- 集成指南: [`MIDJOURNEY_INTEGRATION.md`](MIDJOURNEY_INTEGRATION.md)
- 示例代码: [`lib/examples/midjourney_example.dart`](lib/examples/midjourney_example.dart)

---

### 3. OpenAI DALL-E (已有基础实现)

**特点**: 稳定、易用、快速

```dart
final service = OpenAIService(config);

final result = await service.generateImages(
  prompt: 'A white siamese cat',
  count: 1,
);
```

📚 **文档**: 
- 实现: [`lib/services/api/providers/openai_service.dart`](lib/services/api/providers/openai_service.dart)

---

## 📊 服务对比

| 特性 | Gemini Image | Midjourney | OpenAI DALL-E |
|------|-------------|------------|---------------|
| **响应方式** | 同步 | 异步任务 | 同步 |
| **响应时间** | 3-10秒 | 1-3分钟 | 10-30秒 |
| **图像质量** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| **风格控制** | 一般 | 极强 | 中等 |
| **参数丰富度** | 简单 | 丰富 | 中等 |
| **垫图支持** | ✅ | ✅ | ✅ |
| **计费方式** | Token | 订阅 | Token |
| **最佳场景** | 快速原型 | 艺术创作 | 通用场景 |

## 🏗️ 统一架构

所有服务都基于统一的架构：

```
ApiServiceBase (抽象基类)
    ├── GeminiImageService
    ├── MidjourneyService
    ├── OpenAIService
    └── CustomApiService (模板)
```

### 核心接口

```dart
abstract class ApiServiceBase {
  // 通用方法
  Future<ApiResponse<bool>> testConnection();
  Future<ApiResponse<List<ImageResponse>>> generateImages({...});
  Future<ApiResponse<List<String>>> getAvailableModels({...});
  
  // ... 其他方法
}
```

### 统一的响应格式

```dart
class ApiResponse<T> {
  final bool isSuccess;
  final T? data;
  final String? errorMessage;
  final int? statusCode;
}
```

## 🔧 使用 API Factory

通过工厂模式统一创建服务：

```dart
import 'package:xinghe_new/services/api/api_factory.dart';

final factory = ApiFactory();

// 创建 Gemini 服务
final geminiService = factory.createService('gemini-image', geminiConfig);

// 创建 Midjourney 服务
final mjService = factory.createService('midjourney', mjConfig);

// 创建 OpenAI 服务
final openaiService = factory.createService('openai', openaiConfig);

// 检查是否完全支持
factory.isFullySupported('midjourney');  // true
```

## 📖 快速参考

### Gemini Image

```dart
// 配置
final config = ApiConfig(
  baseUrl: 'YOUR_BASE_URL',
  apiKey: 'YOUR_API_KEY',
  model: 'gemini-2.5-flash-image',
);

// 使用
final helper = GeminiImageHelper(GeminiImageService(config));
final result = await helper.textToImage(
  prompt: 'A cat',
  ratio: ImageAspectRatio.landscape,  // 16:9
  quality: ImageQuality.medium,       // 2K
);
```

### Midjourney

```dart
// 配置
final config = ApiConfig(
  baseUrl: 'YOUR_BASE_URL',
  apiKey: 'YOUR_API_KEY',
);

// 使用
final helper = MidjourneyHelper(MidjourneyService(config));
final result = await helper.submitAndWait(
  prompt: 'Beautiful sunset --ar 16:9 --v 6',
  mode: MidjourneyMode.fast,
);
```

## 🎯 选择合适的服务

### 使用 Gemini Image 当：
- ✅ 需要快速响应（秒级）
- ✅ 进行原型开发
- ✅ 批量生成大量图片
- ✅ 预算有限（按 Token 计费）
- ✅ 需要简单易用的接口

### 使用 Midjourney 当：
- ✅ 追求极致的图像质量
- ✅ 需要丰富的艺术风格
- ✅ 进行专业设计创作
- ✅ 需要精细的参数控制
- ✅ 可以接受较长等待时间

### 使用 OpenAI DALL-E 当：
- ✅ 需要稳定可靠的服务
- ✅ 进行通用图像生成
- ✅ 与 GPT 等服务配合使用

## 🔌 扩展开发

### 添加新的图像服务

1. 创建新的服务类：

```dart
class NewImageService extends ApiServiceBase {
  NewImageService(super.config);
  
  @override
  String get providerName => 'NewService';
  
  // 实现抽象方法...
}
```

2. 更新 API Factory：

```dart
case 'new-service':
  return NewImageService(config);
```

3. 创建使用文档和示例

### 实现更多 Midjourney 功能

可以扩展 `MidjourneyService` 添加：

- Upscale 操作
- Variation 操作
- Pan 操作
- Zoom 操作
- Describe 操作

## 📞 技术支持

### 文档索引

- **Gemini 使用**: [`GEMINI_IMAGE_USAGE.md`](lib/services/api/providers/GEMINI_IMAGE_USAGE.md)
- **Midjourney 使用**: [`MIDJOURNEY_USAGE.md`](lib/services/api/providers/MIDJOURNEY_USAGE.md)
- **API 架构**: [`lib/services/api/README.md`](lib/services/api/README.md)

### 示例代码

- **Gemini 示例**: [`gemini_image_example.dart`](lib/examples/gemini_image_example.dart)
- **Midjourney 示例**: [`midjourney_example.dart`](lib/examples/midjourney_example.dart)

### 核心类

- **基类**: `ApiServiceBase`
- **配置**: `ApiConfig`
- **响应**: `ApiResponse<T>`
- **工厂**: `ApiFactory`

## 🎉 总结

现在你的项目拥有：

- ✅ **2个完整的图像生成服务** (Gemini + Midjourney)
- ✅ **统一的服务架构**
- ✅ **详细的文档和示例**
- ✅ **辅助工具类**（Helper、PromptBuilder）
- ✅ **完善的错误处理**
- ✅ **可扩展的设计**

可以根据不同场景选择最合适的服务，开始创造精美的 AI 图像！🚀

---

**版本**: 1.0.0  
**更新时间**: 2024-01-26  
**维护者**: Your Team
