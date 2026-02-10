import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:xinghe_new/services/oss_config.dart';

/// 直连 OSS 上传服务
/// 
/// 功能：
/// - 直接上传文件到阿里云 OSS（不经过函数计算）
/// - 自动生成签名
/// - 设置公共读权限
class DirectOssUploadService {
  /// 上传视频文件到 OSS
  /// 
  /// [videoFile] 本地视频文件
  /// [targetPath] OSS 目标路径（可选，默认自动生成）
  /// 返回公共访问 URL
  Future<String> uploadVideo(File videoFile, {String? targetPath}) async {
    try {
      debugPrint('[直连 OSS] 开始上传视频: ${videoFile.path}');
      
      // 1. 检查配置
      if (!await OssConfig.isConfigured()) {
        throw Exception('OSS 未配置，请在设置中配置 AccessKey');
      }
      
      final accessKeyId = await OssConfig.getAccessKeyId();
      final accessKeySecret = await OssConfig.getAccessKeySecret();
      final bucket = await OssConfig.getBucket();
      final endpoint = await OssConfig.getEndpoint();
      
      debugPrint('[直连 OSS] Bucket: $bucket');
      debugPrint('[直连 OSS] Endpoint: $endpoint');
      debugPrint('[直连 OSS] AccessKeyId: ${accessKeyId?.substring(0, 10)}...');
      
      // 2. 检查文件是否存在
      if (!await videoFile.exists()) {
        throw Exception('视频文件不存在: ${videoFile.path}');
      }
      
      // 3. 生成目标路径（✅ 固定为 user_videos/ 目录）
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final objectKey = targetPath ?? 'user_videos/$timestamp.mp4';
      
      // ✅ 安全检查：确保路径在 user_videos/ 目录下
      if (!objectKey.startsWith('user_videos/')) {
        throw Exception('安全限制：只允许上传到 user_videos/ 目录');
      }
      
      debugPrint('[直连 OSS] 目标路径: $objectKey');
      
      // 4. 读取文件内容
      final fileBytes = await videoFile.readAsBytes();
      final fileSizeMB = (fileBytes.length / 1024 / 1024).toStringAsFixed(2);
      debugPrint('[直连 OSS] 文件大小: $fileSizeMB MB');
      
      // 5. 生成签名和请求头
      final date = _getGMTDate();
      final contentType = 'video/mp4';
      final contentMd5 = base64Encode(md5.convert(fileBytes).bytes);
      
      // 6. 构建签名字符串
      final canonicalizedOssHeaders = 'x-oss-object-acl:public-read\n';
      final canonicalizedResource = '/$bucket/$objectKey';
      
      final stringToSign = 'PUT\n'
          '$contentMd5\n'
          '$contentType\n'
          '$date\n'
          '$canonicalizedOssHeaders'
          '$canonicalizedResource';
      
      // 7. 计算签名
      final hmac = Hmac(sha1, utf8.encode(accessKeySecret!));
      final signature = base64Encode(hmac.convert(utf8.encode(stringToSign)).bytes);
      
      // 8. 构建请求 URL
      final url = 'https://$bucket.$endpoint/$objectKey';
      debugPrint('[直连 OSS] 上传 URL: $url');
      
      // 9. 发送 PUT 请求
      debugPrint('[直连 OSS] 开始上传...');
      final response = await http.put(
        Uri.parse(url),
        headers: {
          'Host': '$bucket.$endpoint',
          'Date': date,
          'Content-Type': contentType,
          'Content-MD5': contentMd5,
          'Authorization': 'OSS $accessKeyId:$signature',
          'x-oss-object-acl': 'public-read',  // ✅ 设置公共读权限
        },
        body: fileBytes,
      ).timeout(
        const Duration(minutes: 5),  // 视频较大，设置5分钟超时
        onTimeout: () => throw TimeoutException('上传超时'),
      );
      
      debugPrint('[直连 OSS] 响应状态码: ${response.statusCode}');
      
      // 10. 检查响应
      if (response.statusCode == 200) {
        // 构建公共访问 URL
        final publicUrl = 'https://$bucket.$endpoint/$objectKey';
        debugPrint('[直连 OSS] ✅ 上传成功');
        debugPrint('[直连 OSS] 公共 URL: $publicUrl');
        debugPrint('[直连 OSS] 请在浏览器中验证: $publicUrl');
        return publicUrl;
      } else {
        debugPrint('[直连 OSS] ❌ 上传失败: ${response.body}');
        throw Exception('OSS 返回错误 (${response.statusCode}): ${response.body}');
      }
      
    } catch (e, stackTrace) {
      debugPrint('[直连 OSS] ❌ 上传失败: $e');
      debugPrint('[直连 OSS] Stack Trace: $stackTrace');
      rethrow;
    }
  }
  
  /// 上传图片文件到 OSS
  /// 
  /// [imageFile] 本地图片文件
  /// [targetPath] OSS 目标路径（例如：user_images/123456.png）
  /// 返回公共访问 URL
  Future<String> uploadImage(File imageFile, {String? targetPath}) async {
    try {
      debugPrint('[直连 OSS] 开始上传图片: ${imageFile.path}');
      
      // 1. 检查配置
      if (!await OssConfig.isConfigured()) {
        throw Exception('OSS 未配置，请在设置中配置 AccessKey');
      }
      
      final accessKeyId = await OssConfig.getAccessKeyId();
      final accessKeySecret = await OssConfig.getAccessKeySecret();
      final bucket = await OssConfig.getBucket();
      final endpoint = await OssConfig.getEndpoint();
      
      // 2. 检查文件是否存在
      if (!await imageFile.exists()) {
        throw Exception('图片文件不存在: ${imageFile.path}');
      }
      
      // 3. 生成目标路径
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = path.extension(imageFile.path);
      final objectKey = targetPath ?? 'user_images/$timestamp$extension';
      
      debugPrint('[直连 OSS] 目标路径: $objectKey');
      
      // 4. 读取文件内容
      final fileBytes = await imageFile.readAsBytes();
      final fileSizeMB = (fileBytes.length / 1024 / 1024).toStringAsFixed(2);
      debugPrint('[直连 OSS] 文件大小: $fileSizeMB MB');
      
      // 5. 生成签名和请求头
      final date = _getGMTDate();
      final contentType = _getContentType(extension);
      final contentMd5 = base64Encode(md5.convert(fileBytes).bytes);
      
      // 6. 构建签名字符串
      final canonicalizedOssHeaders = 'x-oss-object-acl:public-read\n';
      final canonicalizedResource = '/$bucket/$objectKey';
      
      final stringToSign = 'PUT\n'
          '$contentMd5\n'
          '$contentType\n'
          '$date\n'
          '$canonicalizedOssHeaders'
          '$canonicalizedResource';
      
      // 7. 计算签名
      final hmac = Hmac(sha1, utf8.encode(accessKeySecret!));
      final signature = base64Encode(hmac.convert(utf8.encode(stringToSign)).bytes);
      
      // 8. 构建请求 URL
      final url = 'https://$bucket.$endpoint/$objectKey';
      debugPrint('[直连 OSS] 上传 URL: $url');
      
      // 9. 发送 PUT 请求
      final response = await http.put(
        Uri.parse(url),
        headers: {
          'Host': '$bucket.$endpoint',
          'Date': date,
          'Content-Type': contentType,
          'Content-MD5': contentMd5,
          'Authorization': 'OSS $accessKeyId:$signature',
          'x-oss-object-acl': 'public-read',  // ✅ 设置公共读权限
        },
        body: fileBytes,
      ).timeout(
        const Duration(minutes: 2),
        onTimeout: () => throw TimeoutException('上传超时'),
      );
      
      debugPrint('[直连 OSS] 响应状态码: ${response.statusCode}');
      
      // 10. 检查响应
      if (response.statusCode == 200) {
        // 构建公共访问 URL
        final publicUrl = 'https://$bucket.$endpoint/$objectKey';
        debugPrint('[直连 OSS] ✅ 上传成功: $publicUrl');
        return publicUrl;
      } else {
        debugPrint('[直连 OSS] ❌ 上传失败: ${response.body}');
        throw Exception('OSS 返回错误 (${response.statusCode}): ${response.body}');
      }
      
    } catch (e, stackTrace) {
      debugPrint('[直连 OSS] ❌ 上传失败: $e');
      debugPrint('[直连 OSS] Stack Trace: $stackTrace');
      rethrow;
    }
  }
  
  /// 获取 GMT 格式的日期字符串
  String _getGMTDate() {
    final now = DateTime.now().toUtc();
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    
    final weekday = weekdays[now.weekday - 1];
    final day = now.day.toString().padLeft(2, '0');
    final month = months[now.month - 1];
    final year = now.year;
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    
    return '$weekday, $day $month $year $hour:$minute:$second GMT';
  }
  
  /// 根据文件扩展名获取 Content-Type
  String _getContentType(String extension) {
    switch (extension.toLowerCase()) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.mp4':
        return 'video/mp4';
      default:
        return 'application/octet-stream';
    }
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  
  @override
  String toString() => message;
}
