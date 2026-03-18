import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:xinghe_new/core/logger/log_manager.dart';
import 'package:xinghe_new/services/api/api_repository.dart';
import 'package:xinghe_new/services/api/providers/indextts_service.dart';
import 'package:xinghe_new/features/home/domain/voice_asset.dart';
import 'package:xinghe_new/main.dart';  // ✅ 导入 workSavePathNotifier
import '../production_space_page.dart';
import 'draggable_media_item.dart';  // ✅ 导入拖动组件
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;  // ✅ 导入 path 包

/// 语音生成向导对话框
/// 三步流程：1.AI识别对话 → 2.确认对话 → 3.生成配音
class VoiceGenerationDialog extends StatefulWidget {
  final StoryboardRow storyboard;
  final int storyboardIndex;
  final String workName;  // ✅ 添加作品名称
  final Function(StoryboardRow) onComplete;

  const VoiceGenerationDialog({
    super.key,
    required this.storyboard,
    required this.storyboardIndex,
    required this.workName,  // ✅ 添加作品名称
    required this.onComplete,
  });

  @override
  State<VoiceGenerationDialog> createState() => _VoiceGenerationDialogState();
}

class _VoiceGenerationDialogState extends State<VoiceGenerationDialog> {
  int _currentStep = 0;
  final LogManager _logger = LogManager();
  final ApiRepository _apiRepository = ApiRepository();
  
  // 步骤1：识别的对话
  List<VoiceDialogue> _dialogues = [];
  bool _isParsingScript = false;
  
  // 步骤2：配音生成
  bool _isGenerating = false;
  
  // 配置
  bool _voiceEnabled = false;
  String _voiceServiceUrl = 'http://127.0.0.1:7860';
  String _audioSavePath = '';
  String _indexttsPath = 'D:\\Index-TTS2_XH';

  // 语音库
  List<VoiceAsset> _availableVoices = [];
  
  // ✅ 步骤3：当前正在配音的对话索引（逐个配音）
  int _currentDialogueIndex = 0;
  VoiceAsset? _selectedVoice;  // 当前对话选中的角色声音
  /// 当前对话选择的合成方式
  String _dialogEmotionMode = '与语音参考相同';
  
  // ✅ 配音生成参数（当前对话的）
  String? _dialogEmotionAudioPath;  // 情感参考音频路径
  List<double> _dialogEmotionVector = [0, 0, 0, 0, 0, 0, 0, 0];  // 8维情感向量
  String _dialogEmotionText = '';  // 情感描述文本
  double _dialogEmotionAlpha = 0.6;  // 情感权重
  bool _dialogUseRandomSampling = false;  // 随机采样
  
  // ✅ 每个对话生成的音频路径（key: 对话ID, value: 音频路径）
  Map<String, String> _dialogueAudioMap = {};
  
  final List<String> _emotionLabels = ['快乐', '愤怒', '悲伤', '害怕', '厌恶', '忧郁', '惊讶', '平静'];

  AudioPlayer? _audioPlayer;
  bool _useSystemPlayer = false;

  @override
  void initState() {
    super.initState();
    
    // ✅ 增加异常捕获，防止初始化崩溃
    try {
      print('[语音生成] ========== 开始初始化 ==========');
      
      _loadVoiceConfig();
      print('[语音生成] ✓ _loadVoiceConfig');
      
      _loadVoiceLibrary();
      print('[语音生成] ✓ _loadVoiceLibrary');
      
      // ✅ 恢复状态
      if (widget.storyboard.voiceDialogues.isNotEmpty) {
        _dialogues = List.from(widget.storyboard.voiceDialogues);
        print('[语音生成] ✓ 恢复对话: ${_dialogues.length} 条');
      }
      
      // 恢复当前对话索引
      _currentDialogueIndex = widget.storyboard.currentDialogueIndex.clamp(0, _dialogues.length);
      print('[语音生成] ✓ 恢复对话索引: $_currentDialogueIndex');
      
      // 恢复音频映射
      if (widget.storyboard.dialogueAudioMapJson != null && widget.storyboard.dialogueAudioMapJson!.isNotEmpty) {
        try {
          final decoded = jsonDecode(widget.storyboard.dialogueAudioMapJson!) as Map<String, dynamic>;
          _dialogueAudioMap = decoded.map((key, value) => MapEntry(key, value.toString()));
          print('[语音生成] ✓ 恢复音频映射: ${_dialogueAudioMap.length} 条');
        } catch (e) {
          print('[语音生成] ⚠️ 恢复音频映射失败: $e');
        }
      }
      
      print('[语音生成] ========== 初始化完成 ==========');
    } catch (e, stack) {
      _logger.error('配音向导初始化失败: $e', module: '语音生成');
      print('[语音生成] ❌ initState 异常: $e');
      print('[语音生成] 堆栈: $stack');
    }
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
  
  /// ✅ 恢复配音向导之前保存的状态（已简化，只恢复必要字段）
  void _restoreWizardState() {
    // 此方法已在 initState 中直接内联，不再需要
  }
  
  /// ✅ 保存当前状态到分镜（废弃，不再使用）
  void _saveWizardState() {
    // 不再使用自动保存，只在"完成并保存"时保存
  }

  // ✅ 对话框位置状态
  Offset _dialogPosition = Offset.zero;
  bool _isDialogPositioned = false;

  @override
  Widget build(BuildContext context) {
    // ✅ 初始化对话框位置（居中）
    if (!_isDialogPositioned) {
      final screenSize = MediaQuery.of(context).size;
      _dialogPosition = Offset(
        (screenSize.width - 900) / 2,
        (screenSize.height - 700) / 2,
      );
      _isDialogPositioned = true;
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,  // ✅ 移除默认边距
      child: Stack(
        children: [
          Positioned(
            left: _dialogPosition.dx,
            top: _dialogPosition.dy,
            child: Container(
              width: 900,
              height: 700,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E20),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF3A3A3C), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
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
          ),
        ],
      ),
    );
  }

  /// 顶部标题栏（可拖动）
  Widget _buildHeader() {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _dialogPosition += details.delta;
          
          // ✅ 限制对话框不超出屏幕边界
          final screenSize = MediaQuery.of(context).size;
          _dialogPosition = Offset(
            _dialogPosition.dx.clamp(0.0, screenSize.width - 900),
            _dialogPosition.dy.clamp(0.0, screenSize.height - 700),
          );
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.move,  // ✅ 显示移动光标
        child: Container(
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
              // ✅ 拖动图标提示
              const Icon(Icons.drag_indicator, color: Color(0xFF666666), size: 20),
              const SizedBox(width: 12),
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
              // ✅ 关闭按钮（阻止拖动事件传播）
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: const Icon(Icons.close, color: Color(0xFF888888)),
                  ),
                ),
              ),
            ],
          ),
        ),
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
                child: SelectableText(
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
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
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
          
          // ✅ 当前正在配音的对话信息
          if (_dialogues.isNotEmpty && _currentDialogueIndex < _dialogues.length)
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
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF667EEA).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '对话 ${_currentDialogueIndex + 1}/${_dialogues.length}',
                          style: const TextStyle(color: Color(0xFF667EEA), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.person, color: Color(0xFF667EEA), size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '角色: ${_dialogues[_currentDialogueIndex].character}',
                        style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '台词: ${_dialogues[_currentDialogueIndex].dialogue}',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
          
          const SizedBox(height: 24),
          
          // ✅ 选择当前对话的角色声音
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
                        setState(() {
                          _selectedVoice = voice;
                          if (voice != null) {
                            // ✅ 默认使用自动模式，不从语音资产加载
                            _dialogEmotionMode = '与语音参考相同';
                            _dialogEmotionAudioPath = null;
                            _dialogEmotionVector = [0, 0, 0, 0, 0, 0, 0, 0];
                            _dialogEmotionText = '';
                            _dialogEmotionAlpha = 0.6;
                            _dialogUseRandomSampling = false;
                          }
                        });
                      },
                    ),
                  ),
                ),
                
                // ✅ 合成方式选择
                if (_selectedVoice != null) ...[
                  const SizedBox(height: 12),
                  const Text(
                    '合成方式',
                    style: TextStyle(color: Color(0xFF888888), fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252629),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF3A3A3C)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _dialogEmotionMode,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF252629),
                        icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF888888)),
                        items: const [
                          DropdownMenuItem(value: '与语音参考相同', child: Text('自动（与语音参考相同）', style: TextStyle(color: Colors.white, fontSize: 13))),
                          DropdownMenuItem(value: '使用情感参考音频', child: Text('使用情感参考音频', style: TextStyle(color: Colors.white, fontSize: 13))),
                          DropdownMenuItem(value: '使用情感向量', child: Text('使用情感向量控制', style: TextStyle(color: Colors.white, fontSize: 13))),
                          DropdownMenuItem(value: '使用文本描述', child: Text('使用情感描述文本', style: TextStyle(color: Colors.white, fontSize: 13))),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _dialogEmotionMode = v);
                        },
                      ),
                    ),
                  ),
                  
                  // ✅ 根据合成方式显示对应的控制界面
                  const SizedBox(height: 16),
                  _buildEmotionControlContent(),
                  
                  // ✅ 随机采样开关
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Switch(
                        value: _dialogUseRandomSampling,
                        activeColor: const Color(0xFF667EEA),
                        onChanged: (value) => setState(() => _dialogUseRandomSampling = value),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '随机情感采样',
                        style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13),
                      ),
                    ],
                  ),
                  
                  // ✅ 情感权重（除了"与语音参考相同"模式）
                  if (_dialogEmotionMode != '与语音参考相同') ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('情感权重', style: TextStyle(color: Color(0xFF888888), fontSize: 13)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Slider(
                            value: _dialogEmotionAlpha,
                            min: 0.0,
                            max: 1.0,
                            divisions: 20,
                            activeColor: const Color(0xFF667EEA),
                            inactiveColor: const Color(0xFF3A3A3C),
                            onChanged: (value) => setState(() => _dialogEmotionAlpha = value),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 60,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3A3A3C),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _dialogEmotionAlpha.toStringAsFixed(2),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          
          const SizedBox(height: 24),
          
          // 生成按钮（只生成当前对话）
          if (_currentDialogueIndex < _dialogues.length && _dialogueAudioMap[_dialogues[_currentDialogueIndex].id] == null)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _isGenerating ? null : _generateCurrentDialogueVoice,
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
                        _isGenerating ? '生成中...' : '🎤 生成当前对话配音',
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
          else if (_currentDialogueIndex < _dialogues.length)
            Column(
              children: [
                // ✅ 当前对话配音生成完成
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2AF598).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2AF598)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF2AF598), size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '✅ 当前对话配音完成',
                              style: TextStyle(
                                color: Color(0xFF2AF598),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '已完成 ${_dialogueAudioMap.length}/${_dialogues.length} 条对话',
                              style: const TextStyle(
                                color: Color(0xFFCCCCCC),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 试听按钮
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => _playDialogueAudio(_dialogues[_currentDialogueIndex].id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF667EEA),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.play_arrow, color: Colors.white, size: 18),
                                SizedBox(width: 6),
                                Text(
                                  '试听',
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
                      ),
                      const SizedBox(width: 8),
                      // 重新生成按钮
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => _regenerateCurrentDialogue(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3A3A3C),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF888888)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.refresh, color: Color(0xFF888888), size: 18),
                                SizedBox(width: 6),
                                Text(
                                  '重配',
                                  style: TextStyle(
                                    color: Color(0xFF888888),
                                    fontSize: 13,
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
                const SizedBox(height: 16),
                
                // ✅ 音频文件列表（可拖动）
                _buildVoiceAudioList(),
                const SizedBox(height: 16),
                
                // ✅ 导航按钮
                Row(
                  children: [
                    // 上一条
                    if (_currentDialogueIndex > 0)
                      Expanded(
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => setState(() => _currentDialogueIndex--),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3A3A3C),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.arrow_back, color: Colors.white, size: 18),
                                  SizedBox(width: 6),
                                  Text(
                                    '上一条',
                                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_currentDialogueIndex > 0 && _currentDialogueIndex < _dialogues.length - 1)
                      const SizedBox(width: 12),
                    // 下一条
                    if (_currentDialogueIndex < _dialogues.length - 1)
                      Expanded(
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () => setState(() => _currentDialogueIndex++),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '下一条',
                                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // ✅ 进度提示
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF667EEA).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF667EEA).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFF667EEA), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _dialogueAudioMap.length == _dialogues.length
                              ? '✅ 所有对话已配音完成，点击底部"完成并保存"'
                              : '💡 配完所有对话后，点击底部"完成并保存"',
                          style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
        ),
      ),
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
              onPressed: _canGoNext() ? _saveAllDialoguesAudio : null,
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
      case 2:
        // 步骤3：所有对话都配完音才能完成
        return _dialogueAudioMap.length == _dialogues.length;
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

  /// 手动添加对话（不展示情感项，后期配音时再选合成方式）
  void _manualAddDialogue() {
    final characterController = TextEditingController();
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
                  emotion: '平静',
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

  /// 编辑对话（不展示情感项，配音时在向导内选合成方式）
  void _editDialogue(int index) {
    final dialogue = _dialogues[index];
    final characterController = TextEditingController(text: dialogue.character);
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

  /// 生成当前对话的配音（不合并，单独保存）
  Future<void> _generateCurrentDialogueVoice() async {
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

    // 测试服务连接
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
        '4. 防火墙未阻止连接',
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final dialogue = _dialogues[_currentDialogueIndex];
      
      _logger.info('生成对话配音', module: '语音生成', extra: {
        'index': _currentDialogueIndex + 1,
        'total': _dialogues.length,
        'character': dialogue.character,
        'voice': _selectedVoice!.name,
        'text': dialogue.dialogue,
      });

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      // ✅ 优先使用作品保存路径，如果没设置则使用音频保存路径
      String savePath;
      final workPath = workSavePathNotifier.value;
      final audioSavePath = _audioSavePath;  // ✅ 重命名避免冲突
      
      if (workPath != '未设置' && workPath.isNotEmpty) {
        // 使用作品路径 + 作品名称
        savePath = path.join(workPath, widget.workName);
        debugPrint('📁 使用作品保存路径: $savePath');
      } else if (audioSavePath.isNotEmpty) {
        // 使用音频保存路径
        savePath = audioSavePath;
        debugPrint('📁 使用音频保存路径: $savePath');
      } else {
        // 使用临时目录
        savePath = Directory.systemTemp.path;
        debugPrint('📁 使用临时目录: $savePath');
      }
      
      // 确保目录存在
      final saveDir = Directory(savePath);
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }
      
      final outputPath = '$savePath/voice_${widget.storyboard.id}_${_currentDialogueIndex}_dialogue_${dialogue.id}_$timestamp.wav';

      // ✅ 根据选择的情感控制方式生成
      String? generatedAudioPath;  // ✅ 重命名避免冲突
      
      switch (_dialogEmotionMode) {
        case '与语音参考相同':
          generatedAudioPath = await ttsService.synthesize(
            text: dialogue.dialogue,
            voicePromptPath: _selectedVoice!.audioPath,
            outputPath: outputPath,
            useRandom: _dialogUseRandomSampling,
          );
          break;
          
        case '使用情感参考音频':
          final emotionAudio = _dialogEmotionAudioPath ?? _selectedVoice!.emotionAudioPath;
          if (emotionAudio != null && File(emotionAudio).existsSync()) {
            generatedAudioPath = await ttsService.synthesize(
              text: dialogue.dialogue,
              voicePromptPath: _selectedVoice!.audioPath,
              emotionPromptPath: emotionAudio,
              emotionAlpha: _dialogEmotionAlpha,
              outputPath: outputPath,
              useRandom: _dialogUseRandomSampling,
            );
          } else {
            throw Exception('情感参考音频未设置');
          }
          break;
          
        case '使用情感向量':
          generatedAudioPath = await ttsService.synthesizeWithEmotionVector(
            text: dialogue.dialogue,
            voicePromptPath: _selectedVoice!.audioPath,
            emotionVector: _dialogEmotionVector,
            outputPath: outputPath,
            useRandom: _dialogUseRandomSampling,
          );
          break;
          
        case '使用文本描述':
        default:
          final emotionText = _dialogEmotionText.isNotEmpty 
              ? _dialogEmotionText 
              : dialogue.emotion;
          generatedAudioPath = await ttsService.synthesizeWithEmotionText(
            text: dialogue.dialogue,
            voicePromptPath: _selectedVoice!.audioPath,
            emotionText: emotionText,
            useEmotionText: true,
            emotionAlpha: _dialogEmotionAlpha,
            outputPath: outputPath,
            useRandom: _dialogUseRandomSampling,
          );
          break;
      }

      if (generatedAudioPath != null && generatedAudioPath.isNotEmpty) {
        final savedPath = generatedAudioPath;  // 保存到本地变量
        setState(() {
          _dialogueAudioMap[dialogue.id] = savedPath;
          _isGenerating = false;
        });

        _logger.success('对话配音完成', module: '语音生成', extra: {
          'index': _currentDialogueIndex + 1,
          'path': generatedAudioPath,
          'size': '${(await File(generatedAudioPath).length() / 1024).toStringAsFixed(2)} KB',
        });
      } else {
        throw Exception('IndexTTS 返回空结果');
      }
    } catch (e, stack) {
      _logger.error('生成配音失败: $e', module: '语音生成');
      print('[语音生成] 错误: $e');
      print('[语音生成] 堆栈: $stack');
      setState(() => _isGenerating = false);
      _showErrorDialog('生成失败', '错误: $e\n\n请检查：\n1. IndexTTS 服务是否正常运行\n2. 服务地址是否正确\n3. 声音样本文件是否有效');
    }
  }

  /// 播放指定对话的配音
  Future<void> _playDialogueAudio(String dialogueId) async {
    final audioPath = _dialogueAudioMap[dialogueId];
    if (audioPath == null) return;
    await _playInApp(audioPath);
  }
  
  /// 重新生成当前对话的配音
  void _regenerateCurrentDialogue() {
    final dialogue = _dialogues[_currentDialogueIndex];
    
    // ✅ 删除旧的音频文件
    final oldAudioPath = _dialogueAudioMap[dialogue.id];
    if (oldAudioPath != null) {
      try {
        final oldFile = File(oldAudioPath);
        if (oldFile.existsSync()) {
          oldFile.deleteSync();
          debugPrint('🗑️ 删除旧音频文件: $oldAudioPath');
        }
      } catch (e) {
        debugPrint('⚠️ 删除旧音频文件失败: $e');
      }
    }
    
    setState(() {
      _dialogueAudioMap.remove(dialogue.id);
    });
  }

  /// ✅ 构建配音音频文件列表（可拖动）
  Widget _buildVoiceAudioList() {
    if (_dialogueAudioMap.isEmpty) {
      return const SizedBox.shrink();
    }

    // 获取所有音频文件路径（按对话顺序）
    final audioItems = <MapEntry<int, String>>[];
    for (int i = 0; i < _dialogues.length; i++) {
      final dialogue = _dialogues[i];
      final audioPath = _dialogueAudioMap[dialogue.id];
      if (audioPath != null && File(audioPath).existsSync()) {
        audioItems.add(MapEntry(i, audioPath));
      }
    }

    if (audioItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '音频文件',
          style: TextStyle(
            color: Color(0xFF888888),
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...audioItems.map((entry) {
          final index = entry.key;
          final audioPath = entry.value;
          final fileName = path.basename(audioPath);
          
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: DraggableMediaItem(
              filePath: audioPath,
              dragPreviewText: fileName,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onSecondaryTapDown: (details) => _showAudioContextMenu(context, details, audioPath),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252629),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF3A3A3C)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.audiotrack, color: Color(0xFF2AF598), size: 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '对话 ${index + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _dialogues[index].dialogue.length > 30
                                    ? '${_dialogues[index].dialogue.substring(0, 30)}...'
                                    : _dialogues[index].dialogue,
                                style: const TextStyle(
                                  color: Color(0xFF888888),
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 播放按钮
                        IconButton(
                          icon: const Icon(Icons.play_arrow, color: Color(0xFF667EEA), size: 20),
                          onPressed: () => _playInApp(audioPath),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: '试听',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  /// ✅ 显示音频文件右键菜单
  void _showAudioContextMenu(BuildContext context, TapDownDetails details, String audioPath) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        details.globalPosition,
        details.globalPosition,
      ),
      Offset.zero & overlay.size,
    );

    showMenu(
      context: context,
      position: position,
      color: const Color(0xFF252629),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF3A3A3C)),
      ),
      items: [
        PopupMenuItem(
          child: Row(
            children: const [
              Icon(Icons.play_arrow, color: Color(0xFF2AF598), size: 18),
              SizedBox(width: 12),
              Text('试听', style: TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
          onTap: () => _playInApp(audioPath),
        ),
        PopupMenuItem(
          child: Row(
            children: const [
              Icon(Icons.folder_open, color: Color(0xFF667EEA), size: 18),
              SizedBox(width: 12),
              Text('定位文件', style: TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
          onTap: () => _locateAudioFile(audioPath),
        ),
      ],
    );
  }

  /// ✅ 定位音频文件（在文件资源管理器中显示）
  Future<void> _locateAudioFile(String audioPath) async {
    try {
      if (!File(audioPath).existsSync()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('音频文件不存在'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      // 使用 explorer /select 命令定位文件
      await Process.run('explorer', ['/select,', audioPath]);
      
      debugPrint('📂 定位文件: $audioPath');
    } catch (e) {
      debugPrint('❌ 定位文件失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('定位失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 保存所有对话的配音（不合并，每个对话单独保存）
  void _saveAllDialoguesAudio() {
    // ✅ 保存音频映射和当前对话索引
    final updatedStoryboard = widget.storyboard.copyWith(
      voiceDialogues: _dialogues,
      generatedAudioPath: _dialogueAudioMap.values.isNotEmpty ? _dialogueAudioMap.values.first : null,
      voiceStartTime: 0.0,
      hasVoice: true,
      voiceWizardStep: 2,  // 保持在步骤3
      currentDialogueIndex: _dialogueAudioMap.length == _dialogues.length ? 0 : _currentDialogueIndex,  // 如果全部完成重置为0
      dialogueAudioMapJson: jsonEncode(_dialogueAudioMap),
    );

    widget.onComplete(updatedStoryboard);
    Navigator.pop(context);

    _logger.success('所有对话配音保存完成', module: '语音生成', extra: {
      'storyboardIndex': widget.storyboardIndex,
      'dialogueCount': _dialogues.length,
      'audioFiles': _dialogueAudioMap.length,
    });
  }

  /// 根据选择的合成方式显示不同的控制内容
  Widget _buildEmotionControlContent() {
    switch (_dialogEmotionMode) {
      case '与语音参考相同':
        return const SizedBox.shrink();

      case '使用情感参考音频':
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF252629),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF3A3A3C)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('情感参考音频', style: TextStyle(color: Color(0xFF888888), fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E20),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF3A3A3C)),
                      ),
                      child: Text(
                        _dialogEmotionAudioPath != null 
                            ? _dialogEmotionAudioPath!.split(RegExp(r'[/\\]')).last 
                            : (_selectedVoice?.emotionAudioPath != null
                                ? _selectedVoice!.emotionAudioPath!.split(RegExp(r'[/\\]')).last
                                : '选择情感参考音频文件（可选）'),
                        style: TextStyle(
                          color: _dialogEmotionAudioPath != null || _selectedVoice?.emotionAudioPath != null
                              ? const Color(0xFFCCCCCC) 
                              : const Color(0xFF666666),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _pickDialogEmotionAudio,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF667EEA).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF667EEA)),
                        ),
                        child: const Text(
                          '浏览',
                          style: TextStyle(
                            color: Color(0xFF667EEA),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
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
        
      case '使用情感向量':
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF252629),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF3A3A3C)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('情感向量（8维）', style: TextStyle(color: Color(0xFF888888), fontSize: 12)),
              const SizedBox(height: 8),
              ...List.generate(8, (index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 60,
                        child: Text(
                          _emotionLabels[index],
                          style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: _dialogEmotionVector[index],
                          min: 0.0,
                          max: 1.0,
                          divisions: 20,
                          activeColor: const Color(0xFF667EEA),
                          inactiveColor: const Color(0xFF3A3A3C),
                          onChanged: (value) {
                            setState(() {
                              _dialogEmotionVector[index] = value;
                            });
                          },
                        ),
                      ),
                      Container(
                        width: 50,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A3A3C),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _dialogEmotionVector[index].toStringAsFixed(2),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
        
      case '使用文本描述':
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF252629),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF3A3A3C)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('情感描述文本', style: TextStyle(color: Color(0xFF888888), fontSize: 12)),
              const SizedBox(height: 8),
              TextField(
                controller: TextEditingController(text: _dialogEmotionText.isEmpty 
                    ? (_selectedVoice?.emotionText.isNotEmpty == true ? _selectedVoice!.emotionText : '')
                    : _dialogEmotionText),
                onChanged: (value) => _dialogEmotionText = value,
                maxLines: 2,
                style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 13),
                decoration: InputDecoration(
                  hintText: '描述情感，如：悬疑叙述，语速稍快',
                  hintStyle: const TextStyle(color: Color(0xFF666666)),
                  filled: true,
                  fillColor: const Color(0xFF1E1E20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        );
        
      default:
        return const SizedBox.shrink();
    }
  }

  /// 选择情感参考音频（对话框内）
  Future<void> _pickDialogEmotionAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav', 'mp3', 'm4a', 'aac', 'flac'],
        dialogTitle: '选择情感参考音频',
      );

      if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
        setState(() {
          _dialogEmotionAudioPath = result.files.first.path;
        });
      }
    } catch (e) {
      _logger.error('选择情感音频失败: $e', module: '语音生成');
    }
  }

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

}
