import 'package:flutter/material.dart';
import 'package:xinghe_new/main.dart';
import 'package:xinghe_new/features/home/presentation/watermark_remover_page.dart';

class Toolbox extends StatefulWidget {
  const Toolbox({super.key});

  @override
  State<Toolbox> createState() => _ToolboxState();
}

class _ToolboxState extends State<Toolbox> {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.scaffoldBackground,
      child: Column(
        children: [
          // 标题栏
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: AppTheme.surfaceBackground,
              border: Border(
                bottom: BorderSide(
                  color: AppTheme.dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  '工具箱',
                  style: TextStyle(
                    color: AppTheme.textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
              ],
            ),
          ),
          // 内容区域 - 工具网格
          Expanded(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1400),
                padding: const EdgeInsets.all(48),
                child: GridView.count(
                  crossAxisCount: 4,
                  mainAxisSpacing: 32,
                  crossAxisSpacing: 32,
                  childAspectRatio: 1.1,
                  children: [
                    _buildToolCard(
                      icon: Icons.water_drop_outlined,
                      title: '图片去水印',
                      description: '智能去除图片中的水印',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const WatermarkRemoverPage(),
                          ),
                        );
                      },
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

  /// 构建工具卡片 - 极简设计
  Widget _buildToolCard({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    bool isHovered = false;
    
    return StatefulBuilder(
      builder: (context, setState) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => isHovered = true),
          onExit: (_) => setState(() => isHovered = false),
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: isHovered 
                    ? AppTheme.surfaceBackground.withValues(alpha: 0.8)
                    : AppTheme.surfaceBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isHovered 
                      ? AppTheme.accentColor.withValues(alpha: 0.3)
                      : AppTheme.dividerColor.withValues(alpha: 0.5),
                  width: 1,
                ),
                boxShadow: isHovered ? [
                  BoxShadow(
                    color: AppTheme.accentColor.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ] : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 图标 - 更简洁的设计
                  Icon(
                    icon,
                    size: 40,
                    color: isHovered 
                        ? AppTheme.accentColor
                        : AppTheme.accentColor.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: 20),
                  // 标题
                  Text(
                    title,
                    style: TextStyle(
                      color: AppTheme.textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Microsoft YaHei',
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 描述
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      description,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.subTextColor.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontFamily: 'Microsoft YaHei',
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
