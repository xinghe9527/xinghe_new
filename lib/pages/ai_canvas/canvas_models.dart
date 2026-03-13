import 'package:flutter/material.dart';

/// 图层类型
enum LayerType {
  image,   // 图片图层
  video,   // 视频图层
  text,    // 文本图层
  drawing, // 涂鸦图层
  group,   // 分组图层
}

/// 画布工具
enum CanvasTool {
  select,  // 选择
  pan,     // 拖动画布
  draw,    // 画笔
  text,    // 文本
  image,   // 图片
  video,   // 视频
}


/// 调整大小手柄
enum ResizeHandle {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

/// 画布图层 — 替代原来的 CanvasNode
/// 增加了图层管理所需的属性：名称、层级、可见性、锁定、透明度
class CanvasLayer {
  String id;
  String name;          // 图层名称（用户可编辑）
  LayerType type;
  Offset position;
  Size size;
  Map<String, dynamic> data;

  // 图层管理属性
  int zIndex;           // 层级顺序（越大越靠前）
  bool visible;         // 是否可见
  bool locked;          // 是否锁定（锁定后不可拖动/编辑）
  double opacity;       // 透明度 0.0~1.0

  CanvasLayer({
    required this.id,
    required this.name,
    required this.type,
    required this.position,
    required this.size,
    required this.data,
    this.zIndex = 0,
    this.visible = true,
    this.locked = false,
    this.opacity = 1.0,
  });

  /// 从旧的 CanvasNode 数据迁移
  factory CanvasLayer.fromLegacyNode(Map<String, dynamic> nodeData, int index) {
    final typeStr = nodeData['type'] as String;
    LayerType type;
    if (typeStr.contains('image')) {
      type = LayerType.image;
    } else if (typeStr.contains('video')) {
      type = LayerType.video;
    } else {
      type = LayerType.text;
    }

    final position = nodeData['position'] as Map<String, dynamic>;
    final size = nodeData['size'] as Map<String, dynamic>;
    final data = Map<String, dynamic>.from(nodeData['data'] as Map);

    return CanvasLayer(
      id: nodeData['id'] as String,
      name: nodeData['name'] as String? ?? _defaultName(type, index),
      type: type,
      position: Offset(
        (position['dx'] as num).toDouble(),
        (position['dy'] as num).toDouble(),
      ),
      size: Size(
        (size['width'] as num).toDouble(),
        (size['height'] as num).toDouble(),
      ),
      data: data,
      zIndex: nodeData['zIndex'] as int? ?? index,
      visible: nodeData['visible'] as bool? ?? true,
      locked: nodeData['locked'] as bool? ?? false,
      opacity: (nodeData['opacity'] as num?)?.toDouble() ?? 1.0,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.toString(),
      'position': {'dx': position.dx, 'dy': position.dy},
      'size': {'width': size.width, 'height': size.height},
      'data': data.map((key, value) {
        if (value is String || value is num || value is bool || value == null) {
          return MapEntry(key, value);
        }
        if (value is Color) {
          return MapEntry(key, value.value);
        }
        if (value is List) {
          return MapEntry(key, value);
        }
        return MapEntry(key, value.toString());
      }),
      'zIndex': zIndex,
      'visible': visible,
      'locked': locked,
      'opacity': opacity,
    };
  }

  /// 从 JSON 反序列化
  factory CanvasLayer.fromJson(Map<String, dynamic> json, int fallbackIndex) {
    final typeStr = json['type'] as String;
    LayerType type;
    if (typeStr.contains('image')) {
      type = LayerType.image;
    } else if (typeStr.contains('video')) {
      type = LayerType.video;
    } else if (typeStr.contains('text')) {
      type = LayerType.text;
    } else if (typeStr.contains('drawing')) {
      type = LayerType.drawing;
    } else if (typeStr.contains('group')) {
      type = LayerType.group;
    } else {
      type = LayerType.text;
    }

    final position = json['position'] as Map<String, dynamic>;
    final size = json['size'] as Map<String, dynamic>;
    final data = Map<String, dynamic>.from(json['data'] as Map? ?? {});

    return CanvasLayer(
      id: json['id'] as String,
      name: json['name'] as String? ?? _defaultName(type, fallbackIndex),
      type: type,
      position: Offset(
        (position['dx'] as num).toDouble(),
        (position['dy'] as num).toDouble(),
      ),
      size: Size(
        (size['width'] as num).toDouble(),
        (size['height'] as num).toDouble(),
      ),
      data: data,
      zIndex: json['zIndex'] as int? ?? fallbackIndex,
      visible: json['visible'] as bool? ?? true,
      locked: json['locked'] as bool? ?? false,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
    );
  }

  /// 生成默认图层名称
  static String _defaultName(LayerType type, int index) {
    switch (type) {
      case LayerType.image:
        return '图片 ${index + 1}';
      case LayerType.video:
        return '视频 ${index + 1}';
      case LayerType.text:
        return '文本 ${index + 1}';
      case LayerType.drawing:
        return '涂鸦 ${index + 1}';
      case LayerType.group:
        return '分组 ${index + 1}';
    }
  }

  /// 获取图层的图标
  IconData get icon {
    switch (type) {
      case LayerType.image:
        return Icons.image_outlined;
      case LayerType.video:
        return Icons.videocam_outlined;
      case LayerType.text:
        return Icons.text_fields;
      case LayerType.drawing:
        return Icons.brush;
      case LayerType.group:
        return Icons.folder_outlined;
    }
  }
}

/// 绘制笔画
class DrawingStroke {
  Color color;
  double strokeWidth;
  final List<Offset> points;

  DrawingStroke({
    required this.color,
    required this.strokeWidth,
    required this.points,
  });

  /// 序列化
  Map<String, dynamic> toJson() {
    return {
      'points': points.map((p) => {'dx': p.dx, 'dy': p.dy}).toList(),
      'color': color.value,
      'strokeWidth': strokeWidth,
    };
  }

  /// 反序列化
  factory DrawingStroke.fromJson(Map<String, dynamic> json) {
    final points = (json['points'] as List<dynamic>)
        .map((p) => Offset(
              (p['dx'] as num).toDouble(),
              (p['dy'] as num).toDouble(),
            ))
        .toList();
    return DrawingStroke(
      points: points,
      color: Color(json['color'] as int),
      strokeWidth: (json['strokeWidth'] as num).toDouble(),
    );
  }
}

