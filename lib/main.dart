import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'features/home/presentation/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // 关键：设置为隐藏标题栏，但保留操作按钮（最小化、关闭等）
  // 这样应用背景色就能延伸到最顶部，解决白色标题栏问题
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    minimumSize: Size(1000, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden, 
    title: '星橙AI动漫制作',
  );
  
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const XingheApp());
}

class XingheApp extends StatelessWidget {
  const XingheApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '星橙AI动漫制作',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF161618),
        // 确保全局字体支持中文，避免乱码
        textTheme: ThemeData.dark().textTheme.apply(
          fontFamily: 'Microsoft YaHei',
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
