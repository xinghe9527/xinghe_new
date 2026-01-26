/// 绘图任务数据模型
class DrawingTask {
  final String id;
  String model;
  String ratio;
  String quality;
  int batchCount;
  String prompt;
  List<String> referenceImages;
  List<String> generatedImages;
  TaskStatus status;

  DrawingTask({
    required this.id,
    this.model = 'DALL-E 3',
    this.ratio = '1:1',
    this.quality = '2K',
    this.batchCount = 1,
    this.prompt = '',
    List<String>? referenceImages,
    List<String>? generatedImages,
    this.status = TaskStatus.idle,
  })  : referenceImages = referenceImages ?? [],
        generatedImages = generatedImages ?? [];

  // 创建新任务
  factory DrawingTask.create() {
    return DrawingTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  // 从JSON恢复
  factory DrawingTask.fromJson(Map<String, dynamic> json) {
    return DrawingTask(
      id: json['id'] as String,
      model: json['model'] as String? ?? 'DALL-E 3',
      ratio: json['ratio'] as String? ?? '1:1',
      quality: json['quality'] as String? ?? '2K',
      batchCount: json['batchCount'] as int? ?? 1,
      prompt: json['prompt'] as String? ?? '',
      referenceImages: (json['referenceImages'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ?? [],
      generatedImages: (json['generatedImages'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ?? [],
      status: TaskStatus.values[json['status'] as int? ?? 0],
    );
  }

  // 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'model': model,
      'ratio': ratio,
      'quality': quality,
      'batchCount': batchCount,
      'prompt': prompt,
      'referenceImages': referenceImages,
      'generatedImages': generatedImages,
      'status': status.index,
    };
  }

  DrawingTask copyWith({
    String? model,
    String? ratio,
    String? quality,
    int? batchCount,
    String? prompt,
    List<String>? referenceImages,
    List<String>? generatedImages,
    TaskStatus? status,
  }) {
    return DrawingTask(
      id: id,
      model: model ?? this.model,
      ratio: ratio ?? this.ratio,
      quality: quality ?? this.quality,
      batchCount: batchCount ?? this.batchCount,
      prompt: prompt ?? this.prompt,
      referenceImages: referenceImages ?? this.referenceImages,
      generatedImages: generatedImages ?? this.generatedImages,
      status: status ?? this.status,
    );
  }
}

/// 任务状态枚举
enum TaskStatus {
  idle,       // 等待中
  generating, // 生成中
  completed,  // 已完成
  failed,     // 失败
}
