import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:xinghe_new/services/api/providers/gemini_image_service.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';
import 'package:xinghe_new/services/api/base/api_response.dart';
import 'package:xinghe_new/main.dart';

/// Gemini 图像生成完整示例
/// 
/// 此示例展示了如何使用 GeminiImageService 进行：
/// 1. 文生图
/// 2. 图生图（融合多张图片）
/// 3. 不同宽高比和清晰度的图像生成
class GeminiImageExample extends StatefulWidget {
  const GeminiImageExample({super.key});

  @override
  State<GeminiImageExample> createState() => _GeminiImageExampleState();
}

class _GeminiImageExampleState extends State<GeminiImageExample> {
  late final GeminiImageHelper _helper;
  final TextEditingController _promptController = TextEditingController();
  
  String? _generatedImageUrl;
  bool _isGenerating = false;
  String _selectedRatio = ImageAspectRatio.landscape;
  String _selectedQuality = ImageQuality.medium;
  List<String> _referenceImages = [];

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  void _initializeService() {
    // 创建 Gemini 配置
    final config = ApiConfig(
      provider: 'Gemini',
      baseUrl: 'YOUR_BASE_URL', // 替换为实际的 Base URL
      apiKey: 'YOUR_API_KEY',   // 替换为实际的 API Key
      model: 'gemini-2.5-flash-image',
    );

    // 创建服务和辅助类
    final service = GeminiImageService(config);
    _helper = GeminiImageHelper(service);
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: themeNotifier,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: AppTheme.scaffoldBackground,
          appBar: AppBar(
            title: const Text('Gemini 图像生成示例'),
            backgroundColor: AppTheme.surfaceBackground,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPromptSection(),
                const SizedBox(height: 24),
                _buildOptionsSection(),
                const SizedBox(height: 24),
                _buildReferenceImagesSection(),
                const SizedBox(height: 24),
                _buildGenerateButton(),
                const SizedBox(height: 24),
                _buildResultSection(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==================== UI 组件 ====================

  Widget _buildPromptSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '图像描述',
          style: TextStyle(
            color: AppTheme.textColor,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _promptController,
          maxLines: 3,
          style: TextStyle(color: AppTheme.textColor),
          decoration: InputDecoration(
            hintText: '请输入图像描述，例如：一只睡觉的猫',
            hintStyle: TextStyle(color: AppTheme.subTextColor),
            filled: true,
            fillColor: AppTheme.inputBackground,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '生成选项',
          style: TextStyle(
            color: AppTheme.textColor,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildOptionDropdown(
                label: '宽高比',
                value: _selectedRatio,
                items: {
                  ImageAspectRatio.square: '1:1 正方形',
                  ImageAspectRatio.landscape: '16:9 横向',
                  ImageAspectRatio.portrait: '9:16 竖向',
                  ImageAspectRatio.landscape43: '4:3 横向',
                  ImageAspectRatio.portrait34: '3:4 竖向',
                },
                onChanged: (value) {
                  setState(() => _selectedRatio = value!);
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildOptionDropdown(
                label: '清晰度',
                value: _selectedQuality,
                items: {
                  ImageQuality.low: '1K 标清',
                  ImageQuality.medium: '2K 高清',
                  ImageQuality.high: '4K 超清',
                },
                onChanged: (value) {
                  setState(() => _selectedQuality = value!);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOptionDropdown({
    required String label,
    required String value,
    required Map<String, String> items,
    required Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppTheme.subTextColor,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.inputBackground,
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: AppTheme.surfaceBackground,
            style: TextStyle(color: AppTheme.textColor),
            items: items.entries.map((entry) {
              return DropdownMenuItem(
                value: entry.key,
                child: Text(entry.value),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildReferenceImagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '参考图片（可选）',
              style: TextStyle(
                color: AppTheme.textColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '用于图生图',
              style: TextStyle(
                color: AppTheme.subTextColor,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_referenceImages.isEmpty)
          _buildAddImageButton()
        else
          _buildImagesList(),
      ],
    );
  }

  Widget _buildAddImageButton() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.inputBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppTheme.dividerColor,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 40,
              color: AppTheme.subTextColor,
            ),
            const SizedBox(height: 8),
            Text(
              '点击添加参考图片',
              style: TextStyle(
                color: AppTheme.subTextColor,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagesList() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ..._referenceImages.asMap().entries.map((entry) {
          return Stack(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image: DecorationImage(
                    image: MemoryImage(base64Decode(entry.value)),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _referenceImages.removeAt(entry.key);
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        }).toList(),
        // 添加更多按钮
        GestureDetector(
          onTap: _pickImage,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppTheme.inputBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.dividerColor),
            ),
            child: Icon(
              Icons.add,
              color: AppTheme.subTextColor,
              size: 32,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGenerateButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _isGenerating ? null : _generateImage,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accentColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: _isGenerating
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text('生成中...', style: TextStyle(fontSize: 16)),
                ],
              )
            : const Text('生成图像', style: TextStyle(fontSize: 16)),
      ),
    );
  }

  Widget _buildResultSection() {
    if (_generatedImageUrl == null) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: AppTheme.surfaceBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.image_outlined,
                size: 64,
                color: AppTheme.subTextColor.withOpacity(0.3),
              ),
              const SizedBox(height: 16),
              Text(
                '生成的图片将在这里显示',
                style: TextStyle(
                  color: AppTheme.subTextColor,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '生成结果',
          style: TextStyle(
            color: AppTheme.textColor,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              _generatedImageUrl!,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  height: 300,
                  alignment: Alignment.center,
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: _downloadImage,
              icon: const Icon(Icons.download),
              label: const Text('下载图片'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () {
                setState(() => _generatedImageUrl = null);
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重新生成'),
            ),
          ],
        ),
      ],
    );
  }

  // ==================== 功能方法 ====================

  /// 生成图像
  Future<void> _generateImage() async {
    final prompt = _promptController.text.trim();
    
    if (prompt.isEmpty) {
      _showMessage('请输入图像描述');
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final ApiResponse<List<ImageResponse>> result;
      
      // 根据是否有参考图片选择生成方式
      if (_referenceImages.isEmpty) {
        // 文生图
        result = await _helper.textToImage(
          prompt: prompt,
          ratio: _selectedRatio,
          quality: _selectedQuality,
        );
      } else {
        // 图生图
        result = await _helper.imageToImage(
          prompt: prompt,
          referenceImages: _referenceImages,
          ratio: _selectedRatio,
          quality: _selectedQuality,
        );
      }

      if (result.isSuccess && result.data!.isNotEmpty) {
        setState(() {
          _generatedImageUrl = result.data!.first.imageUrl;
        });
        _showMessage('图像生成成功！');
      } else {
        _showMessage('生成失败: ${result.errorMessage}', isError: true);
      }
    } catch (e) {
      _showMessage('发生错误: $e', isError: true);
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  /// 选择图片
  Future<void> _pickImage() async {
    // TODO: 实现图片选择功能
    // 这里需要使用 image_picker 或 file_picker 包
    _showMessage('图片选择功能待实现');
    
    // 示例代码（需要添加 image_picker 依赖）:
    /*
    import 'package:image_picker/image_picker.dart';
    
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    
    if (pickedFile != null) {
      final bytes = await File(pickedFile.path).readAsBytes();
      final base64Image = base64Encode(bytes);
      
      setState(() {
        _referenceImages.add(base64Image);
      });
    }
    */
  }

  /// 下载图片
  Future<void> _downloadImage() async {
    if (_generatedImageUrl == null) return;
    
    try {
      // 从 data URL 中提取 base64 数据
      final base64Data = _generatedImageUrl!.split(',')[1];
      // final bytes = base64Decode(base64Data);  // TODO: 实现保存时使用
      
      // TODO: 实现文件保存功能
      // 这里需要使用 path_provider 和 file_saver 包
      _showMessage('图片下载功能待实现（base64数据: ${base64Data.substring(0, 20)}...）');
      
      // 示例代码（需要添加相关依赖）:
      /*
      import 'package:path_provider/path_provider.dart';
      import 'package:file_saver/file_saver.dart';
      
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'gemini_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = '${directory.path}/$fileName';
      
      await File(filePath).writeAsBytes(bytes);
      _showMessage('图片已保存到: $filePath');
      */
    } catch (e) {
      _showMessage('下载失败: $e', isError: true);
    }
  }

  /// 显示消息
  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : const Color(0xFF2AF598),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// ==================== 独立使用示例 ====================

/// 示例 1: 简单文生图
Future<void> exampleTextToImage() async {
  // 1. 创建配置
  final config = ApiConfig(
    provider: 'Gemini',
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
    model: 'gemini-2.5-flash-image',
  );

  // 2. 创建服务
  final service = GeminiImageService(config);
  final helper = GeminiImageHelper(service);

  // 3. 生成图片
  final result = await helper.textToImage(
    prompt: '一只睡觉的猫',
    ratio: ImageAspectRatio.landscape,
    quality: ImageQuality.low,
  );

  // 4. 处理结果
  if (result.isSuccess) {
    for (final image in result.data!) {
      print('生成的图片 URL: ${image.imageUrl}');
      print('图片 ID: ${image.imageId}');
      print('元数据: ${image.metadata}');
    }
  } else {
    print('生成失败: ${result.errorMessage}');
  }
}

/// 示例 2: 图生图（融合多张图片）
Future<void> exampleImageToImage() async {
  final config = ApiConfig(
    provider: 'Gemini',
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
  );

  final helper = GeminiImageHelper(GeminiImageService(config));

  // 读取并编码图片
  final image1 = base64Encode(await File('image1.jpg').readAsBytes());
  final image2 = base64Encode(await File('image2.jpg').readAsBytes());
  final image3 = base64Encode(await File('image3.jpg').readAsBytes());

  // 生成融合图片
  final result = await helper.imageToImage(
    prompt: '融合三张图片，输出高清图片',
    referenceImages: [image1, image2, image3],
    ratio: ImageAspectRatio.landscape,
    quality: ImageQuality.high,
  );

  if (result.isSuccess) {
    print('融合成功！图片数量: ${result.data!.length}');
  }
}

/// 示例 3: 使用自定义安全设置
Future<void> exampleWithSafetySettings() async {
  final config = ApiConfig(
    provider: 'Gemini',
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
  );

  final service = GeminiImageService(config);
  final helper = GeminiImageHelper(service);

  // 创建安全设置
  final safetySettings = helper.createSafetySettings(
    harmCategory: 'HARM_CATEGORY_DANGEROUS_CONTENT',
    threshold: 'BLOCK_MEDIUM_AND_ABOVE',
  );

  // 使用原始 service 方法并传入安全设置
  final result = await service.generateImages(
    prompt: '一只可爱的小狗',
    ratio: ImageAspectRatio.square,
    quality: ImageQuality.medium,
    parameters: safetySettings,
  );

  if (result.isSuccess) {
    print('图片生成成功，已应用安全过滤');
  }
}
