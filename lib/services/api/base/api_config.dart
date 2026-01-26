/// API配置模型
class ApiConfig {
  final String provider; // 服务商名称 (openai, anthropic, custom等)
  final String apiKey;
  final String baseUrl;
  final String? model;
  
  const ApiConfig({
    required this.provider,
    required this.apiKey,
    required this.baseUrl,
    this.model,
  });

  // 从JSON创建
  factory ApiConfig.fromJson(Map<String, dynamic> json) {
    return ApiConfig(
      provider: json['provider'] as String,
      apiKey: json['apiKey'] as String,
      baseUrl: json['baseUrl'] as String,
      model: json['model'] as String?,
    );
  }

  // 转换为JSON（注意：不应该序列化apiKey到本地文件）
  Map<String, dynamic> toJson() {
    return {
      'provider': provider,
      'baseUrl': baseUrl,
      'model': model,
      // 注意：apiKey不序列化到JSON，而是通过安全存储单独保存
    };
  }

  ApiConfig copyWith({
    String? provider,
    String? apiKey,
    String? baseUrl,
    String? model,
  }) {
    return ApiConfig(
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
    );
  }
}
