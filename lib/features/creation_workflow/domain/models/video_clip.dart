/// 视频片段模型
class VideoClip {
  final String id;
  final String storyboardId;  // 关联的分镜ID
  final String videoUrl;  // 生成的视频URL
  final VideoGenerationMode generationMode;  // 生成模式
  final String? startFrameUrl;  // 起始帧图片URL（模式C使用）
  final String? endFrameUrl;  // 结束帧图片URL（模式C使用）
  final Map<String, dynamic> parameters;  // 其他参数
  final VideoClipStatus status;  // 生成状态
  final DateTime createdAt;

  VideoClip({
    required this.id,
    required this.storyboardId,
    this.videoUrl = '',
    required this.generationMode,
    this.startFrameUrl,
    this.endFrameUrl,
    this.parameters = const {},
    this.status = VideoClipStatus.pending,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  VideoClip copyWith({
    String? id,
    String? storyboardId,
    String? videoUrl,
    VideoGenerationMode? generationMode,
    String? startFrameUrl,
    String? endFrameUrl,
    Map<String, dynamic>? parameters,
    VideoClipStatus? status,
    DateTime? createdAt,
  }) {
    return VideoClip(
      id: id ?? this.id,
      storyboardId: storyboardId ?? this.storyboardId,
      videoUrl: videoUrl ?? this.videoUrl,
      generationMode: generationMode ?? this.generationMode,
      startFrameUrl: startFrameUrl ?? this.startFrameUrl,
      endFrameUrl: endFrameUrl ?? this.endFrameUrl,
      parameters: parameters ?? this.parameters,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'storyboardId': storyboardId,
      'videoUrl': videoUrl,
      'generationMode': generationMode.name,
      'startFrameUrl': startFrameUrl,
      'endFrameUrl': endFrameUrl,
      'parameters': parameters,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory VideoClip.fromJson(Map<String, dynamic> json) {
    return VideoClip(
      id: json['id'] as String,
      storyboardId: json['storyboardId'] as String,
      videoUrl: json['videoUrl'] as String? ?? '',
      generationMode: VideoGenerationMode.values.firstWhere(
        (e) => e.name == json['generationMode'],
        orElse: () => VideoGenerationMode.textToVideo,
      ),
      startFrameUrl: json['startFrameUrl'] as String?,
      endFrameUrl: json['endFrameUrl'] as String?,
      parameters: json['parameters'] as Map<String, dynamic>? ?? {},
      status: VideoClipStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => VideoClipStatus.pending,
      ),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }
}

/// 视频生成模式
enum VideoGenerationMode {
  textToVideo,    // 模式A：文生视频
  imageToVideo,   // 模式B：图生视频
  keyframes,      // 模式C：首尾帧控制
}

extension VideoGenerationModeExt on VideoGenerationMode {
  String get displayName {
    switch (this) {
      case VideoGenerationMode.textToVideo:
        return '文生视频';
      case VideoGenerationMode.imageToVideo:
        return '图生视频';
      case VideoGenerationMode.keyframes:
        return '首尾帧控制';
    }
  }

  String get description {
    switch (this) {
      case VideoGenerationMode.textToVideo:
        return '直接用文字生成视频';
      case VideoGenerationMode.imageToVideo:
        return '使用分镜图片作为参考生成';
      case VideoGenerationMode.keyframes:
        return '控制起始帧和结束帧生成';
    }
  }
}

/// 视频片段状态
enum VideoClipStatus {
  pending,     // 等待生成
  generating,  // 生成中
  completed,   // 已完成
  failed,      // 失败
}

extension VideoClipStatusExt on VideoClipStatus {
  String get displayName {
    switch (this) {
      case VideoClipStatus.pending:
        return '等待中';
      case VideoClipStatus.generating:
        return '生成中';
      case VideoClipStatus.completed:
        return '已完成';
      case VideoClipStatus.failed:
        return '失败';
    }
  }
}
