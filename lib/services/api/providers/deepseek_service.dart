import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../base/api_service_base.dart';
import '../base/api_response.dart';

/// DeepSeek API 服务
/// 
/// DeepSeek 使用与 OpenAI 完全兼容的 API 格式
/// Base URL: https://api.deepseek.com 或 https://api.deepseek.com/v1
/// 本地API文档: api_docs/deepseek/
class DeepSeekService extends ApiServiceBase {
  DeepSeekService(super.config);

  @override
  String get providerName => 'DeepSeek';

  @override
  Future<ApiResponse<bool>> testConnection() async {
    try {
      final cleanBaseUrl = config.baseUrl.endsWith('/') 
          ? config.baseUrl.substring(0, config.baseUrl.length - 1)
          : config.baseUrl;
      
      final testUrl = '$cleanBaseUrl/models';
      debugPrint('🔍 测试 DeepSeek 连接: $testUrl');
      
      final response = await http.get(
        Uri.parse(testUrl),
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint('📊 测试响应: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        return ApiResponse.success(true, statusCode: response.statusCode);
      } else {
        return ApiResponse.failure(
          '测试失败: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      debugPrint('💥 测试异常: $e');
      return ApiResponse.failure('连接测试失败: $e');
    }
  }

  @override
  Future<ApiResponse<LlmResponse>> generateTextWithMessages({
    required List<Map<String, String>> messages,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      final useModel = model ?? config.model ?? 'deepseek-chat';
      final requestBody = {
        'model': useModel,
        'messages': messages,  // ✅ 直接使用传入的 messages 数组
        ...?parameters,
      };

      final cleanBaseUrl = config.baseUrl.endsWith('/') 
          ? config.baseUrl.substring(0, config.baseUrl.length - 1)
          : config.baseUrl;
      
      final endpoint = '/chat/completions';
      final fullUrl = '$cleanBaseUrl$endpoint';
      
      // 详细日志
      print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🚀 DeepSeek LLM 请求');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('📍 完整 URL: $fullUrl');
      print('🎯 模型: $useModel');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      
      final startTime = DateTime.now();
      final response = await http.post(
        Uri.parse(fullUrl),
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 60));
      
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      print('✅ 请求完成，耗时: ${elapsed}ms');
      print('📊 状态码: ${response.statusCode}\n');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final data = jsonDecode(response.body);
          final text = data['choices'][0]['message']['content'] as String;
          final tokensUsed = data['usage']?['total_tokens'] as int?;

          print('✅ DeepSeek 生成成功，文本长度: ${text.length}\n');
          
          return ApiResponse.success(
            LlmResponse(
              text: text,
              tokensUsed: tokensUsed,
              metadata: data,
            ),
            statusCode: response.statusCode,
          );
        } catch (e) {
          print('❌ 解析响应失败: $e');
          print('响应体: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');
          return ApiResponse.failure(
            '解析响应失败: $e',
            statusCode: response.statusCode,
          );
        }
      } else {
        print('❌ DeepSeek 生成失败');
        print('状态码: ${response.statusCode}');
        print('响应: ${response.body}\n');
        
        return ApiResponse.failure(
          '生成失败: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      print('💥 DeepSeek 异常: $e\n');
      return ApiResponse.failure('生成错误: $e');
    }
  }

  /// ✅ 简单接口：单个 prompt 转为 messages 格式
  @override
  Future<ApiResponse<LlmResponse>> generateText({
    required String prompt,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    return await generateTextWithMessages(
      messages: [
        {'role': 'user', 'content': prompt}
      ],
      model: model,
      parameters: parameters,
    );
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
    return ApiResponse.failure('DeepSeek 不支持图片生成');
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
    return ApiResponse.failure('DeepSeek 不支持视频生成');
  }

  @override
  Future<ApiResponse<UploadResponse>> uploadAsset({
    required String filePath,
    String? assetType,
    Map<String, dynamic>? metadata,
  }) async {
    return ApiResponse.failure('DeepSeek 不支持文件上传');
  }

  @override
  Future<ApiResponse<List<String>>> getAvailableModels({
    String? modelType,
  }) async {
    try {
      final cleanBaseUrl = config.baseUrl.endsWith('/') 
          ? config.baseUrl.substring(0, config.baseUrl.length - 1)
          : config.baseUrl;
      
      final response = await http.get(
        Uri.parse('$cleanBaseUrl/models'),
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final modelIds = (data['data'] as List)
            .map((m) => m['id'] as String)
            .toList();
        return ApiResponse.success(modelIds);
      } else {
        return ApiResponse.failure('获取模型列表失败');
      }
    } catch (e) {
      return ApiResponse.failure('获取模型列表错误: $e');
    }
  }
}
