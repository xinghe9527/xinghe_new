import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xinghe_new/main.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinghe_new/services/api/providers/veo_video_service.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';
import 'package:xinghe_new/services/api/secure_storage_manager.dart';
import 'package:xinghe_new/services/ffmpeg_service.dart';
import 'package:xinghe_new/core/logger/log_manager.dart';
import 'package:xinghe_new/features/home/domain/video_task.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:convert';

/// GeekNow 视频模型列表（与设置界面保持一致）
class GeekNowVideoModels {
  static const List<String> models = [
    // VEO 系列（8个）
    'veo_3_1', 'veo_3_1-4K', 'veo_3_1-fast', 'veo_3_1-fast-4K',
    'veo_3_1-components', 'veo_3_1-components-4K',
    'veo_3_1-fast-components', 'veo_3_1-fast-components-4K',
    // Sora 系列（2个）
    'sora-2', 'sora-turbo',
    // Kling（1个）
    'kling-video-o1',
    // Doubao 系列（3个）
    'doubao-seedance-1-5-pro_480p',
    'doubao-seedance-1-5-pro_720p',
    'doubao-seedance-1-5-pro_1080p',
    // Grok（1个）
    'grok-video-3',
  ];
}

class VideoSpace extends StatefulWidget {
  const VideoSpace({super.key});

  @override
  State<VideoSpace> createState() => _VideoSpaceState();
}

// 全局视频进度管理（避免 Widget 重建时丢失）
final Map<String, int> _globalVideoProgress = {};

class _VideoSpaceState extends State<VideoSpace> {
  final List<VideoTask> _tasks = [VideoTask.create()];
  final LogManager _logger = LogManager();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTasks());
  }

  Future<void> _loadTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tasksJson = prefs.getString('video_tasks');
      if (tasksJson != null && tasksJson.isNotEmpty && mounted) {
        final tasksList = jsonDecode(tasksJson) as List;
        setState(() {
          _tasks.clear();
          _tasks.addAll(tasksList.map((json) => VideoTask.fromJson(json)).toList());
        });
        _logger.success('成功加载 ${_tasks.length} 个视频任务', module: '视频空间');
      }
    } catch (e) {
      debugPrint('加载任务失败: $e');
      _logger.error('加载视频任务失败: $e', module: '视频空间');
    }
  }

  Future<void> _saveTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('video_tasks', jsonEncode(_tasks.map((t) => t.toJson()).toList()));
    } catch (e) {
      debugPrint('保存任务失败: $e');
    }
  }

  void _addNewTask() {
    if (mounted) {
      // 如果有现有任务，从最新任务复制设置
      final newTask = _tasks.isEmpty 
          ? VideoTask.create()
          : VideoTask.create().copyWith(
              model: _tasks.first.model,
              ratio: _tasks.first.ratio,
              quality: _tasks.first.quality,
              batchCount: _tasks.first.batchCount,
              seconds: _tasks.first.seconds,  // ✅ 复制时间设置
            );
      setState(() => _tasks.insert(0, newTask));
      _saveTasks();
      _logger.success('创建新的视频任务', module: '视频空间', extra: {
        'model': newTask.model,
        'ratio': newTask.ratio,
        'quality': newTask.quality,
        'seconds': newTask.seconds,
      });
    }
  }

  void _deleteTask(String taskId) {
    if (mounted) {
      setState(() => _tasks.removeWhere((t) => t.id == taskId));
      _saveTasks();
      _logger.info('删除视频任务', module: '视频空间');
    }
  }

  void _updateTask(VideoTask task) {
    // 先更新数据（无论 mounted 状态）
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      _tasks[index] = task;
      _saveTasks();  // 立即保存到本地存储
    }
    
    // 如果 Widget 还在，触发 UI 更新
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: themeNotifier,
      builder: (context, _, __) {
        return Container(
          color: AppTheme.scaffoldBackground,
          child: Column(
            children: [
              _buildToolbar(),
              Expanded(
                child: _tasks.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.all(24),
                        itemCount: _tasks.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 20),
                        itemBuilder: (context, index) => TaskCard(
                          key: ValueKey(_tasks[index].id),
                          task: _tasks[index],
                          onUpdate: _updateTask,
                          onDelete: () => _deleteTask(_tasks[index].id),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBackground,
        border: Border(bottom: BorderSide(color: AppTheme.dividerColor)),
      ),
      child: Row(
        children: [
          Text('视频空间', style: TextStyle(color: AppTheme.textColor, fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          _toolButton(Icons.delete_sweep_rounded, '清空全部', () {
            if (_tasks.isEmpty) return;
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: AppTheme.surfaceBackground,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: Text('清空全部任务', style: TextStyle(color: AppTheme.textColor)),
                content: Text('确定要删除所有任务吗？此操作不可恢复。', style: TextStyle(color: AppTheme.subTextColor)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: Text('取消', style: TextStyle(color: AppTheme.subTextColor))),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      final count = _tasks.length;
                      setState(() => _tasks.clear());
                      _saveTasks();
                      _logger.warning('清空所有视频任务', module: '视频空间', extra: {'删除数量': count});
                    },
                    child: const Text('确定', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(width: 12),
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
          decoration: BoxDecoration(color: AppTheme.textColor.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
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
              Text('新建任务', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.video_library_outlined, size: 100, color: AppTheme.subTextColor.withOpacity(0.2)),
          const SizedBox(height: 24),
          Text('开始你的视频创作之旅', style: TextStyle(color: AppTheme.textColor, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('创建一个新任务，开始AI视频生成', style: TextStyle(color: AppTheme.subTextColor, fontSize: 14)),
          const SizedBox(height: 32),
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
                    Text('创建任务', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TaskCard extends StatefulWidget {
  final VideoTask task;
  final Function(VideoTask) onUpdate;
  final VoidCallback onDelete;

  const TaskCard({super.key, required this.task, required this.onUpdate, required this.onDelete});

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  late final TextEditingController _controller;
  List<String> _models = ['Runway Gen-3', 'Pika 1.5', 'Stable Video', 'AnimateDiff'];
  final List<String> _ratios = ['16:9', '9:16', '1:1', '4:3', '3:4'];
  final List<String> _qualities = ['720P', '1080P', '2K', '4K'];
  final List<String> _secondsOptions = ['5秒', '10秒', '15秒'];  // 时长选项
  final LogManager _logger = LogManager();
  final SecureStorageManager _storage = SecureStorageManager();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.task.prompt);
    _loadVideoProvider();  // 加载服务商和模型列表
  }

  /// 从设置加载视频服务商，并更新可用模型列表
  Future<void> _loadVideoProvider() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('video_provider') ?? 'openai';
      
      if (mounted) {
        setState(() {
          _models = _getModelsForProvider(provider);
          
          // 如果当前任务的模型不在新列表中，设置为列表第一个
          if (!_models.contains(widget.task.model)) {
            widget.task.model = _models.first;
          }
        });
      }
    } catch (e) {
      _logger.error('加载视频服务商失败: $e', module: '视频空间');
    }
  }

  /// 根据服务商获取可用模型列表
  List<String> _getModelsForProvider(String provider) {
    switch (provider.toLowerCase()) {
      case 'geeknow':
        return GeekNowVideoModels.models;
      case 'openai':
        return ['sora-2', 'sora-turbo'];
      case 'runway':
        return ['runway-gen3', 'runway-gen2'];
      case 'pika':
        return ['pika-1.5', 'pika-1.0'];
      default:
        return ['Runway Gen-3', 'Pika 1.5', 'Stable Video', 'AnimateDiff'];
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _update(VideoTask task) => widget.onUpdate(task);

  /// 显示任务菜单
  void _showTaskMenu(BuildContext context) {
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(1000, 80, 20, 0),  // 右上角位置
      color: AppTheme.surfaceBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete_outline, color: Colors.red, size: 18),
              const SizedBox(width: 8),
              Text('删除', style: TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'delete') {
        widget.onDelete();
      }
    });
  }

  /// 真实的视频生成
  Future<void> _generateVideos() async {
    if (widget.task.prompt.trim().isEmpty) {
      _logger.warning('提示词为空', module: '视频空间');
      return;
    }

    final batchCount = widget.task.batchCount;
    
    // 立即添加占位符并初始化进度
    final placeholders = List.generate(batchCount, (i) => 'loading_${DateTime.now().millisecondsSinceEpoch}_$i');
    
    // 初始化所有占位符的进度为 0（使用全局 Map）
    for (var placeholder in placeholders) {
      _globalVideoProgress[placeholder] = 0;
    }
    
    if (mounted) {
      setState(() {});  // 触发 UI 更新
    }
    
    _update(widget.task.copyWith(
      generatedVideos: [...widget.task.generatedVideos, ...placeholders],
    ));
    
    // 短暂延迟确保 UI 更新
    await Future.delayed(const Duration(milliseconds: 100));

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
      
      // 准备参数
      final size = _convertRatioToSize(widget.task.ratio, widget.task.quality, widget.task.model);
      final seconds = _parseSeconds(widget.task.seconds);
      
      _logger.info('开始并发生成 $batchCount 个视频', module: '视频空间', extra: {
        'model': widget.task.model,
        'size': size,
        'seconds': seconds,
      });
      
      // 步骤1：并发提交所有任务
      final submitFutures = List.generate(batchCount, (i) async {
        _logger.info('提交第 ${i + 1}/$batchCount 个视频任务', module: '视频空间');
        
        final result = await service.generateVideos(
          prompt: widget.task.prompt,
          model: widget.task.model,
          ratio: size,
          parameters: {
            'seconds': seconds,
            'referenceImagePaths': widget.task.referenceImages,
          },
        );
        
        if (result.isSuccess && result.data != null && result.data!.isNotEmpty) {
          final taskId = result.data!.first.videoId;
          
          if (taskId == null || taskId.isEmpty) {
            throw Exception('任务 ${i + 1} 返回的 taskId 为空');
          }
          
          _logger.success('任务 ${i + 1} 提交成功: $taskId', module: '视频空间');
          return {'index': i, 'taskId': taskId, 'placeholder': placeholders[i]};
        } else {
          throw Exception('任务 ${i + 1} 提交失败: ${result.errorMessage}');
        }
      });
      
      // 等待所有任务提交完成
      final submittedTasks = await Future.wait(submitFutures);
      _logger.success('所有任务已提交，开始并发轮询', module: '视频空间');
      
      // 步骤2：并发轮询所有任务，每个任务完成时立即保存
      final pollFutures = submittedTasks.map((task) async {
        final index = task['index'] as int;
        final taskId = task['taskId'] as String?;
        final placeholder = task['placeholder'] as String;
        
        // 检查 taskId 是否有效
        if (taskId == null || taskId.isEmpty) {
          _logger.error('任务 ${index + 1} 的 taskId 无效', module: '视频空间');
          throw Exception('任务 ${index + 1} 的 taskId 为空');
        }
        
        try {
          _logger.info('开始轮询任务 ${index + 1}: $taskId', module: '视频空间');
          
          final statusResult = await helper.pollTaskUntilComplete(
            taskId: taskId,
            maxWaitMinutes: 15,
            onProgress: (progress, status) {
              // 实时更新进度到全局 Map
              _globalVideoProgress[placeholder] = progress;
              
              // 触发 UI 更新（检查占位符是否还存在）
              if (mounted && widget.task.generatedVideos.contains(placeholder)) {
                setState(() {});
              }
              _logger.info('任务 ${index + 1} 进度: $progress%', module: '视频空间');
            },
          );
          
          if (statusResult.isSuccess && statusResult.data!.hasVideo) {
            final videoUrl = statusResult.data!.videoUrl!;
            _logger.success('任务 ${index + 1} 完成', module: '视频空间', extra: {'url': videoUrl});
            
            // 立即下载并保存这个视频
            final savedPath = await _downloadSingleVideo(videoUrl, index);
            
            // 立即替换对应的占位符（无论 mounted 状态）
            final currentVideos = List<String>.from(widget.task.generatedVideos);
            final placeholderIndex = currentVideos.indexOf(placeholder);
            
            _logger.info('准备替换占位符 ${index + 1}', module: '视频空间', extra: {
              'placeholder': placeholder,
              'placeholderIndex': placeholderIndex,
              'totalVideos': currentVideos.length,
              'mounted': mounted,
            });
            
            if (placeholderIndex != -1) {
              currentVideos[placeholderIndex] = savedPath;
              
              _logger.info('占位符已替换为视频路径', module: '视频空间', extra: {
                'index': placeholderIndex,
                'newPath': savedPath,
                'isLocal': !savedPath.startsWith('http'),
              });
              
              // 清理全局进度
              _globalVideoProgress.remove(placeholder);
              
              // 更新任务数据
              _update(widget.task.copyWith(generatedVideos: currentVideos));
              
              // 如果 Widget 还在，触发 UI 更新
              if (mounted) {
                setState(() {});
              }
              
              _logger.success('视频 ${index + 1} UI 已更新', module: '视频空间', extra: {
                'path': savedPath,
                'isLocal': !savedPath.startsWith('http'),
              });
            } else {
              _logger.warning('找不到占位符，无法替换', module: '视频空间', extra: {
                'placeholder': placeholder,
                'currentVideos': currentVideos,
              });
            }
            
            return true;
          } else {
            throw Exception('任务 ${index + 1} 失败: ${statusResult.errorMessage}');
          }
        } catch (e) {
          _logger.error('任务 ${index + 1} 处理失败: $e', module: '视频空间');
          
          // 标记为失败（无论 mounted 状态如何都要更新）
          final currentVideos = List<String>.from(widget.task.generatedVideos);
          final placeholderIndex = currentVideos.indexOf(placeholder);
          
          if (placeholderIndex != -1) {
            currentVideos[placeholderIndex] = 'failed_${DateTime.now().millisecondsSinceEpoch}';
            
            // 清理全局进度
            _globalVideoProgress.remove(placeholder);
            
            // 更新任务数据（即使 Widget 已销毁）
            _update(widget.task.copyWith(generatedVideos: currentVideos));
            
            // 如果 Widget 还在，触发 UI 更新
            if (mounted) {
              setState(() {});
            }
          }
          
          return false;
        }
      }).toList();
      
      // 等待所有任务完成（不抛出错误）
      await Future.wait(pollFutures, eagerError: false);
      
      _logger.success('所有视频任务已处理完成', module: '视频空间');
      
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

  /// 将时长字符串转换为整数
  /// 例如："5秒" -> 5, "10秒" -> 10, "15秒" -> 15
  int _parseSeconds(String secondsStr) {
    // 移除"秒"字，提取数字
    final numStr = secondsStr.replaceAll('秒', '');
    return int.tryParse(numStr) ?? 10;  // 默认10秒
  }

  /// 将比例格式转换为尺寸格式
  /// 例如：'16:9' -> '1280x720', '9:16' -> '720x1280'
  /// 
  /// ⚠️ 重要：不同模型支持的尺寸不同
  /// - Sora (GeekNow): 只支持 720x1280 (竖屏), 1280x720 (横屏)
  /// - VEO/Kling/Doubao/Grok: 支持更多尺寸
  String _convertRatioToSize(String ratio, String quality, String model) {
    // Sora 模型只支持 2 种固定尺寸（根据 GeekNow API 文档）
    if (model.startsWith('sora')) {
      // Sora 只有横屏和竖屏，质量参数不影响尺寸
      switch (ratio) {
        case '16:9':
          return '1280x720';  // 横屏
        case '9:16':
          return '720x1280';  // 竖屏
        case '1:1':
        case '3:4':
          // Sora 不支持 1:1 和 3:4，默认使用竖屏
          return '720x1280';
        case '4:3':
          // Sora 不支持 4:3，默认使用横屏
          return '1280x720';
        default:
          return '720x1280';  // 默认竖屏
      }
    }
    
    // 其他模型：根据质量确定基础分辨率
    int baseWidth = 1280;
    int baseHeight = 720;
    
    if (quality == '1080P') {
      baseWidth = 1920;
      baseHeight = 1080;
    } else if (quality == '2K') {
      baseWidth = 2560;
      baseHeight = 1440;
    } else if (quality == '4K') {
      baseWidth = 3840;
      baseHeight = 2160;
    }
    
    // 根据比例调整
    switch (ratio) {
      case '16:9':
        return '${baseWidth}x$baseHeight';
      case '9:16':
        return '${baseHeight}x$baseWidth';
      case '1:1':
        return '${baseHeight}x$baseHeight';
      case '4:3':
        final h = (baseWidth * 3 / 4).round();
        return '${baseWidth}x$h';
      case '3:4':
        final w = (baseHeight * 3 / 4).round();
        return '${w}x$baseHeight';
      default:
        return '${baseHeight}x$baseWidth'; // 默认竖屏
    }
  }

  /// 构建视频项
  Widget _buildVideoItem(String videoPath) {
    // 占位符：加载中
    if (videoPath.startsWith('loading_')) {
      // 从全局 Map 获取当前进度
      final progress = _globalVideoProgress[videoPath] ?? 0;
      final progressValue = progress / 100.0;
      
      return Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppTheme.inputBackground,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 圆形进度条
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: progressValue,
                          strokeWidth: 3,
                          backgroundColor: Colors.grey.withOpacity(0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            progress == 0 ? Colors.blue : const Color(0xFF2AF598),
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
          ),
          // 删除按钮
          Positioned(
            top: 4,
            right: 4,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _deleteVideo(videoPath),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ),
          ),
        ],
      );
    }
    
    // 占位符：失败
    if (videoPath.startsWith('failed_')) {
      return Container(
        decoration: BoxDecoration(
          color: AppTheme.inputBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.withOpacity(0.3)),
        ),
        child: Stack(
          children: [
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: Colors.red, size: 32),
                  SizedBox(height: 8),
                  Text('生成失败', style: TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _deleteVideo(videoPath),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    // 真实视频
    final isLocalFile = !videoPath.startsWith('http');
    
    return Stack(
      children: [
        GestureDetector(
          onTap: () => _showVideoPreview(videoPath),
          onSecondaryTapDown: (details) => _showVideoContextMenu(context, details, videoPath, isLocalFile),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.inputBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 视频缩略图（优先显示首帧）
                    _buildVideoThumbnail(videoPath),
                    // 播放按钮
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // 删除按钮
        Positioned(
          top: 4,
          right: 4,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _deleteVideo(videoPath),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建视频缩略图
  Widget _buildVideoThumbnail(String videoPath) {
    final isLocalFile = !videoPath.startsWith('http');
    
    if (isLocalFile) {
      // 本地视频：检查是否有对应的首帧图片
      final thumbnailPath = videoPath.replaceAll('.mp4', '.jpg');
      final thumbnailFile = File(thumbnailPath);
      
      return FutureBuilder<bool>(
        future: thumbnailFile.exists(),
        builder: (context, snapshot) {
          if (snapshot.data == true) {
            // 显示首帧图片
            return Image.file(
              thumbnailFile,
              fit: BoxFit.cover,
            );
          } else {
            // 没有首帧，显示默认图标
            return Container(
              color: Colors.black87,
              child: const Icon(Icons.videocam, color: Colors.white54, size: 48),
            );
          }
        },
      );
    } else {
      // 在线 URL：显示默认图标
      return Container(
        color: Colors.black87,
        child: const Icon(Icons.videocam, color: Colors.white54, size: 48),
      );
    }
  }

  /// 删除视频
  void _deleteVideo(String videoPath) {
    final currentVideos = List<String>.from(widget.task.generatedVideos);
    currentVideos.remove(videoPath);
    
    // 清理全局进度 Map
    _globalVideoProgress.remove(videoPath);
    
    if (mounted) {
      setState(() {});
    }
    
    _update(widget.task.copyWith(generatedVideos: currentVideos));
    _logger.info('删除视频', module: '视频空间', extra: {'path': videoPath});
  }

  /// 显示视频预览（放大查看）
  /// 用本地播放器打开视频
  Future<void> _showVideoPreview(String videoPath) async {
    try {
      // 检查是否是本地文件
      final isLocalFile = !videoPath.startsWith('http');
      
      _logger.info('打开视频', module: '视频空间', extra: {
        'path': videoPath,
        'isLocal': isLocalFile,
      });
      
      if (isLocalFile) {
        // 本地文件：检查是否存在
        final file = File(videoPath);
        if (await file.exists()) {
          // Windows: 使用 cmd /c start 打开（兼容性最好）
          final result = await Process.run(
            'cmd',
            ['/c', 'start', '', videoPath],
            runInShell: true,
          );
          
          if (result.exitCode == 0) {
            _logger.success('已用默认播放器打开视频', module: '视频空间', extra: {'path': videoPath});
          } else {
            _logger.error('打开视频失败', module: '视频空间', extra: {
              'exitCode': result.exitCode,
              'stderr': result.stderr,
            });
          }
        } else {
          _logger.error('视频文件不存在', module: '视频空间', extra: {'path': videoPath});
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('视频文件不存在')),
            );
          }
        }
      } else {
        // 网络 URL：用默认浏览器打开
        await Process.run(
          'cmd',
          ['/c', 'start', '', videoPath],
          runInShell: true,
        );
        _logger.success('已在浏览器中打开', module: '视频空间', extra: {'url': videoPath});
      }
    } catch (e) {
      _logger.error('打开视频失败: $e', module: '视频空间');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开视频失败: $e')),
        );
      }
    }
  }

  /// 显示右键菜单
  void _showVideoContextMenu(BuildContext context, TapDownDetails details, String videoPath, bool isLocalFile) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final menuPosition = RelativeRect.fromRect(
      Rect.fromPoints(details.globalPosition, details.globalPosition),
      Offset.zero & overlay.size,
    );
    
    final menuItems = <PopupMenuEntry<String>>[
      if (isLocalFile) ...[
        const PopupMenuItem(
          value: 'open_folder',
          child: Row(
            children: [
              Icon(Icons.folder_open, size: 18),
              SizedBox(width: 8),
              Text('查看文件夹'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'open_video',
          child: Row(
            children: [
              Icon(Icons.play_circle_outline, size: 18),
              SizedBox(width: 8),
              Text('用播放器打开'),
            ],
          ),
        ),
      ] else ...[
        const PopupMenuItem(
          value: 'open_browser',
          child: Row(
            children: [
              Icon(Icons.open_in_browser, size: 18),
              SizedBox(width: 8),
              Text('在浏览器中打开'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'copy_url',
          child: Row(
            children: [
              Icon(Icons.copy, size: 18),
              SizedBox(width: 8),
              Text('复制视频链接'),
            ],
          ),
        ),
      ],
    ];
    
    showMenu(
      context: context,
      position: menuPosition,
      items: menuItems,
    ).then((value) async {
      if (value == 'open_folder') {
        _openFileLocation(videoPath);
      } else if (value == 'open_video') {
        _showVideoPreview(videoPath);
      } else if (value == 'open_browser') {
        // 在浏览器中打开在线 URL
        await Process.start(
          'cmd',
          ['/c', 'start', videoPath],
          mode: ProcessStartMode.detached,
        );
        _logger.info('在浏览器中打开视频', module: '视频空间', extra: {'url': videoPath});
      } else if (value == 'copy_url') {
        await Clipboard.setData(ClipboardData(text: videoPath));
        _logger.success('视频链接已复制', module: '视频空间', extra: {'url': videoPath});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('视频链接已复制')),
          );
        }
      }
    });
  }

  /// 打开文件所在文件夹
  Future<void> _openFileLocation(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final directory = file.parent.path;
        await Process.run('explorer', [directory]);
        _logger.info('打开文件夹', module: '视频空间', extra: {'path': directory});
      }
    } catch (e) {
      _logger.error('打开文件夹失败: $e', module: '视频空间');
    }
  }

  /// 下载并保存单个视频
  Future<String> _downloadSingleVideo(String videoUrl, int index) async {
    try {
      final savePath = videoSavePathNotifier.value;
      
      if (savePath == '未设置' || savePath.isEmpty) {
        _logger.warning('未设置视频保存路径，使用在线 URL', module: '视频空间');
        return videoUrl;
      }
      
      final saveDir = Directory(savePath);
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }
      
      _logger.info('下载视频 ${index + 1}', module: '视频空间', extra: {'url': videoUrl});
      
      final response = await http.get(Uri.parse(videoUrl)).timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          throw Exception('下载超时');
        },
      );
      
      if (response.statusCode == 200) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'video_${timestamp}_$index.mp4';
        final filePath = path.join(savePath, fileName);
        
        await File(filePath).writeAsBytes(response.bodyBytes);
        
        _logger.success('视频已保存', module: '视频空间', extra: {
          'index': index + 1,
          'path': filePath,
          'size': '${(response.bodyBytes.length / 1024 / 1024).toStringAsFixed(2)} MB',
        });
        
        // 提取视频首帧作为缩略图
        try {
          final thumbnailPath = filePath.replaceAll('.mp4', '.jpg');
          final ffmpeg = FFmpegService();
          final success = await ffmpeg.extractFrame(
            videoPath: filePath,
            outputPath: thumbnailPath,
          );
          
          if (success) {
            _logger.success('视频首帧已提取', module: '视频空间', extra: {
              'thumbnail': thumbnailPath,
            });
          }
        } catch (e) {
          _logger.warning('提取首帧失败: $e', module: '视频空间');
        }
        
        return filePath;
      } else {
        _logger.warning('下载失败（状态码: ${response.statusCode}），使用在线 URL', module: '视频空间');
        return videoUrl;
      }
    } catch (e) {
      _logger.error('下载视频 ${index + 1} 失败: $e', module: '视频空间');
      return videoUrl;
    }
  }


  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        children: [
          Expanded(flex: 55, child: _buildLeft()),
          Container(width: 1, color: AppTheme.dividerColor),
          Expanded(flex: 45, child: _buildRight()),
        ],
      ),
    );
  }

  Widget _buildLeft() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Listener(
              onPointerSignal: (event) {
                // 消费滚轮事件，阻止向外传播
              },
              child: Container(
                decoration: BoxDecoration(color: AppTheme.inputBackground, borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.all(14),
                child: SingleChildScrollView(
                  child: TextField(
                    controller: _controller,
                    maxLines: null,
                    style: TextStyle(color: AppTheme.textColor, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '输入视频描述...',
                      hintStyle: TextStyle(color: AppTheme.subTextColor, fontSize: 12),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                    onChanged: (v) => _update(widget.task.copyWith(prompt: v)),
                  ),
                ),
              ),
            ),
          ),
          if (widget.task.referenceImages.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildReferenceImages(),
          ],
          const SizedBox(height: 16),
          _bottomControls(),
        ],
      ),
    );
  }

  Widget _buildReferenceImages() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.task.referenceImages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final imagePath = widget.task.referenceImages[index];
          return Stack(
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _showImagePreview(context, imagePath),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.inputBackground,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.dividerColor),
                      image: DecorationImage(
                        image: FileImage(File(imagePath)),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 1,
                right: 1,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      final newImages = List<String>.from(widget.task.referenceImages);
                      newImages.removeAt(index);
                      _update(widget.task.copyWith(referenceImages: newImages));
                    },
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 10),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showImagePreview(BuildContext context, String imagePath) {
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

  Widget _bottomControls() {
    return Row(
      children: [
        _addImageButton(),
        const SizedBox(width: 12),
        Expanded(child: _params()),
        const SizedBox(width: 12),
        _genButton(),
      ],
    );
  }

  Widget _params() {
    return Wrap(
      spacing: 6,  // 减小间距
      runSpacing: 6,
      children: [
        _compactModelSelector(),  // 紧凑型模型选择器
        _dropdown(null, widget.task.ratio, _ratios, (v) => _update(widget.task.copyWith(ratio: v))),
        _dropdown(null, widget.task.quality, _qualities, (v) => _update(widget.task.copyWith(quality: v))),
        _dropdown(null, widget.task.seconds, _secondsOptions, (v) => _update(widget.task.copyWith(seconds: v))),  // 时长选择器
        _batch(),
      ],
    );
  }

  /// 紧凑型模型选择器（只显示"模型"文字，不显示当前选中值）
  Widget _compactModelSelector() {
    return Container(
      height: 34,  // 减小高度
      padding: const EdgeInsets.symmetric(horizontal: 8),  // 减小内边距
      decoration: BoxDecoration(
        color: AppTheme.inputBackground,
        borderRadius: BorderRadius.circular(6),  // 减小圆角
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('模型', style: TextStyle(color: AppTheme.subTextColor, fontSize: 10)),  // 减小字体
          PopupMenuButton<String>(
            icon: Icon(Icons.arrow_drop_down, color: AppTheme.subTextColor, size: 14),  // 减小图标
            offset: const Offset(0, 34),
            color: AppTheme.surfaceBackground,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            itemBuilder: (context) {
              return _models.map((model) {
                final isSelected = model == widget.task.model;
                return PopupMenuItem<String>(
                  value: model,
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.check : Icons.check_box_outline_blank,
                        size: 16,
                        color: isSelected ? AppTheme.accentColor : Colors.transparent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          model,
                          style: TextStyle(
                            color: isSelected ? AppTheme.accentColor : AppTheme.textColor,
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList();
            },
            onSelected: (v) => _update(widget.task.copyWith(model: v)),
          ),
        ],
      ),
    );
  }

  Widget _dropdown(String? label, String value, List<String> items, Function(String) onChanged) {
    return Container(
      height: 34,  // 减小高度
      padding: const EdgeInsets.symmetric(horizontal: 8),  // 减小内边距
      decoration: BoxDecoration(
        color: AppTheme.inputBackground, 
        borderRadius: BorderRadius.circular(6),  // 减小圆角
        border: Border.all(color: AppTheme.dividerColor)
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null) ...[
            Text(label, style: TextStyle(color: AppTheme.subTextColor, fontSize: 10)),  // 减小字体
            const SizedBox(width: 4),  // 减小间距
          ],
          DropdownButton<String>(
            value: value,
            items: items.map((i) => DropdownMenuItem(value: i, child: Text(i, style: TextStyle(color: AppTheme.textColor, fontSize: 11)))).toList(),  // 减小字体
            onChanged: (v) => onChanged(v!),
            underline: const SizedBox(),
            dropdownColor: AppTheme.surfaceBackground,
            icon: Icon(Icons.arrow_drop_down, color: AppTheme.subTextColor, size: 14),  // 减小图标
            isDense: true,
          ),
        ],
      ),
    );
  }

  Widget _batch() {
    return Container(
      height: 34,  // 减小高度
      padding: const EdgeInsets.symmetric(horizontal: 8),  // 减小内边距
      decoration: BoxDecoration(
        color: AppTheme.inputBackground, 
        borderRadius: BorderRadius.circular(6),  // 减小圆角
        border: Border.all(color: AppTheme.dividerColor)
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('批量', style: TextStyle(color: AppTheme.subTextColor, fontSize: 10)),  // 减小字体
          const SizedBox(width: 4),  // 减小间距
          _batchBtn(Icons.remove, widget.task.batchCount > 1, () => _update(widget.task.copyWith(batchCount: widget.task.batchCount - 1))),
          SizedBox(width: 24, child: Center(child: Text('${widget.task.batchCount}', style: TextStyle(color: AppTheme.textColor, fontSize: 11, fontWeight: FontWeight.bold)))),  // 减小宽度和字体
          _batchBtn(Icons.add, widget.task.batchCount < 20, () => _update(widget.task.copyWith(batchCount: widget.task.batchCount + 1))),
        ],
      ),
    );
  }

  Widget _batchBtn(IconData icon, bool enabled, VoidCallback onTap) {
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Icon(icon, color: enabled ? AppTheme.textColor : AppTheme.subTextColor.withOpacity(0.3), size: 14),  // 减小图标
      ),
    );
  }

  Widget _addImageButton() {
    final canAddMore = widget.task.referenceImages.length < 9;
    return MouseRegion(
      cursor: canAddMore ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      child: GestureDetector(
        onTap: canAddMore ? () async {
          try {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.image,
              allowMultiple: true,
            );
            if (result != null && result.files.isNotEmpty) {
              final currentCount = widget.task.referenceImages.length;
              final availableSlots = 9 - currentCount;
              final newImages = result.files
                  .take(availableSlots.toInt())
                  .map((file) => file.path!)
                  .toList();
              _update(widget.task.copyWith(
                referenceImages: [...widget.task.referenceImages, ...newImages],
              ));
              _logger.success('添加 ${newImages.length} 张参考图片', module: '视频空间');
            }
          } catch (e) {
            _logger.error('添加图片失败: $e', module: '视频空间');
          }
        } : null,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: canAddMore ? AppTheme.inputBackground : AppTheme.inputBackground.withOpacity(0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.dividerColor),
          ),
          child: Icon(
            Icons.add_photo_alternate_outlined, 
            color: canAddMore ? AppTheme.subTextColor : AppTheme.subTextColor.withOpacity(0.3), 
            size: 22
          ),
        ),
      ),
    );
  }

  Widget _genButton() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _generateVideos,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF2AF598), Color(0xFF009EFD)]),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(color: const Color(0xFF2AF598).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: const Center(
            child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildRight() {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: widget.task.generatedVideos.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.video_library_outlined, size: 64, color: AppTheme.subTextColor.withOpacity(0.2)),
                  const SizedBox(height: 12),
                  Text('等待生成', style: TextStyle(color: AppTheme.subTextColor, fontSize: 14)),
                ]))
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 16/9),
                  itemCount: widget.task.generatedVideos.length,
                  itemBuilder: (context, index) {
                    return _buildVideoItem(widget.task.generatedVideos[index]);
                  },
                ),
        ),
        Positioned(
          top: -2,  // 上移到卡片边缘外
          right: 6,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _showTaskMenu(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceBackground.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.dividerColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(Icons.more_horiz, color: AppTheme.textColor, size: 16),  // ⋯ 横向三个点
              ),
            ),
          ),
        ),
      ],
    );
  }
}
