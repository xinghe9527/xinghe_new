# GeekNow 视频生成服务使用指南

## ⚠️ 重要说明：服务商架构

本指南介绍如何使用 **GeekNow 服务**的**视频生成功能**。

**GeekNow** 是一个统一的 AI API Gateway，它集成了多种视频生成模型：
- 本指南涉及的所有模型（VEO、Sora、Kling、Doubao、Grok）都是**通过 GeekNow 的统一接口访问**
- 您只需要**一个 GeekNow API Key**
- 所有请求都发送到 **GeekNow 的服务器**
- GeekNow 内部会路由到相应的 AI 模型

⚠️ **注意**：虽然我们在文档中使用 "VEO 模型"、"Sora 模型" 等术语，但这些都是 GeekNow 提供的模型选项，而不是直接连接到 Google、OpenAI 等原始提供商。

## 概述

GeekNow 视频生成服务支持 **5 大视频模型系列**，共 **15 个模型**：

### VEO 系列（基于 Google 技术）
- **文生视频**：根据文本描述生成视频
- **图生视频**：基于图片生成视频（首帧/首尾帧/参考图模式）
- **多种质量选择**：标准版和 4K 版本
- **快速模式**：牺牲少量质量换取速度
- **固定时长**：8 秒

### Sora 系列（基于 OpenAI 技术）
- **角色引用**：上传角色视频，生成时保持角色一致性
- **角色管理**：从视频中提取角色，获取角色 ID 和名称
- **角色要求**：视频中不能出现真人，仅支持虚拟角色
- **时间范围**：指定角色出现的时间段（1-3秒）
- **场景延续**：基于之前的视频延续场景
- **时长支持**：10 或 15 秒

### Kling 系列（基于快手技术）
- **kling-video-o1**：Kling 视频生成模型
- **支持功能**：文生视频、图生视频、视频编辑
- **时长支持**：5 秒或 10 秒
- **特色功能**：
  - 首尾帧 URL 支持（URL 字符串，不是文件）
  - 视频编辑（基于现有视频生成新视频）
  - 多图参考

### Doubao 系列（基于字节技术）
- **Seedance 1.5 Pro**：Doubao 视频生成模型
- **分辨率选择**：480p（标清）、720p（高清）、1080p（超清）
- **时长支持**：4-11 秒（**最灵活**）
- **特色功能**：
  - 多种宽高比支持（16:9, 4:3, 1:1, 3:4, 9:16, 21:9）
  - 智能比例模式（keep_ratio, adaptive）
  - 首尾帧图片支持

### Grok 系列（基于 xAI 技术）
- **grok-video-3**：Grok 视频生成模型
- **时长支持**：固定 6 秒
- **分辨率选择**：720P（高清）、1080P（超清）
- **宽高比**：2:3（竖屏）、3:2（横屏）、1:1（方形）
- **特色功能**：独特的参数设计（aspect_ratio + size）

## 模型说明

### 模型列表

#### 高质量版本（推荐）
- `veo_3_1` - 标准质量
- `veo_3_1-4K` - 4K 超清

#### 快速版本
- `veo_3_1-fast` - 快速标准
- `veo_3_1-fast-4K` - 快速 4K

#### 参考图专用版本
- `veo_3_1-components` - 参考图标准
- `veo_3_1-components-4K` - 参考图 4K
- `veo_3_1-fast-components` - 参考图快速
- `veo_3_1-fast-components-4K` - 参考图快速 4K

#### Sora 模型
- `sora-2` - Sora 2.0（支持角色引用、场景延续）
- `sora-turbo` - Sora 1.0 Turbo（快速版本）

#### Kling 模型（快手）
- `kling-video-o1` - Kling Video O1（快手视频生成模型）

#### 豆包模型（字节跳动）
- `doubao-seedance-1-5-pro_480p` - 480p 标清版本（快速、低成本）
- `doubao-seedance-1-5-pro_720p` - 720p 高清版本（推荐）
- `doubao-seedance-1-5-pro_1080p` - 1080p 超清版本（最高质量）

#### Grok 模型（xAI/X）
- `grok-video-3` - Grok Video 3 视频生成模型

### 图片输入逻辑

| 图片数量 | 模式 | 说明 |
|---------|------|------|
| 1 张 | 首帧模式 | 图片作为视频首帧 |
| 2 张 | 首尾帧模式 | 第一张作为首帧，第二张作为尾帧 |
| 3 张 | 参考图模式 | 所有图片作为生成参考 |
| 使用 `-components` 模型 | 强制参考图模式 | 无论图片数量 |

## 快速开始

### 创建服务实例

```dart
import 'package:xinghe_new/services/api/providers/geeknow_service.dart';
// 或使用现有的：import 'package:xinghe_new/services/api/providers/veo_video_service.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';

// 配置 GeekNow 服务
final config = ApiConfig(
  baseUrl: 'https://your-geeknow-api.com',  // GeekNow API 地址
  apiKey: 'your-geeknow-api-key',           // GeekNow API Key  
  model: 'veo_3_1',  // 默认视频模型（可选）
);

// 创建 GeekNow 服务实例
final geekNowService = GeekNowService(config);
// 或使用现有实现：final geekNowService = VeoVideoService(config);

// 创建辅助类实例（推荐使用）
final helper = VeoVideoHelper(geekNowService);
```

**重要**：`VeoVideoService` 实际上是 GeekNow 视频服务的实现，未来将重命名为 `GeekNowVideoService`。

## 使用示例

### 0. 使用 Kling 模型生成视频

**⚠️ 重要**：所有视频生成 API 都使用 `multipart/form-data` 格式（即使不上传文件）

#### 0.1 Kling 基础文生视频

```dart
// 方法1：使用便捷方法（推荐）
final result = await helper.klingTextToVideo(
  prompt: '猫咪带着耳机听着歌走路，摇晃脑袋，大雨落下',
  size: '720x1280',
  seconds: 10,  // Kling 支持 5 或 10 秒
);

// 方法2：使用底层 API
final result = await service.generateVideos(
  prompt: '猫咪带着耳机听着歌走路，摇晃脑袋，大雨落下',
  model: VeoModel.klingO1,
  ratio: '720x1280',
  parameters: {'seconds': 10},
);

if (result.isSuccess) {
  final taskId = result.data!.first.videoId!;
  print('✅ 任务提交成功: $taskId');
  
  // 轮询任务状态直到完成
  final status = await helper.pollTaskUntilComplete(
    taskId: taskId,
    maxWaitMinutes: 15,
    onProgress: (progress, status) {
      print('进度: $progress%, 状态: $status');
    },
  );
  
  if (status.isSuccess && status.data!.hasVideo) {
    print('视频URL: ${status.data!.videoUrl}');
    print('模型: ${status.data!.model}');
    print('尺寸: ${status.data!.size}');
  }
}
```

#### 0.2 Kling 图生视频（首尾帧 URL 模式）

⚠️ **重要差异**：Kling 的首尾帧参数是 **URL 字符串**（不是文件路径）

```dart
// 使用在线图片 URL 作为首尾帧
final result = await helper.klingImageToVideoByUrl(
  prompt: '平滑过渡，镜头推进',
  firstFrameUrl: 'https://example.com/first.jpg',
  lastFrameUrl: 'https://example.com/last.jpg',  // 可选
  size: '720x1280',
  seconds: 10,
);

if (result.isSuccess) {
  final taskId = result.data!.first.videoId!;
  
  final status = await helper.pollTaskUntilComplete(taskId: taskId);
  
  if (status.isSuccess && status.data!.hasVideo) {
    print('Kling 视频: ${status.data!.videoUrl}');
  }
}
```

**与 VEO/Sora 的差异**：
- **VEO/Sora**: 使用本地文件路径（`referenceImagePaths`）
- **Kling**: 使用在线 URL（`first_frame_image`, `last_frame_image`）

#### 0.3 Kling 视频编辑

Kling 支持基于现有视频进行编辑：

```dart
// 编辑现有视频
final result = await helper.klingEditVideo(
  prompt: '添加黑白滤镜效果，增加颗粒感，复古风格',
  videoUrl: 'https://example.com/original-video.mp4',
  size: '720x1280',
  seconds: 10,
);

if (result.isSuccess) {
  final taskId = result.data!.first.videoId!;
  
  final status = await helper.pollTaskUntilComplete(
    taskId: taskId,
    onProgress: (progress, status) {
      print('编辑进度: $progress%');
    },
  );
  
  if (status.isSuccess && status.data!.hasVideo) {
    print('原视频: ${videoUrl}');
    print('编辑后: ${status.data!.videoUrl}');
  }
}
```

#### 0.4 Kling 高级组合（参考图 + 首尾帧）

```dart
// 组合使用本地参考图和在线首尾帧
final result = await helper.klingAdvancedGeneration(
  prompt: '融合参考图的风格，从首帧到尾帧平滑过渡',
  referenceImagePaths: [
    '/path/to/style_ref1.jpg',
    '/path/to/style_ref2.jpg',
  ],
  firstFrameUrl: 'https://example.com/start.jpg',
  lastFrameUrl: 'https://example.com/end.jpg',
  size: '720x1280',
  seconds: 10,
);
```

#### 0.5 Kling 参数说明

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `model` | String | ✅ | 固定为 `kling-video-o1` |
| `prompt` | String | ✅ | 视频描述提示词 |
| `size` | String | ❌ | 尺寸，默认 720x1280，可选 1280x720 |
| `seconds` | int | ❌ | 时长，支持 **5 或 10 秒** |
| `input_reference` | File | ❌ | 参考图片文件，可传多张 |
| `first_frame_image` | String (URL) | ❌ | 首帧图片 URL |
| `last_frame_image` | String (URL) | ❌ | 尾帧图片 URL |
| `video` | String (URL) | ❌ | 要编辑的视频 URL |

**💡 Python 代码对比**：
- Python 需要传递 `files={'placeholder': (None, '')}` 来强制 multipart/form-data
- Dart 实现中已自动使用 `http.MultipartRequest`，无需额外处理
- Dart 提供了自动轮询功能（`pollTaskUntilComplete`），Python 需要手动实现

### 0.6 使用豆包模型生成视频

豆包(Doubao)模型特点：**最灵活的时长**（4-11秒）和**多分辨率选择**（480p/720p/1080p）

#### 0.6.1 豆包基础文生视频

```dart
// 使用便捷方法（推荐）
final result = await helper.doubaoTextToVideo(
  prompt: '猫咪听歌摇头晃脑，下大雨',
  resolution: DoubaoResolution.p720,  // 720p 高清（推荐）
  aspectRatio: '16:9',  // 横屏
  seconds: 6,  // 6 秒（豆包支持 4-11 秒）
);

if (result.isSuccess) {
  final taskId = result.data!.first.videoId!;
  
  final status = await helper.pollTaskUntilComplete(
    taskId: taskId,
    onProgress: (progress, status) {
      print('豆包生成进度: $progress%');
    },
  );
  
  if (status.isSuccess && status.data!.hasVideo) {
    print('视频: ${status.data!.videoUrl}');
    print('分辨率: ${status.data!.model}');
  }
}
```

#### 0.6.2 豆包多分辨率对比

```dart
// 生成不同分辨率版本
final resolutions = [
  DoubaoResolution.p480,   // 480p - 快速、省钱
  DoubaoResolution.p720,   // 720p - 平衡
  DoubaoResolution.p1080,  // 1080p - 高质量
];

for (final resolution in resolutions) {
  final result = await helper.doubaoTextToVideo(
    prompt: '产品展示视频',
    resolution: resolution,
    aspectRatio: '16:9',
    seconds: 6,
  );
  
  print('生成${resolution.name}版本...');
}
```

#### 0.6.3 豆包智能宽高比

```dart
// keep_ratio - 保持上传图片的原始比例
final result1 = await helper.doubaoImageToVideo(
  prompt: '照片动起来',
  firstFrameImage: 'https://example.com/photo.jpg',
  resolution: DoubaoResolution.p1080,
  aspectRatio: DoubaoAspectRatio.keepRatio,  // 保持原始比例
  seconds: 6,
);

// adaptive - 自动选择最合适的比例
final result2 = await helper.doubaoImageToVideo(
  prompt: '智能调整',
  firstFrameImage: 'https://example.com/image.jpg',
  resolution: DoubaoResolution.p720,
  aspectRatio: DoubaoAspectRatio.adaptive,  // 智能选择
  seconds: 8,
);
```

#### 0.6.4 豆包灵活时长

```dart
// 豆包支持 4-11 秒的灵活时长（最宽范围）
final durations = [4, 6, 8, 10, 11];

for (final duration in durations) {
  final result = await helper.doubaoTextToVideo(
    prompt: '测试不同时长',
    resolution: DoubaoResolution.p720,
    aspectRatio: '16:9',
    seconds: duration,  // 4-11 秒都支持
  );
  
  print('生成${duration}秒版本');
}
```

#### 0.6.5 豆包参数说明

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `model` | String | ✅ | 分辨率版本（480p/720p/1080p） |
| `prompt` | String | ✅ | 视频描述提示词 |
| `size` | String | ❌ | 宽高比或智能模式 |
| `seconds` | Integer | ❌ | 时长，**4-11 秒**（最灵活） |
| `first_frame_image` | String | ❌ | 首帧图片（URL 或文件） |
| `last_frame_image` | String | ❌ | 尾帧图片（URL 或文件） |

**宽高比选项**：
- 标准比例：`16:9`, `4:3`, `1:1`, `3:4`, `9:16`, `21:9`
- 智能模式：`keep_ratio`（保持图片比例）, `adaptive`（自动选择）

**分辨率选择建议**：
- `480p`：快速测试、低成本、预览
- `720p`：日常使用、性价比高（推荐）
- `1080p`：专业输出、最高质量

### 0.7 使用 Grok 模型生成视频

Grok 模型特点：**固定 6 秒时长**，使用独特的 `aspect_ratio` 参数设计

```dart
// 使用便捷方法（推荐）
final result = await helper.grokTextToVideo(
  prompt: '猫咪听歌摇头晃脑，下大雨',
  aspectRatio: GrokAspectRatio.ratio2x3,  // 2:3 竖屏
  resolution: GrokResolution.p720,        // 720P 高清
);

if (result.isSuccess) {
  final taskId = result.data!.first.videoId!;
  
  final status = await helper.pollTaskUntilComplete(
    taskId: taskId,
    onProgress: (progress, status) {
      print('Grok 生成进度: $progress%');
    },
  );
  
  if (status.isSuccess && status.data!.hasVideo) {
    print('Grok 视频: ${status.data!.videoUrl}');
  }
}

// Grok 宽高比选项
GrokAspectRatio.ratio2x3  // 2:3 竖屏
GrokAspectRatio.ratio3x2  // 3:2 横屏
GrokAspectRatio.ratio1x1  // 1:1 方形

// Grok 分辨率选项
GrokResolution.p720   // 720P 高清
GrokResolution.p1080  // 1080P 超清
```

### 1. 文生视频（VEO 模型）

```dart
// 基础文生视频
final result = await helper.textToVideo(
  prompt: '猫咪带着耳机听着歌走路，摇晃脑袋，大雨落下',
  size: '720x1280',  // 视频尺寸
  seconds: 8,        // VEO 时长8秒
  quality: VeoQuality.standard,
  useFast: false,
);

if (result.isSuccess) {
  final video = result.data!.first;
  print('视频 URL: ${video.videoUrl}');
}
```

### 1.1 生成高清横屏视频

⚠️ **重要限制**：高清模式（`enable_upsample`）**仅支持横屏（1280x720）**

```dart
// 方法1：使用高清专用便捷方法（推荐）
final result = await helper.textToVideoHD(
  prompt: '城市夜景，霓虹灯闪烁，车流穿梭',
  seconds: 8,
  useFast: false,
);

// 方法2：使用标准方法并指定 enableUpsample 参数
final result = await helper.textToVideo(
  prompt: '城市夜景，霓虹灯闪烁，车流穿梭',
  size: '1280x720',  // 必须是横屏
  seconds: 8,
  quality: VeoQuality.standard,
  useFast: false,
  enableUpsample: true,  // 启用高清模式
);

if (result.isSuccess) {
  final taskId = result.data!.first.videoId;
  print('任务ID: $taskId，开始轮询...');
  
  // 轮询任务状态
  final status = await helper.pollTaskUntilComplete(
    taskId: taskId!,
    onProgress: (progress, status) {
      print('进度: $progress%, 状态: $status');
    },
  );
  
  if (status.isSuccess && status.data!.hasVideo) {
    print('高清视频URL: ${status.data!.videoUrl}');
  }
}
```

### 2. 图生视频 - 首帧模式

```dart
// 使用本地图片作为首帧
final result = await helper.imageToVideoFirstFrame(
  prompt: 'The scene slowly changes from day to night',
  firstFramePath: 'first_frame.jpg',  // 图片路径
  size: '720x1280',
  seconds: 8,
  quality: VeoQuality.standard,
  useFast: false,
);

if (result.isSuccess) {
  print('视频已生成: ${result.data!.first.videoUrl}');
}
```

### 3. 图生视频 - 首尾帧模式

```dart
// 生成从首帧到尾帧的过渡视频
final result = await helper.imageToVideoFrames(
  prompt: 'Smooth transition with camera movement',
  firstFramePath: 'start.jpg',  // 首帧路径
  lastFramePath: 'end.jpg',     // 尾帧路径
  size: '1280x720',  // 横向视频
  seconds: 8,
  quality: VeoQuality.fourK,  // 使用 4K
  useFast: false,
);

if (result.isSuccess) {
  print('过渡视频: ${result.data!.first.videoUrl}');
}
```

### 3.1 图生视频 - 高清模式

⚠️ **重要限制**：高清模式（`enable_upsample`）**仅支持横屏（1280x720）**

```dart
// 方法1：使用高清专用便捷方法-首帧模式（推荐）
final result = await helper.imageToVideoHD(
  prompt: '画面从静止慢慢动起来，增加细节和动态效果',
  firstFramePath: 'photo.jpg',
  seconds: 8,
  useFast: false,
);

// 方法2：使用高清专用便捷方法-首尾帧模式
final result = await helper.imageToVideoFramesHD(
  prompt: '从白天到夜晚的平滑过渡',
  firstFramePath: 'day.jpg',
  lastFramePath: 'night.jpg',
  seconds: 8,
  useFast: false,
);

// 方法3：使用标准方法并指定 enableUpsample 参数
final result = await helper.imageToVideoFirstFrame(
  prompt: '画面从静止慢慢动起来',
  firstFramePath: 'photo.jpg',
  size: '1280x720',  // 必须是横屏
  seconds: 8,
  quality: VeoQuality.standard,
  useFast: false,
  enableUpsample: true,  // 启用高清模式
);

if (result.isSuccess) {
  final taskId = result.data!.first.videoId;
  
  // 轮询直到完成
  final status = await helper.pollTaskUntilComplete(
    taskId: taskId!,
    onProgress: (progress, status) {
      print('进度: $progress%, 状态: $status');
    },
  );
  
  if (status.isSuccess && status.data!.hasVideo) {
    print('高清视频URL: ${status.data!.videoUrl}');
  }
}
```

### 4. 图生视频 - 参考图模式（多图）

```dart
// 使用多张参考图生成视频
final result = await helper.imageToVideoReference(
  prompt: '猫咪带着耳机听着歌走路，摇晃脑袋，大雨落下',
  referenceImagePaths: [
    'cat_ref1.jpg',
    'cat_ref2.png',
  ],
  size: '720x1280',
  seconds: 8,
  quality: VeoQuality.standard,
  useFast: false,
);

if (result.isSuccess) {
  print('参考图视频: ${result.data!.first.videoUrl}');
}
```

### 5. 快速生成（Fast 模式）

```dart
// 使用快速模式
final result = await helper.textToVideo(
  prompt: 'A bird flying in the sky',
  quality: VeoQuality.standard,
  useFast: true,  // 启用快速模式
);

// 或直接指定快速模型
final result2 = await service.generateVideos(
  prompt: 'A bird flying',
  model: VeoModel.fast,
);
```

### 6. Sora 角色引用（高级功能）⭐

```dart
// 步骤 1: 准备角色视频 URL（已上传的视频链接）
final characterVideoUrl = 'https://your-cdn.com/character_video.mp4';

// 步骤 2: 使用 Sora 生成保持角色一致的新视频
final result = await helper.soraWithCharacterReference(
  prompt: '猫咪带着耳机听着歌走路，摇晃脑袋，大雨落下',
  characterUrl: characterVideoUrl,
  characterTimestamps: '1,3',  // 角色在视频第1-3秒出现
  size: '720x1280',
  seconds: 10,
  useTurbo: false,  // 使用 Sora 2.0
);

if (result.isSuccess) {
  final taskId = result.data!.first.videoId;
  print('任务已提交: $taskId');
  
  // 步骤 3: 轮询等待完成
  final statusResult = await helper.pollTaskUntilComplete(
    taskId: taskId!,
    maxWaitMinutes: 10,
  );
  
  if (statusResult.isSuccess && statusResult.data!.url != null) {
    print('视频生成完成: ${statusResult.data!.url}');
  }
}
```

### 5. 高清视频生成（VEO 专属）

⚠️ **重要限制**：
- **仅支持横屏**：必须使用 `1280x720` 尺寸
- **不支持竖屏**：`720x1280` 无法使用高清模式
- **仅 VEO 模型支持**：Sora 模型不支持此功能

#### 5.1 高清文生视频

```dart
// 使用专用便捷方法（推荐）
final result = await helper.textToVideoHD(
  prompt: '海边日落，波浪轻拍沙滩，海鸥在天空飞翔',
  seconds: 8,
  useFast: false,  // false=标准质量，true=快速模式
);

if (result.isSuccess) {
  final taskId = result.data!.first.videoId;
  print('任务已提交，ID: $taskId');
  
  // 轮询任务状态
  final status = await helper.pollTaskUntilComplete(
    taskId: taskId!,
    maxWaitMinutes: 10,
    onProgress: (progress, status) {
      print('高清视频生成进度: $progress%');
    },
  );
  
  if (status.isSuccess && status.data!.hasVideo) {
    print('高清视频URL: ${status.data!.videoUrl}');
    print('视频尺寸: ${status.data!.size}');
  }
}
```

#### 5.2 高清图生视频（首帧模式）

```dart
final result = await helper.imageToVideoHD(
  prompt: '画面从静止变为动态，增加细节和动态效果',
  firstFramePath: '/path/to/photo.jpg',
  seconds: 8,
  useFast: false,
);

if (result.isSuccess) {
  // 处理任务（轮询逻辑同上）
}
```

#### 5.3 高清图生视频（首尾帧模式）

```dart
final result = await helper.imageToVideoFramesHD(
  prompt: '从白天到夜晚的平滑过渡，保持高清质量',
  firstFramePath: '/path/to/day.jpg',
  lastFramePath: '/path/to/night.jpg',
  seconds: 8,
  useFast: false,
);

if (result.isSuccess) {
  // 处理任务（轮询逻辑同上）
}
```

#### 5.4 使用标准方法启用高清

如果不使用专用便捷方法，可以通过参数启用：

```dart
// 文生视频 + 高清
final result = await helper.textToVideo(
  prompt: '科幻城市夜景',
  size: '1280x720',  // 必须是横屏
  seconds: 8,
  quality: VeoQuality.standard,
  useFast: false,
  enableUpsample: true,  // 启用高清模式
);

// 图生视频 + 高清
final result = await helper.imageToVideoFirstFrame(
  prompt: '增加动态效果',
  firstFramePath: '/path/to/image.jpg',
  size: '1280x720',  // 必须是横屏
  seconds: 8,
  quality: VeoQuality.standard,
  useFast: false,
  enableUpsample: true,  // 启用高清模式
);
```

#### 5.5 高清模式对比

| 特性 | 标准模式 | 高清模式 |
|------|---------|---------|
| 分辨率 | 标准 | 增强 |
| 细节表现 | 良好 | 优秀 |
| 生成时间 | 2-5 分钟 | 5-10 分钟 |
| 文件大小 | 较小 | 较大 |
| 支持尺寸 | 720x1280, 1280x720 | 仅 1280x720 |
| 适用场景 | 一般用途 | 高质量需求 |

#### 5.6 高清模式最佳实践

1. **尺寸检查**：始终使用 `1280x720`（横屏）
   ```dart
   // ✅ 正确
   size: '1280x720'
   
   // ❌ 错误 - 竖屏不支持高清
   size: '720x1280'
   ```

2. **提示词优化**：高清模式下，更详细的提示词能产生更好的效果
   ```dart
   // ✅ 好的提示词
   prompt: '4K高清城市夜景，霓虹灯闪烁，雨水在地面形成倒影，车流穿梭，细节丰富'
   
   // ❌ 过于简单
   prompt: '城市夜景'
   ```

3. **使用快速模式平衡**：如果不需要最高质量，可以使用快速模式
   ```dart
   await helper.textToVideoHD(
     prompt: '...',
     useFast: true,  // 快速高清模式，时间更短
   );
   ```

4. **预期等待时间**：高清模式通常需要 5-10 分钟
   ```dart
   final status = await helper.pollTaskUntilComplete(
     taskId: taskId!,
     maxWaitMinutes: 15,  // 给高清模式更多时间
     onProgress: (progress, status) {
       print('已等待: ${DateTime.now()}, 进度: $progress%');
     },
   );
   ```

### 6. 视频 Remix（重制/混音）

视频 Remix 功能允许基于现有视频进行重制，生成新的视频变体。可以用于风格转换、效果增强、氛围调整等。

#### 6.1 基础 Remix

```dart
// 风格转换
final result = await helper.remixVideo(
  videoId: 'video_123',  // 已完成的视频任务 ID
  prompt: '将视频转换成黑白电影风格，增加颗粒感和复古滤镜',
  seconds: 8,
  onProgress: (progress, status) {
    print('Remix 进度: $progress%');
  },
);

if (result.isSuccess && result.data!.hasVideo) {
  print('Remix 完成: ${result.data!.videoUrl}');
  print('原视频ID: ${result.data!.remixedFromVideoId}');
  print('新视频ID: ${result.data!.id}');
}
```

#### 6.2 常见 Remix 场景

**场景 1：风格转换**
```dart
final result = await helper.remixVideo(
  videoId: 'video_original',
  prompt: '转换成水彩画风格，柔和的色彩，艺术感',
  seconds: 8,
);
```

**场景 2：效果增强**
```dart
final result = await helper.remixVideo(
  videoId: 'video_original',
  prompt: '增强色彩饱和度，添加动态模糊效果，强化光线对比，4K质量',
  seconds: 8,
);
```

**场景 3：氛围调整**
```dart
final result = await helper.remixVideo(
  videoId: 'video_day',
  prompt: '改变为夜晚场景，添加月光效果，增加神秘氛围，星空点缀',
  seconds: 8,
);
```

**场景 4：特效添加**
```dart
final result = await helper.remixVideo(
  videoId: 'video_normal',
  prompt: '添加下雨效果，雨滴在镜头上，潮湿的地面反光',
  seconds: 8,
);
```

#### 6.3 批量 Remix

**方法 1：使用相同提示词 Remix 多个视频**
```dart
final results = await helper.remixMultipleVideos(
  videoIds: [
    'video_001',
    'video_002',
    'video_003',
  ],
  prompt: '转换成赛博朋克风格，霓虹灯效果，未来感',
  seconds: 8,
  maxWaitMinutes: 15,
);

// 查看结果
results.forEach((videoId, status) {
  if (status != null && status.hasVideo) {
    print('$videoId -> ${status.videoUrl}');
  } else {
    print('$videoId -> 失败');
  }
});
```

**方法 2：创建视频变体系列**
```dart
// 基于同一个原视频，创建多个不同风格的变体
final variations = await helper.createVideoVariations(
  videoId: 'video_original',
  prompts: [
    '黑白复古风格',
    '鲜艳卡通风格',
    '柔和梦幻风格',
    '强烈对比风格',
  ],
  seconds: 8,
  maxWaitMinutes: 15,
);

for (var i = 0; i < variations.length; i++) {
  final variation = variations[i];
  if (variation != null && variation.hasVideo) {
    print('变体${i + 1}: ${variation.videoUrl}');
  }
}
```

#### 6.4 Remix 最佳实践

1. **详细的提示词**：提供越详细的描述，效果越好
   ```dart
   // ❌ 不够详细
   prompt: '改变颜色'
   
   // ✅ 详细描述
   prompt: '将整体色调调整为暖色调，增强橙色和黄色，降低蓝色，营造温暖舒适的氛围'
   ```

2. **指定具体效果**：明确说明想要的视觉效果
   ```dart
   prompt: '添加电影级色彩分级，增加暗角效果，提高对比度，2.35:1宽银幕感觉'
   ```

3. **组合多种效果**：可以在一个提示词中组合多个效果
   ```dart
   prompt: '转换成手绘动画风格 + 增加景深效果 + 柔和的光晕 + 温暖的色调'
   ```

4. **使用艺术风格参考**：引用特定的艺术风格或电影风格
   ```dart
   prompt: '模仿韦斯·安德森电影的对称构图和柔和色彩，复古胶片质感'
   ```

#### 6.5 Remix 工作流程

**完整的 Remix 流程示例**
```dart
// 1. 首先生成原始视频
print('步骤1: 生成原始视频');
final originalResult = await helper.textToVideo(
  prompt: '一只猫在花园里玩耍',
  size: '720x1280',
  seconds: 8,
);

if (!originalResult.isSuccess) {
  print('原始视频生成失败');
  return;
}

final originalTaskId = originalResult.data!.first.videoId!;

// 2. 轮询原始视频状态
print('步骤2: 等待原始视频完成');
final originalStatus = await helper.pollTaskUntilComplete(
  taskId: originalTaskId,
  onProgress: (progress, status) {
    print('原始视频进度: $progress%');
  },
);

if (!originalStatus.isSuccess || !originalStatus.data!.hasVideo) {
  print('原始视频生成失败');
  return;
}

print('原始视频完成: ${originalStatus.data!.videoUrl}');

// 3. 对原始视频进行 Remix
print('步骤3: 开始 Remix');
final remixResult = await helper.remixVideo(
  videoId: originalTaskId,
  prompt: '转换成水彩画风格，柔和色彩，艺术感',
  seconds: 8,
  onProgress: (progress, status) {
    print('Remix 进度: $progress%');
  },
);

if (remixResult.isSuccess && remixResult.data!.hasVideo) {
  print('Remix 完成!');
  print('原始视频: ${originalStatus.data!.videoUrl}');
  print('Remix 视频: ${remixResult.data!.videoUrl}');
} else {
  print('Remix 失败: ${remixResult.errorMessage}');
}
```

#### 6.6 Remix 参数说明

| 参数 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `videoId` | String | ✅ | 原始视频的任务 ID（必须是已完成的视频） |
| `prompt` | String | ✅ | 描述如何修改视频的提示词 |
| `seconds` | int | ✅ | 新视频的时长（秒） |
| `maxWaitMinutes` | int | ❌ | 最大等待时间（分钟），默认 10 |
| `onProgress` | Function | ❌ | 进度回调函数 |

#### 6.7 注意事项

1. **原视频必须已完成**：
   - videoId 必须是已经生成完成的视频任务
   - 可以通过 `getVideoTaskStatus` 检查视频状态

2. **Remix 也是异步任务**：
   - Remix 操作会创建新的任务
   - 需要轮询新任务的状态
   - `remixVideo()` 方法会自动处理轮询

3. **生成时间**：
   - Remix 通常需要 2-8 分钟
   - 复杂的效果可能需要更长时间

4. **视频质量**：
   - Remix 可能会轻微影响视频质量
   - 建议从高质量原视频开始

5. **提示词重要性**：
   - 详细的提示词能产生更好的效果
   - 避免模糊或矛盾的描述

### 7. Sora 角色管理

⚠️ **注意**：角色功能是 Sora 专属，VEO 不支持

Sora 允许从视频中提取角色，然后在后续的视频生成中引用这个角色，保持角色的一致性。

#### 7.1 创建角色（从视频 URL）

```dart
// 从在线视频 URL 创建角色
final result = await helper.createCharacterFromUrl(
  videoUrl: 'https://example.com/cat-video.mp4',
  timestamps: '1,3',  // 角色在视频的 1-3 秒出现
);

if (result.isSuccess) {
  final character = result.data!;
  print('角色ID: ${character.id}');
  print('角色名称: ${character.mentionTag}');  // @username
  print('头像: ${character.profilePictureUrl}');
  print('主页: ${character.permalink}');
  
  if (character.profileDesc != null) {
    print('描述: ${character.profileDesc}');
  }
}
```

#### 7.2 创建角色（从已完成的任务）

```dart
// 1. 先生成包含角色的视频
final videoResult = await service.generateVideos(
  prompt: '一只可爱的橙色小猫，特写镜头，高清',
  model: VeoModel.sora2,
  ratio: '720x1280',
  parameters: {'seconds': 10},
);

// 2. 等待视频完成
final taskStatus = await helper.pollTaskUntilComplete(
  taskId: videoResult.data!.first.videoId!,
);

// 3. 从已完成的任务创建角色
final character = await helper.createCharacterFromTask(
  taskId: taskStatus.data!.id,
  timestamps: '1,3',  // 角色在第 1-3 秒出现
);

if (character.isSuccess) {
  print('角色创建成功: ${character.data!.mentionTag}');
  print('角色ID: ${character.data!.id}');
}
```

#### 7.3 完整的角色工作流程

使用一站式方法完成整个流程：

```dart
final result = await helper.soraCharacterWorkflow(
  initialPrompt: '一只可爱的橙色小猫，特写镜头，高清细节',
  characterTimestamps: '1,3',
  characterPrompt: '在花园里玩耍，追逐蝴蝶',
  seconds: 10,
);

if (result['character'] != null) {
  final character = result['character'] as SoraCharacter;
  print('✓ 角色: ${character.mentionTag}');
  print('  ID: ${character.id}');
  print('  头像: ${character.profilePictureUrl}');
  
  if (result['video'] != null) {
    final video = result['video'] as VeoTaskStatus;
    print('✓ 新视频: ${video.videoUrl}');
  }
} else {
  print('✗ 失败: ${result['error']}');
}
```

#### 7.4 角色数据模型

**SoraCharacter 类字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | String | 角色唯一标识符 |
| `username` | String | 角色名称（用于提示词） |
| `permalink` | String | 角色主页链接（OpenAI） |
| `profilePictureUrl` | String | 角色头像 URL |
| `profileDesc` | String? | 角色描述（可选） |
| `metadata` | Map | 原始响应数据 |

**便捷属性：**

| 属性 | 返回值 | 说明 |
|------|--------|------|
| `mentionTag` | `@{username}` | 用于提示词中的引用标签 |

#### 7.5 使用角色生成视频

创建角色后，可以在提示词中使用 `@username` 引用：

```dart
// 1. 创建角色
final character = await helper.createCharacterFromUrl(
  videoUrl: 'https://example.com/cat.mp4',
  timestamps: '1,2',
);

if (!character.isSuccess) {
  print('角色创建失败');
  return;
}

final cat = character.data!;
print('角色: ${cat.mentionTag}');  // 输出: @character_name

// 2. 在新视频中使用角色
final scenarios = [
  '让 ${cat.mentionTag} 在草地上奔跑',
  '让 ${cat.mentionTag} 跳舞',
  '让 ${cat.mentionTag} 睡觉',
];

for (final scenario in scenarios) {
  final result = await service.generateVideos(
    prompt: scenario,
    model: VeoModel.sora2,
    ratio: '720x1280',
    parameters: {'seconds': 10},
  );
  
  if (result.isSuccess) {
    final taskId = result.data!.first.videoId!;
    print('场景: $scenario - 任务ID: $taskId');
  }
}
```

#### 7.6 角色创建注意事项

1. **时间范围限制**：
   ```dart
   // ✅ 正确 - 范围 1-3 秒
   timestamps: '1,3'  // 差值 2 秒
   timestamps: '0,3'  // 差值 3 秒
   timestamps: '2,3'  // 差值 1 秒
   
   // ❌ 错误 - 范围超过 3 秒
   timestamps: '0,5'  // 差值 5 秒
   
   // ❌ 错误 - 范围小于 1 秒
   timestamps: '1,1.5'  // 差值 0.5 秒
   ```

2. **视频来源**：
   - **方式1**：从在线视频 URL（`url` 参数）
   - **方式2**：从已完成的 Sora 任务（`from_task` 参数）
   - **必须二选一**：不能同时提供或都不提供

3. **角色要求**：
   - ⚠️ **不能是真人**：只能是卡通、动物、虚拟角色
   - 角色在指定时间段内清晰可见
   - 建议使用特写或中景镜头

4. **视频要求**：
   - 视频必须包含明确的角色
   - 建议使用高质量视频
   - 角色在时间段内应保持一致

5. **返回数据**：
   - `username` 是用于提示词的关键字段
   - `permalink` 可以访问角色在 OpenAI 的详情页
   - `profilePictureUrl` 是角色的代表性头像

### 8. Sora 角色引用（使用已有角色）

💡 **提示**：如果您想使用角色功能，建议先阅读"7. Sora 角色管理"章节，了解如何创建和管理角色。

角色引用允许在视频生成时直接使用角色视频 URL 和时间戳，无需预先创建角色对象。

#### 8.1 两种角色使用方式对比

| 方式 | API | 使用场景 | 优势 |
|------|-----|---------|------|
| **角色创建** | `/sora/v1/characters` | 系列视频、角色复用 | 获得角色信息、便于管理 |
| **直接引用** | `/v1/videos` (character_url) | 单次使用 | 快速、无需额外步骤 |

**推荐使用策略**：
- **创建角色**：需要多次使用同一角色时
- **直接引用**：一次性使用或快速测试时

#### 8.2 角色引用参数说明

| 参数 | 类型 | 说明 | 示例 |
|------|------|------|------|
| `characterUrl` | String | 角色视频链接（⚠️ 不能含真人） | `https://xxx.com/cat.mp4` |
| `characterTimestamps` | String | 角色出现时间范围（格式：起始,结束） | `1,3`（第1-3秒） |
| 时间范围 | - | 结束 - 起始 必须在 1-3 秒之间 | ✅ `1,3` ✅ `0,2` ❌ `0,5` |

#### 8.3 直接引用示例

```dart
// 方式1：使用 soraWithCharacterReference（推荐）
final result = await helper.soraWithCharacterReference(
  prompt: '猫咪在草地上奔跑，快乐地摇尾巴',
  characterUrl: 'https://example.com/cat-video.mp4',
  characterTimestamps: '1,3',
  size: '720x1280',
  seconds: 10,
);

// 方式2：使用底层 generateVideos
final result = await service.generateVideos(
  prompt: '猫咪在草地上奔跑',
  model: VeoModel.sora2,
  ratio: '720x1280',
  parameters: {
    'seconds': 10,
    'character_url': 'https://example.com/cat-video.mp4',
    'character_timestamps': '1,3',
  },
);
```

#### ⚠️ 重要限制

1. **真人限制**：角色视频中不能出现真人，只能是卡通、动物、虚拟角色
2. **时间限制**：角色出现的时间段必须在 1-3 秒内
3. **异步处理**：生成任务是异步的，需要轮询查询状态

## 模型选择指南

### 标准版 vs 快速版

| 特性 | 标准版 | 快速版 |
|------|--------|--------|
| 质量 | 高 | 较高 |
| 速度 | 慢 | 快 |
| 适用 | 专业作品 | 快速预览 |

### 标准质量 vs 4K

| 特性 | 标准 | 4K |
|------|------|-----|
| 分辨率 | 标准 | 超高清 |
| 文件大小 | 较小 | 较大 |
| 适用 | 一般使用 | 专业输出 |

### 选择建议

```dart
// 开发测试：快速标准版
model: VeoModel.fast

// 预览展示：标准版
model: VeoModel.standard

// 专业输出：4K 版
model: VeoModel.standard4K

// 快速高清：快速 4K
model: VeoModel.fast4K

// 风格参考：Components 版
model: VeoModel.components

// 角色引用：Sora 2.0
model: VeoModel.sora2

// 快速预览：Sora Turbo
model: VeoModel.soraTurbo
```

## 在 Flutter 中使用

### 基础 Widget

```dart
class VeoVideoGenerator extends StatefulWidget {
  @override
  State<VeoVideoGenerator> createState() => _VeoVideoGeneratorState();
}

class _VeoVideoGeneratorState extends State<VeoVideoGenerator> {
  final _helper = VeoVideoHelper(
    VeoVideoService(ApiConfig(
      baseUrl: 'YOUR_BASE_URL',
      apiKey: 'YOUR_API_KEY',
    )),
  );

  final _promptController = TextEditingController();
  String? _videoUrl;
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _promptController,
          decoration: InputDecoration(
            labelText: '视频描述',
            hintText: '输入视频内容描述...',
          ),
        ),
        
        SizedBox(height: 16),
        
        ElevatedButton(
          onPressed: _isGenerating ? null : _generateVideo,
          child: Text(_isGenerating ? '生成中...' : '生成视频'),
        ),
        
        if (_videoUrl != null)
          Column(
            children: [
              SizedBox(height: 24),
              Text('生成的视频:'),
              // TODO: 使用视频播放器显示
              Text(_videoUrl!),
            ],
          ),
      ],
    );
  }

  Future<void> _generateVideo() async {
    setState(() => _isGenerating = true);
    
    try {
      final result = await _helper.textToVideo(
        prompt: _promptController.text,
        quality: VeoQuality.standard,
        useFast: false,
      );
      
      if (result.isSuccess) {
        setState(() {
          _videoUrl = result.data!.first.videoUrl;
        });
      }
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }
}
```

## 注意事项

1. **生成时间**：视频生成比图片慢，通常需要 2-10 分钟
2. **文件大小**：视频文件较大，注意网络传输
3. **请求格式**：⚠️ 必须使用 `multipart/form-data`，即使不传图片
4. **异步处理**：⚠️ API 返回任务 ID，需轮询查询状态获取视频
5. **模型选择**：根据需求选择合适的质量和速度
6. **图片数量**：注意不同数量图片对应不同模式
7. **Sora 角色引用**：
   - 必须先上传角色视频（不能含真人）
   - 指定角色出现的时间范围（1-3秒）
   - 时间戳格式：`起始秒,结束秒`（例如 `1,3`）
8. **视频尺寸**：支持 `720x1280`（竖屏）和 `1280x720`（横屏）
9. **时长限制**：
   - VEO 只允许生成 8 秒的视频
   - Sora 支持 10 或 15 秒
10. **⚠️ 高清模式限制**（`enable_upsample`）：
    - **仅支持横屏**：必须使用 `1280x720` 尺寸
    - **不支持竖屏**：`720x1280` 无法使用高清模式
    - **建议使用便捷方法**：`textToVideoHD()`, `imageToVideoHD()`, `imageToVideoFramesHD()`
    - 高清模式会增加生成时间
11. **视频 Remix**：
    - **原视频必须已完成**：只能 remix 已经生成完成的视频
    - **使用 JSON 格式**：Remix API 使用 `application/json`（不是 multipart/form-data）
    - **异步处理**：Remix 会创建新的任务，需要轮询状态
    - **生成时间**：通常需要 2-8 分钟
    - **提示词重要性**：详细的提示词能产生更好的效果
12. **Sora 角色管理**（创建角色）：
    - **Sora 专属功能**：仅 Sora 模型支持，VEO 不支持
    - **两种创建方式**：从视频 URL 或从已完成的任务 ID
    - **时间范围限制**：1-3 秒之间（差值最大 3 秒，最小 1 秒）
    - **不能是真人**：只能是卡通、动物、虚拟角色
    - **角色引用**：创建后在提示词中使用 `@username` 引用
13. **Kling 模型特性**：
    - **时长选择**：支持 5 秒或 10 秒（不同于 VEO 的固定 8 秒）
    - **首尾帧模式**：使用 URL 字符串（不是文件路径）
    - **视频编辑**：可以基于现有视频 URL 进行编辑
    - **参数差异**：首尾帧参数名为 `first_frame_image`/`last_frame_image`（URL）
14. **豆包(Doubao)模型特性**：
    - **最灵活的时长**：支持 4-11 秒（所有模型中范围最大）
    - **多分辨率选择**：480p（标清）/ 720p（高清）/ 1080p（超清）
    - **丰富的宽高比**：支持 6 种标准比例 + 2 种智能模式
    - **智能比例**：`keep_ratio`（保持图片比例）、`adaptive`（自动选择）
    - **首尾帧支持**：与 Kling 类似的参数名
15. **Grok 模型特性**：
    - **固定时长**：6 秒（不可调整）
    - **独特参数设计**：使用 `aspect_ratio` + `size` 参数
    - **宽高比**：3 种选项（2:3, 3:2, 1:1）
    - **分辨率**：720P 或 1080P

## 异步任务处理

### 完整流程示例

```dart
// 1. 提交任务
final submitResult = await helper.textToVideo(
  prompt: '猫咪听歌摇头晃脑，下大雨',
  size: '720x1280',
  seconds: 10,
);

if (!submitResult.isSuccess) {
  print('提交失败: ${submitResult.errorMessage}');
  return;
}

// 2. 获取任务 ID
final taskId = submitResult.data!.first.videoId!;
print('任务已提交: $taskId');

// 3. 轮询查询状态
final statusResult = await helper.pollTaskUntilComplete(
  taskId: taskId,
  maxWaitMinutes: 10,  // 最多等待 10 分钟
);

// 4. 处理结果
if (statusResult.isSuccess) {
  final status = statusResult.data!;
  
  if (status.isCompleted && status.url != null) {
    print('✅ 视频生成完成!');
    print('视频 URL: ${status.url}');
    print('模型: ${status.model}');
    print('尺寸: ${status.size}');
  } else {
    print('❌ 任务失败: ${status.failReason}');
  }
} else {
  print('查询失败: ${statusResult.errorMessage}');
}
```

### 手动查询状态

```dart
// 不使用轮询，手动查询
final service = VeoVideoService(config);
final statusResult = await service.getVideoTaskStatus(
  taskId: 'video_bbfbc1d2-ab22-44ca-b9dd-bc16983acac2',
);

if (statusResult.isSuccess) {
  final status = statusResult.data!;
  print('状态: ${status.status}');
  print('进度: ${status.progress}%');
  
  switch (status.status) {
    case 'queued':
      print('排队中...');
      break;
    case 'processing':
      print('处理中: ${status.progress}%');
      break;
    case 'completed':
      print('完成: ${status.videoUrl}');
      print('创建时间: ${status.createdAt}');
      print('完成时间: ${status.completedAt}');
      print('过期时间: ${status.expiresAt}');
      break;
    case 'failed':
      print('失败: ${status.errorMessage}');
      if (status.error != null) {
        print('错误码: ${status.error!.code}');
      }
      break;
    case 'cancelled':
      print('已取消');
      break;
  }
}
```

### 带进度回调的轮询

```dart
// 实时显示进度
final statusResult = await helper.pollTaskUntilComplete(
  taskId: taskId,
  maxWaitMinutes: 10,
  onProgress: (progress, status) {
    print('[$status] 进度: $progress%');
  },
);

if (statusResult.isSuccess && statusResult.data!.hasVideo) {
  print('✅ 视频已生成: ${statusResult.data!.videoUrl}');
}
```

## 任务状态详解

### VeoTaskStatus 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | String | 任务 ID |
| `status` | String | 状态（queued/processing/completed/failed/cancelled） |
| `progress` | int | 进度百分比（0-100） |
| `videoUrl` | String? | 视频下载地址（完成时可用） |
| `model` | String? | 使用的模型 |
| `size` | String? | 视频尺寸 |
| `seconds` | String? | 视频时长 |
| `createdAt` | int? | 创建时间戳 |
| `completedAt` | int? | 完成时间戳 |
| `expiresAt` | int? | 过期时间戳 |
| `error` | VeoTaskError? | 错误信息对象 |

### 便捷属性

```dart
status.isCompleted    // 是否完成
status.isFailed       // 是否失败
status.isCancelled    // 是否取消
status.isFinished     // 是否结束（完成/失败/取消）
status.isProcessing   // 是否处理中
status.hasVideo       // 是否有可用视频
status.errorMessage   // 获取错误消息
```

### 时间戳处理

```dart
final status = statusResult.data!;

if (status.createdAt != null) {
  final created = DateTime.fromMillisecondsSinceEpoch(status.createdAt! * 1000);
  print('创建时间: $created');
}

if (status.completedAt != null) {
  final completed = DateTime.fromMillisecondsSinceEpoch(status.completedAt! * 1000);
  print('完成时间: $completed');
}

if (status.expiresAt != null) {
  final expires = DateTime.fromMillisecondsSinceEpoch(status.expiresAt! * 1000);
  print('过期时间: $expires');
  
  final now = DateTime.now();
  if (now.isAfter(expires)) {
    print('⚠️ 视频已过期');
  }
}
```

## 错误处理

```dart
final result = await helper.textToVideo(prompt: 'test');

if (result.isSuccess) {
  final videos = result.data!;
  for (final video in videos) {
    print('任务 ID: ${video.videoId}');
    print('状态: ${video.metadata['status']}');
  }
} else {
  print('错误: ${result.errorMessage}');
  print('状态码: ${result.statusCode}');
}

// 查询任务时的错误处理
final statusResult = await service.getVideoTaskStatus(taskId: taskId);
if (statusResult.isSuccess) {
  final status = statusResult.data!;
  
  if (status.isFailed && status.error != null) {
    print('错误: ${status.error}');  // 自动格式化为 [code] message
    print('错误码: ${status.error!.code}');
    print('错误消息: ${status.error!.message}');
  }
}
```

## 完整示例

查看 `lib/examples/veo_video_example.dart` 了解更多使用示例。

---

**使用 Veo 创建精彩的 AI 视频！🎬✨**
