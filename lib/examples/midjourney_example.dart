import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:xinghe_new/services/api/providers/midjourney_service.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';
import 'package:xinghe_new/services/api/base/api_response.dart';
import 'package:xinghe_new/main.dart';

/// Midjourney 图像生成完整示例
/// 
/// 此示例展示了如何使用 MidjourneyService 进行：
/// 1. 文生图（Imagine 任务）
/// 2. 图生图（带垫图）
/// 3. 任务状态轮询
/// 4. Prompt 构建器使用
class MidjourneyExample extends StatefulWidget {
  const MidjourneyExample({super.key});

  @override
  State<MidjourneyExample> createState() => _MidjourneyExampleState();
}

class _MidjourneyExampleState extends State<MidjourneyExample> {
  late final MidjourneyHelper _helper;
  final TextEditingController _promptController = TextEditingController();
  final MidjourneyPromptBuilder _promptBuilder = MidjourneyPromptBuilder();
  
  String? _generatedImageUrl;
  bool _isGenerating = false;
  String? _currentTaskId;
  int _progress = 0;
  String _selectedMode = MidjourneyMode.relax;
  List<String> _referenceImages = [];

  // Prompt 参数
  String _selectedRatio = MidjourneyAspectRatio.landscape;
  String _selectedVersion = MidjourneyVersion.v6;
  double _quality = 1.0;
  int _stylize = 500;

  @override
  void initState() {
    super.initState();
    _initializeService();
    _promptController.text = 'A cat sleeping on a cloud';
  }

  void _initializeService() {
    final config = ApiConfig(
      provider: 'Midjourney',   // Midjourney 服务商
      baseUrl: 'YOUR_BASE_URL', // 替换为实际的 Base URL
      apiKey: 'YOUR_API_KEY',   // 替换为实际的 API Key
    );

    final service = MidjourneyService(config);
    _helper = MidjourneyHelper(service);
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
            title: const Text('Midjourney 图像生成'),
            backgroundColor: AppTheme.surfaceBackground,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPromptSection(),
                const SizedBox(height: 24),
                _buildModeSelector(),
                const SizedBox(height: 24),
                _buildParametersSection(),
                const SizedBox(height: 24),
                _buildReferenceImagesSection(),
                const SizedBox(height: 24),
                _buildGenerateButton(),
                const SizedBox(height: 24),
                if (_isGenerating) _buildProgressSection(),
                if (_generatedImageUrl != null) _buildResultSection(),
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
        Row(
          children: [
            Text(
              'Prompt 提示词',
              style: TextStyle(
                color: AppTheme.textColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _usePromptBuilder,
              icon: const Icon(Icons.auto_fix_high, size: 16),
              label: const Text('使用构建器'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _promptController,
          maxLines: 4,
          style: TextStyle(color: AppTheme.textColor, fontSize: 13),
          decoration: InputDecoration(
            hintText: '输入图像描述或使用 Prompt 构建器...',
            hintStyle: TextStyle(color: AppTheme.subTextColor),
            filled: true,
            fillColor: AppTheme.inputBackground,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '提示：使用英文描述可获得更好的效果',
          style: TextStyle(
            color: AppTheme.subTextColor,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '生成模式',
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
              child: _buildModeCard(
                mode: MidjourneyMode.relax,
                title: '慢速模式',
                subtitle: '免费额度，生成较慢',
                icon: Icons.schedule,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildModeCard(
                mode: MidjourneyMode.fast,
                title: '快速模式',
                subtitle: '付费使用，生成快速',
                icon: Icons.flash_on,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModeCard({
    required String mode,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _selectedMode == mode;
    
    return GestureDetector(
      onTap: () => setState(() => _selectedMode = mode),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected 
              ? AppTheme.accentColor.withOpacity(0.1) 
              : AppTheme.surfaceBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.accentColor : AppTheme.dividerColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: isSelected ? AppTheme.accentColor : AppTheme.subTextColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? AppTheme.accentColor : AppTheme.textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: AppTheme.subTextColor,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParametersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Prompt 参数',
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
              child: _buildParameterDropdown(
                label: '宽高比',
                value: _selectedRatio,
                items: {
                  MidjourneyAspectRatio.square: '1:1',
                  MidjourneyAspectRatio.landscape: '16:9',
                  MidjourneyAspectRatio.portrait: '9:16',
                  MidjourneyAspectRatio.standard: '4:3',
                  MidjourneyAspectRatio.wide: '21:9',
                },
                onChanged: (value) => setState(() => _selectedRatio = value!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildParameterDropdown(
                label: '版本',
                value: _selectedVersion,
                items: {
                  MidjourneyVersion.v6: 'V6',
                  MidjourneyVersion.v5: 'V5',
                  MidjourneyVersion.niji5: 'Niji 5',
                },
                onChanged: (value) => setState(() => _selectedVersion = value!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildSlider(
          label: '质量 (Quality)',
          value: _quality,
          min: 0.25,
          max: 2.0,
          divisions: 7,
          onChanged: (value) => setState(() => _quality = value),
          valueLabel: _quality.toString(),
        ),
        const SizedBox(height: 12),
        _buildSlider(
          label: '风格化 (Stylize)',
          value: _stylize.toDouble(),
          min: 0,
          max: 1000,
          divisions: 100,
          onChanged: (value) => setState(() => _stylize = value.toInt()),
          valueLabel: _stylize.toString(),
        ),
      ],
    );
  }

  Widget _buildParameterDropdown({
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
            style: TextStyle(color: AppTheme.textColor, fontSize: 13),
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

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required Function(double) onChanged,
    required String valueLabel,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: AppTheme.subTextColor,
                fontSize: 12,
              ),
            ),
            Text(
              valueLabel,
              style: TextStyle(
                color: AppTheme.accentColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: AppTheme.accentColor,
          onChanged: onChanged,
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
              '垫图（可选）',
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
              '点击添加垫图',
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
          // 处理 base64 数据
          String base64Data = entry.value;
          if (base64Data.startsWith('data:image/')) {
            base64Data = base64Data.split(',')[1];
          }
          
          return Stack(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image: DecorationImage(
                    image: MemoryImage(base64Decode(base64Data)),
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
        if (_referenceImages.length < 5)
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
        child: Text(
          _isGenerating ? '生成中...' : '提交 Imagine 任务',
          style: const TextStyle(fontSize: 16, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildProgressSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(AppTheme.accentColor),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '正在生成图像...',
                style: TextStyle(
                  color: AppTheme.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                '任务 ID:',
                style: TextStyle(
                  color: AppTheme.subTextColor,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _currentTaskId ?? '---',
                  style: TextStyle(
                    color: AppTheme.textColor,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: _progress / 100,
            backgroundColor: AppTheme.dividerColor,
            valueColor: AlwaysStoppedAnimation(AppTheme.accentColor),
          ),
          const SizedBox(height: 8),
          Text(
            '进度: $_progress%',
            style: TextStyle(
              color: AppTheme.subTextColor,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultSection() {
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
              label: const Text('下载'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _generatedImageUrl = null;
                  _currentTaskId = null;
                  _progress = 0;
                });
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

  /// 使用 Prompt 构建器
  void _usePromptBuilder() {
    showDialog(
      context: context,
      builder: (context) => _PromptBuilderDialog(
        builder: _promptBuilder,
        onBuild: (prompt) {
          setState(() {
            _promptController.text = prompt;
          });
        },
        ratio: _selectedRatio,
        version: _selectedVersion,
        quality: _quality,
        stylize: _stylize,
      ),
    );
  }

  /// 生成图像
  Future<void> _generateImage() async {
    final prompt = _promptController.text.trim();
    
    if (prompt.isEmpty) {
      _showMessage('请输入 Prompt', isError: true);
      return;
    }

    setState(() {
      _isGenerating = true;
      _progress = 0;
      _generatedImageUrl = null;
    });

    try {
      // 1. 提交任务
      final ApiResponse<MidjourneyTaskResponse> submitResult;
      
      if (_referenceImages.isEmpty) {
        // 文生图
        submitResult = await _helper.textToImage(
          prompt: prompt,
          mode: _selectedMode,
        );
      } else {
        // 图生图
        submitResult = await _helper.imageToImage(
          prompt: prompt,
          referenceImages: _referenceImages,
          mode: _selectedMode,
        );
      }

      if (!submitResult.isSuccess) {
        _showMessage(submitResult.errorMessage!, isError: true);
        setState(() => _isGenerating = false);
        return;
      }

      final taskId = submitResult.data!.taskId;
      setState(() => _currentTaskId = taskId);
      _showMessage('任务已提交，ID: $taskId');

      // 2. 轮询任务状态
      final statusResult = await _helper.pollTaskUntilComplete(
        taskId: taskId,
        maxAttempts: 60,
        intervalSeconds: 5,
      );

      if (statusResult.isSuccess) {
        final taskStatus = statusResult.data!;
        
        setState(() {
          _generatedImageUrl = taskStatus.imageUrl;
          _progress = 100;
        });
        
        _showMessage('图像生成完成！');
      } else {
        _showMessage(statusResult.errorMessage!, isError: true);
      }
    } catch (e) {
      _showMessage('发生错误: $e', isError: true);
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  /// 选择图片
  Future<void> _pickImage() async {
    _showMessage('图片选择功能待实现');
    // TODO: 实现图片选择功能
  }

  /// 下载图片
  Future<void> _downloadImage() async {
    _showMessage('图片下载功能待实现');
    // TODO: 实现图片下载功能
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

// ==================== Prompt 构建器对话框 ====================

class _PromptBuilderDialog extends StatelessWidget {
  final MidjourneyPromptBuilder builder;
  final Function(String) onBuild;
  final String ratio;
  final String version;
  final double quality;
  final int stylize;

  const _PromptBuilderDialog({
    required this.builder,
    required this.onBuild,
    required this.ratio,
    required this.version,
    required this.quality,
    required this.stylize,
  });

  @override
  Widget build(BuildContext context) {
    final promptController = TextEditingController();
    final negativeController = TextEditingController();

    return AlertDialog(
      backgroundColor: AppTheme.surfaceBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text('Prompt 构建器', style: TextStyle(color: AppTheme.textColor)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: promptController,
              maxLines: 3,
              style: TextStyle(color: AppTheme.textColor),
              decoration: InputDecoration(
                labelText: '基础描述',
                labelStyle: TextStyle(color: AppTheme.subTextColor),
                filled: true,
                fillColor: AppTheme.inputBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: negativeController,
              style: TextStyle(color: AppTheme.textColor),
              decoration: InputDecoration(
                labelText: '负面提示词（可选）',
                labelStyle: TextStyle(color: AppTheme.subTextColor),
                hintText: 'blurry, low quality',
                hintStyle: TextStyle(color: AppTheme.subTextColor.withOpacity(0.5)),
                filled: true,
                fillColor: AppTheme.inputBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('取消', style: TextStyle(color: AppTheme.subTextColor)),
        ),
        ElevatedButton(
          onPressed: () {
            if (promptController.text.trim().isEmpty) {
              return;
            }

            // 构建 prompt
            builder.reset();
            builder.withDescription(promptController.text.trim());
            builder.withAspectRatio(ratio);
            builder.withVersion(version);
            builder.withQuality(quality);
            builder.withStylize(stylize);
            
            if (negativeController.text.trim().isNotEmpty) {
              builder.withNegative(negativeController.text.trim());
            }

            final finalPrompt = builder.build();
            
            Navigator.pop(context);
            onBuild(finalPrompt);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accentColor,
          ),
          child: const Text('生成 Prompt', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

// ==================== 独立使用示例 ====================

/// 示例 1: 简单文生图
Future<void> exampleSimpleTextToImage() async {
  final config = ApiConfig(
    provider: 'Midjourney',
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
  );

  final helper = MidjourneyHelper(MidjourneyService(config));

  // 提交任务
  final result = await helper.textToImage(
    prompt: 'A beautiful sunset over mountains',
    mode: MidjourneyMode.relax,
  );

  if (result.isSuccess) {
    print('任务已提交');
    print('任务 ID: ${result.data!.taskId}');
    print('状态: ${result.data!.description}');
  }
}

/// 示例 2: 提交并等待完成
Future<void> exampleSubmitAndWait() async {
  final config = ApiConfig(
    provider: 'Midjourney',
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
  );

  final helper = MidjourneyHelper(MidjourneyService(config));

  // 提交并自动等待完成
  final result = await helper.submitAndWait(
    prompt: 'Cyberpunk city at night, neon lights --ar 16:9 --v 6',
    mode: MidjourneyMode.fast,
    maxWaitMinutes: 5,
  );

  if (result.isSuccess) {
    print('生成完成！');
    print('图片 URL: ${result.data}');
  } else {
    print('失败: ${result.errorMessage}');
  }
}

/// 示例 3: 使用 Prompt 构建器
Future<void> exampleWithPromptBuilder() async {
  final config = ApiConfig(
    provider: 'Midjourney',
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
  );

  final service = MidjourneyService(config);
  final helper = MidjourneyHelper(service);
  final builder = MidjourneyPromptBuilder();

  // 构建专业的 prompt
  final prompt = builder
    .withDescription('Professional portrait photography, young woman')
    .withAspectRatio('3:4')
    .withVersion(MidjourneyVersion.v6)
    .withQuality(2.0)
    .withStylize(500)
    .withNegative('cartoon, anime, sketch')
    .build();

  print('构建的 Prompt: $prompt');
  
  // 提交任务
  final result = await helper.submitAndWait(
    prompt: prompt,
    mode: MidjourneyMode.fast,
  );

  if (result.isSuccess) {
    print('生成成功: ${result.data}');
  }
}

/// 示例 4: 图生图
Future<void> exampleImageToImage() async {
  final config = ApiConfig(
    provider: 'Midjourney',
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
  );

  final helper = MidjourneyHelper(MidjourneyService(config));

  // 准备参考图片
  final image1 = base64Encode(await File('ref1.jpg').readAsBytes());
  final image2 = base64Encode(await File('ref2.jpg').readAsBytes());

  // 提交融合任务
  final result = await helper.submitAndWait(
    prompt: 'Blend these images into artistic composition',
    referenceImages: [image1, image2],
    mode: MidjourneyMode.fast,
  );

  if (result.isSuccess) {
    print('融合完成: ${result.data}');
  }
}

/// 示例 5: Upscale 操作
Future<void> exampleUpscale() async {
  final config = ApiConfig(
    provider: 'Midjourney',
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
  );

  final helper = MidjourneyHelper(MidjourneyService(config));

  // 第一步：生成初始图片
  print('提交 Imagine 任务...');
  final imagineResult = await helper.textToImage(
    prompt: 'A beautiful cat',
    mode: MidjourneyMode.fast,
  );

  if (!imagineResult.isSuccess) {
    print('提交失败: ${imagineResult.errorMessage}');
    return;
  }

  final originalTaskId = imagineResult.data!.taskId;
  print('原任务 ID: $originalTaskId');

  // 等待原任务完成
  print('等待初始图片生成...');
  final originalStatus = await helper.pollTaskUntilComplete(
    taskId: originalTaskId,
  );

  if (!originalStatus.isSuccess) {
    print('生成失败: ${originalStatus.errorMessage}');
    return;
  }

  print('初始图片生成完成！');

  // 第二步：Upscale 第 2 张图片
  print('提交 Upscale 任务...');
  final upscaleResult = await helper.upscale(
    taskId: originalTaskId,
    index: 2,  // 放大第 2 张
    mode: MidjourneyMode.fast,
  );

  if (!upscaleResult.isSuccess) {
    print('Upscale 提交失败: ${upscaleResult.errorMessage}');
    return;
  }

  final upscaleTaskId = upscaleResult.data!.taskId;
  print('Upscale 任务 ID: $upscaleTaskId');

  // 等待 Upscale 完成
  print('等待 Upscale 完成...');
  final upscaleStatus = await helper.pollTaskUntilComplete(
    taskId: upscaleTaskId,
  );

  if (upscaleStatus.isSuccess) {
    print('Upscale 完成！');
    print('放大后的图片 URL: ${upscaleStatus.data!.imageUrl}');
  }
}

/// 示例 6: Variation 操作
Future<void> exampleVariation() async {
  final config = ApiConfig(
    provider: 'Midjourney',
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
  );

  final helper = MidjourneyHelper(MidjourneyService(config));

  // 假设已有一个完成的任务
  final originalTaskId = 'existing-task-id';

  // 生成第 1 张图的变体
  final variationResult = await helper.variation(
    taskId: originalTaskId,
    index: 1,
    mode: MidjourneyMode.fast,
  );

  if (variationResult.isSuccess) {
    final newTaskId = variationResult.data!.taskId;
    
    // 等待变体生成完成
    final status = await helper.pollTaskUntilComplete(taskId: newTaskId);
    
    if (status.isSuccess) {
      print('变体生成完成: ${status.data!.imageUrl}');
    }
  }
}

/// 示例 7: Reroll 操作
Future<void> exampleReroll() async {
  final config = ApiConfig(
    provider: 'Midjourney',
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
  );

  final helper = MidjourneyHelper(MidjourneyService(config));

  // 假设已有一个完成的任务
  final originalTaskId = 'existing-task-id';

  // 重新生成
  final rerollResult = await helper.reroll(
    taskId: originalTaskId,
    mode: MidjourneyMode.fast,
  );

  if (rerollResult.isSuccess) {
    print('重新生成任务已提交: ${rerollResult.data!.taskId}');
  }
}

/// 示例 8: 完整的工作流（Imagine -> Upscale）
Future<void> exampleCompleteWorkflow() async {
  final config = ApiConfig(
    provider: 'Midjourney',
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
  );

  final service = MidjourneyService(config);
  final helper = MidjourneyHelper(service);

  // 1. 使用 Prompt 构建器
  final builder = MidjourneyPromptBuilder();
  final prompt = builder
    .withDescription('Professional product photography, luxury watch')
    .withAspectRatio('1:1')
    .withVersion('6')
    .withQuality(2.0)
    .withStylize(500)
    .build();

  print('Prompt: $prompt');

  // 2. 提交 Imagine 任务
  print('\n步骤 1: 提交 Imagine 任务');
  final imagineResult = await helper.textToImage(
    prompt: prompt,
    mode: MidjourneyMode.fast,
  );

  if (!imagineResult.isSuccess) {
    print('失败: ${imagineResult.errorMessage}');
    return;
  }

  final imagineTaskId = imagineResult.data!.taskId;
  print('任务已提交，ID: $imagineTaskId');

  // 3. 等待 Imagine 完成
  print('\n步骤 2: 等待初始图片生成');
  final imagineStatus = await helper.pollTaskUntilComplete(
    taskId: imagineTaskId,
    maxAttempts: 60,
    intervalSeconds: 5,
  );

  if (!imagineStatus.isSuccess) {
    print('生成失败: ${imagineStatus.errorMessage}');
    return;
  }

  print('初始图片生成完成');
  print('预览图 URL: ${imagineStatus.data!.imageUrl}');

  // 4. Upscale 最佳的一张（假设是第 2 张）
  print('\n步骤 3: Upscale 第 2 张图片');
  final upscaleResult = await helper.upscale(
    taskId: imagineTaskId,
    index: 2,
    mode: MidjourneyMode.fast,
  );

  if (!upscaleResult.isSuccess) {
    print('Upscale 提交失败: ${upscaleResult.errorMessage}');
    return;
  }

  final upscaleTaskId = upscaleResult.data!.taskId;
  print('Upscale 任务 ID: $upscaleTaskId');

  // 5. 等待 Upscale 完成
  print('\n步骤 4: 等待 Upscale 完成');
  final upscaleStatus = await helper.pollTaskUntilComplete(
    taskId: upscaleTaskId,
  );

  if (upscaleStatus.isSuccess) {
    print('\n✅ 完整工作流完成！');
    print('最终高清图片 URL: ${upscaleStatus.data!.imageUrl}');
  }
}

/// 示例 9: Blend 融合图片
Future<void> exampleBlend() async {
  final config = ApiConfig(
    provider: 'Midjourney',
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
  );

  final helper = MidjourneyHelper(MidjourneyService(config));

  // 准备要融合的图片
  final image1 = base64Encode(await File('photo1.jpg').readAsBytes());
  final image2 = base64Encode(await File('photo2.jpg').readAsBytes());
  final image3 = base64Encode(await File('photo3.jpg').readAsBytes());

  // 方式 1: 提交后立即返回
  final blendResult = await helper.blend(
    images: [image1, image2, image3],
    dimensions: MidjourneyDimensions.square,  // 1:1
    mode: MidjourneyMode.fast,
  );

  if (blendResult.isSuccess) {
    print('Blend 任务已提交: ${blendResult.data!.taskId}');
    
    // 等待完成
    final status = await helper.pollTaskUntilComplete(
      taskId: blendResult.data!.taskId,
    );
    
    if (status.isSuccess) {
      print('融合完成: ${status.data!.imageUrl}');
    }
  }
}

/// 示例 10: Blend 并等待完成（一键融合）
Future<void> exampleBlendAndWait() async {
  final config = ApiConfig(
    provider: 'Midjourney',
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
  );

  final helper = MidjourneyHelper(MidjourneyService(config));

  // 准备图片
  final images = <String>[];
  for (int i = 1; i <= 3; i++) {
    final bytes = await File('image$i.jpg').readAsBytes();
    images.add(base64Encode(bytes));
  }

  // 一键融合并等待
  final result = await helper.blendAndWait(
    images: images,
    dimensions: MidjourneyDimensions.landscape,  // 3:2
    mode: MidjourneyMode.fast,
    maxWaitMinutes: 5,
  );

  if (result.isSuccess) {
    print('融合完成！');
    print('图片 URL: ${result.data}');
  } else {
    print('融合失败: ${result.errorMessage}');
  }
}

/// 示例 11: Blend + Upscale 组合
Future<void> exampleBlendAndUpscale() async {
  final config = ApiConfig(
    provider: 'Midjourney',
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
  );

  final helper = MidjourneyHelper(MidjourneyService(config));

  // 准备图片
  final img1 = base64Encode(await File('art1.jpg').readAsBytes());
  final img2 = base64Encode(await File('art2.jpg').readAsBytes());

  print('步骤 1: Blend 融合');
  
  // 1. Blend
  final blendResult = await helper.blend(
    images: [img1, img2],
    dimensions: MidjourneyDimensions.square,
    mode: MidjourneyMode.fast,
  );

  if (!blendResult.isSuccess) {
    print('Blend 失败');
    return;
  }

  final blendTaskId = blendResult.data!.taskId;

  // 等待 Blend 完成
  print('等待 Blend 完成...');
  await helper.pollTaskUntilComplete(taskId: blendTaskId);

  print('步骤 2: Upscale 放大');

  // 2. Upscale 第 1 张
  final upscaleResult = await helper.upscale(
    taskId: blendTaskId,
    index: 1,
    mode: MidjourneyMode.fast,
  );

  if (upscaleResult.isSuccess) {
    // 等待 Upscale 完成
    final finalStatus = await helper.pollTaskUntilComplete(
      taskId: upscaleResult.data!.taskId,
    );

    if (finalStatus.isSuccess) {
      print('✅ 完成！最终图片: ${finalStatus.data!.imageUrl}');
    }
  }
}

/// 示例 12: Modal 补充输入
Future<void> exampleModal() async {
  final config = ApiConfig(
    provider: 'Midjourney',
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
  );

  final helper = MidjourneyHelper(MidjourneyService(config));

  // 提交任务
  final result = await helper.textToImage(
    prompt: 'A landscape',
    mode: MidjourneyMode.fast,
  );

  // 检查是否需要 Modal
  if (result.data?.code == 21) {
    print('任务需要补充信息（Code: 21）');
    
    // 提交 Modal
    final modalResult = await helper.modal(
      taskId: result.data!.taskId,
      prompt: 'with mountains and a beautiful lake',
    );
    
    if (modalResult.isSuccess) {
      print('Modal 已提交，新任务 ID: ${modalResult.data!.taskId}');
      
      // 等待新任务完成
      final status = await helper.pollTaskUntilComplete(
        taskId: modalResult.data!.taskId,
      );
      
      if (status.isSuccess) {
        print('生成完成: ${status.data!.imageUrl}');
      }
    }
  } else if (result.isSuccess) {
    print('任务正常提交，无需 Modal');
  }
}

/// 示例 13: 局部重绘（Inpaint）
Future<void> exampleInpaint() async {
  final config = ApiConfig(
    provider: 'Midjourney',
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
  );

  final helper = MidjourneyHelper(MidjourneyService(config));

  // 假设已有一个完成的任务
  final originalTaskId = 'existing-task-id';

  // 创建蒙版（标记要重绘的区域）
  // 这里需要实际的蒙版图片
  final maskBase64 = await createInpaintMask();

  // 提交局部重绘
  final result = await helper.inpaint(
    taskId: originalTaskId,
    maskBase64: maskBase64,
    prompt: 'Replace with a blue sky and white clouds',
  );

  if (result.isSuccess) {
    print('局部重绘任务已提交');
    
    // 等待完成
    final status = await helper.pollTaskUntilComplete(
      taskId: result.data!.taskId,
    );
    
    if (status.isSuccess) {
      print('重绘完成: ${status.data!.imageUrl}');
    }
  }
}

// 辅助函数：创建蒙版
Future<String> createInpaintMask() async {
  // TODO: 实际实现需要图像处理库
  // 这里返回示例值
  return 'data:image/png;base64,iVBORw0KGgo...';
}

/// 示例 14: Describe 图生文
Future<void> exampleDescribe() async {
  final config = ApiConfig(
    provider: 'Midjourney',
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
  );

  final helper = MidjourneyHelper(MidjourneyService(config));

  // 读取图片
  final imageBytes = await File('artwork.jpg').readAsBytes();
  final imageBase64 = base64Encode(imageBytes);

  // 分析图片并获取描述
  final result = await helper.describeAndWait(
    imageBase64: imageBase64,
    mode: MidjourneyMode.fast,
    maxWaitMinutes: 3,
  );

  if (result.isSuccess) {
    final describeResult = result.data!;
    
    print('图片分析完成！');
    print('生成了 ${describeResult.prompts.length} 个 prompt 建议：\n');
    
    for (int i = 0; i < describeResult.prompts.length; i++) {
      print('${i + 1}. ${describeResult.prompts[i]}');
    }
    
    print('\n推荐使用: ${describeResult.bestPrompt}');
  } else {
    print('分析失败: ${result.errorMessage}');
  }
}

/// 示例 15: Describe → Imagine 循环
Future<void> exampleDescribeToImagine() async {
  final config = ApiConfig(
    provider: 'Midjourney',
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
  );

  final helper = MidjourneyHelper(MidjourneyService(config));

  print('步骤 1: 分析原图');
  
  // 1. Describe: 分析原图
  final originalImage = await File('original.jpg').readAsBytes();
  final describeResult = await helper.describeAndWait(
    imageBase64: base64Encode(originalImage),
    mode: MidjourneyMode.fast,
  );

  if (!describeResult.isSuccess) {
    print('分析失败');
    return;
  }

  final analyzedPrompt = describeResult.data!.bestPrompt;
  print('分析结果: $analyzedPrompt\n');

  print('步骤 2: 使用分析结果重新生成');
  
  // 2. Imagine: 使用分析的 prompt 重新生成
  final imagineResult = await helper.submitAndWait(
    prompt: analyzedPrompt,
    mode: MidjourneyMode.fast,
  );

  if (imagineResult.isSuccess) {
    print('✅ 重新生成完成');
    print('新图片: ${imagineResult.data}');
  }
}

/// 示例 16: Shorten Prompt 优化
Future<void> exampleShorten() async {
  final config = ApiConfig(
    provider: 'Midjourney',
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
  );

  final helper = MidjourneyHelper(MidjourneyService(config));

  // 冗长的 prompt
  final longPrompt = '''
    A very detailed and extremely beautiful professional photograph 
    of a magnificent sunset over the ocean with lots of colorful 
    clouds and reflections on the water surface
  '''.trim();

  print('原始 Prompt (${longPrompt.length} 字符):');
  print(longPrompt);
  print('');

  // 优化 prompt
  final result = await helper.shortenAndWait(
    prompt: longPrompt,
    mode: MidjourneyMode.fast,
    maxWaitMinutes: 2,
  );

  if (result.isSuccess) {
    final shortenResult = result.data!;
    
    print('优化建议:');
    for (int i = 0; i < shortenResult.shortenedPrompts.length; i++) {
      final optimized = shortenResult.shortenedPrompts[i];
      print('${i + 1}. $optimized (${optimized.length} 字符)');
    }
    
    print('\n最佳优化:');
    print(shortenResult.bestShortened);
    
    print('\n统计:');
    print('- 原长度: ${longPrompt.length} 字符');
    print('- 新长度: ${shortenResult.bestShortened.length} 字符');
    print('- 优化率: ${(shortenResult.optimizationRatio * 100).toInt()}%');
  }
}

/// 示例 17: Shorten + Imagine 工作流
Future<void> exampleShortenToImagine() async {
  final config = ApiConfig(
    provider: 'Midjourney',
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
  );

  final helper = MidjourneyHelper(MidjourneyService(config));

  final verbosePrompt = '''
    Professional high quality photography of a cute little cat 
    with soft fluffy fur sitting comfortably on a cushion
  ''';

  print('步骤 1: 优化 Prompt');
  
  // 1. Shorten
  final shortenResult = await helper.shortenAndWait(
    prompt: verbosePrompt,
    mode: MidjourneyMode.fast,
  );

  if (!shortenResult.isSuccess) {
    print('优化失败');
    return;
  }

  final optimized = shortenResult.data!.bestShortened;
  print('优化结果: $optimized\n');

  print('步骤 2: 使用优化后的 Prompt 生成');
  
  // 2. Imagine
  final imagineResult = await helper.submitAndWait(
    prompt: optimized,
    mode: MidjourneyMode.fast,
  );

  if (imagineResult.isSuccess) {
    print('✅ 生成完成');
    print('图片: ${imagineResult.data}');
  }
}

/// 示例 18: SwapFace 换脸
Future<void> exampleSwapFace() async {
  final config = ApiConfig(
    provider: 'Midjourney',
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
  );

  final helper = MidjourneyHelper(MidjourneyService(config));

  // 换脸操作
  // source: 要使用的人脸
  // target: 要替换脸的图片
  final result = await helper.swapFaceAndWait(
    sourceImagePath: '/path/to/my_face.jpg',    // 我的照片
    targetImagePath: '/path/to/target.jpg',     // 目标场景
    mode: MidjourneyMode.fast,
    maxWaitMinutes: 3,
  );

  if (result.isSuccess) {
    print('换脸完成！');
    print('结果图片: ${result.data}');
  } else {
    print('换脸失败: ${result.errorMessage}');
  }
}

/// 示例 19: 批量生成
Future<void> exampleBatchGeneration() async {
  final config = ApiConfig(
    provider: 'Midjourney',
    baseUrl: 'YOUR_BASE_URL',
    apiKey: 'YOUR_API_KEY',
  );

  final helper = MidjourneyHelper(MidjourneyService(config));

  final prompts = [
    'A red apple on a table',
    'A blue ocean wave',
    'A green forest path',
  ];

  final taskIds = <String>[];

  // 批量提交
  for (final prompt in prompts) {
    final result = await helper.textToImage(
      prompt: prompt,
      mode: MidjourneyMode.relax,
    );
    
    if (result.isSuccess) {
      taskIds.add(result.data!.taskId);
      print('已提交: $prompt');
      
      // 避免请求过快
      await Future.delayed(Duration(seconds: 2));
    }
  }

  print('批量提交完成，共 ${taskIds.length} 个任务');

  // 等待所有任务完成
  final results = <String>[];
  for (final taskId in taskIds) {
    final status = await helper.pollTaskUntilComplete(taskId: taskId);
    
    if (status.isSuccess && status.data!.imageUrl != null) {
      results.add(status.data!.imageUrl!);
    }
  }

  print('批量生成完成，成功 ${results.length} 张');
}
