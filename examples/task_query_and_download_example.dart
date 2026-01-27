import 'dart:io';
import 'package:xinghe_new/services/api/providers/veo_video_service.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';

/// 任务查询和视频下载示例
/// 
/// 对应 Python 查询任务代码的 Dart 实现
void main() async {
  // ================= 配置区 =================
  // ⚠️ 记得填入你的 API Key
  const apiKey = 'YOUR_API_KEY';
  
  // 这是你刚刚生成的任务 ID
  const taskId = 'video_4f573cf0-b4ed-405c-8900-b39a416ef60a';
  const baseUrl = 'https://xxxx';
  // =========================================

  final config = ApiConfig(
    provider: 'GeekNow',
    baseUrl: baseUrl,
    apiKey: apiKey,
  );

  final service = VeoVideoService(config);
  final helper = VeoVideoHelper(service);

  print('=== 任务查询和下载示例 ===\n');

  // 示例1: 自动轮询和下载（推荐）
  await example1AutoPollAndDownload(helper, taskId);

  // 示例2: 手动查询状态
  // await example2ManualQuery(service, taskId);

  // 示例3: 带进度显示的轮询
  // await example3PollWithProgress(helper, taskId);
}

/// 示例1: 自动轮询和下载（推荐方式）
/// 
/// 对应 Python 代码的完整流程
Future<void> example1AutoPollAndDownload(
  VeoVideoHelper helper,
  String taskId,
) async {
  print('【示例1】自动轮询和下载');
  print('-' * 70);

  print('🕵️‍♂️ 开始追踪任务: $taskId');
  print('☕️ Sora 生成较慢 (预计 2-10 分钟)，请耐心等待...\n');

  // 自动轮询直到完成
  final result = await helper.pollTaskUntilComplete(
    taskId: taskId,
    maxWaitMinutes: 15,  // 最长等待 15 分钟
    onProgress: (progress, status) {
      // 打印进度（对应 Python 的动画效果）
      final dots = '.' * (DateTime.now().second % 4);
      stdout.write('\r🔄 状态: [$status] 进度: $progress% $dots    ');
    },
  );

  // 清除进度行
  print('\n');

  // 处理结果
  if (result.isSuccess) {
    final taskStatus = result.data!;

    // 1. 任务完成
    if (taskStatus.isCompleted && taskStatus.hasVideo) {
      print('🎉 任务完成！');
      print('视频URL: ${taskStatus.videoUrl}');
      print('模型: ${taskStatus.model}');
      print('尺寸: ${taskStatus.size}');
      print('时长: ${taskStatus.seconds}秒');

      // 下载视频
      await downloadVideo(
        taskStatus.videoUrl!,
        'sora_${taskId.substring(0, 8)}.mp4',
      );
    }
    // 2. 任务失败
    else if (taskStatus.isFailed) {
      print('❌ 生成失败');
      print('原因: ${taskStatus.errorMessage ?? "未知错误"}');
      print('完整数据: ${taskStatus.metadata}');
    }
    // 3. 虽然返回成功但没有视频
    else {
      print('⚠️ 虽显示完成，但没找到视频链接');
      print('状态: ${taskStatus.status}');
      print('完整返回: ${taskStatus.metadata}');
    }
  } else {
    print('❌ 查询失败: ${result.errorMessage}');
  }

  print('');
}

/// 示例2: 手动查询状态（不使用轮询）
Future<void> example2ManualQuery(
  VeoVideoService service,
  String taskId,
) async {
  print('【示例2】手动查询状态');
  print('-' * 70);

  final result = await service.getVideoTaskStatus(taskId: taskId);

  if (result.isSuccess) {
    final status = result.data!;
    
    print('任务ID: ${status.id}');
    print('状态: ${status.status}');
    print('进度: ${status.progress}%');
    print('模型: ${status.model}');
    
    if (status.hasVideo) {
      print('视频URL: ${status.videoUrl}');
    }
    
    if (status.isFailed) {
      print('失败原因: ${status.errorMessage}');
    }
  } else {
    // 处理 404 等错误
    if (result.statusCode == 404) {
      print('...暂时未查到任务信息（可能是数据同步延迟）');
    } else {
      print('查询接口返回异常: ${result.statusCode} - ${result.errorMessage}');
    }
  }

  print('');
}

/// 示例3: 带详细进度显示的轮询
Future<void> example3PollWithProgress(
  VeoVideoHelper helper,
  String taskId,
) async {
  print('【示例3】带详细进度显示的轮询');
  print('-' * 70);

  var lastProgress = -1;
  var startTime = DateTime.now();

  final result = await helper.pollTaskUntilComplete(
    taskId: taskId,
    maxWaitMinutes: 15,
    onProgress: (progress, status) {
      // 只在进度变化时打印
      if (progress != lastProgress) {
        final elapsed = DateTime.now().difference(startTime);
        final minutes = elapsed.inMinutes;
        final seconds = elapsed.inSeconds % 60;
        
        print('[$minutes:${seconds.toString().padLeft(2, '0')}] '
              '进度: $progress% | 状态: $status');
        
        lastProgress = progress;
        
        // 估算剩余时间（简单线性估算）
        if (progress > 0) {
          final totalEstimated = elapsed.inSeconds * 100 ~/ progress;
          final remaining = totalEstimated - elapsed.inSeconds;
          print('       预计剩余: ${remaining ~/ 60}分${remaining % 60}秒');
        }
      }
    },
  );

  if (result.isSuccess && result.data!.hasVideo) {
    final elapsed = DateTime.now().difference(startTime);
    print('\n✅ 任务完成！总耗时: ${elapsed.inMinutes}分${elapsed.inSeconds % 60}秒');
    print('视频: ${result.data!.videoUrl}');
  }

  print('');
}

/// 下载视频到本地
/// 
/// 对应 Python 的 download_video 函数
Future<void> downloadVideo(String url, String filename) async {
  print('\n📥 正在下载视频...');

  try {
    // 流式下载（对应 Python 的 stream=True）
    final request = await HttpClient().getUrl(Uri.parse(url));
    final response = await request.close();

    if (response.statusCode != 200) {
      throw Exception('下载失败: HTTP ${response.statusCode}');
    }

    final file = File(filename);
    final sink = file.openWrite();

    // 流式写入文件（对应 Python 的 iter_content）
    var downloadedBytes = 0;
    final totalBytes = response.contentLength;

    await for (final chunk in response) {
      sink.add(chunk);
      downloadedBytes += chunk.length;

      // 显示下载进度
      if (totalBytes > 0) {
        final progress = (downloadedBytes / totalBytes * 100).toStringAsFixed(1);
        stdout.write('\r下载进度: $progress%    ');
      }
    }

    await sink.close();

    print('\n✅ 视频已保存至: ${file.absolute.path}');
  } catch (e) {
    print('❌ 下载失败: $e');
    print('视频链接是: $url');
  }
}

/// Python vs Dart 实现对比
void comparisonNotes() {
  print('''
=== Python vs Dart 任务查询对比 ===

Python 实现:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
while True:
    response = requests.get(query_url, headers=headers)
    
    # 处理 404
    if response.status_code == 404:
        print("...暂时未查到任务信息，继续等待...")
        time.sleep(5)
        continue
    
    data = response.json()
    status = data.get("status")
    progress = data.get("progress", 0)
    
    # 兼容多种字段名
    video_url = data.get("url") or data.get("output") or data.get("video_url")
    if not video_url and "data" in data:
        video_url = data["data"].get("url")
    
    if status == "completed":
        download_video(video_url)
        break
    
    time.sleep(5)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Dart 实现（等效）:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 自动轮询（已内置所有逻辑）
final result = await helper.pollTaskUntilComplete(
  taskId: taskId,
  maxWaitMinutes: 15,
  onProgress: (progress, status) {
    print('进度: \$progress%, 状态: \$status');
  },
);

// 自动处理：
// ✅ 404 错误重试（数据同步延迟）
// ✅ 多字段名兼容（url, output, video_url, data.url）
// ✅ 状态判断（completed, failed, cancelled）
// ✅ 进度显示

if (result.isSuccess && result.data!.hasVideo) {
  await downloadVideo(result.data!.videoUrl!, 'video.mp4');
}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

关键差异:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. 轮询逻辑:
   Python: 手动 while True + time.sleep(5)
   Dart:   自动 pollTaskUntilComplete()

2. 404 处理:
   Python: 手动 if response.status_code == 404: continue
   Dart:   自动在 pollTaskUntilComplete 中处理

3. 字段兼容:
   Python: or 链式检查
   Dart:   ?? 空值合并运算符（已在 fromJson 中处理）

4. 进度显示:
   Python: print("\\r...", end="")
   Dart:   onProgress 回调

5. 代码量:
   Python: ~80 行
   Dart:   ~20 行（减少 75%）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''');
}

/// 高级示例：并发查询多个任务
Future<void> concurrentTasksExample(VeoVideoHelper helper) async {
  print('=== 并发查询多个任务 ===\n');

  final taskIds = [
    'video_task_1',
    'video_task_2',
    'video_task_3',
  ];

  print('同时查询 ${taskIds.length} 个任务...\n');

  // 并发轮询所有任务
  final futures = taskIds.map((taskId) async {
    print('开始轮询: $taskId');
    
    final result = await helper.pollTaskUntilComplete(
      taskId: taskId,
      maxWaitMinutes: 15,
      onProgress: (progress, status) {
        print('  [$taskId] $progress% - $status');
      },
    );

    if (result.isSuccess && result.data!.hasVideo) {
      print('✓ $taskId 完成: ${result.data!.videoUrl}');
      return result.data!.videoUrl;
    } else {
      print('✗ $taskId 失败');
      return null;
    }
  });

  final results = await Future.wait(futures);

  print('\n结果汇总:');
  for (var i = 0; i < taskIds.length; i++) {
    print('${i + 1}. ${taskIds[i]}: ${results[i] ?? "失败"}');
  }
}

/// 错误处理示例
Future<void> errorHandlingExample(VeoVideoService service) async {
  print('=== 错误处理示例 ===\n');

  const taskId = 'test_task_id';

  final result = await service.getVideoTaskStatus(taskId: taskId);

  if (result.isSuccess) {
    final status = result.data!;

    print('任务状态: ${status.status}');

    // 检查各种状态
    if (status.isCompleted) {
      print('✅ 任务已完成');
      
      if (status.hasVideo) {
        print('   视频URL: ${status.videoUrl}');
      } else {
        print('   ⚠️ 完成但无视频URL');
      }
    } else if (status.isFailed) {
      print('❌ 任务失败');
      print('   错误: ${status.errorMessage}');
      
      // 访问详细错误信息
      if (status.error != null) {
        print('   错误代码: ${status.error!.code}');
        print('   错误消息: ${status.error!.message}');
      }
    } else if (status.isProcessing) {
      print('🔄 任务处理中');
      print('   进度: ${status.progress}%');
    } else if (status.isCancelled) {
      print('🚫 任务已取消');
    }

    // 访问时间戳信息
    if (status.createdAt != null) {
      final created = DateTime.fromMillisecondsSinceEpoch(
        status.createdAt! * 1000,
      );
      print('创建时间: $created');
    }

    if (status.completedAt != null) {
      final completed = DateTime.fromMillisecondsSinceEpoch(
        status.completedAt! * 1000,
      );
      print('完成时间: $completed');
      
      if (status.createdAt != null) {
        final duration = completed.difference(
          DateTime.fromMillisecondsSinceEpoch(status.createdAt! * 1000),
        );
        print('耗时: ${duration.inMinutes}分${duration.inSeconds % 60}秒');
      }
    }
  } else {
    // 处理查询失败
    print('查询失败:');
    print('  状态码: ${result.statusCode}');
    print('  错误: ${result.errorMessage}');

    switch (result.statusCode) {
      case 404:
        print('  → 任务未找到（可能是数据同步延迟，请稍后重试）');
        break;
      case 401:
        print('  → API Key 无效');
        break;
      case 429:
        print('  → 请求过于频繁');
        break;
      case 500:
        print('  → 服务器错误');
        break;
    }
  }

  print('');
}

/// 带重试的任务查询
Future<void> queryWithRetry(
  VeoVideoService service,
  String taskId, {
  int maxRetries = 3,
}) async {
  print('=== 带重试的任务查询 ===\n');

  for (var i = 0; i < maxRetries; i++) {
    print('尝试 ${i + 1}/$maxRetries...');

    final result = await service.getVideoTaskStatus(taskId: taskId);

    if (result.isSuccess) {
      print('✅ 查询成功');
      print('状态: ${result.data!.status}');
      return;
    }

    // 404 可能是同步延迟，继续重试
    if (result.statusCode == 404 && i < maxRetries - 1) {
      print('暂时未查到，5秒后重试...');
      await Future.delayed(Duration(seconds: 5));
      continue;
    }

    print('❌ 查询失败: ${result.errorMessage}');
    break;
  }

  print('');
}

/// 完整的生成和查询流程
Future<void> completeWorkflow() async {
  print('=== 完整工作流程 ===\n');

  final config = ApiConfig(
    provider: 'GeekNow',
    baseUrl: 'https://xxxx',
    apiKey: 'your-api-key',
  );

  final service = VeoVideoService(config);
  final helper = VeoVideoHelper(service);

  // 步骤1: 提交生成任务
  print('步骤1: 提交视频生成任务');
  final submitResult = await service.generateVideos(
    prompt: '猫咪带着耳机听着歌走路，摇晃脑袋，大雨落下',
    model: VeoModel.klingO1,
    ratio: '720x1280',
    parameters: {'seconds': 10},
  );

  if (!submitResult.isSuccess) {
    print('❌ 提交失败: ${submitResult.errorMessage}');
    return;
  }

  final taskId = submitResult.data!.first.videoId!;
  print('✅ 任务已提交: $taskId\n');

  // 步骤2: 轮询任务状态
  print('步骤2: 轮询任务状态');
  final statusResult = await helper.pollTaskUntilComplete(
    taskId: taskId,
    maxWaitMinutes: 15,
    onProgress: (progress, status) {
      print('进度: $progress%, 状态: $status');
    },
  );

  if (!statusResult.isSuccess || !statusResult.data!.hasVideo) {
    print('❌ 任务失败或无视频');
    return;
  }

  print('✅ 视频生成完成\n');

  // 步骤3: 下载视频
  print('步骤3: 下载视频');
  await downloadVideo(
    statusResult.data!.videoUrl!,
    'output_video.mp4',
  );

  print('\n🎉 完整流程完成！');
}

/// 实现细节说明
void implementationDetails() {
  print('''
=== Dart 实现的关键技术点 ===

1. 自动 404 重试（pollTaskUntilComplete 内部）:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if (!result.isSuccess) {
  // 404 可能是数据同步延迟，继续等待
  if (result.statusCode == 404 && i < 3) {
    await Future.delayed(Duration(seconds: 5));
    continue;  // 重试
  }
  return result;
}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

2. 多字段名兼容（VeoTaskStatus.fromJson 内部）:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
final url = json['video_url'] as String? ??
    json['url'] as String? ??
    json['output'] as String? ??
    (json['data'] as Map<String, dynamic>?)?['url'] as String?;

// 对应 Python 代码:
// video_url = data.get("url") or data.get("output") or data.get("video_url")
// if not video_url and "data" in data:
//     video_url = data["data"].get("url")
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

3. 状态判断（VeoTaskStatus 便捷属性）:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
bool get isCompleted => status == 'completed';
bool get isFailed => status == 'failed';
bool get isCancelled => status == 'cancelled';
bool get isProcessing => status == 'processing' || status == 'queued';
bool get hasVideo => isCompleted && videoUrl != null && videoUrl!.isNotEmpty;

// 使用更简单:
if (result.data!.hasVideo) { ... }

// vs Python:
if data['status'] == 'completed' and data.get('video_url'):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

4. 流式下载:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Python:
  with requests.get(url, stream=True) as r:
      for chunk in r.iter_content(chunk_size=8192):
          f.write(chunk)

Dart:
  await for (final chunk in response) {
    sink.add(chunk);
  }
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''');
}
