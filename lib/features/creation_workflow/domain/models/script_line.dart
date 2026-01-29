/// 剧本行模型
class ScriptLine {
  final String id;
  final String content;  // 中文剧本内容
  final ScriptLineType type;  // 动作/对白
  final String aiPrompt;  // AI生成的绘画提示词
  final List<String> contextTags;  // 上下文标签
  final bool hasContextMemory;  // 是否激活上下文记忆

  ScriptLine({
    required this.id,
    required this.content,
    required this.type,
    this.aiPrompt = '',
    this.contextTags = const [],
    this.hasContextMemory = true,
  });

  ScriptLine copyWith({
    String? id,
    String? content,
    ScriptLineType? type,
    String? aiPrompt,
    List<String>? contextTags,
    bool? hasContextMemory,
  }) {
    return ScriptLine(
      id: id ?? this.id,
      content: content ?? this.content,
      type: type ?? this.type,
      aiPrompt: aiPrompt ?? this.aiPrompt,
      contextTags: contextTags ?? this.contextTags,
      hasContextMemory: hasContextMemory ?? this.hasContextMemory,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'type': type.name,
      'aiPrompt': aiPrompt,
      'contextTags': contextTags,
      'hasContextMemory': hasContextMemory,
    };
  }

  factory ScriptLine.fromJson(Map<String, dynamic> json) {
    return ScriptLine(
      id: json['id'] as String,
      content: json['content'] as String,
      type: ScriptLineType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ScriptLineType.action,
      ),
      aiPrompt: json['aiPrompt'] as String? ?? '',
      contextTags: (json['contextTags'] as List<dynamic>?)?.cast<String>() ?? [],
      hasContextMemory: json['hasContextMemory'] as bool? ?? true,
    );
  }
}

/// 剧本行类型
enum ScriptLineType {
  action,    // 动作描述
  dialogue,  // 对白
}

extension ScriptLineTypeExt on ScriptLineType {
  String get displayName {
    switch (this) {
      case ScriptLineType.action:
        return '动作';
      case ScriptLineType.dialogue:
        return '对白';
    }
  }
}
