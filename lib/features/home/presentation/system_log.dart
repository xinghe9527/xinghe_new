import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xinghe_new/main.dart';
import 'package:xinghe_new/core/logger/log_manager.dart';
import 'package:xinghe_new/core/logger/log_entry.dart';
import 'package:intl/intl.dart';

class SystemLog extends StatefulWidget {
  const SystemLog({super.key});

  @override
  State<SystemLog> createState() => _SystemLogState();
}

class _SystemLogState extends State<SystemLog> {
  final LogManager _logManager = LogManager();
  final ScrollController _scrollController = ScrollController();
  LogLevel? _filterLevel; // 日志级别筛选

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<LogEntry> get _filteredLogs {
    if (_filterLevel == null) {
      return _logManager.logsNotifier.value;
    }
    return _logManager.logsNotifier.value.where((log) => log.level == _filterLevel).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: themeNotifier,
      builder: (context, _, __) {
        return Container(
          color: AppTheme.scaffoldBackground,
          child: Column(
            children: [
              _buildToolbar(),
              Expanded(
                child: ValueListenableBuilder<List<LogEntry>>(
                  valueListenable: _logManager.logsNotifier,
                  builder: (context, logs, _) {
                    final filteredLogs = _filteredLogs;
                    
                    if (filteredLogs.isEmpty) {
                      return _buildEmptyState();
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredLogs.length,
                      itemBuilder: (context, index) {
                        return _LogItem(log: filteredLogs[index]);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBackground,
        border: Border(bottom: BorderSide(color: AppTheme.dividerColor)),
      ),
      child: Row(
        children: [
          Icon(Icons.terminal_rounded, color: AppTheme.textColor, size: 20),
          const SizedBox(width: 12),
          Text('系统日志', style: TextStyle(color: AppTheme.textColor, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(width: 24),
          _buildFilterChip(null, '全部', Icons.list),
          const SizedBox(width: 8),
          _buildFilterChip(LogLevel.success, '成功', Icons.check_circle_outline),
          const SizedBox(width: 8),
          _buildFilterChip(LogLevel.info, '信息', Icons.info_outline),
          const SizedBox(width: 8),
          _buildFilterChip(LogLevel.warning, '警告', Icons.warning_amber_outlined),
          const SizedBox(width: 8),
          _buildFilterChip(LogLevel.error, '错误', Icons.error_outline),
          const Spacer(),
          _toolButton(Icons.file_download_outlined, '导出日志', () {
            final content = _logManager.exportLogs();
            Clipboard.setData(ClipboardData(text: content));
            _showMessage('日志已复制到剪贴板');
          }),
          const SizedBox(width: 12),
          _toolButton(Icons.delete_sweep_rounded, '清空日志', () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: AppTheme.surfaceBackground,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: Text('清空日志', style: TextStyle(color: AppTheme.textColor)),
                content: Text('确定要清空所有日志吗？此操作不可恢复。', style: TextStyle(color: AppTheme.subTextColor)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('取消', style: TextStyle(color: AppTheme.subTextColor)),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _logManager.clearLogs();
                      _showMessage('日志已清空');
                    },
                    child: const Text('确定', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );
          }, color: Colors.red),
        ],
      ),
    );
  }

  Widget _buildFilterChip(LogLevel? level, String label, IconData icon) {
    final isSelected = _filterLevel == level;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _filterLevel = level),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.accentColor.withOpacity(0.15) : AppTheme.inputBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppTheme.accentColor : AppTheme.dividerColor,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: isSelected ? AppTheme.accentColor : AppTheme.subTextColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppTheme.accentColor : AppTheme.subTextColor,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolButton(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.textColor.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon, color: color ?? AppTheme.subTextColor, size: 16),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color ?? AppTheme.subTextColor, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 100, color: AppTheme.subTextColor.withOpacity(0.2)),
          const SizedBox(height: 24),
          Text('暂无系统日志', style: TextStyle(color: AppTheme.textColor, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('所有操作都会在这里显示记录', style: TextStyle(color: AppTheme.subTextColor, fontSize: 14)),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF2AF598),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _LogItem extends StatelessWidget {
  final LogEntry log;

  const _LogItem({required this.log});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _getBorderColor()),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 日志级别图标
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _getBackgroundColor(),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(_getIcon(), size: 16, color: _getColor()),
          ),
          const SizedBox(width: 12),
          // 日志内容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (log.module != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.inputBackground,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          log.module!,
                          style: TextStyle(
                            color: AppTheme.subTextColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      _getLevelText(),
                      style: TextStyle(
                        color: _getColor(),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatTime(log.timestamp),
                      style: TextStyle(
                        color: AppTheme.subTextColor,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  log.message,
                  style: TextStyle(
                    color: AppTheme.textColor,
                    fontSize: 13,
                  ),
                ),
                if (log.extra != null && log.extra!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.inputBackground,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      log.extra.toString(),
                      style: TextStyle(
                        color: AppTheme.subTextColor,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getColor() {
    switch (log.level) {
      case LogLevel.success:
        return const Color(0xFF22C55E);
      case LogLevel.info:
        return const Color(0xFF3B82F6);
      case LogLevel.warning:
        return const Color(0xFFF59E0B);
      case LogLevel.error:
        return const Color(0xFFEF4444);
    }
  }

  Color _getBackgroundColor() {
    return _getColor().withOpacity(0.1);
  }

  Color _getBorderColor() {
    return _getColor().withOpacity(0.2);
  }

  IconData _getIcon() {
    switch (log.level) {
      case LogLevel.success:
        return Icons.check_circle;
      case LogLevel.info:
        return Icons.info;
      case LogLevel.warning:
        return Icons.warning_amber;
      case LogLevel.error:
        return Icons.error;
    }
  }

  String _getLevelText() {
    switch (log.level) {
      case LogLevel.success:
        return '成功';
      case LogLevel.info:
        return '信息';
      case LogLevel.warning:
        return '警告';
      case LogLevel.error:
        return '错误';
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) {
      return '刚刚';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}分钟前';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}小时前';
    } else {
      return DateFormat('MM-dd HH:mm').format(time);
    }
  }
}
