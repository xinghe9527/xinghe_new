# Midjourney SwapFace 操作指南

## ⚠️ 重要提示

SwapFace 是一个强大的人脸替换工具。请负责任地使用：

- ✅ **仅用于合法和道德的用途**
- ❌ 不要用于欺诈或误导
- ❌ 不要侵犯他人隐私权
- ❌ 不要创建虚假身份
- ✅ 获得相关人员的许可

## 概述

SwapFace 功能可以将一张图片中的人脸替换到另一张图片中。

### 主要用途

✅ **合法用途**：
1. 艺术创作和娱乐
2. 电影和游戏制作
3. 教育演示
4. 个人创意项目

❌ **禁止用途**：
1. 制作虚假新闻
2. 侵犯隐私
3. 身份欺诈
4. 任何非法活动

## 快速开始

### 基础用法

```dart
import 'package:xinghe_new/services/api/providers/midjourney_service.dart';

final helper = MidjourneyHelper(MidjourneyService(config));

// 换脸操作
// source: 人脸来源（要使用的脸）
// target: 目标图片（要替换脸的图）
final result = await helper.swapFace(
  sourceImagePath: '/path/to/face_source.jpg',  // 人脸源
  targetImagePath: '/path/to/target_photo.jpg', // 目标图
  mode: MidjourneyMode.fast,
);

if (result.isSuccess) {
  print('SwapFace 任务已提交: ${result.data!.taskId}');
}
```

### 自动等待完成

```dart
// 一键换脸并等待完成
final result = await helper.swapFaceAndWait(
  sourceImagePath: 'face_source.jpg',
  targetImagePath: 'target_photo.jpg',
  mode: MidjourneyMode.fast,
  maxWaitMinutes: 3,
);

if (result.isSuccess) {
  print('换脸完成！');
  print('结果图片: ${result.data}');
}
```

## 使用示例

### 示例 1: 基础换脸

```dart
final config = ApiConfig(
  baseUrl: 'YOUR_BASE_URL',
  apiKey: 'YOUR_API_KEY',
);

final helper = MidjourneyHelper(MidjourneyService(config));

// 执行换脸
final result = await helper.swapFaceAndWait(
  sourceImagePath: 'my_face.jpg',      // 我的照片
  targetImagePath: 'movie_poster.jpg', // 电影海报
  mode: MidjourneyMode.fast,
);

if (result.isSuccess) {
  print('换脸成功: ${result.data}');
  // 可以看到自己出现在电影海报中
}
```

### 示例 2: 批量换脸

```dart
/// 将一张脸应用到多张目标图片
Future<List<String>> batchSwapFace({
  required String sourceFace,
  required List<String> targetImages,
}) async {
  final results = <String>[];

  for (int i = 0; i < targetImages.length; i++) {
    print('处理 ${i + 1}/${targetImages.length}');

    final result = await helper.swapFaceAndWait(
      sourceImagePath: sourceFace,
      targetImagePath: targetImages[i],
      mode: MidjourneyMode.fast,
    );

    if (result.isSuccess) {
      results.add(result.data!);
      print('✅ 完成');
    }

    // 避免请求过快
    await Future.delayed(Duration(seconds: 2));
  }

  return results;
}

// 使用
final swappedImages = await batchSwapFace(
  sourceFace: 'my_selfie.jpg',
  targetImages: [
    'scene1.jpg',
    'scene2.jpg',
    'scene3.jpg',
  ],
);

print('批量换脸完成，成功 ${swappedImages.length} 张');
```

### 示例 3: 多人换脸

```dart
/// 将多张脸分别应用到不同场景
Future<void> multiPersonSwap() async {
  final faces = [
    'person1.jpg',
    'person2.jpg',
    'person3.jpg',
  ];

  final scenes = [
    'beach.jpg',
    'mountain.jpg',
    'city.jpg',
  ];

  // 每张脸应用到每个场景
  for (final face in faces) {
    for (final scene in scenes) {
      final result = await helper.swapFaceAndWait(
        sourceImagePath: face,
        targetImagePath: scene,
        mode: MidjourneyMode.fast,
      );

      if (result.isSuccess) {
        print('${face} + ${scene} = ${result.data}');
      }

      await Future.delayed(Duration(seconds: 2));
    }
  }
}
```

## 在 Flutter 中使用

### SwapFace Widget

```dart
class SwapFaceWidget extends StatefulWidget {
  @override
  State<SwapFaceWidget> createState() => _SwapFaceWidgetState();
}

class _SwapFaceWidgetState extends State<SwapFaceWidget> {
  final _helper = MidjourneyHelper(
    MidjourneyService(ApiConfig(
      baseUrl: 'YOUR_BASE_URL',
      apiKey: 'YOUR_API_KEY',
    )),
  );

  String? _sourceFacePath;
  String? _targetImagePath;
  String? _resultImageUrl;
  bool _isSwapping = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            // 源人脸选择
            Expanded(
              child: _buildImagePicker(
                title: '人脸源',
                imagePath: _sourceFacePath,
                onPick: () => _pickImage(isSource: true),
              ),
            ),
            
            SizedBox(width: 16),
            
            // 目标图片选择
            Expanded(
              child: _buildImagePicker(
                title: '目标图片',
                imagePath: _targetImagePath,
                onPick: () => _pickImage(isSource: false),
              ),
            ),
          ],
        ),
        
        SizedBox(height: 24),
        
        // 换脸按钮
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _canSwap && !_isSwapping 
                ? _performSwapFace 
                : null,
            icon: Icon(Icons.swap_horiz),
            label: Text(_isSwapping ? '换脸中...' : '开始换脸'),
          ),
        ),
        
        // 显示结果
        if (_resultImageUrl != null) ...[
          SizedBox(height: 24),
          Text(
            '换脸结果:',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 12),
          Image.network(_resultImageUrl!),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: _downloadResult,
                icon: Icon(Icons.download),
                label: Text('下载'),
              ),
              TextButton.icon(
                onPressed: _shareResult,
                icon: Icon(Icons.share),
                label: Text('分享'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildImagePicker({
    required String title,
    required String? imagePath,
    required VoidCallback onPick,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        SizedBox(height: 8),
        GestureDetector(
          onTap: onPick,
          child: Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey),
            ),
            child: imagePath != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(imagePath),
                      fit: BoxFit.cover,
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate, size: 48),
                      SizedBox(height: 8),
                      Text('点击选择图片'),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  bool get _canSwap => 
      _sourceFacePath != null && _targetImagePath != null;

  Future<void> _pickImage({required bool isSource}) async {
    // TODO: 使用 image_picker 选择图片
    // final picker = ImagePicker();
    // final file = await picker.pickImage(source: ImageSource.gallery);
    
    _showMessage('图片选择功能待实现');
  }

  Future<void> _performSwapFace() async {
    if (!_canSwap) return;

    setState(() {
      _isSwapping = true;
      _resultImageUrl = null;
    });

    try {
      final result = await _helper.swapFaceAndWait(
        sourceImagePath: _sourceFacePath!,
        targetImagePath: _targetImagePath!,
        mode: MidjourneyMode.fast,
      );

      if (result.isSuccess) {
        setState(() => _resultImageUrl = result.data);
        _showMessage('换脸完成！');
      } else {
        _showMessage('换脸失败: ${result.errorMessage}', isError: true);
      }
    } finally {
      setState(() => _isSwapping = false);
    }
  }

  Future<void> _downloadResult() async {
    // TODO: 实现下载
    _showMessage('下载功能待实现');
  }

  Future<void> _shareResult() async {
    // TODO: 实现分享
    _showMessage('分享功能待实现');
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }
}
```

## 实用场景

### 场景 1: 艺术创作

```dart
/// 将自己的脸放到艺术作品中
Future<String?> createArtPortrait(String myPhoto, String artStyle) async {
  // 1. 先用 Imagine 生成艺术风格图片
  final artResult = await helper.submitAndWait(
    prompt: 'Portrait in $artStyle style --ar 3:4',
    mode: MidjourneyMode.fast,
  );

  if (!artResult.isSuccess) {
    return null;
  }

  // 2. 下载生成的艺术图片
  final artImagePath = await downloadImage(artResult.data!);

  // 3. 换脸
  final swapResult = await helper.swapFaceAndWait(
    sourceImagePath: myPhoto,
    targetImagePath: artImagePath,
    mode: MidjourneyMode.fast,
  );

  return swapResult.data;
}

// 使用
final myArtPortrait = await createArtPortrait(
  'my_selfie.jpg',
  'renaissance painting',
);

print('我的文艺复兴肖像: $myArtPortrait');
```

### 场景 2: 虚拟试装/试妆

```dart
/// 将用户的脸放到模特图片上（虚拟试装）
class VirtualTryOn {
  final MidjourneyHelper helper;

  VirtualTryOn(this.helper);

  Future<String?> tryOutfit({
    required String userPhoto,
    required String outfitPhoto,
  }) async {
    print('虚拟试装中...');

    final result = await helper.swapFaceAndWait(
      sourceImagePath: userPhoto,
      targetImagePath: outfitPhoto,
      mode: MidjourneyMode.fast,
    );

    if (result.isSuccess) {
      print('试装完成！');
      return result.data;
    }

    return null;
  }
}

// 使用
final tryOn = VirtualTryOn(helper);

final result = await tryOn.tryOutfit(
  userPhoto: 'customer_photo.jpg',
  outfitPhoto: 'model_outfit.jpg',
);
```

### 场景 3: 历史人物穿越

```dart
/// 创意项目：将现代人物放到历史场景
Future<void> timeTravel() async {
  final modernPerson = 'person_2024.jpg';
  
  final historicalScenes = [
    'ancient_rome.jpg',
    'medieval_castle.jpg',
    'wild_west.jpg',
  ];

  final results = <String>[];

  for (final scene in historicalScenes) {
    final swapped = await helper.swapFaceAndWait(
      sourceImagePath: modernPerson,
      targetImagePath: scene,
      mode: MidjourneyMode.fast,
    );

    if (swapped.isSuccess) {
      results.add(swapped.data!);
      print('穿越到: $scene ✅');
    }
  }

  print('时间穿越完成，创作了 ${results.length} 张作品');
}
```

## 技术要求

### 源图片要求（人脸源）

- ✅ 清晰的正面人脸
- ✅ 光线均匀
- ✅ 无遮挡（眼镜、口罩等）
- ✅ 分辨率至少 512x512
- ❌ 避免侧脸或模糊照片

### 目标图片要求

- ✅ 包含可识别的人脸
- ✅ 人脸大小适中
- ✅ 清晰可见
- ⚠️ 多人脸可能只替换主要人物

### 最佳效果建议

```dart
// 1. 预处理图片
Future<String> preprocessForSwap(String imagePath) async {
  final bytes = await File(imagePath).readAsBytes();
  final image = img.decodeImage(bytes);

  if (image == null) {
    throw Exception('无法解析图片');
  }

  // 调整大小
  final resized = image.width > 1024
      ? img.copyResize(image, width: 1024)
      : image;

  // 保存为高质量 JPEG
  final temp = await getTemporaryDirectory();
  final processed = File('${temp.path}/processed.jpg');
  await processed.writeAsBytes(img.encodeJpg(resized, quality: 95));

  return processed.path;
}

// 使用
final processedSource = await preprocessForSwap('source.jpg');
final processedTarget = await preprocessForSwap('target.jpg');

await helper.swapFace(
  sourceImagePath: processedSource,
  targetImagePath: processedTarget,
);
```

## 完整示例

### 示例：头像生成器

```dart
class AvatarGenerator {
  final MidjourneyHelper helper;

  AvatarGenerator(this.helper);

  /// 生成不同风格的头像
  Future<List<String>> generateAvatars({
    required String userPhoto,
    required List<String> styles,
  }) async {
    final avatars = <String>[];

    for (final style in styles) {
      print('生成 $style 风格头像...');

      // 1. 先用 Imagine 生成风格背景
      final bgPrompt = 'Portrait background, $style style --ar 1:1';
      final bgResult = await helper.submitAndWait(
        prompt: bgPrompt,
        mode: MidjourneyMode.fast,
      );

      if (!bgResult.isSuccess) {
        continue;
      }

      // 2. 下载背景图
      final bgPath = await downloadImage(bgResult.data!);

      // 3. 换脸
      final swapResult = await helper.swapFaceAndWait(
        sourceImagePath: userPhoto,
        targetImagePath: bgPath,
        mode: MidjourneyMode.fast,
      );

      if (swapResult.isSuccess) {
        avatars.add(swapResult.data!);
        print('✅ $style 头像完成');
      }

      await Future.delayed(Duration(seconds: 3));
    }

    return avatars;
  }

  Future<String> downloadImage(String url) async {
    // TODO: 下载图片到本地
    return 'temp_image.jpg';
  }
}

// 使用
final generator = AvatarGenerator(helper);

final avatars = await generator.generateAvatars(
  userPhoto: 'my_photo.jpg',
  styles: [
    'cyberpunk',
    'fantasy',
    'professional',
    'anime',
  ],
);

print('生成了 ${avatars.length} 个不同风格的头像');
```

## 错误处理

### 人脸检测失败

```dart
Future<ApiResponse<String>> safeSwapFace({
  required String source,
  required String target,
}) async {
  // 验证图片是否包含人脸
  final hasSourceFace = await detectFace(source);
  final hasTargetFace = await detectFace(target);

  if (!hasSourceFace) {
    return ApiResponse.failure('源图片未检测到人脸');
  }

  if (!hasTargetFace) {
    return ApiResponse.failure('目标图片未检测到人脸');
  }

  // 执行换脸
  return helper.swapFaceAndWait(
    sourceImagePath: source,
    targetImagePath: target,
    mode: MidjourneyMode.fast,
  );
}

Future<bool> detectFace(String imagePath) async {
  // TODO: 使用人脸检测库
  // 例如：google_ml_kit, flutter_face_detection
  return true;
}
```

### 重试机制

```dart
Future<String?> swapFaceWithRetry({
  required String source,
  required String target,
  int maxRetries = 3,
}) async {
  for (int i = 0; i < maxRetries; i++) {
    final result = await helper.swapFaceAndWait(
      sourceImagePath: source,
      targetImagePath: target,
      mode: MidjourneyMode.fast,
    );

    if (result.isSuccess) {
      return result.data;
    }

    print('尝试 ${i + 1} 失败，原因: ${result.errorMessage}');

    // 等待后重试
    if (i < maxRetries - 1) {
      await Future.delayed(Duration(seconds: 5));
    }
  }

  return null;
}
```

## 伦理和法律

### 使用准则

1. **获得许可**
   - 使用他人照片前获得明确许可
   - 商业用途需要书面授权

2. **明确标注**
   - 在分享时标注为 AI 生成
   - 不要误导他人

3. **尊重隐私**
   - 不要使用未授权的人脸
   - 不要创建虚假内容

4. **合法使用**
   - 遵守当地法律法规
   - 不用于欺诈或非法活动

### 示例：添加水印

```dart
/// 在换脸结果上添加 AI 生成标记
Future<String> addAIWatermark(String swappedImageUrl) async {
  // 下载结果图片
  final imagePath = await downloadImage(swappedImageUrl);
  final bytes = await File(imagePath).readAsBytes();
  final image = img.decodeImage(bytes);

  if (image != null) {
    // 添加水印文字
    img.drawString(
      image,
      img.arial_24,
      10,
      image.height - 30,
      'AI Generated - Not Real',
    );

    // 保存
    final watermarked = File('${imagePath}_watermarked.jpg');
    await watermarked.writeAsBytes(img.encodeJpg(image));

    return watermarked.path;
  }

  return imagePath;
}
```

## 性能优化

### 图片压缩

```dart
/// 压缩图片以加快上传速度
Future<String> compressForSwap(String imagePath) async {
  final bytes = await File(imagePath).readAsBytes();
  final image = img.decodeImage(bytes);

  if (image == null) {
    return imagePath;
  }

  // 限制最大尺寸
  final maxDim = 1024;
  final resized = image.width > maxDim || image.height > maxDim
      ? img.copyResize(
          image,
          width: image.width > maxDim ? maxDim : null,
          height: image.height > maxDim ? maxDim : null,
        )
      : image;

  // 压缩
  final compressed = img.encodeJpg(resized, quality: 85);

  // 保存临时文件
  final temp = await getTemporaryDirectory();
  final file = File('${temp.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg');
  await file.writeAsBytes(compressed);

  return file.path;
}
```

## 注意事项

1. **文件大小**: 建议每张图片 < 5MB
2. **人脸质量**: 清晰的正面照效果最佳
3. **处理时间**: FAST 模式约 30-60 秒
4. **隐私保护**: 不要上传敏感的个人照片到公共 API
5. **商业使用**: 需要额外的授权和许可

## 技术规格

### API 端点

```
POST /mj/insight-face/swap
Content-Type: multipart/form-data
```

### 请求格式

```
mode: FAST
source: [Binary File]
target: [Binary File]
```

### 响应格式

```json
{
  "code": 1,
  "description": "Submit success",
  "result": "1712211887200849"
}
```

## 常见问题

**Q: 可以换多个人的脸吗？**  
A: 一次只能换一个人脸，通常是图片中最明显的人脸

**Q: 支持什么格式的图片？**  
A: JPG、PNG 等常见格式

**Q: 换脸效果自然吗？**  
A: 取决于源图片和目标图片的质量，通常效果很好

**Q: 可以换动物的脸吗？**  
A: SwapFace 专门用于人脸，动物脸效果可能不理想

**Q: 如何提高换脸质量？**  
A: 
- 使用高质量的源人脸照片
- 确保目标图片中人脸清晰可见
- 选择光线和角度相似的照片

## 与其他功能结合

### SwapFace + Upscale

```dart
// 换脸后放大以获得更高质量
final swapResult = await helper.swapFaceAndWait(
  sourceImagePath: 'face.jpg',
  targetImagePath: 'scene.jpg',
);

// 提取任务 ID 并 Upscale
final taskId = extractTaskId(swapResult.data!);

await helper.upscale(
  taskId: taskId,
  index: 1,
  mode: MidjourneyMode.fast,
);
```

### Imagine + SwapFace

```dart
// 先生成场景，再换脸
final scene = await helper.submitAndWait(
  prompt: 'Astronaut in space --ar 9:16',
);

final scenePath = await downloadImage(scene.data!);

final finalResult = await helper.swapFaceAndWait(
  sourceImagePath: 'my_face.jpg',
  targetImagePath: scenePath,
);

print('我成为宇航员: ${finalResult.data}');
```

## 相关文档

- **Midjourney 使用**: `MIDJOURNEY_USAGE.md`
- **Action 操作**: `MIDJOURNEY_ACTIONS.md`
- **快速参考**: `MIDJOURNEY_QUICK_REFERENCE.md`

---

**请负责任地使用 SwapFace 功能！🎭✨**
