import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xinghe_new/main.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinghe_new/services/api/providers/veo_video_service.dart';
import 'package:xinghe_new/core/logger/error_translator.dart';
import 'package:xinghe_new/services/api/providers/geeknow_service.dart';
import 'package:xinghe_new/services/api/base/api_response.dart';
import 'package:xinghe_new/services/api/providers/yunwu_service.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';
import 'package:xinghe_new/services/api/api_factory.dart';  // ✅ 导入 API 工厂
import 'package:xinghe_new/services/api/secure_storage_manager.dart';
import 'package:xinghe_new/services/ffmpeg_service.dart';
import 'package:xinghe_new/core/logger/log_manager.dart';
import 'package:xinghe_new/features/home/domain/video_task.dart';
import 'package:xinghe_new/features/home/presentation/batch_video_space.dart';  // ✅ 导入批量空间
import 'package:xinghe_new/features/creation_workflow/presentation/widgets/draggable_media_item.dart';  // ✅ 导入拖动组件
import 'package:xinghe_new/features/creation_workflow/presentation/widgets/video_grid_item.dart';  // ✅ 导入原位播放组件
import 'package:xinghe_new/core/aigc_engine/automation_api_client.dart';  // ✅ 导入网页服务商客户端
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:convert';

/// GeekNow 视频模型列表（与设置界面保持一致）
class GeekNowVideoModels {
  static const List<String> models = [
    'sora-2',
    'sora-2[vip]',
    'veo_3_1',
    'veo_3_1-components-4K',
    'veo_3_1-fast-components',
    'veo_3_1-fast-components-4K',
    'grok-video-3',
    'grok-video-3-max',
  ];
}

class VideoSpace extends StatefulWidget {
  const VideoSpace({super.key});

  @override
  State<VideoSpace> createState() => _VideoSpaceState();
}

// 全局视频进度管理（避免 Widget 重建时丢失）
final Map<String, int> _globalVideoProgress = {};

class _VideoSpaceState extends State<VideoSpace> with WidgetsBindingObserver {
  final List<VideoTask> _tasks = [VideoTask.create()];
  final LogManager _logger = LogManager();
  String _lastKnownProvider = '';  // 记录上次加载的服务商

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTasks();
      _checkProviderChange();  // 检查服务商变化
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 当应用从后台恢复时，检查服务商是否变化
    if (state == AppLifecycleState.resumed) {
      _checkProviderChange();
    }
  }

  /// 检查视频服务商是否变化，如果变化则刷新所有任务卡片
  Future<void> _checkProviderChange() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentProvider = prefs.getString('video_provider') ?? 'openai';
      
      if (_lastKnownProvider.isNotEmpty && _lastKnownProvider != currentProvider) {
        _logger.info('检测到视频服务商变化', module: '视频空间', extra: {
          '旧服务商': _lastKnownProvider,
          '新服务商': currentProvider,
        });
        
        // 强制刷新 UI，让所有 TaskCard 重新加载
        if (mounted) {
          setState(() {});
        }
      }
      
      _lastKnownProvider = currentProvider;
    } catch (e) {
      _logger.error('检查服务商变化失败: $e', module: '视频空间');
    }
  }

  Future<void> _loadTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tasksJson = prefs.getString('video_tasks');
      if (tasksJson != null && tasksJson.isNotEmpty && mounted) {
        final tasksList = jsonDecode(tasksJson) as List;
        final tasks = tasksList.map((json) => VideoTask.fromJson(json)).toList();
        
        // ✅ 自动清理遗留的占位符
        var cleanedCount = 0;
        for (var task in tasks) {
          final originalCount = task.generatedVideos.length;
          task.generatedVideos.removeWhere((v) => 
            v.startsWith('loading_') || v.startsWith('failed_')
          );
          cleanedCount += originalCount - task.generatedVideos.length;
        }
        
        if (cleanedCount > 0) {
          _logger.success('清理了 $cleanedCount 个遗留占位符', module: '视频空间');
        }
        
        setState(() {
          _tasks.clear();
          _tasks.addAll(tasks);
        });
        
        // ✅ 保存清理后的任务
        if (cleanedCount > 0) {
          _saveTasks();
        }
        
        _logger.debug('成功加载 ${_tasks.length} 个视频任务', module: '视频空间');
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
      // 如果有现有任务，从最后一个任务复制设置
      final newTask = _tasks.isEmpty 
          ? VideoTask.create()
          : VideoTask.create().copyWith(
              model: _tasks.last.model,  // ✅ 从最后一个任务复制
              ratio: _tasks.last.ratio,
              quality: _tasks.last.quality,
              batchCount: _tasks.last.batchCount,
              seconds: _tasks.last.seconds,
            );
      setState(() => _tasks.add(newTask));  // ✅ 修改：添加到末尾
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
          
          // ✅ 清空全部按钮（位置提前）
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
          
          // ✅ 表格视图按钮（进入批量空间）
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const BatchVideoSpace()),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4C83FF), Color(0xFF2AFADF)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4C83FF).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.table_chart, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text('表格视图', style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    )),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          
          // 批量生成按钮
          _batchGenerateAllButton(),
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

  /// 批量生成按钮
  Widget _batchGenerateAllButton() {
    // ✅ 修复：更准确的状态检测
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
                colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],  // 橙红色渐变
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
              Text('新建任务', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  /// 批量生成所有任务
  Future<void> _generateAllTasks() async {
    // 获取所有有提示词的任务
    final tasksToGenerate = _tasks.where((t) => t.prompt.trim().isNotEmpty).toList();
    
    if (tasksToGenerate.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('没有可生成的任务\n请确保任务有提示词'),
            backgroundColor: Color(0xFFFF6B6B),
          ),
        );
      }
      return;
    }
    
    _logger.success('🚀 开始批量生成 ${tasksToGenerate.length} 个视频任务', module: '视频空间', extra: {
      '总任务数': _tasks.length,
      '待生成': tasksToGenerate.length,
    });
    
    // 并发生成所有任务
    await Future.wait(
      tasksToGenerate.map((task) => _generateSingleTask(task)),
      eagerError: false,
    );
    
    _logger.success('✅ 批量生成完成', module: '视频空间');
  }
  
  /// 生成单个任务（支持批量）
  Future<void> _generateSingleTask(VideoTask task) async {
    if (task.prompt.trim().isEmpty) return;
    
    final batchCount = task.batchCount;
    
    // 立即添加占位符
    final placeholders = List.generate(
      batchCount,
      (i) => 'loading_${DateTime.now().millisecondsSinceEpoch}_${task.id}_$i',
    );
    
    // 初始化进度
    for (var placeholder in placeholders) {
      _globalVideoProgress[placeholder] = 0;
    }
    
    // 更新任务，添加占位符
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
      
      // 从设置中读取用户保存的模型，优先使用设置模型
      final savedModel = await SecureStorageManager().getModel(provider: provider, modelType: 'video');
      final effectiveModel = savedModel ?? task.model;
      
      final config = ApiConfig(provider: provider, baseUrl: baseUrl, apiKey: apiKey);
      final apiFactory = ApiFactory();
      final service = apiFactory.createService(provider, config);
      
      final size = _convertRatioToSize(task.ratio, task.quality, effectiveModel);
      final seconds = _parseSeconds(task.seconds);
      
      // ComfyUI 同步生成
      if (provider.toLowerCase() == 'comfyui' || provider.toLowerCase() == 'openai') {
        final generateFutures = List.generate(batchCount, (i) async {
          final placeholder = placeholders[i];
          
          try {
            final result = await service.generateVideos(
              prompt: task.prompt,
              model: effectiveModel,
              ratio: size,
              referenceImages: task.referenceImages,
              parameters: {'seconds': seconds},
            );
            
            if (result.isSuccess && result.data != null && result.data!.isNotEmpty) {
              final videoUrl = result.data!.first.videoUrl;
              final savedPath = await _downloadSingleVideoForTask(videoUrl, i, task.id);
              
              final currentTask = _tasks.firstWhere((t) => t.id == task.id);
              final currentVideos = List<String>.from(currentTask.generatedVideos);
              final placeholderIndex = currentVideos.indexOf(placeholder);
              
              if (placeholderIndex != -1) {
                currentVideos[placeholderIndex] = savedPath;
                _globalVideoProgress.remove(placeholder);
                _updateTask(currentTask.copyWith(generatedVideos: currentVideos));
              }
              
              return true;
            }
          } catch (e) {
            _logger.error('视频生成失败: $e', module: '视频空间');
            
            final currentTask = _tasks.firstWhere((t) => t.id == task.id);
            final currentVideos = List<String>.from(currentTask.generatedVideos);
            final placeholderIndex = currentVideos.indexOf(placeholder);
            
            if (placeholderIndex != -1) {
              currentVideos[placeholderIndex] = 'failed_${DateTime.now().millisecondsSinceEpoch}';
              _globalVideoProgress.remove(placeholder);
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
            parameters: {'seconds': seconds},
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
            final statusResult = await yunwuHelper.pollTaskUntilComplete(
              taskId: taskId,
              maxWaitMinutes: 15,
              onProgress: (progress, status) {
                _globalVideoProgress[placeholder] = progress;
                if (mounted) setState(() {});
              },
            );
            
            print('📊 [视频空间] 轮询完成: isSuccess=${statusResult.isSuccess}, hasData=${statusResult.data != null}, videoUrl=${statusResult.data?.videoUrl}, error=${statusResult.errorMessage}');
            
            if (statusResult.isSuccess && statusResult.data != null && statusResult.data!.videoUrl != null) {
              final videoUrl = statusResult.data!.videoUrl!;
              final savedPath = await _downloadSingleVideoForTask(videoUrl, index, task.id);
              
              final currentTask = _tasks.firstWhere((t) => t.id == task.id);
              final currentVideos = List<String>.from(currentTask.generatedVideos);
              final placeholderIndex = currentVideos.indexOf(placeholder);
              
              if (placeholderIndex != -1) {
                currentVideos[placeholderIndex] = savedPath;
                _globalVideoProgress.remove(placeholder);
                _updateTask(currentTask.copyWith(generatedVideos: currentVideos));
              }
              
              return true;
            }
          } catch (e) {
            print('❌ [视频空间] yunwu轮询异常: $e');
            final currentTask = _tasks.firstWhere((t) => t.id == task.id);
            final currentVideos = List<String>.from(currentTask.generatedVideos);
            final placeholderIndex = currentVideos.indexOf(placeholder);
            
            if (placeholderIndex != -1) {
              currentVideos[placeholderIndex] = 'failed_${DateTime.now().millisecondsSinceEpoch}';
              _globalVideoProgress.remove(placeholder);
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
            parameters: {'seconds': seconds},
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
            final statusResult = await VeoVideoHelper.pollUntilComplete(
              getStatus: getStatusFn,
              taskId: taskId,
              maxWaitMinutes: 15,
              onProgress: (progress, status) {
                _globalVideoProgress[placeholder] = progress;
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
                _globalVideoProgress.remove(placeholder);
                _updateTask(currentTask.copyWith(generatedVideos: currentVideos));
              }
              
              return true;
            }
          } catch (e) {
            final currentTask = _tasks.firstWhere((t) => t.id == task.id);
            final currentVideos = List<String>.from(currentTask.generatedVideos);
            final placeholderIndex = currentVideos.indexOf(placeholder);
            
            if (placeholderIndex != -1) {
              currentVideos[placeholderIndex] = 'failed_${DateTime.now().millisecondsSinceEpoch}';
              _globalVideoProgress.remove(placeholder);
              _updateTask(currentTask.copyWith(generatedVideos: currentVideos));
            }
          }
          
          return false;
        }).toList();
        
        await Future.wait(pollFutures, eagerError: false);
      }
    } catch (e) {
      print('❌ [视频空间] 外层异常捕获(所有占位符标记失败): $e');
      _logger.error('任务生成失败: $e', module: '视频空间');
      
      // 清理占位符
      final currentTask = _tasks.firstWhere((t) => t.id == task.id, orElse: () => task);
      final currentVideos = List<String>.from(currentTask.generatedVideos);
      for (var placeholder in placeholders) {
        final index = currentVideos.indexOf(placeholder);
        if (index != -1) {
          currentVideos[index] = 'failed_${DateTime.now().millisecondsSinceEpoch}';
          _globalVideoProgress.remove(placeholder);
        }
      }
      _updateTask(currentTask.copyWith(generatedVideos: currentVideos));
    }
  }
  
  /// 下载单个视频（用于批量生成）
  Future<String> _downloadSingleVideoForTask(String videoUrl, int index, String taskId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savePath = prefs.getString('video_save_path');
      
      if (savePath == null || savePath.isEmpty) {
        return videoUrl;
      }
      
      final response = await http.get(Uri.parse(videoUrl)).timeout(
        const Duration(minutes: 5),
      );
      
      if (response.statusCode == 200) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'video_${timestamp}_${taskId}_$index.mp4';
        final filePath = path.join(savePath, fileName);
        
        await File(filePath).writeAsBytes(response.bodyBytes);
        
        // 提取首帧
        try {
          final thumbnailPath = filePath.replaceAll('.mp4', '.jpg');
          final ffmpeg = FFmpegService();
          await ffmpeg.extractFrame(videoPath: filePath, outputPath: thumbnailPath);
        } catch (e) {
          // 忽略首帧提取失败
        }
        
        return filePath;
      }
    } catch (e) {
      _logger.error('下载视频失败: $e', module: '视频空间');
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
    // 简化版本，返回标准尺寸
    switch (ratio) {
      case '16:9':
        return '1280x720';
      case '9:16':
        return '720x1280';
      case '1:1':
        return '1024x1024';
      default:
        return '1280x720';
    }
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

class _TaskCardState extends State<TaskCard> with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;  // ✅ 添加焦点节点
  List<String> _models = ['Runway Gen-3', 'Pika 1.5', 'Stable Video', 'AnimateDiff'];
  final List<String> _ratios = ['16:9', '9:16', '1:1', '4:3', '3:4'];
  final List<String> _qualities = ['720P', '1080P', '2K', '4K'];
  final List<String> _secondsOptions = ['5秒', '10秒', '15秒'];  // 时长选项
  final LogManager _logger = LogManager();
  final SecureStorageManager _storage = SecureStorageManager();
  String _currentProvider = '';  // 记录当前使用的服务商
  String _currentWebTool = '';  // 记录当前网页工具类型
  final _addImageBtnKey = GlobalKey();  // 添加图片按钮的key，用于菜单定位

  @override
  bool get wantKeepAlive => true;  // 保持状态

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.task.prompt);
    _focusNode = FocusNode();  // ✅ 初始化焦点节点
    WidgetsBinding.instance.addObserver(this);  // 添加生命周期监听
    _loadVideoProvider();  // 加载服务商和模型列表
  }

  @override
  void didUpdateWidget(TaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Widget 更新时，重新检查服务商配置
    _checkAndReloadProvider();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);  // 移除监听
    _controller.dispose();
    _focusNode.dispose();  // ✅ 销毁焦点节点
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 当应用从后台恢复时，检查服务商是否变化
    if (state == AppLifecycleState.resumed) {
      _checkAndReloadProvider();
    }
  }

  /// 检查并重新加载服务商配置（如果需要）
  Future<void> _checkAndReloadProvider() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('video_provider') ?? 'openai';
      
      // 如果服务商变化了，重新加载模型列表
      if (provider != _currentProvider) {
        await _loadVideoProvider();
      }
    } catch (e) {
      _logger.error('检查服务商配置失败: $e', module: '视频空间');
    }
  }

  /// 从设置加载视频服务商，并更新可用模型列表
  Future<void> _loadVideoProvider() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('video_provider') ?? 'openai';
      
      _logger.debug('加载视频服务商配置: $provider', module: '视频空间');
      
      final models = _getModelsForProvider(provider);
      
      // 如果当前任务的模型不在新列表中，优先使用用户在设置中保存的模型
      String? resolvedModel;
      if (!models.contains(widget.task.model)) {
        final savedModel = await _storage.getModel(provider: provider, modelType: 'video');
        if (savedModel != null && models.contains(savedModel)) {
          resolvedModel = savedModel;
        } else {
          resolvedModel = models.first;
        }
        _logger.warning(
          '当前模型不在服务商模型列表中，已切换', 
          module: '视频空间',
          extra: {'旧模型': widget.task.model, '新模型': resolvedModel, '服务商': provider}
        );
      }

      final webTool = prefs.getString('video_web_tool') ?? '';

      if (mounted) {
        setState(() {
          _currentProvider = provider;
          _currentWebTool = webTool;
          _models = models;
          if (resolvedModel != null) {
            widget.onUpdate(widget.task.copyWith(model: resolvedModel));
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
      case 'yunwu':
        // Yunwu（云雾）视频模型列表
        return [
          // Sora 系列
          'sora-2-all',
          // VEO3.1 4K 系列（OpenAI视频格式）
          'veo_3_1-4K', 'veo_3_1-fast-4K',
          // Grok 视频系列（xAI）
          'grok-video-3', 'grok-video-3-10s', 'grok-video-3-15s',
        ];
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

  void _update(VideoTask task) => widget.onUpdate(task);

  /// 显示任务菜单（在点击按钮旁边弹出）
  void _showTaskMenu(BuildContext buttonContext) {
    // 获取按钮的 RenderBox 以计算实际位置
    final RenderBox button = buttonContext.findRenderObject() as RenderBox;
    final RenderBox overlay = Overlay.of(buttonContext).context.findRenderObject() as RenderBox;
    final Offset buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);
    final Size buttonSize = button.size;
    
    // 菜单出现在按钮正下方
    final position = RelativeRect.fromLTRB(
      buttonPosition.dx,
      buttonPosition.dy + buttonSize.height,
      overlay.size.width - buttonPosition.dx - buttonSize.width,
      0,
    );
    
    showMenu(
      context: buttonContext,
      position: position,
      color: AppTheme.surfaceBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline, color: AppTheme.subTextColor, size: 16),
              const SizedBox(width: 8),
              Text('删除', style: TextStyle(color: AppTheme.textColor, fontSize: 13)),
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
  
  /// 显示错误对话框
  /// 将技术错误信息转换为用户友好的中文描述
  String _friendlyErrorMessage(String raw) {
    // 移除 'Exception: ' 前缀
    String msg = raw.replaceFirst(RegExp(r'^Exception:\s*'), '');
    
    // 常见错误模式的中文翻译
    if (msg.contains('No available channel')) {
      return '当前模型暂时没有可用通道，请稍后重试或更换其他模型';
    }
    if (msg.contains('HandshakeException') || msg.contains('CERTIFICATE_VERIFY_FAILED')) {
      return '网络连接安全验证失败，请检查网络设置或 API 地址是否正确';
    }
    if (msg.contains('SocketException') || msg.contains('Connection refused')) {
      return '无法连接到服务器，请检查网络连接和 API 地址';
    }
    if (msg.contains('TimeoutException') || msg.contains('轮询超时')) {
      return '视频生成超时，服务器处理时间过长，请稍后重试';
    }
    if (msg.contains('401') || msg.contains('Unauthorized')) {
      return 'API 密钥无效或已过期，请前往设置页面检查密钥配置';
    }
    if (msg.contains('403') || msg.contains('Forbidden')) {
      return '没有权限访问该服务，请检查账户权限或 API 密钥';
    }
    if (msg.contains('429') || msg.contains('rate limit')) {
      return '请求过于频繁，已达到速率限制，请稍后重试';
    }
    if (msg.contains('500') || msg.contains('Internal Server Error')) {
      return '服务器内部错误，请稍后重试';
    }
    if (msg.contains('502') || msg.contains('Bad Gateway')) {
      return '服务器网关错误，请稍后重试';
    }
    if (msg.contains('503') || msg.contains('Service Unavailable')) {
      return '服务暂时不可用，请稍后重试';
    }
    if (msg.contains('未配置')) {
      return msg; // 已经是中文提示
    }
    
    return msg;
  }

  void _showErrorDialog(String title, String message) {
    final friendlyMessage = ErrorTranslator.translate(message);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceBackground,
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 24),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                color: AppTheme.textColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            child: SelectableText(
              friendlyMessage,
              style: TextStyle(
                color: AppTheme.textColor,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '确定',
              style: TextStyle(
                color: AppTheme.accentColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
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
      
      // ✅ 判断是否为网页服务商
      final isWebProvider = ['vidu', 'jimeng', 'keling', 'hailuo'].contains(provider);
      
      if (isWebProvider) {
        // ========== 网页服务商路线 ==========
        _logger.info('使用网页服务商生成视频', module: '视频空间', extra: {'provider': provider});
        
        // 读取网页服务商配置
        final webTool = prefs.getString('video_web_tool');
        final webModel = prefs.getString('video_web_model');
        
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
            '3. 运行: python python_backend/web_automation/api_server.py'
          );
        }
        
        _logger.success('Python API 服务连接成功', module: '视频空间');
        
        // ✅ Vidu 需要顺序生成（每次生成需要刷新页面），其他网页服务商可以并发
        final isViduProvider = provider == 'vidu';
        
        if (isViduProvider) {
          // ========== Vidu 批量生成模式：一次填写提示词，点 N 次创作 ==========
          _logger.info('Vidu 批量模式：一次提交 $batchCount 个视频（点 $batchCount 次创作，间隔 2.5s）', module: '视频空间');
          
          try {
            // 构建 payload（只需一个，共用同一提示词和参数）
            final payload = await _buildViduPayload(
              prefs: prefs, webModel: webModel, webTool: webTool, index: 0,
            );
            debugPrint('🔍 [VIDU生成] webTool=$webTool, payload keys=${payload.keys}, hasSegments=${payload.containsKey("segments")}');
            if (payload.containsKey('segments')) {
              debugPrint('🔍 [VIDU生成] segments=${payload["segments"]}');
            }
            // 告诉 Python 点 N 次创作
            payload['batchCount'] = batchCount;

            // ONE submit call → Python 填写一次提示词，点 N 次创作
            final result = await aigcClient.submitGenerationTask(
              platform: provider,
              toolType: webTool,
              payload: payload,
            );

            // 获取所有 task_ids
            final taskIds = result.taskIds ?? [result.taskId];

            _logger.success(
              'Vidu 批量提交成功：${taskIds.length} 个任务 $taskIds',
              module: '视频空间',
            );

            // 并行轮询所有任务
            final pollFutures = <Future<void>>[];
            for (var i = 0; i < taskIds.length && i < batchCount; i++) {
              final tid = taskIds[i];
              final placeholder = placeholders[i];

              pollFutures.add(() async {
                try {
                  _logger.info(
                    'Vidu 轮询任务 ${i + 1}/${taskIds.length}: $tid',
                    module: '视频空间',
                  );

                  final pollResult = await aigcClient.pollTaskStatus(
                    taskId: tid,
                    interval: const Duration(seconds: 3),
                    maxAttempts: 300,
                    onProgress: (taskResult) {
                      if (taskResult.isRunning) {
                        _globalVideoProgress[placeholder] = 50;
                      }
                      if (mounted && widget.task.generatedVideos.contains(placeholder)) {
                        setState(() {});
                      }
                    },
                  );

                  if (pollResult.isSuccess) {
                    final videoPath =
                        pollResult.localVideoPath ?? pollResult.videoUrl;
                    if (videoPath == null || videoPath.isEmpty) {
                      throw Exception('任务完成但未返回视频地址');
                    }

                    _logger.success(
                      'Vidu 任务 ${i + 1} 完成: $videoPath',
                      module: '视频空间',
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
                        _logger.warning('提取首帧失败: $e', module: '视频空间');
                      }
                    }

                    // 替换占位符
                    final currentVideos = List<String>.from(
                      widget.task.generatedVideos,
                    );
                    final placeholderIndex = currentVideos.indexOf(placeholder);
                    if (placeholderIndex != -1) {
                      currentVideos[placeholderIndex] = videoPath;
                      _globalVideoProgress.remove(placeholder);
                      _update(widget.task.copyWith(generatedVideos: currentVideos));
                      if (mounted) setState(() {});
                    }
                  } else {
                    throw Exception(pollResult.error ?? '生成失败');
                  }
                } catch (e) {
                  _logger.error(
                    'Vidu 任务 ${i + 1} 失败: $e',
                    module: '视频空间',
                  );
                  // 标记为失败
                  final currentVideos = List<String>.from(
                    widget.task.generatedVideos,
                  );
                  final placeholderIndex = currentVideos.indexOf(placeholder);
                  if (placeholderIndex != -1) {
                    currentVideos[placeholderIndex] =
                        'failed_${DateTime.now().millisecondsSinceEpoch}';
                    _globalVideoProgress.remove(placeholder);
                    _update(widget.task.copyWith(generatedVideos: currentVideos));
                    if (mounted) setState(() {});
                  }
                }
              }()); // 立即执行异步闭包
            }

            await Future.wait(pollFutures);
          } catch (e) {
            _logger.error('Vidu 批量提交失败: $e', module: '视频空间');
          }
          
          _logger.success('Vidu 批量生成全部完成', module: '视频空间');
          aigcClient.dispose();
          return;
        }
        
        // ========== 非 Vidu 网页服务商：并发提交 ==========
        _logger.info('开始并发提交 $batchCount 个视频任务', module: '视频空间');
        
        final submitFutures = List.generate(batchCount, (i) async {
          final placeholder = placeholders[i];
          
          try {
            _logger.info('提交任务 ${i + 1}/$batchCount', module: '视频空间');
            
            // ✅ 构建 payload，根据工具类型添加不同参数
            final payload = <String, dynamic>{
              'prompt': widget.task.prompt,
              'model': webModel,
            };
            
            // ✅ 添加保存路径（从设置中读取）
            final savePath = prefs.getString('video_save_path');
            if (savePath != null && savePath.isNotEmpty) {
              // 生成唯一的文件名
              final timestamp = DateTime.now().millisecondsSinceEpoch;
              final fileName = 'video_${timestamp}_${widget.task.id}_$i.mp4';
              final fullPath = path.join(savePath, fileName);
              payload['savePath'] = fullPath;
              _logger.info('设置保存路径: $fullPath', module: '视频空间');
            } else {
              _logger.warning('未设置视频保存路径，将使用默认路径', module: '视频空间');
            }
            
            // ✅ 如果是图生视频，需要提供图片
            if (webTool == 'img2video') {
              if (widget.task.referenceImages == null || widget.task.referenceImages!.isEmpty) {
                throw Exception(
                  '图生视频需要提供参考图片\n\n'
                  '请在视频空间添加参考图片后再生成'
                );
              }
              // 使用第一张参考图片
              payload['imageUrl'] = widget.task.referenceImages!.first;
              _logger.info('使用参考图片: ${widget.task.referenceImages!.first}', module: '视频空间');
            }
            
            // ✅ 如果是参考生视频，可选提供参考文件（图片或视频）
            if (webTool == 'ref2video') {
              if (widget.task.referenceImages != null && widget.task.referenceImages!.isNotEmpty) {
                // 遍历所有参考图片，收集素材库名称和普通文件
                final List<String> assetNames = [];
                final List<String> normalFiles = [];
                
                for (final refPath in widget.task.referenceImages!) {
                  final assetName = await _findAssetNameByPath(refPath);
                  if (assetName != null && assetName.isNotEmpty) {
                    assetNames.add(assetName);
                  } else {
                    normalFiles.add(refPath);
                  }
                }
                
                // 素材库主体名称（逗号分隔，支持多个）
                if (assetNames.isNotEmpty) {
                  payload['characterName'] = assetNames.join(',');
                  _logger.info('参考生视频：素材库主体「${assetNames.join(", ")}」', module: '视频空间');
                }
                
                // 普通文件：只取第一个作为参考文件上传（即使已有素材库主体也上传）
                if (normalFiles.isNotEmpty) {
                  payload['referenceFile'] = normalFiles.first;
                  _logger.info('参考生视频：上传参考文件 ${normalFiles.first}', module: '视频空间');
                }
              } else {
                // 无参考文件，检查是否有角色名用于主体库选择
                if (widget.task.characterName.isNotEmpty) {
                  payload['characterName'] = widget.task.characterName;
                  _logger.info('参考生视频：使用主体库角色「${widget.task.characterName}」', module: '视频空间');
                } else {
                  _logger.info('参考生视频：无参考文件和角色名，仅使用提示词', module: '视频空间');
                }
              }
            }
            
            // ✅ 即梦：始终传递模式（默认全能参考）
            if (provider == 'jimeng') {
              payload['mode'] = prefs.getString('video_web_mode') ?? 'all_ref';
              
              // 解析 prompt 中的 [📷X] 占位符，提取图片路径和角色名
              final segments = await _parsePromptToSegments(widget.task.prompt, prefs);
              final List<String> refImages = [];
              final List<String> charNames = [];
              String cleanPrompt = '';
              
              for (final seg in segments) {
                if (seg['type'] == 'image' && seg['path'] != null && seg['path']!.isNotEmpty) {
                  final name = seg['name'] ?? '';
                  // 去重：同名角色只上传一次
                  if (!charNames.contains(name)) {
                    refImages.add(seg['path']!);
                    charNames.add(name);
                  }
                } else {
                  cleanPrompt += seg['content'] ?? '';
                }
              }
              
              if (refImages.isNotEmpty) {
                payload['referenceImages'] = refImages;
                payload['characterNames'] = charNames;
                payload['prompt'] = cleanPrompt;
                _logger.info('即梦全能参考：${refImages.length}张图(去重), 角色=${charNames.join(",")}', module: '视频空间');
              } else if (widget.task.referenceImages != null && widget.task.referenceImages!.isNotEmpty) {
                // fallback: 用户通过 UI 添加的参考图片
                payload['referenceImages'] = widget.task.referenceImages;
                _logger.info('即梦参考图：${widget.task.referenceImages!.length}张(UI添加)', module: '视频空间');
              }
            }
            
            // ✅ 添加视频参数（比例、分辨率、时长）
            payload['aspectRatio'] = widget.task.ratio;    // e.g. '16:9', '9:16', '1:1'
            payload['resolution'] = widget.task.quality;   // e.g. '1080P', '720P'
            payload['duration'] = _parseSeconds(widget.task.seconds);     // e.g. '10秒' → 10
            
            // 提交生成任务
            final result = await aigcClient.submitGenerationTask(
              platform: provider,
              toolType: webTool,
              payload: payload,
            );
            
            _logger.success('任务 ${i + 1} 提交成功: ${result.taskId}', module: '视频空间');
            
            return {
              'index': i,
              'taskId': result.taskId,
              'placeholder': placeholder,
            };
          } catch (e) {
            _logger.error('任务 ${i + 1} 提交失败: $e', module: '视频空间');
            rethrow;
          }
        });
        
        // 等待所有任务提交完成
        final submittedTasks = await Future.wait(submitFutures);
        _logger.success('所有任务已提交，开始轮询', module: '视频空间');
        
        // ✅ 并发轮询所有任务
        final pollFutures = submittedTasks.map((task) async {
          final index = task['index'] as int;
          final taskId = task['taskId'] as String;
          final placeholder = task['placeholder'] as String;
          
          try {
            _logger.info('开始轮询任务 ${index + 1}: $taskId', module: '视频空间');
            
            // 轮询任务状态
            final result = await aigcClient.pollTaskStatus(
              taskId: taskId,
              interval: const Duration(seconds: 3),
              maxAttempts: 300,  // 最多 15 分钟（与后端 max_wait=900 匹配）
              onProgress: (taskResult) {
                // 更新进度（网页服务商暂时没有精确进度，显示为运行中）
                if (taskResult.isRunning) {
                  _globalVideoProgress[placeholder] = 50;  // 显示 50% 表示运行中
                }
                
                if (mounted && widget.task.generatedVideos.contains(placeholder)) {
                  setState(() {});
                }
                
                _logger.info('任务 ${index + 1} 状态: ${taskResult.status}', module: '视频空间');
              },
            );
            
            if (result.isSuccess) {
              // 任务成功完成
              final videoPath = result.localVideoPath ?? result.videoUrl;
              
              if (videoPath == null || videoPath.isEmpty) {
                throw Exception('任务完成但未返回视频地址');
              }
              
              _logger.success('任务 ${index + 1} 完成', module: '视频空间', extra: {
                'videoPath': videoPath,
                'isLocal': result.localVideoPath != null,
              });
              
              // ✅ 提取视频首帧作为缩略图（本地文件才需要）
              if (videoPath != null && !videoPath.startsWith('http') && videoPath.endsWith('.mp4')) {
                try {
                  final thumbnailPath = videoPath.replaceAll('.mp4', '.jpg');
                  final ffmpeg = FFmpegService();
                  final success = await ffmpeg.extractFrame(
                    videoPath: videoPath,
                    outputPath: thumbnailPath,
                  );
                  if (success) {
                    _logger.success('网页服务商视频首帧已提取', module: '视频空间');
                  }
                } catch (e) {
                  _logger.warning('提取首帧失败: $e', module: '视频空间');
                }
              }
              
              // 替换占位符
              final currentVideos = List<String>.from(widget.task.generatedVideos);
              final placeholderIndex = currentVideos.indexOf(placeholder);
              
              if (placeholderIndex != -1) {
                currentVideos[placeholderIndex] = videoPath;
                _globalVideoProgress.remove(placeholder);
                _update(widget.task.copyWith(generatedVideos: currentVideos));
                
                if (mounted) {
                  setState(() {});
                }
              }
              
              return true;
            } else {
              // 任务失败
              throw Exception(result.error ?? '生成失败');
            }
          } catch (e) {
            _logger.error('任务 ${index + 1} 处理失败: $e', module: '视频空间');
            
            // 标记为失败
            final currentVideos = List<String>.from(widget.task.generatedVideos);
            final placeholderIndex = currentVideos.indexOf(placeholder);
            
            if (placeholderIndex != -1) {
              currentVideos[placeholderIndex] = 'failed_${DateTime.now().millisecondsSinceEpoch}';
              _globalVideoProgress.remove(placeholder);
              _update(widget.task.copyWith(generatedVideos: currentVideos));
              
              if (mounted) {
                setState(() {});
              }
            }
            
            return false;
          }
        }).toList();
        
        // 等待所有任务完成
        await Future.wait(pollFutures, eagerError: false);
        
        _logger.success('所有网页服务商任务已处理完成', module: '视频空间');
        
        // 清理资源
        aigcClient.dispose();
        
        // ✅ 网页服务商处理完成，直接返回
        return;
      }
      
      // ========== API 服务商路线（原有逻辑）==========
      final baseUrl = await _storage.getBaseUrl(provider: provider, modelType: 'video');
      final apiKey = await _storage.getApiKey(provider: provider, modelType: 'video');
      
      // 从设置中读取用户保存的模型，优先使用设置模型
      final savedModel = await _storage.getModel(provider: provider, modelType: 'video');
      final effectiveModel = savedModel ?? widget.task.model;
      
      _logger.info('视频生成配置', module: '视频空间', extra: {
        'provider': provider,
        'baseUrl': baseUrl ?? '(未配置)',
        'hasApiKey': apiKey != null && apiKey.isNotEmpty,
      });
      
      if (baseUrl == null || baseUrl.isEmpty) {
        throw Exception('未配置视频 Base URL\n\n请前往设置页面配置 API 地址');
      }
      
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('未配置视频 API Key\n\n请前往设置页面配置 API 密钥');
      }
      
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
        
        _logger.info('使用 ComfyUI 工作流', module: '视频空间', extra: {
          'workflow': selectedWorkflow,
        });
      }
      
      // ✅ RunningHub 检查：需要配置 WebApp ID
      if (provider.toLowerCase() == 'runninghub') {
        final webappId = prefs.getString('runninghub_video_webapp_id');
        if (webappId == null || webappId.isEmpty) {
          throw Exception('未配置 RunningHub 视频 WebApp ID\n\n请前往设置页面配置 RunningHub AI 应用 ID');
        }
      }
      
      // 创建配置
      final config = ApiConfig(
        provider: provider,
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
      
      // ✅ 使用 API 工厂创建服务（支持所有服务商，包括 ComfyUI）
      final apiFactory = ApiFactory();
      final service = apiFactory.createService(provider, config);
      
      _logger.success('创建 $provider 视频服务', module: '视频空间', extra: {
        'serviceType': service.runtimeType.toString(),
      });
      
      // 准备参数
      final size = _convertRatioToSize(widget.task.ratio, widget.task.quality, effectiveModel);
      final seconds = _parseSeconds(widget.task.seconds);
      
      _logger.info('开始并发生成 $batchCount 个视频', module: '视频空间', extra: {
        'model': effectiveModel,
        'size': size,
        'seconds': seconds,
      });
      
      // ✅ ComfyUI / RunningHub / OpenAI 服务的特殊处理（同步生成，不需要轮询）
      if (provider.toLowerCase() == 'comfyui' || provider.toLowerCase() == 'runninghub' || provider.toLowerCase() == 'openai') {
        _logger.info('使用 $provider 同步生成模式', module: '视频空间');
        
        // ComfyUI 直接生成，无需分步骤
        final generateFutures = List.generate(batchCount, (i) async {
          final placeholder = placeholders[i];
          
          try {
            _logger.info('开始生成第 ${i + 1}/$batchCount 个视频', module: '视频空间');
            
            // ComfyUI的generateVideos内部已处理轮询，直接返回视频URL
            final result = await service.generateVideos(
              prompt: widget.task.prompt,
              model: effectiveModel,
              ratio: size,
              referenceImages: widget.task.referenceImages,  // ✅ 修复：直接传递参考图片
              parameters: {
                'seconds': seconds,
              },
            );
            
            if (result.isSuccess && result.data != null && result.data!.isNotEmpty) {
              final videoUrl = result.data!.first.videoUrl;
              _logger.success('视频 ${i + 1} 生成完成', module: '视频空间', extra: {'url': videoUrl});
              
              // 下载并保存
              final savedPath = await _downloadSingleVideo(videoUrl, i);
              
              // 替换占位符
              final currentVideos = List<String>.from(widget.task.generatedVideos);
              final placeholderIndex = currentVideos.indexOf(placeholder);
              
              if (placeholderIndex != -1) {
                currentVideos[placeholderIndex] = savedPath;
                _globalVideoProgress.remove(placeholder);
                _update(widget.task.copyWith(generatedVideos: currentVideos));
                
                if (mounted) {
                  setState(() {});
                }
              }
              
              return true;
            } else {
              throw Exception('生成失败: ${result.errorMessage}');
            }
          } catch (e) {
            _logger.error('视频 ${i + 1} 生成失败: $e', module: '视频空间');
            
            // 标记为失败
            final currentVideos = List<String>.from(widget.task.generatedVideos);
            final placeholderIndex = currentVideos.indexOf(placeholder);
            
            if (placeholderIndex != -1) {
              currentVideos[placeholderIndex] = 'failed_${DateTime.now().millisecondsSinceEpoch}';
              _globalVideoProgress.remove(placeholder);
              _update(widget.task.copyWith(generatedVideos: currentVideos));
              
              if (mounted) {
                setState(() {});
              }
            }
            
            return false;
          }
        });
        
        // 等待所有视频生成完成
        await Future.wait(generateFutures, eagerError: false);
        _logger.success('所有 $provider 视频已处理完成', module: '视频空间');
        
        return;  // ✅ 同步模式处理完成，直接返回
      }
      
      // ✅ Yunwu 服务的异步轮询模式
      if (provider.toLowerCase() == 'yunwu') {
        _logger.info('使用 Yunwu 异步轮询模式', module: '视频空间');
        final yunwuService = service as YunwuService;
        final yunwuHelper = YunwuHelper(yunwuService);

        final submitFutures = List.generate(batchCount, (i) async {
          _logger.info('提交第 ${i + 1}/$batchCount 个视频任务', module: '视频空间');
          final result = await service.generateVideos(
            prompt: widget.task.prompt,
            model: effectiveModel,
            ratio: size,
            referenceImages: widget.task.referenceImages,
            parameters: {'seconds': seconds},
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

        final submittedTasks = await Future.wait(submitFutures);
        _logger.success('所有 Yunwu 任务已提交，开始并发轮询', module: '视频空间');

        final pollFutures = submittedTasks.map((task) async {
          final index = task['index'] as int;
          final taskId = task['taskId'] as String?;
          final placeholder = task['placeholder'] as String;

          if (taskId == null || taskId.isEmpty) return false;

          try {
            final statusResult = await yunwuHelper.pollTaskUntilComplete(
              taskId: taskId,
              maxWaitMinutes: 15,
              onProgress: (progress, status) {
                _globalVideoProgress[placeholder] = progress;
                if (mounted && widget.task.generatedVideos.contains(placeholder)) {
                  setState(() {});
                }
                _logger.info('任务 ${index + 1} 进度: $progress%', module: '视频空间');
              },
            );

            if (statusResult.isSuccess && statusResult.data != null && statusResult.data!.videoUrl != null) {
              final videoUrl = statusResult.data!.videoUrl!;
              _logger.success('任务 ${index + 1} 完成', module: '视频空间', extra: {'url': videoUrl});

              final savedPath = await _downloadSingleVideo(videoUrl, index);
              final currentVideos = List<String>.from(widget.task.generatedVideos);
              final placeholderIndex = currentVideos.indexOf(placeholder);

              if (placeholderIndex != -1) {
                currentVideos[placeholderIndex] = savedPath;
                _globalVideoProgress.remove(placeholder);
                _update(widget.task.copyWith(generatedVideos: currentVideos));
                if (mounted) setState(() {});
              }
              return true;
            } else {
              throw Exception('任务 ${index + 1} 失败: ${statusResult.errorMessage}');
            }
          } catch (e) {
            _logger.error('任务 ${index + 1} 处理失败: $e', module: '视频空间');
            final currentVideos = List<String>.from(widget.task.generatedVideos);
            final placeholderIndex = currentVideos.indexOf(placeholder);
            if (placeholderIndex != -1) {
              currentVideos[placeholderIndex] = 'failed_${DateTime.now().millisecondsSinceEpoch}';
              _globalVideoProgress.remove(placeholder);
              _update(widget.task.copyWith(generatedVideos: currentVideos));
              if (mounted) setState(() {});
            }
            return false;
          }
        }).toList();

        await Future.wait(pollFutures, eagerError: false);
        return;
      }

      // ✅ 其他服务（GeekNow/OpenAI等）的异步轮询模式
      _logger.info('使用异步轮询模式（适用于 $provider）', module: '视频空间');
      
      // 解析轮询函数：根据服务类型选择对应的 getVideoTaskStatus
      final Future<ApiResponse<VeoTaskStatus>> Function({required String taskId}) getStatusFn2;
      if (service is VeoVideoService) {
        getStatusFn2 = service.getVideoTaskStatus;
      } else if (service is GeekNowService) {
        getStatusFn2 = service.getVideoTaskStatus;
      } else {
        throw UnsupportedError('${service.runtimeType} 不支持视频任务轮询');
      }
      
      // 步骤1：并发提交所有任务
      final submitFutures = List.generate(batchCount, (i) async {
        _logger.info('提交第 ${i + 1}/$batchCount 个视频任务', module: '视频空间');
        
        final result = await service.generateVideos(
          prompt: widget.task.prompt,
          model: effectiveModel,
          ratio: size,
          referenceImages: widget.task.referenceImages,  // ✅ 修复：直接传递参考图片
          parameters: {
            'seconds': seconds,
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
          
          final statusResult = await VeoVideoHelper.pollUntilComplete(
            getStatus: getStatusFn2,
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
          // 清理全局进度
          _globalVideoProgress.remove(placeholder);
        }
      }
      _update(widget.task.copyWith(generatedVideos: currentVideos));
      
      // ✅ 显示详细的错误信息给用户
      if (mounted) {
        _showErrorDialog(
          '视频生成失败',
          _friendlyErrorMessage(e.toString()),
        );
      }
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
    
    // ✅ 构建缩略图 Widget
    final thumbnailWidget = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: _buildVideoThumbnail(videoPath),
    );
    
    // ✅ 如果是本地文件，用 VideoGridItem 支持原位播放
    if (isLocalFile) {
      // 获取缩略图路径
      final thumbnailPath = videoPath.replaceAll('.mp4', '.jpg');
      final thumbnailFile = File(thumbnailPath);
      
      return FutureBuilder<bool>(
        future: thumbnailFile.exists(),
        builder: (context, snapshot) {
          final coverUrl = snapshot.data == true ? thumbnailPath : null;
          
          // 使用 VideoGridItem 支持原位播放
          final videoGridItem = VideoGridItem(
            key: ValueKey(videoPath),
            videoUrl: videoPath,
            thumbnailWidget: thumbnailWidget,
          );
          
          // 用 DraggableMediaItem 包装支持拖动
          return DraggableMediaItem(
            filePath: videoPath,
            dragPreviewText: path.basename(videoPath),
            coverUrl: coverUrl,
            child: Stack(
              children: [
                // ✅ 右键菜单
                GestureDetector(
                  onSecondaryTapDown: (details) => _showVideoContextMenu(context, details, videoPath, isLocalFile),
                  child: videoGridItem,
                ),
                // 删除按钮
                Positioned(
                  top: 4,
                  right: 4,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                        debugPrint('[删除] 点击删除按钮');
                        _deleteVideo(videoPath);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
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
        },
      );
    }
    
    // 网络视频不支持原位播放，保持原有行为
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
                    thumbnailWidget,
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
          SnackBar(content: Text('打开视频失败：${ErrorTranslator.translate('$e')}')),
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
          value: 'open_video',
          child: Row(
            children: [
              Icon(Icons.play_circle_outline, size: 18),
              SizedBox(width: 8),
              Text('使用播放器播放'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'show_in_explorer',
          child: Row(
            children: [
              Icon(Icons.location_searching, size: 18),
              SizedBox(width: 8),
              Text('在文件夹中显示'),
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
      if (value == 'open_video') {
        _showVideoPreview(videoPath);
      } else if (value == 'show_in_explorer') {
        _showInExplorer(videoPath);
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

  /// 在资源管理器中显示文件（定位并选中文件）
  Future<void> _showInExplorer(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        // ✅ 使用 /select 参数定位并选中文件
        await Process.run('explorer', ['/select,', filePath]);
        _logger.success('已在资源管理器中定位到文件', module: '视频空间', extra: {'path': filePath});
      } else {
        _logger.error('文件不存在', module: '视频空间', extra: {'path': filePath});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件不存在')),
          );
        }
      }
    } catch (e) {
      _logger.error('定位文件失败: $e', module: '视频空间');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('定位文件失败：${ErrorTranslator.translate('$e')}')),
        );
      }
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
    super.build(context);  // 必须调用，因为使用了 AutomaticKeepAliveClientMixin
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
            child: MouseRegion(
              cursor: SystemMouseCursors.text,  // ✅ 整个区域显示文本光标
              child: GestureDetector(
                onTap: () {
                  // ✅ 点击容器任意位置，让文本框获得焦点
                  _focusNode.requestFocus();
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.inputBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,  // ✅ 绑定焦点节点
                    maxLines: null,  // ✅ 多行输入
                    keyboardType: TextInputType.multiline,
                    textAlignVertical: TextAlignVertical.top,  // ✅ 文本从顶部开始
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

  /// 图片库插入按钮（仅 VIDU ref2video 模式，样式同添加图片按钮）
  Widget _buildImageLibraryInsertBar() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: '从图片库插入占位符到光标处',
        child: GestureDetector(
          onTap: _showImageLibraryPicker,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: AppTheme.inputBackground,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AppTheme.dividerColor),
            ),
            child: Icon(
              Icons.collections_outlined,
              color: AppTheme.subTextColor,
              size: 12,
            ),
          ),
        ),
      ),
    );
  }

  /// 显示图片库选择器对话框
  Future<void> _showImageLibraryPicker() async {
    final prefs = await SharedPreferences.getInstance();
    final imageLibJson = prefs.getString('image_library_data');
    if (imageLibJson == null || imageLibJson.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('图片库为空，请先在素材库中添加图片')),
        );
      }
      return;
    }

    final List<dynamic> imageList = jsonDecode(imageLibJson);
    if (imageList.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('图片库为空，请先在素材库中添加图片')),
        );
      }
      return;
    }

    if (!mounted) return;
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final filtered = searchQuery.isEmpty
                ? imageList
                : imageList.where((item) {
                    final name = ((item as Map<String, dynamic>)['name'] as String? ?? '').toLowerCase();
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
                      onChanged: (v) => setDialogState(() => searchQuery = v),
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
                              itemBuilder: (ctx, i) {
                                final item = filtered[i] as Map<String, dynamic>;
                                final name = item['name'] as String? ?? '';
                                final filePath = item['path'] as String? ?? '';
                                return MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: GestureDetector(
                                    onTap: () => Navigator.of(ctx).pop(item),
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
                                              child: filePath.isNotEmpty && File(filePath).existsSync()
                                                  ? Image.file(File(filePath), fit: BoxFit.cover, width: double.infinity)
                                                  : Icon(Icons.image, color: AppTheme.subTextColor, size: 32),
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
                                              name,
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
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('取消', style: TextStyle(color: AppTheme.subTextColor)),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected != null) {
      final name = selected['name'] as String? ?? '';
      if (name.isNotEmpty) {
        _insertPlaceholderAtCursor('[📷$name]');
      }
    }
  }

  /// 在光标位置插入占位符文本
  void _insertPlaceholderAtCursor(String placeholder) {
    final text = _controller.text;
    final selection = _controller.selection;
    final cursorPos = selection.isValid ? selection.baseOffset : text.length;

    final newText = text.substring(0, cursorPos) + placeholder + text.substring(cursorPos);
    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(offset: cursorPos + placeholder.length);
    _update(widget.task.copyWith(prompt: newText));
    _focusNode.requestFocus();
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

  /// 构建 Vidu 网页服务商的 payload（供顺序生成模式使用）
  Future<Map<String, dynamic>> _buildViduPayload({
    required SharedPreferences prefs,
    required String webModel,
    required String webTool,
    required int index,
  }) async {
    final payload = <String, dynamic>{
      'prompt': widget.task.prompt,
      'model': webModel,
    };
    
    // 保存路径
    final savePath = prefs.getString('video_save_path');
    if (savePath != null && savePath.isNotEmpty) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'video_${timestamp}_${widget.task.id}_$index.mp4';
      final fullPath = path.join(savePath, fileName);
      payload['savePath'] = fullPath;
    }
    
    // 图生视频
    if (webTool == 'img2video') {
      if (widget.task.referenceImages == null || widget.task.referenceImages!.isEmpty) {
        throw Exception('图生视频需要提供参考图片');
      }
      payload['imageUrl'] = widget.task.referenceImages!.first;
    }
    
    // 参考生视频
    if (webTool == 'ref2video') {
      // 检查提示词中是否包含 [📷name] 占位符（图片库内联模式）
      final hasInlinePlaceholders = RegExp(r'\[📷[^\]]+\]').hasMatch(widget.task.prompt);
      debugPrint('🔍 [ref2video] prompt="${widget.task.prompt}", hasPlaceholders=$hasInlinePlaceholders');

      if (hasInlinePlaceholders) {
        // 图片库内联模式：解析占位符为 segments
        final segments = await _parsePromptToSegments(widget.task.prompt, prefs);
        debugPrint('🔍 [ref2video] 解析得到 ${segments.length} 个 segments: $segments');
        if (segments.isNotEmpty) {
          payload['segments'] = segments;
        }
      } else if (widget.task.referenceImages.isNotEmpty) {
        final List<String> assetNames = [];
        final List<String> normalFiles = [];
        
        for (final refPath in widget.task.referenceImages) {
          final assetName = await _findAssetNameByPath(refPath);
          if (assetName != null && assetName.isNotEmpty) {
            assetNames.add(assetName);
          } else {
            normalFiles.add(refPath);
          }
        }
        
        if (assetNames.isNotEmpty) {
          payload['characterName'] = assetNames.join(',');
        }
        if (normalFiles.isNotEmpty) {
          payload['referenceFile'] = normalFiles.first;
        }
      } else {
        if (widget.task.characterName.isNotEmpty) {
          payload['characterName'] = widget.task.characterName;
        }
      }
    }
    
    // 视频参数
    payload['aspectRatio'] = widget.task.ratio;
    payload['resolution'] = widget.task.quality;
    payload['duration'] = _parseSeconds(widget.task.seconds);

    // ✅ Vidu 去水印开关
    final viduWmFree = prefs.getBool('vidu_watermark_free') ?? false;
    if (viduWmFree) {
      payload['watermarkFree'] = true;
    }

    return payload;
  }

  /// 解析提示词中的 [📷name] 占位符，生成 segments 列表
  /// 返回格式: [{type: "text", content: "..."}, {type: "image", name: "...", path: "..."}]
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
      // 添加占位符前面的文本
      if (match.start > lastEnd) {
        final textBefore = prompt.substring(lastEnd, match.start).trim();
        if (textBefore.isNotEmpty) {
          segments.add({'type': 'text', 'content': textBefore});
        }
      }
      // 添加图片段
      final name = match.group(1)!.trim();
      final filePath = nameToPath[name] ?? '';
      if (filePath.isNotEmpty) {
        segments.add({'type': 'image', 'name': name, 'path': filePath});
      } else {
        _logger.warning('图片库中未找到: $name', module: '视频空间');
        // 名称找不到对应图片时作为文本保留
        segments.add({'type': 'text', 'content': '[📷$name]'});
      }
      lastEnd = match.end;
    }

    // 添加最后一段文本
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
      if (assetsJson == null || assetsJson.isEmpty) return null;
      
      final data = jsonDecode(assetsJson) as Map<String, dynamic>;
      // ✅ 规范化路径用于比较（Windows 路径大小写不敏感，分隔符可能不同）
      final normalizedInput = imagePath.replaceAll('\\', '/').toLowerCase();
      // 提取文件名用于回退匹配
      final inputFileName = normalizedInput.split('/').last;
      
      String? fallbackMatch;  // 文件名匹配的回退结果
      
      for (final entry in data.values) {
        final stylesList = entry as List;
        for (final styleData in stylesList) {
          final assets = (styleData['assets'] as List?) ?? [];
          for (final assetData in assets) {
            final asset = assetData as Map<String, dynamic>;
            final assetPath = (asset['path'] as String?) ?? '';
            final normalizedAsset = assetPath.replaceAll('\\', '/').toLowerCase();
            
            // 策略1：完整路径匹配（规范化后）
            if (normalizedAsset == normalizedInput || assetPath == imagePath) {
              final name = asset['name'] as String? ?? '';
              if (name.isNotEmpty && !name.contains('.png') && !name.contains('.jpg') && !name.contains('.jpeg') && !name.contains('.webp')) {
                return name;
              }
              return null;
            }
            
            // 策略2：文件名匹配（回退）
            if (fallbackMatch == null) {
              final assetFileName = normalizedAsset.split('/').last;
              if (assetFileName == inputFileName && assetFileName.isNotEmpty) {
                final name = asset['name'] as String? ?? '';
                if (name.isNotEmpty && !name.contains('.png') && !name.contains('.jpg') && !name.contains('.jpeg') && !name.contains('.webp')) {
                  fallbackMatch = name;
                }
              }
            }
          }
        }
      }
      
      if (fallbackMatch != null) {
        _logger.info('素材库查找: 使用文件名回退匹配 "$fallbackMatch" for $imagePath', module: '视频空间');
        return fallbackMatch;
      }
    } catch (e) {
      _logger.error('查找素材名称失败: $e', module: '视频空间');
    }
    return null;
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
    final showImageLibBtn = _currentProvider == 'vidu' && _currentWebTool == 'ref2video';
    return Row(
      children: [
        _addImageButton(),
        if (showImageLibBtn) ...[
          const SizedBox(width: 8),
          _buildImageLibraryInsertBar(),
        ],
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
        // 模型选择器已删除，使用设置中的全局配置
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
        onTap: canAddMore ? () => _showAddImageMenu() : null,
        child: Container(
          key: _addImageBtnKey,
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

  /// 显示添加图片菜单（本地文件 / 素材库）
  void _showAddImageMenu() {
    final RenderBox button = _addImageBtnKey.currentContext!.findRenderObject() as RenderBox;
    final offset = button.localToGlobal(Offset.zero);
    final size = button.size;
    
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height),
        Offset.zero & MediaQuery.of(context).size,
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
      if (value == 'local') {
        _pickLocalImages();
      } else if (value == 'library') {
        _pickFromAssetLibrary();
      } else if (value == 'image_library') {
        _showImageLibraryPicker();
      }
    });
  }

  /// 从本地选择图片
  Future<void> _pickLocalImages() async {
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
  }

  /// 从素材库选择图片
  Future<void> _pickFromAssetLibrary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final assetsJson = prefs.getString('asset_library_data');
      
      if (assetsJson == null || assetsJson.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('素材库为空，请先在素材库中添加图片')),
          );
        }
        return;
      }
      
      final data = jsonDecode(assetsJson) as Map<String, dynamic>;
      
      // 按分类整理素材
      const categoryNames = ['角色素材', '场景素材', '物品素材'];
      const categoryIcons = [Icons.person_outline, Icons.landscape_outlined, Icons.inventory_2_outlined];
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('素材库中没有图片')),
          );
        }
        return;
      }
      
      // 显示带分类标签的素材库对话框
      final selected = await showDialog<List<String>>(
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
      
      if (selected != null && selected.isNotEmpty) {
        final currentCount = widget.task.referenceImages.length;
        final availableSlots = 9 - currentCount;
        final newImages = selected.take(availableSlots).toList();
        _update(widget.task.copyWith(
          referenceImages: [...widget.task.referenceImages, ...newImages],
        ));
        _logger.success('从素材库添加 ${newImages.length} 张图片', module: '视频空间');
      }
    } catch (e) {
      _logger.error('从素材库选择失败: $e', module: '视频空间');
    }
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
            child: Builder(
              builder: (buttonContext) => GestureDetector(
                onTap: () => _showTaskMenu(buttonContext),
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
        ),
      ],
    );
  }
}
