import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'update_info.dart';

/// 显示更新对话框
Future<void> showUpdateDialog(BuildContext context, UpdateInfo updateInfo) async {
  await showGeneralDialog(
    context: context,
    barrierDismissible: !updateInfo.forceUpdate && !updateInfo.isBlocked,
    barrierLabel: '',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      return PopScope(
        canPop: !updateInfo.forceUpdate && !updateInfo.isBlocked,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && (updateInfo.forceUpdate || updateInfo.isBlocked)) {
            exit(0);
          }
        },
        child: _UpdateDialog(updateInfo: updateInfo),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation,
        child: child,
      );
    },
  );
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const _UpdateDialog({required this.updateInfo});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _isLaunching = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // 全屏背景：纯黑色半透明遮罩
          Positioned.fill(
            child: GestureDetector(
              onTap: (widget.updateInfo.forceUpdate || widget.updateInfo.isBlocked)
                  ? null
                  : () => Navigator.of(context).pop(),
              child: Container(
                color: Colors.black.withValues(alpha: 0.7),
              ),
            ),
          ),
          
          // 弹窗主体
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 500,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  // 渐变边框
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF00E5FF).withValues(alpha: 0.3),
                      const Color(0xFFAA00FF).withValues(alpha: 0.3),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(1.5),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D0D),
                    borderRadius: BorderRadius.circular(19),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 标题
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: widget.updateInfo.isBlocked
                                      ? [Colors.orange, Colors.deepOrange]
                                      : [const Color(0xFF00E5FF), const Color(0xFFAA00FF)],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                widget.updateInfo.isBlocked
                                    ? Icons.warning_amber_rounded
                                    : Icons.system_update,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              widget.updateInfo.isBlocked ? '必须更新' : '发现新版本',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),

                        // 版本信息
                        _buildVersionInfo(),
                        const SizedBox(height: 24),

                        // 更新日志
                        if (widget.updateInfo.updateLog != null) ...[
                          const Text(
                            '更新内容：',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Text(
                              widget.updateInfo.updateLog!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                height: 1.6,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // 警告提示
                        if (widget.updateInfo.isBlocked) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.orange.withValues(alpha: 0.2),
                                  Colors.deepOrange.withValues(alpha: 0.2),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.5),
                                width: 1.5,
                              ),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.orange, size: 22),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '必须更新后才能继续使用软件',
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // 按钮组
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // 稍后提醒按钮
                            if (!widget.updateInfo.forceUpdate && !widget.updateInfo.isBlocked)
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                ),
                                child: const Text(
                                  '稍后提醒',
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            if (!widget.updateInfo.forceUpdate && !widget.updateInfo.isBlocked)
                              const SizedBox(width: 12),
                            
                            // 立即更新按钮 - 渐变色
                            SizedBox(
                              height: 50,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF00E5FF),
                                      Color(0xFFAA00FF),
                                    ],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                                      blurRadius: 15,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: _isLaunching ? null : _openDownloadUrl,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 32),
                                      child: Center(
                                        child: _isLaunching
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2.5,
                                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                ),
                                              )
                                            : const Text(
                                                '立即更新',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                  letterSpacing: 1,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '当前版本',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.updateInfo.currentVersion,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Icon(
            Icons.arrow_forward,
            color: Colors.white.withValues(alpha: 0.3),
            size: 28,
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                '最新版本',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFF00E5FF), Color(0xFFAA00FF)],
                ).createShader(bounds),
                child: Text(
                  widget.updateInfo.latestVersion,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// ✅ 打开下载链接（夸克网盘）
  Future<void> _openDownloadUrl() async {
    setState(() => _isLaunching = true);

    try {
      final url = widget.updateInfo.downloadUrl;
      debugPrint('🔗 打开下载链接: $url');

      final uri = Uri.parse(url);
      
      // ✅ 使用 url_launcher 打开外部链接
      final canLaunch = await canLaunchUrl(uri);
      
      if (!canLaunch) {
        _showError('无法打开下载链接');
        return;
      }

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,  // ✅ 使用外部浏览器打开
      );

      if (!launched) {
        _showError('打开下载链接失败');
        return;
      }

      debugPrint('✅ 已打开下载链接');

      // ✅ 如果是强制更新，打开链接后退出应用
      if (widget.updateInfo.forceUpdate || widget.updateInfo.isBlocked) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('请在浏览器中下载更新，应用即将退出'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        
        await Future.delayed(const Duration(seconds: 2));
        exit(0);
      } else {
        // 非强制更新，关闭对话框
        if (mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      debugPrint('❌ 打开下载链接失败: $e');
      _showError('打开下载链接失败: $e');
    } finally {
      if (mounted) {
        setState(() => _isLaunching = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}
