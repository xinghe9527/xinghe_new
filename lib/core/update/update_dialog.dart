import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'update_info.dart';
import 'update_downloader.dart';

/// 显示更新对话框
Future<void> showUpdateDialog(BuildContext context, UpdateInfo updateInfo) async {
  return showDialog(
    context: context,
    barrierDismissible: !updateInfo.forceUpdate && !updateInfo.isBlocked,
    builder: (context) => WillPopScope(
      onWillPop: () async => !updateInfo.forceUpdate && !updateInfo.isBlocked,
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
  final UpdateDownloader _downloader = UpdateDownloader();
  bool _isDownloading = false;
  bool _downloadComplete = false;

  @override
  void dispose() {
    _downloader.dispose();
    super.dispose();
  }

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
            widget.updateInfo.isBlocked ? '版本过低，必须更新' : '发现新版本',
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

            // 下载进度
            if (_isDownloading) ...[
              ValueListenableBuilder<String>(
                valueListenable: _downloader.statusNotifier,
                builder: (context, status, _) {
                  return Text(
                    status,
                    style: const TextStyle(color: Color(0xFF888888), fontSize: 13),
                  );
                },
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<double>(
                valueListenable: _downloader.progressNotifier,
                builder: (context, progress, _) {
                  return Column(
                    children: [
                      LinearProgressIndicator(
                        value: progress,
                        backgroundColor: const Color(0xFF3A3A3C),
                        valueColor: const AlwaysStoppedAnimation(Color(0xFF00E5FF)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(progress * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
                      ),
                    ],
                  );
                },
              ),
            ],

            // 警告提示
            if (widget.updateInfo.isBlocked) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '当前版本过低，必须更新后才能使用软件',
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
        // 取消按钮（仅可选更新时显示）
        if (!widget.updateInfo.forceUpdate && !widget.updateInfo.isBlocked && !_isDownloading)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '稍后提醒',
              style: TextStyle(color: Color(0xFF888888)),
            ),
          ),

        // 更新按钮
        if (!_downloadComplete)
          ElevatedButton(
            onPressed: _isDownloading ? null : _startUpdate,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
              disabledBackgroundColor: const Color(0xFF3A3A3C),
            ),
            child: Text(_isDownloading ? '下载中...' : '立即更新'),
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

  Future<void> _startUpdate() async {
    setState(() => _isDownloading = true);

    try {
      // 1. 下载更新包
      final zipPath = await _downloader.download(widget.updateInfo.downloadUrl);
      if (zipPath == null) {
        _showError('下载失败，请稍后重试');
        return;
      }

      // 2. 解压更新包
      final extractPath = await _downloader.extractZip(zipPath);
      if (extractPath == null) {
        _showError('解压失败，请稍后重试');
        return;
      }

      // 3. 执行更新
      await _executeUpdate(extractPath);

      setState(() => _downloadComplete = true);
    } catch (e) {
      _showError('更新失败: $e');
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  Future<void> _executeUpdate(String updateFilesPath) async {
    try {
      // 获取当前应用的安装目录
      final exePath = Platform.resolvedExecutable;
      final appDir = File(exePath).parent.path;

      debugPrint('📂 应用目录: $appDir');
      debugPrint('📂 更新文件: $updateFilesPath');

      // 创建更新脚本（批处理文件）
      final scriptPath = '${Directory.systemTemp.path}\\xinghe_updater.bat';
      final script = '''
@echo off
echo 正在更新星橙AI动漫制作...
timeout /t 2 /nobreak > nul

REM 复制更新文件
xcopy /E /Y "$updateFilesPath\\*" "$appDir\\"

REM 重新启动应用
start "" "$exePath"

REM 删除临时文件
rd /s /q "$updateFilesPath"
del /f /q "$scriptPath"
''';

      await File(scriptPath).writeAsString(script);

      debugPrint('✅ 更新脚本已创建: $scriptPath');

      // 运行更新脚本
      await Process.start(
        'cmd.exe',
        ['/c', scriptPath],
        mode: ProcessStartMode.detached,
      );

      // 退出当前应用
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('更新程序已启动，应用即将重启...')),
        );
      }

      await Future.delayed(const Duration(seconds: 1));
      exit(0);
    } catch (e) {
      debugPrint('❌ 执行更新失败: $e');
      _showError('执行更新失败: $e');
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

    setState(() => _isDownloading = false);
  }
}
