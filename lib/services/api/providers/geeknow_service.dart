import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../base/api_service_base.dart';
import '../base/api_response.dart';

// 导入图像相关的数据模型
import 'openai_service.dart' show 
    ChatMessage,
    ChatMessageContent,
    ChatImageResponse;

// 导入视频相关的数据模型
import 'veo_video_service.dart' show
    VeoTaskStatus,
    SoraCharacter;

/// GeekNow API 服务
/// 
/// GeekNow 是一个统一的 AI API Gateway，提供多种 AI 模型的访问
/// 包括：LLM、图片生成、视频生成、文件上传等功能
class GeekNowService extends ApiServiceBase {
  GeekNowService(super.config);

  @override
  String get providerName => 'GeekNow';
  
  // 日志辅助方法
  void _logRequest(String endpoint, Map<String, dynamic> body) {
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('🔵 GeekNow API 请求');
    debugPrint('📍 URL: ${config.baseUrl}$endpoint');
    debugPrint('🔑 API Key: ${config.apiKey.substring(0, 10)}...');
    debugPrint('📦 请求体: ${jsonEncode(body)}');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }
  
  void _logResponse(int statusCode, String body) {
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('🟢 GeekNow API 响应');
    debugPrint('📊 状态码: $statusCode');
    debugPrint('📄 响应体: ${body.length > 500 ? "${body.substring(0, 500)}..." : body}');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }

  @override
  Future<ApiResponse<bool>> testConnection() async {
    try {
      // ✅ 清理 Base URL，去除末尾的斜杠
      final cleanBaseUrl = config.baseUrl.endsWith('/') 
          ? config.baseUrl.substring(0, config.baseUrl.length - 1)
          : config.baseUrl;
      
      final testUrl = '$cleanBaseUrl/models';  // ← 去掉 /v1
      debugPrint('🔍 测试连接: $testUrl');
      
      final response = await http.get(
        Uri.parse(testUrl),
        headers: {'Authorization': 'Bearer ${config.apiKey}'},
      ).timeout(const Duration(seconds: 10));

      debugPrint('📊 测试响应: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        debugPrint('✅ 测试成功');
        return ApiResponse.success(true, statusCode: response.statusCode);
      } else {
        debugPrint('❌ 测试失败: ${response.body}');
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

  // ==================== LLM 区域 ====================

  @override
  Future<ApiResponse<LlmResponse>> generateTextWithMessages({
    required List<Map<String, String>> messages,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      final useModel = model ?? config.model ?? 'gpt-4';
      final requestBody = {
        'model': useModel,
        'messages': messages,  // ✅ 直接使用传入的 messages 数组
        ...?parameters,
      };

      // ✅ 完全使用用户配置的 Base URL，只添加端点路径
      final cleanBaseUrl = config.baseUrl.endsWith('/') 
          ? config.baseUrl.substring(0, config.baseUrl.length - 1)
          : config.baseUrl;
      
      // 📋 直接使用端点路径，不添加 /v1（用户的 Base URL 已包含）
      final endpoint = '/chat/completions';  // ← 去掉 /v1
      final fullUrl = '$cleanBaseUrl$endpoint';
      
      // ✅ 使用 print 确保输出到控制台
      print('\n');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🚀 GeekNow LLM 请求');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('📍 原始 Base URL: ${config.baseUrl}');
      print('📍 清理后 Base URL: $cleanBaseUrl');
      print('📍 端点路径: $endpoint');
      print('📍 完整 URL: $fullUrl');
      print('🔑 API Key: ${config.apiKey.substring(0, 15)}...');
      print('🎯 模型: $useModel');
      print('📝 Messages 数量: ${messages.length} 条');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      
      _logRequest(endpoint, requestBody);
      
      print('🌐 开始发送 HTTP POST 请求...');
      final uri = Uri.parse(fullUrl);
      print('🔗 URI 对象: $uri');
      print('   - scheme: ${uri.scheme}');
      print('   - host: ${uri.host}');
      print('   - port: ${uri.port}');
      print('   - path: ${uri.path}');
      
      final startTime = DateTime.now();
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('⏰ 请求超时（30秒）');
          throw Exception('请求超时');
        },
      );
      
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      print('✅ HTTP 请求已返回，耗时: ${elapsed}ms');
      
      print('\n');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('📨 GeekNow 响应');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('⏱️ 请求耗时: ${elapsed}ms');
      print('📊 状态码: ${response.statusCode}');
      print('📋 Content-Type: ${response.headers['content-type']}');
      print('📄 响应体前500字符:');
      print(response.body.substring(0, response.body.length > 500 ? 500 : response.body.length));
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      
      _logResponse(response.statusCode, response.body);

      // ✅ 接受所有 2xx 状态码为成功
      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          debugPrint('📄 开始解析响应...');
          debugPrint('响应体类型: ${response.headers['content-type']}');
          debugPrint('响应体长度: ${response.body.length}');
          debugPrint('响应体内容: ${response.body.substring(0, response.body.length > 1000 ? 1000 : response.body.length)}');
          
          final data = jsonDecode(response.body);
          debugPrint('✅ JSON 解析成功');
          debugPrint('数据结构: ${data.keys}');
          
          final text = data['choices'][0]['message']['content'] as String;
          final tokensUsed = data['usage']?['total_tokens'] as int?;

          debugPrint('✅ LLM 生成成功，返回文本长度: ${text.length}');
          
          return ApiResponse.success(
            LlmResponse(
              text: text,
              tokensUsed: tokensUsed,
              metadata: data,
            ),
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ 解析响应失败: $e');
          debugPrint('原始响应: ${response.body}');
          return ApiResponse.failure(
            '解析响应失败: $e\n状态码: ${response.statusCode}\n响应体前500字符: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}',
            statusCode: response.statusCode,
          );
        }
      } else {
        debugPrint('❌ LLM 生成失败');
        debugPrint('状态码: ${response.statusCode}');
        debugPrint('完整URL: $fullUrl');
        debugPrint('响应体: ${response.body}');
        
        // ✅ 返回详细的错误信息给用户
        String errorDetail = '状态码: ${response.statusCode}\n'
            '请求URL: $fullUrl\n'
            '使用模型: $useModel\n';
        
        // 如果响应是 HTML（通常是 404 页面），提取有用信息
        if (response.body.toLowerCase().contains('<!doctype html>') || 
            response.body.toLowerCase().contains('<html>')) {
          errorDetail += '响应: 返回了 HTML 页面（可能端点不存在）';
        } else {
          errorDetail += '响应: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}...';
        }
        
        return ApiResponse.failure(
          errorDetail,
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      debugPrint('💥 LLM 生成异常: $e');
      debugPrint('完整错误堆栈: ${e.toString()}');
      return ApiResponse.failure('网络请求异常: $e');
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

  // ==================== 图片生成区域 ====================

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
    // 图片生成统一入口
    // 根据不同的 model 参数，调用不同的实现
    return ApiResponse.failure('请使用具体的图片生成方法');
  }

  /// 对话格式生图（GeekNow 图像生成 API）
  /// 
  /// 使用 /v1/chat/completions 端点进行图像生成
  Future<ApiResponse<ChatImageResponse>> generateImagesByChat({
    String? prompt,
    String? model,
    List<String>? referenceImagePaths,
    List<ChatMessage>? messages,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      final messageList = messages ?? await _buildChatMessages(
        prompt: prompt,
        referenceImagePaths: referenceImagePaths,
      );

      final requestBody = {
        'model': model ?? config.model ?? 'gpt-4o',
        'messages': messageList.map((msg) => msg.toJson()).toList(),
        ...?parameters,
      };

      // ✅ 直接使用用户配置的 baseUrl
      final response = await http.post(
        Uri.parse('${config.baseUrl}/chat/completions'),  // ← 去掉 /v1
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ApiResponse.success(
          ChatImageResponse.fromJson(data),
          statusCode: 200,
        );
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

  Future<List<ChatMessage>> _buildChatMessages({
    String? prompt,
    List<String>? referenceImagePaths,
  }) async {
    final messages = <ChatMessage>[];

    if (referenceImagePaths != null && referenceImagePaths.isNotEmpty) {
      final contentList = <ChatMessageContent>[];

      for (final imagePath in referenceImagePaths) {
        final imageBytes = await File(imagePath).readAsBytes();
        final base64Image = base64Encode(imageBytes);
        final extension = imagePath.split('.').last.toLowerCase();
        final mimeType = _getMimeType(extension);

        contentList.add(
          ChatMessageContent.image(
            imageUrl: 'data:$mimeType;base64,$base64Image',
          ),
        );
      }

      if (prompt != null && prompt.isNotEmpty) {
        contentList.add(ChatMessageContent.text(text: prompt));
      }

      messages.add(ChatMessage(role: 'user', content: contentList));
    } else if (prompt != null && prompt.isNotEmpty) {
      messages.add(
        ChatMessage(
          role: 'user',
          content: [ChatMessageContent.text(text: prompt)],
        ),
      );
    }

    return messages;
  }

  String _getMimeType(String extension) {
    switch (extension) {
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

  // ==================== 视频生成区域 ====================

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
      final targetModel = model ?? config.model ?? 'veo_3_1';
      final size = ratio ?? '720x1280';
      final seconds = parameters?['seconds'] as int? ?? 8;
      final referenceImagePaths = parameters?['referenceImagePaths'] as List<String>?;
      
      // Sora 角色引用参数
      final characterUrl = parameters?['character_url'] as String?;
      final characterTimestamps = parameters?['character_timestamps'] as String?;
      
      // VEO 高清参数
      final enableUpsample = parameters?['enable_upsample'] as bool?;
      
      // Kling/豆包 首尾帧参数
      final firstFrameImageUrl = parameters?['first_frame_image'] as String?;
      final lastFrameImageUrl = parameters?['last_frame_image'] as String?;
      
      // Kling 视频编辑参数
      final videoUrl = parameters?['video'] as String?;
      
      // Grok 特有参数
      final aspectRatio = parameters?['aspect_ratio'] as String?;
      final grokSize = parameters?['grok_size'] as String?;

      // 使用 multipart/form-data 格式
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${config.baseUrl}/videos'),  // ← 去掉 /v1
      );

      request.headers['Authorization'] = 'Bearer ${config.apiKey}';

      // 基础参数
      request.fields['model'] = targetModel;
      request.fields['prompt'] = prompt;
      
      // Grok 使用 aspect_ratio
      if (aspectRatio != null) {
        request.fields['aspect_ratio'] = aspectRatio;
      } else {
        request.fields['size'] = size;
      }
      
      if (grokSize != null) {
        request.fields['size'] = grokSize;
      }
      
      request.fields['seconds'] = seconds.toString();

      // Sora 角色引用
      if (characterUrl != null) {
        request.fields['character_url'] = characterUrl;
      }
      if (characterTimestamps != null) {
        request.fields['character_timestamps'] = characterTimestamps;
      }

      // VEO 高清模式
      if (enableUpsample != null) {
        request.fields['enable_upsample'] = enableUpsample.toString();
      }

      // Kling/豆包/Grok 首尾帧
      if (firstFrameImageUrl != null) {
        request.fields['first_frame_image'] = firstFrameImageUrl;
      }
      if (lastFrameImageUrl != null) {
        request.fields['last_frame_image'] = lastFrameImageUrl;
      }

      // Kling 视频编辑
      if (videoUrl != null) {
        request.fields['video'] = videoUrl;
      }

      // 参考图片文件
      if (referenceImagePaths != null && referenceImagePaths.isNotEmpty) {
        for (final imagePath in referenceImagePaths) {
          request.files.add(
            await http.MultipartFile.fromPath(
              'input_reference',
              imagePath,
            ),
          );
        }
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return _parseVideoResponse(response.body);
      } else {
        return ApiResponse.failure(
          '视频生成失败: ${response.statusCode} - ${response.body}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('视频生成错误: $e');
    }
  }

  /// 查询视频任务状态
  Future<ApiResponse<VeoTaskStatus>> getVideoTaskStatus({
    required String taskId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('${config.baseUrl}/videos/$taskId'),  // ← 去掉 /v1
        headers: {'Authorization': 'Bearer ${config.apiKey}'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResponse.success(
          VeoTaskStatus.fromJson(data),
          statusCode: 200,
        );
      } else if (response.statusCode == 404) {
        return ApiResponse.failure(
          '任务未找到，可能数据同步延迟',
          statusCode: 404,
        );
      } else {
        return ApiResponse.failure(
          '查询失败: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('查询任务状态错误: $e');
    }
  }

  /// 视频 Remix（VEO/Sora）
  Future<ApiResponse<VeoTaskStatus>> remixVideo({
    required String videoId,
    required String prompt,
    required int seconds,
  }) async {
    try {
      final requestBody = {
        'prompt': prompt,
        'seconds': seconds,
      };

      final response = await http.post(
        Uri.parse('${config.baseUrl}/videos/$videoId/remix'),  // ← 去掉 /v1
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResponse.success(
          VeoTaskStatus.fromJson(data),
          statusCode: 200,
        );
      } else {
        return ApiResponse.failure(
          '视频 Remix 失败: ${response.statusCode} - ${response.body}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('视频 Remix 错误: $e');
    }
  }

  /// Sora 创建角色
  Future<ApiResponse<SoraCharacter>> createCharacter({
    required String timestamps,
    String? url,
    String? fromTask,
  }) async {
    try {
      if (url == null && fromTask == null) {
        return ApiResponse.failure('必须提供 url 或 fromTask 参数之一');
      }
      if (url != null && fromTask != null) {
        return ApiResponse.failure('url 和 fromTask 参数只能提供其中一个');
      }

      final requestBody = <String, dynamic>{
        'timestamps': timestamps,
      };

      if (url != null) requestBody['url'] = url;
      if (fromTask != null) requestBody['from_task'] = fromTask;

      final response = await http.post(
        Uri.parse('${config.baseUrl}/sora/characters'),
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResponse.success(
          SoraCharacter.fromJson(data),
          statusCode: 200,
        );
      } else {
        return ApiResponse.failure(
          '创建角色失败: ${response.statusCode} - ${response.body}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('创建角色错误: $e');
    }
  }

  ApiResponse<List<VideoResponse>> _parseVideoResponse(String responseBody) {
    try {
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      
      // 检查是否为任务响应格式
      if (data.containsKey('id') && data.containsKey('status')) {
        final taskId = data['id'] as String;
        final status = data['status'] as String;
        
        return ApiResponse.success([
          VideoResponse(
            videoUrl: '',
            videoId: taskId,
            duration: null,
            metadata: {
              'taskId': taskId,
              'status': status,
              'progress': data['progress'],
              'model': data['model'],
              'size': data['size'],
              'created_at': data['created_at'],
              'isTask': true,
            },
          ),
        ], statusCode: 200);
      }
      
      // 兼容直接返回视频的格式
      return ApiResponse.failure('不支持的响应格式');
    } catch (e) {
      return ApiResponse.failure('解析响应失败: $e');
    }
  }

  // ==================== 上传区域 ====================

  @override
  Future<ApiResponse<UploadResponse>> uploadAsset({
    required String filePath,
    String? assetType,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${config.baseUrl}/files'),  // ← 去掉 /v1
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

  // ==================== 模型列表查询 ====================

  @override
  Future<ApiResponse<List<String>>> getAvailableModels({
    String? modelType,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('${config.baseUrl}/models'),  // ← 去掉 /v1
        headers: {'Authorization': 'Bearer ${config.apiKey}'},
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

  bool _filterModelByType(String modelId, String? modelType) {
    if (modelType == null) return true;

    switch (modelType) {
      case 'llm':
        return modelId.contains('gpt') || modelId.contains('text');
      case 'image':
        return modelId.contains('dall-e') || modelId.contains('gpt-4');
      case 'video':
        return modelId.contains('veo') ||
            modelId.contains('sora') ||
            modelId.contains('kling') ||
            modelId.contains('doubao') ||
            modelId.contains('grok');
      default:
        return true;
    }
  }
}

// 注意：数据模型和辅助类请从原始文件导入
// import 'openai_service.dart' show ChatMessage, ChatImageResponse, ...
// import 'veo_video_service.dart' show VideoTaskStatus, VeoVideoHelper, ...
