import 'script_line.dart';
import 'entity.dart';
import 'storyboard.dart';
import 'video_clip.dart';

/// 项目模型（完整的创作流数据）
class Project {
  final String id;
  final String name;  // 项目名称
  final List<ScriptLine> scriptLines;  // 剧本列表
  final List<Entity> entities;  // 实体/资产列表
  final List<Storyboard> storyboards;  // 分镜列表
  final List<VideoClip> videoClips;  // 视频片段列表
  final int currentStep;  // 当前步骤（1-4）
  final DateTime createdAt;
  final DateTime updatedAt;

  Project({
    required this.id,
    required this.name,
    this.scriptLines = const [],
    this.entities = const [],
    this.storyboards = const [],
    this.videoClips = const [],
    this.currentStep = 1,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Project copyWith({
    String? id,
    String? name,
    List<ScriptLine>? scriptLines,
    List<Entity>? entities,
    List<Storyboard>? storyboards,
    List<VideoClip>? videoClips,
    int? currentStep,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      scriptLines: scriptLines ?? this.scriptLines,
      entities: entities ?? this.entities,
      storyboards: storyboards ?? this.storyboards,
      videoClips: videoClips ?? this.videoClips,
      currentStep: currentStep ?? this.currentStep,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'scriptLines': scriptLines.map((e) => e.toJson()).toList(),
      'entities': entities.map((e) => e.toJson()).toList(),
      'storyboards': storyboards.map((e) => e.toJson()).toList(),
      'videoClips': videoClips.map((e) => e.toJson()).toList(),
      'currentStep': currentStep,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String,
      name: json['name'] as String,
      scriptLines: (json['scriptLines'] as List<dynamic>?)
              ?.map((e) => ScriptLine.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      entities: (json['entities'] as List<dynamic>?)
              ?.map((e) => Entity.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      storyboards: (json['storyboards'] as List<dynamic>?)
              ?.map((e) => Storyboard.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      videoClips: (json['videoClips'] as List<dynamic>?)
              ?.map((e) => VideoClip.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      currentStep: json['currentStep'] as int? ?? 1,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  /// 创建空项目
  factory Project.empty({required String name}) {
    return Project(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
    );
  }
}
