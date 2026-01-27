import 'package:xinghe_new/services/api/providers/veo_video_service.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';

/// 豆包(Doubao)视频生成完整示例
void main() async {
  // 配置 API（GeekNow 服务）
  final config = ApiConfig(
    provider: 'GeekNow',  // GeekNow 服务商
    baseUrl: 'https://your-geeknow-api.com',
    apiKey: 'your-geeknow-api-key',
  );

  final service = VeoVideoService(config);
  final helper = VeoVideoHelper(service);

  print('=== 豆包视频生成完整示例 ===\n');

  // 示例1: 基础文生视频
  await example1BasicTextToVideo(helper);

  // 示例2: 多分辨率对比
  // await example2MultipleResolutions(helper);

  // 示例3: 智能宽高比
  // await example3SmartAspectRatio(helper);

  // 示例4: 灵活时长测试
  // await example4FlexibleDuration(helper);

  // 示例5: 不同平台适配
  // await example5PlatformOptimization(helper);

  // 示例6: 成本优化策略
  // await example6CostOptimization(helper);

  print('\n示例运行完成！');
}

/// 示例1: 基础文生视频
Future<void> example1BasicTextToVideo(VeoVideoHelper helper) async {
  print('【示例1】豆包基础文生视频');
  print('-' * 70);

  final result = await helper.doubaoTextToVideo(
    prompt: '猫咪听歌摇头晃脑，下大雨',
    resolution: DoubaoResolution.p720,  // 720p 高清
    aspectRatio: '16:9',  // 横屏
    seconds: 6,  // 6 秒
  );

  if (result.isSuccess) {
    final taskId = result.data!.first.videoId!;
    print('✅ 任务提交成功: $taskId');

    final status = await helper.pollTaskUntilComplete(
      taskId: taskId,
      maxWaitMinutes: 15,
      onProgress: (progress, status) {
        print('豆包生成进度: $progress%');
      },
    );

    if (status.isSuccess && status.data!.hasVideo) {
      print('\n🎉 视频生成完成！');
      print('   视频URL: ${status.data!.videoUrl}');
      print('   模型: ${status.data!.model}');
      print('   尺寸: ${status.data!.size}');
      print('   时长: ${status.data!.seconds}秒');
    }
  } else {
    print('❌ 提交失败: ${result.errorMessage}');
  }

  print('');
}

/// 示例2: 多分辨率对比
Future<void> example2MultipleResolutions(VeoVideoHelper helper) async {
  print('【示例2】豆包多分辨率对比');
  print('-' * 70);

  final prompt = '城市夜景，霓虹灯闪烁';
  
  // 测试三种分辨率
  final resolutions = {
    DoubaoResolution.p480: '480p标清',
    DoubaoResolution.p720: '720p高清',
    DoubaoResolution.p1080: '1080p超清',
  };

  for (final entry in resolutions.entries) {
    final resolution = entry.key;
    final name = entry.value;
    
    print('生成$name版本...');

    final result = await helper.doubaoTextToVideo(
      prompt: prompt,
      resolution: resolution,
      aspectRatio: '16:9',
      seconds: 6,
    );

    if (result.isSuccess) {
      final taskId = result.data!.first.videoId!;
      print('  ✓ $name 任务已提交: $taskId');
      
      // 可以并发等待所有任务完成
      // 这里为了演示简化，顺序处理
    } else {
      print('  ✗ $name 提交失败');
    }
  }

  print('');
}

/// 示例3: 智能宽高比
Future<void> example3SmartAspectRatio(VeoVideoHelper helper) async {
  print('【示例3】豆包智能宽高比');
  print('-' * 70);

  // 场景1: keep_ratio - 保持图片原始比例
  print('场景1: 保持原始比例');
  final result1 = await helper.doubaoImageToVideo(
    prompt: '照片动起来，轻微缩放和移动',
    firstFrameImage: 'https://example.com/landscape-photo.jpg',
    resolution: DoubaoResolution.p720,
    aspectRatio: DoubaoAspectRatio.keepRatio,  // 保持原始比例
    seconds: 6,
  );

  if (result1.isSuccess) {
    print('  ✓ 保持原始比例视频已提交');
  }

  // 场景2: adaptive - 自动选择最佳比例
  print('\n场景2: 自动选择最佳比例');
  final result2 = await helper.doubaoImageToVideo(
    prompt: '智能优化比例，动态效果',
    firstFrameImage: 'https://example.com/portrait-photo.jpg',
    resolution: DoubaoResolution.p720,
    aspectRatio: DoubaoAspectRatio.adaptive,  // 智能选择
    seconds: 6,
  );

  if (result2.isSuccess) {
    print('  ✓ 智能比例视频已提交');
  }

  print('');
}

/// 示例4: 灵活时长测试
Future<void> example4FlexibleDuration(VeoVideoHelper helper) async {
  print('【示例4】豆包灵活时长测试');
  print('-' * 70);

  // 豆包支持 4-11 秒的所有整数时长
  final durations = [4, 5, 6, 7, 8, 9, 10, 11];

  print('测试 ${durations.length} 种不同时长...\n');

  for (final duration in durations) {
    final result = await helper.doubaoTextToVideo(
      prompt: '测试${duration}秒时长',
      resolution: DoubaoResolution.p480,  // 使用 480p 快速测试
      aspectRatio: '16:9',
      seconds: duration,
    );

    if (result.isSuccess) {
      print('✓ ${duration}秒版本已提交');
    } else {
      print('✗ ${duration}秒版本提交失败');
    }
  }

  print('');
}

/// 示例5: 不同平台适配
Future<void> example5PlatformOptimization(VeoVideoHelper helper) async {
  print('【示例5】不同平台适配');
  print('-' * 70);

  final prompt = '品牌宣传视频 - 产品展示';

  // 定义不同平台的规格
  final platforms = [
    ('抖音', '9:16', DoubaoResolution.p720, 5),
    ('快手', '9:16', DoubaoResolution.p720, 6),
    ('B站', '16:9', DoubaoResolution.p1080, 10),
    ('YouTube', '16:9', DoubaoResolution.p1080, 10),
    ('Instagram', '1:1', DoubaoResolution.p720, 6),
    ('微信视频号', '9:16', DoubaoResolution.p720, 8),
    ('小红书', '3:4', DoubaoResolution.p720, 5),
  ];

  for (final (platform, ratio, resolution, duration) in platforms) {
    print('生成$platform版本 ($ratio, ${resolution.name}, ${duration}s)...');

    final result = await helper.doubaoTextToVideo(
      prompt: prompt,
      resolution: resolution,
      aspectRatio: ratio,
      seconds: duration,
    );

    if (result.isSuccess) {
      final taskId = result.data!.first.videoId!;
      print('  ✓ 已提交: $taskId');
    } else {
      print('  ✗ 提交失败');
    }
  }

  print('');
}

/// 示例6: 成本优化策略（三阶段）
Future<void> example6CostOptimization(VeoVideoHelper helper) async {
  print('【示例6】成本优化三阶段策略');
  print('-' * 70);

  final prompt = '新产品广告视频';

  // 阶段1: 480p 快速验证（最低成本）
  print('阶段1: 480p 快速验证创意...');
  final stage1 = await helper.doubaoTextToVideo(
    prompt: prompt,
    resolution: DoubaoResolution.p480,  // 480p 标清
    aspectRatio: '16:9',
    seconds: 4,  // 最短时长
  );

  if (!stage1.isSuccess) {
    print('  ✗ 阶段1失败，停止流程');
    return;
  }

  final task1Id = stage1.data!.first.videoId!;
  print('  ✓ 480p 任务已提交: $task1Id');

  final status1 = await helper.pollTaskUntilComplete(taskId: task1Id);

  if (!status1.isSuccess || !status1.data!.hasVideo) {
    print('  ✗ 480p 生成失败');
    return;
  }

  print('  ✅ 480p 完成: ${status1.data!.videoUrl}');
  print('  → 请确认效果是否满意...\n');

  // 模拟用户确认（实际应该等待用户输入）
  final isApproved = true;  // 假设用户满意

  if (!isApproved) {
    print('  用户不满意，停止流程');
    return;
  }

  // 阶段2: 720p 预览确认（中等成本）
  print('阶段2: 720p 高清预览...');
  final stage2 = await helper.doubaoTextToVideo(
    prompt: prompt,
    resolution: DoubaoResolution.p720,  // 720p 高清
    aspectRatio: '16:9',
    seconds: 6,  // 标准时长
  );

  if (stage2.isSuccess) {
    final task2Id = stage2.data!.first.videoId!;
    print('  ✓ 720p 任务已提交: $task2Id');

    final status2 = await helper.pollTaskUntilComplete(taskId: task2Id);

    if (status2.isSuccess && status2.data!.hasVideo) {
      print('  ✅ 720p 完成: ${status2.data!.videoUrl}');
    }
  }

  // 阶段3: 1080p 最终输出（最高成本）
  print('\n阶段3: 1080p 超清最终输出...');
  final stage3 = await helper.doubaoTextToVideo(
    prompt: prompt,
    resolution: DoubaoResolution.p1080,  // 1080p 超清
    aspectRatio: '16:9',
    seconds: 10,  // 完整时长
  );

  if (stage3.isSuccess) {
    final task3Id = stage3.data!.first.videoId!;
    print('  ✓ 1080p 任务已提交: $task3Id');

    final status3 = await helper.pollTaskUntilComplete(taskId: task3Id);

    if (status3.isSuccess && status3.data!.hasVideo) {
      print('  ✅ 1080p 完成: ${status3.data!.videoUrl}');
      print('\n🎉 三阶段优化完成！');
    }
  }

  print('');
}

/// 宽高比使用指南
void aspectRatioGuide() {
  print('''
=== 豆包宽高比使用指南 ===

标准比例适用场景:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
16:9  → 宽屏视频 (B站, YouTube 横屏)
9:16  → 竖屏视频 (抖音, 快手, 视频号)
1:1   → 方形视频 (Instagram 动态)
4:3   → 传统比例 (经典影视)
3:4   → 竖屏传统 (小红书竖屏)
21:9  → 超宽屏 (电影感、沉浸式)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

智能模式:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
keep_ratio → 保持上传图片的原始宽高比
            适合：专业摄影、已有素材
            
adaptive   → 根据图片自动选择最佳比例
            适合：用户上传、未知比例
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

推荐使用:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 明确知道目标平台
aspectRatio: '9:16'  // 明确指定

// 用户上传的图片
aspectRatio: DoubaoAspectRatio.adaptive  // 智能选择

// 保持原图效果
aspectRatio: DoubaoAspectRatio.keepRatio  // 保持原始
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''');
}

/// 分辨率选择指南
void resolutionGuide() {
  print('''
=== 豆包分辨率选择指南 ===

480p 标清版本:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
优势: ✅ 最快速度 ✅ 最低成本
劣势: ❌ 质量较低
适合: 快速测试、原型验证、低质量需求
使用: DoubaoResolution.p480
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

720p 高清版本 (推荐):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
优势: ✅ 性价比最高 ✅ 质量良好 ✅ 速度适中
劣势: -
适合: 日常使用、大部分场景、社交媒体
使用: DoubaoResolution.p720
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1080p 超清版本:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
优势: ✅ 最高质量 ✅ 专业输出
劣势: ❌ 成本最高 ❌ 时间最长
适合: 专业作品、最终输出、高质量需求
使用: DoubaoResolution.p1080
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''');
}

/// 时长选择指南
void durationGuide() {
  print('''
=== 豆包时长选择指南 ===

时长范围: 4-11 秒 (所有模型中最灵活)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
4-5秒  → 快速生成、短视频、产品特写
6-7秒  → 标准时长、平衡选择（推荐）
8-9秒  → 完整叙述、场景展示
10-11秒 → 详细内容、故事叙述

对比其他模型:
VEO:   固定 8 秒
Sora:  10 或 15 秒
Kling: 5 或 10 秒
豆包:  4-11 秒 (最灵活)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''');
}

/// 模型选择决策树
void modelSelectionDecisionTree() {
  print('''
=== 何时选择豆包模型？ ===

✅ 选择豆包 (Doubao):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. 需要灵活的时长（4-11 秒任意选择）
2. 需要多个分辨率版本（480p/720p/1080p）
3. 需要特殊宽高比（如 21:9 超宽屏）
4. 需要智能比例适配（keep_ratio, adaptive）
5. 字节系产品集成
6. 成本敏感（480p 低成本测试）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

选择其他模型的情况:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
VEO   → 需要高清模式(横屏)、4K 输出
Sora  → 需要角色引用、10-15 秒长视频
Kling → 需要 5 秒超短视频、视频编辑功能
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

混合使用策略:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. 原型测试 → 豆包 480p (快速、低成本)
2. 预览确认 → 豆包 720p (高质量预览)
3. 最终输出 → 豆包 1080p 或 VEO 4K (专业品质)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''');
}

/// 完整工作流程示例
Future<void> completeWorkflowExample(VeoVideoHelper helper) async {
  print('=== 完整工作流程示例 ===\n');

  final prompt = '科技产品宣传片 - 未来感设计';

  // 步骤1: 480p 快速验证创意
  print('步骤1: 480p 快速验证...');
  var result = await helper.doubaoTextToVideo(
    prompt: prompt,
    resolution: DoubaoResolution.p480,
    aspectRatio: '16:9',
    seconds: 4,
  );

  if (!result.isSuccess) {
    print('验证失败');
    return;
  }

  var taskId = result.data!.first.videoId!;
  var status = await helper.pollTaskUntilComplete(taskId: taskId);

  if (status.isSuccess && status.data!.hasVideo) {
    print('✓ 480p 完成: ${status.data!.videoUrl}');
    print('→ 确认创意方向\n');
  }

  // 步骤2: 720p 预览
  print('步骤2: 720p 高清预览...');
  result = await helper.doubaoTextToVideo(
    prompt: prompt,
    resolution: DoubaoResolution.p720,
    aspectRatio: '16:9',
    seconds: 8,
  );

  if (result.isSuccess) {
    taskId = result.data!.first.videoId!;
    status = await helper.pollTaskUntilComplete(taskId: taskId);

    if (status.isSuccess && status.data!.hasVideo) {
      print('✓ 720p 完成: ${status.data!.videoUrl}');
      print('→ 客户确认\n');
    }
  }

  // 步骤3: 1080p 最终输出
  print('步骤3: 1080p 超清最终输出...');
  result = await helper.doubaoTextToVideo(
    prompt: prompt,
    resolution: DoubaoResolution.p1080,
    aspectRatio: '16:9',
    seconds: 10,
  );

  if (result.isSuccess) {
    taskId = result.data!.first.videoId!;
    status = await helper.pollTaskUntilComplete(taskId: taskId);

    if (status.isSuccess && status.data!.hasVideo) {
      print('✓ 1080p 完成: ${status.data!.videoUrl}');
      print('\n🎉 完整流程完成！');
    }
  }
}

/// 批量生成不同版本
Future<void> batchGenerationExample(VeoVideoHelper helper) async {
  print('=== 批量生成不同版本 ===\n');

  final prompt = '企业宣传视频';

  // 同时生成多个版本（并发）
  final futures = [
    // 抖音版本
    helper.doubaoTextToVideo(
      prompt: prompt,
      resolution: DoubaoResolution.p720,
      aspectRatio: '9:16',
      seconds: 5,
    ),
    // B站版本
    helper.doubaoTextToVideo(
      prompt: prompt,
      resolution: DoubaoResolution.p1080,
      aspectRatio: '16:9',
      seconds: 10,
    ),
    // Instagram 版本
    helper.doubaoTextToVideo(
      prompt: prompt,
      resolution: DoubaoResolution.p720,
      aspectRatio: '1:1',
      seconds: 6,
    ),
  ];

  final results = await Future.wait(futures);

  print('并发提交完成，开始轮询...');

  for (var i = 0; i < results.length; i++) {
    if (results[i].isSuccess) {
      final taskId = results[i].data!.first.videoId!;
      print('任务${i + 1}: $taskId');
    }
  }
}
