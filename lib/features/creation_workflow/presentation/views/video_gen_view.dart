import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../domain/models/project.dart';
import '../../domain/models/video_clip.dart';
import '../workflow_controller.dart';

/// 第4步：视频生成
class VideoGenView extends StatelessWidget {
  final WorkflowController controller;

  const VideoGenView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF161618),
      child: ValueListenableBuilder<Project>(
        valueListenable: controller.projectNotifier,
        builder: (context, project, _) {
          if (project.storyboards.isEmpty) {
            return _buildNoStoryboardState();
          }
          return Column(
            children: [
              _buildToolbar(),
              Expanded(
                child: _buildVideoList(context, project),
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
      child: const Row(
        children: [
          Text(
            '视频生成',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoStoryboardState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.video_library_outlined,
            size: 100,
            color: Colors.white.withOpacity(0.1),
          ),
          const SizedBox(height: 24),
          const Text(
            '请先完成分镜生成',
            style: TextStyle(
              color: Color(0xFF888888),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '返回第3步生成分镜图片',
            style: TextStyle(
              color: Color(0xFF666666),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoList(BuildContext context, Project project) {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: project.storyboards.length,
      itemBuilder: (context, index) {
        final storyboard = project.storyboards[index];
        final videoClip = project.videoClips.firstWhere(
          (vc) => vc.storyboardId == storyboard.id,
          orElse: () => VideoClip(
            id: '',
            storyboardId: storyboard.id,
            generationMode: VideoGenerationMode.imageToVideo,
          ),
        );

        return _buildVideoItem(context, storyboard.id, storyboard.imageUrl,
            videoClip, index + 1);
      },
    );
  }

  Widget _buildVideoItem(
    BuildContext context,
    String storyboardId,
    String imageUrl,
    VideoClip videoClip,
    int index,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF2A2A2C),
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF888888).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '片段 $index',
                    style: const TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                if (videoClip.status == VideoClipStatus.completed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF888888).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '✓ 已完成',
                      style: TextStyle(
                        color: Color(0xFF888888),
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            // 生成模式选择
            const Text(
              '生成模式',
              style: TextStyle(
                color: Color(0xFF888888),
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: VideoGenerationMode.values.map((mode) {
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _buildModeCard(context, storyboardId, imageUrl, mode),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard(
    BuildContext context,
    String storyboardId,
    String imageUrl,
    VideoGenerationMode mode,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _showGenerateDialog(context, storyboardId, imageUrl, mode),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF252629),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFF3A3A3C),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                _getModeIcon(mode),
                color: const Color(0xFF888888),
                size: 32,
              ),
              const SizedBox(height: 12),
              Text(
                mode.displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                mode.description,
                style: const TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getModeIcon(VideoGenerationMode mode) {
    switch (mode) {
      case VideoGenerationMode.textToVideo:
        return Icons.text_fields;
      case VideoGenerationMode.imageToVideo:
        return Icons.image;
      case VideoGenerationMode.keyframes:
        return Icons.compare;
    }
  }

  void _showGenerateDialog(
    BuildContext context,
    String storyboardId,
    String imageUrl,
    VideoGenerationMode mode,
  ) {
    if (mode == VideoGenerationMode.keyframes) {
      _showKeyframesDialog(context, storyboardId, imageUrl);
    } else {
      controller.generateVideoClip(
        storyboardId: storyboardId,
        mode: mode,
      );
    }
  }

  void _showKeyframesDialog(
    BuildContext context,
    String storyboardId,
    String imageUrl,
  ) {
    String? startFrameUrl = imageUrl;  // 默认使用分镜图
    String? endFrameUrl;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E20),
            title: const Text(
              '首尾帧控制',
              style: TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: 600,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      // 起始帧
                      Expanded(
                        child: Column(
                          children: [
                            const Text(
                              '起始帧',
                              style: TextStyle(
                                color: Color(0xFF888888),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: () async {
                                final result = await FilePicker.platform.pickFiles(
                                  type: FileType.image,
                                );
                                if (result != null && result.files.isNotEmpty) {
                                  setState(() {
                                    startFrameUrl = result.files.first.path;
                                  });
                                }
                              },
                              child: Container(
                                width: 250,
                                height: 150,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF252629),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFF3A3A3C),
                                  ),
                                ),
                                child: startFrameUrl != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          startFrameUrl!,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : const Center(
                                        child: Text(
                                          '点击上传',
                                          style: TextStyle(
                                            color: Color(0xFF666666),
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      const Icon(
                        Icons.arrow_forward,
                        color: Color(0xFF888888),
                        size: 32,
                      ),
                      const SizedBox(width: 20),
                      // 结束帧
                      Expanded(
                        child: Column(
                          children: [
                            const Text(
                              '结束帧（可选）',
                              style: TextStyle(
                                color: Color(0xFF888888),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: () async {
                                final result = await FilePicker.platform.pickFiles(
                                  type: FileType.image,
                                );
                                if (result != null && result.files.isNotEmpty) {
                                  setState(() {
                                    endFrameUrl = result.files.first.path;
                                  });
                                }
                              },
                              child: Container(
                                width: 250,
                                height: 150,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF252629),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFF3A3A3C),
                                  ),
                                ),
                                child: endFrameUrl != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          endFrameUrl!,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : const Center(
                                        child: Text(
                                          '点击上传',
                                          style: TextStyle(
                                            color: Color(0xFF666666),
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  controller.generateVideoClip(
                    storyboardId: storyboardId,
                    mode: VideoGenerationMode.keyframes,
                    startFrameUrl: startFrameUrl,
                    endFrameUrl: endFrameUrl,
                  );
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF888888),
                  foregroundColor: Colors.black,
                ),
                child: const Text('生成视频'),
              ),
            ],
          );
        },
      ),
    );
  }
}
