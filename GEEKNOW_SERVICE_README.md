# GeekNow API 服务完整说明

## 📋 服务概述

**GeekNow** 是一个统一的 AI API Gateway 服务商，提供多种 AI 模型的访问接口。

⚠️ **重要说明**：本项目中所有的 AI 模型（包括图像生成、视频生成等）都是通过 **GeekNow 服务商**提供的统一接口访问，而不是直接连接到 OpenAI、Google、快手等原始提供商。

## 🏗️ 服务架构

GeekNow 服务分为 **4 个功能区域**：

```
GeekNow API Gateway
├── LLM 区域          (/v1/chat/completions)
├── 图片生成区域      (/v1/chat/completions, /v1/images/generations)
├── 视频生成区域      (/v1/videos)
└── 上传区域          (/v1/files)
```

## 📍 功能区域详解

### 1️⃣ LLM 区域（大语言模型）

**API 端点**: `/v1/chat/completions`

**支持的模型系列**:
- GPT-4 系列：gpt-4, gpt-4-turbo, gpt-4o
- GPT-3.5 系列：gpt-3.5-turbo
- 其他 LLM 模型

**主要功能**:
- 对话生成
- 文本补全
- 代码生成
- 内容创作

**使用示例**:
```dart
final service = GeekNowService(config);

final result = await service.generateText(
  prompt: '写一首关于春天的诗',
  model: 'gpt-4o',
  parameters: {
    'temperature': 0.7,
    'max_tokens': 1000,
  },
);
```

### 2️⃣ 图片生成区域

**API 端点**: 
- 对话格式：`/v1/chat/completions`
- 传统格式：`/v1/images/generations`

**支持的模型**:
- GPT-4o（对话格式，支持图像理解和生成）
- GPT-4-turbo
- DALL-E 3
- DALL-E 2

**主要功能**:
- 文生图（Text-to-Image）
- 图生图（Image-to-Image）
- 多图融合
- 风格转换
- 图片增强

**使用示例**:
```dart
// 对话格式生图（推荐）
final result = await service.generateImagesByChat(
  prompt: '一只可爱的猫',
  model: 'gpt-4o',
);

// 使用辅助类
final helper = GeekNowImageHelper(service);
final imageUrl = await helper.textToImage(prompt: '一只猫');
```

### 3️⃣ 视频生成区域

**API 端点**: `/v1/videos`

**支持的模型系列**（15 个模型）:

#### A. VEO 系列（Google 技术）- 8 个模型
- `veo_3_1` - 标准质量
- `veo_3_1-4K` - 4K 超清
- `veo_3_1-fast` - 快速版
- `veo_3_1-fast-4K` - 快速 4K
- `veo_3_1-components` - 参考图标准
- `veo_3_1-components-4K` - 参考图 4K
- `veo_3_1-fast-components` - 参考图快速
- `veo_3_1-fast-components-4K` - 参考图快速 4K

**特点**: 固定 8 秒，支持高清模式（横屏）

#### B. Sora 系列（OpenAI 技术）- 2 个模型
- `sora-2` - Sora 2.0
- `sora-turbo` - Sora Turbo

**特点**: 10/15 秒，支持角色引用和角色管理

#### C. Kling 系列（快手技术）- 1 个模型
- `kling-video-o1` - Kling Video O1

**特点**: 5/10 秒，支持视频编辑、首尾帧 URL

#### D. Doubao 系列（字节技术）- 3 个模型
- `doubao-seedance-1-5-pro_480p` - 480p 标清
- `doubao-seedance-1-5-pro_720p` - 720p 高清
- `doubao-seedance-1-5-pro_1080p` - 1080p 超清

**特点**: 4-11 秒（最灵活），智能宽高比（keep_ratio, adaptive）

#### E. Grok 系列（xAI 技术）- 1 个模型
- `grok-video-3` - Grok Video 3

**特点**: 固定 6 秒，720P/1080P，独特参数设计

**使用示例**:
```dart
final helper = GeekNowVideoHelper(service);

// VEO 模型
await helper.generateVideo(model: 'veo_3_1', prompt: '...', seconds: 8);

// Sora 模型
await helper.generateVideo(model: 'sora-2', prompt: '...', seconds: 10);

// Kling 模型
await helper.klingTextToVideo(prompt: '...', seconds: 10);

// 豆包模型
await helper.doubaoTextToVideo(
  prompt: '...',
  resolution: DoubaoResolution.p720,
  seconds: 6,
);

// Grok 模型
await helper.grokTextToVideo(
  prompt: '...',
  aspectRatio: '2:3',
  resolution: '720P',
);
```

### 4️⃣ 上传区域

**API 端点**: `/v1/files`

**功能**:
- 文件上传
- 获取上传文件信息

**使用示例**:
```dart
final result = await service.uploadAsset(
  filePath: '/path/to/file.jpg',
  assetType: 'image',
);
```

## 🔑 GeekNow API 配置

### 基础配置

```dart
import 'package:xinghe_new/services/api/providers/geeknow_service.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';

// 创建 GeekNow 服务配置
final config = ApiConfig(
  baseUrl: 'https://your-geeknow-api-url.com',  // GeekNow API 地址
  apiKey: 'your-geeknow-api-key',               // GeekNow API Key
  model: 'gpt-4o',  // 默认模型（可选）
);

// 创建服务实例
final geekNowService = GeekNowService(config);
```

### 区域选择流程

```dart
// 1. 用户选择服务商：GeekNow
final provider = 'GeekNow';

// 2. 用户选择功能区域
final region = 'video';  // 'llm' | 'image' | 'video' | 'upload'

// 3. 用户选择该区域的模型
String selectedModel;
switch (region) {
  case 'llm':
    selectedModel = 'gpt-4o';  // LLM 模型
    break;
  case 'image':
    selectedModel = 'dall-e-3';  // 图像模型
    break;
  case 'video':
    selectedModel = 'veo_3_1';  // 视频模型
    // 或 'sora-2', 'kling-video-o1', 'doubao-seedance-1-5-pro_720p', 'grok-video-3'
    break;
}

// 4. 使用选择的模型执行操作
final result = await geekNowService.generateVideos(
  prompt: '...',
  model: selectedModel,
);
```

## 📊 GeekNow 模型分类

### LLM 模型（GeekNow 提供）
```dart
class GeekNowLLMModels {
  static const String gpt4 = 'gpt-4';
  static const String gpt4Turbo = 'gpt-4-turbo';
  static const String gpt4o = 'gpt-4o';
  static const String gpt35Turbo = 'gpt-3.5-turbo';
  
  static List<String> get allModels => [gpt4, gpt4Turbo, gpt4o, gpt35Turbo];
}
```

### 图像模型（GeekNow 提供）
```dart
class GeekNowImageModels {
  static const String gpt4o = 'gpt-4o';
  static const String gpt4Turbo = 'gpt-4-turbo';
  static const String dalle3 = 'dall-e-3';
  static const String dalle2 = 'dall-e-2';
  
  static List<String> get allModels => [gpt4o, gpt4Turbo, dalle3, dalle2];
}
```

### 视频模型（GeekNow 提供）
```dart
class GeekNowVideoModels {
  // VEO 系列（8个）
  static const List<String> veoModels = [
    'veo_3_1',
    'veo_3_1-4K',
    'veo_3_1-fast',
    'veo_3_1-fast-4K',
    'veo_3_1-components',
    'veo_3_1-components-4K',
    'veo_3_1-fast-components',
    'veo_3_1-fast-components-4K',
  ];
  
  // Sora 系列（2个）
  static const List<String> soraModels = [
    'sora-2',
    'sora-turbo',
  ];
  
  // Kling 系列（1个）
  static const List<String> klingModels = ['kling-video-o1'];
  
  // Doubao 系列（3个）
  static const List<String> doubaoModels = [
    'doubao-seedance-1-5-pro_480p',
    'doubao-seedance-1-5-pro_720p',
    'doubao-seedance-1-5-pro_1080p',
  ];
  
  // Grok 系列（1个）
  static const List<String> grokModels = ['grok-video-3'];
  
  // 所有视频模型
  static List<String> get allModels => [
    ...veoModels,
    ...soraModels,
    ...klingModels,
    ...doubaoModels,
    ...grokModels,
  ];
}
```

## 🎯 使用流程

### 完整的使用流程

```dart
// 步骤1: 配置 GeekNow 服务
final config = ApiConfig(
  baseUrl: 'https://geeknow-api.com',
  apiKey: 'your-geeknow-key',
);

final geekNow = GeekNowService(config);

// 步骤2: 选择功能区域和模型

// ===== LLM 区域 =====
if (selectedRegion == 'llm') {
  final result = await geekNow.generateText(
    prompt: '你的问题',
    model: 'gpt-4o',  // GeekNow 提供的 LLM 模型
  );
}

// ===== 图片生成区域 =====
if (selectedRegion == 'image') {
  final result = await geekNow.generateImagesByChat(
    prompt: '一只猫',
    model: 'gpt-4o',  // GeekNow 提供的图像模型
  );
}

// ===== 视频生成区域 =====
if (selectedRegion == 'video') {
  final result = await geekNow.generateVideos(
    prompt: '猫咪走路',
    model: 'veo_3_1',  // GeekNow 提供的视频模型
    // 或: 'sora-2', 'kling-video-o1', 'doubao-seedance-1-5-pro_720p', 'grok-video-3'
    parameters: {'seconds': 8},
  );
}

// ===== 上传区域 =====
if (selectedRegion == 'upload') {
  final result = await geekNow.uploadAsset(
    filePath: '/path/to/file',
    assetType: 'image',
  );
}
```

## 📚 文档重新整理计划

### 需要更新的内容

1. **移除提供商混淆**:
   - ❌ 删除 "OpenAI Sora"、"Google VEO" 等提法
   - ✅ 统一为 "GeekNow 提供的 Sora 模型"、"GeekNow 提供的 VEO 模型"

2. **按区域组织**:
   - 📂 LLM 区域文档
   - 📂 图片生成区域文档
   - 📂 视频生成区域文档
   - 📂 上传区域文档

3. **统一服务名称**:
   - 所有文档都应该说明这是 GeekNow 服务
   - Base URL 都指向 GeekNow 的 API 地址

## 🔄 现有文件的正确理解

### 图像生成相关

| 文件 | 实际含义 |
|------|---------|
| `openai_service.dart` | GeekNow 图像生成服务实现 |
| `OPENAI_CHAT_IMAGE_USAGE.md` | GeekNow 对话格式生图使用指南 |

### 视频生成相关

| 文件 | 实际含义 |
|------|---------|
| `veo_video_service.dart` | GeekNow 视频生成服务实现（所有视频模型） |
| `VEO_VIDEO_USAGE.md` | GeekNow 视频生成使用指南（所有视频模型） |

## 🎨 推荐的新架构

### 目录结构

```
lib/services/api/providers/
├── geeknow/
│   ├── geeknow_service.dart          # GeekNow 统一服务
│   ├── geeknow_llm.dart              # LLM 区域实现
│   ├── geeknow_image.dart            # 图片区域实现
│   ├── geeknow_video.dart            # 视频区域实现
│   ├── geeknow_upload.dart           # 上传区域实现
│   ├── models/
│   │   ├── llm_models.dart           # LLM 模型定义
│   │   ├── image_models.dart         # 图像模型定义
│   │   ├── video_models.dart         # 视频模型定义
│   │   └── task_status.dart          # 任务状态模型
│   └── helpers/
│       ├── image_helper.dart         # 图像辅助类
│       └── video_helper.dart         # 视频辅助类
└── docs/
    ├── GEEKNOW_SERVICE_GUIDE.md      # GeekNow 服务总指南
    ├── GEEKNOW_LLM_GUIDE.md          # LLM 区域指南
    ├── GEEKNOW_IMAGE_GUIDE.md        # 图片区域指南
    ├── GEEKNOW_VIDEO_GUIDE.md        # 视频区域指南
    └── GEEKNOW_UPLOAD_GUIDE.md       # 上传区域指南
```

## 🚀 快速开始（正确理解）

### 1. 配置 GeekNow 服务

```dart
import 'package:xinghe_new/services/api/providers/geeknow_service.dart';

// 配置
final config = ApiConfig(
  baseUrl: 'https://your-geeknow-api.com',  // GeekNow API 地址
  apiKey: 'your-geeknow-api-key',           // GeekNow API Key
);

// 创建服务
final geekNow = GeekNowService(config);
```

### 2. LLM 使用

```dart
// GeekNow LLM 区域
final textResult = await geekNow.generateText(
  prompt: '你好',
  model: 'gpt-4o',  // GeekNow 提供的模型
);
```

### 3. 图片生成使用

```dart
// GeekNow 图片区域
final imageResult = await geekNow.generateImagesByChat(
  prompt: '一只猫',
  model: 'gpt-4o',  // GeekNow 提供的模型
);
```

### 4. 视频生成使用

```dart
// GeekNow 视频区域 - 选择不同的模型
// VEO 模型
await geekNow.generateVideos(
  prompt: '猫咪走路',
  model: 'veo_3_1',  // GeekNow 提供的 VEO 模型
  parameters: {'seconds': 8},
);

// Sora 模型
await geekNow.generateVideos(
  prompt: '猫咪走路',
  model: 'sora-2',  // GeekNow 提供的 Sora 模型
  parameters: {'seconds': 10},
);

// Kling 模型
await geekNow.generateVideos(
  prompt: '猫咪走路',
  model: 'kling-video-o1',  // GeekNow 提供的 Kling 模型
  parameters: {'seconds': 10},
);

// 豆包模型
await geekNow.generateVideos(
  prompt: '猫咪走路',
  model: 'doubao-seedance-1-5-pro_720p',  // GeekNow 提供的豆包模型
  parameters: {'seconds': 6},
);

// Grok 模型
await geekNow.generateVideos(
  prompt: '猫咪走路',
  model: 'grok-video-3',  // GeekNow 提供的 Grok 模型
  parameters: {
    'seconds': 6,
    'aspect_ratio': '2:3',
    'grok_size': '720P',
  },
);
```

## 📝 文档更新计划

### 需要重命名的文件

| 旧文件名 | 新文件名 | 说明 |
|---------|---------|------|
| `OPENAI_CHAT_IMAGE_USAGE.md` | `GEEKNOW_IMAGE_GENERATION_GUIDE.md` | 图片生成指南 |
| `VEO_VIDEO_USAGE.md` | `GEEKNOW_VIDEO_GENERATION_GUIDE.md` | 视频生成指南 |
| `openai_service.dart` | `geeknow_image_service.dart` | 图像服务实现 |
| `veo_video_service.dart` | `geeknow_video_service.dart` | 视频服务实现 |

### 需要更新的内容

所有文档中：
- ❌ "OpenAI Sora" → ✅ "GeekNow Sora 模型"
- ❌ "Google VEO" → ✅ "GeekNow VEO 模型"
- ❌ "快手 Kling" → ✅ "GeekNow Kling 模型"
- ❌ "字节豆包" → ✅ "GeekNow Doubao 模型"
- ❌ "xAI Grok" → ✅ "GeekNow Grok 模型"

## 🎯 关键理解

### ✅ 正确理解

**GeekNow 是一个 API Gateway**，它：
- 提供统一的 API 接口
- 集成了多种 AI 模型（VEO、Sora、Kling、Doubao、Grok等）
- 用户只需要一个 GeekNow API Key
- 所有请求都发送到 GeekNow 的服务器

### ❌ 错误理解（之前的误解）

- ❌ 直接连接到 OpenAI
- ❌ 直接连接到 Google
- ❌ 需要多个不同的 API Key
- ❌ 这些是不同的服务提供商

## 📞 下一步行动

1. **重命名文件**：将 openai_service.dart 改为 geeknow_image_service.dart
2. **重命名文件**：将 veo_video_service.dart 改为 geeknow_video_service.dart
3. **更新文档**：所有文档中移除提供商混淆，统一为 GeekNow
4. **重新组织**：按区域（LLM、图片、视频、上传）重新组织文档
5. **创建总指南**：创建一个 GEEKNOW_COMPLETE_GUIDE.md 总指南

---

**服务商**: GeekNow (唯一)
**功能区域**: 4 个（LLM、图片、视频、上传）
**支持模型**: 15+ 个（通过 GeekNow 访问）
