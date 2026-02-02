import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 无边框窗口的调整大小边框
/// 
/// 在窗口边缘添加透明检测区域，支持拖动调整大小
/// 类似于 VS Code、Discord 等应用的实现方式
class WindowBorder extends StatelessWidget {
  final Widget child;
  final double borderWidth;  // 边框检测区域宽度

  const WindowBorder({
    super.key,
    required this.child,
    this.borderWidth = 4.0,  // 默认4像素
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 主内容
        Positioned.fill(child: child),
        
        // 8个调整大小区域
        
        // 1. 顶部边缘
        Positioned(
          left: borderWidth,
          right: borderWidth,
          top: 32,  // 避开32px的标题栏
          child: _ResizeArea(
            width: double.infinity,
            height: borderWidth,
            edge: ResizeEdge.top,
            cursor: SystemMouseCursors.resizeUpDown,
          ),
        ),
        
        // 2. 底部边缘
        Positioned(
          left: borderWidth,
          right: borderWidth,
          bottom: 0,
          child: _ResizeArea(
            width: double.infinity,
            height: borderWidth,
            edge: ResizeEdge.bottom,
            cursor: SystemMouseCursors.resizeUpDown,
          ),
        ),
        
        // 3. 左边缘
        Positioned(
          left: 0,
          top: 32 + borderWidth,  // 避开标题栏和顶部角落
          bottom: borderWidth,
          child: _ResizeArea(
            width: borderWidth,
            height: double.infinity,
            edge: ResizeEdge.left,
            cursor: SystemMouseCursors.resizeLeftRight,
          ),
        ),
        
        // 4. 右边缘
        Positioned(
          right: 0,
          top: 32 + borderWidth,
          bottom: borderWidth,
          child: _ResizeArea(
            width: borderWidth,
            height: double.infinity,
            edge: ResizeEdge.right,
            cursor: SystemMouseCursors.resizeLeftRight,
          ),
        ),
        
        // 5. 左上角
        Positioned(
          left: 0,
          top: 32,
          child: _ResizeArea(
            width: borderWidth * 2,
            height: borderWidth * 2,
            edge: ResizeEdge.topLeft,
            cursor: SystemMouseCursors.resizeUpLeftDownRight,
          ),
        ),
        
        // 6. 右上角
        Positioned(
          right: 0,
          top: 32,
          child: _ResizeArea(
            width: borderWidth * 2,
            height: borderWidth * 2,
            edge: ResizeEdge.topRight,
            cursor: SystemMouseCursors.resizeUpRightDownLeft,
          ),
        ),
        
        // 7. 左下角
        Positioned(
          left: 0,
          bottom: 0,
          child: _ResizeArea(
            width: borderWidth * 2,
            height: borderWidth * 2,
            edge: ResizeEdge.bottomLeft,
            cursor: SystemMouseCursors.resizeUpRightDownLeft,
          ),
        ),
        
        // 8. 右下角（带视觉提示图标）
        Positioned(
          right: 0,
          bottom: 0,
          child: _ResizeArea(
            width: borderWidth * 3,  // 稍大一些，方便点击
            height: borderWidth * 3,
            edge: ResizeEdge.bottomRight,
            cursor: SystemMouseCursors.resizeUpLeftDownRight,
            showIcon: true,  // 显示调整大小图标
          ),
        ),
      ],
    );
  }
}

/// 调整大小检测区域
class _ResizeArea extends StatefulWidget {
  final double width;
  final double height;
  final ResizeEdge edge;
  final MouseCursor cursor;
  final bool showIcon;

  const _ResizeArea({
    required this.width,
    required this.height,
    required this.edge,
    required this.cursor,
    this.showIcon = false,
  });

  @override
  State<_ResizeArea> createState() => _ResizeAreaState();
}

class _ResizeAreaState extends State<_ResizeArea> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onPanStart: (_) {
          // 开始调整大小
          windowManager.startResizing(widget.edge);
        },
        child: Container(
          width: widget.width,
          height: widget.height,
          color: Colors.transparent,  // 完全透明
          child: widget.showIcon && _isHovered
              ? Center(
                  child: Icon(
                    Icons.filter_list,
                    size: 10,
                    color: Colors.white.withOpacity(0.3),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
