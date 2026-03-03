import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../base/api_service_base.dart';
import '../base/api_response.dart';

/// 阿里云百炼 API 服务
/// 
/// 使用 OpenAI 兼容格式的 Chat API
/// Base URL: https://dashscope.aliyuncs.com/compatible-mode/v1
/// 
/// 支持的模型：
/// - qwen-plus (推荐)
/// - qwen-max (高级)
/// - qwen-turbo (快速)
/// - qwen-long (长文本)
/// - Qwen3 系列
/// - qwen-vl 系列
class AliyunService extends ApiServiceBase {
  AliyunService(super.config);

  @override
  String get providerName => 'Aliyun';

  @override
  Future<ApiResponse<bool>> testConnection() async {
    try {
      final cleanBaseUrl = config.baseUrl.endsWith('/') 
          ? config.baseUrl.substring(0, config.baseUrl.length - 1)
          : config.baseUrl;
      
      // 阿里云没有 /models 端点，直接测试一个简单的生成请求
      final testUrl = '$cleanBaseUrl/chat/completions';
      debugPrint('🔍 测试阿里云连接: $testUrl');
      
      final response = await http.post(
        Uri.parse(testUrl),
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': config.model ?? 'qwen-plus',
          'messages': [
            {'role': 'user', 'content': '你好'}
          ],
          'max_tokens': 10,
        }),
      ).timeout(const Duration(seconds: 10));

      debugPrint('📊 测试响应: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        return ApiResponse.success(true, statusCode: response.statusCode);
      } else {
        return ApiResponse.failure(
          '测试失败: ${response.statusCode}\n${response.body}',
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
      final useModel = model ?? config.model ?? 'qwen-plus';
      final requestBody = {
        'model': useModel,
        'messages': messages,
        ...?parameters,
      };

      final cleanBaseUrl = config.baseUrl.endsWith('/') 
          ? config.baseUrl.substring(0, config.baseUrl.length - 1)
          : config.baseUrl;
      
      final endpoint = '/chat/completions';
      final fullUrl = '$cleanBaseUrl$endpoint';
      
      // 详细日志
      print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🚀 阿里云百炼 LLM 请求');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('📍 完整 URL: $fullUrl');
      print('🎯 模型: $useModel');
      print('📝 Messages: ${messages.length} 条');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      
      final startTime = DateTime.now();
      final response = await http.post(
        Uri.parse(fullUrl),
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 300));  // ✅ 增加到300秒（5分钟），支持生成大量内容
      
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      print('✅ 请求完成，耗时: ${elapsed}ms');
      print('📊 状态码: ${response.statusCode}\n');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final data = jsonDecode(response.body);
          final text = data['choices'][0]['message']['content'] as String;
          final tokensUsed = data['usage']?['total_tokens'] as int?;

          print('✅ 阿里云生成成功，文本长度: ${text.length}\n');
          
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
        print('❌ 阿里云生成失败');
        print('状态码: ${response.statusCode}');
        print('响应: ${response.body}\n');
        
        return ApiResponse.failure(
          '生成失败: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      print('💥 阿里云异常: $e\n');
      
      // 将英文错误提示转换为中文
      String errorMessage = e.toString();
      if (errorMessage.contains('TimeoutException')) {
        errorMessage = '请求超时，请重试。如果问题持续，请尝试缩短剧本长度或稍后再试。';
      } else if (errorMessage.contains('SocketException')) {
        errorMessage = '网络连接失败，请检查网络设置';
      } else if (errorMessage.contains('HandshakeException')) {
        errorMessage = 'SSL 证书验证失败，请检查网络环境';
      } else {
        errorMessage = '生成失败: $errorMessage';
      }
      
      return ApiResponse.failure(errorMessage);
    }
  }

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
    return ApiResponse.failure('阿里云图片生成请使用专门的服务');
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
    return ApiResponse.failure('阿里云视频生成请使用专门的服务');
  }

  @override
  Future<ApiResponse<UploadResponse>> uploadAsset({
    required String filePath,
    String? assetType,
    Map<String, dynamic>? metadata,
  }) async {
    return ApiResponse.failure('阿里云不支持文件上传');
  }

  @override
  Future<ApiResponse<List<String>>> getAvailableModels({
    String? modelType,
  }) async {
    // 返回常用的阿里云模型列表
    return ApiResponse.success([
      'qwen-plus',
      'qwen-max',
      'qwen-turbo',
      'qwen-long',
      'qwen3-max',
      'qwen3-turbo',
    ]);
  }
}
