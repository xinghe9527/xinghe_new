import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';

/// 更新包下载器
class UpdateDownloader {
  final Dio _dio = Dio();
  final ValueNotifier<double> progressNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<String> statusNotifier = ValueNotifier<String>('准备下载...');

  /// 下载更新包（EXE 安装程序）
  /// 
  /// 返回: 下载的文件路径，失败返回 null
  Future<String?> download(String url) async {
    try {
      // ✅ 打印完整的下载 URL（检查签名）
      debugPrint('📥 开始下载更新包');
      debugPrint('🔗 下载 URL（完整）: $url');
      debugPrint('🔑 URL 长度: ${url.length} 字符');
      debugPrint('✅ 包含签名: ${url.contains('Signature=')}');
      
      // 1. 获取临时目录
      final tempDir = await getTemporaryDirectory();
      final savePath = '${tempDir.path}\\xinghe_update.exe';  // ✅ 改为 .exe

      debugPrint('📂 保存路径: $savePath');

      statusNotifier.value = '正在下载...';

      // 2. 下载文件（添加防盗链 Referer）
      await _dio.download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = received / total;
            progressNotifier.value = progress;

            final receivedMB = (received / 1024 / 1024).toStringAsFixed(2);
            final totalMB = (total / 1024 / 1024).toStringAsFixed(2);
            statusNotifier.value = '正在下载... $receivedMB MB / $totalMB MB';

            debugPrint('📊 下载进度: ${(progress * 100).toStringAsFixed(1)}%');
          }
        },
        options: Options(
          receiveTimeout: const Duration(minutes: 10),
          sendTimeout: const Duration(minutes: 10),
          headers: {
            'Referer': 'xinghe.ros',        // ✅ 防盗链 Referer
            'x-xinghe-token': 'xinghe5201314',  // ✅ 安全暗号
          },
        ),
      );

      statusNotifier.value = '下载完成';
      debugPrint('✅ 下载完成: $savePath');

      return savePath;
    } catch (e) {
      statusNotifier.value = '下载失败: $e';
      debugPrint('❌ 下载失败: $e');
      return null;
    }
  }

  /// 解压更新包
  /// 
  /// 返回: 解压后的目录路径，失败返回 null
  Future<String?> extractZip(String zipPath) async {
    try {
      debugPrint('📦 开始解压更新包');
      statusNotifier.value = '正在解压...';

      // 1. 读取 zip 文件
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // 2. 创建解压目录
      final tempDir = await getTemporaryDirectory();
      final extractPath = '${tempDir.path}\\xinghe_update_files';
      final extractDir = Directory(extractPath);

      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
      await extractDir.create(recursive: true);

      // 3. 解压所有文件
      for (final file in archive) {
        final filename = '$extractPath\\${file.name}';

        if (file.isFile) {
          final outFile = File(filename);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
          debugPrint('  📄 解压: ${file.name}');
        } else {
          await Directory(filename).create(recursive: true);
        }
      }

      statusNotifier.value = '解压完成';
      debugPrint('✅ 解压完成: $extractPath');

      return extractPath;
    } catch (e) {
      statusNotifier.value = '解压失败: $e';
      debugPrint('❌ 解压失败: $e');
      return null;
    }
  }

  /// 释放资源
  void dispose() {
    progressNotifier.dispose();
    statusNotifier.dispose();
  }
}
