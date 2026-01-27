import 'dart:convert';
import 'package:http/http.dart' as http;
import '../base/api_service_base.dart';
import '../base/api_config.dart';
import '../base/api_response.dart';

/// Gemini 图像生成服务
/// 支持文生图和图生图功能
class GeminiImageService extends ApiServiceBase {
  GeminiImageService(super.config);

  @override
  String get providerName => 'Gemini Image';

  @override
  Future<ApiResponse<bool>> testConnection() async {
    try {
      // 尝试调用模型列表接口测试连接
      final result = await getAvailableModels(modelType: 'image');
      return ApiResponse.success(
        result.isSuccess,
        statusCode: result.statusCode,
      );
    } catch (e) {
      return ApiResponse.failure('连接测试失败: $e');
    }
  }

  @override
  Future<ApiResponse<LlmResponse>> generateText({
    required String prompt,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    // Gemini Image 服务主要用于图像生成，不支持纯文本生成
    return ApiResponse.failure('Gemini Image 服务不支持纯文本生成');
  }

  @override
  Future<ApiResponse<List<ImageResponse>>> generateImages({
    required String prompt,
    String? model,
    int count = 1,
    String? ratio,
    String? quality,
    List<String>? referenceImages,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      final targetModel = model ?? config.model ?? 'gemini-2.5-flash-image';
      
      // 构建请求体
      final requestBody = _buildImageGenerationRequest(
        prompt: prompt,
        ratio: ratio,
        quality: quality,
        referenceImages: referenceImages,
        parameters: parameters,
      );

      // 发送请求
      final response = await http.post(
        Uri.parse('${config.baseUrl}/v1beta/models/$targetModel:generateContent'),
        headers: _buildHeaders(),
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        return _parseImageResponse(response.body);
      } else {
        return ApiResponse.failure(
          '图像生成失败: ${response.statusCode} - ${response.body}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('图像生成错误: $e');
    }
  }

  @override
  Future<ApiResponse<List<VideoResponse>>> generateVideos({
    required String prompt,
    String? model,
    int count = 1,
    String? ratio,
    String? quality,
    List<String>? referenceImages,
    Map<String, dynamic>? parameters,
  }) async {
    // Gemini Image 服务不支持视频生成
    return ApiResponse.failure('Gemini Image 服务不支持视频生成');
  }

  @override
  Future<ApiResponse<UploadResponse>> uploadAsset({
    required String filePath,
    String? assetType,
    Map<String, dynamic>? metadata,
  }) async {
    // Gemini 使用 inline_data 方式传递图片，不需要单独上传
    return ApiResponse.failure('Gemini 服务使用 inline_data 方式，无需单独上传');
  }

  @override
  Future<ApiResponse<List<String>>> getAvailableModels({
    String? modelType,
  }) async {
    // 返回支持的 Gemini 图像模型列表
    final models = [
      'gemini-2.5-flash-image',
      'gemini-2.0-flash-exp-image',
    ];
    
    return ApiResponse.success(models, statusCode: 200);
  }

  // ==================== 私有方法 ====================

  /// 构建请求头
  Map<String, String> _buildHeaders() {
    return {
      'Authorization': config.apiKey,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  /// 构建图像生成请求体
  Map<String, dynamic> _buildImageGenerationRequest({
    required String prompt,
    String? ratio,
    String? quality,
    List<String>? referenceImages,
    Map<String, dynamic>? parameters,
  }) {
    // 构建 parts 数组
    final parts = <Map<String, dynamic>>[];
    
    // 添加文本提示词
    parts.add({'text': prompt});
    
    // 添加参考图片（如果有）
    if (referenceImages != null && referenceImages.isNotEmpty) {
      for (final imageData in referenceImages) {
        parts.add({
          'inline_data': {
            'mime_type': 'image/jpeg',
            'data': imageData, // Base64 编码的图片数据
          }
        });
      }
    }

    // 构建请求体
    final request = {
      'contents': [
        {
          'role': 'user',
          'parts': parts,
        }
      ],
      'generationConfig': {
        'responseModalities': ['TEXT', 'IMAGE'],
        'imageConfig': {
          'aspectRatio': ratio ?? '16:9',
          'imageSize': quality ?? '1K',
        }
      },
    };

    // 添加安全设置（如果提供）
    if (parameters?['safetySettings'] != null) {
      request['safetySettings'] = parameters!['safetySettings'];
    }

    return request;
  }

  /// 解析图像生成响应
  ApiResponse<List<ImageResponse>> _parseImageResponse(String responseBody) {
    try {
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        return ApiResponse.failure('未返回生成结果');
      }

      final images = <ImageResponse>[];
      
      for (final candidate in candidates) {
        final content = candidate['content'] as Map<String, dynamic>?;
        if (content == null) continue;
        
        final parts = content['parts'] as List?;
        if (parts == null) continue;
        
        for (final part in parts) {
          final inlineData = part['inline_data'] as Map<String, dynamic>?;
          if (inlineData != null) {
            final imageData = inlineData['data'] as String?;
            final mimeType = inlineData['mime_type'] as String?;
            
            if (imageData != null) {
              images.add(ImageResponse(
                imageUrl: 'data:$mimeType;base64,$imageData',
                imageId: data['responseId'] as String?,
                metadata: {
                  'mimeType': mimeType,
                  'modelVersion': data['modelVersion'],
                  'createTime': data['createTime'],
                  'usageMetadata': data['usageMetadata'],
                },
              ));
            }
          }
        }
      }

      if (images.isEmpty) {
        return ApiResponse.failure('响应中未包含图像数据');
      }

      return ApiResponse.success(images, statusCode: 200);
    } catch (e) {
      return ApiResponse.failure('解析响应失败: $e');
    }
  }
}

/// Gemini 图像生成辅助类
/// 提供便捷的图像生成方法
class GeminiImageHelper {
  final GeminiImageService service;

  GeminiImageHelper(this.service);

  /// 文生图
  /// 
  /// 参数：
  /// - prompt: 图像描述文本
  /// - ratio: 宽高比，可选值: '1:1', '16:9', '9:16', '4:3', '3:4'
  /// - quality: 图像清晰度，可选值: '1K', '2K', '4K'
  Future<ApiResponse<List<ImageResponse>>> textToImage({
    required String prompt,
    String ratio = '16:9',
    String quality = '1K',
  }) async {
    return service.generateImages(
      prompt: prompt,
      ratio: ratio,
      quality: quality,
    );
  }

  /// 图生图（融合图片）
  /// 
  /// 参数：
  /// - prompt: 融合描述文本
  /// - referenceImages: 参考图片的 Base64 编码数据列表
  /// - ratio: 宽高比
  /// - quality: 图像清晰度
  Future<ApiResponse<List<ImageResponse>>> imageToImage({
    required String prompt,
    required List<String> referenceImages,
    String ratio = '16:9',
    String quality = '2K',
  }) async {
    return service.generateImages(
      prompt: prompt,
      ratio: ratio,
      quality: quality,
      referenceImages: referenceImages,
    );
  }

  /// 设置安全过滤级别
  /// 
  /// 返回可用于 parameters 参数的安全设置
  Map<String, dynamic> createSafetySettings({
    String harmCategory = 'HARM_CATEGORY_DANGEROUS_CONTENT',
    String threshold = 'BLOCK_MEDIUM_AND_ABOVE',
  }) {
    return {
      'safetySettings': [
        {
          'category': harmCategory,
          'threshold': threshold,
        }
      ]
    };
  }
}

/// 图像宽高比常量
class ImageAspectRatio {
  static const square = '1:1';
  static const landscape = '16:9';
  static const portrait = '9:16';
  static const landscape43 = '4:3';
  static const portrait34 = '3:4';
}

/// 图像质量常量
class ImageQuality {
  static const low = '1K';
  static const medium = '2K';
  static const high = '4K';
}
