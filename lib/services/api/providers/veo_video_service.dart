import 'dart:convert';
import 'package:http/http.dart' as http;
import '../base/api_service_base.dart';
import '../base/api_response.dart';

/// Google Veo 视频生成服务
/// 支持文生视频、图生视频和参考图模式
class VeoVideoService extends ApiServiceBase {
  VeoVideoService(super.config);

  @override
  String get providerName => 'Veo Video';

  @override
  Future<ApiResponse<bool>> testConnection() async {
    try {
      // 尝试获取模型列表测试连接
      final result = await getAvailableModels();
      return ApiResponse.success(
        result.isSuccess,
        statusCode: result.statusCode,
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
    // Veo 是视频生成服务，不支持纯文本生成
    return ApiResponse.failure('Veo 服务不支持纯文本生成');
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
    // Veo 是视频生成服务，不支持图片生成
    return ApiResponse.failure('Veo 服务不支持图片生成，请使用 generateVideos');
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
      final targetModel = model ?? config.model ?? VeoModel.standard;
      final size = ratio ?? '720x1280';
      final seconds = parameters?['seconds'] as int? ?? 8;
      final referenceImagePaths = parameters?['referenceImagePaths'] as List<String>?;
      final characterUrl = parameters?['character_url'] as String?;
      final characterTimestamps = parameters?['character_timestamps'] as String?;
      final enableUpsample = parameters?['enable_upsample'] as bool?;
      
      // Kling 模型特有参数
      final firstFrameImageUrl = parameters?['first_frame_image'] as String?;
      final lastFrameImageUrl = parameters?['last_frame_image'] as String?;
      final videoUrl = parameters?['video'] as String?;
      
      // Grok 模型特有参数
      final aspectRatio = parameters?['aspect_ratio'] as String?;
      final grokSize = parameters?['grok_size'] as String?;

      // ⚠️ 关键：必须使用 multipart/form-data 格式，即使没有文件
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${config.baseUrl}/v1/videos'),
      );

      // 添加请求头（不要手动设置 Content-Type，让 http 库自动处理）
      request.headers['Authorization'] = 'Bearer ${config.apiKey}';

      // 添加文本参数
      request.fields['model'] = targetModel;
      request.fields['prompt'] = prompt;
      
      // Grok 模型使用 aspect_ratio 而不是 size
      if (aspectRatio != null) {
        request.fields['aspect_ratio'] = aspectRatio;
      } else {
        request.fields['size'] = size;  // 其他模型使用 size
      }
      
      // Grok 模型的分辨率参数（720P/1080P）
      if (grokSize != null) {
        request.fields['size'] = grokSize;
      }
      
      request.fields['seconds'] = seconds.toString();

      // Sora 角色引用参数
      if (characterUrl != null) {
        request.fields['character_url'] = characterUrl;
      }
      if (characterTimestamps != null) {
        request.fields['character_timestamps'] = characterTimestamps;
      }

      // VEO 高清参数（只有横屏才能启用）
      if (enableUpsample != null) {
        request.fields['enable_upsample'] = enableUpsample.toString();
      }

      // Kling 首尾帧图片 URL（注意：是 URL 字符串，不是文件）
      if (firstFrameImageUrl != null) {
        request.fields['first_frame_image'] = firstFrameImageUrl;
      }
      if (lastFrameImageUrl != null) {
        request.fields['last_frame_image'] = lastFrameImageUrl;
      }

      // Kling 视频编辑参数（提供视频 URL 进行编辑）
      if (videoUrl != null) {
        request.fields['video'] = videoUrl;
      }

      // 添加参考图片文件（如果有）
      if (referenceImagePaths != null && referenceImagePaths.isNotEmpty) {
        for (final imagePath in referenceImagePaths) {
          request.files.add(
            await http.MultipartFile.fromPath(
              'input_reference',  // Veo/Sora/Kling 使用的字段名
              imagePath,
            ),
          );
        }
      }

      // 发送请求
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

  @override
  Future<ApiResponse<UploadResponse>> uploadAsset({
    required String filePath,
    String? assetType,
    Map<String, dynamic>? metadata,
  }) async {
    // Veo 使用 inline_data 方式
    return ApiResponse.failure('Veo 服务使用 inline_data 方式，无需单独上传');
  }

  @override
  Future<ApiResponse<List<String>>> getAvailableModels({
    String? modelType,
  }) async {
    // 返回所有 Veo 模型
    return ApiResponse.success(VeoModel.allModels, statusCode: 200);
  }

  /// 查询视频任务状态
  /// 
  /// 参数：
  /// - taskId: 任务 ID
  Future<ApiResponse<VeoTaskStatus>> getVideoTaskStatus({
    required String taskId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('${config.baseUrl}/v1/videos/$taskId'),
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

  /// 视频 Remix
  /// 
  /// 基于现有视频进行重制/混音，生成新的视频变体
  /// 
  /// 参数：
  /// - videoId: 原始视频的任务 ID
  /// - prompt: 描述如何修改视频的提示词
  /// - seconds: 新视频的时长（秒）
  /// 
  /// 返回：
  /// - 成功时返回新的任务 ID，需要使用 getVideoTaskStatus 轮询状态
  /// 
  /// 示例：
  /// ```dart
  /// final result = await service.remixVideo(
  ///   videoId: 'video_123',
  ///   prompt: '将视频转换成黑白风格，增加复古滤镜效果',
  ///   seconds: 8,
  /// );
  /// 
  /// if (result.isSuccess) {
  ///   final newTaskId = result.data!.id;
  ///   // 轮询新任务的状态
  /// }
  /// ```
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
        Uri.parse('${config.baseUrl}/v1/videos/$videoId/remix'),
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
  /// 
  /// 从视频中提取角色，用于后续视频生成时引用
  /// 
  /// ⚠️ 注意：这是 Sora 专属功能，VEO 不支持
  /// 
  /// 参数：
  /// - timestamps: 时间范围（秒），格式："起始,结束"，如 "1,3"
  ///   - 范围差值最大 3 秒，最小 1 秒
  /// - url: 视频地址（可选，与 fromTask 二选一）
  /// - fromTask: 已完成的任务 ID（可选，与 url 二选一）
  /// 
  /// 返回：
  /// - 成功时返回角色信息（SoraCharacter）
  /// 
  /// 示例：
  /// ```dart
  /// // 方法1：从视频 URL 创建角色
  /// final result = await service.createCharacter(
  ///   timestamps: '1,3',
  ///   url: 'https://example.com/video.mp4',
  /// );
  /// 
  /// // 方法2：从已完成的任务创建角色
  /// final result = await service.createCharacter(
  ///   timestamps: '1,3',
  ///   fromTask: 'video_123',
  /// );
  /// 
  /// if (result.isSuccess) {
  ///   final character = result.data!;
  ///   print('角色ID: ${character.id}');
  ///   print('角色名称: @${character.username}');
  ///   // 在后续生成中使用：prompt: '让 @${character.username} 跳舞'
  /// }
  /// ```
  Future<ApiResponse<SoraCharacter>> createCharacter({
    required String timestamps,
    String? url,
    String? fromTask,
  }) async {
    try {
      // 验证参数
      if (url == null && fromTask == null) {
        return ApiResponse.failure('必须提供 url 或 fromTask 参数之一');
      }
      if (url != null && fromTask != null) {
        return ApiResponse.failure('url 和 fromTask 参数只能提供其中一个');
      }

      final requestBody = <String, dynamic>{
        'timestamps': timestamps,
      };

      if (url != null) {
        requestBody['url'] = url;
      }
      if (fromTask != null) {
        requestBody['from_task'] = fromTask;
      }

      final response = await http.post(
        Uri.parse('${config.baseUrl}/sora/v1/characters'),
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

  // ==================== 私有方法 ====================

  /// 构建请求头
  /// 解析视频生成响应
  /// 
  /// 注意：Veo/Sora API 返回的是任务信息，而非视频文件
  /// 需要使用返回的任务 ID 轮询查询状态
  ApiResponse<List<VideoResponse>> _parseVideoResponse(String responseBody) {
    try {
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      
      // 检查是否为任务响应格式 (Sora/新版 Veo)
      if (data.containsKey('id') && data.containsKey('status')) {
        final taskId = data['id'] as String;
        final status = data['status'] as String;
        
        // 返回任务信息
        return ApiResponse.success([
          VideoResponse(
            videoUrl: '',  // 任务模式下暂无 URL
            videoId: taskId,
            duration: null,
            metadata: {
              'taskId': taskId,
              'status': status,
              'progress': data['progress'],
              'model': data['model'],
              'size': data['size'],
              'created_at': data['created_at'],
              'isTask': true,  // 标记这是任务响应
            },
          ),
        ], statusCode: 200);
      }
      
      // 兼容旧版直接返回视频的格式
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        return ApiResponse.failure('未返回生成结果');
      }

      final videos = <VideoResponse>[];
      
      for (final candidate in candidates) {
        final content = candidate['content'] as Map<String, dynamic>?;
        if (content == null) continue;
        
        final parts = content['parts'] as List?;
        if (parts == null) continue;
        
        for (final part in parts) {
          final inlineData = part['inline_data'] as Map<String, dynamic>?;
          if (inlineData != null) {
            final videoData = inlineData['data'] as String?;
            final mimeType = inlineData['mime_type'] as String?;
            
            if (videoData != null) {
              videos.add(VideoResponse(
                videoUrl: 'data:$mimeType;base64,$videoData',
                videoId: data['responseId'] as String?,
                duration: null,
                metadata: {
                  'mimeType': mimeType,
                  'modelVersion': data['modelVersion'],
                  'createTime': data['createTime'],
                  'usageMetadata': data['usageMetadata'],
                  'isTask': false,
                },
              ));
            }
          }
        }
      }

      if (videos.isEmpty) {
        return ApiResponse.failure('响应中未包含视频数据');
      }

      return ApiResponse.success(videos, statusCode: 200);
    } catch (e) {
      return ApiResponse.failure('解析响应失败: $e');
    }
  }
}

/// Veo 视频生成辅助类
class VeoVideoHelper {
  final VeoVideoService service;

  VeoVideoHelper(this.service);

  /// 文生视频
  /// 
  /// 参数：
  /// - prompt: 视频描述
  /// - size: 视频尺寸（如 '720x1280'）
  /// - seconds: 时长（秒）
  /// - quality: 质量（standard/4K）
  /// - useFast: 是否使用快速模式
  /// - enableUpsample: 是否启用高清模式（仅横屏 1280x720 支持）
  Future<ApiResponse<List<VideoResponse>>> textToVideo({
    required String prompt,
    String size = '720x1280',
    int seconds = 8,
    String quality = VeoQuality.standard,
    bool useFast = false,
    bool? enableUpsample,
  }) async {
    final model = _selectModel(
      quality: quality,
      useFast: useFast,
      useComponents: false,
    );

    final params = <String, dynamic>{'seconds': seconds};
    if (enableUpsample != null) {
      params['enable_upsample'] = enableUpsample;
    }

    return service.generateVideos(
      prompt: prompt,
      model: model,
      ratio: size,
      parameters: params,
    );
  }

  /// 图生视频（首帧模式）
  /// 
  /// 使用 1 张图作为首帧
  /// 
  /// 参数：
  /// - prompt: 视频描述
  /// - firstFramePath: 首帧图片路径
  /// - size: 视频尺寸
  /// - seconds: 时长
  /// - enableUpsample: 是否启用高清模式（仅横屏 1280x720 支持）
  Future<ApiResponse<List<VideoResponse>>> imageToVideoFirstFrame({
    required String prompt,
    required String firstFramePath,
    String size = '720x1280',
    int seconds = 8,
    String quality = VeoQuality.standard,
    bool useFast = false,
    bool? enableUpsample,
  }) async {
    final model = _selectModel(
      quality: quality,
      useFast: useFast,
      useComponents: false,
    );

    final params = <String, dynamic>{
      'seconds': seconds,
      'referenceImagePaths': [firstFramePath],
    };
    if (enableUpsample != null) {
      params['enable_upsample'] = enableUpsample;
    }

    return service.generateVideos(
      prompt: prompt,
      model: model,
      ratio: size,
      parameters: params,
    );
  }

  /// 图生视频（首尾帧模式）
  /// 
  /// 使用 2 张图作为首帧和尾帧
  /// 
  /// 参数：
  /// - prompt: 视频描述
  /// - firstFramePath: 首帧图片路径
  /// - lastFramePath: 尾帧图片路径
  /// - enableUpsample: 是否启用高清模式（仅横屏 1280x720 支持）
  Future<ApiResponse<List<VideoResponse>>> imageToVideoFrames({
    required String prompt,
    required String firstFramePath,
    required String lastFramePath,
    String size = '720x1280',
    int seconds = 8,
    String quality = VeoQuality.standard,
    bool useFast = false,
    bool? enableUpsample,
  }) async {
    final model = _selectModel(
      quality: quality,
      useFast: useFast,
      useComponents: false,
    );

    final params = <String, dynamic>{
      'seconds': seconds,
      'referenceImagePaths': [firstFramePath, lastFramePath],
    };
    if (enableUpsample != null) {
      params['enable_upsample'] = enableUpsample;
    }

    return service.generateVideos(
      prompt: prompt,
      model: model,
      ratio: size,
      parameters: params,
    );
  }

  /// 图生视频（参考图模式）
  /// 
  /// 使用 3 张图作为参考，或使用 components 模型
  /// 
  /// 参数：
  /// - prompt: 视频描述
  /// - referenceImagePaths: 参考图片路径列表
  /// - enableUpsample: 是否启用高清模式（仅横屏 1280x720 支持）
  Future<ApiResponse<List<VideoResponse>>> imageToVideoReference({
    required String prompt,
    required List<String> referenceImagePaths,
    String size = '720x1280',
    int seconds = 8,
    String quality = VeoQuality.standard,
    bool useFast = false,
    bool? enableUpsample,
  }) async {
    // 使用 components 模型（强制参考图模式）
    final model = _selectModel(
      quality: quality,
      useFast: useFast,
      useComponents: true,
    );

    final params = <String, dynamic>{
      'seconds': seconds,
      'referenceImagePaths': referenceImagePaths,
    };
    if (enableUpsample != null) {
      params['enable_upsample'] = enableUpsample;
    }

    return service.generateVideos(
      prompt: prompt,
      model: model,
      ratio: size,
      parameters: params,
    );
  }

  /// Sora 角色引用生成视频
  /// 
  /// 通过提供角色视频 URL 来引用角色：
  /// 1. 先上传包含角色的视频（不能是真人）
  /// 2. 指定角色出现的时间范围（1-3秒）
  /// 3. 生成新视频时会保持角色一致性
  /// 
  /// 示例：
  /// ```dart
  /// final result = await helper.soraWithCharacterReference(
  ///   prompt: '猫咪带着耳机听着歌走路，摇晃脑袋，大雨落下',
  ///   characterUrl: 'https://xxx.com/character_video.mp4',
  ///   characterTimestamps: '1,3',  // 角色在第1-3秒出现
  ///   size: '720x1280',
  ///   seconds: 10,
  /// );
  /// ```
  /// 
  /// 参数：
  /// - prompt: 视频描述
  /// - characterUrl: 角色视频链接（必须不含真人）
  /// - characterTimestamps: 角色出现的时间范围，格式："起始秒,结束秒"（范围1-3秒）
  /// - size: 视频尺寸（720x1280 或 1280x720）
  /// - seconds: 时长（10 或 15 秒）
  /// - useTurbo: 是否使用 Turbo 快速模式
  Future<ApiResponse<List<VideoResponse>>> soraWithCharacterReference({
    required String prompt,
    required String characterUrl,
    required String characterTimestamps,
    String size = '720x1280',
    int seconds = 10,
    bool useTurbo = false,
  }) async {
    return service.generateVideos(
      prompt: prompt,
      model: useTurbo ? VeoModel.soraTurbo : VeoModel.sora2,
      ratio: size,
      parameters: {
        'seconds': seconds,
        'character_url': characterUrl,
        'character_timestamps': characterTimestamps,
      },
    );
  }

  /// 轮询任务直到完成
  /// 
  /// 参数：
  /// - taskId: 任务 ID
  /// - maxWaitMinutes: 最大等待时间（分钟）
  /// - onProgress: 进度回调（可选）
  Future<ApiResponse<VeoTaskStatus>> pollTaskUntilComplete({
    required String taskId,
    int maxWaitMinutes = 10,
    Function(int progress, String status)? onProgress,
  }) async {
    final maxAttempts = (maxWaitMinutes * 60 / 5).ceil();
    
    for (int i = 0; i < maxAttempts; i++) {
      final result = await service.getVideoTaskStatus(taskId: taskId);
      
      if (!result.isSuccess) {
        // 404 可能是数据同步延迟，继续等待
        if (result.statusCode == 404 && i < 3) {
          await Future.delayed(Duration(seconds: 5));
          continue;
        }
        return result;
      }

      final status = result.data!;
      
      // 调用进度回调
      if (onProgress != null) {
        onProgress(status.progress, status.status);
      }
      
      if (status.isCompleted) {
        return ApiResponse.success(status);
      } else if (status.isFailed) {
        return ApiResponse.failure(
          status.errorMessage ?? '任务失败',
        );
      } else if (status.isCancelled) {
        return ApiResponse.failure('任务已取消');
      }

      // 继续等待
      await Future.delayed(Duration(seconds: 5));
    }

    return ApiResponse.failure('任务超时：已等待 $maxWaitMinutes 分钟');
  }

  /// 选择合适的模型
  String _selectModel({
    required String quality,
    required bool useFast,
    required bool useComponents,
  }) {
    if (useComponents) {
      // Components 模式
      if (useFast) {
        return quality == VeoQuality.standard
            ? VeoModel.fastComponents
            : VeoModel.fastComponents4K;
      } else {
        return quality == VeoQuality.standard
            ? VeoModel.components
            : VeoModel.components4K;
      }
    } else {
      // 标准模式
      if (useFast) {
        return quality == VeoQuality.standard
            ? VeoModel.fast
            : VeoModel.fast4K;
      } else {
        return quality == VeoQuality.standard
            ? VeoModel.standard
            : VeoModel.standard4K;
      }
    }
  }

  /// 生成高清横屏视频（文生视频）
  /// 
  /// ⚠️ 注意：高清模式（enable_upsample）仅支持横屏（1280x720）
  /// 
  /// 参数：
  /// - prompt: 视频描述
  /// - seconds: 时长（秒），默认 8 秒
  /// - useFast: 是否使用快速模式
  Future<ApiResponse<List<VideoResponse>>> textToVideoHD({
    required String prompt,
    int seconds = 8,
    bool useFast = false,
  }) async {
    return textToVideo(
      prompt: prompt,
      size: '1280x720', // 强制横屏
      seconds: seconds,
      quality: VeoQuality.standard,
      useFast: useFast,
      enableUpsample: true,
    );
  }

  /// 生成高清横屏视频（图生视频-首帧模式）
  /// 
  /// ⚠️ 注意：高清模式（enable_upsample）仅支持横屏（1280x720）
  /// 
  /// 参数：
  /// - prompt: 视频描述
  /// - firstFramePath: 首帧图片路径
  /// - seconds: 时长（秒），默认 8 秒
  /// - useFast: 是否使用快速模式
  Future<ApiResponse<List<VideoResponse>>> imageToVideoHD({
    required String prompt,
    required String firstFramePath,
    int seconds = 8,
    bool useFast = false,
  }) async {
    return imageToVideoFirstFrame(
      prompt: prompt,
      firstFramePath: firstFramePath,
      size: '1280x720', // 强制横屏
      seconds: seconds,
      quality: VeoQuality.standard,
      useFast: useFast,
      enableUpsample: true,
    );
  }

  /// 生成高清横屏视频（图生视频-首尾帧模式）
  /// 
  /// ⚠️ 注意：高清模式（enable_upsample）仅支持横屏（1280x720）
  /// 
  /// 参数：
  /// - prompt: 视频描述
  /// - firstFramePath: 首帧图片路径
  /// - lastFramePath: 尾帧图片路径
  /// - seconds: 时长（秒），默认 8 秒
  /// - useFast: 是否使用快速模式
  Future<ApiResponse<List<VideoResponse>>> imageToVideoFramesHD({
    required String prompt,
    required String firstFramePath,
    required String lastFramePath,
    int seconds = 8,
    bool useFast = false,
  }) async {
    return imageToVideoFrames(
      prompt: prompt,
      firstFramePath: firstFramePath,
      lastFramePath: lastFramePath,
      size: '1280x720', // 强制横屏
      seconds: seconds,
      quality: VeoQuality.standard,
      useFast: useFast,
      enableUpsample: true,
    );
  }

  /// 视频 Remix（重制/混音）
  /// 
  /// 基于现有视频进行重制，生成新的视频变体
  /// 
  /// 使用场景：
  /// - 风格转换：将视频转换成不同的艺术风格
  /// - 效果增强：添加滤镜、特效等
  /// - 内容修改：调整视频的色调、光线、氛围等
  /// 
  /// 参数：
  /// - videoId: 原始视频的任务 ID（已完成的视频任务）
  /// - prompt: 描述如何修改视频的提示词
  /// - seconds: 新视频的时长（秒），默认 8 秒
  /// - maxWaitMinutes: 最大等待时间（分钟），默认 10 分钟
  /// - onProgress: 进度回调（可选）
  /// 
  /// 返回：
  /// - 成功时返回新视频的任务状态
  /// 
  /// 示例：
  /// ```dart
  /// // 1. 风格转换
  /// final result = await helper.remixVideo(
  ///   videoId: 'video_123',
  ///   prompt: '将视频转换成黑白电影风格，增加颗粒感和复古滤镜',
  ///   seconds: 8,
  /// );
  /// 
  /// // 2. 效果增强
  /// final result = await helper.remixVideo(
  ///   videoId: 'video_456',
  ///   prompt: '增强色彩饱和度，添加动态模糊效果，强化光线对比',
  ///   seconds: 8,
  /// );
  /// 
  /// // 3. 氛围调整
  /// final result = await helper.remixVideo(
  ///   videoId: 'video_789',
  ///   prompt: '改变为夜晚场景，添加月光效果，增加神秘氛围',
  ///   seconds: 8,
  ///   onProgress: (progress, status) {
  ///     print('Remix 进度: $progress%');
  ///   },
  /// );
  /// 
  /// if (result.isSuccess && result.data!.hasVideo) {
  ///   print('Remix 完成: ${result.data!.videoUrl}');
  ///   print('原视频ID: ${result.data!.remixedFromVideoId}');
  /// }
  /// ```
  Future<ApiResponse<VeoTaskStatus>> remixVideo({
    required String videoId,
    required String prompt,
    int seconds = 8,
    int maxWaitMinutes = 10,
    Function(int progress, String status)? onProgress,
  }) async {
    // 1. 提交 remix 任务
    final submitResult = await service.remixVideo(
      videoId: videoId,
      prompt: prompt,
      seconds: seconds,
    );

    if (!submitResult.isSuccess) {
      return submitResult;
    }

    final newTaskId = submitResult.data!.id;

    // 2. 轮询任务状态直到完成
    return await pollTaskUntilComplete(
      taskId: newTaskId,
      maxWaitMinutes: maxWaitMinutes,
      onProgress: onProgress,
    );
  }

  /// 批量 Remix 多个视频
  /// 
  /// 使用相同的提示词对多个视频进行 remix
  /// 
  /// 参数：
  /// - videoIds: 要 remix 的视频 ID 列表
  /// - prompt: 统一的提示词
  /// - seconds: 新视频的时长
  /// - maxWaitMinutes: 每个任务的最大等待时间
  /// 
  /// 返回：
  /// - Map<原视频ID, 新视频任务状态>
  Future<Map<String, VeoTaskStatus?>> remixMultipleVideos({
    required List<String> videoIds,
    required String prompt,
    int seconds = 8,
    int maxWaitMinutes = 10,
  }) async {
    final results = <String, VeoTaskStatus?>{};

    for (final videoId in videoIds) {
      print('正在 Remix 视频: $videoId');
      
      final result = await remixVideo(
        videoId: videoId,
        prompt: prompt,
        seconds: seconds,
        maxWaitMinutes: maxWaitMinutes,
        onProgress: (progress, status) {
          print('  [$videoId] 进度: $progress% - $status');
        },
      );

      if (result.isSuccess) {
        results[videoId] = result.data;
        print('  ✓ 完成: ${result.data!.videoUrl}');
      } else {
        results[videoId] = null;
        print('  ✗ 失败: ${result.errorMessage}');
      }
    }

    return results;
  }

  /// 创建视频变体系列
  /// 
  /// 基于同一个原视频，使用不同的提示词生成多个变体
  /// 
  /// 参数：
  /// - videoId: 原始视频 ID
  /// - prompts: 不同的提示词列表
  /// - seconds: 新视频的时长
  /// 
  /// 返回：
  /// - List<VeoTaskStatus?> 按 prompts 顺序返回结果
  Future<List<VeoTaskStatus?>> createVideoVariations({
    required String videoId,
    required List<String> prompts,
    int seconds = 8,
    int maxWaitMinutes = 10,
  }) async {
    final results = <VeoTaskStatus?>[];

    for (var i = 0; i < prompts.length; i++) {
      final prompt = prompts[i];
      print('创建变体 ${i + 1}/${prompts.length}: $prompt');
      
      final result = await remixVideo(
        videoId: videoId,
        prompt: prompt,
        seconds: seconds,
        maxWaitMinutes: maxWaitMinutes,
        onProgress: (progress, status) {
          print('  进度: $progress%');
        },
      );

      if (result.isSuccess) {
        results.add(result.data);
        print('  ✓ 完成');
      } else {
        results.add(null);
        print('  ✗ 失败: ${result.errorMessage}');
      }
    }

    return results;
  }

  /// Sora 创建角色（从视频 URL）
  /// 
  /// ⚠️ 注意：这是 Sora 专属功能
  /// 
  /// 参数：
  /// - videoUrl: 视频地址，视频中包含需要创建的角色
  /// - timestamps: 时间范围（秒），格式："起始,结束"，如 "1,3"
  ///   - 范围差值最大 3 秒，最小 1 秒
  ///   - 例如："1,3" 表示视频的 1-3 秒中出现的角色
  /// 
  /// 返回：
  /// - 成功时返回角色信息
  /// 
  /// 示例：
  /// ```dart
  /// final character = await helper.createCharacterFromUrl(
  ///   videoUrl: 'https://example.com/cat-video.mp4',
  ///   timestamps: '1,3',
  /// );
  /// 
  /// if (character.isSuccess) {
  ///   print('角色创建成功: @${character.data!.username}');
  ///   print('头像: ${character.data!.profilePictureUrl}');
  ///   
  ///   // 在后续生成中使用
  ///   final videoResult = await helper.soraWithCharacterReference(
  ///     prompt: '让 ${character.data!.mentionTag} 跳舞',
  ///     characterUrl: videoUrl,
  ///     characterTimestamps: timestamps,
  ///   );
  /// }
  /// ```
  Future<ApiResponse<SoraCharacter>> createCharacterFromUrl({
    required String videoUrl,
    required String timestamps,
  }) async {
    return service.createCharacter(
      timestamps: timestamps,
      url: videoUrl,
    );
  }

  /// Sora 创建角色（从已完成的任务）
  /// 
  /// ⚠️ 注意：这是 Sora 专属功能
  /// 
  /// 参数：
  /// - taskId: 已完成的视频任务 ID
  /// - timestamps: 时间范围（秒），格式："起始,结束"
  /// 
  /// 返回：
  /// - 成功时返回角色信息
  /// 
  /// 示例：
  /// ```dart
  /// // 1. 先生成包含角色的视频
  /// final videoResult = await helper.textToVideo(
  ///   prompt: '一只橙色的猫咪，特写镜头',
  ///   model: VeoModel.sora2,
  ///   size: '720x1280',
  ///   seconds: 10,
  /// );
  /// 
  /// // 2. 等待视频完成
  /// final taskStatus = await helper.pollTaskUntilComplete(
  ///   taskId: videoResult.data!.first.videoId!,
  /// );
  /// 
  /// // 3. 从已完成的任务创建角色
  /// final character = await helper.createCharacterFromTask(
  ///   taskId: taskStatus.data!.id,
  ///   timestamps: '1,3',
  /// );
  /// 
  /// if (character.isSuccess) {
  ///   print('角色: ${character.data!.mentionTag}');
  ///   
  ///   // 4. 使用角色生成新视频
  ///   final newVideo = await helper.textToVideo(
  ///     prompt: '让 ${character.data!.mentionTag} 在草地上奔跑',
  ///     model: VeoModel.sora2,
  ///   );
  /// }
  /// ```
  Future<ApiResponse<SoraCharacter>> createCharacterFromTask({
    required String taskId,
    required String timestamps,
  }) async {
    return service.createCharacter(
      timestamps: timestamps,
      fromTask: taskId,
    );
  }

  /// 完整的 Sora 角色工作流程
  /// 
  /// 一站式创建角色并生成角色引用视频
  /// 
  /// 参数：
  /// - initialPrompt: 初始视频提示词（用于创建包含角色的视频）
  /// - characterTimestamps: 角色出现的时间范围
  /// - characterPrompt: 使用角色的新视频提示词
  /// - seconds: 视频时长
  /// 
  /// 返回：
  /// - 包含角色信息和新视频状态的 Map
  /// 
  /// 示例：
  /// ```dart
  /// final result = await helper.soraCharacterWorkflow(
  ///   initialPrompt: '一只可爱的橙色小猫，特写镜头，高清',
  ///   characterTimestamps: '1,3',
  ///   characterPrompt: '在花园里玩耍，追逐蝴蝶',
  ///   seconds: 10,
  /// );
  /// 
  /// if (result['character'] != null) {
  ///   final character = result['character'] as SoraCharacter;
  ///   print('角色: ${character.mentionTag}');
  ///   
  ///   if (result['video'] != null) {
  ///     final video = result['video'] as VeoTaskStatus;
  ///     print('视频: ${video.videoUrl}');
  ///   }
  /// }
  /// ```
  Future<Map<String, dynamic>> soraCharacterWorkflow({
    required String initialPrompt,
    required String characterTimestamps,
    required String characterPrompt,
    int seconds = 10,
  }) async {
    final result = <String, dynamic>{
      'character': null,
      'video': null,
      'error': null,
    };

    try {
      // 1. 生成初始视频（包含角色）
      print('步骤1: 生成初始视频...');
      final initialVideo = await service.generateVideos(
        prompt: initialPrompt,
        model: VeoModel.sora2,
        ratio: '720x1280',
        parameters: {'seconds': seconds},
      );

      if (!initialVideo.isSuccess) {
        result['error'] = '初始视频生成失败: ${initialVideo.errorMessage}';
        return result;
      }

      final taskId = initialVideo.data!.first.videoId!;

      // 2. 等待初始视频完成
      print('步骤2: 等待视频完成...');
      final videoStatus = await pollTaskUntilComplete(
        taskId: taskId,
        onProgress: (progress, status) {
          print('  初始视频进度: $progress%');
        },
      );

      if (!videoStatus.isSuccess || !videoStatus.data!.hasVideo) {
        result['error'] = '初始视频未完成';
        return result;
      }

      print('步骤3: 创建角色...');
      // 3. 从视频创建角色
      final characterResult = await createCharacterFromTask(
        taskId: taskId,
        timestamps: characterTimestamps,
      );

      if (!characterResult.isSuccess) {
        result['error'] = '角色创建失败: ${characterResult.errorMessage}';
        return result;
      }

      final character = characterResult.data!;
      result['character'] = character;
      print('角色创建成功: ${character.mentionTag}');

      // 4. 使用角色生成新视频
      print('步骤4: 使用角色生成新视频...');
      final newVideoPrompt = '$characterPrompt ${character.mentionTag}';
      
      final newVideo = await service.generateVideos(
        prompt: newVideoPrompt,
        model: VeoModel.sora2,
        ratio: '720x1280',
        parameters: {'seconds': seconds},
      );

      if (!newVideo.isSuccess) {
        result['error'] = '新视频生成失败: ${newVideo.errorMessage}';
        return result;
      }

      final newTaskId = newVideo.data!.first.videoId!;

      // 5. 等待新视频完成
      print('步骤5: 等待新视频完成...');
      final newVideoStatus = await pollTaskUntilComplete(
        taskId: newTaskId,
        onProgress: (progress, status) {
          print('  新视频进度: $progress%');
        },
      );

      if (newVideoStatus.isSuccess && newVideoStatus.data!.hasVideo) {
        result['video'] = newVideoStatus.data!;
        print('完成! 视频URL: ${newVideoStatus.data!.videoUrl}');
      }

      return result;
    } catch (e) {
      result['error'] = '工作流程错误: $e';
      return result;
    }
  }

  /// Kling 文生视频
  /// 
  /// 使用快手 Kling 模型生成视频
  /// 
  /// 参数：
  /// - prompt: 视频描述
  /// - size: 视频尺寸（720x1280 或 1280x720）
  /// - seconds: 时长，Kling 支持 5 或 10 秒
  /// 
  /// 示例：
  /// ```dart
  /// final result = await helper.klingTextToVideo(
  ///   prompt: '猫咪听歌摇头晃脑，下大雨',
  ///   size: '720x1280',
  ///   seconds: 10,
  /// );
  /// ```
  Future<ApiResponse<List<VideoResponse>>> klingTextToVideo({
    required String prompt,
    String size = '720x1280',
    int seconds = 10,
  }) async {
    return service.generateVideos(
      prompt: prompt,
      model: VeoModel.klingO1,
      ratio: size,
      parameters: {'seconds': seconds},
    );
  }

  /// Kling 图生视频（首尾帧模式 - URL）
  /// 
  /// ⚠️ 注意：Kling 的首尾帧参数是 URL 字符串，不是文件路径
  /// 
  /// 参数：
  /// - prompt: 视频描述
  /// - firstFrameUrl: 首帧图片 URL
  /// - lastFrameUrl: 尾帧图片 URL（可选）
  /// - size: 视频尺寸
  /// - seconds: 时长（5 或 10 秒）
  /// 
  /// 示例：
  /// ```dart
  /// final result = await helper.klingImageToVideoByUrl(
  ///   prompt: '平滑过渡，镜头推进',
  ///   firstFrameUrl: 'https://example.com/first.jpg',
  ///   lastFrameUrl: 'https://example.com/last.jpg',
  ///   size: '720x1280',
  ///   seconds: 10,
  /// );
  /// ```
  Future<ApiResponse<List<VideoResponse>>> klingImageToVideoByUrl({
    required String prompt,
    required String firstFrameUrl,
    String? lastFrameUrl,
    String size = '720x1280',
    int seconds = 10,
  }) async {
    final params = <String, dynamic>{
      'seconds': seconds,
      'first_frame_image': firstFrameUrl,
    };

    if (lastFrameUrl != null) {
      params['last_frame_image'] = lastFrameUrl;
    }

    return service.generateVideos(
      prompt: prompt,
      model: VeoModel.klingO1,
      ratio: size,
      parameters: params,
    );
  }

  /// Kling 视频编辑
  /// 
  /// 基于现有视频进行编辑
  /// 
  /// 参数：
  /// - prompt: 编辑描述（如何修改视频）
  /// - videoUrl: 要编辑的视频 URL
  /// - size: 输出视频尺寸
  /// - seconds: 时长（5 或 10 秒）
  /// 
  /// 示例：
  /// ```dart
  /// final result = await helper.klingEditVideo(
  ///   prompt: '添加黑白滤镜效果，增加颗粒感',
  ///   videoUrl: 'https://example.com/original-video.mp4',
  ///   size: '720x1280',
  ///   seconds: 10,
  /// );
  /// ```
  Future<ApiResponse<List<VideoResponse>>> klingEditVideo({
    required String prompt,
    required String videoUrl,
    String size = '720x1280',
    int seconds = 10,
  }) async {
    return service.generateVideos(
      prompt: prompt,
      model: VeoModel.klingO1,
      ratio: size,
      parameters: {
        'seconds': seconds,
        'video': videoUrl,
      },
    );
  }

  /// Kling 图生视频（参考图 + 首尾帧）
  /// 
  /// 组合使用参考图文件和首尾帧 URL
  /// 
  /// 参数：
  /// - prompt: 视频描述
  /// - referenceImagePaths: 参考图片文件路径列表
  /// - firstFrameUrl: 首帧图片 URL（可选）
  /// - lastFrameUrl: 尾帧图片 URL（可选）
  /// - size: 视频尺寸
  /// - seconds: 时长
  /// 
  /// 示例：
  /// ```dart
  /// final result = await helper.klingAdvancedGeneration(
  ///   prompt: '融合参考图的风格，从首帧到尾帧平滑过渡',
  ///   referenceImagePaths: ['/path/to/ref1.jpg', '/path/to/ref2.jpg'],
  ///   firstFrameUrl: 'https://example.com/first.jpg',
  ///   lastFrameUrl: 'https://example.com/last.jpg',
  ///   size: '720x1280',
  ///   seconds: 10,
  /// );
  /// ```
  Future<ApiResponse<List<VideoResponse>>> klingAdvancedGeneration({
    required String prompt,
    List<String>? referenceImagePaths,
    String? firstFrameUrl,
    String? lastFrameUrl,
    String size = '720x1280',
    int seconds = 10,
  }) async {
    final params = <String, dynamic>{
      'seconds': seconds,
    };

    if (referenceImagePaths != null && referenceImagePaths.isNotEmpty) {
      params['referenceImagePaths'] = referenceImagePaths;
    }

    if (firstFrameUrl != null) {
      params['first_frame_image'] = firstFrameUrl;
    }

    if (lastFrameUrl != null) {
      params['last_frame_image'] = lastFrameUrl;
    }

    return service.generateVideos(
      prompt: prompt,
      model: VeoModel.klingO1,
      ratio: size,
      parameters: params,
    );
  }

  /// 豆包文生视频
  /// 
  /// 使用字节跳动豆包 Seedance 模型生成视频
  /// 
  /// 参数：
  /// - prompt: 视频描述
  /// - resolution: 分辨率（480p, 720p, 1080p）
  /// - aspectRatio: 宽高比
  ///   - 标准比例：16:9, 4:3, 1:1, 3:4, 9:16, 21:9
  ///   - 智能模式：keep_ratio（保持图片比例）, adaptive（自动选择）
  /// - seconds: 时长（4-11 秒）
  /// 
  /// 示例：
  /// ```dart
  /// final result = await helper.doubaoTextToVideo(
  ///   prompt: '猫咪听歌摇头晃脑，下大雨',
  ///   resolution: DoubaoResolution.p720,  // 720p 高清
  ///   aspectRatio: '16:9',  // 横屏
  ///   seconds: 6,  // 6 秒视频
  /// );
  /// ```
  Future<ApiResponse<List<VideoResponse>>> doubaoTextToVideo({
    required String prompt,
    DoubaoResolution resolution = DoubaoResolution.p720,
    String aspectRatio = '16:9',
    int seconds = 6,
  }) async {
    return service.generateVideos(
      prompt: prompt,
      model: resolution.modelName,
      ratio: aspectRatio,
      parameters: {'seconds': seconds},
    );
  }

  /// 豆包图生视频（首尾帧模式）
  /// 
  /// 使用首尾帧图片生成视频
  /// 
  /// ⚠️ 注意：豆包的首尾帧参数类型待确认（可能是 URL 或文件）
  /// 
  /// 参数：
  /// - prompt: 视频描述
  /// - firstFrameImage: 首帧图片（URL 或文件路径）
  /// - lastFrameImage: 尾帧图片（URL 或文件路径，可选）
  /// - resolution: 分辨率
  /// - aspectRatio: 宽高比（或使用 'keep_ratio', 'adaptive'）
  /// - seconds: 时长（4-11 秒）
  /// 
  /// 示例：
  /// ```dart
  /// // 方式1：使用 URL
  /// final result = await helper.doubaoImageToVideo(
  ///   prompt: '平滑过渡，镜头推进',
  ///   firstFrameImage: 'https://example.com/first.jpg',
  ///   lastFrameImage: 'https://example.com/last.jpg',
  ///   resolution: DoubaoResolution.p1080,
  ///   aspectRatio: 'keep_ratio',  // 保持图片原始比例
  ///   seconds: 8,
  /// );
  /// 
  /// // 方式2：使用文件路径（如果支持）
  /// final result = await helper.doubaoImageToVideo(
  ///   prompt: '动画效果',
  ///   firstFrameImage: '/path/to/first.jpg',
  ///   resolution: DoubaoResolution.p720,
  ///   aspectRatio: 'adaptive',  // 自动选择最佳比例
  ///   seconds: 6,
  /// );
  /// ```
  Future<ApiResponse<List<VideoResponse>>> doubaoImageToVideo({
    required String prompt,
    required String firstFrameImage,
    String? lastFrameImage,
    DoubaoResolution resolution = DoubaoResolution.p720,
    String aspectRatio = 'adaptive',
    int seconds = 6,
  }) async {
    final params = <String, dynamic>{
      'seconds': seconds,
      'first_frame_image': firstFrameImage,
    };

    if (lastFrameImage != null) {
      params['last_frame_image'] = lastFrameImage;
    }

    return service.generateVideos(
      prompt: prompt,
      model: resolution.modelName,
      ratio: aspectRatio,
      parameters: params,
    );
  }

  /// Grok 文生视频
  /// 
  /// 使用 xAI Grok 模型生成视频
  /// 
  /// ⚠️ 注意：Grok 固定 6 秒时长
  /// 
  /// 参数：
  /// - prompt: 视频描述
  /// - aspectRatio: 宽高比（2:3, 3:2, 1:1）
  /// - resolution: 分辨率（720P 或 1080P）
  /// 
  /// 示例：
  /// ```dart
  /// final result = await helper.grokTextToVideo(
  ///   prompt: '猫咪听歌摇头晃脑，下大雨',
  ///   aspectRatio: GrokAspectRatio.ratio2x3,  // 2:3 竖屏
  ///   resolution: GrokResolution.p720,
  /// );
  /// ```
  Future<ApiResponse<List<VideoResponse>>> grokTextToVideo({
    required String prompt,
    String aspectRatio = GrokAspectRatio.ratio2x3,
    String resolution = GrokResolution.p720,
  }) async {
    return service.generateVideos(
      prompt: prompt,
      model: VeoModel.grokVideo3,
      ratio: '',  // Grok 不使用 ratio 参数
      parameters: {
        'seconds': 6,  // Grok 固定 6 秒
        'aspect_ratio': aspectRatio,  // Grok 使用 aspect_ratio
        'grok_size': resolution,      // Grok 的分辨率参数
      },
    );
  }

  /// Grok 图生视频
  /// 
  /// 使用参考图片生成视频
  /// 
  /// 参数：
  /// - prompt: 视频描述
  /// - referenceImagePath: 参考图片路径
  /// - aspectRatio: 宽高比
  /// - resolution: 分辨率
  /// 
  /// 示例：
  /// ```dart
  /// final result = await helper.grokImageToVideo(
  ///   prompt: '基于参考图生成动态视频',
  ///   referenceImagePath: '/path/to/reference.jpg',
  ///   aspectRatio: GrokAspectRatio.ratio1x1,
  ///   resolution: GrokResolution.p1080,
  /// );
  /// ```
  Future<ApiResponse<List<VideoResponse>>> grokImageToVideo({
    required String prompt,
    required String referenceImagePath,
    String aspectRatio = GrokAspectRatio.ratio2x3,
    String resolution = GrokResolution.p720,
  }) async {
    return service.generateVideos(
      prompt: prompt,
      model: VeoModel.grokVideo3,
      ratio: '',
      parameters: {
        'seconds': 6,
        'aspect_ratio': aspectRatio,
        'grok_size': resolution,
        'referenceImagePaths': [referenceImagePath],
      },
    );
  }
}

/// Grok 宽高比常量
class GrokAspectRatio {
  /// 2:3 竖屏
  static const String ratio2x3 = '2:3';
  
  /// 3:2 横屏
  static const String ratio3x2 = '3:2';
  
  /// 1:1 方形
  static const String ratio1x1 = '1:1';
  
  /// 所有支持的宽高比
  static List<String> get allRatios => [ratio2x3, ratio3x2, ratio1x1];
}

/// Grok 分辨率常量
class GrokResolution {
  /// 720P 高清
  static const String p720 = '720P';
  
  /// 1080P 超清
  static const String p1080 = '1080P';
  
  /// 所有支持的分辨率
  static List<String> get allResolutions => [p720, p1080];
}

/// 豆包(Doubao)分辨率选项
enum DoubaoResolution {
  /// 480p 标清版本（快速、低成本）
  p480('doubao-seedance-1-5-pro_480p'),
  
  /// 720p 高清版本（推荐）
  p720('doubao-seedance-1-5-pro_720p'),
  
  /// 1080p 超清版本（最高质量）
  p1080('doubao-seedance-1-5-pro_1080p');

  final String modelName;
  const DoubaoResolution(this.modelName);
}

/// 豆包宽高比常量
class DoubaoAspectRatio {
  /// 标准宽高比
  static const String ratio16x9 = '16:9';    // 宽屏
  static const String ratio4x3 = '4:3';      // 传统
  static const String ratio1x1 = '1:1';      // 方形
  static const String ratio3x4 = '3:4';      // 竖屏传统
  static const String ratio9x16 = '9:16';    // 竖屏
  static const String ratio21x9 = '21:9';    // 超宽屏
  
  /// 智能模式
  static const String keepRatio = 'keep_ratio';      // 保持上传图片比例
  static const String adaptive = 'adaptive';          // 自动选择最佳比例
  
  /// 所有标准比例
  static List<String> get standardRatios => [
    ratio16x9,
    ratio4x3,
    ratio1x1,
    ratio3x4,
    ratio9x16,
    ratio21x9,
  ];
  
  /// 所有比例（包括智能模式）
  static List<String> get allRatios => [
    ...standardRatios,
    keepRatio,
    adaptive,
  ];
}

/// Veo/Sora 模型常量
class VeoModel {
  // ==================== Veo 模型 ====================
  
  // 高质量版本
  static const String standard = 'veo_3_1';
  static const String standard4K = 'veo_3_1-4K';

  // 快速版本
  static const String fast = 'veo_3_1-fast';
  static const String fast4K = 'veo_3_1-fast-4K';

  // 参考图版本
  static const String components = 'veo_3_1-components';
  static const String components4K = 'veo_3_1-components-4K';
  static const String fastComponents = 'veo_3_1-fast-components';
  static const String fastComponents4K = 'veo_3_1-fast-components-4K';

  // ==================== Sora 模型 ====================
  
  /// Sora 2.0 - 支持角色引用、场景延续
  static const String sora2 = 'sora-2';
  
  /// Sora 1.0 (Turbo) - 快速版本
  static const String soraTurbo = 'sora-turbo';

  // ==================== Kling 模型 ====================
  
  /// Kling Video O1 - 快手 Kling 视频生成模型
  static const String klingO1 = 'kling-video-o1';

  // ==================== 豆包(Doubao)模型 ====================
  
  /// Doubao Seedance 1.5 Pro - 480p 标清版本
  static const String doubao480p = 'doubao-seedance-1-5-pro_480p';
  
  /// Doubao Seedance 1.5 Pro - 720p 高清版本（推荐）
  static const String doubao720p = 'doubao-seedance-1-5-pro_720p';
  
  /// Doubao Seedance 1.5 Pro - 1080p 超清版本
  static const String doubao1080p = 'doubao-seedance-1-5-pro_1080p';

  // ==================== Grok 模型 (xAI) ====================
  
  /// Grok Video 3 - xAI/X 视频生成模型
  static const String grokVideo3 = 'grok-video-3';

  // ==================== 模型列表 ====================
  
  /// 获取所有 Veo 模型
  static List<String> get veoModels => [
    standard,
    standard4K,
    fast,
    fast4K,
    components,
    components4K,
    fastComponents,
    fastComponents4K,
  ];

  /// 获取所有 Sora 模型
  static List<String> get soraModels => [
    sora2,
    soraTurbo,
  ];

  /// 获取所有 Kling 模型
  static List<String> get klingModels => [
    klingO1,
  ];

  /// 获取所有豆包模型
  static List<String> get doubaoModels => [
    doubao480p,
    doubao720p,
    doubao1080p,
  ];

  /// 获取所有 Grok 模型
  static List<String> get grokModels => [
    grokVideo3,
  ];

  /// 获取所有模型列表
  static List<String> get allModels => [
    ...veoModels,
    ...soraModels,
    ...klingModels,
    ...doubaoModels,
    ...grokModels,
  ];
}

/// Veo 视频质量常量
class VeoQuality {
  /// 标准质量
  static const String standard = 'standard';
  
  /// 4K 高清
  static const String fourK = '4K';
}

/// Veo/Sora 任务状态
class VeoTaskStatus {
  final String id;            // 任务 ID
  final String? object;       // 对象类型（通常是 "video"）
  final String status;        // queued, processing, completed, failed, cancelled
  final int progress;         // 进度 0-100
  final String? videoUrl;     // 视频 URL（完成时）
  final String? model;        // 使用的模型
  final String? size;         // 视频尺寸
  final String? seconds;      // 视频时长（字符串格式）
  final int? createdAt;       // 创建时间戳
  final int? completedAt;     // 完成时间戳
  final int? expiresAt;       // 过期时间戳
  final String? remixedFromVideoId;  // 如果是基于其他视频混音的
  final VeoTaskError? error;  // 错误信息
  final Map<String, dynamic> metadata;

  VeoTaskStatus({
    required this.id,
    this.object,
    required this.status,
    required this.progress,
    this.videoUrl,
    this.model,
    this.size,
    this.seconds,
    this.createdAt,
    this.completedAt,
    this.expiresAt,
    this.remixedFromVideoId,
    this.error,
    required this.metadata,
  });

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isCancelled => status == 'cancelled';
  bool get isFinished => isCompleted || isFailed || isCancelled;
  bool get isProcessing => status == 'processing' || status == 'queued';

  /// 视频是否可用（完成且有 URL）
  bool get hasVideo => isCompleted && videoUrl != null && videoUrl!.isNotEmpty;

  /// 获取错误消息
  String? get errorMessage => error?.message ?? 
      metadata['fail_reason'] as String? ?? 
      metadata['failReason'] as String?;

  factory VeoTaskStatus.fromJson(Map<String, dynamic> json) {
    // 兼容多种可能的字段名
    final url = json['video_url'] as String? ??
        json['url'] as String? ??
        json['output'] as String? ??
        (json['data'] as Map<String, dynamic>?)?['url'] as String?;

    // 解析错误信息
    VeoTaskError? taskError;
    if (json['error'] != null) {
      taskError = VeoTaskError.fromJson(json['error'] as Map<String, dynamic>);
    }

    return VeoTaskStatus(
      id: json['id'] as String? ?? '',
      object: json['object'] as String?,
      status: json['status'] as String,
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      videoUrl: url,
      model: json['model'] as String?,
      size: json['size'] as String?,
      seconds: json['seconds'] as String?,
      createdAt: json['created_at'] as int?,
      completedAt: json['completed_at'] as int?,
      expiresAt: json['expires_at'] as int?,
      remixedFromVideoId: json['remixed_from_video_id'] as String?,
      error: taskError,
      metadata: json,
    );
  }
}

/// Veo/Sora 任务错误信息
class VeoTaskError {
  final String message;
  final String code;

  VeoTaskError({
    required this.message,
    required this.code,
  });

  factory VeoTaskError.fromJson(Map<String, dynamic> json) {
    return VeoTaskError(
      message: json['message'] as String,
      code: json['code'] as String,
    );
  }

  @override
  String toString() => '[$code] $message';
}

/// Sora 角色信息
/// 
/// 从视频中提取的角色，可用于后续视频生成时引用
class SoraCharacter {
  /// 角色 ID
  final String id;
  
  /// 角色名称，用于在提示词中引用，格式：@{username}
  final String username;
  
  /// 角色主页链接（OpenAI 角色主页）
  final String permalink;
  
  /// 角色头像 URL
  final String profilePictureUrl;
  
  /// 角色描述（可选）
  final String? profileDesc;
  
  /// 原始响应数据
  final Map<String, dynamic> metadata;

  SoraCharacter({
    required this.id,
    required this.username,
    required this.permalink,
    required this.profilePictureUrl,
    this.profileDesc,
    required this.metadata,
  });

  factory SoraCharacter.fromJson(Map<String, dynamic> json) {
    return SoraCharacter(
      id: json['id'] as String,
      username: json['username'] as String,
      permalink: json['permalink'] as String,
      profilePictureUrl: json['profile_picture_url'] as String,
      profileDesc: json['profile_desc'] as String?,
      metadata: json,
    );
  }

  /// 获取用于提示词中的角色引用标签
  /// 
  /// 返回格式：@{username}
  /// 
  /// 示例：
  /// ```dart
  /// final character = result.data!;
  /// final prompt = '让 ${character.mentionTag} 跳舞';
  /// // 结果：让 @character_name 跳舞
  /// ```
  String get mentionTag => '@$username';

  @override
  String toString() => 'SoraCharacter(id: $id, username: @$username)';
}
