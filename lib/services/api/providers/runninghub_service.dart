import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../base/api_service_base.dart';
import '../base/api_response.dart';

/// RunningHub 云端 ComfyUI 服务
///
/// 通过 RunningHub API 调用云端 ComfyUI 工作流
/// 用户使用自己的 RunningHub 账号和 RH 币
class RunningHubService extends ApiServiceBase {
  RunningHubService(super.config);

  static const String _apiHost = 'https://www.runninghub.cn';

  @override
  String get providerName => 'RunningHub';

  @override
  Future<ApiResponse<bool>> testConnection() async {
    try {
      debugPrint('🔍 测试 RunningHub 连接');

      final apiKey = config.apiKey;
      if (apiKey.isEmpty) {
        return ApiResponse.failure('请先填写 RunningHub API Key');
      }

      // 使用获取账户信息接口验证 API Key
      final response = await http.post(
        Uri.parse('$_apiHost/task/openapi/account'),
        headers: {
          'Content-Type': 'application/json',
          'Host': 'www.runninghub.cn',
        },
        body: jsonEncode({'apiKey': apiKey}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0) {
          debugPrint('✅ RunningHub 连接成功');
          return ApiResponse.success(true, statusCode: 200);
        } else {
          return ApiResponse.failure(
            'API Key 无效: ${data['msg'] ?? '未知错误'}',
            statusCode: response.statusCode,
          );
        }
      } else {
        return ApiResponse.failure(
          'RunningHub 响应异常: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } on TimeoutException {
      return ApiResponse.failure('RunningHub 连接超时，请检查网络');
    } catch (e) {
      return ApiResponse.failure('连接失败: $e');
    }
  }

  @override
  Future<ApiResponse<LlmResponse>> generateText({
    required String prompt,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    return ApiResponse.failure('RunningHub 不支持文本生成');
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
      debugPrint('\n🎨 RunningHub 生成图片');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      // 获取 WebApp ID
      final webappId = await _getWebappId('image');
      if (webappId == null || webappId.isEmpty) {
        return ApiResponse.failure('未配置图片 WebApp ID\n\n请在设置页面填写 RunningHub AI 应用 ID');
      }

      debugPrint('   WebApp ID: $webappId');
      debugPrint('   Prompt: ${prompt.substring(0, prompt.length > 100 ? 100 : prompt.length)}...');

      return await _runTask(
        webappId: webappId,
        prompt: prompt,
        referenceImages: referenceImages,
        isVideo: false,
      );
    } catch (e) {
      debugPrint('❌ RunningHub 图片生成失败: $e');
      return ApiResponse.failure('RunningHub 图片生成失败: $e');
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
      debugPrint('\n🎬 RunningHub 生成视频');
      debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      // 获取 WebApp ID
      final webappId = await _getWebappId('video');
      if (webappId == null || webappId.isEmpty) {
        return ApiResponse.failure('未配置视频 WebApp ID\n\n请在设置页面填写 RunningHub AI 应用 ID');
      }

      debugPrint('   WebApp ID: $webappId');
      debugPrint('   Prompt: ${prompt.substring(0, prompt.length > 100 ? 100 : prompt.length)}...');

      final imageResult = await _runTask(
        webappId: webappId,
        prompt: prompt,
        referenceImages: referenceImages,
        isVideo: true,
      );

      if (imageResult.isSuccess && imageResult.data != null) {
        final videos = imageResult.data!
            .map((img) => VideoResponse(
                  videoUrl: img.imageUrl,
                  videoId: img.imageId,
                  metadata: img.metadata,
                ))
            .toList();
        return ApiResponse.success(videos);
      } else {
        return ApiResponse.failure(imageResult.error ?? '视频生成失败');
      }
    } catch (e) {
      debugPrint('❌ RunningHub 视频生成失败: $e');
      return ApiResponse.failure('RunningHub 视频生成失败: $e');
    }
  }

  @override
  Future<ApiResponse<UploadResponse>> uploadAsset({
    required String filePath,
    String? assetType,
    Map<String, dynamic>? metadata,
  }) async {
    return ApiResponse.failure('请通过 generateImages/generateVideos 的 referenceImages 参数上传图片');
  }

  @override
  Future<ApiResponse<List<String>>> getAvailableModels({
    String? modelType,
  }) async {
    return ApiResponse.success(['RunningHub AI 应用']);
  }

  // ==================== 内部方法 ====================

  /// 获取 WebApp ID
  Future<String?> _getWebappId(String type) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('runninghub_${type}_webapp_id');
  }

  /// 运行 RunningHub 任务（核心方法）
  Future<ApiResponse<List<ImageResponse>>> _runTask({
    required String webappId,
    required String prompt,
    List<String>? referenceImages,
    required bool isVideo,
  }) async {
    final apiKey = config.apiKey;

    // 1. 获取 AI 应用的节点信息
    debugPrint('📋 获取节点信息...');
    final nodeInfoList = await _getNodeInfoList(apiKey, webappId);
    if (nodeInfoList == null) {
      return ApiResponse.failure('获取 AI 应用节点信息失败\n\n请检查 WebApp ID 是否正确');
    }

    debugPrint('   节点数量: ${nodeInfoList.length}');

    // 2. 设置文本提示词到 STRING 类型节点
    _setPromptToNodes(nodeInfoList, prompt);

    // 3. 上传并设置参考图片到 IMAGE 类型节点
    if (referenceImages != null && referenceImages.isNotEmpty) {
      await _uploadAndSetImages(apiKey, nodeInfoList, referenceImages);
    }

    // 4. 提交任务
    debugPrint('🚀 提交任务...');
    final taskId = await _submitTask(apiKey, webappId, nodeInfoList);
    if (taskId == null) {
      return ApiResponse.failure('提交任务失败');
    }
    debugPrint('   任务ID: $taskId');

    // 5. 轮询等待结果
    debugPrint('⏳ 等待任务完成...');
    final results = await _waitForResults(apiKey, taskId, isVideo: isVideo);
    if (results == null || results.isEmpty) {
      return ApiResponse.failure('任务执行失败或超时');
    }

    debugPrint('✅ 任务完成，获得 ${results.length} 个结果');

    final images = results
        .map((r) => ImageResponse(
              imageUrl: r['fileUrl'] as String,
              imageId: taskId,
              metadata: {
                'taskCostTime': r['taskCostTime'],
                'fileType': r['fileType'],
                'consumeCoins': r['consumeCoins'],
              },
            ))
        .toList();

    return ApiResponse.success(images);
  }

  /// 获取 AI 应用的节点信息列表
  Future<List<Map<String, dynamic>>?> _getNodeInfoList(
      String apiKey, String webappId) async {
    try {
      final response = await http.get(
        Uri.parse(
            '$_apiHost/api/webapp/apiCallDemo?apiKey=$apiKey&webappId=$webappId'),
        headers: {'Host': 'www.runninghub.cn'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0) {
          final list = data['data']?['nodeInfoList'] as List?;
          if (list != null) {
            return list
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }
        } else {
          debugPrint('❌ 获取节点信息失败: ${data['msg']}');
        }
      }
      return null;
    } catch (e) {
      debugPrint('❌ 获取节点信息异常: $e');
      return null;
    }
  }

  /// 设置提示词到 STRING 类型的节点
  void _setPromptToNodes(
      List<Map<String, dynamic>> nodeInfoList, String prompt) {
    for (final node in nodeInfoList) {
      if (node['fieldType'] == 'STRING') {
        final desc = (node['description'] ?? '').toString().toLowerCase();
        final fieldName = (node['fieldName'] ?? '').toString().toLowerCase();
        // 优先设置包含 prompt/text/描述 关键词的节点
        if (desc.contains('prompt') ||
            desc.contains('text') ||
            desc.contains('描述') ||
            desc.contains('输入') ||
            fieldName == 'prompt' ||
            fieldName == 'text') {
          node['fieldValue'] = prompt;
          debugPrint(
              '   ✏️ 设置提示词到节点 ${node['nodeId']}: ${node['nodeName']}');
        }
      }
    }
  }

  /// 上传参考图片并设置到 IMAGE 节点
  Future<void> _uploadAndSetImages(
    String apiKey,
    List<Map<String, dynamic>> nodeInfoList,
    List<String> imagePaths,
  ) async {
    final imageNodes = nodeInfoList
        .where((n) => n['fieldType'] == 'IMAGE')
        .toList();

    if (imageNodes.isEmpty) {
      debugPrint('   ⚠️ 没有 IMAGE 类型节点，跳过图片上传');
      return;
    }

    for (int i = 0; i < imagePaths.length && i < imageNodes.length; i++) {
      try {
        final uploadedFileName = await _uploadFile(apiKey, imagePaths[i]);
        if (uploadedFileName != null) {
          imageNodes[i]['fieldValue'] = uploadedFileName;
          debugPrint('   📸 上传图片到节点 ${imageNodes[i]['nodeId']}: $uploadedFileName');
        }
      } catch (e) {
        debugPrint('   ❌ 上传图片 $i 失败: $e');
      }
    }
  }

  /// 上传文件到 RunningHub
  Future<String?> _uploadFile(String apiKey, String filePath) async {
    try {
      final uri = Uri.parse('$_apiHost/task/openapi/upload');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Host'] = 'www.runninghub.cn';
      request.fields['apiKey'] = apiKey;
      request.fields['fileType'] = 'input';
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      final streamResponse =
          await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0) {
          return data['data']?['fileName'] as String?;
        }
      }
      return null;
    } catch (e) {
      debugPrint('❌ 文件上传异常: $e');
      return null;
    }
  }

  /// 提交任务
  Future<String?> _submitTask(
    String apiKey,
    String webappId,
    List<Map<String, dynamic>> nodeInfoList,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiHost/task/openapi/ai-app/run'),
        headers: {
          'Host': 'www.runninghub.cn',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'webappId': webappId,
          'apiKey': apiKey,
          'nodeInfoList': nodeInfoList,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0) {
          final taskId = data['data']?['taskId'] as String?;

          // 检查节点错误
          final promptTips = data['data']?['promptTips'];
          if (promptTips != null) {
            try {
              final tips = jsonDecode(promptTips as String);
              final nodeErrors = tips['node_errors'] as Map?;
              if (nodeErrors != null && nodeErrors.isNotEmpty) {
                debugPrint('⚠️ 节点错误: $nodeErrors');
              }
            } catch (_) {}
          }

          return taskId;
        } else {
          debugPrint('❌ 提交任务失败: ${data['msg']}');
        }
      }
      return null;
    } catch (e) {
      debugPrint('❌ 提交任务异常: $e');
      return null;
    }
  }

  /// 轮询等待任务完成
  Future<List<Map<String, dynamic>>?> _waitForResults(
    String apiKey,
    String taskId, {
    bool isVideo = false,
  }) async {
    final timeout = isVideo
        ? const Duration(minutes: 15)
        : const Duration(minutes: 10);
    final startTime = DateTime.now();

    while (DateTime.now().difference(startTime) < timeout) {
      await Future.delayed(const Duration(seconds: 5));

      try {
        final response = await http.post(
          Uri.parse('$_apiHost/task/openapi/outputs'),
          headers: {
            'Host': 'www.runninghub.cn',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'apiKey': apiKey,
            'taskId': taskId,
          }),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final code = data['code'] as int?;

          if (code == 0 && data['data'] != null) {
            // 成功
            final results = (data['data'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            return results;
          } else if (code == 805) {
            // 失败
            final failedReason = data['data']?['failedReason'];
            debugPrint('❌ 任务失败: $failedReason');
            return null;
          } else if (code == 804) {
            debugPrint('   ⏳ 运行中...');
          } else if (code == 813) {
            debugPrint('   ⏳ 排队中...');
          }
        }
      } catch (e) {
        debugPrint('   ⚠️ 查询状态异常: $e');
      }
    }

    debugPrint('⏰ 任务超时');
    return null;
  }
}
