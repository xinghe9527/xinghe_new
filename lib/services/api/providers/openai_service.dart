import 'dart:convert';
import 'package:http/http.dart' as http;
import '../base/api_service_base.dart';
import '../base/api_config.dart';
import '../base/api_response.dart';

/// OpenAI API服务实现
class OpenAIService extends ApiServiceBase {
  OpenAIService(super.config);

  @override
  String get providerName => 'OpenAI';

  @override
  Future<ApiResponse<bool>> testConnection() async {
    try {
      final response = await http.get(
        Uri.parse('${config.baseUrl}/models'),
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return ApiResponse.success(true, statusCode: 200);
      } else {
        return ApiResponse.failure(
          'API连接失败: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
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
      final requestBody = {
        'model': model ?? config.model ?? 'gpt-4',
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
        ...?parameters,
      };

      final response = await http.post(
        Uri.parse('${config.baseUrl}/chat/completions'),
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['choices'][0]['message']['content'] as String;
        final tokensUsed = data['usage']['total_tokens'] as int?;

        return ApiResponse.success(
          LlmResponse(
            text: text,
            tokensUsed: tokensUsed,
            metadata: data,
          ),
          statusCode: 200,
        );
      } else {
        return ApiResponse.failure(
          '生成失败: ${response.statusCode} - ${response.body}',
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
      final requestBody = {
        'model': model ?? 'dall-e-3',
        'prompt': prompt,
        'n': count,
        'size': _convertRatioToSize(ratio),
        'quality': quality?.toLowerCase() ?? 'standard',
        ...?parameters,
      };

      final response = await http.post(
        Uri.parse('${config.baseUrl}/images/generations'),
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final images = (data['data'] as List).map((img) {
          return ImageResponse(
            imageUrl: img['url'] as String,
            imageId: img['revised_prompt'] as String?,
            metadata: img,
          );
        }).toList();

        return ApiResponse.success(images, statusCode: 200);
      } else {
        return ApiResponse.failure(
          '生成失败: ${response.statusCode} - ${response.body}',
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
    // OpenAI暂时不支持视频生成
    return ApiResponse.failure('OpenAI暂不支持视频生成');
  }

  @override
  Future<ApiResponse<UploadResponse>> uploadAsset({
    required String filePath,
    String? assetType,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${config.baseUrl}/files'),
      );

      request.headers['Authorization'] = 'Bearer ${config.apiKey}';
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
      request.fields['purpose'] = assetType ?? 'fine-tune';

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ApiResponse.success(
          UploadResponse(
            uploadId: data['id'] as String,
            uploadUrl: data['filename'] as String,
            metadata: data,
          ),
          statusCode: 200,
        );
      } else {
        return ApiResponse.failure(
          '上传失败: ${response.statusCode} - ${response.body}',
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
      final response = await http.get(
        Uri.parse('${config.baseUrl}/models'),
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = (data['data'] as List)
            .map((model) => model['id'] as String)
            .where((id) => _filterModelByType(id, modelType))
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

  // 辅助方法：转换比例到OpenAI的尺寸格式
  String _convertRatioToSize(String? ratio) {
    switch (ratio) {
      case '1:1':
        return '1024x1024';
      case '16:9':
        return '1792x1024';
      case '9:16':
        return '1024x1792';
      default:
        return '1024x1024';
    }
  }

  // 辅助方法：根据类型过滤模型
  bool _filterModelByType(String modelId, String? modelType) {
    if (modelType == null) return true;

    switch (modelType) {
      case 'llm':
        return modelId.contains('gpt') || modelId.contains('text');
      case 'image':
        return modelId.contains('dall-e');
      case 'video':
        return false; // OpenAI暂不支持视频
      default:
        return true;
    }
  }
}
