import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'features/home/presentation/home_screen.dart';

// 全局主题状态管理器
final ValueNotifier<int> themeNotifier = ValueNotifier<int>(0); // 0: 深邃黑, 1: 纯净白, 2: 梦幻粉

// 全局保存路径管理器
final ValueNotifier<String> imageSavePathNotifier = ValueNotifier<String>('未设置');
final ValueNotifier<String> videoSavePathNotifier = ValueNotifier<String>('未设置');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    minimumSize: Size(1000, 600),
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
    await windowManager.setMinimumSize(const Size(1000, 600));
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setSkipTaskbar(false);
  });

  runApp(const XingheApp());
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
