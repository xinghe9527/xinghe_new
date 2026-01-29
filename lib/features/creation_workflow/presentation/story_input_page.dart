import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinghe_new/main.dart';
import 'package:xinghe_new/features/home/presentation/settings_page.dart';
import 'dart:convert';
import 'widgets/custom_title_bar.dart';
import 'prompt_preset_manager.dart';
import 'workspace_page.dart';

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
  
  String _selectedPresetName = '默认';
  String _selectedPresetContent = '';
  bool _isGenerating = false;
  bool _showSettings = false;

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
        // 保存当前作品选择的提示词预设
        'selectedPresetName': _selectedPresetName,
        'selectedPresetContent': _selectedPresetContent,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      await prefs.setString('work_${widget.workId}', jsonEncode(data));
    } catch (e) {
      debugPrint('保存作品数据失败: $e');
    }
  }

  @override
  void dispose() {
    _storyController.dispose();
    _scriptController.dispose();
    super.dispose();
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
      // TODO: 调用LLM API生成剧本
      // 这里使用Mock数据模拟
      await Future.delayed(const Duration(seconds: 2));
      
      // Mock生成的剧本
      final mockScript = '''第一幕：都市之夜

【场景：未来都市的高楼天台，夜晚，霓虹灯闪烁】

主角站在天台边缘，俯瞰着这座充满科技感的城市。全息广告在空中漂浮，飞行器穿梭于摩天大楼之间。

主角（独白）：又是一个无眠之夜。这座城市从不睡觉，就像我一样。

【主角转身，走向天台门口】

第二幕：黑客任务

【场景：主角的地下工作室】

多个全息屏幕环绕着主角，显示着复杂的代码和数据流。主角快速敲击着虚拟键盘。

主角：终于找到了...这个防火墙的漏洞。

【警报声突然响起】

主角：什么？被追踪了？

【屏幕上出现红色警告】

第三幕：追逐

【场景：城市街道】

主角匆忙离开工作室，消失在霓虹灯闪烁的街道中。机械警察开始搜索...

【待续】''';

      if (mounted) {
        setState(() {
          _scriptController.text = mockScript;
        });
        // 自动保存
        await _saveWorkData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败：$e')),
        );
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
