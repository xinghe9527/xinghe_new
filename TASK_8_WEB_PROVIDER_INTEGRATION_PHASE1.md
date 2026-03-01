# ✅ 任务 8 第一阶段：网页服务商集成 - 配置验证

## 📋 问题描述

用户在设置中选择了 Vidu 网页服务商并配置了工具和模型，但在视频空间生成视频时，系统仍然报错：
```
Exception: 未配置视频 Base URL
请前往设置页面配置 API 地址
```

**原因**：生成逻辑还在走 API 服务商的路线，没有判断是否为网页服务商。

## ✅ 已完成的修改

### 修改文件：`lib/features/home/presentation/video_space.dart`

在 `_generateVideos()` 方法中添加了网页服务商判断逻辑：

```dart
try {
  // 读取视频 API 配置
  final prefs = await SharedPreferences.getInstance();
  final provider = prefs.getString('video_provider') ?? 'geeknow';
  
  // ✅ 判断是否为网页服务商
  final isWebProvider = ['vidu', 'jimeng', 'keling', 'hailuo'].contains(provider);
  
  if (isWebProvider) {
    // ========== 网页服务商路线 ==========
    _logger.info('使用网页服务商生成视频', module: '视频空间', extra: {'provider': provider});
    
    // 读取网页服务商配置
    final webTool = prefs.getString('video_web_tool');
    final webModel = prefs.getString('video_web_model');
    
    // 验证配置
    if (webTool == null || webTool.isEmpty) {
      throw Exception('未配置网页服务商工具\n\n请前往设置页面选择工具类型（如：文生视频）');
    }
    
    if (webModel == null || webModel.isEmpty) {
      throw Exception('未配置网页服务商模型\n\n请前往设置页面选择模型（如：Vidu Q3）');
    }
    
    _logger.info('网页服务商配置', module: '视频空间', extra: {
      'provider': provider,
      'tool': webTool,
      'model': webModel,
    });
    
    // TODO: 调用 AutomationApiClient 生成视频
    throw Exception('网页服务商功能开发中\n\n即将支持通过浏览器自动化生成视频');
  }
  
  // ========== API 服务商路线（原有逻辑）==========
  final baseUrl = await _storage.getBaseUrl(provider: provider, modelType: 'video');
  final apiKey = await _storage.getApiKey(provider: provider, modelType: 'video');
  
  // ... 原有的 API 服务商逻辑
}
```

## 🎯 现在的行为

### 场景 1：选择网页服务商但未配置工具
**错误提示**：
```
未配置网页服务商工具

请前往设置页面选择工具类型（如：文生视频）
```

### 场景 2：选择网页服务商但未配置模型
**错误提示**：
```
未配置网页服务商模型

请前往设置页面选择模型（如：Vidu Q3）
```

### 场景 3：配置完整但功能未实现
**错误提示**：
```
网页服务商功能开发中

即将支持通过浏览器自动化生成视频
```

### 场景 4：选择 API 服务商
**行为**：正常走原有的 API 路线，不受影响

## 📊 验证清单

- [x] 代码编译通过
- [x] 网页服务商判断逻辑正确
- [x] 配置验证逻辑完整
- [x] 错误提示友好清晰
- [x] API 服务商不受影响
- [ ] 实际调用 AutomationApiClient（下一阶段）

## 🚀 下一步工作（第二阶段）

### 需要实现的功能

1. **导入 AutomationApiClient**
   ```dart
   import 'package:xinghe_new/core/aigc_engine/automation_api_client.dart';
   ```

2. **调用网页服务商生成视频**
   ```dart
   // 替换 TODO 部分
   final aigcClient = AutomationApiClient();
   
   // 提交生成任务
   final taskId = await aigcClient.submitGenerationTask(
     platform: provider,  // 'vidu'
     toolType: webTool,   // 'text2video'
     payload: {
       'prompt': widget.task.prompt,
       'model': webModel,  // 'vidu-q3'
     },
   );
   
   // 轮询任务状态
   while (true) {
     final result = await aigcClient.getTaskStatus(taskId);
     
     if (result.status == 'completed') {
       // 视频生成完成
       final videoUrl = result.videoUrl;
       final localPath = result.localVideoPath;
       
       // 保存视频并更新 UI
       break;
     } else if (result.status == 'failed') {
       throw Exception('生成失败: ${result.error}');
     }
     
     // 等待后继续轮询
     await Future.delayed(Duration(seconds: 5));
   }
   ```

3. **处理批量生成**
   - 支持 `batchCount` 参数
   - 并发提交多个任务
   - 分别轮询每个任务的状态
   - 实时更新进度

4. **浏览器窗口控制**
   - 生成开始时显示浏览器窗口
   - 生成完成后隐藏浏览器窗口
   - 用户可以手动控制显示/隐藏

## 📝 测试步骤

### 当前阶段测试（配置验证）

1. 打开设置 → API设置 → 视频模型
2. 选择"Vidu（网页服务商）"
3. 不选择工具，直接去视频空间生成
4. **预期**：提示"未配置网页服务商工具"
5. 返回设置，选择工具"文生视频"
6. 不选择模型，直接去视频空间生成
7. **预期**：提示"未配置网页服务商模型"
8. 返回设置，选择模型"Vidu Q3"
9. 去视频空间生成
10. **预期**：提示"网页服务商功能开发中"

### 下一阶段测试（实际生成）

1. 完成上述配置
2. 去视频空间生成视频
3. **预期**：
   - 浏览器自动打开 Vidu 网站
   - 自动填写提示词
   - 自动点击生成按钮
   - 等待视频生成完成
   - 自动下载视频
   - 视频显示在视频空间

## 🔧 技术细节

### 配置存储键名
- `video_provider` - 服务商名称（'vidu', 'jimeng', 'keling', 'hailuo'）
- `video_web_tool` - 工具类型（'text2video', 'img2video', 'ref2video'）
- `video_web_model` - 模型名称（'vidu-q3', 'vidu-q2', 'vidu-q1'）

### 日志输出
```
✅ 使用网页服务商生成视频
   provider: vidu
   tool: text2video
   model: vidu-q3
```

## 📌 注意事项

1. **绝对隔离原则**：网页服务商和 API 服务商的代码完全分离
2. **提前返回**：网页服务商处理完成后应该 `return`，不继续执行 API 服务商代码
3. **错误处理**：所有错误都应该有清晰的提示，告诉用户如何解决
4. **日志记录**：关键步骤都要记录日志，方便调试

## 总结

第一阶段已完成！现在系统可以正确识别网页服务商，验证配置，并给出友好的错误提示。用户不会再看到"未配置 Base URL"这样的误导性错误了。

下一步需要实现实际的视频生成逻辑，调用 Python 后端的 AutomationApiClient。
