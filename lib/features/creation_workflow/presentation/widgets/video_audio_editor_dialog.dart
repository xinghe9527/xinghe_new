import 'package:flutter/material.dart';
import 'dart:io';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:audioplayers/audioplayers.dart';
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
  
  // 音频播放器（用于播放多个音频轨道）
  final Map<String, AudioPlayer> _audioPlayers = {};
  
  // 时间轴相关
  double _videoDuration = 5.0;
  double _currentPlayTime = 0.0;
  bool _isPlaying = false;
  double _volume = 50.0;  // ✅ 添加音量状态
  
  // ✅ 多条音频轨道（每个对话一条）
  final Map<String, double> _audioDurations = {};  // key: dialogueId, value: duration
  final Map<String, double> _audioStartTimes = {};  // key: dialogueId, value: startTime
  final Map<String, bool> _audioMuted = {};  // key: dialogueId, value: isMuted
  final Map<String, List<double>> _audioWaveforms = {};  // key: dialogueId, value: waveform data
  final Map<String, int> _audioTrackIndex = {};  // key: dialogueId, value: trackIndex (轨道索引)
  final Map<String, double> _audioOffsets = {};  // key: dialogueId, value: offset in original audio (音频文件内的偏移量)
  
  // 视频片段管理
  final List<VideoSegment> _videoSegments = [];
  String? _selectedVideoId;
  
  // 选中的音轨
  String? _selectedAudioId;
  
  // 拖动状态
  bool _isDragging = false;
  String? _draggingAudioId;
  
  // ✅ 滚动控制器（用于同步时间刻度和轨道内容）
  final ScrollController _horizontalScrollController = ScrollController();
  
  // 时间轴缩放
  double _timelineZoom = 1.0;  // 1.0 = 正常，2.0 = 放大2倍

  @override
  void initState() {
    super.initState();
    // 初始化每个对话的起始时间为0
    for (final entry in widget.dialogues.asMap().entries) {
      final index = entry.key;
      final dialogue = entry.value;
      _audioStartTimes[dialogue.id] = 0.0;
      _audioMuted[dialogue.id] = false;  // 默认不静音
      _audioTrackIndex[dialogue.id] = index;  // 记录轨道索引
      _audioOffsets[dialogue.id] = 0.0;  // 默认从音频文件开头播放
      // 为每个音频创建播放器
      _audioPlayers[dialogue.id] = AudioPlayer();
    }
    
    // 初始化视频片段（初始只有一个完整视频）
    _videoSegments.add(VideoSegment(
      id: 'video_0',
      startTime: 0.0,
      duration: 0.0,  // 会在加载后更新
    ));
    
    _initializeMediaKit();
    _getAllAudioDurations();
    _generateAllWaveforms();
  }
  
  /// 生成所有音频的波形数据
  Future<void> _generateAllWaveforms() async {
    for (final entry in widget.dialogueAudioMap.entries) {
      try {
        final waveform = await _generateWaveformData(entry.value);
        if (mounted) {
          setState(() {
            _audioWaveforms[entry.key] = waveform;
          });
        }
      } catch (e) {
        _logger.error('生成波形失败: $e', module: '视频编辑器');
      }
    }
  }

  /// 生成音频波形数据（使用FFmpeg提取真实波形）
  Future<List<double>> _generateWaveformData(String audioPath) async {
    try {
      print('[波形生成] 开始提取波形: $audioPath');
      
      // 使用 FFmpeg 提取音频波形数据
      final result = await Process.run(
        'ffmpeg',
        [
          '-i', audioPath,
          '-ac', '1',  // 单声道
          '-ar', '8000',  // 采样率 8000Hz
          '-f', 's16le',  // 16位PCM
          '-'
        ],
        stdoutEncoding: null,  // 二进制输出
      );

      print('[波形生成] FFmpeg 退出码: ${result.exitCode}');
      
      if (result.exitCode == 0 && result.stdout is List<int>) {
        final bytes = result.stdout as List<int>;
        print('[波形生成] 获取到 ${bytes.length} 字节数据');
        
        final samples = <double>[];
        
        // 每2个字节组成一个16位采样点
        for (int i = 0; i < bytes.length - 1; i += 2) {
          final sample = (bytes[i] | (bytes[i + 1] << 8));
          // 转换为 -32768 到 32767 的范围
          final signedSample = sample > 32767 ? sample - 65536 : sample;
          // 归一化到 0.0 - 1.0
          final normalized = (signedSample.abs() / 32768.0).clamp(0.0, 1.0);
          samples.add(normalized);
        }
        
        print('[波形生成] 解析出 ${samples.length} 个采样点');
        
        // 降采样到 300 个点
        if (samples.length > 300) {
          final step = samples.length / 300;
          final downsampled = <double>[];
          for (int i = 0; i < 300; i++) {
            final index = (i * step).floor();
            if (index < samples.length) {
              // 取一小段的最大值（更能体现音频特征）
              final start = index;
              final end = ((i + 1) * step).floor().clamp(0, samples.length);
              double maxValue = 0.0;
              for (int j = start; j < end; j++) {
                if (samples[j] > maxValue) {
                  maxValue = samples[j];
                }
              }
              downsampled.add(maxValue);
            }
          }
          print('[波形生成] 降采样到 ${downsampled.length} 个点');
          return downsampled;
        }
        
        print('[波形生成] 使用原始采样点: ${samples.length}');
        return samples.take(300).toList();
      } else {
        print('[波形生成] FFmpeg 失败，stderr: ${result.stderr}');
      }
    } catch (e) {
      print('[波形生成] FFmpeg 提取失败: $e');
    }
    
    // 如果 FFmpeg 失败，生成模拟波形作为降级方案
    print('[波形生成] 使用模拟波形作为降级方案');
    return List.generate(300, (i) {
      // 生成随机但有规律的波形
      final base = (i % 50) / 50.0;
      final variation = (i % 10) / 20.0;
      return (base + variation).clamp(0.1, 0.9);
    });
  }

  @override
  void dispose() {
    // 先释放音频播放器
    for (final player in _audioPlayers.values) {
      player.stop();
      player.dispose();
    }
    _audioPlayers.clear();
    // 释放滚动控制器
    _horizontalScrollController.dispose();
    // 再释放视频播放器
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
          // 实时同步音频播放
          if (_isPlaying) {
            _syncAudioPlayback();
          }
        }
      });

      // 监听时长
      _player.stream.duration.listen((duration) {
        if (mounted && duration.inMilliseconds > 0) {
          setState(() {
            _videoDuration = duration.inMilliseconds / 1000.0;
            // 更新视频片段时长
            if (_videoSegments.isNotEmpty) {
              _videoSegments[0].duration = _videoDuration;
            }
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
        
        // 加载音频到播放器
        final player = _audioPlayers[entry.key];
        if (player != null) {
          await player.setSource(DeviceFileSource(entry.value));
          await player.setVolume(_volume / 100.0);  // ✅ 设置初始音量
          await player.setReleaseMode(ReleaseMode.stop);  // 播放完后停止
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
        width: 1600,  // ✅ 从 1400 增加到 1600
        height: 1100,  // ✅ 从 1000 增加到 1100
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
                    // ✅ 视频播放器（5倍大小）
                    Expanded(
                      flex: 5,
                      child: _buildVideoPlayer(),
                    ),
                    const SizedBox(height: 16),
                    // 播放控制栏
                    _buildPlaybackControls(),
                    const SizedBox(height: 16),
                    // 时间轴区域（5倍大小，与视频相同）
                    Expanded(
                      flex: 5,
                      child: _buildTimeline(),
                    ),
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
              onChanged: (value) async {
                // ✅ 拖动或点击时立即跳转并暂停
                if (_isPlaying) {
                  await _player.pause();
                  for (final player in _audioPlayers.values) {
                    await player.pause();
                  }
                }
                
                setState(() {
                  _currentPlayTime = value;
                });
                await _player.seek(Duration(milliseconds: (value * 1000).toInt()));
              },
            ),
          ),
          
          const SizedBox(width: 16),
          
          // 音量控制
          Icon(
            _volume == 0 ? Icons.volume_off : _volume < 50 ? Icons.volume_down : Icons.volume_up,
            color: const Color(0xFF888888),
            size: 18,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Slider(
              value: _volume,
              min: 0.0,
              max: 100.0,
              activeColor: const Color(0xFF888888),
              inactiveColor: const Color(0xFF3A3A3C),
              onChanged: (value) {
                setState(() {
                  _volume = value;
                });
                // ✅ 设置视频音量（0.0 - 1.0）
                _player.setVolume(value / 100.0);
                // ✅ 设置所有音频播放器的音量
                for (final player in _audioPlayers.values) {
                  player.setVolume(value / 100.0);
                }
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
    final pixelsPerSecond = 80.0 * _timelineZoom;
    final totalWidth = (_videoDuration * pixelsPerSecond).clamp(800.0, double.infinity);
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1C),
        border: Border(top: BorderSide(color: Color(0xFF3A3A3C))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ 顶部：时间轴标题 + 时间刻度线（在同一行）+ 缩放控制
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 左侧：时间轴标题（固定宽度，和下方标签列对齐）
              const SizedBox(
                width: 100,
                child: Text(
                  '时间轴',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // 中间：时间刻度线（可水平滚动）
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: SingleChildScrollView(
                    controller: _horizontalScrollController,
                    scrollDirection: Axis.horizontal,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTapDown: (details) async {
                        final clickX = details.localPosition.dx;
                        final newTime = (clickX / pixelsPerSecond).clamp(0.0, _videoDuration);
                        
                        if (_isPlaying) {
                          await _player.pause();
                          for (final player in _audioPlayers.values) {
                            await player.pause();
                          }
                        }
                        
                        setState(() {
                          _currentPlayTime = newTime;
                        });
                        
                        await _player.seek(Duration(milliseconds: (newTime * 1000).toInt()));
                      },
                      child: Container(
                        width: totalWidth,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              const Color(0xFF2A2A2C),
                              const Color(0xFF1A1A1C),
                            ],
                          ),
                          border: const Border(
                            bottom: BorderSide(color: Color(0xFF667EEA), width: 2),
                          ),
                        ),
                        child: Stack(
                          children: [
                            // 时间刻度
                            ...List.generate((_videoDuration + 1).toInt(), (i) {
                              return Positioned(
                                left: i * pixelsPerSecond,
                                top: 0,
                                bottom: 0,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${i}s',
                                      style: const TextStyle(
                                        color: Color(0xFFCCCCCC),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      width: 2,
                                      height: 8,
                                      color: const Color(0xFF667EEA),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            // 播放头指示器（圆点在底部，向上移动2px）
                            Positioned(
                              left: _currentPlayTime * pixelsPerSecond - 8,
                              bottom: 2,  // ✅ 向上移动2px
                              child: GestureDetector(
                                onHorizontalDragUpdate: (details) async {
                                  final delta = details.delta.dx / pixelsPerSecond;
                                  final newTime = (_currentPlayTime + delta).clamp(0.0, _videoDuration);
                                  
                                  if (_isPlaying) {
                                    await _player.pause();
                                    for (final player in _audioPlayers.values) {
                                      await player.pause();
                                    }
                                  }
                                  
                                  setState(() {
                                    _currentPlayTime = newTime;
                                  });
                                  
                                  await _player.seek(Duration(milliseconds: (newTime * 1000).toInt()));
                                },
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.resizeColumn,
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF6B6B),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFFF6B6B).withValues(alpha: 0.6),
                                          blurRadius: 6,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // 右侧：全局缩放控制
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF252629),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF3A3A3C)),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _timelineZoom = (_timelineZoom * 0.8).clamp(0.5, 3.0);
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFF3A3A3C),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.remove, color: Colors.white, size: 16),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120,
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        ),
                        child: Slider(
                          value: _timelineZoom,
                          min: 0.5,
                          max: 3.0,
                          activeColor: const Color(0xFF667EEA),
                          inactiveColor: const Color(0xFF3A3A3C),
                          onChanged: (value) {
                            setState(() {
                              _timelineZoom = value;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _timelineZoom = (_timelineZoom * 1.25).clamp(0.5, 3.0);
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFF3A3A3C),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.add, color: Colors.white, size: 16),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(_timelineZoom * 100).toInt()}%',
                      style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // ✅ 轨道区域（左侧标签 + 右侧轨道内容，作为一个整体垂直滚动）
          Expanded(
            child: SingleChildScrollView(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左侧标签列（固定宽度）
                  SizedBox(
                    width: 100,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 视频标签
                        Container(
                          height: 30,
                          alignment: Alignment.centerLeft,
                          child: const Text('视频', style: TextStyle(color: Color(0xFF888888), fontSize: 12)),
                        ),
                        const SizedBox(height: 10),
                        // 音频轨道标签
                        ...widget.dialogues.asMap().entries.map((entry) {
                          final index = entry.key;
                          final dialogue = entry.value;
                          
                          final trackAudios = _audioTrackIndex.entries
                              .where((e) => e.value == index)
                              .map((e) => e.key)
                              .toList();
                          final isAnyMuted = trackAudios.any((id) => _audioMuted[id] ?? false);
                          
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              height: 32,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        final newMutedState = !isAnyMuted;
                                        for (final audioId in trackAudios) {
                                          _audioMuted[audioId] = newMutedState;
                                        }
                                      });
                                    },
                                    child: Icon(
                                      isAnyMuted ? Icons.volume_off : Icons.volume_up,
                                      color: isAnyMuted ? const Color(0xFF666666) : const Color(0xFF2AF598),
                                      size: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      dialogue.character,
                                      style: TextStyle(
                                        color: isAnyMuted ? const Color(0xFF666666) : const Color(0xFF888888),
                                        fontSize: 11,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  // 右侧轨道内容（使用相同的滚动控制器）
                  Expanded(
                    child: _buildTimelineTracks(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 时间轴轨道（只包含轨道内容，不包含时间刻度）
  Widget _buildTimelineTracks() {
    final pixelsPerSecond = 80.0 * _timelineZoom;
    final totalWidth = (_videoDuration * pixelsPerSecond).clamp(800.0, double.infinity);

    return SingleChildScrollView(
      controller: _horizontalScrollController,
      scrollDirection: Axis.horizontal,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (details) async {
          final clickX = details.localPosition.dx;
          final newTime = (clickX / pixelsPerSecond).clamp(0.0, _videoDuration);
          
          if (_isPlaying) {
            await _player.pause();
            for (final player in _audioPlayers.values) {
              await player.pause();
            }
          }
          
          setState(() {
            _currentPlayTime = newTime;
          });
          
          await _player.seek(Duration(milliseconds: (newTime * 1000).toInt()));
        },
        child: SizedBox(
          width: totalWidth,
          height: 300,
          child: Stack(
            clipBehavior: Clip.none,  // ✅ 允许内容溢出边界
            children: [
              // ✅ 背景网格线（垂直线）
              ...List.generate((_videoDuration + 1).toInt(), (i) {
                return Positioned(
                  left: i * pixelsPerSecond,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 1,
                    color: const Color(0xFF2A2A2C),
                  ),
                );
              }),
            
            // ✅ 视频轨道（支持多个片段）
            ...() {
              final List<Widget> videoTracks = [];
              
              for (final segment in _videoSegments) {
                final isSelected = _selectedVideoId == segment.id;
                
                videoTracks.add(
                  Positioned(
                    left: segment.startTime * pixelsPerSecond,
                    top: 0,  // ✅ 从顶部开始，和左侧"视频"标签对齐
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() {
                          _selectedVideoId = segment.id;
                        });
                      },
                      onSecondaryTapDown: (details) {
                        setState(() {
                          _selectedVideoId = segment.id;
                        });
                        _showVideoContextMenu(context, details.globalPosition, segment.id);
                      },
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          final delta = details.delta.dx / pixelsPerSecond;
                          segment.startTime = (segment.startTime + delta).clamp(0.0, _videoDuration - 0.1);
                        });
                      },
                      child: Container(
                        width: segment.duration * pixelsPerSecond,
                        height: 30,
                        decoration: BoxDecoration(
                          color: isSelected 
                              ? const Color(0xFF4A9EFF).withValues(alpha: 0.8)
                              : const Color(0xFF4A9EFF).withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isSelected ? const Color(0xFFFFD700) : const Color(0xFF4A9EFF),
                            width: isSelected ? 3 : 1,
                          ),
                          boxShadow: isSelected ? [
                            BoxShadow(
                              color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ] : null,
                        ),
                        child: const Center(
                          child: Text(
                            '视频',
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }
              
              return videoTracks;
            }(),
            
            // ✅ 多条音频轨道（包括分割后的片段，保持在同一轨道）
            ...() {
              final List<Widget> audioTracks = [];
              
              // 遍历所有音频ID（包括分割后的片段）
              for (final audioId in _audioStartTimes.keys) {
                final audioPath = widget.dialogueAudioMap[audioId];
                if (audioPath == null) continue;
                
                // 获取轨道索引
                final trackIndex = _audioTrackIndex[audioId] ?? 0;
                
                // 找到对应的对话（可能是原始对话或分割片段）
                VoiceDialogue? dialogue;
                try {
                  dialogue = widget.dialogues.firstWhere((d) => d.id == audioId);
                } catch (e) {
                  // 如果找不到（分割片段），使用原始对话的信息
                  final originalId = audioId.split('_split_')[0];
                  try {
                    final originalDialogue = widget.dialogues.firstWhere((d) => d.id == originalId);
                    // 为分割片段创建临时对话对象
                    dialogue = VoiceDialogue(
                      id: audioId,
                      character: originalDialogue.character,
                      dialogue: originalDialogue.dialogue,
                      emotion: originalDialogue.emotion,
                    );
                  } catch (e2) {
                    continue; // 跳过无法找到的音频
                  }
                }
                
                final startTime = _audioStartTimes[audioId] ?? 0.0;
                final duration = _audioDurations[audioId] ?? 3.0;
                // ✅ 调整位置：视频轨道30px + 间距10px = 40px，然后每个音频轨道32px + 间距10px = 42px
                final topPosition = 40.0 + (trackIndex * 42.0);
                final isMuted = _audioMuted[audioId] ?? false;
                final waveform = _audioWaveforms[audioId] ?? [];
                final isSelected = _selectedAudioId == audioId;
                
                // 判断是否是分割片段
                final isSplitSegment = audioId.contains('_split_');
                String displayText = dialogue.character;
                
                // 如果是分割片段，显示对话内容的一部分
                if (isSplitSegment && dialogue.dialogue.isNotEmpty) {
                  // 显示前几个字作为标识
                  final previewLength = dialogue.dialogue.length > 3 ? 3 : dialogue.dialogue.length;
                  displayText = '${dialogue.dialogue.substring(0, previewLength)}...';
                } else if (dialogue.dialogue.isNotEmpty) {
                  // 原始片段也显示前几个字
                  final previewLength = dialogue.dialogue.length > 3 ? 3 : dialogue.dialogue.length;
                  displayText = '${dialogue.dialogue.substring(0, previewLength)}...';
                }
                
                audioTracks.add(
                  Positioned(
                    left: startTime * pixelsPerSecond,
                    top: topPosition,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() {
                          _selectedAudioId = audioId;
                        });
                      },
                      onSecondaryTapDown: (details) {
                        setState(() {
                          _selectedAudioId = audioId;
                        });
                        _showAudioContextMenu(context, details.globalPosition, audioId);
                      },
                      onHorizontalDragStart: (details) {
                        setState(() {
                          _selectedAudioId = audioId;
                          _isDragging = true;
                          _draggingAudioId = audioId;
                        });
                        if (_isPlaying) {
                          _player.pause();
                          for (final player in _audioPlayers.values) {
                            player.pause();
                          }
                        }
                      },
                      onHorizontalDragUpdate: (details) {
                        if (_isDragging && _draggingAudioId == audioId) {
                          setState(() {
                            final delta = details.delta.dx / pixelsPerSecond;
                            final currentStart = _audioStartTimes[audioId] ?? 0.0;
                            final newStartTime = (currentStart + delta).clamp(0.0, _videoDuration - 0.1);
                            _audioStartTimes[audioId] = newStartTime;
                          });
                        }
                      },
                      onHorizontalDragEnd: (details) {
                        setState(() {
                          _isDragging = false;
                          _draggingAudioId = null;
                        });
                      },
                      child: Container(
                        width: duration * pixelsPerSecond,
                        height: 32,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isSelected ? [
                              const Color(0xFFFFD700).withValues(alpha: 0.9),
                              const Color(0xFFFFA500).withValues(alpha: 0.9),
                            ] : isMuted ? [
                              const Color(0xFF666666).withValues(alpha: 0.5),
                              const Color(0xFF444444).withValues(alpha: 0.5),
                            ] : [
                              const Color(0xFF2AF598).withValues(alpha: 0.8),
                              const Color(0xFF009EFD).withValues(alpha: 0.8),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isSelected 
                                ? const Color(0xFFFFD700)
                                : isMuted ? const Color(0xFF666666) : const Color(0xFF2AF598),
                            width: isSelected ? 3 : 2,
                          ),
                          boxShadow: isSelected ? [
                            BoxShadow(
                              color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ] : null,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: Stack(
                            children: [
                              if (waveform.isNotEmpty)
                                CustomPaint(
                                  size: Size(duration * pixelsPerSecond, 32),
                                  painter: RealWaveformPainter(
                                    waveform: waveform,
                                    color: isMuted 
                                        ? Colors.white.withValues(alpha: 0.2)
                                        : Colors.white.withValues(alpha: 0.7),
                                  ),
                                ),
                              Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isMuted ? Icons.volume_off : Icons.music_note,
                                      color: Colors.white,
                                      size: 12,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        displayText,
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
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }
              
              return audioTracks;
            }(),
            
            // 播放头延伸线（向上移动10px，与球下方无缝连接）
            Positioned(
              left: _currentPlayTime * pixelsPerSecond - 1,
              top: -10,  // ✅ 向上移动10px，连接到球的下方
              bottom: 0,
              child: Container(
                width: 2,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B6B),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF6B6B).withValues(alpha: 0.5),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
  void _togglePlayPause() async {
    try {
      if (_isPlaying) {
        await _player.pause();
        // 暂停所有音频
        for (final player in _audioPlayers.values) {
          try {
            await player.pause();
          } catch (e) {
            print('[播放控制] 暂停音频失败: $e');
          }
        }
      } else {
        await _player.play();
        // 播放所有在当前时间点应该播放的音频
        await _syncAudioPlayback();
      }
    } catch (e) {
      print('[播放控制] 错误: $e');
      _logger.error('播放控制失败: $e', module: '视频编辑器');
    }
  }
  
  /// 同步音频播放
  Future<void> _syncAudioPlayback() async {
    try {
      // 遍历所有音频播放器（包括分割后的片段）
      for (final entry in _audioPlayers.entries) {
        final audioId = entry.key;
        final player = entry.value;
        
        final isMuted = _audioMuted[audioId] ?? false;
        final startTime = _audioStartTimes[audioId] ?? 0.0;
        final duration = _audioDurations[audioId] ?? 3.0;
        final endTime = startTime + duration;
        final offset = _audioOffsets[audioId] ?? 0.0;  // 获取音频偏移量
        
        // 如果静音，暂停播放
        if (isMuted) {
          try {
            await player.pause();
          } catch (e) {
            // 忽略
          }
          continue;
        }
        
        // 如果当前时间在音频范围内，播放音频
        if (_currentPlayTime >= startTime && _currentPlayTime < endTime) {
          // 计算在时间轴上的位置
          final timelinePosition = _currentPlayTime - startTime;
          // 加上偏移量，得到在原始音频文件中的位置
          final audioPosition = offset + timelinePosition;
          
          try {
            await player.seek(Duration(milliseconds: (audioPosition * 1000).toInt()));
            await player.resume();
          } catch (e) {
            print('[音频同步] 播放失败 $audioId: $e');
          }
        } else {
          try {
            await player.pause();
          } catch (e) {
            // 忽略暂停错误
          }
        }
      }
    } catch (e) {
      print('[音频同步] 错误: $e');
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

      // ✅ 收集所有未静音的音频轨道
      final audioTracks = <Map<String, dynamic>>[];
      
      for (final entry in _audioStartTimes.entries) {
        final audioId = entry.key;
        final startTime = entry.value;
        final isMuted = _audioMuted[audioId] ?? false;
        final audioPath = widget.dialogueAudioMap[audioId];
        
        // 只添加未静音且有路径的音频
        if (!isMuted && audioPath != null) {
          audioTracks.add({
            'path': audioPath,
            'startTime': startTime,
          });
        }
      }
      
      if (audioTracks.isEmpty) {
        throw Exception('没有可用的音频轨道（所有音频都已静音）');
      }
      
      debugPrint('[预览] 使用 ${audioTracks.length} 个音频轨道');
      
      // 使用FFmpeg快速合成预览（支持多音频）
      final previewPath = await _ffmpegService.mergeVideoWithMultipleAudios(
        videoPath: widget.videoPath,
        audioTracks: audioTracks,
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
  
  /// 显示视频右键菜单
  void _showVideoContextMenu(BuildContext context, Offset position, String videoId) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: const Color(0xFF252629),
      items: [
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.content_cut, color: Color(0xFF2AF598), size: 18),
              SizedBox(width: 8),
              Text('在播放头处分割', style: TextStyle(color: Colors.white)),
            ],
          ),
          onTap: () {
            _splitVideoAtPlayhead(videoId);
          },
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.folder_open, color: Color(0xFF667EEA), size: 18),
              SizedBox(width: 8),
              Text('定位文件', style: TextStyle(color: Colors.white)),
            ],
          ),
          onTap: () {
            _locateFile(widget.videoPath);
          },
        ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.delete, color: Color(0xFFFF6B6B), size: 18),
              SizedBox(width: 8),
              Text('删除', style: TextStyle(color: Colors.white)),
            ],
          ),
          onTap: () {
            setState(() {
              _videoSegments.removeWhere((s) => s.id == videoId);
              if (_selectedVideoId == videoId) {
                _selectedVideoId = null;
              }
            });
            _logger.success('视频片段已删除', module: '视频编辑器');
          },
        ),
      ],
    );
  }
  
  /// 在播放头处分割视频
  void _splitVideoAtPlayhead(String videoId) {
    final segment = _videoSegments.firstWhere((s) => s.id == videoId);
    final startTime = segment.startTime;
    final endTime = startTime + segment.duration;
    
    // 检查播放头是否在视频范围内
    if (_currentPlayTime <= startTime || _currentPlayTime >= endTime) {
      _logger.warning('播放头不在视频范围内', module: '视频编辑器');
      return;
    }
    
    // 计算分割点
    final splitPoint = _currentPlayTime - startTime;
    final firstPartDuration = splitPoint;
    final secondPartDuration = segment.duration - splitPoint;
    
    // 创建新的视频片段ID
    final newVideoId = 'video_${DateTime.now().millisecondsSinceEpoch}';
    
    setState(() {
      // 第一部分：缩短时长
      segment.duration = firstPartDuration;
      
      // 第二部分：新的视频片段
      _videoSegments.add(VideoSegment(
        id: newVideoId,
        startTime: _currentPlayTime,
        duration: secondPartDuration,
      ));
    });
    
    _logger.success('视频已在 ${_currentPlayTime.toStringAsFixed(2)}s 处分割成两部分', module: '视频编辑器');
  }
  
  /// 显示音频右键菜单
  void _showAudioContextMenu(BuildContext context, Offset position, String audioId) {
    final audioPath = widget.dialogueAudioMap[audioId];
    
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: const Color(0xFF252629),
      items: [
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.content_cut, color: Color(0xFF2AF598), size: 18),
              SizedBox(width: 8),
              Text('在播放头处分割', style: TextStyle(color: Colors.white)),
            ],
          ),
          onTap: () {
            _splitAudioAtPlayhead(audioId);
          },
        ),
        if (audioPath != null)
          PopupMenuItem(
            child: const Row(
              children: [
                Icon(Icons.folder_open, color: Color(0xFF667EEA), size: 18),
                SizedBox(width: 8),
                Text('定位文件', style: TextStyle(color: Colors.white)),
              ],
            ),
            onTap: () {
              _locateFile(audioPath);
            },
          ),
        PopupMenuItem(
          child: const Row(
            children: [
              Icon(Icons.delete, color: Color(0xFFFF6B6B), size: 18),
              SizedBox(width: 8),
              Text('删除', style: TextStyle(color: Colors.white)),
            ],
          ),
          onTap: () {
            setState(() {
              _audioStartTimes.remove(audioId);
              _audioDurations.remove(audioId);
              _audioMuted.remove(audioId);
              _audioWaveforms.remove(audioId);
              if (_selectedAudioId == audioId) {
                _selectedAudioId = null;
              }
            });
            _logger.success('音频已删除', module: '视频编辑器');
          },
        ),
      ],
    );
  }
  
  /// 定位文件（在文件管理器中打开并选中文件）
  void _locateFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        _logger.error('文件不存在: $filePath', module: '视频编辑器');
        debugPrint('[定位文件] 文件不存在: $filePath');
        return;
      }
      
      // 获取绝对路径并转换为 Windows 格式（反斜杠）
      final absolutePath = file.absolute.path.replaceAll('/', '\\');
      debugPrint('[定位文件] 原始路径: $filePath');
      debugPrint('[定位文件] 绝对路径: $absolutePath');
      
      // 在 Windows 上使用 explorer /select 命令
      // 注意：路径需要使用反斜杠
      final result = await Process.run(
        'explorer',
        ['/select,', absolutePath],
        runInShell: true,
      );
      
      if (result.exitCode == 0) {
        _logger.success('已定位文件', module: '视频编辑器');
      } else {
        debugPrint('[定位文件] 失败: exitCode=${result.exitCode}');
        debugPrint('[定位文件] stderr: ${result.stderr}');
        _logger.error('定位文件失败', module: '视频编辑器');
      }
    } catch (e, stack) {
      debugPrint('[定位文件] 异常: $e');
      debugPrint('[定位文件] 堆栈: $stack');
      _logger.error('定位文件失败: $e', module: '视频编辑器');
    }
  }
  
  /// 在播放头处分割音频
  void _splitAudioAtPlayhead(String audioId) {
    final startTime = _audioStartTimes[audioId] ?? 0.0;
    final duration = _audioDurations[audioId] ?? 3.0;
    final endTime = startTime + duration;
    
    // 检查播放头是否在音频范围内
    if (_currentPlayTime <= startTime || _currentPlayTime >= endTime) {
      _logger.warning('播放头不在音频范围内', module: '视频编辑器');
      return;
    }
    
    // 计算分割点
    final splitPoint = _currentPlayTime - startTime;
    final firstPartDuration = splitPoint;
    final secondPartDuration = duration - splitPoint;
    
    // 找到原始对话
    final originalDialogue = widget.dialogues.firstWhere((d) => d.id == audioId);
    final audioPath = widget.dialogueAudioMap[audioId];
    final waveform = _audioWaveforms[audioId] ?? [];
    final originalTrackIndex = _audioTrackIndex[audioId] ?? 0;
    final originalOffset = _audioOffsets[audioId] ?? 0.0;  // 获取原始偏移量
    
    // 创建第二部分的新ID
    final newAudioId = '${audioId}_split_${DateTime.now().millisecondsSinceEpoch}';
    
    // 计算分割位置（字符）
    final totalChars = originalDialogue.dialogue.length;
    final splitCharIndex = (totalChars * (splitPoint / duration)).round();
    final firstPartText = originalDialogue.dialogue.substring(0, splitCharIndex);
    
    setState(() {
      // 第一部分：保持原位置，缩短时长，更新文字
      _audioDurations[audioId] = firstPartDuration;
      
      // 更新原始对话的文字（只保留前半部分）
      final updatedDialogue = VoiceDialogue(
        id: audioId,
        character: originalDialogue.character,
        dialogue: firstPartText.isNotEmpty ? firstPartText : originalDialogue.dialogue,
        emotion: originalDialogue.emotion,
      );
      final originalIndex = widget.dialogues.indexWhere((d) => d.id == audioId);
      if (originalIndex != -1) {
        widget.dialogues[originalIndex] = updatedDialogue;
      }
      
      // 第二部分：新的音频片段，保持在同一轨道
      _audioStartTimes[newAudioId] = _currentPlayTime;
      _audioDurations[newAudioId] = secondPartDuration;
      _audioMuted[newAudioId] = _audioMuted[audioId] ?? false;
      _audioTrackIndex[newAudioId] = originalTrackIndex;
      _audioOffsets[newAudioId] = originalOffset + splitPoint;  // ✅ 设置偏移量，从分割点开始播放
      
      // 分割波形数据
      if (waveform.isNotEmpty) {
        final splitIndex = (waveform.length * (splitPoint / duration)).round();
        _audioWaveforms[audioId] = waveform.sublist(0, splitIndex);
        _audioWaveforms[newAudioId] = waveform.sublist(splitIndex);
      }
      
      // 为新片段创建音频播放器
      if (audioPath != null) {
        _audioPlayers[newAudioId] = AudioPlayer();
        _audioPlayers[newAudioId]!.setSource(DeviceFileSource(audioPath));
        _audioPlayers[newAudioId]!.setVolume(_volume / 100.0);  // ✅ 设置音量
        _audioPlayers[newAudioId]!.setReleaseMode(ReleaseMode.stop);
      }
      
      // 将新片段添加到对话映射中（使用相同的音频文件）
      if (audioPath != null) {
        widget.dialogueAudioMap[newAudioId] = audioPath;
      }
      
      // 注意：不添加到 widget.dialogues，因为这只是分割片段，不是新对话
    });
    
    _logger.success('音频已在 ${_currentPlayTime.toStringAsFixed(2)}s 处分割成两部分', module: '视频编辑器');
  }
}

/// 真实波形绘制器（像剪映那样）
class RealWaveformPainter extends CustomPainter {
  final List<double> waveform;
  final Color color;

  RealWaveformPainter({
    required this.waveform,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final barWidth = size.width / waveform.length;
    final centerY = size.height / 2;

    for (int i = 0; i < waveform.length; i++) {
      final amplitude = waveform[i];
      final barHeight = amplitude * size.height * 0.95;
      
      // 绘制细长的竖条（从中心向上下延伸）
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          i * barWidth + barWidth * 0.05,
          centerY - barHeight / 2,
          barWidth * 0.9,
          barHeight.clamp(1.0, size.height),
        ),
        const Radius.circular(0.3),
      );
      
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant RealWaveformPainter oldDelegate) {
    return oldDelegate.waveform != waveform || oldDelegate.color != color;
  }
}

/// 视频片段数据模型
class VideoSegment {
  final String id;
  double startTime;
  double duration;

  VideoSegment({
    required this.id,
    required this.startTime,
    required this.duration,
  });
}
