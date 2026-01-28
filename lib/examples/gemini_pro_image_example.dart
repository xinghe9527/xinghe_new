import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/api/base/api_config.dart';
import '../services/api/providers/gemini_pro_image_service.dart';

/// Gemini 3 Pro 图像生成示例
/// 
/// 这个示例展示了如何使用 GeminiProImageService 生成图片
class GeminiProImageExample extends StatefulWidget {
  const GeminiProImageExample({Key? key}) : super(key: key);

  @override
  State<GeminiProImageExample> createState() => _GeminiProImageExampleState();
}

class _GeminiProImageExampleState extends State<GeminiProImageExample> {
  GeminiProImageService? _service;
  
  String? _generatedImageBase64;
  bool _isLoading = false;
  String? _errorMessage;
  
  // UI 控件状态
  final TextEditingController _promptController = TextEditingController(
    text: 'A serene Japanese garden with cherry blossoms',
  );
  String _selectedRatio = '1:1';
  String _selectedQuality = '2K';
  
  @override
  void initState() {
    super.initState();
    _initService();
  }
  
  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }
  
  /// 初始化服务
  void _initService() {
    // TODO: 从环境变量或安全存储中获取 API Key
    const apiKey = 'YOUR_API_KEY'; // 替换为实际的 API Key
    
    final config = ApiConfig(
      provider: 'yunwu',
      apiKey: apiKey,
      baseUrl: 'https://yunwu.ai',
      model: 'gemini-3-pro-image-preview',
    );
    
    _service = GeminiProImageService(config);
  }
  
  /// 生成图片
  Future<void> _generateImage() async {
    if (_service == null) {
      setState(() {
        _errorMessage = '服务未初始化';
      });
      return;
    }
    
    if (_promptController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = '请输入提示词';
      });
      return;
    }
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _generatedImageBase64 = null;
    });
    
    try {
      final result = await _service!.generateImages(
        prompt: _promptController.text.trim(),
        ratio: _selectedRatio,
        quality: _selectedQuality,
      );
      
      if (result.isSuccess && result.data != null && result.data!.isNotEmpty) {
        final image = result.data!.first;
        setState(() {
          _generatedImageBase64 = image.base64Data;
        });
        
        // 打印一些调试信息
        print('图片生成成功!');
        print('完成原因: ${image.finishReason}');
        print('MIME 类型: ${image.mimeType}');
        print('数据大小: ${image.base64Data?.length ?? 0} bytes');
      } else {
        setState(() {
          _errorMessage = result.error ?? '未知错误';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '发生异常: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  /// 测试连接
  Future<void> _testConnection() async {
    if (_service == null) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final result = await _service!.testConnection();
      
      if (result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('连接成功!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() {
          _errorMessage = '连接失败: ${result.error}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '连接异常: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemini 3 Pro 图片生成'),
        actions: [
          IconButton(
            icon: const Icon(Icons.wifi),
            onPressed: _testConnection,
            tooltip: '测试连接',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 提示词输入
            TextField(
              controller: _promptController,
              decoration: const InputDecoration(
                labelText: '提示词',
                hintText: '输入您想生成的图片描述...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            
            const SizedBox(height: 16),
            
            // 宽高比选择
            DropdownButtonFormField<String>(
              value: _selectedRatio,
              decoration: const InputDecoration(
                labelText: '宽高比',
                border: OutlineInputBorder(),
              ),
              items: GeminiProImageService.supportedAspectRatios
                  .map((ratio) => DropdownMenuItem(
                        value: ratio,
                        child: Text(ratio),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedRatio = value;
                  });
                }
              },
            ),
            
            const SizedBox(height: 16),
            
            // 清晰度选择
            DropdownButtonFormField<String>(
              value: _selectedQuality,
              decoration: const InputDecoration(
                labelText: '清晰度',
                border: OutlineInputBorder(),
              ),
              items: GeminiProImageService.supportedImageSizes
                  .map((size) => DropdownMenuItem(
                        value: size,
                        child: Text(size),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedQuality = value;
                  });
                }
              },
            ),
            
            const SizedBox(height: 24),
            
            // 生成按钮
            ElevatedButton(
              onPressed: _isLoading ? null : _generateImage,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('生成图片'),
            ),
            
            const SizedBox(height: 24),
            
            // 错误消息
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade900),
                ),
              ),
            
            // 生成的图片
            if (_generatedImageBase64 != null) ...[
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    base64Decode(_generatedImageBase64!),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 命令行示例
/// 
/// 这个函数展示了如何在非 Flutter 环境中使用服务
Future<void> runCommandLineExample() async {
  print('=== Gemini 3 Pro 图像生成命令行示例 ===\n');
  
  // 1. 创建服务
  final config = ApiConfig(
    provider: 'yunwu',
    apiKey: 'YOUR_API_KEY',
    baseUrl: 'https://yunwu.ai',
    model: 'gemini-3-pro-image-preview',
  );
  
  final service = GeminiProImageService(config);
  
  // 2. 测试连接
  print('测试连接...');
  final connectionTest = await service.testConnection();
  if (!connectionTest.isSuccess) {
    print('❌ 连接失败');
    return;
  }
  print('✅ 连接成功\n');
  
  // 3. 生成图片
  print('生成图片...');
  final result = await service.generateImages(
    prompt: 'A cute cat playing with a ball of yarn',
    ratio: '1:1',
    quality: '2K',
  );
  
  if (result.isSuccess && result.data != null) {
    print('✅ 图片生成成功!');
    print('生成了 ${result.data!.length} 张图片');
    
    // 保存图片
    for (var i = 0; i < result.data!.length; i++) {
      final image = result.data![i];
      final base64Data = image.base64Data;
      
      if (base64Data != null) {
        final bytes = base64Decode(base64Data);
        final file = File('generated_image_$i.jpg');
        await file.writeAsBytes(bytes);
        print('图片已保存到: ${file.path}');
      }
    }
  } else {
    print('❌ 生成失败: ${result.error}');
  }
}

/// 批量生成示例
Future<void> batchGenerationExample() async {
  final config = ApiConfig(
    provider: 'yunwu',
    apiKey: 'YOUR_API_KEY',
    baseUrl: 'https://yunwu.ai',
    model: 'gemini-3-pro-image-preview',
  );
  
  final service = GeminiProImageService(config);
  
  // 定义多个任务
  final tasks = [
    {'prompt': 'A peaceful mountain landscape', 'ratio': '16:9'},
    {'prompt': 'A vibrant city at night', 'ratio': '9:16'},
    {'prompt': 'A cozy coffee shop interior', 'ratio': '1:1'},
  ];
  
  print('开始批量生成 ${tasks.length} 张图片...\n');
  
  for (var i = 0; i < tasks.length; i++) {
    final task = tasks[i];
    print('任务 ${i + 1}/${tasks.length}: ${task['prompt']}');
    
    final result = await service.generateImages(
      prompt: task['prompt'] as String,
      ratio: task['ratio'] as String?,
      quality: '2K',
    );
    
    if (result.isSuccess && result.data != null) {
      print('  ✅ 成功');
    } else {
      print('  ❌ 失败: ${result.error}');
    }
  }
  
  print('\n批量生成完成!');
}

/// 使用参考图片的示例
Future<void> imageToImageExample() async {
  final config = ApiConfig(
    provider: 'yunwu',
    apiKey: 'YOUR_API_KEY',
    baseUrl: 'https://yunwu.ai',
    model: 'gemini-3-pro-image-preview',
  );
  
  final service = GeminiProImageService(config);
  
  // 使用参考图片生成新图片
  final result = await service.generateImages(
    prompt: 'Transform this into a watercolor painting style',
    referenceImages: [
      'path/to/reference/image.jpg',
    ],
    ratio: '1:1',
    quality: '2K',
  );
  
  if (result.isSuccess && result.data != null) {
    print('图生图成功!');
    // 处理生成的图片...
  } else {
    print('图生图失败: ${result.error}');
  }
}
