import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
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
/// 本地API文档: api_docs/geeknow/
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
    try {
      print('🔵 [GeekNow.generateImages] 开始');
      print('   Prompt: ${prompt.substring(0, prompt.length > 100 ? 100 : prompt.length)}...');
      print('   Model: ${model ?? "未设置"}');
      print('   Ratio: ${ratio ?? "未设置"}');
      print('   Quality: ${quality ?? "未设置"}');
      print('   参考图片: ${referenceImages?.length ?? 0} 张\n');
      
      // ✅ 构建完整的参数
      final fullParameters = <String, dynamic>{
        ...?parameters,
      };
      
      // 添加比例参数（如果提供）
      if (ratio != null) {
        fullParameters['size'] = ratio;  // Gemini 使用 'size' 作为 aspectRatio
      }
      
      // 添加质量参数（如果提供）
      if (quality != null) {
        fullParameters['quality'] = quality;  // 用于映射 imageSize
      }
      
      print('📦 完整参数: $fullParameters\n');
      
      // ✅ 调用 GeekNow 的图片生成方法
      print('📞 调用 generateImagesByChat...');
      final response = await generateImagesByChat(
        prompt: prompt,
        model: model,
        referenceImagePaths: referenceImages,
        parameters: fullParameters,
      ).timeout(
        const Duration(seconds: 120),  // 2分钟超时
        onTimeout: () {
          print('⏰ generateImagesByChat 超时！');
          throw Exception('图片生成超时（120秒）');
        },
      );
      
      print('✅ generateImagesByChat 返回');
      print('   Success: ${response.isSuccess}');
      
      if (response.isSuccess && response.data != null) {
        print('✅ 开始提取图片 URL...');
        
        // ✅ 使用 ChatImageResponse 的便捷方法获取图片 URL
        final imageUrls = response.data!.imageUrls;
        
        print('   找到 ${imageUrls.length} 个图片 URL');
        for (var url in imageUrls) {
          print('   - $url');
        }
        
        if (imageUrls.isEmpty) {
          print('   ❌ 未找到图片 URL');
          return ApiResponse.failure('未找到生成的图片');
        }
        
        // ✅ 转换为标准 ImageResponse 列表
        final imageList = imageUrls.map((url) => ImageResponse(
          imageUrl: url,
          imageId: null,
          metadata: {},
        )).toList();
        
        print('   ✅ 成功转换为 ImageResponse 列表\n');
        
        return ApiResponse.success(imageList);
      } else {
        print('   ❌ 响应失败: ${response.error}\n');
        return ApiResponse.failure(response.error ?? '图片生成失败');
      }
    } catch (e) {
      return ApiResponse.failure('图片生成错误: $e');
    }
  }

  /// 对话格式生图（GeekNow 图像生成 API）
  /// 
  /// 使用 /v1/chat/completions 端点或 Gemini 官方端点进行图像生成
  Future<ApiResponse<ChatImageResponse>> generateImagesByChat({
    String? prompt,
    String? model,
    List<String>? referenceImagePaths,
    List<ChatMessage>? messages,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      final targetModel = model ?? config.model ?? 'gpt-4o';
      
      // ✅ 检测是否为 Gemini 模型，使用官方 API 格式
      if (targetModel.toLowerCase().contains('gemini')) {
        return await _generateGeminiImage(
          prompt: prompt,
          model: targetModel,
          referenceImagePaths: referenceImagePaths,
          parameters: parameters,
        );
      }
      
      // ✅ 非 Gemini 模型，使用 OpenAI 兼容格式
      final messageList = messages ?? await _buildChatMessages(
        prompt: prompt,
        referenceImagePaths: referenceImagePaths,
      );

      Map<String, dynamic> requestBody = {
        'model': targetModel,
        'messages': messageList.map((msg) => msg.toJson()).toList(),
      };

      // 添加额外参数
      if (parameters != null) {
        requestBody.addAll(parameters);
      }

      print('📤 OpenAI 格式请求体: ${jsonEncode(requestBody).substring(0, 200)}...\n');

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

  /// Gemini 官方格式生图
  Future<ApiResponse<ChatImageResponse>> _generateGeminiImage({
    String? prompt,
    required String model,
    List<String>? referenceImagePaths,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      print('');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🔍 使用 Gemini 官方 API 格式生成图片');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      
      // 从 parameters 中提取比例参数（与 OpenAIService 保持一致）
      final aspectRatio = parameters?['size'] ?? '16:9';  // 直接使用，如 "16:9", "9:16", "1:1"
      final imageSize = parameters?['quality'] ?? '1K';   // 直接使用，如 "1K", "2K", "4K"
      
      print('📦 接收到的 parameters:');
      print('   原始 parameters: $parameters');
      print('');
      print('📐 解析后的参数:');
      print('   aspectRatio: $aspectRatio (从 parameters[\'size\'] 读取)');
      print('   imageSize: $imageSize (从 parameters[\'quality\'] 读取)');
      print('   prompt: ${prompt?.substring(0, prompt.length > 50 ? 50 : prompt.length)}...');
      print('   model: $model');
      print('   参考图片数量: ${referenceImagePaths?.length ?? 0}');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      
      // ✅ 构建 Gemini 格式的 contents
      final contents = [];
      final parts = [];
      
      // 添加参考图片（如果有）
      if (referenceImagePaths != null && referenceImagePaths.isNotEmpty) {
        for (final imagePath in referenceImagePaths) {
          Uint8List imageBytes;
          String mimeType;
          
          // ✅ 判断是 URL 还是本地文件路径
          if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
            // 在线图片：下载到内存
            print('   📥 下载在线图片: $imagePath');
            final response = await http.get(Uri.parse(imagePath));
            if (response.statusCode == 200) {
              imageBytes = response.bodyBytes;
              // 从 Content-Type 获取 MIME 类型
              mimeType = response.headers['content-type'] ?? 'image/jpeg';
              print('   ✅ 下载成功，大小: ${imageBytes.length} 字节');
            } else {
              print('   ❌ 下载失败: HTTP ${response.statusCode}');
              continue;  // 跳过这张图片
            }
          } else {
            // 本地文件：直接读取
            print('   📂 读取本地文件: $imagePath');
            imageBytes = await File(imagePath).readAsBytes();
            final extension = imagePath.split('.').last.toLowerCase();
            mimeType = _getMimeType(extension);
            print('   ✅ 读取成功，大小: ${imageBytes.length} 字节');
          }
          
          final base64Image = base64Encode(imageBytes);
          
          parts.add({
            'inline_data': {
              'mime_type': mimeType,
              'data': base64Image,
            },
          });
        }
      }
      
      // 添加文本提示词
      if (prompt != null && prompt.isNotEmpty) {
        parts.add({
          'text': prompt,
        });
      }
      
      contents.add({
        'role': 'user',
        'parts': parts,
      });
      
      // ✅ 构建 Gemini 官方请求体
      final requestBody = {
        'contents': contents,
        'generationConfig': {
          'responseModalities': ['TEXT', 'IMAGE'],
          'imageConfig': {
            'aspectRatio': aspectRatio,    // 使用从 parameters 提取的比例
            'imageSize': imageSize,        // 使用从 parameters 提取的质量
          },
        },
      };
      
      print('');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('📤 Gemini 官方 API 请求详情');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🤖 模型: $model');
      print('   支持的模型: gemini-2.5-flash-image-preview, gemini-3-pro-image-preview, gemini-3-pro-image-preview-lite');
      
      // ✅ 使用 Gemini 官方端点: /v1beta/models/{model}:generateContent
      final endpoint = '${config.baseUrl.replaceAll('/v1', '')}/v1beta/models/$model:generateContent';
      print('🔗 URL: $endpoint');
      print('');
      print('📦 Request Body:');
      print('   contents[0].parts: ${parts.length} 项');
      if (referenceImagePaths != null && referenceImagePaths.isNotEmpty) {
        print('   - 🖼️ 参考图片: ${referenceImagePaths.length} 张');
      }
      print('   - 📝 文本提示: ${prompt ?? "无"}');
      print('');
      print('   generationConfig:');
      print('     - responseModalities: [TEXT, IMAGE]');
      print('     - imageConfig:');
      print('       • aspectRatio: $aspectRatio');
      print('       • imageSize: $imageSize');
      print('');
      print('📄 完整 JSON (前 500 字符):');
      final jsonStr = jsonEncode(requestBody);
      print(jsonStr.substring(0, jsonStr.length > 500 ? 500 : jsonStr.length));
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      
      print('');
      print('🌐 正在发送 HTTP 请求...');
      print('🔑 API Key: ${config.apiKey.substring(0, 10)}...');
      
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );
      
      print('');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('📥 API 响应');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('📊 Status Code: ${response.statusCode}');
      print('📄 Response Length: ${response.body.length} 字符');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ 响应成功');
        print('📦 Response Data (原始):');
        print(jsonEncode(data));
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        
        // ✅ 使用正确的 Gemini 响应解析逻辑
        return _parseGeminiResponse(data);
      } else {
        print('❌ 响应失败');
        print('📄 Response Body: ${response.body}');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        
        return ApiResponse.failure(
          'Gemini 图像生成失败: ${response.statusCode} - ${response.body}',
          statusCode: response.statusCode,
        );
      }
    } catch (e, stackTrace) {
      print('💥 Gemini 图像生成异常: $e');
      print('Stack: $stackTrace');
      return ApiResponse.failure('Gemini 图像生成错误: $e');
    }
  }

  /// 解析 Gemini API 响应
  ApiResponse<ChatImageResponse> _parseGeminiResponse(Map<String, dynamic> data) {
    try {
      print('🔍 开始解析 Gemini 响应...');
      print('📊 Response 数据结构:');
      print('   - candidates 数量: ${(data['candidates'] as List?)?.length ?? 0}');
      print('   - responseId: ${data['responseId']}');
      print('   - modelVersion: ${data['modelVersion']}');

      // 转换为 OpenAI 兼容格式
      final choices = <Map<String, dynamic>>[];
      final candidates = data['candidates'] as List?;
      
      print('🔍 candidates: ${candidates != null ? "存在" : "null"}');

      if (candidates != null && candidates.isNotEmpty) {
        print('📦 遍历 ${candidates.length} 个 candidates...');
        
        for (var i = 0; i < candidates.length; i++) {
          final candidate = candidates[i] as Map<String, dynamic>;
          final content = candidate['content'] as Map<String, dynamic>?;
          final parts = content?['parts'] as List?;

          print('   Candidate $i:');
          print('     - content: ${content != null ? "存在" : "null"}');
          print('     - parts 数量: ${parts?.length ?? 0}');

          if (parts != null && parts.isNotEmpty) {
            // 查找图片数据（支持两种格式）
            String? imageContent;
            
            for (var j = 0; j < parts.length; j++) {
              final part = parts[j];
              print('       Part $j 类型: ${part.runtimeType}');
              
              if (part is Map<String, dynamic>) {
                print('       Part $j 包含的 keys: ${part.keys.join(", ")}');
                
                // 格式1: inlineData (base64 图片数据)
                if (part.containsKey('inlineData')) {
                  final inlineData = part['inlineData'] as Map<String, dynamic>;
                  final imageData = inlineData['data'] as String?;
                  if (imageData != null) {
                    imageContent = 'data:image/jpeg;base64,$imageData';
                    print('       ✅ 找到 inlineData 图片！长度: ${imageData.length} 字符');
                    break;
                  }
                }
                
                // 格式2: text (Markdown 或 URL 格式的图片链接)
                if (part.containsKey('text')) {
                  final textContent = part['text'] as String?;
                  if (textContent != null) {
                    print('       📝 text 内容: $textContent');
                    
                    // 提取 Markdown 格式：![image](url)
                    final markdownPattern = RegExp(r'!\[.*?\]\((https?://[^)]+)\)');
                    final markdownMatch = markdownPattern.firstMatch(textContent);
                    if (markdownMatch != null && markdownMatch.group(1) != null) {
                      imageContent = markdownMatch.group(1)!;
                      print('       ✅ 找到 Markdown 图片链接: $imageContent');
                      break;
                    }
                    
                    // 提取普通 URL
                    final urlPattern = RegExp(r'https?://[^\s)]+');
                    final urlMatch = urlPattern.firstMatch(textContent);
                    if (urlMatch != null) {
                      imageContent = urlMatch.group(0)!;
                      print('       ✅ 找到普通 URL 图片链接: $imageContent');
                      break;
                    }
                  }
                }
              }
            }

            // 如果找到图片，转换为 OpenAI 格式
            if (imageContent != null) {
              choices.add({
                'index': i,
                'message': {
                  'role': 'assistant',
                  'content': '![image]($imageContent)',  // Markdown 格式
                },
                'finish_reason': candidate['finishReason'] ?? 'stop',
              });
              
              print('       ✅ 已添加到 choices！');
            } else {
              print('       ⚠️ 未找到图片数据或链接！');
            }
          }
        }
      }

      // 构造 OpenAI 兼容的响应
      final openaiResponse = {
        'id': data['responseId'] ?? data['id'] ?? 'gemini-${DateTime.now().millisecondsSinceEpoch}',
        'object': 'chat.completion',
        'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'model': data['modelVersion'] ?? 'gemini',
        'choices': choices,
        'usage': data['usageMetadata'] != null
            ? {
                'prompt_tokens': (data['usageMetadata'] as Map)['promptTokenCount'] ?? 0,
                'completion_tokens': (data['usageMetadata'] as Map)['candidatesTokenCount'] ?? 0,
                'total_tokens': (data['usageMetadata'] as Map)['totalTokenCount'] ?? 0,
              }
            : {
                'prompt_tokens': 0,
                'completion_tokens': 0,
                'total_tokens': 0,
              },
      };

      print('');
      print('✅ Gemini 响应解析完成！');
      print('📦 转换后的 OpenAI 兼容格式:');
      print('   - 总共 ${choices.length} 个 choices');
      if (choices.isEmpty) {
        print('   ⚠️ 警告：没有找到任何图片！');
      } else {
        for (var i = 0; i < choices.length; i++) {
          final choice = choices[i];
          final content = (choice['message'] as Map)['content'] as String;
          print('   Choice $i: ${content.length > 100 ? "${content.substring(0, 100)}..." : content}');
        }
      }
      print('');

      return ApiResponse.success(
        ChatImageResponse.fromJson(openaiResponse),
        statusCode: 200,
      );
    } catch (e, stackTrace) {
      print('❌ 解析 Gemini 响应失败！');
      print('错误: $e');
      print('堆栈: $stackTrace');
      return ApiResponse.failure('解析 Gemini 响应失败: $e');
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
