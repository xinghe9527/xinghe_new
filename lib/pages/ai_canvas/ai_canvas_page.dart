import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:xinghe_new/main.dart';
import 'package:window_manager/window_manager.dart';
import 'package:xinghe_new/core/widgets/window_border.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinghe_new/features/home/domain/voice_asset.dart';
import 'package:xinghe_new/features/home/presentation/settings_page.dart';
import 'package:xinghe_new/services/api/api_factory.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';
import 'package:xinghe_new/services/api/base/api_response.dart';
import 'package:xinghe_new/services/api/secure_storage_manager.dart';
import 'package:xinghe_new/services/api/providers/openai_service.dart';
import 'package:xinghe_new/core/logger/log_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:convert';
import 'dart:async';

/// GeekNow 图片模型列表（与设置界面保持一致）
class GeekNowImageModels {
  static const List<String> models = [
    // Gemini 图像生成系列
    'gemini-3-pro-image-preview',
    'gemini-3-pro-image-preview-lite',
    'gemini-2.5-flash-image-preview',
  ];
}

/// GeekNow 视频模型列表
class GeekNowVideoModels {
  static const List<String> models = [
    // VEO 系列
    'veo_3_1', 'veo_3_1-4K', 'veo_3_1-fast', 'veo_3_1-fast-4K',
    'veo_3_1-components', 'veo_3_1-components-4K',
    'veo_3_1-fast-components', 'veo_3_1-fast-components-4K',
    // Sora 系列
    'sora-2', 'sora-turbo',
    // Kling
    'kling-video-o1',
    // Doubao 系列
    'doubao-seedance-1-5-pro_480p',
    'doubao-seedance-1-5-pro_720p',
    'doubao-seedance-1-5-pro_1080p',
    // Grok
    'grok-video-3',
  ];
}

/// Yunwu（云雾）图片模型列表
class YunwuImageModels {
  static const List<String> models = [
    'gemini-2.5-flash-image-preview',
    'gemini-3-pro-image-preview',
    'gemini-3-pro-image-preview-lite',
  ];
}

/// Yunwu（云雾）视频模型列表
class YunwuVideoModels {
  static const List<String> models = [
    // Sora 系列
    'sora-2', 'sora-2-all', 'sora-2-pro',
    // VEO2 系列
    'veo2', 'veo2-fast', 'veo2-fast-frames', 'veo2-fast-components',
    'veo2-pro', 'veo2-pro-components',
    // VEO3 系列
    'veo3', 'veo3-fast', 'veo3-fast-frames', 'veo3-frames',
    'veo3-pro', 'veo3-pro-frames',
    // VEO3.1 系列
    'veo3.1', 'veo3.1-fast', 'veo3.1-pro', 'veo3.1-components',
  ];
}

class AiCanvasPage extends StatefulWidget {
  const AiCanvasPage({super.key});

  @override
  State<AiCanvasPage> createState() => _AiCanvasPageState();
}

class _AiCanvasPageState extends State<AiCanvasPage> with TickerProviderStateMixin {
  // 画布偏移和缩放
  Offset _canvasOffset = Offset.zero;
  double _scale = 1.0;
  
  // 节点列表
  final List<CanvasNode> _nodes = [];
  
  // 显示设置页面
  bool _showSettings = false;
  
  // 拖动状态
  Offset? _lastPanPosition;
  CanvasNode? _draggingNode;
  Offset? _draggingOffset;
  bool _isMiddleButtonPressed = false; // 中键按下状态
  DrawingStroke? _draggingStroke; // 拖动的涂鸦
  Offset? _draggingStrokeOffset; // 涂鸦拖动偏移
  
  // 选中的节点
  String? _selectedNodeId;
  final Set<String> _selectedNodeIds = {};
  
  // 当前工具
  CanvasTool _currentTool = CanvasTool.select;
  
  // 调整大小状态
  CanvasNode? _resizingNode;
  ResizeHandle? _resizeHandle;
  
  // 框选状态
  Offset? _selectionStart;
  Offset? _selectionEnd;
  
  // 文本框创建状态
  Offset? _textBoxStart;
  Offset? _textBoxEnd;
  bool _isCreatingTextBox = false;
  
  // 图片框创建状态
  Offset? _imageBoxStart;
  Offset? _imageBoxEnd;
  bool _isCreatingImageBox = false;
  
  // 视频框创建状态
  Offset? _videoBoxStart;
  Offset? _videoBoxEnd;
  bool _isCreatingVideoBox = false;
  
  // 画笔状态
  final List<DrawingStroke> _strokes = [];
  DrawingStroke? _currentStroke;
  DrawingStroke? _selectedStroke; // 选中的涂鸦
  Color _brushColor = Colors.black;
  double _brushSize = 3.0;
  bool _showBrushToolbar = false; // 画笔工具栏显示状态
  
  // 文本设置状态
  String _textFontFamily = 'Arial';
  double _textFontSize = 16.0;
  Color _textColor = Colors.black;
  bool _textBold = false;
  bool _textItalic = false;
  bool _textUnderline = false;
  bool _showTextToolbar = false; // 文本工具栏显示状态
  
  // 动画控制器
  late AnimationController _scaleAnimationController;
  late Animation<double> _scaleAnimation;
  
  // 缩放焦点（用于以鼠标为中心缩放）
  Offset? _zoomFocalPoint;
  double? _zoomStartScale;
  Offset? _zoomStartOffset;
  
  // 从画布选择状态
  bool _isSelectingFromCanvas = false;
  CanvasNode? _targetNodeForImage; // 目标节点（用于接收选择的图片）
  
  // 视频播放器控制器映射（使用 media_kit）
  final Map<String, Player> _videoPlayers = {};
  final Map<String, VideoController> _videoControllers = {};
  
  // API 服务商和模型
  String _imageProvider = 'geeknow';
  String _videoProvider = 'geeknow';
  List<String> _availableImageModels = GeekNowImageModels.models;
  List<String> _availableVideoModels = GeekNowVideoModels.models;
  
  // ComfyUI 工作流
  List<Map<String, dynamic>> _comfyUIWorkflows = [];
  
  // API 服务
  final SecureStorageManager _storage = SecureStorageManager();
  final LogManager _logger = LogManager();

  // 配色
  static const Color _bgColor = Color(0xFFF5F5F5); // 浅灰背景
  static const Color _toolbarBg = Colors.white;
  static const Color _cardBg = Colors.white;
  static const Color _accentBlue = Color(0xFF3B82F6);
  static const Color _borderColor = Color(0xFFE5E7EB);

  @override
  void initState() {
    super.initState();
    
    _scaleAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.0).animate(
      CurvedAnimation(parent: _scaleAnimationController, curve: Curves.easeOut),
    )..addListener(() {
      setState(() {
        final currentScale = _scaleAnimation.value;
        
        // 如果有焦点，以焦点为中心缩放
        if (_zoomFocalPoint != null && _zoomStartScale != null && _zoomStartOffset != null) {
          final scaleChange = currentScale / _zoomStartScale!;
          _canvasOffset = _zoomFocalPoint! - (_zoomFocalPoint! - _zoomStartOffset!) * scaleChange;
        }
        
        _scale = currentScale;
      });
    });
    
    // 加载 API 服务商配置
    _loadImageProvider();
    
    // 加载保存的画布数据
    _loadCanvasData();
  }

  @override
  void dispose() {
    // 保存画布数据
    _saveCanvasData();
    
    _scaleAnimationController.dispose();
    // 清理所有视频播放器
    for (var player in _videoPlayers.values) {
      player.dispose();
    }
    _videoPlayers.clear();
    _videoControllers.clear();
    super.dispose();
  }
  
  /// 从设置加载图片和视频服务商，并更新可用模型列表
  Future<void> _loadImageProvider() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final imageProvider = prefs.getString('image_provider') ?? 'geeknow';
      final videoProvider = prefs.getString('video_provider') ?? 'geeknow';
      
      // 加载 ComfyUI 工作流
      final workflowsJson = prefs.getString('comfyui_workflows');
      List<Map<String, dynamic>> workflows = [];
      if (workflowsJson != null && workflowsJson.isNotEmpty) {
        try {
          workflows = List<Map<String, dynamic>>.from(
            (jsonDecode(workflowsJson) as List).map((w) => Map<String, dynamic>.from(w as Map))
          );
        } catch (e) {
          debugPrint('解析 ComfyUI 工作流失败: $e');
        }
      }
      
      if (mounted) {
        setState(() {
          _imageProvider = imageProvider;
          _videoProvider = videoProvider;
          _comfyUIWorkflows = workflows;
          _availableImageModels = _getModelsForProvider(imageProvider, 'image');
          _availableVideoModels = _getModelsForProvider(videoProvider, 'video');
        });
      }
    } catch (e) {
      debugPrint('加载服务商配置失败: $e');
    }
  }
  
  /// 根据服务商和类型获取可用模型列表
  List<String> _getModelsForProvider(String provider, String modelType) {
    // ComfyUI 特殊处理：返回工作流列表
    if (provider.toLowerCase() == 'comfyui') {
      if (_comfyUIWorkflows.isEmpty) {
        return ['未配置工作流'];
      }
      // 根据类型过滤工作流
      final filteredWorkflows = _comfyUIWorkflows.where((w) {
        final type = w['type'] ?? 'image';
        return type == modelType;
      }).toList();
      
      if (filteredWorkflows.isEmpty) {
        return ['无${modelType == 'image' ? '图片' : '视频'}工作流'];
      }
      
      // 返回工作流名称或ID
      return filteredWorkflows.map((w) {
        return (w['name'] ?? w['id'] ?? '未命名工作流') as String;
      }).toList();
    }
    
    if (modelType == 'image') {
      // 图片模型
      switch (provider.toLowerCase()) {
        case 'geeknow':
          return GeekNowImageModels.models;
        case 'yunwu':
          return YunwuImageModels.models;
        case 'openai':
          return ['gpt-4o', 'gpt-4-turbo', 'dall-e-3', 'dall-e-2'];
        case 'gemini':
        case 'gemini-image':
          return ['gemini-3-pro-image-preview', 'gemini-2.5-flash-image', 'gemini-pro-vision'];
        case 'gemini-3-pro-image':
        case 'gemini-pro-image':
          return ['gemini-3-pro-image-preview', 'gemini-3-pro-image-preview-lite'];
        case 'midjourney':
        case 'mj':
          return ['midjourney-v6', 'midjourney-v5.2', 'midjourney-niji'];
        case 'deepseek':
          return []; // DeepSeek 不支持图片生成
        case 'aliyun':
        case 'qwen':
        case 'tongyi':
          return ['qwen-vl-plus', 'qwen-vl-max'];
        default:
          return ['DALL-E 3', 'Midjourney', 'Stable Diffusion'];
      }
    } else {
      // 视频模型
      switch (provider.toLowerCase()) {
        case 'geeknow':
          return GeekNowVideoModels.models;
        case 'yunwu':
          return YunwuVideoModels.models;
        case 'veo':
        case 'veo-video':
          return ['veo-2', 'veo-1'];
        case 'runway':
          return ['gen-3', 'gen-2'];
        case 'pika':
          return ['pika-1.0', 'pika-1.5'];
        default:
          return ['Sora', 'Runway', 'Pika'];
      }
    }
  }
  
  /// 根据名称获取 ComfyUI 工作流的完整信息
  Map<String, dynamic>? _getWorkflowByName(String name) {
    try {
      return _comfyUIWorkflows.firstWhere(
        (w) => (w['name'] ?? w['id']) == name,
        orElse: () => {},
      );
    } catch (e) {
      return null;
    }
  }
  
  /// 获取模型的简写名称（用于按钮显示）
  String _getShortModelName(String fullName, String provider) {
    // 非 ComfyUI 服务商，直接返回原名称
    if (provider.toLowerCase() != 'comfyui') {
      return fullName;
    }
    
    // ComfyUI 工作流名称简写规则
    // 如果名称长度小于等于 20 个字符，直接显示
    if (fullName.length <= 20) {
      return fullName;
    }
    
    // 尝试智能简写
    // 1. 如果包含 .json 后缀，去掉后缀
    String shortName = fullName.replaceAll('.json', '');
    
    // 2. 如果包含常见前缀（video-、image-、workflow-等），保留前缀+部分内容
    final prefixes = ['video-', 'image-', 'workflow-', 'video_', 'image_', 'workflow_'];
    for (final prefix in prefixes) {
      if (shortName.toLowerCase().startsWith(prefix)) {
        final remaining = shortName.substring(prefix.length);
        // 保留前缀 + 前10个字符 + ...
        if (remaining.length > 10) {
          return '$prefix${remaining.substring(0, 10)}...';
        }
        return shortName;
      }
    }
    
    // 3. 默认简写：前15个字符 + ...
    return '${shortName.substring(0, 15)}...';
  }
  
  /// 保存画布数据到本地
  Future<void> _saveCanvasData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 准备保存的数据
      final canvasData = {
        'offset': {'dx': _canvasOffset.dx, 'dy': _canvasOffset.dy},
        'scale': _scale,
        'nodes': _nodes.map((node) => {
          'id': node.id,
          'type': node.type.toString(),
          'position': {'dx': node.position.dx, 'dy': node.position.dy},
          'size': {'width': node.size.width, 'height': node.size.height},
          'data': node.data.map((key, value) {
            // 只保存可序列化的数据
            if (value is String || value is num || value is bool || value == null) {
              return MapEntry(key, value);
            }
            return MapEntry(key, value.toString());
          }),
        }).toList(),
        'strokes': _strokes.map((stroke) => {
          'points': stroke.points.map((p) => {'dx': p.dx, 'dy': p.dy}).toList(),
          'color': stroke.color.value,
          'strokeWidth': stroke.strokeWidth,
        }).toList(),
      };
      
      // 保存到 SharedPreferences
      await prefs.setString('canvas_data', jsonEncode(canvasData));
      debugPrint('✅ 画布数据已保存');
    } catch (e) {
      debugPrint('❌ 保存画布数据失败: $e');
    }
  }
  
  /// 从本地加载画布数据
  Future<void> _loadCanvasData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final canvasDataJson = prefs.getString('canvas_data');
      
      if (canvasDataJson == null || canvasDataJson.isEmpty) {
        debugPrint('没有保存的画布数据');
        return;
      }
      
      final canvasData = jsonDecode(canvasDataJson) as Map<String, dynamic>;
      
      // 恢复画布偏移和缩放
      final offset = canvasData['offset'] as Map<String, dynamic>?;
      if (offset != null) {
        _canvasOffset = Offset(offset['dx'] as double, offset['dy'] as double);
      }
      
      final scale = canvasData['scale'] as double?;
      if (scale != null) {
        _scale = scale;
      }
      
      // 恢复节点
      final nodes = canvasData['nodes'] as List<dynamic>?;
      if (nodes != null) {
        _nodes.clear();
        for (final nodeData in nodes) {
          final node = nodeData as Map<String, dynamic>;
          final typeStr = node['type'] as String;
          final type = NodeType.values.firstWhere(
            (t) => t.toString() == typeStr,
            orElse: () => NodeType.text,
          );
          
          final position = node['position'] as Map<String, dynamic>;
          final size = node['size'] as Map<String, dynamic>;
          final data = Map<String, dynamic>.from(node['data'] as Map);
          
          _nodes.add(CanvasNode(
            id: node['id'] as String,
            type: type,
            position: Offset(position['dx'] as double, position['dy'] as double),
            size: Size(size['width'] as double, size['height'] as double),
            data: data,
          ));
        }
      }
      
      // 恢复涂鸦
      final strokes = canvasData['strokes'] as List<dynamic>?;
      if (strokes != null) {
        _strokes.clear();
        for (final strokeData in strokes) {
          final stroke = strokeData as Map<String, dynamic>;
          final points = (stroke['points'] as List<dynamic>)
              .map((p) => Offset((p['dx'] as num).toDouble(), (p['dy'] as num).toDouble()))
              .toList();
          final color = Color(stroke['color'] as int);
          final strokeWidth = (stroke['strokeWidth'] as num).toDouble();
          
          _strokes.add(DrawingStroke(
            points: points,
            color: color,
            strokeWidth: strokeWidth,
          ));
        }
      }
      
      if (mounted) {
        setState(() {});
      }
      
      debugPrint('✅ 画布数据已加载');
      debugPrint('- 节点数量: ${_nodes.length}');
      debugPrint('- 涂鸦数量: ${_strokes.length}');
    } catch (e) {
      debugPrint('❌ 加载画布数据失败: $e');
    }
  }
  
  /// 自动保存的 setState 包装方法
  void _setStateAndSave(VoidCallback fn) {
    setState(fn);
    // 延迟保存，避免频繁保存
    Future.delayed(const Duration(milliseconds: 500), () {
      _saveCanvasData();
    });
  }
  
  /// 生成图片或视频内容
  Future<void> _generateContent(CanvasNode node) async {
    final isImage = node.type == NodeType.image;
    final provider = isImage ? _imageProvider : _videoProvider;
    final model = node.data['model'] ?? (isImage ? _availableImageModels.first : _availableVideoModels.first);
    final prompt = node.data['prompt'] ?? '';
    
    if (prompt.trim().isEmpty) {
      _showMessage('请输入提示词');
      return;
    }
    
    debugPrint('========== 开始生成 ==========');
    debugPrint('服务商: $provider');
    debugPrint('模型: $model');
    debugPrint('提示词: ${prompt.substring(0, prompt.length > 20 ? 20 : prompt.length)}');
    
    _logger.info('开始生成${isImage ? '图片' : '视频'}', module: 'AI画布', extra: {
      '服务商': provider,
      '模型': model,
      '提示词': prompt.substring(0, prompt.length > 20 ? 20 : prompt.length),
    });
    
    try {
      // 标记为生成中
      setState(() {
        node.data['isGenerating'] = true;
      });
      
      // 读取 API 配置
      final modelType = isImage ? 'image' : 'video';
      final baseUrl = await _storage.getBaseUrl(provider: provider, modelType: modelType);
      final apiKey = await _storage.getApiKey(provider: provider, modelType: modelType);
      
      if (baseUrl == null || apiKey == null) {
        throw Exception('未配置 $provider API');
      }
      
      final config = ApiConfig(provider: provider, baseUrl: baseUrl, apiKey: apiKey);
      final apiFactory = ApiFactory();
      final service = apiFactory.createService(provider, config);
      
      // 获取参考图片
      final referenceImages = node.data['referenceImages'] as List<String>? ?? [];
      
      debugPrint('========== 参考图片信息 ==========');
      debugPrint('node.data 包含的键: ${node.data.keys.toList()}');
      debugPrint('referenceImages 类型: ${node.data['referenceImages']?.runtimeType}');
      debugPrint('参考图片数量: ${referenceImages.length}');
      if (referenceImages.isNotEmpty) {
        for (int i = 0; i < referenceImages.length; i++) {
          debugPrint('参考图片 ${i + 1}: ${referenceImages[i]}');
        }
      } else {
        debugPrint('⚠️ 没有参考图片');
        debugPrint('⚠️ 检查是否正确添加了参考图片');
      }
      
      // 获取首尾帧图片（视频）
      final firstFrameImage = node.data['firstFrameImage'] as String?;
      final lastFrameImage = node.data['lastFrameImage'] as String?;
      
      // ✅ 将首尾帧图片添加到参考图片列表（用于传递给 API）
      final allReferenceImages = <String>[...referenceImages];
      if (firstFrameImage != null) {
        allReferenceImages.insert(0, firstFrameImage); // 首帧放在第一位
        debugPrint('✅ 添加首帧图片: $firstFrameImage');
      }
      if (lastFrameImage != null) {
        allReferenceImages.add(lastFrameImage); // 尾帧放在最后
        debugPrint('✅ 添加尾帧图片: $lastFrameImage');
      }
      
      debugPrint('最终传递的参考图片数量: ${allReferenceImages.length}');
      
      // 构建参数
      final parameters = <String, dynamic>{};
      
      if (isImage) {
        // 图片生成参数
        parameters['size'] = node.data['ratio'] ?? '1:1';
        parameters['quality'] = node.data['resolution'] ?? '1K';
      } else {
        // 视频生成参数
        parameters['duration'] = node.data['ratio'] ?? '5s';
        parameters['resolution'] = node.data['resolution'] ?? '1K';
        parameters['size'] = node.data['videoRatio'] ?? '16:9'; // 视频比例
        if (firstFrameImage != null) {
          parameters['first_frame'] = firstFrameImage;
        }
        if (lastFrameImage != null) {
          parameters['last_frame'] = lastFrameImage;
        }
      }
      
      // 调用 API 生成
      ApiResponse<dynamic> result;
      
      if (provider.toLowerCase() == 'comfyui') {
        // ComfyUI 需要传递工作流信息
        debugPrint('========== ComfyUI 工作流处理 ==========');
        debugPrint('节点类型: ${isImage ? "图片" : "视频"}');
        debugPrint('查找工作流: $model');
        debugPrint('可用工作流数量: ${_comfyUIWorkflows.length}');
        
        final workflow = _getWorkflowByName(model);
        
        if (workflow != null && workflow.isNotEmpty) {
          debugPrint('✅ 找到工作流: ${workflow['name'] ?? workflow['id']}');
          debugPrint('工作流ID: ${workflow['id']}');
          
          // 重要：将工作流信息传递给 API
          parameters['workflow'] = workflow['workflow'];
          parameters['workflow_id'] = workflow['id'];
          parameters['workflow_name'] = workflow['name'] ?? workflow['id'];
          
          debugPrint('传递参数:');
          debugPrint('  - workflow_id: ${workflow['id']}');
          debugPrint('  - workflow_name: ${workflow['name'] ?? workflow['id']}');
        } else {
          debugPrint('⚠️ 未找到工作流: $model');
          debugPrint('可用工作流列表:');
          for (var w in _comfyUIWorkflows) {
            debugPrint('  - ${w['name'] ?? w['id']}');
          }
          throw Exception('未找到工作流: $model');
        }
        
        debugPrint('调用 API - 模型参数: $model');
        
        // ✅ 根据节点类型调用不同的方法
        result = isImage
            ? await service.generateImages(
                prompt: prompt,
                model: model,
                referenceImages: allReferenceImages.isNotEmpty ? allReferenceImages : null,
                parameters: parameters,
              )
            : await service.generateVideos(
                prompt: prompt,
                model: model,
                referenceImages: allReferenceImages.isNotEmpty ? allReferenceImages : null,
                parameters: parameters,
              );
      } else if (service is OpenAIService && isImage) {
        result = await service.generateImagesByChat(
          prompt: prompt,
          model: model,
          referenceImagePaths: allReferenceImages.isNotEmpty ? allReferenceImages : null,
          parameters: parameters,
        );
      } else {
        result = isImage
            ? await service.generateImages(
                prompt: prompt,
                model: model,
                referenceImages: allReferenceImages.isNotEmpty ? allReferenceImages : null,
                parameters: parameters,
              )
            : await service.generateVideos(
                prompt: prompt,
                model: model,
                referenceImages: allReferenceImages.isNotEmpty ? allReferenceImages : null,
                parameters: parameters,
              );
      }
      
      // 处理结果
      if (result.isSuccess && result.data != null) {
        debugPrint('========== 处理生成结果 ==========');
        debugPrint('结果类型: ${result.data.runtimeType}');
        
        List<String> urls = [];
        
        // 处理不同的返回格式
        if (result.data is ChatImageResponse) {
          // OpenAI Chat API 格式
          urls = (result.data as ChatImageResponse).imageUrls;
          debugPrint('✅ ChatImageResponse 格式，获取到 ${urls.length} 个URL');
        } else if (result.data is List<ImageResponse>) {
          // 标准 ImageResponse 列表格式（ComfyUI 图片、Gemini 等）
          urls = (result.data as List<ImageResponse>)
              .map((img) => img.imageUrl)
              .toList();
          debugPrint('✅ List<ImageResponse> 格式，获取到 ${urls.length} 个URL');
        } else if (result.data is List<VideoResponse>) {
          // 标准 VideoResponse 列表格式（ComfyUI 视频等）
          urls = (result.data as List<VideoResponse>)
              .map((vid) => vid.videoUrl)
              .toList();
          debugPrint('✅ List<VideoResponse> 格式，获取到 ${urls.length} 个URL');
          for (int i = 0; i < urls.length; i++) {
            debugPrint('视频URL ${i + 1}: ${urls[i]}');
          }
        } else if (result.data is List) {
          // 通用列表格式
          debugPrint('⚠️ 通用 List 格式');
          urls = (result.data as List).map((item) {
            if (item is ImageResponse) {
              return item.imageUrl;
            } else if (item is VideoResponse) {
              return item.videoUrl;
            } else if (item is Map && item.containsKey('imageUrl')) {
              return item['imageUrl'] as String;
            } else if (item is Map && item.containsKey('videoUrl')) {
              return item['videoUrl'] as String;
            }
            return item.toString();
          }).toList();
          debugPrint('获取到 ${urls.length} 个URL');
        } else if (result.data is Map) {
          // 单个结果格式
          debugPrint('⚠️ Map 格式');
          if (result.data['imageUrl'] != null) {
            urls = [result.data['imageUrl']];
          } else if (result.data['videoUrl'] != null) {
            urls = [result.data['videoUrl']];
          }
        }
        
        if (urls.isNotEmpty) {
          debugPrint('准备下载第一个文件: ${urls.first}');
          _logger.info('获取到 ${urls.length} 个URL', module: 'AI画布', extra: {'第一个URL': urls.first});
          
          // 下载并保存文件
          final savedPath = await _downloadAndSaveFile(urls.first, isImage);
          
          debugPrint('下载结果: ${savedPath ?? "失败"}');
          
          if (savedPath != null) {
            debugPrint('✅ 准备更新节点状态');
            
            // 如果是视频，先清理旧的播放器
            if (!isImage) {
              debugPrint('清理旧的视频播放器...');
              final oldPlayer = _videoPlayers[node.id];
              final oldController = _videoControllers[node.id];
              if (oldPlayer != null) {
                try {
                  oldPlayer.dispose();
                  debugPrint('✅ 旧播放器已清理');
                } catch (e) {
                  debugPrint('清理旧播放器失败: $e');
                }
              }
              _videoPlayers.remove(node.id);
              _videoControllers.remove(node.id);
            }
            
            setState(() {
              if (isImage) {
                node.data['generatedImagePath'] = savedPath;
                node.data['_sizeAdjusted'] = false; // 重置标记，允许重新调整大小
                debugPrint('✅ 已设置 generatedImagePath: $savedPath');
              } else {
                node.data['generatedVideoPath'] = savedPath;
                node.data['_sizeAdjusted'] = false; // 重置标记，允许重新调整大小
                debugPrint('✅ 已设置 generatedVideoPath: $savedPath');
              }
              node.data['isGenerating'] = false;
            });
            
            // 立即调整节点大小以匹配生成的图片
            if (isImage) {
              _adjustNodeSizeToImage(node, savedPath);
            }
            
            // 自动保存
            _saveCanvasData();
            
            _logger.success('生成成功', module: 'AI画布', extra: {'文件': savedPath});
            _showMessage('生成成功！');
            debugPrint('========== 生成完成 ==========');
          } else {
            throw Exception('保存文件失败');
          }
        } else {
          throw Exception('未返回有效的URL');
        }
      } else {
        throw Exception(result.error ?? '生成失败');
      }
    } catch (e) {
      _logger.error('生成失败: $e', module: 'AI画布');
      setState(() {
        node.data['isGenerating'] = false;
      });
      _showMessage('生成失败: $e');
    }
  }
  
  /// 下载并保存文件
  Future<String?> _downloadAndSaveFile(String url, bool isImage) async {
    try {
      debugPrint('========== 下载文件 ==========');
      debugPrint('URL: $url');
      debugPrint('类型: ${isImage ? "图片" : "视频"}');
      
      _logger.info('开始下载文件', module: 'AI画布', extra: {'URL': url});
      
      final response = await http.get(Uri.parse(url));
      
      debugPrint('HTTP 状态码: ${response.statusCode}');
      debugPrint('内容长度: ${response.bodyBytes.length} bytes');
      
      _logger.info('HTTP响应', module: 'AI画布', extra: {
        '状态码': response.statusCode,
        '内容长度': response.bodyBytes.length,
      });
      
      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        // 优先使用画布空间保存路径
        final canvasSavePath = prefs.getString('canvas_save_path') ?? '';
        final savePath = canvasSavePath.isNotEmpty 
            ? canvasSavePath 
            : (prefs.getString(isImage ? 'image_save_path' : 'video_save_path') ?? '');
        final dir = Directory(savePath.isNotEmpty ? savePath : Directory.systemTemp.path);
        
        debugPrint('保存目录: ${dir.path}');
        debugPrint('使用画布空间保存路径: ${canvasSavePath.isNotEmpty}');
        
        if (!await dir.exists()) {
          await dir.create(recursive: true);
          _logger.info('创建保存目录', module: 'AI画布', extra: {'路径': dir.path});
        }
        
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final extension = isImage ? 'png' : 'mp4';
        final filename = 'canvas_${isImage ? 'image' : 'video'}_$timestamp.$extension';
        final file = File(path.join(dir.path, filename));
        
        debugPrint('保存文件: ${file.path}');
        
        await file.writeAsBytes(response.bodyBytes);
        
        debugPrint('✅ 文件保存成功');
        
        _logger.success('文件保存成功', module: 'AI画布', extra: {
          '路径': file.path,
          '大小': '${(response.bodyBytes.length / 1024).toStringAsFixed(2)} KB',
        });
        
        return file.path;
      } else {
        debugPrint('❌ HTTP请求失败: ${response.statusCode}');
        _logger.error('HTTP请求失败', module: 'AI画布', extra: {
          '状态码': response.statusCode,
          '响应': response.body.substring(0, response.body.length > 200 ? 200 : response.body.length),
        });
      }
    } catch (e, stackTrace) {
      debugPrint('❌ 下载文件异常: $e');
      debugPrint('堆栈: $stackTrace');
      _logger.error('下载文件失败: $e', module: 'AI画布');
    }
    return null;
  }
  
  /// 显示提示消息
  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
  
  /// 调整节点大小以匹配图片宽高比
  Future<void> _adjustNodeSizeToImage(CanvasNode node, String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        debugPrint('[调整大小] 文件不存在: $imagePath');
        return;
      }
      
      // 解码图片获取尺寸
      final bytes = await file.readAsBytes();
      final image = await decodeImageFromList(bytes);
      
      final imageWidth = image.width.toDouble();
      final imageHeight = image.height.toDouble();
      final aspectRatio = imageWidth / imageHeight;
      
      debugPrint('[调整大小] 图片尺寸: ${imageWidth.toInt()}x${imageHeight.toInt()}, 宽高比: ${aspectRatio.toStringAsFixed(2)}');
      
      // 保存宽高比信息，用于后续手动调整大小时保持比例
      node.data['_imageAspectRatio'] = aspectRatio;
      
      // 判断是生成的图片还是插入的图片
      final isGeneratedImage = node.data['generatedImagePath'] != null;
      
      // 计算新的节点尺寸（保持宽高比，不留白）
      double finalWidth, finalHeight;
      
      if (aspectRatio >= 1.0) {
        // 横图：宽度大于等于高度，以宽度为基准
        final baseWidth = isGeneratedImage ? 270.0 : 400.0; // 生成图片缩小到约 270px（400的2/3）
        finalWidth = baseWidth;
        finalHeight = baseWidth / aspectRatio;
        
        // 限制尺寸范围
        finalWidth = finalWidth.clamp(200.0, 4000.0);
        finalHeight = finalHeight.clamp(150.0, 4000.0);
      } else {
        // 竖图：高度大于宽度，以高度为基准
        final baseHeight = isGeneratedImage ? 270.0 : 400.0; // 生成图片缩小到约 270px（400的2/3）
        finalHeight = baseHeight;
        finalWidth = baseHeight * aspectRatio;
        
        // 限制尺寸范围
        finalHeight = finalHeight.clamp(200.0, 4000.0);
        finalWidth = finalWidth.clamp(150.0, 4000.0);
      }
      
      debugPrint('[调整大小] 节点尺寸: ${finalWidth.toInt()}x${finalHeight.toInt()}');
      
      if (mounted) {
        setState(() {
          node.size = Size(finalWidth, finalHeight);
          node.data['_sizeAdjusted'] = true; // 标记已调整
        });
        
        _logger.info('调整节点大小', module: 'AI画布', extra: {
          '图片尺寸': '${imageWidth.toInt()}x${imageHeight.toInt()}',
          '宽高比': aspectRatio.toStringAsFixed(2),
          '图片方向': aspectRatio >= 1.0 ? '横图' : '竖图',
          '节点尺寸': '${finalWidth.toInt()}x${finalHeight.toInt()}',
          '是否生成': isGeneratedImage,
        });
      }
    } catch (e) {
      debugPrint('[调整大小] 失败: $e');
      _logger.error('调整节点大小失败: $e', module: 'AI画布');
    }
  }

  void _smoothZoomTo(double targetScale, {Offset? focalPoint}) {
    targetScale = targetScale.clamp(0.1, 5.0); // 扩大缩放范围：0.1x 到 5x
    
    // 保存缩放起始状态
    _zoomStartScale = _scale;
    _zoomStartOffset = _canvasOffset;
    _zoomFocalPoint = focalPoint;
    
    _scaleAnimation = Tween<double>(
      begin: _scale,
      end: targetScale,
    ).animate(
      CurvedAnimation(parent: _scaleAnimationController, curve: Curves.easeOut),
    )..addListener(() {
      setState(() {
        final currentScale = _scaleAnimation.value;
        
        // 如果有焦点，以焦点为中心缩放
        if (_zoomFocalPoint != null && _zoomStartScale != null && _zoomStartOffset != null) {
          final scaleChange = currentScale / _zoomStartScale!;
          _canvasOffset = _zoomFocalPoint! - (_zoomFocalPoint! - _zoomStartOffset!) * scaleChange;
        }
        
        _scale = currentScale;
      });
    });
    
    _scaleAnimationController.forward(from: 0);
  }

  void _resetView() {
    setState(() {
      _canvasOffset = Offset.zero;
      _smoothZoomTo(1.0);
    });
  }

  void _selectNode(String? nodeId) {
    setState(() {
      _selectedNodeId = nodeId;
    });
  }
  
  /// 删除选中的元素（节点和涂鸦）
  void _deleteSelectedElements() {
    setState(() {
      // 删除选中的节点
      if (_selectedNodeId != null) {
        final nodeToRemove = _nodes.firstWhere(
          (node) => node.id == _selectedNodeId,
          orElse: () => _nodes.first, // 不会执行到这里
        );
        
        // 如果是视频节点，清理播放器
        if (nodeToRemove.type == NodeType.video) {
          _videoPlayers[nodeToRemove.id]?.dispose();
          _videoPlayers.remove(nodeToRemove.id);
          _videoControllers.remove(nodeToRemove.id);
        }
        
        _nodes.removeWhere((node) => node.id == _selectedNodeId);
        _selectedNodeId = null;
        
        debugPrint('删除节点');
      }
      
      // 删除选中的多个节点
      if (_selectedNodeIds.isNotEmpty) {
        final count = _selectedNodeIds.length;
        
        for (final nodeId in _selectedNodeIds) {
          final nodeToRemove = _nodes.firstWhere(
            (node) => node.id == nodeId,
            orElse: () => _nodes.first,
          );
          
          // 如果是视频节点，清理播放器
          if (nodeToRemove.type == NodeType.video) {
            _videoPlayers[nodeToRemove.id]?.dispose();
            _videoPlayers.remove(nodeToRemove.id);
            _videoControllers.remove(nodeToRemove.id);
          }
        }
        
        _nodes.removeWhere((node) => _selectedNodeIds.contains(node.id));
        _selectedNodeIds.clear();
        _selectedNodeId = null;
        
        debugPrint('删除多个节点: $count');
      }
      
      // 删除选中的涂鸦
      if (_selectedStroke != null) {
        _strokes.remove(_selectedStroke);
        _selectedStroke = null;
        
        debugPrint('删除涂鸦');
      }
    });
    
    // 自动保存
    _saveCanvasData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: _showSettings
          ? SettingsPage(onBack: () => setState(() => _showSettings = false))
          : Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                // 监听键盘事件
                if (event is KeyDownEvent) {
                  // 删除键：Delete 或 Backspace
                  if (event.logicalKey == LogicalKeyboardKey.delete ||
                      event.logicalKey == LogicalKeyboardKey.backspace) {
                    _deleteSelectedElements();
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: WindowBorder(
                child: Column(
                  children: [
                    _buildTitleBar(context),
                    Expanded(
                      child: Stack(
                        children: [
                          // 画布区域
                          Listener(
                            onPointerDown: (event) {
                              // 检测中键按下
                              if (event.buttons == 4) {
                                setState(() {
                                  _isMiddleButtonPressed = true;
                                  _lastPanPosition = event.localPosition;
                                });
                              }
                            },
                      onPointerUp: (event) {
                        setState(() {
                          _isMiddleButtonPressed = false;
                        });
                      },
                      onPointerMove: (event) {
                        // 中键拖动画布
                        if (_isMiddleButtonPressed && _lastPanPosition != null) {
                          setState(() {
                            final delta = event.localPosition - _lastPanPosition!;
                            _canvasOffset += delta;
                            _lastPanPosition = event.localPosition;
                          });
                        }
                      },
                      onPointerSignal: (event) {
                        if (event is PointerScrollEvent) {
                          final delta = event.scrollDelta.dy;
                          final newScale = _scale * (1 - delta / 1000);
                          _smoothZoomTo(newScale, focalPoint: event.localPosition);
                        }
                      },
                      child: GestureDetector(
                        onDoubleTap: _resetView,
                        onSecondaryTapDown: (details) {
                          // 右键菜单
                          if (_selectedStroke != null) {
                            _showStrokeContextMenu(details.globalPosition);
                          } else if (_selectedNodeId != null) {
                            final node = _nodes.firstWhere((n) => n.id == _selectedNodeId);
                            if (node.type == NodeType.text) {
                              _showTextNodeContextMenu(details.globalPosition, node);
                            }
                          }
                        },
                        onTapDown: (details) {
                          // 任何操作开始时，隐藏工具栏
                          if (_showBrushToolbar || _showTextToolbar) {
                            setState(() {
                              _showBrushToolbar = false;
                              _showTextToolbar = false;
                            });
                          }
                          
                          // 拖动画布工具
                          if (_currentTool == CanvasTool.pan) {
                            return;
                          }
                          
                          // 画笔工具：开始绘制
                          if (_currentTool == CanvasTool.draw) {
                            setState(() {
                              // 将屏幕坐标转换为画布坐标
                              final canvasPoint = Offset(
                                (details.localPosition.dx - _canvasOffset.dx) / _scale,
                                (details.localPosition.dy - _canvasOffset.dy) / _scale,
                              );
                              _currentStroke = DrawingStroke(
                                color: _brushColor,
                                strokeWidth: _brushSize,
                                points: [canvasPoint],
                              );
                            });
                            return;
                          }
                          
                          // 选择工具：检查是否点击到涂鸦
                          if (_currentTool == CanvasTool.select) {
                            for (var stroke in _strokes.reversed) {
                              if (_isPointNearStroke(details.localPosition, stroke)) {
                                setState(() {
                                  _selectedStroke = stroke;
                                  _selectNode(null);
                                });
                                return;
                              }
                            }
                          }
                          
                          // 点击空白处取消选择
                          bool hitNode = false;
                          for (var node in _nodes.reversed) {
                            final nodeRect = Rect.fromLTWH(
                              node.position.dx * _scale + _canvasOffset.dx,
                              node.position.dy * _scale + _canvasOffset.dy,
                              node.size.width * _scale,
                              node.size.height * _scale,
                            );
                            
                            if (nodeRect.contains(details.localPosition)) {
                              hitNode = true;
                              break;
                            }
                          }
                          
                          if (!hitNode && _currentTool == CanvasTool.select) {
                            _selectNode(null);
                            _selectedNodeIds.clear(); // 清除多选状态
                            _selectedStroke = null;
                          }
                        },
                        onPanStart: (details) {
                          // 任何拖动操作开始时，隐藏工具栏
                          if (_showBrushToolbar || _showTextToolbar) {
                            setState(() {
                              _showBrushToolbar = false;
                              _showTextToolbar = false;
                            });
                          }
                          
                          _lastPanPosition = details.localPosition;
                          
                          // 拖动画布工具
                          if (_currentTool == CanvasTool.pan) {
                            return;
                          }
                          
                          // 画笔工具：开始绘制
                          if (_currentTool == CanvasTool.draw) {
                            setState(() {
                              // 将屏幕坐标转换为画布坐标
                              final canvasPoint = Offset(
                                (details.localPosition.dx - _canvasOffset.dx) / _scale,
                                (details.localPosition.dy - _canvasOffset.dy) / _scale,
                              );
                              _currentStroke = DrawingStroke(
                                color: _brushColor,
                                strokeWidth: _brushSize,
                                points: [canvasPoint],
                              );
                            });
                            return;
                          }
                          
                          // 根据当前工具处理点击
                          if (_currentTool == CanvasTool.image) {
                            // 图片工具：开始拖动创建图片框
                            setState(() {
                              _isCreatingImageBox = true;
                              _imageBoxStart = details.localPosition;
                              _imageBoxEnd = details.localPosition;
                            });
                            return;
                          } else if (_currentTool == CanvasTool.video) {
                            // 视频工具：开始拖动创建视频框
                            setState(() {
                              _isCreatingVideoBox = true;
                              _videoBoxStart = details.localPosition;
                              _videoBoxEnd = details.localPosition;
                            });
                            return;
                          } else if (_currentTool == CanvasTool.text) {
                            // 文本工具：开始拖动创建文本框
                            setState(() {
                              _isCreatingTextBox = true;
                              _textBoxStart = details.localPosition;
                              _textBoxEnd = details.localPosition;
                            });
                            return;
                          }
                          
                          // 选择工具
                          if (_currentTool == CanvasTool.select) {
                            // 检查是否点击到涂鸦
                            for (var stroke in _strokes.reversed) {
                              if (_isPointNearStroke(details.localPosition, stroke)) {
                                setState(() {
                                  _selectedStroke = stroke;
                                  _draggingStroke = stroke;
                                  // 记录拖动开始时的画布坐标
                                  _draggingStrokeOffset = Offset(
                                    (details.localPosition.dx - _canvasOffset.dx) / _scale,
                                    (details.localPosition.dy - _canvasOffset.dy) / _scale,
                                  );
                                  _selectNode(null);
                                });
                                return;
                              }
                            }
                            
                            // 检查是否点击到节点或调整大小手柄
                            for (var node in _nodes.reversed) {
                              final nodeRect = Rect.fromLTWH(
                                node.position.dx * _scale + _canvasOffset.dx,
                                node.position.dy * _scale + _canvasOffset.dy,
                                node.size.width * _scale,
                                node.size.height * _scale,
                              );
                              
                              // 检查是否点击调整大小手柄（只有单选时才显示调整手柄）
                              if (_selectedNodeId == node.id && _selectedNodeIds.isEmpty) {
                                final handle = _getResizeHandle(details.localPosition, nodeRect);
                                if (handle != null) {
                                  _resizingNode = node;
                                  _resizeHandle = handle;
                                  return;
                                }
                              }
                              
                              if (nodeRect.contains(details.localPosition)) {
                                // 如果点击的节点在已选中的节点集合中，准备批量拖动
                                if (_selectedNodeIds.contains(node.id)) {
                                  _draggingNode = node;
                                  _draggingOffset = details.localPosition - nodeRect.topLeft;
                                  // 不改变选中状态，保持多选
                                  _selectedStroke = null;
                                  return;
                                }
                                
                                // 否则，单选该节点
                                _draggingNode = node;
                                _draggingOffset = details.localPosition - nodeRect.topLeft;
                                _selectNode(node.id);
                                _selectedNodeIds.clear(); // 清除多选状态
                                _selectedStroke = null;
                                return;
                              }
                            }
                            
                            // 没有点击到节点或涂鸦，开始框选
                            _selectionStart = details.localPosition;
                            _selectionEnd = details.localPosition;
                          }
                        },
                        onPanUpdate: (details) {
                          // 拖动画布工具 - 在 setState 外部处理以避免影响其他逻辑
                          if (_currentTool == CanvasTool.pan && _lastPanPosition != null) {
                            setState(() {
                              final delta = details.localPosition - _lastPanPosition!;
                              _canvasOffset += delta;
                              _lastPanPosition = details.localPosition;
                            });
                            return;
                          }
                          
                          setState(() {
                            // 画笔工具：继续绘制
                            if (_currentTool == CanvasTool.draw && _currentStroke != null) {
                              // 将屏幕坐标转换为画布坐标
                              final canvasPoint = Offset(
                                (details.localPosition.dx - _canvasOffset.dx) / _scale,
                                (details.localPosition.dy - _canvasOffset.dy) / _scale,
                              );
                              _currentStroke!.points.add(canvasPoint);
                              return;
                            }
                            
                            // 文本工具：拖动创建文本框
                            if (_isCreatingTextBox && _textBoxStart != null) {
                              _textBoxEnd = details.localPosition;
                              return;
                            }
                            
                            // 图片工具：拖动创建图片框
                            if (_isCreatingImageBox && _imageBoxStart != null) {
                              _imageBoxEnd = details.localPosition;
                              return;
                            }
                            
                            // 视频工具：拖动创建视频框
                            if (_isCreatingVideoBox && _videoBoxStart != null) {
                              _videoBoxEnd = details.localPosition;
                              return;
                            }
                            
                            // 框选
                            if (_currentTool == CanvasTool.select && _selectionStart != null && _draggingNode == null && _resizingNode == null) {
                              _selectionEnd = details.localPosition;
                              return;
                            }
                            
                            if (_resizingNode != null && _resizeHandle != null) {
                              // 调整大小
                              final delta = (details.localPosition - _lastPanPosition!) / _scale;
                              _lastPanPosition = details.localPosition;
                              
                              // 获取媒体路径以计算宽高比（图片或视频）
                              String? mediaPath;
                              if (_resizingNode!.type == NodeType.image) {
                                mediaPath = _resizingNode!.data['generatedImagePath'] ?? _resizingNode!.data['displayImagePath'];
                              } else if (_resizingNode!.type == NodeType.video) {
                                mediaPath = _resizingNode!.data['generatedVideoPath'] ?? _resizingNode!.data['displayVideoPath'];
                              }
                              
                              // 如果有媒体文件且有宽高比信息，按照宽高比调整；否则自由调整
                              if (mediaPath != null && _resizingNode!.data['_imageAspectRatio'] != null) {
                                final aspectRatio = _resizingNode!.data['_imageAspectRatio'] as double;
                                
                                // 计算保持宽高比的最小尺寸
                                // 如果宽高比 >= 1（横向），最小宽度100，最小高度 = 100/宽高比
                                // 如果宽高比 < 1（竖向），最小高度100，最小宽度 = 100*宽高比
                                double minWidth, minHeight;
                                if (aspectRatio >= 1.0) {
                                  // 横图：以最小宽度为基准
                                  minWidth = 100.0;
                                  minHeight = minWidth / aspectRatio;
                                } else {
                                  // 竖图：以最小高度为基准
                                  minHeight = 100.0;
                                  minWidth = minHeight * aspectRatio;
                                }
                                
                                // 最大尺寸同理
                                double maxWidth, maxHeight;
                                if (aspectRatio >= 1.0) {
                                  // 横图：以最大宽度为基准
                                  maxWidth = 4000.0;
                                  maxHeight = maxWidth / aspectRatio;
                                } else {
                                  // 竖图：以最大高度为基准
                                  maxHeight = 4000.0;
                                  maxWidth = maxHeight * aspectRatio;
                                }
                                
                                // 根据拖动方向计算新尺寸（保持宽高比）
                                double newWidth, newHeight;
                                
                                switch (_resizeHandle!) {
                                  case ResizeHandle.bottomRight:
                                    // 右下角：根据宽度变化计算
                                    newWidth = _resizingNode!.size.width + delta.dx;
                                    break;
                                  case ResizeHandle.topLeft:
                                    // 左上角：根据宽度变化计算（反向）
                                    newWidth = _resizingNode!.size.width - delta.dx;
                                    break;
                                  case ResizeHandle.bottomLeft:
                                    // 左下角：根据宽度变化计算（反向）
                                    newWidth = _resizingNode!.size.width - delta.dx;
                                    break;
                                  case ResizeHandle.topRight:
                                    // 右上角：根据宽度变化计算
                                    newWidth = _resizingNode!.size.width + delta.dx;
                                    break;
                                }
                                
                                // 限制宽度范围
                                newWidth = newWidth.clamp(minWidth, maxWidth);
                                
                                // 根据宽高比计算高度（这样可以保证宽高比不变）
                                newHeight = newWidth / aspectRatio;
                                
                                // 根据手柄位置调整节点位置
                                switch (_resizeHandle!) {
                                  case ResizeHandle.topLeft:
                                    // 左上角：需要调整位置
                                    final widthDiff = _resizingNode!.size.width - newWidth;
                                    final heightDiff = _resizingNode!.size.height - newHeight;
                                    _resizingNode!.position = Offset(
                                      _resizingNode!.position.dx + widthDiff,
                                      _resizingNode!.position.dy + heightDiff,
                                    );
                                    break;
                                  case ResizeHandle.topRight:
                                    // 右上角：需要调整Y位置
                                    final heightDiff = _resizingNode!.size.height - newHeight;
                                    _resizingNode!.position = Offset(
                                      _resizingNode!.position.dx,
                                      _resizingNode!.position.dy + heightDiff,
                                    );
                                    break;
                                  case ResizeHandle.bottomLeft:
                                    // 左下角：需要调整X位置
                                    final widthDiff = _resizingNode!.size.width - newWidth;
                                    _resizingNode!.position = Offset(
                                      _resizingNode!.position.dx + widthDiff,
                                      _resizingNode!.position.dy,
                                    );
                                    break;
                                  case ResizeHandle.bottomRight:
                                    // 右下角：不需要调整位置
                                    break;
                                }
                                
                                _resizingNode!.size = Size(newWidth, newHeight);
                              } else {
                                // 没有图片或没有宽高比信息，自由调整
                                switch (_resizeHandle!) {
                                  case ResizeHandle.bottomRight:
                                    _resizingNode!.size = Size(
                                      (_resizingNode!.size.width + delta.dx).clamp(100.0, 4000.0),
                                      (_resizingNode!.size.height + delta.dy).clamp(80.0, 4000.0),
                                    );
                                    break;
                                  case ResizeHandle.bottomLeft:
                                    final newWidth = (_resizingNode!.size.width - delta.dx).clamp(100.0, 4000.0);
                                    if (newWidth != _resizingNode!.size.width) {
                                      _resizingNode!.position = Offset(
                                        _resizingNode!.position.dx + delta.dx,
                                        _resizingNode!.position.dy,
                                      );
                                    }
                                    _resizingNode!.size = Size(
                                      newWidth,
                                      (_resizingNode!.size.height + delta.dy).clamp(80.0, 4000.0),
                                    );
                                    break;
                                  case ResizeHandle.topRight:
                                    final newHeight = (_resizingNode!.size.height - delta.dy).clamp(80.0, 4000.0);
                                    if (newHeight != _resizingNode!.size.height) {
                                      _resizingNode!.position = Offset(
                                        _resizingNode!.position.dx,
                                        _resizingNode!.position.dy + delta.dy,
                                      );
                                    }
                                    _resizingNode!.size = Size(
                                      (_resizingNode!.size.width + delta.dx).clamp(100.0, 4000.0),
                                      newHeight,
                                    );
                                    break;
                                  case ResizeHandle.topLeft:
                                    final newWidth = (_resizingNode!.size.width - delta.dx).clamp(100.0, 4000.0);
                                    final newHeight = (_resizingNode!.size.height - delta.dy).clamp(80.0, 4000.0);
                                    if (newWidth != _resizingNode!.size.width) {
                                      _resizingNode!.position = Offset(
                                        _resizingNode!.position.dx + delta.dx,
                                        _resizingNode!.position.dy,
                                      );
                                    }
                                    if (newHeight != _resizingNode!.size.height) {
                                      _resizingNode!.position = Offset(
                                        _resizingNode!.position.dx,
                                        _resizingNode!.position.dy + delta.dy,
                                      );
                                    }
                                    _resizingNode!.size = Size(newWidth, newHeight);
                                    break;
                                }
                              }
                            } else if (_draggingStroke != null && _draggingStrokeOffset != null) {
                              // 拖动涂鸦
                              final currentCanvasPoint = Offset(
                                (details.localPosition.dx - _canvasOffset.dx) / _scale,
                                (details.localPosition.dy - _canvasOffset.dy) / _scale,
                              );
                              final delta = currentCanvasPoint - _draggingStrokeOffset!;
                              
                              // 更新涂鸦所有点的位置
                              for (int i = 0; i < _draggingStroke!.points.length; i++) {
                                _draggingStroke!.points[i] += delta;
                              }
                              
                              _draggingStrokeOffset = currentCanvasPoint;
                            } else if (_draggingNode != null && _lastPanPosition != null) {
                              // 计算移动增量
                              final delta = (details.localPosition - _lastPanPosition!) / _scale;
                              _lastPanPosition = details.localPosition;
                              
                              // 如果有多个选中的节点，批量移动
                              if (_selectedNodeIds.isNotEmpty) {
                                for (var node in _nodes) {
                                  if (_selectedNodeIds.contains(node.id)) {
                                    node.position += delta;
                                  }
                                }
                              } else {
                                // 单个节点移动
                                _draggingNode!.position += delta;
                              }
                            }
                          });
                        },
                        onPanEnd: (details) {
                          // 文本框创建结束
                          if (_isCreatingTextBox && _textBoxStart != null && _textBoxEnd != null) {
                            final rect = Rect.fromPoints(_textBoxStart!, _textBoxEnd!);
                            final width = rect.width.abs().clamp(100.0, 4000.0);
                            final height = rect.height.abs().clamp(80.0, 4000.0);
                            
                            setState(() {
                              final newNode = CanvasNode(
                                id: DateTime.now().millisecondsSinceEpoch.toString(),
                                type: NodeType.text,
                                position: Offset(
                                  (rect.left - _canvasOffset.dx) / _scale,
                                  (rect.top - _canvasOffset.dy) / _scale,
                                ),
                                size: Size(width, height),
                                data: {
                                  'fontFamily': _textFontFamily,
                                  'fontSize': _textFontSize,
                                  'color': _textColor,
                                  'bold': _textBold,
                                  'italic': _textItalic,
                                  'underline': _textUnderline,
                                },
                              );
                              _nodes.add(newNode);
                              _selectNode(newNode.id);
                              
                              _isCreatingTextBox = false;
                              _textBoxStart = null;
                            });
                            
                            // 自动保存
                            _saveCanvasData();
                            
                            _textBoxEnd = null;
                            _currentTool = CanvasTool.select;
                            return;
                          }
                          
                          // 图片框创建结束
                          if (_isCreatingImageBox && _imageBoxStart != null && _imageBoxEnd != null) {
                            final rect = Rect.fromPoints(_imageBoxStart!, _imageBoxEnd!);
                            // 允许更小的尺寸，最小 100x100，最大 4000x4000
                            final width = rect.width.abs().clamp(100.0, 4000.0);
                            final height = rect.height.abs().clamp(100.0, 4000.0);
                            
                            setState(() {
                              final newNode = CanvasNode(
                                id: DateTime.now().millisecondsSinceEpoch.toString(),
                                type: NodeType.image,
                                position: Offset(
                                  (rect.left - _canvasOffset.dx) / _scale,
                                  (rect.top - _canvasOffset.dy) / _scale,
                                ),
                                size: Size(width, height),
                                data: {
                                  'model': _availableImageModels.isNotEmpty ? _availableImageModels.first : 'gemini-3-pro-image-preview',
                                },
                              );
                              _nodes.add(newNode);
                              _selectNode(newNode.id);
                              
                              _isCreatingImageBox = false;
                              _imageBoxStart = null;
                              _imageBoxEnd = null;
                              _currentTool = CanvasTool.select;
                            });
                            
                            // 自动保存
                            _saveCanvasData();
                            return;
                          }
                          
                          // 视频框创建结束
                          if (_isCreatingVideoBox && _videoBoxStart != null && _videoBoxEnd != null) {
                            final rect = Rect.fromPoints(_videoBoxStart!, _videoBoxEnd!);
                            // 允许更小的尺寸，最小 100x100，最大 4000x4000
                            final width = rect.width.abs().clamp(100.0, 4000.0);
                            final height = rect.height.abs().clamp(100.0, 4000.0);
                            
                            setState(() {
                              final newNode = CanvasNode(
                                id: DateTime.now().millisecondsSinceEpoch.toString(),
                                type: NodeType.video,
                                position: Offset(
                                  (rect.left - _canvasOffset.dx) / _scale,
                                  (rect.top - _canvasOffset.dy) / _scale,
                                ),
                                size: Size(width, height),
                                data: {
                                  'model': _availableVideoModels.isNotEmpty ? _availableVideoModels.first : 'veo_3_1',
                                },
                              );
                              _nodes.add(newNode);
                              _selectNode(newNode.id);
                              
                              _isCreatingVideoBox = false;
                              _videoBoxStart = null;
                              _videoBoxEnd = null;
                              _currentTool = CanvasTool.select;
                            });
                            
                            // 自动保存
                            _saveCanvasData();
                            return;
                          }
                          
                          // 画笔工具：完成绘制
                          if (_currentTool == CanvasTool.draw && _currentStroke != null) {
                            setState(() {
                              _strokes.add(_currentStroke!);
                              _currentStroke = null;
                            });
                            return;
                          }
                          
                          // 框选结束：选中框内的节点和涂鸦
                          if (_selectionStart != null && _selectionEnd != null) {
                            final selectionRect = Rect.fromPoints(_selectionStart!, _selectionEnd!);
                            _selectedNodeIds.clear();
                            
                            // 选中节点
                            for (var node in _nodes) {
                              final nodeRect = Rect.fromLTWH(
                                node.position.dx * _scale + _canvasOffset.dx,
                                node.position.dy * _scale + _canvasOffset.dy,
                                node.size.width * _scale,
                                node.size.height * _scale,
                              );
                              
                              if (selectionRect.overlaps(nodeRect)) {
                                _selectedNodeIds.add(node.id);
                              }
                            }
                            
                            // 选中涂鸦 - 需要将涂鸦的画布坐标转换为屏幕坐标
                            for (var stroke in _strokes) {
                              bool strokeInSelection = false;
                              for (var point in stroke.points) {
                                // 将画布坐标转换为屏幕坐标
                                final screenPoint = Offset(
                                  point.dx * _scale + _canvasOffset.dx,
                                  point.dy * _scale + _canvasOffset.dy,
                                );
                                if (selectionRect.contains(screenPoint)) {
                                  strokeInSelection = true;
                                  break;
                                }
                              }
                              
                              if (strokeInSelection) {
                                _selectedStroke = stroke;
                                break;
                              }
                            }
                            
                            setState(() {
                              _selectionStart = null;
                              _selectionEnd = null;
                              if (_selectedNodeIds.isNotEmpty) {
                                _selectedNodeId = _selectedNodeIds.first;
                              }
                            });
                            return;
                          }
                          
                          _draggingNode = null;
                          _draggingOffset = null;
                          _draggingStroke = null;
                          _draggingStrokeOffset = null;
                          _lastPanPosition = null;
                          _resizingNode = null;
                          _resizeHandle = null;
                        },
                        child: Container(
                          color: _bgColor,
                          child: Stack(
                            children: [
                              // 绘制涂鸦
                              CustomPaint(
                                painter: DrawingPainter(
                                  strokes: _strokes,
                                  currentStroke: _currentStroke,
                                  selectedStroke: _selectedStroke,
                                  canvasOffset: _canvasOffset,
                                  scale: _scale,
                                ),
                                child: Container(),
                              ),
                              
                              // 渲染节点
                              ..._nodes.map((node) {
                                final screenPos = Offset(
                                  node.position.dx * _scale + _canvasOffset.dx,
                                  node.position.dy * _scale + _canvasOffset.dy,
                                );
                                
                                return Positioned(
                                  left: screenPos.dx,
                                  top: screenPos.dy,
                                  child: Transform.scale(
                                    scale: _scale,
                                    alignment: Alignment.topLeft,
                                    child: _buildNodeCard(node),
                                  ),
                                );
                              }),
                              
                              // 框选矩形
                              if (_selectionStart != null && _selectionEnd != null)
                                CustomPaint(
                                  painter: SelectionBoxPainter(
                                    start: _selectionStart!,
                                    end: _selectionEnd!,
                                  ),
                                  child: Container(),
                                ),
                              
                              // 文本框创建预览
                              if (_isCreatingTextBox && _textBoxStart != null && _textBoxEnd != null)
                                CustomPaint(
                                  painter: SelectionBoxPainter(
                                    start: _textBoxStart!,
                                    end: _textBoxEnd!,
                                  ),
                                  child: Container(),
                                ),
                              
                              // 图片框创建预览
                              if (_isCreatingImageBox && _imageBoxStart != null && _imageBoxEnd != null)
                                CustomPaint(
                                  painter: SelectionBoxPainter(
                                    start: _imageBoxStart!,
                                    end: _imageBoxEnd!,
                                  ),
                                  child: Container(),
                                ),
                              
                              // 视频框创建预览
                              if (_isCreatingVideoBox && _videoBoxStart != null && _videoBoxEnd != null)
                                CustomPaint(
                                  painter: SelectionBoxPainter(
                                    start: _videoBoxStart!,
                                    end: _videoBoxEnd!,
                                  ),
                                  child: Container(),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // 左侧工具栏
                    Positioned(
                      left: 16,
                      top: 16,
                      child: _buildToolbar(),
                    ),
                    
                    // 画笔工具栏（当选择画笔工具且显示状态为true时显示）
                    if (_currentTool == CanvasTool.draw && _showBrushToolbar)
                      Positioned(
                        left: 88,
                        top: 16,
                        child: _buildBrushToolbar(),
                      ),
                    
                    // 文本工具栏（当选择文本工具且显示状态为true时显示）
                    if (_currentTool == CanvasTool.text && _showTextToolbar)
                      Positioned(
                        left: 88,
                        top: 16,
                        child: _buildTextToolbar(),
                      ),

                    // 右下角缩放控制
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: _buildZoomControls(),
                    ),

                    // 底部编辑面板（仅图片和视频需要，且不是仅显示节点）
                    if (_selectedNodeId != null)
                      () {
                        final node = _nodes.firstWhere((n) => n.id == _selectedNodeId);
                        final isDisplayOnly = node.data['isDisplayOnly'] == true;
                        
                        // 仅显示节点不显示编辑面板
                        if (isDisplayOnly) {
                          return const SizedBox.shrink();
                        }
                        
                        if (node.type == NodeType.image || node.type == NodeType.video) {
                          // 计算节点在屏幕上的位置
                          final nodeScreenPos = Offset(
                            node.position.dx * _scale + _canvasOffset.dx,
                            node.position.dy * _scale + _canvasOffset.dy,
                          );
                          final nodeScreenSize = Size(
                            node.size.width * _scale,
                            node.size.height * _scale,
                          );
                          
                          // 面板宽度
                          const panelWidth = 600.0;
                          
                          // 计算居中位置
                          final panelLeft = nodeScreenPos.dx + (nodeScreenSize.width - panelWidth) / 2;
                          
                          return Positioned(
                            left: panelLeft,
                            top: nodeScreenPos.dy + nodeScreenSize.height + 12,
                            child: _buildCompactEditPanel(node),
                          );
                        }
                        return const SizedBox.shrink();
                      }(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar(BuildContext context) {
    return Stack(
      children: [
        DragToMoveArea(
          child: Container(
            height: 32,
            color: AppTheme.scaffoldBackground,
            child: Center(
              child: Text(
                'R·O·S 动漫制作 - AI 画布',
                style: TextStyle(
                  color: AppTheme.subTextColor,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: Row(
            children: [
              // 设置按钮
              _WindowControlButton(
                icon: Icons.tune_rounded,
                onPressed: () {
                  setState(() {
                    _showSettings = !_showSettings;
                  });
                },
              ),
              _WindowControlButton(
                icon: Icons.minimize,
                onPressed: () => windowManager.minimize(),
              ),
              _WindowControlButton(
                icon: Icons.crop_square,
                onPressed: () async {
                  if (await windowManager.isMaximized()) {
                    windowManager.unmaximize();
                  } else {
                    windowManager.maximize();
                  }
                },
              ),
              _WindowControlButton(
                icon: Icons.close,
                isClose: true,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: _toolbarBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToolButton(Icons.near_me, "选择", CanvasTool.select),
          const SizedBox(height: 8),
          _buildToolButton(Icons.pan_tool, "拖动画布", CanvasTool.pan),
          const SizedBox(height: 8),
          // 插入媒体按钮
          _buildInsertMediaButton(),
          const SizedBox(height: 8),
          _buildToolButton(Icons.brush, "画笔", CanvasTool.draw),
          const SizedBox(height: 8),
          _buildToolButton(Icons.text_fields, "文本", CanvasTool.text),
          const SizedBox(height: 8),
          // 分隔线
          Container(
            width: 32,
            height: 1,
            color: _borderColor,
          ),
          const SizedBox(height: 8),
          _buildToolButton(Icons.image_outlined, "图片", CanvasTool.image),
          const SizedBox(height: 8),
          _buildToolButton(Icons.videocam_outlined, "视频", CanvasTool.video),
        ],
      ),
    );
  }
  
  // 插入媒体按钮
  Widget _buildInsertMediaButton() {
    return Tooltip(
      message: "插入媒体",
      child: InkWell(
        onTap: () {
          _showInsertMediaMenu();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.add,
            color: Colors.black87,
            size: 24,
          ),
        ),
      ),
    );
  }
  
  // 显示插入媒体菜单
  void _showInsertMediaMenu() {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx + 72, // 工具栏右侧
        position.dy + 120, // 按钮位置
        position.dx + 72,
        position.dy + 120,
      ),
      color: Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _borderColor, width: 1),
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'image',
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.image_outlined, size: 20, color: Colors.black87),
              const SizedBox(width: 12),
              const Text(
                "插入图片",
                style: TextStyle(fontSize: 14, color: Colors.black87),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'video',
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.videocam_outlined, size: 20, color: Colors.black87),
              const SizedBox(width: 12),
              const Text(
                "插入视频",
                style: TextStyle(fontSize: 14, color: Colors.black87),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        if (value == 'image') {
          _insertLocalImage();
        } else if (value == 'video') {
          _insertLocalVideo();
        }
      }
    });
  }
  
  // 插入本地图片
  Future<void> _insertLocalImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true, // 允许多选
      );
      
      if (result != null && result.files.isNotEmpty) {
        // 计算起始位置（屏幕中心偏左上）
        final screenCenterX = (MediaQuery.of(context).size.width / 2 - _canvasOffset.dx) / _scale - 300;
        final screenCenterY = (MediaQuery.of(context).size.height / 2 - _canvasOffset.dy) / _scale - 200;
        
        // 用于自动排列的变量
        double currentX = screenCenterX;
        double currentY = screenCenterY;
        double maxHeightInRow = 0;
        const spacing = 20.0; // 节点之间的间距
        const maxRowWidth = 1400.0; // 每行最大宽度
        
        final List<CanvasNode> newNodes = [];
        
        for (var file in result.files) {
          if (file.path == null) continue;
          
          final imagePath = file.path!;
          
          // 读取图片尺寸以计算合适的节点大小
          final imageFile = File(imagePath);
          final bytes = await imageFile.readAsBytes();
          final image = await decodeImageFromList(bytes);
          
          final imageWidth = image.width.toDouble();
          final imageHeight = image.height.toDouble();
          final aspectRatio = imageWidth / imageHeight;
          
          // 根据图片方向计算节点大小
          double nodeWidth, nodeHeight;
          
          if (aspectRatio >= 1.0) {
            // 横图：以宽度为基准
            const baseWidth = 400.0;
            nodeWidth = baseWidth;
            nodeHeight = baseWidth / aspectRatio;
          } else {
            // 竖图：以高度为基准
            const baseHeight = 400.0;
            nodeHeight = baseHeight;
            nodeWidth = baseHeight * aspectRatio;
          }
          
          // 限制尺寸范围
          nodeWidth = nodeWidth.clamp(100.0, 4000.0);
          nodeHeight = nodeHeight.clamp(100.0, 4000.0);
          
          // 检查是否需要换行
          if (currentX - screenCenterX + nodeWidth > maxRowWidth && newNodes.isNotEmpty) {
            // 换行
            currentX = screenCenterX;
            currentY += maxHeightInRow + spacing;
            maxHeightInRow = 0;
          }
          
          // 创建一个显示节点（不是生成节点）
          final newNode = CanvasNode(
            id: '${DateTime.now().millisecondsSinceEpoch}_${newNodes.length}',
            type: NodeType.image,
            position: Offset(currentX, currentY),
            size: Size(nodeWidth, nodeHeight),
            data: {
              'displayImagePath': imagePath, // 用于直接显示的图片
              'isDisplayOnly': true, // 标记为仅显示节点
              '_imageAspectRatio': aspectRatio, // 保存宽高比
              '_sizeAdjusted': true, // 标记已调整，避免重复调整
            },
          );
          
          newNodes.add(newNode);
          
          // 更新位置
          currentX += nodeWidth + spacing;
          maxHeightInRow = nodeHeight > maxHeightInRow ? nodeHeight : maxHeightInRow;
          
          _logger.info('插入图片 ${newNodes.length}/${result.files.length}', module: 'AI画布', extra: {
            '图片尺寸': '${imageWidth.toInt()}x${imageHeight.toInt()}',
            '宽高比': aspectRatio.toStringAsFixed(2),
            '节点尺寸': '${nodeWidth.toInt()}x${nodeHeight.toInt()}',
          });
        }
        
        // 批量添加节点
        if (newNodes.isNotEmpty) {
          setState(() {
            _nodes.addAll(newNodes);
            // 选中所有新添加的节点
            _selectedNodeIds.clear();
            _selectedNodeIds.addAll(newNodes.map((n) => n.id));
            _selectedNodeId = newNodes.first.id;
          });
          
          // 自动保存
          _saveCanvasData();
          
          _showMessage('成功插入 ${newNodes.length} 张图片');
        }
      }
    } catch (e) {
      print("插入图片失败: $e");
      _logger.error('插入图片失败: $e', module: 'AI画布');
      _showMessage('插入图片失败: $e');
    }
  }
  
  // 插入本地视频
  Future<void> _insertLocalVideo() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: true, // 允许多选
      );
      
      if (result != null && result.files.isNotEmpty) {
        debugPrint('========== 开始批量插入视频 ==========');
        debugPrint('选中视频数量: ${result.files.length}');
        
        // 计算起始位置（屏幕中心偏左上）
        final screenCenterX = (MediaQuery.of(context).size.width / 2 - _canvasOffset.dx) / _scale - 300;
        final screenCenterY = (MediaQuery.of(context).size.height / 2 - _canvasOffset.dy) / _scale - 200;
        
        // 用于自动排列的变量
        double currentX = screenCenterX;
        double currentY = screenCenterY;
        const defaultSize = 400.0; // 默认大小
        const spacing = 20.0; // 节点之间的间距
        const maxRowWidth = 1400.0; // 每行最大宽度
        
        final List<CanvasNode> newNodes = [];
        
        for (var file in result.files) {
          if (file.path == null) continue;
          
          final videoPath = file.path!;
          
          debugPrint('处理视频 ${newNodes.length + 1}/${result.files.length}: $videoPath');
          
          // 检查是否需要换行
          if (currentX - screenCenterX + defaultSize > maxRowWidth && newNodes.isNotEmpty) {
            // 换行
            currentX = screenCenterX;
            currentY += defaultSize + spacing;
          }
          
          // 创建一个显示节点（不是生成节点）
          final newNode = CanvasNode(
            id: '${DateTime.now().millisecondsSinceEpoch}_${newNodes.length}',
            type: NodeType.video,
            position: Offset(currentX, currentY),
            size: const Size(defaultSize, defaultSize),
            data: {
              'displayVideoPath': videoPath, // 用于直接显示的视频
              'isDisplayOnly': true, // 标记为仅显示节点
              '_sizeAdjusted': false, // 标记未调整，等待视频加载后调整
            },
          );
          
          newNodes.add(newNode);
          
          // 更新位置
          currentX += defaultSize + spacing;
          
          debugPrint('创建节点: 位置(${currentX.toInt()}, ${currentY.toInt()})');
        }
        
        debugPrint('========== 批量插入视频完成 ==========');
        
        // 批量添加节点
        if (newNodes.isNotEmpty) {
          setState(() {
            _nodes.addAll(newNodes);
            // 选中所有新添加的节点
            _selectedNodeIds.clear();
            _selectedNodeIds.addAll(newNodes.map((n) => n.id));
            _selectedNodeId = newNodes.first.id;
            
            // 延迟一帧后再初始化视频控制器，避免崩溃
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) {
                setState(() {});
              }
            });
          });
          
          // 自动保存
          _saveCanvasData();
          
          _showMessage('成功插入 ${newNodes.length} 个视频');
        }
      }
    } catch (e) {
      debugPrint("插入视频失败: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("插入视频失败: $e"), duration: const Duration(seconds: 3)),
      );
    }
  }

  Widget _buildToolButton(IconData icon, String tooltip, CanvasTool tool) {
    final isActive = _currentTool == tool;
    
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          setState(() {
            if (tool == CanvasTool.draw) {
              // 画笔工具：切换工具和工具栏显示
              if (_currentTool == CanvasTool.draw) {
                // 如果已经是画笔工具，只切换工具栏显示
                _showBrushToolbar = !_showBrushToolbar;
              } else {
                // 切换到画笔工具，显示工具栏
                _currentTool = tool;
                _showBrushToolbar = true;
                _showTextToolbar = false;
                _selectNode(null);
              }
            } else if (tool == CanvasTool.text) {
              // 文本工具：切换工具和工具栏显示
              if (_currentTool == CanvasTool.text) {
                // 如果已经是文本工具，只切换工具栏显示
                _showTextToolbar = !_showTextToolbar;
              } else {
                // 切换到文本工具，显示工具栏
                _currentTool = tool;
                _showTextToolbar = true;
                _showBrushToolbar = false;
                _selectNode(null);
              }
            } else {
              _currentTool = tool;
              _showBrushToolbar = false;
              _showTextToolbar = false;
              // 如果切换到非选择工具，取消选择
              if (tool != CanvasTool.select) {
                _selectNode(null);
                _selectedStroke = null;
              }
            }
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isActive ? _accentBlue.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isActive ? Border.all(color: _accentBlue, width: 2) : null,
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: isActive ? _accentBlue : Colors.black87,
            size: 22,
          ),
        ),
      ),
    );
  }
  
  // 画笔工具栏
  Widget _buildBrushToolbar() {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _toolbarBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "画笔设置",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          
          // 粗细调节
          Row(
            children: [
              const Text("粗细:", style: TextStyle(fontSize: 12)),
              Expanded(
                child: Slider(
                  value: _brushSize,
                  min: 1,
                  max: 20,
                  divisions: 19,
                  onChanged: (val) {
                    setState(() => _brushSize = val);
                  },
                ),
              ),
              Text("${_brushSize.toInt()}px", style: const TextStyle(fontSize: 11)),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // 颜色选择器
          const Text("颜色:", style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          
          // 渐变色带
          GestureDetector(
            onTapDown: (details) {
              final width = 248.0;
              final x = details.localPosition.dx.clamp(0.0, width);
              final hue = (x / width) * 360;
              setState(() {
                _brushColor = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
              });
            },
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: const LinearGradient(
                  colors: [
                    Colors.red,
                    Colors.yellow,
                    Colors.green,
                    Colors.cyan,
                    Colors.blue,
                    Colors.purple,
                    Colors.red,
                  ],
                ),
              ),
              child: Stack(
                children: [
                  // 当前颜色指示器
                  Positioned(
                    left: (HSVColor.fromColor(_brushColor).hue / 360) * 248 - 8,
                    top: -4,
                    child: Container(
                      width: 16,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: Colors.black26, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // 亮度调节
          GestureDetector(
            onTapDown: (details) {
              final width = 248.0;
              final x = details.localPosition.dx.clamp(0.0, width);
              final brightness = x / width;
              final hsv = HSVColor.fromColor(_brushColor);
              setState(() {
                _brushColor = hsv.withValue(brightness).toColor();
              });
            },
            child: Container(
              height: 24,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: LinearGradient(
                  colors: [
                    Colors.black,
                    HSVColor.fromColor(_brushColor).withValue(1.0).toColor(),
                  ],
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // 当前颜色预览
          Row(
            children: [
              const Text("当前:", style: TextStyle(fontSize: 12)),
              const SizedBox(width: 8),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _brushColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _borderColor, width: 2),
                ),
              ),
              const Spacer(),
              // 清除按钮
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _strokes.clear();
                  });
                },
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text("清除", style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildZoomControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _toolbarBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove, size: 16),
            onPressed: () => _smoothZoomTo(_scale - 0.1),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          Text(
            "${(_scale * 100).toInt()}%",
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            onPressed: () => _smoothZoomTo(_scale + 0.1),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }


  Widget _buildNodeCard(CanvasNode node) {
    final isSelected = _selectedNodeId == node.id || _selectedNodeIds.contains(node.id);
    
    return Stack(
      children: [
        GestureDetector(
          onTap: () {
            // 如果正在从画布选择参考图片或首尾帧
            if (_isSelectingFromCanvas && _targetNodeForImage != null) {
              // 只能选择图片节点
              if (node.type == NodeType.image && node.data['generatedImagePath'] != null) {
                final selectingFrameType = _targetNodeForImage!.data['_selectingFrameType'];
                
                if (selectingFrameType != null) {
                  // 选择首帧或尾帧
                  setState(() {
                    if (selectingFrameType == 'first') {
                      _targetNodeForImage!.data['firstFrameImage'] = node.data['generatedImagePath'];
                    } else {
                      _targetNodeForImage!.data['lastFrameImage'] = node.data['generatedImagePath'];
                    }
                    _targetNodeForImage!.data.remove('_selectingFrameType');
                    _isSelectingFromCanvas = false;
                    _selectNode(_targetNodeForImage!.id);
                    _targetNodeForImage = null;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("已设置${selectingFrameType == 'first' ? '首帧' : '尾帧'}图片"),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                } else {
                  // 选择参考图片
                  setState(() {
                    // 初始化参考图片列表
                    if (_targetNodeForImage!.data['referenceImages'] == null) {
                      _targetNodeForImage!.data['referenceImages'] = <String>[];
                    }
                    // 添加到参考图片列表
                    final imagePath = node.data['generatedImagePath'];
                    (_targetNodeForImage!.data['referenceImages'] as List<String>).add(imagePath);
                    
                    debugPrint('========== 从画布添加参考图片 ==========');
                    debugPrint('目标节点ID: ${_targetNodeForImage!.id}');
                    debugPrint('添加的图片路径: $imagePath');
                    debugPrint('当前参考图片总数: ${(_targetNodeForImage!.data['referenceImages'] as List).length}');
                    
                    _isSelectingFromCanvas = false;
                    _selectNode(_targetNodeForImage!.id);
                    _targetNodeForImage = null;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("已添加参考图片"), duration: Duration(seconds: 1)),
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("请选择包含生成图片的节点"), duration: Duration(seconds: 1)),
                );
              }
            } else {
              _selectNode(node.id);
            }
          },
          onDoubleTap: () {
            // 双击文本框进入编辑模式
            if (node.type == NodeType.text) {
              setState(() {
                node.data['isEditing'] = true;
              });
            }
          },
          child: Container(
            width: node.size.width,
            height: node.size.height,
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(8),
              border: isSelected 
                  ? Border.all(color: _accentBlue, width: 2)
                  : (_isSelectingFromCanvas && node.type == NodeType.image 
                      ? Border.all(color: Colors.green, width: 2)
                      : null), // 不选中时无边框，更自然
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isSelected ? 0.15 : 0.08),
                  blurRadius: isSelected ? 16 : 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _buildNodeContent(node),
          ),
        ),
        
        // 调整大小手柄（只在单选时显示）
        if (isSelected && _selectedNodeIds.isEmpty) ...[
          _buildResizeHandle(node, ResizeHandle.topLeft),
          _buildResizeHandle(node, ResizeHandle.topRight),
          _buildResizeHandle(node, ResizeHandle.bottomLeft),
          _buildResizeHandle(node, ResizeHandle.bottomRight),
        ],
      ],
    );
  }
  
  Widget _buildResizeHandle(CanvasNode node, ResizeHandle handle) {
    double left = 0, top = 0;
    SystemMouseCursor cursor = SystemMouseCursors.resizeUpLeftDownRight;
    
    switch (handle) {
      case ResizeHandle.topLeft:
        left = -6;
        top = -6;
        cursor = SystemMouseCursors.resizeUpLeftDownRight; // ↖↘
        break;
      case ResizeHandle.topRight:
        left = node.size.width - 6;
        top = -6;
        cursor = SystemMouseCursors.resizeUpRightDownLeft; // ↗↙
        break;
      case ResizeHandle.bottomLeft:
        left = -6;
        top = node.size.height - 6;
        cursor = SystemMouseCursors.resizeUpRightDownLeft; // ↗↙
        break;
      case ResizeHandle.bottomRight:
        left = node.size.width - 6;
        top = node.size.height - 6;
        cursor = SystemMouseCursors.resizeUpLeftDownRight; // ↖↘
        break;
    }
    
    return Positioned(
      left: left,
      top: top,
      child: MouseRegion(
        cursor: cursor, // 设置鼠标指针样式
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: _accentBlue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  ResizeHandle? _getResizeHandle(Offset position, Rect nodeRect) {
    const handleSize = 16.0;
    
    final handles = {
      ResizeHandle.topLeft: Rect.fromLTWH(
        nodeRect.left - handleSize / 2,
        nodeRect.top - handleSize / 2,
        handleSize,
        handleSize,
      ),
      ResizeHandle.topRight: Rect.fromLTWH(
        nodeRect.right - handleSize / 2,
        nodeRect.top - handleSize / 2,
        handleSize,
        handleSize,
      ),
      ResizeHandle.bottomLeft: Rect.fromLTWH(
        nodeRect.left - handleSize / 2,
        nodeRect.bottom - handleSize / 2,
        handleSize,
        handleSize,
      ),
      ResizeHandle.bottomRight: Rect.fromLTWH(
        nodeRect.right - handleSize / 2,
        nodeRect.bottom - handleSize / 2,
        handleSize,
        handleSize,
      ),
    };
    
    for (var entry in handles.entries) {
      if (entry.value.contains(position)) {
        return entry.key;
      }
    }
    
    return null;
  }

  Widget _buildNodeContent(CanvasNode node) {
    switch (node.type) {
      case NodeType.image:
        return _buildImageNode(node);
      case NodeType.video:
        return _buildVideoNode(node);
      case NodeType.text:
        return _buildTextNode(node);
    }
  }

  Widget _buildImageNode(CanvasNode node) {
    // 检查是否是直接显示的图片
    final displayImagePath = node.data['displayImagePath'];
    if (displayImagePath != null && displayImagePath is String) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(displayImagePath),
          fit: BoxFit.contain, // 使用 contain 完整显示图片
          errorBuilder: (context, error, stackTrace) {
            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 8),
                  Text(
                    "图片加载失败",
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            );
          },
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) {
              // 图片加载完成，调整节点大小以匹配图片宽高比
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _adjustNodeSizeToImage(node, displayImagePath);
              });
              return child;
            }
            return frame == null
                ? const Center(child: CircularProgressIndicator())
                : child;
          },
        ),
      );
    }
    
    // 优先显示生成的图片，而不是参考图片
    final generatedImagePath = node.data['generatedImagePath'];
    
    if (generatedImagePath != null && generatedImagePath is String) {
      // 显示API生成的图片
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(generatedImagePath),
          fit: BoxFit.contain, // 使用 contain 完整显示图片
          errorBuilder: (context, error, stackTrace) {
            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 8),
                  Text(
                    "图片加载失败",
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),
            );
          },
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            // 对于生成的图片，我们在生成成功后已经调整过大小了
            // 这里只处理异步加载的情况
            if (!wasSynchronouslyLoaded && frame != null) {
              // 异步加载完成，检查是否需要调整大小
              if (node.data['_sizeAdjusted'] != true) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _adjustNodeSizeToImage(node, generatedImagePath);
                });
              }
            }
            return frame == null
                ? const Center(child: CircularProgressIndicator())
                : child;
          },
        ),
      );
    }
    
    // 默认占位符（等待生成）
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 8),
          Text(
            "等待生成图片",
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoNode(CanvasNode node) {
    // 优先显示生成的视频，其次是直接显示的视频
    final generatedVideoPath = node.data['generatedVideoPath'];
    final displayVideoPath = node.data['displayVideoPath'];
    final videoPath = (generatedVideoPath != null && generatedVideoPath is String) 
        ? generatedVideoPath 
        : displayVideoPath;
    
    if (videoPath != null && videoPath is String) {
      debugPrint('========== 渲染视频节点 ==========');
      debugPrint('节点ID: ${node.id}');
      debugPrint('视频路径: $videoPath');
      debugPrint('是否为生成的视频: ${generatedVideoPath != null}');
      
      // 获取或创建视频播放器
      if (!_videoPlayers.containsKey(node.id)) {
        debugPrint('创建新的视频播放器...');
        try {
          final player = Player();
          final controller = VideoController(player);
          
          _videoPlayers[node.id] = player;
          _videoControllers[node.id] = controller;
          
          // 打开视频文件
          debugPrint('打开视频文件: $videoPath');
          player.open(Media(videoPath), play: false);
          player.setPlaylistMode(PlaylistMode.loop);
          
          // 监听视频尺寸变化，自动调整节点大小
          player.stream.width.listen((width) {
            if (width != null && width > 0 && node.data['_sizeAdjusted'] != true) {
              final height = player.state.height;
              if (height != null && height > 0) {
                debugPrint('视频尺寸已加载: ${width}x$height');
                _adjustVideoNodeSize(node, width.toDouble(), height.toDouble());
              }
            }
          });
          
          debugPrint('✅ 视频播放器创建成功');
        } catch (e) {
          debugPrint('❌ 创建视频播放器失败: $e');
          return _buildVideoErrorWidget();
        }
      } else {
        debugPrint('使用现有的视频播放器');
      }
      
      final player = _videoPlayers[node.id];
      final controller = _videoControllers[node.id];
      
      // 如果播放器不存在，显示错误
      if (player == null || controller == null) {
        debugPrint('❌ 播放器或控制器为空');
        return _buildVideoErrorWidget();
      }
      
      debugPrint('✅ 渲染视频播放器');
      
      // 显示视频播放器
      return MouseRegion(
        onEnter: (_) {
          // 鼠标进入时播放
          try {
            player.play();
          } catch (e) {
            debugPrint('播放视频失败: $e');
          }
        },
        onExit: (_) {
          // 鼠标离开时暂停
          try {
            player.pause();
          } catch (e) {
            debugPrint('暂停视频失败: $e');
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: node.size.width,
            height: node.size.height,
            child: Video(
              controller: controller,
              controls: NoVideoControls,
              fit: BoxFit.contain, // 完整显示视频，不裁剪
            ),
          ),
        ),
      );
    }
    
    // 默认占位符
    debugPrint('显示视频占位符（节点ID: ${node.id}）');
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.videocam_outlined, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 8),
          Text(
            "视频",
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }
  
  /// 调整视频节点大小以匹配视频宽高比
  void _adjustVideoNodeSize(CanvasNode node, double videoWidth, double videoHeight) {
    if (node.data['_sizeAdjusted'] == true) {
      return; // 已经调整过了
    }
    
    final aspectRatio = videoWidth / videoHeight;
    
    debugPrint('========== 调整视频节点大小 ==========');
    debugPrint('视频尺寸: ${videoWidth.toInt()}x${videoHeight.toInt()}');
    debugPrint('宽高比: ${aspectRatio.toStringAsFixed(4)}');
    debugPrint('视频方向: ${aspectRatio >= 1.0 ? '横向' : '竖向'}');
    
    // 根据视频方向计算节点大小
    double nodeWidth, nodeHeight;
    
    if (aspectRatio >= 1.0) {
      // 横向视频：以宽度为基准
      const baseWidth = 400.0;
      nodeWidth = baseWidth;
      nodeHeight = baseWidth / aspectRatio;
      
      // 如果高度超出范围，按比例缩放
      if (nodeHeight > 800.0) {
        nodeHeight = 800.0;
        nodeWidth = nodeHeight * aspectRatio;
      } else if (nodeHeight < 200.0) {
        nodeHeight = 200.0;
        nodeWidth = nodeHeight * aspectRatio;
      }
    } else {
      // 竖向视频：以高度为基准
      const baseHeight = 400.0;
      nodeHeight = baseHeight;
      nodeWidth = baseHeight * aspectRatio;
      
      // 如果宽度超出范围，按比例缩放
      if (nodeWidth > 800.0) {
        nodeWidth = 800.0;
        nodeHeight = nodeWidth / aspectRatio;
      } else if (nodeWidth < 200.0) {
        nodeWidth = 200.0;
        nodeHeight = nodeWidth / aspectRatio;
      }
    }
    
    // 最终确保在范围内（保持宽高比）
    if (nodeWidth > 800.0) {
      nodeWidth = 800.0;
      nodeHeight = nodeWidth / aspectRatio;
    }
    if (nodeHeight > 800.0) {
      nodeHeight = 800.0;
      nodeWidth = nodeHeight * aspectRatio;
    }
    
    debugPrint('最终节点尺寸: ${nodeWidth.toInt()}x${nodeHeight.toInt()}');
    debugPrint('节点宽高比: ${(nodeWidth / nodeHeight).toStringAsFixed(4)}');
    debugPrint('========== 调整完成 ==========');
    
    if (mounted) {
      setState(() {
        node.size = Size(nodeWidth, nodeHeight);
        node.data['_imageAspectRatio'] = aspectRatio;
        node.data['_sizeAdjusted'] = true;
      });
    }
  }
  
  // 视频错误显示组件
  Widget _buildVideoErrorWidget() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
          const SizedBox(height: 8),
          Text(
            "视频加载失败",
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildTextNode(CanvasNode node) {
    // 获取文本样式设置
    final fontFamily = node.data['fontFamily'] ?? _textFontFamily;
    final fontSize = node.data['fontSize'] ?? _textFontSize;
    final color = node.data['color'] ?? _textColor;
    final bold = node.data['bold'] ?? _textBold;
    final italic = node.data['italic'] ?? _textItalic;
    final underline = node.data['underline'] ?? _textUnderline;
    
    // 检查是否处于编辑模式
    final isEditing = node.data['isEditing'] ?? false;
    
    if (!isEditing) {
      // 非编辑模式：显示文本，双击进入编辑
      return GestureDetector(
        onDoubleTap: () {
          setState(() {
            node.data['isEditing'] = true;
          });
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          alignment: Alignment.topLeft,
          child: Text(
            node.data['text']?.isEmpty ?? true ? "双击编辑文本..." : node.data['text'],
            style: TextStyle(
              fontSize: fontSize,
              color: node.data['text']?.isEmpty ?? true ? Colors.black26 : color,
              fontFamily: fontFamily,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              decoration: underline ? TextDecoration.underline : TextDecoration.none,
            ),
          ),
        ),
      );
    }
    
    // 编辑模式：显示输入框
    return TextField(
      controller: TextEditingController(text: node.data['text'] ?? ''),
      onChanged: (val) {
        node.data['text'] = val;
      },
      onTapOutside: (event) {
        // 点击外部时退出编辑模式
        setState(() {
          node.data['isEditing'] = false;
        });
      },
      autofocus: true,
      maxLines: null,
      style: TextStyle(
        fontSize: fontSize,
        color: color,
        fontFamily: fontFamily,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        decoration: underline ? TextDecoration.underline : TextDecoration.none,
      ),
      decoration: const InputDecoration(
        border: InputBorder.none,
        hintText: "输入文本...",
        hintStyle: TextStyle(color: Colors.black26),
        contentPadding: EdgeInsets.all(12),
      ),
    );
  }
  
  // 文本工具栏
  Widget _buildTextToolbar() {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _toolbarBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "文本设置",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          
          // 字体和字号选择
          Row(
            children: [
              // 字体选择
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("字体", style: TextStyle(fontSize: 11, color: Colors.black54)),
                    const SizedBox(height: 4),
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: _borderColor),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _textFontFamily,
                          isExpanded: true,
                          icon: const Icon(Icons.arrow_drop_down, size: 20),
                          style: const TextStyle(fontSize: 13, color: Colors.black87),
                          dropdownColor: Colors.white,
                          items: ['Arial', 'Times New Roman', 'Courier New', 'Georgia', 'Verdana']
                              .map((font) => DropdownMenuItem(
                                    value: font,
                                    child: Text(font),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _textFontFamily = val);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 字号选择
              Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("字号", style: TextStyle(fontSize: 11, color: Colors.black54)),
                    const SizedBox(height: 4),
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: _borderColor),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<double>(
                          value: _textFontSize,
                          isExpanded: true,
                          icon: const Icon(Icons.arrow_drop_down, size: 20),
                          style: const TextStyle(fontSize: 13, color: Colors.black87),
                          dropdownColor: Colors.white,
                          items: [8.0, 10.0, 12.0, 14.0, 16.0, 18.0, 20.0, 24.0, 28.0, 32.0, 36.0, 48.0, 60.0, 72.0]
                              .map((size) => DropdownMenuItem(
                                    value: size,
                                    child: Text("${size.toInt()}"),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _textFontSize = val);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // 文本样式按钮
          Row(
            children: [
              const Text("样式:", style: TextStyle(fontSize: 12)),
              const SizedBox(width: 8),
              _buildStyleButton(Icons.format_bold, "粗体", _textBold, () {
                setState(() => _textBold = !_textBold);
              }),
              const SizedBox(width: 4),
              _buildStyleButton(Icons.format_italic, "斜体", _textItalic, () {
                setState(() => _textItalic = !_textItalic);
              }),
              const SizedBox(width: 4),
              _buildStyleButton(Icons.format_underline, "下划线", _textUnderline, () {
                setState(() => _textUnderline = !_textUnderline);
              }),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // 颜色选择
          const Text("颜色:", style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          
          // 渐变色带
          GestureDetector(
            onTapDown: (details) {
              final width = 288.0;
              final x = details.localPosition.dx.clamp(0.0, width);
              final hue = (x / width) * 360;
              setState(() {
                _textColor = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
              });
            },
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: const LinearGradient(
                  colors: [
                    Colors.red,
                    Colors.yellow,
                    Colors.green,
                    Colors.cyan,
                    Colors.blue,
                    Colors.purple,
                    Colors.red,
                  ],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: (HSVColor.fromColor(_textColor).hue / 360) * 288 - 8,
                    top: -4,
                    child: Container(
                      width: 16,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: Colors.black26, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // 亮度调节
          GestureDetector(
            onTapDown: (details) {
              final width = 288.0;
              final x = details.localPosition.dx.clamp(0.0, width);
              final brightness = x / width;
              final hsv = HSVColor.fromColor(_textColor);
              setState(() {
                _textColor = hsv.withValue(brightness).toColor();
              });
            },
            child: Container(
              height: 24,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: LinearGradient(
                  colors: [
                    Colors.black,
                    HSVColor.fromColor(_textColor).withValue(1.0).toColor(),
                  ],
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // 当前颜色预览
          Row(
            children: [
              const Text("当前:", style: TextStyle(fontSize: 12)),
              const SizedBox(width: 8),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _textColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _borderColor, width: 2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildStyleButton(IconData icon, String tooltip, bool isActive, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isActive ? _accentBlue.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: isActive ? Border.all(color: _accentBlue, width: 1.5) : null,
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 18,
            color: isActive ? _accentBlue : Colors.black54,
          ),
        ),
      ),
    );
  }
  
  // 检测点是否靠近涂鸦
  bool _isPointNearStroke(Offset screenPoint, DrawingStroke stroke) {
    const threshold = 10.0;
    
    // 将屏幕坐标转换为画布坐标
    final canvasPoint = Offset(
      (screenPoint.dx - _canvasOffset.dx) / _scale,
      (screenPoint.dy - _canvasOffset.dy) / _scale,
    );
    
    for (var strokePoint in stroke.points) {
      final distance = (canvasPoint - strokePoint).distance;
      if (distance < (threshold + stroke.strokeWidth) / _scale) {
        return true;
      }
    }
    
    return false;
  }
  
  // 从本地选择首帧/尾帧图片
  Future<void> _pickFrameImage(CanvasNode node, {required bool isFirstFrame}) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      
      if (result != null && result.files.single.path != null) {
        setState(() {
          if (isFirstFrame) {
            node.data['firstFrameImage'] = result.files.single.path;
          } else {
            node.data['lastFrameImage'] = result.files.single.path;
          }
        });
        print("设置${isFirstFrame ? '首帧' : '尾帧'}图片: ${result.files.single.path}");
      }
    } catch (e) {
      print("选择图片失败: $e");
    }
  }
  
  // 从画布选择首帧/尾帧图片
  void _selectFrameFromCanvas(CanvasNode targetNode, {required bool isFirstFrame}) {
    setState(() {
      _isSelectingFromCanvas = true;
      _targetNodeForImage = targetNode;
      // 标记是选择首帧还是尾帧
      targetNode.data['_selectingFrameType'] = isFirstFrame ? 'first' : 'last';
      _selectNode(null);
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("请点击画布上的图片节点作为${isFirstFrame ? '首帧' : '尾帧'}"),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: "取消",
          onPressed: () {
            setState(() {
              _isSelectingFromCanvas = false;
              _targetNodeForImage = null;
              targetNode.data.remove('_selectingFrameType');
            });
          },
        ),
      ),
    );
  }
  
  // 打开素材库
  void _openMaterialLibrary(CanvasNode node) async {
    // 根据节点类型决定显示的素材库类型
    // 图片节点：显示角色、场景、物品素材
    // 视频节点：显示角色、场景、物品、语音素材
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _MaterialLibraryDialog(
        nodeType: node.type,
      ),
    );
    
    if (result != null && mounted) {
      if (node.type == NodeType.image) {
        // 图片节点：添加选择的图片到参考图片列表
        final selectedImages = result['images'] as List<String>?;
        if (selectedImages != null && selectedImages.isNotEmpty) {
          setState(() {
            if (node.data['referenceImages'] == null) {
              node.data['referenceImages'] = <String>[];
            }
            final referenceImages = node.data['referenceImages'] as List<String>;
            for (var imagePath in selectedImages) {
              if (referenceImages.length < 10) {
                referenceImages.add(imagePath);
              }
            }
          });
        }
      } else if (node.type == NodeType.video) {
        // 视频节点：可以添加图片素材或语音
        final selectedImages = result['images'] as List<String>?;
        final selectedVoice = result['voice'] as String?;
        
        if (selectedImages != null && selectedImages.isNotEmpty) {
          // 添加图片素材到参考图片列表
          setState(() {
            if (node.data['referenceImages'] == null) {
              node.data['referenceImages'] = <String>[];
            }
            final referenceImages = node.data['referenceImages'] as List<String>;
            for (var imagePath in selectedImages) {
              if (referenceImages.length < 10) {
                referenceImages.add(imagePath);
              }
            }
          });
        }
        
        if (selectedVoice != null) {
          // 添加语音素材
          setState(() {
            node.data['voiceAsset'] = selectedVoice;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("已选择语音: $selectedVoice"), duration: const Duration(seconds: 2)),
          );
        }
      }
    }
  }
  
  // 从本地选择参考图片
  Future<void> _pickReferenceImage(CanvasNode node) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true, // 允许多选
      );
      
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          // 初始化参考图片列表
          if (node.data['referenceImages'] == null) {
            node.data['referenceImages'] = <String>[];
          }
          
          final referenceImages = node.data['referenceImages'] as List<String>;
          
          // 添加所有选择的图片，但限制总数不超过10张
          for (var file in result.files) {
            if (file.path != null && referenceImages.length < 10) {
              referenceImages.add(file.path!);
              debugPrint('✅ 添加参考图片: ${file.path}');
            }
          }
          
          debugPrint('========== 参考图片添加完成 ==========');
          debugPrint('节点ID: ${node.id}');
          debugPrint('当前参考图片总数: ${referenceImages.length}');
          debugPrint('参考图片列表: $referenceImages');
          
          // 如果超过10张，显示提示
          if (result.files.length > 10 || referenceImages.length >= 10) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("最多只能添加10张参考图片"),
                duration: Duration(seconds: 2),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("已添加 ${result.files.length} 张参考图片"),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        });
        print("添加了 ${result.files.length} 张参考图片");
      }
    } catch (e) {
      print("选择图片失败: $e");
    }
  }
  
  // 从画布选择参考图片
  void _selectReferenceFromCanvas(CanvasNode targetNode) {
    setState(() {
      _isSelectingFromCanvas = true;
      _targetNodeForImage = targetNode;
      _selectNode(null); // 取消当前选择
    });
    
    // 显示提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("请点击画布上的图片节点作为参考"),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: "取消",
          onPressed: () {
            setState(() {
              _isSelectingFromCanvas = false;
              _targetNodeForImage = null;
            });
          },
        ),
      ),
    );
  }
  
  // 从本地选择图片（旧方法，保留用于其他用途）
  Future<void> _pickImageFromLocal(CanvasNode node) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      
      if (result != null && result.files.single.path != null) {
        setState(() {
          node.data['imagePath'] = result.files.single.path;
          node.data['imageSource'] = 'local';
        });
        print("选择了本地图片: ${result.files.single.path}");
      }
    } catch (e) {
      print("选择图片失败: $e");
    }
  }
  
  // 从画布选择图片（旧方法，保留用于其他用途）
  void _selectImageFromCanvas(CanvasNode targetNode) {
    setState(() {
      _isSelectingFromCanvas = true;
      _targetNodeForImage = targetNode;
      _selectNode(null); // 取消当前选择
    });
    
    // 显示提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("请点击画布上的图片节点进行选择"),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: "取消",
          onPressed: () {
            setState(() {
              _isSelectingFromCanvas = false;
              _targetNodeForImage = null;
            });
          },
        ),
      ),
    );
  }
  
  // 显示文本节点右键菜单
  void _showTextNodeContextMenu(Offset position, CanvasNode node) {
    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      color: Colors.white,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _borderColor, width: 1),
      ),
      items: <PopupMenuEntry<void>>[
        PopupMenuItem<void>(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _accentBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.edit, size: 20, color: _accentBlue),
              ),
              const SizedBox(width: 12),
              const Text("编辑", style: TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w500)),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              _showTextNodeEditDialog(node);
            });
          },
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<void>(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
              ),
              const SizedBox(width: 12),
              const Text("删除", style: TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w500)),
            ],
          ),
          onTap: () {
            setState(() {
              // 清理视频播放器
              if (_videoPlayers.containsKey(node.id)) {
                _videoPlayers[node.id]?.dispose();
                _videoPlayers.remove(node.id);
                _videoControllers.remove(node.id);
              }
              _nodes.remove(node);
              _selectedNodeId = null;
            });
          },
        ),
      ],
    );
  }
  
  // 显示文本节点编辑对话框
  void _showTextNodeEditDialog(CanvasNode node) {
    String tempFontFamily = node.data['fontFamily'] ?? _textFontFamily;
    double tempFontSize = node.data['fontSize'] ?? _textFontSize;
    Color tempColor = node.data['color'] ?? _textColor;
    bool tempBold = node.data['bold'] ?? _textBold;
    bool tempItalic = node.data['italic'] ?? _textItalic;
    bool tempUnderline = node.data['underline'] ?? _textUnderline;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text("编辑文本样式"),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 字体和字号
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("字体", style: TextStyle(fontSize: 11, color: Colors.black54)),
                            const SizedBox(height: 4),
                            Container(
                              height: 40,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: _borderColor),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: tempFontFamily,
                                  isExpanded: true,
                                  icon: const Icon(Icons.arrow_drop_down, size: 20),
                                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                                  dropdownColor: Colors.white,
                                  items: ['Arial', 'Times New Roman', 'Courier New', 'Georgia', 'Verdana']
                                      .map((font) => DropdownMenuItem(value: font, child: Text(font)))
                                      .toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setDialogState(() => tempFontFamily = val);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("字号", style: TextStyle(fontSize: 11, color: Colors.black54)),
                            const SizedBox(height: 4),
                            Container(
                              height: 40,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: _borderColor),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<double>(
                                  value: tempFontSize,
                                  isExpanded: true,
                                  icon: const Icon(Icons.arrow_drop_down, size: 20),
                                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                                  dropdownColor: Colors.white,
                                  items: [8.0, 10.0, 12.0, 14.0, 16.0, 18.0, 20.0, 24.0, 28.0, 32.0, 36.0, 48.0, 60.0, 72.0]
                                      .map((size) => DropdownMenuItem(value: size, child: Text("${size.toInt()}")))
                                      .toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setDialogState(() => tempFontSize = val);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 文本样式
                  Row(
                    children: [
                      const Text("样式:", style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => setDialogState(() => tempBold = !tempBold),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: tempBold ? _accentBlue.withValues(alpha: 0.2) : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: tempBold ? Border.all(color: _accentBlue, width: 1.5) : null,
                          ),
                          alignment: Alignment.center,
                          child: Icon(Icons.format_bold, size: 18, color: tempBold ? _accentBlue : Colors.black54),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () => setDialogState(() => tempItalic = !tempItalic),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: tempItalic ? _accentBlue.withValues(alpha: 0.2) : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: tempItalic ? Border.all(color: _accentBlue, width: 1.5) : null,
                          ),
                          alignment: Alignment.center,
                          child: Icon(Icons.format_italic, size: 18, color: tempItalic ? _accentBlue : Colors.black54),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () => setDialogState(() => tempUnderline = !tempUnderline),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: tempUnderline ? _accentBlue.withValues(alpha: 0.2) : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: tempUnderline ? Border.all(color: _accentBlue, width: 1.5) : null,
                          ),
                          alignment: Alignment.center,
                          child: Icon(Icons.format_underline, size: 18, color: tempUnderline ? _accentBlue : Colors.black54),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // 颜色选择
                  const Text("颜色:", style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  
                  GestureDetector(
                    onTapDown: (details) {
                      final width = 368.0;
                      final x = details.localPosition.dx.clamp(0.0, width);
                      final hue = (x / width) * 360;
                      setDialogState(() {
                        tempColor = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
                      });
                    },
                    child: Container(
                      height: 32,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        gradient: const LinearGradient(
                          colors: [Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Colors.purple, Colors.red],
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            left: (HSVColor.fromColor(tempColor).hue / 360) * 368 - 8,
                            top: -4,
                            child: Container(
                              width: 16,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                border: Border.all(color: Colors.black26, width: 2),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  GestureDetector(
                    onTapDown: (details) {
                      final width = 368.0;
                      final x = details.localPosition.dx.clamp(0.0, width);
                      final brightness = x / width;
                      final hsv = HSVColor.fromColor(tempColor);
                      setDialogState(() {
                        tempColor = hsv.withValue(brightness).toColor();
                      });
                    },
                    child: Container(
                      height: 24,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        gradient: LinearGradient(
                          colors: [Colors.black, HSVColor.fromColor(tempColor).withValue(1.0).toColor()],
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  Row(
                    children: [
                      const Text("当前:", style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 8),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: tempColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey, width: 2),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: Colors.black54,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text("取消", style: TextStyle(fontSize: 15)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  node.data['fontFamily'] = tempFontFamily;
                  node.data['fontSize'] = tempFontSize;
                  node.data['color'] = tempColor;
                  node.data['bold'] = tempBold;
                  node.data['italic'] = tempItalic;
                  node.data['underline'] = tempUnderline;
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text("确定", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
  
  // 显示涂鸦右键菜单
  void _showStrokeContextMenu(Offset position) {
    showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      color: Colors.white,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _borderColor, width: 1),
      ),
      items: <PopupMenuEntry<void>>[
        PopupMenuItem<void>(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _accentBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.edit, size: 20, color: _accentBlue),
              ),
              const SizedBox(width: 12),
              const Text("编辑", style: TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w500)),
            ],
          ),
          onTap: () {
            Future.delayed(Duration.zero, () {
              _showStrokeEditDialog();
            });
          },
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<void>(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
              ),
              const SizedBox(width: 12),
              const Text("删除", style: TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w500)),
            ],
          ),
          onTap: () {
            setState(() {
              _strokes.remove(_selectedStroke);
              _selectedStroke = null;
            });
          },
        ),
      ],
    );
  }
  
  // 显示涂鸦编辑对话框
  void _showStrokeEditDialog() {
    if (_selectedStroke == null) return;
    
    Color tempColor = _selectedStroke!.color;
    double tempWidth = _selectedStroke!.strokeWidth;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text("编辑涂鸦"),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("粗细:", style: TextStyle(fontSize: 12)),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: tempWidth,
                        min: 1,
                        max: 20,
                        divisions: 19,
                        onChanged: (val) {
                          setDialogState(() => tempWidth = val);
                        },
                      ),
                    ),
                    Text("${tempWidth.toInt()}px", style: const TextStyle(fontSize: 11)),
                  ],
                ),
                
                const SizedBox(height: 16),
                const Text("颜色:", style: TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                
                // 渐变色带
                GestureDetector(
                  onTapDown: (details) {
                    final width = 368.0;
                    final x = details.localPosition.dx.clamp(0.0, width);
                    final hue = (x / width) * 360;
                    setDialogState(() {
                      tempColor = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
                    });
                  },
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      gradient: const LinearGradient(
                        colors: [
                          Colors.red,
                          Colors.yellow,
                          Colors.green,
                          Colors.cyan,
                          Colors.blue,
                          Colors.purple,
                          Colors.red,
                        ],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          left: (HSVColor.fromColor(tempColor).hue / 360) * 368 - 8,
                          top: -4,
                          child: Container(
                            width: 16,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(color: Colors.black26, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // 亮度调节
                GestureDetector(
                  onTapDown: (details) {
                    final width = 368.0;
                    final x = details.localPosition.dx.clamp(0.0, width);
                    final brightness = x / width;
                    final hsv = HSVColor.fromColor(tempColor);
                    setDialogState(() {
                      tempColor = hsv.withValue(brightness).toColor();
                    });
                  },
                  child: Container(
                    height: 24,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      gradient: LinearGradient(
                        colors: [
                          Colors.black,
                          HSVColor.fromColor(tempColor).withValue(1.0).toColor(),
                        ],
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // 当前颜色预览
                Row(
                  children: [
                    const Text("当前:", style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 8),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: tempColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey, width: 2),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: Colors.black54,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text("取消", style: TextStyle(fontSize: 15)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _selectedStroke!.color = tempColor;
                  _selectedStroke!.strokeWidth = tempWidth;
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text("确定", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }

  // 紧凑的编辑面板（浮动在节点下方）
  Widget _buildCompactEditPanel(CanvasNode node) {
    // 获取上传的参考图片列表（图片和视频节点都可以有）
    final referenceImages = node.data['referenceImages'] as List<String>? ?? [];
    
    // 获取首尾帧图片（视频节点）
    final firstFrameImage = node.data['firstFrameImage'] as String?;
    final lastFrameImage = node.data['lastFrameImage'] as String?;
    final frameImages = <String>[];
    if (firstFrameImage != null) frameImages.add(firstFrameImage);
    if (lastFrameImage != null) frameImages.add(lastFrameImage);
    
    return Container(
      width: 600,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 提示词输入框
          TextField(
            decoration: InputDecoration(
              hintText: node.type == NodeType.image ? "描述你想要生成的图片..." : "描述你想要生成的视频...",
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: _borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: _borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: _accentBlue, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            maxLines: 3,
            style: const TextStyle(fontSize: 14, color: Colors.black),
            onChanged: (val) {
              node.data['prompt'] = val;
            },
          ),
          
          // 参考图片缩略图列表（图片和视频节点都显示）
          if (referenceImages.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: referenceImages.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        GestureDetector(
                          onTap: () {
                            // 点击放大查看图片
                            showDialog(
                              context: context,
                              builder: (context) => Dialog(
                                backgroundColor: Colors.transparent,
                                child: Stack(
                                  children: [
                                    Center(
                                      child: InteractiveViewer(
                                        child: Image.file(
                                          File(referenceImages[index]),
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 20,
                                      right: 20,
                                      child: IconButton(
                                        icon: const Icon(Icons.close, color: Colors.white, size: 32),
                                        onPressed: () => Navigator.pop(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(
                              File(referenceImages[index]),
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        // 删除按钮
                        Positioned(
                          top: 1,
                          right: 1,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                referenceImages.removeAt(index);
                              });
                            },
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
          
          // 首尾帧图片缩略图列表（仅视频节点）
          if (node.type == NodeType.video && frameImages.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: frameImages.length,
                itemBuilder: (context, index) {
                  final isFirstFrame = (index == 0 && firstFrameImage != null);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        GestureDetector(
                          onTap: () {
                            // 点击放大查看图片
                            showDialog(
                              context: context,
                              builder: (context) => Dialog(
                                backgroundColor: Colors.transparent,
                                child: Stack(
                                  children: [
                                    Center(
                                      child: InteractiveViewer(
                                        child: Image.file(
                                          File(frameImages[index]),
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 20,
                                      right: 20,
                                      child: IconButton(
                                        icon: const Icon(Icons.close, color: Colors.white, size: 32),
                                        onPressed: () => Navigator.pop(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(
                              File(frameImages[index]),
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        // 删除按钮
                        Positioned(
                          top: 1,
                          right: 1,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                if (isFirstFrame) {
                                  node.data.remove('firstFrameImage');
                                } else {
                                  node.data.remove('lastFrameImage');
                                }
                              });
                            },
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
          
          const SizedBox(height: 12),
          
          // 底部控制栏
          Row(
            children: [
              // 图片节点：参考图按钮 / 视频节点：首尾帧按钮
              if (node.type == NodeType.image)
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.image_outlined,
                    color: Colors.grey[700],
                    size: 24,
                  ),
                  color: Colors.white,
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: _borderColor, width: 1),
                  ),
                  offset: const Offset(0, 48),
                  padding: EdgeInsets.zero,
                  itemBuilder: (context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'local',
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.upload_file, size: 20, color: Colors.black87),
                          const SizedBox(width: 12),
                          const Text(
                            "从本地上传图片",
                            style: TextStyle(fontSize: 14, color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'library',
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.photo_library_outlined, size: 20, color: Colors.black87),
                          const SizedBox(width: 12),
                          const Text(
                            "素材库",
                            style: TextStyle(fontSize: 14, color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'canvas',
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.crop_free, size: 20, color: Colors.black87),
                          const SizedBox(width: 12),
                          const Text(
                            "从画布选择",
                            style: TextStyle(fontSize: 14, color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    switch (value) {
                      case 'local':
                        _pickReferenceImage(node);
                        break;
                      case 'library':
                        _openMaterialLibrary(node);
                        break;
                      case 'canvas':
                        _selectReferenceFromCanvas(node);
                        break;
                    }
                  },
                )
              else if (node.type == NodeType.video)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 首帧按钮
                    PopupMenuButton<String>(
                      icon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.first_page,
                            color: Colors.grey[700],
                            size: 20,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            "首帧",
                            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                      color: Colors.white,
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: _borderColor, width: 1),
                      ),
                      offset: const Offset(0, 40),
                      padding: EdgeInsets.zero,
                      itemBuilder: (context) => <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(
                          value: 'local',
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              Icon(Icons.upload_file, size: 20, color: Colors.black87),
                              const SizedBox(width: 12),
                              const Text(
                                "从本地上传图片",
                                style: TextStyle(fontSize: 14, color: Colors.black87),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'library',
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              Icon(Icons.photo_library_outlined, size: 20, color: Colors.black87),
                              const SizedBox(width: 12),
                              const Text(
                                "素材库",
                                style: TextStyle(fontSize: 14, color: Colors.black87),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'canvas',
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              Icon(Icons.crop_free, size: 20, color: Colors.black87),
                              const SizedBox(width: 12),
                              const Text(
                                "从画布选择",
                                style: TextStyle(fontSize: 14, color: Colors.black87),
                              ),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (value) {
                        switch (value) {
                          case 'local':
                            _pickFrameImage(node, isFirstFrame: true);
                            break;
                          case 'library':
                            _openMaterialLibrary(node);
                            break;
                          case 'canvas':
                            _selectFrameFromCanvas(node, isFirstFrame: true);
                            break;
                        }
                      },
                    ),
                    
                    const SizedBox(width: 8),
                    
                    // 尾帧按钮
                    PopupMenuButton<String>(
                      icon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.last_page,
                            color: Colors.grey[700],
                            size: 20,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            "尾帧",
                            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                      color: Colors.white,
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: _borderColor, width: 1),
                      ),
                      offset: const Offset(0, 40),
                      padding: EdgeInsets.zero,
                      itemBuilder: (context) => <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(
                          value: 'local',
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              Icon(Icons.upload_file, size: 20, color: Colors.black87),
                              const SizedBox(width: 12),
                              const Text(
                                "从本地上传图片",
                                style: TextStyle(fontSize: 14, color: Colors.black87),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'library',
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              Icon(Icons.photo_library_outlined, size: 20, color: Colors.black87),
                              const SizedBox(width: 12),
                              const Text(
                                "素材库",
                                style: TextStyle(fontSize: 14, color: Colors.black87),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'canvas',
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              Icon(Icons.crop_free, size: 20, color: Colors.black87),
                              const SizedBox(width: 12),
                              const Text(
                                "从画布选择",
                                style: TextStyle(fontSize: 14, color: Colors.black87),
                              ),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (value) {
                        switch (value) {
                          case 'local':
                            _pickFrameImage(node, isFirstFrame: false);
                            break;
                          case 'library':
                            _openMaterialLibrary(node);
                            break;
                          case 'canvas':
                            _selectFrameFromCanvas(node, isFirstFrame: false);
                            break;
                        }
                      },
                    ),
                  ],
                ),
              
              const SizedBox(width: 12),
              
              // 模型选择 - 无边框
              PopupMenuButton<String>(
                initialValue: node.data['model'] ?? (node.type == NodeType.image 
                    ? (_availableImageModels.isNotEmpty ? _availableImageModels.first : null)
                    : (_availableVideoModels.isNotEmpty ? _availableVideoModels.first : null)),
                icon: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        (node.type == NodeType.image ? _imageProvider : _videoProvider).toLowerCase() == 'comfyui'
                            ? Icons.account_tree // ComfyUI 工作流图标
                            : Icons.auto_awesome,
                        size: 16,
                        color: Colors.grey[700],
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _getShortModelName(
                            node.data['model'] ?? (node.type == NodeType.image 
                                ? (_availableImageModels.isNotEmpty ? _availableImageModels.first : '未设置')
                                : (_availableVideoModels.isNotEmpty ? _availableVideoModels.first : '未设置')),
                            node.type == NodeType.image ? _imageProvider : _videoProvider,
                          ),
                          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey[600]),
                    ],
                  ),
                ),
                color: Colors.white,
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: _borderColor, width: 1),
                ),
                offset: const Offset(0, 40),
                padding: EdgeInsets.zero,
                itemBuilder: (context) {
                  final models = node.type == NodeType.image ? _availableImageModels : _availableVideoModels;
                  final provider = node.type == NodeType.image ? _imageProvider : _videoProvider;
                  final isComfyUI = provider.toLowerCase() == 'comfyui';
                  
                  if (models.isEmpty) {
                    return [
                      const PopupMenuItem<String>(
                        enabled: false,
                        height: 48,
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          '请在设置中配置模型',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ),
                    ];
                  }
                  
                  // 检查是否是 ComfyUI 的提示信息
                  if (models.length == 1 && (models.first.contains('未配置') || models.first.contains('无'))) {
                    return [
                      PopupMenuItem<String>(
                        enabled: false,
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          models.first,
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ),
                    ];
                  }
                  
                  return models.map((model) {
                    return PopupMenuItem<String>(
                      value: model,
                      height: 60, // 固定高度，足够显示多行文本
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isComfyUI) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.account_tree,
                                size: 18,
                                color: Colors.blue[700],
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              model,
                              style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.3),
                              softWrap: true, // 允许换行
                              maxLines: 2, // 最多2行
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList();
                },
                onSelected: (model) {
                  setState(() {
                    node.data['model'] = model;
                  });
                },
              ),
              
              const Spacer(),
              
              // 分辨率选择 - 无边框
              _buildCompactDropdown(
                value: node.data['resolution'] ?? "1K",
                items: ["1K", "2K", "4K"],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => node.data['resolution'] = val);
                  }
                },
              ),
              
              const SizedBox(width: 8),
              
              // 视频节点：比例选择
              if (node.type == NodeType.video)
                _buildCompactDropdown(
                  value: () {
                    final videoRatio = node.data['videoRatio'];
                    const items = ["16:9", "9:16", "1:1", "4:3", "3:4"];
                    // 确保 value 在 items 列表中，否则使用默认值
                    if (videoRatio != null && items.contains(videoRatio)) {
                      return videoRatio as String;
                    }
                    return "16:9"; // 默认 16:9
                  }(),
                  items: const ["16:9", "9:16", "1:1", "4:3", "3:4"],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => node.data['videoRatio'] = val);
                    }
                  },
                ),
              
              // 视频节点：时长选择
              if (node.type == NodeType.video) ...[
                const SizedBox(width: 8),
                _buildCompactDropdown(
                  value: () {
                    final ratio = node.data['ratio'];
                    const items = ["5s", "8s", "10s", "15s"];
                    // 确保 value 在 items 列表中，否则使用默认值
                    if (ratio != null && items.contains(ratio)) {
                      return ratio as String;
                    }
                    return "5s";
                  }(),
                  items: const ["5s", "8s", "10s", "15s"],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => node.data['ratio'] = val);
                    }
                  },
                ),
              ],
              
              // 图片节点：比例选择
              if (node.type == NodeType.image) ...[
                const SizedBox(width: 8),
                _buildCompactDropdown(
                  value: () {
                    final ratio = node.data['ratio'];
                    const items = ["1:1", "16:9", "9:16", "4:3", "3:4"];
                    // 确保 value 在 items 列表中，否则使用默认值
                    if (ratio != null && items.contains(ratio)) {
                      return ratio as String;
                    }
                    return "1:1";
                  }(),
                  items: const ["1:1", "16:9", "9:16", "4:3", "3:4"],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => node.data['ratio'] = val);
                    }
                  },
                ),
              ],
              
              const SizedBox(width: 12),
              
              // 生成按钮 - 黑色纸飞机图标，无背景
              IconButton(
                icon: const Icon(Icons.send, size: 24, color: Colors.black87),
                onPressed: () => _generateContent(node),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  // 紧凑的下拉框 - 无边框版本
  Widget _buildCompactDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          icon: Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey[600]),
          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          dropdownColor: Colors.white,
          items: items
              .map((item) => DropdownMenuItem(
                    value: item,
                    child: Text(item),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

}

// 画布工具
enum CanvasTool {
  select,  // 选择
  pan,     // 拖动画布（手掌）
  draw,    // 画笔
  text,    // 文本
  image,   // 图片
  video,   // 视频
}

// 调整大小手柄
enum ResizeHandle {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

// 节点类型
enum NodeType {
  image,
  video,
  text,
}

// 节点数据模型
class CanvasNode {
  String id;
  NodeType type;
  Offset position;
  Size size;
  Map<String, dynamic> data;

  CanvasNode({
    required this.id,
    required this.type,
    required this.position,
    required this.size,
    required this.data,
  });
}

// 窗口控制按钮
class _WindowControlButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isClose;

  const _WindowControlButton({
    required this.icon,
    required this.onPressed,
    this.isClose = false,
  });

  @override
  State<_WindowControlButton> createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<_WindowControlButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: 32,
          color: _isHovered
              ? (widget.isClose ? Colors.red : AppTheme.textColor.withValues(alpha: 0.1))
              : Colors.transparent,
          child: Icon(
            widget.icon,
            size: 16,
            color: _isHovered && widget.isClose ? Colors.white : AppTheme.subTextColor,
          ),
        ),
      ),
    );
  }
}

// 绘制笔画
class DrawingStroke {
  Color color;
  double strokeWidth;
  final List<Offset> points;

  DrawingStroke({
    required this.color,
    required this.strokeWidth,
    required this.points,
  });
}

// 绘制画笔
class DrawingPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final DrawingStroke? currentStroke;
  final DrawingStroke? selectedStroke;
  final Offset canvasOffset;
  final double scale;

  DrawingPainter({
    required this.strokes,
    this.currentStroke,
    this.selectedStroke,
    required this.canvasOffset,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制已完成的笔画
    for (var stroke in strokes) {
      _drawStroke(canvas, stroke, stroke == selectedStroke);
    }
    
    // 绘制当前笔画
    if (currentStroke != null) {
      _drawStroke(canvas, currentStroke!, false);
    }
  }
  
  void _drawStroke(Canvas canvas, DrawingStroke stroke, bool isSelected) {
    if (stroke.points.length < 2) return;
    
    // 如果选中，先绘制外层高亮
    if (isSelected) {
      final highlightPaint = Paint()
        ..color = const Color(0xFF3B82F6).withValues(alpha: 0.3)
        ..strokeWidth = (stroke.strokeWidth + 6) * scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      
      final path = Path();
      final firstPoint = _transformPoint(stroke.points[0]);
      path.moveTo(firstPoint.dx, firstPoint.dy);
      
      for (int i = 1; i < stroke.points.length; i++) {
        final point = _transformPoint(stroke.points[i]);
        path.lineTo(point.dx, point.dy);
      }
      
      canvas.drawPath(path, highlightPaint);
    }
    
    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.strokeWidth * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    
    final path = Path();
    final firstPoint = _transformPoint(stroke.points[0]);
    path.moveTo(firstPoint.dx, firstPoint.dy);
    
    for (int i = 1; i < stroke.points.length; i++) {
      final point = _transformPoint(stroke.points[i]);
      path.lineTo(point.dx, point.dy);
    }
    
    canvas.drawPath(path, paint);
  }
  
  // 将画布坐标转换为屏幕坐标
  Offset _transformPoint(Offset point) {
    return Offset(
      point.dx * scale + canvasOffset.dx,
      point.dy * scale + canvasOffset.dy,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// 框选矩形绘制器
class SelectionBoxPainter extends CustomPainter {
  final Offset start;
  final Offset end;

  SelectionBoxPainter({
    required this.start,
    required this.end,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromPoints(start, end);
    
    final fillPaint = Paint()
      ..color = const Color(0xFF3B82F6).withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;
    
    final strokePaint = Paint()
      ..color = const Color(0xFF3B82F6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    
    canvas.drawRect(rect, fillPaint);
    canvas.drawRect(rect, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}


// 素材库对话框
class _MaterialLibraryDialog extends StatefulWidget {
  final NodeType nodeType;
  
  const _MaterialLibraryDialog({
    required this.nodeType,
  });

  @override
  State<_MaterialLibraryDialog> createState() => _MaterialLibraryDialogState();
}

class _MaterialLibraryDialogState extends State<_MaterialLibraryDialog> {
  int _selectedCategoryIndex = 0;
  final List<String> _imageCategories = ['角色素材', '场景素材', '物品素材'];
  final List<String> _videoCategories = ['角色素材', '场景素材', '物品素材', '语音库'];
  
  // 实际素材数据
  final Map<int, List<AssetStyle>> _stylesByCategory = {};
  List<VoiceAsset> _voiceAssets = [];
  bool _isLoading = true;
  
  final Set<String> _selectedImages = {};
  String? _selectedVoice;

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  // 加载素材数据
  Future<void> _loadAssets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 加载图片素材（角色、场景、物品）- 图片和视频节点都需要
      final assetsJson = prefs.getString('asset_library_data');
      if (assetsJson != null && assetsJson.isNotEmpty) {
        final data = jsonDecode(assetsJson) as Map<String, dynamic>;
        
        setState(() {
          data.forEach((key, value) {
            final categoryIndex = int.parse(key);
            if (categoryIndex >= 0 && categoryIndex <= 2) { // 前3个分类
              final stylesList = (value as List).map((styleData) {
                return AssetStyle.fromJson(styleData);
              }).toList();
              _stylesByCategory[categoryIndex] = stylesList;
            }
          });
        });
      }
      
      // 加载语音素材 - 视频节点需要
      if (widget.nodeType == NodeType.video) {
        final voicesJson = prefs.getString('voice_library_data');
        if (voicesJson != null && voicesJson.isNotEmpty) {
          final voicesList = (jsonDecode(voicesJson) as List)
              .map((item) => VoiceAsset.fromJson(item as Map<String, dynamic>))
              .toList();
          
          setState(() {
            _voiceAssets = voicesList;
          });
        }
      }
      
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('加载素材失败: $e');
      setState(() => _isLoading = false);
    }
  }

  // 获取当前分类的所有素材
  List<AssetItem> _getCurrentAssets() {
    if (_selectedCategoryIndex <= 2) {
      // 角色、场景、物品素材
      final styles = _stylesByCategory[_selectedCategoryIndex] ?? [];
      final allAssets = <AssetItem>[];
      for (var style in styles) {
        allAssets.addAll(style.assets);
      }
      return allAssets;
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.nodeType == NodeType.image ? _imageCategories : _videoCategories;
    final isVoiceCategory = widget.nodeType == NodeType.video && _selectedCategoryIndex == 3;
    final assets = isVoiceCategory ? [] : _getCurrentAssets();
    final voices = isVoiceCategory ? _voiceAssets : [];
    
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 800,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Text(
                  widget.nodeType == NodeType.image ? '选择素材' : '选择素材',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // 分类标签
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final isSelected = _selectedCategoryIndex == index;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(categories[index]),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedCategoryIndex = index);
                        }
                      },
                    ),
                  );
                },
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 素材网格
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : (assets.isEmpty && voices.isEmpty)
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                '暂无素材\n请在素材库页面添加素材',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.0,
                          ),
                          itemCount: isVoiceCategory ? voices.length : assets.length,
                          itemBuilder: (context, index) {
                            if (isVoiceCategory) {
                              // 语音素材
                              final voice = voices[index];
                              final isSelected = _selectedVoice == voice.id;
                              
                              return GestureDetector(
                                onTap: () {
                                  setState(() => _selectedVoice = voice.id);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFF3B82F6).withValues(alpha: 0.1) : Colors.grey[100],
                                    border: Border.all(
                                      color: isSelected ? const Color(0xFF3B82F6) : Colors.grey[300]!,
                                      width: isSelected ? 2 : 1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.mic,
                                        size: 32,
                                        color: isSelected ? const Color(0xFF3B82F6) : Colors.grey[600],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        voice.name,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isSelected ? const Color(0xFF3B82F6) : Colors.black87,
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            } else {
                              // 图片素材（角色、场景、物品）
                              final asset = assets[index];
                              final isSelected = _selectedImages.contains(asset.path);
                              
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedImages.remove(asset.path);
                                    } else if (_selectedImages.length < 10) {
                                      _selectedImages.add(asset.path);
                                    }
                                  });
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isSelected ? const Color(0xFF3B82F6) : Colors.grey[300]!,
                                      width: isSelected ? 3 : 1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.file(
                                          File(asset.path),
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          height: double.infinity,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Container(
                                              color: Colors.grey[200],
                                              child: Icon(Icons.broken_image, color: Colors.grey[400]),
                                            );
                                          },
                                        ),
                                      ),
                                      if (isSelected)
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: Container(
                                            width: 24,
                                            height: 24,
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF3B82F6),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.check, color: Colors.white, size: 16),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            }
                          },
                        ),
            ),
            
            const SizedBox(height: 16),
            
            // 底部按钮
            Row(
              children: [
                if (!isVoiceCategory)
                  Text(
                    '已选择 ${_selectedImages.length}/10',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    if (isVoiceCategory) {
                      // 语音素材
                      if (_selectedVoice != null) {
                        Navigator.pop(context, {'voice': _selectedVoice});
                      }
                    } else {
                      // 图片素材
                      if (_selectedImages.isNotEmpty) {
                        Navigator.pop(context, {'images': _selectedImages.toList()});
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: const Text('确定'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 素材风格类
class AssetStyle {
  String name;
  String description;
  List<AssetItem> assets;

  AssetStyle({
    required this.name,
    required this.description,
    this.assets = const [],
  });

  factory AssetStyle.fromJson(Map<String, dynamic> json) {
    return AssetStyle(
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      assets: (json['assets'] as List?)
          ?.map((item) => AssetItem.fromJson(item as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'assets': assets.map((item) => item.toJson()).toList(),
    };
  }
}

// 素材项类
class AssetItem {
  String id;
  String name;
  String path;
  String? characterInfo;
  bool isUploaded;
  String? videoUrl;

  AssetItem({
    required this.id,
    required this.name,
    required this.path,
    this.characterInfo,
    this.isUploaded = false,
    this.videoUrl,
  });

  factory AssetItem.fromJson(Map<String, dynamic> json) {
    return AssetItem(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      characterInfo: json['characterInfo'],
      isUploaded: json['isUploaded'] ?? false,
      videoUrl: json['videoUrl'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'characterInfo': characterInfo,
      'isUploaded': isUploaded,
      'videoUrl': videoUrl,
    };
  }
}
