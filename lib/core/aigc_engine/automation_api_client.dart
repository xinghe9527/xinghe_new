import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

// ============================================================================
// 数据模型
// ============================================================================

/// AIGC 任务结果实体类
/// 
/// 用于接收 Python FastAPI 返回的任务结果
class AigcTaskResult {
  /// 任务 ID
  final String taskId;
  
  /// 任务状态：pending, running, success, failed, cancelled
  final String status;
  
  /// 消息描述
  final String message;
  
  /// 创建时间
  final String createdAt;
  
  /// 更新时间
  final String? updatedAt;
  
  /// 提示词
  final String? prompt;
  
  /// 平台名称（vidu, jimeng, keling, hailuo）
  final String? platform;
  
  /// 工具类型（text2video, img2video, text2image）
  final String? toolType;
  
  /// 云端视频地址（用于在线播放）
  final String? videoUrl;
  
  /// 本地视频路径（用于本地播放）
  final String? localVideoPath;
  
  /// 云端图片地址
  final String? imageUrl;
  
  /// 本地图片路径
  final String? localImagePath;
  
  /// 批量图片地址列表（Google Flow 批量生成用）
  final List<String>? localImagePaths;
  
  /// 批量图片 URL 列表
  final List<String>? imageUrls;
  
  /// 错误信息
  final String? error;
  
  /// 详细结果数据
  final Map<String, dynamic>? result;

  /// 批量模式时的所有任务 ID（Vidu 批量生成用）
  final List<String>? taskIds;

  AigcTaskResult({
    required this.taskId,
    required this.status,
    required this.message,
    required this.createdAt,
    this.updatedAt,
    this.prompt,
    this.platform,
    this.toolType,
    this.videoUrl,
    this.localVideoPath,
    this.imageUrl,
    this.localImagePath,
    this.localImagePaths,
    this.imageUrls,
    this.error,
    this.result,
    this.taskIds,
  });

  /// 从 JSON 创建实例
  factory AigcTaskResult.fromJson(Map<String, dynamic> json) {
    // 从 result 字段中提取媒体地址
    final resultData = json['result'] as Map<String, dynamic>?;
    
    return AigcTaskResult(
      taskId: json['task_id'] as String,
      status: json['status'] as String,
      message: json['message'] as String? ?? '',
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String?,
      prompt: json['prompt'] as String?,
      platform: json['platform'] as String?,
      toolType: json['tool_type'] as String?,
      videoUrl: resultData?['video_url'] as String?,
      localVideoPath: resultData?['local_video_path'] as String?,
      imageUrl: resultData?['image_url'] as String?,
      localImagePath: resultData?['local_image_path'] as String?,
      localImagePaths: (resultData?['local_image_paths'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      imageUrls: (resultData?['image_urls'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      error: json['error'] as String?,
      result: resultData,
      taskIds: (json['task_ids'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'task_id': taskId,
      'status': status,
      'message': message,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'prompt': prompt,
      'platform': platform,
      'tool_type': toolType,
      'video_url': videoUrl,
      'local_video_path': localVideoPath,
      'image_url': imageUrl,
      'local_image_path': localImagePath,
      'error': error,
      'result': result,
    };
  }

  /// 是否成功
  bool get isSuccess => status == 'success';

  /// 是否失败
  bool get isFailed => status == 'failed';

  /// 是否运行中
  bool get isRunning => status == 'running';

  /// 是否等待中
  bool get isPending => status == 'pending';

  /// 是否已取消
  bool get isCancelled => status == 'cancelled';

  /// 是否已完成（成功或失败）
  bool get isCompleted => isSuccess || isFailed || isCancelled;

  /// 获取媒体地址（优先云端，备选本地）
  String? get mediaUrl => videoUrl ?? imageUrl;

  /// 获取本地媒体路径
  String? get localMediaPath => localVideoPath ?? localImagePath;

  @override
  String toString() {
    return 'AigcTaskResult(taskId: $taskId, status: $status, platform: $platform, toolType: $toolType)';
  }
}

/// 浏览器控制结果
class BrowserControlResult {
  final bool success;
  final String message;
  final bool windowFound;

  BrowserControlResult({
    required this.success,
    required this.message,
    required this.windowFound,
  });

  factory BrowserControlResult.fromJson(Map<String, dynamic> json) {
    return BrowserControlResult(
      success: json['success'] as bool,
      message: json['message'] as String,
      windowFound: json['window_found'] as bool? ?? false,
    );
  }
}

// ============================================================================
// 统一 AIGC 自动化网关
// ============================================================================

/// 统一 AIGC 自动化 API 客户端
/// 
/// 负责与本地 Python FastAPI 服务通信
/// 支持多平台（Vidu、即梦、可灵、海螺）和多工具类型（文生视频、图生视频、文生图）
/// 
/// 设计原则：
/// - 高扩展性：新增平台无需修改核心逻辑
/// - 统一接口：所有平台使用相同的调用方式
/// - 完全隔离：不影响现有业务代码
class AutomationApiClient {
  /// API 基础地址
  static const String _baseUrl = 'http://127.0.0.1:8123';

  /// HTTP 客户端
  final http.Client _client;

  /// 请求超时时间
  final Duration timeout;

  /// 构造函数
  AutomationApiClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  // ==========================================================================
  // 核心方法：任务提交
  // ==========================================================================

  /// 提交生成任务（统一入口）
  /// 
  /// [platform] 平台名称：'vidu', 'jimeng', 'keling', 'hailuo'
  /// [toolType] 工具类型：'text2video', 'img2video', 'text2image'
  /// [payload] 任务参数，必须包含：
  ///   - prompt: 提示词（必需）
  ///   - imageUrl: 图片地址（img2video 时必需）
  ///   - model: 模型名称（可选）
  ///   - duration: 视频时长（可选）
  ///   - aspectRatio: 宽高比（可选）
  ///   - 其他平台特定参数
  /// 
  /// 返回任务 ID 和初始状态
  Future<AigcTaskResult> submitGenerationTask({
    required String platform,
    required String toolType,
    required Map<String, dynamic> payload,
  }) async {
    try {
      // 验证必需参数
      if (!payload.containsKey('prompt') && toolType != 'img2video') {
        throw ArgumentError('payload 必须包含 prompt 字段');
      }

      if (toolType == 'img2video' && !payload.containsKey('imageUrl')) {
        throw ArgumentError('img2video 类型必须包含 imageUrl 字段');
      }

      // 构建请求体
      final requestBody = {
        'platform': platform,
        'tool_type': toolType,
        'payload': payload,
      };

      // 发送 POST 请求
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/api/generate'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(requestBody),
          )
          .timeout(timeout);

      // 解析响应
      if (response.statusCode == 200) {
        final jsonData = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return AigcTaskResult.fromJson(jsonData);
      } else {
        throw Exception('任务提交失败: HTTP ${response.statusCode}\n${response.body}');
      }
    } on TimeoutException {
      throw Exception('请求超时，请检查 Python API 服务是否启动');
    } catch (e) {
      throw Exception('提交任务失败: $e');
    }
  }

  // ==========================================================================
  // 便捷方法：各平台快速调用
  // ==========================================================================

  /// Vidu 文生视频
  Future<AigcTaskResult> viduText2Video({
    required String prompt,
    String? model,
    int? duration,
    String? aspectRatio,
  }) async {
    return submitGenerationTask(
      platform: 'vidu',
      toolType: 'text2video',
      payload: {
        'prompt': prompt,
        if (model != null) 'model': model,
        if (duration != null) 'duration': duration,
        if (aspectRatio != null) 'aspect_ratio': aspectRatio,
      },
    );
  }

  /// Vidu 图生视频
  Future<AigcTaskResult> viduImage2Video({
    required String imageUrl,
    required String prompt,
    String? model,
    int? duration,
  }) async {
    return submitGenerationTask(
      platform: 'vidu',
      toolType: 'img2video',
      payload: {
        'image_url': imageUrl,
        'prompt': prompt,
        if (model != null) 'model': model,
        if (duration != null) 'duration': duration,
      },
    );
  }

  /// 即梦文生视频
  Future<AigcTaskResult> jimengText2Video({
    required String prompt,
    String? model,
    int? duration,
    List<String>? referenceImages,
    List<String>? characterNames,
  }) async {
    return submitGenerationTask(
      platform: 'jimeng',
      toolType: 'text2video',
      payload: {
        'prompt': prompt,
        if (model != null) 'model': model,
        if (duration != null) 'duration': duration,
        if (referenceImages != null) 'referenceImages': referenceImages,
        if (characterNames != null) 'characterNames': characterNames,
      },
    );
  }

  /// 可灵文生视频
  Future<AigcTaskResult> kelingText2Video({
    required String prompt,
    String? model,
    int? duration,
  }) async {
    return submitGenerationTask(
      platform: 'keling',
      toolType: 'text2video',
      payload: {
        'prompt': prompt,
        if (model != null) 'model': model,
        if (duration != null) 'duration': duration,
      },
    );
  }

  /// 海螺文生视频
  Future<AigcTaskResult> hailuoText2Video({
    required String prompt,
    String? model,
    int? duration,
  }) async {
    return submitGenerationTask(
      platform: 'hailuo',
      toolType: 'text2video',
      payload: {
        'prompt': prompt,
        if (model != null) 'model': model,
        if (duration != null) 'duration': duration,
      },
    );
  }

  // ==========================================================================
  // 任务状态查询
  // ==========================================================================

  /// 查询任务状态
  /// 
  /// [taskId] 任务 ID
  /// 返回任务的最新状态
  Future<AigcTaskResult> getTaskStatus(String taskId) async {
    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl/api/task/$taskId'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
            },
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return AigcTaskResult.fromJson(jsonData);
      } else if (response.statusCode == 404) {
        throw Exception('任务不存在: $taskId');
      } else {
        throw Exception('查询任务失败: HTTP ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('请求超时');
    } catch (e) {
      throw Exception('查询任务状态失败: $e');
    }
  }

  /// 轮询查询任务状态（直到完成）
  /// 
  /// [taskId] 任务 ID
  /// [interval] 轮询间隔（默认 2 秒）
  /// [maxAttempts] 最大尝试次数（默认 150 次，即 5 分钟）
  /// [onProgress] 进度回调
  /// 
  /// 返回最终任务结果
  Future<AigcTaskResult> pollTaskStatus({
    required String taskId,
    Duration interval = const Duration(seconds: 2),
    int maxAttempts = 150,
    void Function(AigcTaskResult)? onProgress,
  }) async {
    int attempts = 0;

    while (attempts < maxAttempts) {
      attempts++;

      try {
        final result = await getTaskStatus(taskId);

        // 回调进度
        onProgress?.call(result);

        // 如果任务已完成，返回结果
        if (result.isCompleted) {
          return result;
        }

        // 等待下一次轮询
        await Future.delayed(interval);
      } catch (e) {
        // 如果是最后一次尝试，抛出异常
        if (attempts >= maxAttempts) {
          rethrow;
        }
        // 否则继续尝试
        await Future.delayed(interval);
      }
    }

    throw Exception('轮询超时：任务未在规定时间内完成');
  }

  /// 获取所有任务列表
  Future<List<AigcTaskResult>> getAllTasks() async {
    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl/api/tasks'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
            },
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final tasks = jsonData['tasks'] as List<dynamic>;
        return tasks.map((task) => AigcTaskResult.fromJson(task as Map<String, dynamic>)).toList();
      } else {
        throw Exception('获取任务列表失败: HTTP ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('请求超时');
    } catch (e) {
      throw Exception('获取任务列表失败: $e');
    }
  }

  // ==========================================================================
  // 任务控制
  // ==========================================================================

  /// 取消任务
  /// 
  /// [taskId] 任务 ID
  Future<void> cancelTask(String taskId) async {
    try {
      final response = await _client
          .delete(
            Uri.parse('$_baseUrl/api/task/$taskId'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
            },
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        throw Exception('取消任务失败: HTTP ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('请求超时');
    } catch (e) {
      throw Exception('取消任务失败: $e');
    }
  }

  // ==========================================================================
  // 浏览器窗口控制
  // ==========================================================================

  /// 显示浏览器窗口（激活并置顶）
  Future<BrowserControlResult> showBrowser() async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/api/browser/show'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
            },
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return BrowserControlResult.fromJson(jsonData);
      } else {
        throw Exception('显示浏览器失败: HTTP ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('请求超时');
    } catch (e) {
      throw Exception('显示浏览器失败: $e');
    }
  }

  /// 隐藏浏览器窗口（最小化）
  Future<BrowserControlResult> hideBrowser() async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/api/browser/hide'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
            },
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return BrowserControlResult.fromJson(jsonData);
      } else {
        throw Exception('隐藏浏览器失败: HTTP ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('请求超时');
    } catch (e) {
      throw Exception('隐藏浏览器失败: $e');
    }
  }

  // ==========================================================================
  // 健康检查
  // ==========================================================================

  /// 检查 API 服务是否可用
  Future<bool> checkHealth() async {
    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl/health'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
            },
          )
          .timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 获取服务器信息
  Future<Map<String, dynamic>> getServerInfo() async {
    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl/'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
            },
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      } else {
        throw Exception('获取服务器信息失败: HTTP ${response.statusCode}');
      }
    } on TimeoutException {
      throw Exception('请求超时');
    } catch (e) {
      throw Exception('获取服务器信息失败: $e');
    }
  }

  // ==========================================================================
  // 资源清理
  // ==========================================================================

  /// 关闭客户端
  void dispose() {
    _client.close();
  }
}

// ============================================================================
// 全局单例（可选）
// ============================================================================

/// 全局 AIGC 自动化 API 客户端实例
/// 
/// 使用方式：
/// ```dart
/// final result = await aigcApiClient.viduText2Video(prompt: '一个赛博朋克风格的女孩');
/// ```
final AutomationApiClient aigcApiClient = AutomationApiClient();
