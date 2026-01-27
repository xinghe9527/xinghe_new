import 'package:xinghe_new/services/api/providers/veo_video_service.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';

/// 视频生成完整示例
/// 
/// 对应 Python 代码的 Dart 实现
void main() async {
  // ==========================================
  // ⚠️ 请务必先去重置 Key，然后填入新的！
  // ==========================================
  const apiKey = 'YOUR_API_KEY';
  const baseUrl = 'https://xxxxx';

  // 创建配置（GeekNow 服务）
  final config = ApiConfig(
    provider: 'GeekNow',
    baseUrl: baseUrl,
    apiKey: apiKey,
  );

  // 创建服务实例
  final service = VeoVideoService(config);
  final helper = VeoVideoHelper(service);

  print('=== 视频生成示例 ===\n');

  // 示例1: 使用 Kling 模型生成视频
  await example1KlingGeneration(service, helper);

  // 示例2: 使用 Sora 模型
  // await example2SoraGeneration(service, helper);

  // 示例3: 使用 VEO 模型
  // await example3VeoGeneration(helper);

  print('\n示例运行完成！');
}

/// 示例1: 使用 Kling 模型生成视频
/// 
/// 对应 Python 代码：
/// ```python
/// payload = {
///     "model": "kling-video-o1",
///     "prompt": "猫咪带着耳机听着歌走路，摇晃脑袋，大雨落下",
///     "size": "720x1280",
///     "seconds": 10
/// }
/// ```
Future<void> example1KlingGeneration(
  VeoVideoService service,
  VeoVideoHelper helper,
) async {
  print('【示例1】使用 Kling 模型生成视频');
  print('-' * 60);

  // 1. 提交视频生成任务
  print('🚀 正在以 multipart/form-data 格式提交任务...');
  
  final result = await service.generateVideos(
    prompt: '猫咪带着耳机听着歌走路，摇晃脑袋，大雨落下',
    model: VeoModel.klingO1,  // Kling 模型
    ratio: '720x1280',
    parameters: {
      'seconds': 10,
    },
  );

  // 2. 检查提交结果
  if (!result.isSuccess) {
    print('❌ 提交失败，服务器返回：');
    print('   错误: ${result.errorMessage}');
    print('   状态码: ${result.statusCode}');
    return;
  }

  print('✅ 提交成功！');
  final taskId = result.data!.first.videoId;
  print('   任务ID: $taskId');
  print('   元数据: ${result.data!.first.metadata}');

  // 3. 轮询任务状态直到完成
  print('\n⏳ 开始轮询任务状态...');
  final statusResult = await helper.pollTaskUntilComplete(
    taskId: taskId!,
    maxWaitMinutes: 15,  // Kling 模型可能需要更长时间
    onProgress: (progress, status) {
      print('   📊 进度: $progress%, 状态: $status');
    },
  );

  // 4. 处理最终结果
  if (statusResult.isSuccess && statusResult.data!.hasVideo) {
    print('\n🎉 视频生成完成！');
    print('   视频URL: ${statusResult.data!.videoUrl}');
    print('   模型: ${statusResult.data!.model}');
    print('   尺寸: ${statusResult.data!.size}');
    print('   时长: ${statusResult.data!.seconds}秒');
    
    if (statusResult.data!.createdAt != null) {
      final createdTime = DateTime.fromMillisecondsSinceEpoch(
        statusResult.data!.createdAt! * 1000,
      );
      print('   创建时间: $createdTime');
    }
    
    if (statusResult.data!.completedAt != null) {
      final completedTime = DateTime.fromMillisecondsSinceEpoch(
        statusResult.data!.completedAt! * 1000,
      );
      print('   完成时间: $completedTime');
    }
  } else {
    print('\n❌ 视频生成失败');
    print('   错误: ${statusResult.errorMessage}');
  }

  print('');
}

/// 示例2: 使用 Sora 模型生成视频
Future<void> example2SoraGeneration(
  VeoVideoService service,
  VeoVideoHelper helper,
) async {
  print('【示例2】使用 Sora 模型生成视频');
  print('-' * 60);

  final result = await service.generateVideos(
    prompt: '猫咪带着耳机听着歌走路，摇晃脑袋，大雨落下',
    model: VeoModel.sora2,
    ratio: '720x1280',
    parameters: {
      'seconds': 10,
    },
  );

  if (result.isSuccess) {
    final taskId = result.data!.first.videoId!;
    print('✅ Sora 任务提交成功: $taskId');
    
    // 轮询状态
    final status = await helper.pollTaskUntilComplete(
      taskId: taskId,
      onProgress: (progress, status) {
        print('Sora 进度: $progress%');
      },
    );
    
    if (status.isSuccess && status.data!.hasVideo) {
      print('Sora 视频: ${status.data!.videoUrl}');
    }
  } else {
    print('❌ Sora 提交失败: ${result.errorMessage}');
  }

  print('');
}

/// 示例3: 使用 VEO 模型生成视频
Future<void> example3VeoGeneration(VeoVideoHelper helper) async {
  print('【示例3】使用 VEO 模型生成视频');
  print('-' * 60);

  final result = await helper.textToVideo(
    prompt: '猫咪带着耳机听着歌走路，摇晃脑袋，大雨落下',
    size: '720x1280',
    seconds: 8,  // VEO 只支持 8 秒
    quality: VeoQuality.standard,
    useFast: false,
  );

  if (result.isSuccess) {
    final taskId = result.data!.first.videoId!;
    print('✅ VEO 任务提交成功: $taskId');
    
    // 轮询状态
    final status = await helper.pollTaskUntilComplete(
      taskId: taskId,
      onProgress: (progress, status) {
        print('VEO 进度: $progress%');
      },
    );
    
    if (status.isSuccess && status.data!.hasVideo) {
      print('VEO 视频: ${status.data!.videoUrl}');
    }
  } else {
    print('❌ VEO 提交失败: ${result.errorMessage}');
  }

  print('');
}

/// 关键技术说明示例
void technicalNotes() {
  print('=== 关键技术说明 ===\n');

  print('1. Content-Type 处理:');
  print('   Python: 通过传递空 files 对象强制 multipart/form-data');
  print('   ```python');
  print('   files = {\'placeholder\': (None, \'\')}');
  print('   response = requests.post(url, data=payload, files=files)');
  print('   ```');
  print('');
  print('   Dart: 始终使用 MultipartRequest');
  print('   ```dart');
  print('   var request = http.MultipartRequest(\'POST\', uri);');
  print('   request.fields[\'model\'] = model;');
  print('   request.fields[\'prompt\'] = prompt;');
  print('   // 即使没有文件，也是 multipart/form-data 格式');
  print('   ```');
  print('');

  print('2. 异步任务处理:');
  print('   - API 返回任务 ID，不是直接返回视频');
  print('   - 需要轮询 /v1/videos/{taskId} 查询状态');
  print('   - Dart 实现自动处理轮询（pollTaskUntilComplete）');
  print('');

  print('3. 模型支持:');
  print('   - VEO 模型: veo_3_1, veo_3_1-fast, veo_3_1-4K 等');
  print('   - Sora 模型: sora-2, sora-turbo');
  print('   - Kling 模型: kling-video-o1');
  print('');
}

/// 错误处理示例
Future<void> errorHandlingExample(VeoVideoService service) async {
  print('=== 错误处理示例 ===\n');

  final result = await service.generateVideos(
    prompt: '测试视频',
    model: VeoModel.klingO1,
    ratio: '720x1280',
    parameters: {'seconds': 10},
  );

  // 详细的错误处理
  if (result.isSuccess) {
    print('✅ 任务提交成功');
    print('   任务ID: ${result.data!.first.videoId}');
    print('   状态码: ${result.statusCode}');
  } else {
    print('❌ 任务提交失败');
    print('   错误信息: ${result.errorMessage}');
    print('   状态码: ${result.statusCode}');
    
    // 根据状态码处理不同错误
    switch (result.statusCode) {
      case 400:
        print('   → 请求参数错误，请检查参数格式');
        break;
      case 401:
        print('   → API Key 无效，请检查授权');
        break;
      case 429:
        print('   → 请求过于频繁，请稍后重试');
        break;
      case 500:
        print('   → 服务器内部错误');
        break;
      default:
        print('   → 未知错误');
    }
  }
}

/// 完整的生产级使用示例
Future<void> productionExample() async {
  print('=== 生产级使用示例 ===\n');

  // 1. 配置（建议从环境变量或配置文件读取）
  final config = ApiConfig(
    provider: 'GeekNow',
    baseUrl: const String.fromEnvironment('VIDEO_API_BASE_URL'),
    apiKey: const String.fromEnvironment('VIDEO_API_KEY'),
  );

  final service = VeoVideoService(config);
  final helper = VeoVideoHelper(service);

  // 2. 参数准备
  final videoRequest = {
    'prompt': '猫咪带着耳机听着歌走路，摇晃脑袋，大雨落下',
    'model': VeoModel.klingO1,
    'size': '720x1280',
    'seconds': 10,
  };

  print('准备生成视频:');
  print('  模型: ${videoRequest['model']}');
  print('  提示词: ${videoRequest['prompt']}');
  print('  尺寸: ${videoRequest['size']}');
  print('  时长: ${videoRequest['seconds']}秒');

  // 3. 提交任务（带重试）
  final result = await _submitWithRetry(
    service: service,
    prompt: videoRequest['prompt'] as String,
    model: videoRequest['model'] as String,
    size: videoRequest['size'] as String,
    seconds: videoRequest['seconds'] as int,
    maxRetries: 3,
  );

  if (!result.isSuccess) {
    print('提交失败，已重试 3 次');
    return;
  }

  final taskId = result.data!.first.videoId!;
  print('\n任务提交成功: $taskId');

  // 4. 轮询任务状态
  print('开始轮询任务状态...');
  final statusResult = await helper.pollTaskUntilComplete(
    taskId: taskId,
    maxWaitMinutes: 15,
    onProgress: (progress, status) {
      final now = DateTime.now().toIso8601String();
      print('[$now] 进度: $progress%, 状态: $status');
    },
  );

  // 5. 处理结果
  if (statusResult.isSuccess && statusResult.data!.hasVideo) {
    print('\n✅ 视频生成成功！');
    print('视频URL: ${statusResult.data!.videoUrl}');
    
    // 可选：下载视频到本地
    // await downloadVideo(statusResult.data!.videoUrl!, 'output/video.mp4');
  } else {
    print('\n❌ 视频生成失败');
    if (statusResult.data?.errorMessage != null) {
      print('错误: ${statusResult.data!.errorMessage}');
    }
  }
}

/// 带重试的任务提交
Future<dynamic> _submitWithRetry({
  required VeoVideoService service,
  required String prompt,
  required String model,
  required String size,
  required int seconds,
  int maxRetries = 3,
}) async {
  for (var i = 0; i < maxRetries; i++) {
    try {
      final result = await service.generateVideos(
        prompt: prompt,
        model: model,
        ratio: size,
        parameters: {'seconds': seconds},
      );

      if (result.isSuccess) {
        return result;
      }

      // 429 限流错误，等待后重试
      if (result.statusCode == 429 && i < maxRetries - 1) {
        final waitSeconds = (i + 1) * 5;
        print('请求限流，等待 $waitSeconds 秒后重试...');
        await Future.delayed(Duration(seconds: waitSeconds));
        continue;
      }

      return result;
    } catch (e) {
      print('提交异常: $e');
      if (i < maxRetries - 1) {
        await Future.delayed(Duration(seconds: 5));
      }
    }
  }

  return null;
}

/// Python vs Dart 代码对比说明
void pythonVsDartComparison() {
  print('''
=== Python vs Dart 代码对比 ===

Python 代码:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
import requests

API_KEY = "your-api-key"
BASE_URL = "https://xxxxx/v1/videos"

headers = {
    "Authorization": f"Bearer {API_KEY}"
}

payload = {
    "model": "kling-video-o1",
    "prompt": "猫咪带着耳机听着歌走路，摇晃脑袋，大雨落下",
    "size": "720x1280",
    "seconds": 10
}

# 关键技巧：强制使用 multipart/form-data
files = {
    'placeholder': (None, '')
}

response = requests.post(BASE_URL, headers=headers, data=payload, files=files)
print(response.json())
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Dart 代码（等效实现）:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
import 'package:http/http.dart' as http;

final config = ApiConfig(
  baseUrl: 'https://xxxxx',
  apiKey: 'your-api-key',
);

final service = VeoVideoService(config);

final result = await service.generateVideos(
  prompt: '猫咪带着耳机听着歌走路，摇晃脑袋，大雨落下',
  model: VeoModel.klingO1,
  ratio: '720x1280',
  parameters: {'seconds': 10},
);

if (result.isSuccess) {
  print(result.data!.first.metadata);
}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

关键差异：
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Content-Type 处理:
   Python: 通过 files={'placeholder': (None, '')} 强制
   Dart:   通过 http.MultipartRequest 自动处理

2. 异步处理:
   Python: 需要手动编写轮询逻辑
   Dart:   提供 pollTaskUntilComplete() 自动轮询

3. 类型安全:
   Python: 运行时检查
   Dart:   编译时类型检查

4. 错误处理:
   Python: 手动检查 status_code
   Dart:   ApiResponse 封装，isSuccess 属性
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''');
}

/// 实际代码中的关键实现（generateVideos 方法内部）
void implementationDetails() {
  print('''
=== Dart 实现内部细节 ===

在 VeoVideoService.generateVideos() 方法中：

```dart
// ⚠️ 关键：必须使用 multipart/form-data 格式，即使没有文件
var request = http.MultipartRequest(
  'POST',
  Uri.parse('\${config.baseUrl}/v1/videos'),
);

// 添加请求头（不要手动设置 Content-Type，让 http 库自动处理）
request.headers['Authorization'] = 'Bearer \${config.apiKey}';

// 添加文本参数（对应 Python 的 data/payload）
request.fields['model'] = targetModel;
request.fields['prompt'] = prompt;
request.fields['size'] = size;
request.fields['seconds'] = seconds.toString();

// VEO 高清参数（可选）
if (enableUpsample != null) {
  request.fields['enable_upsample'] = enableUpsample.toString();
}

// Sora 角色引用参数（可选）
if (characterUrl != null) {
  request.fields['character_url'] = characterUrl;
}
if (characterTimestamps != null) {
  request.fields['character_timestamps'] = characterTimestamps;
}

// 添加参考图片文件（如果有）
if (referenceImagePaths != null && referenceImagePaths.isNotEmpty) {
  for (final imagePath in referenceImagePaths) {
    request.files.add(
      await http.MultipartFile.fromPath(
        'input_reference',
        imagePath,
      ),
    );
  }
}

// 发送请求
final streamedResponse = await request.send();
final response = await http.Response.fromStream(streamedResponse);

// 解析响应
if (response.statusCode == 200) {
  return _parseVideoResponse(response.body);
}
```

关键点：
1. 始终使用 MultipartRequest（即使没有文件）
2. 不手动设置 Content-Type（让 http 库自动处理）
3. 所有参数通过 request.fields 添加
4. 文件通过 request.files 添加
''');
}
