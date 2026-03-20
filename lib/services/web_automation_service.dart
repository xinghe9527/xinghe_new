import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:xinghe_new/core/logger/log_manager.dart';

/// 网页自动化服务 - 负责调用 Python Playwright 脚本
/// 
/// 功能：
/// - 调用 Python 脚本执行网页自动化任务
/// - 管理进程生命周期
/// - 解析 JSON 返回结果
/// - 监控执行状态
class WebAutomationService {
  final LogManager _logger = LogManager();
  
  /// Python 可执行文件路径（默认使用系统 Python）
  String pythonExecutable = 'python';
  
  /// Python 脚本根目录
  String get scriptRootPath => 'python_backend${Platform.pathSeparator}web_automation';
  
  /// 测试：调用 hello_flutter.py
  /// 
  /// [message] 要传递给 Python 的参数
  /// 返回 Python 脚本的 JSON 响应
  Future<Map<String, dynamic>> testHelloFlutter(String message) async {
    try {
      _logger.info('开始测试 Python 通信', module: '网页自动化', extra: {
        'message': message,
      });
      
      // 构建脚本路径
      final scriptPath = '$scriptRootPath${Platform.pathSeparator}hello_flutter.py';
      
      // 检查脚本是否存在
      final scriptFile = File(scriptPath);
      if (!await scriptFile.exists()) {
        throw Exception('Python 脚本不存在: $scriptPath');
      }
      
      // 调用 Python 脚本
      final result = await _runPythonScript(
        scriptPath: scriptPath,
        arguments: [message],
      );
      
      _logger.success('Python 通信测试成功', module: '网页自动化', extra: {
        'result': result,
      });
      
      return result;
      
    } catch (e, stackTrace) {
      _logger.error('Python 通信测试失败: $e', module: '网页自动化', extra: {
        'stackTrace': stackTrace.toString(),
      });
      rethrow;
    }
  }
  
  /// 核心方法：运行 Python 脚本
  /// 
  /// [scriptPath] Python 脚本路径
  /// [arguments] 命令行参数列表
  /// [timeout] 超时时间（默认 60 秒）
  Future<Map<String, dynamic>> _runPythonScript({
    required String scriptPath,
    List<String> arguments = const [],
    Duration timeout = const Duration(seconds: 60),
  }) async {
    try {
      // 构建完整命令
      final fullArguments = [scriptPath, ...arguments];
      
      _logger.info('执行 Python 脚本', module: '网页自动化', extra: {
        'python': pythonExecutable,
        'script': scriptPath,
        'arguments': arguments,
      });
      
      // 启动进程
      final process = await Process.start(
        pythonExecutable,
        fullArguments,
        runInShell: true, // Windows 兼容性
      );
      
      // 收集输出
      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();
      
      // 监听标准输出
      process.stdout
          .transform(utf8.decoder)
          .listen((data) {
        stdoutBuffer.write(data);
        if (kDebugMode) {
          print('[Python stdout] $data');
        }
      });
      
      // 监听错误输出
      process.stderr
          .transform(utf8.decoder)
          .listen((data) {
        stderrBuffer.write(data);
        if (kDebugMode) {
          print('[Python stderr] $data');
        }
      });
      
      // 等待进程结束（带超时）
      final exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          process.kill();
          throw TimeoutException('Python 脚本执行超时');
        },
      );
      
      // 获取完整输出
      final stdout = stdoutBuffer.toString().trim();
      final stderr = stderrBuffer.toString().trim();
      
      _logger.info('Python 脚本执行完成', module: '网页自动化', extra: {
        'exitCode': exitCode,
        'stdout': stdout,
        'stderr': stderr,
      });
      
      // 检查退出码
      if (exitCode != 0) {
        throw Exception('Python 脚本执行失败 (退出码: $exitCode)\nStderr: $stderr');
      }
      
      // 解析 JSON 输出
      if (stdout.isEmpty) {
        throw Exception('Python 脚本没有返回任何输出');
      }
      
      try {
        final jsonResult = jsonDecode(stdout) as Map<String, dynamic>;
        return jsonResult;
      } catch (e) {
        throw Exception('无法解析 Python 返回的 JSON:\n$stdout\n错误: $e');
      }
      
    } catch (e) {
      _logger.error('运行 Python 脚本失败: $e', module: '网页自动化');
      rethrow;
    }
  }
  
  /// 设置自定义 Python 路径（如果用户使用虚拟环境）
  void setPythonPath(String path) {
    pythonExecutable = path;
    _logger.info('设置 Python 路径', module: '网页自动化', extra: {
      'path': path,
    });
  }
}
