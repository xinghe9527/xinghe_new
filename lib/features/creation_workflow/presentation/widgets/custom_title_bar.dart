import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:xinghe_new/main.dart';

/// 自定义标题栏（与主界面保持一致）
class CustomTitleBar extends StatelessWidget implements PreferredSizeWidget {
  final String? subtitle;  // 左上角小字（作品名称等）
  final VoidCallback? onBack;  // 返回按钮回调
  final VoidCallback? onSettings;  // 设置按钮回调

  const CustomTitleBar({
    super.key,
    this.subtitle,
    this.onBack,
    this.onSettings,
  });

  @override
  Size get preferredSize => const Size.fromHeight(32);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 可拖动区域
        DragToMoveArea(
          child: Container(
            height: 32,
            color: AppTheme.scaffoldBackground,
            child: Center(
              child: Text(
                'R·O·S 动漫制作',
                style: TextStyle(
                  color: AppTheme.subTextColor,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
        // 左上角：返回按钮 + 作品名称
        if (onBack != null || subtitle != null)
          Positioned(
            left: 0,
            top: 0,
            child: Row(
              children: [
                if (onBack != null)
                  _WindowControlButton(
                    icon: Icons.arrow_back,
                    onPressed: onBack!,
                  ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 6),
                    child: Text(
                      subtitle!,
                      style: TextStyle(
                        color: AppTheme.subTextColor,
                        fontSize: 16, // ✅ 16号字体
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        // 右侧：窗口控制按钮
        Positioned(
          right: 0,
          top: 0,
          child: Row(
            children: [
              // 设置按钮（可选）
              if (onSettings != null)
                _WindowControlButton(
                  icon: Icons.tune_rounded,
                  onPressed: onSettings!,
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
                onPressed: onBack ?? () => windowManager.close(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 窗口控制按钮组件
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
