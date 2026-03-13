import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

/// 水印去除引擎管理器
/// 负责启动、监控和停止 Python 后端引擎进程
class WatermarkEngineManager {
  static final WatermarkEngineManager _instance = WatermarkEngineManager._internal();
  factory WatermarkEngineManager() => _instance;
  WatermarkEngineManager._internal();

  Process? _engineProcess;
  bool _isRunning = false;
  bool _isStopping = false;
  Timer? _healthCheckTimer;
  
  static const String _engineHost = '127.0.0.1';
  static const int _enginePort = 8000;
  static const String _healthCheckUrl = 'http://$_engineHost:$_enginePort/';
  
  /// 引擎是否正在运行
  bool get isRunning => _isRunning;
  
  /// 启动引擎（静默启动，隐藏命令行窗口）
  Future<bool> startEngine() async {
    if (_isRunning) {
      debugPrint('✅ 引擎已在运行');
      return true;
    }
    
    try {
      debugPrint('🚀 正在启动水印去除引擎...');
      
      // 获取引擎可执行文件路径
      final enginePath = _getEnginePath();
      
      // 🔧 开发模式降级处理：如果找不到 EXE，尝试连接已运行的服务
      if (enginePath == null || !await File(enginePath).exists()) {
        debugPrint('⚠️ 找不到引擎文件: $enginePath');
        debugPrint('🔍 尝试连接已运行的后端服务...');
        
        // 尝试连接已存在的服务（开发模式：手动运行 python main.py）
        final isServiceRunning = await checkHealth();
        if (isServiceRunning) {
          debugPrint('✅ 检测到后端服务已运行（开发模式）');
          _isRunning = true;
          _startHealthCheck();
          return true;
        } else {
          debugPrint('❌ 后端服务未运行');
          debugPrint('');
          debugPrint('💡 开发模式解决方案：');
          debugPrint('   1. 打开新终端，运行: cd python_backend');
          debugPrint('   2. 运行: python main.py');
          debugPrint('   3. 等待服务启动后，重新尝试使用功能');
          debugPrint('');
          debugPrint('💡 生产模式解决方案：');
          debugPrint('   1. 运行: cd python_backend');
          debugPrint('   2. 运行: build_engine.bat');
          debugPrint('   3. 引擎会自动复制到 Flutter 构建目录');
          debugPrint('');
          return false;
        }
      }
      
      debugPrint('📂 引擎路径: $enginePath');
      
      // 检查模型文件是否存在
      final modelPath = path.join(path.dirname(enginePath), 'lama_model.onnx');
      if (!await File(modelPath).exists()) {
        debugPrint('❌ 找不到模型文件: $modelPath');
        debugPrint('💡 请先运行 python_backend/download_model.py 下载模型');
        return false;
      }
      
      // 启动进程（静默模式）
      if (Platform.isWindows) {
        // Windows: 使用 CREATE_NO_WINDOW 标志隐藏窗口
        _engineProcess = await Process.start(
          enginePath,
          [],
          mode: ProcessStartMode.detached,
          runInShell: false,
        );
      } else {
        // Linux/Mac: 直接启动
        _engineProcess = await Process.start(
          enginePath,
          [],
          mode: ProcessStartMode.detached,
        );
      }
      
      debugPrint('🔧 引擎进程已启动 (PID: ${_engineProcess?.pid})');
      
      // 等待引擎启动（端口探活）
      final started = await _waitForEngineReady();
      
      if (started) {
        _isRunning = true;
        _startHealthCheck();
        debugPrint('✅ 引擎启动成功！');
        return true;
      } else {
        debugPrint('❌ 引擎启动超时');
        await stopEngine();
        return false;
      }
      
    } catch (e, stackTrace) {
      debugPrint('❌ 启动引擎失败: $e');
      debugPrint('堆栈: $stackTrace');
      
      // 🔧 即使启动失败，也尝试连接已运行的服务
      debugPrint('🔍 尝试连接已运行的后端服务...');
      final isServiceRunning = await checkHealth();
      if (isServiceRunning) {
        debugPrint('✅ 检测到后端服务已运行（开发模式）');
        _isRunning = true;
        _startHealthCheck();
        return true;
      }
      
      return false;
    }
  }
  
  /// 停止引擎
  Future<void> stopEngine() async {
    if (!_isRunning) {
      debugPrint('引擎未运行');
      return;
    }
    
    _isStopping = true;
    
    try {
      debugPrint('🛑 正在停止引擎...');
      
      // 停止健康检查
      _healthCheckTimer?.cancel();
      _healthCheckTimer = null;
      
      // 杀死进程并等待退出
      if (_engineProcess != null) {
        final killed = _engineProcess!.kill();
        if (killed) {
          // 等待进程实际退出，最多5秒
          try {
            await _engineProcess!.exitCode.timeout(const Duration(seconds: 5));
          } catch (_) {
            // 超时则强制 SIGKILL
            _engineProcess!.kill(ProcessSignal.sigkill);
          }
        }
        debugPrint('✅ 引擎进程已终止');
      }
      
      _isRunning = false;
      _engineProcess = null;
      
    } catch (e) {
      debugPrint('停止引擎时出错: $e');
    } finally {
      _isStopping = false;
    }
  }
  
  /// 检查引擎是否健康
  Future<bool> checkHealth() async {
    try {
      final response = await http.get(Uri.parse(_healthCheckUrl)).timeout(
        const Duration(seconds: 2),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
  
  /// 等待引擎就绪（端口探活）
  Future<bool> _waitForEngineReady() async {
    debugPrint('⏳ 等待引擎就绪...');
    
    const maxAttempts = 30; // 最多等待 30 秒
    const checkInterval = Duration(seconds: 1);
    
    for (int i = 0; i < maxAttempts; i++) {
      final isReady = await checkHealth();
      
      if (isReady) {
        debugPrint('✅ 引擎已就绪 (耗时: ${i + 1} 秒)');
        return true;
      }
      
      if (i % 5 == 0) {
        debugPrint('⏳ 等待中... (${i + 1}/$maxAttempts)');
      }
      
      await Future.delayed(checkInterval);
    }
    
    return false;
  }
  
  /// 启动健康检查定时器
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    
    _healthCheckTimer = Timer.periodic(
      const Duration(seconds: 10),
      (timer) async {
        // 如果正在停止引擎，跳过此次检查
        if (_isStopping || !_isRunning) return;
        
        final isHealthy = await checkHealth();
        
        // 再次检查状态，避免在检查期间引擎已停止
        if (!isHealthy && _isRunning && !_isStopping) {
          debugPrint('⚠️ 引擎健康检查失败，尝试重启...');
          _isRunning = false;
          await startEngine();
        }
      },
    );
  }
  
  /// 获取引擎可执行文件路径
  String? _getEnginePath() {
    try {
      // 获取当前可执行文件所在目录
      final exePath = Platform.resolvedExecutable;
      final exeDir = path.dirname(exePath);
      
      String engineName;
      if (Platform.isWindows) {
        engineName = 'watermark_engine.exe';
      } else {
        engineName = 'watermark_engine';
      }
      
      // 引擎应该在应用同级目录
      final enginePath = path.join(exeDir, engineName);
      
      return enginePath;
    } catch (e) {
      debugPrint('获取引擎路径失败: $e');
      return null;
    }
  }
}
