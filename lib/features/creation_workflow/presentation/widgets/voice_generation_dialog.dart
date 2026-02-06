import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:xinghe_new/core/logger/log_manager.dart';
import 'package:xinghe_new/services/api/api_repository.dart';
import 'package:xinghe_new/services/api/providers/indextts_service.dart';
import 'package:xinghe_new/services/ffmpeg_service.dart';
import 'package:xinghe_new/features/home/domain/voice_asset.dart';
import 'package:path/path.dart' as path;
import '../production_space_page.dart';
import 'dart:convert';
import 'dart:io';

/// 语音生成向导对话框
/// 三步流程：1.AI识别对话 → 2.确认对话 → 3.生成配音
class VoiceGenerationDialog extends StatefulWidget {
  final StoryboardRow storyboard;
  final int storyboardIndex;
  final Function(StoryboardRow) onComplete;

  const VoiceGenerationDialog({
    super.key,
    required this.storyboard,
    required this.storyboardIndex,
    required this.onComplete,
  });

  @override
  State<VoiceGenerationDialog> createState() => _VoiceGenerationDialogState();
}

class _VoiceGenerationDialogState extends State<VoiceGenerationDialog> {
  int _currentStep = 0;
  final LogManager _logger = LogManager();
  final ApiRepository _apiRepository = ApiRepository();
  final FFmpegService _ffmpegService = FFmpegService();
  
  // 步骤1：识别的对话
  List<VoiceDialogue> _dialogues = [];
  bool _isParsingScript = false;
  
  // 步骤2：配音生成
  bool _isGenerating = false;
  bool _isMerging = false;  // 是否正在合成
  String? _generatedAudioPath;
  double _voiceStartTime = 0.0;
  double _videoDuration = 5.0;  // 默认视频时长
  bool _isLoadingDuration = false;
  
  // 配置
  bool _voiceEnabled = false;
  String _voiceServiceUrl = 'http://127.0.0.1:7860';
  String _audioSavePath = '';
  String _indexttsPath = 'D:\\Index-TTS2_XH';
  double _defaultEmotionAlpha = 0.6;
  
  // 语音库
  List<VoiceAsset> _availableVoices = [];
  VoiceAsset? _selectedVoice;  // 选中的角色声音

  AudioPlayer? _audioPlayer;
  bool _useSystemPlayer = false;

  @override
  void initState() {
    super.initState();
    _loadVoiceConfig();
    _loadVoiceLibrary();
    _initDialogues();
    _estimateVideoDuration();
  }

  @override
  void dispose() {
    _audioPlayer?.dispose();
    super.dispose();
  }

  /// 应用内播放音频；插件不可用时回退到系统播放器
  Future<void> _playInApp(String path) async {
    if (_useSystemPlayer) {
      try {
        await Process.run('cmd', ['/c', 'start', '', path]);
      } catch (_) {}
      return;
    }
    try {
      _audioPlayer ??= AudioPlayer();
      await _audioPlayer!.stop();
      await _audioPlayer!.play(DeviceFileSource(path));
    } on MissingPluginException catch (_) {
      _useSystemPlayer = true;
      try {
        await Process.run('cmd', ['/c', 'start', '', path]);
      } catch (_) {}
    } catch (e) {
      _logger.error('应用内播放失败: $e', module: '语音生成');
    }
  }

  /// 加载语音配置
  Future<void> _loadVoiceConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _voiceEnabled = prefs.getBool('voice_enabled') ?? false;
        _voiceServiceUrl = prefs.getString('voice_service_url') ?? 'http://127.0.0.1:7860';
        _audioSavePath = prefs.getString('audio_save_path') ?? '';
        _indexttsPath = prefs.getString('indextts_path') ?? 'D:\\Index-TTS2_XH';
        _defaultEmotionAlpha = prefs.getDouble('default_emotion_alpha') ?? 0.6;
      });
    } catch (e) {
      _logger.error('加载语音配置失败: $e', module: '语音生成');
    }
  }

  /// 加载语音库
  Future<void> _loadVoiceLibrary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final voicesJson = prefs.getString('voice_library_data');
      
      if (voicesJson != null && voicesJson.isNotEmpty) {
        final voicesList = (jsonDecode(voicesJson) as List)
            .map((item) => VoiceAsset.fromJson(item as Map<String, dynamic>))
            .toList();
        
        setState(() {
          _availableVoices = voicesList;
        });
        
        _logger.info('加载语音库', module: '语音生成', extra: {
          'count': voicesList.length,
        });
      }
    } catch (e) {
      _logger.error('加载语音库失败: $e', module: '语音生成');
    }
  }

  /// 初始化对话列表
  void _initDialogues() {
    if (widget.storyboard.voiceDialogues.isNotEmpty) {
      _dialogues = List.from(widget.storyboard.voiceDialogues);
    }
  }

  /// 获取视频时长
  Future<void> _estimateVideoDuration() async {
    if (widget.storyboard.videoUrls.isEmpty) {
      setState(() {
        _videoDuration = 5.0;  // 默认5秒
      });
      return;
    }
    
    setState(() => _isLoadingDuration = true);
    
    try {
      final videoUrl = widget.storyboard.videoUrls.first;
      
      // 检查是否是本地文件
      if (videoUrl.startsWith('http://') || videoUrl.startsWith('https://')) {
        // 在线视频，使用默认时长
        setState(() {
          _videoDuration = 5.0;
          _isLoadingDuration = false;
        });
        return;
      }
      
      // 本地视频文件，获取实际时长
      final duration = await _ffmpegService.getVideoDuration(videoUrl);
      
      setState(() {
        _videoDuration = duration ?? 5.0;
        _isLoadingDuration = false;
      });
      
      _logger.info('获取视频时长', module: '语音生成', extra: {
        'duration': _videoDuration,
      });
    } catch (e) {
      _logger.error('获取视频时长失败: $e', module: '语音生成');
      setState(() {
        _videoDuration = 5.0;
        _isLoadingDuration = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 900,
        height: 700,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E20),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF3A3A3C), width: 2),
        ),
        child: Column(
          children: [
            _buildHeader(),
            _buildStepIndicator(),
            Expanded(child: _buildCurrentStep()),
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
            child: const Icon(Icons.mic, color: Color(0xFF667EEA), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '分镜 ${widget.storyboardIndex + 1} - 配音生成向导',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getStepDescription(),
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

  String _getStepDescription() {
    switch (_currentStep) {
      case 0:
        return '识别剧本中的对话内容';
      case 1:
        return '确认对话列表并编辑';
      case 2:
        return '生成配音并调整时间轴';
      default:
        return '';
    }
  }

  /// 步骤指示器
  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 40),
      child: Row(
        children: [
          _buildStepItem(0, '识别对话', Icons.search),
          Expanded(child: _buildStepLine(0)),
          _buildStepItem(1, '确认编辑', Icons.edit),
          Expanded(child: _buildStepLine(1)),
          _buildStepItem(2, '生成配音', Icons.mic),
        ],
      ),
    );
  }

  Widget _buildStepItem(int step, String label, IconData icon) {
    final isActive = _currentStep == step;
    final isCompleted = _currentStep > step;

    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isCompleted
                ? const Color(0xFF2AF598)
                : isActive
                    ? const Color(0xFF667EEA)
                    : const Color(0xFF3A3A3C),
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive ? const Color(0xFF667EEA) : Colors.transparent,
              width: 2,
            ),
          ),
          child: Icon(
            isCompleted ? Icons.check : icon,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: isActive ? const Color(0xFF667EEA) : const Color(0xFF888888),
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine(int step) {
    final isCompleted = _currentStep > step;
    return Container(
      height: 2,
      margin: const EdgeInsets.only(bottom: 30),
      color: isCompleted ? const Color(0xFF2AF598) : const Color(0xFF3A3A3C),
    );
  }

  /// 当前步骤内容
  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildStep1_ParseScript();
      case 1:
        return _buildStep2_ConfirmDialogues();
      case 2:
        return _buildStep3_GenerateVoice();
      default:
        return Container();
    }
  }

  /// 步骤1：识别对话
  Widget _buildStep1_ParseScript() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📝 当前分镜剧本内容',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF252629),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF3A3A3C)),
              ),
              child: SingleChildScrollView(
                child: Text(
                  widget.storyboard.scriptSegment,
                  style: const TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontSize: 14,
                    height: 1.8,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '🤖 智能提取对话',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _isParsingScript ? null : _parseScriptWithAI,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isParsingScript)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          else
                            const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                          const SizedBox(width: 12),
                          Text(
                            _isParsingScript ? 'AI识别中...' : 'AI自动识别对话',
                            style: const TextStyle(
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
              ),
              const SizedBox(width: 16),
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _manualAddDialogue,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF667EEA), width: 2),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.edit, color: Color(0xFF667EEA), size: 20),
                          SizedBox(width: 12),
                          Text(
                            '手动输入对话',
                            style: TextStyle(
                              color: Color(0xFF667EEA),
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF667EEA).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF667EEA).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFF667EEA), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '💡 提示：AI将自动识别剧本中的角色对话，包括角色名称、情感和台词内容',
                    style: TextStyle(
                      color: const Color(0xFF667EEA).withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 步骤2：确认对话列表
  Widget _buildStep2_ConfirmDialogues() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '✅ 识别到 ${_dialogues.length} 条对话',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _manualAddDialogue,
                icon: const Icon(Icons.add, color: Color(0xFF667EEA)),
                label: const Text('添加对话', style: TextStyle(color: Color(0xFF667EEA))),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // ✅ 语音库状态提示
          if (_availableVoices.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '⚠️ 语音库为空，无法继续生成配音\n请先在【素材库 > 语音库】中上传角色声音样本',
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          
          const SizedBox(height: 8),
          Expanded(
            child: _dialogues.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.chat_bubble_outline, color: Color(0xFF666666), size: 64),
                        const SizedBox(height: 16),
                        const Text(
                          '暂无对话',
                          style: TextStyle(color: Color(0xFF666666), fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _manualAddDialogue,
                          child: const Text('点击添加对话', style: TextStyle(color: Color(0xFF667EEA))),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _dialogues.length,
                    itemBuilder: (context, index) => _buildDialogueItem(index),
                  ),
          ),
        ],
      ),
    );
  }

  /// 对话项
  Widget _buildDialogueItem(int index) {
    final dialogue = _dialogues[index];
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF252629),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3A3C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '对话 ${index + 1}',
                  style: const TextStyle(
                    color: Color(0xFF667EEA),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.edit, color: Color(0xFF888888), size: 18),
                onPressed: () => _editDialogue(index),
                tooltip: '编辑',
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                onPressed: () => _deleteDialogue(index),
                tooltip: '删除',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildInfoItem('角色', dialogue.character, Icons.person),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildInfoItem('情感', dialogue.emotion, Icons.sentiment_satisfied),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoItem('台词', dialogue.dialogue, Icons.chat_bubble),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF888888), size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF666666),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFFCCCCCC),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 步骤3：生成配音
  Widget _buildStep3_GenerateVoice() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🎵 配音生成',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          
          // 对话信息显示
          if (_dialogues.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF252629),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF3A3A3C)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person, color: Color(0xFF667EEA), size: 16),
                      const SizedBox(width: 8),
                      Text(
                        '角色: ${_dialogues.first.character}',
                        style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 13),
                      ),
                      const SizedBox(width: 24),
                      const Icon(Icons.sentiment_satisfied, color: Color(0xFF667EEA), size: 16),
                      const SizedBox(width: 8),
                      Text(
                        '情感: ${_dialogues.first.emotion}',
                        style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '台词: ${_dialogues.first.dialogue}',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
          
          const SizedBox(height: 24),
          
          // ✅ 选择角色声音
          const Text(
            '🎤 选择角色声音',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          
          if (_availableVoices.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '⚠️ 语音库为空\n\n请先在【素材库 > 语音库】中上传角色声音样本',
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF252629),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF3A3A3C)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<VoiceAsset>(
                      value: _selectedVoice,
                      hint: const Text('请选择角色声音', style: TextStyle(color: Color(0xFF888888))),
                      isExpanded: true,
                      dropdownColor: const Color(0xFF252629),
                      icon: const Icon(Icons.unfold_more, color: Color(0xFF888888), size: 20),
                      items: _availableVoices.map((voice) {
                        return DropdownMenuItem<VoiceAsset>(
                          value: voice,
                          child: Row(
                            children: [
                              const Icon(Icons.mic, color: Color(0xFF667EEA), size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  voice.name,
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.play_arrow, color: Color(0xFF2AF598), size: 18),
                                onPressed: () => _previewVoiceSample(voice),
                                tooltip: '试听',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (voice) {
                        setState(() => _selectedVoice = voice);
                      },
                    ),
                  ),
                ),
                
                // ✅ 显示选中声音的情感控制配置
                if (_selectedVoice != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF667EEA).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF667EEA).withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline, color: Color(0xFF667EEA), size: 16),
                            const SizedBox(width: 8),
                            const Text(
                              '将使用以下情感控制配置：',
                              style: TextStyle(color: Color(0xFF667EEA), fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• 模式: ${_selectedVoice!.emotionControlMode}',
                          style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 11),
                        ),
                        if (_selectedVoice!.emotionControlMode != '与语音参考相同')
                          Text(
                            '• 情感权重: ${_selectedVoice!.emotionAlpha.toStringAsFixed(2)}',
                            style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 11),
                          ),
                        if (_selectedVoice!.useRandomSampling)
                          const Text(
                            '• 随机情感采样: 已启用',
                            style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          
          const SizedBox(height: 24),
          
          // 生成按钮
          if (_generatedAudioPath == null)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _isGenerating ? null : _generateVoice,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2AF598), Color(0xFF009EFD)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isGenerating)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      else
                        const Icon(Icons.mic, color: Colors.white, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        _isGenerating ? '生成中...' : '🎤 生成配音',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF2AF598), size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      '✅ 配音生成完成',
                      style: TextStyle(
                        color: Color(0xFF2AF598),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        // 试听配音
                        _playGeneratedAudio();
                      },
                      icon: const Icon(Icons.play_arrow, color: Color(0xFF667EEA)),
                      label: const Text('试听配音', style: TextStyle(color: Color(0xFF667EEA))),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // 时间轴对齐
                const Text(
                  '⏱️ 音视频时间轴对齐',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF252629),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF3A3A3C)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Text('📹 视频时长:', style: TextStyle(color: Color(0xFF888888), fontSize: 13)),
                          const SizedBox(width: 8),
                          if (_isLoadingDuration)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Color(0xFF667EEA)),
                              ),
                            )
                          else
                            Text('${_videoDuration.toStringAsFixed(1)} 秒', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Text('配音起始时间:', style: TextStyle(color: Color(0xFF888888), fontSize: 13)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Slider(
                              value: _voiceStartTime,
                              min: 0.0,
                              max: _videoDuration,
                              divisions: (_videoDuration * 10).toInt(),
                              activeColor: const Color(0xFF667EEA),
                              inactiveColor: const Color(0xFF3A3A3C),
                              onChanged: (value) {
                                setState(() => _voiceStartTime = value);
                              },
                            ),
                          ),
                          Container(
                            width: 80,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3A3A3C),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${_voiceStartTime.toStringAsFixed(1)} 秒',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // 时间轴可视化
                      _buildTimeline(),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // 预览按钮
                MouseRegion(
                  cursor: _isMerging ? SystemMouseCursors.wait : SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _isMerging ? null : _previewMergedVideo,
                    child: Opacity(
                      opacity: _isMerging ? 0.6 : 1.0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF667EEA), width: 2),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_isMerging)
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(Color(0xFF667EEA)),
                                ),
                              )
                            else
                              const Icon(Icons.play_circle_outline, color: Color(0xFF667EEA), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              _isMerging ? '合成中...' : '▶️ 预览合成效果',
                              style: const TextStyle(
                                color: Color(0xFF667EEA),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
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

  /// 时间轴可视化
  Widget _buildTimeline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('时间轴预览:', style: TextStyle(color: Color(0xFF888888), fontSize: 12)),
        const SizedBox(height: 12),
        SizedBox(
          height: 60,
          child: Stack(
            children: [
              // 视频轨道
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('视频', style: TextStyle(color: Color(0xFF666666), fontSize: 10)),
                    const SizedBox(height: 4),
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A9EFF).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              // 音频轨道
              Positioned(
                left: 0,
                right: 0,
                top: 30,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('音频', style: TextStyle(color: Color(0xFF666666), fontSize: 10)),
                    const SizedBox(height: 4),
                    Stack(
                      children: [
                        // 背景轨道
                        Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: const Color(0xFF3A3A3C),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        // 音频片段
                        if (_voiceStartTime < _videoDuration)
                          Positioned(
                            left: (_voiceStartTime / _videoDuration) * MediaQuery.of(context).size.width * 0.6,
                            child: Container(
                              width: (((_videoDuration - _voiceStartTime) / _videoDuration) * MediaQuery.of(context).size.width * 0.6).clamp(20, double.infinity),
                              height: 8,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF2AF598), Color(0xFF009EFD)],
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 时间刻度
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            (_videoDuration + 1).toInt(),
            (i) => Text(
              '${i}s',
              style: const TextStyle(color: Color(0xFF666666), fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }

  /// 底部按钮栏
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
          if (_currentStep > 0)
            TextButton.icon(
              onPressed: () => setState(() => _currentStep--),
              icon: const Icon(Icons.arrow_back, color: Color(0xFF888888)),
              label: const Text('上一步', style: TextStyle(color: Color(0xFF888888))),
            ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Color(0xFF888888))),
          ),
          const SizedBox(width: 12),
          if (_currentStep < 2)
            ElevatedButton.icon(
              onPressed: _canGoNext() ? () => setState(() => _currentStep++) : null,
              icon: const Icon(Icons.arrow_forward, color: Colors.white),
              label: const Text('下一步', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF667EEA),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: _generatedAudioPath != null ? _saveAndComplete : null,
              icon: const Icon(Icons.check, color: Colors.white),
              label: const Text('完成并保存', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2AF598),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
        ],
      ),
    );
  }

  bool _canGoNext() {
    switch (_currentStep) {
      case 0:
        return _dialogues.isNotEmpty;  // 至少有一条对话才能进入下一步
      case 1:
        return _dialogues.isNotEmpty && _availableVoices.isNotEmpty;  // 有对话且有可用声音
      default:
        return false;
    }
  }

  // ============ 业务逻辑方法 ============

  /// AI识别剧本对话
  Future<void> _parseScriptWithAI() async {
    if (!_voiceEnabled) {
      _showErrorDialog('语音合成功能未启用', '请先在设置中启用语音合成功能');
      return;
    }

    setState(() => _isParsingScript = true);

    try {
      // 获取LLM配置
      final prefs = await SharedPreferences.getInstance();
      final llmProvider = prefs.getString('llm_provider') ?? 'openai';
      
      _logger.info('开始AI识别对话', module: '语音生成', extra: {
        'scriptLength': widget.storyboard.scriptSegment.length,
        'llmProvider': llmProvider,
      });

      final prompt = '''请从以下剧本片段中提取所有角色对话，输出JSON格式。

剧本内容：
${widget.storyboard.scriptSegment}

输出格式（严格遵守）：
[
  {
    "character": "角色名",
    "emotion": "情感描述",
    "dialogue": "台词内容"
  }
]

规则：
1. 只提取有引号""或「」的直接对话
2. 角色名通常在冒号前，如"小明："
3. 情感标注通常在括号内，如"(惊讶)"，如果没有则推测合适的情感
4. 忽略所有场景、镜头、动作描述
5. 如果没有对话，返回空数组 []
6. 只输出JSON，不要其他文字

现在开始提取：''';

      final messages = [
        {'role': 'user', 'content': prompt}
      ];

      _apiRepository.clearCache();
      final response = await _apiRepository.generateTextWithMessages(
        provider: llmProvider,
        messages: messages,
        parameters: {'temperature': 0.3, 'max_tokens': 1000},
      );

      if (response.isSuccess && response.data != null) {
        final text = response.data!.text.trim();
        
        // 提取JSON（可能包裹在```json```中）
        String jsonText = text;
        if (text.contains('```json')) {
          final match = RegExp(r'```json\s*(.*?)\s*```', dotAll: true).firstMatch(text);
          if (match != null) {
            jsonText = match.group(1)!;
          }
        } else if (text.contains('```')) {
          final match = RegExp(r'```\s*(.*?)\s*```', dotAll: true).firstMatch(text);
          if (match != null) {
            jsonText = match.group(1)!;
          }
        }
        
        final jsonData = jsonDecode(jsonText) as List;
        
        final dialogues = jsonData.map((item) {
          return VoiceDialogue(
            id: DateTime.now().millisecondsSinceEpoch.toString() + '_' + jsonData.indexOf(item).toString(),
            character: item['character'] ?? '未知',
            emotion: item['emotion'] ?? '平静',
            dialogue: item['dialogue'] ?? '',
          );
        }).where((d) => d.dialogue.isNotEmpty).toList();

        setState(() {
          _dialogues = dialogues;
          _isParsingScript = false;
        });

        _logger.success('AI识别对话完成', module: '语音生成', extra: {
          'count': dialogues.length,
        });

        if (dialogues.isEmpty) {
          _showErrorDialog('未识别到对话', '剧本中可能没有角色对话，您可以手动添加');
        } else {
          // 自动进入下一步
          setState(() => _currentStep = 1);
        }
      } else {
        throw Exception(response.error ?? 'AI识别失败');
      }
    } catch (e) {
      _logger.error('AI识别对话失败: $e', module: '语音生成');
      setState(() => _isParsingScript = false);
      _showErrorDialog('识别失败', '错误: $e\n\n请检查LLM配置或尝试手动添加对话');
    }
  }

  /// 手动添加对话
  void _manualAddDialogue() {
    final characterController = TextEditingController();
    final emotionController = TextEditingController(text: '平静');
    final dialogueController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        title: const Text('添加对话', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: characterController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '角色名称',
                  labelStyle: TextStyle(color: Color(0xFF888888)),
                  hintText: '例如: 小明',
                  hintStyle: TextStyle(color: Color(0xFF666666)),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3A3A3C)),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF667EEA)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emotionController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '情感',
                  labelStyle: TextStyle(color: Color(0xFF888888)),
                  hintText: '例如: 开心、悲伤、惊讶',
                  hintStyle: TextStyle(color: Color(0xFF666666)),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3A3A3C)),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF667EEA)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: dialogueController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '台词内容',
                  labelStyle: TextStyle(color: Color(0xFF888888)),
                  hintText: '输入角色的台词...',
                  hintStyle: TextStyle(color: Color(0xFF666666)),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3A3A3C)),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF667EEA)),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Color(0xFF888888))),
          ),
          ElevatedButton(
            onPressed: () {
              if (characterController.text.isNotEmpty && dialogueController.text.isNotEmpty) {
                final newDialogue = VoiceDialogue(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  character: characterController.text.trim(),
                  emotion: emotionController.text.trim(),
                  dialogue: dialogueController.text.trim(),
                );
                
                setState(() {
                  _dialogues.add(newDialogue);
                });
                
                Navigator.pop(context);
                
                // 如果在步骤1，自动进入步骤2
                if (_currentStep == 0) {
                  setState(() => _currentStep = 1);
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF667EEA)),
            child: const Text('添加', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// 编辑对话
  void _editDialogue(int index) {
    final dialogue = _dialogues[index];
    final characterController = TextEditingController(text: dialogue.character);
    final emotionController = TextEditingController(text: dialogue.emotion);
    final dialogueController = TextEditingController(text: dialogue.dialogue);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        title: const Text('编辑对话', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: characterController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '角色名称',
                  labelStyle: TextStyle(color: Color(0xFF888888)),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3A3A3C)),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF667EEA)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emotionController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '情感',
                  labelStyle: TextStyle(color: Color(0xFF888888)),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3A3A3C)),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF667EEA)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: dialogueController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '台词内容',
                  labelStyle: TextStyle(color: Color(0xFF888888)),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3A3A3C)),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF667EEA)),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: Color(0xFF888888))),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _dialogues[index] = dialogue.copyWith(
                  character: characterController.text.trim(),
                  emotion: emotionController.text.trim(),
                  dialogue: dialogueController.text.trim(),
                );
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF667EEA)),
            child: const Text('保存', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// 删除对话
  void _deleteDialogue(int index) {
    setState(() {
      _dialogues.removeAt(index);
    });
  }

  /// 试听声音样本（应用内播放）
  Future<void> _previewVoiceSample(VoiceAsset voice) async {
    try {
      final audioFile = File(voice.audioPath);
      if (await audioFile.exists()) {
        await _playInApp(voice.audioPath);
        _logger.info('试听声音样本', module: '语音生成', extra: {'name': voice.name});
      }
    } catch (e) {
      _logger.error('试听失败: $e', module: '语音生成');
    }
  }

  /// 生成配音
  Future<void> _generateVoice() async {
    if (_dialogues.isEmpty) {
      _showErrorDialog('没有对话', '请先添加至少一条对话');
      return;
    }

    if (!_voiceEnabled) {
      _showErrorDialog('功能未启用', '请在【设置 > API设置 > 语音合成】中启用语音合成功能');
      return;
    }

    if (_selectedVoice == null) {
      _showErrorDialog('未选择声音', '请先选择角色的声音样本');
      return;
    }

    // 验证声音文件存在
    final voiceFile = File(_selectedVoice!.audioPath);
    if (!await voiceFile.exists()) {
      _showErrorDialog('声音文件不存在', '路径: ${_selectedVoice!.audioPath}\n\n请检查文件是否被移动或删除');
      return;
    }

    // ✅ 先测试服务连接
    final ttsService = IndexTTSService(
      baseUrl: _voiceServiceUrl,
      indexttsPath: _indexttsPath,
    );
    final isConnected = await ttsService.testConnection();
    
    if (!isConnected) {
      _showErrorDialog(
        'IndexTTS 服务未连接',
        '无法连接到 IndexTTS 服务\n\n'
        '服务地址: $_voiceServiceUrl\n\n'
        '请确保：\n'
        '1. IndexTTS 已安装\n'
        '2. 已运行命令: uv run webui.py\n'
        '3. 服务正常启动在 http://127.0.0.1:7860\n'
        '4. 防火墙未阻止连接\n\n'
        '💡 提示：可以在浏览器访问该地址测试服务是否正常',
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      // 合并所有对话的台词
      final fullText = _dialogues.map((d) => d.dialogue).join(' ');
      
      _logger.info('开始生成配音', module: '语音生成', extra: {
        'text': fullText,
        'dialogueCount': _dialogues.length,
        'character': _selectedVoice!.name,
        'emotion': _dialogues.first.emotion,
      });

      // 创建 IndexTTS 服务
      final ttsService = IndexTTSService(
        baseUrl: _voiceServiceUrl,
        indexttsPath: _indexttsPath,
      );
      
      // 生成输出路径
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputDir = _audioSavePath.isNotEmpty 
          ? _audioSavePath 
          : Directory.systemTemp.path;
      final outputPath = '$outputDir/voice_${widget.storyboard.id}_$timestamp.wav';

      // ✅ 根据语音资产的情感控制配置调用 IndexTTS
      String? audioPath;
      
      switch (_selectedVoice!.emotionControlMode) {
        case '与语音参考相同':
          audioPath = await ttsService.synthesize(
            text: fullText,
            voicePromptPath: _selectedVoice!.audioPath,
            outputPath: outputPath,
            useRandom: _selectedVoice!.useRandomSampling,
          );
          break;
          
        case '使用情感参考音频':
          if (_selectedVoice!.emotionAudioPath != null) {
            audioPath = await ttsService.synthesize(
              text: fullText,
              voicePromptPath: _selectedVoice!.audioPath,
              emotionPromptPath: _selectedVoice!.emotionAudioPath,
              emotionAlpha: _selectedVoice!.emotionAlpha,
              outputPath: outputPath,
              useRandom: _selectedVoice!.useRandomSampling,
            );
          } else {
            throw Exception('情感参考音频未设置');
          }
          break;
          
        case '使用情感向量':
          audioPath = await ttsService.synthesizeWithEmotionVector(
            text: fullText,
            voicePromptPath: _selectedVoice!.audioPath,
            emotionVector: _selectedVoice!.emotionVector,
            outputPath: outputPath,
            useRandom: _selectedVoice!.useRandomSampling,
          );
          break;
          
        case '使用文本描述':
        default:
          // 使用对话的情感 + 语音资产的文本情感（如果有）
          final emotionDescription = _selectedVoice!.emotionText.isNotEmpty 
              ? _selectedVoice!.emotionText 
              : _dialogues.first.emotion;
          
          audioPath = await ttsService.synthesizeWithEmotionText(
            text: fullText,
            voicePromptPath: _selectedVoice!.audioPath,
            emotionText: emotionDescription,
            useEmotionText: true,
            emotionAlpha: _selectedVoice!.emotionAlpha,
            outputPath: outputPath,
            useRandom: _selectedVoice!.useRandomSampling,
          );
          break;
      }

      if (audioPath != null) {
        setState(() {
          _generatedAudioPath = audioPath;
          _isGenerating = false;
        });

        _logger.success('配音生成完成', module: '语音生成', extra: {
          'path': audioPath,
          'size': '${(await File(audioPath).length() / 1024).toStringAsFixed(2)} KB',
        });
      } else {
        throw Exception('IndexTTS 返回空结果');
      }
    } catch (e) {
      _logger.error('生成配音失败: $e', module: '语音生成');
      setState(() => _isGenerating = false);
      _showErrorDialog('生成失败', '错误: $e\n\n请检查：\n1. IndexTTS 服务是否正常运行\n2. 服务地址是否正确\n3. 声音样本文件是否有效');
    }
  }

  /// 播放生成的配音（应用内播放）
  Future<void> _playGeneratedAudio() async {
    if (_generatedAudioPath == null) return;
    await _playInApp(_generatedAudioPath!);
  }

  /// 预览合成效果
  Future<void> _previewMergedVideo() async {
    if (_generatedAudioPath == null) {
      _showErrorDialog('未生成配音', '请先生成配音');
      return;
    }

    if (widget.storyboard.videoUrls.isEmpty) {
      _showErrorDialog('没有视频', '此分镜还没有生成视频');
      return;
    }

    final videoUrl = widget.storyboard.videoUrls.first;
    
    // 检查是否是本地文件
    if (videoUrl.startsWith('http://') || videoUrl.startsWith('https://')) {
      _showErrorDialog('不支持在线视频', '预览功能仅支持本地视频文件\n\n请先下载视频到本地');
      return;
    }

    setState(() => _isMerging = true);

    try {
      _logger.info('开始预览合成', module: '语音生成', extra: {
        'videoPath': videoUrl,
        'audioPath': _generatedAudioPath,
        'startTime': _voiceStartTime,
      });

      // 使用 FFmpeg 快速生成预览
      final previewPath = await _ffmpegService.mergeVideoAudioWithTiming(
        videoPath: videoUrl,
        audioPath: _generatedAudioPath!,
        audioStartTime: _voiceStartTime,
        isPreview: true,  // 预览模式（快速，低质量）
      );

      setState(() => _isMerging = false);

      if (previewPath != null) {
        _logger.success('预览生成完成', module: '语音生成', extra: {
          'path': previewPath,
        });

        // 自动播放预览
        await Process.run('cmd', ['/c', 'start', '', previewPath]);
        
        _showSuccessDialog(
          '预览已生成',
          '预览视频已在默认播放器中打开\n\n'
          '✓ 视频时长: ${_videoDuration.toStringAsFixed(1)}秒\n'
          '✓ 配音起始: ${_voiceStartTime.toStringAsFixed(1)}秒\n\n'
          '如果效果满意，点击"完成并保存"将生成高质量版本',
        );
      } else {
        throw Exception('FFmpeg 返回空结果');
      }
    } catch (e) {
      _logger.error('预览合成失败: $e', module: '语音生成');
      setState(() => _isMerging = false);
      _showErrorDialog('预览失败', '错误: $e\n\n请确保 FFmpeg 已正确安装');
    }
  }

  /// 保存并完成
  Future<void> _saveAndComplete() async {
    if (_generatedAudioPath == null) return;

    // 如果有视频，询问是否合成
    if (widget.storyboard.videoUrls.isNotEmpty) {
      final videoUrl = widget.storyboard.videoUrls.first;
      
      // 检查是否是本地视频
      if (!videoUrl.startsWith('http://') && !videoUrl.startsWith('https://')) {
        final shouldMerge = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E20),
            title: const Text('合成音视频', style: TextStyle(color: Colors.white)),
            content: const Text(
              '是否要将配音合成到视频中？\n\n'
              '✓ 是：生成包含配音的新视频（推荐）\n'
              '✓ 否：仅保存配音文件',
              style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('仅保存配音', style: TextStyle(color: Color(0xFF888888))),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF667EEA)),
                child: const Text('合成到视频', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );

        if (shouldMerge == true) {
          await _mergeAndSave(videoUrl);
          return;
        }
      }
    }

    // 仅保存配音
    _saveConfigOnly();
  }

  /// 仅保存配音配置（不合成视频）
  void _saveConfigOnly() {
    final updatedStoryboard = widget.storyboard.copyWith(
      voiceDialogues: _dialogues,
      generatedAudioPath: _generatedAudioPath,
      voiceStartTime: _voiceStartTime,
      hasVoice: true,
    );

    widget.onComplete(updatedStoryboard);
    Navigator.pop(context);

    _logger.success('配音保存完成', module: '语音生成', extra: {
      'storyboardIndex': widget.storyboardIndex,
      'dialogueCount': _dialogues.length,
    });
  }

  /// 合成并保存
  Future<void> _mergeAndSave(String videoPath) async {
    setState(() => _isMerging = true);

    try {
      _logger.info('开始合成音视频（高质量）', module: '语音生成', extra: {
        'videoPath': videoPath,
        'audioPath': _generatedAudioPath,
        'startTime': _voiceStartTime,
      });

      // 生成输出路径（与原视频同目录）
      final videoDir = path.dirname(videoPath);
      final videoBasename = path.basenameWithoutExtension(videoPath);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = path.join(videoDir, '${videoBasename}_voiced_$timestamp.mp4');

      // 使用 FFmpeg 合成高质量版本
      final mergedPath = await _ffmpegService.mergeVideoAudioWithTiming(
        videoPath: videoPath,
        audioPath: _generatedAudioPath!,
        audioStartTime: _voiceStartTime,
        outputPath: outputPath,
        isPreview: false,  // 高质量模式
      );

      setState(() => _isMerging = false);

      if (mergedPath != null) {
        _logger.success('音视频合成完成', module: '语音生成', extra: {
          'outputPath': mergedPath,
        });

        // 更新分镜，添加新的视频URL
        final updatedVideoUrls = List<String>.from(widget.storyboard.videoUrls);
        updatedVideoUrls.add(mergedPath);  // 添加新视频到列表

        final updatedStoryboard = widget.storyboard.copyWith(
          voiceDialogues: _dialogues,
          generatedAudioPath: _generatedAudioPath,
          voiceStartTime: _voiceStartTime,
          hasVoice: true,
          videoUrls: updatedVideoUrls,  // 更新视频列表
        );

        widget.onComplete(updatedStoryboard);
        Navigator.pop(context);

        // 显示成功消息并询问是否播放
        final shouldPlay = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E20),
            title: Row(
              children: const [
                Icon(Icons.check_circle, color: Color(0xFF2AF598), size: 24),
                SizedBox(width: 12),
                Text('合成完成', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Text(
              '✅ 音视频合成成功！\n\n'
              '新视频已保存到:\n$mergedPath\n\n'
              '是否立即播放查看效果？',
              style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('稍后查看', style: TextStyle(color: Color(0xFF888888))),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2AF598)),
                child: const Text('立即播放', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );

        if (shouldPlay == true) {
          await Process.run('cmd', ['/c', 'start', '', mergedPath]);
        }
      } else {
        throw Exception('FFmpeg 返回空结果');
      }
    } catch (e) {
      _logger.error('合成失败: $e', module: '语音生成');
      setState(() => _isMerging = false);
      _showErrorDialog('合成失败', '错误: $e\n\n请确保 FFmpeg 已正确安装');
    }
  }

  /// 显示错误对话框
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 24),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了', style: TextStyle(color: Color(0xFF667EEA))),
          ),
        ],
      ),
    );
  }

  /// 显示成功对话框
  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF2AF598), size: 24),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了', style: TextStyle(color: Color(0xFF667EEA))),
          ),
        ],
      ),
    );
  }
}
