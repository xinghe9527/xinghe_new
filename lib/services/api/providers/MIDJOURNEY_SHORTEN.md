# Midjourney Shorten 操作指南

## 概述

Shorten 是 Midjourney 的 Prompt 优化工具，可以分析并简化冗长的 prompt，提取关键要素。

### 主要用途

1. **简化冗长 Prompt** - 去除冗余信息
2. **提取关键词** - 保留核心描述
3. **优化效率** - 减少 Token 消耗
4. **学习工具** - 了解哪些词最重要

## 快速开始

### 基础用法

```dart
import 'package:xinghe_new/services/api/providers/midjourney_service.dart';

final helper = MidjourneyHelper(MidjourneyService(config));

// 优化冗长的 prompt
final longPrompt = '''
  A very detailed and extremely beautiful landscape photograph 
  showing a magnificent sunset over the mountains with lots of 
  trees and a lake in the foreground, shot with professional 
  camera equipment using high quality lenses
''';

final result = await helper.shorten(
  prompt: longPrompt,
  mode: MidjourneyMode.fast,
);

if (result.isSuccess) {
  print('Shorten 任务已提交: ${result.data!.taskId}');
}
```

### 自动等待结果

```dart
// 一键优化并获取结果
final result = await helper.shortenAndWait(
  prompt: longPrompt,
  mode: MidjourneyMode.fast,
  maxWaitMinutes: 2,
);

if (result.isSuccess) {
  final shortenResult = result.data!;
  
  print('原始 Prompt (${shortenResult.originalPrompt.length} 字符):');
  print(shortenResult.originalPrompt);
  
  print('\n优化建议:');
  for (int i = 0; i < shortenResult.shortenedPrompts.length; i++) {
    final shortened = shortenResult.shortenedPrompts[i];
    print('${i + 1}. $shortened (${shortened.length} 字符)');
  }
  
  print('\n最佳优化版本:');
  print(shortenResult.bestShortened);
  
  print('\n优化比例: ${(shortenResult.optimizationRatio * 100).toStringAsFixed(1)}%');
}
```

## 使用示例

### 示例 1: 基础 Prompt 优化

```dart
final config = ApiConfig(
  baseUrl: 'YOUR_BASE_URL',
  apiKey: 'YOUR_API_KEY',
);

final helper = MidjourneyHelper(MidjourneyService(config));

// 原始冗长 prompt
final original = '''
  A photograph of a cute fluffy white cat sitting on a comfortable 
  soft cushion in a bright sunny room with large windows
''';

// 优化
final result = await helper.shortenAndWait(
  prompt: original,
  mode: MidjourneyMode.fast,
);

if (result.isSuccess) {
  final shortened = result.data!.bestShortened;
  
  print('原始: $original');
  print('优化: $shortened');
  print('节省: ${(result.data!.optimizationRatio * 100).toInt()}%');
}
```

### 示例 2: 批量优化 Prompts

```dart
final prompts = [
  'A very detailed image of a red apple on a wooden table',
  'An extremely beautiful sunset over the ocean with birds',
  'A professional photograph of a modern building architecture',
];

final optimized = <String>[];

for (final prompt in prompts) {
  final result = await helper.shortenAndWait(
    prompt: prompt,
    mode: MidjourneyMode.relax,
  );
  
  if (result.isSuccess) {
    optimized.add(result.data!.bestShortened);
    print('✅ $prompt');
    print('→  ${result.data!.bestShortened}\n');
  }
  
  await Future.delayed(Duration(seconds: 2));
}

print('批量优化完成，共 ${optimized.length} 个');
```

### 示例 3: Shorten → Imagine 工作流

```dart
/// 优化 prompt 后生成图片
Future<String?> optimizeAndGenerate(String longPrompt) async {
  print('原始 Prompt: $longPrompt\n');
  
  // 1. Shorten: 优化 prompt
  print('步骤 1: 优化 Prompt');
  final shortenResult = await helper.shortenAndWait(
    prompt: longPrompt,
    mode: MidjourneyMode.fast,
  );
  
  if (!shortenResult.isSuccess) {
    return null;
  }
  
  final optimized = shortenResult.data!.bestShortened;
  print('优化后: $optimized');
  print('节省: ${(shortenResult.data!.optimizationRatio * 100).toInt()}%\n');
  
  // 2. Imagine: 使用优化的 prompt 生成
  print('步骤 2: 使用优化的 Prompt 生成图片');
  final imagineResult = await helper.submitAndWait(
    prompt: optimized,
    mode: MidjourneyMode.fast,
  );
  
  if (imagineResult.isSuccess) {
    print('✅ 生成完成');
    return imagineResult.data;
  }
  
  return null;
}
```

### 示例 4: 对比测试

```dart
/// 对比原始和优化后的效果
Future<void> compareResults(String longPrompt) async {
  // 1. 使用原始 prompt 生成
  print('使用原始 Prompt 生成...');
  final original = await helper.submitAndWait(
    prompt: longPrompt,
    mode: MidjourneyMode.fast,
  );
  
  // 2. 优化 prompt
  print('优化 Prompt...');
  final shortenResult = await helper.shortenAndWait(
    prompt: longPrompt,
    mode: MidjourneyMode.fast,
  );
  
  if (!shortenResult.isSuccess) {
    return;
  }
  
  // 3. 使用优化后的 prompt 生成
  print('使用优化后的 Prompt 生成...');
  final optimized = await helper.submitAndWait(
    prompt: shortenResult.data!.bestShortened,
    mode: MidjourneyMode.fast,
  );
  
  // 4. 对比
  print('\n===== 对比结果 =====');
  print('原始 Prompt: $longPrompt');
  print('原始结果: ${original.data}');
  print('\n优化 Prompt: ${shortenResult.data!.bestShortened}');
  print('优化结果: ${optimized.data}');
  print('\nPrompt 长度减少: ${(shortenResult.data!.optimizationRatio * 100).toInt()}%');
}
```

## 在 Flutter 中使用

### Prompt 优化器 Widget

```dart
class PromptOptimizerWidget extends StatefulWidget {
  @override
  State<PromptOptimizerWidget> createState() => _PromptOptimizerWidgetState();
}

class _PromptOptimizerWidgetState extends State<PromptOptimizerWidget> {
  final _helper = MidjourneyHelper(
    MidjourneyService(ApiConfig(
      baseUrl: 'YOUR_BASE_URL',
      apiKey: 'YOUR_API_KEY',
    )),
  );

  final _promptController = TextEditingController();
  List<String> _optimizedPrompts = [];
  bool _isOptimizing = false;
  String? _selectedOptimized;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Prompt 优化器',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        
        SizedBox(height: 16),
        
        // 输入原始 prompt
        TextField(
          controller: _promptController,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: '输入冗长的 Prompt',
            hintText: '粘贴你的 prompt，系统会帮你优化...',
            border: OutlineInputBorder(),
          ),
        ),
        
        SizedBox(height: 12),
        
        // 字符统计
        Text(
          '当前长度: ${_promptController.text.length} 字符',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        
        SizedBox(height: 16),
        
        // 优化按钮
        ElevatedButton(
          onPressed: _isOptimizing ? null : _optimizePrompt,
          child: Text(_isOptimizing ? '优化中...' : '优化 Prompt'),
        ),
        
        // 显示优化结果
        if (_optimizedPrompts.isNotEmpty) ...[
          SizedBox(height: 24),
          Text(
            '优化建议:',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 12),
          
          ..._optimizedPrompts.asMap().entries.map((entry) {
            return _buildOptimizedPromptCard(
              index: entry.key + 1,
              prompt: entry.value,
            );
          }).toList(),
          
          SizedBox(height: 16),
          
          // 使用优化后的 prompt 生成
          if (_selectedOptimized != null)
            ElevatedButton.icon(
              onPressed: () => _generateWithOptimized(_selectedOptimized!),
              icon: Icon(Icons.image),
              label: Text('使用此 Prompt 生成图片'),
            ),
        ],
      ],
    );
  }

  Widget _buildOptimizedPromptCard({
    required int index,
    required String prompt,
  }) {
    final isSelected = _selectedOptimized == prompt;
    
    return Card(
      color: isSelected ? Colors.blue.withOpacity(0.1) : null,
      child: InkWell(
        onTap: () {
          setState(() => _selectedOptimized = prompt);
        },
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '建议 $index',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    '${prompt.length} 字符',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  Spacer(),
                  if (isSelected)
                    Icon(Icons.check_circle, color: Colors.blue, size: 20),
                  IconButton(
                    icon: Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: prompt));
                      _showMessage('已复制');
                    },
                  ),
                ],
              ),
              SizedBox(height: 8),
              Text(prompt),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _optimizePrompt() async {
    final prompt = _promptController.text.trim();
    
    if (prompt.isEmpty) {
      _showMessage('请输入 Prompt');
      return;
    }

    setState(() {
      _isOptimizing = true;
      _optimizedPrompts.clear();
      _selectedOptimized = null;
    });

    try {
      final result = await _helper.shortenAndWait(
        prompt: prompt,
        mode: MidjourneyMode.fast,
      );

      if (result.isSuccess) {
        setState(() {
          _optimizedPrompts = result.data!.shortenedPrompts;
          _selectedOptimized = result.data!.bestShortened;
        });
        
        _showMessage('优化完成！生成了 ${_optimizedPrompts.length} 个建议');
      } else {
        _showMessage('优化失败: ${result.errorMessage}', isError: true);
      }
    } finally {
      setState(() => _isOptimizing = false);
    }
  }

  Future<void> _generateWithOptimized(String optimizedPrompt) async {
    // 使用优化后的 prompt 生成图片
    final result = await _helper.submitAndWait(
      prompt: optimizedPrompt,
      mode: MidjourneyMode.fast,
    );
    
    if (result.isSuccess) {
      _showMessage('生成完成！');
      // TODO: 显示生成的图片
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

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }
}
```

## 实用场景

### 场景 1: 新手 Prompt 优化

```dart
/// 帮助新手优化他们的 prompt
Future<void> helpOptimize(String userPrompt) async {
  print('用户输入: $userPrompt\n');
  
  // 优化
  final result = await helper.shortenAndWait(
    prompt: userPrompt,
    mode: MidjourneyMode.fast,
  );
  
  if (result.isSuccess) {
    print('系统建议:');
    
    for (int i = 0; i < result.data!.shortenedPrompts.length; i++) {
      final optimized = result.data!.shortenedPrompts[i];
      print('${i + 1}. $optimized');
    }
    
    print('\n💡 学习要点:');
    print('- 原长度: ${result.data!.originalPrompt.length} 字符');
    print('- 新长度: ${result.data!.bestShortened.length} 字符');
    print('- 优化了: ${(result.data!.optimizationRatio * 100).toInt()}%');
  }
}
```

### 场景 2: Prompt 质量检查器

```dart
class PromptQualityChecker {
  final MidjourneyHelper helper;

  PromptQualityChecker(this.helper);

  /// 检查并优化 prompt
  Future<PromptAnalysis> analyze(String prompt) async {
    final analysis = PromptAnalysis(original: prompt);
    
    // 1. 长度检查
    if (prompt.length > 200) {
      analysis.warnings.add('Prompt 过长，建议优化');
      
      // 2. 自动优化
      final shortenResult = await helper.shortenAndWait(
        prompt: prompt,
        mode: MidjourneyMode.fast,
      );
      
      if (shortenResult.isSuccess) {
        analysis.optimized = shortenResult.data!.bestShortened;
        analysis.suggestions = shortenResult.data!.shortenedPrompts;
      }
    } else {
      analysis.warnings.add('Prompt 长度适中');
    }
    
    return analysis;
  }
}

class PromptAnalysis {
  final String original;
  String? optimized;
  List<String> suggestions = [];
  List<String> warnings = [];

  PromptAnalysis({required this.original});

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('原始: $original');
    
    if (warnings.isNotEmpty) {
      buffer.writeln('\n警告:');
      for (final warning in warnings) {
        buffer.writeln('  ⚠️  $warning');
      }
    }
    
    if (optimized != null) {
      buffer.writeln('\n建议: $optimized');
    }
    
    if (suggestions.isNotEmpty) {
      buffer.writeln('\n其他建议:');
      for (int i = 0; i < suggestions.length; i++) {
        buffer.writeln('  ${i + 1}. ${suggestions[i]}');
      }
    }
    
    return buffer.toString();
  }
}

// 使用
final checker = PromptQualityChecker(helper);

final analysis = await checker.analyze(
  'A very very detailed and beautiful photograph of a cat',
);

print(analysis);
```

### 场景 3: 智能 Prompt 助手

```dart
class SmartPromptAssistant {
  final MidjourneyHelper helper;

  SmartPromptAssistant(this.helper);

  /// 智能优化：根据长度自动决定是否需要 shorten
  Future<String> smartOptimize(String prompt) async {
    // 短 prompt（< 100 字符）：直接返回
    if (prompt.length < 100) {
      print('✅ Prompt 已经很简洁');
      return prompt;
    }
    
    // 中等长度（100-200 字符）：轻度优化
    if (prompt.length < 200) {
      print('ℹ️  Prompt 适中，进行轻度优化');
      final result = await helper.shortenAndWait(prompt: prompt);
      return result.data?.bestShortened ?? prompt;
    }
    
    // 长 prompt（> 200 字符）：强力优化
    print('⚠️  Prompt 过长，进行强力优化');
    final result = await helper.shortenAndWait(prompt: prompt);
    
    if (result.isSuccess) {
      final optimized = result.data!.bestShortened;
      print('优化: ${prompt.length} → ${optimized.length} 字符');
      return optimized;
    }
    
    return prompt;
  }
}

// 使用
final assistant = SmartPromptAssistant(helper);

final userPrompt = _promptController.text;
final optimized = await assistant.smartOptimize(userPrompt);

print('最终使用: $optimized');
```

## 与其他功能结合

### Describe + Shorten

```dart
/// 从图片提取 prompt，然后优化
Future<String?> extractAndOptimize(String imagePath) async {
  // 1. Describe: 从图片提取 prompt
  final bytes = await File(imagePath).readAsBytes();
  final describeResult = await helper.describeAndWait(
    imageBase64: base64Encode(bytes),
    mode: MidjourneyMode.fast,
  );
  
  if (!describeResult.isSuccess) {
    return null;
  }
  
  final describedPrompt = describeResult.data!.bestPrompt;
  print('Describe 结果: $describedPrompt');
  
  // 2. Shorten: 优化提取的 prompt
  final shortenResult = await helper.shortenAndWait(
    prompt: describedPrompt,
    mode: MidjourneyMode.fast,
  );
  
  if (shortenResult.isSuccess) {
    final optimized = shortenResult.data!.bestShortened;
    print('Shorten 结果: $optimized');
    return optimized;
  }
  
  return null;
}
```

### Shorten + Prompt Builder

```dart
/// 优化后使用 PromptBuilder 添加参数
Future<String> optimizeAndEnhance(String longPrompt) async {
  // 1. Shorten: 简化描述
  final shortenResult = await helper.shortenAndWait(
    prompt: longPrompt,
    mode: MidjourneyMode.fast,
  );
  
  if (!shortenResult.isSuccess) {
    return longPrompt;
  }
  
  final simplified = shortenResult.data!.bestShortened;
  
  // 2. PromptBuilder: 添加参数
  final builder = MidjourneyPromptBuilder();
  final enhanced = builder
    .withDescription(simplified)
    .withAspectRatio('16:9')
    .withVersion('6')
    .withQuality(2.0)
    .withStylize(500)
    .build();
  
  print('原始: $longPrompt');
  print('简化: $simplified');
  print('增强: $enhanced');
  
  return enhanced;
}
```

## 高级功能

### 1. Prompt 学习系统

```dart
class PromptLearningSystem {
  final MidjourneyHelper helper;
  final List<PromptPair> _history = [];

  PromptLearningSystem(this.helper);

  /// 记录优化历史
  Future<void> learn(String prompt) async {
    final result = await helper.shortenAndWait(prompt: prompt);
    
    if (result.isSuccess) {
      final pair = PromptPair(
        original: prompt,
        optimized: result.data!.bestShortened,
        savedChars: prompt.length - result.data!.bestShortened.length,
      );
      
      _history.add(pair);
    }
  }

  /// 分析学习内容
  String analyzeLearnings() {
    if (_history.isEmpty) {
      return '暂无学习记录';
    }
    
    final totalSaved = _history.fold<int>(
      0,
      (sum, pair) => sum + pair.savedChars,
    );
    
    final avgRatio = _history.fold<double>(
      0,
      (sum, pair) => sum + (pair.savedChars / pair.original.length),
    ) / _history.length;
    
    return '''
    学习统计:
    - 优化次数: ${_history.length}
    - 平均节省: ${(avgRatio * 100).toStringAsFixed(1)}%
    - 总节省字符: $totalSaved
    
    建议:
    ${_generateTips()}
    ''';
  }

  String _generateTips() {
    // 分析常见的冗余词
    final redundantWords = <String>[];
    
    for (final pair in _history) {
      final removed = _findRemovedWords(pair.original, pair.optimized);
      redundantWords.addAll(removed);
    }
    
    final common = _mostCommon(redundantWords, 5);
    
    return '避免使用: ${common.join(", ")}';
  }

  List<String> _findRemovedWords(String original, String optimized) {
    final origWords = original.toLowerCase().split(RegExp(r'\W+'));
    final optWords = optimized.toLowerCase().split(RegExp(r'\W+'));
    
    return origWords.where((w) => !optWords.contains(w)).toList();
  }

  List<String> _mostCommon(List<String> words, int count) {
    final freq = <String, int>{};
    for (final word in words) {
      freq[word] = (freq[word] ?? 0) + 1;
    }
    
    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return sorted.take(count).map((e) => e.key).toList();
  }
}

class PromptPair {
  final String original;
  final String optimized;
  final int savedChars;

  PromptPair({
    required this.original,
    required this.optimized,
    required this.savedChars,
  });
}
```

### 2. A/B 测试工具

```dart
/// 对比原始和优化版本的生成效果
Future<void> abTest(String longPrompt) async {
  print('🔬 A/B 测试开始\n');
  
  // A 组：原始 prompt
  print('A 组: 使用原始 Prompt');
  final startA = DateTime.now();
  
  final resultA = await helper.submitAndWait(
    prompt: longPrompt,
    mode: MidjourneyMode.fast,
  );
  
  final timeA = DateTime.now().difference(startA);
  
  // B 组：优化后的 prompt
  print('B 组: 使用优化 Prompt');
  final shortenResult = await helper.shortenAndWait(prompt: longPrompt);
  
  if (!shortenResult.isSuccess) {
    print('优化失败');
    return;
  }
  
  final optimized = shortenResult.data!.bestShortened;
  final startB = DateTime.now();
  
  final resultB = await helper.submitAndWait(
    prompt: optimized,
    mode: MidjourneyMode.fast,
  );
  
  final timeB = DateTime.now().difference(startB);
  
  // 结果对比
  print('\n📊 测试结果:');
  print('A 组 (原始):');
  print('  Prompt: $longPrompt');
  print('  耗时: ${timeA.inSeconds}秒');
  print('  结果: ${resultA.data}');
  
  print('\nB 组 (优化):');
  print('  Prompt: $optimized');
  print('  耗时: ${timeB.inSeconds}秒');
  print('  结果: ${resultB.data}');
  
  print('\n节省 Prompt 长度: ${longPrompt.length - optimized.length} 字符');
}
```

## 最佳实践

### 1. 何时使用 Shorten

**使用 Shorten 当**:
- ✅ Prompt 超过 150 字符
- ✅ 包含大量重复描述
- ✅ 想学习如何简化表达
- ✅ 优化 Token 消耗

**不需要 Shorten 当**:
- ❌ Prompt 已经很简洁（< 100 字符）
- ❌ 每个词都很关键
- ❌ 需要保留所有细节

### 2. 优化策略

```dart
String getOptimizationStrategy(String prompt) {
  final length = prompt.length;
  
  if (length < 100) {
    return '无需优化';
  } else if (length < 200) {
    return '建议轻度优化';
  } else {
    return '强烈建议优化';
  }
}

// 使用
final strategy = getOptimizationStrategy(userPrompt);
print(strategy);

if (strategy != '无需优化') {
  await helper.shortenAndWait(prompt: userPrompt);
}
```

### 3. 保存优化历史

```dart
class OptimizationHistory {
  final _history = <OptimizationRecord>[];

  void add({
    required String original,
    required String optimized,
    required double ratio,
  }) {
    _history.add(OptimizationRecord(
      original: original,
      optimized: optimized,
      optimizationRatio: ratio,
      timestamp: DateTime.now(),
    ));
  }

  List<OptimizationRecord> get recent => _history.reversed.take(10).toList();

  double get averageOptimization {
    if (_history.isEmpty) return 0;
    return _history.map((r) => r.optimizationRatio).reduce((a, b) => a + b) / 
           _history.length;
  }
}

class OptimizationRecord {
  final String original;
  final String optimized;
  final double optimizationRatio;
  final DateTime timestamp;

  OptimizationRecord({
    required this.original,
    required this.optimized,
    required this.optimizationRatio,
    required this.timestamp,
  });
}
```

## 注意事项

1. **优化程度**: Shorten 会保留核心内容，去除冗余
2. **多个建议**: 通常返回多个优化版本供选择
3. **响应时间**: 比 Imagine 快，通常 10-30 秒
4. **适用范围**: 主要用于优化英文 prompt
5. **Token 节省**: 优化后的 prompt 消耗更少资源

## 完整示例：Prompt 优化中心

```dart
class PromptOptimizationCenter {
  final MidjourneyHelper helper;

  PromptOptimizationCenter(this.helper);

  /// 完整的优化服务
  Future<OptimizationReport> optimize(String prompt) async {
    final report = OptimizationReport(original: prompt);
    
    // 1. 分析原始 prompt
    print('📊 分析原始 Prompt...');
    report.originalLength = prompt.length;
    report.originalWordCount = prompt.split(RegExp(r'\s+')).length;
    
    // 2. 执行优化
    print('🔧 优化中...');
    final result = await helper.shortenAndWait(
      prompt: prompt,
      mode: MidjourneyMode.fast,
    );
    
    if (!result.isSuccess) {
      report.error = result.errorMessage;
      return report;
    }
    
    // 3. 分析优化结果
    final shortened = result.data!;
    report.optimizedPrompts = shortened.shortenedPrompts;
    report.bestOptimized = shortened.bestShortened;
    report.optimizedLength = shortened.bestShortened.length;
    report.optimizedWordCount = shortened.bestShortened.split(RegExp(r'\s+')).length;
    report.optimizationRatio = shortened.optimizationRatio;
    
    // 4. 生成建议
    report.suggestions = _generateSuggestions(prompt, shortened.bestShortened);
    
    return report;
  }

  List<String> _generateSuggestions(String original, String optimized) {
    final suggestions = <String>[];
    
    // 分析删除的词
    final origWords = original.toLowerCase().split(RegExp(r'\W+'));
    final optWords = optimized.toLowerCase().split(RegExp(r'\W+'));
    final removed = origWords.where((w) => !optWords.contains(w)).toList();
    
    if (removed.isNotEmpty) {
      suggestions.add('删除了这些词: ${removed.take(5).join(", ")}');
    }
    
    // 长度建议
    if (optimized.length < 80) {
      suggestions.add('✅ 优化后的 prompt 简洁高效');
    } else if (optimized.length > 150) {
      suggestions.add('⚠️  可能还需要进一步优化');
    }
    
    return suggestions;
  }
}

class OptimizationReport {
  final String original;
  int originalLength = 0;
  int originalWordCount = 0;
  
  List<String> optimizedPrompts = [];
  String? bestOptimized;
  int optimizedLength = 0;
  int optimizedWordCount = 0;
  double optimizationRatio = 0;
  
  List<String> suggestions = [];
  String? error;

  OptimizationReport({required this.original});

  @override
  String toString() {
    if (error != null) {
      return '错误: $error';
    }
    
    return '''
    📈 优化报告
    
    原始 Prompt:
    - 内容: $original
    - 长度: $originalLength 字符
    - 词数: $originalWordCount 词
    
    优化后:
    - 内容: $bestOptimized
    - 长度: $optimizedLength 字符
    - 词数: $optimizedWordCount 词
    
    效果:
    - 节省: ${(optimizationRatio * 100).toStringAsFixed(1)}%
    - 减少: ${originalLength - optimizedLength} 字符
    
    建议:
    ${suggestions.map((s) => '  • $s').join('\n')}
    
    其他优化版本:
    ${optimizedPrompts.asMap().entries.map((e) => '  ${e.key + 1}. ${e.value}').join('\n')}
    ''';
  }
}

// 使用
final center = PromptOptimizationCenter(helper);

final report = await center.optimize(
  'A very detailed and extremely beautiful photograph...',
);

print(report);
```

## 性能和成本

### Token 节省

| 原始长度 | 优化后 | 节省比例 | Token 节省 |
|---------|--------|----------|-----------|
| 200 字符 | ~120 | ~40% | 显著 |
| 150 字符 | ~100 | ~33% | 中等 |
| 100 字符 | ~80 | ~20% | 较小 |

### 建议的使用频率

```dart
// 开发阶段：经常使用
// 帮助学习如何写简洁的 prompt

// 生产环境：按需使用
// 当用户 prompt 过长时自动优化
if (userPrompt.length > 150) {
  final optimized = await helper.shortenAndWait(prompt: userPrompt);
  // 使用优化后的版本
}
```

## 常见问题

**Q: Shorten 会改变 prompt 的含义吗？**  
A: 不会，只是简化表达，保留核心含义

**Q: 所有 prompt 都需要 shorten 吗？**  
A: 不需要，只有冗长的 prompt 才建议优化

**Q: Shorten 生成几个优化版本？**  
A: 通常 3-5 个不同的优化版本

**Q: 可以多次 shorten 吗？**  
A: 可以，但通常一次就够了

**Q: Shorten 和 Describe 有什么区别？**  
A: 
- Describe: 图片 → 文本（分析）
- Shorten: 文本 → 文本（优化）

## 相关文档

- **Describe 图生文**: `MIDJOURNEY_DESCRIBE.md`
- **Midjourney 使用**: `MIDJOURNEY_USAGE.md`
- **快速参考**: `MIDJOURNEY_QUICK_REFERENCE.md`

---

**Shorten 让你的 Prompt 更简洁高效！✂️✨**
