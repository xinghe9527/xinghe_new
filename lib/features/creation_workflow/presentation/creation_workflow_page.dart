import 'package:flutter/material.dart';
import '../domain/models/project.dart';
import 'workflow_controller.dart';
import 'views/script_editor_view.dart';
import 'views/entity_manager_view.dart';
import 'views/storyboard_view.dart';
import 'views/video_gen_view.dart';

/// 项目创作流主页面（全屏弹窗）
class CreationWorkflowPage extends StatefulWidget {
  final String projectName;
  final String? projectId;  // 作品ID，用于加载/保存

  const CreationWorkflowPage({
    super.key,
    required this.projectName,
    this.projectId,
  });

  @override
  State<CreationWorkflowPage> createState() => _CreationWorkflowPageState();
}

class _CreationWorkflowPageState extends State<CreationWorkflowPage> {
  late final WorkflowController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WorkflowController(
      initialProject: Project.empty(name: widget.projectName),
      projectId: widget.projectId,
    );
    // 如果有projectId，加载已保存的数据
    if (widget.projectId != null) {
      _controller.loadProject();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF161618),
      body: Column(
        children: [
          _buildHeader(),
          _buildStepIndicator(),
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: _controller.currentStepNotifier,
              builder: (context, step, _) {
                return _buildStepContent(step);
              },
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  /// 顶部标题栏
  Widget _buildHeader() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 返回按钮
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: '返回',
          ),
          const SizedBox(width: 12),
          // 项目标题
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.projectName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'AI 动漫创作工作流',
                  style: TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // 加载指示器
          ValueListenableBuilder<bool>(
            valueListenable: _controller.isLoadingNotifier,
            builder: (context, isLoading, _) {
              if (!isLoading) return const SizedBox.shrink();
              return const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Color(0xFF888888)),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 步骤指示器
  Widget _buildStepIndicator() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1C),
        border: Border(
          bottom: BorderSide(color: Color(0xFF2A2A2C), width: 1),
        ),
      ),
      child: ValueListenableBuilder<int>(
        valueListenable: _controller.currentStepNotifier,
        builder: (context, currentStep, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStepItem(1, '剧本创作', currentStep),
              _buildStepArrow(currentStep >= 2),
              _buildStepItem(2, '角色/场景', currentStep),
              _buildStepArrow(currentStep >= 3),
              _buildStepItem(3, '分镜生成', currentStep),
              _buildStepArrow(currentStep >= 4),
              _buildStepItem(4, '视频合成', currentStep),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStepItem(int step, String label, int currentStep) {
      final isActive = step == currentStep;
    final isCompleted = step < currentStep;

    return GestureDetector(
      onTap: () => _controller.goToStep(step),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF3A3A3C).withOpacity(0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? const Color(0xFF888888)
                : isCompleted
                    ? const Color(0xFF666666)
                    : const Color(0xFF3A3A3C),
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isActive || isCompleted
                    ? const Color(0xFF888888)
                    : const Color(0xFF3A3A3C),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isCompleted
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : Text(
                        '$step',
                        style: TextStyle(
                          color: isActive || isCompleted
                              ? Colors.white
                              : const Color(0xFF666666),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? const Color(0xFF888888)
                    : isCompleted
                        ? const Color(0xFF888888)
                        : const Color(0xFF666666),
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepArrow(bool isActive) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Icon(
        Icons.arrow_forward,
        color: isActive
            ? const Color(0xFF666666)
            : const Color(0xFF3A3A3C),
        size: 20,
      ),
    );
  }

  /// 步骤内容区域
  Widget _buildStepContent(int step) {
    switch (step) {
      case 1:
        return ScriptEditorView(controller: _controller);
      case 2:
        return EntityManagerView(controller: _controller);
      case 3:
        return StoryboardView(controller: _controller);
      case 4:
        return VideoGenView(controller: _controller);
      default:
        return const Center(child: Text('未知步骤'));
    }
  }

  /// 底部操作栏
  Widget _buildFooter() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ValueListenableBuilder<int>(
        valueListenable: _controller.currentStepNotifier,
        builder: (context, step, _) {
          return Row(
            children: [
              // 错误提示
              Expanded(
                child: ValueListenableBuilder<String?>(
                  valueListenable: _controller.errorMessageNotifier,
                  builder: (context, error, _) {
                    if (error == null) return const SizedBox.shrink();
                    return Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            error,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              // 上一步按钮
              if (step > 1)
                TextButton.icon(
                  onPressed: _controller.previousStep,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('上一步'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              // 下一步/完成按钮
              ElevatedButton.icon(
                onPressed: step < 4 ? _controller.nextStep : _saveAndExit,
                icon: Icon(step < 4 ? Icons.arrow_forward : Icons.check,
                    size: 18),
                label: Text(step < 4 ? '下一步' : '完成'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3A3A3C),
                  foregroundColor: const Color(0xFF888888),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 保存并退出
  void _saveAndExit() {
    // TODO: 保存项目数据
    Navigator.of(context).pop(_controller.project);
  }
}
