import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:window_manager/window_manager.dart';
import 'package:xinghe_new/core/widgets/window_border.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinghe_new/features/home/domain/voice_asset.dart';
import 'package:xinghe_new/features/home/presentation/settings_page.dart';
import 'package:xinghe_new/services/api/api_factory.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';
import 'package:xinghe_new/services/api/base/api_response.dart';
import 'package:xinghe_new/services/api/provider_preference_helper.dart';
import 'package:xinghe_new/services/api/secure_storage_manager.dart';
import 'package:xinghe_new/core/logger/log_manager.dart';
import 'package:xinghe_new/core/aigc_engine/automation_api_client.dart';
import 'package:xinghe_new/services/ffmpeg_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:xinghe_new/features/creation_workflow/presentation/widgets/draggable_media_item.dart'; // ✅ 导入拖动组件
import 'package:xinghe_new/pages/ai_canvas/agent_chat_panel.dart';
import 'package:xinghe_new/pages/ai_canvas/canvas_agent_service.dart';

/// GeekNow 图片模型列表（与设置界面保持一致）
class GeekNowImageModels {
  static const List<String> models = [
    'gemini-3.1-flash-image-preview',
    'gemini-3-pro-image-preview',
    'gemini-2.5-flash-image-preview',
  ];
}

/// GeekNow 视频模型列表
class GeekNowVideoModels {
  static const List<String> models = [
    'sora-2',
    'sora-2[vip]',
    'veo_3_1',
    'veo_3_1-components-4K',
    'veo_3_1-fast-components',
    'veo_3_1-fast-components-4K',
    'grok-video-3',
    'grok-video-3-max',
  ];
}

/// Yunwu（云雾）图片模型列表
class YunwuImageModels {
  static const List<String> models = [
    'gemini-3.1-flash-image-preview',
    'gemini-3-pro-image-preview',
    'gemini-2.5-flash-image-preview',
  ];
}

/// Yunwu（云雾）视频模型列表
class YunwuVideoModels {
  static const List<String> models = [
    // Sora 系列
    'sora-2-all',
    // VEO3.1 4K 系列（OpenAI视频格式）
    'veo_3_1-4K', 'veo_3_1-fast-4K',
    // Grok 视频系列（xAI）
    'grok-video-3', 'grok-video-3-10s', 'grok-video-3-15s',
  ];
}

class AiCanvasPage extends StatefulWidget {
  const AiCanvasPage({super.key});

  @override
  State<AiCanvasPage> createState() => _AiCanvasPageState();
}

class _AiCanvasPageState extends State<AiCanvasPage>
    with TickerProviderStateMixin {
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
  bool _isSpacePressed = false; // 空格键按下状态（用于空格+鼠标拖动画布）
  bool _isPanning = false; // 正在拖动画布中（用于光标切换）
  Offset? _cursorPosition; // 鼠标在画布Stack中的位置（自定义光标用）
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
  DrawingStroke? _selectedStroke; // 选中的涂鸦（单击选中）
  final Set<DrawingStroke> _selectedStrokes = {}; // 框选的涂鸦（多选）
  Color _brushColor = Colors.black;
  double _brushSize = 3.0;
  bool _showBrushToolbar = false; // 画笔工具栏显示状态

  // 网格背景状态
  bool _showGrid = false;
  bool _gridDots = true; // true=点阵, false=线条

  // 图层面板状态
  bool _showLayerPanel = false;
  final Set<String> _hiddenNodeIds = {}; // 隐藏的节点ID
  final Set<int> _hiddenStrokeIndices = {}; // 隐藏的涂鸦索引

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

  // 画布焦点节点（用于从文本输入框切换回画布快捷键）
  final FocusNode _canvasFocusNode = FocusNode();
  Offset? _zoomFocalPoint;
  double? _zoomStartScale;
  Offset? _zoomStartOffset;

  // 从画布选择状态
  bool _isSelectingFromCanvas = false;
  CanvasNode? _targetNodeForImage; // 目标节点（用于接收选择的图片）

  // Agent 面板状态
  bool _showAgentPanel = false;
  final Set<String> _agentHighlightedNodeIds = {};
  Timer? _agentHighlightTimer;

  // 视频播放器控制器映射（使用 media_kit）
  final Map<String, Player> _videoPlayers = {};
  final Map<String, VideoController> _videoControllers = {};

  // API 服务商和模型
  String _imageProvider = 'geeknow';
  String _videoProvider = 'geeknow';
  List<String> _availableImageModels = GeekNowImageModels.models;
  List<String> _availableVideoModels = GeekNowVideoModels.models;
  String? _currentImageModel;
  String? _currentVideoModel;

  // ComfyUI 工作流
  List<Map<String, dynamic>> _comfyUIWorkflows = [];

  // API 服务
  final SecureStorageManager _storage = SecureStorageManager();
  final LogManager _logger = LogManager();

  // 配色
  static const Color _bgColor = Color(0xFFF3F6FB); // 更柔和的浅灰蓝背景
  static const Color _toolbarBg = Colors.white;
  static const Color _cardBg = Colors.white;
  static const Color _accentBlue = Color(0xFF3B82F6);
  static const Color _accentCyan = Color(0xFF2AFADF);
  static const Color _accentIndigo = Color(0xFF4C83FF);
  static const Color _surfaceStrong = Color(0xFFFFFFFF);
  static const Color _surfaceSoft = Color(0xFFF7FAFF);
  static const Color _surfaceMuted = Color(0xFFEEF3FB);
  static const Color _textPrimary = Color(0xFF111827);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _borderColor = Color(0xFFE5E7EB);

  // 撤销/重做历史
  final List<Map<String, dynamic>> _undoStack = [];
  final List<Map<String, dynamic>> _redoStack = [];
  static const int _maxUndoHistory = 50;
  Map<String, dynamic>? _pendingUndoSnapshot; // 拖动开始时的快照
  bool _dragDidMove = false; // 本次拖动是否实际移动了

  // 对齐参考线
  static const double _snapThreshold = 8.0; // 吸附阈值（屏幕像素）
  List<double> _alignGuideX = []; // 垂直参考线 X 坐标（屏幕坐标）
  List<double> _alignGuideY = []; // 水平参考线 Y 坐标（屏幕坐标）

  // 画布截图 Key
  final GlobalKey _canvasRepaintKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    _scaleAnimationController = AnimationController(
      duration: const Duration(milliseconds: 120),
      vsync: this,
    );

    _scaleAnimation =
        Tween<double>(begin: 1.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _scaleAnimationController,
            curve: Curves.easeOut,
          ),
        )..addListener(() {
          setState(() {
            final currentScale = _scaleAnimation.value;

            // 如果有焦点，以焦点为中心缩放
            if (_zoomFocalPoint != null &&
                _zoomStartScale != null &&
                _zoomStartOffset != null) {
              final scaleChange = currentScale / _zoomStartScale!;
              _canvasOffset =
                  _zoomFocalPoint! -
                  (_zoomFocalPoint! - _zoomStartOffset!) * scaleChange;
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

    _agentHighlightTimer?.cancel();
    _scaleAnimationController.dispose();
    _canvasFocusNode.dispose();
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
            (jsonDecode(workflowsJson) as List).map(
              (w) => Map<String, dynamic>.from(w as Map),
            ),
          );
        } catch (e) {
          debugPrint('解析 ComfyUI 工作流失败: $e');
        }
      }

      if (mounted) {
        final imageModels = _getModelsForProvider(imageProvider, 'image');
        final videoModels = _getModelsForProvider(videoProvider, 'video');
        final savedImageModel = await _storage.getModel(
          provider: imageProvider,
          modelType: 'image',
        );
        final savedVideoModel = await _storage.getModel(
          provider: videoProvider,
          modelType: 'video',
        );

        setState(() {
          _imageProvider = imageProvider;
          _videoProvider = videoProvider;
          _comfyUIWorkflows = workflows;
          _availableImageModels = imageModels;
          _availableVideoModels = videoModels;
          _currentImageModel =
              savedImageModel != null && imageModels.contains(savedImageModel)
              ? savedImageModel
              : (imageModels.isNotEmpty ? imageModels.first : null);
          _currentVideoModel =
              savedVideoModel != null && videoModels.contains(savedVideoModel)
              ? savedVideoModel
              : (videoModels.isNotEmpty ? videoModels.first : null);
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
        case 'google_flow':
          return ['nano-banana-pro', 'nano-banana-2'];
        case 'runninghub':
          return ['使用设置中配置的 AI 应用'];
        default:
          return [];
      }
    } else {
      // 视频模型
      switch (provider.toLowerCase()) {
        case 'geeknow':
          return GeekNowVideoModels.models;
        case 'yunwu':
          return YunwuVideoModels.models;
        case 'openai':
          return ['sora-2', 'sora-turbo'];
        case 'vidu':
          return ['vidu-q3', 'vidu-q2', 'vidu-q1', 'vidu-2.0'];
        case 'jimeng':
          return [
            'seedance-2.0-fast',
            'seedance-2.0',
            'jimeng-video-3.5-pro',
            'jimeng-video-3.0-pro',
            'jimeng-video-3.0-fast',
            'jimeng-video-3.0',
          ];
        case 'runninghub':
          return ['使用设置中配置的 AI 应用'];
        default:
          return [];
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

  /// 从节点数据中安全地提取 Color 值
  Color _getColorFromData(dynamic value, Color fallback) {
    if (value == null) return fallback;
    if (value is Color) return value;
    if (value is int) return Color(value);
    if (value is String) {
      // 尝试解析 "Color(0xff000000)" 格式
      final match = RegExp(r'Color\(0x([0-9a-fA-F]+)\)').firstMatch(value);
      if (match != null) {
        final hex = int.tryParse(match.group(1)!, radix: 16);
        if (hex != null) return Color(hex);
      }
      // 尝试解析纯数字
      final intVal = int.tryParse(value);
      if (intVal != null) return Color(intVal);
    }
    return fallback;
  }

  /// 获取服务商显示名称（与设置页面保持一致）
  String _getProviderDisplayName(String provider) {
    const displayNames = {
      'openai': 'OpenAI',
      'geeknow': 'GeekNow',
      'yunwu': 'Yunwu',
      'comfyui': 'ComfyUI',
      'runninghub': 'RunningHub（云端）',
      'vidu': 'Vidu',
      'jimeng': '即梦',
      'google_flow': 'Google Flow',
      'deepseek': 'DeepSeek',
      'aliyun': '阿里云',
    };
    return displayNames[provider.toLowerCase()] ?? provider;
  }

  /// 获取图片服务商列表（与设置页面保持一致）
  List<Map<String, String>> _getImageProviderList() {
    return [
      {'key': 'openai', 'name': 'OpenAI'},
      {'key': 'geeknow', 'name': 'GeekNow'},
      {'key': 'yunwu', 'name': 'Yunwu（云雾）'},
      {'key': 'comfyui', 'name': 'ComfyUI（本地）'},
      {'key': 'runninghub', 'name': 'RunningHub（云端）'},
      {'key': 'google_flow', 'name': 'Google Flow（网页服务商）'},
    ];
  }

  /// 获取视频服务商列表（与设置页面保持一致）
  List<Map<String, String>> _getVideoProviderList() {
    return [
      {'key': 'openai', 'name': 'OpenAI'},
      {'key': 'geeknow', 'name': 'GeekNow'},
      {'key': 'yunwu', 'name': 'Yunwu（云雾）'},
      {'key': 'comfyui', 'name': 'ComfyUI（本地）'},
      {'key': 'runninghub', 'name': 'RunningHub（云端）'},
      {'key': 'vidu', 'name': 'Vidu（网页服务商）'},
      {'key': 'jimeng', 'name': '即梦（网页服务商）'},
    ];
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
    final prefixes = [
      'video-',
      'image-',
      'workflow-',
      'video_',
      'image_',
      'workflow_',
    ];
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

  /// Vidu 视频工具列表
  List<Map<String, String>> _getViduVideoTools() => const [
    {'id': 'text2video', 'name': '文生视频'},
    {'id': 'img2video', 'name': '图生视频'},
    {'id': 'ref2video', 'name': '参考生视频'},
  ];

  /// Vidu 各工具对应的模型
  List<Map<String, String>> _getViduModelsForTool(String tool) {
    const data = <String, List<Map<String, String>>>{
      'text2video': [
        {'id': 'vidu-q3', 'name': 'Vidu Q3'},
        {'id': 'vidu-q2', 'name': 'Vidu Q2'},
        {'id': 'vidu-q1', 'name': 'Vidu Q1'},
      ],
      'img2video': [
        {'id': 'vidu-q3', 'name': 'Vidu Q3'},
        {'id': 'vidu-q2', 'name': 'Vidu Q2'},
        {'id': 'vidu-q1', 'name': 'Vidu Q1'},
        {'id': 'vidu-2.0', 'name': 'Vidu 2.0'},
      ],
      'ref2video': [
        {'id': 'vidu-q2-pro', 'name': 'Vidu Q2 Pro'},
        {'id': 'vidu-q2', 'name': 'Vidu Q2'},
        {'id': 'vidu-q1', 'name': 'Vidu Q1'},
        {'id': 'vidu-2.0', 'name': 'Vidu 2.0'},
      ],
    };
    return data[tool] ?? [];
  }

  /// 即梦视频模型列表（用于级联菜单第二列）
  List<Map<String, String>> _getJimengVideoModels() => const [
    {'id': 'seedance-2.0-fast', 'name': 'Seedance 2.0 Fast'},
    {'id': 'seedance-2.0', 'name': 'Seedance 2.0'},
    {'id': 'jimeng-video-3.5-pro', 'name': 'Seedance 1.5 Pro'},
    {'id': 'jimeng-video-3.0-pro', 'name': 'Seedance 1.0'},
    {'id': 'jimeng-video-3.0-fast', 'name': 'Seedance 1.0 Fast'},
    {'id': 'jimeng-video-3.0', 'name': 'Seedance 1.0 mini'},
  ];

  /// 即梦各模型对应的生成方式
  List<Map<String, String>> _getJimengModesForModel(String modelId) {
    const data = <String, List<Map<String, String>>>{
      'seedance-2.0-fast': [
        {'id': 'all_ref', 'name': '全能参考'},
        {'id': 'first_last_frame', 'name': '首尾帧'},
        {'id': 'smart_multi_frame', 'name': '智能多帧'},
        {'id': 'subject_ref', 'name': '主体参考'},
      ],
      'seedance-2.0': [
        {'id': 'all_ref', 'name': '全能参考'},
        {'id': 'first_last_frame', 'name': '首尾帧'},
        {'id': 'smart_multi_frame', 'name': '智能多帧'},
        {'id': 'subject_ref', 'name': '主体参考'},
      ],
      'jimeng-video-3.5-pro': [
        {'id': 'first_last_frame', 'name': '首尾帧'},
      ],
      'jimeng-video-3.0-pro': [
        {'id': 'first_last_frame', 'name': '首尾帧'},
      ],
      'jimeng-video-3.0-fast': [
        {'id': 'first_last_frame', 'name': '首尾帧'},
        {'id': 'smart_multi_frame', 'name': '智能多帧'},
      ],
      'jimeng-video-3.0': [
        {'id': 'first_last_frame', 'name': '首尾帧'},
        {'id': 'subject_ref', 'name': '主体参考'},
      ],
    };
    return data[modelId] ?? [];
  }

  /// 保存画布数据到本地
  Future<void> _saveCanvasData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 准备保存的数据
      final canvasData = {
        'offset': {'dx': _canvasOffset.dx, 'dy': _canvasOffset.dy},
        'scale': _scale,
        'nodes': _nodes
            .map(
              (node) => {
                'id': node.id,
                'type': node.type.toString(),
                'position': {'dx': node.position.dx, 'dy': node.position.dy},
                'size': {'width': node.size.width, 'height': node.size.height},
                'data': node.data.map((key, value) {
                  // 只保存可序列化的数据
                  if (value is String ||
                      value is num ||
                      value is bool ||
                      value == null) {
                    return MapEntry(key, value);
                  }
                  if (value is Color) {
                    return MapEntry(key, value.toARGB32());
                  }
                  if (value is List) {
                    return MapEntry(key, value);
                  }
                  return MapEntry(key, value.toString());
                }),
              },
            )
            .toList(),
        'strokes': _strokes
            .map(
              (stroke) => {
                'points': stroke.points
                    .map((p) => {'dx': p.dx, 'dy': p.dy})
                    .toList(),
                'color': stroke.color.value,
                'strokeWidth': stroke.strokeWidth,
              },
            )
            .toList(),
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

          _nodes.add(
            CanvasNode(
              id: node['id'] as String,
              type: type,
              position: Offset(
                position['dx'] as double,
                position['dy'] as double,
              ),
              size: Size(size['width'] as double, size['height'] as double),
              data: data,
            ),
          );
        }
      }

      // 恢复涂鸦
      final strokes = canvasData['strokes'] as List<dynamic>?;
      if (strokes != null) {
        _strokes.clear();
        for (final strokeData in strokes) {
          final stroke = strokeData as Map<String, dynamic>;
          final points = (stroke['points'] as List<dynamic>)
              .map(
                (p) => Offset(
                  (p['dx'] as num).toDouble(),
                  (p['dy'] as num).toDouble(),
                ),
              )
              .toList();
          final color = Color(stroke['color'] as int);
          final strokeWidth = (stroke['strokeWidth'] as num).toDouble();

          _strokes.add(
            DrawingStroke(
              points: points,
              color: color,
              strokeWidth: strokeWidth,
            ),
          );
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
    final provider =
        node.data['provider'] as String? ??
        (isImage ? _imageProvider : _videoProvider);
    final defaultModels = _getModelsForProvider(
      provider,
      isImage ? 'image' : 'video',
    );
    final model =
        node.data['model'] ??
        (defaultModels.isNotEmpty ? defaultModels.first : '');
    final prompt = node.data['prompt'] ?? '';

    if (prompt.trim().isEmpty) {
      _showMessage('请输入提示词');
      return;
    }

    debugPrint('========== 开始生成 ==========');
    debugPrint('服务商: $provider');
    debugPrint('模型: $model');
    debugPrint(
      '提示词: ${prompt.substring(0, prompt.length > 20 ? 20 : prompt.length)}',
    );

    _logger.info(
      '开始生成${isImage ? '图片' : '视频'}',
      module: 'AI画布',
      extra: {
        '服务商': provider,
        '模型': model,
        '提示词': prompt.substring(0, prompt.length > 20 ? 20 : prompt.length),
      },
    );

    try {
      // 标记为生成中
      setState(() {
        node.data['isGenerating'] = true;
      });

      // ✅ 检查是否为网页服务商
      final isGoogleFlow = provider.toLowerCase() == 'google_flow';
      final isViduWeb = ['vidu', 'jimeng'].contains(provider.toLowerCase());

      // ========== Google Flow 图片生成 ==========
      if (isGoogleFlow && isImage) {
        _logger.info(
          '使用 Google Flow 生成图片',
          module: 'AI画布',
          extra: {'provider': provider},
        );

        final aigcClient = AutomationApiClient();
        try {
          final isHealthy = await aigcClient.checkHealth();
          if (!isHealthy) {
            throw Exception('Python API 服务未启动\n\n请先启动 Python 服务');
          }

          final prefs = await SharedPreferences.getInstance();
          final payload = <String, dynamic>{
            'prompt': prompt,
            'model': model,
            'aspectRatio': node.data['imageRatio'] as String? ?? '1:1',
          };

          // 保存路径
          final canvasSavePath = prefs.getString('canvas_save_path');
          final imgSavePath = prefs.getString('image_save_path');
          final saveDirPath =
              (canvasSavePath != null && canvasSavePath.isNotEmpty)
              ? canvasSavePath
              : (imgSavePath != null && imgSavePath.isNotEmpty)
              ? imgSavePath
              : null;
          if (saveDirPath != null) {
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final fileName = 'canvas_flow_${timestamp}_${node.id}.png';
            payload['savePath'] = path.join(saveDirPath, fileName);
          }

          // 参考图片
          final referenceImages =
              node.data['referenceImages'] as List<String>? ?? [];
          if (referenceImages.isNotEmpty) {
            payload['referenceFile'] = referenceImages;
          }

          final submitResult = await aigcClient.submitGenerationTask(
            platform: 'google_flow',
            toolType: 'text2image',
            payload: payload,
          );

          final tid = submitResult.taskIds?.first ?? submitResult.taskId;
          _logger.success('Google Flow 任务提交成功: $tid', module: 'AI画布');

          final pollResult = await aigcClient.pollTaskStatus(
            taskId: tid,
            interval: const Duration(seconds: 5),
            maxAttempts: 60,
          );

          if (pollResult.isSuccess) {
            final imagePath = pollResult.localImagePath ?? pollResult.imageUrl;
            if (imagePath == null || imagePath.isEmpty) {
              throw Exception('任务完成但未返回图片地址');
            }

            String finalPath = imagePath;
            if (imagePath.startsWith('http')) {
              final downloaded = await _downloadAndSaveFile(imagePath, true);
              if (downloaded != null) {
                finalPath = downloaded;
              }
            }

            setState(() {
              node.data['generatedImagePath'] = finalPath;
              node.data['_sizeAdjusted'] = false;
              node.data['isGenerating'] = false;
            });

            _saveCanvasData();
            _logger.success(
              'Google Flow 图片生成成功',
              module: 'AI画布',
              extra: {'文件': finalPath},
            );
            _showMessage('图片生成成功！');
          } else {
            throw Exception(pollResult.error ?? 'Google Flow 生成失败');
          }
        } finally {
          aigcClient.dispose();
        }
        return;
      }

      if (isViduWeb && !isImage) {
        // ========== VIDU 网页服务商路线（参考批量空间实现） ==========
        _logger.info(
          '使用网页服务商生成视频',
          module: 'AI画布',
          extra: {'provider': provider},
        );

        final prefs = await SharedPreferences.getInstance();
        final webTool = ProviderPreferenceHelper.getVideoWebTool(
          prefs,
          provider,
        );
        final webModel = ProviderPreferenceHelper.getVideoWebModel(
          prefs,
          provider,
        );

        if (webTool == null || webTool.isEmpty) {
          throw Exception('未配置网页服务商工具\n\n请前往设置页面选择工具类型（如：文生视频）');
        }
        if (webModel == null || webModel.isEmpty) {
          throw Exception('未配置网页服务商模型\n\n请前往设置页面选择模型（如：Vidu Q3）');
        }

        final aigcClient = AutomationApiClient();
        try {
          final isHealthy = await aigcClient.checkHealth();
          if (!isHealthy) {
            throw Exception(
              'Python API 服务未启动\n\n'
              '请先启动 Python 服务：\n'
              '1. 打开命令行\n'
              '2. 进入项目目录\n'
              '3. 运行: python python_backend/web_automation/api_server.py',
            );
          }

          _logger.success('Python API 服务连接成功', module: 'AI画布');

          // 构建 payload
          final payload = <String, dynamic>{
            'prompt': prompt,
            'model': webModel,
          };

          // 保存路径
          final savePath = prefs.getString('video_save_path');
          if (savePath != null && savePath.isNotEmpty) {
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final fileName = 'canvas_video_${timestamp}_${node.id}.mp4';
            payload['savePath'] = path.join(savePath, fileName);
          }

          // 参考图片处理
          final referenceImages =
              node.data['referenceImages'] as List<String>? ?? [];
          final firstFrameImage = node.data['firstFrameImage'] as String?;
          if (webTool == 'img2video') {
            final imgSource =
                firstFrameImage ??
                (referenceImages.isNotEmpty ? referenceImages.first : null);
            if (imgSource == null) {
              throw Exception('图生视频需要提供参考图片');
            }
            payload['imageUrl'] = imgSource;
          }
          if (webTool == 'ref2video') {
            // 检查prompt中是否包含 [📷name] 占位符（图片库内联模式）
            final hasInlinePlaceholders = RegExp(
              r'\[📷[^\]]+\]',
            ).hasMatch(prompt);
            if (hasInlinePlaceholders) {
              final segments = await _parsePromptToSegments(prompt, prefs);
              if (segments.isNotEmpty) {
                payload['segments'] = segments;
              }
            } else if (referenceImages.isNotEmpty) {
              payload['referenceFile'] = referenceImages.first;
            }
          }

          // ✅ 即梦：始终传递模式（默认全能参考）
          if (provider.toLowerCase() == 'jimeng') {
            payload['mode'] =
                ProviderPreferenceHelper.getVideoWebMode(prefs, provider) ??
                'all_ref';

            // 有参考图时传递图片和角色名
            if (referenceImages.isNotEmpty) {
              payload['referenceImages'] = referenceImages;
              final charNames =
                  node.data['characterNames'] as List<String>? ?? [];
              if (charNames.isNotEmpty) {
                payload['characterNames'] = charNames;
              }
            }
          }

          // 视频参数
          final videoRatio = node.data['videoRatio'] as String? ?? '16:9';
          final videoQuality = node.data['resolution'] as String? ?? '1K';
          payload['aspectRatio'] = videoRatio;
          payload['resolution'] = videoQuality;
          payload['duration'] = node.data['ratio'] ?? '5s';
          payload['batchCount'] = 1;

          // ✅ Vidu 去水印开关
          final viduWmFree = ProviderPreferenceHelper.getVideoWatermarkFree(
            prefs,
            provider,
          );
          if (viduWmFree) {
            payload['watermarkFree'] = true;
          }

          _logger.info(
            '提交 VIDU 生成任务',
            module: 'AI画布',
            extra: {'tool': webTool, 'model': webModel},
          );

          // 提交任务
          final submitResult = await aigcClient.submitGenerationTask(
            platform: provider,
            toolType: webTool,
            payload: payload,
          );

          final taskIds = submitResult.taskIds ?? [submitResult.taskId];
          final tid = taskIds.first;

          _logger.success('VIDU 任务提交成功: $tid', module: 'AI画布');

          // 轮询任务状态
          final pollResult = await aigcClient.pollTaskStatus(
            taskId: tid,
            interval: const Duration(seconds: 3),
            maxAttempts: 300,
          );

          if (pollResult.isSuccess) {
            final videoPath = pollResult.localVideoPath ?? pollResult.videoUrl;
            if (videoPath == null || videoPath.isEmpty) {
              throw Exception('任务完成但未返回视频地址');
            }

            _logger.success('VIDU 视频生成完成: $videoPath', module: 'AI画布');

            // 提取首帧缩略图
            if (!videoPath.startsWith('http') && videoPath.endsWith('.mp4')) {
              try {
                final thumbnailPath = videoPath.replaceAll('.mp4', '.jpg');
                final ffmpeg = FFmpegService();
                await ffmpeg.extractFrame(
                  videoPath: videoPath,
                  outputPath: thumbnailPath,
                );
              } catch (e) {
                _logger.warning('提取首帧失败: $e', module: 'AI画布');
              }
            }

            // 如果是网络URL，下载到本地
            String finalPath = videoPath;
            if (videoPath.startsWith('http')) {
              final downloaded = await _downloadAndSaveFile(videoPath, false);
              if (downloaded != null) {
                finalPath = downloaded;
              } else {
                throw Exception('下载视频文件失败');
              }
            }

            // 清理旧播放器
            final oldPlayer = _videoPlayers[node.id];
            if (oldPlayer != null) {
              try {
                oldPlayer.dispose();
              } catch (_) {}
            }
            _videoPlayers.remove(node.id);
            _videoControllers.remove(node.id);

            setState(() {
              node.data['generatedVideoPath'] = finalPath;
              node.data['_sizeAdjusted'] = false;
              node.data['isGenerating'] = false;
            });

            _saveCanvasData();
            _logger.success('生成成功', module: 'AI画布', extra: {'文件': finalPath});
            _showMessage('视频生成成功！');
          } else {
            throw Exception(pollResult.error ?? 'VIDU 生成失败');
          }
        } finally {
          aigcClient.dispose();
        }
        return;
      }

      // 读取 API 配置
      final modelType = isImage ? 'image' : 'video';
      final baseUrl = await _storage.getBaseUrl(
        provider: provider,
        modelType: modelType,
      );
      final apiKey = await _storage.getApiKey(
        provider: provider,
        modelType: modelType,
      );
      final configModel = await _storage.getModel(
        provider: provider,
        modelType: modelType,
      );

      if (baseUrl == null || apiKey == null) {
        throw Exception('未配置 $provider API');
      }

      final config = ApiConfig(
        provider: provider,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: configModel,
      );
      final apiFactory = ApiFactory();
      final service = apiFactory.createService(provider, config);

      // 获取参考图片
      final referenceImages =
          node.data['referenceImages'] as List<String>? ?? [];

      debugPrint('========== 参考图片信息 ==========');
      debugPrint('node.data 包含的键: ${node.data.keys.toList()}');
      debugPrint(
        'referenceImages 类型: ${node.data['referenceImages']?.runtimeType}',
      );
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
      final imageRatio = node.data['ratio'] as String? ?? '1:1';
      final imageQuality = node.data['resolution'] as String? ?? '1K';
      final videoRatio = node.data['videoRatio'] as String? ?? '16:9';
      final videoQuality = node.data['resolution'] as String? ?? '1K';

      if (isImage) {
        // 图片生成参数
        parameters['size'] = imageRatio;
        parameters['quality'] = imageQuality;
      } else {
        // 视频生成参数
        parameters['duration'] = node.data['ratio'] ?? '5s';
        parameters['resolution'] = videoQuality;
        parameters['size'] = videoRatio; // 视频比例
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
          debugPrint(
            '  - workflow_name: ${workflow['name'] ?? workflow['id']}',
          );
        } else {
          debugPrint('⚠️ 未找到工作流: $model');
          debugPrint('可用工作流列表:');
          for (var w in _comfyUIWorkflows) {
            debugPrint('  - ${w['name'] ?? w['id']}');
          }
          throw Exception('未找到工作流: $model');
        }

        // 优先使用设置里配的模型
        final effectiveModel = configModel ?? model;
        debugPrint(
          '调用 API - 模型参数: $effectiveModel (设置: $configModel, 节点: $model)',
        );

        // ✅ 根据节点类型调用不同的方法
        result = isImage
            ? await service.generateImages(
                prompt: prompt,
                model: effectiveModel,
                ratio: imageRatio,
                quality: imageQuality,
                referenceImages: allReferenceImages.isNotEmpty
                    ? allReferenceImages
                    : null,
                parameters: parameters,
              )
            : await service.generateVideos(
                prompt: prompt,
                model: effectiveModel,
                ratio: videoRatio,
                quality: videoQuality,
                referenceImages: allReferenceImages.isNotEmpty
                    ? allReferenceImages
                    : null,
                parameters: parameters,
              );
      } else {
        result = isImage
            ? await service.generateImages(
                prompt: prompt,
                model: model,
                ratio: imageRatio,
                quality: imageQuality,
                referenceImages: allReferenceImages.isNotEmpty
                    ? allReferenceImages
                    : null,
                parameters: parameters,
              )
            : await service.generateVideos(
                prompt: prompt,
                model: model,
                ratio: videoRatio,
                quality: videoQuality,
                referenceImages: allReferenceImages.isNotEmpty
                    ? allReferenceImages
                    : null,
                parameters: parameters,
              );
      }

      // 处理结果
      if (result.isSuccess && result.data != null) {
        debugPrint('========== 处理生成结果 ==========');
        debugPrint('结果类型: ${result.data.runtimeType}');

        List<String> urls = [];

        // 处理不同的返回格式
        if (result.data is List<ImageResponse>) {
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
          _logger.info(
            '获取到 ${urls.length} 个URL',
            module: 'AI画布',
            extra: {'第一个URL': urls.first},
          );

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

      _logger.info(
        'HTTP响应',
        module: 'AI画布',
        extra: {'状态码': response.statusCode, '内容长度': response.bodyBytes.length},
      );

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        // 优先使用画布空间保存路径
        final canvasSavePath = prefs.getString('canvas_save_path') ?? '';
        final savePath = canvasSavePath.isNotEmpty
            ? canvasSavePath
            : (prefs.getString(
                    isImage ? 'image_save_path' : 'video_save_path',
                  ) ??
                  '');
        final dir = Directory(
          savePath.isNotEmpty ? savePath : Directory.systemTemp.path,
        );

        debugPrint('保存目录: ${dir.path}');
        debugPrint('使用画布空间保存路径: ${canvasSavePath.isNotEmpty}');

        if (!await dir.exists()) {
          await dir.create(recursive: true);
          _logger.info('创建保存目录', module: 'AI画布', extra: {'路径': dir.path});
        }

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final extension = isImage ? 'png' : 'mp4';
        final filename =
            'canvas_${isImage ? 'image' : 'video'}_$timestamp.$extension';
        final file = File(path.join(dir.path, filename));

        debugPrint('保存文件: ${file.path}');

        await file.writeAsBytes(response.bodyBytes);

        debugPrint('✅ 文件保存成功');

        _logger.success(
          '文件保存成功',
          module: 'AI画布',
          extra: {
            '路径': file.path,
            '大小': '${(response.bodyBytes.length / 1024).toStringAsFixed(2)} KB',
          },
        );

        return file.path;
      } else {
        debugPrint('❌ HTTP请求失败: ${response.statusCode}');
        _logger.error(
          'HTTP请求失败',
          module: 'AI画布',
          extra: {
            '状态码': response.statusCode,
            '响应': response.body.substring(
              0,
              response.body.length > 200 ? 200 : response.body.length,
            ),
          },
        );
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
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
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

      debugPrint(
        '[调整大小] 图片尺寸: ${imageWidth.toInt()}x${imageHeight.toInt()}, 宽高比: ${aspectRatio.toStringAsFixed(2)}',
      );

      // 保存宽高比信息，用于后续手动调整大小时保持比例
      node.data['_imageAspectRatio'] = aspectRatio;

      // 判断是生成的图片还是插入的图片
      final isGeneratedImage = node.data['generatedImagePath'] != null;

      // 计算新的节点尺寸（保持宽高比，不留白）
      double finalWidth, finalHeight;

      if (aspectRatio >= 1.0) {
        // 横图：宽度大于等于高度，以宽度为基准
        final baseWidth = isGeneratedImage
            ? 270.0
            : 400.0; // 生成图片缩小到约 270px（400的2/3）
        finalWidth = baseWidth;
        finalHeight = baseWidth / aspectRatio;

        // 限制尺寸范围
        finalWidth = finalWidth.clamp(200.0, 4000.0);
        finalHeight = finalHeight.clamp(150.0, 4000.0);
      } else {
        // 竖图：高度大于宽度，以高度为基准
        final baseHeight = isGeneratedImage
            ? 270.0
            : 400.0; // 生成图片缩小到约 270px（400的2/3）
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

        _logger.info(
          '调整节点大小',
          module: 'AI画布',
          extra: {
            '图片尺寸': '${imageWidth.toInt()}x${imageHeight.toInt()}',
            '宽高比': aspectRatio.toStringAsFixed(2),
            '图片方向': aspectRatio >= 1.0 ? '横图' : '竖图',
            '节点尺寸': '${finalWidth.toInt()}x${finalHeight.toInt()}',
            '是否生成': isGeneratedImage,
          },
        );
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

    _scaleAnimation =
        Tween<double>(begin: _scale, end: targetScale).animate(
          CurvedAnimation(
            parent: _scaleAnimationController,
            curve: Curves.easeOut,
          ),
        )..addListener(() {
          setState(() {
            final currentScale = _scaleAnimation.value;

            // 如果有焦点，以焦点为中心缩放
            if (_zoomFocalPoint != null &&
                _zoomStartScale != null &&
                _zoomStartOffset != null) {
              final scaleChange = currentScale / _zoomStartScale!;
              _canvasOffset =
                  _zoomFocalPoint! -
                  (_zoomFocalPoint! - _zoomStartOffset!) * scaleChange;
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

  /// 自适应缩放：让所有内容刚好适应窗口
  void _zoomToFit() {
    if (_nodes.isEmpty && _strokes.isEmpty) {
      _resetView();
      return;
    }

    // 计算所有元素的包围盒（画布坐标）
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (var node in _nodes) {
      if (node.position.dx < minX) minX = node.position.dx;
      if (node.position.dy < minY) minY = node.position.dy;
      if (node.position.dx + node.size.width > maxX)
        maxX = node.position.dx + node.size.width;
      if (node.position.dy + node.size.height > maxY)
        maxY = node.position.dy + node.size.height;
    }
    for (var stroke in _strokes) {
      for (var point in stroke.points) {
        if (point.dx < minX) minX = point.dx;
        if (point.dy < minY) minY = point.dy;
        if (point.dx > maxX) maxX = point.dx;
        if (point.dy > maxY) maxY = point.dy;
      }
    }

    if (minX == double.infinity) {
      _resetView();
      return;
    }

    final contentWidth = maxX - minX;
    final contentHeight = maxY - minY;
    if (contentWidth <= 0 || contentHeight <= 0) {
      _resetView();
      return;
    }

    final viewSize =
        (context.findRenderObject() as RenderBox?)?.size ??
        const Size(800, 600);
    final padding = 60.0;
    final availableWidth = viewSize.width - padding * 2;
    final availableHeight = viewSize.height - padding * 2;

    final scaleX = availableWidth / contentWidth;
    final scaleY = availableHeight / contentHeight;
    final targetScale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.1, 5.0);

    setState(() {
      _scale = targetScale;
      _canvasOffset = Offset(
        (viewSize.width - contentWidth * targetScale) / 2 - minX * targetScale,
        (viewSize.height - contentHeight * targetScale) / 2 -
            minY * targetScale,
      );
    });
  }

  void _selectNode(String? nodeId) {
    setState(() {
      _selectedNodeId = nodeId;
    });
  }

  // ==================== 撤销/重做系统 ====================

  /// 创建当前画布状态快照
  Map<String, dynamic> _createSnapshot() {
    return {
      'nodes': _nodes
          .map(
            (node) => {
              'id': node.id,
              'type': node.type.toString(),
              'position': {'dx': node.position.dx, 'dy': node.position.dy},
              'size': {'width': node.size.width, 'height': node.size.height},
              'data': Map<String, dynamic>.from(
                node.data.map((key, value) {
                  if (value is String ||
                      value is num ||
                      value is bool ||
                      value == null) {
                    return MapEntry(key, value);
                  }
                  if (value is Color) {
                    return MapEntry(key, value.toARGB32());
                  }
                  if (value is List) {
                    return MapEntry(key, value);
                  }
                  return MapEntry(key, value.toString());
                }),
              ),
            },
          )
          .toList(),
      'strokes': _strokes
          .map(
            (stroke) => {
              'points': stroke.points
                  .map((p) => {'dx': p.dx, 'dy': p.dy})
                  .toList(),
              'color': stroke.color.value,
              'strokeWidth': stroke.strokeWidth,
            },
          )
          .toList(),
    };
  }

  /// 记录当前状态到撤销栈（在变更前调用）
  void _pushUndo() {
    _undoStack.add(_createSnapshot());
    if (_undoStack.length > _maxUndoHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  /// 拖动开始时暂存快照
  void _startTrackingForUndo() {
    _pendingUndoSnapshot = _createSnapshot();
    _dragDidMove = false;
  }

  /// 拖动结束后提交快照（仅在实际移动时）
  void _commitPendingUndo() {
    if (_pendingUndoSnapshot != null && _dragDidMove) {
      _undoStack.add(_pendingUndoSnapshot!);
      if (_undoStack.length > _maxUndoHistory) {
        _undoStack.removeAt(0);
      }
      _redoStack.clear();
    }
    _pendingUndoSnapshot = null;
    _dragDidMove = false;
  }

  /// 撤销
  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_createSnapshot());
    _restoreSnapshot(_undoStack.removeLast());
  }

  /// 重做
  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_createSnapshot());
    _restoreSnapshot(_redoStack.removeLast());
  }

  /// 从快照恢复画布状态
  void _restoreSnapshot(Map<String, dynamic> snapshot) {
    // 清理被移除节点的视频播放器
    final restoredNodeIds = <String>{};
    for (final nodeData in (snapshot['nodes'] as List)) {
      restoredNodeIds.add((nodeData as Map<String, dynamic>)['id'] as String);
    }
    for (final nodeId
        in _nodes.map((n) => n.id).toSet().difference(restoredNodeIds)) {
      _videoPlayers[nodeId]?.dispose();
      _videoPlayers.remove(nodeId);
      _videoControllers.remove(nodeId);
    }

    setState(() {
      // 恢复节点
      _nodes.clear();
      for (final nodeData in (snapshot['nodes'] as List)) {
        final node = nodeData as Map<String, dynamic>;
        final typeStr = node['type'] as String;
        final type = NodeType.values.firstWhere(
          (t) => t.toString() == typeStr,
          orElse: () => NodeType.text,
        );
        final position = node['position'] as Map<String, dynamic>;
        final size = node['size'] as Map<String, dynamic>;
        _nodes.add(
          CanvasNode(
            id: node['id'] as String,
            type: type,
            position: Offset(
              position['dx'] as double,
              position['dy'] as double,
            ),
            size: Size(size['width'] as double, size['height'] as double),
            data: Map<String, dynamic>.from(node['data'] as Map),
          ),
        );
      }

      // 恢复笔画
      _strokes.clear();
      for (final strokeData in (snapshot['strokes'] as List)) {
        final stroke = strokeData as Map<String, dynamic>;
        final points = (stroke['points'] as List)
            .map(
              (p) => Offset(
                (p['dx'] as num).toDouble(),
                (p['dy'] as num).toDouble(),
              ),
            )
            .toList();
        _strokes.add(
          DrawingStroke(
            points: points,
            color: Color(stroke['color'] as int),
            strokeWidth: (stroke['strokeWidth'] as num).toDouble(),
          ),
        );
      }

      // 清除选择状态
      _selectedNodeId = null;
      _selectedNodeIds.clear();
      _selectedStroke = null;
      _selectedStrokes.clear();
      _draggingNode = null;
      _draggingStroke = null;
    });
    _saveCanvasData();
  }

  bool get _canUndo => _undoStack.isNotEmpty;
  bool get _canRedo => _redoStack.isNotEmpty;

  // ==================== 对齐参考线系统 ====================

  /// 计算拖动节点的吸附位置和参考线
  /// 返回吸附后的 delta 修正值（画布坐标）
  Offset _calcSnapAndGuides(CanvasNode dragNode, Offset proposedPosition) {
    _alignGuideX.clear();
    _alignGuideY.clear();

    final dragRect = Rect.fromLTWH(
      proposedPosition.dx,
      proposedPosition.dy,
      dragNode.size.width,
      dragNode.size.height,
    );
    final dragCX = dragRect.left + dragRect.width / 2;
    final dragCY = dragRect.top + dragRect.height / 2;

    // 收集所有目标边缘（排除被拖拽的节点和其他选中节点）
    final movingIds = <String>{dragNode.id, ..._selectedNodeIds};
    final threshold = _snapThreshold / _scale;

    double snapDx = 0;
    double snapDy = 0;
    double bestDistX = threshold + 1;
    double bestDistY = threshold + 1;

    for (var other in _nodes) {
      if (movingIds.contains(other.id)) continue;

      final oRect = Rect.fromLTWH(
        other.position.dx,
        other.position.dy,
        other.size.width,
        other.size.height,
      );
      final oCX = oRect.left + oRect.width / 2;
      final oCY = oRect.top + oRect.height / 2;

      // X 轴对齐检测：左-左、右-右、中-中、左-右、右-左
      final xPairs = [
        [dragRect.left, oRect.left],
        [dragRect.right, oRect.right],
        [dragCX, oCX],
        [dragRect.left, oRect.right],
        [dragRect.right, oRect.left],
      ];
      for (var pair in xPairs) {
        final dist = (pair[0] - pair[1]).abs();
        if (dist < threshold && dist < bestDistX) {
          bestDistX = dist;
          snapDx = pair[1] - pair[0];
          _alignGuideX = [pair[1] * _scale + _canvasOffset.dx];
        }
      }

      // Y 轴对齐检测：上-上、下-下、中-中、上-下、下-上
      final yPairs = [
        [dragRect.top, oRect.top],
        [dragRect.bottom, oRect.bottom],
        [dragCY, oCY],
        [dragRect.top, oRect.bottom],
        [dragRect.bottom, oRect.top],
      ];
      for (var pair in yPairs) {
        final dist = (pair[0] - pair[1]).abs();
        if (dist < threshold && dist < bestDistY) {
          bestDistY = dist;
          snapDy = pair[1] - pair[0];
          _alignGuideY = [pair[1] * _scale + _canvasOffset.dy];
        }
      }
    }

    return Offset(snapDx, snapDy);
  }

  // ==================== 复制/粘贴系统 ====================

  List<Map<String, dynamic>>? _clipboardNodes;
  List<Map<String, dynamic>>? _clipboardStrokes;

  /// 复制选中元素到剪贴板
  void _copySelected() {
    final nodesToCopy = <Map<String, dynamic>>[];
    final strokesToCopy = <Map<String, dynamic>>[];

    // 复制选中节点
    final selectedIds = <String>{};
    if (_selectedNodeId != null) selectedIds.add(_selectedNodeId!);
    selectedIds.addAll(_selectedNodeIds);

    for (var node in _nodes) {
      if (selectedIds.contains(node.id)) {
        nodesToCopy.add({
          'type': node.type.toString(),
          'position': {'dx': node.position.dx, 'dy': node.position.dy},
          'size': {'width': node.size.width, 'height': node.size.height},
          'data': Map<String, dynamic>.from(
            node.data.map((key, value) {
              if (value is String ||
                  value is num ||
                  value is bool ||
                  value == null) {
                return MapEntry(key, value);
              }
              if (value is Color) {
                return MapEntry(key, value.toARGB32());
              }
              if (value is List) {
                return MapEntry(key, value);
              }
              return MapEntry(key, value.toString());
            }),
          ),
        });
      }
    }

    // 复制选中笔画
    if (_selectedStroke != null && _selectedStrokes.isEmpty) {
      strokesToCopy.add({
        'points': _selectedStroke!.points
            .map((p) => {'dx': p.dx, 'dy': p.dy})
            .toList(),
        'color': _selectedStroke!.color.value,
        'strokeWidth': _selectedStroke!.strokeWidth,
      });
    }
    for (var stroke in _selectedStrokes) {
      strokesToCopy.add({
        'points': stroke.points.map((p) => {'dx': p.dx, 'dy': p.dy}).toList(),
        'color': stroke.color.value,
        'strokeWidth': stroke.strokeWidth,
      });
    }

    if (nodesToCopy.isNotEmpty || strokesToCopy.isNotEmpty) {
      _clipboardNodes = nodesToCopy;
      _clipboardStrokes = strokesToCopy;
    }
  }

  /// 粘贴剪贴板内容（偏移 30px 避免重叠）
  void _pasteFromClipboard() {
    if ((_clipboardNodes == null || _clipboardNodes!.isEmpty) &&
        (_clipboardStrokes == null || _clipboardStrokes!.isEmpty))
      return;

    _pushUndo();
    const offset = 30.0;

    setState(() {
      _selectedNodeIds.clear();
      _selectedNodeId = null;
      _selectedStroke = null;
      _selectedStrokes.clear();

      // 粘贴节点
      if (_clipboardNodes != null) {
        for (var nodeData in _clipboardNodes!) {
          final position = nodeData['position'] as Map<String, dynamic>;
          final size = nodeData['size'] as Map<String, dynamic>;
          final typeStr = nodeData['type'] as String;
          final type = NodeType.values.firstWhere(
            (t) => t.toString() == typeStr,
            orElse: () => NodeType.text,
          );
          final newId =
              DateTime.now().millisecondsSinceEpoch.toString() +
              '_${_nodes.length}';
          final newNode = CanvasNode(
            id: newId,
            type: type,
            position: Offset(
              (position['dx'] as double) + offset,
              (position['dy'] as double) + offset,
            ),
            size: Size(size['width'] as double, size['height'] as double),
            data: Map<String, dynamic>.from(nodeData['data'] as Map),
          );
          _nodes.add(newNode);
          _selectedNodeIds.add(newId);
        }
      }

      // 粘贴笔画
      if (_clipboardStrokes != null) {
        for (var strokeData in _clipboardStrokes!) {
          final points = (strokeData['points'] as List)
              .map(
                (p) => Offset(
                  (p['dx'] as num).toDouble() + offset,
                  (p['dy'] as num).toDouble() + offset,
                ),
              )
              .toList();
          final newStroke = DrawingStroke(
            points: points,
            color: Color(strokeData['color'] as int),
            strokeWidth: (strokeData['strokeWidth'] as num).toDouble(),
          );
          _strokes.add(newStroke);
          _selectedStrokes.add(newStroke);
        }
      }
    });

    _saveCanvasData();
  }

  /// 快速复制（复制+粘贴一步完成）
  void _duplicate() {
    _copySelected();
    _pasteFromClipboard();
  }

  // ==================== 分组系统 ====================

  /// 将选中的节点分组
  void _groupSelected() {
    if (_selectedNodeIds.length < 2) return;
    _pushUndo();
    final groupId = 'g_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      for (var node in _nodes) {
        if (_selectedNodeIds.contains(node.id)) {
          node.data['groupId'] = groupId;
        }
      }
    });
    _saveCanvasData();
  }

  /// 取消选中节点的分组
  void _ungroupSelected() {
    _pushUndo();
    final selectedIds = {..._selectedNodeIds};
    if (_selectedNodeId != null) selectedIds.add(_selectedNodeId!);
    setState(() {
      for (var node in _nodes) {
        if (selectedIds.contains(node.id)) {
          node.data.remove('groupId');
        }
      }
    });
    _saveCanvasData();
  }

  /// 自动扩展选择到同一组的所有节点
  void _expandSelectionToGroup(String nodeId) {
    final node = _nodes.where((n) => n.id == nodeId).firstOrNull;
    if (node == null) return;
    final groupId = node.data['groupId'] as String?;
    if (groupId == null) return;
    for (var other in _nodes) {
      if (other.data['groupId'] == groupId) {
        _selectedNodeIds.add(other.id);
      }
    }
  }

  /// 删除选中的元素（节点和涂鸦）
  void _deleteSelectedElements() {
    _pushUndo();
    setState(() {
      // 删除选中的节点
      if (_selectedNodeId != null) {
        final nodeToRemove = _nodes
            .where((node) => node.id == _selectedNodeId)
            .firstOrNull;

        // 如果是视频节点，清理播放器
        if (nodeToRemove != null && nodeToRemove.type == NodeType.video) {
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
          final nodeToRemove = _nodes
              .where((node) => node.id == nodeId)
              .firstOrNull;

          // 如果是视频节点，清理播放器
          if (nodeToRemove != null && nodeToRemove.type == NodeType.video) {
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

      // 删除框选的多条涂鸦
      if (_selectedStrokes.isNotEmpty) {
        final count = _selectedStrokes.length;
        _strokes.removeWhere((s) => _selectedStrokes.contains(s));
        _selectedStrokes.clear();

        debugPrint('删除多条涂鸦: $count');
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
              focusNode: _canvasFocusNode,
              autofocus: true,
              onKeyEvent: (node, event) {
                // 焦点在文本输入框中时（AI 助手对话框、文本节点编辑等），放行键盘事件
                final primaryFocus = FocusManager.instance.primaryFocus;
                if (primaryFocus != null &&
                    primaryFocus != node &&
                    primaryFocus.context != null) {
                  bool isInTextField = false;
                  primaryFocus.context!.visitAncestorElements((element) {
                    if (element.widget is EditableText) {
                      isInTextField = true;
                      return false;
                    }
                    return true;
                  });
                  if (isInTextField) return KeyEventResult.ignored;
                }

                // 空格键按下/释放：切换拖动画布模式
                if (event.logicalKey == LogicalKeyboardKey.space) {
                  if (event is KeyDownEvent && !_isSpacePressed) {
                    setState(() => _isSpacePressed = true);
                    return KeyEventResult.handled;
                  } else if (event is KeyUpEvent) {
                    setState(() {
                      _isSpacePressed = false;
                      _isPanning = false;
                    });
                    return KeyEventResult.handled;
                  }
                }

                // 监听键盘事件
                if (event is KeyDownEvent) {
                  final isCtrl = HardwareKeyboard.instance.isControlPressed;
                  final isShift = HardwareKeyboard.instance.isShiftPressed;

                  // Ctrl+Z: 撤销
                  if (isCtrl &&
                      !isShift &&
                      event.logicalKey == LogicalKeyboardKey.keyZ) {
                    _undo();
                    return KeyEventResult.handled;
                  }
                  // Ctrl+Shift+Z 或 Ctrl+Y: 重做
                  if ((isCtrl &&
                          isShift &&
                          event.logicalKey == LogicalKeyboardKey.keyZ) ||
                      (isCtrl && event.logicalKey == LogicalKeyboardKey.keyY)) {
                    _redo();
                    return KeyEventResult.handled;
                  }
                  // Ctrl+C: 复制
                  if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyC) {
                    _copySelected();
                    return KeyEventResult.handled;
                  }
                  // Ctrl+V: 粘贴
                  if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyV) {
                    _pasteFromClipboard();
                    return KeyEventResult.handled;
                  }
                  // Ctrl+D: 快速复制
                  if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyD) {
                    _duplicate();
                    return KeyEventResult.handled;
                  }
                  // Ctrl+G: 分组
                  if (isCtrl &&
                      !isShift &&
                      event.logicalKey == LogicalKeyboardKey.keyG) {
                    _groupSelected();
                    return KeyEventResult.handled;
                  }
                  // Ctrl+Shift+G: 取消分组
                  if (isCtrl &&
                      isShift &&
                      event.logicalKey == LogicalKeyboardKey.keyG) {
                    _ungroupSelected();
                    return KeyEventResult.handled;
                  }
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
                      child: Row(
                        children: [
                          // 画布区域（占满剩余空间）
                          Expanded(
                            child: Stack(
                              children: [
                                // 画布交互区域（保持非定位，避免 GestureDetector 变全尺寸干扰手势竞技场）
                                MouseRegion(
                                  cursor: _currentTool == CanvasTool.draw
                                      ? SystemMouseCursors.precise
                                      : SystemMouseCursors.basic,
                                  child: Listener(
                                    onPointerDown: (event) {
                                      // 点击画布时收回焦点，确保键盘快捷键可用
                                      _canvasFocusNode.requestFocus();
                                      // 更新光标位置
                                      _cursorPosition = event.localPosition;
                                      // 检测中键按下
                                      if (event.buttons == 4) {
                                        setState(() {
                                          _isMiddleButtonPressed = true;
                                          _isPanning = true;
                                          _lastPanPosition =
                                              event.localPosition;
                                        });
                                      }
                                      // 空格+左键按下：拖动画布
                                      if (_isSpacePressed && event.buttons == 1) {
                                        setState(() {
                                          _isPanning = true;
                                          _lastPanPosition =
                                              event.localPosition;
                                        });
                                      }
                                    },
                                    onPointerUp: (event) {
                                      setState(() {
                                        _isMiddleButtonPressed = false;
                                        _isPanning = false;
                                      });
                                    },
                                    onPointerMove: (event) {
                                      // 更新光标位置
                                      _cursorPosition = event.localPosition;
                                      // 中键或空格+左键拖动画布
                                      if ((_isMiddleButtonPressed || (_isSpacePressed && event.buttons == 1)) &&
                                          _lastPanPosition != null) {
                                        setState(() {
                                          _isPanning = true;
                                          final delta =
                                              event.localPosition -
                                              _lastPanPosition!;
                                          _canvasOffset += delta;
                                          _lastPanPosition =
                                              event.localPosition;
                                        });
                                      }
                                    },
                                    onPointerSignal: (event) {
                                      if (event is PointerScrollEvent) {
                                        final isCtrl = HardwareKeyboard.instance.isControlPressed;
                                        if (isCtrl) {
                                          // Ctrl+滚轮：缩放画布（直接更新，不走动画，避免连续滚轮的帧间延迟）
                                          final delta = event.scrollDelta.dy;
                                          final targetScale =
                                              (_scale * (1 - delta / 400)).clamp(0.1, 5.0);
                                          final focalPoint = event.localPosition;
                                          setState(() {
                                            final scaleChange = targetScale / _scale;
                                            _canvasOffset = focalPoint -
                                                (focalPoint - _canvasOffset) * scaleChange;
                                            _scale = targetScale;
                                          });
                                        } else {
                                          // 普通滚轮：上下平移画布
                                          final isShift = HardwareKeyboard.instance.isShiftPressed;
                                          setState(() {
                                            if (isShift) {
                                              // Shift+滚轮：左右平移
                                              _canvasOffset = Offset(
                                                _canvasOffset.dx - event.scrollDelta.dy,
                                                _canvasOffset.dy,
                                              );
                                            } else {
                                              // 普通滚轮：上下平移
                                              _canvasOffset = Offset(
                                                _canvasOffset.dx - event.scrollDelta.dx,
                                                _canvasOffset.dy - event.scrollDelta.dy,
                                              );
                                            }
                                          });
                                        }
                                      }
                                    },
                                    child: GestureDetector(
                                      onDoubleTap: _resetView,
                                      onSecondaryTapDown: (details) {
                                        // 右键菜单——所有节点类型均支持
                                        if (_selectedStroke != null) {
                                          _showStrokeContextMenu(
                                            details.globalPosition,
                                          );
                                        } else if (_selectedNodeId != null) {
                                          final node = _nodes
                                              .where(
                                                (n) => n.id == _selectedNodeId,
                                              )
                                              .firstOrNull;
                                          if (node != null) {
                                            _showNodeContextMenu(
                                              details.globalPosition,
                                              node,
                                            );
                                          }
                                        }
                                      },
                                      onTapDown: (details) {
                                        // 任何操作开始时，隐藏工具栏
                                        if (_showBrushToolbar ||
                                            _showTextToolbar) {
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
                                              (details.localPosition.dx -
                                                      _canvasOffset.dx) /
                                                  _scale,
                                              (details.localPosition.dy -
                                                      _canvasOffset.dy) /
                                                  _scale,
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
                                          for (var stroke
                                              in _strokes.reversed) {
                                            if (_isPointNearStroke(
                                              details.localPosition,
                                              stroke,
                                            )) {
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
                                            node.position.dx * _scale +
                                                _canvasOffset.dx,
                                            node.position.dy * _scale +
                                                _canvasOffset.dy,
                                            node.size.width * _scale,
                                            node.size.height * _scale,
                                          );

                                          if (nodeRect.contains(
                                            details.localPosition,
                                          )) {
                                            hitNode = true;
                                            break;
                                          }
                                        }

                                        if (!hitNode &&
                                            _currentTool == CanvasTool.select) {
                                          _selectNode(null);
                                          _selectedNodeIds.clear(); // 清除多选状态
                                          _selectedStroke = null;
                                          _selectedStrokes.clear(); // 清除多涂鸦选中
                                          // 取消画布选择模式
                                          _cancelCanvasSelection();
                                        }
                                      },
                                      onPanStart: (details) {
                                        // 任何拖动操作开始时，隐藏工具栏
                                        if (_showBrushToolbar ||
                                            _showTextToolbar) {
                                          setState(() {
                                            _showBrushToolbar = false;
                                            _showTextToolbar = false;
                                          });
                                        }

                                        _lastPanPosition =
                                            details.localPosition;

                                        // 空格+拖动 或 拖动画布工具
                                        if (_isSpacePressed || _currentTool == CanvasTool.pan) {
                                          setState(() => _isPanning = true);
                                          return;
                                        }

                                        // 画笔工具：开始绘制
                                        if (_currentTool == CanvasTool.draw) {
                                          setState(() {
                                            // 将屏幕坐标转换为画布坐标
                                            final canvasPoint = Offset(
                                              (details.localPosition.dx -
                                                      _canvasOffset.dx) /
                                                  _scale,
                                              (details.localPosition.dy -
                                                      _canvasOffset.dy) /
                                                  _scale,
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
                                            _imageBoxStart =
                                                details.localPosition;
                                            _imageBoxEnd =
                                                details.localPosition;
                                          });
                                          return;
                                        } else if (_currentTool ==
                                            CanvasTool.video) {
                                          // 视频工具：开始拖动创建视频框
                                          setState(() {
                                            _isCreatingVideoBox = true;
                                            _videoBoxStart =
                                                details.localPosition;
                                            _videoBoxEnd =
                                                details.localPosition;
                                          });
                                          return;
                                        } else if (_currentTool ==
                                            CanvasTool.text) {
                                          // 文本工具：开始拖动创建文本框
                                          setState(() {
                                            _isCreatingTextBox = true;
                                            _textBoxStart =
                                                details.localPosition;
                                            _textBoxEnd = details.localPosition;
                                          });
                                          return;
                                        }

                                        // 选择工具
                                        if (_currentTool == CanvasTool.select) {
                                          // 检查是否点击到涂鸦
                                          for (var stroke
                                              in _strokes.reversed) {
                                            if (_isPointNearStroke(
                                              details.localPosition,
                                              stroke,
                                            )) {
                                              _startTrackingForUndo();
                                              setState(() {
                                                _draggingStroke = stroke;
                                                _draggingStrokeOffset = Offset(
                                                  (details.localPosition.dx -
                                                          _canvasOffset.dx) /
                                                      _scale,
                                                  (details.localPosition.dy -
                                                          _canvasOffset.dy) /
                                                      _scale,
                                                );
                                                _lastPanPosition =
                                                    details.localPosition;
                                                if (_selectedStrokes.contains(
                                                  stroke,
                                                )) {
                                                  // 点击的是已框选的笔画，保留多选状态
                                                  _selectedStroke = stroke;
                                                } else {
                                                  // 单选该笔画，清除其他选择
                                                  _selectedStroke = stroke;
                                                  _selectedNodeIds.clear();
                                                  _selectedStrokes.clear();
                                                  _selectNode(null);
                                                }
                                              });
                                              return;
                                            }
                                          }

                                          // 检查是否点击到节点或调整大小手柄
                                          for (var node in _nodes.reversed) {
                                            final nodeRect = Rect.fromLTWH(
                                              node.position.dx * _scale +
                                                  _canvasOffset.dx,
                                              node.position.dy * _scale +
                                                  _canvasOffset.dy,
                                              node.size.width * _scale,
                                              node.size.height * _scale,
                                            );

                                            // 检查是否点击调整大小手柄（只有单选时才显示调整手柄）
                                            if (_selectedNodeId == node.id &&
                                                _selectedNodeIds.isEmpty) {
                                              final handle = _getResizeHandle(
                                                details.localPosition,
                                                nodeRect,
                                              );
                                              if (handle != null) {
                                                _startTrackingForUndo();
                                                _resizingNode = node;
                                                _resizeHandle = handle;
                                                _lastPanPosition =
                                                    details.localPosition;
                                                return;
                                              }
                                            }

                                            if (nodeRect.contains(
                                              details.localPosition,
                                            )) {
                                              // 如果点击的节点在已选中的节点集合中，准备批量拖动
                                              if (_selectedNodeIds.contains(
                                                node.id,
                                              )) {
                                                _startTrackingForUndo();
                                                _draggingNode = node;
                                                _draggingOffset =
                                                    details.localPosition -
                                                    nodeRect.topLeft;
                                                _lastPanPosition =
                                                    details.localPosition;
                                                // 保留多选状态（包括笔画选择）
                                                return;
                                              }

                                              // 否则，单选该节点
                                              _startTrackingForUndo();
                                              _draggingNode = node;
                                              _draggingOffset =
                                                  details.localPosition -
                                                  nodeRect.topLeft;
                                              _selectNode(node.id);
                                              _selectedNodeIds.clear();
                                              _selectedStroke = null;
                                              _selectedStrokes.clear();
                                              // 自动扩展到同组节点
                                              if (node.data['groupId'] !=
                                                  null) {
                                                _selectedNodeIds.add(node.id);
                                                _expandSelectionToGroup(
                                                  node.id,
                                                );
                                              }
                                              return;
                                            }
                                          }

                                          // 没有点击到节点或涂鸦，开始框选
                                          _selectionStart =
                                              details.localPosition;
                                          _selectionEnd = details.localPosition;
                                        }
                                      },
                                      onPanUpdate: (details) {
                                        // 空格+拖动 或 拖动画布工具
                                        if ((_isSpacePressed || _currentTool == CanvasTool.pan) &&
                                            _lastPanPosition != null) {
                                          setState(() {
                                            _isPanning = true;
                                            final delta =
                                                details.localPosition -
                                                _lastPanPosition!;
                                            _canvasOffset += delta;
                                            _lastPanPosition =
                                                details.localPosition;
                                          });
                                          return;
                                        }

                                        setState(() {
                                          // 画笔工具：继续绘制
                                          if (_currentTool == CanvasTool.draw &&
                                              _currentStroke != null) {
                                            // 将屏幕坐标转换为画布坐标
                                            final canvasPoint = Offset(
                                              (details.localPosition.dx -
                                                      _canvasOffset.dx) /
                                                  _scale,
                                              (details.localPosition.dy -
                                                      _canvasOffset.dy) /
                                                  _scale,
                                            );
                                            _currentStroke!.points.add(
                                              canvasPoint,
                                            );
                                            return;
                                          }

                                          // 文本工具：拖动创建文本框
                                          if (_isCreatingTextBox &&
                                              _textBoxStart != null) {
                                            _textBoxEnd = details.localPosition;
                                            return;
                                          }

                                          // 图片工具：拖动创建图片框
                                          if (_isCreatingImageBox &&
                                              _imageBoxStart != null) {
                                            _imageBoxEnd =
                                                details.localPosition;
                                            return;
                                          }

                                          // 视频工具：拖动创建视频框
                                          if (_isCreatingVideoBox &&
                                              _videoBoxStart != null) {
                                            _videoBoxEnd =
                                                details.localPosition;
                                            return;
                                          }

                                          // 框选
                                          if (_currentTool ==
                                                  CanvasTool.select &&
                                              _selectionStart != null &&
                                              _draggingNode == null &&
                                              _resizingNode == null) {
                                            _selectionEnd =
                                                details.localPosition;
                                            return;
                                          }

                                          if (_resizingNode != null &&
                                              _resizeHandle != null) {
                                            _dragDidMove = true;
                                            // 调整大小
                                            final delta =
                                                (details.localPosition -
                                                    _lastPanPosition!) /
                                                _scale;
                                            _lastPanPosition =
                                                details.localPosition;

                                            // 获取媒体路径以计算宽高比（图片或视频）
                                            String? mediaPath;
                                            if (_resizingNode!.type ==
                                                NodeType.image) {
                                              mediaPath =
                                                  _resizingNode!
                                                      .data['generatedImagePath'] ??
                                                  _resizingNode!
                                                      .data['displayImagePath'];
                                            } else if (_resizingNode!.type ==
                                                NodeType.video) {
                                              mediaPath =
                                                  _resizingNode!
                                                      .data['generatedVideoPath'] ??
                                                  _resizingNode!
                                                      .data['displayVideoPath'];
                                            }

                                            // 如果有媒体文件且有宽高比信息，按照宽高比调整；否则自由调整
                                            if (mediaPath != null &&
                                                _resizingNode!
                                                        .data['_imageAspectRatio'] !=
                                                    null) {
                                              final aspectRatio =
                                                  _resizingNode!
                                                          .data['_imageAspectRatio']
                                                      as double;

                                              // 计算保持宽高比的最小尺寸
                                              // 如果宽高比 >= 1（横向），最小宽度100，最小高度 = 100/宽高比
                                              // 如果宽高比 < 1（竖向），最小高度100，最小宽度 = 100*宽高比
                                              double minWidth, minHeight;
                                              if (aspectRatio >= 1.0) {
                                                // 横图：以最小宽度为基准
                                                minWidth = 100.0;
                                                minHeight =
                                                    minWidth / aspectRatio;
                                              } else {
                                                // 竖图：以最小高度为基准
                                                minHeight = 100.0;
                                                minWidth =
                                                    minHeight * aspectRatio;
                                              }

                                              // 最大尺寸同理
                                              double maxWidth, maxHeight;
                                              if (aspectRatio >= 1.0) {
                                                // 横图：以最大宽度为基准
                                                maxWidth = 4000.0;
                                                maxHeight =
                                                    maxWidth / aspectRatio;
                                              } else {
                                                // 竖图：以最大高度为基准
                                                maxHeight = 4000.0;
                                                maxWidth =
                                                    maxHeight * aspectRatio;
                                              }

                                              // 根据拖动方向计算新尺寸（保持宽高比）
                                              double newWidth, newHeight;

                                              switch (_resizeHandle!) {
                                                case ResizeHandle.bottomRight:
                                                  // 右下角：根据宽度变化计算
                                                  newWidth =
                                                      _resizingNode!
                                                          .size
                                                          .width +
                                                      delta.dx;
                                                  break;
                                                case ResizeHandle.topLeft:
                                                  // 左上角：根据宽度变化计算（反向）
                                                  newWidth =
                                                      _resizingNode!
                                                          .size
                                                          .width -
                                                      delta.dx;
                                                  break;
                                                case ResizeHandle.bottomLeft:
                                                  // 左下角：根据宽度变化计算（反向）
                                                  newWidth =
                                                      _resizingNode!
                                                          .size
                                                          .width -
                                                      delta.dx;
                                                  break;
                                                case ResizeHandle.topRight:
                                                  // 右上角：根据宽度变化计算
                                                  newWidth =
                                                      _resizingNode!
                                                          .size
                                                          .width +
                                                      delta.dx;
                                                  break;
                                              }

                                              // 限制宽度范围
                                              newWidth = newWidth.clamp(
                                                minWidth,
                                                maxWidth,
                                              );

                                              // 根据宽高比计算高度（这样可以保证宽高比不变）
                                              newHeight =
                                                  newWidth / aspectRatio;

                                              // 根据手柄位置调整节点位置
                                              switch (_resizeHandle!) {
                                                case ResizeHandle.topLeft:
                                                  // 左上角：需要调整位置
                                                  final widthDiff =
                                                      _resizingNode!
                                                          .size
                                                          .width -
                                                      newWidth;
                                                  final heightDiff =
                                                      _resizingNode!
                                                          .size
                                                          .height -
                                                      newHeight;
                                                  _resizingNode!
                                                      .position = Offset(
                                                    _resizingNode!.position.dx +
                                                        widthDiff,
                                                    _resizingNode!.position.dy +
                                                        heightDiff,
                                                  );
                                                  break;
                                                case ResizeHandle.topRight:
                                                  // 右上角：需要调整Y位置
                                                  final heightDiff =
                                                      _resizingNode!
                                                          .size
                                                          .height -
                                                      newHeight;
                                                  _resizingNode!
                                                      .position = Offset(
                                                    _resizingNode!.position.dx,
                                                    _resizingNode!.position.dy +
                                                        heightDiff,
                                                  );
                                                  break;
                                                case ResizeHandle.bottomLeft:
                                                  // 左下角：需要调整X位置
                                                  final widthDiff =
                                                      _resizingNode!
                                                          .size
                                                          .width -
                                                      newWidth;
                                                  _resizingNode!
                                                      .position = Offset(
                                                    _resizingNode!.position.dx +
                                                        widthDiff,
                                                    _resizingNode!.position.dy,
                                                  );
                                                  break;
                                                case ResizeHandle.bottomRight:
                                                  // 右下角：不需要调整位置
                                                  break;
                                              }

                                              _resizingNode!.size = Size(
                                                newWidth,
                                                newHeight,
                                              );
                                            } else {
                                              // 没有图片或没有宽高比信息，自由调整
                                              switch (_resizeHandle!) {
                                                case ResizeHandle.bottomRight:
                                                  _resizingNode!.size = Size(
                                                    (_resizingNode!.size.width +
                                                            delta.dx)
                                                        .clamp(100.0, 4000.0),
                                                    (_resizingNode!
                                                                .size
                                                                .height +
                                                            delta.dy)
                                                        .clamp(80.0, 4000.0),
                                                  );
                                                  break;
                                                case ResizeHandle.bottomLeft:
                                                  final newWidth =
                                                      (_resizingNode!
                                                                  .size
                                                                  .width -
                                                              delta.dx)
                                                          .clamp(100.0, 4000.0);
                                                  if (newWidth !=
                                                      _resizingNode!
                                                          .size
                                                          .width) {
                                                    _resizingNode!.position =
                                                        Offset(
                                                          _resizingNode!
                                                                  .position
                                                                  .dx +
                                                              delta.dx,
                                                          _resizingNode!
                                                              .position
                                                              .dy,
                                                        );
                                                  }
                                                  _resizingNode!.size = Size(
                                                    newWidth,
                                                    (_resizingNode!
                                                                .size
                                                                .height +
                                                            delta.dy)
                                                        .clamp(80.0, 4000.0),
                                                  );
                                                  break;
                                                case ResizeHandle.topRight:
                                                  final newHeight =
                                                      (_resizingNode!
                                                                  .size
                                                                  .height -
                                                              delta.dy)
                                                          .clamp(80.0, 4000.0);
                                                  if (newHeight !=
                                                      _resizingNode!
                                                          .size
                                                          .height) {
                                                    _resizingNode!.position =
                                                        Offset(
                                                          _resizingNode!
                                                              .position
                                                              .dx,
                                                          _resizingNode!
                                                                  .position
                                                                  .dy +
                                                              delta.dy,
                                                        );
                                                  }
                                                  _resizingNode!.size = Size(
                                                    (_resizingNode!.size.width +
                                                            delta.dx)
                                                        .clamp(100.0, 4000.0),
                                                    newHeight,
                                                  );
                                                  break;
                                                case ResizeHandle.topLeft:
                                                  final newWidth =
                                                      (_resizingNode!
                                                                  .size
                                                                  .width -
                                                              delta.dx)
                                                          .clamp(100.0, 4000.0);
                                                  final newHeight =
                                                      (_resizingNode!
                                                                  .size
                                                                  .height -
                                                              delta.dy)
                                                          .clamp(80.0, 4000.0);
                                                  if (newWidth !=
                                                      _resizingNode!
                                                          .size
                                                          .width) {
                                                    _resizingNode!.position =
                                                        Offset(
                                                          _resizingNode!
                                                                  .position
                                                                  .dx +
                                                              delta.dx,
                                                          _resizingNode!
                                                              .position
                                                              .dy,
                                                        );
                                                  }
                                                  if (newHeight !=
                                                      _resizingNode!
                                                          .size
                                                          .height) {
                                                    _resizingNode!.position =
                                                        Offset(
                                                          _resizingNode!
                                                              .position
                                                              .dx,
                                                          _resizingNode!
                                                                  .position
                                                                  .dy +
                                                              delta.dy,
                                                        );
                                                  }
                                                  _resizingNode!.size = Size(
                                                    newWidth,
                                                    newHeight,
                                                  );
                                                  break;
                                              }
                                            }
                                          } else if (_draggingStroke != null &&
                                              _draggingStrokeOffset != null) {
                                            _dragDidMove = true;
                                            // 拖动涂鸦
                                            final currentCanvasPoint = Offset(
                                              (details.localPosition.dx -
                                                      _canvasOffset.dx) /
                                                  _scale,
                                              (details.localPosition.dy -
                                                      _canvasOffset.dy) /
                                                  _scale,
                                            );
                                            final delta =
                                                currentCanvasPoint -
                                                _draggingStrokeOffset!;

                                            // 移动所有选中的笔画（包括当前拖动的）
                                            if (_selectedStrokes.isNotEmpty) {
                                              for (var stroke
                                                  in _selectedStrokes) {
                                                for (
                                                  int i = 0;
                                                  i < stroke.points.length;
                                                  i++
                                                ) {
                                                  stroke.points[i] += delta;
                                                }
                                              }
                                              // 如果拖动的笔画不在选中集合中也要移动
                                              if (!_selectedStrokes.contains(
                                                _draggingStroke!,
                                              )) {
                                                for (
                                                  int i = 0;
                                                  i <
                                                      _draggingStroke!
                                                          .points
                                                          .length;
                                                  i++
                                                ) {
                                                  _draggingStroke!.points[i] +=
                                                      delta;
                                                }
                                              }
                                            } else {
                                              // 单条笔画移动
                                              for (
                                                int i = 0;
                                                i <
                                                    _draggingStroke!
                                                        .points
                                                        .length;
                                                i++
                                              ) {
                                                _draggingStroke!.points[i] +=
                                                    delta;
                                              }
                                            }

                                            // 同时移动所有选中的节点
                                            if (_selectedNodeIds.isNotEmpty) {
                                              for (var node in _nodes) {
                                                if (_selectedNodeIds.contains(
                                                  node.id,
                                                )) {
                                                  node.position += delta;
                                                }
                                              }
                                            }

                                            _draggingStrokeOffset =
                                                currentCanvasPoint;
                                          } else if (_draggingNode != null &&
                                              _lastPanPosition != null) {
                                            _dragDidMove = true;
                                            // 计算移动增量
                                            final delta =
                                                (details.localPosition -
                                                    _lastPanPosition!) /
                                                _scale;
                                            _lastPanPosition =
                                                details.localPosition;

                                            // 如果有多个选中的节点，批量移动
                                            if (_selectedNodeIds.isNotEmpty) {
                                              for (var node in _nodes) {
                                                if (_selectedNodeIds.contains(
                                                  node.id,
                                                )) {
                                                  node.position += delta;
                                                }
                                              }
                                              // 确保拖拽节点不在选中集合中时也被移动
                                              if (!_selectedNodeIds.contains(
                                                _draggingNode!.id,
                                              )) {
                                                _draggingNode!.position +=
                                                    delta;
                                              }
                                              // 同时移动所有选中的笔画
                                              for (var stroke
                                                  in _selectedStrokes) {
                                                for (
                                                  int i = 0;
                                                  i < stroke.points.length;
                                                  i++
                                                ) {
                                                  stroke.points[i] += delta;
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
                                        // 重置拖动状态
                                        if (_isPanning) {
                                          setState(() => _isPanning = false);
                                          return;
                                        }

                                        // 文本框创建结束
                                        if (_isCreatingTextBox &&
                                            _textBoxStart != null &&
                                            _textBoxEnd != null) {
                                          _pushUndo();
                                          final rect = Rect.fromPoints(
                                            _textBoxStart!,
                                            _textBoxEnd!,
                                          );
                                          final width = rect.width.abs().clamp(
                                            100.0,
                                            4000.0,
                                          );
                                          final height = rect.height
                                              .abs()
                                              .clamp(80.0, 4000.0);

                                          setState(() {
                                            final newNode = CanvasNode(
                                              id: DateTime.now()
                                                  .millisecondsSinceEpoch
                                                  .toString(),
                                              type: NodeType.text,
                                              position: Offset(
                                                (rect.left - _canvasOffset.dx) /
                                                    _scale,
                                                (rect.top - _canvasOffset.dy) /
                                                    _scale,
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
                                        if (_isCreatingImageBox &&
                                            _imageBoxStart != null &&
                                            _imageBoxEnd != null) {
                                          _pushUndo();
                                          final rect = Rect.fromPoints(
                                            _imageBoxStart!,
                                            _imageBoxEnd!,
                                          );
                                          // 允许更小的尺寸，最小 100x100，最大 4000x4000
                                          final width = rect.width.abs().clamp(
                                            100.0,
                                            4000.0,
                                          );
                                          final height = rect.height
                                              .abs()
                                              .clamp(100.0, 4000.0);

                                          setState(() {
                                            final newNode = CanvasNode(
                                              id: DateTime.now()
                                                  .millisecondsSinceEpoch
                                                  .toString(),
                                              type: NodeType.image,
                                              position: Offset(
                                                (rect.left - _canvasOffset.dx) /
                                                    _scale,
                                                (rect.top - _canvasOffset.dy) /
                                                    _scale,
                                              ),
                                              size: Size(width, height),
                                              data: {
                                                'provider': _imageProvider,
                                                'model':
                                                    _availableImageModels
                                                        .isNotEmpty
                                                    ? _availableImageModels
                                                          .first
                                                    : 'gemini-3-pro-image-preview',
                                                'resolution': '1K',
                                                'ratio': '1:1',
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
                                        if (_isCreatingVideoBox &&
                                            _videoBoxStart != null &&
                                            _videoBoxEnd != null) {
                                          _pushUndo();
                                          final rect = Rect.fromPoints(
                                            _videoBoxStart!,
                                            _videoBoxEnd!,
                                          );
                                          // 允许更小的尺寸，最小 100x100，最大 4000x4000
                                          final width = rect.width.abs().clamp(
                                            100.0,
                                            4000.0,
                                          );
                                          final height = rect.height
                                              .abs()
                                              .clamp(100.0, 4000.0);

                                          setState(() {
                                            final newNode = CanvasNode(
                                              id: DateTime.now()
                                                  .millisecondsSinceEpoch
                                                  .toString(),
                                              type: NodeType.video,
                                              position: Offset(
                                                (rect.left - _canvasOffset.dx) /
                                                    _scale,
                                                (rect.top - _canvasOffset.dy) /
                                                    _scale,
                                              ),
                                              size: Size(width, height),
                                              data: {
                                                'provider': _videoProvider,
                                                'model':
                                                    _availableVideoModels
                                                        .isNotEmpty
                                                    ? _availableVideoModels
                                                          .first
                                                    : 'veo_3_1',
                                                'resolution': '1K',
                                                'videoRatio': '16:9',
                                                'ratio': '5s',
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
                                        if (_currentTool == CanvasTool.draw &&
                                            _currentStroke != null) {
                                          _pushUndo();
                                          setState(() {
                                            _strokes.add(_currentStroke!);
                                            _currentStroke = null;
                                          });
                                          return;
                                        }

                                        // 框选结束：选中框内的节点和涂鸦
                                        if (_selectionStart != null &&
                                            _selectionEnd != null) {
                                          final selectionRect = Rect.fromPoints(
                                            _selectionStart!,
                                            _selectionEnd!,
                                          );
                                          _selectedNodeIds.clear();

                                          // 选中节点
                                          for (var node in _nodes) {
                                            final nodeRect = Rect.fromLTWH(
                                              node.position.dx * _scale +
                                                  _canvasOffset.dx,
                                              node.position.dy * _scale +
                                                  _canvasOffset.dy,
                                              node.size.width * _scale,
                                              node.size.height * _scale,
                                            );

                                            if (selectionRect.overlaps(
                                              nodeRect,
                                            )) {
                                              _selectedNodeIds.add(node.id);
                                            }
                                          }

                                          // 选中涂鸦 - 使用包围盒 overlaps 与节点一致
                                          _selectedStrokes.clear();
                                          for (var stroke in _strokes) {
                                            if (stroke.points.isEmpty) continue;
                                            // 计算笔画的包围盒（画布坐标转屏幕坐标）
                                            double minX = double.infinity,
                                                minY = double.infinity,
                                                maxX = double.negativeInfinity,
                                                maxY = double.negativeInfinity;
                                            for (var point in stroke.points) {
                                              final sx =
                                                  point.dx * _scale +
                                                  _canvasOffset.dx;
                                              final sy =
                                                  point.dy * _scale +
                                                  _canvasOffset.dy;
                                              if (sx < minX) minX = sx;
                                              if (sy < minY) minY = sy;
                                              if (sx > maxX) maxX = sx;
                                              if (sy > maxY) maxY = sy;
                                            }
                                            // 扩大包围盒以包含笔画宽度
                                            final halfWidth =
                                                stroke.strokeWidth * _scale / 2;
                                            final strokeRect = Rect.fromLTRB(
                                              minX - halfWidth,
                                              minY - halfWidth,
                                              maxX + halfWidth,
                                              maxY + halfWidth,
                                            );
                                            if (selectionRect.overlaps(
                                              strokeRect,
                                            )) {
                                              _selectedStrokes.add(stroke);
                                            }
                                          }
                                          // 如果只选中一条涂鸦，也设置单选变量以兼容编辑功能
                                          if (_selectedStrokes.length == 1) {
                                            _selectedStroke =
                                                _selectedStrokes.first;
                                          }

                                          setState(() {
                                            _selectionStart = null;
                                            _selectionEnd = null;
                                            // 仅单选时设置_selectedNodeId，避免弹出编辑面板
                                            if (_selectedNodeIds.length == 1 &&
                                                _selectedStrokes.isEmpty) {
                                              _selectedNodeId =
                                                  _selectedNodeIds.first;
                                            }
                                          });
                                          return;
                                        }

                                        _commitPendingUndo();
                                        if (_dragDidMove) {
                                          _saveCanvasData();
                                        }
                                        _draggingNode = null;
                                        _draggingOffset = null;
                                        _draggingStroke = null;
                                        _draggingStrokeOffset = null;
                                        _lastPanPosition = null;
                                        _resizingNode = null;
                                        _resizeHandle = null;
                                      },
                                      child: RepaintBoundary(
                                        key: _canvasRepaintKey,
                                        child: Container(
                                          color: _bgColor,
                                          child: Stack(
                                            children: [
                                              // 网格背景
                                              if (_showGrid)
                                                CustomPaint(
                                                  painter: _GridPainter(
                                                    canvasOffset: _canvasOffset,
                                                    scale: _scale,
                                                    isDots: _gridDots,
                                                  ),
                                                  child: Container(),
                                                ),

                                              // 绘制涂鸦
                                              CustomPaint(
                                                painter: DrawingPainter(
                                                  strokes: _strokes
                                                      .where(
                                                        (s) =>
                                                            !_hiddenStrokeIndices
                                                                .contains(
                                                                  _strokes
                                                                      .indexOf(
                                                                        s,
                                                                      ),
                                                                ),
                                                      )
                                                      .toList(),
                                                  currentStroke: _currentStroke,
                                                  selectedStroke:
                                                      _selectedStroke,
                                                  selectedStrokes:
                                                      _selectedStrokes,
                                                  canvasOffset: _canvasOffset,
                                                  scale: _scale,
                                                ),
                                                child: Container(),
                                              ),

                                              // 渲染节点（单节点异常不拖垮整个画布）
                                              ..._nodes
                                                  .where(
                                                    (n) => !_hiddenNodeIds
                                                        .contains(n.id),
                                                  )
                                                  .map((node) {
                                                    try {
                                                    final screenPos = Offset(
                                                      node.position.dx *
                                                              _scale +
                                                          _canvasOffset.dx,
                                                      node.position.dy *
                                                              _scale +
                                                          _canvasOffset.dy,
                                                    );

                                                    return Positioned(
                                                      key: ValueKey(node.id),
                                                      left: screenPos.dx,
                                                      top: screenPos.dy,
                                                      child: Transform.scale(
                                                        scale: _scale,
                                                        alignment:
                                                            Alignment.topLeft,
                                                        child: _buildNodeCard(
                                                          node,
                                                        ),
                                                      ),
                                                    );
                                                    } catch (e) {
                                                      debugPrint('⚠️ 节点 ${node.id} 渲染异常: $e');
                                                      return const SizedBox.shrink();
                                                    }
                                                  }),

                                              // 框选矩形
                                              if (_selectionStart != null &&
                                                  _selectionEnd != null)
                                                CustomPaint(
                                                  painter: SelectionBoxPainter(
                                                    start: _selectionStart!,
                                                    end: _selectionEnd!,
                                                  ),
                                                  child: Container(),
                                                ),

                                              // 文本框创建预览
                                              if (_isCreatingTextBox &&
                                                  _textBoxStart != null &&
                                                  _textBoxEnd != null)
                                                CustomPaint(
                                                  painter: SelectionBoxPainter(
                                                    start: _textBoxStart!,
                                                    end: _textBoxEnd!,
                                                  ),
                                                  child: Container(),
                                                ),

                                              // 图片框创建预览
                                              if (_isCreatingImageBox &&
                                                  _imageBoxStart != null &&
                                                  _imageBoxEnd != null)
                                                CustomPaint(
                                                  painter: SelectionBoxPainter(
                                                    start: _imageBoxStart!,
                                                    end: _imageBoxEnd!,
                                                  ),
                                                  child: Container(),
                                                ),

                                              // 视频框创建预览
                                              if (_isCreatingVideoBox &&
                                                  _videoBoxStart != null &&
                                                  _videoBoxEnd != null)
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
                                  ),
                                ),
                                // 光标跟踪层（填满画布，仅用于光标样式变化和位置跟踪，不影响手势竞技场）
                                Positioned.fill(
                                  child: MouseRegion(
                                    cursor: (_isPanning || _isMiddleButtonPressed || _isSpacePressed || _currentTool == CanvasTool.pan)
                                        ? SystemMouseCursors.none
                                        : MouseCursor.defer,
                                    opaque: false,
                                    onHover: (event) {
                                      if (_isSpacePressed || _isPanning || _isMiddleButtonPressed || _currentTool == CanvasTool.pan) {
                                        setState(() => _cursorPosition = event.localPosition);
                                      }
                                    },
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                                Positioned(
                                  left: 16,
                                  top: 16,
                                  child: _buildToolbar(),
                                ),

                                // 画笔工具栏（当选择画笔工具且显示状态为true时显示）
                                if (_currentTool == CanvasTool.draw &&
                                    _showBrushToolbar)
                                  Positioned(
                                    left: 88,
                                    top: 16,
                                    child: _buildBrushToolbar(),
                                  ),

                                // 文本工具栏（当选择文本工具且显示状态为true时显示）
                                if (_currentTool == CanvasTool.text &&
                                    _showTextToolbar)
                                  Positioned(
                                    left: 88,
                                    top: 16,
                                    child: _buildTextToolbar(),
                                  ),

                                // 迷你地图
                                Positioned(
                                  right: 16,
                                  bottom: 56,
                                  child: _buildMinimap(),
                                ),

                                // 右下角缩放控制
                                Positioned(
                                  right: 16,
                                  bottom: 16,
                                  child: _buildZoomControls(),
                                ),

                                // 底部编辑面板（仅图片和视频需要，且不是仅显示节点，且不在多选模式下）
                                if (_selectedNodeId != null &&
                                    _selectedNodeIds.isEmpty)
                                  () {
                                    try {
                                    final node = _nodes
                                        .where((n) => n.id == _selectedNodeId)
                                        .firstOrNull;
                                    if (node == null)
                                      return const SizedBox.shrink();
                                    final isDisplayOnly =
                                        node.data['isDisplayOnly'] == true;

                                    // 仅显示节点不显示编辑面板
                                    if (isDisplayOnly) {
                                      return const SizedBox.shrink();
                                    }

                                    if (node.type == NodeType.image ||
                                        node.type == NodeType.video) {
                                      // 计算节点在屏幕上的位置
                                      final nodeScreenPos = Offset(
                                        node.position.dx * _scale +
                                            _canvasOffset.dx,
                                        node.position.dy * _scale +
                                            _canvasOffset.dy,
                                      );
                                      final nodeScreenSize = Size(
                                        node.size.width * _scale,
                                        node.size.height * _scale,
                                      );

                                      // 面板宽度
                                      final panelWidth =
                                          node.type == NodeType.video
                                          ? 600.0
                                          : 520.0;

                                      final viewportSize = MediaQuery.sizeOf(
                                        context,
                                      );
                                      final maxPanelLeft =
                                          viewportSize.width -
                                          (_showAgentPanel ? 360.0 : 0.0) -
                                          panelWidth -
                                          20;

                                      // 计算居中位置，并限制在可视区域内
                                      final panelLeft =
                                          (nodeScreenPos.dx +
                                                  (nodeScreenSize.width -
                                                          panelWidth) /
                                                      2)
                                              .clamp(
                                                20.0,
                                                maxPanelLeft < 20.0
                                                    ? 20.0
                                                    : maxPanelLeft,
                                              )
                                              .toDouble();

                                      return Positioned(
                                        left: panelLeft,
                                        top:
                                            nodeScreenPos.dy +
                                            nodeScreenSize.height +
                                            12,
                                        child: _buildCompactEditPanel(node),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                    } catch (e) {
                                      debugPrint('⚠️ 编辑面板构建异常: $e');
                                      return const SizedBox.shrink();
                                    }
                                  }(),

                                // 自定义拖动光标覆盖层（Windows 不支持 grab/grabbing 系统光标）
                                if ((_isPanning || _isMiddleButtonPressed || _isSpacePressed || _currentTool == CanvasTool.pan) && _cursorPosition != null)
                                  Positioned(
                                    left: _cursorPosition!.dx - 8,
                                    top: _cursorPosition!.dy - 2,
                                    child: IgnorePointer(
                                      child: Icon(
                                        _isPanning || _isMiddleButtonPressed
                                            ? Icons.back_hand
                                            : Icons.pan_tool,
                                        size: 16,
                                        color: Colors.white,
                                        shadows: const [
                                          Shadow(blurRadius: 2, color: Colors.black87),
                                          Shadow(blurRadius: 1, color: Colors.black54),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // Agent 聊天面板
                          if (_showAgentPanel)
                            AgentChatPanel(
                              currentImageProvider: _imageProvider,
                              currentImageModel: _currentImageModel,
                              currentVideoProvider: _videoProvider,
                              currentVideoModel: _currentVideoModel,
                              canvasContextSummary:
                                  _buildAgentCanvasContextSummary(),
                              onPlanReady: _applyDesignPlan,
                              onActionBundleReady: _applyAgentActionBundle,
                              onActionBundlePreview:
                                  _previewAgentActionBundleTargets,
                              onClose: () {
                                setState(() {
                                  _showAgentPanel = false;
                                });
                              },
                            ),
                          // 图层面板
                          if (_showLayerPanel) _buildLayerPanel(),
                        ],
                      ),
                    ),
                    // 画布选择模式底部提示条
                    if (_isSelectingFromCanvas)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0EBF5),
                          border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
                        ),
                        child: Row(
                          children: [
                            Text(
                              _targetNodeForImage?.data['_selectingFrameType'] != null
                                  ? '请点击画布上的图片节点作为${_targetNodeForImage!.data['_selectingFrameType'] == 'first' ? '首帧' : '尾帧'}'
                                  : '请点击画布上的图片节点作为参考',
                              style: const TextStyle(
                                color: Color(0xFF555555),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: _cancelCanvasSelection,
                              child: const Text(
                                '取消',
                                style: TextStyle(
                                  color: Color(0xFF5C6BC0),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
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
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFBFDFF), Color(0xFFF1F6FF)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              border: Border(
                bottom: BorderSide(
                  color: _accentBlue.withValues(alpha: 0.12),
                  width: 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: _accentBlue.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_accentCyan, _accentIndigo],
                      ),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: _accentBlue.withValues(alpha: 0.24),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Text(
                      'AI CANVAS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.9,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'R·O·S 动漫制作 · AI 画布',
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.84),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _accentBlue.withValues(alpha: 0.12),
                      ),
                    ),
                    child: const Text(
                      '灵感 / 布局 / 生成',
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
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
      width: 64,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFEFEFF), Color(0xFFF3F7FF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _accentBlue.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: _accentBlue.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.95),
            blurRadius: 12,
            offset: const Offset(-2, -2),
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
            width: 36,
            height: 1,
            color: _accentBlue.withValues(alpha: 0.12),
          ),
          const SizedBox(height: 8),
          _buildToolButton(Icons.image_outlined, "图片", CanvasTool.image),
          const SizedBox(height: 8),
          _buildToolButton(Icons.videocam_outlined, "视频", CanvasTool.video),
          const SizedBox(height: 8),
          // 分隔线
          Container(
            width: 36,
            height: 1,
            color: _accentBlue.withValues(alpha: 0.12),
          ),
          const SizedBox(height: 8),
          // AI Agent 按钮
          _buildAgentButton(),
          const SizedBox(height: 8),
          // 分隔线
          Container(
            width: 36,
            height: 1,
            color: _accentBlue.withValues(alpha: 0.12),
          ),
          const SizedBox(height: 8),
          // 撤销按钮
          Tooltip(
            message: "撤销 (Ctrl+Z)",
            child: InkWell(
              onTap: _canUndo ? _undo : null,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.undo,
                  size: 20,
                  color: _canUndo ? Colors.grey[700] : Colors.grey[300],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // 重做按钮
          Tooltip(
            message: "重做 (Ctrl+Y)",
            child: InkWell(
              onTap: _canRedo ? _redo : null,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.redo,
                  size: 20,
                  color: _canRedo ? Colors.grey[700] : Colors.grey[300],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 分隔线
          Container(
            width: 36,
            height: 1,
            color: _accentBlue.withValues(alpha: 0.12),
          ),
          const SizedBox(height: 4),
          // 图层面板切换按钮
          Tooltip(
            message: "图层面板",
            child: InkWell(
              onTap: () => setState(() => _showLayerPanel = !_showLayerPanel),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: _showLayerPanel
                      ? _accentBlue.withValues(alpha: 0.1)
                      : null,
                ),
                child: Icon(
                  Icons.layers,
                  size: 20,
                  color: _showLayerPanel ? _accentBlue : Colors.grey[700],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // AI Agent 按钮
  Widget _buildAgentButton() {
    return Tooltip(
      message: "AI 设计助手",
      child: InkWell(
        onTap: () {
          setState(() {
            _showAgentPanel = !_showAgentPanel;
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: _showAgentPanel
                ? const LinearGradient(colors: [_accentCyan, _accentIndigo])
                : null,
            color: _showAgentPanel ? null : _surfaceSoft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _showAgentPanel
                  ? Colors.white.withValues(alpha: 0.65)
                  : _accentBlue.withValues(alpha: 0.10),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: (_showAgentPanel ? _accentBlue : Colors.black)
                    .withValues(alpha: _showAgentPanel ? 0.24 : 0.05),
                blurRadius: _showAgentPanel ? 16 : 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.auto_awesome,
            color: _showAgentPanel ? Colors.white : _textPrimary,
            size: 22,
          ),
        ),
      ),
    );
  }

  String _buildAgentCanvasContextSummary() {
    final selectedIds = <String>{
      if (_selectedNodeId != null) _selectedNodeId!,
      ..._selectedNodeIds,
    }.toList();

    final nodes = _nodes.take(40).map((node) {
      final summary = <String, dynamic>{
        'id': node.id,
        'label': _getNodeAlias(node),
        'type': node.type.name,
        'x': node.position.dx.round(),
        'y': node.position.dy.round(),
        'width': node.size.width.round(),
        'height': node.size.height.round(),
      };

      switch (node.type) {
        case NodeType.text:
          summary['text'] = node.data['text'] ?? '';
          break;
        case NodeType.image:
          summary['prompt'] = node.data['prompt'] ?? '';
          summary['hasGeneratedImage'] =
              node.data['generatedImagePath'] != null;
          break;
        case NodeType.video:
          summary['prompt'] = node.data['prompt'] ?? '';
          summary['hasGeneratedVideo'] =
              node.data['generatedVideoPath'] != null;
          break;
      }
      return summary;
    }).toList();

    return jsonEncode({
      'selectedNodeIds': selectedIds,
      'nodeCount': _nodes.length,
      'nodes': nodes,
    });
  }

  String _normalizeNodeText(String? text) {
    if (text == null) return '';
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _shortNodeText(String? text, {int maxLength = 14}) {
    final normalized = _normalizeNodeText(text);
    if (normalized.isEmpty) return '';
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength)}...';
  }

  String _getNodeAlias(CanvasNode node) {
    final storedName = _normalizeNodeText(
      (node.data['label'] ?? node.data['name'])?.toString(),
    );
    if (storedName.isNotEmpty) return storedName;

    switch (node.type) {
      case NodeType.text:
        final text = _shortNodeText(
          node.data['text']?.toString(),
          maxLength: 16,
        );
        return text.isNotEmpty ? '文本「$text」' : '文本节点';
      case NodeType.image:
        final prompt = _shortNodeText(
          node.data['prompt']?.toString(),
          maxLength: 12,
        );
        return prompt.isNotEmpty ? '图片「$prompt」' : '图片节点';
      case NodeType.video:
        final prompt = _shortNodeText(
          node.data['prompt']?.toString(),
          maxLength: 12,
        );
        return prompt.isNotEmpty ? '视频「$prompt」' : '视频节点';
    }
  }

  void _setNodeAlias(CanvasNode node, String alias) {
    final normalized = _normalizeNodeText(alias);
    if (normalized.isNotEmpty) {
      node.data['name'] = normalized;
      node.data['label'] = normalized;
    }
  }

  void _flashAgentHighlightNodeIds(Iterable<String> nodeIds) {
    final ids = nodeIds.where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return;

    _agentHighlightTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _agentHighlightedNodeIds
        ..clear()
        ..addAll(ids);
    });

    _agentHighlightTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _agentHighlightedNodeIds.clear();
      });
    });
  }

  Offset _currentCanvasViewportCenter() {
    final viewportWidth =
        MediaQuery.of(context).size.width - (_showAgentPanel ? 360 : 0);
    final viewportHeight = MediaQuery.of(context).size.height - 32;
    return Offset(
      (viewportWidth / 2 - _canvasOffset.dx) / _scale,
      (viewportHeight / 2 - _canvasOffset.dy) / _scale,
    );
  }

  double? _readActionDouble(Map<String, dynamic> source, String key) {
    final value = source[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Size _resolveAgentActionSize(AgentAction action, NodeType nodeType) {
    final width =
        _readActionDouble(action.options, 'width') ??
        _readActionDouble(action.payload, 'width') ??
        (nodeType == NodeType.video ? 640 : 300);
    final height =
        _readActionDouble(action.options, 'height') ??
        _readActionDouble(action.payload, 'height') ??
        (nodeType == NodeType.video
            ? 360
            : nodeType == NodeType.text
            ? 120
            : 300);
    return Size(
      width.clamp(100.0, 4000.0).toDouble(),
      height.clamp(60.0, 4000.0).toDouble(),
    );
  }

  Offset _resolveAgentActionPosition(AgentAction action, int index) {
    final x = _readActionDouble(action.position, 'x');
    final y = _readActionDouble(action.position, 'y');
    if (x != null && y != null) {
      return Offset(x, y);
    }

    final center = _currentCanvasViewportCenter();
    final dx = (index % 3) * 36.0;
    final dy = (index ~/ 3) * 36.0;
    return Offset(center.dx + dx, center.dy + dy);
  }

  String _nextAgentNodeId(String suffix) {
    return '${DateTime.now().microsecondsSinceEpoch}_agent_$suffix';
  }

  bool _removeCanvasNodeById(String nodeId) {
    final node = _nodes.where((n) => n.id == nodeId).firstOrNull;
    if (node == null) return false;

    if (node.type == NodeType.video) {
      _videoPlayers[node.id]?.dispose();
      _videoPlayers.remove(node.id);
      _videoControllers.remove(node.id);
    }

    _nodes.removeWhere((n) => n.id == nodeId);
    _selectedNodeIds.remove(nodeId);
    if (_selectedNodeId == nodeId) {
      _selectedNodeId = null;
    }
    return true;
  }

  CanvasNode? _createNodeFromAgentAction(AgentAction action, int index) {
    switch (action.type) {
      case 'generate_image':
        final payload = action.payload;
        final prompt = (payload['prompt'] as String? ?? '').trim();
        if (prompt.isEmpty) return null;
        final node = CanvasNode(
          id: _nextAgentNodeId('img_$index'),
          type: NodeType.image,
          position: _resolveAgentActionPosition(action, index),
          size: _resolveAgentActionSize(action, NodeType.image),
          data: {
            'prompt': prompt,
            'provider':
                payload['provider'] as String? ??
                action.options['provider'] as String? ??
                _imageProvider,
            'model':
                payload['model'] as String? ??
                action.options['model'] as String? ??
                _currentImageModel ??
                (_availableImageModels.isNotEmpty
                    ? _availableImageModels.first
                    : ''),
            'resolution': payload['quality'] as String? ?? '1K',
            'ratio': payload['ratio'] as String? ?? '1:1',
            if (payload['referenceImages'] is List)
              'referenceImages': List<String>.from(
                payload['referenceImages'] as List,
              ),
          },
        );
        _setNodeAlias(
          node,
          (payload['label'] ?? payload['name'] ?? '').toString(),
        );
        return node;
      case 'generate_video':
        final payload = action.payload;
        final prompt = (payload['prompt'] as String? ?? '').trim();
        if (prompt.isEmpty) return null;
        final node = CanvasNode(
          id: _nextAgentNodeId('video_$index'),
          type: NodeType.video,
          position: _resolveAgentActionPosition(action, index),
          size: _resolveAgentActionSize(action, NodeType.video),
          data: {
            'prompt': prompt,
            'provider':
                payload['provider'] as String? ??
                action.options['provider'] as String? ??
                _videoProvider,
            'model':
                payload['model'] as String? ??
                action.options['model'] as String? ??
                _currentVideoModel ??
                (_availableVideoModels.isNotEmpty
                    ? _availableVideoModels.first
                    : ''),
            'resolution': payload['quality'] as String? ?? '1K',
            'videoRatio': payload['ratio'] as String? ?? '16:9',
            'ratio': payload['duration'] as String? ?? '5s',
            if (payload['referenceImages'] is List)
              'referenceImages': List<String>.from(
                payload['referenceImages'] as List,
              ),
          },
        );
        _setNodeAlias(
          node,
          (payload['label'] ?? payload['name'] ?? '').toString(),
        );
        return node;
      case 'create_text_node':
      case 'create_note_node':
        final payload = action.payload;
        final text = (payload['text'] ?? payload['content'] ?? '')
            .toString()
            .trim();
        if (text.isEmpty) return null;
        final node = CanvasNode(
          id: _nextAgentNodeId('text_$index'),
          type: NodeType.text,
          position: _resolveAgentActionPosition(action, index),
          size: _resolveAgentActionSize(action, NodeType.text),
          data: {
            'text': text,
            'fontFamily': _textFontFamily,
            'fontSize':
                _readActionDouble(payload, 'fontSize') ??
                (action.type == 'create_note_node' ? 14.0 : _textFontSize),
            'color': _getColorFromData(payload['color'], _textColor),
            'bold': payload['bold'] as bool? ?? false,
            'italic': payload['italic'] as bool? ?? false,
            'underline': payload['underline'] as bool? ?? false,
          },
        );
        _setNodeAlias(
          node,
          (payload['label'] ?? payload['name'] ?? '').toString(),
        );
        return node;
    }
    return null;
  }

  bool _applyNodeMutation(CanvasNode node, AgentAction action) {
    final payload = action.payload['changes'] is Map
        ? Map<String, dynamic>.from(action.payload['changes'] as Map)
        : Map<String, dynamic>.from(action.payload);
    var changed = false;

    final x = _readActionDouble(action.position, 'x');
    final y = _readActionDouble(action.position, 'y');
    if (x != null && y != null) {
      node.position = Offset(x, y);
      changed = true;
    }

    final width =
        _readActionDouble(action.options, 'width') ??
        _readActionDouble(payload, 'width');
    final height =
        _readActionDouble(action.options, 'height') ??
        _readActionDouble(payload, 'height');
    if (width != null || height != null) {
      node.size = Size(
        (width ?? node.size.width).clamp(60.0, 4000.0).toDouble(),
        (height ?? node.size.height).clamp(60.0, 4000.0).toDouble(),
      );
      changed = true;
    }

    for (final entry in payload.entries) {
      switch (entry.key) {
        case 'text':
          node.data['text'] = entry.value?.toString() ?? '';
          changed = true;
          break;
        case 'prompt':
          node.data['prompt'] = entry.value?.toString() ?? '';
          changed = true;
          break;
        case 'provider':
        case 'model':
        case 'resolution':
        case 'ratio':
        case 'videoRatio':
          node.data[entry.key] = entry.value;
          changed = true;
          break;
        case 'duration':
          node.data['ratio'] = entry.value;
          changed = true;
          break;
        case 'referenceImages':
          if (entry.value is List) {
            node.data['referenceImages'] = List<String>.from(
              entry.value as List,
            );
            changed = true;
          }
          break;
        case 'color':
          node.data['color'] = _getColorFromData(entry.value, _textColor);
          changed = true;
          break;
        case 'fontSize':
          final fontSize = entry.value is num
              ? entry.value.toDouble()
              : double.tryParse(entry.value.toString());
          if (fontSize != null) {
            node.data['fontSize'] = fontSize;
            changed = true;
          }
          break;
        case 'bold':
        case 'italic':
        case 'underline':
          node.data[entry.key] = entry.value == true;
          changed = true;
          break;
      }
    }

    return changed;
  }

  Future<String> _applyAgentActionBundle(AgentActionBundle bundle) async {
    if (bundle.actions.isEmpty) {
      return '没有可执行动作，已作为普通聊天处理。';
    }

    final executableActions = bundle.actions
        .where((a) => a.isExecutable)
        .toList();
    if (executableActions.isEmpty) {
      return '本次回复只包含建议，没有自动执行动作。';
    }

    _pushUndo();

    final newNodes = <CanvasNode>[];
    final nodesToGenerate = <CanvasNode>[];
    final highlightedNodeIds = <String>{};
    final createdAliases = <String>[];
    final updatedAliases = <String>[];
    final movedAliases = <String>[];
    final deletedAliases = <String>[];
    var createdCount = 0;
    var updatedCount = 0;
    var movedCount = 0;
    var deletedCount = 0;
    var skippedCount = 0;

    setState(() {
      for (var i = 0; i < executableActions.length; i++) {
        final action = executableActions[i];
        switch (action.type) {
          case 'generate_image':
          case 'generate_video':
          case 'create_text_node':
          case 'create_note_node':
            final node = _createNodeFromAgentAction(action, i);
            if (node == null) {
              skippedCount++;
              continue;
            }
            _nodes.add(node);
            newNodes.add(node);
            highlightedNodeIds.add(node.id);
            createdAliases.add(_getNodeAlias(node));
            if (node.type == NodeType.image || node.type == NodeType.video) {
              nodesToGenerate.add(node);
            }
            createdCount++;
            break;
          case 'update_node':
            final node = _nodes.where((n) => n.id == action.nodeId).firstOrNull;
            if (node == null) {
              skippedCount++;
              continue;
            }
            if (_applyNodeMutation(node, action)) {
              updatedCount++;
              highlightedNodeIds.add(node.id);
              updatedAliases.add(_getNodeAlias(node));
            } else {
              skippedCount++;
            }
            break;
          case 'move_node':
            final node = _nodes.where((n) => n.id == action.nodeId).firstOrNull;
            if (node == null) {
              skippedCount++;
              continue;
            }
            final x = _readActionDouble(action.position, 'x');
            final y = _readActionDouble(action.position, 'y');
            if (x == null || y == null) {
              skippedCount++;
              continue;
            }
            node.position = Offset(x, y);
            movedCount++;
            highlightedNodeIds.add(node.id);
            movedAliases.add(_getNodeAlias(node));
            break;
          case 'delete_node':
            if (action.nodeId == null) {
              skippedCount++;
              continue;
            }
            final node = _nodes.where((n) => n.id == action.nodeId).firstOrNull;
            if (node == null || !_removeCanvasNodeById(action.nodeId!)) {
              skippedCount++;
              continue;
            }
            deletedCount++;
            deletedAliases.add(_getNodeAlias(node));
            break;
          default:
            skippedCount++;
            break;
        }
      }

      if (newNodes.isNotEmpty) {
        _selectedNodeIds.clear();
        _selectedNodeIds.addAll(newNodes.map((n) => n.id));
        _selectedNodeId = newNodes.first.id;
      }
    });

    await _saveCanvasData();

    if (nodesToGenerate.isNotEmpty) {
      unawaited(_autoGenerateNodes(nodesToGenerate));
    }

    _flashAgentHighlightNodeIds(highlightedNodeIds);

    final parts = <String>[];
    if (createdCount > 0) parts.add('创建 $createdCount 个元素');
    if (updatedCount > 0) parts.add('更新 $updatedCount 个节点');
    if (movedCount > 0) parts.add('移动 $movedCount 个节点');
    if (deletedCount > 0) parts.add('删除 $deletedCount 个节点');
    if (nodesToGenerate.isNotEmpty) {
      parts.add('开始生成 ${nodesToGenerate.length} 个媒体元素');
    }
    if (skippedCount > 0) parts.add('跳过 $skippedCount 个动作');

    final detailLines = <String>[];
    if (createdAliases.isNotEmpty) {
      detailLines.add('创建：${createdAliases.take(3).join('、')}');
    }
    if (updatedAliases.isNotEmpty) {
      detailLines.add('更新：${updatedAliases.take(3).join('、')}');
    }
    if (movedAliases.isNotEmpty) {
      detailLines.add('移动：${movedAliases.take(3).join('、')}');
    }
    if (deletedAliases.isNotEmpty) {
      detailLines.add('删除：${deletedAliases.take(3).join('、')}');
    }

    final summary = parts.isEmpty
        ? '没有执行任何动作。'
        : [
            '已执行：${parts.join('，')}',
            if (detailLines.isNotEmpty) detailLines.join('\n'),
          ].join('\n');
    if (mounted) {
      _showMessage(summary);
    }
    return summary;
  }

  void _previewAgentActionBundleTargets(AgentActionBundle bundle) {
    final targetIds = bundle.actions
        .map((action) => action.nodeId)
        .whereType<String>()
        .where((id) => _nodes.any((node) => node.id == id))
        .toSet();
    _flashAgentHighlightNodeIds(targetIds);
  }

  /// 将 Agent 设计方案应用到画布
  void _applyDesignPlan(DesignPlan plan) {
    if (plan.elements.isEmpty) {
      _showMessage('设计方案为空');
      return;
    }

    // 计算当前视口中心（画布坐标系）
    final viewportWidth =
        MediaQuery.of(context).size.width - (_showAgentPanel ? 360 : 0);
    final viewportHeight = MediaQuery.of(context).size.height - 32; // 减去标题栏
    final centerX = (viewportWidth / 2 - _canvasOffset.dx) / _scale;
    final centerY = (viewportHeight / 2 - _canvasOffset.dy) / _scale;

    // 计算方案中所有元素的包围盒
    double planMinX = double.infinity, planMinY = double.infinity;
    double planMaxX = double.negativeInfinity,
        planMaxY = double.negativeInfinity;
    for (final el in plan.elements) {
      if (el.x < planMinX) planMinX = el.x;
      if (el.y < planMinY) planMinY = el.y;
      if (el.x + el.width > planMaxX) planMaxX = el.x + el.width;
      if (el.y + el.height > planMaxY) planMaxY = el.y + el.height;
    }
    final planCenterX = (planMinX + planMaxX) / 2;
    final planCenterY = (planMinY + planMaxY) / 2;

    // 偏移量：将方案中心映射到视口中心
    final offsetX = centerX - planCenterX;
    final offsetY = centerY - planCenterY;

    final newNodes = <CanvasNode>[];

    for (int i = 0; i < plan.elements.length; i++) {
      final element = plan.elements[i];

      NodeType nodeType;
      final data = <String, dynamic>{};

      switch (element.type) {
        case 'video':
          nodeType = NodeType.video;
          data['prompt'] = element.prompt;
          data['provider'] = _videoProvider;
          data['model'] =
              _currentVideoModel ??
              (_availableVideoModels.isNotEmpty
                  ? _availableVideoModels.first
                  : '');
          if (element.ratio != null) data['videoRatio'] = element.ratio;
          if (element.duration != null) data['ratio'] = element.duration;
          break;
        case 'text':
          nodeType = NodeType.text;
          data['text'] = element.prompt;
          data['fontFamily'] = _textFontFamily;
          data['fontSize'] = _textFontSize;
          data['color'] = _textColor;
          data['bold'] = _textBold;
          data['italic'] = _textItalic;
          data['underline'] = _textUnderline;
          break;
        default:
          nodeType = NodeType.image;
          data['prompt'] = element.prompt;
          data['provider'] = _imageProvider;
          data['model'] =
              _currentImageModel ??
              (_availableImageModels.isNotEmpty
                  ? _availableImageModels.first
                  : '');
          if (element.ratio != null) data['ratio'] = element.ratio;
          break;
      }

      // 应用偏移量，让节点出现在当前视口中心区域
      final node = CanvasNode(
        id: '${DateTime.now().millisecondsSinceEpoch}_agent_$i',
        type: nodeType,
        position: Offset(element.x + offsetX, element.y + offsetY),
        size: Size(element.width, element.height),
        data: data,
      );

      newNodes.add(node);
      debugPrint(
        '🎨 [Agent] 创建节点: ${element.type} 位置(${node.position.dx.toInt()}, ${node.position.dy.toInt()}) 大小(${node.size.width.toInt()}x${node.size.height.toInt()})',
      );
    }

    setState(() {
      _nodes.addAll(newNodes);
      _selectedNodeIds.clear();
      _selectedNodeIds.addAll(newNodes.map((n) => n.id));
      if (newNodes.isNotEmpty) {
        _selectedNodeId = newNodes.first.id;
      }
    });

    _saveCanvasData();

    // 统计要生成的元素
    final genCount = newNodes
        .where((n) => n.type == NodeType.image || n.type == NodeType.video)
        .length;
    if (genCount > 0) {
      _showMessage('已创建 ${newNodes.length} 个元素，正在自动生成 $genCount 个图片/视频...');
    } else {
      _showMessage('已创建 ${newNodes.length} 个文本元素');
    }

    // 自动开始生成所有图片和视频节点
    _autoGenerateNodes(newNodes);
  }

  /// 自动按顺序生成所有图片和视频节点
  Future<void> _autoGenerateNodes(List<CanvasNode> nodes) async {
    int successCount = 0;
    int failCount = 0;

    for (final node in nodes) {
      if (node.type == NodeType.image || node.type == NodeType.video) {
        final prompt = node.data['prompt'] as String?;
        if (prompt != null && prompt.isNotEmpty) {
          debugPrint(
            '🚀 [Agent] 开始生成: ${node.type.name} - ${prompt.substring(0, prompt.length > 50 ? 50 : prompt.length)}...',
          );
          try {
            await _generateContent(node);
            successCount++;
            debugPrint('✅ [Agent] 生成完成: ${node.id}');
          } catch (e) {
            failCount++;
            debugPrint('❌ [Agent] 生成失败: ${node.id} - $e');
          }
          // 刷新UI
          if (mounted) setState(() {});
        }
      }
    }

    if (mounted && (successCount > 0 || failCount > 0)) {
      _showMessage(
        '生成完成：$successCount 成功${failCount > 0 ? "，$failCount 失败" : ""}',
      );
    }
  }

  // 插入媒体按钮
  Widget _buildInsertMediaButton() {
    return Tooltip(
      message: "插入媒体",
      child: InkWell(
        onTap: () {
          _showInsertMediaMenu();
        },
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _surfaceSoft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _accentBlue.withValues(alpha: 0.10)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.add_photo_alternate_rounded,
            color: _textPrimary,
            size: 22,
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
      color: _surfaceStrong,
      elevation: 14,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _accentBlue.withValues(alpha: 0.12), width: 1),
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'image',
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _surfaceMuted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.image_outlined,
                  size: 18,
                  color: _accentBlue,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                "插入图片",
                style: TextStyle(
                  fontSize: 14,
                  color: _textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'video',
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _surfaceMuted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.videocam_outlined,
                  size: 18,
                  color: _accentBlue,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                "插入视频",
                style: TextStyle(
                  fontSize: 14,
                  color: _textPrimary,
                  fontWeight: FontWeight.w600,
                ),
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
        final screenCenterX =
            (MediaQuery.of(context).size.width / 2 - _canvasOffset.dx) /
                _scale -
            300;
        final screenCenterY =
            (MediaQuery.of(context).size.height / 2 - _canvasOffset.dy) /
                _scale -
            200;

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
          if (currentX - screenCenterX + nodeWidth > maxRowWidth &&
              newNodes.isNotEmpty) {
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
          maxHeightInRow = nodeHeight > maxHeightInRow
              ? nodeHeight
              : maxHeightInRow;

          _logger.info(
            '插入图片 ${newNodes.length}/${result.files.length}',
            module: 'AI画布',
            extra: {
              '图片尺寸': '${imageWidth.toInt()}x${imageHeight.toInt()}',
              '宽高比': aspectRatio.toStringAsFixed(2),
              '节点尺寸': '${nodeWidth.toInt()}x${nodeHeight.toInt()}',
            },
          );
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
        final screenCenterX =
            (MediaQuery.of(context).size.width / 2 - _canvasOffset.dx) /
                _scale -
            300;
        final screenCenterY =
            (MediaQuery.of(context).size.height / 2 - _canvasOffset.dy) /
                _scale -
            200;

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

          debugPrint(
            '处理视频 ${newNodes.length + 1}/${result.files.length}: $videoPath',
          );

          // 检查是否需要换行
          if (currentX - screenCenterX + defaultSize > maxRowWidth &&
              newNodes.isNotEmpty) {
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
        SnackBar(
          content: Text("插入视频失败: $e"),
          duration: const Duration(seconds: 3),
        ),
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
                _showTextToolbar = !_showTextToolbar;
              } else {
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
                _selectedStrokes.clear();
              }
            }
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: isActive
                ? const LinearGradient(colors: [_accentCyan, _accentIndigo])
                : null,
            color: isActive ? null : _surfaceSoft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive
                  ? Colors.white.withValues(alpha: 0.65)
                  : _accentBlue.withValues(alpha: 0.10),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: (isActive ? _accentBlue : Colors.black).withValues(
                  alpha: isActive ? 0.24 : 0.05,
                ),
                blurRadius: isActive ? 16 : 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: isActive ? Colors.white : _textPrimary,
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
              Text(
                "${_brushSize.toInt()}px",
                style: const TextStyle(fontSize: 11),
              ),
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

  // ==================== 图层面板 ====================

  /// 构建图层面板
  Widget _buildLayerPanel() {
    // 收集所有图层项
    final List<_LayerEntry> entries = [];

    // 节点图层
    for (final node in _nodes) {
      IconData icon;
      final name = _getNodeAlias(node);
      switch (node.type) {
        case NodeType.image:
          icon = Icons.image_outlined;
        case NodeType.video:
          icon = Icons.videocam_outlined;
        case NodeType.text:
          icon = Icons.text_fields;
      }
      entries.add(
        _LayerEntry(
          kind: _LayerKind.node,
          id: node.id,
          name: name,
          icon: icon,
          isSelected:
              _selectedNodeId == node.id || _selectedNodeIds.contains(node.id),
          isAgentHighlighted: _agentHighlightedNodeIds.contains(node.id),
          isHidden: _hiddenNodeIds.contains(node.id),
        ),
      );
    }

    // 涂鸦图层
    for (int i = 0; i < _strokes.length; i++) {
      entries.add(
        _LayerEntry(
          kind: _LayerKind.stroke,
          id: 'stroke_$i',
          index: i,
          name: '涂鸦 ${i + 1}',
          icon: Icons.brush,
          isSelected:
              _selectedStroke == _strokes[i] ||
              _selectedStrokes.contains(_strokes[i]),
          isHidden: _hiddenStrokeIndices.contains(i),
        ),
      );
    }

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: _borderColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // 标题栏
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _borderColor)),
            ),
            child: Row(
              children: [
                Icon(Icons.layers, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  '图层',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const Spacer(),
                Text(
                  '${entries.length}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => setState(() => _showLayerPanel = false),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 14, color: Colors.grey[500]),
                  ),
                ),
              ],
            ),
          ),
          // 图层列表
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.layers_clear,
                          size: 32,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '暂无图层',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry =
                          entries[entries.length - 1 - index]; // 倒序，最后添加的在上面
                      return _buildLayerItem(entry);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 构建单个图层项
  Widget _buildLayerItem(_LayerEntry entry) {
    return InkWell(
      onTap: () {
        setState(() {
          // 点击选中对应元素
          _selectedNodeId = null;
          _selectedNodeIds.clear();
          _selectedStroke = null;
          _selectedStrokes.clear();

          switch (entry.kind) {
            case _LayerKind.node:
              _selectedNodeId = entry.id;
            case _LayerKind.stroke:
              _selectedStroke = _strokes[entry.index!];
          }
        });
      },
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: entry.isSelected
              ? _accentBlue.withValues(alpha: 0.08)
              : entry.isAgentHighlighted
              ? const Color(0xFF22C55E).withValues(alpha: 0.10)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: _borderColor.withValues(alpha: 0.5)),
            left: entry.isSelected
                ? BorderSide(color: _accentBlue, width: 3)
                : entry.isAgentHighlighted
                ? const BorderSide(color: Color(0xFF22C55E), width: 3)
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            Icon(
              entry.icon,
              size: 14,
              color: entry.isHidden
                  ? Colors.grey[300]
                  : (entry.isSelected ? _accentBlue : Colors.grey[600]),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entry.name,
                style: TextStyle(
                  fontSize: 12,
                  color: entry.isHidden ? Colors.grey[400] : Colors.grey[800],
                  fontWeight: entry.isSelected
                      ? FontWeight.w600
                      : FontWeight.normal,
                  decoration: entry.isHidden
                      ? TextDecoration.lineThrough
                      : null,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            // 可见性切换
            InkWell(
              onTap: () {
                setState(() {
                  switch (entry.kind) {
                    case _LayerKind.node:
                      if (_hiddenNodeIds.contains(entry.id)) {
                        _hiddenNodeIds.remove(entry.id);
                      } else {
                        _hiddenNodeIds.add(entry.id);
                      }
                    case _LayerKind.stroke:
                      if (_hiddenStrokeIndices.contains(entry.index!)) {
                        _hiddenStrokeIndices.remove(entry.index!);
                      } else {
                        _hiddenStrokeIndices.add(entry.index!);
                      }
                  }
                });
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  entry.isHidden ? Icons.visibility_off : Icons.visibility,
                  size: 14,
                  color: entry.isHidden ? Colors.grey[400] : Colors.grey[500],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 迷你地图：显示画布内容概览和当前视口
  Widget _buildMinimap() {
    const mapWidth = 160.0;
    const mapHeight = 100.0;

    return Container(
      width: mapWidth,
      height: mapHeight,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: GestureDetector(
          onTapDown: (details) =>
              _onMinimapTap(details.localPosition, mapWidth, mapHeight),
          onPanUpdate: (details) =>
              _onMinimapTap(details.localPosition, mapWidth, mapHeight),
          child: CustomPaint(
            painter: _MinimapPainter(
              nodes: _nodes,
              strokes: _strokes,
              canvasOffset: _canvasOffset,
              scale: _scale,
              viewportSize: MediaQuery.of(context).size,
            ),
            size: const Size(mapWidth, mapHeight),
          ),
        ),
      ),
    );
  }

  /// 迷你地图点击/拖动：将点击位置转换为画布偏移
  void _onMinimapTap(Offset localPos, double mapWidth, double mapHeight) {
    // 复制 _MinimapPainter 的边界计算逻辑
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (var node in _nodes) {
      minX = minX < node.position.dx ? minX : node.position.dx;
      minY = minY < node.position.dy ? minY : node.position.dy;
      maxX = maxX > (node.position.dx + node.size.width)
          ? maxX
          : (node.position.dx + node.size.width);
      maxY = maxY > (node.position.dy + node.size.height)
          ? maxY
          : (node.position.dy + node.size.height);
    }
    for (var stroke in _strokes) {
      for (var p in stroke.points) {
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy > maxY) maxY = p.dy;
      }
    }

    final vpSize = MediaQuery.of(context).size;
    final vpLeft = -_canvasOffset.dx / _scale;
    final vpTop = -_canvasOffset.dy / _scale;
    final vpRight = (vpSize.width - _canvasOffset.dx) / _scale;
    final vpBottom = (vpSize.height - _canvasOffset.dy) / _scale;
    if (vpLeft < minX) minX = vpLeft;
    if (vpTop < minY) minY = vpTop;
    if (vpRight > maxX) maxX = vpRight;
    if (vpBottom > maxY) maxY = vpBottom;

    if (minX >= maxX || minY >= maxY) return;

    const padding = 50.0;
    minX -= padding;
    minY -= padding;
    maxX += padding;
    maxY += padding;

    final contentWidth = maxX - minX;
    final contentHeight = maxY - minY;
    final scaleX = mapWidth / contentWidth;
    final scaleY = mapHeight / contentHeight;
    final mapScale = scaleX < scaleY ? scaleX : scaleY;

    final offsetX = (mapWidth - contentWidth * mapScale) / 2;
    final offsetY = (mapHeight - contentHeight * mapScale) / 2;

    // 小地图坐标 → 世界坐标
    final worldX = (localPos.dx - offsetX) / mapScale + minX;
    final worldY = (localPos.dy - offsetY) / mapScale + minY;

    // 将视口中心移动到该世界坐标
    setState(() {
      _canvasOffset = Offset(
        vpSize.width / 2 - worldX * _scale,
        vpSize.height / 2 - worldY * _scale,
      );
    });
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
          // 适应窗口
          Tooltip(
            message: "适应窗口",
            child: IconButton(
              icon: const Icon(Icons.fit_screen, size: 16),
              onPressed: _zoomToFit,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),
          Container(width: 1, height: 20, color: _borderColor),
          IconButton(
            icon: const Icon(Icons.remove, size: 16),
            onPressed: () => _smoothZoomTo(_scale - 0.1),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          // 点击回到 100%
          GestureDetector(
            onTap: () => _smoothZoomTo(1.0),
            child: Tooltip(
              message: "重置为 100%",
              child: Text(
                "${(_scale * 100).toInt()}%",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 16),
            onPressed: () => _smoothZoomTo(_scale + 0.1),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          Container(width: 1, height: 20, color: _borderColor),
          // 网格开关
          Tooltip(
            message: _showGrid ? "隐藏网格" : "显示网格",
            child: IconButton(
              icon: Icon(
                _showGrid ? Icons.grid_on : Icons.grid_off,
                size: 16,
                color: _showGrid ? _accentBlue : Colors.grey[600],
              ),
              onPressed: () => setState(() => _showGrid = !_showGrid),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ),
          // 网格类型切换（仅在显示网格时）
          if (_showGrid)
            Tooltip(
              message: _gridDots ? "切换为线条" : "切换为点阵",
              child: IconButton(
                icon: Icon(
                  _gridDots ? Icons.circle : Icons.border_all,
                  size: 14,
                  color: Colors.grey[600],
                ),
                onPressed: () => setState(() => _gridDots = !_gridDots),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNodeCard(CanvasNode node) {
    final isSelected =
        _selectedNodeId == node.id || _selectedNodeIds.contains(node.id);
    final isAgentHighlighted = _agentHighlightedNodeIds.contains(node.id);

    return Stack(
      children: [
        GestureDetector(
          onTap: () {
            // 如果正在从画布选择参考图片或首尾帧
            if (_isSelectingFromCanvas && _targetNodeForImage != null) {
              // 只能选择图片节点（生成的图片或插入的媒体图片）
              final imagePath = node.type == NodeType.image
                  ? (node.data['generatedImagePath'] ??
                        node.data['displayImagePath'])
                  : null;
              if (imagePath != null) {
                final selectingFrameType =
                    _targetNodeForImage!.data['_selectingFrameType'];

                if (selectingFrameType != null) {
                  // 选择首帧或尾帧
                  setState(() {
                    if (selectingFrameType == 'first') {
                      _targetNodeForImage!.data['firstFrameImage'] = imagePath;
                    } else {
                      _targetNodeForImage!.data['lastFrameImage'] = imagePath;
                    }
                    _targetNodeForImage!.data.remove('_selectingFrameType');
                    _isSelectingFromCanvas = false;
                    _selectNode(_targetNodeForImage!.id);
                    _targetNodeForImage = null;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        "已设置${selectingFrameType == 'first' ? '首帧' : '尾帧'}图片",
                        style: const TextStyle(color: Color(0xFF555555), fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 0.3),
                      ),
                      backgroundColor: const Color(0xFFF0EBF5),
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
                    (_targetNodeForImage!.data['referenceImages']
                            as List<String>)
                        .add(imagePath);

                    _isSelectingFromCanvas = false;
                    _selectNode(_targetNodeForImage!.id);
                    _targetNodeForImage = null;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text("已添加参考图片", style: TextStyle(color: Color(0xFF555555), fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 0.3)),
                      backgroundColor: const Color(0xFFF0EBF5),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text("请选择包含图片的节点", style: TextStyle(color: Color(0xFF555555), fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 0.3)),
                    backgroundColor: const Color(0xFFF0EBF5),
                    duration: const Duration(seconds: 1),
                  ),
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
                  : isAgentHighlighted
                  ? Border.all(color: const Color(0xFF22C55E), width: 2)
                  : (_isSelectingFromCanvas && node.type == NodeType.image
                        ? Border.all(color: Colors.green, width: 2)
                        : null), // 不选中时无边框，更自然
              boxShadow: [
                BoxShadow(
                  color:
                      (isSelected
                              ? _accentBlue
                              : isAgentHighlighted
                              ? const Color(0xFF22C55E)
                              : Colors.black)
                          .withValues(
                            alpha: isSelected
                                ? 0.18
                                : isAgentHighlighted
                                ? 0.20
                                : 0.08,
                          ),
                  blurRadius: isSelected || isAgentHighlighted ? 16 : 8,
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
      final imageWidget = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(displayImagePath),
          fit: BoxFit.contain, // 使用 contain 完整显示图片
          gaplessPlayback: true,
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
              if (node.data['_sizeAdjusted'] != true) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _adjustNodeSizeToImage(node, displayImagePath);
                });
              }
              return child;
            }
            return frame == null
                ? const Center(child: CircularProgressIndicator())
                : child;
          },
        ),
      );

      // ✅ 添加拖动功能
      return DraggableMediaItem(
        filePath: displayImagePath,
        dragPreviewText: path.basename(displayImagePath),
        coverUrl: displayImagePath,
        child: imageWidget,
      );
    }

    // 优先显示生成的图片，而不是参考图片
    final generatedImagePath = node.data['generatedImagePath'];

    if (generatedImagePath != null && generatedImagePath is String) {
      // 显示API生成的图片
      final imageWidget = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(generatedImagePath),
          fit: BoxFit.contain, // 使用 contain 完整显示图片
          gaplessPlayback: true,
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

      // ✅ 添加拖动功能
      return DraggableMediaItem(
        filePath: generatedImagePath,
        dragPreviewText: path.basename(generatedImagePath),
        coverUrl: generatedImagePath,
        child: imageWidget,
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
    final videoPath =
        (generatedVideoPath != null && generatedVideoPath is String)
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
            if (width != null &&
                width > 0 &&
                node.data['_sizeAdjusted'] != true) {
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
          Text("视频", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        ],
      ),
    );
  }

  /// 调整视频节点大小以匹配视频宽高比
  void _adjustVideoNodeSize(
    CanvasNode node,
    double videoWidth,
    double videoHeight,
  ) {
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
          Text("视频加载失败", style: TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildTextNode(CanvasNode node) {
    // 获取文本样式设置（显式转 double，阻止 JSON 反序列化的 int 导致类型错误）
    final fontFamily = node.data['fontFamily'] ?? _textFontFamily;
    final double fontSize = (node.data['fontSize'] as num?)?.toDouble() ?? _textFontSize;
    final color = _getColorFromData(node.data['color'], _textColor);
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
            node.data['text']?.isEmpty ?? true
                ? "双击编辑文本..."
                : node.data['text'],
            style: TextStyle(
              fontSize: fontSize,
              color: node.data['text']?.isEmpty ?? true
                  ? Colors.black26
                  : color,
              fontFamily: fontFamily,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              decoration: underline
                  ? TextDecoration.underline
                  : TextDecoration.none,
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
                    const Text(
                      "字体",
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
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
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                          dropdownColor: Colors.white,
                          items:
                              [
                                    'Arial',
                                    'Times New Roman',
                                    'Courier New',
                                    'Georgia',
                                    'Verdana',
                                  ]
                                  .map(
                                    (font) => DropdownMenuItem(
                                      value: font,
                                      child: Text(font),
                                    ),
                                  )
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
                    const Text(
                      "字号",
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
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
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                          dropdownColor: Colors.white,
                          items:
                              [
                                    8.0,
                                    10.0,
                                    12.0,
                                    14.0,
                                    16.0,
                                    18.0,
                                    20.0,
                                    24.0,
                                    28.0,
                                    32.0,
                                    36.0,
                                    48.0,
                                    60.0,
                                    72.0,
                                  ]
                                  .map(
                                    (size) => DropdownMenuItem(
                                      value: size,
                                      child: Text("${size.toInt()}"),
                                    ),
                                  )
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
              _buildStyleButton(
                Icons.format_underline,
                "下划线",
                _textUnderline,
                () {
                  setState(() => _textUnderline = !_textUnderline);
                },
              ),
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

  Widget _buildStyleButton(
    IconData icon,
    String tooltip,
    bool isActive,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isActive
                ? _accentBlue.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: isActive
                ? Border.all(color: _accentBlue, width: 1.5)
                : null,
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
  Future<void> _pickFrameImage(
    CanvasNode node, {
    required bool isFirstFrame,
  }) async {
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
  void _selectFrameFromCanvas(
    CanvasNode targetNode, {
    required bool isFirstFrame,
  }) {
    setState(() {
      _isSelectingFromCanvas = true;
      _targetNodeForImage = targetNode;
      targetNode.data['_selectingFrameType'] = isFirstFrame ? 'first' : 'last';
      _selectNode(null);
    });
  }

  // 打开图片库 - 从素材库的图片库中选择（SharedPreferences image_library_data）
  void _openImageLibrary(CanvasNode targetNode, {bool? isFirstFrame}) async {
    final prefs = await SharedPreferences.getInstance();
    final imageLibJson = prefs.getString('image_library_data');
    if (imageLibJson == null || imageLibJson.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('图片库为空，请先在素材库中添加图片')));
      }
      return;
    }

    final List<dynamic> imageList = jsonDecode(imageLibJson);
    if (imageList.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('图片库为空，请先在素材库中添加图片')));
      }
      return;
    }

    // 转换为统一格式
    final entries = imageList
        .map((item) {
          final m = item as Map<String, dynamic>;
          return {
            'name': m['name'] as String? ?? '',
            'path': m['path'] as String? ?? '',
          };
        })
        .where((e) => e['path']!.isNotEmpty)
        .toList();

    if (!mounted) return;

    if (isFirstFrame != null) {
      // 首帧/尾帧模式 - 单选，直接设置图片路径
      final selected = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) =>
            _ImageLibraryDialog(imageEntries: entries, singleSelect: true),
      );
      if (selected != null && mounted) {
        setState(() {
          if (isFirstFrame) {
            targetNode.data['firstFrameImage'] = selected['path'];
          } else {
            targetNode.data['lastFrameImage'] = selected['path'];
          }
        });
      }
    } else {
      // 参考图片模式 - 插入 [📷name] 占位符到prompt
      final selected = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) =>
            _ImageLibraryDialog(imageEntries: entries, singleSelect: true),
      );
      if (selected != null && mounted) {
        final name = selected['name'] ?? '';
        if (name.isNotEmpty) {
          setState(() {
            final currentPrompt = targetNode.data['prompt'] as String? ?? '';
            targetNode.data['prompt'] = currentPrompt.isEmpty
                ? '[📷$name]'
                : '$currentPrompt [📷$name]';
          });
        }
      }
    }
  }

  /// 解析提示词中的 [📷name] 占位符，生成 segments 列表
  Future<List<Map<String, String>>> _parsePromptToSegments(
    String prompt,
    SharedPreferences prefs,
  ) async {
    final imageLibJson = prefs.getString('image_library_data');
    final Map<String, String> nameToPath = {};
    if (imageLibJson != null && imageLibJson.isNotEmpty) {
      final List<dynamic> imageList = jsonDecode(imageLibJson);
      for (final item in imageList) {
        final name = (item as Map<String, dynamic>)['name'] as String? ?? '';
        final filePath = item['path'] as String? ?? '';
        if (name.isNotEmpty && filePath.isNotEmpty) {
          nameToPath[name] = filePath;
        }
      }
    }

    final segments = <Map<String, String>>[];
    final pattern = RegExp(r'\[📷([^\]]+)\]');
    int lastEnd = 0;

    for (final match in pattern.allMatches(prompt)) {
      if (match.start > lastEnd) {
        final textBefore = prompt.substring(lastEnd, match.start).trim();
        if (textBefore.isNotEmpty) {
          segments.add({'type': 'text', 'content': textBefore});
        }
      }
      final name = match.group(1)!.trim();
      final filePath = nameToPath[name] ?? '';
      if (filePath.isNotEmpty) {
        segments.add({'type': 'image', 'name': name, 'path': filePath});
      } else {
        segments.add({'type': 'text', 'content': '[📷$name]'});
      }
      lastEnd = match.end;
    }

    if (lastEnd < prompt.length) {
      final textAfter = prompt.substring(lastEnd).trim();
      if (textAfter.isNotEmpty) {
        segments.add({'type': 'text', 'content': textAfter});
      }
    }

    return segments;
  }

  // 打开素材库
  void _openMaterialLibrary(CanvasNode node) async {
    // 根据节点类型决定显示的素材库类型
    // 图片节点：显示角色、场景、物品素材
    // 视频节点：显示角色、场景、物品、语音素材

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _MaterialLibraryDialog(nodeType: node.type),
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
            final referenceImages =
                node.data['referenceImages'] as List<String>;
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
            final referenceImages =
                node.data['referenceImages'] as List<String>;
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
            SnackBar(
              content: Text("已选择语音: $selectedVoice"),
              duration: const Duration(seconds: 2),
            ),
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

  // 取消画布选择模式
  void _cancelCanvasSelection() {
    if (!_isSelectingFromCanvas) return;
    setState(() {
      _targetNodeForImage?.data.remove('_selectingFrameType');
      _isSelectingFromCanvas = false;
      _targetNodeForImage = null;
    });
  }

  // 从画布选择参考图片
  void _selectReferenceFromCanvas(CanvasNode targetNode) {
    setState(() {
      _isSelectingFromCanvas = true;
      _targetNodeForImage = targetNode;
      _selectNode(null);
    });
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
  /// 通用节点右键菜单（lovart 风格：纯文字 + 快捷键，无图标、无色块、无装饰）
  void _showNodeContextMenu(Offset position, CanvasNode node) {
    final bool isText = node.type == NodeType.text;
    final bool isImage = node.type == NodeType.image;
    final bool isVideo = node.type == NodeType.video;
    final String? imagePath = isImage
        ? (node.data['generatedImagePath'] ?? node.data['displayImagePath']) as String?
        : null;
    final String? videoPath = isVideo
        ? node.data['generatedVideoPath'] as String?
        : null;

    PopupMenuItem<String> _item(String value, String label, [String? shortcut]) {
      return PopupMenuItem<String>(
        value: value,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13, color: Colors.black87)),
            if (shortcut != null) ...[
              const SizedBox(width: 32),
              Text(shortcut, style: TextStyle(fontSize: 12, color: Colors.grey[400])),
            ],
          ],
        ),
      );
    }

    final items = <PopupMenuEntry<String>>[
      _item('copy', '复制', 'Ctrl+C'),
      _item('paste', '粘贴', 'Ctrl+V'),
      _item('duplicate', '创建副本', 'Ctrl+D'),
    ];

    // 文本节点
    if (isText) {
      items.add(_item('edit_text', '编辑文本'));
    }

    // 图片节点
    if (imagePath != null) {
      items.add(_item('locate_file', '定位文件'));
    }

    // 视频节点
    if (videoPath != null) {
      items.add(_item('locate_file', '定位文件'));
      items.add(_item('play_video', '播放视频'));
    }

    items.add(_item('delete', '删除', 'Delete'));

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.15), width: 1),
      ),
      items: items,
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'copy':
          _selectNode(node.id);
          _copySelected();
          break;
        case 'paste':
          _pasteFromClipboard();
          break;
        case 'duplicate':
          _selectNode(node.id);
          _duplicate();
          break;
        case 'edit_text':
          setState(() => node.data['isEditing'] = true);
          break;
        case 'locate_file':
          final filePath = imagePath ?? videoPath;
          if (filePath != null) {
            Process.run('explorer', ['/select,', filePath]);
          }
          break;
        case 'play_video':
          if (videoPath != null) {
            Process.run('cmd', ['/c', 'start', '', videoPath]);
          }
          break;
        case 'delete':
          _selectNode(node.id);
          _deleteSelectedElements();
          _saveCanvasData();
          break;
      }
    });
  }

  // 保留旧方法名兼容
  void _showTextNodeContextMenu(Offset position, CanvasNode node) =>
      _showNodeContextMenu(position, node);

  // 显示文本节点编辑对话框
  void _showTextNodeEditDialog(CanvasNode node) {
    String tempFontFamily = node.data['fontFamily'] ?? _textFontFamily;
    double tempFontSize = node.data['fontSize'] ?? _textFontSize;
    Color tempColor = _getColorFromData(node.data['color'], _textColor);
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
                            const Text(
                              "字体",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: 40,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: _borderColor),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: tempFontFamily,
                                  isExpanded: true,
                                  icon: const Icon(
                                    Icons.arrow_drop_down,
                                    size: 20,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black87,
                                  ),
                                  dropdownColor: Colors.white,
                                  items:
                                      [
                                            'Arial',
                                            'Times New Roman',
                                            'Courier New',
                                            'Georgia',
                                            'Verdana',
                                          ]
                                          .map(
                                            (font) => DropdownMenuItem(
                                              value: font,
                                              child: Text(font),
                                            ),
                                          )
                                          .toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setDialogState(
                                        () => tempFontFamily = val,
                                      );
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
                            const Text(
                              "字号",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: 40,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: _borderColor),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<double>(
                                  value: tempFontSize,
                                  isExpanded: true,
                                  icon: const Icon(
                                    Icons.arrow_drop_down,
                                    size: 20,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black87,
                                  ),
                                  dropdownColor: Colors.white,
                                  items:
                                      [
                                            8.0,
                                            10.0,
                                            12.0,
                                            14.0,
                                            16.0,
                                            18.0,
                                            20.0,
                                            24.0,
                                            28.0,
                                            32.0,
                                            36.0,
                                            48.0,
                                            60.0,
                                            72.0,
                                          ]
                                          .map(
                                            (size) => DropdownMenuItem(
                                              value: size,
                                              child: Text("${size.toInt()}"),
                                            ),
                                          )
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
                            color: tempBold
                                ? _accentBlue.withValues(alpha: 0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: tempBold
                                ? Border.all(color: _accentBlue, width: 1.5)
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.format_bold,
                            size: 18,
                            color: tempBold ? _accentBlue : Colors.black54,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () =>
                            setDialogState(() => tempItalic = !tempItalic),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: tempItalic
                                ? _accentBlue.withValues(alpha: 0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: tempItalic
                                ? Border.all(color: _accentBlue, width: 1.5)
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.format_italic,
                            size: 18,
                            color: tempItalic ? _accentBlue : Colors.black54,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () => setDialogState(
                          () => tempUnderline = !tempUnderline,
                        ),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: tempUnderline
                                ? _accentBlue.withValues(alpha: 0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: tempUnderline
                                ? Border.all(color: _accentBlue, width: 1.5)
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.format_underline,
                            size: 18,
                            color: tempUnderline ? _accentBlue : Colors.black54,
                          ),
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
                        tempColor = HSVColor.fromAHSV(
                          1.0,
                          hue,
                          1.0,
                          1.0,
                        ).toColor();
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
                            left:
                                (HSVColor.fromColor(tempColor).hue / 360) *
                                    368 -
                                8,
                            top: -4,
                            child: Container(
                              width: 16,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                border: Border.all(
                                  color: Colors.black26,
                                  width: 2,
                                ),
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
                          colors: [
                            Colors.black,
                            HSVColor.fromColor(
                              tempColor,
                            ).withValue(1.0).toColor(),
                          ],
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                "确定",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
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
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
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
              const Text(
                "编辑",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black,
                  fontWeight: FontWeight.w500,
                ),
              ),
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
                child: const Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                "删除",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black,
                  fontWeight: FontWeight.w500,
                ),
              ),
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
                    Text(
                      "${tempWidth.toInt()}px",
                      style: const TextStyle(fontSize: 11),
                    ),
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
                      tempColor = HSVColor.fromAHSV(
                        1.0,
                        hue,
                        1.0,
                        1.0,
                      ).toColor();
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
                          left:
                              (HSVColor.fromColor(tempColor).hue / 360) * 368 -
                              8,
                          top: -4,
                          child: Container(
                            width: 16,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(
                                color: Colors.black26,
                                width: 2,
                              ),
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
                          HSVColor.fromColor(
                            tempColor,
                          ).withValue(1.0).toColor(),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                "确定",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showProviderModelCascadeMenu({
    required BuildContext anchorContext,
    required CanvasNode node,
  }) async {
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox?;
    if (anchorBox == null || overlayBox == null) return;

    final anchorTopLeft = anchorBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final anchorRect = Rect.fromLTWH(
      anchorTopLeft.dx,
      anchorTopLeft.dy,
      anchorBox.size.width,
      anchorBox.size.height,
    );

    final isVideo = node.type == NodeType.video;
    final providers = isVideo
        ? _getVideoProviderList()
        : _getImageProviderList();
    final currentProvider =
        (node.data['provider'] as String?) ??
        (isVideo ? _videoProvider : _imageProvider);

    final maxLeft = overlayBox.size.width - 680.0;
    final panelLeft = (anchorRect.left - 8).clamp(
      16.0,
      maxLeft < 16.0 ? 16.0 : maxLeft,
    );
    final maxTop = overlayBox.size.height - 356.0;
    final panelTop = (anchorRect.top - 8).clamp(
      16.0,
      maxTop < 16.0 ? 16.0 : maxTop,
    );

    String hoveredProvider = currentProvider;
    String? hoveredMiddleItem;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'provider_model_cascade',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            // 判断当前 provider 是否需要三列级联（Vidu: 工具→模型, 即梦: 模型→方式）
            final isThreeColumn =
                isVideo &&
                (hoveredProvider == 'vidu' || hoveredProvider == 'jimeng');

            // 第二列内容
            List<Map<String, String>> secondColumnItems;
            if (isVideo && hoveredProvider == 'vidu') {
              secondColumnItems = _getViduVideoTools();
            } else if (isVideo && hoveredProvider == 'jimeng') {
              secondColumnItems = _getJimengVideoModels();
            } else {
              final models = _getModelsForProvider(
                hoveredProvider,
                isVideo ? 'video' : 'image',
              );
              secondColumnItems = models
                  .map((m) => {'id': m, 'name': m})
                  .toList();
            }

            // 第三列内容（仅 Vidu/即梦 视频）
            List<Map<String, String>> thirdColumnItems = [];
            if (hoveredMiddleItem != null) {
              if (isVideo && hoveredProvider == 'vidu') {
                thirdColumnItems = _getViduModelsForTool(hoveredMiddleItem!);
              } else if (isVideo && hoveredProvider == 'jimeng') {
                thirdColumnItems = _getJimengModesForModel(hoveredMiddleItem!);
              }
            }

            final selectedModel = node.data['model'] as String?;

            Widget buildProviderRow(Map<String, String> provider) {
              final providerKey = provider['key']!;
              final isHovered = hoveredProvider == providerKey;
              final isSelected = currentProvider == providerKey;

              return MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) {
                  if (hoveredProvider != providerKey) {
                    setDialogState(() {
                      hoveredProvider = providerKey;
                      hoveredMiddleItem = null;
                    });
                  }
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isHovered ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          provider['name']!,
                          style: TextStyle(
                            fontSize: 14,
                            color: isHovered || isSelected
                                ? _textPrimary
                                : _textPrimary,
                            fontWeight: isHovered || isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 120),
                        opacity: isHovered ? 1 : 0,
                        child: const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: _textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            // 普通模型行（直接点击选择）
            Widget buildModelRow(String model) {
              final isSelected =
                  hoveredProvider == currentProvider && model == selectedModel;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  hoverColor: Colors.black.withValues(alpha: 0.05),
                  onTap: () {
                    setState(() {
                      node.data['provider'] = hoveredProvider;
                      node.data['model'] = model;
                    });
                    Navigator.of(dialogContext).pop();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            model,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: _textPrimary,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (isSelected)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: _textPrimary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // 中间列行（hover 展开第三列）
            Widget buildMiddleRow(Map<String, String> item) {
              final itemId = item['id']!;
              final itemName = item['name']!;
              final isHovered = hoveredMiddleItem == itemId;

              return MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) {
                  if (hoveredMiddleItem != itemId) {
                    setDialogState(() => hoveredMiddleItem = itemId);
                  }
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isHovered
                        ? const Color(0xFFF0F0EF)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          itemName,
                          style: TextStyle(
                            fontSize: 14,
                            color: _textPrimary,
                            fontWeight: isHovered
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 120),
                        opacity: isHovered ? 1 : 0,
                        child: const Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: _textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            // 第三列行（最终选择，保存到 node.data 和 SharedPreferences）
            Widget buildThirdRow(Map<String, String> item) {
              final itemId = item['id']!;
              final itemName = item['name']!;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  hoverColor: Colors.black.withValues(alpha: 0.05),
                  onTap: () async {
                    final prefs = await SharedPreferences.getInstance();
                    setState(() {
                      node.data['provider'] = hoveredProvider;
                      if (hoveredProvider == 'vidu') {
                        // Vidu: 中间列=工具, 第三列=模型
                        node.data['model'] = itemId;
                        node.data['webTool'] = hoveredMiddleItem;
                        ProviderPreferenceHelper.setVideoWebTool(
                          prefs,
                          hoveredProvider,
                          hoveredMiddleItem!,
                        );
                        ProviderPreferenceHelper.setVideoWebModel(
                          prefs,
                          hoveredProvider,
                          itemId,
                        );
                      } else if (hoveredProvider == 'jimeng') {
                        // 即梦: 中间列=模型, 第三列=方式
                        node.data['model'] = hoveredMiddleItem;
                        node.data['webMode'] = itemId;
                        ProviderPreferenceHelper.setVideoWebModel(
                          prefs,
                          hoveredProvider,
                          hoveredMiddleItem!,
                        );
                        ProviderPreferenceHelper.setVideoWebMode(
                          prefs,
                          hoveredProvider,
                          itemId,
                        );
                      }
                    });
                    Navigator.of(dialogContext).pop();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Text(
                      itemName,
                      style: const TextStyle(
                        fontSize: 14,
                        color: _textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            }

            return Material(
              color: Colors.transparent,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => Navigator.of(dialogContext).pop(),
                    ),
                  ),
                  Positioned(
                    left: panelLeft.toDouble(),
                    top: panelTop.toDouble(),
                    child: GestureDetector(
                      onTap: () {},
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 第一列：服务商
                          Container(
                            width: 238,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F8F7),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.10),
                                  blurRadius: 24,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: providers
                                  .map(buildProviderRow)
                                  .toList(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // 第二列：模型（或 Vidu 工具 / 即梦模型）
                          Container(
                            key: ValueKey('col2_$hoveredProvider'),
                            width: isThreeColumn ? 200 : 248,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 24,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: isThreeColumn
                                  ? secondColumnItems
                                        .map(buildMiddleRow)
                                        .toList()
                                  : secondColumnItems
                                        .map(
                                          (item) => buildModelRow(item['id']!),
                                        )
                                        .toList(),
                            ),
                          ),
                          // 第三列：Vidu 模型 / 即梦方式（条件显示）
                          if (isThreeColumn && thirdColumnItems.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Container(
                              key: ValueKey(
                                'col3_${hoveredProvider}_$hoveredMiddleItem',
                              ),
                              width: 200,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 24,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: thirdColumnItems
                                    .map(buildThirdRow)
                                    .toList(),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
    );
  }

  // 紧凑的编辑面板（浮动在节点下方）
  Widget _buildCompactEditPanel(CanvasNode node) {
    final referenceImages =
        (node.data['referenceImages'] as List?)?.whereType<String>().toList() ??
        [];
    final firstFrameImage = node.data['firstFrameImage'] as String?;
    final lastFrameImage = node.data['lastFrameImage'] as String?;
    final frameImages = <String>[];
    if (firstFrameImage != null) frameImages.add(firstFrameImage);
    if (lastFrameImage != null) frameImages.add(lastFrameImage);
    final isVideo = node.type == NodeType.video;
    final isGenerating = node.data['isGenerating'] == true;
    final currentProvider =
        (node.data['provider'] as String?) ??
        (isVideo ? _videoProvider : _imageProvider);
    final currentModel = node.data['model'] as String?;

    Widget buildActionSurface({
      required Widget child,
      bool accent = false,
      double? minWidth,
    }) {
      return Container(
        constraints: BoxConstraints(minWidth: minWidth ?? 0, minHeight: 36),
        padding: EdgeInsets.symmetric(
          horizontal: accent ? 14 : 10,
          vertical: accent ? 10 : 10,
        ),
        decoration: BoxDecoration(
          color: accent
              ? const Color(0xFF111827).withValues(alpha: 0.76)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: accent ? 0.12 : 0.0),
              blurRadius: accent ? 12 : 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      );
    }

    Widget buildIconSurface({
      required Widget child,
      int? count,
      String? badge,
    }) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: child,
          ),
          if (count != null && count > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          if (badge != null)
            Positioned(
              left: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      );
    }

    Widget buildPreviewTile({
      required String imagePath,
      required String label,
      required VoidCallback onRemove,
    }) {
      return Container(
        width: 44,
        height: 44,
        margin: const EdgeInsets.only(right: 8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => Dialog(
                    backgroundColor: Colors.transparent,
                    child: Stack(
                      children: [
                        Center(
                          child: InteractiveViewer(
                            child: Image.file(
                              File(imagePath),
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 20,
                          right: 20,
                          child: IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 32,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              child: Container(
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(File(imagePath), fit: BoxFit.cover),
                ),
              ),
            ),
            Positioned(
              top: -4,
              right: -4,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.70),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 10, color: Colors.white),
                ),
              ),
            ),
            if (label.isNotEmpty)
              Positioned(
                left: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.58),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    Widget buildImageReferenceButton() {
      return PopupMenuButton<String>(
        tooltip: '添加参考图',
        offset: const Offset(0, 46),
        elevation: 14,
        color: Colors.white,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        icon: buildIconSurface(
          count: referenceImages.isEmpty ? null : referenceImages.length,
          child: const Icon(
            Icons.add_photo_alternate_outlined,
            size: 18,
            color: _textPrimary,
          ),
        ),
        itemBuilder: (context) => const [
          PopupMenuItem<String>(
            value: 'local',
            child: Text(
              '从本地上传图片',
              style: TextStyle(
                fontSize: 14,
                color: _textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          PopupMenuItem<String>(
            value: 'library',
            child: Text(
              '素材库',
              style: TextStyle(
                fontSize: 14,
                color: _textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          PopupMenuItem<String>(
            value: 'imageLibrary',
            child: Text(
              '图片库',
              style: TextStyle(
                fontSize: 14,
                color: _textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          PopupMenuItem<String>(
            value: 'canvas',
            child: Text(
              '从画布选择',
              style: TextStyle(
                fontSize: 14,
                color: _textPrimary,
                fontWeight: FontWeight.w600,
              ),
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
            case 'imageLibrary':
              _openImageLibrary(node);
              break;
            case 'canvas':
              _selectReferenceFromCanvas(node);
              break;
          }
        },
      );
    }

    Widget buildFramePickerButton({
      required String tooltip,
      required String? previewPath,
      required String label,
      required bool isFirstFrame,
    }) {
      return PopupMenuButton<String>(
        tooltip: tooltip,
        offset: const Offset(0, 40),
        elevation: 14,
        color: Colors.white,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: buildActionSurface(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: _textPrimary,
              fontWeight: previewPath != null
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
        ),
        itemBuilder: (context) => const [
          PopupMenuItem<String>(
            value: 'local',
            child: Text(
              '从本地上传图片',
              style: TextStyle(
                fontSize: 14,
                color: _textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          PopupMenuItem<String>(
            value: 'library',
            child: Text(
              '素材库',
              style: TextStyle(
                fontSize: 14,
                color: _textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          PopupMenuItem<String>(
            value: 'imageLibrary',
            child: Text(
              '图片库',
              style: TextStyle(
                fontSize: 14,
                color: _textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          PopupMenuItem<String>(
            value: 'canvas',
            child: Text(
              '从画布选择',
              style: TextStyle(
                fontSize: 14,
                color: _textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        onSelected: (value) {
          switch (value) {
            case 'local':
              _pickFrameImage(node, isFirstFrame: isFirstFrame);
              break;
            case 'library':
              _openMaterialLibrary(node);
              break;
            case 'imageLibrary':
              _openImageLibrary(node, isFirstFrame: isFirstFrame);
              break;
            case 'canvas':
              _selectFrameFromCanvas(node, isFirstFrame: isFirstFrame);
              break;
          }
        },
      );
    }

    final toolbarItems = <Widget>[
      buildImageReferenceButton(),
      Builder(
        builder: (buttonContext) {
          return Tooltip(
            message: currentModel == null
                ? '选择服务商与模型'
                : '${_getProviderDisplayName(currentProvider)} · ${_getShortModelName(currentModel, currentProvider)}',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                hoverColor: Colors.black.withValues(alpha: 0.05),
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                onTap: () => _showProviderModelCascadeMenu(
                  anchorContext: buttonContext,
                  node: node,
                ),
                borderRadius: BorderRadius.circular(13),
                child: buildActionSurface(
                  minWidth: 0,
                  child: Text(
                    _getProviderDisplayName(currentProvider),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _textPrimary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      _buildCompactDropdown(
        value: _normalizeDropdownValue(
          node.data['resolution'] as String?,
          const ['1K', '2K', '4K'],
        ),
        items: const ['1K', '2K', '4K'],
        onChanged: (val) {
          if (val != null) {
            setState(() => node.data['resolution'] = val);
          }
        },
      ),
      if (isVideo) ...[
        buildFramePickerButton(
          tooltip: '设置首帧图片',
          previewPath: firstFrameImage,
          label: firstFrameImage != null ? '首帧 ✓' : '首帧',
          isFirstFrame: true,
        ),
        buildFramePickerButton(
          tooltip: '设置尾帧图片',
          previewPath: lastFrameImage,
          label: lastFrameImage != null ? '尾帧 ✓' : '尾帧',
          isFirstFrame: false,
        ),
        _buildCompactDropdown(
          value: _normalizeDropdownValue(
            node.data['videoRatio'] as String?,
            const ['16:9', '9:16', '1:1', '4:3', '3:4'],
          ),
          items: const ['16:9', '9:16', '1:1', '4:3', '3:4'],
          onChanged: (val) {
            if (val != null) {
              setState(() => node.data['videoRatio'] = val);
            }
          },
        ),
        _buildCompactDropdown(
          value: _normalizeDropdownValue(node.data['ratio'] as String?, const [
            '5s',
            '8s',
            '10s',
            '15s',
          ]),
          items: const ['5s', '8s', '10s', '15s'],
          onChanged: (val) {
            if (val != null) {
              setState(() => node.data['ratio'] = val);
            }
          },
        ),
      ] else
        _buildCompactDropdown(
          value: _normalizeDropdownValue(node.data['ratio'] as String?, const [
            '1:1',
            '16:9',
            '9:16',
            '4:3',
            '3:4',
          ]),
          items: const ['1:1', '16:9', '9:16', '4:3', '3:4'],
          onChanged: (val) {
            if (val != null) {
              setState(() => node.data['ratio'] = val);
            }
          },
        ),
    ];

    return Container(
      width: isVideo ? 600 : 520,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            key: ValueKey('${node.id}_${node.data['prompt'] ?? ''}'),
            initialValue: node.data['prompt'] as String? ?? '',
            decoration: InputDecoration(
              hintText: isVideo ? '描述视频画面、动作和镜头…' : '今天我们要创作什么',
              hintStyle: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              filled: true,
              fillColor: const Color(0xFFFDFEFF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Colors.black.withValues(alpha: 0.05),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                borderSide: BorderSide(
                  color: Colors.black.withValues(alpha: 0.14),
                  width: 1.1,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            minLines: 3,
            maxLines: 3,
            style: const TextStyle(
              fontSize: 14,
              color: _textPrimary,
              height: 1.45,
            ),
            onChanged: (val) {
              node.data['prompt'] = val;
            },
          ),
          if (referenceImages.isNotEmpty || frameImages.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (int i = 0; i < referenceImages.length; i++)
                    buildPreviewTile(
                      imagePath: referenceImages[i],
                      label: '',
                      onRemove: () {
                        setState(() {
                          final updatedImages = List<String>.from(
                            referenceImages,
                          )..removeAt(i);
                          if (updatedImages.isEmpty) {
                            node.data.remove('referenceImages');
                          } else {
                            node.data['referenceImages'] = updatedImages;
                          }
                        });
                      },
                    ),
                  if (firstFrameImage != null)
                    buildPreviewTile(
                      imagePath: firstFrameImage,
                      label: '首',
                      onRemove: () {
                        setState(() {
                          node.data.remove('firstFrameImage');
                        });
                      },
                    ),
                  if (lastFrameImage != null)
                    buildPreviewTile(
                      imagePath: lastFrameImage,
                      label: '尾',
                      onRemove: () {
                        setState(() {
                          node.data.remove('lastFrameImage');
                        });
                      },
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: toolbarItems,
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                onTap: isGenerating ? null : () => _generateContent(node),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF5EECD3), Color(0xFF3B9AED)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3B9AED).withValues(alpha: 0.30),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: isGenerating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                  ),
                ),
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
    final safeValue = _normalizeDropdownValue(value, items);

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isDense: true,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: _textSecondary,
          ),
          style: const TextStyle(
            fontSize: 12,
            color: _textPrimary,
            fontWeight: FontWeight.w400,
          ),
          dropdownColor: Colors.white,
          menuMaxHeight: 320,
          items: items
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  String _normalizeDropdownValue(String? value, List<String> items) {
    if (items.isEmpty) {
      return '';
    }
    if (value != null && items.contains(value)) {
      return value;
    }
    return items.first;
  }
}

// 画布工具
enum CanvasTool {
  select, // 选择
  pan, // 拖动画布（手掌）
  draw, // 画笔
  text, // 文本
  image, // 图片
  video, // 视频
}

/// 图层项类型
enum _LayerKind { node, stroke }

/// 图层面板的条目数据
class _LayerEntry {
  final _LayerKind kind;
  final String id;
  final int? index; // 涂鸦/形状的列表索引
  final String name;
  final IconData icon;
  final bool isSelected;
  final bool isAgentHighlighted;
  final bool isHidden;

  _LayerEntry({
    required this.kind,
    required this.id,
    this.index,
    required this.name,
    required this.icon,
    this.isSelected = false,
    this.isAgentHighlighted = false,
    this.isHidden = false,
  });
}

// 调整大小手柄
enum ResizeHandle { topLeft, topRight, bottomLeft, bottomRight }

// 节点类型
enum NodeType { image, video, text }

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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 46,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _isHovered
                ? (widget.isClose
                      ? const Color(0xFFE11D48).withValues(alpha: 0.12)
                      : const Color(0xFF0F172A).withValues(alpha: 0.06))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            widget.icon,
            size: 16,
            color: _isHovered && widget.isClose
                ? const Color(0xFFC81E4B)
                : const Color(0xFF334155),
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
  final Set<DrawingStroke> selectedStrokes;
  final Offset canvasOffset;
  final double scale;

  DrawingPainter({
    required this.strokes,
    this.currentStroke,
    this.selectedStroke,
    this.selectedStrokes = const {},
    required this.canvasOffset,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制已完成的笔画
    for (var stroke in strokes) {
      _drawStroke(
        canvas,
        stroke,
        stroke == selectedStroke || selectedStrokes.contains(stroke),
      );
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

// 对齐参考线绘制器
class _AlignGuidePainter extends CustomPainter {
  final List<double> guideX;
  final List<double> guideY;

  _AlignGuidePainter({required this.guideX, required this.guideY});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x663B82F6)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    for (var x in guideX) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y in guideY) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AlignGuidePainter oldDelegate) {
    return guideX != oldDelegate.guideX || guideY != oldDelegate.guideY;
  }
}

/// 网格背景绘制器
class _GridPainter extends CustomPainter {
  final Offset canvasOffset;
  final double scale;
  final bool isDots;

  _GridPainter({
    required this.canvasOffset,
    required this.scale,
    required this.isDots,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const gridSize = 40.0; // 基础网格大小
    final step = gridSize * scale;
    if (step < 5) return; // 太小不画

    final paint = Paint()
      ..color = const Color(0xFFDEE2E6)
      ..strokeWidth = 0.5;

    // 计算偏移后的起始位置
    final startX = canvasOffset.dx % step;
    final startY = canvasOffset.dy % step;

    if (isDots) {
      paint.style = PaintingStyle.fill;
      for (double x = startX; x < size.width; x += step) {
        for (double y = startY; y < size.height; y += step) {
          canvas.drawCircle(Offset(x, y), 1.2, paint);
        }
      }
    } else {
      paint.style = PaintingStyle.stroke;
      for (double x = startX; x < size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
      for (double y = startY; y < size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return canvasOffset != oldDelegate.canvasOffset ||
        scale != oldDelegate.scale ||
        isDots != oldDelegate.isDots;
  }
}

class _MinimapPainter extends CustomPainter {
  final List<CanvasNode> nodes;
  final List<DrawingStroke> strokes;
  final Offset canvasOffset;
  final double scale;
  final Size viewportSize;

  _MinimapPainter({
    required this.nodes,
    required this.strokes,
    required this.canvasOffset,
    required this.scale,
    required this.viewportSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 计算画布内容的边界
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (var node in nodes) {
      minX = minX < node.position.dx ? minX : node.position.dx;
      minY = minY < node.position.dy ? minY : node.position.dy;
      maxX = maxX > (node.position.dx + node.size.width)
          ? maxX
          : (node.position.dx + node.size.width);
      maxY = maxY > (node.position.dy + node.size.height)
          ? maxY
          : (node.position.dy + node.size.height);
    }
    for (var stroke in strokes) {
      for (var p in stroke.points) {
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy > maxY) maxY = p.dy;
      }
    }

    // 包含当前视口范围
    final vpLeft = -canvasOffset.dx / scale;
    final vpTop = -canvasOffset.dy / scale;
    final vpRight = (viewportSize.width - canvasOffset.dx) / scale;
    final vpBottom = (viewportSize.height - canvasOffset.dy) / scale;
    if (vpLeft < minX) minX = vpLeft;
    if (vpTop < minY) minY = vpTop;
    if (vpRight > maxX) maxX = vpRight;
    if (vpBottom > maxY) maxY = vpBottom;

    if (minX >= maxX || minY >= maxY) return;

    // 增加边距
    final padding = 50.0;
    minX -= padding;
    minY -= padding;
    maxX += padding;
    maxY += padding;

    final contentWidth = maxX - minX;
    final contentHeight = maxY - minY;
    final scaleX = size.width / contentWidth;
    final scaleY = size.height / contentHeight;
    final mapScale = scaleX < scaleY ? scaleX : scaleY;

    final offsetX = (size.width - contentWidth * mapScale) / 2;
    final offsetY = (size.height - contentHeight * mapScale) / 2;

    Offset toMap(double x, double y) => Offset(
      (x - minX) * mapScale + offsetX,
      (y - minY) * mapScale + offsetY,
    );

    // 背景
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFFF8F9FA),
    );

    // 绘制节点
    final nodePaint = Paint()
      ..color = const Color(0xFFADB5BD)
      ..style = PaintingStyle.fill;
    for (var node in nodes) {
      final tl = toMap(node.position.dx, node.position.dy);
      final br = toMap(
        node.position.dx + node.size.width,
        node.position.dy + node.size.height,
      );
      canvas.drawRect(Rect.fromPoints(tl, br), nodePaint);
    }

    // 绘制笔画 (简化为点)
    final strokePaint = Paint()
      ..color = const Color(0xFF868E96)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var stroke in strokes) {
      if (stroke.points.length < 2) continue;
      final path = Path();
      final first = toMap(stroke.points.first.dx, stroke.points.first.dy);
      path.moveTo(first.dx, first.dy);
      for (var i = 1; i < stroke.points.length; i++) {
        final p = toMap(stroke.points[i].dx, stroke.points[i].dy);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, strokePaint);
    }

    // 绘制视口框
    final vpTL = toMap(vpLeft, vpTop);
    final vpBR = toMap(vpRight, vpBottom);
    final vpPaint = Paint()
      ..color = const Color(0xFF3B82F6).withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromPoints(vpTL, vpBR), vpPaint);
    final vpBorderPaint = Paint()
      ..color = const Color(0xFF3B82F6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromPoints(vpTL, vpBR), vpBorderPaint);
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) => true;
}

// 框选矩形绘制器
class SelectionBoxPainter extends CustomPainter {
  final Offset start;
  final Offset end;

  SelectionBoxPainter({required this.start, required this.end});

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

  const _MaterialLibraryDialog({required this.nodeType});

  @override
  State<_MaterialLibraryDialog> createState() => _MaterialLibraryDialogState();
}

class _MaterialLibraryDialogState extends State<_MaterialLibraryDialog> {
  int _selectedCategoryIndex = 0;
  final List<String> _imageCategories = ['角色素材', '场景素材', '物品素材'];
  final List<String> _videoCategories = ['角色素材', '场景素材', '物品素材', '语音库'];
  final List<IconData> _categoryIcons = [
    Icons.person,
    Icons.landscape,
    Icons.inventory_2,
    Icons.mic,
  ];

  // 实际素材数据
  final Map<int, List<AssetStyle>> _stylesByCategory = {};
  List<VoiceAsset> _voiceAssets = [];
  bool _isLoading = true;

  final Set<String> _selectedImages = {};
  String? _selectedVoice;
  String _searchQuery = '';

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
            if (categoryIndex >= 0 && categoryIndex <= 2) {
              // 前3个分类
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
    final categories = widget.nodeType == NodeType.image
        ? _imageCategories
        : _videoCategories;
    final isVoiceCategory =
        widget.nodeType == NodeType.video && _selectedCategoryIndex == 3;
    final allAssets = isVoiceCategory ? <AssetItem>[] : _getCurrentAssets();
    final filteredAssets = _searchQuery.isEmpty
        ? allAssets
        : allAssets
              .where(
                (a) =>
                    a.name.toLowerCase().contains(_searchQuery.toLowerCase()),
              )
              .toList();
    final voices = isVoiceCategory ? _voiceAssets : <VoiceAsset>[];

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 500,
        height: 480,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Icon(Icons.photo_library, color: Colors.grey[700], size: 22),
                const SizedBox(width: 8),
                const Text(
                  '选择素材',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (_selectedImages.isNotEmpty)
                  Text(
                    '已选 ${_selectedImages.length}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.grey[500], size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 分类标签栏
            Row(
              children: List.generate(categories.length, (i) {
                final isActive = _selectedCategoryIndex == i;
                final count = i <= 2
                    ? (_stylesByCategory[i]?.fold<int>(
                            0,
                            (sum, s) => sum + s.assets.length,
                          ) ??
                          0)
                    : _voiceAssets.length;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _selectedCategoryIndex = i;
                      _searchQuery = '';
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: isActive
                                ? const Color(0xFF111827)
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _categoryIcons[i],
                            size: 16,
                            color: isActive
                                ? const Color(0xFF111827)
                                : Colors.grey[400],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${categories[i]}($count)',
                            style: TextStyle(
                              color: isActive
                                  ? const Color(0xFF111827)
                                  : Colors.grey[400],
                              fontSize: 12,
                              fontWeight: isActive
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            // 搜索栏
            if (!isVoiceCategory)
              TextField(
                style: const TextStyle(color: Color(0xFF111827), fontSize: 13),
                decoration: InputDecoration(
                  hintText: '搜索素材名称...',
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12),
                  prefixIcon: Icon(
                    Icons.search,
                    color: Colors.grey[400],
                    size: 18,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            const SizedBox(height: 8),
            // 素材网格
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : (filteredAssets.isEmpty && voices.isEmpty)
                  ? Center(
                      child: Text(
                        _searchQuery.isEmpty ? '该分类暂无素材' : '无匹配结果',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    )
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 0.85,
                          ),
                      itemCount: isVoiceCategory
                          ? voices.length
                          : filteredAssets.length,
                      itemBuilder: (context, index) {
                        if (isVoiceCategory) {
                          final voice = voices[index];
                          final isSelected = _selectedVoice == voice.id;
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _selectedVoice = voice.id),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(
                                        0xFF111827,
                                      ).withValues(alpha: 0.06)
                                    : Colors.grey[50],
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF111827)
                                      : Colors.grey[300]!,
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
                                    color: isSelected
                                        ? const Color(0xFF111827)
                                        : Colors.grey[500],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    voice.name,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isSelected
                                          ? const Color(0xFF111827)
                                          : Colors.grey[700],
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.normal,
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
                          final asset = filteredAssets[index];
                          final isSelected = _selectedImages.contains(
                            asset.path,
                          );
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
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF111827)
                                      : Colors.grey[300]!,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(7),
                                      ),
                                      child: Image.file(
                                        File(asset.path),
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: Colors.grey[100],
                                          child: Icon(
                                            Icons.broken_image,
                                            color: Colors.grey[400],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Text(
                                      asset.name,
                                      style: TextStyle(
                                        color: Colors.grey[800],
                                        fontSize: 10,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
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
            const SizedBox(height: 12),
            // 底部按钮
            Row(
              children: [
                if (!isVoiceCategory)
                  Text(
                    '已选择 ${_selectedImages.length}/10',
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('取消', style: TextStyle(color: Colors.grey[500])),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    if (isVoiceCategory) {
                      if (_selectedVoice != null) {
                        Navigator.pop(context, {'voice': _selectedVoice});
                      }
                    } else {
                      if (_selectedImages.isNotEmpty) {
                        Navigator.pop(context, {
                          'images': _selectedImages.toList(),
                        });
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF111827),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
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

// 图片库对话框 - 展示画布上所有已生成的图片
class _ImageLibraryDialog extends StatefulWidget {
  final List<Map<String, String>> imageEntries; // {name, path}
  final bool singleSelect;

  const _ImageLibraryDialog({
    required this.imageEntries,
    this.singleSelect = true,
  });

  @override
  State<_ImageLibraryDialog> createState() => _ImageLibraryDialogState();
}

class _ImageLibraryDialogState extends State<_ImageLibraryDialog> {
  int _selectedIndex = -1;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _searchQuery.isEmpty
        ? widget.imageEntries
        : widget.imageEntries
              .where(
                (e) => (e['name'] ?? '').toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ),
              )
              .toList();

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 500,
        height: 480,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.collections_outlined,
                  color: Colors.grey[700],
                  size: 22,
                ),
                const SizedBox(width: 8),
                const Text(
                  '图片库',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '素材库中的图片',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.grey[500], size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              style: const TextStyle(color: Color(0xFF111827), fontSize: 13),
              decoration: InputDecoration(
                hintText: '搜索图片名称...',
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12),
                prefixIcon: Icon(
                  Icons.search,
                  color: Colors.grey[400],
                  size: 18,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        _searchQuery.isEmpty ? '图片库为空，请先在素材库中添加图片' : '无匹配结果',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    )
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 0.85,
                          ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final entry = filtered[index];
                        final imgPath = entry['path'] ?? '';
                        final name = entry['name'] ?? '';
                        final isSelected =
                            _selectedIndex >= 0 &&
                            _selectedIndex < widget.imageEntries.length &&
                            widget.imageEntries[_selectedIndex]['path'] ==
                                imgPath;

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              final globalIndex = widget.imageEntries.indexOf(
                                entry,
                              );
                              _selectedIndex = isSelected ? -1 : globalIndex;
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF111827)
                                    : Colors.grey[300]!,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(7),
                                    ),
                                    child:
                                        imgPath.isNotEmpty &&
                                            File(imgPath).existsSync()
                                        ? Image.file(
                                            File(imgPath),
                                            fit: BoxFit.cover,
                                            width: double.infinity,
                                          )
                                        : Container(
                                            color: Colors.grey[100],
                                            child: Icon(
                                              Icons.image,
                                              color: Colors.grey[400],
                                              size: 32,
                                            ),
                                          ),
                                  ),
                                ),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                    horizontal: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: const BorderRadius.vertical(
                                      bottom: Radius.circular(7),
                                    ),
                                  ),
                                  child: Text(
                                    name,
                                    style: TextStyle(
                                      color: Colors.grey[800],
                                      fontSize: 10,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('取消', style: TextStyle(color: Colors.grey[500])),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _selectedIndex < 0
                      ? null
                      : () => Navigator.pop(
                          context,
                          widget.imageEntries[_selectedIndex],
                        ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF111827),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
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
      assets:
          (json['assets'] as List?)
              ?.map((item) => AssetItem.fromJson(item as Map<String, dynamic>))
              .toList() ??
          [],
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
