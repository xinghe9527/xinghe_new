import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:xinghe_new/services/direct_oss_upload_service.dart';

class AvatarUploadService {
  final DirectOssUploadService _ossService = DirectOssUploadService();

  /// 上传头像到 OSS
  /// 返回上传后的 URL
  Future<String> uploadAvatar({
    required String userId,
    required String localPath,
  }) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        throw Exception('文件不存在');
      }

      // 生成唯一的文件名
      final extension = path.extension(localPath);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'avatars/$userId/$timestamp$extension';

      // 上传到 OSS
      final url = await _ossService.uploadImage(
        file,
        targetPath: fileName,
      );

      return url;
    } catch (e) {
      print('头像上传失败: $e');
      rethrow;
    }
  }

  /// 删除旧头像（可选）
  Future<void> deleteAvatar(String avatarUrl) async {
    try {
      // 从 URL 中提取 objectKey
      final uri = Uri.parse(avatarUrl);
      final objectKey = uri.path.substring(1); // 移除开头的 '/'
      
      // TODO: 实现 OSS 删除逻辑
      print('删除旧头像: $objectKey');
    } catch (e) {
      print('删除头像失败: $e');
    }
  }
}
