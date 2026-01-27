import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'log_entry.dart';

/// 全局日志管理器（单例）
class LogManager {
  static final LogManager _instance = LogManager._internal();
  factory LogManager() => _instance;
  LogManager._internal();

  final ValueNotifier<List<LogEntry>> logsNotifier = ValueNotifier([]);
  final int maxLogs = 500; // 最多保存500条日志

  /// 添加日志
  void log({
    required LogLevel level,
    required String message,
    String? module,
    Map<String, dynamic>? extra,
  }) {
    final entry = LogEntry.create(
      level: level,
      message: message,
      module: module,
      extra: extra,
    );

    final logs = List<LogEntry>.from(logsNotifier.value);
    logs.insert(0, entry); // 新日志插入到最前面

    // 限制日志数量
    if (logs.length > maxLogs) {
      logs.removeRange(maxLogs, logs.length);
    }

    logsNotifier.value = logs;
    _saveLogs(); // 自动保存
  }

  /// 成功日志
  void success(String message, {String? module, Map<String, dynamic>? extra}) {
    log(level: LogLevel.success, message: message, module: module, extra: extra);
  }

  /// 信息日志
  void info(String message, {String? module, Map<String, dynamic>? extra}) {
    log(level: LogLevel.info, message: message, module: module, extra: extra);
  }

  /// 警告日志
  void warning(String message, {String? module, Map<String, dynamic>? extra}) {
    log(level: LogLevel.warning, message: message, module: module, extra: extra);
  }

  /// 错误日志
  void error(String message, {String? module, Map<String, dynamic>? extra}) {
    log(level: LogLevel.error, message: message, module: module, extra: extra);
  }

  /// 清空所有日志
  void clearLogs() {
    logsNotifier.value = [];
    _saveLogs();
  }

  /// 加载保存的日志
  Future<void> loadLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logsJson = prefs.getString('system_logs');
      if (logsJson != null && logsJson.isNotEmpty) {
        final logsList = jsonDecode(logsJson) as List;
        logsNotifier.value = logsList.map((json) => LogEntry.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint('加载日志失败: $e');
    }
  }

  /// 保存日志
  Future<void> _saveLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 只保存最近100条日志到持久化存储
      final logsToSave = logsNotifier.value.take(100).toList();
      await prefs.setString('system_logs', jsonEncode(logsToSave.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('保存日志失败: $e');
    }
  }

  /// 导出日志（用于调试或用户反馈）
  String exportLogs() {
    final buffer = StringBuffer();
    buffer.writeln('=== 系统日志导出 ===');
    buffer.writeln('导出时间: ${DateTime.now()}');
    buffer.writeln('日志总数: ${logsNotifier.value.length}');
    buffer.writeln('');
    
    for (final log in logsNotifier.value) {
      buffer.writeln('[${log.timestamp}] [${log.level.name.toUpperCase()}] ${log.module ?? 'SYSTEM'}: ${log.message}');
      if (log.extra != null) {
        buffer.writeln('  额外信息: ${log.extra}');
      }
    }
    
    return buffer.toString();
  }
}
