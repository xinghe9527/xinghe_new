import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../base/api_service_base.dart';
import '../base/api_response.dart';

/// Midjourney API 服务
/// 支持 Imagine 任务提交和图像生成
class MidjourneyService extends ApiServiceBase {
  MidjourneyService(super.config);

  @override
  String get providerName => 'Midjourney';

  @override
  Future<ApiResponse<bool>> testConnection() async {
    try {
      // Midjourney 没有专门的健康检查接口，可以尝试提交一个简单任务
      final result = await submitImagine(
        prompt: 'test',
        mode: MidjourneyMode.relax,
      );
      
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
    // Midjourney 不支持纯文本生成
    return ApiResponse.failure('Midjourney 服务不支持纯文本生成');
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
    // 提交 Imagine 任务
    final mode = parameters?['mode'] as String? ?? MidjourneyMode.relax;
    final state = parameters?['state'] as String?;
    final notifyHook = parameters?['notifyHook'] as String?;

    final result = await submitImagine(
      prompt: prompt,
      mode: mode,
      base64Array: referenceImages,
      state: state,
      notifyHook: notifyHook,
    );

    if (result.isSuccess) {
      // Midjourney 是异步任务，返回任务 ID
      // 需要轮询或使用回调来获取最终图片
      return ApiResponse.success(
        [
          ImageResponse(
            imageUrl: '', // 任务提交阶段还没有图片 URL
            imageId: result.data!.taskId,
            metadata: {
              'taskId': result.data!.taskId,
              'code': result.data!.code,
              'description': result.data!.description,
            },
          )
        ],
        statusCode: result.statusCode,
      );
    } else {
      return ApiResponse.failure(
        result.errorMessage ?? '提交任务失败',
        statusCode: result.statusCode,
      );
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
    // Midjourney 不支持视频生成
    return ApiResponse.failure('Midjourney 服务不支持视频生成');
  }

  @override
  Future<ApiResponse<UploadResponse>> uploadAsset({
    required String filePath,
    String? assetType,
    Map<String, dynamic>? metadata,
  }) async {
    // Midjourney 使用 base64 方式传递图片，不需要单独上传
    return ApiResponse.failure('Midjourney 服务使用 base64 方式，无需单独上传');
  }

  @override
  Future<ApiResponse<List<String>>> getAvailableModels({
    String? modelType,
  }) async {
    // Midjourney 模型相对固定，主要通过 prompt 参数控制
    final models = [
      'midjourney-v6',
      'midjourney-v5',
      'niji-v5',
    ];
    
    return ApiResponse.success(models, statusCode: 200);
  }

  // ==================== Midjourney 专有方法 ====================

  /// 提交 Imagine 任务
  /// 
  /// 参数：
  /// - prompt: 提示词（必需）
  /// - mode: 调用模式（RELAX 慢速 / FAST 快速）
  /// - base64Array: 垫图 base64 数组（可选）
  /// - state: 自定义参数（可选）
  /// - notifyHook: 回调接口（可选）
  Future<ApiResponse<MidjourneyTaskResponse>> submitImagine({
    required String prompt,
    String mode = MidjourneyMode.relax,
    List<String>? base64Array,
    String? state,
    String? notifyHook,
  }) async {
    try {
      // 构建请求体
      final requestBody = {
        'mode': mode,
        'prompt': prompt,
        if (base64Array != null && base64Array.isNotEmpty)
          'base64Array': base64Array,
        if (state != null) 'state': state,
        if (notifyHook != null) 'notifyhook': notifyHook,
      };

      // 发送请求
      final response = await http.post(
        Uri.parse('${config.baseUrl}/mj/submit/imagine'),
        headers: _buildHeaders(),
        body: jsonEncode(requestBody),
      );

      // 解析响应
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        final code = data['code'] as int;
        final description = data['description'] as String;
        final taskId = data['result'] as String;

        // 判断是否成功
        if (code == 1) {
          return ApiResponse.success(
            MidjourneyTaskResponse(
              code: code,
              description: description,
              taskId: taskId,
            ),
            statusCode: 200,
          );
        } else {
          // 处理各种错误码
          String errorMsg;
          switch (code) {
            case 22:
              errorMsg = '任务排队中，请稍后再试';
              break;
            case 23:
              errorMsg = '队列已满，请稍后尝试';
              break;
            case 24:
              errorMsg = 'prompt 包含敏感词';
              break;
            default:
              errorMsg = description;
          }
          
          return ApiResponse.failure(
            errorMsg,
            statusCode: 200, // HTTP 请求成功，但业务失败
          );
        }
      } else {
        return ApiResponse.failure(
          '提交失败: HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('提交任务错误: $e');
    }
  }

  /// 上传图片到 Discord
  /// 
  /// 将本地图片上传到 Discord，获取 CDN URL
  /// 
  /// 用途：
  /// - 获取可在 Midjourney 中使用的图片 URL
  /// - 用于需要 URL 而非 base64 的场景
  /// 
  /// 参数：
  /// - base64Array: 图片 base64 数组（必需）
  /// - mode: 调用模式（RELAX 慢速 / FAST 快速）
  Future<ApiResponse<List<String>>> uploadToDiscord({
    required List<String> base64Array,
    String mode = MidjourneyMode.relax,
  }) async {
    try {
      // 构建请求体
      final requestBody = {
        'mode': mode,
        'base64Array': base64Array,
      };

      // 发送请求
      final response = await http.post(
        Uri.parse('${config.baseUrl}/mj/submit/upload-discord-images'),
        headers: _buildHeaders(),
        body: jsonEncode(requestBody),
      );

      // 解析响应
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        final code = data['code'] as int;
        final description = data['description'] as String;
        final result = data['result'] as List<dynamic>?;

        // 判断是否成功
        if (code == 1 && result != null) {
          final imageUrls = result.map((url) => url.toString()).toList();
          
          return ApiResponse.success(
            imageUrls,
            statusCode: 200,
          );
        } else {
          // 处理各种错误码
          String errorMsg;
          switch (code) {
            case 22:
              errorMsg = '任务排队中，请稍后再试';
              break;
            case 23:
              errorMsg = '队列已满，请稍后尝试';
              break;
            case 24:
              errorMsg = '图片包含敏感内容';
              break;
            default:
              errorMsg = description;
          }
          
          return ApiResponse.failure(
            errorMsg,
            statusCode: 200,
          );
        }
      } else {
        return ApiResponse.failure(
          '上传失败: HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('上传到 Discord 错误: $e');
    }
  }

  /// 提交 Video 任务（视频生成）
  /// 
  /// 基于已生成的图片创建视频
  /// 
  /// 参数：
  /// - taskId: 父任务 ID（必需，来自 Imagine 任务）
  /// - index: 视频索引号（必需，1-4）
  /// - motion: 运动幅度（必需，low/high）
  /// - mode: 调用模式（RELAX 慢速 / FAST 快速）
  /// - prompt: 提示词（可选）
  /// - image: 首帧图片（可选，url 或 base64）
  /// - action: 视频操作（可选，extend=扩展）
  /// - state: 自定义参数（可选）
  /// - notifyHook: 回调接口（可选）
  Future<ApiResponse<MidjourneyTaskResponse>> submitVideo({
    required String taskId,
    required int index,
    required String motion,
    String mode = MidjourneyMode.relax,
    String? prompt,
    String? image,
    String? action,
    String? state,
    String? notifyHook,
  }) async {
    try {
      // 构建请求体
      final requestBody = {
        'mode': mode,
        'taskId': taskId,
        'index': index,
        'motion': motion,
        if (prompt != null && prompt.isNotEmpty) 'prompt': prompt,
        if (image != null && image.isNotEmpty) 'image': image,
        if (action != null && action.isNotEmpty) 'action': action,
        if (state != null) 'state': state,
        if (notifyHook != null) 'notifyHook': notifyHook,
      };

      // 发送请求
      final response = await http.post(
        Uri.parse('${config.baseUrl}/mj/submit/video'),
        headers: _buildHeaders(),
        body: jsonEncode(requestBody),
      );

      // 解析响应
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        final code = data['code'] as int?;
        final description = data['description'] as String?;
        final videoTaskId = data['result'] as String?;

        // 判断是否成功
        if (code == 1 && videoTaskId != null) {
          return ApiResponse.success(
            MidjourneyTaskResponse(
              code: code!,
              description: description ?? 'Success',
              taskId: videoTaskId,
            ),
            statusCode: 200,
          );
        } else {
          // 处理各种错误码
          String errorMsg;
          switch (code) {
            case 22:
              errorMsg = '任务排队中，请稍后再试';
              break;
            case 23:
              errorMsg = '队列已满，请稍后尝试';
              break;
            case 24:
              errorMsg = 'prompt 包含敏感词';
              break;
            default:
              errorMsg = description ?? '未知错误';
          }
          
          return ApiResponse.failure(
            errorMsg,
            statusCode: 200,
          );
        }
      } else {
        return ApiResponse.failure(
          '提交失败: HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('提交 Video 任务错误: $e');
    }
  }

  /// 提交 SwapFace 任务（换脸）
  /// 
  /// 将源图片的人脸替换到目标图片上
  /// 
  /// 注意：此接口使用 multipart/form-data 上传
  /// 
  /// 参数：
  /// - sourceImagePath: 人脸源图片路径（必需）
  /// - targetImagePath: 目标图片路径（必需）
  /// - mode: 调用模式（RELAX 慢速 / FAST 快速）
  Future<ApiResponse<MidjourneyTaskResponse>> submitSwapFace({
    required String sourceImagePath,
    required String targetImagePath,
    String mode = MidjourneyMode.relax,
  }) async {
    try {
      // 创建 multipart 请求
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${config.baseUrl}/mj/insight-face/swap'),
      );

      // 添加请求头
      request.headers['Authorization'] = config.apiKey;

      // 添加模式参数
      request.fields['mode'] = mode;

      // 添加图片文件
      request.files.add(
        await http.MultipartFile.fromPath(
          'source',
          sourceImagePath,
        ),
      );
      
      request.files.add(
        await http.MultipartFile.fromPath(
          'target',
          targetImagePath,
        ),
      );

      // 发送请求
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      // 解析响应
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        final code = data['code'] as int;
        final description = data['description'] as String;
        final taskId = data['result'] as String;

        // 判断是否成功
        if (code == 1) {
          return ApiResponse.success(
            MidjourneyTaskResponse(
              code: code,
              description: description,
              taskId: taskId,
            ),
            statusCode: 200,
          );
        } else {
          // 处理各种错误码
          String errorMsg;
          switch (code) {
            case 22:
              errorMsg = '任务排队中，请稍后再试';
              break;
            case 23:
              errorMsg = '队列已满，请稍后尝试';
              break;
            case 24:
              errorMsg = '图片包含敏感内容';
              break;
            default:
              errorMsg = description;
          }
          
          return ApiResponse.failure(
            errorMsg,
            statusCode: 200,
          );
        }
      } else {
        return ApiResponse.failure(
          '提交失败: HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('提交 SwapFace 任务错误: $e');
    }
  }

  /// 提交 Shorten 任务（Prompt 优化）
  /// 
  /// 优化和简化 prompt
  /// 
  /// 用途：
  /// - 简化冗长的 prompt
  /// - 优化 prompt 效率
  /// - 提取关键要素
  /// 
  /// 参数：
  /// - prompt: 要优化的提示词（必需）
  /// - mode: 调用模式（RELAX 慢速 / FAST 快速）
  /// - botType: bot 类型（mj / niji）
  /// - state: 自定义参数（可选）
  /// - notifyHook: 回调接口（可选）
  Future<ApiResponse<MidjourneyTaskResponse>> submitShorten({
    required String prompt,
    String mode = MidjourneyMode.relax,
    String? botType,
    String? state,
    String? notifyHook,
  }) async {
    try {
      // 构建请求体
      final requestBody = {
        'mode': mode,
        'prompt': prompt,
        if (botType != null) 'botType': botType,
        if (state != null) 'state': state,
        if (notifyHook != null) 'notifyhook': notifyHook,
      };

      // 发送请求
      final response = await http.post(
        Uri.parse('${config.baseUrl}/mj/submit/shorten'),
        headers: _buildHeaders(),
        body: jsonEncode(requestBody),
      );

      // 解析响应
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        final code = data['code'] as int;
        final description = data['description'] as String;
        final taskId = data['result'] as String;

        // 判断是否成功
        if (code == 1) {
          return ApiResponse.success(
            MidjourneyTaskResponse(
              code: code,
              description: description,
              taskId: taskId,
            ),
            statusCode: 200,
          );
        } else {
          // 处理各种错误码
          String errorMsg;
          switch (code) {
            case 22:
              errorMsg = '任务排队中，请稍后再试';
              break;
            case 23:
              errorMsg = '队列已满，请稍后尝试';
              break;
            case 24:
              errorMsg = 'prompt 包含敏感词';
              break;
            default:
              errorMsg = description;
          }
          
          return ApiResponse.failure(
            errorMsg,
            statusCode: 200,
          );
        }
      } else {
        return ApiResponse.failure(
          '提交失败: HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('提交 Shorten 任务错误: $e');
    }
  }

  /// 提交 Describe 任务（图生文）
  /// 
  /// 分析图片并生成描述性文本
  /// 
  /// 用途：
  /// - 分析图片内容
  /// - 反向工程 prompt
  /// - 学习如何描述图片
  /// 
  /// 参数：
  /// - base64: 图片 base64（必需）
  /// - mode: 调用模式（RELAX 慢速 / FAST 快速）
  /// - botType: bot 类型（mj / niji）
  /// - state: 自定义参数（可选）
  /// - notifyHook: 回调接口（可选）
  Future<ApiResponse<MidjourneyTaskResponse>> submitDescribe({
    required String base64,
    String mode = MidjourneyMode.relax,
    String? botType,
    String? state,
    String? notifyHook,
  }) async {
    try {
      // 构建请求体
      final requestBody = {
        'mode': mode,
        'base64': base64,
        if (botType != null) 'botType': botType,
        if (state != null) 'state': state,
        if (notifyHook != null) 'notifyhook': notifyHook,
      };

      // 发送请求
      final response = await http.post(
        Uri.parse('${config.baseUrl}/mj/submit/describe'),
        headers: _buildHeaders(),
        body: jsonEncode(requestBody),
      );

      // 解析响应
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        final code = data['code'] as int;
        final description = data['description'] as String;
        final taskId = data['result'] as String;

        // 判断是否成功
        if (code == 1) {
          return ApiResponse.success(
            MidjourneyTaskResponse(
              code: code,
              description: description,
              taskId: taskId,
            ),
            statusCode: 200,
          );
        } else {
          // 处理各种错误码
          String errorMsg;
          switch (code) {
            case 22:
              errorMsg = '任务排队中，请稍后再试';
              break;
            case 23:
              errorMsg = '队列已满，请稍后尝试';
              break;
            case 24:
              errorMsg = '图片包含敏感内容';
              break;
            default:
              errorMsg = description;
          }
          
          return ApiResponse.failure(
            errorMsg,
            statusCode: 200,
          );
        }
      } else {
        return ApiResponse.failure(
          '提交失败: HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('提交 Describe 任务错误: $e');
    }
  }

  /// 提交 Modal 任务
  /// 
  /// 当其他任务返回 code: 21 时，需要调用此接口传入额外信息
  /// 
  /// 用途：
  /// - 局部重绘：通过 maskBase64 指定重绘区域
  /// - 细节修改：通过 prompt 描述修改内容
  /// 
  /// 参数：
  /// - taskId: 原任务 ID（必需）
  /// - prompt: 提示词（通常需要）
  /// - maskBase64: 局部重绘的蒙版 base64（可选）
  Future<ApiResponse<MidjourneyTaskResponse>> submitModal({
    required String taskId,
    String? prompt,
    String? maskBase64,
  }) async {
    try {
      // 构建请求体
      final requestBody = {
        'taskId': taskId,
        if (prompt != null && prompt.isNotEmpty) 'prompt': prompt,
        if (maskBase64 != null && maskBase64.isNotEmpty) 'maskBase64': maskBase64,
      };

      // 发送请求
      final response = await http.post(
        Uri.parse('${config.baseUrl}/mj/submit/modal'),
        headers: _buildHeaders(),
        body: jsonEncode(requestBody),
      );

      // 解析响应
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        final code = data['code'] as int;
        final description = data['description'] as String;
        final resultTaskId = data['result'] as String;

        // 判断是否成功
        if (code == 1) {
          return ApiResponse.success(
            MidjourneyTaskResponse(
              code: code,
              description: description,
              taskId: resultTaskId,
            ),
            statusCode: 200,
          );
        } else {
          // 处理各种错误码
          String errorMsg;
          switch (code) {
            case 22:
              errorMsg = '任务排队中，请稍后再试';
              break;
            case 23:
              errorMsg = '队列已满，请稍后尝试';
              break;
            case 24:
              errorMsg = 'prompt 包含敏感词';
              break;
            default:
              errorMsg = description;
          }
          
          return ApiResponse.failure(
            errorMsg,
            statusCode: 200,
          );
        }
      } else {
        return ApiResponse.failure(
          '提交失败: HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('提交 Modal 任务错误: $e');
    }
  }

  /// 提交 Blend 任务（融图）
  /// 
  /// 专门用于融合多张图片的接口
  /// 
  /// 参数：
  /// - base64Array: 图片 base64 数组（必需，2-5张图片）
  /// - mode: 调用模式（RELAX 慢速 / FAST 快速）
  /// - dimensions: 比例（PORTRAIT/SQUARE/LANDSCAPE）
  /// - botType: bot 类型（mj / niji）
  /// - state: 自定义参数（可选）
  /// - notifyHook: 回调接口（可选）
  Future<ApiResponse<MidjourneyTaskResponse>> submitBlend({
    required List<String> base64Array,
    String mode = MidjourneyMode.relax,
    String? dimensions,
    String? botType,
    String? state,
    String? notifyHook,
  }) async {
    try {
      // 验证图片数量
      if (base64Array.length < 2 || base64Array.length > 5) {
        return ApiResponse.failure('Blend 操作需要 2-5 张图片');
      }

      // 构建请求体
      final requestBody = {
        'mode': mode,
        'base64Array': base64Array,
        if (dimensions != null) 'dimensions': dimensions,
        if (botType != null) 'botType': botType,
        if (state != null) 'state': state,
        if (notifyHook != null) 'notifyhook': notifyHook,
      };

      // 发送请求
      final response = await http.post(
        Uri.parse('${config.baseUrl}/mj/submit/blend'),
        headers: _buildHeaders(),
        body: jsonEncode(requestBody),
      );

      // 解析响应
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        final code = data['code'] as int;
        final description = data['description'] as String;
        final taskId = data['result'] as String;

        // 判断是否成功
        if (code == 1) {
          return ApiResponse.success(
            MidjourneyTaskResponse(
              code: code,
              description: description,
              taskId: taskId,
            ),
            statusCode: 200,
          );
        } else {
          // 处理各种错误码
          String errorMsg;
          switch (code) {
            case 22:
              errorMsg = '任务排队中，请稍后再试';
              break;
            case 23:
              errorMsg = '队列已满，请稍后尝试';
              break;
            case 24:
              errorMsg = 'prompt 包含敏感词';
              break;
            default:
              errorMsg = description;
          }
          
          return ApiResponse.failure(
            errorMsg,
            statusCode: 200,
          );
        }
      } else {
        return ApiResponse.failure(
          '提交失败: HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('提交 Blend 任务错误: $e');
    }
  }

  /// 提交 Action 任务
  /// 
  /// 用于对已生成的图片执行操作（如 Upscale、Variation 等）
  /// 
  /// 参数：
  /// - taskId: 原任务 ID（必需）
  /// - customId: 动作标识（必需），从任务查询结果中获取
  /// - mode: 调用模式（RELAX 慢速 / FAST 快速）
  /// - botType: bot 类型（mj / niji）
  /// - state: 自定义参数（可选）
  /// - notifyHook: 回调接口（可选）
  Future<ApiResponse<MidjourneyTaskResponse>> submitAction({
    required String taskId,
    required String customId,
    String mode = MidjourneyMode.relax,
    String? botType,
    String? state,
    String? notifyHook,
  }) async {
    try {
      // 构建请求体
      final requestBody = {
        'taskId': taskId,
        'customId': customId,
        'mode': mode,
        if (botType != null) 'botType': botType,
        if (state != null) 'state': state,
        if (notifyHook != null) 'notifyhook': notifyHook,
      };

      // 发送请求
      final response = await http.post(
        Uri.parse('${config.baseUrl}/mj/submit/action'),
        headers: _buildHeaders(),
        body: jsonEncode(requestBody),
      );

      // 解析响应
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        final code = data['code'] as int;
        final description = data['description'] as String;
        final newTaskId = data['result'] as String;

        // 判断是否成功
        if (code == 1) {
          return ApiResponse.success(
            MidjourneyTaskResponse(
              code: code,
              description: description,
              taskId: newTaskId,
            ),
            statusCode: 200,
          );
        } else {
          // 处理各种错误码
          String errorMsg;
          switch (code) {
            case 22:
              errorMsg = '任务排队中，请稍后再试';
              break;
            case 23:
              errorMsg = '队列已满，请稍后尝试';
              break;
            case 24:
              errorMsg = 'prompt 包含敏感词';
              break;
            default:
              errorMsg = description;
          }
          
          return ApiResponse.failure(
            errorMsg,
            statusCode: 200,
          );
        }
      } else {
        return ApiResponse.failure(
          '提交失败: HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('提交 Action 任务错误: $e');
    }
  }

  /// 查询任务状态
  /// 
  /// 参数：
  /// - taskId: 任务 ID
  Future<ApiResponse<MidjourneyTaskStatus>> getTaskStatus({
    required String taskId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('${config.baseUrl}/mj/task/$taskId/fetch'),
        headers: _buildHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        return ApiResponse.success(
          MidjourneyTaskStatus.fromJson(data),
          statusCode: 200,
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

  /// 批量查询任务状态
  /// 
  /// 一次查询多个任务的状态
  /// 
  /// 参数：
  /// - taskIds: 任务 ID 列表
  Future<ApiResponse<List<MidjourneyTaskStatus>>> getTaskStatusBatch({
    required List<String> taskIds,
  }) async {
    try {
      final requestBody = {
        'ids': taskIds,
      };

      final response = await http.post(
        Uri.parse('${config.baseUrl}/mj/task/list-by-condition'),
        headers: _buildHeaders(),
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;
        
        final statuses = data
            .map((item) => MidjourneyTaskStatus.fromJson(item as Map<String, dynamic>))
            .toList();
        
        return ApiResponse.success(statuses, statusCode: 200);
      } else {
        return ApiResponse.failure(
          '批量查询失败: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('批量查询任务状态错误: $e');
    }
  }

  /// 获取任务图片的 Seed
  /// 
  /// Seed 用于复现相同的图片生成结果
  /// 
  /// 参数：
  /// - taskId: 任务 ID
  Future<ApiResponse<String>> getImageSeed({
    required String taskId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('${config.baseUrl}/mj/task/$taskId/image-seed'),
        headers: _buildHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        final code = data['code'] as int;
        final description = data['description'] as String;
        final seed = data['result'] as String?;

        if (code == 1 && seed != null) {
          return ApiResponse.success(seed, statusCode: 200);
        } else {
          return ApiResponse.failure(description, statusCode: 200);
        }
      } else {
        return ApiResponse.failure(
          '获取 seed 失败: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ApiResponse.failure('获取图片 seed 错误: $e');
    }
  }

  // ==================== 私有方法 ====================

  /// 构建请求头
  Map<String, String> _buildHeaders() {
    return {
      'Authorization': config.apiKey,
      'Content-Type': 'application/json',
    };
  }
}

// ==================== 数据模型 ====================

/// Midjourney 任务响应
class MidjourneyTaskResponse {
  final int code;
  final String description;
  final String taskId;

  MidjourneyTaskResponse({
    required this.code,
    required this.description,
    required this.taskId,
  });

  bool get isSuccess => code == 1;

  Map<String, dynamic> toJson() => {
    'code': code,
    'description': description,
    'taskId': taskId,
  };
}

/// Midjourney 任务状态（完整版）
class MidjourneyTaskStatus {
  final String id;
  final String status; // 'NOT_START', 'SUBMITTED', 'MODAL', 'IN_PROGRESS', 'FAILURE', 'SUCCESS', 'CANCEL'
  final String? action; // 任务类型
  final String? prompt;
  final String? promptEn;
  final String? description;
  final int? submitTime;
  final int? startTime;
  final int? finishTime;
  final int? imageWidth;
  final int? imageHeight;
  final String? imageUrl;
  final String? videoUrl;
  final String? progress;
  final String? failReason;
  final List<MidjourneyButton>? buttons;
  final String? state;
  final List<String>? imageUrls;
  final Map<String, dynamic>? metadata;

  MidjourneyTaskStatus({
    required this.id,
    required this.status,
    this.action,
    this.prompt,
    this.promptEn,
    this.description,
    this.submitTime,
    this.startTime,
    this.finishTime,
    this.imageWidth,
    this.imageHeight,
    this.imageUrl,
    this.videoUrl,
    this.progress,
    this.failReason,
    this.buttons,
    this.state,
    this.imageUrls,
    this.metadata,
  });

  bool get isFinished => status == 'SUCCESS' || status == 'FAILURE' || status == 'CANCEL';
  bool get isSuccess => status == 'SUCCESS';
  bool get isFailed => status == 'FAILURE';
  bool get isCanceled => status == 'CANCEL';
  bool get needsModal => status == 'MODAL';

  /// 获取进度百分比
  int? get progressPercent {
    if (progress == null) return null;
    final match = RegExp(r'(\d+)%').firstMatch(progress!);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  factory MidjourneyTaskStatus.fromJson(Map<String, dynamic> json) {
    // 解析 buttons 数组
    List<MidjourneyButton>? buttons;
    if (json['buttons'] != null) {
      buttons = (json['buttons'] as List)
          .map((b) => MidjourneyButton.fromJson(b as Map<String, dynamic>))
          .toList();
    }

    // 解析 imageUrls 数组
    List<String>? imageUrls;
    if (json['imageUrls'] != null) {
      imageUrls = (json['imageUrls'] as List)
          .map((url) => url.toString())
          .toList();
    }

    return MidjourneyTaskStatus(
      id: json['id'] as String,
      status: json['status'] as String,
      action: json['action'] as String?,
      prompt: json['prompt'] as String?,
      promptEn: json['promptEn'] as String?,
      description: json['description'] as String?,
      submitTime: json['submitTime'] as int?,
      startTime: json['startTime'] as int?,
      finishTime: json['finishTime'] as int?,
      imageWidth: json['imageWidth'] as int?,
      imageHeight: json['imageHeight'] as int?,
      imageUrl: json['imageUrl'] as String?,
      videoUrl: json['VideoUrl'] as String?,  // 注意大小写
      progress: json['progress']?.toString(),
      failReason: json['failReason'] as String?,
      buttons: buttons,
      state: json['state'] as String?,
      imageUrls: imageUrls,
      metadata: json,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status,
    'action': action,
    'prompt': prompt,
    'promptEn': promptEn,
    'imageUrl': imageUrl,
    'videoUrl': videoUrl,
    'progress': progress,
    'failReason': failReason,
    'buttons': buttons?.map((b) => b.toJson()).toList(),
    'imageUrls': imageUrls,
  };
}

/// Midjourney 按钮信息
class MidjourneyButton {
  final String customId;  // 动作标识
  final String? emoji;    // 图标
  final String? label;    // 文本（如 U1, U2, V1, V2）
  final int? type;        // 样式：2=Primary, 3=Green
  final int? style;       // 内部使用

  MidjourneyButton({
    required this.customId,
    this.emoji,
    this.label,
    this.type,
    this.style,
  });

  factory MidjourneyButton.fromJson(Map<String, dynamic> json) {
    return MidjourneyButton(
      customId: json['customId'] as String,
      emoji: json['emoji'] as String?,
      label: json['label'] as String?,
      type: json['type'] as int?,
      style: json['style'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'customId': customId,
    'emoji': emoji,
    'label': label,
    'type': type,
    'style': style,
  };
}

/// Midjourney Describe 结果
class MidjourneyDescribeResult {
  final String taskId;
  final List<String> prompts;  // 生成的多个 prompt 建议
  final Map<String, dynamic> metadata;

  MidjourneyDescribeResult({
    required this.taskId,
    required this.prompts,
    required this.metadata,
  });

  /// 获取最佳 prompt（通常是第一个）
  String get bestPrompt => prompts.isNotEmpty ? prompts.first : '';

  Map<String, dynamic> toJson() => {
    'taskId': taskId,
    'prompts': prompts,
    'metadata': metadata,
  };
}

/// Midjourney Shorten 结果
class MidjourneyShortenResult {
  final String taskId;
  final String originalPrompt;          // 原始 prompt
  final List<String> shortenedPrompts;  // 优化后的 prompt 建议
  final Map<String, dynamic> metadata;

  MidjourneyShortenResult({
    required this.taskId,
    required this.originalPrompt,
    required this.shortenedPrompts,
    required this.metadata,
  });

  /// 获取最佳优化版本（通常是第一个）
  String get bestShortened => shortenedPrompts.isNotEmpty ? shortenedPrompts.first : '';

  /// 计算优化比例
  double get optimizationRatio {
    if (shortenedPrompts.isEmpty) return 0;
    final shortened = bestShortened;
    return 1 - (shortened.length / originalPrompt.length);
  }

  Map<String, dynamic> toJson() => {
    'taskId': taskId,
    'originalPrompt': originalPrompt,
    'shortenedPrompts': shortenedPrompts,
    'optimizationRatio': optimizationRatio,
    'metadata': metadata,
  };
}

/// Midjourney 调用模式常量
class MidjourneyMode {
  /// 慢速模式（免费）
  static const String relax = 'RELAX';
  
  /// 快速模式（付费）
  static const String fast = 'FAST';
}

/// Midjourney Bot 类型常量
class MidjourneyBotType {
  /// Midjourney 标准 Bot
  static const String midjourney = 'mj';
  
  /// Niji Journey Bot (动漫风格)
  static const String niji = 'niji';
}

/// Midjourney Blend 比例常量
class MidjourneyDimensions {
  /// 竖向 2:3
  static const String portrait = 'PORTRAIT';
  
  /// 正方形 1:1
  static const String square = 'SQUARE';
  
  /// 横向 3:2
  static const String landscape = 'LANDSCAPE';
}

/// Midjourney 视频运动幅度常量
class MidjourneyMotion {
  /// 低运动幅度（较稳定）
  static const String low = 'low';
  
  /// 高运动幅度（较动感）
  static const String high = 'high';
}

/// Midjourney 任务状态常量
class MidjourneyTaskStatus_Status {
  /// 已提交
  static const String submitted = 'SUBMITTED';
  
  /// 进行中
  static const String inProgress = 'IN_PROGRESS';
  
  /// 成功
  static const String success = 'SUCCESS';
  
  /// 失败
  static const String failure = 'FAILURE';
}

// ==================== 辅助工具类 ====================

/// Midjourney 辅助类
/// 提供便捷的图像生成方法
class MidjourneyHelper {
  final MidjourneyService service;

  MidjourneyHelper(this.service);

  /// 提交文生图任务
  /// 
  /// 参数：
  /// - prompt: 图像描述
  /// - mode: 生成模式（RELAX 慢速 / FAST 快速）
  /// - customState: 自定义状态参数
  Future<ApiResponse<MidjourneyTaskResponse>> textToImage({
    required String prompt,
    String mode = MidjourneyMode.relax,
    String? customState,
  }) async {
    return service.submitImagine(
      prompt: prompt,
      mode: mode,
      state: customState,
    );
  }

  /// 提交图生图任务（使用垫图）
  /// 
  /// 参数：
  /// - prompt: 图像描述
  /// - referenceImages: 参考图片的 Base64 数组
  /// - mode: 生成模式
  Future<ApiResponse<MidjourneyTaskResponse>> imageToImage({
    required String prompt,
    required List<String> referenceImages,
    String mode = MidjourneyMode.relax,
  }) async {
    // 确保 base64 数据包含 data URI 前缀
    final base64Array = referenceImages.map((img) {
      if (img.startsWith('data:image/')) {
        return img;
      } else {
        return 'data:image/png;base64,$img';
      }
    }).toList();

    return service.submitImagine(
      prompt: prompt,
      mode: mode,
      base64Array: base64Array,
    );
  }

  /// 轮询任务状态直到完成
  /// 
  /// 参数：
  /// - taskId: 任务 ID
  /// - maxAttempts: 最大轮询次数
  /// - intervalSeconds: 轮询间隔（秒）
  Future<ApiResponse<MidjourneyTaskStatus>> pollTaskUntilComplete({
    required String taskId,
    int maxAttempts = 60,
    int intervalSeconds = 5,
  }) async {
    for (int i = 0; i < maxAttempts; i++) {
      final result = await service.getTaskStatus(taskId: taskId);
      
      if (!result.isSuccess) {
        return ApiResponse.failure(
          result.errorMessage ?? '查询任务状态失败',
        );
      }

      final status = result.data!;
      
      // 如果任务已完成，返回结果
      if (status.isFinished) {
        if (status.isSuccess) {
          return ApiResponse.success(status);
        } else {
          return ApiResponse.failure(
            status.failReason ?? '任务失败',
          );
        }
      }

      // 等待后继续轮询
      await Future.delayed(Duration(seconds: intervalSeconds));
    }

    return ApiResponse.failure('任务超时：已轮询 $maxAttempts 次仍未完成');
  }

  /// 提交任务并等待完成
  /// 
  /// 这是一个便捷方法，会自动轮询直到任务完成
  Future<ApiResponse<String>> submitAndWait({
    required String prompt,
    String mode = MidjourneyMode.relax,
    List<String>? referenceImages,
    int maxWaitMinutes = 5,
  }) async {
    // 1. 提交任务
    final submitResult = referenceImages == null || referenceImages.isEmpty
        ? await textToImage(prompt: prompt, mode: mode)
        : await imageToImage(
            prompt: prompt,
            referenceImages: referenceImages,
            mode: mode,
          );

    if (!submitResult.isSuccess) {
      return ApiResponse.failure(
        submitResult.errorMessage ?? '提交任务失败',
      );
    }

    final taskId = submitResult.data!.taskId;

    // 2. 轮询等待完成
    final maxAttempts = (maxWaitMinutes * 60 / 5).ceil();
    final statusResult = await pollTaskUntilComplete(
      taskId: taskId,
      maxAttempts: maxAttempts,
      intervalSeconds: 5,
    );

    if (statusResult.isSuccess) {
      final imageUrl = statusResult.data!.imageUrl;
      if (imageUrl == null || imageUrl.isEmpty) {
        return ApiResponse.failure('任务完成但未返回图片 URL');
      }
      return ApiResponse.success(imageUrl);
    } else {
      return ApiResponse.failure(
        statusResult.errorMessage ?? '任务执行失败',
      );
    }
  }

  /// 执行 Upscale 操作（放大某个图片）
  /// 
  /// 参数：
  /// - taskId: 原任务 ID
  /// - index: 要放大的图片索引 (1-4)
  /// - customId: 如果已知 customId，可直接传入
  /// - mode: 调用模式
  Future<ApiResponse<MidjourneyTaskResponse>> upscale({
    required String taskId,
    int? index,
    String? customId,
    String mode = MidjourneyMode.relax,
  }) async {
    // 如果没有提供 customId，需要先查询任务获取
    String actionId = customId ?? '';
    
    if (actionId.isEmpty && index != null) {
      // 构建标准的 upscale customId 格式
      // 实际使用时需要从任务状态中获取完整的 customId
      actionId = 'MJ::JOB::upsample::$index::$taskId';
    }

    if (actionId.isEmpty) {
      return ApiResponse.failure('必须提供 customId 或 index');
    }

    return service.submitAction(
      taskId: taskId,
      customId: actionId,
      mode: mode,
    );
  }

  /// 执行 Variation 操作（生成某个图片的变体）
  /// 
  /// 参数：
  /// - taskId: 原任务 ID
  /// - index: 要变体的图片索引 (1-4)
  /// - customId: 如果已知 customId，可直接传入
  /// - mode: 调用模式
  Future<ApiResponse<MidjourneyTaskResponse>> variation({
    required String taskId,
    int? index,
    String? customId,
    String mode = MidjourneyMode.relax,
  }) async {
    String actionId = customId ?? '';
    
    if (actionId.isEmpty && index != null) {
      // 构建标准的 variation customId 格式
      actionId = 'MJ::JOB::variation::$index::$taskId';
    }

    if (actionId.isEmpty) {
      return ApiResponse.failure('必须提供 customId 或 index');
    }

    return service.submitAction(
      taskId: taskId,
      customId: actionId,
      mode: mode,
    );
  }

  /// 执行 Reroll 操作（重新生成）
  /// 
  /// 参数：
  /// - taskId: 原任务 ID
  /// - customId: 如果已知 customId，可直接传入
  /// - mode: 调用模式
  Future<ApiResponse<MidjourneyTaskResponse>> reroll({
    required String taskId,
    String? customId,
    String mode = MidjourneyMode.relax,
  }) async {
    String actionId = customId ?? '';
    
    if (actionId.isEmpty) {
      // 构建标准的 reroll customId 格式
      actionId = 'MJ::JOB::reroll::0::$taskId';
    }

    return service.submitAction(
      taskId: taskId,
      customId: actionId,
      mode: mode,
    );
  }

  /// 提交 Blend 任务（融合图片）
  /// 
  /// 专门用于融合 2-5 张图片
  /// 
  /// 参数：
  /// - images: 图片 Base64 数组（2-5 张）
  /// - dimensions: 输出比例
  /// - mode: 调用模式
  /// - botType: Bot 类型
  Future<ApiResponse<MidjourneyTaskResponse>> blend({
    required List<String> images,
    String dimensions = MidjourneyDimensions.square,
    String mode = MidjourneyMode.relax,
    String? botType,
  }) async {
    // 确保 base64 数据包含 data URI 前缀
    final base64Array = images.map((img) {
      if (img.startsWith('data:image/')) {
        return img;
      } else {
        return 'data:image/png;base64,$img';
      }
    }).toList();

    return service.submitBlend(
      base64Array: base64Array,
      mode: mode,
      dimensions: dimensions,
      botType: botType,
    );
  }

  /// Blend 并等待完成
  /// 
  /// 便捷方法，自动等待融合完成
  Future<ApiResponse<String>> blendAndWait({
    required List<String> images,
    String dimensions = MidjourneyDimensions.square,
    String mode = MidjourneyMode.relax,
    int maxWaitMinutes = 5,
  }) async {
    // 1. 提交 Blend 任务
    final submitResult = await blend(
      images: images,
      dimensions: dimensions,
      mode: mode,
    );

    if (!submitResult.isSuccess) {
      return ApiResponse.failure(
        submitResult.errorMessage ?? '提交 Blend 任务失败',
      );
    }

    final taskId = submitResult.data!.taskId;

    // 2. 轮询等待完成
    final maxAttempts = (maxWaitMinutes * 60 / 5).ceil();
    final statusResult = await pollTaskUntilComplete(
      taskId: taskId,
      maxAttempts: maxAttempts,
      intervalSeconds: 5,
    );

    if (statusResult.isSuccess) {
      final imageUrl = statusResult.data!.imageUrl;
      if (imageUrl == null || imageUrl.isEmpty) {
        return ApiResponse.failure('Blend 完成但未返回图片 URL');
      }
      return ApiResponse.success(imageUrl);
    } else {
      return ApiResponse.failure(
        statusResult.errorMessage ?? 'Blend 任务执行失败',
      );
    }
  }

  /// 提交 Modal 任务（补充输入）
  /// 
  /// 当任务返回 code: 21 时，需要调用此方法提供额外信息
  /// 
  /// 参数：
  /// - taskId: 原任务 ID
  /// - prompt: 补充的提示词
  /// - maskBase64: 局部重绘的蒙版（可选）
  Future<ApiResponse<MidjourneyTaskResponse>> modal({
    required String taskId,
    String? prompt,
    String? maskBase64,
  }) async {
    return service.submitModal(
      taskId: taskId,
      prompt: prompt,
      maskBase64: maskBase64,
    );
  }

  /// 局部重绘
  /// 
  /// 对图片的指定区域进行重绘
  /// 
  /// 参数：
  /// - taskId: 原任务 ID
  /// - maskBase64: 蒙版图片（标记要重绘的区域）
  /// - prompt: 重绘描述
  Future<ApiResponse<MidjourneyTaskResponse>> inpaint({
    required String taskId,
    required String maskBase64,
    String? prompt,
  }) async {
    // 确保 maskBase64 包含 data URI 前缀
    String mask = maskBase64;
    if (!mask.startsWith('data:image/')) {
      mask = 'data:image/png;base64,$mask';
    }

    return service.submitModal(
      taskId: taskId,
      maskBase64: mask,
      prompt: prompt,
    );
  }

  /// Modal 并等待完成
  /// 
  /// 提交 Modal 任务并自动等待完成
  Future<ApiResponse<String>> modalAndWait({
    required String taskId,
    String? prompt,
    String? maskBase64,
    int maxWaitMinutes = 5,
  }) async {
    // 1. 提交 Modal 任务
    final submitResult = await modal(
      taskId: taskId,
      prompt: prompt,
      maskBase64: maskBase64,
    );

    if (!submitResult.isSuccess) {
      return ApiResponse.failure(
        submitResult.errorMessage ?? '提交 Modal 任务失败',
      );
    }

    final newTaskId = submitResult.data!.taskId;

    // 2. 轮询等待完成
    final maxAttempts = (maxWaitMinutes * 60 / 5).ceil();
    final statusResult = await pollTaskUntilComplete(
      taskId: newTaskId,
      maxAttempts: maxAttempts,
      intervalSeconds: 5,
    );

    if (statusResult.isSuccess) {
      final imageUrl = statusResult.data!.imageUrl;
      if (imageUrl == null || imageUrl.isEmpty) {
        return ApiResponse.failure('Modal 完成但未返回图片 URL');
      }
      return ApiResponse.success(imageUrl);
    } else {
      return ApiResponse.failure(
        statusResult.errorMessage ?? 'Modal 任务执行失败',
      );
    }
  }

  /// 提交 Describe 任务（图生文）
  /// 
  /// 分析图片并生成描述
  /// 
  /// 参数：
  /// - imageBase64: 图片 Base64 编码
  /// - mode: 调用模式
  /// - botType: Bot 类型
  Future<ApiResponse<MidjourneyTaskResponse>> describe({
    required String imageBase64,
    String mode = MidjourneyMode.relax,
    String? botType,
  }) async {
    // 确保 base64 数据包含 data URI 前缀
    String base64 = imageBase64;
    if (!base64.startsWith('data:image/')) {
      base64 = 'data:image/png;base64,$base64';
    }

    return service.submitDescribe(
      base64: base64,
      mode: mode,
      botType: botType,
    );
  }

  /// Describe 并等待完成
  /// 
  /// 提交图生文任务并自动获取描述结果
  Future<ApiResponse<MidjourneyDescribeResult>> describeAndWait({
    required String imageBase64,
    String mode = MidjourneyMode.relax,
    int maxWaitMinutes = 3,
  }) async {
    // 1. 提交 Describe 任务
    final submitResult = await describe(
      imageBase64: imageBase64,
      mode: mode,
    );

    if (!submitResult.isSuccess) {
      return ApiResponse.failure(
        submitResult.errorMessage ?? '提交 Describe 任务失败',
      );
    }

    final taskId = submitResult.data!.taskId;

    // 2. 轮询等待完成
    final maxAttempts = (maxWaitMinutes * 60 / 5).ceil();
    final statusResult = await pollTaskUntilComplete(
      taskId: taskId,
      maxAttempts: maxAttempts,
      intervalSeconds: 5,
    );

    if (statusResult.isSuccess) {
      final metadata = statusResult.data!.metadata;
      
      // 从 metadata 中提取描述结果
      // 注意：实际的响应格式可能需要根据 API 调整
      final prompts = metadata?['prompts'] as List<dynamic>?;
      
      return ApiResponse.success(
        MidjourneyDescribeResult(
          taskId: taskId,
          prompts: prompts?.map((p) => p.toString()).toList() ?? [],
          metadata: metadata ?? {},
        ),
      );
    } else {
      return ApiResponse.failure(
        statusResult.errorMessage ?? 'Describe 任务执行失败',
      );
    }
  }

  /// 提交 Shorten 任务（Prompt 优化）
  /// 
  /// 优化 prompt，简化冗长的描述
  /// 
  /// 参数：
  /// - prompt: 要优化的 prompt
  /// - mode: 调用模式
  Future<ApiResponse<MidjourneyTaskResponse>> shorten({
    required String prompt,
    String mode = MidjourneyMode.relax,
  }) async {
    return service.submitShorten(
      prompt: prompt,
      mode: mode,
    );
  }

  /// Shorten 并等待完成
  /// 
  /// 提交 Shorten 任务并自动获取优化结果
  Future<ApiResponse<MidjourneyShortenResult>> shortenAndWait({
    required String prompt,
    String mode = MidjourneyMode.relax,
    int maxWaitMinutes = 2,
  }) async {
    // 1. 提交 Shorten 任务
    final submitResult = await shorten(
      prompt: prompt,
      mode: mode,
    );

    if (!submitResult.isSuccess) {
      return ApiResponse.failure(
        submitResult.errorMessage ?? '提交 Shorten 任务失败',
      );
    }

    final taskId = submitResult.data!.taskId;

    // 2. 轮询等待完成
    final maxAttempts = (maxWaitMinutes * 60 / 5).ceil();
    final statusResult = await pollTaskUntilComplete(
      taskId: taskId,
      maxAttempts: maxAttempts,
      intervalSeconds: 5,
    );

    if (statusResult.isSuccess) {
      final metadata = statusResult.data!.metadata;
      
      // 从 metadata 中提取优化结果
      final shortenedPrompts = metadata?['shortenedPrompts'] as List<dynamic>?;
      
      return ApiResponse.success(
        MidjourneyShortenResult(
          taskId: taskId,
          originalPrompt: prompt,
          shortenedPrompts: shortenedPrompts?.map((p) => p.toString()).toList() ?? [],
          metadata: metadata ?? {},
        ),
      );
    } else {
      return ApiResponse.failure(
        statusResult.errorMessage ?? 'Shorten 任务执行失败',
      );
    }
  }

  /// 提交 SwapFace 任务（换脸）
  /// 
  /// 将源图片的人脸替换到目标图片中
  /// 
  /// 参数：
  /// - sourceImagePath: 人脸源图片路径
  /// - targetImagePath: 目标图片路径
  /// - mode: 调用模式
  Future<ApiResponse<MidjourneyTaskResponse>> swapFace({
    required String sourceImagePath,
    required String targetImagePath,
    String mode = MidjourneyMode.relax,
  }) async {
    return service.submitSwapFace(
      sourceImagePath: sourceImagePath,
      targetImagePath: targetImagePath,
      mode: mode,
    );
  }

  /// SwapFace 并等待完成
  /// 
  /// 提交换脸任务并自动等待完成
  Future<ApiResponse<String>> swapFaceAndWait({
    required String sourceImagePath,
    required String targetImagePath,
    String mode = MidjourneyMode.relax,
    int maxWaitMinutes = 3,
  }) async {
    // 1. 提交 SwapFace 任务
    final submitResult = await swapFace(
      sourceImagePath: sourceImagePath,
      targetImagePath: targetImagePath,
      mode: mode,
    );

    if (!submitResult.isSuccess) {
      return ApiResponse.failure(
        submitResult.errorMessage ?? '提交 SwapFace 任务失败',
      );
    }

    final taskId = submitResult.data!.taskId;

    // 2. 轮询等待完成
    final maxAttempts = (maxWaitMinutes * 60 / 5).ceil();
    final statusResult = await pollTaskUntilComplete(
      taskId: taskId,
      maxAttempts: maxAttempts,
      intervalSeconds: 5,
    );

    if (statusResult.isSuccess) {
      final imageUrl = statusResult.data!.imageUrl;
      if (imageUrl == null || imageUrl.isEmpty) {
        return ApiResponse.failure('SwapFace 完成但未返回图片 URL');
      }
      return ApiResponse.success(imageUrl);
    } else {
      return ApiResponse.failure(
        statusResult.errorMessage ?? 'SwapFace 任务执行失败',
      );
    }
  }

  /// 生成视频（基于图片）
  /// 
  /// 将静态图片转换为动态视频
  /// 
  /// 参数：
  /// - taskId: 父任务 ID（来自 Imagine）
  /// - index: 图片索引（1-4）
  /// - motion: 运动幅度（low/high）
  /// - mode: 调用模式
  /// - prompt: 可选的提示词
  Future<ApiResponse<MidjourneyTaskResponse>> generateVideo({
    required String taskId,
    required int index,
    String motion = MidjourneyMotion.low,
    String mode = MidjourneyMode.relax,
    String? prompt,
  }) async {
    return service.submitVideo(
      taskId: taskId,
      index: index,
      motion: motion,
      mode: mode,
      prompt: prompt,
    );
  }

  /// 扩展视频
  /// 
  /// 延长已生成视频的时长
  /// 
  /// 参数：
  /// - videoTaskId: 视频任务 ID
  /// - index: 索引
  /// - mode: 调用模式
  Future<ApiResponse<MidjourneyTaskResponse>> extendVideo({
    required String videoTaskId,
    required int index,
    String mode = MidjourneyMode.relax,
  }) async {
    return service.submitVideo(
      taskId: videoTaskId,
      index: index,
      motion: MidjourneyMotion.low,
      mode: mode,
      action: 'extend',
    );
  }

  /// 生成视频并等待完成
  /// 
  /// 一键生成视频
  Future<ApiResponse<String>> generateVideoAndWait({
    required String taskId,
    required int index,
    String motion = MidjourneyMotion.low,
    String mode = MidjourneyMode.relax,
    String? prompt,
    int maxWaitMinutes = 10,
  }) async {
    // 1. 提交视频任务
    final submitResult = await generateVideo(
      taskId: taskId,
      index: index,
      motion: motion,
      mode: mode,
      prompt: prompt,
    );

    if (!submitResult.isSuccess) {
      return ApiResponse.failure(
        submitResult.errorMessage ?? '提交视频任务失败',
      );
    }

    final videoTaskId = submitResult.data!.taskId;

    // 2. 轮询等待完成（视频生成时间较长）
    final maxAttempts = (maxWaitMinutes * 60 / 10).ceil();
    final statusResult = await pollTaskUntilComplete(
      taskId: videoTaskId,
      maxAttempts: maxAttempts,
      intervalSeconds: 10,  // 视频生成较慢，间隔延长
    );

    if (statusResult.isSuccess) {
      final videoUrl = statusResult.data!.imageUrl;  // 视频 URL 也在 imageUrl 字段
      if (videoUrl == null || videoUrl.isEmpty) {
        return ApiResponse.failure('视频生成完成但未返回 URL');
      }
      return ApiResponse.success(videoUrl);
    } else {
      return ApiResponse.failure(
        statusResult.errorMessage ?? '视频生成失败',
      );
    }
  }

  /// 上传图片到 Discord（辅助方法）
  /// 
  /// 将图片上传到 Discord 并获取 CDN URL
  /// 
  /// 参数：
  /// - imagePaths: 图片路径列表
  /// - mode: 调用模式
  Future<ApiResponse<List<String>>> uploadImagesToDiscord({
    required List<String> imagePaths,
    String mode = MidjourneyMode.relax,
  }) async {
    // 读取图片并转换为 base64
    final base64Array = <String>[];
    
    for (final path in imagePaths) {
      try {
        final bytes = await File(path).readAsBytes();
        final base64 = base64Encode(bytes);
        
        // 添加 data URI 前缀
        if (!base64.startsWith('data:image/')) {
          base64Array.add('data:image/jpeg;base64,$base64');
        } else {
          base64Array.add(base64);
        }
      } catch (e) {
        return ApiResponse.failure('读取图片失败: $path - $e');
      }
    }

    // 上传到 Discord
    return service.uploadToDiscord(
      base64Array: base64Array,
      mode: mode,
    );
  }
}

/// Midjourney Prompt 构建器
/// 帮助构建符合 Midjourney 规范的 prompt
class MidjourneyPromptBuilder {
  String _prompt = '';
  final List<String> _parameters = [];

  /// 设置基础描述
  MidjourneyPromptBuilder withDescription(String description) {
    _prompt = description;
    return this;
  }

  /// 添加风格参数
  MidjourneyPromptBuilder withStyle(String style) {
    _parameters.add('--style $style');
    return this;
  }

  /// 设置宽高比
  MidjourneyPromptBuilder withAspectRatio(String ratio) {
    _parameters.add('--ar $ratio');
    return this;
  }

  /// 设置版本
  MidjourneyPromptBuilder withVersion(String version) {
    _parameters.add('--v $version');
    return this;
  }

  /// 设置质量
  MidjourneyPromptBuilder withQuality(double quality) {
    _parameters.add('--q $quality');
    return this;
  }

  /// 设置种子值
  MidjourneyPromptBuilder withSeed(int seed) {
    _parameters.add('--seed $seed');
    return this;
  }

  /// 设置风格化程度
  MidjourneyPromptBuilder withStylize(int value) {
    _parameters.add('--s $value');
    return this;
  }

  /// 设置混乱度
  MidjourneyPromptBuilder withChaos(int value) {
    _parameters.add('--c $value');
    return this;
  }

  /// 添加负面提示词
  MidjourneyPromptBuilder withNegative(String negative) {
    _parameters.add('--no $negative');
    return this;
  }

  /// 构建最终 prompt
  String build() {
    if (_prompt.isEmpty) {
      throw Exception('必须设置基础描述');
    }

    if (_parameters.isEmpty) {
      return _prompt;
    }

    return '$_prompt ${_parameters.join(' ')}';
  }

  /// 重置构建器
  void reset() {
    _prompt = '';
    _parameters.clear();
  }
}

/// Midjourney 常用宽高比
class MidjourneyAspectRatio {
  static const String square = '1:1';
  static const String landscape = '16:9';
  static const String portrait = '9:16';
  static const String standard = '4:3';
  static const String wide = '21:9';
}

/// Midjourney 版本
class MidjourneyVersion {
  static const String v6 = '6';
  static const String v5 = '5';
  static const String v4 = '4';
  static const String niji5 = 'niji 5';
}
