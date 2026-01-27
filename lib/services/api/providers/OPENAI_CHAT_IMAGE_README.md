# OpenAI 对话格式生图 API

## 📝 概述

本模块为 OpenAI 的对话格式图像生成 API（`/v1/chat/completions`）提供了完整的 Flutter/Dart 实现。这是一个强大的图像生成接口，使用类似 ChatGPT 的对话方式来生成和编辑图像。

## ✨ 主要特性

- ✅ **文生图（Text-to-Image）** - 通过文本描述生成图像
- ✅ **图生图（Image-to-Image）** - 基于参考图片生成新图像
- ✅ **多图融合** - 融合多张图片的风格和元素
- ✅ **风格转换** - 将图片转换为不同艺术风格
- ✅ **图片增强** - 优化图片质量和细节
- ✅ **对话式生成** - 通过多轮对话逐步完善图像
- ✅ **批量生成** - 一次请求生成多张图片
- ✅ **完整参数支持** - temperature, top_p, max_tokens 等

## 📦 包含内容

### 1. 核心服务类

**`OpenAIService`** (openai_service.dart)
- `generateImagesByChat()` - 主要的图像生成方法
- 完整的参数支持
- 类型安全的数据模型

### 2. 辅助类

**`OpenAIChatImageHelper`** (openai_service.dart)
提供简化的 API，适合大多数场景：
- `textToImage()` - 简单文生图
- `imageToImage()` - 简单图生图
- `styleTransfer()` - 风格转换
- `multiImageBlend()` - 多图融合
- `generateMultiple()` - 批量生成
- `enhanceImage()` - 图片增强
- `createVariations()` - 创意变体
- `blendConcepts()` - 概念混合
- `reimagineScene()` - 场景重构
- `artistStyleImitation()` - 艺术家风格模仿

### 3. 数据模型

**请求模型：**
- `ChatMessage` - 聊天消息
- `ChatMessageContent` - 消息内容（文本/图片）
- `ChatImageUrl` - 图片 URL 包装

**响应模型：**
- `ChatImageResponse` - 完整的响应对象
- `ChatImageChoice` - 单个生成选择项
- `ChatImageUsage` - Token 使用统计

### 4. 文档

- **OPENAI_CHAT_IMAGE_USAGE.md** - 详细使用指南
  - 快速开始
  - Helper 类使用示例
  - 高级用法
  - 完整 API 参考
  - FAQ 常见问题
  - 故障排查

### 5. 示例代码

- **examples/openai_chat_image_example.dart** - 完整的实际使用示例
  - 7 个详细示例
  - 实用的辅助函数
  - 错误处理最佳实践

## 🚀 快速开始

### 基础用法

```dart
// 1. 创建服务实例
final config = ApiConfig(
  baseUrl: 'https://your-api-base-url.com',
  apiKey: 'your-api-key',
  model: 'gpt-4o',
);

final service = OpenAIService(config);
final helper = OpenAIChatImageHelper(service);

// 2. 生成图片
final imageUrl = await helper.textToImage(
  prompt: '一只可爱的小猫在花园里玩耍',
);

print('生成的图片: $imageUrl');
```

### 图生图

```dart
final imageUrl = await helper.imageToImage(
  imagePath: '/path/to/photo.jpg',
  prompt: '转换成油画风格',
);
```

### 风格转换

```dart
final imageUrl = await helper.styleTransfer(
  imagePath: '/path/to/photo.jpg',
  targetStyle: '水彩画',
  keepComposition: true,
);
```

## 📚 支持的模型

- `gpt-4o` - GPT-4 Omni（推荐）
- `gpt-4-turbo`
- `dall-e-3` - DALL-E 3
- `dall-e-2` - DALL-E 2

## 🔧 高级功能

### 对话式生成

```dart
final conversationHistory = <ChatMessage>[];

// 第一轮
conversationHistory.add(ChatMessage(
  role: 'user',
  content: [ChatMessageContent.text(text: '生成一座城市')],
));

var result = await service.generateImagesByChat(
  messages: conversationHistory,
);

// 第二轮：基于第一轮结果继续
conversationHistory.add(result.data!.choices.first.message);
conversationHistory.add(ChatMessage(
  role: 'user',
  content: [ChatMessageContent.text(text: '添加飞行汽车')],
));

result = await service.generateImagesByChat(
  messages: conversationHistory,
);
```

### 完整参数控制

```dart
final result = await service.generateImagesByChat(
  prompt: '科幻场景',
  model: 'gpt-4o',
  parameters: {
    'temperature': 0.8,
    'top_p': 0.95,
    'n': 3,  // 生成3张
    'max_tokens': 1000,
  },
);

// 访问详细信息
print('Token使用: ${result.data!.usage?.totalTokens}');
print('生成的图片: ${result.data!.imageUrls}');
```

## 📖 详细文档

完整使用指南请参阅：
- [OPENAI_CHAT_IMAGE_USAGE.md](./OPENAI_CHAT_IMAGE_USAGE.md) - 详细使用文档
- [examples/openai_chat_image_example.dart](../../../examples/openai_chat_image_example.dart) - 实际代码示例

## 🔑 关键特点

1. **类型安全** - 完整的 Dart 类型定义，编译时错误检查
2. **易于使用** - Helper 类提供简化的 API
3. **灵活强大** - 直接 API 提供完全控制
4. **完整文档** - 详细的文档和示例
5. **错误处理** - 健壮的错误处理机制
6. **异步支持** - 完全异步，不阻塞 UI

## 💡 使用建议

### 何时使用 Helper 类？
- ✅ 快速原型开发
- ✅ 简单的图像生成任务
- ✅ 不需要详细响应信息

### 何时使用直接 API？
- ✅ 需要访问完整响应数据
- ✅ 实现对话式交互
- ✅ 需要精细控制所有参数
- ✅ 需要 Token 使用统计

## 🎯 典型应用场景

1. **内容创作平台** - 为用户提供图像生成功能
2. **设计工具** - 风格转换、图片增强
3. **艺术创作** - 艺术风格模仿、概念混合
4. **电商应用** - 产品图片优化、场景重构
5. **社交媒体** - 滤镜效果、创意编辑
6. **游戏开发** - 资源生成、概念设计

## ⚠️ 注意事项

1. **API 配额** - 注意 API 调用限制和成本
2. **图片大小** - 大图片会消耗更多 tokens
3. **URL 时效** - 及时下载保存重要图片
4. **错误处理** - 始终检查 `isSuccess` 和处理错误
5. **网络超时** - 图像生成可能需要较长时间

## 🔄 版本历史

### v1.0.0 (2026-01-26)
- ✨ 初始版本
- ✨ 实现完整的对话格式图像生成 API
- ✨ 添加 `OpenAIChatImageHelper` 辅助类
- ✨ 完整的数据模型和类型定义
- ✨ 详细的使用文档和示例

## 📞 支持

如有问题或建议，请参考：
- 详细文档：[OPENAI_CHAT_IMAGE_USAGE.md](./OPENAI_CHAT_IMAGE_USAGE.md)
- 示例代码：[openai_chat_image_example.dart](../../../examples/openai_chat_image_example.dart)
- FAQ 部分：[常见问题解答](./OPENAI_CHAT_IMAGE_USAGE.md#常见问题faq)

## 📄 许可

本项目的许可信息请参考项目根目录的 LICENSE 文件。
