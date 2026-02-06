/// 语音素材数据模型
class VoiceAsset {
  final String id;
  final String name;              // 角色名称（如：小明、小红）
  final String audioPath;         // 音频文件路径
  final String? coverImagePath;   // 封面图路径
  final String gender;            // 性别：男生/女生
  final String style;             // 风格：解说/疑惑/叙事语气等
  final DateTime addedTime;       // 添加时间
  final String? description;      // 描述（可选）
  
  // ✅ 情感控制配置
  final String emotionControlMode;       // 情感控制模式
  final String? emotionAudioPath;        // 情感参考音频路径
  final List<double> emotionVector;      // 情感向量
  final String emotionText;              // 文本情感描述
  final double emotionAlpha;             // 情感权重
  final bool useRandomSampling;          // 随机采样

  VoiceAsset({
    required this.id,
    required this.name,
    required this.audioPath,
    this.coverImagePath,
    this.gender = '男生',
    this.style = '解说',
    required this.addedTime,
    this.description,
    this.emotionControlMode = '使用文本描述',
    this.emotionAudioPath,
    List<double>? emotionVector,
    this.emotionText = '',
    this.emotionAlpha = 0.6,
    this.useRandomSampling = false,
  }) : emotionVector = emotionVector ?? [0, 0, 0, 0, 0, 0, 0, 0];

  factory VoiceAsset.fromJson(Map<String, dynamic> json) {
    return VoiceAsset(
      id: json['id'] as String,
      name: json['name'] as String,
      audioPath: json['audioPath'] as String,
      coverImagePath: json['coverImagePath'] as String?,
      gender: json['gender'] as String? ?? '男生',
      style: json['style'] as String? ?? '解说',
      addedTime: DateTime.parse(json['addedTime'] as String),
      description: json['description'] as String?,
      emotionControlMode: json['emotionControlMode'] as String? ?? '使用文本描述',
      emotionAudioPath: json['emotionAudioPath'] as String?,
      emotionVector: (json['emotionVector'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList(),
      emotionText: json['emotionText'] as String? ?? '',
      emotionAlpha: (json['emotionAlpha'] as num?)?.toDouble() ?? 0.6,
      useRandomSampling: json['useRandomSampling'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'audioPath': audioPath,
      'coverImagePath': coverImagePath,
      'gender': gender,
      'style': style,
      'addedTime': addedTime.toIso8601String(),
      'description': description,
      'emotionControlMode': emotionControlMode,
      'emotionAudioPath': emotionAudioPath,
      'emotionVector': emotionVector,
      'emotionText': emotionText,
      'emotionAlpha': emotionAlpha,
      'useRandomSampling': useRandomSampling,
    };
  }

  VoiceAsset copyWith({
    String? name,
    String? audioPath,
    String? coverImagePath,
    String? gender,
    String? style,
    String? description,
    String? emotionControlMode,
    String? emotionAudioPath,
    List<double>? emotionVector,
    String? emotionText,
    double? emotionAlpha,
    bool? useRandomSampling,
  }) {
    return VoiceAsset(
      id: id,
      name: name ?? this.name,
      audioPath: audioPath ?? this.audioPath,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      gender: gender ?? this.gender,
      style: style ?? this.style,
      addedTime: addedTime,
      description: description ?? this.description,
      emotionControlMode: emotionControlMode ?? this.emotionControlMode,
      emotionAudioPath: emotionAudioPath ?? this.emotionAudioPath,
      emotionVector: emotionVector ?? this.emotionVector,
      emotionText: emotionText ?? this.emotionText,
      emotionAlpha: emotionAlpha ?? this.emotionAlpha,
      useRandomSampling: useRandomSampling ?? this.useRandomSampling,
    );
  }
}
