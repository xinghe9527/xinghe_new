import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../domain/models/project.dart';
import '../domain/models/script_line.dart';
import '../domain/models/entity.dart';
import '../domain/models/storyboard.dart';
import '../domain/models/video_clip.dart';
import '../data/real_ai_service.dart';

/// 工作流控制器（使用 ValueNotifier 进行状态管理）
class WorkflowController {
  final ValueNotifier<Project> projectNotifier;
  final ValueNotifier<int> currentStepNotifier;
  final ValueNotifier<bool> isLoadingNotifier;
  final ValueNotifier<String?> errorMessageNotifier;
  final String? projectId;  // 作品ID，用于保存/加载
  
  final RealAIService _aiService = RealAIService(); // ✅ 使用真实 AI 服务

  WorkflowController({
    required Project initialProject,
    this.projectId,
  })  : projectNotifier = ValueNotifier(initialProject),
        currentStepNotifier = ValueNotifier(initialProject.currentStep),
        isLoadingNotifier = ValueNotifier(false),
        errorMessageNotifier = ValueNotifier(null);

  Project get project => projectNotifier.value;
  int get currentStep => currentStepNotifier.value;
  bool get isLoading => isLoadingNotifier.value;
  String? get errorMessage => errorMessageNotifier.value;

  /// 更新项目（并自动保存）
  void updateProject(Project newProject) {
    projectNotifier.value = newProject;
    // 自动保存到本地
    _autoSaveProject();
  }

  /// 自动保存项目
  Future<void> _autoSaveProject() async {
    if (projectId == null) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'project_$projectId';
      final json = jsonEncode(project.toJson());
      await prefs.setString(key, json);
      debugPrint('✅ 自动保存项目: $projectId');
    } catch (e) {
      debugPrint('⚠️ 保存项目失败: $e');
    }
  }

  /// 加载项目数据
  Future<void> loadProject() async {
    if (projectId == null) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'project_$projectId';
      final jsonStr = prefs.getString(key);
      
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        final loadedProject = Project.fromJson(json);
        projectNotifier.value = loadedProject;
        currentStepNotifier.value = loadedProject.currentStep;
        debugPrint('✅ 加载项目数据: $projectId');
      }
    } catch (e) {
      debugPrint('⚠️ 加载项目失败: $e');
    }
  }

  /// 切换到指定步骤
  void goToStep(int step) {
    if (step >= 1 && step <= 4) {
      currentStepNotifier.value = step;
      updateProject(project.copyWith(currentStep: step));
    }
  }

  /// 下一步
  void nextStep() {
    if (currentStep < 4) {
      goToStep(currentStep + 1);
    }
  }

  /// 上一步
  void previousStep() {
    if (currentStep > 1) {
      goToStep(currentStep - 1);
    }
  }

  // ==================== 第1步：剧本编辑 ====================

  /// AI生成剧本
  Future<void> generateScript(String theme) async {
    try {
      isLoadingNotifier.value = true;
      errorMessageNotifier.value = null;

      final scriptLines = await _aiService.generateScript(theme: theme);
      updateProject(project.copyWith(scriptLines: scriptLines));
    } catch (e) {
      errorMessageNotifier.value = '剧本生成失败：$e';
    } finally {
      isLoadingNotifier.value = false;
    }
  }

  /// 添加剧本行
  void addScriptLine(ScriptLine line, {int? insertAt}) {
    final lines = List<ScriptLine>.from(project.scriptLines);
    if (insertAt != null && insertAt >= 0 && insertAt <= lines.length) {
      lines.insert(insertAt, line);
    } else {
      lines.add(line);
    }
    updateProject(project.copyWith(scriptLines: lines));
  }

  /// 更新剧本行
  void updateScriptLine(String id, ScriptLine updatedLine) {
    final lines = project.scriptLines.map((line) {
      return line.id == id ? updatedLine : line;
    }).toList();
    updateProject(project.copyWith(scriptLines: lines));
  }

  /// 删除剧本行
  void deleteScriptLine(String id) {
    final lines = project.scriptLines.where((line) => line.id != id).toList();
    updateProject(project.copyWith(scriptLines: lines));
  }

  /// 扩写剧本（在两行之间插入新内容）
  Future<void> expandScript(int insertAt) async {
    try {
      isLoadingNotifier.value = true;
      errorMessageNotifier.value = null;

      final previousContext = insertAt > 0 
          ? project.scriptLines[insertAt - 1].content 
          : '';
      final nextContext = insertAt < project.scriptLines.length 
          ? project.scriptLines[insertAt].content 
          : '';

      final newLine = await _aiService.expandScript(
        previousContext: previousContext,
        nextContext: nextContext,
      );

      addScriptLine(newLine, insertAt: insertAt);
    } catch (e) {
      errorMessageNotifier.value = '扩写失败：$e';
    } finally {
      isLoadingNotifier.value = false;
    }
  }

  // ==================== 第2步：实体管理 ====================

  /// 从剧本提取实体
  Future<void> extractEntities() async {
    try {
      isLoadingNotifier.value = true;
      errorMessageNotifier.value = null;

      final entities = await _aiService.extractEntities(
        scriptLines: project.scriptLines,
      );
      updateProject(project.copyWith(entities: entities));
    } catch (e) {
      errorMessageNotifier.value = '实体提取失败：$e';
    } finally {
      isLoadingNotifier.value = false;
    }
  }

  /// 添加实体
  void addEntity(Entity entity) {
    final entities = List<Entity>.from(project.entities)..add(entity);
    updateProject(project.copyWith(entities: entities));
  }

  /// 更新实体
  void updateEntity(String id, Entity updatedEntity) {
    final entities = project.entities.map((entity) {
      return entity.id == id ? updatedEntity : entity;
    }).toList();
    updateProject(project.copyWith(entities: entities));
  }

  /// 删除实体
  void deleteEntity(String id) {
    final entities = project.entities.where((entity) => entity.id != id).toList();
    updateProject(project.copyWith(entities: entities));
  }

  /// 切换实体锁定状态
  void toggleEntityLock(String id) {
    final entity = project.entities.firstWhere((e) => e.id == id);
    updateEntity(id, entity.copyWith(isLocked: !entity.isLocked));
  }

  // ==================== 第3步：分镜生成 ====================

  /// 生成分镜图片
  Future<void> generateStoryboard(String scriptLineId) async {
    try {
      isLoadingNotifier.value = true;
      errorMessageNotifier.value = null;

      // 找到对应的剧本行
      final scriptLine = project.scriptLines.firstWhere(
        (line) => line.id == scriptLineId,
      );

      // 构建最终提示词
      final finalPrompt = _aiService.buildFinalPrompt(
        sceneDescription: scriptLine.aiPrompt,
        involvedEntities: project.entities,
        scriptContent: scriptLine.content,
      );

      // 生成图片
      final imageUrl = await _aiService.generateStoryboardImage(
        prompt: finalPrompt,
      );

      // 创建分镜
      final storyboard = Storyboard(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        scriptLineId: scriptLineId,
        imageUrl: imageUrl,
        finalPrompt: finalPrompt,
      );

      addStoryboard(storyboard);
    } catch (e) {
      errorMessageNotifier.value = '分镜生成失败：$e';
    } finally {
      isLoadingNotifier.value = false;
    }
  }

  /// 添加分镜
  void addStoryboard(Storyboard storyboard) {
    final storyboards = List<Storyboard>.from(project.storyboards)
      ..add(storyboard);
    updateProject(project.copyWith(storyboards: storyboards));
  }

  /// 更新分镜
  void updateStoryboard(String id, Storyboard updatedStoryboard) {
    final storyboards = project.storyboards.map((sb) {
      return sb.id == id ? updatedStoryboard : sb;
    }).toList();
    updateProject(project.copyWith(storyboards: storyboards));
  }

  /// 确认分镜
  void confirmStoryboard(String id) {
    final storyboard = project.storyboards.firstWhere((sb) => sb.id == id);
    updateStoryboard(id, storyboard.copyWith(isConfirmed: true));
  }

  /// 🔥 批量生成所有分镜图片
  Future<void> batchGenerateAllStoryboardImages() async {
    try {
      isLoadingNotifier.value = true;
      errorMessageNotifier.value = null;
      
      int successCount = 0;
      int failCount = 0;
      
      // 找出所有还没有图片的剧本行
      final scriptLinesToGenerate = project.scriptLines.where((line) {
        final hasImage = project.storyboards.any(
          (sb) => sb.scriptLineId == line.id && sb.imageUrl.isNotEmpty,
        );
        return !hasImage;
      }).toList();
      
      if (scriptLinesToGenerate.isEmpty) {
        errorMessageNotifier.value = '所有分镜都已生成图片';
        return;
      }
      
      // 并发生成所有图片（限制并发数为 3）
      for (int i = 0; i < scriptLinesToGenerate.length; i += 3) {
        final batch = scriptLinesToGenerate.skip(i).take(3).toList();
        final futures = batch.map((line) async {
          try {
            await generateStoryboard(line.id);
            successCount++;
          } catch (e) {
            failCount++;
            debugPrint('生成分镜失败 [${line.id}]: $e');
          }
        });
        await Future.wait(futures);
      }
      
      errorMessageNotifier.value = '批量生成完成：成功 $successCount 个，失败 $failCount 个';
    } catch (e) {
      errorMessageNotifier.value = '批量生成失败：$e';
    } finally {
      isLoadingNotifier.value = false;
    }
  }

  /// 🔥 批量生成所有分镜视频
  Future<void> batchGenerateAllStoryboardVideos() async {
    try {
      isLoadingNotifier.value = true;
      errorMessageNotifier.value = null;
      
      int successCount = 0;
      int failCount = 0;
      
      // 找出所有已确认的分镜（有图片）但还没有视频的
      final storyboardsToGenerate = project.storyboards.where((sb) {
        final hasVideo = project.videoClips.any(
          (clip) => clip.storyboardId == sb.id,
        );
        return sb.imageUrl.isNotEmpty && !hasVideo;
      }).toList();
      
      if (storyboardsToGenerate.isEmpty) {
        errorMessageNotifier.value = '没有可生成视频的分镜（需要先生成图片）';
        return;
      }
      
      // 并发生成所有视频（限制并发数为 2，因为视频生成较慢）
      for (int i = 0; i < storyboardsToGenerate.length; i += 2) {
        final batch = storyboardsToGenerate.skip(i).take(2).toList();
        final futures = batch.map((sb) async {
          try {
            await generateVideoClip(
              storyboardId: sb.id,
              mode: VideoGenerationMode.imageToVideo,
            );
            successCount++;
          } catch (e) {
            failCount++;
            debugPrint('生成视频失败 [${sb.id}]: $e');
          }
        });
        await Future.wait(futures);
      }
      
      errorMessageNotifier.value = '批量生成完成：成功 $successCount 个，失败 $failCount 个';
    } catch (e) {
      errorMessageNotifier.value = '批量生成失败：$e';
    } finally {
      isLoadingNotifier.value = false;
    }
  }

  // ==================== 第4步：视频生成 ====================

  /// 生成视频片段
  Future<void> generateVideoClip({
    required String storyboardId,
    required VideoGenerationMode mode,
    String? startFrameUrl,
    String? endFrameUrl,
  }) async {
    try {
      isLoadingNotifier.value = true;
      errorMessageNotifier.value = null;

      // 找到对应的分镜
      final storyboard = project.storyboards.firstWhere(
        (sb) => sb.id == storyboardId,
      );

      // 生成视频
      final videoUrl = await _aiService.generateVideoClip(
        prompt: storyboard.finalPrompt,
        imageUrl: mode == VideoGenerationMode.imageToVideo 
            ? storyboard.imageUrl 
            : null,
        startFrameUrl: startFrameUrl,
        endFrameUrl: endFrameUrl,
      );

      // 创建视频片段
      final videoClip = VideoClip(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        storyboardId: storyboardId,
        videoUrl: videoUrl,
        generationMode: mode,
        startFrameUrl: startFrameUrl,
        endFrameUrl: endFrameUrl,
        status: VideoClipStatus.completed,
      );

      addVideoClip(videoClip);
    } catch (e) {
      errorMessageNotifier.value = '视频生成失败：$e';
    } finally {
      isLoadingNotifier.value = false;
    }
  }

  /// 添加视频片段
  void addVideoClip(VideoClip clip) {
    final clips = List<VideoClip>.from(project.videoClips)..add(clip);
    updateProject(project.copyWith(videoClips: clips));
  }

  /// 更新视频片段
  void updateVideoClip(String id, VideoClip updatedClip) {
    final clips = project.videoClips.map((clip) {
      return clip.id == id ? updatedClip : clip;
    }).toList();
    updateProject(project.copyWith(videoClips: clips));
  }

  /// 释放资源
  void dispose() {
    projectNotifier.dispose();
    currentStepNotifier.dispose();
    isLoadingNotifier.dispose();
    errorMessageNotifier.dispose();
  }
}
