# 视频空间实施指南

## 📋 当前状态

**已完成**：
- ✅ 导入已添加（VeoVideoService, API Config 等）
- ✅ 视频任务数据模型
- ✅ 基础UI框架

**待实施**：
- ⏳ 真实视频生成 API 调用
- ⏳ 异步任务轮询
- ⏳ 视频保存到本地
- ⏳ 视频播放器

## 🎯 实施方案（参考绘图空间）

### 步骤 1: 修改生成按钮

**位置**: `lib/features/home/presentation/video_space.dart` 第 693 行

**当前代码**（模拟生成）：
```dart
onTap: isGen ? null : () async {
  // 模拟延迟
  await Future.delayed(const Duration(seconds: 3));
  final videos = List.generate(...);
  // ...
}
```

**应改为**（真实 API 调用）：
```dart
onTap: _generateVideos,  // 调用真实方法
```

### 步骤 2: 实现视频生成方法

**添加位置**: _TaskCardState 类中，`_update` 方法之后

```dart
/// 真实的视频生成
Future<void> _generateVideos() async {
  if (widget.task.prompt.trim().isEmpty) {
    _logger.warning('提示词为空', module: '视频空间');
    return;
  }

  final batchCount = widget.task.batchCount;
  
  // 立即添加占位符
  final placeholders = List.generate(batchCount, (i) => 'loading_${DateTime.now().millisecondsSinceEpoch}_$i');
  _update(widget.task.copyWith(
    generatedVideos: [...widget.task.generatedVideos, ...placeholders],
  ));

  try {
    // 读取视频 API 配置
    final prefs = await SharedPreferences.getInstance();
    final provider = prefs.getString('video_provider') ?? 'geeknow';
    final baseUrl = await _storage.getBaseUrl(provider: provider);
    final apiKey = await _storage.getApiKey(provider: provider);
    
    if (baseUrl == null || apiKey == null) {
      throw Exception('未配置视频 API');
    }
    
    // 创建配置
    final config = ApiConfig(
      provider: provider,
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
    
    // 创建服务
    final service = VeoVideoService(config);
    final helper = VeoVideoHelper(service);
    
    // 批量生成（多次调用）
    final allVideoUrls = <String>[];
    
    for (int i = 0; i < batchCount; i++) {
      _logger.info('生成第 ${i + 1}/$batchCount 个视频', module: '视频空间');
      
      // 调用视频生成 API
      final result = await service.generateVideos(
        prompt: widget.task.prompt,
        model: widget.task.model,
        ratio: widget.task.ratio,
        parameters: {
          'seconds': _getSecondsForModel(widget.task.model),
          'referenceImagePaths': widget.task.referenceImages,
        },
      );
      
      if (result.isSuccess && result.data != null && result.data!.isNotEmpty) {
        final taskId = result.data!.first.videoId;
        
        if (taskId != null) {
          // 轮询任务状态
          _logger.info('开始轮询任务: $taskId', module: '视频空间');
          
          final statusResult = await helper.pollTaskUntilComplete(
            taskId: taskId,
            maxWaitMinutes: 15,
            onProgress: (progress, status) {
              _logger.info('视频生成进度: $progress%', module: '视频空间');
            },
          );
          
          if (statusResult.isSuccess && statusResult.data!.hasVideo) {
            final videoUrl = statusResult.data!.videoUrl!;
            allVideoUrls.add(videoUrl);
            
            _logger.success('视频生成成功', module: '视频空间', extra: {
              'url': videoUrl,
            });
          }
        }
      }
      
      // 避免请求过快
      if (i < batchCount - 1) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    
    // 下载并保存视频
    final savedPaths = await _downloadAndSaveVideos(allVideoUrls);
    
    // 替换占位符
    final currentVideos = List<String>.from(widget.task.generatedVideos);
    for (var placeholder in placeholders) {
      currentVideos.remove(placeholder);
    }
    currentVideos.addAll(savedPaths);
    
    _update(widget.task.copyWith(
      generatedVideos: currentVideos,
    ));
    
  } catch (e) {
    _logger.error('视频生成失败: $e', module: '视频空间');
    
    // 标记为失败
    final currentVideos = List<String>.from(widget.task.generatedVideos);
    for (var placeholder in placeholders) {
      final index = currentVideos.indexOf(placeholder);
      if (index != -1) {
        currentVideos[index] = 'failed_${DateTime.now().millisecondsSinceEpoch}';
      }
    }
    _update(widget.task.copyWith(generatedVideos: currentVideos));
  }
}

/// 根据模型获取默认时长
int _getSecondsForModel(String model) {
  if (model.startsWith('veo')) return 8;
  if (model.startsWith('sora')) return 10;
  if (model.startsWith('kling')) return 10;
  if (model.startsWith('doubao')) return 6;
  if (model.startsWith('grok')) return 6;
  return 8;
}

/// 下载并保存视频
Future<List<String>> _downloadAndSaveVideos(List<String> videoUrls) async {
  final savedPaths = <String>[];
  
  try {
    final savePath = videoSavePathNotifier.value;
    
    if (savePath == '未设置' || savePath.isEmpty) {
      _logger.warning('未设置视频保存路径', module: '视频空间');
      return videoUrls;
    }
    
    final saveDir = Directory(savePath);
    if (!await saveDir.exists()) {
      await saveDir.create(recursive: true);
    }
    
    for (var i = 0; i < videoUrls.length; i++) {
      try {
        final url = videoUrls[i];
        final response = await http.get(Uri.parse(url));
        
        if (response.statusCode == 200) {
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final fileName = 'video_${timestamp}_$i.mp4';
          final filePath = path.join(savePath, fileName);
          
          await File(filePath).writeAsBytes(response.bodyBytes);
          savedPaths.add(filePath);
          
          _logger.success('视频已保存', module: '视频空间', extra: {
            'path': filePath,
          });
        } else {
          savedPaths.add(url);
        }
      } catch (e) {
        savedPaths.add(videoUrls[i]);
      }
    }
  } catch (e) {
    return videoUrls;
  }
  
  return savedPaths;
}
```

### 步骤 3: 修改视频显示

**位置**: _buildRight() 方法中的 GridView.builder

**参考绘图空间的实现**，添加：
- 占位符处理（loading_）
- 失败状态（failed_）
- 视频播放器（video_player package）

### 步骤 4: 添加必要字段

**在 _TaskCardState 类开头添加**：
```dart
final SecureStorageManager _storage = SecureStorageManager();
```

## 📝 关键差异（视频 vs 图片）

| 特性 | 图片 | 视频 |
|------|------|------|
| 生成方式 | 同步返回 | 异步（需轮询） |
| API 调用 | generateImagesByChat | generateVideos |
| 结果获取 | 立即返回 URL | 轮询任务状态 |
| 显示组件 | Image.network | video_player |
| 文件大小 | 小（KB-MB） | 大（MB-百MB） |

## 🚀 快速实施

1. 复制上面的代码到对应位置
2. 修改按钮调用 `_generateVideos`
3. 添加视频播放器组件
4. 测试功能

**预计时间**: 30-60 分钟

---

**创建日期**: 2026-01-27
**参考**: 绘图空间实现
