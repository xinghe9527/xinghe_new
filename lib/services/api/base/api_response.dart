/// 统一的API响应模型
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? error;
  final int? statusCode;

  const ApiResponse({
    required this.success,
    this.data,
    this.error,
    this.statusCode,
  });

  // 成功响应
  factory ApiResponse.success(T data, {int? statusCode}) {
    return ApiResponse(
      success: true,
      data: data,
      statusCode: statusCode,
    );
  }

  // 失败响应
  factory ApiResponse.failure(String error, {int? statusCode}) {
    return ApiResponse(
      success: false,
      error: error,
      statusCode: statusCode,
    );
  }

  // 便捷 getter
  bool get isSuccess => success;
  bool get isFailure => !success;
  String? get errorMessage => error;
}

/// LLM文本生成响应
class LlmResponse {
  final String text;
  final int? tokensUsed;
  final Map<String, dynamic>? metadata;

  const LlmResponse({
    required this.text,
    this.tokensUsed,
    this.metadata,
  });
}

/// 图片生成响应
class ImageResponse {
  final String imageUrl;
  final String? imageId;
  final Map<String, dynamic>? metadata;

  const ImageResponse({
    required this.imageUrl,
    this.imageId,
    this.metadata,
  });
}

/// 视频生成响应
class VideoResponse {
  final String videoUrl;
  final String? videoId;
  final int? duration;
  final Map<String, dynamic>? metadata;

  const VideoResponse({
    required this.videoUrl,
    this.videoId,
    this.duration,
    this.metadata,
  });
}

/// 素材上传响应
class UploadResponse {
  final String uploadId;
  final String uploadUrl;
  final Map<String, dynamic>? metadata;

  const UploadResponse({
    required this.uploadId,
    required this.uploadUrl,
    this.metadata,
  });
}
