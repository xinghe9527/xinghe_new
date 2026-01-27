# GeekNow 服务架构重构计划

## 🎯 重构目标

将现有的代码和文档重新组织，正确反映 **GeekNow 作为唯一服务商**的事实，按照**功能区域**（LLM、图片、视频、上传）来组织所有内容。

## ❌ 当前问题

1. **文件命名混乱**：
   - `openai_service.dart` - 误导性命名，实际是 GeekNow 图像服务
   - `veo_video_service.dart` - 误导性命名，实际是 GeekNow 视频服务

2. **文档描述混乱**：
   - 多次提到 "OpenAI Sora"、"Google VEO" 等
   - 让人误以为是连接到多个不同的服务提供商

3. **架构理解偏差**：
   - 实际：GeekNow 是统一的 API Gateway
   - 误解：多个独立的服务提供商

## ✅ 重构方案

### 阶段 1: 文件重命名

#### 核心服务文件

| 旧文件名 | 新文件名 | 说明 |
|---------|---------|------|
| `openai_service.dart` | `geeknow_image_service.dart` | GeekNow 图像服务 |
| `veo_video_service.dart` | `geeknow_video_service.dart` | GeekNow 视频服务 |
| - | `geeknow_llm_service.dart` | GeekNow LLM 服务（新建） |
| - | `geeknow_upload_service.dart` | GeekNow 上传服务（新建） |

#### 文档文件

| 旧文件名 | 新文件名 | 说明 |
|---------|---------|------|
| `OPENAI_CHAT_IMAGE_USAGE.md` | `GEEKNOW_IMAGE_GUIDE.md` | 图片生成指南 |
| `OPENAI_CHAT_IMAGE_README.md` | `GEEKNOW_IMAGE_README.md` | 图片功能概述 |
| `VEO_VIDEO_USAGE.md` | `GEEKNOW_VIDEO_GUIDE.md` | 视频生成指南 |
| - | `GEEKNOW_LLM_GUIDE.md` | LLM 使用指南（新建） |
| - | `GEEKNOW_COMPLETE_GUIDE.md` | 完整服务指南（新建） |

### 阶段 2: 代码重构

#### 2.1 创建统一的 GeekNow 服务类

```dart
// lib/services/api/providers/geeknow_service.dart
class GeekNowService extends ApiServiceBase {
  GeekNowService(super.config);
  
  @override
  String get providerName => 'GeekNow';
  
  // 四个功能区域的方法
  // 1. LLM 区域
  Future<ApiResponse<LlmResponse>> generateText(...);
  
  // 2. 图片区域
  Future<ApiResponse<ChatImageResponse>> generateImagesByChat(...);
  
  // 3. 视频区域
  Future<ApiResponse<List<VideoResponse>>> generateVideos(...);
  Future<ApiResponse<VideoTaskStatus>> getVideoTaskStatus(...);
  Future<ApiResponse<VideoTaskStatus>> remixVideo(...);
  Future<ApiResponse<SoraCharacter>> createCharacter(...);
  
  // 4. 上传区域
  Future<ApiResponse<UploadResponse>> uploadAsset(...);
}
```

#### 2.2 创建区域辅助类

```dart
// lib/services/api/providers/geeknow_helpers.dart

/// GeekNow 图片生成辅助类
class GeekNowImageHelper {
  final GeekNowService service;
  GeekNowImageHelper(this.service);
  
  // 图片生成便捷方法
  Future<String?> textToImage({required String prompt}) { ... }
  Future<String?> imageToImage({required String imagePath, required String prompt}) { ... }
  // ... 其他 11 个方法
}

/// GeekNow 视频生成辅助类
class GeekNowVideoHelper {
  final GeekNowService service;
  GeekNowVideoHelper(this.service);
  
  // 通用视频生成
  Future<ApiResponse<List<VideoResponse>>> generateVideo({
    required String model,  // 用户选择的模型
    required String prompt,
    required int seconds,
    Map<String, dynamic>? parameters,
  }) { ... }
  
  // VEO 系列方法
  Future<ApiResponse<List<VideoResponse>>> veoTextToVideo(...) { ... }
  Future<ApiResponse<List<VideoResponse>>> veoTextToVideoHD(...) { ... }
  
  // Sora 系列方法
  Future<ApiResponse<List<VideoResponse>>> soraWithCharacterReference(...) { ... }
  Future<ApiResponse<SoraCharacter>> createCharacterFromUrl(...) { ... }
  
  // Kling 系列方法
  Future<ApiResponse<List<VideoResponse>>> klingTextToVideo(...) { ... }
  Future<ApiResponse<List<VideoResponse>>> klingEditVideo(...) { ... }
  
  // Doubao 系列方法
  Future<ApiResponse<List<VideoResponse>>> doubaoTextToVideo(...) { ... }
  
  // Grok 系列方法
  Future<ApiResponse<List<VideoResponse>>> grokTextToVideo(...) { ... }
  
  // 通用任务管理
  Future<ApiResponse<VideoTaskStatus>> pollTaskUntilComplete(...) { ... }
}
```

#### 2.3 创建模型定义类

```dart
// lib/services/api/providers/geeknow_models.dart

/// GeekNow LLM 模型
class GeekNowLLMModels {
  static const String gpt4 = 'gpt-4';
  static const String gpt4o = 'gpt-4o';
  // ...
}

/// GeekNow 图像模型
class GeekNowImageModels {
  static const String gpt4o = 'gpt-4o';
  static const String dalle3 = 'dall-e-3';
  // ...
}

/// GeekNow 视频模型
class GeekNowVideoModels {
  // VEO 系列
  static const String veo31 = 'veo_3_1';
  static const String veo31_4K = 'veo_3_1-4K';
  // ...
  
  // Sora 系列
  static const String sora2 = 'sora-2';
  static const String soraTurbo = 'sora-turbo';
  
  // Kling 系列
  static const String klingO1 = 'kling-video-o1';
  
  // Doubao 系列
  static const String doubao480p = 'doubao-seedance-1-5-pro_480p';
  static const String doubao720p = 'doubao-seedance-1-5-pro_720p';
  static const String doubao1080p = 'doubao-seedance-1-5-pro_1080p';
  
  // Grok 系列
  static const String grokVideo3 = 'grok-video-3';
  
  /// 按系列分类
  static List<String> get veoModels => [...];
  static List<String> get soraModels => [...];
  static List<String> get klingModels => [...];
  static List<String> get doubaoModels => [...];
  static List<String> get grokModels => [...];
  
  /// 所有视频模型
  static List<String> get allModels => [...];
}
```

### 阶段 3: 文档重构

#### 3.1 创建主指南

**`GEEKNOW_COMPLETE_GUIDE.md`** - 总指南
- GeekNow 服务概述
- 四个功能区域介绍
- 快速开始
- 配置说明

#### 3.2 创建区域指南

**`GEEKNOW_LLM_GUIDE.md`** - LLM 区域
- 支持的 LLM 模型列表
- 使用示例
- 参数说明

**`GEEKNOW_IMAGE_GUIDE.md`** - 图片区域
- 支持的图像模型列表
- 对话格式生图
- 图片编辑和增强
- 所有便捷方法

**`GEEKNOW_VIDEO_GUIDE.md`** - 视频区域
- 支持的视频模型列表（按系列分类）
- VEO 系列使用（8个模型）
- Sora 系列使用（2个模型）
- Kling 系列使用（1个模型）
- Doubao 系列使用（3个模型）
- Grok 系列使用（1个模型）
- 通用任务管理

**`GEEKNOW_UPLOAD_GUIDE.md`** - 上传区域
- 文件上传
- 支持的文件类型
- 使用示例

#### 3.3 更新所有变更日志

在所有变更日志开头添加说明：
```markdown
⚠️ **服务商说明**：本功能由 GeekNow 服务提供。GeekNow 是一个统一的 AI API Gateway，
集成了多种 AI 模型（包括基于 OpenAI、Google、快手等技术的模型），但所有请求都通过 
GeekNow 的统一接口访问。
```

### 阶段 4: UI 集成逻辑

#### 4.1 用户选择流程

```dart
// 1. 用户选择服务商
final selectedProvider = 'GeekNow';

// 2. 用户选择功能区域
enum GeekNowRegion {
  llm,      // LLM 大语言模型
  image,    // 图片生成
  video,    // 视频生成
  upload,   // 文件上传
}

final selectedRegion = GeekNowRegion.video;

// 3. 根据区域显示对应的模型列表
List<String> getModelsForRegion(GeekNowRegion region) {
  switch (region) {
    case GeekNowRegion.llm:
      return GeekNowLLMModels.allModels;
    case GeekNowRegion.image:
      return GeekNowImageModels.allModels;
    case GeekNowRegion.video:
      return GeekNowVideoModels.allModels;  // 15 个视频模型
    case GeekNowRegion.upload:
      return [];  // 上传不需要选择模型
  }
}

// 4. 用户选择具体模型
final selectedModel = 'veo_3_1';  // 或 'sora-2', 'kling-video-o1' 等

// 5. 执行操作
final geekNow = GeekNowService(config);
final result = await geekNow.generateVideos(
  prompt: '...',
  model: selectedModel,
  parameters: {...},
);
```

#### 4.2 UI 示例（伪代码）

```dart
// 服务商选择
DropdownButton(
  items: ['GeekNow', 'Midjourney', 'Custom'],
  onChanged: (provider) {
    setState(() => selectedProvider = provider);
  },
);

// 区域选择（仅当选择 GeekNow 时显示）
if (selectedProvider == 'GeekNow') {
  DropdownButton(
    items: ['LLM', '图片生成', '视频生成', '上传'],
    onChanged: (region) {
      setState(() => selectedRegion = region);
      // 更新模型列表
      updateModelList(region);
    },
  );
}

// 模型选择（根据区域动态变化）
DropdownButton(
  items: getModelsForRegion(selectedRegion),
  onChanged: (model) {
    setState(() => selectedModel = model);
  },
);
```

## 📊 重构优先级

### 🔴 高优先级（立即执行）

1. ✅ 创建 `GEEKNOW_SERVICE_README.md` - 说明正确的服务架构
2. ✅ 创建 `REFACTORING_PLAN.md` - 本文档
3. ⏳ 重命名核心服务文件
4. ⏳ 更新主使用指南
5. ⏳ 创建 GeekNow 完整指南

### 🟡 中优先级（后续执行）

6. 更新所有变更日志，添加 GeekNow 说明
7. 更新所有示例代码
8. 重新组织文档目录结构

### 🟢 低优先级（可选）

9. 创建 UI 集成示例
10. 添加更多单元测试
11. 性能优化文档

## 🛠️ 具体执行步骤

### 步骤 1: 文件重命名（保留兼容性）

建议使用**软链接或别名**方式，保持向后兼容：

```dart
// 新文件：geeknow_service.dart（主服务）
// 旧文件：openai_service.dart, veo_video_service.dart 保留，但标记为 deprecated

// geeknow_service.dart
export 'openai_service.dart';  // 临时导出，逐步迁移
export 'veo_video_service.dart';

// 或者直接在旧文件顶部添加注释：
/// @deprecated
/// ⚠️ 注意：本文件实际是 GeekNow 图像服务的实现
/// GeekNow 是统一的 API Gateway，提供多种 AI 模型访问
/// 请参阅 GEEKNOW_SERVICE_README.md 了解正确的架构
```

### 步骤 2: 文档更新模板

在每个文档开头添加：

```markdown
# GeekNow [功能区域] 使用指南

## ⚠️ 服务商说明

本指南介绍如何使用 **GeekNow 服务**的 [功能区域] 功能。

**GeekNow** 是一个统一的 AI API Gateway，它集成了多种 AI 模型：
- 本指南涉及的模型（如 Sora、VEO、Kling 等）都是通过 GeekNow 的统一接口访问
- 您只需要一个 GeekNow API Key
- 所有请求都发送到 GeekNow 的服务器
- GeekNow 内部会路由到相应的 AI 模型

## 配置

```dart
final config = ApiConfig(
  baseUrl: 'https://your-geeknow-api.com',  // GeekNow API 地址
  apiKey: 'your-geeknow-key',               // GeekNow API Key
);

final geekNow = GeekNowService(config);
```
```

### 步骤 3: 创建主指南文档

**`GEEKNOW_COMPLETE_GUIDE.md`** 结构：

```markdown
# GeekNow API 完整使用指南

## 服务概述
GeekNow 是一个统一的 AI API Gateway...

## 功能区域
### 1. LLM 区域
- 支持的模型
- 使用方法
- 详细指南链接

### 2. 图片生成区域
- 支持的模型
- 使用方法
- 详细指南链接

### 3. 视频生成区域
- 支持的模型（按系列分类）
  - VEO 系列（8 个）
  - Sora 系列（2 个）
  - Kling 系列（1 个）
  - Doubao 系列（3 个）
  - Grok 系列（1 个）
- 使用方法
- 详细指南链接

### 4. 上传区域
- 文件上传
- 使用方法
```

## 📝 重命名命令（供参考）

```bash
# 核心服务文件
mv openai_service.dart geeknow_image_service.dart
mv veo_video_service.dart geeknow_video_service.dart

# 文档文件
mv OPENAI_CHAT_IMAGE_USAGE.md GEEKNOW_IMAGE_GUIDE.md
mv OPENAI_CHAT_IMAGE_README.md GEEKNOW_IMAGE_README.md
mv VEO_VIDEO_USAGE.md GEEKNOW_VIDEO_GUIDE.md

# 示例文件
mv examples/openai_chat_image_example.dart examples/geeknow_image_example.dart
mv examples/kling_video_example.dart examples/geeknow_kling_example.dart
mv examples/doubao_video_example.dart examples/geeknow_doubao_example.dart
```

## 🎯 用户交互流程（正确版本）

### UI 流程图

```
1. 选择服务商
   └─> [GeekNow] [Midjourney] [Custom]
        │
        ↓
2. 选择功能区域（仅 GeekNow）
   └─> [LLM] [图片生成] [视频生成] [上传]
        │
        ↓
3. 选择模型（根据区域动态显示）
   │
   ├─> LLM 区域模型：
   │   [gpt-4o] [gpt-4-turbo] [gpt-3.5-turbo]
   │
   ├─> 图片区域模型：
   │   [gpt-4o] [dall-e-3] [dall-e-2]
   │
   ├─> 视频区域模型：
   │   [VEO系列▼] [Sora系列▼] [Kling] [Doubao系列▼] [Grok]
   │    │
   │    ├─> VEO 系列：
   │    │   [veo_3_1] [veo_3_1-4K] [veo_3_1-fast] ...
   │    │
   │    ├─> Sora 系列：
   │    │   [sora-2] [sora-turbo]
   │    │
   │    ├─> Doubao 系列：
   │    │   [480p] [720p] [1080p]
   │    │
   │    └─> 单一模型：[kling-video-o1] [grok-video-3]
   │
   └─> 上传区域：无需选择模型
```

### 代码实现

```dart
class ApiRegionSelector extends StatefulWidget {
  @override
  _ApiRegionSelectorState createState() => _ApiRegionSelectorState();
}

class _ApiRegionSelectorState extends State<ApiRegionSelector> {
  String selectedProvider = 'GeekNow';
  String selectedRegion = 'video';
  String selectedModel = '';
  
  List<String> getModelList() {
    if (selectedProvider != 'GeekNow') return [];
    
    switch (selectedRegion) {
      case 'llm':
        return GeekNowLLMModels.allModels;
      case 'image':
        return GeekNowImageModels.allModels;
      case 'video':
        return GeekNowVideoModels.allModels;  // 15 个视频模型
      case 'upload':
        return [];  // 上传不需要模型
      default:
        return [];
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 服务商选择
        DropdownButton<String>(
          value: selectedProvider,
          items: ['GeekNow', 'Midjourney', 'Custom']
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (value) {
            setState(() {
              selectedProvider = value!;
              selectedRegion = '';
              selectedModel = '';
            });
          },
        ),
        
        // 区域选择（仅 GeekNow）
        if (selectedProvider == 'GeekNow')
          DropdownButton<String>(
            value: selectedRegion,
            items: ['llm', 'image', 'video', 'upload']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (value) {
              setState(() {
                selectedRegion = value!;
                selectedModel = '';  // 重置模型选择
              });
            },
          ),
        
        // 模型选择
        if (selectedProvider == 'GeekNow' && selectedRegion.isNotEmpty)
          DropdownButton<String>(
            value: selectedModel.isEmpty ? null : selectedModel,
            items: getModelList()
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (value) {
              setState(() => selectedModel = value!);
            },
          ),
      ],
    );
  }
}
```

## 📋 待办清单

### 立即执行

- [x] 创建 `GEEKNOW_SERVICE_README.md` - 说明正确架构
- [x] 创建 `REFACTORING_PLAN.md` - 重构计划
- [ ] 创建 `GEEKNOW_COMPLETE_GUIDE.md` - 总使用指南
- [ ] 更新 `VEO_VIDEO_USAGE.md` 开头，添加 GeekNow 说明
- [ ] 更新 `OPENAI_CHAT_IMAGE_USAGE.md` 开头，添加 GeekNow 说明

### 后续执行

- [ ] 重命名核心服务文件（或添加 deprecated 注释）
- [ ] 创建区域指南（LLM、图片、视频、上传）
- [ ] 更新所有示例代码
- [ ] 更新所有变更日志

## 💬 与用户确认

在执行大规模重构前，需要确认：

1. ✅ 是否保留旧文件名（向后兼容）？
2. ✅ 是否需要立即重命名所有文件？
3. ✅ 文档更新的优先级？
4. ✅ UI 集成的具体需求？

---

**创建日期**: 2026-01-26
**状态**: 等待用户确认
**目标**: 正确反映 GeekNow 作为统一服务商的架构
