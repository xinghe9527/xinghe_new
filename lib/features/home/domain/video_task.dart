/// 视频任务数据模型
class VideoTask {
  final String id;
  String model;
  String ratio;
  String quality;
  int batchCount;
  String seconds;  // 时长选择
  String prompt;
  List<String> referenceImages;
  List<String> generatedVideos;
  TaskStatus status;

  VideoTask({
    required this.id,
    this.model = 'Runway Gen-3',
    this.ratio = '16:9',
    this.quality = '1080P',
    this.batchCount = 1,
    this.seconds = '10秒',  // 默认10秒
    this.prompt = '',
    List<String>? referenceImages,
    List<String>? generatedVideos,
    this.status = TaskStatus.idle,
  })  : referenceImages = referenceImages ?? [],
        generatedVideos = generatedVideos ?? [];

  // 创建新任务
  factory VideoTask.create() {
    return VideoTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  // 从JSON恢复
  factory VideoTask.fromJson(Map<String, dynamic> json) {
    return VideoTask(
      id: json['id'] as String,
      model: json['model'] as String? ?? 'Runway Gen-3',
      ratio: json['ratio'] as String? ?? '16:9',
      quality: json['quality'] as String? ?? '1080P',
      batchCount: json['batchCount'] as int? ?? 1,
      seconds: json['seconds'] as String? ?? '10秒',
      prompt: json['prompt'] as String? ?? '',
      referenceImages: (json['referenceImages'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ?? [],
      generatedVideos: (json['generatedVideos'] as List<dynamic>?)
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
      'seconds': seconds,
      'prompt': prompt,
      'referenceImages': referenceImages,
      'generatedVideos': generatedVideos,
      'status': status.index,
    };
  }

  VideoTask copyWith({
    String? model,
    String? ratio,
    String? quality,
    int? batchCount,
    String? seconds,
    String? prompt,
    List<String>? referenceImages,
    List<String>? generatedVideos,
    TaskStatus? status,
  }) {
    return VideoTask(
      id: id,
      model: model ?? this.model,
      ratio: ratio ?? this.ratio,
      quality: quality ?? this.quality,
      batchCount: batchCount ?? this.batchCount,
      seconds: seconds ?? this.seconds,
      prompt: prompt ?? this.prompt,
      referenceImages: referenceImages ?? this.referenceImages,
      generatedVideos: generatedVideos ?? this.generatedVideos,
      status: status ?? this.status,
    );
  }
}

/// 任务状态枚举（复用DrawingTask的枚举）
enum TaskStatus {
  idle,       // 等待中
  generating, // 生成中
  completed,  // 已完成
  failed,     // 失败
}
