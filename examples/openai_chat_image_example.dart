import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:xinghe_new/services/api/providers/openai_service.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';

/// OpenAI 对话格式生图 - 完整示例
void main() async {
  // 配置 API（GeekNow 服务）
  final config = ApiConfig(
    provider: 'GeekNow',  // GeekNow 服务商
    baseUrl: 'https://your-geeknow-api.com',
    apiKey: 'your-geeknow-api-key',
    model: 'gpt-4o',
  );

  final service = OpenAIService(config);
  final helper = OpenAIChatImageHelper(service);

  print('=== OpenAI 对话格式生图示例 ===\n');

  // 示例1: 简单文生图
  await example1TextToImage(helper);

  // 示例2: 图生图
  // await example2ImageToImage(helper);

  // 示例3: 风格转换
  // await example3StyleTransfer(helper);

  // 示例4: 批量生成
  // await example4BatchGeneration(helper);

  // 示例5: 多图融合
  // await example5MultiImageBlend(helper);

  // 示例6: 对话式生成
  // await example6ConversationalGeneration(service);

  // 示例7: 完整参数控制
  // await example7AdvancedParameters(service);

  print('\n示例运行完成！');
}

/// 示例1: 简单文生图
Future<void> example1TextToImage(OpenAIChatImageHelper helper) async {
  print('【示例1】简单文生图');
  print('-' * 50);

  final imageUrl = await helper.textToImage(
    prompt: '一只可爱的橙色小猫，坐在彩虹上，背景是星空，卡通风格',
  );

  if (imageUrl != null) {
    print('✓ 生成成功！');
    print('图片URL: $imageUrl');

    // 可选：下载图片
    // await downloadImage(imageUrl, 'output/cat_on_rainbow.jpg');
  } else {
    print('✗ 生成失败');
  }

  print('');
}

/// 示例2: 图生图
Future<void> example2ImageToImage(OpenAIChatImageHelper helper) async {
  print('【示例2】图生图');
  print('-' * 50);

  final imageUrl = await helper.imageToImage(
    imagePath: '/path/to/your/photo.jpg',
    prompt: '将这张照片转换成油画风格，增强色彩饱和度',
  );

  if (imageUrl != null) {
    print('✓ 图生图成功！');
    print('图片URL: $imageUrl');
  } else {
    print('✗ 图生图失败');
  }

  print('');
}

/// 示例3: 风格转换
Future<void> example3StyleTransfer(OpenAIChatImageHelper helper) async {
  print('【示例3】风格转换');
  print('-' * 50);

  final styles = ['油画', '水彩', '素描', '动漫'];

  for (final style in styles) {
    print('正在生成 $style 风格...');

    final imageUrl = await helper.styleTransfer(
      imagePath: '/path/to/your/photo.jpg',
      targetStyle: style,
      keepComposition: true,
    );

    if (imageUrl != null) {
      print('  ✓ $style: $imageUrl');
    } else {
      print('  ✗ $style: 失败');
    }
  }

  print('');
}

/// 示例4: 批量生成
Future<void> example4BatchGeneration(OpenAIChatImageHelper helper) async {
  print('【示例4】批量生成');
  print('-' * 50);

  final imageUrls = await helper.generateMultiple(
    prompt: '未来派科幻城市，霓虹灯，赛博朋克风格',
    count: 4,
  );

  print('生成了 ${imageUrls.length} 张图片:');
  for (var i = 0; i < imageUrls.length; i++) {
    print('  ${i + 1}. ${imageUrls[i]}');
  }

  print('');
}

/// 示例5: 多图融合
Future<void> example5MultiImageBlend(OpenAIChatImageHelper helper) async {
  print('【示例5】多图融合');
  print('-' * 50);

  final imageUrl = await helper.multiImageBlend(
    imagePaths: [
      '/path/to/image1.jpg',
      '/path/to/image2.jpg',
      '/path/to/image3.jpg',
    ],
    prompt: '融合这些图片的风格和元素，创作一幅新的艺术作品',
  );

  if (imageUrl != null) {
    print('✓ 融合成功！');
    print('图片URL: $imageUrl');
  } else {
    print('✗ 融合失败');
  }

  print('');
}

/// 示例6: 对话式生成
Future<void> example6ConversationalGeneration(OpenAIService service) async {
  print('【示例6】对话式生成');
  print('-' * 50);

  // 维护对话历史
  final conversationHistory = <ChatMessage>[];

  // 第一轮：生成初始图像
  print('第一轮：生成基础场景...');
  conversationHistory.add(
    ChatMessage(
      role: 'user',
      content: [
        ChatMessageContent.text(text: '生成一座未来主义的摩天大楼'),
      ],
    ),
  );

  var result = await service.generateImagesByChat(
    messages: conversationHistory,
  );

  if (result.isSuccess) {
    final firstImageUrl = result.data!.firstImageUrl;
    print('  ✓ 第一轮完成: $firstImageUrl');

    // 保存助手的回复
    conversationHistory.add(result.data!.choices.first.message);

    // 第二轮：基于第一轮结果继续
    print('第二轮：添加细节...');
    conversationHistory.add(
      ChatMessage(
        role: 'user',
        content: [
          ChatMessageContent.text(
            text: '在大楼周围添加飞行汽车和霓虹灯',
          ),
        ],
      ),
    );

    result = await service.generateImagesByChat(
      messages: conversationHistory,
    );

    if (result.isSuccess) {
      final finalImageUrl = result.data!.firstImageUrl;
      print('  ✓ 第二轮完成: $finalImageUrl');
    }
  } else {
    print('  ✗ 生成失败: ${result.errorMessage}');
  }

  print('');
}

/// 示例7: 完整参数控制
Future<void> example7AdvancedParameters(OpenAIService service) async {
  print('【示例7】完整参数控制');
  print('-' * 50);

  final result = await service.generateImagesByChat(
    prompt: '一幅超现实主义艺术作品，融合机械和自然元素',
    model: 'gpt-4o',
    parameters: {
      'temperature': 0.8, // 更高的创造性
      'top_p': 0.95,
      'n': 2, // 生成2张
      'max_tokens': 1000,
      'presence_penalty': 0.1,
      'frequency_penalty': 0.1,
    },
  );

  if (result.isSuccess) {
    final response = result.data!;

    print('✓ 生成成功！');
    print('模型: ${response.model}');
    print('创建时间: ${DateTime.fromMillisecondsSinceEpoch(response.created * 1000)}');

    if (response.usage != null) {
      print('Token使用:');
      print('  - 提示词: ${response.usage!.promptTokens}');
      print('  - 完成: ${response.usage!.completionTokens}');
      print('  - 总计: ${response.usage!.totalTokens}');
    }

    print('生成的图片:');
    for (var i = 0; i < response.imageUrls.length; i++) {
      print('  ${i + 1}. ${response.imageUrls[i]}');
    }
  } else {
    print('✗ 生成失败: ${result.errorMessage}');
  }

  print('');
}

/// 辅助函数：下载图片
Future<void> downloadImage(String url, String savePath) async {
  try {
    print('正在下载图片...');

    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final file = File(savePath);

      // 确保目录存在
      await file.parent.create(recursive: true);

      await file.writeAsBytes(response.bodyBytes);
      print('✓ 图片已保存到: $savePath');
    } else {
      print('✗ 下载失败: HTTP ${response.statusCode}');
    }
  } catch (e) {
    print('✗ 下载错误: $e');
  }
}

/// 辅助函数：带重试的生成
Future<String?> generateWithRetry({
  required OpenAIChatImageHelper helper,
  required String prompt,
  int maxRetries = 3,
  Duration retryDelay = const Duration(seconds: 5),
}) async {
  for (var i = 0; i < maxRetries; i++) {
    try {
      final imageUrl = await helper.textToImage(prompt: prompt);

      if (imageUrl != null) {
        return imageUrl;
      }

      // 如果返回null，可能是API错误，等待后重试
      if (i < maxRetries - 1) {
        print('生成失败，${retryDelay.inSeconds} 秒后重试...');
        await Future.delayed(retryDelay * (i + 1)); // 指数退避
      }
    } catch (e) {
      print('异常: $e');
      if (i < maxRetries - 1) {
        await Future.delayed(retryDelay);
      }
    }
  }

  return null;
}

/// 辅助函数：批量风格转换
Future<Map<String, String?>> batchStyleTransfer({
  required OpenAIChatImageHelper helper,
  required String imagePath,
  required List<String> styles,
}) async {
  print('正在批量转换 ${styles.length} 种风格...');

  final results = <String, String?>{};

  // 并发执行
  final futures = styles.map((style) async {
    final url = await helper.styleTransfer(
      imagePath: imagePath,
      targetStyle: style,
    );
    return MapEntry(style, url);
  });

  final entries = await Future.wait(futures);
  results.addEntries(entries);

  return results;
}

/// 辅助函数：验证图片URL
Future<bool> isImageUrlValid(String url) async {
  try {
    final response = await http.head(Uri.parse(url));
    return response.statusCode == 200;
  } catch (e) {
    return false;
  }
}

/// 辅助函数：图片增强示例
Future<void> enhanceImageExample(OpenAIChatImageHelper helper) async {
  print('【图片增强示例】');
  print('-' * 50);

  final enhancedUrl = await helper.enhanceImage(
    imagePath: '/path/to/photo.jpg',
    enhancements: [
      '提高清晰度',
      '增强色彩饱和度',
      '优化光线和对比度',
      '去除噪点',
    ],
  );

  if (enhancedUrl != null) {
    print('✓ 增强成功: $enhancedUrl');
  } else {
    print('✗ 增强失败');
  }

  print('');
}

/// 辅助函数：场景重构示例
Future<void> reimagineSceneExample(OpenAIChatImageHelper helper) async {
  print('【场景重构示例】');
  print('-' * 50);

  final reimaginedUrl = await helper.reimagineScene(
    imagePath: '/path/to/daytime-scene.jpg',
    timeOfDay: '夜晚',
    weather: '雨天',
    additionalChanges: '添加霓虹灯和反光效果',
  );

  if (reimaginedUrl != null) {
    print('✓ 重构成功: $reimaginedUrl');
  } else {
    print('✗ 重构失败');
  }

  print('');
}

/// 辅助函数：艺术家风格模仿示例
Future<void> artistStyleExample(OpenAIChatImageHelper helper) async {
  print('【艺术家风格模仿示例】');
  print('-' * 50);

  final artists = ['梵高', '毕加索', '莫奈', '达利'];

  for (final artist in artists) {
    print('生成 $artist 风格...');

    final imageUrl = await helper.artistStyleImitation(
      prompt: '星空下的城市夜景',
      artistStyle: artist,
    );

    if (imageUrl != null) {
      print('  ✓ $artist: $imageUrl');
    } else {
      print('  ✗ $artist: 失败');
    }
  }

  print('');
}
