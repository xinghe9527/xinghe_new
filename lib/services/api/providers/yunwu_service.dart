import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../base/api_service_base.dart';
import '../base/api_response.dart';

/// Yunwu（云雾）API 服务实现
/// 
/// 这是一个独立的服务商，与 GeekNow、OpenAI 等并列
/// 支持 LLM、图像、视频等多种 AI 能力
/// 
/// API 文档来源: https://yunwu.ai
/// 本地API文档: api_docs/yunwu/
class YunwuService extends ApiServiceBase {
  YunwuService(super.config);

  @override
  String get providerName => 'Yunwu';

  @override
  Future<ApiResponse<bool>> testConnection() async {
    try {
      // TODO: 等待 API 文档后实现具体的连接测试
      // 暂时返回成功
      return ApiResponse.success(true, statusCode: 200);
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
      final useModel = model ?? 'gemini-2.5-pro';
      
      // 构建 Gemini 格式的请求体
      final requestBody = <String, dynamic>{
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt}
            ],
          }
        ],
      };

      // 添加可选的配置
      if (parameters != null) {
        if (parameters.containsKey('systemInstruction')) {
          requestBody['systemInstruction'] = parameters['systemInstruction'];
        }
        if (parameters.containsKey('generationConfig')) {
          requestBody['generationConfig'] = parameters['generationConfig'];
        }
      }

      // Gemini 使用 query 参数传递 API Key，而不是 header
      final uri = Uri.parse('${config.baseUrl}/v1beta/models/$useModel:generateContent')
          .replace(queryParameters: {'key': config.apiKey});

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        // 解析 Gemini 响应
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final candidate = candidates[0] as Map<String, dynamic>;
          final content = candidate['content'] as Map<String, dynamic>?;
          final parts = content?['parts'] as List?;
          
          String text = '';
          if (parts != null && parts.isNotEmpty) {
            final part = parts[0] as Map<String, dynamic>;
            text = part['text'] as String? ?? '';
          }

          final usageMetadata = data['usageMetadata'] as Map<String, dynamic>?;
          final totalTokens = usageMetadata?['totalTokenCount'] as int?;

          return ApiResponse.success(
            LlmResponse(
              text: text,
              tokensUsed: totalTokens,
              metadata: data,
            ),
            statusCode: 200,
          );
        } else {
          return ApiResponse.failure('响应格式错误：无 candidates');
        }
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

  /// Gemini 流式文本生成
  /// 
  /// **API 文档**: POST /v1beta/models/{model}:streamGenerateContent
  /// 
  /// **特点**:
  /// - 流式输出（SSE）
  /// - 支持思考过程（thinkingConfig）
  /// - 支持安全设置（safetySettings）
  /// - 支持工具调用（tools）
  /// 
  /// **参数**:
  /// - [prompt] 提示词
  /// - [model] Gemini 模型名称
  /// - [parameters] 配置参数（systemInstruction, generationConfig, safetySettings, tools）
  /// 
  /// **返回**: Stream 响应（需要处理 SSE 流）
  Future<ApiResponse<Map<String, dynamic>>> generateTextStream({
    required String prompt,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      final useModel = model ?? 'gemini-2.5-pro';
      
      // 构建请求体
      final requestBody = <String, dynamic>{
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt}
            ],
          }
        ],
      };

      // 添加可选配置
      if (parameters != null) {
        if (parameters.containsKey('systemInstruction')) {
          requestBody['systemInstruction'] = parameters['systemInstruction'];
        }
        if (parameters.containsKey('generationConfig')) {
          requestBody['generationConfig'] = parameters['generationConfig'];
        }
        if (parameters.containsKey('safetySettings')) {
          requestBody['safetySettings'] = parameters['safetySettings'];
        }
        if (parameters.containsKey('tools')) {
          requestBody['tools'] = parameters['tools'];
        }
      }

      // 使用 streamGenerateContent 端点，添加 alt=sse 参数
      final uri = Uri.parse('${config.baseUrl}/v1beta/models/$useModel:streamGenerateContent')
          .replace(queryParameters: {
        'key': config.apiKey,
        'alt': 'sse',
      });

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        // 注意：实际使用时应该使用 StreamedResponse 处理 SSE
        // 这里简化处理，返回完整响应
        return ApiResponse.success(
          {'body': response.body},
          statusCode: 200,
        );
      } else {
        return ApiResponse.failure(
          '流式生成失败: ${response.statusCode} - ${response.body}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('流式生成错误: $e');
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
      final useModel = model ?? 'gemini-3.1-flash-image-preview';

      // 构建 parts
      final parts = <Map<String, dynamic>>[];

      // 1. 添加参考图片（文件路径 → base64）
      if (referenceImages != null && referenceImages.isNotEmpty) {
        for (final imagePath in referenceImages) {
          Uint8List imageBytes;
          String mimeType;

          if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
            final resp = await http.get(Uri.parse(imagePath));
            if (resp.statusCode == 200) {
              imageBytes = resp.bodyBytes;
              mimeType = resp.headers['content-type'] ?? 'image/jpeg';
            } else {
              continue;
            }
          } else {
            final file = io.File(imagePath);
            if (!await file.exists()) continue;
            imageBytes = await file.readAsBytes();
            final ext = imagePath.split('.').last.toLowerCase();
            mimeType = const {
              'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
              'gif': 'image/gif', 'webp': 'image/webp', 'bmp': 'image/bmp',
            }[ext] ?? 'image/jpeg';
          }

          parts.add({
            'inline_data': {
              'mime_type': mimeType,
              'data': base64Encode(imageBytes),
            }
          });
        }
      }

      // 2. 添加文本提示词
      parts.add({'text': prompt});

      // 3. 构建 generationConfig（含 imageConfig）
      final aspectRatio = parameters?['size'] ?? ratio ?? '1:1';
      final imageSize = parameters?['quality'] ?? quality ?? '1K';

      final requestBody = <String, dynamic>{
        'contents': [
          {
            'role': 'user',
            'parts': parts,
          }
        ],
        'generationConfig': {
          'responseModalities': ['TEXT', 'IMAGE'],
          'imageConfig': {
            'aspectRatio': aspectRatio,
            'imageSize': imageSize,
          },
        },
      };

      // 使用 query 参数传递 API Key
      final uri = Uri.parse('${config.baseUrl}/v1beta/models/$useModel:generateContent')
          .replace(queryParameters: {'key': config.apiKey});

      print('🎨 [Yunwu] generateImages: model=$useModel, aspectRatio=$aspectRatio, imageSize=$imageSize');
      print('🔗 [Yunwu] URL: $uri');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      print('📥 [Yunwu] 响应状态: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final images = <ImageResponse>[];
        final candidates = data['candidates'] as List?;

        if (candidates != null) {
          for (final candidate in candidates) {
            final content = (candidate as Map<String, dynamic>)['content'] as Map<String, dynamic>?;
            final partsList = content?['parts'] as List?;
            if (partsList == null) continue;

            for (final part in partsList) {
              if (part is! Map<String, dynamic>) continue;

              // 格式1: inlineData（base64 图片）→ 保存到临时文件
              if (part.containsKey('inlineData')) {
                final inlineData = part['inlineData'] as Map<String, dynamic>;
                final imageData = inlineData['data'] as String?;
                final mimeType = inlineData['mimeType'] as String? ?? 'image/png';
                if (imageData != null) {
                  final ext = mimeType.contains('png') ? 'png' : 'jpg';
                  final tempDir = io.Directory.systemTemp;
                  final tempFile = io.File(
                    '${tempDir.path}/yunwu_${DateTime.now().millisecondsSinceEpoch}_${images.length}.$ext',
                  );
                  await tempFile.writeAsBytes(base64Decode(imageData));
                  images.add(ImageResponse(
                    imageUrl: tempFile.path,
                    imageId: '${candidates.indexOf(candidate)}_${partsList.indexOf(part)}',
                    metadata: candidate,
                  ));
                  print('✅ [Yunwu] inlineData 图片已保存: ${tempFile.path}');
                }
                continue;
              }

              // 格式2: text 中提取 URL
              if (part.containsKey('text')) {
                final text = part['text'] as String;
                final markdownPattern = RegExp(r'!\[.*?\]\((https?://[^)]+)\)');
                final match = markdownPattern.firstMatch(text);
                if (match != null && match.group(1) != null) {
                  images.add(ImageResponse(
                    imageUrl: match.group(1)!,
                    imageId: '${candidates.indexOf(candidate)}',
                    metadata: candidate,
                  ));
                } else {
                  final urlPattern = RegExp(r'https?://[^\s)]+');
                  final urlMatch = urlPattern.firstMatch(text);
                  if (urlMatch != null) {
                    images.add(ImageResponse(
                      imageUrl: urlMatch.group(0)!,
                      imageId: '${candidates.indexOf(candidate)}',
                      metadata: candidate,
                    ));
                  }
                }
              }
            }
          }
        }

        print('🎨 [Yunwu] 解析到 ${images.length} 张图片');
        return ApiResponse.success(images, statusCode: 200);
      } else {
        print('❌ [Yunwu] 生成失败: ${response.statusCode} - ${response.body}');
        return ApiResponse.failure(
          '图像生成失败: ${response.statusCode} - ${response.body}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      print('❌ [Yunwu] 图像生成异常: $e');
      return ApiResponse.failure('图像生成错误: $e');
    }
  }

  /// 判断是否为 VEO OpenAI 格式模型
  bool _isVeoOpenAIModel(String model) => model.startsWith('veo_3_1');

  /// 判断是否为 Grok 视频模型
  bool _isGrokVideoModel(String model) => model.startsWith('grok-video');

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
      final useModel = model ?? 'sora-2-all';
      print('🎬 [Yunwu] generateVideos: model=$useModel, ratio=$ratio, quality=$quality');

      // VEO 模型走 OpenAI 视频格式 (/v1/videos)
      if (_isVeoOpenAIModel(useModel)) {
        print('🎬 [Yunwu] → VEO OpenAI 格式');
        return _generateVeoVideoOpenAI(
          prompt: prompt,
          model: useModel,
          ratio: ratio,
          referenceImages: referenceImages,
          parameters: parameters,
        );
      }

      // Grok 视频模型走统一格式但使用 Grok 参数
      if (_isGrokVideoModel(useModel)) {
        print('🎬 [Yunwu] → Grok 统一格式');
        return _generateGrokVideo(
          prompt: prompt,
          model: useModel,
          ratio: ratio,
          quality: quality,
          referenceImages: referenceImages,
          parameters: parameters,
        );
      }

      // Sora 等模型走统一格式 (/v1/video/create)
      final seconds = parameters?['seconds'] as int? ?? 10;
      final characterUrl = parameters?['character_url'] as String?;
      final characterTimestamps = parameters?['character_timestamps'] as String?;

      // 从 ratio 推断 orientation (e.g. "720x1280" → portrait, "1280x720" → landscape)
      String orientation = 'portrait';
      if (ratio != null && ratio.contains('x')) {
        final parts = ratio.split('x');
        final w = int.tryParse(parts[0]) ?? 720;
        final h = int.tryParse(parts[1]) ?? 1280;
        orientation = w >= h ? 'landscape' : 'portrait';
      } else if (ratio == '16:9') {
        orientation = 'landscape';
      } else if (ratio == '9:16') {
        orientation = 'portrait';
      }

      // quality 映射 size: "1080p"/"hd" → large, 默认 small
      String size = 'small';
      if (quality == '1080p' || quality == 'hd' || quality == 'large') {
        size = 'large';
      }

      final request = YunwuVideoCreateRequest(
        images: referenceImages ?? [],
        model: useModel,
        orientation: orientation,
        prompt: prompt,
        size: size,
        duration: seconds,
        characterUrl: characterUrl,
        characterTimestamps: characterTimestamps,
      );

      final result = await createVideo(request);

      if (result.isSuccess && result.data != null) {
        final task = result.data!;
        return ApiResponse.success([
          VideoResponse(
            videoUrl: '',
            videoId: task.id,
            duration: seconds,
            metadata: {
              'taskId': task.id,
              'status': task.status,
              'isTask': true,
            },
          ),
        ], statusCode: 200);
      } else {
        return ApiResponse.failure(result.error ?? '创建视频失败');
      }
    } catch (e) {
      return ApiResponse.failure('视频生成错误: $e');
    }
  }

  /// VEO 视频生成（OpenAI 视频格式 /v1/videos，multipart/form-data）
  Future<ApiResponse<List<VideoResponse>>> _generateVeoVideoOpenAI({
    required String prompt,
    required String model,
    String? ratio,
    List<String>? referenceImages,
    Map<String, dynamic>? parameters,
  }) async {
    final seconds = parameters?['seconds'] as int? ?? 8;

    // 转换比例格式: "1280x720" → "16x9", "720x1280" → "9x16", "16:9" → "16x9"
    String size = '16x9';
    if (ratio != null) {
      if (ratio == '16:9' || ratio == '1280x720') {
        size = '16x9';
      } else if (ratio == '9:16' || ratio == '720x1280') {
        size = '9x16';
      } else if (ratio.contains('x')) {
        final parts = ratio.split('x');
        final w = int.tryParse(parts[0]) ?? 1280;
        final h = int.tryParse(parts[1]) ?? 720;
        size = w >= h ? '16x9' : '9x16';
      }
    }

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('${config.baseUrl}/v1/videos'),
    );

    request.headers['Authorization'] = 'Bearer ${config.apiKey}';
    request.fields['model'] = model;
    request.fields['prompt'] = prompt;
    request.fields['seconds'] = seconds.toString();
    request.fields['size'] = size;
    request.fields['watermark'] = 'false';

    // 添加参考图片（垫图）
    if (referenceImages != null && referenceImages.isNotEmpty) {
      for (final imagePath in referenceImages) {
        if (imagePath.startsWith('http')) {
          // URL 方式：作为字段传递
          request.fields['input_reference'] = imagePath;
        } else {
          // 本地文件方式
          request.files.add(
            await http.MultipartFile.fromPath('input_reference', imagePath),
          );
        }
      }
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final taskId = data['id'] as String;
      final status = data['status'] as String? ?? 'queued';
      return ApiResponse.success([
        VideoResponse(
          videoUrl: '',
          videoId: taskId,
          duration: seconds,
          metadata: {
            'taskId': taskId,
            'status': status,
            'isTask': true,
          },
        ),
      ], statusCode: 200);
    } else {
      return ApiResponse.failure(
        '创建 VEO 视频失败: ${response.statusCode} - ${response.body}',
        statusCode: response.statusCode,
      );
    }
  }

  /// Grok 视频生成（统一视频格式 /v1/video/create，JSON body）
  ///
  /// Grok 使用 aspect_ratio(2:3/3:2/1:1) + size(720P/1080P)，与 Sora 的参数格式不同
  Future<ApiResponse<List<VideoResponse>>> _generateGrokVideo({
    required String prompt,
    required String model,
    String? ratio,
    String? quality,
    List<String>? referenceImages,
    Map<String, dynamic>? parameters,
  }) async {
    // 转换比例: "16:9" → "3:2", "9:16" → "2:3", "1:1" → "1:1"
    String aspectRatio = '3:2';
    if (ratio != null) {
      if (ratio == '16:9' || ratio == '1280x720' || ratio == '3:2') {
        aspectRatio = '3:2';
      } else if (ratio == '9:16' || ratio == '720x1280' || ratio == '2:3') {
        aspectRatio = '2:3';
      } else if (ratio == '1:1' || ratio == '1024x1024') {
        aspectRatio = '1:1';
      } else if (ratio.contains('x')) {
        final parts = ratio.split('x');
        final w = int.tryParse(parts[0]) ?? 1280;
        final h = int.tryParse(parts[1]) ?? 720;
        aspectRatio = w > h ? '3:2' : (w < h ? '2:3' : '1:1');
      }
    }

    // 分辨率映射
    String size = '720P';
    if (quality == '1080p' || quality == 'hd' || quality == 'large') {
      size = '1080P';
    }

    final requestBody = <String, dynamic>{
      'model': model,
      'prompt': prompt,
      'aspect_ratio': aspectRatio,
      'size': size,
      'images': referenceImages ?? [],
    };

    final response = await http.post(
      Uri.parse('${config.baseUrl}/v1/video/create'),
      headers: {
        'Authorization': 'Bearer ${config.apiKey}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final taskId = data['id'] as String;
      final status = data['status'] as String? ?? 'pending';
      return ApiResponse.success([
        VideoResponse(
          videoUrl: '',
          videoId: taskId,
          duration: null,
          metadata: {
            'taskId': taskId,
            'status': status,
            'isTask': true,
          },
        ),
      ], statusCode: 200);
    } else {
      return ApiResponse.failure(
        '创建 Grok 视频失败: ${response.statusCode} - ${response.body}',
        statusCode: response.statusCode,
      );
    }
  }

  @override
  Future<ApiResponse<UploadResponse>> uploadAsset({
    required String filePath,
    String? assetType,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      // TODO: 根据 Yunwu API 文档实现文件上传
      return ApiResponse.failure('Yunwu 文件上传 API 待实现');
    } catch (e) {
      return ApiResponse.failure('上传错误: $e');
    }
  }

  @override
  Future<ApiResponse<List<String>>> getAvailableModels({
    String? modelType,
  }) async {
    try {
      // TODO: 根据 Yunwu API 文档实现模型列表获取
      // 暂时返回空列表
      return ApiResponse.success([], statusCode: 200);
    } catch (e) {
      return ApiResponse.failure('获取模型列表错误: $e');
    }
  }

  // ============================================================
  // Yunwu 视频 API（统一格式）
  // ============================================================

  /// 创建视频（统一格式 - 专用接口）
  /// 
  /// **API 文档**: POST /v1/video/create
  /// 
  /// **参数**:
  /// - [request] 视频创建请求对象
  /// 
  /// **返回**:
  /// - id: 任务ID
  /// - status: 初始状态
  /// - status_update_time: 状态更新时间
  /// 
  /// **后续操作**: 使用返回的任务ID调用 `queryVideoTask()` 轮询状态
  Future<ApiResponse<YunwuVideoTaskStatus>> createVideo(YunwuVideoCreateRequest request) async {
    try {
      final requestJson = request.toJson();
      final url = '${config.baseUrl}/v1/video/create';
      
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestJson),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResponse.success(
          YunwuVideoTaskStatus.fromJson(data),
          statusCode: 200,
        );
      } else {
        // 尝试解析 API 返回的中文错误信息
        String errorMsg = '服务器返回错误 (${response.statusCode})';
        try {
          final errorData = jsonDecode(response.body) as Map<String, dynamic>;
          final error = errorData['error'] as Map<String, dynamic>?;
          if (error != null) {
            errorMsg = (error['message_zh'] as String?) ??
                       (error['message'] as String?) ??
                       errorMsg;
          }
        } catch (_) {}
        return ApiResponse.failure(
          errorMsg,
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('创建视频错误: $e');
    }
  }

  /// 创建视频（Chat 格式 - OpenAI 兼容）
  /// 
  /// **API 文档**: POST /v1/chat/completions
  /// 
  /// **特点**:
  /// - 使用 OpenAI Chat 格式
  /// - 支持多模态内容（文本 + 图片）
  /// - 支持流式输出（stream: true，返回 SSE 流）
  /// - 支持多轮对话修改视频
  /// 
  /// **参数**:
  /// - [prompt] 视频生成提示词（简单模式）
  /// - [messages] 完整的对话历史（高级模式，用于连续修改）
  /// - [model] 模型名称（如 "sora-2", "sora-2-pro"）
  /// - [imageUrls] 参考图片URL列表（可选，用于图生视频）
  /// - [stream] 是否使用流式输出
  /// - [parameters] 其他参数（temperature, top_p, max_tokens 等）
  /// 
  /// **返回**: Chat 格式的响应（包含任务ID、进度、视频链接等）
  /// 
  /// **使用场景**:
  /// 1. 单次生成：传入 prompt
  /// 2. 连续修改：传入 messages（包含历史对话）
  Future<ApiResponse<Map<String, dynamic>>> createVideoByChat({
    String? prompt,
    List<Map<String, dynamic>>? messages,
    required String model,
    List<String>? imageUrls,
    bool stream = false,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      late final List<Map<String, dynamic>> messageList;
      
      if (messages != null && messages.isNotEmpty) {
        // 高级模式：使用提供的完整对话历史
        messageList = messages;
      } else if (prompt != null) {
        // 简单模式：构建单条消息
        dynamic messageContent;
        
        if (imageUrls != null && imageUrls.isNotEmpty) {
          // 多模态内容：文本 + 图片
          final contentList = <Map<String, dynamic>>[];
          
          // 添加文本
          contentList.add({
            'type': 'text',
            'text': prompt,
          });
          
          // 添加图片
          for (final url in imageUrls) {
            contentList.add({
              'type': 'image_url',
              'image_url': {
                'url': url,
              },
            });
          }
          
          messageContent = contentList;
        } else {
          // 纯文本内容
          messageContent = prompt;
        }

        messageList = [
          {
            'role': 'user',
            'content': messageContent,
          }
        ];
      } else {
        return ApiResponse.failure('必须提供 prompt 或 messages');
      }

      final requestBody = {
        'model': model,
        'messages': messageList,
        'stream': stream,
        ...?parameters,
      };

      final response = await http.post(
        Uri.parse('${config.baseUrl}/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResponse.success(data, statusCode: 200);
      } else {
        return ApiResponse.failure(
          '创建视频失败: ${response.statusCode} - ${response.body}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('创建视频错误: $e');
    }
  }

  /// 查询视频任务状态
  /// 
  /// **API 文档**: GET /v1/video/query
  /// 
  /// **参数**:
  /// - [taskId] 任务ID
  ///   - 统一格式: "sora-2:task_01kbfq03gpe0wr9ge11z09xqrj"
  ///   - OpenAI格式: "video_55cb73b3-60af-40c8-95fd-eae8fd758ade"
  /// 
  /// **返回**:
  /// - id: 任务ID
  /// - status: 任务状态
  /// - video_url: 视频URL（完成时）
  /// - enhanced_prompt: 增强后的提示词
  /// - status_update_time: 状态更新时间戳
  Future<ApiResponse<YunwuVideoTaskStatus>> queryVideoTask(String taskId) async {
    try {
      // OpenAI 视频格式的任务ID以 video_ 开头，使用 /v1/videos/{id}
      final isOpenAIFormat = taskId.startsWith('video_');

      final Uri uri = isOpenAIFormat
          ? Uri.parse('${config.baseUrl}/v1/videos/$taskId')
          : Uri.parse('${config.baseUrl}/v1/video/query').replace(queryParameters: {'id': taskId});

      print('🔍 [Yunwu] queryVideoTask: taskId=$taskId, isOpenAI=$isOpenAIFormat, uri=$uri');

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        print('🔍 [Yunwu] queryVideoTask 响应: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}');
        final taskStatus = YunwuVideoTaskStatus.fromJson(data);
        print('🔍 [Yunwu] 解析状态: status=${taskStatus.status}, videoUrl=${taskStatus.videoUrl}, isCompleted=${taskStatus.isCompleted}, isFailed=${taskStatus.isFailed}');

        // OpenAI 格式：任务完成但无 videoUrl 时，从 /content 端点获取下载地址
        if (isOpenAIFormat && taskStatus.isCompleted && taskStatus.videoUrl == null) {
          final contentUrl = '${config.baseUrl}/v1/videos/$taskId/content';
          try {
            // 使用 HttpClient 禁止自动跟随重定向，以获取 CDN 下载地址
            final httpClient = io.HttpClient();
            httpClient.autoUncompress = false;
            try {
              final req = await httpClient.getUrl(Uri.parse(contentUrl));
              req.headers.set('Authorization', 'Bearer ${config.apiKey}');
              req.followRedirects = false;
              final res = await req.close();

              String? downloadUrl;
              if (res.statusCode == 302 || res.statusCode == 301) {
                // 重定向到 CDN 公开地址
                downloadUrl = res.headers.value('location');
              } else if (res.statusCode == 200) {
                final contentType = res.headers.contentType?.value ?? '';
                if (contentType.contains('json')) {
                  final body = await res.transform(io.SystemEncoding().decoder).join();
                  final contentData = jsonDecode(body) as Map<String, dynamic>;
                  downloadUrl = contentData['url'] as String? ??
                      contentData['download_url'] as String? ??
                      contentData['video_url'] as String?;
                } else {
                  // 二进制视频：保存到临时文件
                  final tempDir = await io.Directory.systemTemp.createTemp('veo_');
                  final tempFile = io.File('${tempDir.path}/video.mp4');
                  await res.pipe(tempFile.openWrite());
                  downloadUrl = tempFile.path;
                }
              }
              httpClient.close();

              if (downloadUrl != null) {
                return ApiResponse.success(
                  YunwuVideoTaskStatus(
                    id: taskStatus.id,
                    status: taskStatus.status,
                    videoUrl: downloadUrl,
                    enhancedPrompt: taskStatus.enhancedPrompt,
                    statusUpdateTime: taskStatus.statusUpdateTime,
                    failReason: taskStatus.failReason,
                  ),
                  statusCode: 200,
                );
              }
            } finally {
              httpClient.close(force: true);
            }
          } catch (_) {
            // /content 请求失败，回退使用 content URL
          }
          // 兜底：直接使用 content 端点 URL（可能需要 auth）
          return ApiResponse.success(
            YunwuVideoTaskStatus(
              id: taskStatus.id,
              status: taskStatus.status,
              videoUrl: contentUrl,
              enhancedPrompt: taskStatus.enhancedPrompt,
              statusUpdateTime: taskStatus.statusUpdateTime,
              failReason: taskStatus.failReason,
            ),
            statusCode: 200,
          );
        }

        return ApiResponse.success(taskStatus, statusCode: 200);
      } else {
        print('❌ [Yunwu] queryVideoTask 失败: ${response.statusCode} - ${response.body}');
        return ApiResponse.failure(
          '查询任务失败: ${response.statusCode} - ${response.body}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      print('❌ [Yunwu] queryVideoTask 异常: $e');
      return ApiResponse.failure('查询任务错误: $e');
    }
  }

  /// 创建视频（VEO 统一格式 - 旧版 API）
  /// 
  /// **API 文档**: POST /v1/video/create
  /// 
  /// **注意**: 新的 VEO 模型(veo_3_1-4K, veo_3_1-fast-4K)已改用 OpenAI 视频格式(/v1/videos)
  /// 此方法保留用于兼容旧模型
  /// 
  /// **返回**: 任务ID + 状态
  Future<ApiResponse<YunwuVideoTaskStatus>> createVeoVideo(YunwuVeoCreateRequest request) async {
    try {
      final response = await http.post(
        Uri.parse('${config.baseUrl}/v1/video/create'),
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(request.toJson()),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResponse.success(
          YunwuVideoTaskStatus.fromJson(data),
          statusCode: 200,
        );
      } else {
        return ApiResponse.failure(
          '创建 VEO 视频失败: ${response.statusCode} - ${response.body}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('创建 VEO 视频错误: $e');
    }
  }

  // ============================================================
  // Yunwu 角色管理 API
  // ============================================================

  /// 创建角色（从视频中提取）
  /// 
  /// **API 文档**: POST /sora/v1/characters
  /// 
  /// **用途**: 从视频中提取角色，用于后续视频生成中的角色引用
  /// 
  /// **参数**:
  /// - [videoUrl] 视频URL（与 fromTask 二选一）
  /// - [fromTask] 任务ID（与 videoUrl 二选一）
  /// - [timestamps] 时间范围，如 "1,3" 表示1-3秒（差值1-3秒）
  /// 
  /// **返回**: 角色信息（id, username, permalink, profile_picture_url）
  /// 
  /// **使用**: 在提示词中使用 `@{username}` 引用角色
  Future<ApiResponse<YunwuCharacter>> createCharacter({
    String? videoUrl,
    String? fromTask,
    required String timestamps,
  }) async {
    try {
      if (videoUrl == null && fromTask == null) {
        return ApiResponse.failure('必须提供 videoUrl 或 fromTask');
      }

      final requestBody = <String, dynamic>{
        'timestamps': timestamps,
      };
      
      if (videoUrl != null) {
        requestBody['url'] = videoUrl;
      }
      
      if (fromTask != null) {
        requestBody['from_task'] = fromTask;
      }

      final response = await http.post(
        Uri.parse('${config.baseUrl}/sora/v1/characters'),
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResponse.success(
          YunwuCharacter.fromJson(data),
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
}  // YunwuService 类结束

// ============================================================
// Yunwu 数据模型类
// ============================================================

/// Yunwu 视频任务状态
class YunwuVideoTaskStatus {
  // 状态码常量（统一格式）
  static const String statusPending = 'pending';
  static const String statusImageDownloading = 'image_downloading';
  static const String statusVideoGenerating = 'video_generating';
  static const String statusVideoGenerationCompleted = 'video_generation_completed';
  static const String statusVideoGenerationFailed = 'video_generation_failed';
  static const String statusVideoUpsampling = 'video_upsampling';
  static const String statusVideoUpsamplingCompleted = 'video_upsampling_completed';
  static const String statusVideoUpsamplingFailed = 'video_upsampling_failed';
  static const String statusCompleted = 'completed';
  static const String statusFailed = 'failed';
  static const String statusError = 'error';
  // OpenAI 视频格式状态
  static const String statusQueued = 'queued';
  static const String statusProcessing = 'processing';

  final String id;
  final String status;
  final String? videoUrl;
  final String? enhancedPrompt;
  final int? statusUpdateTime;
  final String? failReason;

  YunwuVideoTaskStatus({
    required this.id,
    required this.status,
    this.videoUrl,
    this.enhancedPrompt,
    this.statusUpdateTime,
    this.failReason,
  });

  factory YunwuVideoTaskStatus.fromJson(Map<String, dynamic> json) {
    // 尝试从多个字段获取失败原因
    String? reason = json['fail_reason'] as String? ??
                     json['error'] as String? ??
                     json['message'] as String?;
    // 如果有嵌套 error 对象
    if (reason == null && json['error'] is Map) {
      final err = json['error'] as Map<String, dynamic>;
      reason = (err['message_zh'] as String?) ?? (err['message'] as String?);
    }
    // 兼容多种 video URL 字段名（统一格式用 video_url，OpenAI 格式可能用 url/output 等）
    String? videoUrl = json['video_url'] as String?;
    videoUrl ??= json['url'] as String?;
    videoUrl ??= json['download_url'] as String?;
    if (videoUrl == null && json['output'] is Map) {
      final output = json['output'] as Map<String, dynamic>;
      videoUrl = output['url'] as String? ?? output['video_url'] as String?;
    }
    if (videoUrl == null && json['result'] is Map) {
      final result = json['result'] as Map<String, dynamic>;
      videoUrl = result['url'] as String? ?? result['video_url'] as String?;
    }

    return YunwuVideoTaskStatus(
      id: json['id'] as String,
      status: json['status'] as String,
      videoUrl: videoUrl,
      enhancedPrompt: json['enhanced_prompt'] as String?,
      statusUpdateTime: json['status_update_time'] as int?,
      failReason: reason,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'status': status,
      'video_url': videoUrl,
      'enhanced_prompt': enhancedPrompt,
      'status_update_time': statusUpdateTime,
      if (failReason != null) 'fail_reason': failReason,
    };
  }

  /// 任务是否已完成
  bool get isCompleted => 
    status == statusCompleted || 
    status == statusVideoUpsamplingCompleted;

  /// 任务是否失败
  bool get isFailed => 
    status == statusFailed || 
    status == statusError ||
    status == statusVideoGenerationFailed ||
    status == statusVideoUpsamplingFailed;

  /// 任务是否进行中
  bool get isProcessing => !isCompleted && !isFailed;

  /// 获取状态的中文描述
  String get statusDescription {
    switch (status) {
      case statusPending:
      case statusQueued:
        return '排队中';
      case statusProcessing:
        return '处理中';
      case statusImageDownloading:
        return '下载图片中';
      case statusVideoGenerating:
        return '生成视频中';
      case statusVideoGenerationCompleted:
        return '视频生成完成';
      case statusVideoGenerationFailed:
        return '视频生成失败';
      case statusVideoUpsampling:
        return '视频增强中';
      case statusVideoUpsamplingCompleted:
        return '视频增强完成';
      case statusVideoUpsamplingFailed:
        return '视频增强失败';
      case statusCompleted:
        return '完成';
      case statusFailed:
        return '失败';
      case statusError:
        return '错误';
      default:
        return status;
    }
  }
}

/// Yunwu 视频创建请求（Sora 格式）
class YunwuVideoCreateRequest {
  final List<String> images;       // 图片链接（可以为空数组，用于文生视频）
  final String model;               // 模型名字（如 "sora-2", "sora-2-all", "sora-2-pro"）
  final String orientation;         // portrait（竖屏）/ landscape（横屏）
  final String prompt;              // 提示词
  final String size;                // small（720p）/ large（1080p）
  final int duration;               // 时长（秒），支持 10, 15, 25
  final bool watermark;             // 水印控制
  final bool private;               // 是否隐藏视频（true-不发布，无法remix）
  final String? characterUrl;       // 角色视频链接（不能含真人）
  final String? characterTimestamps; // 角色出现的秒数范围，格式 "{start},{end}"（差值1-3秒）

  YunwuVideoCreateRequest({
    required this.images,
    required this.model,
    required this.orientation,
    required this.prompt,
    required this.size,
    required this.duration,
    this.watermark = true,
    this.private = false,
    this.characterUrl,
    this.characterTimestamps,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'images': images,
      'model': model,
      'orientation': orientation,
      'prompt': prompt,
      'size': size,
      'duration': duration,
      'watermark': watermark,
      'private': private,
    };
    if (characterUrl != null) {
      json['character_url'] = characterUrl;
    }
    if (characterTimestamps != null) {
      json['character_timestamps'] = characterTimestamps;
    }
    return json;
  }
}

/// Yunwu VEO 视频创建请求（Google VEO 格式）
class YunwuVeoCreateRequest {
  final String model;               // VEO 模型名字（veo2/veo3/veo3.1系列）
  final String prompt;              // 提示词
  final bool enhancePrompt;         // 中文转英文
  final bool enableUpsample;        // 是否启用增强
  final List<String> images;        // 图片数组（首帧/尾帧/组件）
  final String? aspectRatio;        // 比例（仅 veo3 支持："16:9" 或 "9:16"）

  YunwuVeoCreateRequest({
    required this.model,
    required this.prompt,
    this.enhancePrompt = true,       // 默认启用中文转英文
    this.enableUpsample = false,     // 默认不启用增强
    this.images = const [],
    this.aspectRatio,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'model': model,
      'prompt': prompt,
      'enhance_prompt': enhancePrompt,
      'enable_upsample': enableUpsample,
      'images': images,
    };
    
    if (aspectRatio != null) {
      json['aspect_ratio'] = aspectRatio;
    }
    
    return json;
  }
}

/// Yunwu 角色信息
class YunwuCharacter {
  final String id;                    // 角色ID
  final String username;              // 角色名称（用于 @username 引用）
  final String permalink;             // 角色主页链接
  final String profilePictureUrl;     // 角色头像URL

  YunwuCharacter({
    required this.id,
    required this.username,
    required this.permalink,
    required this.profilePictureUrl,
  });

  factory YunwuCharacter.fromJson(Map<String, dynamic> json) {
    return YunwuCharacter(
      id: json['id'] as String,
      username: json['username'] as String,
      permalink: json['permalink'] as String,
      profilePictureUrl: json['profile_picture_url'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'permalink': permalink,
      'profile_picture_url': profilePictureUrl,
    };
  }

  /// 获取角色引用字符串（用于提示词）
  String get reference => '@$username,';
}

/// Yunwu API 辅助类
/// 提供便捷的方法来执行常见的 AI 任务
class YunwuHelper {
  final YunwuService service;

  YunwuHelper(this.service);

  /// 文生视频（简单模式）
  Future<ApiResponse<YunwuVideoTaskStatus>> textToVideo({
    required String prompt,
    required String model,
    String orientation = 'landscape',
    String size = 'large',
    int duration = 10,
    bool watermark = true,
    bool private = false,
  }) async {
    return service.createVideo(
      YunwuVideoCreateRequest(
        images: [],  // 空数组表示文生视频
        model: model,
        orientation: orientation,
        prompt: prompt,
        size: size,
        duration: duration,
        watermark: watermark,
        private: private,
      ),
    );
  }

  /// 图生视频（简单模式）
  Future<ApiResponse<YunwuVideoTaskStatus>> imageToVideo({
    required List<String> imageUrls,
    required String prompt,
    required String model,
    String orientation = 'landscape',
    String size = 'large',
    int duration = 10,
    bool watermark = true,
    bool private = false,
  }) async {
    return service.createVideo(
      YunwuVideoCreateRequest(
        images: imageUrls,
        model: model,
        orientation: orientation,
        prompt: prompt,
        size: size,
        duration: duration,
        watermark: watermark,
        private: private,
      ),
    );
  }

  /// 轮询任务直到完成
  Future<ApiResponse<YunwuVideoTaskStatus>> pollTaskUntilComplete({
    required String taskId,
    Duration interval = const Duration(seconds: 5),
    int maxWaitMinutes = 15,
    void Function(int progress, String status)? onProgress,
  }) async {
    final maxAttempts = (maxWaitMinutes * 60 / interval.inSeconds).ceil();
    for (var i = 0; i < maxAttempts; i++) {
      final result = await service.queryVideoTask(taskId);
      
      if (!result.isSuccess) {
        // 可能是网络抖动，前几次重试
        if (i < 3) {
          print('⚠️ [Yunwu] 轮询第${i+1}次失败，重试... error=${result.errorMessage}');
          await Future.delayed(interval);
          continue;
        }
        print('❌ [Yunwu] 轮询连续失败，放弃: ${result.errorMessage}');
        return result;
      }

      final status = result.data!;

      // 估算进度
      final estimatedProgress = status.isCompleted ? 100 : (i * 100 ~/ maxAttempts).clamp(0, 95);
      onProgress?.call(estimatedProgress, status.statusDescription);
      
      if (status.isCompleted) {
        return result;
      }
      
      if (status.isFailed) {
        final reason = status.failReason ?? status.statusDescription;
        // 翻译常见英文错误为中文
        final zhReason = _translateFailReason(reason);
        return ApiResponse.failure('视频生成失败: $zhReason');
      }

      await Future.delayed(interval);
    }

    return ApiResponse.failure('轮询超时：已等待 $maxWaitMinutes 分钟');
  }

  /// 翻译常见的英文失败原因为中文
  String _translateFailReason(String reason) {
    final lower = reason.toLowerCase();
    if (lower == 'task failed' || lower == 'failed') return '任务处理失败，请重试或更换模型';
    if (lower.contains('timeout')) return '服务器处理超时';
    if (lower.contains('content policy') || lower.contains('safety')) return '内容不符合安全策略';
    if (lower.contains('rate limit')) return '请求过于频繁，请稍后重试';
    if (lower.contains('no available channel')) return '当前模型暂无可用通道，请更换模型或稍后重试';
    if (lower.contains('quota') || lower.contains('balance')) return '账户额度不足';
    return reason;
  }
}
