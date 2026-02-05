import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// 阿里云 OSS 文件上传服务
/// 
/// 功能：
/// - 通过阿里云函数计算上传视频
/// - 通过阿里云函数计算上传图片
/// - 获取公共访问 URL
class AliyunOssUploadService {
  // ✅ 阿里云函数计算公网地址
  static const String _uploadUrl = 'https://xinghe-angchuan-agxvbiyacd.cn-chengdu.fcapp.run';
  
  // ✅ 安全暗号 (Token)
  static const String _token = 'xinghe5201314';
  
  /// 上传视频文件到阿里云 OSS（带重试）
  /// 
  /// [videoFile] 本地视频文件
  /// 返回公共访问 URL
  Future<String> uploadVideo(File videoFile, {int maxRetries = 3}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        debugPrint('[阿里云] 开始上传视频 (尝试 $attempt/$maxRetries): ${videoFile.path}');
        
        // 1. 检查文件是否存在
        if (!await videoFile.exists()) {
          throw Exception('视频文件不存在: ${videoFile.path}');
        }
        
        // 2. 读取文件
        final fileBytes = await videoFile.readAsBytes();
        final fileSizeMB = (fileBytes.length / 1024 / 1024).toStringAsFixed(2);
        debugPrint('[阿里云] 文件大小: $fileSizeMB MB');
        
        // 3. 准备 multipart 请求
        final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl));
        
        // ✅ 添加 Token 校验头
        request.headers['x-xinghe-token'] = _token;
        
        // 4. 添加文件（字段名：file）
        final fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
        request.files.add(http.MultipartFile.fromBytes(
          'file',  // ✅ 后端要求的字段名
          fileBytes,
          filename: fileName,
        ));
        
        // 5. 发送请求（设置超时）
        debugPrint('[阿里云] 正在上传到函数计算...');
        debugPrint('[阿里云] URL: $_uploadUrl');
        debugPrint('[阿里云] 文件名: $fileName');
        debugPrint('[阿里云] Headers: ${request.headers}');
        
        final streamedResponse = await request.send().timeout(
          const Duration(minutes: 2),  // 视频较大，设置2分钟超时
          onTimeout: () => throw TimeoutException('上传超时'),
        );
        
        // 6. 读取响应
        final response = await http.Response.fromStream(streamedResponse);
        
        debugPrint('[阿里云] 响应状态码: ${response.statusCode}');
        debugPrint('[阿里云] 响应内容: ${response.body}');
        
        if (response.statusCode == 200) {
          // 6. 解析返回的 URL
          final responseData = jsonDecode(response.body) as Map<String, dynamic>;
          final publicUrl = responseData['url'] as String?;
          
          if (publicUrl == null || publicUrl.isEmpty) {
            throw Exception('服务器返回成功但 URL 为空');
          }
          
          debugPrint('[阿里云] ✅ 上传成功: $publicUrl');
          return publicUrl;
        } else {
          throw Exception('服务器返回错误 (${response.statusCode}): ${response.body}');
        }
        
      } catch (e, stackTrace) {
        debugPrint('[阿里云] ❌ 上传失败 (尝试 $attempt/$maxRetries): $e');
        
        if (attempt == maxRetries) {
          // 最后一次尝试也失败了
          debugPrint('[阿里云] Stack Trace: $stackTrace');
          rethrow;
        }
        
        // 等待后重试
        await Future.delayed(Duration(seconds: attempt * 2));
        debugPrint('[阿里云] 准备重试...');
      }
    }
    
    throw Exception('上传失败：已重试 $maxRetries 次');
  }
  
  /// 上传图片文件到阿里云 OSS
  /// 
  /// [imageFile] 本地图片文件
  /// 返回公共访问 URL
  Future<String> uploadImage(File imageFile) async {
    try {
      debugPrint('[阿里云] 开始上传图片: ${imageFile.path}');
      
      if (!await imageFile.exists()) {
        throw Exception('图片文件不存在: ${imageFile.path}');
      }
      
      // 读取文件
      final fileBytes = await imageFile.readAsBytes();
      final fileSizeMB = (fileBytes.length / 1024 / 1024).toStringAsFixed(2);
      debugPrint('[阿里云] 文件大小: $fileSizeMB MB');
      
      // 获取文件扩展名
      final extension = imageFile.path.split('.').last.toLowerCase();
      
      // 准备 multipart 请求
      final request = http.MultipartRequest('POST', Uri.parse(_uploadUrl));
      
      // ✅ 添加 Token 校验头
      request.headers['x-xinghe-token'] = _token;
      
      // 添加文件
      final fileName = 'image_${DateTime.now().millisecondsSinceEpoch}.$extension';
      request.files.add(http.MultipartFile.fromBytes(
        'file',  // ✅ 后端要求的字段名
        fileBytes,
        filename: fileName,
      ));
      
      debugPrint('[阿里云] Headers: ${request.headers}');
      
      // 发送请求
      debugPrint('[阿里云] 正在上传到函数计算...');
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException('上传超时'),
      );
      
      // 读取响应
      final response = await http.Response.fromStream(streamedResponse);
      
      debugPrint('[阿里云] 响应状态码: ${response.statusCode}');
      debugPrint('[阿里云] 响应内容: ${response.body}');
      
      if (response.statusCode == 200) {
        // 解析返回的 URL
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;
        final publicUrl = responseData['url'] as String?;
        
        if (publicUrl == null || publicUrl.isEmpty) {
          throw Exception('服务器返回成功但 URL 为空');
        }
        
        debugPrint('[阿里云] ✅ 图片上传成功: $publicUrl');
        return publicUrl;
      } else {
        throw Exception('服务器返回错误 (${response.statusCode}): ${response.body}');
      }
      
    } catch (e, stackTrace) {
      debugPrint('[阿里云] ❌ 图片上传失败: $e');
      debugPrint('[阿里云] Stack Trace: $stackTrace');
      rethrow;
    }
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  
  @override
  String toString() => message;
}
