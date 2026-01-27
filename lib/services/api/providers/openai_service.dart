import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../base/api_service_base.dart';
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

  /// OpenAI对话格式生图
  /// 使用 /v1/chat/completions 端点，支持文生图和图生图
  /// 
  /// [prompt] - 文本提示词
  /// [model] - 模型名称，如 "gpt-4o", "dall-e-3" 等
  /// [referenceImagePaths] - 参考图片的本地路径列表（用于图生图）
  /// [messages] - 自定义消息列表（如果提供，将覆盖 prompt 和 referenceImagePaths）
  /// [parameters] - 其他参数，如 temperature, top_p, n, max_tokens 等
  Future<ApiResponse<ChatImageResponse>> generateImagesByChat({
    String? prompt,
    String? model,
    List<String>? referenceImagePaths,
    List<ChatMessage>? messages,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      // 构建消息列表
      final messageList = messages ?? await _buildChatMessages(
        prompt: prompt,
        referenceImagePaths: referenceImagePaths,
      );

      // 构建请求体
      final requestBody = {
        'model': model ?? config.model ?? 'gpt-4o',
        'messages': messageList.map((msg) => msg.toJson()).toList(),
        ...?parameters,
      };

      // 处理 baseUrl：如果以 /v1 结尾，去掉它（避免路径重复）
      var apiBaseUrl = config.baseUrl;
      if (apiBaseUrl.endsWith('/v1')) {
        apiBaseUrl = apiBaseUrl.substring(0, apiBaseUrl.length - 3);
      }

      // 发送请求
      final response = await http.post(
        Uri.parse('$apiBaseUrl/v1/chat/completions'),
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

  /// 构建聊天消息列表
  Future<List<ChatMessage>> _buildChatMessages({
    String? prompt,
    List<String>? referenceImagePaths,
  }) async {
    final messages = <ChatMessage>[];

    // 如果有参考图片，构建图生图消息
    if (referenceImagePaths != null && referenceImagePaths.isNotEmpty) {
      final contentList = <ChatMessageContent>[];

      // 添加参考图片
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

      // 添加文本提示词
      if (prompt != null && prompt.isNotEmpty) {
        contentList.add(ChatMessageContent.text(text: prompt));
      }

      messages.add(
        ChatMessage(
          role: 'user',
          content: contentList,
        ),
      );
    } else if (prompt != null && prompt.isNotEmpty) {
      // 纯文生图
      messages.add(
        ChatMessage(
          role: 'user',
          content: [ChatMessageContent.text(text: prompt)],
        ),
      );
    }

    return messages;
  }

  /// 获取MIME类型
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
}

/// 聊天消息
class ChatMessage {
  final String role;
  final dynamic content; // 可以是 String 或 List<ChatMessageContent>

  ChatMessage({
    required this.role,
    required this.content,
  });

  Map<String, dynamic> toJson() {
    if (content is String) {
      return {
        'role': role,
        'content': content,
      };
    } else if (content is List<ChatMessageContent>) {
      return {
        'role': role,
        'content': (content as List<ChatMessageContent>)
            .map((c) => c.toJson())
            .toList(),
      };
    } else {
      return {
        'role': role,
        'content': content,
      };
    }
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final contentData = json['content'];
    dynamic parsedContent;

    if (contentData is String) {
      parsedContent = contentData;
    } else if (contentData is List) {
      parsedContent = contentData
          .map((item) => ChatMessageContent.fromJson(item as Map<String, dynamic>))
          .toList();
    } else {
      parsedContent = contentData;
    }

    return ChatMessage(
      role: json['role'] as String,
      content: parsedContent,
    );
  }
}

/// 聊天消息内容
class ChatMessageContent {
  final String type; // "text" 或 "image_url"
  final String? text;
  final ChatImageUrl? imageUrl;

  ChatMessageContent({
    required this.type,
    this.text,
    this.imageUrl,
  });

  /// 创建文本内容
  factory ChatMessageContent.text({required String text}) {
    return ChatMessageContent(
      type: 'text',
      text: text,
    );
  }

  /// 创建图片内容
  factory ChatMessageContent.image({
    required String imageUrl,
    String? detail,
  }) {
    return ChatMessageContent(
      type: 'image_url',
      imageUrl: ChatImageUrl(url: imageUrl, detail: detail),
    );
  }

  Map<String, dynamic> toJson() {
    if (type == 'text') {
      return {
        'type': 'text',
        'text': text,
      };
    } else {
      return {
        'type': 'image_url',
        'image_url': imageUrl!.toJson(),
      };
    }
  }

  factory ChatMessageContent.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    if (type == 'text') {
      return ChatMessageContent.text(text: json['text'] as String);
    } else {
      return ChatMessageContent.image(
        imageUrl: (json['image_url'] as Map<String, dynamic>)['url'] as String,
        detail: (json['image_url'] as Map<String, dynamic>?)?['detail'] as String?,
      );
    }
  }
}

/// 聊天图片URL
class ChatImageUrl {
  final String url;
  final String? detail; // "auto", "low", "high"

  ChatImageUrl({
    required this.url,
    this.detail,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'url': url,
    };
    if (detail != null) {
      json['detail'] = detail;
    }
    return json;
  }
}

/// 聊天图像生成响应
class ChatImageResponse {
  final String id;
  final String object;
  final int created;
  final String model;
  final List<ChatImageChoice> choices;
  final ChatImageUsage? usage;
  final Map<String, dynamic> metadata;

  ChatImageResponse({
    required this.id,
    required this.object,
    required this.created,
    required this.model,
    required this.choices,
    this.usage,
    required this.metadata,
  });

  factory ChatImageResponse.fromJson(Map<String, dynamic> json) {
    return ChatImageResponse(
      id: json['id'] as String,
      object: json['object'] as String,
      created: json['created'] as int,
      model: json['model'] as String,
      choices: (json['choices'] as List)
          .map((choice) => ChatImageChoice.fromJson(choice as Map<String, dynamic>))
          .toList(),
      usage: json['usage'] != null
          ? ChatImageUsage.fromJson(json['usage'] as Map<String, dynamic>)
          : null,
      metadata: json,
    );
  }

  /// 获取所有生成的图片URL
  List<String> get imageUrls {
    return choices
        .map((choice) => choice.extractImageUrls())
        .expand((urls) => urls)
        .toList();
  }

  /// 获取第一个图片URL
  String? get firstImageUrl {
    final urls = imageUrls;
    return urls.isNotEmpty ? urls.first : null;
  }
}

/// 聊天图像选择项
class ChatImageChoice {
  final int index;
  final ChatMessage message;
  final String? finishReason;

  ChatImageChoice({
    required this.index,
    required this.message,
    this.finishReason,
  });

  factory ChatImageChoice.fromJson(Map<String, dynamic> json) {
    return ChatImageChoice(
      index: json['index'] as int,
      message: ChatMessage.fromJson(json['message'] as Map<String, dynamic>),
      finishReason: json['finish_reason'] as String?,
    );
  }

  /// 从消息内容中提取图片URL
  List<String> extractImageUrls() {
    final content = message.content;
    final urls = <String>[];

    if (content is String) {
      // 1. 优先提取 Markdown 格式的图片链接：![xxx](url)
      final markdownPattern = RegExp(r'!\[.*?\]\((https?://[^)]+)\)');
      final markdownMatches = markdownPattern.allMatches(content);
      for (final match in markdownMatches) {
        if (match.group(1) != null) {
          urls.add(match.group(1)!);
        }
      }
      
      // 2. 如果没有找到 Markdown 格式，尝试直接提取 URL
      if (urls.isEmpty) {
        final urlPattern = RegExp(r'https?://[^\s)]+');
        final matches = urlPattern.allMatches(content);
        for (final match in matches) {
          urls.add(match.group(0)!);
        }
      }
    } else if (content is List<ChatMessageContent>) {
      for (final item in content) {
        if (item.type == 'image_url' && item.imageUrl != null) {
          urls.add(item.imageUrl!.url);
        }
      }
    }

    return urls;
  }
}

/// 聊天图像使用统计
class ChatImageUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  ChatImageUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });

  factory ChatImageUsage.fromJson(Map<String, dynamic> json) {
    return ChatImageUsage(
      promptTokens: json['prompt_tokens'] as int,
      completionTokens: json['completion_tokens'] as int,
      totalTokens: json['total_tokens'] as int,
    );
  }
}

/// OpenAI 聊天图像生成辅助类
/// 提供便捷的方法来执行常见的图像生成任务
class OpenAIChatImageHelper {
  final OpenAIService service;

  OpenAIChatImageHelper(this.service);

  /// 简单文生图
  /// 
  /// [prompt] - 文本提示词
  /// [model] - 模型名称，默认使用配置中的模型
  Future<String?> textToImage({
    required String prompt,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    final result = await service.generateImagesByChat(
      prompt: prompt,
      model: model,
      parameters: parameters,
    );

    if (result.isSuccess) {
      return result.data!.firstImageUrl;
    }
    return null;
  }

  /// 简单图生图
  /// 
  /// [imagePath] - 参考图片路径
  /// [prompt] - 文本提示词，描述期望的变化
  /// [model] - 模型名称
  Future<String?> imageToImage({
    required String imagePath,
    required String prompt,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    final result = await service.generateImagesByChat(
      prompt: prompt,
      referenceImagePaths: [imagePath],
      model: model,
      parameters: parameters,
    );

    if (result.isSuccess) {
      return result.data!.firstImageUrl;
    }
    return null;
  }

  /// 多图融合生成
  /// 
  /// [imagePaths] - 多张参考图片路径
  /// [prompt] - 文本提示词，描述如何融合
  Future<String?> multiImageBlend({
    required List<String> imagePaths,
    required String prompt,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    final result = await service.generateImagesByChat(
      prompt: prompt,
      referenceImagePaths: imagePaths,
      model: model,
      parameters: parameters,
    );

    if (result.isSuccess) {
      return result.data!.firstImageUrl;
    }
    return null;
  }

  /// 批量生成（一个提示词生成多张图片）
  /// 
  /// [prompt] - 文本提示词
  /// [count] - 生成数量
  Future<List<String>> generateMultiple({
    required String prompt,
    required int count,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    final params = {...?parameters, 'n': count};
    
    final result = await service.generateImagesByChat(
      prompt: prompt,
      model: model,
      parameters: params,
    );

    if (result.isSuccess) {
      return result.data!.imageUrls;
    }
    return [];
  }

  /// 风格转换
  /// 
  /// [imagePath] - 原始图片路径
  /// [targetStyle] - 目标风格（如 "油画", "水彩", "素描" 等）
  Future<String?> styleTransfer({
    required String imagePath,
    required String targetStyle,
    String? model,
    bool keepComposition = true,
    Map<String, dynamic>? parameters,
  }) async {
    final prompt = keepComposition
        ? '将这张图片转换成${targetStyle}风格，保持主要构图和内容不变'
        : '将这张图片转换成${targetStyle}风格';

    return imageToImage(
      imagePath: imagePath,
      prompt: prompt,
      model: model,
      parameters: parameters,
    );
  }

  /// 图片增强/优化
  /// 
  /// [imagePath] - 原始图片路径
  /// [enhancements] - 增强描述（如 "提高清晰度", "增强色彩" 等）
  Future<String?> enhanceImage({
    required String imagePath,
    required List<String> enhancements,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    final prompt = '对这张图片进行以下优化: ${enhancements.join("、")}';

    return imageToImage(
      imagePath: imagePath,
      prompt: prompt,
      model: model,
      parameters: parameters,
    );
  }

  /// 创意变体
  /// 
  /// [imagePath] - 原始图片路径
  /// [variations] - 变化描述
  /// [count] - 生成变体数量
  Future<List<String>> createVariations({
    required String imagePath,
    required String variations,
    int count = 1,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    final params = {...?parameters, 'n': count};

    final result = await service.generateImagesByChat(
      prompt: variations,
      referenceImagePaths: [imagePath],
      model: model,
      parameters: params,
    );

    if (result.isSuccess) {
      return result.data!.imageUrls;
    }
    return [];
  }

  /// 概念混合
  /// 
  /// 将多个概念融合生成新图像
  /// [concepts] - 概念列表（如 ["未来城市", "自然森林", "水下世界"]）
  Future<String?> blendConcepts({
    required List<String> concepts,
    String? additionalPrompt,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    final prompt = '创作一幅融合以下概念的图像: ${concepts.join("、")}' +
        (additionalPrompt != null ? '。$additionalPrompt' : '');

    return textToImage(
      prompt: prompt,
      model: model,
      parameters: parameters,
    );
  }

  /// 场景重构
  /// 
  /// [imagePath] - 参考图片路径
  /// [timeOfDay] - 时间（如 "日出", "正午", "黄昏", "夜晚"）
  /// [weather] - 天气（如 "晴天", "雨天", "雪天", "雾天"）
  Future<String?> reimagineScene({
    required String imagePath,
    String? timeOfDay,
    String? weather,
    String? additionalChanges,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    final changes = <String>[];
    if (timeOfDay != null) changes.add('时间改为$timeOfDay');
    if (weather != null) changes.add('天气改为$weather');
    if (additionalChanges != null) changes.add(additionalChanges);

    final prompt = changes.isEmpty
        ? '重新想象这个场景'
        : '重新想象这个场景: ${changes.join("，")}';

    return imageToImage(
      imagePath: imagePath,
      prompt: prompt,
      model: model,
      parameters: parameters,
    );
  }

  /// 艺术家风格模仿
  /// 
  /// [imagePath] - 原始图片路径（可选）
  /// [prompt] - 内容描述
  /// [artistStyle] - 艺术家风格（如 "梵高", "毕加索", "莫奈" 等）
  Future<String?> artistStyleImitation({
    String? imagePath,
    required String prompt,
    required String artistStyle,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    final fullPrompt = '$prompt，采用${artistStyle}的艺术风格';

    if (imagePath != null) {
      return imageToImage(
        imagePath: imagePath,
        prompt: fullPrompt,
        model: model,
        parameters: parameters,
      );
    } else {
      return textToImage(
        prompt: fullPrompt,
        model: model,
        parameters: parameters,
      );
    }
  }
}
