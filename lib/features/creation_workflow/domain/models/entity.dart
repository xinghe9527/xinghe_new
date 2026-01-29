/// 实体/资产模型（角色、场景）
class Entity {
  final String id;
  final EntityType type;  // 角色/场景
  final String name;  // 名称（如：张三）
  final String fixedPrompt;  // 固定描述词（如：银发，红瞳，机能风外套）
  final bool isLocked;  // 是否锁定形象

  Entity({
    required this.id,
    required this.type,
    required this.name,
    this.fixedPrompt = '',
    this.isLocked = false,
  });

  Entity copyWith({
    String? id,
    EntityType? type,
    String? name,
    String? fixedPrompt,
    bool? isLocked,
  }) {
    return Entity(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      fixedPrompt: fixedPrompt ?? this.fixedPrompt,
      isLocked: isLocked ?? this.isLocked,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'name': name,
      'fixedPrompt': fixedPrompt,
      'isLocked': isLocked,
    };
  }

  factory Entity.fromJson(Map<String, dynamic> json) {
    return Entity(
      id: json['id'] as String,
      type: EntityType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => EntityType.character,
      ),
      name: json['name'] as String,
      fixedPrompt: json['fixedPrompt'] as String? ?? '',
      isLocked: json['isLocked'] as bool? ?? false,
    );
  }
}

/// 实体类型
enum EntityType {
  character,  // 角色
  scene,      // 场景
}

extension EntityTypeExt on EntityType {
  String get displayName {
    switch (this) {
      case EntityType.character:
        return '角色';
      case EntityType.scene:
        return '场景';
    }
  }
}
