/// 分镜模型
class Storyboard {
  final String id;
  final String scriptLineId;  // 关联的剧本行ID
  final String imageUrl;  // 生成的图片URL
  final String finalPrompt;  // 最终使用的提示词
  final bool isConfirmed;  // 是否已确认
  final DateTime createdAt;

  Storyboard({
    required this.id,
    required this.scriptLineId,
    this.imageUrl = '',
    this.finalPrompt = '',
    this.isConfirmed = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Storyboard copyWith({
    String? id,
    String? scriptLineId,
    String? imageUrl,
    String? finalPrompt,
    bool? isConfirmed,
    DateTime? createdAt,
  }) {
    return Storyboard(
      id: id ?? this.id,
      scriptLineId: scriptLineId ?? this.scriptLineId,
      imageUrl: imageUrl ?? this.imageUrl,
      finalPrompt: finalPrompt ?? this.finalPrompt,
      isConfirmed: isConfirmed ?? this.isConfirmed,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'scriptLineId': scriptLineId,
      'imageUrl': imageUrl,
      'finalPrompt': finalPrompt,
      'isConfirmed': isConfirmed,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Storyboard.fromJson(Map<String, dynamic> json) {
    return Storyboard(
      id: json['id'] as String,
      scriptLineId: json['scriptLineId'] as String,
      imageUrl: json['imageUrl'] as String? ?? '',
      finalPrompt: json['finalPrompt'] as String? ?? '',
      isConfirmed: json['isConfirmed'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }
}
