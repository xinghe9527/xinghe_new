import 'package:flutter/material.dart';
import 'package:xinghe_new/main.dart';
import 'package:xinghe_new/features/home/presentation/settings_page.dart';
import 'widgets/custom_title_bar.dart';
import 'story_input_page.dart';
import 'script_input_page.dart';

/// 创作模式选择界面（故事输入 vs 剧本输入）
class CreationModeSelector extends StatefulWidget {
  final String workId;
  final String workName;

  const CreationModeSelector({
    super.key,
    required this.workId,
    required this.workName,
  });

  @override
  State<CreationModeSelector> createState() => _CreationModeSelectorState();
}

class _CreationModeSelectorState extends State<CreationModeSelector> {
  bool _showSettings = false;

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
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildModeButton(
            context,
            icon: Icons.auto_stories,
            title: '故事输入',
            description: '输入故事，AI生成剧本',
            gradient: const LinearGradient(
              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
            ),
            onTap: () => _navigateToStoryInput(context),
          ),
          const SizedBox(width: 60),
          _buildModeButton(
            context,
            icon: Icons.description,
            title: '剧本输入',
            description: '直接输入剧本内容',
            gradient: const LinearGradient(
              colors: [Color(0xFFf093fb), Color(0xFFF5576C)],
            ),
            onTap: () => _navigateToScriptInput(context),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 280,
          height: 320,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 80, color: Colors.white),
              const SizedBox(height: 24),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  description,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToStoryInput(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StoryInputPage(
          workId: widget.workId,
          workName: widget.workName,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  void _navigateToScriptInput(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScriptInputPage(
          workId: widget.workId,
          workName: widget.workName,
        ),
        fullscreenDialog: true,
      ),
    );
  }
}
