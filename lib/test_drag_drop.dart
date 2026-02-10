import 'package:flutter/material.dart';
import 'features/creation_workflow/presentation/widgets/draggable_media_item.dart';

/// 测试拖放功能的简单页面
class TestDragDropPage extends StatelessWidget {
  const TestDragDropPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('测试拖放功能'),
        backgroundColor: const Color(0xFF667EEA),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '拖动下面的卡片到剪映或文件管理器',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            
            // 可拖动的视频卡片
            DraggableMediaItem(
              filePath: 'C:\\Users\\Administrator\\Desktop\\test.mp4',  // 替换为实际文件路径
              dragPreviewText: '测试视频',
              child: Container(
                width: 200,
                height: 150,
                decoration: BoxDecoration(
                  color: const Color(0xFF4A9EFF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.video_file, color: Colors.white, size: 48),
                    SizedBox(height: 8),
                    Text(
                      '拖动我',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 40),
            const Text(
              '提示：按住鼠标左键拖动',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
