/// 日志条目数据模型
class LogEntry {
  final String id;
  final DateTime timestamp;
  final LogLevel level;
  final String module; // 模块名称（绘图空间、视频空间等）
  final String action; // 操作描述
  final String? details; // 详细信息

  LogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.module,
    required this.action,
    this.details,
  });

  // 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'level': level.index,
      'module': module,
      'action': action,
      'details': details,
    };
  }

  // 从JSON恢复
  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      level: LogLevel.values[json['level'] as int],
      module: json['module'] as String,
      action: json['action'] as String,
      details: json['details'] as String?,
    );
  }
}

/// 日志级别
enum LogLevel {
  success, // 成功（绿色）
  error,   // 错误（红色）
  info,    // 信息（灰色）
  warning, // 警告（黄色）
}
