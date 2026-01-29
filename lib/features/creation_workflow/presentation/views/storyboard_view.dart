import 'package:flutter/material.dart';
import '../../domain/models/project.dart';
import '../../domain/models/storyboard.dart';
import '../workflow_controller.dart';

/// 第3步：分镜生成
class StoryboardView extends StatelessWidget {
  final WorkflowController controller;

  const StoryboardView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF161618),
      child: ValueListenableBuilder<Project>(
        valueListenable: controller.projectNotifier,
        builder: (context, project, _) {
          if (project.scriptLines.isEmpty) {
            return _buildNoScriptState();
          }
          return Column(
            children: [
              _buildToolbar(),
              Expanded(
                child: _buildTimelineView(context, project),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1C),
        border: Border(
          bottom: BorderSide(color: Color(0xFF2A2A2C), width: 1),
        ),
      ),
      child: Row(
        children: [
          const Text(
            '分镜生成',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // 批量图片生成按钮
          ElevatedButton.icon(
            onPressed: () => _batchGenerateImages(),
            icon: const Icon(Icons.collections, size: 18),
            label: const Text('批量图片生成'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A8FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
          ),
          const SizedBox(width: 12),
          // 批量视频生成按钮
          ElevatedButton.icon(
            onPressed: () => _batchGenerateVideos(),
            icon: const Icon(Icons.video_library, size: 18),
            label: const Text('批量视频生成'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B6B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoScriptState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.movie_outlined,
            size: 100,
            color: Colors.white.withOpacity(0.1),
          ),
          const SizedBox(height: 24),
          const Text(
            '请先完成剧本创作',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '返回第1步添加剧本内容',
            style: TextStyle(
              color: Color(0xFF666666),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineView(BuildContext context, Project project) {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: project.scriptLines.length,
      itemBuilder: (context, index) {
        final scriptLine = project.scriptLines[index];
        final storyboard = project.storyboards.firstWhere(
          (sb) => sb.scriptLineId == scriptLine.id,
          orElse: () => Storyboard(
            id: '',
            scriptLineId: scriptLine.id,
          ),
        );

        return _buildStoryboardItem(
          context,
          scriptLine.id,
          scriptLine.content,
          storyboard,
          index + 1,
        );
      },
    );
  }

  Widget _buildStoryboardItem(
    BuildContext context,
    String scriptLineId,
    String scriptContent,
    Storyboard storyboard,
    int index,
  ) {
    final hasImage = storyboard.imageUrl.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: storyboard.isConfirmed
              ? const Color(0xFF888888)
              : const Color(0xFF2A2A2C),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFF2A2A2C), width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF888888).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '$index',
                      style: const TextStyle(
                        color: Color(0xFF888888),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    scriptContent,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (storyboard.isConfirmed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF888888).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.check_circle,
                            color: Color(0xFF888888), size: 16),
                        SizedBox(width: 6),
                        Text(
                          '已确认',
                          style: TextStyle(
                            color: Color(0xFF888888),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // 内容区
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 图片预览
                Container(
                  width: 300,
                  height: 200,
                  decoration: BoxDecoration(
                    color: const Color(0xFF252629),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF3A3A3C),
                      width: 1,
                    ),
                  ),
                  child: hasImage
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            storyboard.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return _buildPlaceholder();
                            },
                          ),
                        )
                      : _buildPlaceholder(),
                ),
                const SizedBox(width: 20),
                // 右侧信息和操作
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '提示词',
                        style: TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF252629),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          storyboard.finalPrompt.isEmpty
                              ? '(待生成)'
                              : storyboard.finalPrompt,
                          style: TextStyle(
                            color: storyboard.finalPrompt.isEmpty
                                ? const Color(0xFF666666)
                                : const Color(0xFFCCCCCC),
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          if (!hasImage)
                            ElevatedButton.icon(
                              onPressed: () =>
                                  controller.generateStoryboard(scriptLineId),
                              icon: const Icon(Icons.image, size: 18),
                              label: const Text('生成图片'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF888888),
                                foregroundColor: Colors.black,
                              ),
                            )
                          else ...[
                            if (!storyboard.isConfirmed)
                              ElevatedButton.icon(
                                onPressed: () =>
                                    controller.confirmStoryboard(storyboard.id),
                                icon: const Icon(Icons.check, size: 18),
                                label: const Text('确认分镜'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF888888),
                                  foregroundColor: Colors.black,
                                ),
                              ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  controller.generateStoryboard(scriptLineId),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('重新生成'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(
                                    color: Color(0xFF3A3A3C)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_outlined,
            size: 60,
            color: Colors.white.withOpacity(0.1),
          ),
          const SizedBox(height: 12),
          const Text(
            '点击生成图片',
            style: TextStyle(
              color: Color(0xFF666666),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  /// 批量生成所有分镜图片
  void _batchGenerateImages() {
    controller.batchGenerateAllStoryboardImages();
  }

  /// 批量生成所有分镜视频
  void _batchGenerateVideos() {
    controller.batchGenerateAllStoryboardVideos();
  }
}
