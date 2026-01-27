# GeekNow API 完整使用指南

## 📋 服务概述

**GeekNow** 是一个统一的 AI API Gateway 服务商，提供多种 AI 功能的访问接口。

### 什么是 GeekNow？

GeekNow 是一个**API 网关服务**，它：
- 🔗 集成了多种 AI 模型（图像生成、视频生成、LLM 等）
- 🔑 提供统一的 API Key 和认证
- 🌐 提供统一的 API 端点
- 🚀 简化了多模型的访问和管理

### 重要理解

⚠️ **关键概念**：
- GeekNow 是**唯一的服务提供商**
- 所有 AI 模型（VEO、Sora、Kling、Doubao、Grok等）都是**通过 GeekNow 访问**
- 您不需要分别注册 OpenAI、Google、快手等账号
- 只需要一个 GeekNow API Key 即可访问所有模型

## 🏗️ 服务架构

GeekNow 服务分为 **4 个功能区域**：

```
┌─────────────────────────────────────────┐
│         GeekNow API Gateway             │
│  (统一的服务商、统一的API Key)           │
└─────────────────────────────────────────┘
           │
    ┌──────┴──────┐
    │             │
    ▼             ▼
┌─────────┐   ┌─────────┐
│ 前端区域 │   │ 后端区域 │
└─────────┘   └─────────┘
    │
    ├─── 1️⃣ LLM 区域 (/v1/chat/completions)
    │     └─ gpt-4o, gpt-4-turbo, gpt-3.5-turbo ...
    │
    ├─── 2️⃣ 图片生成区域 (/v1/chat/completions)
    │     └─ gpt-4o, dall-e-3, dall-e-2 ...
    │
    ├─── 3️⃣ 视频生成区域 (/v1/videos)
    │     ├─ VEO 系列 (8个模型)
    │     ├─ Sora 系列 (2个模型)
    │     ├─ Kling 系列 (1个模型)
    │     ├─ Doubao 系列 (3个模型)
    │     └─ Grok 系列 (1个模型)
    │
    └─── 4️⃣ 上传区域 (/v1/files)
          └─ 文件上传
```

## 🚀 快速开始

### 第一步：配置 GeekNow 服务

```dart
import 'package:xinghe_new/services/api/base/api_config.dart';
import 'package:xinghe_new/services/api/providers/geeknow_service.dart';

// 创建 GeekNow 配置
final config = ApiConfig(
  baseUrl: 'https://your-geeknow-api.com',  // GeekNow API 基础地址
  apiKey: 'your-geeknow-api-key',           // GeekNow API Key
  model: 'gpt-4o',  // 默认模型（可选）
);

// 创建 GeekNow 服务实例
final geekNow = GeekNowService(config);
```

### 第二步：选择功能区域和模型

## 1️⃣ LLM 区域使用

### API 端点
`POST /v1/chat/completions`

### 支持的模型
- `gpt-4o` - GPT-4 Omni（推荐）
- `gpt-4-turbo` - GPT-4 Turbo
- `gpt-4` - GPT-4
- `gpt-3.5-turbo` - GPT-3.5 Turbo

### 使用示例

```dart
// 文本对话生成
final result = await geekNow.generateText(
  prompt: '请介绍一下人工智能的发展历史',
  model: 'gpt-4o',  // GeekNow 提供的 LLM 模型
  parameters: {
    'temperature': 0.7,
    'max_tokens': 2000,
  },
);

if (result.isSuccess) {
  print('回复: ${result.data!.text}');
  print('Token 使用: ${result.data!.tokensUsed}');
}
```

## 2️⃣ 图片生成区域使用

### API 端点
`POST /v1/chat/completions`（对话格式）

### 支持的模型
- `gpt-4o` - 支持图像理解和生成（推荐）
- `gpt-4-turbo` - 支持图像
- `dall-e-3` - 专业图像生成
- `dall-e-2` - 图像生成

### 使用示例

```dart
// 创建图像辅助类
final imageHelper = OpenAIChatImageHelper(geekNow);

// 文生图
final imageUrl = await imageHelper.textToImage(
  prompt: '一只可爱的橙色小猫，坐在彩虹上',
);

if (imageUrl != null) {
  print('生成的图片: $imageUrl');
}

// 图生图
final newImageUrl = await imageHelper.imageToImage(
  imagePath: '/path/to/photo.jpg',
  prompt: '转换成油画风格',
);

// 风格转换
final styledUrl = await imageHelper.styleTransfer(
  imagePath: '/path/to/photo.jpg',
  targetStyle: '水彩画',
  keepComposition: true,
);
```

**详细指南**: [GEEKNOW_IMAGE_GUIDE.md](./lib/services/api/providers/OPENAI_CHAT_IMAGE_USAGE.md)

## 3️⃣ 视频生成区域使用

### API 端点
- 生成：`POST /v1/videos`
- 查询：`GET /v1/videos/{task_id}`
- Remix：`POST /v1/videos/{video_id}/remix`
- 创建角色：`POST /sora/v1/characters`

### 支持的模型系列（15 个模型）

#### A. VEO 系列（8 个）- 基于 Google 技术
```dart
'veo_3_1'                    // 标准质量，8秒
'veo_3_1-4K'                 // 4K 超清，8秒
'veo_3_1-fast'               // 快速版，8秒
'veo_3_1-fast-4K'            // 快速 4K，8秒
'veo_3_1-components'         // 参考图标准，8秒
'veo_3_1-components-4K'      // 参考图 4K，8秒
'veo_3_1-fast-components'    // 参考图快速，8秒
'veo_3_1-fast-components-4K' // 参考图快速 4K，8秒
```
**特点**: 固定 8 秒，支持高清模式（enable_upsample，仅横屏）

#### B. Sora 系列（2 个）- 基于 OpenAI 技术
```dart
'sora-2'       // Sora 2.0，10/15秒，支持角色引用
'sora-turbo'   // Sora Turbo，10秒，快速版
```
**特点**: 10/15 秒，支持角色管理和引用

#### C. Kling 系列（1 个）- 基于快手技术
```dart
'kling-video-o1'  // Kling Video O1，5/10秒
```
**特点**: 5/10 秒，支持视频编辑、首尾帧 URL

#### D. Doubao 系列（3 个）- 基于字节技术
```dart
'doubao-seedance-1-5-pro_480p'   // 480p 标清，4-11秒
'doubao-seedance-1-5-pro_720p'   // 720p 高清，4-11秒
'doubao-seedance-1-5-pro_1080p'  // 1080p 超清，4-11秒
```
**特点**: 4-11 秒（最灵活），智能宽高比（keep_ratio, adaptive）

#### E. Grok 系列（1 个）- 基于 xAI 技术
```dart
'grok-video-3'  // Grok Video 3，固定6秒
```
**特点**: 固定 6 秒，720P/1080P，独特参数设计

### 使用示例

```dart
// 创建视频辅助类
final videoHelper = VeoVideoHelper(geekNow);

// VEO 模型生成
final veoResult = await videoHelper.textToVideo(
  prompt: '猫咪在花园里玩耍',
  size: '720x1280',
  seconds: 8,  // VEO 固定 8 秒
  quality: VeoQuality.standard,
);

// Sora 模型生成（带角色引用）
final soraResult = await videoHelper.soraWithCharacterReference(
  prompt: '猫咪跳舞',
  characterUrl: 'https://example.com/character.mp4',
  characterTimestamps: '1,3',
  size: '720x1280',
  seconds: 10,
);

// Kling 模型生成
final klingResult = await videoHelper.klingTextToVideo(
  prompt: '城市夜景',
  size: '720x1280',
  seconds: 10,  // Kling 支持 5 或 10 秒
);

// Doubao 模型生成
final doubaoResult = await videoHelper.doubaoTextToVideo(
  prompt: '产品展示',
  resolution: DoubaoResolution.p720,
  aspectRatio: '16:9',
  seconds: 6,  // Doubao 支持 4-11 秒
);

// Grok 模型生成
final grokResult = await videoHelper.grokTextToVideo(
  prompt: '科技场景',
  aspectRatio: GrokAspectRatio.ratio2x3,
  resolution: GrokResolution.p720,
);

// 统一的任务查询（适用所有模型）
if (veoResult.isSuccess) {
  final taskId = veoResult.data!.first.videoId!;
  
  final status = await videoHelper.pollTaskUntilComplete(
    taskId: taskId,
    onProgress: (progress, status) {
      print('进度: $progress%');
    },
  );
  
  if (status.isSuccess && status.data!.hasVideo) {
    print('视频完成: ${status.data!.videoUrl}');
  }
}
```

**详细指南**: [GEEKNOW_VIDEO_GUIDE.md](./lib/services/api/providers/VEO_VIDEO_USAGE.md)

## 4️⃣ 上传区域使用

### API 端点
`POST /v1/files`

### 使用示例

```dart
// 上传文件
final result = await geekNow.uploadAsset(
  filePath: '/path/to/file.jpg',
  assetType: 'image',
);

if (result.isSuccess) {
  print('文件ID: ${result.data!.uploadId}');
  print('文件URL: ${result.data!.uploadUrl}');
}
```

## 📊 功能区域对比

| 功能区域 | API 端点 | 模型数量 | 主要用途 |
|---------|---------|---------|---------|
| **LLM** | `/v1/chat/completions` | 4+ | 对话、文本生成 |
| **图片** | `/v1/chat/completions` | 4+ | 图像生成、编辑 |
| **视频** | `/v1/videos` | **15** | 视频生成、编辑 |
| **上传** | `/v1/files` | - | 文件上传 |

## 🎯 模型选择指南

### 视频生成模型对比

| 模型系列 | 模型数 | 时长 | 特色功能 | 适用场景 |
|---------|-------|------|---------|---------|
| **VEO** | 8 | 8秒 | 高清模式、4K | 高质量输出 |
| **Sora** | 2 | 10/15秒 | 角色引用 | 角色一致性 |
| **Kling** | 1 | 5/10秒 | 视频编辑 | 快速生成、后期处理 |
| **Doubao** | 3 | 4-11秒 | 智能比例、多分辨率 | 灵活需求、多平台 |
| **Grok** | 1 | 6秒 | 720P/1080P | 标准需求 |

### 如何选择模型？

#### 按时长选择
- **4-5 秒**: Doubao 480p/720p（快速测试）
- **6 秒**: Doubao, Grok
- **8 秒**: VEO 系列
- **10 秒**: Sora, Kling, Doubao
- **11 秒**: Doubao（最长）
- **15 秒**: Sora（长视频）

#### 按特殊需求选择
- **需要高清模式**: VEO（横屏）
- **需要角色引用**: Sora
- **需要视频编辑**: Kling
- **需要多分辨率**: Doubao（480p/720p/1080p）
- **需要智能比例**: Doubao（keep_ratio, adaptive）

#### 按成本优化选择
- **测试阶段**: Doubao 480p（最低成本）
- **预览阶段**: Doubao 720p、Kling 5秒
- **最终输出**: VEO 4K、Doubao 1080p

## 💻 代码示例

### 完整的使用流程

```dart
// 1. 配置 GeekNow 服务
final config = ApiConfig(
  baseUrl: 'https://your-geeknow-api.com',
  apiKey: 'your-geeknow-api-key',
);

final geekNow = GeekNowService(config);

// 2. 根据用户选择的区域和模型执行操作

// ===== LLM 区域 =====
if (selectedRegion == 'llm') {
  final result = await geekNow.generateText(
    prompt: '介绍人工智能',
    model: selectedModel,  // 'gpt-4o', 'gpt-4-turbo' 等
  );
}

// ===== 图片生成区域 =====
if (selectedRegion == 'image') {
  final helper = OpenAIChatImageHelper(geekNow);
  
  final imageUrl = await helper.textToImage(
    prompt: '一只可爱的猫',
  );
  
  // 或使用完整 API
  final result = await geekNow.generateImagesByChat(
    prompt: '一只猫',
    model: selectedModel,  // 'gpt-4o', 'dall-e-3' 等
  );
}

// ===== 视频生成区域 =====
if (selectedRegion == 'video') {
  final helper = VeoVideoHelper(geekNow);
  
  // 根据选择的模型使用对应的方法
  ApiResponse<List<VideoResponse>> result;
  
  if (selectedModel.startsWith('veo')) {
    // VEO 系列
    result = await helper.textToVideo(
      prompt: '猫咪走路',
      seconds: 8,
      quality: VeoQuality.standard,
    );
  } else if (selectedModel.startsWith('sora')) {
    // Sora 系列
    result = await geekNow.generateVideos(
      prompt: '猫咪走路',
      model: selectedModel,
      parameters: {'seconds': 10},
    );
  } else if (selectedModel == 'kling-video-o1') {
    // Kling
    result = await helper.klingTextToVideo(
      prompt: '猫咪走路',
      seconds: 10,
    );
  } else if (selectedModel.startsWith('doubao')) {
    // Doubao
    final resolution = _parseDoubaoResolution(selectedModel);
    result = await helper.doubaoTextToVideo(
      prompt: '猫咪走路',
      resolution: resolution,
      aspectRatio: '16:9',
      seconds: 6,
    );
  } else if (selectedModel == 'grok-video-3') {
    // Grok
    result = await helper.grokTextToVideo(
      prompt: '猫咪走路',
      aspectRatio: GrokAspectRatio.ratio2x3,
      resolution: GrokResolution.p720,
    );
  }
  
  // 统一的任务处理
  if (result.isSuccess) {
    final taskId = result.data!.first.videoId!;
    
    final status = await helper.pollTaskUntilComplete(
      taskId: taskId,
      onProgress: (progress, status) {
        print('进度: $progress%');
      },
    );
    
    if (status.isSuccess && status.data!.hasVideo) {
      print('视频完成: ${status.data!.videoUrl}');
    }
  }
}

// ===== 上传区域 =====
if (selectedRegion == 'upload') {
  final result = await geekNow.uploadAsset(
    filePath: '/path/to/file',
    assetType: 'image',
  );
}
```

## 📚 详细文档索引

### 核心文档
1. **本文档** - GeekNow 服务总指南
2. **[图片生成指南](./lib/services/api/providers/OPENAI_CHAT_IMAGE_USAGE.md)** - 图片生成详细使用
3. **[视频生成指南](./lib/services/api/providers/VEO_VIDEO_USAGE.md)** - 视频生成详细使用（所有15个模型）

### 示例代码
1. `examples/geeknow_image_example.dart` - 图像生成示例
2. `examples/geeknow_video_example.dart` - 视频生成基础示例
3. `examples/task_query_and_download_example.dart` - 任务查询和下载
4. `examples/kling_video_example.dart` - Kling 模型专用示例
5. `examples/doubao_video_example.dart` - Doubao 模型专用示例

### 技术文档
1. `GEEKNOW_SERVICE_README.md` - 服务架构说明
2. `REFACTORING_PLAN.md` - 重构计划
3. `PYTHON_VS_DART_COMPARISON.md` - Python vs Dart 对比
4. `UNIFIED_TASK_API_VERIFICATION.md` - 统一 API 验证

## 🔧 高级用法

### 多模型并发生成

```dart
// 同时使用多个模型生成相同内容，对比效果
final prompt = '品牌宣传视频';

final futures = [
  // VEO
  geekNow.generateVideos(
    prompt: prompt,
    model: 'veo_3_1',
    parameters: {'seconds': 8},
  ),
  // Sora
  geekNow.generateVideos(
    prompt: prompt,
    model: 'sora-2',
    parameters: {'seconds': 10},
  ),
  // Kling
  geekNow.generateVideos(
    prompt: prompt,
    model: 'kling-video-o1',
    parameters: {'seconds': 10},
  ),
  // Doubao
  geekNow.generateVideos(
    prompt: prompt,
    model: 'doubao-seedance-1-5-pro_720p',
    parameters: {'seconds': 6},
  ),
];

final results = await Future.wait(futures);

// 统一处理所有结果
for (var i = 0; i < results.length; i++) {
  if (results[i].isSuccess) {
    final taskId = results[i].data!.first.videoId!;
    print('模型${i+1}任务ID: $taskId');
  }
}
```

## ⚙️ 配置选项

### ApiConfig 参数

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `baseUrl` | String | ✅ | GeekNow API 基础地址 |
| `apiKey` | String | ✅ | GeekNow API Key |
| `model` | String | ❌ | 默认模型（可选） |

### 环境变量配置（推荐）

```dart
// 从环境变量读取配置
final config = ApiConfig(
  baseUrl: const String.fromEnvironment('GEEKNOW_API_URL'),
  apiKey: const String.fromEnvironment('GEEKNOW_API_KEY'),
);
```

## 🎨 UI 集成建议

### 区域和模型选择器

```dart
// 1. 定义区域
enum GeekNowRegion {
  llm('LLM', '/v1/chat/completions'),
  image('图片生成', '/v1/chat/completions'),
  video('视频生成', '/v1/videos'),
  upload('上传', '/v1/files');
  
  final String displayName;
  final String endpoint;
  const GeekNowRegion(this.displayName, this.endpoint);
}

// 2. 获取区域的模型列表
List<String> getModelsForRegion(GeekNowRegion region) {
  switch (region) {
    case GeekNowRegion.llm:
      return ['gpt-4o', 'gpt-4-turbo', 'gpt-3.5-turbo'];
    case GeekNowRegion.image:
      return ['gpt-4o', 'gpt-4-turbo', 'dall-e-3', 'dall-e-2'];
    case GeekNowRegion.video:
      return GeekNowVideoModels.allModels;  // 15 个模型
    case GeekNowRegion.upload:
      return [];
  }
}

// 3. UI 构建
Widget buildRegionSelector() {
  return Column(
    children: [
      Text('GeekNow 服务'),
      DropdownButton<GeekNowRegion>(
        items: GeekNowRegion.values.map((region) {
          return DropdownMenuItem(
            value: region,
            child: Text(region.displayName),
          );
        }).toList(),
        onChanged: (region) {
          // 更新区域，刷新模型列表
        },
      ),
      // 模型选择
      DropdownButton<String>(
        items: getModelsForRegion(selectedRegion).map((model) {
          return DropdownMenuItem(value: model, child: Text(model));
        }).toList(),
        onChanged: (model) {
          // 更新选择的模型
        },
      ),
    ],
  );
}
```

## ❓ 常见问题

### Q1: GeekNow 和 OpenAI/Google 的关系？

**A:** GeekNow 是一个 API Gateway（API 网关），它：
- 集成了多种 AI 模型的访问
- 提供统一的接口和认证
- 您通过 GeekNow 访问这些模型，而不是直接连接到 OpenAI、Google 等

### Q2: 我需要多个 API Key 吗？

**A:** 不需要。您只需要**一个 GeekNow API Key** 就可以访问所有支持的模型（LLM、图片、视频等）。

### Q3: 如何选择合适的视频模型？

**A:** 根据您的需求：
- **高质量输出**: VEO 4K
- **角色一致性**: Sora
- **快速生成**: Kling 5秒、Doubao 480p
- **灵活时长**: Doubao（4-11秒）
- **多平台适配**: Doubao（智能比例）

### Q4: 所有模型的价格一样吗？

**A:** 不一样。不同模型的成本不同：
- 480p < 720p < 1080p < 4K
- 标准版 < 快速版
- 时长越长越贵

详情请咨询 GeekNow 服务商。

## 📞 支持和反馈

- **GeekNow 文档**: 本项目文档
- **技术支持**: 联系 GeekNow 服务商
- **问题反馈**: 提交 Issue 或联系开发团队

---

**服务商**: GeekNow（唯一）
**功能区域**: 4 个（LLM、图片、视频、上传）
**支持模型**: 15+ 个视频模型，4+ 个图像模型，4+ 个 LLM 模型
**文档版本**: v2.0
**更新日期**: 2026-01-26
