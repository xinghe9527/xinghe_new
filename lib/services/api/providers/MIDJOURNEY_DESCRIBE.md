# Midjourney Describe 操作指南

## 概述

Describe 是 Midjourney 的图生文功能，可以分析图片并生成多个描述性 prompt。

### 主要用途

1. **反向工程 Prompt** - 学习如何描述图片
2. **图片分析** - 了解图片的关键元素
3. **Prompt 优化** - 获取更好的描述词汇
4. **学习工具** - 学习 Midjourney 的描述方式

## 快速开始

### 基础用法

```dart
import 'dart:convert';
import 'dart:io';
import 'package:xinghe_new/services/api/providers/midjourney_service.dart';

// 1. 读取图片
final imageBytes = await File('photo.jpg').readAsBytes();
final imageBase64 = base64Encode(imageBytes);

// 2. 分析图片
final helper = MidjourneyHelper(MidjourneyService(config));

final result = await helper.describe(
  imageBase64: imageBase64,
  mode: MidjourneyMode.fast,
);

if (result.isSuccess) {
  print('Describe 任务已提交: ${result.data!.taskId}');
}
```

### 自动等待结果

```dart
// 一键分析并获取描述
final result = await helper.describeAndWait(
  imageBase64: imageBase64,
  mode: MidjourneyMode.fast,
  maxWaitMinutes: 3,
);

if (result.isSuccess) {
  final describeResult = result.data!;
  
  print('生成了 ${describeResult.prompts.length} 个 prompt 建议：');
  
  for (int i = 0; i < describeResult.prompts.length; i++) {
    print('${i + 1}. ${describeResult.prompts[i]}');
  }
  
  print('\n最佳 prompt: ${describeResult.bestPrompt}');
}
```

## 使用示例

### 示例 1: 分析单张图片

```dart
final config = ApiConfig(
  baseUrl: 'YOUR_BASE_URL',
  apiKey: 'YOUR_API_KEY',
);

final helper = MidjourneyHelper(MidjourneyService(config));

// 读取图片
final bytes = await File('artwork.jpg').readAsBytes();
final base64 = base64Encode(bytes);

// 分析
final result = await helper.describeAndWait(
  imageBase64: base64,
  mode: MidjourneyMode.fast,
);

if (result.isSuccess) {
  print('图片分析结果：');
  
  for (final prompt in result.data!.prompts) {
    print('- $prompt');
  }
}
```

### 示例 2: 使用描述重新生成

```dart
// 第一步：分析现有图片
final describeResult = await helper.describeAndWait(
  imageBase64: existingImageBase64,
  mode: MidjourneyMode.fast,
);

if (describeResult.isSuccess) {
  // 获取最佳描述
  final bestPrompt = describeResult.data!.bestPrompt;
  
  print('原图描述: $bestPrompt');
  
  // 第二步：使用该描述重新生成
  final imagineResult = await helper.submitAndWait(
    prompt: bestPrompt,
    mode: MidjourneyMode.fast,
  );
  
  if (imagineResult.isSuccess) {
    print('重新生成完成: ${imagineResult.data}');
  }
}
```

### 示例 3: 批量分析图片

```dart
final imagePaths = [
  'photo1.jpg',
  'photo2.jpg',
  'photo3.jpg',
];

final descriptions = <String, List<String>>{};

for (final path in imagePaths) {
  // 读取图片
  final bytes = await File(path).readAsBytes();
  final base64 = base64Encode(bytes);
  
  // 分析
  final result = await helper.describeAndWait(
    imageBase64: base64,
    mode: MidjourneyMode.relax,
  );
  
  if (result.isSuccess) {
    descriptions[path] = result.data!.prompts;
    print('$path 分析完成');
  }
  
  // 避免请求过快
  await Future.delayed(Duration(seconds: 3));
}

// 输出所有描述
descriptions.forEach((path, prompts) {
  print('\n$path:');
  prompts.forEach((p) => print('  - $p'));
});
```

### 示例 4: Describe + 改进后重生成

```dart
/// 分析图片，改进 prompt，重新生成
Future<String?> improveAndRegenerate({
  required String originalImage,
  required String improvements,
}) async {
  // 1. 分析原图
  print('步骤 1: 分析原图');
  
  final bytes = await File(originalImage).readAsBytes();
  final base64 = base64Encode(bytes);
  
  final describeResult = await helper.describeAndWait(
    imageBase64: base64,
    mode: MidjourneyMode.fast,
  );
  
  if (!describeResult.isSuccess) {
    return null;
  }
  
  final originalPrompt = describeResult.data!.bestPrompt;
  print('原始描述: $originalPrompt');
  
  // 2. 改进 prompt
  final improvedPrompt = '$originalPrompt, $improvements';
  print('改进后: $improvedPrompt');
  
  // 3. 重新生成
  print('步骤 2: 使用改进的 prompt 重新生成');
  
  final imagineResult = await helper.submitAndWait(
    prompt: improvedPrompt,
    mode: MidjourneyMode.fast,
  );
  
  if (imagineResult.isSuccess) {
    print('✅ 改进版生成完成');
    return imagineResult.data;
  }
  
  return null;
}

// 使用
final improved = await improveAndRegenerate(
  originalImage: 'old_photo.jpg',
  improvements: 'high quality, professional photography, 8k',
);
```

## 在 Flutter 中使用

### Describe Widget

```dart
class DescribeWidget extends StatefulWidget {
  @override
  State<DescribeWidget> createState() => _DescribeWidgetState();
}

class _DescribeWidgetState extends State<DescribeWidget> {
  final _helper = MidjourneyHelper(
    MidjourneyService(ApiConfig(
      baseUrl: 'YOUR_BASE_URL',
      apiKey: 'YOUR_API_KEY',
    )),
  );

  String? _selectedImagePath;
  List<String> _prompts = [];
  bool _isAnalyzing = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 选择图片按钮
        ElevatedButton.icon(
          onPressed: _pickImage,
          icon: Icon(Icons.image),
          label: Text('选择图片'),
        ),
        
        // 显示选中的图片
        if (_selectedImagePath != null)
          Column(
            children: [
              SizedBox(height: 16),
              Image.file(
                File(_selectedImagePath!),
                height: 300,
                fit: BoxFit.contain,
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isAnalyzing ? null : _analyzeImage,
                child: Text(_isAnalyzing ? '分析中...' : '分析图片'),
              ),
            ],
          ),
        
        // 显示分析结果
        if (_prompts.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 24),
              Text(
                'Prompt 建议：',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 12),
              ..._prompts.asMap().entries.map((entry) {
                return _buildPromptCard(
                  index: entry.key + 1,
                  prompt: entry.value,
                );
              }).toList(),
            ],
          ),
      ],
    );
  }

  Widget _buildPromptCard({
    required int index,
    required String prompt,
  }) {
    return Card(
      margin: EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Prompt $index',
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                Spacer(),
                IconButton(
                  icon: Icon(Icons.copy, size: 18),
                  onPressed: () => _copyPrompt(prompt),
                  tooltip: '复制',
                ),
                IconButton(
                  icon: Icon(Icons.image, size: 18),
                  onPressed: () => _usePrompt(prompt),
                  tooltip: '使用此 Prompt 生成',
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              prompt,
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    // TODO: 实现图片选择
    // 使用 image_picker
  }

  Future<void> _analyzeImage() async {
    if (_selectedImagePath == null) return;

    setState(() {
      _isAnalyzing = true;
      _prompts.clear();
    });

    try {
      // 读取图片
      final bytes = await File(_selectedImagePath!).readAsBytes();
      final base64 = base64Encode(bytes);

      // 分析
      final result = await _helper.describeAndWait(
        imageBase64: base64,
        mode: MidjourneyMode.fast,
      );

      if (result.isSuccess) {
        setState(() {
          _prompts = result.data!.prompts;
        });
        
        _showMessage('分析完成！生成了 ${_prompts.length} 个 prompt');
      } else {
        _showMessage('分析失败: ${result.errorMessage}', isError: true);
      }
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  void _copyPrompt(String prompt) {
    Clipboard.setData(ClipboardData(text: prompt));
    _showMessage('Prompt 已复制');
  }

  Future<void> _usePrompt(String prompt) async {
    // 使用该 prompt 生成新图片
    setState(() => _isAnalyzing = true);
    
    try {
      final result = await _helper.submitAndWait(
        prompt: prompt,
        mode: MidjourneyMode.fast,
      );
      
      if (result.isSuccess) {
        _showMessage('使用此 Prompt 生成完成');
        // TODO: 显示新生成的图片
      }
    } finally {
      setState(() => _isAnalyzing = false);
    }
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

### 场景 1: 学习 Prompt 编写

```dart
/// 分析优秀作品，学习描述技巧
Future<void> learnFromMasterpieces() async {
  final masterpieces = [
    'art1.jpg',
    'art2.jpg',
    'art3.jpg',
  ];

  print('📚 学习大师作品的描述方式：\n');

  for (final path in masterpieces) {
    final bytes = await File(path).readAsBytes();
    final base64 = base64Encode(bytes);

    final result = await helper.describeAndWait(
      imageBase64: base64,
      mode: MidjourneyMode.relax,
    );

    if (result.isSuccess) {
      print('🎨 $path:');
      print('   ${result.data!.bestPrompt}\n');
    }
  }
}
```

### 场景 2: Prompt 优化助手

```dart
/// 优化用户的 prompt
Future<String> optimizePrompt({
  required String userPrompt,
  required String referenceImage,
}) async {
  print('原始 prompt: $userPrompt');

  // 1. 分析参考图片
  final bytes = await File(referenceImage).readAsBytes();
  final base64 = base64Encode(bytes);

  final describeResult = await helper.describeAndWait(
    imageBase64: base64,
    mode: MidjourneyMode.fast,
  );

  if (describeResult.isSuccess) {
    final aiPrompt = describeResult.data!.bestPrompt;
    print('AI 建议: $aiPrompt');

    // 2. 合并用户 prompt 和 AI 建议
    final optimized = _mergePrompts(userPrompt, aiPrompt);
    print('优化后: $optimized');

    return optimized;
  }

  return userPrompt;
}

String _mergePrompts(String user, String ai) {
  // 简单合并策略
  final userTerms = user.split(',').map((s) => s.trim()).toSet();
  final aiTerms = ai.split(',').map((s) => s.trim()).toSet();

  // 保留用户的关键词，补充 AI 的描述
  final merged = {...userTerms, ...aiTerms.take(3)};

  return merged.join(', ');
}
```

### 场景 3: 风格分析器

```dart
/// 分析多张图片，提取共同风格
Future<String> analyzeStyle(List<String> imagePaths) async {
  final allPrompts = <String>[];

  // 分析所有图片
  for (final path in imagePaths) {
    final bytes = await File(path).readAsBytes();
    final base64 = base64Encode(bytes);

    final result = await helper.describeAndWait(
      imageBase64: base64,
      mode: MidjourneyMode.relax,
    );

    if (result.isSuccess) {
      allPrompts.addAll(result.data!.prompts);
    }
  }

  // 提取共同元素
  final commonTerms = _extractCommonTerms(allPrompts);

  return commonTerms.join(', ');
}

Set<String> _extractCommonTerms(List<String> prompts) {
  // 简单的词频分析
  final termCounts = <String, int>{};

  for (final prompt in prompts) {
    final terms = prompt.split(',').map((s) => s.trim().toLowerCase());
    
    for (final term in terms) {
      termCounts[term] = (termCounts[term] ?? 0) + 1;
    }
  }

  // 返回出现频率最高的术语
  final sorted = termCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return sorted.take(5).map((e) => e.key).toSet();
}
```

### 场景 4: 图片数据库建立

```dart
class ImageDatabase {
  final MidjourneyHelper helper;
  final Map<String, List<String>> _database = {};

  ImageDatabase(this.helper);

  /// 添加图片到数据库
  Future<void> addImage(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final base64 = base64Encode(bytes);

    final result = await helper.describeAndWait(
      imageBase64: base64,
      mode: MidjourneyMode.relax,
    );

    if (result.isSuccess) {
      _database[imagePath] = result.data!.prompts;
      print('已添加: $imagePath');
    }
  }

  /// 搜索相似图片
  List<String> search(String query) {
    final results = <String>[];

    _database.forEach((path, prompts) {
      for (final prompt in prompts) {
        if (prompt.toLowerCase().contains(query.toLowerCase())) {
          results.add(path);
          break;
        }
      }
    });

    return results;
  }

  /// 获取图片的所有描述
  List<String>? getDescriptions(String imagePath) {
    return _database[imagePath];
  }
}

// 使用
final db = ImageDatabase(helper);

// 添加图片
await db.addImage('landscape1.jpg');
await db.addImage('portrait1.jpg');
await db.addImage('abstract1.jpg');

// 搜索
final landscapes = db.search('mountain');
print('找到 ${landscapes.length} 张包含山的图片');
```

## 与其他操作结合

### Describe → Imagine

```dart
/// 分析图片 → 使用描述生成新图
Future<String?> cloneImage(String originalImage) async {
  // 1. Describe: 分析原图
  final bytes = await File(originalImage).readAsBytes();
  final base64 = base64Encode(bytes);

  final describeResult = await helper.describeAndWait(
    imageBase64: base64,
    mode: MidjourneyMode.fast,
  );

  if (!describeResult.isSuccess) {
    return null;
  }

  final prompt = describeResult.data!.bestPrompt;

  // 2. Imagine: 使用描述生成新图
  final imagineResult = await helper.submitAndWait(
    prompt: prompt,
    mode: MidjourneyMode.fast,
  );

  return imagineResult.data;
}
```

### Describe → 修改 Prompt → Imagine

```dart
/// 分析图片，修改某些元素，重新生成
Future<String?> reimagineWithChanges({
  required String originalImage,
  required Map<String, String> changes,  // 要修改的元素
}) async {
  // 1. Describe
  final bytes = await File(originalImage).readAsBytes();
  final describeResult = await helper.describeAndWait(
    imageBase64: base64Encode(bytes),
    mode: MidjourneyMode.fast,
  );

  if (!describeResult.isSuccess) {
    return null;
  }

  var prompt = describeResult.data!.bestPrompt;

  // 2. 应用修改
  changes.forEach((oldTerm, newTerm) {
    prompt = prompt.replaceAll(oldTerm, newTerm);
  });

  print('修改后的 prompt: $prompt');

  // 3. Imagine
  final imagineResult = await helper.submitAndWait(
    prompt: prompt,
    mode: MidjourneyMode.fast,
  );

  return imagineResult.data;
}

// 使用
final newImage = await reimagineWithChanges(
  originalImage: 'cat.jpg',
  changes: {
    'cat': 'dog',        // 将猫改为狗
    'black': 'white',    // 颜色改为白色
  },
);
```

## 高级功能

### 1. Prompt 质量评分

```dart
/// 评估 describe 生成的 prompt 质量
double evaluatePromptQuality(String prompt) {
  double score = 0.0;

  // 长度得分（60-150 字符较理想）
  final length = prompt.length;
  if (length >= 60 && length <= 150) {
    score += 0.3;
  }

  // 包含细节描述
  final detailKeywords = ['detailed', 'high quality', '8k', '4k', 'professional'];
  final hasDetails = detailKeywords.any((kw) => 
    prompt.toLowerCase().contains(kw)
  );
  if (hasDetails) score += 0.2;

  // 包含风格描述
  final styleKeywords = ['style', 'artistic', 'realistic', 'painting'];
  final hasStyle = styleKeywords.any((kw) => 
    prompt.toLowerCase().contains(kw)
  );
  if (hasStyle) score += 0.2;

  // 包含技术参数
  if (prompt.contains('--')) {
    score += 0.3;
  }

  return score;
}

// 使用
final result = await helper.describeAndWait(imageBase64: base64);

if (result.isSuccess) {
  for (final prompt in result.data!.prompts) {
    final quality = evaluatePromptQuality(prompt);
    print('Prompt: $prompt');
    print('质量评分: ${(quality * 100).toStringAsFixed(0)}%\n');
  }
}
```

### 2. 自动选择最佳 Prompt

```dart
Future<String> selectBestPrompt(String imageBase64) async {
  final result = await helper.describeAndWait(
    imageBase64: imageBase64,
    mode: MidjourneyMode.fast,
  );

  if (!result.isSuccess || result.data!.prompts.isEmpty) {
    return '';
  }

  // 评分并排序
  final scored = result.data!.prompts.map((prompt) {
    return MapEntry(prompt, evaluatePromptQuality(prompt));
  }).toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return scored.first.key;
}
```

### 3. Prompt 库管理

```dart
class PromptLibrary {
  final Map<String, PromptEntry> _library = {};

  /// 添加图片及其描述
  Future<void> addFromImage({
    required String imagePath,
    required MidjourneyHelper helper,
    String? category,
  }) async {
    final bytes = await File(imagePath).readAsBytes();
    final result = await helper.describeAndWait(
      imageBase64: base64Encode(bytes),
    );

    if (result.isSuccess) {
      final entry = PromptEntry(
        imagePath: imagePath,
        prompts: result.data!.prompts,
        category: category,
        addedAt: DateTime.now(),
      );

      _library[imagePath] = entry;
    }
  }

  /// 按类别搜索
  List<PromptEntry> searchByCategory(String category) {
    return _library.values
        .where((e) => e.category == category)
        .toList();
  }

  /// 按关键词搜索
  List<PromptEntry> searchByKeyword(String keyword) {
    return _library.values.where((entry) {
      return entry.prompts.any((p) => 
        p.toLowerCase().contains(keyword.toLowerCase())
      );
    }).toList();
  }

  /// 导出为 JSON
  String exportToJson() {
    return jsonEncode(
      _library.map((key, value) => MapEntry(key, value.toJson())),
    );
  }
}

class PromptEntry {
  final String imagePath;
  final List<String> prompts;
  final String? category;
  final DateTime addedAt;

  PromptEntry({
    required this.imagePath,
    required this.prompts,
    this.category,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
    'imagePath': imagePath,
    'prompts': prompts,
    'category': category,
    'addedAt': addedAt.toIso8601String(),
  };
}
```

## 最佳实践

### 1. 图片预处理

```dart
/// 优化图片以获得更好的 Describe 结果
Future<String> prepareImageForDescribe(String imagePath) async {
  final bytes = await File(imagePath).readAsBytes();
  final image = img.decodeImage(bytes);

  if (image == null) {
    throw Exception('无法解析图片');
  }

  // 调整大小（建议 512-1024px）
  final resized = image.width > 1024
      ? img.copyResize(image, width: 1024)
      : image;

  // 转换为 JPEG
  final jpeg = img.encodeJpg(resized, quality: 90);

  return base64Encode(jpeg);
}
```

### 2. 批量处理优化

```dart
class BatchDescriber {
  final MidjourneyHelper helper;
  final Duration _delay = Duration(seconds: 3);

  BatchDescriber(this.helper);

  Future<Map<String, List<String>>> describeMultiple(
    List<String> imagePaths,
  ) async {
    final results = <String, List<String>>{};

    for (int i = 0; i < imagePaths.length; i++) {
      final path = imagePaths[i];
      
      print('处理 ${i + 1}/${imagePaths.length}: $path');

      try {
        final bytes = await File(path).readAsBytes();
        final result = await helper.describeAndWait(
          imageBase64: base64Encode(bytes),
          mode: MidjourneyMode.relax,
        );

        if (result.isSuccess) {
          results[path] = result.data!.prompts;
        }
      } catch (e) {
        print('错误: $e');
      }

      // 避免请求过快
      if (i < imagePaths.length - 1) {
        await Future.delayed(_delay);
      }
    }

    return results;
  }
}
```

### 3. 智能 Prompt 生成器

```dart
class SmartPromptGenerator {
  final MidjourneyHelper helper;

  SmartPromptGenerator(this.helper);

  /// 基于参考图片生成智能 prompt
  Future<String?> generateFrom({
    required String referenceImage,
    String? styleModifier,
    List<String>? additionalKeywords,
  }) async {
    // 1. Describe 分析参考图
    final bytes = await File(referenceImage).readAsBytes();
    final describeResult = await helper.describeAndWait(
      imageBase64: base64Encode(bytes),
      mode: MidjourneyMode.fast,
    );

    if (!describeResult.isSuccess) {
      return null;
    }

    var prompt = describeResult.data!.bestPrompt;

    // 2. 应用风格修改
    if (styleModifier != null) {
      prompt = '$prompt, $styleModifier';
    }

    // 3. 添加额外关键词
    if (additionalKeywords != null && additionalKeywords.isNotEmpty) {
      prompt = '$prompt, ${additionalKeywords.join(", ")}';
    }

    return prompt;
  }
}

// 使用
final generator = SmartPromptGenerator(helper);

final prompt = await generator.generateFrom(
  referenceImage: 'reference.jpg',
  styleModifier: 'cyberpunk style',
  additionalKeywords: ['neon lights', 'rainy night'],
);

print('生成的 prompt: $prompt');

// 使用 prompt 生成新图
final result = await helper.submitAndWait(prompt: prompt!);
```

## 注意事项

1. **图片格式**: 支持 JPG、PNG 等常见格式
2. **图片大小**: 建议不超过 5MB
3. **响应时间**: 通常比 Imagine 快，但仍需轮询
4. **Prompt 数量**: 通常返回 4 个 prompt 建议
5. **语言**: 返回的 prompt 为英文

## 实用工具

### Describe 结果处理器

```dart
class DescribeResultProcessor {
  /// 提取关键词
  List<String> extractKeywords(List<String> prompts) {
    final allWords = <String>[];
    
    for (final prompt in prompts) {
      final words = prompt
          .split(RegExp(r'[,\s]+'))
          .where((w) => w.length > 3)
          .toList();
      
      allWords.addAll(words);
    }
    
    return allWords.toSet().toList();
  }

  /// 提取技术参数
  Map<String, String> extractParameters(String prompt) {
    final params = <String, String>{};
    final regex = RegExp(r'--(\w+)\s+([\w:\.]+)');
    
    for (final match in regex.allMatches(prompt)) {
      params[match.group(1)!] = match.group(2)!;
    }
    
    return params;
  }

  /// 美化显示
  String formatPrompt(String prompt) {
    // 分离描述和参数
    final parts = prompt.split('--');
    
    if (parts.length == 1) {
      return prompt;
    }
    
    final description = parts[0].trim();
    final parameters = parts.sublist(1).map((p) => '--$p').join(' ');
    
    return '$description\n参数: $parameters';
  }
}
```

## 错误处理

### 图片验证

```dart
Future<bool> validateImage(String base64String) async {
  try {
    // 检查格式
    if (!base64String.startsWith('data:image/')) {
      return false;
    }
    
    // 检查大小
    final sizeInBytes = base64String.length * 0.75;  // 估算
    final sizeInMB = sizeInBytes / (1024 * 1024);
    
    if (sizeInMB > 5) {
      print('图片过大: ${sizeInMB.toStringAsFixed(2)} MB');
      return false;
    }
    
    return true;
  } catch (e) {
    return false;
  }
}

// 使用
if (await validateImage(base64)) {
  await helper.describe(imageBase64: base64);
} else {
  print('图片验证失败');
}
```

## 完整示例：Prompt 学习工具

```dart
class PromptLearningTool {
  final MidjourneyHelper helper;

  PromptLearningTool(this.helper);

  /// 学习模式：上传图片，获取描述，学习 prompt 编写
  Future<void> learn(String imagePath) async {
    print('📚 Prompt 学习工具\n');
    print('正在分析图片: $imagePath\n');

    // 1. Describe
    final bytes = await File(imagePath).readAsBytes();
    final result = await helper.describeAndWait(
      imageBase64: base64Encode(bytes),
      mode: MidjourneyMode.fast,
    );

    if (!result.isSuccess) {
      print('分析失败');
      return;
    }

    final prompts = result.data!.prompts;

    // 2. 展示学习内容
    print('🎨 Midjourney 生成了 ${prompts.length} 个描述建议：\n');

    for (int i = 0; i < prompts.length; i++) {
      final prompt = prompts[i];
      
      print('📝 建议 ${i + 1}:');
      print('   $prompt\n');
      
      // 分析 prompt 结构
      _analyzePromptStructure(prompt);
      print('');
    }

    // 3. 推荐最佳 prompt
    final best = prompts.first;
    print('⭐ 推荐使用: $best\n');

    // 4. 询问是否要使用此 prompt 生成
    print('💡 提示: 你可以使用这些 prompt 来生成相似的图片');
  }

  void _analyzePromptStructure(String prompt) {
    final processor = DescribeResultProcessor();

    // 提取关键词
    final keywords = processor.extractKeywords([prompt]);
    print('   关键词: ${keywords.take(5).join(", ")}');

    // 提取参数
    final params = processor.extractParameters(prompt);
    if (params.isNotEmpty) {
      print('   参数: ${params.entries.map((e) => "${e.key}=${e.value}").join(", ")}');
    }
  }
}

// 使用
final learningTool = PromptLearningTool(helper);

await learningTool.learn('beautiful_artwork.jpg');
```

## API 规格

### 请求格式

```json
{
  "mode": "FAST",
  "base64": "data:image/png;base64,xxx",
  "botType": "mj",
  "state": "",
  "notifyhook": ""
}
```

### 响应格式

```json
{
  "code": 1,
  "description": "Submit success",
  "result": "1712205491372224"
}
```

### 结果数据（从任务状态获取）

```json
{
  "id": "task-id",
  "status": "SUCCESS",
  "prompts": [
    "A professional photograph of...",
    "High quality image featuring...",
    "Detailed illustration showing...",
    "Artistic rendering depicting..."
  ]
}
```

## 常见问题

**Q: Describe 生成几个 prompt？**  
A: 通常生成 4 个不同的 prompt 建议

**Q: 可以用中文图片吗？**  
A: 可以，但生成的描述是英文

**Q: Describe 需要多长时间？**  
A: FAST 模式约 10-20 秒，RELAX 模式约 30-60 秒

**Q: 可以用 Describe 的结果直接生成图片吗？**  
A: 可以！这是学习 Prompt 的好方法

**Q: Niji Bot 和 MJ Bot 的 Describe 有区别吗？**  
A: Niji Bot 更擅长分析动漫风格图片

## 相关文档

- **Midjourney 使用指南**: `MIDJOURNEY_USAGE.md`
- **Action 操作**: `MIDJOURNEY_ACTIONS.md`
- **Blend 融图**: `MIDJOURNEY_BLEND.md`
- **Modal 补充**: `MIDJOURNEY_MODAL.md`
- **快速参考**: `MIDJOURNEY_QUICK_REFERENCE.md`

---

**Describe 功能让你轻松学习如何编写优秀的 Prompt！📝✨**
