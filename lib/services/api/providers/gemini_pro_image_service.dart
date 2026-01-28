import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../base/api_service_base.dart';
import '../base/api_response.dart';

/// Gemini 3 Pro 图像生成服务
/// 
/// 支持通过云雾API调用 gemini-3-pro-image-preview 模型
/// 可以控制图片宽高比和清晰度
class GeminiProImageService extends ApiServiceBase {
  GeminiProImageService(super.config);

  @override
  String get providerName => 'Gemini 3 Pro Image';

  /// 默认模型名称
  static const String defaultModel = 'gemini-3-pro-image-preview';
  
  /// 支持的宽高比选项
  static const List<String> supportedAspectRatios = [
    '1:1',   // 正方形
    '3:4',   // 竖版
    '4:3',   // 横版
    '9:16',  // 手机竖屏
    '16:9',  // 手机横屏
  ];
  
  /// 支持的图片尺寸选项
  static const List<String> supportedImageSizes = [
    '1K',    // 低分辨率
    '2K',    // 中分辨率
    '4K',    // 高分辨率
  ];

  @override
  Future<ApiResponse<bool>> testConnection() async {
    try {
      // 使用简单的请求测试连接
      final response = await http.get(
        Uri.parse('${config.baseUrl}/v1beta/models/$defaultModel'),
        headers: _buildHeaders(),
      );
      
      return ApiResponse.success(
        response.statusCode == 200 || response.statusCode == 404,
        statusCode: response.statusCode,
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
    // 此服务专注于图像生成
    return ApiResponse.failure('Gemini 3 Pro Image 服务不支持纯文本生成');
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
      final targetModel = model ?? config.model ?? defaultModel;
      
      // 验证参数
      if (ratio != null && !supportedAspectRatios.contains(ratio)) {
        return ApiResponse.failure(
          '不支持的宽高比: $ratio。支持的选项: ${supportedAspectRatios.join(", ")}'
        );
      }
      
      if (quality != null && !supportedImageSizes.contains(quality)) {
        return ApiResponse.failure(
          '不支持的图片尺寸: $quality。支持的选项: ${supportedImageSizes.join(", ")}'
        );
      }
      
      // 构建请求体
      final requestBody = _buildImageGenerationRequest(
        prompt: prompt,
        ratio: ratio ?? '1:1',
        quality: quality ?? '1K',
        referenceImages: referenceImages,
        parameters: parameters,
      );

      // 发送请求
      final url = '${config.baseUrl}/v1beta/models/$targetModel:generateContent?key=${config.apiKey}';
      final response = await http.post(
        Uri.parse(url),
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
    return ApiResponse.failure('Gemini 3 Pro Image 服务不支持视频生成');
  }

  @override
  Future<ApiResponse<UploadResponse>> uploadAsset({
    required String filePath,
    String? assetType,
    Map<String, dynamic>? metadata,
  }) async {
    // 此服务使用 base64 内联图片,不需要单独上传
    return ApiResponse.failure('Gemini 3 Pro Image 服务不支持单独上传素材');
  }

  @override
  Future<ApiResponse<List<String>>> getAvailableModels({
    String? modelType,
  }) async {
    // 返回支持的模型列表
    return ApiResponse.success([defaultModel]);
  }

  /// 构建请求头
  Map<String, String> _buildHeaders() {
    return {
      'Content-Type': 'application/json',
    };
  }

  /// 构建图像生成请求体
  Map<String, dynamic> _buildImageGenerationRequest({
    required String prompt,
    required String ratio,
    required String quality,
    List<String>? referenceImages,
    Map<String, dynamic>? parameters,
  }) {
    final List<Map<String, dynamic>> parts = [];
    
    // 添加文本提示
    parts.add({'text': prompt});
    
    // 添加参考图片(如果有)
    if (referenceImages != null && referenceImages.isNotEmpty) {
      for (final imagePath in referenceImages) {
        try {
          final imageData = _readImageAsBase64(imagePath);
          if (imageData != null) {
            parts.add({
              'inline_data': {
                'mime_type': _getMimeType(imagePath),
                'data': imageData,
              }
            });
          }
        } catch (e) {
          print('读取图片失败: $imagePath - $e');
        }
      }
    }
    
    return {
      'contents': [
        {
          'role': 'user',
          'parts': parts,
        }
      ],
      'generationConfig': {
        'responseModalities': ['IMAGE'],
        'imageConfig': {
          'aspectRatio': ratio,
          'imageSize': quality,
        },
        ...?parameters, // 合并额外的参数
      },
    };
  }

  /// 读取图片并转换为 Base64
  String? _readImageAsBase64(String filePath) {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        return null;
      }
      final bytes = file.readAsBytesSync();
      return base64Encode(bytes);
    } catch (e) {
      print('Base64 编码失败: $e');
      return null;
    }
  }

  /// 根据文件扩展名获取 MIME 类型
  String _getMimeType(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  /// 解析图像响应
  ApiResponse<List<ImageResponse>> _parseImageResponse(String responseBody) {
    try {
      final json = jsonDecode(responseBody) as Map<String, dynamic>;
      final candidates = json['candidates'] as List?;
      
      if (candidates == null || candidates.isEmpty) {
        return ApiResponse.failure('响应中没有生成的图像');
      }

      final List<ImageResponse> images = [];
      
      for (final candidate in candidates) {
        final content = candidate['content'];
        if (content != null) {
          final parts = content['parts'] as List?;
          if (parts != null) {
            for (final part in parts) {
              final inlineData = part['inline_data'];
              if (inlineData != null) {
                final imageData = inlineData['data'] as String?;
                final mimeType = inlineData['mime_type'] as String?;
                
                if (imageData != null) {
                  images.add(ImageResponse(
                    imageUrl: '', // Gemini 返回的是 base64 数据,不是 URL
                    metadata: {
                      'base64Data': imageData,
                      'mimeType': mimeType,
                      'finishReason': candidate['finishReason'],
                      'safetyRatings': candidate['safetyRatings'],
                    },
                  ));
                }
              }
            }
          }
        }
      }

      if (images.isEmpty) {
        return ApiResponse.failure('无法解析生成的图像');
      }

      return ApiResponse.success(images, statusCode: 200);
    } catch (e) {
      return ApiResponse.failure('解析响应失败: $e');
    }
  }
}

/// 扩展 ImageResponse 以支持 base64 数据和 MIME 类型
extension ImageResponseExtension on ImageResponse {
  /// Base64 编码的图片数据
  String? get base64Data => metadata?['base64Data'] as String?;
  
  /// MIME 类型
  String? get mimeType => metadata?['mimeType'] as String?;
  
  /// 安全评级
  List<dynamic>? get safetyRatings => metadata?['safetyRatings'] as List?;
  
  /// 完成原因
  String? get finishReason => metadata?['finishReason'] as String?;
}
