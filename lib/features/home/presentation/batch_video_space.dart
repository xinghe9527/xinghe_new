import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart'; // ✅ 导入窗口管理器
import 'package:xinghe_new/main.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinghe_new/services/api/providers/veo_video_service.dart';
import 'package:xinghe_new/services/api/providers/geeknow_service.dart';
import 'package:xinghe_new/services/api/base/api_response.dart';
import 'package:xinghe_new/services/api/providers/yunwu_service.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';
import 'package:xinghe_new/services/api/api_factory.dart';
import 'package:xinghe_new/services/api/provider_preference_helper.dart';
import 'package:xinghe_new/services/api/secure_storage_manager.dart';
import 'package:xinghe_new/services/ffmpeg_service.dart';
import 'package:xinghe_new/core/logger/log_manager.dart';
import 'package:xinghe_new/features/home/domain/video_task.dart';
import 'package:xinghe_new/features/creation_workflow/presentation/widgets/draggable_media_item.dart'; // ✅ 导入拖动组件
import 'package:xinghe_new/features/creation_workflow/presentation/widgets/video_grid_item.dart'; // ✅ 导入原位播放组件
import 'package:xinghe_new/features/home/presentation/settings_page.dart'; // ✅ 导入设置页面
import 'package:xinghe_new/core/aigc_engine/automation_api_client.dart'; // ✅ 导入网页服务商客户端
import 'package:xinghe_new/services/api/api_repository.dart'; // ✅ 导入 API 仓库
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
  final ApiRepository _apiRepository = ApiRepository(); // ✅ API Repository
  bool _showSettings = false; // ✅ 控制设置页面显示
  bool _isSmartMatching = false; // ✅ 智能匹配中
  final Map<String, TextEditingController> _promptControllers = {};

  @override
  void dispose() {
    for (final controller in _promptControllers.values) {
      controller.dispose();
    }
    _promptControllers.clear();
    super.dispose();
  }

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
        final tasks = tasksList
            .map((json) => VideoTask.fromJson(json))
            .toList();

        // 读取 pending 任务信息
        final pendingJson = prefs.getString('batch_pending_tasks') ?? '{}';
        final pendingTasks = Map<String, dynamic>.from(jsonDecode(pendingJson));
        final pendingPlaceholders = pendingTasks.keys.toSet();

        // 清理遗留占位符（保留有 pending 记录的 loading_ 占位符）
        var cleanedCount = 0;
        for (var task in tasks) {
          final originalCount = task.generatedVideos.length;
          task.generatedVideos.removeWhere(
            (v) => (v.startsWith('loading_') && !pendingPlaceholders.contains(v))
                || v.startsWith('failed_'),
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

        _logger.debug('成功加载 ${_tasks.length} 个批量任务', module: '批量空间');

        // 恢复未完成的生成任务轮询
        if (pendingPlaceholders.isNotEmpty) {
          _resumePendingTasks();
        }
      }
    } catch (e) {
      _logger.error('加载批量任务失败: $e', module: '批量空间');
    }
  }

  Future<void> _saveTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'batch_video_tasks',
        jsonEncode(_tasks.map((t) => t.toJson()).toList()),
      );
    } catch (e) {
      _logger.error('保存批量任务失败: $e', module: '批量空间');
    }
  }

  // ========== 生成中任务持久化（防止切换页面丢失） ==========

  /// 保存正在生成中的任务信息到 SharedPreferences
  Future<void> _savePendingTask({
    required String placeholder,
    required String taskId,
    required String provider,
    required String videoTaskId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingJson = prefs.getString('batch_pending_tasks') ?? '{}';
      final pending = Map<String, dynamic>.from(jsonDecode(pendingJson));
      pending[placeholder] = {
        'taskId': taskId,
        'provider': provider,
        'videoTaskId': videoTaskId,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString('batch_pending_tasks', jsonEncode(pending));
    } catch (e) {
      _logger.error('保存生成中任务失败: $e', module: '批量空间');
    }
  }

  /// 移除已完成/失败的 pending 记录
  Future<void> _removePendingTask(String placeholder) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingJson = prefs.getString('batch_pending_tasks') ?? '{}';
      final pending = Map<String, dynamic>.from(jsonDecode(pendingJson));
      pending.remove(placeholder);
      await prefs.setString('batch_pending_tasks', jsonEncode(pending));
    } catch (e) {
      _logger.error('移除生成中任务记录失败: $e', module: '批量空间');
    }
  }

  /// 获取所有 pending 任务
  Future<Map<String, dynamic>> _getPendingTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingJson = prefs.getString('batch_pending_tasks') ?? '{}';
      return Map<String, dynamic>.from(jsonDecode(pendingJson));
    } catch (e) {
      _logger.error('读取生成中任务失败: $e', module: '批量空间');
      return {};
    }
  }

  /// 恢复所有未完成的生成任务轮询
  Future<void> _resumePendingTasks() async {
    final pending = await _getPendingTasks();
    if (pending.isEmpty) return;

    _logger.info('【批量空间】发现 ${pending.length} 个待恢复的生成任务', module: '批量空间');

    final aigcClient = AutomationApiClient();

    // 检查 API 服务是否可用
    final isHealthy = await aigcClient.checkHealth();
    if (!isHealthy) {
      _logger.warning('【批量空间】Python API 服务不可用，无法恢复轮询', module: '批量空间');
      // 服务不可用时清理所有 pending 和 loading_ 占位符
      for (final placeholder in pending.keys) {
        await _removePendingTask(placeholder);
      }
      for (var task in _tasks) {
        task.generatedVideos.removeWhere((v) => v.startsWith('loading_'));
      }
      _saveTasks();
      if (mounted) setState(() {});
      aigcClient.dispose();
      return;
    }

    final pollFutures = <Future<void>>[];

    for (final entry in pending.entries) {
      final placeholder = entry.key;
      final info = Map<String, dynamic>.from(entry.value);
      final taskId = info['taskId'] as String;
      final videoTaskId = info['videoTaskId'] as String;

      // 确认该占位符仍存在于任务列表中
      final taskIndex = _tasks.indexWhere((t) => t.id == videoTaskId);
      if (taskIndex == -1) {
        _logger.warning('【批量空间】任务 $videoTaskId 已不存在，跳过恢复', module: '批量空间');
        _removePendingTask(placeholder);
        continue;
      }

      final task = _tasks[taskIndex];
      if (!task.generatedVideos.contains(placeholder)) {
        _logger.warning('【批量空间】占位符 $placeholder 已不存在，跳过恢复', module: '批量空间');
        _removePendingTask(placeholder);
        continue;
      }

      // 恢复进度显示
      _batchVideoProgress[placeholder] = 50;
      if (mounted) setState(() {});

      _logger.info('【批量空间】恢复轮询任务: $taskId (占位符: $placeholder)', module: '批量空间');

      pollFutures.add(() async {
        try {
          // 先检查任务是否还存在（Python 重启后旧任务会消失）
          try {
            await aigcClient.getTaskStatus(taskId);
          } catch (e) {
            _logger.warning('【批量空间】任务 $taskId 已不存在（可能后端已重启），放弃恢复', module: '批量空间');
            throw Exception('任务不存在');
          }

          final pollResult = await aigcClient.pollTaskStatus(
            taskId: taskId,
            interval: const Duration(seconds: 3),
            maxAttempts: 300,
            onProgress: (taskResult) {
              if (taskResult.isRunning) {
                _batchVideoProgress[placeholder] = 50;
              }
              if (mounted) setState(() {});
            },
          );

          if (pollResult.isSuccess) {
            final videoPath = pollResult.localVideoPath ?? pollResult.videoUrl;
            if (videoPath == null || videoPath.isEmpty) {
              throw Exception('任务完成但未返回视频地址');
            }

            _logger.success('【批量空间】恢复任务完成: $videoPath', module: '批量空间');

            // 提取首帧
            if (!videoPath.startsWith('http') && videoPath.endsWith('.mp4')) {
              try {
                final thumbnailPath = videoPath.replaceAll('.mp4', '.jpg');
                final ffmpeg = FFmpegService();
                await ffmpeg.extractFrame(
                  videoPath: videoPath,
                  outputPath: thumbnailPath,
                );
              } catch (e) {
                _logger.warning('【批量空间】提取首帧失败: $e', module: '批量空间');
              }
            }

            // 替换占位符
            final currentTask = _tasks.firstWhere(
              (t) => t.id == videoTaskId,
              orElse: () => task,
            );
            final currentVideos = List<String>.from(currentTask.generatedVideos);
            final placeholderIndex = currentVideos.indexOf(placeholder);
            if (placeholderIndex != -1) {
              currentVideos[placeholderIndex] = videoPath;
              _batchVideoProgress.remove(placeholder);
              _updateTask(currentTask.copyWith(generatedVideos: currentVideos));
              if (mounted) setState(() {});
            }
          } else {
            throw Exception(pollResult.error ?? '生成失败');
          }

          await _removePendingTask(placeholder);
        } catch (e) {
          _logger.error('【批量空间】恢复轮询失败: $e', module: '批量空间');
          // 标记为失败
          try {
            final currentTask = _tasks.firstWhere(
              (t) => t.id == videoTaskId,
              orElse: () => task,
            );
            final currentVideos = List<String>.from(currentTask.generatedVideos);
            final placeholderIndex = currentVideos.indexOf(placeholder);
            if (placeholderIndex != -1) {
              currentVideos[placeholderIndex] =
                  'failed_${DateTime.now().millisecondsSinceEpoch}';
              _batchVideoProgress.remove(placeholder);
              _updateTask(currentTask.copyWith(generatedVideos: currentVideos));
            }
          } catch (_) {}
          await _removePendingTask(placeholder);
        }
      }());
    }

    if (pollFutures.isNotEmpty) {
      // 不 await，让轮询在后台运行
      Future.wait(pollFutures).then((_) {
        _logger.success('【批量空间】所有恢复任务已完成', module: '批量空间');
        aigcClient.dispose();
      });
    } else {
      aigcClient.dispose();
    }
  }

  Future<void> _addNewTask() async {
    VideoTask newTask;
    if (_tasks.isEmpty) {
      newTask = VideoTask.create();
      // 从设置中读取用户保存的模型
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('video_provider') ?? 'geeknow';
      final savedModel = await SecureStorageManager().getModel(provider: provider, modelType: 'video');
      if (savedModel != null && savedModel.isNotEmpty) {
        newTask = newTask.copyWith(model: savedModel);
      }
    } else {
      newTask = VideoTask.create().copyWith(
            model: _tasks.last.model,
            ratio: _tasks.last.ratio,
            quality: _tasks.last.quality,
            batchCount: _tasks.last.batchCount,
            seconds: _tasks.last.seconds,
          );
    }
    setState(() => _tasks.add(newTask));
    _saveTasks();
    _logger.success(
      '创建新的批量任务',
      module: '批量空间',
      extra: {
        'taskId': newTask.id,
        '任务索引': _tasks.length - 1,
        '任务总数': _tasks.length,
      },
    );

    // 输出所有任务的ID，方便调试
    for (var i = 0; i < _tasks.length; i++) {
      _logger.info('任务 $i: ID=${_tasks[i].id}', module: '批量空间');
    }
  }

  void _deleteTask(String taskId) {
    _promptControllers.remove(taskId)?.dispose();
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

    _logger.success(
      '🚀 开始生成单个任务',
      module: '批量空间',
      extra: {
        '提示词': task.prompt.substring(
          0,
          task.prompt.length > 20 ? 20 : task.prompt.length,
        ),
        '批量': task.batchCount,
      },
    );

    // 生成这一个任务
    await _generateSingleTask(task);

    _logger.success('✅ 单个任务生成完成', module: '批量空间');
  }

  void _updateTask(VideoTask task) {
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      _logger.info(
        '【_updateTask】准备更新任务 [$index]',
        module: '批量空间',
        extra: {
          'taskId': task.id,
          '旧图片数': _tasks[index].referenceImages.length,
          '新图片数': task.referenceImages.length,
        },
      );

      _tasks[index] = task;

      _logger.success(
        '【_updateTask】任务已更新',
        module: '批量空间',
        extra: {
          'taskId': task.id,
          'index': index,
          'prompt': task.prompt.length > 20
              ? '${task.prompt.substring(0, 20)}...'
              : task.prompt,
          'images': task.referenceImages.length,
          'videos': task.generatedVideos.length,
        },
      );

      // 输出更新后所有任务的状态
      for (var i = 0; i < _tasks.length; i++) {
        _logger.info(
          '  更新后任务[$i]: ID=${_tasks[i].id}, 图片数=${_tasks[i].referenceImages.length}',
          module: '批量空间',
        );
      }

      _saveTasks();
    } else {
      _logger.warning(
        '【_updateTask】任务不存在！',
        module: '批量空间',
        extra: {'taskId': task.id},
      );
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

      // 兼容多种编码：先读字节，再尝试 UTF-8 / 系统编码（GBK/ANSI）
      final bytes = await file.readAsBytes();
      String content;
      try {
        content = utf8.decode(bytes);
      } catch (_) {
        content = systemEncoding.decode(bytes);
      }
      // 去除 UTF-8 BOM 前缀
      if (content.startsWith('\uFEFF')) {
        content = content.substring(1);
      }
      final lines = content.split('\n');

      if (lines.isEmpty) {
        _showMessage('CSV文件为空', isError: true);
        return;
      }

      // 跳过表头
      final dataLines = lines
          .skip(1)
          .where((line) => line.trim().isNotEmpty)
          .toList();

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
        final seconds = parts.length > 2
            ? _validateSeconds(parts[2].trim())
            : '自动';
        final batchCount = parts.length > 3
            ? _validateBatchCount(parts[3].trim())
            : 1;

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

        // 解析生成视频
        final generatedVideos = <String>[];
        if (parts.length > 5 && parts[5].trim().isNotEmpty) {
          final videoPaths = parts[5].split('|');
          for (var videoPath in videoPaths) {
            final trimmedPath = videoPath.trim();
            if (trimmedPath.isNotEmpty && File(trimmedPath).existsSync()) {
              generatedVideos.add(trimmedPath);
            } else if (trimmedPath.isNotEmpty) {
              warnings.add('第${i + 2}行: 视频路径无效 - $trimmedPath');
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
          generatedVideos: generatedVideos,
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
          _logger.info(
            '  任务[$i]: ID=${_tasks[i].id}, 提示词=${_tasks[i].prompt.length > 20 ? _tasks[i].prompt.substring(0, 20) : _tasks[i].prompt}...',
            module: '批量空间',
          );
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
  Future<bool?> _showImportPreview(
    List<VideoTask> tasks,
    List<String> warnings,
  ) async {
    // 统计视频信息
    final tasksWithVideos = tasks
        .where((t) => t.generatedVideos.isNotEmpty)
        .length;
    final totalVideos = tasks.fold<int>(
      0,
      (sum, t) => sum + t.generatedVideos.length,
    );

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
                style: TextStyle(
                  color: AppTheme.textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (tasksWithVideos > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '其中 $tasksWithVideos 个任务包含 $totalVideos 个生成视频',
                  style: TextStyle(color: AppTheme.accentColor, fontSize: 14),
                ),
              ],
              if (warnings.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  '警告 (${warnings.length})',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: warnings
                          .map(
                            (w) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '• $w',
                                style: TextStyle(
                                  color: AppTheme.subTextColor,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          )
                          .toList(),
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
      lines.add('提示词,比例,时长,批量,参考图片,生成视频');

      for (var task in _tasks) {
        final prompt = task.prompt.contains(',')
            ? '"${task.prompt}"'
            : task.prompt;
        final images = task.referenceImages.join('|');
        final videos = task.generatedVideos.join('|');
        lines.add(
          '$prompt,${task.ratio},${task.seconds},${task.batchCount},$images,$videos',
        );
      }

      final file = File(result);
      // 添加 UTF-8 BOM，让 WPS/Excel 识别为 UTF-8 编码
      await file.writeAsString('\uFEFF${lines.join('\n')}', encoding: utf8);

      _logger.success('成功导出 ${_tasks.length} 个任务', module: '批量空间');
      _showMessage('成功导出到 $result');
    } catch (e) {
      _logger.error('导出CSV失败: $e', module: '批量空间');
      _showMessage('导出失败: $e', isError: true);
    }
  }

  /// 批量生成所有任务
  Future<void> _generateAllTasks() async {
    final tasksToGenerate = _tasks
        .where((t) => t.prompt.trim().isNotEmpty)
        .toList();

    if (tasksToGenerate.isEmpty) {
      _showMessage('没有可生成的任务\n请确保任务有提示词', isError: true);
      return;
    }

    _logger.success(
      '🚀 开始批量生成 ${tasksToGenerate.length} 个视频任务',
      module: '批量空间',
    );

    await Future.wait(
      tasksToGenerate.map((task) => _generateSingleTask(task)),
      eagerError: false,
    );

    _logger.success('✅ 批量生成完成', module: '批量空间');
  }

  /// 构建网页服务商的 payload
  Future<Map<String, dynamic>> _buildWebPayload({
    required VideoTask task,
    required String webModel,
    required String webTool,
    required int index,
    required SharedPreferences prefs,
    required String provider,
  }) async {
    final payload = <String, dynamic>{'prompt': task.prompt, 'model': webModel};

    // 添加保存路径
    final savePath = prefs.getString('video_save_path');
    if (savePath != null && savePath.isNotEmpty) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'video_${timestamp}_${task.id}_$index.mp4';
      final fullPath = path.join(savePath, fileName);
      payload['savePath'] = fullPath;
    }

    // 图生视频
    if (webTool == 'img2video') {
      if (task.referenceImages.isEmpty) {
        throw Exception('图生视频需要提供参考图片\n\n请在批量空间添加参考图片后再生成');
      }
      payload['imageUrl'] = task.referenceImages.first;
    }

    // 参考生视频
    if (webTool == 'ref2video') {
      // 检查提示词中是否包含 [📷name] 占位符（图片库内联模式）
      final hasInlinePlaceholders = RegExp(r'\[📷[^\]]+\]').hasMatch(task.prompt);

      if (hasInlinePlaceholders) {
        // 图片库内联模式：解析占位符为 segments
        final segments = await _parsePromptToSegments(task.prompt, prefs);
        if (segments.isNotEmpty) {
          payload['segments'] = segments;
          // 清理 prompt 中的占位符文本，仅保留纯文本部分
          payload['prompt'] = task.prompt.replaceAll(RegExp(r'\[📷[^\]]+\]'), '').trim();
        }
      } else if (task.referenceImages.isNotEmpty) {
        final List<String> assetNames = [];
        final List<String> normalFiles = [];

        for (final refPath in task.referenceImages) {
          final assetName = await _findAssetNameByPath(refPath);
          if (assetName != null && assetName.isNotEmpty) {
            assetNames.add(assetName);
          } else {
            normalFiles.add(refPath);
          }
        }

        if (assetNames.isNotEmpty) {
          payload['characterName'] = assetNames.join(',');
          _logger.info(
            '【批量空间】参考生视频：素材库主体「${assetNames.join(", ")}」',
            module: '批量空间',
          );
        }
        if (normalFiles.isNotEmpty) {
          payload['referenceFile'] = normalFiles.first;
          _logger.info(
            '【批量空间】参考生视频：上传参考文件 ${normalFiles.first}',
            module: '批量空间',
          );
        }
      } else {
        if (task.characterName.isNotEmpty) {
          payload['characterName'] = task.characterName;
          _logger.info(
            '【批量空间】参考生视频：使用任务角色名「${task.characterName}」',
            module: '批量空间',
          );
        }
      }
    }

    // 视频参数
    payload['aspectRatio'] = task.ratio;
    payload['resolution'] = task.quality;
    payload['duration'] = task.seconds;

    // ✅ Vidu 去水印开关
    final viduWmFree = ProviderPreferenceHelper.getVideoWatermarkFree(
      prefs,
      provider,
    );
    if (viduWmFree) {
      payload['watermarkFree'] = true;
    }

    // ✅ 即梦专用：将 segments 转换为 referenceImages + characterNames
    if (provider == 'jimeng') {
      payload['mode'] = ProviderPreferenceHelper.getVideoWebMode(
            prefs,
            provider,
          ) ??
          'all_ref';
      
      // 如果 segments 未设置（webTool 不是 ref2video），但 prompt 中有 [📷xxx]，直接解析
      var segments = payload['segments'] as List<Map<String, String>>?;
      if (segments == null && RegExp(r'\[📷[^\]]+\]').hasMatch(task.prompt)) {
        segments = await _parsePromptToSegments(task.prompt, prefs);
        if (segments.isNotEmpty) {
          payload['prompt'] = task.prompt.replaceAll(RegExp(r'\[📷[^\]]+\]'), '').trim();
        }
      }
      
      if (segments != null && segments.isNotEmpty) {
        final List<String> refImages = [];
        final List<String> charNames = [];
        String cleanPrompt = '';
        for (final seg in segments) {
          if (seg['type'] == 'image' && seg['path'] != null && seg['path']!.isNotEmpty) {
            final name = seg['name'] ?? '';
            if (!charNames.contains(name)) {
              refImages.add(seg['path']!);
              charNames.add(name);
            }
          } else {
            cleanPrompt += seg['content'] ?? '';
          }
        }
        if (refImages.isNotEmpty) {
          payload.remove('segments');
          payload['referenceImages'] = refImages;
          payload['characterNames'] = charNames;
          payload['prompt'] = cleanPrompt;
        }
      }
    }

    return payload;
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

    // 记录每个占位符在 generatedVideos 中的固定索引（防止并发替换时 indexOf 竞态）
    final baseIndex = task.generatedVideos.length;
    final placeholderIndices = <String, int>{
      for (var i = 0; i < placeholders.length; i++)
        placeholders[i]: baseIndex + i,
    };

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

      // 从设置中读取用户保存的模型，优先使用设置模型
      final savedModel = await SecureStorageManager().getModel(provider: provider, modelType: 'video');
      final effectiveModel = savedModel ?? task.model;

      _logger.info('【批量空间】使用 Provider: $provider', module: '批量空间');
      _logger.info(
        '【批量空间】任务信息',
        module: '批量空间',
        extra: {
          'taskId': task.id,
          'prompt': task.prompt.substring(
            0,
            task.prompt.length > 30 ? 30 : task.prompt.length,
          ),
          'model': effectiveModel,
          'ratio': task.ratio,
          'seconds': task.seconds,
          'batchCount': task.batchCount,
          'referenceImages': task.referenceImages.length,
        },
      );

      // ✅ 判断是否为网页服务商
      final isWebProvider = [
        'vidu',
        'jimeng',
        'keling',
        'hailuo',
      ].contains(provider);

      if (isWebProvider) {
        // ========== 网页服务商路线 ==========
        _logger.info(
          '【批量空间】使用网页服务商生成视频',
          module: '批量空间',
          extra: {'provider': provider},
        );

        // 读取网页服务商配置
        final resolvedWebTool =
            ProviderPreferenceHelper.getVideoWebTool(prefs, provider) ?? '';
        final resolvedWebModel =
            ProviderPreferenceHelper.getVideoWebModel(prefs, provider) ?? '';

        if (resolvedWebTool.isEmpty) {
          throw Exception('未配置网页服务商工具\n\n请前往设置页面选择工具类型（如：文生视频）');
        }

        if (resolvedWebModel.isEmpty) {
          throw Exception('未配置网页服务商模型\n\n请前往设置页面选择模型（如：Vidu Q3）');
        }

        _logger.info(
          '【批量空间】网页服务商配置',
          module: '批量空间',
          extra: {
            'provider': provider,
            'tool': resolvedWebTool,
            'model': resolvedWebModel,
          },
        );

        // ✅ 创建 AutomationApiClient 实例
        final aigcClient = AutomationApiClient();

        // ✅ 检查 API 服务是否可用
        final isHealthy = await aigcClient.checkHealth();
        if (!isHealthy) {
          throw Exception(
            'Python API 服务未启动\n\n'
            '请先启动 Python 服务：\n'
            '1. 打开命令行\n'
            '2. 进入项目目录\n'
            '3. 运行: python python_backend/web_automation/api_server.py',
          );
        }

        _logger.success('【批量空间】Python API 服务连接成功', module: '批量空间');

        // ✅ Vidu 需要顺序生成（每次生成需要刷新页面），其他网页服务商可以并发
        final isViduProvider = provider == 'vidu';
        print('🔧 DEBUG批量: provider=$provider, isVidu=$isViduProvider, batchCount=$batchCount, taskId=${task.id}');

        if (isViduProvider) {
          // ========== Vidu 批量生成模式：一次填写提示词，点 N 次创作 ==========
          _logger.info(
            '【批量空间】Vidu 批量模式：一次提交 $batchCount 个视频（点 $batchCount 次创作，间隔 2.5s）',
            module: '批量空间',
          );

          try {
            // 构建 payload（只需一个，共用同一提示词和参数）
            final payload = await _buildWebPayload(
              task: task,
              webModel: resolvedWebModel,
              webTool: resolvedWebTool,
              index: 0,
              prefs: prefs,
              provider: provider,
            );
            // 告诉 Python 点 N 次创作
            payload['batchCount'] = batchCount;

            // ONE submit call → Python 填写一次提示词，点 N 次创作
            final result = await aigcClient.submitGenerationTask(
              platform: provider,
              toolType: resolvedWebTool,
              payload: payload,
            );

            // 获取所有 task_ids
            final taskIds = result.taskIds ?? [result.taskId];

            _logger.success(
              '【批量空间】Vidu 批量提交成功：${taskIds.length} 个任务 $taskIds',
              module: '批量空间',
            );
            print('🔧 DEBUG批量: taskIds=$taskIds, placeholders=$placeholders');

            // 保存 pending 任务信息（防止切换页面丢失）
            for (var i = 0; i < taskIds.length && i < batchCount; i++) {
              await _savePendingTask(
                placeholder: placeholders[i],
                taskId: taskIds[i],
                provider: provider,
                videoTaskId: task.id,
              );
            }

            // 并行轮询所有任务
            final pollFutures = <Future<void>>[];
            for (var i = 0; i < taskIds.length && i < batchCount; i++) {
              final tid = taskIds[i];
              final placeholder = placeholders[i];
              final fixedIndex = placeholderIndices[placeholder] ?? -1;

              pollFutures.add(() async {
                try {
                  _logger.info(
                    '【批量空间】Vidu 轮询任务 ${i + 1}/${taskIds.length}: $tid (占位符索引: $fixedIndex)',
                    module: '批量空间',
                  );

                  final pollResult = await aigcClient.pollTaskStatus(
                    taskId: tid,
                    interval: const Duration(seconds: 3),
                    maxAttempts: 300,
                    onProgress: (taskResult) {
                      if (taskResult.isRunning) {
                        _batchVideoProgress[placeholder] = 50;
                      }
                      if (mounted) setState(() {});
                    },
                  );

                  if (pollResult.isSuccess) {
                    final videoPath =
                        pollResult.localVideoPath ?? pollResult.videoUrl;
                    if (videoPath == null || videoPath.isEmpty) {
                      throw Exception('任务完成但未返回视频地址');
                    }

                    _logger.success(
                      '【批量空间】Vidu 任务 ${i + 1} 完成: $videoPath',
                      module: '批量空间',
                    );

                    // 提取首帧
                    if (!videoPath.startsWith('http') &&
                        videoPath.endsWith('.mp4')) {
                      try {
                        final thumbnailPath = videoPath.replaceAll('.mp4', '.jpg');
                        final ffmpeg = FFmpegService();
                        await ffmpeg.extractFrame(
                          videoPath: videoPath,
                          outputPath: thumbnailPath,
                        );
                      } catch (e) {
                        _logger.warning('【批量空间】提取首帧失败: $e', module: '批量空间');
                      }
                    }

                    // 替换占位符（使用固定索引，避免并发竞态）
                    final currentTask = _tasks.firstWhere((t) => t.id == task.id);
                    final currentVideos = List<String>.from(
                      currentTask.generatedVideos,
                    );
                    if (fixedIndex >= 0 &&
                        fixedIndex < currentVideos.length &&
                        currentVideos[fixedIndex] == placeholder) {
                      currentVideos[fixedIndex] = videoPath;
                      _batchVideoProgress.remove(placeholder);
                      _updateTask(
                        currentTask.copyWith(generatedVideos: currentVideos),
                      );
                    } else {
                      // 索引验证失败，回退到 indexOf
                      final fallbackIndex = currentVideos.indexOf(placeholder);
                      if (fallbackIndex != -1) {
                        currentVideos[fallbackIndex] = videoPath;
                        _batchVideoProgress.remove(placeholder);
                        _updateTask(
                          currentTask.copyWith(generatedVideos: currentVideos),
                        );
                      } else {
                        _logger.warning(
                          '【批量空间】占位符替换失败: fixedIndex=$fixedIndex, placeholder=$placeholder',
                          module: '批量空间',
                        );
                      }
                    }
                    await _removePendingTask(placeholder);
                  } else {
                    throw Exception(pollResult.error ?? '生成失败');
                  }
                } catch (e) {
                  _logger.error(
                    '【批量空间】Vidu 任务 ${i + 1} 失败: $e',
                    module: '批量空间',
                  );
                  // 标记为失败
                  try {
                    final currentTask = _tasks.firstWhere(
                      (t) => t.id == task.id,
                      orElse: () => task,
                    );
                    final currentVideos = List<String>.from(
                      currentTask.generatedVideos,
                    );
                    final idx = (fixedIndex >= 0 &&
                            fixedIndex < currentVideos.length &&
                            currentVideos[fixedIndex] == placeholder)
                        ? fixedIndex
                        : currentVideos.indexOf(placeholder);
                    if (idx != -1) {
                      currentVideos[idx] =
                          'failed_${DateTime.now().millisecondsSinceEpoch}';
                      _batchVideoProgress.remove(placeholder);
                      _updateTask(
                        currentTask.copyWith(generatedVideos: currentVideos),
                      );
                    }
                  } catch (_) {}
                  await _removePendingTask(placeholder);
                  if (mounted) {
                    _showMessage('Vidu 任务 ${i + 1} 失败: $e', isError: true);
                  }
                }
              }()); // 立即执行异步闭包
            }

            await Future.wait(pollFutures);
          } catch (e) {
            _logger.error('【批量空间】Vidu 批量提交失败: $e', module: '批量空间');
            if (mounted) {
              _showMessage('Vidu 批量提交失败: $e', isError: true);
            }
          }

          _logger.success('【批量空间】Vidu 批量生成全部完成', module: '批量空间');
          aigcClient.dispose();
          return;
        }

        // ========== 非 Vidu 网页服务商：并发提交 ==========
        _logger.info('【批量空间】开始并发提交 $batchCount 个网页服务商视频任务', module: '批量空间');

        final submitFutures = List.generate(batchCount, (i) async {
          final placeholder = placeholders[i];

          try {
            _logger.info('【批量空间】提交网页任务 ${i + 1}/$batchCount', module: '批量空间');

            // ✅ 构建 payload（复用辅助方法）
            final payload = await _buildWebPayload(
              task: task,
              webModel: resolvedWebModel,
              webTool: resolvedWebTool,
              index: i,
              prefs: prefs,
              provider: provider,
            );

            // 提交生成任务
            final result = await aigcClient.submitGenerationTask(
              platform: provider,
              toolType: resolvedWebTool,
              payload: payload,
            );

            _logger.success(
              '【批量空间】网页任务 ${i + 1} 提交成功: ${result.taskId}',
              module: '批量空间',
            );
            print(
              '✅ [批量空间] 任务 ${i + 1} 提交成功: taskId=${result.taskId}, status=${result.status}',
            );

            return {
              'index': i,
              'taskId': result.taskId,
              'placeholder': placeholder,
            };
          } catch (e) {
            _logger.error('【批量空间】网页任务 ${i + 1} 提交失败: $e', module: '批量空间');
            rethrow;
          }
        });

        // 等待所有任务提交完成
        final submittedTasks = await Future.wait(submitFutures);
        _logger.success('【批量空间】所有网页任务已提交，开始轮询', module: '批量空间');

        // 保存 pending 任务信息（防止切换页面丢失）
        for (final taskInfo in submittedTasks) {
          await _savePendingTask(
            placeholder: taskInfo['placeholder'] as String,
            taskId: taskInfo['taskId'] as String,
            provider: provider,
            videoTaskId: task.id,
          );
        }

        // ✅ 并发轮询所有任务
        final pollFutures = submittedTasks.map((taskInfo) async {
          final index = taskInfo['index'] as int;
          final taskId = taskInfo['taskId'] as String;
          final placeholder = taskInfo['placeholder'] as String;

          try {
            _logger.info(
              '【批量空间】开始轮询网页任务 ${index + 1}: $taskId',
              module: '批量空间',
            );

            // 轮询任务状态
            final result = await aigcClient.pollTaskStatus(
              taskId: taskId,
              interval: const Duration(seconds: 3),
              maxAttempts: 300, // 最多 15 分钟（与后端 max_wait=900 匹配）
              onProgress: (taskResult) {
                // 更新进度
                if (taskResult.isRunning) {
                  _batchVideoProgress[placeholder] = 50; // 显示 50% 表示运行中
                }

                if (mounted) {
                  setState(() {});
                }

                print(
                  '📡 [批量空间] 任务 ${index + 1} 轮询: status=${taskResult.status}, taskId=$taskId',
                );
                _logger.info(
                  '【批量空间】网页任务 ${index + 1} 状态: ${taskResult.status}',
                  module: '批量空间',
                );
              },
            );

            print(
              '📡 [批量空间] 任务 ${index + 1} 轮询结束: status=${result.status}, success=${result.isSuccess}',
            );

            if (result.isSuccess) {
              // 任务成功完成
              final videoPath = result.localVideoPath ?? result.videoUrl;

              if (videoPath == null || videoPath.isEmpty) {
                throw Exception('任务完成但未返回视频地址');
              }

              _logger.success(
                '【批量空间】网页任务 ${index + 1} 完成',
                module: '批量空间',
                extra: {
                  'videoPath': videoPath,
                  'isLocal': result.localVideoPath != null,
                },
              );

              // ✅ 提取视频首帧作为缩略图（本地文件才需要）
              if (videoPath != null &&
                  !videoPath.startsWith('http') &&
                  videoPath.endsWith('.mp4')) {
                try {
                  final thumbnailPath = videoPath.replaceAll('.mp4', '.jpg');
                  final ffmpeg = FFmpegService();
                  final success = await ffmpeg.extractFrame(
                    videoPath: videoPath,
                    outputPath: thumbnailPath,
                  );
                  if (success) {
                    _logger.success('【批量空间】网页服务商视频首帧已提取', module: '批量空间');
                  }
                } catch (e) {
                  _logger.warning('【批量空间】提取首帧失败: $e', module: '批量空间');
                }
              }

              // 替换占位符
              final currentTask = _tasks.firstWhere((t) => t.id == task.id);
              final currentVideos = List<String>.from(
                currentTask.generatedVideos,
              );
              final placeholderIndex = currentVideos.indexOf(placeholder);

              if (placeholderIndex != -1) {
                currentVideos[placeholderIndex] = videoPath;
                _batchVideoProgress.remove(placeholder);
                _updateTask(
                  currentTask.copyWith(generatedVideos: currentVideos),
                );

                if (mounted) {
                  setState(() {});
                }
              }

              await _removePendingTask(placeholder);
              return true;
            } else {
              // 任务失败
              throw Exception(result.error ?? '生成失败');
            }
          } catch (e) {
            _logger.error('【批量空间】网页任务 ${index + 1} 处理失败: $e', module: '批量空间');
            print('❌ [批量空间] 网页任务 ${index + 1} 失败: $e'); // 确保控制台可见

            // 标记为失败
            try {
              final currentTask = _tasks.firstWhere(
                (t) => t.id == task.id,
                orElse: () => task,
              );
              final currentVideos = List<String>.from(
                currentTask.generatedVideos,
              );
              final placeholderIndex = currentVideos.indexOf(placeholder);

              if (placeholderIndex != -1) {
                currentVideos[placeholderIndex] =
                    'failed_${DateTime.now().millisecondsSinceEpoch}';
                _batchVideoProgress.remove(placeholder);
                _updateTask(
                  currentTask.copyWith(generatedVideos: currentVideos),
                );
              }
            } catch (e2) {
              _logger.error('【批量空间】清理占位符失败: $e2', module: '批量空间');
            }

            await _removePendingTask(placeholder);

            // 显示错误给用户
            if (mounted) {
              _showMessage('任务 ${index + 1} 失败: $e', isError: true);
            }

            return false;
          }
        }).toList();

        // 等待所有任务完成
        await Future.wait(pollFutures, eagerError: false);

        _logger.success('【批量空间】所有网页服务商任务已处理完成', module: '批量空间');

        // 清理资源
        aigcClient.dispose();

        // ✅ 网页服务商处理完成，直接返回
        return;
      }

      // ========== API 服务商路线（原有逻辑）==========
      final baseUrl = await SecureStorageManager().getBaseUrl(
        provider: provider,
        modelType: 'video',
      );
      final apiKey = await SecureStorageManager().getApiKey(
        provider: provider,
        modelType: 'video',
      );

      if (baseUrl == null || apiKey == null) {
        throw Exception('未配置视频 API');
      }

      // ✅ ComfyUI 特殊检查：需要选择工作流
      if (provider.toLowerCase() == 'comfyui') {
        final selectedWorkflow = prefs.getString(
          'comfyui_selected_video_workflow',
        );
        if (selectedWorkflow == null || selectedWorkflow.isEmpty) {
          throw Exception('未选择 ComfyUI 视频工作流\n\n请前往设置页面选择一个视频工作流');
        }

        final workflowsJson = prefs.getString('comfyui_workflows');
        if (workflowsJson == null || workflowsJson.isEmpty) {
          throw Exception('未找到 ComfyUI 工作流数据\n\n请前往设置页面重新读取工作流');
        }

        _logger.success(
          '【批量空间】使用 ComfyUI 工作流: $selectedWorkflow',
          module: '批量空间',
        );

        // ✅ 检查工作流类型
        final workflows = List<Map<String, dynamic>>.from(
          (jsonDecode(workflowsJson) as List).map(
            (w) => Map<String, dynamic>.from(w as Map),
          ),
        );
        final workflow = workflows.firstWhere(
          (w) => w['id'] == selectedWorkflow,
          orElse: () => throw Exception('工作流未找到: $selectedWorkflow'),
        );

        final workflowType = workflow['type'] as String?;
        _logger.info('【批量空间】工作流类型: $workflowType', module: '批量空间');

        if (workflowType != 'video') {
          _logger.warning(
            '⚠️ 选中的工作流不是视频类型！',
            module: '批量空间',
            extra: {
              'workflowName': workflow['name'],
              'workflowType': workflowType,
            },
          );
          throw Exception(
            '选中的工作流不是视频类型\n\n当前工作流: ${workflow['name']}\n类型: $workflowType\n\n请在设置中选择一个视频工作流（类型应为 video）',
          );
        }
      }

      // ✅ RunningHub 检查：需要配置 WebApp ID
      if (provider.toLowerCase() == 'runninghub') {
        final webappId = prefs.getString('runninghub_video_webapp_id');
        if (webappId == null || webappId.isEmpty) {
          throw Exception('未配置 RunningHub 视频 WebApp ID\n\n请前往设置页面配置 RunningHub AI 应用 ID');
        }
        _logger.success('【批量空间】使用 RunningHub: $webappId', module: '批量空间');
      }

      final config = ApiConfig(
        provider: provider,
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
      final apiFactory = ApiFactory();
      final service = apiFactory.createService(provider, config);

      // 准备参数 - "自动"选项不传参数
      final size = task.ratio == '自动'
          ? null
          : _convertRatioToSize(task.ratio, task.quality, effectiveModel);
      final seconds = task.seconds == '自动' ? null : _parseSeconds(task.seconds);

      final parameters = <String, dynamic>{};
      if (seconds != null) {
        parameters['seconds'] = seconds;
      }

      // ComfyUI / RunningHub / OpenAI 同步生成
      if (provider.toLowerCase() == 'comfyui' || provider.toLowerCase() == 'runninghub' || provider.toLowerCase() == 'openai') {
        final generateFutures = List.generate(batchCount, (i) async {
          final placeholder = placeholders[i];

          try {
            final result = await service.generateVideos(
              prompt: task.prompt,
              model: effectiveModel,
              ratio: size,
              referenceImages: task.referenceImages,
              parameters: parameters,
            );

            if (result.isSuccess &&
                result.data != null &&
                result.data!.isNotEmpty) {
              final videoUrl = result.data!.first.videoUrl;
              final savedPath = await _downloadSingleVideoForTask(
                videoUrl,
                i,
                task.id,
              );

              final currentTask = _tasks.firstWhere((t) => t.id == task.id);
              final currentVideos = List<String>.from(
                currentTask.generatedVideos,
              );
              final placeholderIndex = currentVideos.indexOf(placeholder);

              if (placeholderIndex != -1) {
                currentVideos[placeholderIndex] = savedPath;
                _batchVideoProgress.remove(placeholder);
                _updateTask(
                  currentTask.copyWith(generatedVideos: currentVideos),
                );

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
            final currentVideos = List<String>.from(
              currentTask.generatedVideos,
            );
            final placeholderIndex = currentVideos.indexOf(placeholder);

            if (placeholderIndex != -1) {
              currentVideos[placeholderIndex] =
                  'failed_${DateTime.now().millisecondsSinceEpoch}';
              _batchVideoProgress.remove(placeholder);
              _updateTask(currentTask.copyWith(generatedVideos: currentVideos));
            }
          }

          return false;
        });

        await Future.wait(generateFutures, eagerError: false);
      } else if (provider.toLowerCase() == 'yunwu') {
        // Yunwu 服务的异步轮询模式
        final yunwuService = service as YunwuService;
        final yunwuHelper = YunwuHelper(yunwuService);

        final submitFutures = List.generate(batchCount, (i) async {
          final result = await service.generateVideos(
            prompt: task.prompt,
            model: effectiveModel,
            ratio: size,
            referenceImages: task.referenceImages,
            parameters: parameters,
          );

          if (result.isSuccess &&
              result.data != null &&
              result.data!.isNotEmpty) {
            return {
              'index': i,
              'taskId': result.data!.first.videoId,
              'placeholder': placeholders[i],
            };
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
            final statusResult = await yunwuHelper.pollTaskUntilComplete(
              taskId: taskId,
              maxWaitMinutes: 15,
              onProgress: (progress, status) {
                _batchVideoProgress[placeholder] = progress;
                if (mounted) setState(() {});
              },
            );

            if (statusResult.isSuccess && statusResult.data != null && statusResult.data!.videoUrl != null) {
              final videoUrl = statusResult.data!.videoUrl!;
              final savedPath = await _downloadSingleVideoForTask(
                videoUrl,
                index,
                task.id,
              );

              final currentTask = _tasks.firstWhere((t) => t.id == task.id);
              final currentVideos = List<String>.from(
                currentTask.generatedVideos,
              );
              final placeholderIndex = currentVideos.indexOf(placeholder);

              if (placeholderIndex != -1) {
                currentVideos[placeholderIndex] = savedPath;
                _batchVideoProgress.remove(placeholder);
                _updateTask(
                  currentTask.copyWith(generatedVideos: currentVideos),
                );

                await Future.delayed(const Duration(milliseconds: 500));
                if (mounted) {
                  setState(() {});
                }
              }

              return true;
            }
          } catch (e) {
            final currentTask = _tasks.firstWhere((t) => t.id == task.id);
            final currentVideos = List<String>.from(
              currentTask.generatedVideos,
            );
            final placeholderIndex = currentVideos.indexOf(placeholder);

            if (placeholderIndex != -1) {
              currentVideos[placeholderIndex] =
                  'failed_${DateTime.now().millisecondsSinceEpoch}';
              _batchVideoProgress.remove(placeholder);
              _updateTask(currentTask.copyWith(generatedVideos: currentVideos));
            }
          }

          return false;
        }).toList();

        await Future.wait(pollFutures, eagerError: false);
      } else {
        // 其他服务的异步轮询模式（GeekNow/Veo/OpenAI等）
        // 解析轮询函数：根据服务类型选择对应的 getVideoTaskStatus
        final Future<ApiResponse<VeoTaskStatus>> Function({required String taskId}) getStatusFn;
        if (service is VeoVideoService) {
          getStatusFn = service.getVideoTaskStatus;
        } else if (service is GeekNowService) {
          getStatusFn = service.getVideoTaskStatus;
        } else {
          throw UnsupportedError('${service.runtimeType} 不支持视频任务轮询');
        }

        final submitFutures = List.generate(batchCount, (i) async {
          final result = await service.generateVideos(
            prompt: task.prompt,
            model: effectiveModel,
            ratio: size,
            referenceImages: task.referenceImages,
            parameters: parameters,
          );

          if (result.isSuccess &&
              result.data != null &&
              result.data!.isNotEmpty) {
            return {
              'index': i,
              'taskId': result.data!.first.videoId,
              'placeholder': placeholders[i],
            };
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
            final statusResult = await VeoVideoHelper.pollUntilComplete(
              getStatus: getStatusFn,
              taskId: taskId,
              maxWaitMinutes: 15,
              onProgress: (progress, status) {
                _batchVideoProgress[placeholder] = progress;
                if (mounted) setState(() {});
              },
            );

            if (statusResult.isSuccess && statusResult.data!.hasVideo) {
              final videoUrl = statusResult.data!.videoUrl!;
              final savedPath = await _downloadSingleVideoForTask(
                videoUrl,
                index,
                task.id,
              );

              final currentTask = _tasks.firstWhere((t) => t.id == task.id);
              final currentVideos = List<String>.from(
                currentTask.generatedVideos,
              );
              final placeholderIndex = currentVideos.indexOf(placeholder);

              if (placeholderIndex != -1) {
                currentVideos[placeholderIndex] = savedPath;
                _batchVideoProgress.remove(placeholder);
                _updateTask(
                  currentTask.copyWith(generatedVideos: currentVideos),
                );

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
            final currentVideos = List<String>.from(
              currentTask.generatedVideos,
            );
            final placeholderIndex = currentVideos.indexOf(placeholder);

            if (placeholderIndex != -1) {
              currentVideos[placeholderIndex] =
                  'failed_${DateTime.now().millisecondsSinceEpoch}';
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
      print('❌ [批量空间] 外层异常: $e');

      // 清理占位符
      try {
        final currentTask = _tasks.firstWhere(
          (t) => t.id == task.id,
          orElse: () => task,
        );
        final currentVideos = List<String>.from(currentTask.generatedVideos);
        for (var placeholder in placeholders) {
          final index = currentVideos.indexOf(placeholder);
          if (index != -1) {
            currentVideos[index] =
                'failed_${DateTime.now().millisecondsSinceEpoch}';
            _batchVideoProgress.remove(placeholder);
          }
        }
        _updateTask(currentTask.copyWith(generatedVideos: currentVideos));
      } catch (e2) {
        _logger.error('清理占位符失败: $e2', module: '批量空间');
      }
    }
  }

  /// 下载单个视频
  Future<String> _downloadSingleVideoForTask(
    String videoUrl,
    int index,
    String taskId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savePath = prefs.getString('video_save_path');

      if (savePath == null || savePath.isEmpty) {
        _logger.warning('未设置视频保存路径，使用在线URL', module: '批量空间');
        return videoUrl;
      }

      _logger.info(
        '开始下载视频 ${index + 1}',
        module: '批量空间',
        extra: {'url': videoUrl},
      );

      final response = await http
          .get(Uri.parse(videoUrl))
          .timeout(const Duration(minutes: 5));

      if (response.statusCode == 200) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'video_${timestamp}_${taskId}_$index.mp4';
        final filePath = path.join(savePath, fileName);

        await File(filePath).writeAsBytes(response.bodyBytes);

        _logger.success(
          '视频已保存',
          module: '批量空间',
          extra: {
            'path': filePath,
            'size':
                '${(response.bodyBytes.length / 1024 / 1024).toStringAsFixed(2)} MB',
          },
        );

        // ✅ 提取首帧
        try {
          final thumbnailPath = filePath.replaceAll('.mp4', '.jpg');
          _logger.info(
            '开始提取视频首帧',
            module: '批量空间',
            extra: {'video': filePath, 'thumbnail': thumbnailPath},
          );

          final ffmpeg = FFmpegService();
          final success = await ffmpeg.extractFrame(
            videoPath: filePath,
            outputPath: thumbnailPath,
          );

          if (success) {
            _logger.success(
              '视频首帧已提取',
              module: '批量空间',
              extra: {'thumbnail': thumbnailPath},
            );
          } else {
            _logger.warning('首帧提取失败', module: '批量空间');
          }
        } catch (e) {
          _logger.error('提取首帧失败: $e', module: '批量空间');
        }

        return filePath;
      } else {
        _logger.warning(
          '下载失败（状态码: ${response.statusCode}），使用在线URL',
          module: '批量空间',
        );
        return videoUrl;
      }
    } catch (e) {
      _logger.error('下载视频失败: $e', module: '批量空间');
    }

    return videoUrl;
  }

  /// 解析提示词中的 [📷name] 占位符，生成 segments 列表
  Future<List<Map<String, String>>> _parsePromptToSegments(
    String prompt,
    SharedPreferences prefs,
  ) async {
    // 加载图片库
    final imageLibJson = prefs.getString('image_library_data');
    final Map<String, String> nameToPath = {};
    if (imageLibJson != null && imageLibJson.isNotEmpty) {
      final List<dynamic> imageList = jsonDecode(imageLibJson);
      for (final item in imageList) {
        final name = (item as Map<String, dynamic>)['name'] as String? ?? '';
        final filePath = item['path'] as String? ?? '';
        if (name.isNotEmpty && filePath.isNotEmpty) {
          nameToPath[name] = filePath;
        }
      }
    }

    final segments = <Map<String, String>>[];
    final pattern = RegExp(r'\[📷([^\]]+)\]');
    int lastEnd = 0;

    for (final match in pattern.allMatches(prompt)) {
      if (match.start > lastEnd) {
        final textBefore = prompt.substring(lastEnd, match.start).trim();
        if (textBefore.isNotEmpty) {
          segments.add({'type': 'text', 'content': textBefore});
        }
      }
      final name = match.group(1)!.trim();
      final filePath = nameToPath[name] ?? '';
      if (filePath.isNotEmpty) {
        segments.add({'type': 'image', 'name': name, 'path': filePath});
      } else {
        _logger.warning('图片库中未找到: $name', module: '批量空间');
        segments.add({'type': 'text', 'content': '[📷$name]'});
      }
      lastEnd = match.end;
    }

    if (lastEnd < prompt.length) {
      final textAfter = prompt.substring(lastEnd).trim();
      if (textAfter.isNotEmpty) {
        segments.add({'type': 'text', 'content': textAfter});
      }
    }

    return segments;
  }

  /// 根据图片路径在素材库中查找素材名称
  /// 如果找到，说明这张图来自素材库，返回用户自定义的名称
  Future<String?> _findAssetNameByPath(String imagePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final assetsJson = prefs.getString('asset_library_data');
      if (assetsJson == null || assetsJson.isEmpty) {
        _logger.warning('素材库数据为空，无法查找: $imagePath', module: '批量空间');
        return null;
      }

      final data = jsonDecode(assetsJson) as Map<String, dynamic>;
      // ✅ 规范化路径用于比较（Windows 路径大小写不敏感，分隔符可能不同）
      final normalizedInput = imagePath.replaceAll('\\', '/').toLowerCase();
      // 提取文件名用于回退匹配
      final inputFileName = normalizedInput.split('/').last;

      String? fallbackMatch; // 文件名匹配的回退结果

      for (final entry in data.values) {
        final stylesList = entry as List;
        for (final styleData in stylesList) {
          final assets = (styleData['assets'] as List?) ?? [];
          for (final assetData in assets) {
            final asset = assetData as Map<String, dynamic>;
            final assetPath = (asset['path'] as String?) ?? '';
            final normalizedAsset = assetPath
                .replaceAll('\\', '/')
                .toLowerCase();

            // 策略1：完整路径匹配（规范化后）
            if (normalizedAsset == normalizedInput || assetPath == imagePath) {
              final name = asset['name'] as String? ?? '';
              if (name.isNotEmpty &&
                  !name.contains('.png') &&
                  !name.contains('.jpg') &&
                  !name.contains('.jpeg') &&
                  !name.contains('.webp')) {
                return name;
              }
              return null;
            }

            // 策略2：文件名匹配（回退）
            if (fallbackMatch == null) {
              final assetFileName = normalizedAsset.split('/').last;
              if (assetFileName == inputFileName && assetFileName.isNotEmpty) {
                final name = asset['name'] as String? ?? '';
                if (name.isNotEmpty &&
                    !name.contains('.png') &&
                    !name.contains('.jpg') &&
                    !name.contains('.jpeg') &&
                    !name.contains('.webp')) {
                  fallbackMatch = name;
                }
              }
            }
          }
        }
      }

      // 完整路径未匹配，使用文件名回退
      if (fallbackMatch != null) {
        _logger.info(
          '素材库查找: 使用文件名回退匹配 "$fallbackMatch" for $imagePath',
          module: '批量空间',
        );
        return fallbackMatch;
      }
    } catch (e) {
      _logger.error('查找素材名称失败: $e', module: '批量空间');
    }
    return null;
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
        content: Text(
          '确定要删除所有任务吗？此操作不可恢复。',
          style: TextStyle(color: AppTheme.subTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: AppTheme.subTextColor)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              final count = _tasks.length;
              for (final c in _promptControllers.values) { c.dispose(); }
              _promptControllers.clear();
              setState(() => _tasks.clear());
              _saveTasks();
              _logger.warning(
                '清空所有批量任务',
                module: '批量空间',
                extra: {'删除数量': count},
              );
              _showMessage('已清空 $count 个任务');
            },
            child: const Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// 智能匹配类型选择对话框
  void _showSmartMatchTypeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceBackground,
        title: Text('选择匹配类型', style: TextStyle(color: AppTheme.textColor)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 主体库匹配
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  _smartMatchAssets(matchSource: 'asset');
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.inputBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.dividerColor),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.person, color: AppTheme.accentColor, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('主体库匹配', style: TextStyle(color: AppTheme.textColor, fontSize: 15, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('从素材库匹配角色/场景/道具，添加为参考图片', style: TextStyle(color: AppTheme.subTextColor, fontSize: 12)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: AppTheme.subTextColor),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 图片库匹配
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  _smartMatchAssets(matchSource: 'imageLib');
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.inputBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.dividerColor),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.image, color: Colors.orangeAccent, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('图片库匹配', style: TextStyle(color: AppTheme.textColor, fontSize: 15, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('从图片库匹配，插入 [📷名称] 占位符到提示词', style: TextStyle(color: AppTheme.subTextColor, fontSize: 12)),
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

  /// ✅ 智能匹配 - 通过 LLM 分析提示词，自动匹配素材
  Future<void> _smartMatchAssets({required String matchSource}) async {
    if (_tasks.isEmpty) {
      _showMessage('没有任务可匹配', isError: true);
      return;
    }

    // 只处理有提示词的任务
    final tasksWithPrompt = _tasks
        .where((t) => t.prompt.trim().isNotEmpty)
        .toList();
    if (tasksWithPrompt.isEmpty) {
      _showMessage('没有包含提示词的任务', isError: true);
      return;
    }

    setState(() => _isSmartMatching = true);

    try {
      // 1. 根据 matchSource 加载对应的库数据
      final prefs = await SharedPreferences.getInstance();
      final allAssets = <Map<String, String>>[];

      if (matchSource == 'asset') {
        // 主体库匹配
        final assetsJson = prefs.getString('asset_library_data');
        if (assetsJson == null || assetsJson.isEmpty) {
          _showMessage('素材库为空\n请先在素材库中添加图片', isError: true);
          return;
        }
        final data = jsonDecode(assetsJson) as Map<String, dynamic>;
        data.forEach((key, value) {
          final stylesList = (value as List);
          for (var styleData in stylesList) {
            final assets = (styleData['assets'] as List?) ?? [];
            for (var assetData in assets) {
              final assetMap = assetData as Map<String, dynamic>;
              final name = assetMap['name'] as String? ?? '';
              final assetPath = assetMap['path'] as String? ?? '';
              if (name.isNotEmpty && assetPath.isNotEmpty) {
                allAssets.add({'path': assetPath, 'name': name, 'source': 'asset'});
              }
            }
          }
        });
      } else {
        // 图片库匹配
        final imageLibJson = prefs.getString('image_library_data');
        if (imageLibJson == null || imageLibJson.isEmpty) {
          _showMessage('图片库为空\n请先在图片库中添加图片', isError: true);
          return;
        }
        final List<dynamic> imageList = jsonDecode(imageLibJson);
        for (final item in imageList) {
          final imgItem = item as Map<String, dynamic>;
          final name = imgItem['name'] as String? ?? '';
          final imgPath = imgItem['path'] as String? ?? '';
          if (name.isNotEmpty && imgPath.isNotEmpty) {
            allAssets.add({'path': imgPath, 'name': name, 'source': 'imageLib'});
          }
        }
      }

      if (allAssets.isEmpty) {
        _showMessage('${matchSource == 'asset' ? '素材库' : '图片库'}中没有可用的资产', isError: true);
        return;
      }

      // 提取所有素材名称（去重）
      final assetNames = allAssets.map((a) => a['name']!).toSet().toList();
      _logger.info(
        '【智能匹配-${matchSource == 'asset' ? '主体库' : '图片库'}】共 ${allAssets.length} 个资产，${assetNames.length} 个不同名称',
        module: '批量空间',
      );

      // 2. 读取 LLM 配置
      final llmProvider = prefs.getString('llm_provider') ?? 'geeknow';
      final llmModel = await SecureStorageManager().getModel(
        provider: llmProvider,
        modelType: 'llm',
      );

      _logger.info('【智能匹配】使用 LLM: $llmProvider, 模型: $llmModel', module: '批量空间');

      // 3. 构建 LLM 的提示词，让它分析所有任务的提示词
      final promptList = tasksWithPrompt
          .asMap()
          .entries
          .map((entry) {
            return '任务${entry.key + 1}: ${entry.value.prompt}';
          })
          .join('\n');

      final systemPrompt =
          '''你是一个素材匹配助手。用户有以下素材库资产名称列表：
${assetNames.join('、')}

用户将给你一系列视频生成提示词。请分析每个提示词的内容，找出其中**提到的、对应的、或描述的**素材库资产名称。

规则：
1. 只匹配素材库中存在的名称，不要编造
2. 即使提示词中没有精确出现名称，但如果语义上明显指的是某个素材，也算匹配
3. 一个提示词可以匹配多个素材
4. 如果提示词中没有匹配任何素材，返回空数组

请严格按以下 JSON 格式返回（不要添加任何其他文字或markdown标记）：
{"matches": [{"taskIndex": 0, "assetNames": ["素材名1", "素材名2"]}, {"taskIndex": 1, "assetNames": []}]}

taskIndex 从 0 开始，对应任务序号。''';

      final userPrompt = '请分析以下提示词，匹配素材库资产：\n\n$promptList';

      _logger.info(
        '【智能匹配】调用 LLM 分析 ${tasksWithPrompt.length} 个提示词',
        module: '批量空间',
      );

      // 4. 调用 LLM
      _apiRepository.clearCache();
      final response = await _apiRepository.generateTextWithMessages(
        provider: llmProvider,
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        model: llmModel,
        parameters: {'temperature': 0.1, 'max_tokens': 4000},
      );

      if (!response.isSuccess || response.data == null) {
        throw Exception('LLM 调用失败: ${response.errorMessage ?? "未知错误"}');
      }

      final responseText = response.data!.text.trim();
      _logger.info('【智能匹配】LLM 返回: $responseText', module: '批量空间');

      // 5. 解析 LLM 返回的 JSON
      // 清除可能的 markdown 代码块标记
      String cleanJson = responseText;
      if (cleanJson.contains('```json')) {
        cleanJson = cleanJson
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();
      } else if (cleanJson.contains('```')) {
        cleanJson = cleanJson.replaceAll('```', '').trim();
      }

      final matchResult = jsonDecode(cleanJson) as Map<String, dynamic>;
      final matches = (matchResult['matches'] as List?) ?? [];

      // 6. 根据匹配结果更新每个任务
      int matchedCount = 0;
      int totalImagesAdded = 0;

      for (final match in matches) {
        final taskIndex = match['taskIndex'] as int;
        final matchedAssetNames = List<String>.from(
          match['assetNames'] as List? ?? [],
        );

        if (matchedAssetNames.isEmpty) continue;
        if (taskIndex < 0 || taskIndex >= tasksWithPrompt.length) continue;

        final task = tasksWithPrompt[taskIndex];

        // 分离：普通素材库资产 vs 图片库资产
        final matchedPaths = <String>[];
        final imageLibPlaceholders = <String>[];

        for (final assetName in matchedAssetNames) {
          final matchedAsset = allAssets.firstWhere(
            (a) => a['name'] == assetName,
            orElse: () => <String, String>{},
          );
          if (matchedAsset.isNotEmpty && matchedAsset['path']!.isNotEmpty) {
            if (matchedAsset['source'] == 'imageLib') {
              // 图片库资产 → 插入占位符到提示词
              imageLibPlaceholders.add('[📷$assetName]');
            } else {
              // 普通素材库资产 → 设置到 referenceImages
              matchedPaths.add(matchedAsset['path']!);
            }
          }
        }

        if (matchedPaths.isEmpty && imageLibPlaceholders.isEmpty) continue;

        _logger.info(
          '【智能匹配】任务 ${taskIndex + 1}: 匹配到 ${matchedAssetNames.join(", ")}',
          module: '批量空间',
        );

        // 构建更新后的提示词（在每个匹配名称后紧跟插入占位符）
        String updatedPrompt = task.prompt;
        if (imageLibPlaceholders.isNotEmpty) {
          // 按名称长度降序排列，避免短名称先匹配导致长名称被截断
          final sortedNames = matchedAssetNames
              .where((name) => imageLibPlaceholders.contains('[📷$name]'))
              .toList()
            ..sort((a, b) => b.length.compareTo(a.length));

          for (final name in sortedNames) {
            final placeholder = '[📷$name]';
            // 找到名称在文本中的位置，在其后面插入占位符
            final nameIndex = updatedPrompt.indexOf(name);
            if (nameIndex >= 0) {
              final insertPos = nameIndex + name.length;
              updatedPrompt = updatedPrompt.substring(0, insertPos) +
                  placeholder +
                  updatedPrompt.substring(insertPos);
            }
          }
        }

        final updatedTask = task.copyWith(
          referenceImages: matchedPaths.isNotEmpty ? matchedPaths : task.referenceImages,
          prompt: updatedPrompt,
        );
        _updateTask(updatedTask);

        matchedCount++;
        totalImagesAdded += matchedPaths.length + imageLibPlaceholders.length;
      }

      _logger.success(
        '【智能匹配】完成！匹配了 $matchedCount 个任务，添加了 $totalImagesAdded 张图片',
        module: '批量空间',
      );
      _showMessage('智能匹配完成\n匹配了 $matchedCount 个任务，添加了 $totalImagesAdded 张素材图片');
    } catch (e, stackTrace) {
      _logger.error(
        '【智能匹配】失败: $e',
        module: '批量空间',
        extra: {'stackTrace': stackTrace.toString()},
      );
      _showMessage('智能匹配失败: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSmartMatching = false);
      }
    }
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
                  'R·O·S 动漫制作',
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
                    setState(() {
                      _showSettings = true;
                    });
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
          body: Column(
            children: [
              // ✅ 标题栏
              _buildTitleBar(),
              Expanded(
                child: _showSettings
                    ? SettingsPage(
                        onBack: () => setState(() => _showSettings = false),
                      )
                    : Column(
                        children: [
                          _buildToolbar(),
                          Expanded(
                            child: _tasks.isEmpty
                                ? _buildEmptyState()
                                : _buildTable(),
                          ),
                        ],
                      ),
              ),
            ],
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.textColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.arrow_back,
                      color: AppTheme.subTextColor,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '返回',
                      style: TextStyle(
                        color: AppTheme.subTextColor,
                        fontSize: 13,
                      ),
                    ),
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
          // ✅ 智能匹配
          _toolButton(
            Icons.auto_fix_high,
            _isSmartMatching ? '匹配中...' : '智能匹配',
            _isSmartMatching ? () {} : _showSmartMatchTypeDialog,
          ),
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

  Widget _toolButton(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? color,
  }) {
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
              Text(
                label,
                style: TextStyle(
                  color: color ?? AppTheme.subTextColor,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _batchGenerateButton() {
    final hasValidTasks = _tasks.any((t) => t.prompt.trim().isNotEmpty);
    final isAnyGenerating = _tasks.any(
      (t) => t.generatedVideos.any((v) => v.startsWith('loading_')),
    );

    return MouseRegion(
      cursor: hasValidTasks && !isAnyGenerating
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
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
                  ? [
                      BoxShadow(
                        color: const Color(0xFFFF6B6B).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
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
            gradient: const LinearGradient(
              colors: [Color(0xFF2AF598), Color(0xFF009EFD)],
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2AF598).withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: const [
              Icon(Icons.add, color: Colors.white, size: 18),
              SizedBox(width: 6),
              Text(
                '新建行',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
          SizedBox(width: 110, child: _buildImageCell(task)),
          // 提示词
          Expanded(child: _buildPromptCell(task)),
          // 视频
          SizedBox(width: 110, child: _buildVideoCell(task)),
          // 设置
          SizedBox(width: 240, child: _buildSettingsCell(task)),
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
          onTapUp: (details) {
            _logger.info('点击添加图片', module: '批量空间', extra: {'taskId': task.id});
            _showImageSourceDialog(task.id, tapPosition: details.globalPosition);
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
            _showImagesDialog(task.id); // ✅ 传递 task ID
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
          _logger.info(
            '点击查看多张图片',
            module: '批量空间',
            extra: {'taskId': task.id, '图片数': task.referenceImages.length},
          );
          _showImagesDialog(task.id); // ✅ 传递 task ID
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
                    const Icon(
                      Icons.photo_library,
                      color: Colors.white,
                      size: 18,
                    ),
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
  TextEditingController _getPromptController(VideoTask task) {
    if (!_promptControllers.containsKey(task.id)) {
      _promptControllers[task.id] = TextEditingController(text: task.prompt);
    }
    final controller = _promptControllers[task.id]!;
    // 同步外部更新（智能匹配等）
    // IME 组合期间不同步，避免打断输入法造成重复输入
    if (controller.text != task.prompt &&
        controller.value.composing == TextRange.empty) {
      final cursorPos = controller.selection.baseOffset;
      controller.text = task.prompt;
      if (cursorPos >= 0 && cursorPos <= task.prompt.length) {
        controller.selection = TextSelection.collapsed(offset: cursorPos);
      }
    }
    return controller;
  }

  Widget _buildPromptCell(VideoTask task) {
    final controller = _getPromptController(task);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextFormField(
        controller: controller,
        maxLines: null, // ✅ 允许多行
        minLines: 1,
        style: TextStyle(color: AppTheme.textColor, fontSize: 13),
        decoration: InputDecoration(
          hintText: '输入视频描述...',
          hintStyle: TextStyle(
            color: AppTheme.subTextColor.withOpacity(0.5),
            fontSize: 12,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          isDense: true,
        ),
        onChanged: (v) {
          // 直接更新数据，不触发 setState/rebuild（避免打断 IME 输入法）
          final index = _tasks.indexWhere((t) => t.id == task.id);
          if (index != -1) {
            _tasks[index] = _tasks[index].copyWith(prompt: v);
            _saveTasks();
          }
        },
      ),
    );
  }

  /// 构建视频单元格
  Widget _buildVideoCell(VideoTask task) {
    // 过滤掉失败的占位符，保留真实视频和加载中的视频
    final allVideos = task.generatedVideos
        .where((v) => !v.startsWith('failed_'))
        .toList();

    // 真实视频（不包括 loading）
    final realVideos = allVideos
        .where((v) => !v.startsWith('loading_'))
        .toList();

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
      final thumbnailPath = videoPath.replaceAll('.mp4', '.jpg');
      final thumbnailFile = File(thumbnailPath);

      if (!hasLoading) {
        // 只有一个视频且没有生成中的，显示缩略图（点击弹出对话框）
        return FutureBuilder<bool>(
          key: ValueKey('${thumbnailPath}_single'),
          future: thumbnailFile.exists(),
          builder: (context, thumbnailSnapshot) {
            final coverUrl = thumbnailSnapshot.data == true
                ? thumbnailPath
                : null;

            return DraggableMediaItem(
              filePath: videoPath,
              dragPreviewText: path.basename(videoPath),
              coverUrl: coverUrl,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _showVideosDialog(task.id), // ✅ 点击弹出对话框
                  onSecondaryTapDown: (details) => _showSingleVideoContextMenu(
                    context,
                    details,
                    videoPath,
                    task,
                  ),
                  child: _buildVideoThumbnail(videoPath, clickable: false),
                ),
              ),
            );
          },
        );
      } else {
        // 有一个视频 + 有生成中的，显示缩略图 + 生成中标记，点击弹出对话框
        final loadingVideos = allVideos
            .where((v) => v.startsWith('loading_'))
            .toList();

        return FutureBuilder<bool>(
          key: ValueKey('${thumbnailPath}_loading'),
          future: thumbnailFile.exists(),
          builder: (context, thumbnailSnapshot) {
            final coverUrl = thumbnailSnapshot.data == true
                ? thumbnailPath
                : null;

            return DraggableMediaItem(
              filePath: videoPath,
              dragPreviewText: path.basename(videoPath),
              coverUrl: coverUrl,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Stack(
                  children: [
                    // ✅ 缩略图（点击弹出对话框）
                    GestureDetector(
                      onTap: () => _showVideosDialog(task.id),
                      onSecondaryTapDown: (details) =>
                          _showSingleVideoContextMenu(
                            context,
                            details,
                            videoPath,
                            task,
                          ),
                      child: _buildVideoThumbnail(videoPath, clickable: false),
                    ),
                    // 生成中标记（点击弹出对话框）
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => _showVideosDialog(task.id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
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
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
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
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }
    }

    // ✅ 有真实视频（可能还有生成中的）- 点击弹出对话框查看所有视频（包括生成中的）
    final firstVideoPath = realVideos.first;
    final thumbnailPath = firstVideoPath.replaceAll('.mp4', '.jpg');
    final thumbnailFile = File(thumbnailPath);

    return FutureBuilder<bool>(
      key: ValueKey('${thumbnailPath}_multiple'),
      future: thumbnailFile.exists(),
      builder: (context, thumbnailSnapshot) {
        final coverUrl = thumbnailSnapshot.data == true ? thumbnailPath : null;

        return DraggableMediaItem(
          filePath: firstVideoPath,
          dragPreviewText: path.basename(firstVideoPath),
          coverUrl: coverUrl,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _showVideosDialog(task.id), // ✅ 传递 task ID
              child: Stack(
                children: [
                  // ✅ 背景显示第一个视频的缩略图
                  _buildVideoThumbnail(realVideos.first),
                  // 数量标记（显示已完成/总数）
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: hasLoading
                            ? Colors.orange
                            : AppTheme.accentColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Text(
                        hasLoading
                            ? '${realVideos.length}/${allVideos.length}'
                            : '${realVideos.length}',
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
    );
  }

  /// 构建视频缩略图（显示首帧）
  Widget _buildVideoThumbnail(
    String videoPath, {
    VoidCallback? onTap,
    bool clickable = true,
  }) {
    if (videoPath.startsWith('http')) {
      // 在线视频 - 显示播放图标
      return Container(
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: AppTheme.inputBackground,
        ),
        child: const Center(
          child: Icon(
            Icons.play_circle_outline,
            color: Colors.white54,
            size: 32,
          ),
        ),
      );
    }

    // ✅ 本地视频 - 显示首帧缩略图
    final thumbnailPath = videoPath.replaceAll('.mp4', '.jpg');
    final thumbnailFile = File(thumbnailPath);

    Widget content = FutureBuilder<bool>(
      key: ValueKey(thumbnailPath), // ✅ 添加 key 确保每次都重新检查
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
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 20,
                ),
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
        child: GestureDetector(onTap: onTap, child: content),
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
              child: _buildCompactDropdown(task.ratio, [
                '自动',
                '16:9',
                '9:16',
                '1:1',
                '4:3',
                '3:4',
              ], (v) => _updateTask(task.copyWith(ratio: v))),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildCompactDropdown(task.seconds, [
                '自动',
                '5秒',
                '10秒',
                '15秒',
              ], (v) => _updateTask(task.copyWith(seconds: v))),
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
              child: Tooltip(
                message: '删除',
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _deleteTask(task.id),
                    child: Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.inputBackground, // ✅ 改为正常颜色
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.dividerColor),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.delete_outline,
                          color: AppTheme.subTextColor,
                          size: 16,
                        ), // ✅ 正常颜色
                      ),
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
  Widget _buildCompactDropdown(
    String value,
    List<String> items,
    Function(String) onChanged,
  ) {
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
        items: items
            .map(
              (i) => DropdownMenuItem(
                value: i,
                child: Text(
                  i,
                  style: TextStyle(color: AppTheme.textColor, fontSize: 11),
                ),
              ),
            )
            .toList(),
        onChanged: (v) => onChanged(v!),
        underline: const SizedBox(),
        dropdownColor: AppTheme.surfaceBackground,
        icon: Icon(
          Icons.arrow_drop_down,
          color: AppTheme.subTextColor,
          size: 16,
        ),
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
          Text(
            '批量',
            style: TextStyle(color: AppTheme.subTextColor, fontSize: 10),
          ),
          const SizedBox(width: 4),
          MouseRegion(
            cursor: task.batchCount > 1
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: GestureDetector(
              onTap: task.batchCount > 1
                  ? () => _updateTask(
                      task.copyWith(batchCount: task.batchCount - 1),
                    )
                  : null,
              child: Icon(
                Icons.remove,
                color: task.batchCount > 1
                    ? AppTheme.textColor
                    : AppTheme.subTextColor.withOpacity(0.3),
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
            cursor: task.batchCount < 20
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: GestureDetector(
              onTap: task.batchCount < 20
                  ? () => _updateTask(
                      task.copyWith(batchCount: task.batchCount + 1),
                    )
                  : null,
              child: Icon(
                Icons.add,
                color: task.batchCount < 20
                    ? AppTheme.textColor
                    : AppTheme.subTextColor.withOpacity(0.3),
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 显示图片来源选择对话框
  void _showImageSourceDialog(String taskId, {Offset? tapPosition}) {
    _logger.info('显示图片来源菜单', module: '批量空间', extra: {'taskId': taskId});
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final pos = tapPosition ?? Offset(overlay.size.width / 2, overlay.size.height / 2);
    
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(pos.dx, pos.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      color: AppTheme.surfaceBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(
          value: 'local',
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 16, color: AppTheme.textColor),
              const SizedBox(width: 8),
              Text('本地文件', style: TextStyle(color: AppTheme.textColor, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'library',
          child: Row(
            children: [
              Icon(Icons.photo_library, size: 16, color: AppTheme.textColor),
              const SizedBox(width: 8),
              Text('素材库', style: TextStyle(color: AppTheme.textColor, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'image_library',
          child: Row(
            children: [
              Icon(Icons.image, size: 16, color: AppTheme.textColor),
              const SizedBox(width: 8),
              Text('图片库', style: TextStyle(color: AppTheme.textColor, fontSize: 13)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'local') _addLocalImages(taskId);
      else if (value == 'library') _addAssetLibraryImages(taskId);
      else if (value == 'image_library') _addImageLibraryPlaceholders(taskId);
    });
  }

  /// 添加本地图片
  Future<void> _addLocalImages(String taskId) async {
    try {
      _logger.info('【添加本地图片】开始', module: '批量空间', extra: {'接收到的taskId': taskId});

      // ✅ 先输出所有任务的ID，确认列表状态
      for (var i = 0; i < _tasks.length; i++) {
        _logger.info(
          '  任务列表[$i]: ID=${_tasks[i].id}, 图片数=${_tasks[i].referenceImages.length}',
          module: '批量空间',
        );
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
          _logger.error(
            '【添加本地图片】未找到任务！',
            module: '批量空间',
            extra: {'taskId': taskId},
          );
          _showMessage('任务不存在', isError: true);
          return;
        }

        final task = _tasks[taskIndex];
        _logger.info(
          '【添加本地图片】找到任务，索引: $taskIndex，当前图片数: ${task.referenceImages.length}',
          module: '批量空间',
        );

        final updatedTask = task.copyWith(
          referenceImages: [...task.referenceImages, ...newImages],
        );

        _logger.info(
          '更新任务，图片总数: ${updatedTask.referenceImages.length}',
          module: '批量空间',
        );
        _updateTask(updatedTask);
        _showMessage('添加了 ${newImages.length} 张图片');
        _logger.success(
          '添加本地图片成功',
          module: '批量空间',
          extra: {'数量': newImages.length, '任务索引': taskIndex},
        );
      } else {
        _logger.info('用户取消选择图片', module: '批量空间');
      }
    } catch (e, stackTrace) {
      _logger.error(
        '添加本地图片失败: $e',
        module: '批量空间',
        extra: {'stackTrace': stackTrace.toString()},
      );
      _showMessage('添加失败: $e', isError: true);
    }
  }

  /// 添加素材库图片
  Future<void> _addAssetLibraryImages(String taskId) async {
    try {
      _logger.info(
        '【添加素材库图片】开始',
        module: '批量空间',
        extra: {'接收到的taskId': taskId},
      );

      // 加载素材库数据
      final prefs = await SharedPreferences.getInstance();
      final assetsJson = prefs.getString('asset_library_data');

      if (assetsJson == null || assetsJson.isEmpty) {
        _showMessage('素材库为空\n请先在素材库中添加图片', isError: true);
        return;
      }

      // 按分类整理素材
      final data = jsonDecode(assetsJson) as Map<String, dynamic>;
      final assetsByCategory = <int, List<Map<String, String>>>{};

      for (int i = 0; i < 3; i++) {
        final categoryData = data['$i'];
        final assets = <Map<String, String>>[];
        if (categoryData != null) {
          final stylesList = categoryData as List;
          for (var styleData in stylesList) {
            final assetsList = (styleData['assets'] as List?) ?? [];
            for (var assetData in assetsList) {
              final asset = assetData as Map<String, dynamic>;
              assets.add({
                'path': asset['path'] as String,
                'name': asset['name'] as String,
              });
            }
          }
        }
        assetsByCategory[i] = assets;
      }

      final totalAssets = assetsByCategory.values.fold<int>(0, (sum, list) => sum + list.length);
      if (totalAssets == 0) {
        _showMessage('素材库中没有图片\n请先在素材库中添加图片', isError: true);
        return;
      }

      // 显示素材库选择对话框
      final selectedAssets = await _showAssetLibraryDialog(assetsByCategory);

      if (selectedAssets != null && selectedAssets.isNotEmpty) {
        _logger.info('【添加素材库图片】选择了 ${selectedAssets.length} 张图片', module: '批量空间');

        final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
        if (taskIndex == -1) {
          _showMessage('任务不存在', isError: true);
          return;
        }

        final task = _tasks[taskIndex];
        final updatedTask = task.copyWith(
          referenceImages: [...task.referenceImages, ...selectedAssets],
        );
        _updateTask(updatedTask);
        _showMessage('从素材库添加了 ${selectedAssets.length} 张图片');
      }
    } catch (e, stackTrace) {
      _logger.error(
        '从素材库添加图片失败: $e',
        module: '批量空间',
        extra: {'stackTrace': stackTrace.toString()},
      );
      _showMessage('添加失败: $e', isError: true);
    }
  }

  /// 添加图片库占位符到提示词
  Future<void> _addImageLibraryPlaceholders(String taskId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final imageLibJson = prefs.getString('image_library_data');

      if (imageLibJson == null || imageLibJson.isEmpty) {
        _showMessage('图片库为空\n请先在图片库中添加图片', isError: true);
        return;
      }

      final List<dynamic> imageList = jsonDecode(imageLibJson);
      final allImages = <Map<String, String>>[];
      for (final item in imageList) {
        final imgItem = item as Map<String, dynamic>;
        final name = imgItem['name'] as String? ?? '';
        final imgPath = imgItem['path'] as String? ?? '';
        if (name.isNotEmpty && imgPath.isNotEmpty) {
          allImages.add({'name': name, 'path': imgPath});
        }
      }

      if (allImages.isEmpty) {
        _showMessage('图片库中没有可用图片', isError: true);
        return;
      }

      // 显示图片库选择对话框
      final selectedImages = await _showImageLibraryDialog(allImages);
      if (selectedImages == null || selectedImages.isEmpty) return;

      // 找到对应的任务
      final taskIndex = _tasks.indexWhere((t) => t.id == taskId);
      if (taskIndex == -1) {
        _showMessage('任务不存在', isError: true);
        return;
      }

      final task = _tasks[taskIndex];
      // 生成占位符并在光标位置插入
      final placeholders = selectedImages.map((img) => '[📷${img['name']}]').join(' ');
      final controller = _promptControllers[taskId];
      String updatedPrompt;
      if (controller != null) {
        final cursorPos = controller.selection.baseOffset;
        final text = controller.text;
        if (cursorPos >= 0 && cursorPos <= text.length) {
          updatedPrompt = text.substring(0, cursorPos) + placeholders + text.substring(cursorPos);
          // 更新 controller 并设置光标到插入内容之后
          controller.text = updatedPrompt;
          controller.selection = TextSelection.collapsed(offset: cursorPos + placeholders.length);
        } else {
          updatedPrompt = text.isEmpty ? placeholders : '$placeholders $text';
          controller.text = updatedPrompt;
          controller.selection = TextSelection.collapsed(offset: updatedPrompt.length);
        }
      } else {
        updatedPrompt = task.prompt.isEmpty ? placeholders : '$placeholders ${task.prompt}';
      }

      final updatedTask = task.copyWith(prompt: updatedPrompt);
      _updateTask(updatedTask);

      _showMessage('已插入 ${selectedImages.length} 个图片库占位符');
      _logger.success(
        '插入图片库占位符成功',
        module: '批量空间',
        extra: {'数量': selectedImages.length, '占位符': placeholders},
      );
    } catch (e) {
      _logger.error('添加图片库占位符失败: $e', module: '批量空间');
      _showMessage('添加失败: $e', isError: true);
    }
  }

  /// 显示图片库选择对话框
  Future<List<Map<String, String>>?> _showImageLibraryDialog(
    List<Map<String, String>> allImages,
  ) async {
    String searchQuery = '';

    return showDialog<List<Map<String, String>>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final filtered = searchQuery.isEmpty
              ? allImages
              : allImages.where((item) {
                  final name = (item['name'] ?? '').toLowerCase();
                  return name.contains(searchQuery.toLowerCase());
                }).toList();
          return AlertDialog(
            backgroundColor: AppTheme.surfaceBackground,
            title: Text('选择图片插入', style: TextStyle(color: AppTheme.textColor, fontSize: 16)),
            content: SizedBox(
              width: 400,
              height: 350,
              child: Column(
                children: [
                  TextField(
                    style: TextStyle(color: AppTheme.textColor, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '搜索图片名称...',
                      hintStyle: TextStyle(color: AppTheme.subTextColor, fontSize: 12),
                      prefixIcon: Icon(Icons.search, color: AppTheme.subTextColor, size: 18),
                      filled: true,
                      fillColor: AppTheme.inputBackground,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => searchQuery = v),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(child: Text('无匹配结果', style: TextStyle(color: AppTheme.subTextColor)))
                        : GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 1,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final image = filtered[index];
                              return MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () => Navigator.pop(context, [image]),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppTheme.inputBackground,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: AppTheme.dividerColor),
                                    ),
                                    child: Column(
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                                            child: Image.file(File(image['path']!), fit: BoxFit.cover, width: double.infinity),
                                          ),
                                        ),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                                          decoration: BoxDecoration(
                                            color: AppTheme.surfaceBackground,
                                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
                                          ),
                                          child: Text(
                                            image['name']!,
                                            style: TextStyle(fontSize: 10, color: AppTheme.textColor),
                                            textAlign: TextAlign.center,
                                            overflow: TextOverflow.ellipsis,
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
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: Text('取消', style: TextStyle(color: AppTheme.subTextColor)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 显示素材库选择对话框
  Future<List<String>?> _showAssetLibraryDialog(
    Map<int, List<Map<String, String>>> assetsByCategory,
  ) async {
    const categoryNames = ['角色素材', '场景素材', '物品素材'];
    const categoryIcons = [Icons.person_outline, Icons.landscape_outlined, Icons.inventory_2_outlined];

    return showDialog<List<String>>(
      context: context,
      builder: (ctx) {
        int selectedCategory = 0;
        final selectedPaths = <String>[];
        String searchQuery = '';
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final currentAssets = assetsByCategory[selectedCategory] ?? [];
            final filtered = searchQuery.isEmpty
                ? currentAssets
                : currentAssets.where((item) {
                    final name = (item['name'] ?? '').toLowerCase();
                    return name.contains(searchQuery.toLowerCase());
                  }).toList();
            return AlertDialog(
              backgroundColor: AppTheme.surfaceBackground,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Row(
                children: [
                  Icon(Icons.photo_library, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Text('选择素材', style: TextStyle(color: AppTheme.textColor, fontSize: 16)),
                  const Spacer(),
                  if (selectedPaths.isNotEmpty)
                    Text('已选 ${selectedPaths.length}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                ],
              ),
              content: SizedBox(
                width: 500,
                height: 440,
                child: Column(
                  children: [
                    // 分类标签栏
                    Row(
                      children: List.generate(3, (i) {
                        final isActive = selectedCategory == i;
                        final count = assetsByCategory[i]?.length ?? 0;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setDialogState(() {
                              selectedCategory = i;
                              searchQuery = '';
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: isActive ? Colors.white : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(categoryIcons[i], size: 16,
                                    color: isActive ? Colors.white : AppTheme.subTextColor),
                                  const SizedBox(width: 4),
                                  Text('${categoryNames[i]}($count)',
                                    style: TextStyle(
                                      color: isActive ? Colors.white : AppTheme.subTextColor,
                                      fontSize: 12,
                                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                                    )),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    // 搜索栏
                    TextField(
                      style: TextStyle(color: AppTheme.textColor, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '搜索素材名称...',
                        hintStyle: TextStyle(color: AppTheme.subTextColor, fontSize: 12),
                        prefixIcon: Icon(Icons.search, color: AppTheme.subTextColor, size: 18),
                        filled: true,
                        fillColor: AppTheme.inputBackground,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        isDense: true,
                      ),
                      onChanged: (v) => setDialogState(() => searchQuery = v),
                    ),
                    const SizedBox(height: 8),
                    // 素材网格
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(child: Text(
                              searchQuery.isEmpty ? '该分类暂无素材' : '无匹配结果',
                              style: TextStyle(color: AppTheme.subTextColor)))
                          : GridView.builder(
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: 0.85,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (ctx, index) {
                                final asset = filtered[index];
                                final isSelected = selectedPaths.contains(asset['path']);
                                return GestureDetector(
                                  onTap: () {
                                    setDialogState(() {
                                      if (isSelected) {
                                        selectedPaths.remove(asset['path']);
                                      } else {
                                        selectedPaths.add(asset['path']!);
                                      }
                                    });
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected ? Colors.white : AppTheme.dividerColor,
                                        width: isSelected ? 2 : 1,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                                            child: Image.file(
                                              File(asset['path']!),
                                              fit: BoxFit.cover,
                                              width: double.infinity,
                                              errorBuilder: (_, __, ___) => Container(
                                                color: AppTheme.inputBackground,
                                                child: Icon(Icons.broken_image, color: AppTheme.subTextColor),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(4),
                                          child: Text(
                                            asset['name']!,
                                            style: TextStyle(color: AppTheme.textColor, fontSize: 10),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: Text('取消', style: TextStyle(color: AppTheme.subTextColor)),
                ),
                ElevatedButton(
                  onPressed: selectedPaths.isEmpty ? null : () => Navigator.pop(ctx, selectedPaths),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
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
                    onTapUp: (details) {
                      Navigator.pop(dialogContext);
                      _showImageSourceDialog(taskId, tapPosition: details.globalPosition);
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
                          Icon(
                            Icons.add,
                            color: AppTheme.accentColor,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '添加',
                            style: TextStyle(
                              color: AppTheme.accentColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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
                          Icon(
                            Icons.add_photo_alternate,
                            size: 64,
                            color: AppTheme.subTextColor.withOpacity(0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '还没有参考图片',
                            style: TextStyle(color: AppTheme.subTextColor),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(dialogContext);
                              _showImageSourceDialog(taskId);
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
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
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
                                    final newImages = List<String>.from(
                                      currentTask.referenceImages,
                                    );
                                    newImages.removeAt(index);

                                    // ✅ 更新任务数据
                                    _updateTask(
                                      currentTask.copyWith(
                                        referenceImages: newImages,
                                      ),
                                    );

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
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 14,
                                    ),
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
                child: Text(
                  '关闭',
                  style: TextStyle(color: AppTheme.accentColor),
                ),
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
          final allVideos = currentTask.generatedVideos
              .where((v) => !v.startsWith('failed_'))
              .toList();

          final realVideos = allVideos
              .where((v) => !v.startsWith('loading_'))
              .toList();
          final loadingVideos = allVideos
              .where((v) => v.startsWith('loading_'))
              .toList();

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
                itemCount: allVideos.length, // ✅ 显示所有视频（包括生成中的）
                itemBuilder: (context, index) {
                  final videoPath = allVideos[index];

                  // ✅ 如果是加载中的视频，显示进度
                  if (videoPath.startsWith('loading_')) {
                    final progress = _batchVideoProgress[videoPath] ?? 0;

                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: AppTheme.inputBackground,
                        border: Border.all(
                          color: AppTheme.accentColor.withOpacity(0.3),
                        ),
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
                                    backgroundColor: Colors.grey.withOpacity(
                                      0.2,
                                    ),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      progress == 0
                                          ? Colors.blue
                                          : AppTheme.accentColor,
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
                              style: TextStyle(
                                color: AppTheme.subTextColor,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // ✅ 真实视频
                  final thumbnailPath = videoPath.replaceAll('.mp4', '.jpg');
                  final thumbnailFile = File(thumbnailPath);

                  // ✅ 检查缩略图是否存在
                  return FutureBuilder<bool>(
                    key: ValueKey('${thumbnailPath}_exists'),
                    future: thumbnailFile.exists(),
                    builder: (context, thumbnailSnapshot) {
                      final coverUrl = thumbnailSnapshot.data == true
                          ? thumbnailPath
                          : null;

                      // ✅ 构建缩略图 Widget
                      final thumbnailWidget = ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: FutureBuilder<bool>(
                          key: ValueKey(thumbnailPath),
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
                                child: Icon(
                                  Icons.videocam,
                                  color: Colors.white54,
                                  size: 32,
                                ),
                              ),
                            );
                          },
                        ),
                      );

                      // ✅ 使用 VideoGridItem 支持原位播放
                      final videoGridItem = VideoGridItem(
                        videoUrl: videoPath,
                        thumbnailWidget: thumbnailWidget,
                      );

                      // ✅ 使用 DraggableMediaItem 包装支持拖动
                      return DraggableMediaItem(
                        filePath: videoPath,
                        dragPreviewText: path.basename(videoPath),
                        coverUrl: coverUrl,
                        child: Stack(
                          children: [
                            // ✅ 右键菜单
                            GestureDetector(
                              onSecondaryTapDown: (details) =>
                                  _showVideoContextMenu(
                                    context,
                                    details,
                                    videoPath,
                                    currentTask,
                                    setDialogState,
                                  ),
                              child: videoGridItem,
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
                      );
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(
                  '关闭',
                  style: TextStyle(color: AppTheme.accentColor),
                ),
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
              Icon(
                Icons.play_circle_outline,
                size: 18,
                color: AppTheme.textColor,
              ),
              const SizedBox(width: 12),
              Text('使用播放器播放', style: TextStyle(color: AppTheme.textColor)),
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
              Icon(
                Icons.play_circle_outline,
                size: 18,
                color: AppTheme.textColor,
              ),
              const SizedBox(width: 12),
              Text('使用播放器播放', style: TextStyle(color: AppTheme.textColor)),
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
        if (newVideos
            .where((v) => !v.startsWith('loading_') && !v.startsWith('failed_'))
            .isEmpty) {
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
              child: InteractiveViewer(child: Image.file(File(imagePath))),
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
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 24,
                    ),
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
          await Process.run('cmd', [
            '/c',
            'start',
            '',
            videoPath,
          ], runInShell: true);
          _logger.success('已用默认播放器打开视频', module: '批量空间');
        } else {
          _showMessage('视频文件不存在', isError: true);
        }
      } else {
        await Process.run('cmd', [
          '/c',
          'start',
          '',
          videoPath,
        ], runInShell: true);
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
          Icon(
            Icons.table_chart,
            size: 100,
            color: AppTheme.subTextColor.withOpacity(0.2),
          ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4C83FF), Color(0xFF2AFADF)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4C83FF).withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.upload_file, color: Colors.white, size: 20),
                        SizedBox(width: 10),
                        Text(
                          '导入CSV',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2AF598), Color(0xFF009EFD)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2AF598).withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.add_circle_outline,
                          color: Colors.white,
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Text(
                          '新建行',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
              ? (widget.isClose
                    ? Colors.red
                    : AppTheme.textColor.withOpacity(0.1))
              : Colors.transparent,
          child: Icon(
            widget.icon,
            size: 16,
            color: _isHovered && widget.isClose
                ? Colors.white
                : AppTheme.subTextColor,
          ),
        ),
      ),
    );
  }
}
