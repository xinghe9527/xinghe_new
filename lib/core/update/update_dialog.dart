import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'update_info.dart';

/// 显示更新对话框
Future<void> showUpdateDialog(BuildContext context, UpdateInfo updateInfo) async {
  return showDialog(
    context: context,
    barrierDismissible: !updateInfo.forceUpdate && !updateInfo.isBlocked,  // ✅ 强制更新时不可关闭
    builder: (context) => PopScope(
      canPop: !updateInfo.forceUpdate && !updateInfo.isBlocked,  // ✅ 强制更新时不可返回
      onPopInvokedWithResult: (didPop, result) {
        // ✅ 如果是强制更新且用户尝试关闭，退出应用
        if (!didPop && (updateInfo.forceUpdate || updateInfo.isBlocked)) {
          exit(0);
        }
      },
      child: _UpdateDialog(updateInfo: updateInfo),
    ),
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
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            widget.updateInfo.isBlocked ? Icons.warning_amber_rounded : Icons.system_update,
            color: widget.updateInfo.isBlocked ? Colors.orange : const Color(0xFF00E5FF),
            size: 28,
          ),
          const SizedBox(width: 12),
          Text(
            widget.updateInfo.isBlocked ? '必须更新' : '发现新版本',
            style: const TextStyle(color: Colors.white, fontSize: 20),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 版本信息
            _buildVersionInfo(),
            const SizedBox(height: 16),

            // 更新日志
            if (widget.updateInfo.updateLog != null) ...[
              const Text(
                '更新内容：',
                style: TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF252629),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.updateInfo.updateLog!,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 警告提示
            if (widget.updateInfo.isBlocked) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '必须更新后才能继续使用软件',
                        style: TextStyle(color: Colors.orange, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        // ✅ 取消按钮（仅非强制更新时显示）
        if (!widget.updateInfo.forceUpdate && !widget.updateInfo.isBlocked)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '稍后提醒',
              style: TextStyle(color: Color(0xFF888888)),
            ),
          ),

        // ✅ 立即更新按钮（跳转到夸克网盘）
        ElevatedButton(
          onPressed: _isLaunching ? null : _openDownloadUrl,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E5FF),
            foregroundColor: Colors.black,
            disabledBackgroundColor: const Color(0xFF3A3A3C),
          ),
          child: Text(_isLaunching ? '正在打开...' : '立即更新'),
        ),
      ],
    );
  }

  Widget _buildVersionInfo() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '当前版本',
              style: TextStyle(color: Color(0xFF888888), fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              widget.updateInfo.currentVersion,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
        const Icon(Icons.arrow_forward, color: Color(0xFF888888)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              '最新版本',
              style: TextStyle(color: Color(0xFF888888), fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              widget.updateInfo.latestVersion,
              style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
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
