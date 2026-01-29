import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinghe_new/main.dart';
import 'package:xinghe_new/features/home/presentation/settings_page.dart';
import 'dart:convert';
import 'dart:async';
import 'widgets/custom_title_bar.dart';
import 'prompt_preset_manager.dart';
import 'workspace_page.dart';
import '../data/real_ai_service.dart';

/// 故事输入页面（故事→剧本）
class StoryInputPage extends StatefulWidget {
  final String workId;
  final String workName;

  const StoryInputPage({
    super.key,
    required this.workId,
    required this.workName,
  });

  @override
  State<StoryInputPage> createState() => _StoryInputPageState();
}

class _StoryInputPageState extends State<StoryInputPage> {
  final TextEditingController _storyController = TextEditingController();
  final TextEditingController _scriptController = TextEditingController();
  final RealAIService _aiService = RealAIService(); // ✅ 真实 AI 服务
  
  String _selectedPresetName = '默认';
  String _selectedPresetContent = '';
  bool _isGenerating = false;
  bool _showSettings = false;
  Timer? _saveDebounceTimer; // ✅ 防抖定时器

  @override
  void initState() {
    super.initState();
    _loadWorkData();
  }

  /// 加载作品数据
  Future<void> _loadWorkData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final workJson = prefs.getString('work_${widget.workId}');
      
      if (workJson != null && workJson.isNotEmpty) {
        final data = jsonDecode(workJson) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _storyController.text = data['story'] ?? '';
            _scriptController.text = data['script'] ?? '';
            // 加载当前作品选择的提示词预设
            _selectedPresetName = data['selectedPresetName'] ?? '默认';
            _selectedPresetContent = data['selectedPresetContent'] ?? '';
          });
        }
      }
    } catch (e) {
      debugPrint('加载作品数据失败: $e');
    }
  }

  /// 保存作品数据
  Future<void> _saveWorkData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'id': widget.workId,
        'name': widget.workName,
        'story': _storyController.text,
        'script': _scriptController.text,
        'sourceType': '故事输入',
        'currentPage': 'story_input',  // ✅ 记录当前在故事输入页
        // 保存当前作品选择的提示词预设
        'selectedPresetName': _selectedPresetName,
        'selectedPresetContent': _selectedPresetContent,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      await prefs.setString('work_${widget.workId}', jsonEncode(data));
      debugPrint('💾 保存故事输入状态: currentPage = story_input');
    } catch (e) {
      debugPrint('保存作品数据失败: $e');
    }
  }

  @override
  void dispose() {
    _saveDebounceTimer?.cancel(); // ✅ 取消防抖定时器
    _storyController.dispose();
    _scriptController.dispose();
    super.dispose();
  }

  /// ✅ 防抖保存 - 避免频繁保存
  void _debouncedSave() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(seconds: 1), () {
      _saveWorkData();
      debugPrint('💾 故事内容已自动保存');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: CustomTitleBar(
        subtitle: widget.workName,
        onBack: () => Navigator.pop(context),
        onSettings: () => setState(() => _showSettings = true),
      ),
      body: _showSettings
          ? SettingsPage(onBack: () => setState(() => _showSettings = false))
          : Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            // 左边：故事输入
            Expanded(
              child: _buildStoryInput(),
            ),
            const SizedBox(width: 24),
            // 右边：剧本生成
            Expanded(
              child: _buildScriptOutput(),
            ),
          ],
        ),
      ),
    );
  }

  /// 左边：故事输入框
  Widget _buildStoryInput() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.edit_note, color: Color(0xFF888888), size: 20),
                const SizedBox(width: 8),
                const Text(
                  '故事内容',
                  style: TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF2A2A2C), height: 1),
          Expanded(
            child: TextField(
              controller: _storyController,
              maxLines: null,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                hintText: '在此粘贴或输入您的故事...\n\n例如：\n在一个赛博朋克风格的未来都市，主角是一名黑客...',
                hintStyle: TextStyle(color: Color(0xFF666666)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
              ),
              onChanged: (_) => _debouncedSave(), // ✅ 添加自动保存（防抖1秒）
            ),
          ),
        ],
      ),
    );
  }

  /// 右边：剧本生成
  Widget _buildScriptOutput() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部工具栏
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.movie_creation, color: Color(0xFF888888), size: 20),
                const SizedBox(width: 8),
                const Text(
                  '生成的剧本',
                  style: TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // 提示词预设按钮（小书图标）
                IconButton(
                  onPressed: _openPromptPresetManager,
                  icon: const Icon(Icons.menu_book, size: 20),
                  color: const Color(0xFF888888),
                  tooltip: '剧本提示词（当前：$_selectedPresetName）',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF3A3A3C).withOpacity(0.3),
                  ),
                ),
                const SizedBox(width: 12),
                // 生成剧本按钮（大按钮）
                OutlinedButton.icon(
                  onPressed: _isGenerating ? null : _generateScript,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Color(0xFF888888)),
                          ),
                        )
                      : const Icon(Icons.auto_awesome, size: 16),
                  label: Text(_isGenerating ? '生成中...' : '生成剧本'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF888888),
                    side: const BorderSide(color: Color(0xFF3A3A3C)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 下一步按钮
                OutlinedButton.icon(
                  onPressed: _scriptController.text.trim().isEmpty
                      ? null
                      : _goToWorkspace,
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('下一步'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF888888),
                    side: const BorderSide(color: Color(0xFF3A3A3C)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF2A2A2C), height: 1),
          // 剧本内容
          Expanded(
            child: TextField(
              controller: _scriptController,
              maxLines: null,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                hintText: '生成的剧本将显示在这里...',
                hintStyle: TextStyle(color: Color(0xFF666666)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 打开提示词预设管理器
  void _openPromptPresetManager() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => PromptPresetManager(
        currentPresetName: _selectedPresetName,
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedPresetName = result['name'] ?? '默认';
        _selectedPresetContent = result['content'] ?? '';
      });
      // 保存选择
      await _saveWorkData();
      debugPrint('✅ 作品 ${widget.workName} 选择提示词预设: $_selectedPresetName');
    }
  }

  /// 生成剧本
  Future<void> _generateScript() async {
    final story = _storyController.text.trim();
    if (story.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入故事内容')),
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      // ✅ 调用真实 LLM API 生成剧本（传递提示词预设）
      final scriptLines = await _aiService.generateScript(
        theme: story,
        presetPrompt: _selectedPresetContent.isNotEmpty ? _selectedPresetContent : null,  // ✅ 传递提示词
      );
      
      // ✅ 直接使用 API 返回的内容（不添加任何前缀）
      final scriptText = scriptLines.map((line) => line.content).join('\n\n');

      if (mounted) {
        setState(() {
          _scriptController.text = scriptText;
        });
        // 自动保存
        await _saveWorkData();
        
        // 显示成功提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 成功生成剧本（${scriptLines.length} 个场景）'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        // ✅ 检查是否是内容过长的特定错误
        if (e.toString().contains('CONTENT_TOO_LONG')) {
          // 显示内容过长的提示
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E20),
              title: const Row(
                children: [
                  Icon(Icons.warning_rounded, color: Color(0xFFFFA726), size: 28),
                  SizedBox(width: 12),
                  Text(
                    '⚠️ 生成内容过多',
                    style: TextStyle(color: Color(0xFFFFA726)),
                  ),
                ],
              ),
              content: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '您的故事内容生成的剧本过长，已达到最大限制（8000 tokens）。',
                    style: TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
                  ),
                  SizedBox(height: 16),
                  Text(
                    '📌 提示：',
                    style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '过长的剧本不利于后续的分镜制作和视频生成。',
                    style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                  ),
                  SizedBox(height: 16),
                  Text(
                    '💡 建议：',
                    style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '1. 精简故事内容，保留核心情节\n'
                    '2. 去掉不必要的细节描写\n'
                    '3. 或将故事分成多个章节，分别制作',
                    style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('我知道了', style: TextStyle(color: Color(0xFF00E5FF))),
                ),
              ],
            ),
          );
        } else {
          // 显示其他错误
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E20),
              title: const Text(
                '❌ 生成失败',
                style: TextStyle(color: Colors.red),
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '错误详情：',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      e.toString(),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  /// 进入作品空间
  Future<void> _goToWorkspace() async {
    final script = _scriptController.text.trim();
    if (script.isEmpty) return;

    // 保存数据
    await _saveWorkData();

    // 进入作品空间
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => WorkspacePage(
          initialScript: script,
          sourceType: '故事输入',
          workId: widget.workId,
          workName: widget.workName,
        ),
        fullscreenDialog: true,
      ),
    );
  }
}
