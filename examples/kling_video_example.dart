import 'dart:io';
import 'package:xinghe_new/services/api/providers/veo_video_service.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';

/// Kling 视频生成完整示例
/// 
/// 展示 Kling 模型的所有功能
void main() async {
  // 配置 API（GeekNow 服务）
  final config = ApiConfig(
    provider: 'GeekNow',  // GeekNow 服务商
    baseUrl: 'https://your-geeknow-api.com',
    apiKey: 'your-geeknow-api-key',
  );

  final service = VeoVideoService(config);
  final helper = VeoVideoHelper(service);

  print('=== Kling 视频生成完整示例 ===\n');

  // 示例1: 基础文生视频
  await example1TextToVideo(helper);

  // 示例2: 5秒短视频
  // await example2ShortVideo(helper);

  // 示例3: 首尾帧 URL 生成
  // await example3FramesFromUrl(helper);

  // 示例4: 视频编辑
  // await example4VideoEdit(helper);

  // 示例5: 高级组合
  // await example5AdvancedCombination(helper);

  // 示例6: 批量生成不同时长
  // await example6MultipleDurations(helper);

  print('\n示例运行完成！');
}

/// 示例1: 基础文生视频
Future<void> example1TextToVideo(VeoVideoHelper helper) async {
  print('【示例1】Kling 基础文生视频');
  print('-' * 70);

  final result = await helper.klingTextToVideo(
    prompt: '猫咪带着耳机听着歌走路，摇晃脑袋，大雨落下',
    size: '720x1280',
    seconds: 10,
  );

  if (result.isSuccess) {
    final taskId = result.data!.first.videoId!;
    print('✅ 任务提交成功: $taskId');

    // 轮询直到完成
    final status = await helper.pollTaskUntilComplete(
      taskId: taskId,
      maxWaitMinutes: 15,
      onProgress: (progress, status) {
        final dots = '.' * (DateTime.now().second % 4);
        stdout.write('\r🔄 状态: [$status] 进度: $progress% $dots    ');
      },
    );

    print('\n');

    if (status.isSuccess && status.data!.hasVideo) {
      print('🎉 视频生成完成！');
      print('   视频URL: ${status.data!.videoUrl}');
      print('   模型: ${status.data!.model}');
      print('   尺寸: ${status.data!.size}');
      print('   时长: ${status.data!.seconds}秒');
    } else {
      print('❌ 生成失败: ${status.errorMessage}');
    }
  } else {
    print('❌ 提交失败: ${result.errorMessage}');
  }

  print('');
}

/// 示例2: 5秒短视频
Future<void> example2ShortVideo(VeoVideoHelper helper) async {
  print('【示例2】Kling 5秒短视频');
  print('-' * 70);

  // Kling 特色：支持 5 秒短视频
  final result = await helper.klingTextToVideo(
    prompt: '产品展示，360度旋转特写',
    size: '720x1280',
    seconds: 5,  // 5 秒版本，生成更快
  );

  if (result.isSuccess) {
    final taskId = result.data!.first.videoId!;
    print('✅ 5秒视频任务已提交: $taskId');

    final status = await helper.pollTaskUntilComplete(taskId: taskId);

    if (status.isSuccess && status.data!.hasVideo) {
      print('✅ 5秒视频完成: ${status.data!.videoUrl}');
    }
  }

  print('');
}

/// 示例3: 首尾帧 URL 生成
Future<void> example3FramesFromUrl(VeoVideoHelper helper) async {
  print('【示例3】Kling 首尾帧 URL 生成');
  print('-' * 70);

  // ⚠️ 注意：Kling 使用 URL，不是文件路径
  final result = await helper.klingImageToVideoByUrl(
    prompt: '从白天到夜晚的平滑过渡，延时摄影效果',
    firstFrameUrl: 'https://ark-project.tos-cn-beijing.volces.com/doc_image/seepro_first_frame.jpeg',
    lastFrameUrl: 'https://ark-project.tos-cn-beijing.volces.com/doc_image/seepro_last_frame.jpeg',
    size: '1280x720',  // 横屏
    seconds: 10,
  );

  if (result.isSuccess) {
    final taskId = result.data!.first.videoId!;
    print('✅ 首尾帧视频任务已提交: $taskId');

    final status = await helper.pollTaskUntilComplete(
      taskId: taskId,
      onProgress: (progress, status) {
        print('首尾帧生成进度: $progress%');
      },
    );

    if (status.isSuccess && status.data!.hasVideo) {
      print('✅ 过渡视频完成: ${status.data!.videoUrl}');
    }
  }

  print('');
}

/// 示例4: 视频编辑
Future<void> example4VideoEdit(VeoVideoHelper helper) async {
  print('【示例4】Kling 视频编辑');
  print('-' * 70);

  // 编辑现有视频
  final originalVideoUrl = 'https://example.com/original-video.mp4';

  final editTasks = [
    '添加黑白滤镜，增加电影颗粒感',
    '增强色彩饱和度，鲜艳效果',
    '添加慢动作效果，放慢50%',
    '转换成卡通风格，手绘质感',
  ];

  for (var i = 0; i < editTasks.length; i++) {
    final prompt = editTasks[i];
    print('编辑${i + 1}: $prompt');

    final result = await helper.klingEditVideo(
      prompt: prompt,
      videoUrl: originalVideoUrl,
      size: '720x1280',
      seconds: 10,
    );

    if (result.isSuccess) {
      final taskId = result.data!.first.videoId!;

      final status = await helper.pollTaskUntilComplete(
        taskId: taskId,
        onProgress: (progress, status) {
          stdout.write('\r  进度: $progress%    ');
        },
      );

      print('');

      if (status.isSuccess && status.data!.hasVideo) {
        print('  ✓ 完成: ${status.data!.videoUrl}');
      } else {
        print('  ✗ 失败');
      }
    }
  }

  print('');
}

/// 示例5: 高级组合（参考图 + 首尾帧）
Future<void> example5AdvancedCombination(VeoVideoHelper helper) async {
  print('【示例5】Kling 高级组合');
  print('-' * 70);

  // 组合本地参考图和在线首尾帧
  final result = await helper.klingAdvancedGeneration(
    prompt: '融合参考图的艺术风格，从日出到日落的优雅渐变',
    referenceImagePaths: [
      '/path/to/style_reference1.jpg',  // 风格参考1（本地文件）
      '/path/to/style_reference2.jpg',  // 风格参考2（本地文件）
    ],
    firstFrameUrl: 'https://example.com/sunrise.jpg',  // 首帧（在线URL）
    lastFrameUrl: 'https://example.com/sunset.jpg',    // 尾帧（在线URL）
    size: '1280x720',
    seconds: 10,
  );

  if (result.isSuccess) {
    final taskId = result.data!.first.videoId!;
    print('✅ 高级组合任务已提交: $taskId');

    final status = await helper.pollTaskUntilComplete(taskId: taskId);

    if (status.isSuccess && status.data!.hasVideo) {
      print('✅ 组合视频完成: ${status.data!.videoUrl}');
    }
  }

  print('');
}

/// 示例6: 批量生成不同时长版本
Future<void> example6MultipleDurations(VeoVideoHelper helper) async {
  print('【示例6】批量生成不同时长版本');
  print('-' * 70);

  final prompt = '城市夜景，霓虹灯闪烁，车流穿梭';
  final durations = [5, 10];  // Kling 支持的时长

  for (final duration in durations) {
    print('生成${duration}秒版本...');

    final result = await helper.klingTextToVideo(
      prompt: prompt,
      size: '720x1280',
      seconds: duration,
    );

    if (result.isSuccess) {
      final taskId = result.data!.first.videoId!;

      final status = await helper.pollTaskUntilComplete(
        taskId: taskId,
        onProgress: (progress, status) {
          stdout.write('\r  [${duration}秒] 进度: $progress%    ');
        },
      );

      print('');

      if (status.isSuccess && status.data!.hasVideo) {
        print('  ✓ ${duration}秒版本: ${status.data!.videoUrl}');
      }
    }
  }

  print('');
}

/// Kling 模型特性说明
void klingFeatures() {
  print('''
=== Kling 模型特性 ===

1. 时长灵活性:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Kling: 5 秒或 10 秒
VEO:   固定 8 秒
Sora:  10 秒或 15 秒

使用场景:
- 5秒: 快速预览、短视频、产品展示
- 10秒: 完整叙述、场景展示
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

2. 首尾帧 URL 支持:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
VEO/Sora:  使用本地文件路径
           referenceImagePaths: ['/path/to/image.jpg']

Kling:     使用在线 URL
           first_frame_image: 'https://example.com/first.jpg'
           last_frame_image: 'https://example.com/last.jpg'

优势:
- 无需下载图片到本地
- 直接使用 CDN 资源
- 更快更方便
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

3. 视频编辑功能:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Kling:     在生成 API 中直接支持
           video: 'https://example.com/video.mp4'

VEO/Sora:  使用专门的 remix API
           /v1/videos/{id}/remix

区别:
- Kling 使用视频 URL
- VEO/Sora 使用任务 ID
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

4. 多图参考:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
所有模型都支持 input_reference 参数
Kling 可以同时使用:
- input_reference (参考图文件)
- first_frame_image (首帧 URL)
- last_frame_image (尾帧 URL)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''');
}

/// 参数使用对比
void parameterComparison() {
  print('''
=== Kling 参数使用示例 ===

1. 文生视频（最简单）:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
await helper.klingTextToVideo(
  prompt: '猫咪走路',
  size: '720x1280',
  seconds: 10,  // 或 5
);
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

2. 首帧图片生成:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
await helper.klingImageToVideoByUrl(
  prompt: '画面动起来',
  firstFrameUrl: 'https://example.com/photo.jpg',
  seconds: 10,
);
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

3. 首尾帧过渡:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
await helper.klingImageToVideoByUrl(
  prompt: '平滑过渡',
  firstFrameUrl: 'https://example.com/start.jpg',
  lastFrameUrl: 'https://example.com/end.jpg',
  seconds: 10,
);
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

4. 视频编辑:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
await helper.klingEditVideo(
  prompt: '添加黑白滤镜',
  videoUrl: 'https://example.com/video.mp4',
  seconds: 10,
);
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

5. 高级组合:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
await helper.klingAdvancedGeneration(
  prompt: '融合风格，平滑过渡',
  referenceImagePaths: ['/path/ref.jpg'],  // 风格参考（文件）
  firstFrameUrl: 'https://example.com/first.jpg',  // 首帧（URL）
  lastFrameUrl: 'https://example.com/last.jpg',    // 尾帧（URL）
  seconds: 10,
);
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''');
}

/// 实际应用场景示例
void realWorldScenarios() {
  print('''
=== Kling 实际应用场景 ===

场景1: 社交媒体短视频
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 5秒快速生成，适合抖音、Instagram Stories
await helper.klingTextToVideo(
  prompt: '产品亮点展示，快速剪辑',
  seconds: 5,
);
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

场景2: 照片转视频
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 使用已有的 CDN 图片
await helper.klingImageToVideoByUrl(
  prompt: '照片动起来，轻微缩放和移动',
  firstFrameUrl: 'https://cdn.example.com/photo.jpg',
  seconds: 5,
);
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

场景3: 视频后期处理
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 给已有视频添加效果
await helper.klingEditVideo(
  prompt: '添加复古胶片效果，暗角，颗粒感',
  videoUrl: 'https://storage.example.com/raw-video.mp4',
  seconds: 10,
);
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

场景4: 时间轴视频
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 日出到日落的时间流逝
await helper.klingImageToVideoByUrl(
  prompt: '时间流逝，光线变化，云朵移动',
  firstFrameUrl: 'https://example.com/6am.jpg',
  lastFrameUrl: 'https://example.com/6pm.jpg',
  seconds: 10,
);
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''');
}

/// 模型选择指南
void modelSelectionGuide() {
  print('''
=== 何时使用哪个模型？ ===

选择 Kling (kling-video-o1):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ 需要 5 秒短视频
✅ 已有在线图片 URL（首尾帧）
✅ 需要编辑现有视频
✅ 快速生成和迭代
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

选择 VEO (veo_3_1):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ 需要固定 8 秒视频
✅ 需要高清模式（横屏）
✅ Google 生态集成
✅ 4K 超清输出
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

选择 Sora (sora-2):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ 需要角色引用功能
✅ 需要 10-15 秒长视频
✅ 需要角色一致性
✅ OpenAI 生态集成
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

混合使用策略:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. 原型测试: Kling (5秒，快速)
2. 预览确认: VEO/Sora (标准质量)
3. 最终输出: VEO 4K (专业品质)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''');
}

/// 错误处理最佳实践
Future<void> errorHandlingBestPractices(VeoVideoHelper helper) async {
  print('=== 错误处理最佳实践 ===\n');

  try {
    final result = await helper.klingTextToVideo(
      prompt: '测试视频',
      seconds: 10,
    );

    if (!result.isSuccess) {
      print('❌ 任务提交失败');
      print('   错误: ${result.errorMessage}');
      print('   状态码: ${result.statusCode}');

      // 根据错误码采取不同措施
      switch (result.statusCode) {
        case 400:
          print('   → 检查参数是否正确');
          print('   → seconds 必须是 5 或 10');
          break;
        case 401:
          print('   → 检查 API Key 是否有效');
          break;
        case 429:
          print('   → 请求过于频繁，稍后重试');
          break;
        case 500:
          print('   → 服务器错误，联系技术支持');
          break;
      }
      return;
    }

    final taskId = result.data!.first.videoId!;
    print('✅ 任务提交成功: $taskId');

    // 轮询状态
    final status = await helper.pollTaskUntilComplete(
      taskId: taskId,
      maxWaitMinutes: 15,
    );

    if (status.isSuccess) {
      if (status.data!.hasVideo) {
        print('✅ 视频生成成功: ${status.data!.videoUrl}');
      } else {
        print('⚠️ 任务完成但无视频URL');
        print('   状态: ${status.data!.status}');
        print('   完整数据: ${status.data!.metadata}');
      }
    } else {
      print('❌ 轮询失败: ${status.errorMessage}');
    }
  } catch (e, stackTrace) {
    print('💥 异常: $e');
    print('堆栈: $stackTrace');
  }
}
