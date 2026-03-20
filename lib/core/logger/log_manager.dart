import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'log_entry.dart';
import 'error_translator.dart';

/// 全局日志管理器（单例）
class LogManager {
  static final LogManager _instance = LogManager._internal();
  factory LogManager() => _instance;
  LogManager._internal();

  final ValueNotifier<List<LogEntry>> logsNotifier = ValueNotifier([]);
  final int maxLogs = 500; // 最多保存500条日志
  Timer? _saveDebounceTimer;

  /// 添加日志
  void log({
    required LogLevel level,
    required String message,
    String? module,
    Map<String, dynamic>? extra,
  }) {
    final translatedExtra = extra != null ? _translateExtraKeys(extra) : null;
    final entry = LogEntry.create(
      level: level,
      message: message,
      module: module,
      extra: translatedExtra,
    );

    final logs = List<LogEntry>.from(logsNotifier.value);
    logs.insert(0, entry); // 新日志插入到最前面

    // 限制日志数量
    if (logs.length > maxLogs) {
      logs.removeRange(maxLogs, logs.length);
    }

    logsNotifier.value = logs;
    _debounceSave(); // 防抖保存
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

  /// 错误日志（自动翻译为通俗中文）
  void error(String message, {String? module, Map<String, dynamic>? extra}) {
    final translated = ErrorTranslator.translate(message);
    // 如果翻译后的消息和原始消息不同，把原始信息放到 extra 中方便调试
    Map<String, dynamic>? finalExtra = extra;
    if (translated != message) {
      finalExtra = {...?extra, '原始信息': message};
    }
    log(level: LogLevel.error, message: translated, module: module, extra: finalExtra);
  }

  /// 翻译 extra 字典的英文 key 为中文
  static const _keyTranslations = {
    'provider': '服务商',
    'path': '路径',
    'theme': '主题',
    'workflow': '工作流',
    'elapsed': '耗时(ms)',
    'model': '模型',
    'url': '地址',
    'URL': '地址',
    'status': '状态',
    'error': '错误',
    'file': '文件',
    'count': '数量',
    'size': '大小',
    'type': '类型',
    'name': '名称',
    'method': '方式',
    'result': '结果',
    'remainingImages': '剩余图片',
    'hasLoading': '有加载中',
    'newStatus': '新状态',
    'scriptPath': '脚本路径',
    'pythonPath': 'Python路径',
    'stdout': '标准输出',
    'stderr': '错误输出',
    'exitCode': '退出码',
    'taskId': '任务ID',
    'fileName': '文件名',
    'fileSize': '文件大小',
    'uploadUrl': '上传地址',
    'bucket': '存储桶',
    'objectKey': '对象路径',
    'speakerId': '说话人',
    'requestId': '请求ID',
  };

  Map<String, dynamic> _translateExtraKeys(Map<String, dynamic> extra) {
    return extra.map((key, value) {
      final translated = _keyTranslations[key] ?? key;
      // 同时翻译 TaskStatus.xxx 格式的值
      final translatedValue = value is String && value.startsWith('TaskStatus.')
          ? _translateTaskStatus(value)
          : value;
      return MapEntry(translated, translatedValue);
    });
  }

  String _translateTaskStatus(String status) {
    switch (status) {
      case 'TaskStatus.completed': return '已完成';
      case 'TaskStatus.generating': return '生成中';
      case 'TaskStatus.pending': return '等待中';
      case 'TaskStatus.failed': return '失败';
      default: return status;
    }
  }

  /// 仅输出到控制台的调试日志（不写入系统日志界面）
  void debug(String message, {String? module}) {
    final prefix = module != null ? '[$module] ' : '';
    debugPrint('$prefix$message');
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

  /// 防抖保存（2秒内多次写入只落盘一次）
  void _debounceSave() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(seconds: 2), _saveLogs);
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
