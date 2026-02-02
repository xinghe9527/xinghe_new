import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'settings_page.dart';
import 'drawing_space.dart';
import 'video_space.dart';
import 'asset_library.dart';
import 'system_log.dart';
import 'widgets/creation_space.dart';
import 'package:xinghe_new/core/widgets/window_border.dart';  // ✅ 导入窗口边框
import 'package:xinghe_new/main.dart'; // 引入全局 themeNotifier 和 AppTheme
import 'package:xinghe_new/core/update/update_checker.dart'; // 自动更新

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0; // 默认选中创作空间
  bool _showSettings = false; // 控制是否显示设置页面

  final List<String> _menuItems = ['创作空间', '绘图空间', '视频空间', '素材库', '系统日志'];

  final List<IconData> _menuIcons = [
    Icons.auto_awesome,
    Icons.brush,
    Icons.movie_creation,
    Icons.folder_open,
    Icons.terminal,
  ];

  @override
  void initState() {
    super.initState();
    // 延迟检查更新，确保页面加载完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateChecker.checkOnStartup(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: themeNotifier,
      builder: (context, themeIndex, _) {
        return Scaffold(
          backgroundColor: AppTheme.scaffoldBackground,
          body: WindowBorder(
            child: Column(
            children: [
              // 1. 自定义可拖动标题栏 + 右上角窗口控制按钮
              Stack(
                children: [
                  DragToMoveArea(
                    child: SizedBox(
                      height: 32,
                      child: Center(
                        child: Text(
                          '星橙AI动漫制作',
                          style: TextStyle(
                            color: AppTheme.subTextColor,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Row(
                      children: [
                        _WindowControlButton(
                          icon: Icons.tune_rounded,
                          onPressed: () {
                            setState(() {
                              _showSettings = true;
                            });
                          },
                        ),
                        _WindowControlButton(
                          icon: Icons.minimize,
                          onPressed: () => windowManager.minimize(),
                        ),
                        _WindowControlButton(
                          icon: Icons.crop_square,
                          onPressed: () async {
                            if (await windowManager.isMaximized()) {
                              windowManager.unmaximize();
                            } else {
                              windowManager.maximize();
                            }
                          },
                        ),
                        _WindowControlButton(
                          icon: Icons.close,
                          isClose: true,
                          onPressed: () => windowManager.close(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Expanded(
                child: _showSettings 
                  ? SettingsPage(onBack: () => setState(() => _showSettings = false))
                  : Row(
                      children: [
                        // 2. 左侧：侧边栏
                        Container(
                          width: 200, 
                          color: AppTheme.scaffoldBackground,
                          child: Column(
                            children: [
                              // 登录入口
                              MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () {},
                                  child: Container(
                                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                                    color: Colors.transparent,
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: const Color(0xFF2C2C2C),
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppTheme.accentColor.withOpacity(0.2),
                                                blurRadius: 8,
                                              ),
                                            ],
                                          ),
                                          child: ClipOval(
                                            child: Image.asset(
                                              'assets/logo.png',
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) {
                                                return Icon(Icons.stars, color: AppTheme.accentColor, size: 22);
                                              },
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('点击登录', style: TextStyle(color: AppTheme.textColor, fontSize: 13, fontWeight: FontWeight.bold)),
                                              Text('同步创意', style: TextStyle(color: AppTheme.subTextColor, fontSize: 10)),
                                            ],
                                          ),
                                        ),
                                        Icon(Icons.chevron_right, color: AppTheme.subTextColor, size: 14),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              // 菜单列表
                              ...List.generate(_menuItems.length, (index) {
                                return _SideMenuItem(
                                  icon: _menuIcons[index],
                                  label: _menuItems[index],
                                  isSelected: _selectedIndex == index,
                                  onTap: () => setState(() => _selectedIndex = index),
                                );
                              }),
                              const Spacer(),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                        VerticalDivider(width: 1, color: AppTheme.dividerColor),
                        // 3. 右侧：内容工作区
                        Expanded(
                          child: _buildContentArea(),
                        ),
                      ],
                    ),
              ),
            ],
            ),
          ),
        );
      },
    );
  }

  // 根据选中的菜单显示不同内容
  Widget _buildContentArea() {
    switch (_selectedIndex) {
      case 0: // 创作空间
        return const CreationSpace();
      case 1: // 绘图空间
        return const DrawingSpace();
      case 2: // 视频空间
        return const VideoSpace();
      case 3: // 素材库
        return const AssetLibrary();
      case 4: // 系统日志
        return const SystemLog();
      default:
        return _buildPlaceholder('未知空间');
    }
  }

  // 占位界面
  Widget _buildPlaceholder(String title) {
    return Container(
      color: AppTheme.scaffoldBackground,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.construction_outlined,
              size: 80,
              color: AppTheme.subTextColor.withOpacity(0.3),
            ),
            const SizedBox(height: 20),
            Text(
              '$title 正在建设中...',
              style: TextStyle(
                color: AppTheme.subTextColor,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 侧边栏菜单项
class _SideMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SideMenuItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.sideBarItemHover : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: AppTheme.textColor,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: AppTheme.textColor,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  fontFamily: 'Microsoft YaHei',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 窗口控制按钮组件
class _WindowControlButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isClose;

  const _WindowControlButton({
    required this.icon,
    required this.onPressed,
    this.isClose = false,
  });

  @override
  State<_WindowControlButton> createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<_WindowControlButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: 32,
          color: _isHovered
              ? (widget.isClose ? Colors.red : AppTheme.textColor.withOpacity(0.1))
              : Colors.transparent,
          child: Icon(
            widget.icon,
            size: 16,
            color: _isHovered && widget.isClose ? Colors.white : AppTheme.subTextColor,
          ),
        ),
      ),
    );
  }
}
