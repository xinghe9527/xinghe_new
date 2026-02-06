import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:xinghe_new/main.dart';
import 'package:xinghe_new/core/logger/log_manager.dart';
import 'package:xinghe_new/services/api/providers/indextts_service.dart';
import 'package:xinghe_new/features/home/domain/voice_asset.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

/// 语音素材详情编辑对话框
/// 类似素材详情，可以设置封面、性别、风格，测试语音等
class VoiceAssetDetailDialog extends StatefulWidget {
  final VoiceAsset? existingVoice;  // 如果是编辑模式，传入现有语音
  final String? initialAudioPath;   // 如果是新建模式，传入音频路径
  final Function(VoiceAsset) onSave;

  const VoiceAssetDetailDialog({
    super.key,
    this.existingVoice,
    this.initialAudioPath,
    required this.onSave,
  });

  @override
  State<VoiceAssetDetailDialog> createState() => _VoiceAssetDetailDialogState();
}

class _VoiceAssetDetailDialogState extends State<VoiceAssetDetailDialog> {
  final LogManager _logger = LogManager();
  
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _testTextController;
  
  String? _coverImagePath;
  String? _audioPath;
  String _gender = '男生';
  String _style = '解说';
  
  // 测试语音相关
  bool _isTesting = false;
  bool _voiceEnabled = false;
  String _voiceServiceUrl = '';
  String _indexttsPath = 'D:\\Index-TTS2_XH';
  
  // ✅ 情感控制（4种模式）
  String _emotionControlMode = '使用文本描述';  // 默认模式
  String? _emotionAudioPath;  // 情感参考音频路径
  List<double> _emotionVector = [0, 0, 0, 0, 0, 0, 0, 0];  // 8维情感向量
  String _emotionText = '';  // 文本情感描述
  double _emotionAlpha = 0.6;  // 情感权重
  bool _useRandomSampling = false;  // 随机情感采样
  
  // 选项
  final List<String> _genderOptions = ['男生', '女生'];
  final List<String> _styleOptions = ['解说', '疑惑', '叙事语气', '活泼', '温柔', '严肃', '激动'];
  final List<String> _emotionControlModes = [
    '与语音参考相同',
    '使用情感参考音频',
    '使用情感向量',
    '使用文本描述',
  ];
  final List<String> _emotionLabels = ['快乐', '愤怒', '悲伤', '害怕', '厌恶', '忧郁', '惊讶', '平静'];

  /// 应用内音频播放器（不弹外部播放器）
  AudioPlayer? _audioPlayer;
  /// 最近一次试听生成成功的音频路径，用于「播放」按钮直接重播
  String? _lastTestAudioPath;

  /// 是否已确认无法使用应用内播放（MissingPluginException 时设为 true，改用系统播放器）
  bool _useSystemPlayer = false;

  @override
  void initState() {
    super.initState();
    _initControllers();
    _loadVoiceConfig();
    // 不在 initState 创建 AudioPlayer，避免桌面端 MissingPluginException 导致无法打开界面
  }

  void _initControllers() {
    if (widget.existingVoice != null) {
      // 编辑模式
      final voice = widget.existingVoice!;
      _nameController = TextEditingController(text: voice.name);
      _descController = TextEditingController(text: voice.description ?? '');
      _coverImagePath = voice.coverImagePath;
      _audioPath = voice.audioPath;
      _gender = voice.gender;
      _style = voice.style;
      // ✅ 加载情感控制配置
      _emotionControlMode = voice.emotionControlMode;
      _emotionAudioPath = voice.emotionAudioPath;
      _emotionVector = List.from(voice.emotionVector);
      _emotionText = voice.emotionText;
      _emotionAlpha = voice.emotionAlpha;
      _useRandomSampling = voice.useRandomSampling;
    } else {
      // 新建模式
      _nameController = TextEditingController();
      _descController = TextEditingController();
      _audioPath = widget.initialAudioPath;
    }
    
    _testTextController = TextEditingController(text: '这是一段测试文本，用于试听语音效果。');
  }

  Future<void> _loadVoiceConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _voiceEnabled = prefs.getBool('voice_enabled') ?? false;
        _voiceServiceUrl = prefs.getString('voice_service_url') ?? 'http://127.0.0.1:7860';
        _indexttsPath = prefs.getString('indextts_path') ?? 'D:\\Index-TTS2_XH';
      });
    } catch (e) {
      _logger.error('加载语音配置失败: $e', module: '语音库');
    }
  }

  @override
  void dispose() {
    _audioPlayer?.dispose();
    _nameController.dispose();
    _descController.dispose();
    _testTextController.dispose();
    super.dispose();
  }

  /// 应用内播放音频；若插件不可用（如桌面端 MissingPluginException）则回退到系统播放器
  Future<void> _playInApp(String path) async {
    if (_useSystemPlayer) {
      try {
        await Process.run('cmd', ['/c', 'start', '', path]);
      } catch (e) {
        if (mounted) _showMessage('播放失败: $e');
      }
      return;
    }
    try {
      _audioPlayer ??= AudioPlayer();
      await _audioPlayer!.stop();
      await _audioPlayer!.play(DeviceFileSource(path));
    } on MissingPluginException catch (_) {
      _useSystemPlayer = true;
      _logger.warning('audioplayers 插件不可用，改用系统播放器', module: '语音库');
      if (mounted) _showMessage('将使用系统默认播放器');
      try {
        await Process.run('cmd', ['/c', 'start', '', path]);
      } catch (e) {
        if (mounted) _showMessage('播放失败: $e');
      }
    } catch (e) {
      _logger.error('应用内播放失败: $e', module: '语音库');
      if (mounted) _showMessage('播放失败: $e');
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
          color: AppTheme.surfaceBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.dividerColor, width: 2),
        ),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildContent()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.scaffoldBackground,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
        ),
        border: Border(bottom: BorderSide(color: AppTheme.dividerColor)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.mic, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.existingVoice != null ? '编辑语音素材' : '添加语音素材',
                  style: TextStyle(
                    color: AppTheme.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '设置角色信息并测试语音效果',
                  style: TextStyle(
                    color: AppTheme.subTextColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: AppTheme.subTextColor),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：封面图预览
          _buildCoverSection(),
          
          const SizedBox(width: 32),
          
          // 右侧：详细信息
          Expanded(child: _buildDetailSection()),
        ],
      ),
    );
  }

  Widget _buildCoverSection() {
    return Column(
      children: [
        // 封面图
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            color: AppTheme.scaffoldBackground,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: const Color(0xFF667EEA), width: 3),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: _coverImagePath != null && File(_coverImagePath!).existsSync()
                ? Image.file(
                    File(_coverImagePath!),
                    fit: BoxFit.cover,
                  )
                : Icon(
                    Icons.person,
                    size: 100,
                    color: AppTheme.subTextColor.withOpacity(0.3),
                  ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // 更换封面按钮
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _pickCoverImage,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF667EEA).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF667EEA)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.image, color: Color(0xFF667EEA), size: 16),
                  const SizedBox(width: 6),
                  Text(
                    _coverImagePath != null ? '更换封面' : '上传封面',
                    style: const TextStyle(
                      color: Color(0xFF667EEA),
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
    );
  }

  Widget _buildDetailSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 名称
        _buildFieldLabel('名称'),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          style: TextStyle(color: AppTheme.textColor, fontSize: 15),
          decoration: InputDecoration(
            hintText: '例如: 尚尚',
            hintStyle: TextStyle(color: AppTheme.subTextColor),
            filled: true,
            fillColor: AppTheme.scaffoldBackground,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        
        const SizedBox(height: 20),
        
        // 风格和性别
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldLabel('风格'),
                  const SizedBox(height: 8),
                  _buildDropdown(
                    value: _style,
                    items: _styleOptions,
                    onChanged: (value) => setState(() => _style = value!),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldLabel('类型'),
                  const SizedBox(height: 8),
                  _buildDropdown(
                    value: _gender,
                    items: _genderOptions,
                    onChanged: (value) => setState(() => _gender = value!),
                  ),
                ],
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 20),
        
        // 参考音频
        _buildFieldLabel('参考音频'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.scaffoldBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.dividerColor),
          ),
          child: Row(
            children: [
              const Icon(Icons.audiotrack, color: Color(0xFF667EEA), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _audioPath != null ? _audioPath!.split('\\').last : '未选择音频',
                  style: TextStyle(
                    color: _audioPath != null ? AppTheme.textColor : AppTheme.subTextColor,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              if (_audioPath != null)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _playOriginalAudio,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2AF598).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '浏览',
                        style: TextStyle(
                          color: Color(0xFF2AF598),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        
        // ✅ 情感控制（完整版）
        _buildFieldLabel('情感控制'),
        const SizedBox(height: 8),
        _buildEmotionControlSection(),
        
        const SizedBox(height: 24),
        
        // 试听测试
        _buildFieldLabel('试听'),
        const SizedBox(height: 8),
        
        // ✅ IndexTTS 状态提示
        if (!_voiceEnabled)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.orange, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '⚠️ 语音合成未启用，请在设置中启用并配置 IndexTTS',
                    style: TextStyle(color: Colors.orange, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.scaffoldBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _testTextController,
                maxLines: 2,
                style: TextStyle(color: AppTheme.textColor, fontSize: 13),
                decoration: InputDecoration(
                  hintText: '输入测试文本...',
                  hintStyle: TextStyle(color: AppTheme.subTextColor),
                  border: InputBorder.none,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: MouseRegion(
                      cursor: _isTesting ? SystemMouseCursors.basic : SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: _isTesting ? null : _testVoice,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isTesting)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(Colors.white),
                                  ),
                                )
                              else
                                const Icon(Icons.volume_up, color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                _isTesting ? '生成中...' : '试听',
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
                  ),
                  const SizedBox(width: 8),
                  // 播放：仅在有上次生成结果时可点，直接播放不重新生成
                  MouseRegion(
                    cursor: _lastTestAudioPath != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
                    child: GestureDetector(
                      onTap: _lastTestAudioPath != null ? () => _playInApp(_lastTestAudioPath!) : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: _lastTestAudioPath != null
                              ? const Color(0xFF2AF598).withOpacity(0.25)
                              : Colors.grey.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _lastTestAudioPath != null ? const Color(0xFF2AF598) : Colors.grey.withOpacity(0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.play_arrow,
                              color: _lastTestAudioPath != null ? const Color(0xFF2AF598) : Colors.grey,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '播放',
                              style: TextStyle(
                                color: _lastTestAudioPath != null ? const Color(0xFF2AF598) : Colors.grey,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _showIndexTTSHelp,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A3A3C),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.help_outline, color: Color(0xFF667EEA), size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 情感控制完整界面
  Widget _buildEmotionControlSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.scaffoldBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 模式选择下拉框
          _buildDropdown(
            value: _emotionControlMode,
            items: _emotionControlModes,
            onChanged: (value) => setState(() => _emotionControlMode = value!),
          ),
          
          const SizedBox(height: 16),
          
          // 根据模式显示不同的控制界面
          _buildEmotionControlContent(),
          
          const SizedBox(height: 16),
          
          // 随机情感采样开关
          Row(
            children: [
              Switch(
                value: _useRandomSampling,
                activeColor: const Color(0xFF667EEA),
                onChanged: (value) => setState(() => _useRandomSampling = value),
              ),
              const SizedBox(width: 8),
              const Text(
                '随机情感采样',
                style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13),
              ),
            ],
          ),
          
          // 情感权重（除了"与语音参考相同"模式）
          if (_emotionControlMode != '与语音参考相同') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('情感权重', style: TextStyle(color: Color(0xFF888888), fontSize: 13)),
                const SizedBox(width: 16),
                Expanded(
                  child: Slider(
                    value: _emotionAlpha,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    activeColor: const Color(0xFF667EEA),
                    inactiveColor: const Color(0xFF3A3A3C),
                    onChanged: (value) => setState(() => _emotionAlpha = value),
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
                    _emotionAlpha.toStringAsFixed(2),
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
      ),
    );
  }

  /// 根据选择的模式显示不同的控制内容
  Widget _buildEmotionControlContent() {
    switch (_emotionControlMode) {
      case '与语音参考相同':
        return const SizedBox.shrink();

      case '使用情感参考音频':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('情感音频', style: TextStyle(color: Color(0xFF888888), fontSize: 12)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252629),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF3A3A3C)),
                    ),
                    child: Text(
                      _emotionAudioPath != null 
                          ? _emotionAudioPath!.split('\\').last 
                          : '选择情感参考音频文件',
                      style: TextStyle(
                        color: _emotionAudioPath != null ? const Color(0xFFCCCCCC) : const Color(0xFF666666),
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
                    onTap: _pickEmotionAudio,
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
        );
        
      case '使用情感向量':
        return Column(
          children: List.generate(8, (index) {
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
                      value: _emotionVector[index],
                      min: 0.0,
                      max: 1.0,
                      divisions: 20,
                      activeColor: const Color(0xFF667EEA),
                      inactiveColor: const Color(0xFF3A3A3C),
                      onChanged: (value) {
                        setState(() {
                          _emotionVector[index] = value;
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
                      _emotionVector[index].toStringAsFixed(2),
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
        );
        
      case '使用文本描述':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Switch(
                  value: true,  // 启用文本描述
                  activeColor: const Color(0xFF667EEA),
                  onChanged: null,  // 不可关闭
                ),
                const SizedBox(width: 8),
                const Text(
                  '随机情感采样',
                  style: TextStyle(color: Color(0xFF888888), fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: TextEditingController(text: _emotionText.isEmpty ? '悬疑叙述，语速稍快' : _emotionText),
              onChanged: (value) => _emotionText = value,
              maxLines: 2,
              style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 13),
              decoration: InputDecoration(
                hintText: '描述情感，如：悬疑叙述，语速稍快',
                hintStyle: const TextStyle(color: Color(0xFF666666)),
                filled: true,
                fillColor: const Color(0xFF252629),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        );
        
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        color: AppTheme.textColor,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.scaffoldBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: AppTheme.surfaceBackground,
          icon: Icon(Icons.unfold_more, color: AppTheme.subTextColor, size: 20),
          items: items.map((item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                style: TextStyle(color: AppTheme.textColor, fontSize: 14),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.scaffoldBackground,
        border: Border(top: BorderSide(color: AppTheme.dividerColor)),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
      ),
      child: Row(
        children: [
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: AppTheme.subTextColor)),
          ),
          const SizedBox(width: 12),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _save,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2AF598), Color(0xFF009EFD)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      '确认',
                      style: TextStyle(
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

  Future<void> _pickCoverImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        dialogTitle: '选择封面图',
      );

      if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
        setState(() {
          _coverImagePath = result.files.first.path;
        });
      }
    } catch (e) {
      _logger.error('选择封面图失败: $e', module: '语音库');
    }
  }

  Future<void> _playOriginalAudio() async {
    if (_audioPath == null) return;
    _showMessage('正在播放...');
    await _playInApp(_audioPath!);
  }

  /// 选择情感参考音频
  Future<void> _pickEmotionAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav', 'mp3', 'm4a', 'aac', 'flac'],
        dialogTitle: '选择情感参考音频',
      );

      if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
        setState(() {
          _emotionAudioPath = result.files.first.path;
        });
      }
    } catch (e) {
      _logger.error('选择情感音频失败: $e', module: '语音库');
    }
  }

  Future<void> _testVoice() async {
    if (_audioPath == null) {
      _showMessage('请先选择音频文件');
      return;
    }

    if (_testTextController.text.trim().isEmpty) {
      _showMessage('请输入测试文本');
      return;
    }

    if (!_voiceEnabled) {
      _showIndexTTSHelp();  // 直接显示帮助
      return;
    }

    // 验证情感模式参数
    if (_emotionControlMode == '使用情感参考音频' && _emotionAudioPath == null) {
      _showMessage('请先选择情感参考音频文件');
      return;
    }

    // ✅ 先测试服务连接
    final ttsService = IndexTTSService(
      baseUrl: _voiceServiceUrl,
      indexttsPath: _indexttsPath,
    );
    final isConnected = await ttsService.testConnection();
    
    if (!isConnected) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E20),
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 24),
              SizedBox(width: 12),
              Text('服务连接失败', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Text(
            '无法连接到 IndexTTS 服务\n\n'
            '服务地址: $_voiceServiceUrl\n\n'
            '请确保：\n'
            '1. IndexTTS 服务已启动（uv run webui.py）\n'
            '2. 服务地址正确\n'
            '3. 防火墙未阻止连接',
            style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消', style: TextStyle(color: Color(0xFF888888))),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showIndexTTSHelp();
              },
              child: const Text('查看帮助', style: TextStyle(color: Color(0xFF667EEA))),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _isTesting = true);

    try {
      final ttsService = IndexTTSService(
        baseUrl: _voiceServiceUrl,
        indexttsPath: _indexttsPath,
      );
      
      final tempDir = Directory.systemTemp.path;
      final testOutputPath = '$tempDir/test_voice_${DateTime.now().millisecondsSinceEpoch}.wav';
      final testText = _testTextController.text.trim();

      _logger.info('测试语音', module: '语音库', extra: {
        'text': testText,
        'mode': _emotionControlMode,
        'useRandom': _useRandomSampling,
      });

      String? audioPath;

      // 根据不同的情感控制模式调用不同的 API
      switch (_emotionControlMode) {
        case '与语音参考相同':
          // 最简单的模式：只用声音样本，不加额外情感控制
          audioPath = await ttsService.synthesize(
            text: testText,
            voicePromptPath: _audioPath!,
            outputPath: testOutputPath,
            useRandom: _useRandomSampling,
          );
          break;
          
        case '使用情感参考音频':
          // 使用情感参考音频
          audioPath = await ttsService.synthesize(
            text: testText,
            voicePromptPath: _audioPath!,
            emotionPromptPath: _emotionAudioPath,
            emotionAlpha: _emotionAlpha,
            outputPath: testOutputPath,
            useRandom: _useRandomSampling,
          );
          break;
          
        case '使用情感向量':
          // 使用8维情感向量
          audioPath = await ttsService.synthesizeWithEmotionVector(
            text: testText,
            voicePromptPath: _audioPath!,
            emotionVector: _emotionVector,
            outputPath: testOutputPath,
            useRandom: _useRandomSampling,
          );
          break;
          
        case '使用文本描述':
          // 使用文本描述情感
          final emotionDescription = _emotionText.isNotEmpty ? _emotionText : _style;
          audioPath = await ttsService.synthesizeWithEmotionText(
            text: testText,
            voicePromptPath: _audioPath!,
            emotionText: emotionDescription,
            useEmotionText: true,
            emotionAlpha: _emotionAlpha,
            outputPath: testOutputPath,
            useRandom: _useRandomSampling,
          );
          break;
      }

      setState(() => _isTesting = false);

      if (audioPath != null) {
        setState(() => _lastTestAudioPath = audioPath);
        _logger.success('测试语音生成完成', module: '语音库', extra: {
          'mode': _emotionControlMode,
          'path': audioPath,
        });
        _showMessage('正在播放测试语音...');
        await _playInApp(audioPath);
      } else {
        _showMessage('测试失败，请检查 IndexTTS 服务');
      }
    } catch (e) {
      _logger.error('测试语音失败: $e', module: '语音库');
      setState(() => _isTesting = false);
      
      // 显示详细错误信息
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E20),
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 24),
              SizedBox(width: 12),
              Text('测试失败', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '❌ 错误信息：',
                  style: TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  e.toString(),
                  style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 12),
                ),
                const SizedBox(height: 16),
                const Text(
                  '💡 常见原因：',
                  style: TextStyle(color: Color(0xFF667EEA), fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  '1. 未安装或未加入 PATH：需安装 uv 并在本应用所在环境 PATH 中可用\n\n'
                  '2. IndexTTS 路径错误：在设置→API→语音合成中核对「IndexTTS 安装路径」\n\n'
                  '3. 工作目录下无 checkpoints：请在 IndexTTS 安装目录下运行 uv run webui.py 确认环境\n\n'
                  '4. 控制台：运行应用时查看输出中的 [IndexTTS] 行可看到具体错误',
                  style: TextStyle(color: Color(0xFF888888), fontSize: 12, height: 1.6),
                ),
              ],
            ),
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

  void _save() {
    if (_nameController.text.trim().isEmpty) {
      _showMessage('请输入角色名称');
      return;
    }

    if (_audioPath == null) {
      _showMessage('请选择音频文件');
      return;
    }

    final voice = VoiceAsset(
      id: widget.existingVoice?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      audioPath: _audioPath!,
      coverImagePath: _coverImagePath,
      gender: _gender,
      style: _style,
      addedTime: widget.existingVoice?.addedTime ?? DateTime.now(),
      description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
      // ✅ 保存情感控制配置
      emotionControlMode: _emotionControlMode,
      emotionAudioPath: _emotionAudioPath,
      emotionVector: _emotionVector,
      emotionText: _emotionText,
      emotionAlpha: _emotionAlpha,
      useRandomSampling: _useRandomSampling,
    );

    widget.onSave(voice);
    Navigator.pop(context);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF667EEA),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 显示 IndexTTS 帮助信息
  void _showIndexTTSHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Color(0xFF667EEA), size: 24),
            SizedBox(width: 12),
            Text('IndexTTS 使用说明', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '📋 当前状态：',
                style: TextStyle(color: Color(0xFF667EEA), fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '• 语音功能：${_voiceEnabled ? "✅ 已启用" : "❌ 未启用"}',
                style: TextStyle(color: _voiceEnabled ? const Color(0xFF2AF598) : Colors.red, fontSize: 13),
              ),
              Text(
                '• 服务地址：$_voiceServiceUrl',
                style: const TextStyle(color: Color(0xFF888888), fontSize: 13),
              ),
              const SizedBox(height: 16),
              const Text(
                '🚀 启动 IndexTTS 服务：',
                style: TextStyle(color: Color(0xFF667EEA), fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF252629),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '1. 打开命令行（CMD 或 PowerShell）\n'
                  '2. 进入 IndexTTS 目录\n'
                  '3. 运行命令: uv run webui.py\n'
                  '4. 等待服务启动（约10-30秒）\n'
                  '5. 看到提示: Running on http://127.0.0.1:7860',
                  style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 12, height: 1.6),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '⚠️ 当前限制：',
                style: TextStyle(color: Colors.orange, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '由于 IndexTTS 使用 Gradio WebUI，当前版本的 API 调用可能需要调整。\n\n'
                '建议：先在 IndexTTS 的 Web 界面（http://127.0.0.1:7860）测试语音合成是否正常工作。\n\n'
                '后续可以优化为直接调用 Python 脚本，更稳定可靠。',
                style: TextStyle(color: Color(0xFF888888), fontSize: 12, height: 1.6),
              ),
            ],
          ),
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
