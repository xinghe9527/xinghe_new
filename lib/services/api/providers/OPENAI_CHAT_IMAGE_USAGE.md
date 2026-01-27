# GeekNow 图像生成服务使用指南

## ⚠️ 重要说明：服务商架构

本指南介绍如何使用 **GeekNow 服务**的**图像生成功能**。

**GeekNow** 是一个统一的 AI API Gateway，它集成了多种图像生成模型：
- 本指南涉及的所有模型（gpt-4o、dall-e-3 等）都是**通过 GeekNow 的统一接口访问**
- 您只需要**一个 GeekNow API Key**
- 所有请求都发送到 **GeekNow 的服务器**
- GeekNow 内部会路由到相应的 AI 模型

⚠️ **注意**：虽然模型名称如 "gpt-4o"、"dall-e-3" 等与 OpenAI 的模型名称相同，但这些是 GeekNow 提供的模型访问，而不是直接连接到 OpenAI。

## 概述

GeekNow 图像生成服务使用 `/v1/chat/completions` 端点，通过对话接口进行图像生成。支持：

- **文生图（Text-to-Image）**：通过文本提示词生成图像
- **图生图（Image-to-Image）**：基于参考图片和文本提示词生成新图像

## GeekNow 提供的图像模型

- `gpt-4o` - GPT-4 Omni（推荐，通过 GeekNow 访问）
- `gpt-4-turbo` - GPT-4 Turbo（通过 GeekNow 访问）
- `dall-e-3` - DALL-E 3（通过 GeekNow 访问）
- `dall-e-2` - DALL-E 2（通过 GeekNow 访问）

## 快速开始

### 1. 创建服务实例

```dart
import 'package:your_project/services/api/providers/geeknow_service.dart';
// 或使用现有的：import 'package:your_project/services/api/providers/openai_service.dart';
import 'package:your_project/services/api/base/api_config.dart';

// 配置 GeekNow 服务
final config = ApiConfig(
  baseUrl: 'https://your-geeknow-api.com',  // GeekNow API 地址
  apiKey: 'your-geeknow-api-key',           // GeekNow API Key
  model: 'gpt-4o',  // 默认模型
);

// 创建 GeekNow 服务实例
final geekNowService = GeekNowService(config);
// 或使用现有实现：final geekNowService = OpenAIService(config);

// 创建辅助类实例（推荐用于简单任务）
final helper = OpenAIChatImageHelper(geekNowService);
```

**重要**：`OpenAIService` 实际上是 GeekNow 图像服务的实现，未来将重命名为 `GeekNowImageService`。

### 2. 文生图（Text-to-Image）

最简单的使用方式，只需提供文本提示词：

```dart
// 基础文生图
final result = await openAIService.generateImagesByChat(
  prompt: '一只可爱的卡通猫咪，坐在彩虹上，星空背景',
  model: 'gpt-4o',
);

if (result.isSuccess) {
  final response = result.data!;
  print('生成的图片URL: ${response.firstImageUrl}');
  
  // 获取所有图片URL
  for (final url in response.imageUrls) {
    print('图片: $url');
  }
} else {
  print('生成失败: ${result.errorMessage}');
}
```

### 3. 图生图（Image-to-Image）

基于参考图片和文本提示词生成新图像：

```dart
// 图生图 - 提供参考图片路径
final result = await openAIService.generateImagesByChat(
  prompt: '将这张图片转换成油画风格，增强色彩饱和度',
  referenceImagePaths: [
    '/path/to/reference/image1.jpg',
    '/path/to/reference/image2.png',
  ],
  model: 'gpt-4o',
);

if (result.isSuccess) {
  final response = result.data!;
  print('生成的图片: ${response.firstImageUrl}');
  print('使用的模型: ${response.model}');
  print('Token 使用: ${response.usage?.totalTokens}');
} else {
  print('生成失败: ${result.errorMessage}');
}
```

## 使用 Helper 类（推荐）

`OpenAIChatImageHelper` 提供了简化的 API，适合大多数常见场景。

### 1. 简单文生图

```dart
final helper = OpenAIChatImageHelper(openAIService);

// 最简单的用法
final imageUrl = await helper.textToImage(
  prompt: '一只可爱的小狗在草地上玩耍',
);

if (imageUrl != null) {
  print('生成的图片: $imageUrl');
}
```

### 2. 简单图生图

```dart
final imageUrl = await helper.imageToImage(
  imagePath: '/path/to/image.jpg',
  prompt: '将图片转换成卡通风格',
);
```

### 3. 风格转换

```dart
// 快速风格转换
final imageUrl = await helper.styleTransfer(
  imagePath: '/path/to/photo.jpg',
  targetStyle: '油画',
  keepComposition: true,  // 保持原始构图
);

// 常用风格示例
final styles = ['油画', '水彩', '素描', '赛博朋克', '动漫', '像素艺术'];
for (final style in styles) {
  final result = await helper.styleTransfer(
    imagePath: '/path/to/photo.jpg',
    targetStyle: style,
  );
  print('$style: $result');
}
```

### 4. 多图融合

```dart
final imageUrl = await helper.multiImageBlend(
  imagePaths: [
    '/path/to/image1.jpg',
    '/path/to/image2.jpg',
    '/path/to/image3.jpg',
  ],
  prompt: '融合这些图片的风格，创作一幅新的艺术作品',
);
```

### 5. 批量生成

```dart
// 一次生成多张图片
final imageUrls = await helper.generateMultiple(
  prompt: '未来派科幻城市',
  count: 4,  // 生成4张
);

print('生成了 ${imageUrls.length} 张图片');
for (var i = 0; i < imageUrls.length; i++) {
  print('图片${i + 1}: ${imageUrls[i]}');
}
```

### 6. 图片增强

```dart
final enhancedUrl = await helper.enhanceImage(
  imagePath: '/path/to/photo.jpg',
  enhancements: [
    '提高清晰度',
    '增强色彩饱和度',
    '优化光线',
    '去除噪点',
  ],
);
```

### 7. 创意变体

```dart
// 生成多个创意变体
final variations = await helper.createVariations(
  imagePath: '/path/to/original.jpg',
  variations: '创作3个不同角度和光线的版本',
  count: 3,
);

for (var i = 0; i < variations.length; i++) {
  print('变体${i + 1}: ${variations[i]}');
}
```

### 8. 概念混合

```dart
final imageUrl = await helper.blendConcepts(
  concepts: ['未来城市', '热带雨林', '水下世界'],
  additionalPrompt: '色彩鲜艳，富有想象力',
);
```

### 9. 场景重构

```dart
// 改变场景的时间和天气
final reimaginedUrl = await helper.reimagineScene(
  imagePath: '/path/to/daytime-scene.jpg',
  timeOfDay: '夜晚',
  weather: '雨天',
  additionalChanges: '增加霓虹灯效果',
);
```

### 10. 艺术家风格模仿

```dart
// 基于现有图片模仿艺术家风格
final styledUrl = await helper.artistStyleImitation(
  imagePath: '/path/to/photo.jpg',
  prompt: '城市夜景',
  artistStyle: '梵高',
);

// 或直接用文字生成
final newArtUrl = await helper.artistStyleImitation(
  prompt: '星空下的麦田',
  artistStyle: '莫奈',
);
```

## 高级用法

### 1. 自定义参数

支持的参数包括：

```dart
final result = await openAIService.generateImagesByChat(
  prompt: '科幻城市夜景',
  model: 'gpt-4o',
  parameters: {
    'temperature': 0.7,        // 控制创造性 (0.0-2.0)
    'top_p': 0.9,              // 核采样参数 (0.0-1.0)
    'n': 1,                    // 生成图片数量
    'max_tokens': 1000,        // 最大token数
    'presence_penalty': 0.0,   // 存在惩罚 (-2.0-2.0)
    'frequency_penalty': 0.0,  // 频率惩罚 (-2.0-2.0)
  },
);
```

### 2. 自定义消息格式

如果需要完全控制消息结构，可以直接提供 `ChatMessage` 列表：

```dart
final messages = [
  ChatMessage(
    role: 'system',
    content: [
      ChatMessageContent.text(
        text: '你是一个专业的图像生成助手，擅长创作高质量的艺术作品。',
      ),
    ],
  ),
  ChatMessage(
    role: 'user',
    content: [
      ChatMessageContent.text(
        text: '请生成一幅未来主义风格的城市景观',
      ),
    ],
  ),
];

final result = await openAIService.generateImagesByChat(
  messages: messages,
  model: 'gpt-4o',
);
```

### 3. 混合文本和图片输入

可以在同一个消息中同时包含文本和多张图片：

```dart
final messages = [
  ChatMessage(
    role: 'user',
    content: [
      ChatMessageContent.image(
        imageUrl: 'data:image/jpeg;base64,/9j/4AAQ...',  // Base64编码的图片
        detail: 'high',  // 图片细节级别: auto, low, high
      ),
      ChatMessageContent.image(
        imageUrl: 'https://example.com/another-image.jpg',  // 或者URL
      ),
      ChatMessageContent.text(
        text: '结合这两张图片的风格，创作一幅新的作品',
      ),
    ],
  ),
];

final result = await openAIService.generateImagesByChat(
  messages: messages,
);
```

## 数据模型详解

### ChatImageResponse

响应对象包含完整的生成结果：

```dart
class ChatImageResponse {
  final String id;              // 响应ID
  final String object;          // 对象类型 "chat.completion"
  final int created;            // 创建时间戳
  final String model;           // 使用的模型
  final List<ChatImageChoice> choices;  // 生成的选择项
  final ChatImageUsage? usage;  // Token使用统计
  final Map<String, dynamic> metadata;  // 原始响应数据
  
  // 便捷方法
  List<String> get imageUrls;   // 获取所有图片URL
  String? get firstImageUrl;    // 获取第一张图片URL
}
```

**使用示例：**

```dart
if (result.isSuccess) {
  final response = result.data!;
  
  // 基本信息
  print('响应ID: ${response.id}');
  print('模型: ${response.model}');
  print('创建时间: ${DateTime.fromMillisecondsSinceEpoch(response.created * 1000)}');
  
  // 图片URL
  print('第一张图片: ${response.firstImageUrl}');
  print('所有图片: ${response.imageUrls.join(", ")}');
  
  // Token使用情况
  if (response.usage != null) {
    print('提示词tokens: ${response.usage!.promptTokens}');
    print('完成tokens: ${response.usage!.completionTokens}');
    print('总计tokens: ${response.usage!.totalTokens}');
  }
  
  // 遍历所有选择项
  for (final choice in response.choices) {
    print('选择项 ${choice.index}: ${choice.message.content}');
    print('结束原因: ${choice.finishReason}');
  }
}
```

### ChatMessage

表示对话中的一条消息：

```dart
class ChatMessage {
  final String role;            // 角色: "system", "user", "assistant"
  final dynamic content;        // 内容: String 或 List<ChatMessageContent>
}
```

### ChatMessageContent

消息内容，可以是文本或图片：

```dart
class ChatMessageContent {
  final String type;            // "text" 或 "image_url"
  final String? text;           // 文本内容
  final ChatImageUrl? imageUrl; // 图片URL
  
  // 工厂构造函数
  factory ChatMessageContent.text({required String text});
  factory ChatMessageContent.image({
    required String imageUrl,
    String? detail,  // "auto", "low", "high"
  });
}
```

### ChatImageChoice

单个生成选择项：

```dart
class ChatImageChoice {
  final int index;              // 选择项索引
  final ChatMessage message;    // 消息内容
  final String? finishReason;   // 结束原因: "stop", "length", "content_filter"
  
  // 从消息中提取图片URL
  List<String> extractImageUrls();
}
```

### ChatImageUsage

Token 使用统计：

```dart
class ChatImageUsage {
  final int promptTokens;       // 提示词使用的tokens
  final int completionTokens;   // 完成使用的tokens
  final int totalTokens;        // 总计tokens
}
```

## 完整示例

### 示例1：批量生成多张图片

```dart
Future<void> generateMultipleImages() async {
  final prompts = [
    '一只橙色的猫',
    '一只黑色的狗',
    '一只白色的兔子',
  ];
  
  for (final prompt in prompts) {
    final result = await openAIService.generateImagesByChat(
      prompt: prompt,
      model: 'gpt-4o',
      parameters: {
        'n': 2,  // 每个提示词生成2张图片
      },
    );
    
    if (result.isSuccess) {
      final response = result.data!;
      print('提示词: $prompt');
      print('生成了 ${response.imageUrls.length} 张图片:');
      for (final url in response.imageUrls) {
        print('  - $url');
      }
    }
  }
}
```

### 示例2：图片风格转换

```dart
Future<void> convertImageStyle() async {
  final styles = [
    '油画风格',
    '水彩画风格',
    '素描风格',
    '赛博朋克风格',
  ];
  
  final originalImagePath = '/path/to/original/image.jpg';
  
  for (final style in styles) {
    final result = await openAIService.generateImagesByChat(
      prompt: '将这张图片转换成$style，保持主要构图不变',
      referenceImagePaths: [originalImagePath],
      model: 'gpt-4o',
    );
    
    if (result.isSuccess) {
      final imageUrl = result.data!.firstImageUrl;
      print('$style 转换结果: $imageUrl');
    }
  }
}
```

### 示例3：对话式图像生成

```dart
Future<void> conversationalImageGeneration() async {
  // 第一轮：生成初始图像
  final firstResult = await openAIService.generateImagesByChat(
    prompt: '一座未来主义的摩天大楼',
    model: 'gpt-4o',
  );
  
  if (!firstResult.isSuccess) {
    print('初始生成失败');
    return;
  }
  
  // 第二轮：基于第一轮结果继续对话
  final messages = [
    ChatMessage(
      role: 'user',
      content: [
        ChatMessageContent.text(text: '一座未来主义的摩天大楼'),
      ],
    ),
    ChatMessage(
      role: 'assistant',
      content: firstResult.data!.choices.first.message.content,
    ),
    ChatMessage(
      role: 'user',
      content: [
        ChatMessageContent.text(
          text: '现在在大楼周围添加飞行汽车和霓虹灯',
        ),
      ],
    ),
  ];
  
  final secondResult = await openAIService.generateImagesByChat(
    messages: messages,
    model: 'gpt-4o',
  );
  
  if (secondResult.isSuccess) {
    print('最终图片: ${secondResult.data!.firstImageUrl}');
  }
}
```

## 错误处理

```dart
Future<void> generateWithErrorHandling() async {
  try {
    final result = await openAIService.generateImagesByChat(
      prompt: '测试图片生成',
      model: 'gpt-4o',
    );
    
    if (result.isSuccess) {
      final response = result.data!;
      
      // 检查是否真的生成了图片
      if (response.imageUrls.isEmpty) {
        print('警告：API返回成功但没有图片URL');
        return;
      }
      
      print('生成成功: ${response.firstImageUrl}');
      
    } else {
      // 处理API错误
      print('错误码: ${result.statusCode}');
      print('错误信息: ${result.errorMessage}');
      
      // 根据错误码进行不同处理
      switch (result.statusCode) {
        case 400:
          print('请求参数错误');
          break;
        case 401:
          print('API密钥无效');
          break;
        case 429:
          print('请求过于频繁，请稍后重试');
          break;
        case 500:
          print('服务器错误');
          break;
        default:
          print('未知错误');
      }
    }
  } catch (e, stackTrace) {
    print('异常: $e');
    print('堆栈: $stackTrace');
  }
}
```

## 参数说明

### 常用参数

| 参数 | 类型 | 说明 | 默认值 |
|------|------|------|--------|
| `prompt` | String | 文本提示词 | - |
| `model` | String | 模型名称 | config.model 或 'gpt-4o' |
| `referenceImagePaths` | List<String> | 参考图片路径列表 | null |
| `messages` | List<ChatMessage> | 自定义消息列表 | null |
| `parameters` | Map<String, dynamic> | 其他API参数 | null |

### parameters 支持的参数

| 参数 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `temperature` | double | 0.0-2.0 | 控制输出的随机性，值越高越随机 |
| `top_p` | double | 0.0-1.0 | 核采样参数，控制输出的多样性 |
| `n` | int | ≥1 | 生成的图片数量 |
| `stream` | bool | - | 是否使用流式响应 |
| `stop` | List<String> | - | 停止词列表 |
| `max_tokens` | int | ≥1 | 最大token数量 |
| `presence_penalty` | double | -2.0-2.0 | 存在惩罚，鼓励模型谈论新主题 |
| `frequency_penalty` | double | -2.0-2.0 | 频率惩罚，降低重复内容 |
| `logit_bias` | Map<String, int> | - | 调整特定token的概率 |
| `user` | String | - | 用户标识符 |
| `response_format` | Map | - | 响应格式设置 |

## 图片格式支持

### 输入图片格式（referenceImagePaths）

- JPEG/JPG
- PNG
- GIF
- WebP

### 输出图片格式

API 返回的是图片 URL，具体格式取决于 API 实现，通常为：
- JPEG
- PNG

## 注意事项

1. **Base64 编码**：
   - 参考图片会自动转换为 Base64 编码嵌入请求中
   - 大型图片会增加请求大小和处理时间
   - 建议对大图进行压缩后再使用

2. **Token 限制**：
   - 图片会占用大量 tokens
   - 高分辨率图片的 token 消耗更大
   - 使用 `detail: 'low'` 可以减少 token 消耗

3. **API 配额**：
   - 注意 API 的调用频率限制
   - 图像生成通常比文本生成消耗更多配额

4. **错误处理**：
   - 始终检查 `result.isSuccess` 和 `response.imageUrls.isEmpty`
   - 处理网络超时和 API 错误
   - 实现重试机制

5. **模型兼容性**：
   - 并非所有模型都支持图像生成
   - 不同模型对图片格式和尺寸的要求可能不同
   - 建议使用官方推荐的模型（如 `gpt-4o`, `dall-e-3`）

6. **图片URL有效期**：
   - API 返回的图片 URL 可能有时效性
   - 建议及时下载保存重要图片

## 最佳实践

1. **提示词优化**：
   - 提供详细、清晰的描述
   - 包含风格、颜色、构图等关键信息
   - 使用专业术语提高生成质量

2. **图生图优化**：
   - 使用高质量的参考图片
   - 提示词应明确说明期望的变化
   - 可以提供多张参考图片来融合风格

3. **性能优化**：
   - 批量生成时使用异步处理
   - 缓存生成结果避免重复请求
   - 合理设置 `n` 参数一次生成多张

4. **成本优化**：
   - 使用合适的模型（如 `dall-e-2` 比 `dall-e-3` 便宜）
   - 调整 `detail` 参数减少 token 消耗
   - 在测试阶段使用较小的图片和较低的质量设置

## Helper 类方法参考

### 基础方法

| 方法 | 说明 | 返回值 |
|------|------|--------|
| `textToImage()` | 简单文生图 | `Future<String?>` |
| `imageToImage()` | 简单图生图 | `Future<String?>` |
| `multiImageBlend()` | 多图融合生成 | `Future<String?>` |
| `generateMultiple()` | 批量生成 | `Future<List<String>>` |

### 高级方法

| 方法 | 说明 | 返回值 |
|------|------|--------|
| `styleTransfer()` | 风格转换 | `Future<String?>` |
| `enhanceImage()` | 图片增强/优化 | `Future<String?>` |
| `createVariations()` | 创意变体 | `Future<List<String>>` |
| `blendConcepts()` | 概念混合 | `Future<String?>` |
| `reimagineScene()` | 场景重构 | `Future<String?>` |
| `artistStyleImitation()` | 艺术家风格模仿 | `Future<String?>` |

## 常见问题（FAQ）

### Q1: 如何选择使用直接 API 还是 Helper 类？

**A:** 
- **使用 Helper 类**：适合大多数简单场景，代码更简洁，一行代码即可完成任务。
- **使用直接 API**：需要完全控制请求参数、处理完整响应数据（如 token 使用统计）、或实现对话式交互时。

### Q2: 生成的图片如何保存到本地？

**A:** API 返回的是图片 URL，需要下载后保存：

```dart
import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> downloadImage(String url, String savePath) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode == 200) {
    final file = File(savePath);
    await file.writeAsBytes(response.bodyBytes);
    print('图片已保存到: $savePath');
  }
}

// 使用示例
final imageUrl = await helper.textToImage(prompt: '一只猫');
if (imageUrl != null) {
  await downloadImage(imageUrl, '/path/to/save/cat.jpg');
}
```

### Q3: 如何处理大图片以减少 token 消耗？

**A:** 使用 `detail: 'low'` 参数：

```dart
final messages = [
  ChatMessage(
    role: 'user',
    content: [
      ChatMessageContent.image(
        imageUrl: 'data:image/jpeg;base64,...',
        detail: 'low',  // 低细节模式，减少token消耗
      ),
      ChatMessageContent.text(text: '描述这张图片'),
    ],
  ),
];

final result = await openAIService.generateImagesByChat(messages: messages);
```

### Q4: 支持流式响应吗？

**A:** 虽然 API 支持 `stream: true` 参数，但图像生成通常不适合流式响应。当前实现不支持流式，如需实现，可以通过 parameters 传入：

```dart
final result = await openAIService.generateImagesByChat(
  prompt: '...',
  parameters: {'stream': true},
);
```

但需要修改代码以处理 Server-Sent Events (SSE) 流。

### Q5: 如何实现对话式图像生成？

**A:** 维护对话历史，逐步添加新消息：

```dart
// 初始化对话历史
final conversationHistory = <ChatMessage>[];

// 第一轮
conversationHistory.add(
  ChatMessage(
    role: 'user',
    content: [ChatMessageContent.text(text: '生成一座城市')],
  ),
);

var result = await openAIService.generateImagesByChat(
  messages: conversationHistory,
);

if (result.isSuccess) {
  // 保存助手的回复
  conversationHistory.add(result.data!.choices.first.message);
  
  // 第二轮：基于第一轮结果继续
  conversationHistory.add(
    ChatMessage(
      role: 'user',
      content: [ChatMessageContent.text(text: '添加一些飞行汽车')],
    ),
  );
  
  result = await openAIService.generateImagesByChat(
    messages: conversationHistory,
  );
}
```

### Q6: 如何同时生成多种风格的图片？

**A:** 使用并发请求：

```dart
Future<Map<String, String?>> generateMultipleStyles(
  String imagePath,
  List<String> styles,
) async {
  final helper = OpenAIChatImageHelper(openAIService);
  final results = <String, String?>{};
  
  // 并发执行所有请求
  final futures = styles.map((style) async {
    final url = await helper.styleTransfer(
      imagePath: imagePath,
      targetStyle: style,
    );
    return MapEntry(style, url);
  });
  
  final entries = await Future.wait(futures);
  results.addEntries(entries);
  
  return results;
}

// 使用
final styleResults = await generateMultipleStyles(
  '/path/to/image.jpg',
  ['油画', '水彩', '素描', '卡通'],
);

styleResults.forEach((style, url) {
  print('$style: $url');
});
```

### Q7: 如何处理 API 限流（429 错误）？

**A:** 实现重试机制：

```dart
Future<String?> generateWithRetry({
  required String prompt,
  int maxRetries = 3,
  Duration retryDelay = const Duration(seconds: 5),
}) async {
  final helper = OpenAIChatImageHelper(openAIService);
  
  for (var i = 0; i < maxRetries; i++) {
    try {
      final result = await openAIService.generateImagesByChat(
        prompt: prompt,
      );
      
      if (result.isSuccess) {
        return result.data!.firstImageUrl;
      }
      
      // 如果是限流错误，等待后重试
      if (result.statusCode == 429) {
        print('请求过于频繁，等待 ${retryDelay.inSeconds} 秒后重试...');
        await Future.delayed(retryDelay * (i + 1));  // 指数退避
        continue;
      }
      
      // 其他错误直接返回
      print('错误: ${result.errorMessage}');
      return null;
      
    } catch (e) {
      print('异常: $e');
      if (i < maxRetries - 1) {
        await Future.delayed(retryDelay);
      }
    }
  }
  
  return null;
}
```

### Q8: 如何验证生成的图片URL是否有效？

**A:** 发送 HEAD 请求检查：

```dart
Future<bool> isImageUrlValid(String url) async {
  try {
    final response = await http.head(Uri.parse(url));
    return response.statusCode == 200;
  } catch (e) {
    return false;
  }
}

// 使用
final imageUrl = await helper.textToImage(prompt: '...');
if (imageUrl != null) {
  if (await isImageUrlValid(imageUrl)) {
    print('图片URL有效: $imageUrl');
  } else {
    print('图片URL无效或已过期');
  }
}
```

### Q9: 支持哪些图片尺寸？

**A:** 不同模型支持不同尺寸：

**DALL-E 3:**
- 1024x1024 (1:1)
- 1792x1024 (16:9 横向)
- 1024x1792 (9:16 竖向)

**DALL-E 2:**
- 256x256
- 512x512
- 1024x1024

可以通过 parameters 指定：

```dart
final result = await openAIService.generateImagesByChat(
  prompt: '...',
  parameters: {
    'size': '1792x1024',  // 具体尺寸取决于使用的模型
  },
);
```

### Q10: 如何优化成本？

**A:** 几个建议：

1. **选择合适的模型**：
   - `dall-e-2` 比 `dall-e-3` 便宜
   - `gpt-4o` 在某些任务上更经济

2. **减少图片分辨率**：
   ```dart
   parameters: {'detail': 'low'}  // 低分辨率，减少token
   ```

3. **缓存结果**：
   ```dart
   final cache = <String, String>{};
   
   Future<String?> getCachedOrGenerate(String prompt) async {
     if (cache.containsKey(prompt)) {
       return cache[prompt];
     }
     
     final url = await helper.textToImage(prompt: prompt);
     if (url != null) {
       cache[prompt] = url;
     }
     return url;
   }
   ```

4. **批量生成**：
   ```dart
   // 一次请求生成多张，比多次单独请求更经济
   final urls = await helper.generateMultiple(
     prompt: '...',
     count: 4,
   );
   ```

## 故障排查

### 问题：API 返回 401 错误

**解决方案：**
- 检查 API Key 是否正确
- 确认 API Key 有效且未过期
- 验证 baseUrl 是否正确

### 问题：生成的图片不符合预期

**解决方案：**
- 使用更详细、具体的提示词
- 尝试不同的 temperature 值
- 使用参考图片提供更多上下文
- 尝试多次生成并选择最佳结果

### 问题：图片 URL 无法访问

**解决方案：**
- 检查网络连接
- URL 可能已过期，及时下载保存
- 验证 URL 格式是否正确

### 问题：处理大图片时出现错误

**解决方案：**
- 使用 `detail: 'low'` 减少 token 消耗
- 压缩图片后再使用
- 分批处理多张大图

## 相关资源

- [OpenAI API 文档](https://platform.openai.com/docs/api-reference)
- [DALL-E 图像生成指南](https://platform.openai.com/docs/guides/images)
- [GPT-4 Vision 文档](https://platform.openai.com/docs/guides/vision)
- [Chat Completions API](https://platform.openai.com/docs/api-reference/chat)

## 更新日志

### v1.0.0
- 初始版本
- 支持文生图和图生图
- 实现 `OpenAIChatImageHelper` 辅助类
- 完整的数据模型和错误处理
