import 'package:flutter/services.dart';
import 'dart:io';

/// 原生拖放服务（使用 Platform Channel）
class NativeDragService {
  static const MethodChannel _channel = MethodChannel('native_drag');
  
  /// 开始拖动文件
  /// 
  /// [filePath] 要拖动的文件路径
  /// 返回 true 表示拖动成功开始
  static Future<bool> startDrag(String filePath) async {
    try {
      // 检查文件是否存在
      final file = File(filePath);
      if (!await file.exists()) {
        print('[原生拖动] ❌ 文件不存在: $filePath');
        return false;
      }
      
      // 获取绝对路径
      final absolutePath = file.absolute.path;
      print('[原生拖动] 🎯 开始拖动: $absolutePath');
      
      // 调用原生方法
      final result = await _channel.invokeMethod('startDrag', {
        'filePath': absolutePath,
      });
      
      print('[原生拖动] ${result ? "✅ 成功" : "❌ 失败"}');
      return result as bool;
    } catch (e) {
      print('[原生拖动] ❌ 异常: $e');
      return false;
    }
  }
  
  /// 检查原生拖放是否可用
  static Future<bool> isAvailable() async {
    try {
      final result = await _channel.invokeMethod('isAvailable');
      return result as bool;
    } catch (e) {
      return false;
    }
  }
}
