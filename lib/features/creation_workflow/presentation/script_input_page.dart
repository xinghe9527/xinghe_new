import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinghe_new/main.dart';
import 'package:xinghe_new/features/home/presentation/settings_page.dart';
import 'dart:convert';
import 'widgets/custom_title_bar.dart';
import 'workspace_page.dart';

/// 剧本输入页面（直接输入剧本）
class ScriptInputPage extends StatefulWidget {
  final String workId;
  final String workName;

  const ScriptInputPage({
    super.key,
    required this.workId,
    required this.workName,
  });

  @override
  State<ScriptInputPage> createState() => _ScriptInputPageState();
}

class _ScriptInputPageState extends State<ScriptInputPage> {
  final TextEditingController _scriptController = TextEditingController();
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
            _scriptController.text = data['script'] ?? '';
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
        'script': _scriptController.text,
        'sourceType': '剧本输入',
        'updatedAt': DateTime.now().toIso8601String(),
      };
      await prefs.setString('work_${widget.workId}', jsonEncode(data));
    } catch (e) {
      debugPrint('保存作品数据失败: $e');
    }
  }

  @override
  void dispose() {
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
                    const Icon(Icons.description, color: Color(0xFF888888), size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      '剧本内容',
                      style: TextStyle(
                        color: Color(0xFF888888),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    // 下一步按钮（右上角）
                    ElevatedButton.icon(
                      onPressed: _scriptController.text.trim().isEmpty
                          ? null
                          : _goToWorkspace,
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: const Text('下一步'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3A3A3C),
                        foregroundColor: const Color(0xFF888888),
                        disabledBackgroundColor: const Color(0xFF2A2A2C),
                        disabledForegroundColor: const Color(0xFF666666),
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
              // 剧本输入框
              Expanded(
                child: TextField(
                  controller: _scriptController,
                  maxLines: null,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: '在此粘贴或输入您的剧本...\n\n例如：\n\n第一幕：都市之夜\n\n【场景：未来都市的高楼天台，夜晚】\n\n主角站在天台边缘...',
                    hintStyle: TextStyle(color: Color(0xFF666666)),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                  onChanged: (_) {
                    setState(() {});
                    _saveWorkData();  // 自动保存
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
          sourceType: '剧本输入',
          workId: widget.workId,
          workName: widget.workName,
        ),
        fullscreenDialog: true,
      ),
    );
  }
}
