import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// FFmpeg 视频处理服务
/// 
/// 功能：
/// - 图片转视频（3秒静态视频）
/// - 视频合并
/// - 提取视频首帧
class FFmpegService {
  /// 获取 FFmpeg 路径
  /// 
  /// 优先级：
  /// 1. 打包在应用中的 FFmpeg（Windows: exe同目录/ffmpeg.exe）
  /// 2. 系统 PATH 中的 FFmpeg
  static Future<String> _getFFmpegPath() async {
    if (Platform.isWindows) {
      // 获取 exe 所在目录
      final exePath = Platform.resolvedExecutable;
      final exeDir = path.dirname(exePath);
      final bundledFFmpeg = path.join(exeDir, 'ffmpeg.exe');
      
      debugPrint('[FFmpeg] 检查打包的 FFmpeg: $bundledFFmpeg');
      
      if (await File(bundledFFmpeg).exists()) {
        debugPrint('[FFmpeg] ✅ 使用打包的 FFmpeg');
        return bundledFFmpeg;
      } else {
        debugPrint('[FFmpeg] ⚠️ 未找到打包的 FFmpeg，尝试系统 FFmpeg');
      }
    }
    
    // 回退到系统 FFmpeg
    return 'ffmpeg';
  }
  
  /// 将图片转换为 3 秒静态视频
  /// 
  /// [imageFile] 输入图片
  /// 返回生成的视频文件
  Future<File> convertImageToVideo(File imageFile) async {
    debugPrint('[FFmpeg] 开始转换图片为视频: ${imageFile.path}');
    
    // 1. 检查输入文件
    if (!await imageFile.exists()) {
      throw Exception('输入图片不存在: ${imageFile.path}');
    }
    
    // 2. 获取临时目录
    final tempDir = await getTemporaryDirectory();
    
    // 3. 生成输出路径
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = path.join(tempDir.path, 'video_$timestamp.mp4');
    
    // 4. 构建 FFmpeg 命令
    final ffmpegPath = await _getFFmpegPath();
    final args = [
      '-y',                    // 覆盖已有文件
      '-loop', '1',            // 循环输入图片
      '-i', imageFile.path,    // 输入文件
      '-f', 'lavfi',           // 使用 lavfi 滤镜
      '-i', 'anullsrc=channel_layout=stereo:sample_rate=44100', // 生成静音音频
      '-t', '3',               // 持续 3 秒
      '-vf', 'scale=720:-2',   // 缩放到 720p（保持宽高比）
      '-pix_fmt', 'yuv420p',   // 像素格式（兼容性好）
      '-c:v', 'libx264',       // 视频编码器
      '-c:a', 'aac',           // 音频编码器
      '-shortest',             // 以最短流为准
      outputPath,              // 输出文件
    ];
    
    debugPrint('[FFmpeg] 执行命令: $ffmpegPath ${args.join(" ")}');
    
    // 5. 在后台 Isolate 中执行（避免阻塞UI）
    final result = await compute(_runFFmpegProcess, _FFmpegParams(
      command: ffmpegPath,
      args: args,
    ));
    
    // 6. 检查结果
    if (result.exitCode == 0) {
      final outputFile = File(outputPath);
      if (await outputFile.exists()) {
        debugPrint('[FFmpeg] ✅ 转换成功: $outputPath');
        return outputFile;
      } else {
        throw Exception('FFmpeg 转换成功但输出文件不存在');
      }
    } else {
      throw Exception('FFmpeg 转换失败\nExit Code: ${result.exitCode}\nError: ${result.stderr}');
    }
  }
  
  /// 合并多个视频文件
  /// 
  /// [videoFiles] 视频文件列表（按顺序）
  /// 返回合并后的视频文件
  Future<File> concatVideos(List<File> videoFiles) async {
    if (videoFiles.isEmpty) {
      throw Exception('没有视频文件需要合并');
    }
    
    if (videoFiles.length == 1) {
      return videoFiles.first;
    }
    
    debugPrint('[FFmpeg] 开始合并 ${videoFiles.length} 个视频');
    
    final tempDir = await getTemporaryDirectory();
    
    // 创建文件列表
    final listFilePath = path.join(tempDir.path, 'concat_list_${DateTime.now().millisecondsSinceEpoch}.txt');
    final fileListContent = videoFiles.map((file) {
      final filePath = file.path.replaceAll('\\', '/');
      return "file '$filePath'";
    }).join('\n');
    
    await File(listFilePath).writeAsString(fileListContent);
    
    // 生成输出路径
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = path.join(tempDir.path, 'merged_$timestamp.mp4');
    
    // 构建命令
    final ffmpegPath = await _getFFmpegPath();
    final args = [
      '-y',
      '-f', 'concat',
      '-safe', '0',
      '-i', listFilePath,
      '-c', 'copy',  // 直接复制流（不重新编码，速度快）
      outputPath,
    ];
    
    debugPrint('[FFmpeg] 合并命令: $ffmpegPath ${args.join(" ")}');
    
    final result = await compute(_runFFmpegProcess, _FFmpegParams(
      command: ffmpegPath,
      args: args,
    ));
    
    // 清理文件列表
    await File(listFilePath).delete();
    
    if (result.exitCode == 0) {
      final outputFile = File(outputPath);
      if (await outputFile.exists()) {
        debugPrint('[FFmpeg] ✅ 合并成功: $outputPath');
        return outputFile;
      } else {
        throw Exception('FFmpeg 合并成功但输出文件不存在');
      }
    } else {
      throw Exception('FFmpeg 合并失败\nExit Code: ${result.exitCode}\nError: ${result.stderr}');
    }
  }
  
  /// 提取视频首帧（生成缩略图）
  /// 
  /// [videoPath] 视频文件路径
  /// [outputPath] 输出图片路径
  /// [timeOffset] 提取时间点（默认0.1秒）
  Future<bool> extractFrame({
    required String videoPath,
    required String outputPath,
    Duration timeOffset = const Duration(milliseconds: 100),
  }) async {
    debugPrint('[FFmpeg] 提取首帧: $videoPath');
    
    final ffmpegPath = await _getFFmpegPath();
    final seconds = timeOffset.inMilliseconds / 1000.0;
    
    final args = [
      '-y',
      '-ss', seconds.toStringAsFixed(3),  // 时间点
      '-i', videoPath,                     // 输入视频
      '-vframes', '1',                     // 只提取一帧
      '-q:v', '2',                         // 高质量 JPEG（1-31，2是高质量）
      outputPath,                          // 输出图片
    ];
    
    final result = await compute(_runFFmpegProcess, _FFmpegParams(
      command: ffmpegPath,
      args: args,
    ));
    
    final success = result.exitCode == 0 && await File(outputPath).exists();
    if (success) {
      debugPrint('[FFmpeg] ✅ 首帧提取成功: $outputPath');
    } else {
      debugPrint('[FFmpeg] ❌ 首帧提取失败');
    }
    
    return success;
  }
}

/// FFmpeg 进程参数
class _FFmpegParams {
  final String command;
  final List<String> args;
  
  _FFmpegParams({required this.command, required this.args});
}

/// FFmpeg 进程结果
class _FFmpegResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  
  _FFmpegResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}

/// 在后台 Isolate 中运行 FFmpeg（不阻塞 UI）
Future<_FFmpegResult> _runFFmpegProcess(_FFmpegParams params) async {
  try {
    final result = await Process.run(
      params.command,
      params.args,
      runInShell: true,
    );
    
    return _FFmpegResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  } catch (e) {
    return _FFmpegResult(
      exitCode: -1,
      stdout: '',
      stderr: e.toString(),
    );
  }
}
