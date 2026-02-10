import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'dart:async';  // ✅ 添加 async 导入以使用 StreamSubscription

/// 视频网格项 - 支持原位播放
class VideoGridItem extends StatefulWidget {
  final String videoUrl;
  final Widget thumbnailWidget;

  const VideoGridItem({
    super.key,
    required this.videoUrl,
    required this.thumbnailWidget,
  });

  @override
  State<VideoGridItem> createState() => _VideoGridItemState();
}

class _VideoGridItemState extends State<VideoGridItem> {
  Player? _player;
  VideoController? _controller;
  bool _isPlaying = false;
  bool _isDisposed = false;
  StreamSubscription? _completedSubscription;  // ✅ 添加订阅引用

  @override
  void dispose() {
    _isDisposed = true;
    _cleanupPlayer();
    super.dispose();
  }

  void _cleanupPlayer() {
    try {
      // ✅ 取消订阅
      _completedSubscription?.cancel();
      _completedSubscription = null;
      
      // ✅ 释放播放器
      _player?.dispose();
      
      debugPrint('🧹 [VideoGridItem] 清理播放器资源');
    } catch (e) {
      debugPrint('❌ [VideoGridItem] 清理播放器失败: $e');
    }
    _player = null;
    _controller = null;
  }

  void _togglePlay() {
    if (_isDisposed) return;
    
    if (_isPlaying) {
      // 停止播放
      debugPrint('⏹️ [VideoGridItem] 停止播放');
      _cleanupPlayer();
      if (mounted) {
        setState(() {
          _isPlaying = false;
        });
      }
    } else {
      // 开始播放
      try {
        debugPrint('▶️ [VideoGridItem] 开始播放: ${widget.videoUrl}');
        
        final player = Player();
        final controller = VideoController(player);
        
        player.open(Media(widget.videoUrl));
        
        // ✅ 监听播放完成（保存订阅引用）
        _completedSubscription = player.stream.completed.listen((completed) {
          if (completed && mounted && !_isDisposed) {
            debugPrint('✅ [VideoGridItem] 播放完成，恢复缩略图');
            // 播放完成，恢复缩略图
            _cleanupPlayer();
            if (mounted) {
              setState(() {
                _isPlaying = false;
              });
            }
          }
        });
        
        if (mounted && !_isDisposed) {
          setState(() {
            _player = player;
            _controller = controller;
            _isPlaying = true;
          });
        }
      } catch (e) {
        debugPrint('❌ [VideoGridItem] 创建播放器失败: $e');
        if (mounted && !_isDisposed) {
          setState(() {
            _isPlaying = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 添加错误处理
    try {
      return GestureDetector(
        onTap: _togglePlay,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1C),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: const Color(0xFF3A3A3C),
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: _isPlaying && _controller != null
                ? Video(
                    controller: _controller!,
                    controls: NoVideoControls,
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      widget.thumbnailWidget,
                      // 播放按钮
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('VideoGridItem build error: $e');
      // 返回一个简单的容器作为后备
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1C),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: const Color(0xFF3A3A3C),
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.thumbnailWidget,
              Center(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
}
