import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_kit/media_kit.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/auth/presentation/auth_provider.dart';
import 'core/logger/log_manager.dart';

// 全局主题状态管理器
final ValueNotifier<int> themeNotifier = ValueNotifier<int>(
  0,
); // 0: 深邃黑, 1: 纯净白, 2: 梦幻粉

// 全局认证状态管理器
final AuthProvider authProvider = AuthProvider();

// 全局保存路径管理器
final ValueNotifier<String> imageSavePathNotifier = ValueNotifier<String>(
  '未设置',
);
final ValueNotifier<String> videoSavePathNotifier = ValueNotifier<String>(
  '未设置',
);
final ValueNotifier<String> workSavePathNotifier = ValueNotifier<String>(
  '未设置',
); // ✅ 作品保存路径
final ValueNotifier<String> canvasSavePathNotifier = ValueNotifier<String>(
  '未设置',
); // ✅ 画布空间保存路径

// 全局路由观察器（用于监听页面切换）
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

// ==========================================
// Python 后端进程守护管理器（单例）
// ==========================================
class PythonBackendManager {
  static final PythonBackendManager _instance = PythonBackendManager._();
  factory PythonBackendManager() => _instance;
  PythonBackendManager._();

  Process? _process;
  bool _isRunning = false;
  bool _externalProcess = false; // 是否由外部进程管理（端口已占用时）

  bool get isRunning => _isRunning;

  /// 启动 Python 后端服务
  /// - Release 模式：从 exe 同级目录启动 api_server.exe
  /// - Debug 模式：用 python 命令启动 api_server.py 脚本
  /// - 自动检测端口占用，避免重复启动
  Future<void> start() async {
    if (_isRunning) {
      debugPrint('⚠️ Python 后端已在运行，跳过重复启动');
      return;
    }

    try {
      // === 端口健康检查：验证 8123 上是否有活跃的 API 服务 ===
      final healthStatus = await _checkServerHealth();
      if (healthStatus == _ServerHealth.healthy) {
        debugPrint('✅ Python 后端已在运行且健康，跳过启动');
        _isRunning = true;
        _externalProcess = true;
        return;
      } else if (healthStatus == _ServerHealth.portOccupied) {
        // 端口被占用但不是我们的服务（僵尸进程），尝试清理
        debugPrint('⚠️ 端口 8123 被非 API 进程占用，尝试清理...');
        await _killProcessOnPort(8123);
        await Future.delayed(const Duration(seconds: 1)); // 等待端口释放
      }
      // healthStatus == _ServerHealth.free → 正常启动

      // === 策略 1：Release 模式 — 查找同级 api_server.exe ===
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final serverExePath = '$exeDir${Platform.pathSeparator}api_server.exe';

      if (File(serverExePath).existsSync()) {
        debugPrint('🚀 [Release] 正在启动 Python 后端: $serverExePath');
        _process = await Process.start(
          serverExePath,
          [],
          workingDirectory: exeDir,
          mode: ProcessStartMode.normal,
        );
      } else {
        // === 策略 2：Debug 模式 — 用 python 命令启动脚本 ===
        // 从项目根目录查找 api_server.py
        final projectRoot = _findProjectRoot(exeDir);
        if (projectRoot == null) {
          debugPrint('⚠️ 未找到项目根目录，无法启动 Python 后端（开发模式）');
          return;
        }
        final scriptPath =
            '$projectRoot${Platform.pathSeparator}python_backend${Platform.pathSeparator}web_automation${Platform.pathSeparator}api_server.py';
        if (!File(scriptPath).existsSync()) {
          debugPrint('⚠️ api_server.py 未找到: $scriptPath');
          return;
        }
        final workDir =
            '$projectRoot${Platform.pathSeparator}python_backend${Platform.pathSeparator}web_automation';
        debugPrint('🚀 [Debug] 正在启动 Python 后端: python $scriptPath');
        _process = await Process.start(
          'python',
          ['-u', scriptPath], // -u: 无缓冲输出，确保 print 实时可见
          workingDirectory: workDir,
          mode: ProcessStartMode.normal,
        );
      }

      _isRunning = true;
      debugPrint('✅ Python 后端已启动 (PID: ${_process!.pid})');

      // 监听进程退出（意外崩溃时记录日志）
      _process!.exitCode.then((code) {
        _isRunning = false;
        _process = null;
        if (code != 0) {
          debugPrint('❌ Python 后端进程异常退出 (exit code: $code)');
        } else {
          debugPrint('ℹ️ Python 后端进程正常退出');
        }
      });

      // 捕获 stderr 输出（用于调试 Python 启动错误）
      _process!.stderr.transform(const SystemEncoding().decoder).listen((data) {
        debugPrint('🐍 [Python stderr] $data');
      });
      // 捕获 stdout 输出（Python print 语句）
      _process!.stdout.transform(const SystemEncoding().decoder).listen((data) {
        debugPrint('🐍 [Python] $data');
      });

      // 等待服务启动（PyInstaller --onefile exe 需要解压，可能较慢）
      // 轮询健康检查，最多等 30 秒
      var ready = false;
      for (var i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (!_isRunning) break; // 进程已退出
        final health = await _checkServerHealth();
        if (health == _ServerHealth.healthy) {
          ready = true;
          break;
        }
        if (i % 5 == 4) debugPrint('⏳ 等待 Python 后端启动... (${i + 1}s)');
      }
      if (ready) {
        debugPrint('✅ Python 后端服务就绪 (http://127.0.0.1:8123)');
      } else if (!_isRunning) {
        debugPrint('❌ Python 后端在启动等待期间已崩溃，请检查上方 stderr 日志');
      } else {
        debugPrint('⚠️ Python 后端启动超时（30s），服务可能仍在加载中');
      }
    } catch (e) {
      debugPrint('❌ 启动 Python 后端失败: $e');
    }
  }

  /// 从 exe 目录向上查找项目根目录（含 pubspec.yaml 的目录）
  String? _findProjectRoot(String startDir) {
    var dir = Directory(startDir);
    // 最多向上查找 10 层
    for (var i = 0; i < 10; i++) {
      final pubspec = File('${dir.path}${Platform.pathSeparator}pubspec.yaml');
      if (pubspec.existsSync()) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break; // 到达根目录
      dir = parent;
    }
    return null;
  }

  /// 立即杀掉 Python 后端进程（同步，用于窗口关闭时快速退出）
  void killImmediate() {
    if (_process != null) {
      final pid = _process!.pid;
      debugPrint('🛑 立即杀掉 Python 后端 (PID: $pid)');
      try {
        _process!.kill(ProcessSignal.sigkill);
      } catch (e) {
        debugPrint('⚠️ kill进程失败: $e');
      }
      if (Platform.isWindows) {
        try {
          Process.runSync('taskkill', ['/F', '/T', '/PID', '$pid']);
        } catch (e) {
          debugPrint('⚠️ taskkill PID失败: $e');
        }
      }
    }
    // 按进程名杀掉所有 api_server.exe（包括 PyInstaller 子进程和上次残留的）
    if (Platform.isWindows) {
      try {
        Process.runSync('taskkill', ['/F', '/IM', 'api_server.exe']);
      } catch (e) {
        debugPrint('⚠️ taskkill api_server失败: $e');
      }
    }
    _process = null;
    _isRunning = false;
    _externalProcess = false;
  }

  /// 关闭 Python 后端进程（仅关闭由本实例启动的进程）
  Future<void> stop() async {
    if (_externalProcess) {
      debugPrint('ℹ️ Python 后端由外部管理，不执行关闭');
      _isRunning = false;
      _externalProcess = false;
      return;
    }
    if (_process != null) {
      debugPrint('🛑 正在关闭 Python 后端 (PID: ${_process!.pid})...');
      try {
        _process!.kill(ProcessSignal.sigterm);
        // Windows 上 SIGTERM 可能不生效，用 taskkill /T 强制结束整棵进程树
        if (Platform.isWindows) {
          await Process.run('taskkill', [
            '/F',
            '/T',
            '/PID',
            '${_process!.pid}',
          ]);
          // 额外按进程名清理残留（防止 PyInstaller 子进程逃逸）
          await Process.run('taskkill', ['/F', '/IM', 'api_server.exe']);
        }
      } catch (e) {
        debugPrint('⚠️ 关闭 Python 后端时出错: $e');
      }
      _process = null;
      _isRunning = false;
      debugPrint('✅ Python 后端已关闭');
    }
  }

  /// 检查指定端口是否被占用
  Future<bool> _isPortInUse(int port) async {
    try {
      final socket = await Socket.connect(
        '127.0.0.1',
        port,
        timeout: const Duration(seconds: 1),
      );
      socket.destroy();
      return true; // 能连上说明端口已被占用
    } catch (_) {
      return false; // 连不上说明端口空闲
    }
  }

  /// 检查 Python 后端服务的健康状态
  Future<_ServerHealth> _checkServerHealth() async {
    try {
      // 先检查端口是否有东西在监听
      if (!await _isPortInUse(8123)) {
        return _ServerHealth.free;
      }
      // 端口有监听，尝试 HTTP 健康检查
      final response = await http
          .get(Uri.parse('http://127.0.0.1:8123/docs'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        return _ServerHealth.healthy; // 是我们的 FastAPI 服务
      }
      return _ServerHealth.portOccupied; // 端口被占用但不是我们的服务
    } on TimeoutException {
      return _ServerHealth.portOccupied;
    } catch (_) {
      return _ServerHealth.portOccupied;
    }
  }

  /// 杀掉占用指定端口的进程（Windows 专用）
  Future<void> _killProcessOnPort(int port) async {
    if (!Platform.isWindows) return;
    try {
      // 用 netstat 查找占用端口的 PID
      final result = await Process.run('cmd', [
        '/c',
        'netstat -ano | findstr :$port | findstr LISTENING',
      ]);
      final output = result.stdout.toString().trim();
      if (output.isEmpty) return;

      // 解析 PID（netstat 输出最后一列是 PID）
      final lines = output.split('\n');
      final pids = <String>{};
      for (final line in lines) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.isNotEmpty) {
          pids.add(parts.last);
        }
      }
      // 杀掉找到的 PID
      for (final pid in pids) {
        if (pid.isNotEmpty && pid != '0') {
          debugPrint('🛑 杀掉占用端口 $port 的进程 PID: $pid');
          await Process.run('taskkill', ['/F', '/PID', pid]);
        }
      }
    } catch (e) {
      debugPrint('⚠️ 清理端口 $port 失败: $e');
    }
  }
}

/// Python 后端服务健康状态
enum _ServerHealth {
  free, // 端口空闲，可以启动
  healthy, // 服务正常运行，跳过启动
  portOccupied, // 端口被占用但不是我们的服务
}

// 全局 Python 后端管理器实例
final pythonBackend = PythonBackendManager();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ 初始化 media_kit（视频播放器）
  MediaKit.ensureInitialized();

  // ✅ OSS 配置将在版本检查时自动初始化（从 version.json 获取）
  debugPrint('✅ OSS 配置将从远程 version.json 动态加载');

  debugPrint('✅ 应用初始化开始');

  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    minimumSize: Size(1280, 720), // ✅ 最小尺寸改为1280x720
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'R·O·S 动漫制作',
    alwaysOnTop: false,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setTitle('R·O·S 动漫制作');
    await windowManager.setSize(const Size(1280, 720));
    await windowManager.setMinimumSize(const Size(1280, 720)); // ✅ 最小尺寸1280x720
    await windowManager.setResizable(true); // ✅ 启用调整大小
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setSkipTaskbar(false);
  });

  // 初始化日志管理器
  final logManager = LogManager();
  await logManager.loadLogs();

  // 加载保存路径配置
  await _loadSavePaths();

  // 初始化认证状态（自动登录）
  await authProvider.initialize();

  // ✅ 启动 Python 后端服务（后台启动，不阻塞 UI 显示）
  pythonBackend.start();

  logManager.success('应用启动成功', module: '系统');

  runApp(const XingheApp());
}

/// 启动时加载保存路径
Future<void> _loadSavePaths() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final imagePath = prefs.getString('image_save_path');
    final videoPath = prefs.getString('video_save_path');
    final workPath = prefs.getString('work_save_path');

    if (imagePath != null && imagePath.isNotEmpty) {
      imageSavePathNotifier.value = imagePath;
      debugPrint('✅ 加载图片保存路径: $imagePath');
    }

    if (videoPath != null && videoPath.isNotEmpty) {
      videoSavePathNotifier.value = videoPath;
      debugPrint('✅ 加载视频保存路径: $videoPath');
    }

    if (workPath != null && workPath.isNotEmpty) {
      workSavePathNotifier.value = workPath;
      debugPrint('✅ 加载作品保存路径: $workPath');
    }

    // ✅ 加载画布空间保存路径
    final canvasPath = prefs.getString('canvas_save_path');
    if (canvasPath != null && canvasPath.isNotEmpty) {
      canvasSavePathNotifier.value = canvasPath;
      debugPrint('✅ 加载画布空间保存路径: $canvasPath');
    }
  } catch (e) {
    debugPrint('⚠️ 加载保存路径失败: $e');
  }
}

class XingheApp extends StatefulWidget {
  const XingheApp({super.key});

  @override
  State<XingheApp> createState() => _XingheAppState();
}

class _XingheAppState extends State<XingheApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // 启用窗口关闭拦截（先清理再退出）
    windowManager.setPreventClose(true);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  /// 窗口关闭前回调：立即杀进程并强制退出
  @override
  void onWindowClose() async {
    debugPrint('🛑 用户关闭窗口');
    // 杀掉 Python 后端进程
    pythonBackend.killImmediate();
    // 强制退出整个进程（窗口自动随进程销毁）
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: themeNotifier,
      builder: (context, themeIndex, _) {
        final themeData = _getThemeData(themeIndex);
        return MaterialApp(
          title: 'R·O·S 动漫制作',
          debugShowCheckedModeBanner: false,
          theme: themeData,
          home: const HomeScreen(),
          navigatorObservers: [routeObserver],
        );
      },
    );
  }

  ThemeData _getThemeData(int index) {
    switch (index) {
      case 1: // 纯净白
        return ThemeData.light().copyWith(
          scaffoldBackgroundColor: const Color(0xFFF5F5F7),
          primaryColor: const Color(0xFF009EFD),
          textTheme: ThemeData.light().textTheme.apply(
            fontFamily: 'Microsoft YaHei',
            bodyColor: Colors.black87,
            displayColor: Colors.black,
          ),
          dividerColor: Colors.black12,
        );
      case 2: // 梦幻粉
        return ThemeData.light().copyWith(
          scaffoldBackgroundColor: const Color(0xFFFFF0F5),
          primaryColor: const Color(0xFFFF69B4),
          textTheme: ThemeData.light().textTheme.apply(
            fontFamily: 'Microsoft YaHei',
            bodyColor: const Color(0xFFD81B60),
            displayColor: const Color(0xFF880E4F),
          ),
          dividerColor: const Color(0xFFFFD1DC),
        );
      default: // 深邃黑
        return ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF161618),
          primaryColor: const Color(0xFF00E5FF),
          textTheme: ThemeData.dark().textTheme.apply(
            fontFamily: 'Microsoft YaHei',
            bodyColor: Colors.white,
            displayColor: Colors.white,
          ),
          dividerColor: Colors.white10,
        );
    }
  }
}

// 辅助类：根据当前主题获取颜色
class AppTheme {
  static Color get scaffoldBackground {
    switch (themeNotifier.value) {
      case 1:
        return const Color(0xFFF5F5F7);
      case 2:
        return const Color(0xFFFFF0F5);
      default:
        return const Color(0xFF161618);
    }
  }

  static Color get surfaceBackground {
    switch (themeNotifier.value) {
      case 1:
        return const Color(0xFFFFFFFF);
      case 2:
        return const Color(0xFFFFD1DC);
      default:
        return const Color(0xFF1D1D1F);
    }
  }

  static Color get inputBackground {
    switch (themeNotifier.value) {
      case 1:
        return const Color(0xFFECECEC);
      case 2:
        return const Color(0xFFFFE4E1);
      default:
        return const Color(0xFF252629);
    }
  }

  static Color get textColor {
    switch (themeNotifier.value) {
      case 1:
        return Colors.black87;
      case 2:
        return const Color(0xFF880E4F);
      default:
        return Colors.white;
    }
  }

  static Color get subTextColor {
    switch (themeNotifier.value) {
      case 1:
        return Colors.black45;
      case 2:
        return const Color(0xFFD81B60).withOpacity(0.6);
      default:
        return Colors.white38;
    }
  }

  static Color get accentColor {
    switch (themeNotifier.value) {
      case 1:
        return const Color(0xFF009EFD);
      case 2:
        return const Color(0xFFFF69B4);
      default:
        return const Color(0xFF00E5FF);
    }
  }

  static Color get dividerColor {
    switch (themeNotifier.value) {
      case 1:
        return Colors.black.withOpacity(0.08);
      case 2:
        return const Color(0xFFFFD1DC);
      default:
        return Colors.white.withOpacity(0.06);
    }
  }

  static Color get sideBarItemHover {
    switch (themeNotifier.value) {
      case 1:
        return Colors.black.withOpacity(0.05);
      case 2:
        return Colors.white.withOpacity(0.3);
      default:
        return const Color(0xFF3E3F42);
    }
  }
}
