import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 1; // 默认选中绘图空间

  final List<String> _menuItems = ['创作空间', '绘图空间', '视频空间', '素材库', '系统日志'];

  final List<IconData> _menuIcons = [
    Icons.auto_awesome,
    Icons.brush,
    Icons.movie_creation,
    Icons.folder_open,
    Icons.terminal,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF161618),
      body: Column(
        children: [
          // -------------------------
          // 1. 自定义可拖动标题栏 + 右上角窗口控制按钮 (包含设置按钮)
          // -------------------------
          Stack(
            children: [
              const DragToMoveArea(
                child: SizedBox(
                  height: 32,
                  child: Center(
                    child: Text(
                      '星橙AI动漫制作',
                      style: TextStyle(
                        color: Colors.white54,
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
                    // 更换为更精致的设置图标 (tune_rounded)
                    _WindowControlButton(
                      icon: Icons.tune_rounded, 
                      onPressed: () {
                        // 处理设置点击
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
            child: Row(
              children: [
                // -------------------------
                // 2. 左侧：侧边栏 (更简洁、紧凑)
                // -------------------------
                Container(
                  width: 200, 
                  color: const Color(0xFF161618),
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
                                        color: const Color(0xFF00E5FF).withOpacity(0.2),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: ClipOval(
                                    child: Image.asset(
                                      'assets/logo.png',
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return const Icon(Icons.stars, color: Color(0xFF00E5FF), size: 22);
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('点击登录', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                      Text('同步创意', style: TextStyle(color: Colors.grey, fontSize: 10)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right, color: Colors.grey, size: 14),
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
                VerticalDivider(width: 1, color: Colors.white.withOpacity(0.06)),
                // -------------------------
                // 3. 右侧：内容工作区
                // -------------------------
                Expanded(
                  child: Container(
                    color: const Color(0xFF161618),
                    child: Column(
                      children: [
                        Container(
                          height: 54,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            children: [
                              Text('AI 图像生成', style: TextStyle(color: Colors.grey[400], fontSize: 14, fontWeight: FontWeight.w500)),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.more_horiz, color: Colors.grey, size: 22), 
                                onPressed: () {},
                                mouseCursor: SystemMouseCursors.click,
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1D1D1F),
                              borderRadius: const BorderRadius.only(topLeft: Radius.circular(20)),
                              border: Border.all(color: Colors.white.withOpacity(0.04)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 340,
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    border: Border(right: BorderSide(color: Colors.white.withOpacity(0.05))),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('提示词', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 16),
                                      Expanded(
                                        child: Container(
                                          decoration: BoxDecoration(color: const Color(0xFF252629), borderRadius: BorderRadius.circular(14)),
                                          child: const TextField(
                                            maxLines: null,
                                            style: TextStyle(color: Colors.white, fontSize: 15),
                                            decoration: InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.all(18), hintText: '描述你想要生成的画面...', hintStyle: TextStyle(color: Colors.grey, fontSize: 14)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      Container(
                                        width: double.infinity,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(14),
                                          gradient: const LinearGradient(colors: [Color(0xFF2AF598), Color(0xFF009EFD)]),
                                          boxShadow: [BoxShadow(color: const Color(0xFF2AF598).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: () {}, 
                                            borderRadius: BorderRadius.circular(14), 
                                            mouseCursor: SystemMouseCursors.click,
                                            child: const Center(child: Text('立即生成', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17))),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // 修正：背景颜色与左侧提示词区域统一 (0xFF1D1D1F)
                                Expanded(
                                  child: Container(
                                    color: const Color(0xFF1D1D1F), 
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center, 
                                        children: [
                                          Icon(Icons.image_outlined, size: 100, color: Colors.white.withOpacity(0.03)), 
                                          const SizedBox(height: 20), 
                                          Text('等待生成预览', style: TextStyle(color: Colors.white.withOpacity(0.08), fontSize: 15))
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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
            color: isSelected ? const Color(0xFF3E3F42) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
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

// 窗口控制按钮组件 (包含设置、最小化、还原、关闭)
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
              ? (widget.isClose ? Colors.red : Colors.white.withOpacity(0.1))
              : Colors.transparent,
          child: Icon(
            widget.icon,
            size: 16,
            color: _isHovered && widget.isClose ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }
}
