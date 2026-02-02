# ComfyUI 视频生成问题修复

## 问题分析

用户反馈使用ComfyUI生成视频时"一点击就失败"，且看不到任何错误信息。

经过代码分析，发现了以下关键问题：

### 1. 工作流类型识别错误 ⚠️
**问题位置**: `lib/features/home/presentation/settings_page.dart:819-826`

**问题描述**: 
- 工作流文件 `video-wan2.2smoothmix.json` 被识别为 `image` 类型
- 原因：代码只检查 `video_` 前缀（下划线），而用户的文件名使用 `video-`（横杠）

**日志证据**:
```
✅ 读取工作流: video-wan2.2smoothmix.json (image)  // ❌ 应该是 video！
```

### 2. 服务创建硬编码错误 🚨
**问题位置**: `lib/features/home/presentation/video_space.dart:535`

**问题描述**:
- 视频生成代码硬编码使用了 `VeoVideoService`
- **完全忽略**了用户在设置中选择的服务商（如 ComfyUI）
- 导致即使用户选择了ComfyUI，实际还是调用VeoVideoService

**原代码**:
```dart
final service = VeoVideoService(config);  // ❌ 硬编码！
```

### 3. 错误信息不可见
**问题描述**:
- 所有错误只在日志中输出，用户界面没有显示
- 用户只能看到"生成失败"图标，完全不知道问题在哪

---

## 修复内容

### ✅ 修复1：工作流类型识别
**文件**: `lib/features/home/presentation/settings_page.dart`

**修改**:
```dart
// 修改前：
if (filename.startsWith('video_')) {
  workflowType = 'video';
}

// 修改后：
final filename = file.uri.pathSegments.last.toLowerCase();
if (filename.startsWith('video_') || filename.startsWith('video-')) {
  workflowType = 'video';
}
```

**效果**: 现在支持 `video_xxx.json` 和 `video-xxx.json` 两种命名方式

---

### ✅ 修复2：动态服务创建
**文件**: `lib/features/home/presentation/video_space.dart`

**修改**:
1. 导入API工厂:
```dart
import 'package:xinghe_new/services/api/api_factory.dart';
```

2. 使用API工厂创建服务:
```dart
// 修改前：
final service = VeoVideoService(config);  // ❌ 硬编码

// 修改后：
final apiFactory = ApiFactory();
final service = apiFactory.createService(provider, config);  // ✅ 动态创建
```

3. 添加详细日志:
```dart
_logger.info('视频生成配置', module: '视频空间', extra: {
  'provider': provider,
  'baseUrl': baseUrl ?? '(未配置)',
  'hasApiKey': apiKey != null && apiKey.isNotEmpty,
});

_logger.success('创建 $provider 视频服务', module: '视频空间', extra: {
  'serviceType': service.runtimeType.toString(),
});
```

**效果**: 
- 现在会根据设置正确使用 ComfyUI、GeekNow、OpenAI 等服务
- 日志清晰显示使用的服务商和服务类型

---

### ✅ 修复3：ComfyUI 特殊检查
**文件**: `lib/features/home/presentation/video_space.dart`

**新增检查**:
```dart
// ComfyUI 特殊检查：需要选择工作流
if (provider.toLowerCase() == 'comfyui') {
  final selectedWorkflow = prefs.getString('comfyui_selected_video_workflow');
  if (selectedWorkflow == null || selectedWorkflow.isEmpty) {
    throw Exception('未选择 ComfyUI 视频工作流\n\n请前往设置页面选择一个视频工作流');
  }
  
  final workflowsJson = prefs.getString('comfyui_workflows');
  if (workflowsJson == null || workflowsJson.isEmpty) {
    throw Exception('未找到 ComfyUI 工作流数据\n\n请前往设置页面重新读取工作流');
  }
}
```

**效果**: 在生成前就检查ComfyUI必需的配置，给出明确的提示

---

### ✅ 修复4：错误对话框
**文件**: `lib/features/home/presentation/video_space.dart`

**新增功能**:
```dart
void _showErrorDialog(String title, String message) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 24),
          const SizedBox(width: 12),
          Text(title, ...),
        ],
      ),
      content: SingleChildScrollView(
        child: SelectableText(message, ...),  // ✅ 可选择文本，方便复制错误信息
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('确定', ...),
        ),
      ],
    ),
  );
}
```

**效果**: 
- 用户可以清楚地看到错误信息
- 错误信息可选择和复制，方便排查问题

---

### ✅ 修复5：ComfyUI错误检测增强
**文件**: `lib/services/api/providers/comfyui_service.dart`

**增强内容**:

1. **检测任务失败状态**:
```dart
// 检查任务状态（是否失败）
final status = history['status'] as Map<String, dynamic>?;
if (status != null) {
  final statusMessages = status['messages'] as List?;
  
  // 检查是否有错误消息
  if (statusMessages != null && statusMessages.isNotEmpty) {
    final errorMessages = statusMessages
        .where((msg) => msg is List && msg.length >= 2 && msg[0] == 'error')
        .map((msg) => msg[1].toString())
        .toList();
    
    if (errorMessages.isNotEmpty) {
      final errorDetail = errorMessages.join('\n');
      throw Exception('ComfyUI 工作流执行失败\n\n错误详情:\n$errorDetail');
    }
  }
}
```

2. **详细的输出节点日志**:
```dart
// 如果有outputs但没有gifs，打印详细信息
if (outputs.isNotEmpty) {
  debugPrint('   ⚠️ 找到outputs但没有视频数据');
  debugPrint('   📋 输出节点类型: ${outputs.keys.join(", ")}');
  for (final entry in outputs.entries) {
    if (entry.value is Map) {
      final keys = (entry.value as Map).keys.join(", ");
      debugPrint('   📋 节点 ${entry.key} 的输出字段: $keys');
    }
  }
}
```

3. **更有用的超时提示**:
```dart
throw Exception('视频生成超时（20分钟）\n\n可能原因：\n1. ComfyUI 队列繁忙\n2. 视频生成缓慢\n3. 工作流没有视频输出节点\n\n💡 建议：\n1. 检查 ComfyUI 控制台日志\n2. 确认工作流包含 VHS_VideoCombine 等视频生成节点\n3. 手动在 ComfyUI 中测试该工作流');
```

**效果**:
- 捕获ComfyUI的详细错误信息
- 清晰显示工作流的输出节点结构
- 给出具体的排查建议

---

## 使用指南

### 步骤1：重新读取工作流
1. 打开 **设置 > 保存设置**
2. 找到 **ComfyUI 工作流管理** 区域
3. 点击 **"读取工作流"** 按钮
4. 检查日志，确认 `video-wan2.2smoothmix.json` 现在被识别为 `video` 类型

**预期日志**:
```
✅ 读取工作流: video-wan2.2smoothmix.json (video)  // ✅ 正确！
```

---

### 步骤2：配置视频模型
1. 打开 **设置 > API设置 > 视频模型**
2. 选择 **ComfyUI（本地）** 作为服务商
3. 配置 **Base URL**: `http://127.0.0.1:8188/`
4. **API Key** 可以随便填写（ComfyUI本地服务不需要）
5. 在 **ComfyUI 工作流** 下拉框中选择 `video-wan2.2smoothmix`
6. 点击 **"保存"** 按钮

---

### 步骤3：测试视频生成
1. 回到 **视频空间**
2. 输入提示词（例如："女人在奔跑"）
3. 点击生成按钮
4. 观察控制台日志

**预期日志**:
```
ℹ️ 视频生成配置
   provider: comfyui
   baseUrl: http://127.0.0.1:8188/
   hasApiKey: true

✅ 创建 comfyui 视频服务
   serviceType: ComfyUIService

🎬 ComfyUI 生成视频
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Prompt: 女人在奔跑
   使用工作流: video-wan2.2smoothmix
   ...
```

---

### 步骤4：排查错误

如果仍然失败，现在你可以看到详细的错误信息：

#### 错误1：未选择工作流
**错误信息**:
```
未选择 ComfyUI 视频工作流

请前往设置页面选择一个视频工作流
```

**解决方法**: 按照步骤2配置工作流

---

#### 错误2：ComfyUI未运行
**错误信息**:
```
ComfyUI 未运行

💡 请先启动 ComfyUI：
python main.py --listen 0.0.0.0 --port 8188
```

**解决方法**: 启动ComfyUI服务

---

#### 错误3：工作流执行失败
**错误信息**:
```
ComfyUI 工作流执行失败

错误详情:
[具体的错误消息]

💡 建议：
1. 检查工作流是否包含视频生成节点（如 VHS_VideoCombine）
2. 检查ComfyUI控制台是否有详细错误日志
3. 确认所有必需的自定义节点已安装
```

**解决方法**: 
1. 打开ComfyUI控制台查看详细错误
2. 确认工作流包含 `VHS_VideoCombine` 等视频输出节点
3. 检查是否缺少自定义节点（如 ComfyUI-VideoHelperSuite）

---

#### 错误4：工作流没有视频输出
**错误信息**:
```
⚠️ 找到outputs但没有视频数据
📋 输出节点类型: SaveImage, LoadImage
📋 节点 SaveImage 的输出字段: images
```

**解决方法**: 
- 当前工作流只有图片输出节点，没有视频输出节点
- 需要添加 `VHS_VideoCombine` 或类似的视频生成节点

---

## 工作流要求

要使ComfyUI视频生成正常工作，工作流JSON文件必须：

### 1. 文件命名
- ✅ `video-xxx.json` 或 `video_xxx.json`
- ❌ `xxx-video.json` 或其他格式

### 2. 元数据（可选）
```json
{
  "metadata": {
    "type": "video",
    "name": "视频工作流名称",
    "description": "工作流描述"
  },
  "workflow": {
    // 节点定义...
  }
}
```

### 3. 必需节点
工作流必须包含**视频输出节点**，例如：
- `VHS_VideoCombine` (VideoHelperSuite插件)
- 或其他能输出 `gifs` 字段的节点

**输出格式**:
```json
{
  "outputs": {
    "节点ID": {
      "gifs": [
        {
          "filename": "video.mp4",
          "subfolder": "",
          "type": "output"
        }
      ]
    }
  }
}
```

---

## 常见问题

### Q1: 为什么我的工作流被识别为图片类型？
**A**: 
- 检查文件名是否以 `video-` 或 `video_` 开头
- 或者在JSON中添加 `metadata.type: "video"`

### Q2: 生成一直超时怎么办？
**A**:
1. 检查ComfyUI是否正在运行
2. 手动在ComfyUI界面中测试该工作流
3. 查看ComfyUI控制台的详细日志
4. 可能是工作流太复杂或缺少必需的模型/节点

### Q3: 如何确认ComfyUI服务正常？
**A**:
1. 在浏览器中访问 `http://127.0.0.1:8188`
2. 应该能看到ComfyUI的Web界面
3. 在设置中点击"测试连接"按钮

### Q4: 生成按钮一点击就失败？
**A**: 现在修复后，你会看到详细的错误对话框，按照错误提示排查即可

---

## 技术细节

### API工厂支持的服务商
```dart
case 'comfyui':
  return ComfyUIService(config);
case 'geeknow':
  return GeekNowService(config);
case 'yunwu':
  return YunwuService(config);
case 'openai':
  return OpenAIService(config);
// ... 等等
```

### ComfyUI视频输出检测
代码会在轮询时检查：
1. `history[promptId].outputs[nodeId].gifs` - 标准视频输出
2. `history[promptId].status.messages` - 错误消息
3. 如果都没有，会打印所有输出节点的结构

---

## 总结

本次修复解决了3个核心问题：
1. ✅ **工作流识别** - 支持 `video-` 命名
2. ✅ **服务选择** - 动态创建正确的服务（不再硬编码）
3. ✅ **错误可见** - 详细的错误对话框和日志

现在当你点击生成按钮时：
- 如果配置有问题，会立即显示明确的错误提示
- 如果ComfyUI工作流失败，会显示具体的错误详情
- 所有日志都会清晰记录服务商、工作流名称、节点结构等信息

---

**修复时间**: 2026-02-03
**修复文件**: 
- `lib/features/home/presentation/settings_page.dart`
- `lib/features/home/presentation/video_space.dart`
- `lib/services/api/providers/comfyui_service.dart`
