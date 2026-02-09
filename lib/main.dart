import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_kit/media_kit.dart';
import 'features/home/presentation/home_screen.dart';
import 'core/logger/log_manager.dart';

// 全局主题状态管理器
final ValueNotifier<int> themeNotifier = ValueNotifier<int>(0); // 0: 深邃黑, 1: 纯净白, 2: 梦幻粉

// 全局保存路径管理器
final ValueNotifier<String> imageSavePathNotifier = ValueNotifier<String>('未设置');
final ValueNotifier<String> videoSavePathNotifier = ValueNotifier<String>('未设置');
final ValueNotifier<String> workSavePathNotifier = ValueNotifier<String>('未设置');  // ✅ 作品保存路径

// 全局路由观察器（用于监听页面切换）
final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ✅ 初始化 media_kit（视频播放器）
  MediaKit.ensureInitialized();
  
  // ✅ 已移除 Supabase 初始化，改用阿里云 OSS
  debugPrint('✅ 应用初始化开始');
  
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    minimumSize: Size(1280, 720),  // ✅ 最小尺寸改为1280x720
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: '星橙AI动漫制作',
    alwaysOnTop: false,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setTitle('星橙AI动漫制作');
    await windowManager.setSize(const Size(1280, 720));
    await windowManager.setMinimumSize(const Size(1280, 720));  // ✅ 最小尺寸1280x720
    await windowManager.setResizable(true);  // ✅ 启用调整大小
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
  } catch (e) {
    debugPrint('⚠️ 加载保存路径失败: $e');
  }
}

class XingheApp extends StatelessWidget {
  const XingheApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: themeNotifier,
      builder: (context, themeIndex, _) {
        final themeData = _getThemeData(themeIndex);
        return MaterialApp(
          title: '星橙AI动漫制作',
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
      case 1: return const Color(0xFFF5F5F7);
      case 2: return const Color(0xFFFFF0F5);
      default: return const Color(0xFF161618);
    }
  }

  static Color get surfaceBackground {
    switch (themeNotifier.value) {
      case 1: return const Color(0xFFFFFFFF);
      case 2: return const Color(0xFFFFD1DC);
      default: return const Color(0xFF1D1D1F);
    }
  }

  static Color get inputBackground {
    switch (themeNotifier.value) {
      case 1: return const Color(0xFFECECEC);
      case 2: return const Color(0xFFFFE4E1);
      default: return const Color(0xFF252629);
    }
  }

  static Color get textColor {
    switch (themeNotifier.value) {
      case 1: return Colors.black87;
      case 2: return const Color(0xFF880E4F);
      default: return Colors.white;
    }
  }

  static Color get subTextColor {
    switch (themeNotifier.value) {
      case 1: return Colors.black45;
      case 2: return const Color(0xFFD81B60).withOpacity(0.6);
      default: return Colors.white38;
    }
  }

  static Color get accentColor {
    switch (themeNotifier.value) {
      case 1: return const Color(0xFF009EFD);
      case 2: return const Color(0xFFFF69B4);
      default: return const Color(0xFF00E5FF);
    }
  }

  static Color get dividerColor {
    switch (themeNotifier.value) {
      case 1: return Colors.black.withOpacity(0.08);
      case 2: return const Color(0xFFFFD1DC);
      default: return Colors.white.withOpacity(0.06);
    }
  }

  static Color get sideBarItemHover {
    switch (themeNotifier.value) {
      case 1: return Colors.black.withOpacity(0.05);
      case 2: return Colors.white.withOpacity(0.3);
      default: return const Color(0xFF3E3F42);
    }
  }
}
