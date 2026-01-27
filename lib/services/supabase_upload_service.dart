import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as path;

/// Supabase 文件上传服务
/// 
/// 功能：
/// - 上传视频到 Supabase Storage
/// - 上传图片到 Supabase Storage
/// - 获取公共访问 URL
class SupabaseUploadService {
  final supabase = Supabase.instance.client;
  
  /// 上传视频文件到 Supabase Storage（带重试）
  /// 
  /// [videoFile] 本地视频文件
  /// 返回公共访问 URL
  Future<String> uploadVideo(File videoFile, {int maxRetries = 3}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        debugPrint('[Supabase] 开始上传视频 (尝试 $attempt/$maxRetries): ${videoFile.path}');
        
        // 1. 检查文件是否存在
        if (!await videoFile.exists()) {
          throw Exception('视频文件不存在: ${videoFile.path}');
        }
        
        // 2. 生成唯一文件路径
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final randomStr = DateTime.now().microsecondsSinceEpoch.toString().substring(10);
        final filePath = 'videos/video_${timestamp}_$randomStr.mp4';
        
        // 3. 读取文件字节
        final fileBytes = await videoFile.readAsBytes();
        final fileSizeMB = (fileBytes.length / 1024 / 1024).toStringAsFixed(2);
        debugPrint('[Supabase] 文件大小: $fileSizeMB MB');
        
        // 4. 上传到 Supabase（设置超时）
        await supabase.storage
            .from('xinghe_uploads')
            .uploadBinary(
              filePath,
              fileBytes,
              fileOptions: const FileOptions(
                contentType: 'video/mp4',
                upsert: false,
              ),
            )
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () => throw TimeoutException('上传超时'),
            );
        
        // 5. 获取公共 URL
        final publicUrl = supabase.storage
            .from('xinghe_uploads')
            .getPublicUrl(filePath);
        
        debugPrint('[Supabase] ✅ 上传成功: $publicUrl');
        return publicUrl;
        
      } catch (e, stackTrace) {
        debugPrint('[Supabase] ❌ 上传失败 (尝试 $attempt/$maxRetries): $e');
        
        if (attempt == maxRetries) {
          // 最后一次尝试也失败了
          debugPrint('[Supabase] Stack Trace: $stackTrace');
          rethrow;
        }
        
        // 等待后重试
        await Future.delayed(Duration(seconds: attempt * 2));
        debugPrint('[Supabase] 准备重试...');
      }
    }
    
    throw Exception('上传失败：已重试 $maxRetries 次');
  }
  
  /// 上传图片文件到 Supabase Storage
  /// 
  /// [imageFile] 本地图片文件
  /// 返回公共访问 URL
  Future<String> uploadImage(File imageFile) async {
    try {
      debugPrint('[Supabase] 开始上传图片: ${imageFile.path}');
      
      if (!await imageFile.exists()) {
        throw Exception('图片文件不存在: ${imageFile.path}');
      }
      
      // 生成唯一文件路径
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = path.extension(imageFile.path).toLowerCase();
      final filePath = 'images/image_$timestamp$extension';
      
      // 读取文件
      final fileBytes = await imageFile.readAsBytes();
      
      // 确定 content type
      String contentType = 'image/jpeg';
      if (extension == '.png') contentType = 'image/png';
      if (extension == '.gif') contentType = 'image/gif';
      if (extension == '.webp') contentType = 'image/webp';
      
      // 上传
      await supabase.storage
          .from('xinghe_uploads')
          .uploadBinary(
            filePath,
            fileBytes,
            fileOptions: FileOptions(
              contentType: contentType,
              upsert: false,
            ),
          );
      
      // 获取公共 URL
      final publicUrl = supabase.storage
          .from('xinghe_uploads')
          .getPublicUrl(filePath);
      
      debugPrint('[Supabase] ✅ 图片上传成功: $publicUrl');
      return publicUrl;
      
    } catch (e, stackTrace) {
      debugPrint('[Supabase] ❌ 图片上传失败: $e');
      debugPrint('[Supabase] Stack Trace: $stackTrace');
      rethrow;
    }
  }
  
  /// 列出已上传的文件
  /// 
  /// [folder] 文件夹路径（如 'videos' 或 'images'）
  Future<List<FileObject>> listFiles({String folder = ''}) async {
    try {
      final files = await supabase.storage
          .from('xinghe_uploads')
          .list(path: folder);
      
      debugPrint('[Supabase] 文件夹 "$folder" 中有 ${files.length} 个文件');
      return files;
    } catch (e) {
      debugPrint('[Supabase] ❌ 列出文件失败: $e');
      return [];
    }
  }
  
  /// 删除文件
  /// 
  /// [filePath] 文件路径（从 URL 中提取）
  Future<bool> deleteFile(String filePath) async {
    try {
      await supabase.storage
          .from('xinghe_uploads')
          .remove([filePath]);
      
      debugPrint('[Supabase] ✅ 文件删除成功: $filePath');
      return true;
    } catch (e) {
      debugPrint('[Supabase] ❌ 文件删除失败: $e');
      return false;
    }
  }
}
