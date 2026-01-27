import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:xinghe_new/services/ffmpeg_service.dart';
import 'package:xinghe_new/services/supabase_upload_service.dart';
import 'package:xinghe_new/services/api/providers/veo_video_service.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';
import 'package:xinghe_new/core/logger/log_manager.dart';

/// 上传任务
class UploadTask {
  final String id;
  final File imageFile;
  final String assetName;
  final ApiConfig apiConfig;
  
  UploadTaskStatus status = UploadTaskStatus.pending;
  String? error;
  String? characterInfo;  // @username,
  String? videoUrl;
  
  UploadTask({
    required this.id,
    required this.imageFile,
    required this.assetName,
    required this.apiConfig,
  });
}

enum UploadTaskStatus {
  pending,      // 等待中
  processing,   // 处理中
  completed,    // 已完成
  failed,       // 失败
}

/// 上传队列管理器（单例）
/// 
/// 功能：
/// - 串行处理上传任务（避免并发导致崩溃）
/// - 后台运行（切换界面不中断）
/// - 任务状态通知
class UploadQueueManager {
  static final UploadQueueManager _instance = UploadQueueManager._internal();
  factory UploadQueueManager() => _instance;
  UploadQueueManager._internal();

  final List<UploadTask> _queue = [];
  final List<UploadTask> _completedTasks = [];  // 保存已完成的任务
  bool _isProcessing = false;
  
  final FFmpegService _ffmpegService = FFmpegService();
  final SupabaseUploadService _uploadService = SupabaseUploadService();
  final LogManager _logger = LogManager();
  
  // 任务状态更新回调
  final _statusController = StreamController<UploadTask>.broadcast();
  Stream<UploadTask> get statusStream => _statusController.stream;

  /// 添加上传任务到队列
  void addTask(UploadTask task) {
    _queue.add(task);
    _logger.info('添加上传任务到队列', module: '上传队列', extra: {
      'taskId': task.id,
      'name': task.assetName,
      'queueLength': _queue.length,
    });
    
    // 如果当前没有在处理，立即开始
    if (!_isProcessing) {
      _processQueue();
    }
  }

  /// 处理队列（串行执行）
  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty) {
      return;
    }

    _isProcessing = true;

    while (_queue.isNotEmpty) {
      final task = _queue.first;
      
      try {
        // 更新状态为处理中
        task.status = UploadTaskStatus.processing;
        _notifyStatusChange(task);
        
        _logger.info('开始处理上传任务', module: '上传队列', extra: {
          'taskId': task.id,
          'name': task.assetName,
        });

        // Step 1: 图片转视频
        _logger.info('Step 1/4: 图片转视频', module: '上传队列');
        final videoFile = await _ffmpegService.convertImageToVideo(task.imageFile);
        
        // Step 2: 上传到 Supabase
        _logger.info('Step 2/4: 上传到 Supabase', module: '上传队列');
        final videoUrl = await _uploadService.uploadVideo(videoFile);
        task.videoUrl = videoUrl;
        
        // Step 3: 调用 Sora API 创建角色
        _logger.info('Step 3/4: 创建 Sora 角色', module: '上传队列');
        final result = await _createCharacter(videoUrl, task.apiConfig);
        
        if (result != null) {
          task.characterInfo = '@${result.username},';
          
          _logger.success('上传任务完成', module: '上传队列', extra: {
            'taskId': task.id,
            'character': task.characterInfo,
          });
          
          task.status = UploadTaskStatus.completed;
        } else {
          throw Exception('角色创建失败：API 返回空结果');
        }
        
        // Step 4: 清理临时文件
        _logger.info('Step 4/4: 清理临时文件', module: '上传队列');
        await videoFile.delete();
        
      } catch (e, stackTrace) {
        task.status = UploadTaskStatus.failed;
        task.error = e.toString();
        
        _logger.error('上传任务失败', module: '上传队列', extra: {
          'taskId': task.id,
          'error': e.toString(),
        });
        
        debugPrint('Stack Trace: $stackTrace');
      }
      
      // 通知状态变化
      _notifyStatusChange(task);
      
      // 保存已完成或失败的任务
      if (task.status == UploadTaskStatus.completed || task.status == UploadTaskStatus.failed) {
        _completedTasks.add(task);
        // 只保留最近 50 个已完成任务
        if (_completedTasks.length > 50) {
          _completedTasks.removeAt(0);
        }
      }
      
      // 从队列中移除
      _queue.removeAt(0);
      
      // 短暂延迟，避免过快处理
      await Future.delayed(const Duration(milliseconds: 500));
    }

    _isProcessing = false;
    _logger.info('上传队列处理完成', module: '上传队列');
  }

  /// 调用 Sora API 创建角色
  Future<SoraCharacter?> _createCharacter(String videoUrl, ApiConfig config) async {
    try {
      final service = VeoVideoService(config);
      final result = await service.createCharacter(
        timestamps: '0,3',
        url: videoUrl,
      );
      
      if (result.isSuccess) {
        return result.data;
      } else {
        throw Exception(result.errorMessage ?? '创建角色失败');
      }
    } catch (e) {
      _logger.error('Sora API 调用失败: $e', module: '上传队列');
      rethrow;
    }
  }

  /// 通知状态变化
  void _notifyStatusChange(UploadTask task) {
    debugPrint('[队列管理器] 发送状态通知: ${task.id}, 状态: ${task.status}, 角色: ${task.characterInfo}');
    
    if (!_statusController.isClosed) {
      _statusController.add(task);
      debugPrint('[队列管理器] 状态通知已发送');
    } else {
      debugPrint('[队列管理器] 警告：Stream 已关闭，无法发送通知');
    }
  }

  /// 获取当前队列状态
  Map<String, dynamic> getQueueStatus() {
    return {
      'total': _queue.length,
      'processing': _isProcessing,
      'pending': _queue.where((t) => t.status == UploadTaskStatus.pending).length,
      'processing_count': _queue.where((t) => t.status == UploadTaskStatus.processing).length,
    };
  }

  /// 获取已完成的任务
  List<UploadTask> getCompletedTasks() {
    return List.from(_completedTasks);
  }

  /// 清空队列
  void clearQueue() {
    _queue.clear();
    _logger.warning('上传队列已清空', module: '上传队列');
  }

  /// 清空已完成任务
  void clearCompletedTasks() {
    _completedTasks.clear();
  }

  /// 释放资源
  void dispose() {
    _statusController.close();
  }
}
