# ✅ TASK 7: 网页服务商设置界面 - 完成报告

## 📋 任务概述
在设置页面添加网页服务商（Vidu、即梦、可灵、海螺）的配置界面，与现有 API 服务商完全隔离。

## ✅ 已完成的工作

### 1. 创建 `_buildWebProviderConfig` 方法
**位置**: `lib/features/home/presentation/settings_page.dart` (第 3378 行附近)

**功能**:
- 统一的网页服务商配置界面构建器
- 支持多平台（vidu, jimeng, keling, hailuo）
- 动态显示工具选择（文生视频、图生视频、参考生视频等）
- 动态显示模型选择（根据选择的工具显示对应模型）
- 自动保存配置

**参数**:
```dart
Widget _buildWebProviderConfig({
  required String provider,        // 服务商名称
  required String modelType,        // 'image' 或 'video'
  required String? selectedTool,    // 当前选择的工具
  required String? selectedModel,   // 当前选择的模型
  required Function(String) onToolChanged,   // 工具变更回调
  required Function(String) onModelChanged,  // 模型变更回调
})
```

**界面元素**:
- 工具选择下拉框（带图标）
- 模型选择下拉框（带描述）
- 保存按钮

### 2. 更新 `_buildVideoForm` 方法
**位置**: `lib/features/home/presentation/settings_page.dart` (第 1991 行附近)

**修改内容**:
- ✅ 添加 `isWebProvider` 判断逻辑
- ✅ 根据服务商类型显示不同界面：
  - 网页服务商：显示工具和模型选择
  - API 服务商：显示 API Key、Base URL、模型选择
- ✅ 切换服务商时自动重置配置
- ✅ 添加 `modelType: 'video'` 参数传递
- ✅ 更新提示文本（网页服务商 vs API 服务商）

### 3. `_buildImageForm` 方法（已存在）
**位置**: `lib/features/home/presentation/settings_page.dart` (第 1866 行附近)

**状态**: 已经实现了网页服务商支持，现在可以正常工作

## 🎯 功能特性

### 网页服务商配置（Vidu 示例）
```dart
final Map<String, dynamic> _viduConfig = {
  'tools': {
    'image': [
      {'id': 'text2image', 'name': '文生图片', 'icon': Icons.image},
      {'id': 'ref2image', 'name': '参考生图', 'icon': Icons.collections},
    ],
    'video': [
      {'id': 'text2video', 'name': '文生视频', 'icon': Icons.videocam},
      {'id': 'img2video', 'name': '图生视频', 'icon': Icons.video_library},
      {'id': 'ref2video', 'name': '参考生视频', 'icon': Icons.video_collection},
    ],
  },
  'models': {
    'text2video': [
      {'id': 'vidu-q3', 'name': 'Vidu Q3', 'desc': '免费5次'},
      {'id': 'vidu-q2', 'name': 'Vidu Q2', 'desc': '动态精准，速度精准'},
      {'id': 'vidu-q1', 'name': 'Vidu Q1', 'desc': '画面更清晰'},
    ],
    // ... 其他工具的模型
  },
};
```

### 配置保存逻辑
- 图片配置：`image_web_tool`, `image_web_model`
- 视频配置：`video_web_tool`, `video_web_model`
- 使用 `SharedPreferences` 持久化存储

## 📊 服务商列表

### 图片模型服务商
- OpenAI
- GeekNow
- Yunwu（云雾）
- ComfyUI（本地）
- Azure
- Anthropic
- **Vidu（网页服务商）** ✅
- **即梦（网页服务商）** ✅
- **可灵（网页服务商）** ✅
- **海螺（网页服务商）** ✅

### 视频模型服务商
- OpenAI
- GeekNow
- Yunwu（云雾）
- ComfyUI（本地）
- Azure
- Anthropic
- **Vidu（网页服务商）** ✅
- **即梦（网页服务商）** ✅
- **可灵（网页服务商）** ✅
- **海螺（网页服务商）** ✅

## 🔄 用户交互流程

### 选择网页服务商
1. 用户在"图片模型"或"视频模型"标签页
2. 从"API 服务商"下拉框选择网页服务商（如 Vidu）
3. 界面自动切换为网页服务商配置界面

### 配置网页服务商
1. 选择工具类型（如"文生视频"）
2. 选择具体模型（如"Vidu Q3"）
3. 点击"保存配置"按钮
4. 配置自动保存到本地

### 切换回 API 服务商
1. 从下拉框选择 API 服务商（如 OpenAI）
2. 界面自动切换为 API 配置界面
3. 显示 API Key、Base URL、模型选择

## 🎨 界面设计

### 网页服务商界面
```
┌─────────────────────────────────────┐
│ API 服务商                          │
│ [Vidu（网页服务商）        ▼]      │
├─────────────────────────────────────┤
│ 选择工具                            │
│ 选择要使用的生成工具类型            │
│ [📹 文生视频               ▼]      │
├─────────────────────────────────────┤
│ 选择模型                            │
│ 选择要使用的具体模型                │
│ [Vidu Q3                   ▼]      │
│  免费5次                            │
├─────────────────────────────────────┤
│ [保存配置]                          │
└─────────────────────────────────────┘
```

### API 服务商界面（原有）
```
┌─────────────────────────────────────┐
│ API 服务商                          │
│ [OpenAI                    ▼]      │
├─────────────────────────────────────┤
│ API Key                             │
│ [sk-...                    👁 📋]  │
├─────────────────────────────────────┤
│ Base URL (API 地址)                 │
│ [https://api.openai.com/v1]        │
├─────────────────────────────────────┤
│ 选择推理模型                        │
│ [gpt-4-turbo              ▼]      │
├─────────────────────────────────────┤
│ [保存配置] [测试连接]               │
└─────────────────────────────────────┘
```

## 🔧 技术实现

### 状态管理
```dart
// 网页服务商配置（图片）
String? _imageWebTool;   // 选择的工具类型
String? _imageWebModel;  // 选择的模型

// 网页服务商配置（视频）
String? _videoWebTool;   // 选择的工具类型
String? _videoWebModel;  // 选择的模型
```

### 配置加载
```dart
Future<void> _loadImageConfig() async {
  // ... 加载 API 配置
  
  // ✅ 加载网页服务商配置
  final webTool = prefs.getString('image_web_tool');
  final webModel = prefs.getString('image_web_model');
  
  setState(() {
    _imageWebTool = webTool;
    _imageWebModel = webModel;
  });
}
```

### 配置保存
```dart
Future<void> _saveImageConfig() async {
  final isWebProvider = ['vidu', 'jimeng', 'keling', 'hailuo'].contains(_imageProvider);
  
  if (isWebProvider) {
    // 保存网页服务商配置
    if (_imageWebTool != null) {
      await prefs.setString('image_web_tool', _imageWebTool!);
    }
    if (_imageWebModel != null) {
      await prefs.setString('image_web_model', _imageWebModel!);
    }
  } else {
    // 保存 API 服务商配置
    // ...
  }
}
```

## ✅ 验证清单

- [x] `_buildWebProviderConfig` 方法已创建
- [x] `_buildImageForm` 支持网页服务商
- [x] `_buildVideoForm` 支持网页服务商
- [x] 工具选择下拉框正常工作
- [x] 模型选择下拉框正常工作
- [x] 配置保存逻辑正常
- [x] 配置加载逻辑正常
- [x] 切换服务商时重置配置
- [x] 界面提示文本正确
- [x] 代码编译无错误

## 🚀 下一步工作

### TASK 8: 集成 AutomationApiClient
在生成图片/视频的逻辑中添加判断：
- 如果是网页服务商，调用 `AutomationApiClient.submitGenerationTask()`
- 如果是 API 服务商，走原来的 API 路线

**需要修改的文件**:
- 图片生成逻辑（可能在 `character_generation_page.dart` 或其他页面）
- 视频生成逻辑（可能在相关的视频生成页面）

**实现思路**:
```dart
// 伪代码示例
Future<void> generateImage(String prompt) async {
  final prefs = await SharedPreferences.getInstance();
  final provider = prefs.getString('image_provider') ?? 'openai';
  
  if (['vidu', 'jimeng', 'keling', 'hailuo'].contains(provider)) {
    // 网页服务商路线
    final tool = prefs.getString('image_web_tool');
    final model = prefs.getString('image_web_model');
    
    final result = await AutomationApiClient.submitGenerationTask(
      platform: provider,
      toolType: tool,
      payload: {'prompt': prompt, 'model': model},
    );
    
    // 处理结果
  } else {
    // API 服务商路线（原有逻辑）
    // ...
  }
}
```

## 📝 总结

TASK 7 已完成！设置页面现在可以：
1. ✅ 显示网页服务商选项（Vidu、即梦、可灵、海螺）
2. ✅ 根据服务商类型显示不同的配置界面
3. ✅ 支持工具和模型的动态选择
4. ✅ 自动保存和加载配置
5. ✅ 完全隔离现有 API 服务商功能

用户现在可以在设置中选择网页服务商并配置相应的工具和模型。下一步需要在实际的生成逻辑中集成 `AutomationApiClient` 来调用 Python 后端。
