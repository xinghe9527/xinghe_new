/// 日志条目数据模型
class LogEntry {
  final String id;
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? module; // 模块名称（绘图空间、视频空间等）
  final Map<String, dynamic>? extra; // 额外信息

  LogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.message,
    this.module,
    this.extra,
  });

  factory LogEntry.create({
    required LogLevel level,
    required String message,
    String? module,
    Map<String, dynamic>? extra,
  }) {
    return LogEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      level: level,
      message: message,
      module: module,
      extra: extra,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'level': level.index,
      'message': message,
      'module': module,
      'extra': extra,
    };
  }

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      level: LogLevel.values[json['level'] as int],
      message: json['message'] as String,
      module: json['module'] as String?,
      extra: json['extra'] as Map<String, dynamic>?,
    );
  }
}

/// 日志级别枚举
enum LogLevel {
  success, // 成功 - 绿色
  info,    // 信息 - 蓝色
  warning, // 警告 - 橙色
  error,   // 错误 - 红色
}
