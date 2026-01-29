import 'api_config.dart';
import 'api_response.dart';

/// API服务抽象基类
/// 所有API服务商都必须实现这个接口
abstract class ApiServiceBase {
  final ApiConfig config;

  ApiServiceBase(this.config);

  /// 服务商名称
  String get providerName;

  /// 测试API连接
  Future<ApiResponse<bool>> testConnection();

  /// LLM文本生成（简单接口）
  Future<ApiResponse<LlmResponse>> generateText({
    required String prompt,
    String? model,
    Map<String, dynamic>? parameters,
  });

  /// LLM文本生成（支持完整 messages 数组）
  Future<ApiResponse<LlmResponse>> generateTextWithMessages({
    required List<Map<String, String>> messages,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    // 默认实现：使用最后一条消息作为 prompt
    final lastMessage = messages.isNotEmpty ? messages.last['content'] ?? '' : '';
    return await generateText(
      prompt: lastMessage,
      model: model,
      parameters: parameters,
    );
  }

  /// 图片生成
  Future<ApiResponse<List<ImageResponse>>> generateImages({
    required String prompt,
    String? model,
    int count = 1,
    String? ratio,
    String? quality,
    List<String>? referenceImages,
    Map<String, dynamic>? parameters,
  });

  /// 视频生成
  Future<ApiResponse<List<VideoResponse>>> generateVideos({
    required String prompt,
    String? model,
    int count = 1,
    String? ratio,
    String? quality,
    List<String>? referenceImages,
    Map<String, dynamic>? parameters,
  });

  /// 上传素材
  Future<ApiResponse<UploadResponse>> uploadAsset({
    required String filePath,
    String? assetType,
    Map<String, dynamic>? metadata,
  });

  /// 获取可用模型列表
  Future<ApiResponse<List<String>>> getAvailableModels({
    String? modelType, // 'llm', 'image', 'video'
  });
}
