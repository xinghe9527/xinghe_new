import 'package:flutter/material.dart';
import 'dart:io';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:xinghe_new/core/logger/log_manager.dart';
import 'package:xinghe_new/services/ffmpeg_service.dart';
import '../production_space_page.dart';

/// 视频音频编辑器对话框
/// 功能：视频预览 + 音频波形 + 多轨道时间轴 + 拖动调整
class VideoAudioEditorDialog extends StatefulWidget {
  final String videoPath;
  final List<VoiceDialogue> dialogues;
  final Map<String, String> dialogueAudioMap;  // key: dialogueId, value: audioPath
  final int videoIndex;
  final int storyboardIndex;
  final Function(Map<String, double>) onMerge;  // 返回每个对话的起始时间

  const VideoAudioEditorDialog({
    super.key,
    required this.videoPath,
    required this.dialogues,
    required this.dialogueAudioMap,
    required this.videoIndex,
    required this.storyboardIndex,
    required this.onMerge,
  });

  @override
  State<VideoAudioEditorDialog> createState() => _VideoAudioEditorDialogState();
}

class _VideoAudioEditorDialogState extends State<VideoAudioEditorDialog> {
  final LogManager _logger = LogManager();
  final FFmpegService _ffmpegService = FFmpegService();
  
  // media_kit 播放器
  late final Player _player;
  late final VideoController _videoController;
  bool _isInitializing = true;
  bool _isMerging = false;
  
  // 时间轴相关
  double _videoDuration = 5.0;
  double _currentPlayTime = 0.0;
  bool _isPlaying = false;
  
  // ✅ 多条音频轨道（每个对话一条）
  final Map<String, double> _audioDurations = {};  // key: dialogueId, value: duration
  final Map<String, double> _audioStartTimes = {};  // key: dialogueId, value: startTime
  
  // 时间轴缩放
  double _timelineZoom = 1.0;  // 1.0 = 正常，2.0 = 放大2倍

  @override
  void initState() {
    super.initState();
    // 初始化每个对话的起始时间为0
    for (final dialogue in widget.dialogues) {
      _audioStartTimes[dialogue.id] = 0.0;
    }
    _initializeMediaKit();
    _getAllAudioDurations();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  /// 初始化 media_kit 播放器
  Future<void> _initializeMediaKit() async {
    try {
      print('[视频编辑器] 开始初始化 media_kit 播放器');
      
      // 检查文件是否存在
      final videoFile = File(widget.videoPath);
      if (!await videoFile.exists()) {
        throw Exception('视频文件不存在');
      }

      // 创建播放器
      _player = Player();
      _videoController = VideoController(_player);
      
      print('[视频编辑器] 播放器创建完成');

      // 监听播放状态
      _player.stream.playing.listen((playing) {
        if (mounted) {
          setState(() => _isPlaying = playing);
        }
      });

      // 监听播放进度
      _player.stream.position.listen((position) {
        if (mounted) {
          setState(() {
            _currentPlayTime = position.inMilliseconds / 1000.0;
          });
        }
      });

      // 监听时长
      _player.stream.duration.listen((duration) {
        if (mounted && duration.inMilliseconds > 0) {
          setState(() {
            _videoDuration = duration.inMilliseconds / 1000.0;
          });
        }
      });

      // 打开视频
      await _player.open(Media(widget.videoPath));
      
      print('[视频编辑器] 视频已打开');

      if (mounted) {
        setState(() => _isInitializing = false);
      }

      _logger.success('视频初始化完成', module: '视频编辑器');
    } catch (e, stack) {
      _logger.error('视频初始化失败: $e', module: '视频编辑器');
      print('[视频编辑器] ❌ 初始化失败: $e');
      print('[视频编辑器] 堆栈: $stack');
      
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  /// 获取所有音频的时长
  Future<void> _getAllAudioDurations() async {
    for (final entry in widget.dialogueAudioMap.entries) {
      try {
        final duration = await _ffmpegService.getAudioDuration(entry.value);
        if (mounted) {
          setState(() {
            _audioDurations[entry.key] = duration ?? 3.0;
          });
        }
      } catch (e) {
        _logger.error('获取音频时长失败: $e', module: '视频编辑器');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 1000,
        height: 700,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E20),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF3A3A3C), width: 2),
        ),
        child: Column(
          children: [
            _buildHeader(),
            if (_isInitializing)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF667EEA)),
                      SizedBox(height: 16),
                      Text(
                        '正在加载视频...',
                        style: TextStyle(color: Color(0xFF888888), fontSize: 14),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: Column(
                  children: [
                    // ✅ media_kit 视频播放器
                    Expanded(child: _buildVideoPlayer()),
                    const SizedBox(height: 16),
                    // 播放控制栏
                    _buildPlaybackControls(),
                    const SizedBox(height: 16),
                    // 时间轴区域
                    _buildTimeline(),
                  ],
                ),
              ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  /// 顶部标题栏
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF252629),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
        ),
        border: Border(bottom: BorderSide(color: Color(0xFF3A3A3C))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF667EEA).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.movie_edit, color: Color(0xFF667EEA), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '视频音频编辑器',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '分镜 ${widget.storyboardIndex} - 视频 ${widget.videoIndex}',
                  style: const TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF888888)),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  /// media_kit 视频播放器
  Widget _buildVideoPlayer() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Video(
          controller: _videoController,
          controls: NoVideoControls,  // 不显示默认控制条
        ),
      ),
    );
  }

  /// 播放控制栏
  Widget _buildPlaybackControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF252629),
        border: Border(
          top: BorderSide(color: Color(0xFF3A3A3C)),
          bottom: BorderSide(color: Color(0xFF3A3A3C)),
        ),
      ),
      child: Row(
        children: [
          // 播放/暂停按钮
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _togglePlayPause,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          
          // 时间显示
          Text(
            '${_formatTime(_currentPlayTime)} / ${_formatTime(_videoDuration)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 16),
          
          // 播放进度条
          Expanded(
            child: Slider(
              value: _currentPlayTime.clamp(0.0, _videoDuration),
              min: 0.0,
              max: _videoDuration,
              activeColor: const Color(0xFF667EEA),
              inactiveColor: const Color(0xFF3A3A3C),
              onChanged: (value) {
                _player.seek(Duration(milliseconds: (value * 1000).toInt()));
              },
            ),
          ),
          
          const SizedBox(width: 16),
          
          // 音量控制
          const Icon(Icons.volume_up, color: Color(0xFF888888), size: 18),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Slider(
              value: 50.0,
              min: 0.0,
              max: 100.0,
              activeColor: const Color(0xFF888888),
              inactiveColor: const Color(0xFF3A3A3C),
              onChanged: (value) {
                _player.setVolume(value);
              },
            ),
          ),
          
          const SizedBox(width: 16),
          
          // ✅ 预览效果按钮
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _previewMerge,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2AF598).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF2AF598)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.visibility, color: Color(0xFF2AF598), size: 16),
                    SizedBox(width: 4),
                    Text(
                      '预览效果',
                      style: TextStyle(
                        color: Color(0xFF2AF598),
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
    );
  }

  /// 时间轴区域（多轨道，可滚动）
  Widget _buildTimeline() {
    // ✅ 根据对话数量动态计算高度（至少150，每增加一个对话增加36）
    final timelineHeight = (150.0 + (widget.dialogues.length * 36.0)).clamp(150.0, 350.0);
    
    return Container(
      height: timelineHeight,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1C),
        border: Border(top: BorderSide(color: Color(0xFF3A3A3C))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '时间轴',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              // 缩放控制
              IconButton(
                icon: const Icon(Icons.zoom_out, color: Color(0xFF888888)),
                onPressed: () {
                  setState(() {
                    _timelineZoom = (_timelineZoom * 0.8).clamp(0.5, 3.0);
                  });
                },
                tooltip: '缩小',
              ),
              Text(
                '${(_timelineZoom * 100).toInt()}%',
                style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
              ),
              IconButton(
                icon: const Icon(Icons.zoom_in, color: Color(0xFF888888)),
                onPressed: () {
                  setState(() {
                    _timelineZoom = (_timelineZoom * 1.25).clamp(0.5, 3.0);
                  });
                },
                tooltip: '放大',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              children: [
                // 轨道标签
                SizedBox(
                  width: 80,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        const Text('视频', style: TextStyle(color: Color(0xFF888888), fontSize: 12)),
                        const SizedBox(height: 40),
                        // ✅ 每个对话一个轨道标签
                        ...widget.dialogues.asMap().entries.map((entry) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 36),
                            child: Text(
                              '对话${entry.key + 1}',
                              style: const TextStyle(color: Color(0xFF888888), fontSize: 11),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                // 时间轴轨道
                Expanded(
                  child: _buildTimelineTracks(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 时间轴轨道
  Widget _buildTimelineTracks() {
    final pixelsPerSecond = 60.0 * _timelineZoom;
    final totalWidth = _videoDuration * pixelsPerSecond;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: totalWidth,
        height: 100,
        child: Stack(
          children: [
            // 时间刻度线
            ...List.generate((_videoDuration + 1).toInt(), (i) {
              return Positioned(
                left: i * pixelsPerSecond,
                top: 0,
                bottom: 0,
                child: Column(
                  children: [
                    Text(
                      '${i}s',
                      style: const TextStyle(color: Color(0xFF666666), fontSize: 10),
                    ),
                    Container(
                      width: 1,
                      height: 80,
                      color: const Color(0xFF3A3A3C),
                    ),
                  ],
                ),
              );
            }),
            
            // 视频轨道
            Positioned(
              left: 0,
              top: 20,
              child: Container(
                width: _videoDuration * pixelsPerSecond,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFF4A9EFF).withOpacity(0.5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF4A9EFF)),
                ),
                child: const Center(
                  child: Text(
                    '视频',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            
            // ✅ 多条音频轨道（每个对话一条，可拖动）
            ...widget.dialogues.asMap().entries.map((entry) {
              final dialogueIndex = entry.key;
              final dialogue = entry.value;
              final audioPath = widget.dialogueAudioMap[dialogue.id];
              
              if (audioPath == null) return const SizedBox.shrink();
              
              final startTime = _audioStartTimes[dialogue.id] ?? 0.0;
              final duration = _audioDurations[dialogue.id] ?? 3.0;
              final topPosition = 60.0 + (dialogueIndex * 36.0);
              
              return Positioned(
                left: startTime * pixelsPerSecond,
                top: topPosition,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      final delta = details.delta.dx / pixelsPerSecond;
                      final newStartTime = (startTime + delta).clamp(0.0, _videoDuration - 0.1);
                      _audioStartTimes[dialogue.id] = newStartTime;
                    });
                  },
                  child: Container(
                    width: duration * pixelsPerSecond,
                    height: 28,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF2AF598).withOpacity(0.8),
                          Color(0xFF009EFD).withOpacity(0.8),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF2AF598), width: 2),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.music_note, color: Colors.white, size: 12),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              dialogue.character,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            
          ],
        ),
      ),
    );
  }

  /// 底部按钮
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF252629),
        border: Border(top: BorderSide(color: Color(0xFF3A3A3C))),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      child: Row(
        children: [
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Color(0xFF888888))),
          ),
          const SizedBox(width: 12),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _isMerging ? null : _startMerge,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2AF598), Color(0xFF009EFD)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isMerging)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    else
                      const Icon(Icons.check, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _isMerging ? '合成中...' : '开始合成',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
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
    );
  }

  // ============ 业务方法 ============

  /// 播放/暂停切换
  void _togglePlayPause() {
    if (_isPlaying) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  /// 格式化时间
  String _formatTime(double seconds) {
    final minutes = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  /// 快速预览合成效果
  Future<void> _previewMerge() async {
    try {
      // 暂停播放
      _player.pause();
      
      // 显示加载提示
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              color: Color(0xFF1E1E20),
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF667EEA)),
                    SizedBox(height: 16),
                    Text(
                      '正在生成预览...',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      // ✅ TODO: 多音频合并预览（目前使用第一个音频作为预览）
      final firstAudioPath = widget.dialogueAudioMap.values.isNotEmpty 
          ? widget.dialogueAudioMap.values.first 
          : null;
      final firstStartTime = _audioStartTimes.values.isNotEmpty 
          ? _audioStartTimes.values.first 
          : 0.0;
      
      if (firstAudioPath == null) {
        throw Exception('没有可用的音频文件');
      }
      
      // 使用FFmpeg快速合成预览
      final previewPath = await _ffmpegService.mergeVideoAudioWithTiming(
        videoPath: widget.videoPath,
        audioPath: firstAudioPath,
        audioStartTime: firstStartTime,
        isPreview: true,
      );

      // 关闭加载提示
      if (mounted) Navigator.pop(context);

      if (previewPath != null) {
        // 在外部播放器中打开预览
        await Process.run('cmd', ['/c', 'start', '', previewPath]);
        
        _logger.success('预览生成完成', module: '视频编辑器');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _logger.error('预览失败: $e', module: '视频编辑器');
    }
  }

  /// 开始合成（返回所有对话的起始时间）
  Future<void> _startMerge() async {
    setState(() => _isMerging = true);
    await widget.onMerge(_audioStartTimes);
    if (mounted) {
      setState(() => _isMerging = false);
      Navigator.pop(context);
    }
  }
}
