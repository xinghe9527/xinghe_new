import 'dart:convert';
import 'package:http/http.dart' as http;
import '../base/api_service_base.dart';
import '../base/api_response.dart';

/// Yunwu（云雾）API 服务实现
/// 
/// 这是一个独立的服务商，与 GeekNow、OpenAI 等并列
/// 支持 LLM、图像、视频等多种 AI 能力
/// 
/// API 文档来源: https://yunwu.ai
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
      final useModel = model ?? 'gemini-2.5-flash-image-preview';
      
      // 构建 Gemini 图像生成请求
      final requestBody = <String, dynamic>{
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt}
            ],
          }
        ],
        'generationConfig': {
          'responseModalities': ['TEXT', 'IMAGE'],
        },
      };

      // 如果有参考图片，添加到 parts 中
      if (referenceImages != null && referenceImages.isNotEmpty) {
        final parts = requestBody['contents'][0]['parts'] as List;
        for (final imageUrl in referenceImages) {
          parts.add({
            'inline_data': {
              'mime_type': 'image/jpeg',
              'data': imageUrl,  // 注意：这里应该是 base64 数据，不是 URL
            }
          });
        }
      }

      // 使用 query 参数传递 API Key
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
        
        // 解析 Gemini 图像响应
        final images = <ImageResponse>[];
        final candidates = data['candidates'] as List?;
        
        if (candidates != null) {
          for (final candidate in candidates) {
            final content = (candidate as Map<String, dynamic>)['content'] as Map<String, dynamic>?;
            final parts = content?['parts'] as List?;
            
            if (parts != null) {
              for (final part in parts) {
                if (part is Map<String, dynamic> && part.containsKey('text')) {
                  final text = part['text'] as String;
                  
                  // 提取图片 URL（Markdown 或普通 URL）
                  final markdownPattern = RegExp(r'!\[.*?\]\((https?://[^)]+)\)');
                  final match = markdownPattern.firstMatch(text);
                  if (match != null && match.group(1) != null) {
                    images.add(ImageResponse(
                      imageUrl: match.group(1)!,
                      imageId: (candidate as Map)['index']?.toString(),
                      metadata: candidate,
                    ));
                  }
                }
              }
            }
          }
        }

        return ApiResponse.success(images, statusCode: 200);
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
    try {
      // TODO: 根据 Yunwu API 文档实现视频生成
      return ApiResponse.failure('Yunwu 视频生成 API 待实现');
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
          '创建视频失败: ${response.statusCode} - ${response.body}',
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
  /// - [taskId] 任务ID，格式如 "sora-2:task_01kbfq03gpe0wr9ge11z09xqrj"
  /// 
  /// **返回**:
  /// - id: 任务ID
  /// - status: 任务状态
  /// - video_url: 视频URL（完成时）
  /// - enhanced_prompt: 增强后的提示词
  /// - status_update_time: 状态更新时间戳
  Future<ApiResponse<YunwuVideoTaskStatus>> queryVideoTask(String taskId) async {
    try {
      final response = await http.get(
        Uri.parse('${config.baseUrl}/v1/video/query').replace(queryParameters: {
          'id': taskId,
        }),
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResponse.success(
          YunwuVideoTaskStatus.fromJson(data),
          statusCode: 200,
        );
      } else {
        return ApiResponse.failure(
          '查询任务失败: ${response.statusCode} - ${response.body}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('查询任务错误: $e');
    }
  }

  /// 创建视频（VEO 格式 - Google VEO 模型）
  /// 
  /// **API 文档**: POST /v1/video/create
  /// 
  /// **支持的模型**:
  /// - VEO2: veo2, veo2-fast, veo2-fast-frames, veo2-fast-components, veo2-pro, veo2-pro-components
  /// - VEO3: veo3, veo3-fast, veo3-fast-frames, veo3-frames, veo3-pro, veo3-pro-frames（支持音频）
  /// - VEO3.1: veo3.1, veo3.1-fast, veo3.1-pro（自适应首帧）
  /// 
  /// **参数**:
  /// - [request] VEO 视频创建请求对象
  /// 
  /// **特点**:
  /// - VEO3 系列支持自动配音
  /// - 支持首帧、尾帧、组件等多种模式
  /// - 支持中文提示词自动转英文
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
  // 状态码常量
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

  final String id;
  final String status;
  final String? videoUrl;
  final String? enhancedPrompt;
  final int? statusUpdateTime;

  YunwuVideoTaskStatus({
    required this.id,
    required this.status,
    this.videoUrl,
    this.enhancedPrompt,
    this.statusUpdateTime,
  });

  factory YunwuVideoTaskStatus.fromJson(Map<String, dynamic> json) {
    return YunwuVideoTaskStatus(
      id: json['id'] as String,
      status: json['status'] as String,
      videoUrl: json['video_url'] as String?,
      enhancedPrompt: json['enhanced_prompt'] as String?,
      statusUpdateTime: json['status_update_time'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'status': status,
      'video_url': videoUrl,
      'enhanced_prompt': enhancedPrompt,
      'status_update_time': statusUpdateTime,
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
        return '排队中';
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

  YunwuVideoCreateRequest({
    required this.images,
    required this.model,
    required this.orientation,
    required this.prompt,
    required this.size,
    required this.duration,
    this.watermark = true,   // 默认 true（优先无水印，出错兜底有水印）
    this.private = false,    // 默认 false（公开，可 remix）
  });

  Map<String, dynamic> toJson() {
    return {
      'images': images,
      'model': model,
      'orientation': orientation,
      'prompt': prompt,
      'size': size,
      'duration': duration,
      'watermark': watermark,
      'private': private,
    };
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
    Duration interval = const Duration(seconds: 3),
    int maxAttempts = 100,
    void Function(int progress)? onProgress,
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      final result = await service.queryVideoTask(taskId);
      
      if (!result.isSuccess) {
        return result;
      }

      final status = result.data!;
      
      if (status.isCompleted) {
        return result;
      }
      
      if (status.isFailed) {
        return ApiResponse.failure('任务失败');
      }

      // 等待后重试
      await Future.delayed(interval);
    }

    return ApiResponse.failure('轮询超时');
  }
}
