import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinghe_new/main.dart';
import 'package:xinghe_new/features/home/presentation/settings_page.dart';
import 'dart:convert';
import 'widgets/custom_title_bar.dart';
import 'character_generation_page.dart';
import 'scene_generation_page.dart';
import 'item_generation_page.dart';
import 'production_space_page.dart';

/// 作品空间页面（剧本空间 + 角色/场景/物品管理）
class WorkspacePage extends StatefulWidget {
  final String initialScript;
  final String sourceType;  // '故事输入' 或 '剧本输入' 或 '已有作品'
  final String workId;  // 作品ID（必需）
  final String workName;  // 作品名称（必需）

  const WorkspacePage({
    super.key,
    required this.initialScript,
    required this.sourceType,
    required this.workId,
    required this.workName,
  });

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  late TextEditingController _scriptController;
  bool _showSettings = false;
  String _storyboardPromptName = '默认';
  String _storyboardPromptContent = '';
  int _currentTabIndex = 0;  // 0: 剧本空间, 1: 制作空间
  
  @override
  void initState() {
    super.initState();
    _scriptController = TextEditingController(text: widget.initialScript);
    
    // 加载已有作品数据
    if (widget.sourceType == '已有作品') {
      _loadWork();
    }
  }

  @override
  void dispose() {
    _scriptController.dispose();
    super.dispose();
  }

  /// 加载作品数据
  Future<void> _loadWork() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final workJson = prefs.getString('work_${widget.workId}');
      
      if (workJson != null && workJson.isNotEmpty) {
        final data = jsonDecode(workJson) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _scriptController.text = data['script'] ?? widget.initialScript;
            _storyboardPromptName = data['storyboardPromptName'] ?? '默认';
            _storyboardPromptContent = data['storyboardPromptContent'] ?? '';
            _currentTabIndex = data['currentTabIndex'] ?? 0;  // 恢复标签状态
          });
        }
      }
    } catch (e) {
      debugPrint('加载作品失败: $e');
    }
  }

  /// 保存作品数据
  Future<void> _saveWork() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'id': widget.workId,
        'name': widget.workName,
        'script': _scriptController.text,
        'sourceType': widget.sourceType,
        'storyboardPromptName': _storyboardPromptName,
        'storyboardPromptContent': _storyboardPromptContent,
        'currentTabIndex': _currentTabIndex,  // 保存当前标签状态
        'updatedAt': DateTime.now().toIso8601String(),
      };
      await prefs.setString('work_${widget.workId}', jsonEncode(data));
      debugPrint('✅ 自动保存作品: ${widget.workName} (标签: $_currentTabIndex)');
    } catch (e) {
      debugPrint('⚠️ 保存作品失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: CustomTitleBar(
        subtitle: widget.workName,
        onBack: () => _exitWorkspace(),
        onSettings: () => setState(() => _showSettings = true),
      ),
      body: _showSettings
          ? SettingsPage(onBack: () => setState(() => _showSettings = false))
          : Column(
              children: [
                _buildTabBar(),
                Expanded(
                  child: _currentTabIndex == 0
                      ? _buildScriptSpace()
                      : _buildProductionSpace(),
                ),
              ],
            ),
    );
  }

  /// 标签栏
  Widget _buildTabBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E20),
        border: Border(bottom: BorderSide(color: Color(0xFF2A2A2C))),
      ),
      child: Row(
        children: [
          _buildTabButton(0, Icons.movie, '剧本空间'),
          const SizedBox(width: 12),
          _buildTabButton(1, Icons.grid_on, '分镜空间'),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, IconData icon, String label) {
    final isActive = _currentTabIndex == index;
    return OutlinedButton.icon(
      onPressed: () {
        setState(() => _currentTabIndex = index);
        _saveWork();  // 切换标签时保存状态
      },
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: isActive ? const Color(0xFFFFFFFF) : const Color(0xFF888888),
        side: BorderSide(
          color: isActive ? const Color(0xFF888888) : const Color(0xFF3A3A3C),
        ),
        backgroundColor: isActive ? const Color(0xFF3A3A3C) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }

  /// 制作空间视图
  Widget _buildProductionSpace() {
    return ProductionSpacePage(
      workId: widget.workId,
      workName: widget.workName,
      scriptContent: _scriptController.text,
      storyboardPromptContent: _storyboardPromptContent,
      storyboardPromptName: _storyboardPromptName,
      onPromptChanged: (name, content) {
        setState(() {
          _storyboardPromptName = name;
          _storyboardPromptContent = content;
        });
        _saveWork();
      },
    );
  }

  /// 剧本空间
  Widget _buildScriptSpace() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
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
                  const Icon(Icons.movie, color: Color(0xFF888888), size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    '剧本空间',
                    style: TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                ),
                const Spacer(),
                // 角色按钮
                _buildToolButton(
                  icon: Icons.person,
                  label: '角色',
                  onTap: _openCharacterGeneration,
                ),
                  const SizedBox(width: 12),
                  // 场景按钮
                  _buildToolButton(
                    icon: Icons.landscape,
                    label: '场景',
                    onTap: _openSceneGeneration,
                  ),
                  const SizedBox(width: 12),
                  // 物品按钮
                  _buildToolButton(
                    icon: Icons.category,
                    label: '物品',
                    onTap: _openItemGeneration,
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF2A2A2C), height: 1),
            // 剧本内容编辑区
            Expanded(
              child: TextField(
                controller: _scriptController,
                maxLines: null,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: '在此编辑剧本内容...',
                  hintStyle: TextStyle(color: Color(0xFF666666)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                ),
                onChanged: (_) => _saveWork(),  // 自动保存
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 工具按钮
  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF888888),
        side: const BorderSide(color: Color(0xFF3A3A3C)),
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }

  /// 打开角色生成页面
  Future<void> _openCharacterGeneration() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CharacterGenerationPage(
          workId: widget.workId,
          workName: widget.workName,
          scriptContent: _scriptController.text,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  /// 打开场景生成页面
  Future<void> _openSceneGeneration() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SceneGenerationPage(
          workId: widget.workId,
          workName: widget.workName,
          scriptContent: _scriptController.text,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  /// 打开物品生成页面
  Future<void> _openItemGeneration() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ItemGenerationPage(
          workId: widget.workId,
          workName: widget.workName,
          scriptContent: _scriptController.text,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  /// 退出作品空间
  void _exitWorkspace() async {
    await _saveWork();  // 保存后退出
    if (mounted) {
      Navigator.pop(context);
    }
  }
}
