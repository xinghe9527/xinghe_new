import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// 水印去除服务 - 调用本地 Python 后端（LaMa ONNX）
class WatermarkRemoverService {
  static const String _baseUrl = 'http://127.0.0.1:8000';
  
  /// 检查后端服务是否运行
  static Future<bool> checkService() async {
    try {
      final response = await http.get(Uri.parse(_baseUrl)).timeout(
        const Duration(seconds: 2),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ 后端服务未运行: $e');
      return false;
    }
  }
  
  /// 使用 LaMa 模型去除水印
  /// [imagePath] 原始图片路径
  /// [maskPoints] 水印区域的点集合（手动涂抹）
  /// [maskRects] 水印区域的矩形集合（矩形框选）
  static Future<Uint8List?> removeWatermark({
    required String imagePath,
    List<Offset>? maskPoints,
    List<Rect>? maskRects,
    double brushSize = 20.0,
  }) async {
    try {
      debugPrint('🚀 开始调用 LaMa 后端服务');
      
      // 1. 检查服务是否运行
      final isRunning = await checkService();
      if (!isRunning) {
        throw Exception('Python 后端服务未运行！\n\n请先启动服务:\ncd python_backend\npython main.py');
      }
      
      // 2. 读取原始图片
      final imageBytes = await File(imagePath).readAsBytes();
      img.Image? image = img.decodeImage(imageBytes);
      
      if (image == null) {
        throw Exception('无法解码图片');
      }

      debugPrint('📐 图片尺寸: ${image.width}x${image.height}');

      // 3. 创建遮罩图片
      final mask = _createMask(
        image.width,
        image.height,
        maskPoints,
        maskRects,
        brushSize,
      );

      debugPrint('🎭 遮罩创建完成');

      // 4. 编码图片和遮罩为 PNG
      final imageEncoded = img.encodePng(image);
      final maskEncoded = img.encodePng(mask);

      // 5. 发送到 Python 后端
      debugPrint('📤 发送请求到后端...');
      
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/remove_watermark'),
      );
      
      request.files.add(http.MultipartFile.fromBytes(
        'image',
        imageEncoded,
        filename: 'image.png',
      ));
      
      request.files.add(http.MultipartFile.fromBytes(
        'mask',
        maskEncoded,
        filename: 'mask.png',
      ));
      
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
      );
      
      if (streamedResponse.statusCode == 200) {
        final responseBytes = await streamedResponse.stream.toBytes();
        debugPrint('✅ 后端处理完成，大小: ${responseBytes.length} bytes');
        return responseBytes;
      } else {
        final responseBody = await streamedResponse.stream.bytesToString();
        throw Exception('后端返回错误: ${streamedResponse.statusCode}\n$responseBody');
      }
      
    } catch (e, stackTrace) {
      debugPrint('❌ LaMa 去水印失败: $e');
      debugPrint('堆栈: $stackTrace');
      rethrow;
    }
  }

  /// 智能检测水印区域
  static Future<List<Rect>> detectWatermark(String imagePath) async {
    try {
      debugPrint('开始智能检测水印: $imagePath');
      final bytes = await File(imagePath).readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      
      if (image == null) {
        debugPrint('无法解码图片');
        return [];
      }

      debugPrint('图片尺寸: ${image.width}x${image.height}');
      
      // 转换为灰度图
      final gray = img.grayscale(image);
      
      // 边缘检测
      final edges = img.sobel(gray);
      
      // 查找高对比度区域（可能是水印）
      final watermarkRegions = <Rect>[];
      final threshold = 100;
      
      debugPrint('开始扫描边缘...');
      for (int y = 0; y < edges.height - 50; y += 10) {
        for (int x = 0; x < edges.width - 50; x += 10) {
          int edgeCount = 0;
          
          for (int dy = 0; dy < 50; dy++) {
            for (int dx = 0; dx < 50; dx++) {
              final pixel = edges.getPixel(x + dx, y + dy);
              if (pixel.r > threshold) {
                edgeCount++;
              }
            }
          }
          
          if (edgeCount > 200) {
            watermarkRegions.add(Rect.fromLTWH(
              x.toDouble(),
              y.toDouble(),
              50,
              50,
            ));
          }
        }
      }
      
      debugPrint('检测到 ${watermarkRegions.length} 个可能的水印区域');
      
      final merged = _mergeRects(watermarkRegions);
      debugPrint('合并后剩余 ${merged.length} 个区域');
      
      return merged;
    } catch (e, stackTrace) {
      debugPrint('检测水印失败: $e');
      debugPrint('堆栈: $stackTrace');
      return [];
    }
  }

  /// 创建遮罩图像
  static img.Image _createMask(
    int width,
    int height,
    List<Offset>? points,
    List<Rect>? rects,
    double brushSize,
  ) {
    final mask = img.Image(width: width, height: height);
    img.fill(mask, color: img.ColorRgb8(0, 0, 0)); // 黑色背景

    // 绘制涂抹点
    if (points != null) {
      for (final point in points) {
        _drawCircle(
          mask,
          point.dx.toInt(),
          point.dy.toInt(),
          (brushSize / 2).toInt(),
          img.ColorRgb8(255, 255, 255), // 白色表示需要修复的区域
        );
      }
    }

    // 绘制矩形
    if (rects != null) {
      for (final rect in rects) {
        img.fillRect(
          mask,
          x1: rect.left.toInt(),
          y1: rect.top.toInt(),
          x2: rect.right.toInt(),
          y2: rect.bottom.toInt(),
          color: img.ColorRgb8(255, 255, 255),
        );
      }
    }

    return mask;
  }

  /// 在图像上绘制圆形
  static void _drawCircle(
    img.Image image,
    int cx,
    int cy,
    int radius,
    img.Color color,
  ) {
    for (int y = -radius; y <= radius; y++) {
      for (int x = -radius; x <= radius; x++) {
        if (x * x + y * y <= radius * radius) {
          final px = cx + x;
          final py = cy + y;
          if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
            image.setPixel(px, py, color);
          }
        }
      }
    }
  }

  /// 合并相邻的矩形区域
  static List<Rect> _mergeRects(List<Rect> rects) {
    if (rects.isEmpty) return [];

    final merged = <Rect>[];
    final used = List.filled(rects.length, false);

    for (int i = 0; i < rects.length; i++) {
      if (used[i]) continue;

      var current = rects[i];
      used[i] = true;

      bool changed = true;
      while (changed) {
        changed = false;
        for (int j = 0; j < rects.length; j++) {
          if (used[j]) continue;

          if (current.overlaps(rects[j]) ||
              _isAdjacent(current, rects[j])) {
            current = current.expandToInclude(rects[j]);
            used[j] = true;
            changed = true;
          }
        }
      }

      merged.add(current);
    }

    return merged;
  }

  /// 检查两个矩形是否相邻
  static bool _isAdjacent(Rect a, Rect b) {
    const threshold = 20.0;
    return (a.left - b.right).abs() < threshold ||
        (a.right - b.left).abs() < threshold ||
        (a.top - b.bottom).abs() < threshold ||
        (a.bottom - b.top).abs() < threshold;
  }
}
