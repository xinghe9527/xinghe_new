import 'dart:convert';
import 'package:http/http.dart' as http;
import '../base/api_service_base.dart';
import '../base/api_config.dart';
import '../base/api_response.dart';

/// 自定义API服务实现模板
/// 可以根据不同API服务商的文档进行定制
class CustomApiService extends ApiServiceBase {
  final String customProviderName;

  CustomApiService(super.config, {required this.customProviderName});

  @override
  String get providerName => customProviderName;

  @override
  Future<ApiResponse<bool>> testConnection() async {
    try {
      // TODO: 根据具体API文档实现连接测试
      final response = await http.get(
        Uri.parse('${config.baseUrl}/health'),
        headers: _buildHeaders(),
      ).timeout(const Duration(seconds: 10));

      return ApiResponse.success(
        response.statusCode == 200,
        statusCode: response.statusCode,
      );
    } catch (e) {
      return ApiResponse.failure('连接错误: $e');
    }
  }

  @override
  Future<ApiResponse<LlmResponse>> generateText({
    required String prompt,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      // TODO: 根据具体API文档实现文本生成
      final requestBody = {
        'prompt': prompt,
        'model': model ?? config.model,
        ...?parameters,
      };

      final response = await http.post(
        Uri.parse('${config.baseUrl}/generate/text'),
        headers: _buildHeaders(),
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // TODO: 根据实际API响应格式调整解析逻辑
        return ApiResponse.success(
          LlmResponse(
            text: data['text'] as String,
            tokensUsed: data['tokens_used'] as int?,
            metadata: data,
          ),
          statusCode: 200,
        );
      } else {
        return ApiResponse.failure(
          '生成失败: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('生成错误: $e');
    }
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
      // TODO: 根据具体API文档实现图片生成
      final requestBody = {
        'prompt': prompt,
        'model': model ?? config.model,
        'count': count,
        'ratio': ratio,
        'quality': quality,
        'reference_images': referenceImages,
        ...?parameters,
      };

      final response = await http.post(
        Uri.parse('${config.baseUrl}/generate/image'),
        headers: _buildHeaders(),
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // TODO: 根据实际API响应格式调整解析逻辑
        final images = (data['images'] as List).map((img) {
          return ImageResponse(
            imageUrl: img['url'] as String,
            imageId: img['id'] as String?,
            metadata: img,
          );
        }).toList();

        return ApiResponse.success(images, statusCode: 200);
      } else {
        return ApiResponse.failure(
          '生成失败: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('生成错误: $e');
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
    try {
      // TODO: 根据具体API文档实现视频生成
      final requestBody = {
        'prompt': prompt,
        'model': model ?? config.model,
        'count': count,
        'ratio': ratio,
        'quality': quality,
        'reference_images': referenceImages,
        ...?parameters,
      };

      final response = await http.post(
        Uri.parse('${config.baseUrl}/generate/video'),
        headers: _buildHeaders(),
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // TODO: 根据实际API响应格式调整解析逻辑
        final videos = (data['videos'] as List).map((video) {
          return VideoResponse(
            videoUrl: video['url'] as String,
            videoId: video['id'] as String?,
            duration: video['duration'] as int?,
            metadata: video,
          );
        }).toList();

        return ApiResponse.success(videos, statusCode: 200);
      } else {
        return ApiResponse.failure(
          '生成失败: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('生成错误: $e');
    }
  }

  @override
  Future<ApiResponse<UploadResponse>> uploadAsset({
    required String filePath,
    String? assetType,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      // TODO: 根据具体API文档实现文件上传
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${config.baseUrl}/upload'),
      );

      request.headers.addAll(_buildHeaders());
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      
      if (assetType != null) {
        request.fields['type'] = assetType;
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        return ApiResponse.success(
          UploadResponse(
            uploadId: data['id'] as String,
            uploadUrl: data['url'] as String,
            metadata: data,
          ),
          statusCode: 200,
        );
      } else {
        return ApiResponse.failure(
          '上传失败: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('上传错误: $e');
    }
  }

  @override
  Future<ApiResponse<List<String>>> getAvailableModels({
    String? modelType,
  }) async {
    try {
      // TODO: 根据具体API文档实现模型列表获取
      final response = await http.get(
        Uri.parse('${config.baseUrl}/models'),
        headers: _buildHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // TODO: 根据实际API响应格式调整解析逻辑
        final models = (data['models'] as List)
            .map((model) => model['name'] as String)
            .toList();

        return ApiResponse.success(models, statusCode: 200);
      } else {
        return ApiResponse.failure(
          '获取模型列表失败: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('获取模型列表错误: $e');
    }
  }

  // 构建请求头
  Map<String, String> _buildHeaders() {
    return {
      'Authorization': 'Bearer ${config.apiKey}',
      'Content-Type': 'application/json',
      // TODO: 根据具体API文档添加其他必要的请求头
    };
  }
}
