import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';  // ✅ 导入窗口管理器
import 'package:xinghe_new/main.dart';
import 'package:xinghe_new/core/widgets/window_border.dart';  // ✅ 导入窗口边框
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinghe_new/services/api/providers/veo_video_service.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';
import 'package:xinghe_new/services/api/api_factory.dart';
import 'package:xinghe_new/services/api/secure_storage_manager.dart';
import 'package:xinghe_new/services/ffmpeg_service.dart';
import 'package:xinghe_new/core/logger/log_manager.dart';
import 'package:xinghe_new/features/home/domain/video_task.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:convert';

/// 批量视频空间 - Excel表格式界面
class BatchVideoSpace extends StatefulWidget {
  const BatchVideoSpace({super.key});

  @override
  State<BatchVideoSpace> createState() => _BatchVideoSpaceState();
}

// 全局视频进度管理
final Map<String, int> _batchVideoProgress = {};

class _BatchVideoSpaceState extends State<BatchVideoSpace> {
  final List<VideoTask> _tasks = [];
  final LogManager _logger = LogManager();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTasks();
    });
  }

  Future<void> _loadTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tasksJson = prefs.getString('batch_video_tasks');
      if (tasksJson != null && tasksJson.isNotEmpty && mounted) {
        final tasksList = jsonDecode(tasksJson) as List;
        final tasks = tasksList.map((json) => VideoTask.fromJson(json)).toList();
        
        // 清理遗留占位符
        var cleanedCount = 0;
        for (var task in tasks) {
          final originalCount = task.generatedVideos.length;
          task.generatedVideos.removeWhere((v) => 
            v.startsWith('loading_') || v.startsWith('failed_')
          );
          cleanedCount += originalCount - task.generatedVideos.length;
        }
        
        setState(() {
          _tasks.clear();
          _tasks.addAll(tasks);
        });
        
        if (cleanedCount > 0) {
          _saveTasks();
        }
        
        _logger.success('成功加载 ${_tasks.length} 个批量任务', module: '批量空间');
      }
    } catch (e) {
      _logger.error('加载批量任务失败: $e', module: '批量空间');
    }
  }

  Future<void> _saveTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('batch_video_tasks', jsonEncode(_tasks.map((t) => t.toJson()).toList()));
    } catch (e) {
      _logger.error('保存批量任务失败: $e', module: '批量空间');
    }
  }

  void _addNewTask() {
    final newTask = _tasks.isEmpty 
        ? VideoTask.create()
        : VideoTask.create().copyWith(
            model: _tasks.last.model,
            ratio: _tasks.last.ratio,
            quality: _tasks.last.quality,
            batchCount: _tasks.last.batchCount,
            seconds: _tasks.last.seconds,
          );
    setState(() => _tasks.add(newTask));
    _saveTasks();
    _logger.success('创建新的批量任务', module: '批量空间', extra: {
      'taskId': newTask.id,
      '任务索引': _tasks.length - 1,
      '任务总数': _tasks.length,
    });
    
    // 输出所有任务的ID，方便调试
    for (var i = 0; i < _tasks.length; i++) {
      _logger.info('任务 $i: ID=${_tasks[i].id}', module: '批量空间');
    }
  }

  void _deleteTask(String taskId) {
    setState(() => _tasks.removeWhere((t) => t.id == taskId));
    _saveTasks();
    _logger.info('删除批量任务', module: '批量空间');
  }

  /// 单行生成（只生成这一个任务）
  Future<void> _generateSingleRow(VideoTask task) async {
    if (task.prompt.trim().isEmpty) {
      _showMessage('请先输入提示词', isError: true);
      return;
    }
    
    _logger.success('🚀 开始生成单个任务', module: '批量空间', extra: {
      '提示词': task.prompt.substring(0, task.prompt.length > 20 ? 20 : task.prompt.length),
      '批量': task.batchCount,
    });
    
    // 生成这一个任务
    await _generateSingleTask(task);
    
    _logger.success('✅ 单个任务生成完成', module: '批量空间');
  }

  void _updateTask(VideoTask task) {
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      _logger.info('【_updateTask】准备更新任务 [$index]', module: '批量空间', extra: {
        'taskId': task.id,
        '旧图片数': _tasks[index].referenceImages.length,
        '新图片数': task.referenceImages.length,
      });
      
      _tasks[index] = task;
      
      _logger.success('【_updateTask】任务已更新', module: '批量空间', extra: {
        'taskId': task.id,
        'index': index,
        'prompt': task.prompt.length > 20 ? '${task.prompt.substring(0, 20)}...' : task.prompt,
        'images': task.referenceImages.length,
        'videos': task.generatedVideos.length,
      });
      
      // 输出更新后所有任务的状态
      for (var i = 0; i < _tasks.length; i++) {
        _logger.info('  更新后任务[$i]: ID=${_tasks[i].id}, 图片数=${_tasks[i].referenceImages.length}', module: '批量空间');
      }
      
      _saveTasks();
    } else {
      _logger.warning('【_updateTask】任务不存在！', module: '批量空间', extra: {'taskId': task.id});
    }
    if (mounted) {
      setState(() {});
    }
  }

  /// 导入CSV
  Future<void> _importCSV() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      
      if (result == null || result.files.isEmpty) return;
      
      final file = File(result.files.first.path!);
      final content = await file.readAsString(encoding: utf8);
      final lines = content.split('\n');
      
      if (lines.isEmpty) {
        _showMessage('CSV文件为空', isError: true);
        return;
      }
      
      // 跳过表头
      final dataLines = lines.skip(1).where((line) => line.trim().isNotEmpty).toList();
      
      if (dataLines.isEmpty) {
        _showMessage('CSV文件没有数据', isError: true);
        return;
      }
      
      final newTasks = <VideoTask>[];
      final warnings = <String>[];
      
      for (var i = 0; i < dataLines.length; i++) {
        final line = dataLines[i].trim();
        final parts = _parseCSVLine(line);
        
        if (parts.isEmpty) continue;
        
        // 解析字段
        final prompt = parts.isNotEmpty ? parts[0].trim() : '';
        if (prompt.isEmpty) {
          warnings.add('第${i + 2}行: 提示词为空，已跳过');
          continue;
        }
        
        final ratio = parts.length > 1 ? _validateRatio(parts[1].trim()) : '自动';
        final seconds = parts.length > 2 ? _validateSeconds(parts[2].trim()) : '自动';
        final batchCount = parts.length > 3 ? _validateBatchCount(parts[3].trim()) : 1;
        
        // 解析参考图片
        final referenceImages = <String>[];
        if (parts.length > 4 && parts[4].trim().isNotEmpty) {
          final imagePaths = parts[4].split('|');
          for (var imagePath in imagePaths) {
            final trimmedPath = imagePath.trim();
            if (trimmedPath.isNotEmpty && File(trimmedPath).existsSync()) {
              referenceImages.add(trimmedPath);
            } else if (trimmedPath.isNotEmpty) {
              warnings.add('第${i + 2}行: 图片路径无效 - $trimmedPath');
            }
          }
        }
        
        // ✅ 创建唯一ID：时间戳 + 索引，确保每个任务ID都不同
        final uniqueId = '${DateTime.now().millisecondsSinceEpoch}_$i';
        final newTask = VideoTask(
          id: uniqueId,
          prompt: prompt,
          ratio: ratio,
          seconds: seconds,
          batchCount: batchCount,
          referenceImages: referenceImages,
        );
        
        newTasks.add(newTask);
        _logger.info('创建CSV任务 $i', module: '批量空间', extra: {'taskId': uniqueId});
      }
      
      if (newTasks.isEmpty) {
        _showMessage('没有可导入的任务', isError: true);
        return;
      }
      
      // 显示预览对话框
      final confirmed = await _showImportPreview(newTasks, warnings);
      if (confirmed == true) {
        setState(() {
          _tasks.addAll(newTasks);
        });
        _saveTasks();
        _logger.success('成功导入 ${newTasks.length} 个任务', module: '批量空间');
        _showMessage('成功导入 ${newTasks.length} 个任务');
        
        // ✅ 输出所有任务的ID，确认没有重复
        _logger.info('导入后的任务列表:', module: '批量空间');
        for (var i = 0; i < _tasks.length; i++) {
          _logger.info('  任务[$i]: ID=${_tasks[i].id}, 提示词=${_tasks[i].prompt.length > 20 ? _tasks[i].prompt.substring(0, 20) : _tasks[i].prompt}...', module: '批量空间');
        }
      }
    } catch (e) {
      _logger.error('导入CSV失败: $e', module: '批量空间');
      _showMessage('导入失败: $e', isError: true);
    }
  }

  /// 解析CSV行(处理引号包裹的逗号)
  List<String> _parseCSVLine(String line) {
    final result = <String>[];
    var current = StringBuffer();
    var inQuotes = false;
    
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(current.toString());
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }
    
    result.add(current.toString());
    return result;
  }

  /// 验证比例
  String _validateRatio(String ratio) {
    const validRatios = ['自动', '16:9', '9:16', '1:1', '4:3', '3:4'];
    return validRatios.contains(ratio) ? ratio : '自动';
  }

  /// 验证时长
  String _validateSeconds(String seconds) {
    const validSeconds = ['自动', '5秒', '10秒', '15秒'];
    return validSeconds.contains(seconds) ? seconds : '自动';
  }

  /// 验证批量数
  int _validateBatchCount(String batch) {
    final count = int.tryParse(batch) ?? 1;
    if (count < 1) return 1;
    if (count > 20) return 20;
    return count;
  }

  /// 显示导入预览对话框
  Future<bool?> _showImportPreview(List<VideoTask> tasks, List<String> warnings) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceBackground,
        title: Text('导入预览', style: TextStyle(color: AppTheme.textColor)),
        content: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '即将导入 ${tasks.length} 个任务',
                style: TextStyle(color: AppTheme.textColor, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              if (warnings.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  '警告 (${warnings.length})',
                  style: const TextStyle(color: Colors.orange, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: warnings.map((w) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '• $w',
                          style: TextStyle(color: AppTheme.subTextColor, fontSize: 12),
                        ),
                      )).toList(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消', style: TextStyle(color: AppTheme.subTextColor)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('确认导入', style: TextStyle(color: AppTheme.accentColor)),
          ),
        ],
      ),
    );
  }

  /// 导出CSV
  Future<void> _exportCSV() async {
    try {
      if (_tasks.isEmpty) {
        _showMessage('没有可导出的任务', isError: true);
        return;
      }
      
      final result = await FilePicker.platform.saveFile(
        dialogTitle: '导出CSV',
        fileName: 'batch_tasks_${DateTime.now().millisecondsSinceEpoch}.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      
      if (result == null) return;
      
      final lines = <String>[];
      lines.add('提示词,比例,时长,批量,参考图片');
      
      for (var task in _tasks) {
        final prompt = task.prompt.contains(',') ? '"${task.prompt}"' : task.prompt;
        final images = task.referenceImages.join('|');
        lines.add('$prompt,${task.ratio},${task.seconds},${task.batchCount},$images');
      }
      
      final file = File(result);
      await file.writeAsString(lines.join('\n'), encoding: utf8);
      
      _logger.success('成功导出 ${_tasks.length} 个任务', module: '批量空间');
      _showMessage('成功导出到 $result');
    } catch (e) {
      _logger.error('导出CSV失败: $e', module: '批量空间');
      _showMessage('导出失败: $e', isError: true);
    }
  }

  /// 批量生成所有任务
  Future<void> _generateAllTasks() async {
    final tasksToGenerate = _tasks.where((t) => t.prompt.trim().isNotEmpty).toList();
    
    if (tasksToGenerate.isEmpty) {
      _showMessage('没有可生成的任务\n请确保任务有提示词', isError: true);
      return;
    }
    
    _logger.success('🚀 开始批量生成 ${tasksToGenerate.length} 个视频任务', module: '批量空间');
    
    await Future.wait(
      tasksToGenerate.map((task) => _generateSingleTask(task)),
      eagerError: false,
    );
    
    _logger.success('✅ 批量生成完成', module: '批量空间');
  }

  /// 生成单个任务
  Future<void> _generateSingleTask(VideoTask task) async {
    if (task.prompt.trim().isEmpty) return;
    
    final batchCount = task.batchCount;
    
    // 添加占位符
    final placeholders = List.generate(
      batchCount,
      (i) => 'loading_${DateTime.now().millisecondsSinceEpoch}_${task.id}_$i',
    );
    
    // 初始化进度
    for (var placeholder in placeholders) {
      _batchVideoProgress[placeholder] = 0;
    }
    
    // 更新任务
    final updatedTask = task.copyWith(
      generatedVideos: [...task.generatedVideos, ...placeholders],
    );
    _updateTask(updatedTask);
    
    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('video_provider') ?? 'geeknow';
      final baseUrl = await SecureStorageManager().getBaseUrl(provider: provider, modelType: 'video');
      final apiKey = await SecureStorageManager().getApiKey(provider: provider, modelType: 'video');
      
      if (baseUrl == null || apiKey == null) {
        throw Exception('未配置视频 API');
      }
      
      _logger.info('【批量空间】使用 Provider: $provider', module: '批量空间');
      _logger.info('【批量空间】任务信息', module: '批量空间', extra: {
        'taskId': task.id,
        'prompt': task.prompt.substring(0, task.prompt.length > 30 ? 30 : task.prompt.length),
        'model': task.model,
        'ratio': task.ratio,
        'seconds': task.seconds,
        'batchCount': task.batchCount,
        'referenceImages': task.referenceImages.length,
      });
      
      // ✅ ComfyUI 特殊检查：需要选择工作流
      if (provider.toLowerCase() == 'comfyui') {
        final selectedWorkflow = prefs.getString('comfyui_selected_video_workflow');
        if (selectedWorkflow == null || selectedWorkflow.isEmpty) {
          throw Exception('未选择 ComfyUI 视频工作流\n\n请前往设置页面选择一个视频工作流');
        }
        
        final workflowsJson = prefs.getString('comfyui_workflows');
        if (workflowsJson == null || workflowsJson.isEmpty) {
          throw Exception('未找到 ComfyUI 工作流数据\n\n请前往设置页面重新读取工作流');
        }
        
        _logger.success('【批量空间】使用 ComfyUI 工作流: $selectedWorkflow', module: '批量空间');
        
        // ✅ 检查工作流类型
        final workflows = List<Map<String, dynamic>>.from(
          (jsonDecode(workflowsJson) as List).map((w) => Map<String, dynamic>.from(w as Map))
        );
        final workflow = workflows.firstWhere(
          (w) => w['id'] == selectedWorkflow,
          orElse: () => throw Exception('工作流未找到: $selectedWorkflow'),
        );
        
        final workflowType = workflow['type'] as String?;
        _logger.info('【批量空间】工作流类型: $workflowType', module: '批量空间');
        
        if (workflowType != 'video') {
          _logger.warning('⚠️ 选中的工作流不是视频类型！', module: '批量空间', extra: {
            'workflowName': workflow['name'],
            'workflowType': workflowType,
          });
          throw Exception('选中的工作流不是视频类型\n\n当前工作流: ${workflow['name']}\n类型: $workflowType\n\n请在设置中选择一个视频工作流（类型应为 video）');
        }
      }
      
      final config = ApiConfig(provider: provider, baseUrl: baseUrl, apiKey: apiKey);
      final apiFactory = ApiFactory();
      final service = apiFactory.createService(provider, config);
      
      // 准备参数 - "自动"选项不传参数
      final size = task.ratio == '自动' ? null : _convertRatioToSize(task.ratio, task.quality, task.model);
      final seconds = task.seconds == '自动' ? null : _parseSeconds(task.seconds);
      
      final parameters = <String, dynamic>{};
      if (seconds != null) {
        parameters['seconds'] = seconds;
      }
      
      // ComfyUI 同步生成
      if (provider.toLowerCase() == 'comfyui') {
        final generateFutures = List.generate(batchCount, (i) async {
          final placeholder = placeholders[i];
          
          try {
            final result = await service.generateVideos(
              prompt: task.prompt,
              model: task.model,
              ratio: size,
              referenceImages: task.referenceImages,
              parameters: parameters,
            );
            
            if (result.isSuccess && result.data != null && result.data!.isNotEmpty) {
              final videoUrl = result.data!.first.videoUrl;
              final savedPath = await _downloadSingleVideoForTask(videoUrl, i, task.id);
              
              final currentTask = _tasks.firstWhere((t) => t.id == task.id);
              final currentVideos = List<String>.from(currentTask.generatedVideos);
              final placeholderIndex = currentVideos.indexOf(placeholder);
              
              if (placeholderIndex != -1) {
                currentVideos[placeholderIndex] = savedPath;
                _batchVideoProgress.remove(placeholder);
                _updateTask(currentTask.copyWith(generatedVideos: currentVideos));
                
                // ✅ 延迟后再次刷新，确保首帧显示
                await Future.delayed(const Duration(milliseconds: 500));
                if (mounted) {
                  setState(() {});
                }
              }
              
              return true;
            }
          } catch (e) {
            _logger.error('视频生成失败: $e', module: '批量空间');
            
            final currentTask = _tasks.firstWhere((t) => t.id == task.id);
            final currentVideos = List<String>.from(currentTask.generatedVideos);
            final placeholderIndex = currentVideos.indexOf(placeholder);
            
            if (placeholderIndex != -1) {
              currentVideos[placeholderIndex] = 'failed_${DateTime.now().millisecondsSinceEpoch}';
              _batchVideoProgress.remove(placeholder);
              _updateTask(currentTask.copyWith(generatedVideos: currentVideos));
            }
          }
          
          return false;
        });
        
        await Future.wait(generateFutures, eagerError: false);
      } else {
        // 其他服务的异步轮询模式
        final helper = VeoVideoHelper(service as VeoVideoService);
        
        final submitFutures = List.generate(batchCount, (i) async {
          final result = await service.generateVideos(
            prompt: task.prompt,
            model: task.model,
            ratio: size,
            referenceImages: task.referenceImages,
            parameters: parameters,
          );
          
          if (result.isSuccess && result.data != null && result.data!.isNotEmpty) {
            return {'index': i, 'taskId': result.data!.first.videoId, 'placeholder': placeholders[i]};
          } else {
            throw Exception('提交失败: ${result.errorMessage}');
          }
        });
        
        final submittedTasks = await Future.wait(submitFutures);
        
        final pollFutures = submittedTasks.map((taskInfo) async {
          final index = taskInfo['index'] as int;
          final taskId = taskInfo['taskId'] as String?;
          final placeholder = taskInfo['placeholder'] as String;
          
          if (taskId == null) return false;
          
          try {
            final statusResult = await helper.pollTaskUntilComplete(
              taskId: taskId,
              maxWaitMinutes: 15,
              onProgress: (progress, status) {
                _batchVideoProgress[placeholder] = progress;
                if (mounted) setState(() {});
              },
            );
            
            if (statusResult.isSuccess && statusResult.data!.hasVideo) {
              final videoUrl = statusResult.data!.videoUrl!;
              final savedPath = await _downloadSingleVideoForTask(videoUrl, index, task.id);
              
              final currentTask = _tasks.firstWhere((t) => t.id == task.id);
              final currentVideos = List<String>.from(currentTask.generatedVideos);
              final placeholderIndex = currentVideos.indexOf(placeholder);
              
              if (placeholderIndex != -1) {
                currentVideos[placeholderIndex] = savedPath;
                _batchVideoProgress.remove(placeholder);
                _updateTask(currentTask.copyWith(generatedVideos: currentVideos));
                
                // ✅ 延迟后再次刷新，确保首帧显示
                await Future.delayed(const Duration(milliseconds: 500));
                if (mounted) {
                  setState(() {});
                }
              }
              
              return true;
            }
          } catch (e) {
            final currentTask = _tasks.firstWhere((t) => t.id == task.id);
            final currentVideos = List<String>.from(currentTask.generatedVideos);
            final placeholderIndex = currentVideos.indexOf(placeholder);
            
            if (placeholderIndex != -1) {
              currentVideos[placeholderIndex] = 'failed_${DateTime.now().millisecondsSinceEpoch}';
              _batchVideoProgress.remove(placeholder);
              _updateTask(currentTask.copyWith(generatedVideos: currentVideos));
            }
          }
          
          return false;
        }).toList();
        
        await Future.wait(pollFutures, eagerError: false);
      }
    } catch (e) {
      _logger.error('任务生成失败: $e', module: '批量空间');
      
      // 清理占位符
      final currentTask = _tasks.firstWhere((t) => t.id == task.id, orElse: () => task);
      final currentVideos = List<String>.from(currentTask.generatedVideos);
      for (var placeholder in placeholders) {
        final index = currentVideos.indexOf(placeholder);
        if (index != -1) {
          currentVideos[index] = 'failed_${DateTime.now().millisecondsSinceEpoch}';
          _batchVideoProgress.remove(placeholder);
        }
      }
      _updateTask(currentTask.copyWith(generatedVideos: currentVideos));
    }
  }

  /// 下载单个视频
  Future<String> _downloadSingleVideoForTask(String videoUrl, int index, String taskId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savePath = prefs.getString('video_save_path');
      
      if (savePath == null || savePath.isEmpty) {
        _logger.warning('未设置视频保存路径，使用在线URL', module: '批量空间');
        return videoUrl;
      }
      
      _logger.info('开始下载视频 ${index + 1}', module: '批量空间', extra: {'url': videoUrl});
      
      final response = await http.get(Uri.parse(videoUrl)).timeout(
        const Duration(minutes: 5),
      );
      
      if (response.statusCode == 200) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'video_${timestamp}_${taskId}_$index.mp4';
        final filePath = path.join(savePath, fileName);
        
        await File(filePath).writeAsBytes(response.bodyBytes);
        
        _logger.success('视频已保存', module: '批量空间', extra: {
          'path': filePath,
          'size': '${(response.bodyBytes.length / 1024 / 1024).toStringAsFixed(2)} MB',
        });
        
        // ✅ 提取首帧
        try {
          final thumbnailPath = filePath.replaceAll('.mp4', '.jpg');
          _logger.info('开始提取视频首帧', module: '批量空间', extra: {
            'video': filePath,
            'thumbnail': thumbnailPath,
          });
          
          final ffmpeg = FFmpegService();
          final success = await ffmpeg.extractFrame(
            videoPath: filePath, 
            outputPath: thumbnailPath,
          );
          
          if (success) {
            _logger.success('视频首帧已提取', module: '批量空间', extra: {
              'thumbnail': thumbnailPath,
            });
          } else {
            _logger.warning('首帧提取失败', module: '批量空间');
          }
        } catch (e) {
          _logger.error('提取首帧失败: $e', module: '批量空间');
        }
        
        return filePath;
      } else {
        _logger.warning('下载失败（状态码: ${response.statusCode}），使用在线URL', module: '批量空间');
        return videoUrl;
      }
    } catch (e) {
      _logger.error('下载视频失败: $e', module: '批量空间');
    }
    
    return videoUrl;
  }

  /// 将时长字符串转换为整数
  int _parseSeconds(String secondsStr) {
    final numStr = secondsStr.replaceAll('秒', '');
    return int.tryParse(numStr) ?? 10;
  }

  /// 将比例转换为尺寸
  String _convertRatioToSize(String ratio, String quality, String model) {
    switch (ratio) {
      case '16:9':
        return '1280x720';
      case '9:16':
        return '720x1280';
      case '1:1':
        return '1024x1024';
      case '4:3':
        return '1280x960';
      case '3:4':
        return '960x1280';
      default:
        return '1280x720';
    }
  }

  /// 显示消息
  void _showMessage(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : const Color(0xFF2AF598),
        ),
      );
    }
  }

  /// 清空所有任务
  void _clearAllTasks() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceBackground,
        title: Text('清空所有任务', style: TextStyle(color: AppTheme.textColor)),
        content: Text('确定要删除所有任务吗？此操作不可恢复。', style: TextStyle(color: AppTheme.subTextColor)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: AppTheme.subTextColor)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              final count = _tasks.length;
              setState(() => _tasks.clear());
              _saveTasks();
              _logger.warning('清空所有批量任务', module: '批量空间', extra: {'删除数量': count});
              _showMessage('已清空 $count 个任务');
            },
            child: const Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// 标题栏（和其他界面保持一致）
  Widget _buildTitleBar() {
    return Container(
      height: 32,
      color: AppTheme.scaffoldBackground,
      child: Stack(
        children: [
          // 可拖动区域
          DragToMoveArea(
            child: SizedBox(
              height: 32,
              width: double.infinity,
              child: Center(
                child: Text(
                  '星橙AI动漫制作',
                  style: TextStyle(
                    color: AppTheme.subTextColor,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
          // 右侧窗口控制按钮
          Positioned(
            right: 0,
            top: 0,
            child: Row(
              children: [
                // ✅ 设置按钮
                _WindowControlButton(
                  icon: Icons.tune_rounded,
                  onPressed: () {
                    // 返回主界面，由主界面处理设置
                    Navigator.pop(context);
                  },
                ),
                _WindowControlButton(
                  icon: Icons.minimize,
                  onPressed: () => windowManager.minimize(),
                ),
                _WindowControlButton(
                  icon: Icons.crop_square,
                  onPressed: () async {
                    if (await windowManager.isMaximized()) {
                      windowManager.unmaximize();
                    } else {
                      windowManager.maximize();
                    }
                  },
                ),
                _WindowControlButton(
                  icon: Icons.close,
                  isClose: true,
                  onPressed: () => windowManager.close(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: themeNotifier,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: AppTheme.scaffoldBackground,
          body: WindowBorder(
            child: Column(
            children: [
              // ✅ 标题栏
              _buildTitleBar(),
              _buildToolbar(),
              Expanded(
                child: _tasks.isEmpty
                    ? _buildEmptyState()
                    : _buildTable(),
              ),
            ],
            ),
          ),
        );
      },
    );
  }

  /// 构建工具栏
  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBackground,
        border: Border(bottom: BorderSide(color: AppTheme.dividerColor)),
      ),
      child: Row(
        children: [
          // 返回按钮
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.textColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.arrow_back, color: AppTheme.subTextColor, size: 16),
                    const SizedBox(width: 6),
                    Text('返回', style: TextStyle(color: AppTheme.subTextColor, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 导入CSV
          _toolButton(Icons.upload_file, '导入CSV', _importCSV),
          const SizedBox(width: 12),
          // 导出CSV
          _toolButton(Icons.download, '导出CSV', _exportCSV),
          const SizedBox(width: 12),
          // ✅ 清空面板（改为正常颜色，位置提前）
          _toolButton(Icons.delete_sweep_rounded, '清空面板', _clearAllTasks),
          const SizedBox(width: 12),
          // ✅ 批量生成（位置靠后）
          _batchGenerateButton(),
          const Spacer(),
          // 新建行
          _newTaskButton(),
        ],
      ),
    );
  }

  Widget _toolButton(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.textColor.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon, color: color ?? AppTheme.subTextColor, size: 16),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color ?? AppTheme.subTextColor, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _batchGenerateButton() {
    final hasValidTasks = _tasks.any((t) => t.prompt.trim().isNotEmpty);
    final isAnyGenerating = _tasks.any((t) => 
      t.generatedVideos.any((v) => v.startsWith('loading_'))
    );
    
    return MouseRegion(
      cursor: hasValidTasks && !isAnyGenerating ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: hasValidTasks && !isAnyGenerating ? _generateAllTasks : null,
        child: Opacity(
          opacity: hasValidTasks && !isAnyGenerating ? 1.0 : 0.5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: hasValidTasks && !isAnyGenerating
                  ? [BoxShadow(color: const Color(0xFFFF6B6B).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isAnyGenerating ? Icons.hourglass_empty : Icons.flash_on,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  isAnyGenerating ? '生成中...' : '批量生成',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _newTaskButton() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _addNewTask,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF2AF598), Color(0xFF009EFD)]),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(color: const Color(0xFF2AF598).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(
            children: const [
              Icon(Icons.add, color: Colors.white, size: 18),
              SizedBox(width: 6),
              Text('新建行', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建表格
  Widget _buildTable() {
    return Container(
      color: AppTheme.surfaceBackground,
      child: Column(
        children: [
          // 表头
          _buildTableHeader(),
          // 表格内容
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              itemCount: _tasks.length,
              itemBuilder: (context, index) {
                return _buildTableRow(index);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 构建表头
  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.textColor.withOpacity(0.05),
        border: Border(bottom: BorderSide(color: AppTheme.dividerColor)),
      ),
      child: Row(
        children: [
          // 序号
          SizedBox(
            width: 40,
            child: Text(
              '#',
              style: TextStyle(
                color: AppTheme.subTextColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // 图片
          SizedBox(
            width: 110,
            child: Text(
              '图片',
              style: TextStyle(
                color: AppTheme.subTextColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // 提示词
          Expanded(
            child: Text(
              '提示词',
              style: TextStyle(
                color: AppTheme.subTextColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // 视频
          SizedBox(
            width: 110,
            child: Text(
              '视频',
              style: TextStyle(
                color: AppTheme.subTextColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // 设置
          SizedBox(
            width: 240,
            child: Text(
              '设置',
              style: TextStyle(
                color: AppTheme.subTextColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建表格行
  Widget _buildTableRow(int index) {
    final task = _tasks[index];
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.inputBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 序号
          SizedBox(
            width: 40,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: AppTheme.textColor,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // 图片
          SizedBox(
            width: 110,
            child: _buildImageCell(task),
          ),
          // 提示词
          Expanded(
            child: _buildPromptCell(task),
          ),
          // 视频
          SizedBox(
            width: 110,
            child: _buildVideoCell(task),
          ),
          // 设置
          SizedBox(
            width: 240,
            child: _buildSettingsCell(task),
          ),
        ],
      ),
    );
  }

  /// 构建图片单元格
  Widget _buildImageCell(VideoTask task) {
    if (task.referenceImages.isEmpty) {
      // ✅ 空状态 - 可点击添加图片
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            _logger.info('点击添加图片', module: '批量空间', extra: {'taskId': task.id});
            _showImageSourceDialog(task.id);  // ✅ 传递 task ID
          },
          child: Center(
            child: Icon(
              Icons.add_photo_alternate_outlined,
              color: AppTheme.subTextColor.withOpacity(0.3),
              size: 24,
            ),
          ),
        ),
      );
    }
    
    if (task.referenceImages.length == 1) {
      // ✅ 单张图片 - 点击可添加更多或查看大图
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            _logger.info('点击查看图片', module: '批量空间', extra: {'taskId': task.id});
            _showImagesDialog(task.id);  // ✅ 传递 task ID
          },
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              image: DecorationImage(
                image: FileImage(File(task.referenceImages.first)),
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      );
    }
    
    // 多张图片显示数量 - 点击弹出对话框
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          _logger.info('点击查看多张图片', module: '批量空间', extra: {'taskId': task.id, '图片数': task.referenceImages.length});
          _showImagesDialog(task.id);  // ✅ 传递 task ID
        },
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: AppTheme.textColor.withOpacity(0.05),
          ),
          child: Stack(
            children: [
              // 第一张图片作为背景
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  image: DecorationImage(
                    image: FileImage(File(task.referenceImages.first)),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              // 半透明遮罩
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: Colors.black.withOpacity(0.5),
                ),
              ),
              // 数量标签
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.photo_library, color: Colors.white, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      '${task.referenceImages.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建提示词单元格
  Widget _buildPromptCell(VideoTask task) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextFormField(
        initialValue: task.prompt,
        maxLines: null,  // ✅ 允许多行
        minLines: 1,
        style: TextStyle(color: AppTheme.textColor, fontSize: 13),
        decoration: InputDecoration(
          hintText: '输入视频描述...',
          hintStyle: TextStyle(color: AppTheme.subTextColor.withOpacity(0.5), fontSize: 12),
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          isDense: true,
        ),
        onChanged: (v) {
          // ✅ 使用 post frame callback 避免在构建期间调用 setState
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateTask(task.copyWith(prompt: v));
          });
        },
      ),
    );
  }

  /// 构建视频单元格
  Widget _buildVideoCell(VideoTask task) {
    // 过滤掉失败的占位符，保留真实视频和加载中的视频
    final allVideos = task.generatedVideos.where((v) => 
      !v.startsWith('failed_')
    ).toList();
    
    // 真实视频（不包括 loading）
    final realVideos = allVideos.where((v) => !v.startsWith('loading_')).toList();
    
    // 检查是否有加载中的视频
    final hasLoading = allVideos.any((v) => v.startsWith('loading_'));
    
    // ✅ 如果没有任何视频（包括加载中），显示"等待生成"
    if (realVideos.isEmpty && !hasLoading) {
      return Center(
        child: Text(
          '等待生成',
          style: TextStyle(
            color: AppTheme.subTextColor.withOpacity(0.5),
            fontSize: 11,
          ),
        ),
      );
    }
    
    // ✅ 如果只有加载中的视频，没有真实视频，显示加载圈
    if (realVideos.isEmpty && hasLoading) {
      return Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentColor),
          ),
        ),
      );
    }
    
    // ✅ 单个真实视频
    if (realVideos.length == 1) {
      final videoPath = realVideos.first;
      
      if (!hasLoading) {
        // 只有一个视频且没有生成中的，直接显示
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => _playVideo(videoPath),
            onSecondaryTapDown: (details) => _showSingleVideoContextMenu(context, details, videoPath, task),
            child: _buildVideoThumbnail(videoPath, clickable: false),
          ),
        );
      } else {
        // 有一个视频 + 有生成中的，显示视频 + 生成中标记
        final loadingVideos = allVideos.where((v) => v.startsWith('loading_')).toList();
        
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => _showVideosDialog(task.id),  // ✅ 点击弹出对话框
            child: Stack(
              children: [
                _buildVideoThumbnail(videoPath, clickable: false),
                // 生成中标记
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${loadingVideos.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    
    // ✅ 有真实视频（可能还有生成中的）- 点击弹出对话框查看所有视频（包括生成中的）
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _showVideosDialog(task.id),  // ✅ 传递 task ID
        child: Stack(
          children: [
            // ✅ 背景显示第一个视频的缩略图
            _buildVideoThumbnail(realVideos.first),
            // 数量标记（显示已完成/总数）
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: hasLoading ? Colors.orange : AppTheme.accentColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Text(
                  hasLoading ? '${realVideos.length}/${allVideos.length}' : '${realVideos.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建视频缩略图（显示首帧）
  Widget _buildVideoThumbnail(String videoPath, {VoidCallback? onTap, bool clickable = true}) {
    if (videoPath.startsWith('http')) {
      // 在线视频 - 显示播放图标
      return Container(
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: AppTheme.inputBackground,
        ),
        child: const Center(
          child: Icon(Icons.play_circle_outline, color: Colors.white54, size: 32),
        ),
      );
    }
    
    // ✅ 本地视频 - 显示首帧缩略图
    final thumbnailPath = videoPath.replaceAll('.mp4', '.jpg');
    final thumbnailFile = File(thumbnailPath);
    
    Widget content = FutureBuilder<bool>(
      key: ValueKey(thumbnailPath),  // ✅ 添加 key 确保每次都重新检查
      future: thumbnailFile.exists(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: AppTheme.inputBackground,
            ),
            child: const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        
        if (snapshot.data == true) {
          // ✅ 显示首帧图片
          return Container(
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              image: DecorationImage(
                image: FileImage(thumbnailFile),
                fit: BoxFit.cover,
              ),
            ),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
              ),
            ),
          );
        }
        
        // 首帧不存在 - 显示默认图标
        return Container(
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: AppTheme.inputBackground,
          ),
          child: const Center(
            child: Icon(Icons.videocam, color: Colors.white54, size: 24),
          ),
        );
      },
    );
    
    // ✅ 根据参数决定是否可点击
    if (clickable && onTap != null) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: content,
        ),
      );
    }
    
    return content;
  }

  /// 构建设置单元格(两排布局)
  Widget _buildSettingsCell(VideoTask task) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 第一排: 比例 + 时长
        Row(
          children: [
            Expanded(
              child: _buildCompactDropdown(
                task.ratio,
                ['自动', '16:9', '9:16', '1:1', '4:3', '3:4'],
                (v) => _updateTask(task.copyWith(ratio: v)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildCompactDropdown(
                task.seconds,
                ['自动', '5秒', '10秒', '15秒'],
                (v) => _updateTask(task.copyWith(seconds: v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 第二排: 批量 + 删除 + 生成
        Row(
          children: [
            // 批量控制（缩小）
            Expanded(flex: 3, child: _buildBatchControl(task)),
            const SizedBox(width: 4),
            // 删除按钮（正常颜色）
            Expanded(
              flex: 2,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _deleteTask(task.id),
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.inputBackground,  // ✅ 改为正常颜色
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.dividerColor),
                    ),
                    child: Center(
                      child: Icon(Icons.delete_outline, 
                        color: AppTheme.subTextColor, size: 16),  // ✅ 正常颜色
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // ✅ 单行生成按钮（飞机图标）
            Expanded(
              flex: 2,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _generateSingleRow(task),
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2AF598), Color(0xFF009EFD)],
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Center(
                      child: Icon(Icons.send, color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 构建紧凑型下拉框
  Widget _buildCompactDropdown(String value, List<String> items, Function(String) onChanged) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.inputBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: DropdownButton<String>(
        value: value,
        items: items.map((i) => DropdownMenuItem(
          value: i,
          child: Text(
            i,
            style: TextStyle(
              color: AppTheme.textColor,
              fontSize: 11,
            ),
          ),
        )).toList(),
        onChanged: (v) => onChanged(v!),
        underline: const SizedBox(),
        dropdownColor: AppTheme.surfaceBackground,
        icon: Icon(Icons.arrow_drop_down, color: AppTheme.subTextColor, size: 16),
        isDense: true,
        isExpanded: true,
      ),
    );
  }

  /// 构建批量控制
  Widget _buildBatchControl(VideoTask task) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.inputBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        children: [
          Text('批量', style: TextStyle(color: AppTheme.subTextColor, fontSize: 10)),
          const SizedBox(width: 4),
          MouseRegion(
            cursor: task.batchCount > 1 ? SystemMouseCursors.click : SystemMouseCursors.basic,
            child: GestureDetector(
              onTap: task.batchCount > 1
                  ? () => _updateTask(task.copyWith(batchCount: task.batchCount - 1))
                  : null,
              child: Icon(
                Icons.remove,
                color: task.batchCount > 1 ? AppTheme.textColor : AppTheme.subTextColor.withOpacity(0.3),
                size: 16,
              ),
            ),
          ),
          SizedBox(
            width: 24,
            child: Center(
              child: Text(
                '${task.batchCount}',
                style: TextStyle(
                  color: AppTheme.textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          MouseRegion(
            cursor: task.batchCount < 20 ? SystemMouseCursors.click : SystemMouseCursors.basic,
            child: GestureDetector(
              onTap: task.batchCount < 20
                  ? () => _updateTask(task.copyWith(batchCount: task.batchCount + 1))
                  : null,
              child: Icon(
                Icons.add,
                color: task.batchCount < 20 ? AppTheme.textColor : AppTheme.subTextColor.withOpacity(0.3),
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示图片来源选择对话框
  void _showImageSourceDialog(String taskId) {
    _logger.info('显示图片来源对话框', module: '批量空间', extra: {'taskId': taskId});
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceBackground,
        title: Text('选择图片来源', style: TextStyle(color: AppTheme.textColor)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 本地图片
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  // ✅ 传递 task ID
                  _addLocalImages(taskId);
                },
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.inputBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.dividerColor),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.folder_open, color: AppTheme.accentColor, size: 32),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('本地图片', style: TextStyle(
                              color: AppTheme.textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            )),
                            const SizedBox(height: 4),
                            Text('从电脑中选择图片', style: TextStyle(
                              color: AppTheme.subTextColor,
                              fontSize: 12,
                            )),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: AppTheme.subTextColor),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 素材库图片
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  // ✅ 传递 task ID
                  _addAssetLibraryImages(taskId);
                },
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.inputBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.dividerColor),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.photo_library, color: AppTheme.accentColor, size: 32),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('素材库', style: TextStyle(
                              color: AppTheme.textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            )),
                            const SizedBox(height: 4),
                            Text('从素材库中选择', style: TextStyle(
                              color: AppTheme.subTextColor,
                              fontSize: 12,
                            )),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: AppTheme.subTextColor),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: AppTheme.subTextColor)),
          ),
        ],
      ),
    );
  }

  /// 添加本地图片
  Future<void> _addLocalImages(String taskId) async {
    try {
      _logger.info('【添加本地图片】开始', module: '批量空间', extra: {'接收到的taskId': taskId});
      
      // ✅ 先输出所有任务的ID，确认列表状态
      for (var i = 0; i < _tasks.length; i++) {
        _logger.info('  任务列表[$i]: ID=${_tasks[i].id}, 图片数=${_tasks[i].referenceImages.length}', module: '批量空间');
      }
      
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
      
      if (result != null && result.files.isNotEmpty) {
        final newImages = result.files.map((f) => f.path!).toList();
        _logger.info('【添加本地图片】选择了 ${newImages.length} 张图片', module: '批量空间');
        
        // ✅ 从列表中获取正确的 task
        final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
        if (taskIndex == -1) {
          _logger.error('【添加本地图片】未找到任务！', module: '批量空间', extra: {'taskId': taskId});
          _showMessage('任务不存在', isError: true);
          return;
        }
        
        final task = _tasks[taskIndex];
        _logger.info('【添加本地图片】找到任务，索引: $taskIndex，当前图片数: ${task.referenceImages.length}', module: '批量空间');
        
        final updatedTask = task.copyWith(
          referenceImages: [...task.referenceImages, ...newImages],
        );
        
        _logger.info('更新任务，图片总数: ${updatedTask.referenceImages.length}', module: '批量空间');
        _updateTask(updatedTask);
        _showMessage('添加了 ${newImages.length} 张图片');
        _logger.success('添加本地图片成功', module: '批量空间', extra: {'数量': newImages.length, '任务索引': taskIndex});
      } else {
        _logger.info('用户取消选择图片', module: '批量空间');
      }
    } catch (e, stackTrace) {
      _logger.error('添加本地图片失败: $e', module: '批量空间', extra: {'stackTrace': stackTrace.toString()});
      _showMessage('添加失败: $e', isError: true);
    }
  }

  /// 添加素材库图片
  Future<void> _addAssetLibraryImages(String taskId) async {
    try {
      _logger.info('【添加素材库图片】开始', module: '批量空间', extra: {'接收到的taskId': taskId});
      
      // ✅ 先输出所有任务的ID，确认列表状态
      for (var i = 0; i < _tasks.length; i++) {
        _logger.info('  任务列表[$i]: ID=${_tasks[i].id}, 图片数=${_tasks[i].referenceImages.length}', module: '批量空间');
      }
      
      // 加载素材库数据
      final prefs = await SharedPreferences.getInstance();
      final assetsJson = prefs.getString('asset_library_data');
      
      if (assetsJson == null || assetsJson.isEmpty) {
        _showMessage('素材库为空\n请先在素材库中添加图片', isError: true);
        return;
      }
      
      // 解析素材数据
      final data = jsonDecode(assetsJson) as Map<String, dynamic>;
      final allAssets = <Map<String, String>>[];  // ✅ 使用Map存储素材信息
      
      data.forEach((key, value) {
        final stylesList = (value as List);
        for (var styleData in stylesList) {
          final assets = (styleData['assets'] as List?) ?? [];
          for (var assetData in assets) {
            final assetMap = assetData as Map<String, dynamic>;
            allAssets.add({
              'path': assetMap['path'] as String,
              'name': assetMap['name'] as String,
            });
          }
        }
      });
      
      _logger.info('素材库中找到 ${allAssets.length} 张图片', module: '批量空间');
      
      if (allAssets.isEmpty) {
        _showMessage('素材库中没有图片\n请先在素材库中添加图片', isError: true);
        return;
      }
      
      // 显示素材库选择对话框
      final selectedAssets = await _showAssetLibraryDialog(allAssets);
      
      if (selectedAssets != null && selectedAssets.isNotEmpty) {
        final newImages = selectedAssets.map((asset) => asset['path']!).toList();
        _logger.info('【添加素材库图片】选择了 ${newImages.length} 张图片', module: '批量空间');
        
        // ✅ 从列表中获取正确的 task
        final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
        if (taskIndex == -1) {
          _logger.error('【添加素材库图片】未找到任务！', module: '批量空间', extra: {'taskId': taskId});
          _showMessage('任务不存在', isError: true);
          return;
        }
        
        final task = _tasks[taskIndex];
        _logger.info('【添加素材库图片】找到任务，索引: $taskIndex，当前图片数: ${task.referenceImages.length}', module: '批量空间');
        
        final updatedTask = task.copyWith(
          referenceImages: [...task.referenceImages, ...newImages],
        );
        
        _logger.info('更新任务，图片总数: ${updatedTask.referenceImages.length}', module: '批量空间');
        _updateTask(updatedTask);
        _showMessage('从素材库添加了 ${newImages.length} 张图片');
        _logger.success('从素材库添加图片成功', module: '批量空间', extra: {'数量': newImages.length, '任务索引': taskIndex});
      } else {
        _logger.info('用户取消选择', module: '批量空间');
      }
    } catch (e, stackTrace) {
      _logger.error('从素材库添加图片失败: $e', module: '批量空间', extra: {'stackTrace': stackTrace.toString()});
      _showMessage('添加失败: $e', isError: true);
    }
  }

  /// 显示素材库选择对话框
  Future<List<Map<String, String>>?> _showAssetLibraryDialog(List<Map<String, String>> allAssets) async {
    final selectedAssets = <Map<String, String>>[];
    
    return showDialog<List<Map<String, String>>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: AppTheme.surfaceBackground,
            title: Row(
              children: [
                Icon(Icons.photo_library, color: AppTheme.accentColor, size: 24),
                const SizedBox(width: 12),
                Text('选择素材库图片', style: TextStyle(color: AppTheme.textColor)),
                const Spacer(),
                if (selectedAssets.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '已选 ${selectedAssets.length}',
                      style: TextStyle(
                        color: AppTheme.accentColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            content: SizedBox(
              width: 700,
              height: 500,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.8,
                ),
                itemCount: allAssets.length,
                itemBuilder: (context, index) {
                  final asset = allAssets[index];
                  final assetPath = asset['path']!;
                  final isSelected = selectedAssets.any((a) => a['path'] == assetPath);
                  
                  return MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            selectedAssets.removeWhere((a) => a['path'] == assetPath);
                          } else {
                            selectedAssets.add(asset);
                          }
                        });
                      },
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected 
                                    ? AppTheme.accentColor 
                                    : AppTheme.dividerColor,
                                width: isSelected ? 3 : 1,
                              ),
                              image: DecorationImage(
                                image: FileImage(File(asset['path']!)),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          if (isSelected)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentColor,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.check, color: Colors.white, size: 16),
                              ),
                            ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(8),
                                ),
                              ),
                              child: Text(
                                asset['name']!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: Text('取消', style: TextStyle(color: AppTheme.subTextColor)),
              ),
              TextButton(
                onPressed: selectedAssets.isEmpty
                    ? null
                    : () => Navigator.pop(context, selectedAssets),
                child: Text(
                  '确定 (${selectedAssets.length})',
                  style: TextStyle(
                    color: selectedAssets.isEmpty 
                        ? AppTheme.subTextColor 
                        : AppTheme.accentColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 显示图片对话框
  void _showImagesDialog(String taskId) {
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          // ✅ 实时获取最新的task数据
          final currentTask = _tasks.firstWhere((t) => t.id == taskId);
          
          return AlertDialog(
            backgroundColor: AppTheme.surfaceBackground,
            title: Row(
              children: [
                Text(
                  '参考图片 (${currentTask.referenceImages.length})',
                  style: TextStyle(color: AppTheme.textColor),
                ),
                const Spacer(),
                // ✅ 添加图片按钮
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(dialogContext);
                      _showImageSourceDialog(taskId);  // ✅ 传递 task ID
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.accentColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, color: AppTheme.accentColor, size: 16),
                          const SizedBox(width: 4),
                          Text('添加', style: TextStyle(
                            color: AppTheme.accentColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          )),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 600,
              height: 400,
              child: currentTask.referenceImages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate, 
                            size: 64, 
                            color: AppTheme.subTextColor.withOpacity(0.3)),
                          const SizedBox(height: 16),
                          Text('还没有参考图片', 
                            style: TextStyle(color: AppTheme.subTextColor)),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(dialogContext);
                              _showImageSourceDialog(taskId);  // ✅ 传递 task ID
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('添加图片'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accentColor,
                            ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: currentTask.referenceImages.length,
                itemBuilder: (context, index) {
                  final imagePath = currentTask.referenceImages[index];
                  return Stack(
                    children: [
                      // 图片
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => _showImagePreview(imagePath),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              image: DecorationImage(
                                image: FileImage(File(imagePath)),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // ✅ 删除按钮（修复：使用setDialogState刷新对话框）
                      Positioned(
                        top: 4,
                        right: 4,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          final newImages = List<String>.from(currentTask.referenceImages);
                          newImages.removeAt(index);
                          
                          // ✅ 更新任务数据
                          _updateTask(currentTask.copyWith(referenceImages: newImages));
                          
                          // ✅ 刷新对话框
                          setDialogState(() {});
                          
                          // 如果没有图片了，关闭对话框
                          if (newImages.isEmpty) {
                            Navigator.pop(dialogContext);
                          }
                        },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('关闭', style: TextStyle(color: AppTheme.accentColor)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 显示视频对话框（包括已完成和生成中的视频）
  void _showVideosDialog(String taskId) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          // ✅ 实时获取最新的task数据
          final currentTask = _tasks.firstWhere((t) => t.id == taskId);
          
          // 所有视频（包括生成中的，但不包括失败的）
          final allVideos = currentTask.generatedVideos.where((v) => 
            !v.startsWith('failed_')
          ).toList();
          
          final realVideos = allVideos.where((v) => !v.startsWith('loading_')).toList();
          final loadingVideos = allVideos.where((v) => v.startsWith('loading_')).toList();
          
          // ✅ 如果有生成中的视频，定期刷新对话框
          if (loadingVideos.isNotEmpty) {
            Future.delayed(const Duration(seconds: 1), () {
              if (context.mounted) {
                setDialogState(() {});
              }
            });
          }
          
          return AlertDialog(
            backgroundColor: AppTheme.surfaceBackground,
            title: Text(
              '生成视频 (${realVideos.length}${loadingVideos.isNotEmpty ? " + ${loadingVideos.length}生成中" : ""})',
              style: TextStyle(color: AppTheme.textColor),
            ),
            content: SizedBox(
              width: 700,
              height: 450,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 16 / 9,
                ),
                itemCount: allVideos.length,  // ✅ 显示所有视频（包括生成中的）
                itemBuilder: (context, index) {
                  final videoPath = allVideos[index];
                  
                  // ✅ 如果是加载中的视频，显示进度
                  if (videoPath.startsWith('loading_')) {
                    final progress = _batchVideoProgress[videoPath] ?? 0;
                    
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: AppTheme.inputBackground,
                        border: Border.all(color: AppTheme.accentColor.withOpacity(0.3)),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 48,
                              height: 48,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    value: progress / 100.0,
                                    strokeWidth: 3,
                                    backgroundColor: Colors.grey.withOpacity(0.2),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      progress == 0 ? Colors.blue : AppTheme.accentColor,
                                    ),
                                  ),
                                  Text(
                                    '$progress%',
                                    style: TextStyle(
                                      color: AppTheme.textColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              progress == 0 ? '等待中...' : '生成中...',
                              style: TextStyle(color: AppTheme.subTextColor, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  
                  // ✅ 真实视频
                  final thumbnailPath = videoPath.replaceAll('.mp4', '.jpg');
                  final thumbnailFile = File(thumbnailPath);
                  
                  return MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _playVideo(videoPath),
                      onSecondaryTapDown: (details) => _showVideoContextMenu(
                        context, 
                        details, 
                        videoPath, 
                        currentTask,
                        setDialogState,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: AppTheme.inputBackground,
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // ✅ 显示首帧图片
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: FutureBuilder<bool>(
                                key: ValueKey(thumbnailPath),  // ✅ 添加 key
                                future: thumbnailFile.exists(),
                                builder: (context, snapshot) {
                                  if (snapshot.data == true) {
                                    return Image.file(
                                      thumbnailFile,
                                      fit: BoxFit.cover,
                                    );
                                  }
                                  return Container(
                                    color: AppTheme.inputBackground,
                                    child: const Center(
                                      child: Icon(Icons.videocam, 
                                        color: Colors.white54, size: 32),
                                    ),
                                  );
                                },
                              ),
                            ),
                            // 播放按钮
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                            ),
                            // 视频编号
                            Positioned(
                              bottom: 8,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '视频 ${index + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text('关闭', style: TextStyle(color: AppTheme.accentColor)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 显示单个视频右键菜单（表格行内）
  void _showSingleVideoContextMenu(
    BuildContext context,
    TapDownDetails details,
    String videoPath,
    VideoTask task,
  ) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final menuPosition = RelativeRect.fromRect(
      Rect.fromPoints(details.globalPosition, details.globalPosition),
      Offset.zero & overlay.size,
    );
    
    showMenu(
      context: context,
      position: menuPosition,
      color: AppTheme.surfaceBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(
          value: 'play',
          child: Row(
            children: [
              Icon(Icons.play_circle_outline, size: 18, color: AppTheme.textColor),
              const SizedBox(width: 12),
              Text('播放视频', style: TextStyle(color: AppTheme.textColor)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'open_folder',
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 18, color: AppTheme.textColor),
              const SizedBox(width: 12),
              Text('定位文件', style: TextStyle(color: AppTheme.textColor)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              const SizedBox(width: 12),
              Text('删除视频', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    ).then((value) async {
      if (value == 'play') {
        await _playVideo(videoPath);
      } else if (value == 'open_folder') {
        try {
          await Process.run('explorer', ['/select,', videoPath]);
          _logger.success('已定位文件', module: '批量空间');
        } catch (e) {
          _logger.error('定位文件失败: $e', module: '批量空间');
          _showMessage('定位文件失败', isError: true);
        }
      } else if (value == 'delete') {
        // 删除视频
        final newVideos = List<String>.from(task.generatedVideos);
        newVideos.remove(videoPath);
        _updateTask(task.copyWith(generatedVideos: newVideos));
        
        _logger.info('删除视频', module: '批量空间', extra: {'path': videoPath});
        
        // 删除本地文件
        try {
          if (!videoPath.startsWith('http')) {
            final file = File(videoPath);
            if (await file.exists()) {
              await file.delete();
              // 同时删除首帧
              final thumbnailPath = videoPath.replaceAll('.mp4', '.jpg');
              final thumbnailFile = File(thumbnailPath);
              if (await thumbnailFile.exists()) {
                await thumbnailFile.delete();
              }
              _logger.success('已删除本地文件', module: '批量空间');
            }
          }
        } catch (e) {
          _logger.error('删除本地文件失败: $e', module: '批量空间');
        }
      }
    });
  }

  /// 显示视频右键菜单（对话框内）
  void _showVideoContextMenu(
    BuildContext context,
    TapDownDetails details,
    String videoPath,
    VideoTask task,
    StateSetter setDialogState,
  ) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final menuPosition = RelativeRect.fromRect(
      Rect.fromPoints(details.globalPosition, details.globalPosition),
      Offset.zero & overlay.size,
    );
    
    showMenu(
      context: context,
      position: menuPosition,
      color: AppTheme.surfaceBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(
          value: 'play',
          child: Row(
            children: [
              Icon(Icons.play_circle_outline, size: 18, color: AppTheme.textColor),
              const SizedBox(width: 12),
              Text('播放视频', style: TextStyle(color: AppTheme.textColor)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'open_folder',
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 18, color: AppTheme.textColor),
              const SizedBox(width: 12),
              Text('定位文件', style: TextStyle(color: AppTheme.textColor)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              const SizedBox(width: 12),
              Text('删除视频', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    ).then((value) async {
      if (value == 'play') {
        await _playVideo(videoPath);
      } else if (value == 'open_folder') {
        try {
          await Process.run('explorer', ['/select,', videoPath]);
          _logger.success('已定位文件', module: '批量空间');
        } catch (e) {
          _logger.error('定位文件失败: $e', module: '批量空间');
          _showMessage('定位文件失败', isError: true);
        }
      } else if (value == 'delete') {
        // 删除视频
        final newVideos = List<String>.from(task.generatedVideos);
        newVideos.remove(videoPath);
        _updateTask(task.copyWith(generatedVideos: newVideos));
        
        // 刷新对话框
        setDialogState(() {});
        
        // 如果没有视频了，关闭对话框
        if (newVideos.where((v) => 
          !v.startsWith('loading_') && !v.startsWith('failed_')
        ).isEmpty) {
          Navigator.pop(context);
        }
        
        _logger.info('删除视频', module: '批量空间', extra: {'path': videoPath});
        
        // 删除本地文件
        try {
          if (!videoPath.startsWith('http')) {
            final file = File(videoPath);
            if (await file.exists()) {
              await file.delete();
              // 同时删除首帧
              final thumbnailPath = videoPath.replaceAll('.mp4', '.jpg');
              final thumbnailFile = File(thumbnailPath);
              if (await thumbnailFile.exists()) {
                await thumbnailFile.delete();
              }
              _logger.success('已删除本地文件', module: '批量空间');
            }
          }
        } catch (e) {
          _logger.error('删除本地文件失败: $e', module: '批量空间');
        }
      }
    });
  }

  /// 显示图片预览
  void _showImagePreview(String imagePath) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.file(File(imagePath)),
              ),
            ),
            Positioned(
              top: 20,
              right: 20,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 播放视频
  Future<void> _playVideo(String videoPath) async {
    try {
      final isLocalFile = !videoPath.startsWith('http');
      
      if (isLocalFile) {
        final file = File(videoPath);
        if (await file.exists()) {
          await Process.run('cmd', ['/c', 'start', '', videoPath], runInShell: true);
          _logger.success('已用默认播放器打开视频', module: '批量空间');
        } else {
          _showMessage('视频文件不存在', isError: true);
        }
      } else {
        await Process.run('cmd', ['/c', 'start', '', videoPath], runInShell: true);
        _logger.success('已在浏览器中打开', module: '批量空间');
      }
    } catch (e) {
      _logger.error('打开视频失败: $e', module: '批量空间');
      _showMessage('打开视频失败: $e', isError: true);
    }
  }

  /// 构建空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.table_chart, size: 100, color: AppTheme.subTextColor.withOpacity(0.2)),
          const SizedBox(height: 24),
          Text(
            '开始批量创作',
            style: TextStyle(
              color: AppTheme.textColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '点击"新建行"创建任务，或"导入CSV"批量导入',
            style: TextStyle(color: AppTheme.subTextColor, fontSize: 14),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _importCSV,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF4C83FF), Color(0xFF2AFADF)]),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(color: const Color(0xFF4C83FF).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.upload_file, color: Colors.white, size: 20),
                        SizedBox(width: 10),
                        Text('导入CSV', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _addNewTask,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF2AF598), Color(0xFF009EFD)]),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(color: const Color(0xFF2AF598).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.add_circle_outline, color: Colors.white, size: 20),
                        SizedBox(width: 10),
                        Text('新建行', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 窗口控制按钮
class _WindowControlButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isClose;

  const _WindowControlButton({
    required this.icon,
    required this.onPressed,
    this.isClose = false,
  });

  @override
  State<_WindowControlButton> createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<_WindowControlButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: 32,
          color: _isHovered
              ? (widget.isClose ? Colors.red : AppTheme.textColor.withOpacity(0.1))
              : Colors.transparent,
          child: Icon(
            widget.icon,
            size: 16,
            color: _isHovered && widget.isClose ? Colors.white : AppTheme.subTextColor,
          ),
        ),
      ),
    );
  }
}
