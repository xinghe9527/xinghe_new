import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:xinghe_new/services/ffmpeg_service.dart';
import 'package:xinghe_new/services/aliyun_oss_upload_service.dart';  // ✅ 改为阿里云上传服务
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
  pending,          // 等待中
  processing,       // 处理中（FFmpeg）
  ffmpegCompleted,  // FFmpeg 完成，开始上传
  uploading,        // 上传中
  completed,        // 已完成
  failed,           // 失败
}

/// 上传队列管理器（单例）
/// 
/// 功能：
/// - 并发处理上传任务，但 FFmpeg 保持串行（避免资源竞争）
/// - 后台运行（切换界面不中断）
/// - 任务状态通知
class UploadQueueManager {
  static final UploadQueueManager _instance = UploadQueueManager._internal();
  factory UploadQueueManager() => _instance;
  UploadQueueManager._internal();

  final List<UploadTask> _queue = [];
  final List<UploadTask> _completedTasks = [];  // 保存已完成的任务
  bool _isProcessing = false;
  bool _ffmpegLocked = false;  // ✅ FFmpeg 串行锁
  
  final FFmpegService _ffmpegService = FFmpegService();
  final AliyunOssUploadService _uploadService = AliyunOssUploadService();  // ✅ 使用阿里云上传服务
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
    
    // ✅ 立即并发处理该任务
    _processTask(task);
  }

  /// ✅ 处理单个任务（并发执行，但 FFmpeg 保持串行）
  Future<void> _processTask(UploadTask task) async {
    try {
      _logger.info('开始处理上传任务', module: '上传队列', extra: {
        'taskId': task.id,
        'name': task.assetName,
      });

      // Step 1: 图片转视频（串行等待）
      await _waitForFFmpegLock();  // ✅ 等待 FFmpeg 锁
      _ffmpegLocked = true;  // ✅ 获取锁
      
      task.status = UploadTaskStatus.processing;
      _notifyStatusChange(task);
      
      _logger.info('Step 1/4: 图片转视频', module: '上传队列');
      final videoFile = await _ffmpegService.convertImageToVideo(task.imageFile);
      
      _ffmpegLocked = false;  // ✅ 释放锁，下一个任务可以开始 FFmpeg
      
      // ✅ FFmpeg 完成，发送通知（此时可以继续生成下一个）
      task.status = UploadTaskStatus.ffmpegCompleted;
      _notifyStatusChange(task);
      
      // Step 2: 上传到阿里云 OSS（并发，不需要等待）
      task.status = UploadTaskStatus.uploading;
      _notifyStatusChange(task);
      _logger.info('Step 2/4: 上传到阿里云 OSS', module: '上传队列');
      final videoUrl = await _uploadService.uploadVideo(videoFile);
      task.videoUrl = videoUrl;
      _logger.success('视频上传成功，URL: $videoUrl', module: '上传队列');
      
      // Step 3: 调用 Sora API 创建角色
      _logger.info('Step 3/4: 创建 Sora 角色', module: '上传队列');
      debugPrint('[队列管理器] 开始创建角色，视频URL: $videoUrl');
      debugPrint('[队列管理器] API配置: ${task.apiConfig.provider}, ${task.apiConfig.baseUrl}');
      
      final result = await _createCharacter(videoUrl, task.apiConfig);
      
      if (result != null) {
        task.characterInfo = '@${result.username},';
        debugPrint('[队列管理器] ✅ 角色创建成功: ${task.characterInfo}');
        
        _logger.success('上传任务完成', module: '上传队列', extra: {
          'taskId': task.id,
          'character': task.characterInfo,
        });
        
        task.status = UploadTaskStatus.completed;
      } else {
        debugPrint('[队列管理器] ❌ 角色创建失败：API 返回空结果');
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
      
      // ✅ 如果失败，确保释放 FFmpeg 锁
      if (_ffmpegLocked) {
        _ffmpegLocked = false;
      }
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
    _queue.remove(task);
  }
  
  /// ✅ 等待 FFmpeg 锁释放
  Future<void> _waitForFFmpegLock() async {
    while (_ffmpegLocked) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  /// 调用 Sora API 创建角色
  Future<SoraCharacter?> _createCharacter(String videoUrl, ApiConfig config) async {
    try {
      debugPrint('[队列管理器] 创建 VeoVideoService...');
      final service = VeoVideoService(config);
      
      debugPrint('[队列管理器] 调用 createCharacter API...');
      debugPrint('[队列管理器] - videoUrl: $videoUrl');
      debugPrint('[队列管理器] - timestamps: 0,3');
      
      final result = await service.createCharacter(
        timestamps: '0,3',
        url: videoUrl,
      );
      
      debugPrint('[队列管理器] API 响应: isSuccess=${result.isSuccess}');
      
      if (result.isSuccess) {
        debugPrint('[队列管理器] 角色数据: ${result.data?.username}');
        return result.data;
      } else {
        debugPrint('[队列管理器] ❌ API 错误: ${result.errorMessage}');
        throw Exception(result.errorMessage ?? '创建角色失败');
      }
    } catch (e, stackTrace) {
      debugPrint('[队列管理器] ❌ _createCharacter 异常: $e');
      debugPrint('[队列管理器] ❌ Stack Trace: $stackTrace');
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
