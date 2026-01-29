import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xinghe_new/main.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinghe_new/services/api/secure_storage_manager.dart';
import 'package:xinghe_new/core/logger/log_manager.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class SettingsPage extends StatefulWidget {
  final VoidCallback onBack;

  const SettingsPage({super.key, required this.onBack});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _mainTabIndex = 0;
  int _apiSubTabIndex = 0;
  bool _isPickingImagePath = false;
  bool _isPickingVideoPath = false;
  
  // 密码可见性状态
  bool _llmApiKeyVisible = false;
  bool _imageApiKeyVisible = false;
  bool _videoApiKeyVisible = false;
  bool _uploadApiKeyVisible = false;

  final List<String> _mainTabs = ['API设置', '风格设置', '保存设置'];
  final List<String> _apiSubTabs = ['LLM模型', '图片模型', '视频模型', '上传设置'];

  // API配置状态
  final SecureStorageManager _storage = SecureStorageManager();
  final LogManager _logger = LogManager();
  
  // ✅ 防抖定时器 - 避免频繁保存
  Timer? _saveDebounceTimer;
  
  // LLM API 配置
  String _llmProvider = 'openai';
  final TextEditingController _llmApiKeyController = TextEditingController();
  final TextEditingController _llmBaseUrlController = TextEditingController();
  final TextEditingController _llmModelController = TextEditingController();

  // 图片 API 配置
  String _imageProvider = 'openai';
  final TextEditingController _imageApiKeyController = TextEditingController();
  final TextEditingController _imageBaseUrlController = TextEditingController();
  final TextEditingController _imageModelController = TextEditingController();

  // 视频 API 配置
  String _videoProvider = 'openai';
  final TextEditingController _videoApiKeyController = TextEditingController();
  final TextEditingController _videoBaseUrlController = TextEditingController();
  final TextEditingController _videoModelController = TextEditingController();

  // 上传 API 配置
  String _uploadProvider = 'openai';
  final TextEditingController _uploadApiKeyController = TextEditingController();
  final TextEditingController _uploadBaseUrlController = TextEditingController();

  // GeekNow 模型列表
  final Map<String, List<String>> _geekNowModels = {
    'llm': [
      // OpenAI 系列
      'gpt-4o', 'gpt-4-turbo', 'gpt-4', 'gpt-3.5-turbo',
      // DeepSeek 系列
      'deepseek-chat', 'deepseek-coder',
      // Claude 系列
      'claude-3-opus', 'claude-3-sonnet', 'claude-3-haiku',
      // Gemini 系列
      'gemini-pro', 'gemini-pro-vision',
      // Llama 系列
      'llama-3-70b', 'llama-3-8b',
      // 其他常用模型
      'mixtral-8x7b', 'qwen-turbo', 'qwen-plus',
    ],
    'image': [
      // OpenAI 系列
      'gpt-4o', 'gpt-4-turbo', 'dall-e-3', 'dall-e-2',
      // Gemini 图像生成系列
      'gemini-3-pro-image-preview', 'gemini-3-pro-image-preview-lite', 'gemini-2.5-flash-image-preview', 'gemini-2.5-flash-image', 'gemini-pro-vision',
      // Stable Diffusion 系列
      'stable-diffusion-xl', 'stable-diffusion-3',
      // Midjourney 风格
      'midjourney-v6', 'midjourney-niji',
    ],
    'video': [
      // VEO 系列
      'veo_3_1', 'veo_3_1-4K', 'veo_3_1-fast', 'veo_3_1-fast-4K',
      'veo_3_1-components', 'veo_3_1-components-4K',
      'veo_3_1-fast-components', 'veo_3_1-fast-components-4K',
      // Sora 系列
      'sora-2', 'sora-turbo',
      // Kling
      'kling-video-o1',
      // Doubao 系列
      'doubao-seedance-1-5-pro_480p',
      'doubao-seedance-1-5-pro_720p',
      'doubao-seedance-1-5-pro_1080p',
      // Grok
      'grok-video-3',
    ],
  };

  // Yunwu（云雾）模型列表
  final Map<String, List<String>> _yunwuModels = {
    'llm': [
      // Gemini 系列（Google）
      'gemini-2.5-pro',
      'gemini-2.5-flash',
      'gemini-1.5-pro',
      'gemini-1.5-flash',
    ],
    'image': [
      // Gemini 图像生成系列（Google）
      'gemini-2.5-flash-image-preview',
      'gemini-3-pro-image-preview',
      'gemini-3-pro-image-preview-lite',
    ],
    'video': [
      // Sora 系列（根据 API 文档）
      'sora-2',        // 支持 duration: 10
      'sora-2-all',    // 支持 duration: 10, 15
      'sora-2-pro',    // 支持 duration: 15, 25; size: large (1080p)
      
      // VEO2 系列（Google）
      'veo2', 'veo2-fast', 'veo2-fast-frames', 'veo2-fast-components', 
      'veo2-pro', 'veo2-pro-components',
      
      // VEO3 系列（Google，支持音频）
      'veo3', 'veo3-fast', 'veo3-fast-frames', 'veo3-frames', 
      'veo3-pro', 'veo3-pro-frames',
      
      // VEO3.1 系列（Google，最新）
      'veo3.1', 'veo3.1-fast', 'veo3.1-pro', 'veo3.1-components',
    ],
  };

  final List<Map<String, dynamic>> _styleOptions = [
    {
      'name': '深邃黑',
      'desc': '极客 OLED 风格，沉浸式创作体验',
      'colors': [const Color(0xFF161618), const Color(0xFF252629)],
      'accent': const Color(0xFF00E5FF),
    },
    {
      'name': '纯净白',
      'desc': '简约高雅，如同白纸般的纯净视野',
      'colors': [const Color(0xFFF5F5F7), const Color(0xFFFFFFFF)],
      'accent': const Color(0xFF009EFD),
    },
    {
      'name': '梦幻粉',
      'desc': '柔和浪漫，赋予灵感更多温润色彩',
      'colors': [const Color(0xFFFFF0F5), const Color(0xFFFFD1DC)],
      'accent': const Color(0xFFFF69B4),
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadAllConfigs();
  }

  @override
  void dispose() {
    _saveDebounceTimer?.cancel(); // ✅ 取消防抖定时器
    _llmApiKeyController.dispose();
    _llmBaseUrlController.dispose();
    _llmModelController.dispose();
    _imageApiKeyController.dispose();
    _imageBaseUrlController.dispose();
    _imageModelController.dispose();
    _videoApiKeyController.dispose();
    _videoBaseUrlController.dispose();
    _videoModelController.dispose();
    _uploadApiKeyController.dispose();
    _uploadBaseUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadAllConfigs() async {
    await _loadLLMConfig();
    await _loadImageConfig();
    await _loadVideoConfig();
    await _loadUploadConfig();
    await _loadSavePathsConfig();
  }

  /// 加载保存路径配置
  Future<void> _loadSavePathsConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final imagePath = prefs.getString('image_save_path');
      final videoPath = prefs.getString('video_save_path');

      if (imagePath != null && imagePath.isNotEmpty) {
        imageSavePathNotifier.value = imagePath;
        _logger.info('加载图片保存路径: $imagePath', module: '设置');
      }

      if (videoPath != null && videoPath.isNotEmpty) {
        videoSavePathNotifier.value = videoPath;
        _logger.info('加载视频保存路径: $videoPath', module: '设置');
      }
    } catch (e) {
      _logger.error('加载保存路径配置失败: $e', module: '设置');
    }
  }

  Future<void> _loadLLMConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('llm_provider') ?? 'openai';
      final apiKey = await _storage.getApiKey(provider: provider, modelType: 'llm');
      final baseUrl = await _storage.getBaseUrl(provider: provider, modelType: 'llm');
      final model = await _storage.getModel(provider: provider, modelType: 'llm');

      if (mounted) {
        setState(() {
          _llmProvider = provider;
          _llmApiKeyController.text = apiKey ?? '';
          _llmBaseUrlController.text = baseUrl ?? _getDefaultBaseUrl(provider);
          _llmModelController.text = model ?? '';
        });
      }
    } catch (e) {
      _logger.error('加载LLM配置失败: $e', module: '设置');
    }
  }

  Future<void> _loadImageConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('image_provider') ?? 'openai';
      final apiKey = await _storage.getApiKey(provider: provider, modelType: 'image');
      final baseUrl = await _storage.getBaseUrl(provider: provider, modelType: 'image');
      final model = await _storage.getModel(provider: provider, modelType: 'image');

      if (mounted) {
        setState(() {
          _imageProvider = provider;
          _imageApiKeyController.text = apiKey ?? '';
          _imageBaseUrlController.text = baseUrl ?? _getDefaultBaseUrl(provider);
          _imageModelController.text = model ?? '';
        });
      }
    } catch (e) {
      _logger.error('加载图片配置失败: $e', module: '设置');
    }
  }

  Future<void> _loadVideoConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('video_provider') ?? 'openai';
      final apiKey = await _storage.getApiKey(provider: provider, modelType: 'video');
      final baseUrl = await _storage.getBaseUrl(provider: provider, modelType: 'video');
      final model = await _storage.getModel(provider: provider, modelType: 'video');

      if (mounted) {
        setState(() {
          _videoProvider = provider;
          _videoApiKeyController.text = apiKey ?? '';
          _videoBaseUrlController.text = baseUrl ?? _getDefaultBaseUrl(provider);
          _videoModelController.text = model ?? '';
        });
      }
    } catch (e) {
      _logger.error('加载视频配置失败: $e', module: '设置');
    }
  }

  Future<void> _loadUploadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('upload_provider') ?? 'openai';
      final apiKey = await _storage.getApiKey(provider: provider, modelType: 'upload');
      final baseUrl = await _storage.getBaseUrl(provider: provider, modelType: 'upload');

      if (mounted) {
        setState(() {
          _uploadProvider = provider;
          _uploadApiKeyController.text = apiKey ?? '';
          _uploadBaseUrlController.text = baseUrl ?? _getDefaultBaseUrl(provider);
        });
      }
    } catch (e) {
      _logger.error('加载上传配置失败: $e', module: '设置');
    }
  }

  String _getDefaultBaseUrl(String provider) {
    switch (provider.toLowerCase()) {
      case 'openai':
        return 'https://api.openai.com/v1';
      case 'geeknow':
        return 'https://api.geeknow.ai/v1';
      case 'yunwu':
        return 'https://yunwu.ai';  // Yunwu API 地址（根据文档）
      case 'azure':
        return 'https://your-resource.openai.azure.com';
      case 'anthropic':
        return 'https://api.anthropic.com/v1';
      default:
        return 'https://api.openai.com/v1';
    }
  }

  /// ✅ 防抖保存包装器 - 避免频繁保存
  void _debouncedSave(VoidCallback saveFunction) {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(seconds: 1), () {
      saveFunction();
    });
  }

  Future<void> _saveLLMConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('llm_provider', _llmProvider);
      
      if (_llmApiKeyController.text.isNotEmpty) {
        await _storage.saveApiKey(provider: _llmProvider, apiKey: _llmApiKeyController.text, modelType: 'llm');
      }
      if (_llmBaseUrlController.text.isNotEmpty) {
        await _storage.saveBaseUrl(provider: _llmProvider, baseUrl: _llmBaseUrlController.text, modelType: 'llm');
      }
      if (_llmModelController.text.isNotEmpty) {
        await _storage.saveModel(provider: _llmProvider, modelType: 'llm', model: _llmModelController.text);
      }

      _logger.success('保存LLM配置成功', module: '设置', extra: {'provider': _llmProvider});
      _showMessage('LLM配置已保存');
    } catch (e) {
      _logger.error('保存LLM配置失败: $e', module: '设置');
      _showMessage('保存失败: $e', isError: true);
    }
  }

  Future<void> _saveImageConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('image_provider', _imageProvider);
      
      if (_imageApiKeyController.text.isNotEmpty) {
        await _storage.saveApiKey(provider: _imageProvider, apiKey: _imageApiKeyController.text, modelType: 'image');
      }
      if (_imageBaseUrlController.text.isNotEmpty) {
        await _storage.saveBaseUrl(provider: _imageProvider, baseUrl: _imageBaseUrlController.text, modelType: 'image');
      }
      if (_imageModelController.text.isNotEmpty) {
        await _storage.saveModel(provider: _imageProvider, modelType: 'image', model: _imageModelController.text);
      }

      _logger.success('保存图片API配置成功', module: '设置', extra: {'provider': _imageProvider});
      _showMessage('图片API配置已保存');
    } catch (e) {
      _logger.error('保存图片配置失败: $e', module: '设置');
      _showMessage('保存失败: $e', isError: true);
    }
  }

  Future<void> _saveVideoConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('video_provider', _videoProvider);
      
      if (_videoApiKeyController.text.isNotEmpty) {
        await _storage.saveApiKey(provider: _videoProvider, apiKey: _videoApiKeyController.text, modelType: 'video');
      }
      if (_videoBaseUrlController.text.isNotEmpty) {
        await _storage.saveBaseUrl(provider: _videoProvider, baseUrl: _videoBaseUrlController.text, modelType: 'video');
      }
      if (_videoModelController.text.isNotEmpty) {
        await _storage.saveModel(provider: _videoProvider, modelType: 'video', model: _videoModelController.text);
      }

      _logger.success('保存视频API配置成功', module: '设置', extra: {'provider': _videoProvider});
      _showMessage('视频API配置已保存');
    } catch (e) {
      _logger.error('保存视频配置失败: $e', module: '设置');
      _showMessage('保存失败: $e', isError: true);
    }
  }

  Future<void> _saveUploadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('upload_provider', _uploadProvider);
      
      if (_uploadApiKeyController.text.isNotEmpty) {
        await _storage.saveApiKey(provider: _uploadProvider, apiKey: _uploadApiKeyController.text, modelType: 'upload');
      }
      if (_uploadBaseUrlController.text.isNotEmpty) {
        await _storage.saveBaseUrl(provider: _uploadProvider, baseUrl: _uploadBaseUrlController.text, modelType: 'upload');
      }

      _logger.success('保存上传API配置成功', module: '设置', extra: {'provider': _uploadProvider});
      _showMessage('上传API配置已保存');
    } catch (e) {
      _logger.error('保存上传配置失败: $e', module: '设置');
      _showMessage('保存失败: $e', isError: true);
    }
  }

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

  Future<void> _pickImageDirectory() async {
    if (_isPickingImagePath) return;
    
    setState(() => _isPickingImagePath = true);
    
    try {
      final String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择图片保存文件夹',
        lockParentWindow: true,
      );
      
      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        // 更新内存中的值
        imageSavePathNotifier.value = selectedDirectory;
        
        // 持久化保存到 SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('image_save_path', selectedDirectory);
        
        _logger.success('设置图片保存路径', module: '设置', extra: {'path': selectedDirectory});
        if (mounted) {
          _showMessage('图片保存路径已更新: $selectedDirectory');
        }
      }
    } catch (e) {
      _logger.error('选择图片路径失败: $e', module: '设置');
      if (mounted) {
        _showMessage('选择文件夹时出错: ${e.toString()}', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingImagePath = false);
      }
    }
  }

  Future<void> _pickVideoDirectory() async {
    if (_isPickingVideoPath) return;
    
    setState(() => _isPickingVideoPath = true);
    
    try {
      final String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择视频保存文件夹',
        lockParentWindow: true,
      );
      
      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        // 更新内存中的值
        videoSavePathNotifier.value = selectedDirectory;
        
        // 持久化保存到 SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('video_save_path', selectedDirectory);
        
        _logger.success('设置视频保存路径', module: '设置', extra: {'path': selectedDirectory});
        if (mounted) {
          _showMessage('视频保存路径已更新: $selectedDirectory');
        }
      }
    } catch (e) {
      _logger.error('选择视频路径失败: $e', module: '设置');
      if (mounted) {
        _showMessage('选择文件夹时出错: ${e.toString()}', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingVideoPath = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: themeNotifier,
      builder: (context, currentThemeIndex, _) {
        return Container(
          color: AppTheme.scaffoldBackground,
          child: Column(
            children: [
              // 顶部返回栏
              Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    _buildIconButton(Icons.arrow_back_ios_new_rounded, '返回工作台', widget.onBack),
                    const SizedBox(width: 20),
                    Text(
                      '设置',
                      style: TextStyle(
                        color: AppTheme.textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppTheme.dividerColor),
              
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 左侧导航菜单
                    Container(
                      width: 200,
                      decoration: BoxDecoration(
                        border: Border(right: BorderSide(color: AppTheme.dividerColor)),
                      ),
                      child: Column(
                        children: List.generate(_mainTabs.length, (index) {
                          return _buildLeftNavItem(index, _mainTabIndex == index);
                        }),
                      ),
                    ),
                    
                    // 右侧内容区域
                    Expanded(
                      child: _buildContentArea(currentThemeIndex),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 左侧导航项
  Widget _buildLeftNavItem(int index, bool isSelected) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          // 切换前清除焦点
          FocusScope.of(context).unfocus();
          setState(() => _mainTabIndex = index);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.sideBarItemHover : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: isSelected ? AppTheme.accentColor : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                index == 0 ? Icons.api : index == 1 ? Icons.palette : Icons.save,
                size: 18,
                color: isSelected ? AppTheme.textColor : AppTheme.subTextColor,
              ),
              const SizedBox(width: 12),
              Text(
                _mainTabs[index],
                style: TextStyle(
                  color: isSelected ? AppTheme.textColor : AppTheme.subTextColor,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContentArea(int themeIndex) {
    switch (_mainTabIndex) {
      case 0:
        return _buildApiConfigurationForm();
      case 1:
        return _buildStyleSettings(themeIndex);
      case 2:
        return _buildSaveSettings();
      default:
        return _buildPlaceholderView();
    }
  }

  Widget _buildMainTab(int index, bool isSelected) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _mainTabIndex = index),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? AppTheme.accentColor : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            _mainTabs[index],
            style: TextStyle(
              color: isSelected ? AppTheme.textColor : AppTheme.subTextColor,
              fontSize: 15,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubTab(int index, bool isSelected) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() => _apiSubTabIndex = index),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.sideBarItemHover : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _apiSubTabs[index],
            style: TextStyle(
              color: AppTheme.textColor,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSaveSettings() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFormHeader('本地保存路径设置', icon: Icons.save_rounded),
          const SizedBox(height: 12),
          Text('配置生成后的图片与视频存放路径，系统将自动进行分类保存', style: TextStyle(color: AppTheme.subTextColor, fontSize: 13)),
          const SizedBox(height: 40),

          _buildPathSelector(
            title: '图片保存路径',
            notifier: imageSavePathNotifier,
            onPick: _pickImageDirectory,
            isLoading: _isPickingImagePath,
          ),

          const SizedBox(height: 32),

          _buildPathSelector(
            title: '视频保存路径',
            notifier: videoSavePathNotifier,
            onPick: _pickVideoDirectory,
            isLoading: _isPickingVideoPath,
          ),

          const SizedBox(height: 60),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.textColor.withOpacity(0.02),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.dividerColor),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, color: const Color(0xFF2AF598).withOpacity(0.7), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '设置已实时自动保存。生成内容时，系统将直接导出至上述文件夹。',
                    style: TextStyle(color: AppTheme.subTextColor, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPathSelector({
    required String title,
    required ValueNotifier<String> notifier,
    required VoidCallback onPick,
    bool isLoading = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel(title),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: notifier,
                builder: (context, path, _) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.textColor.withOpacity(0.05)),
                    ),
                    child: Text(
                      path,
                      style: TextStyle(
                        color: path == '未设置' ? AppTheme.subTextColor : AppTheme.textColor,
                        fontSize: 14,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            MouseRegion(
              cursor: isLoading ? SystemMouseCursors.wait : SystemMouseCursors.click,
              child: GestureDetector(
                onTap: isLoading ? null : onPick,
                child: Opacity(
                  opacity: isLoading ? 0.6 : 1.0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2AF598), Color(0xFF009EFD)],
                      ),
                    ),
                    child: Row(
                      children: [
                        if (isLoading)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        else
                          const Icon(Icons.folder_open_rounded, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          isLoading ? '选择中...' : '更改目录',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStyleSettings(int currentThemeIndex) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFormHeader('视觉风格设置', icon: Icons.palette_rounded),
          const SizedBox(height: 12),
          Text('选择后立即自动应用全局风格。系统将自动调整全局色彩规则', style: TextStyle(color: AppTheme.subTextColor, fontSize: 13)),
          const SizedBox(height: 40),
          
          Wrap(
            spacing: 24,
            runSpacing: 24,
            children: List.generate(_styleOptions.length, (index) {
              final style = _styleOptions[index];
              final isSelected = currentThemeIndex == index;
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    themeNotifier.value = index;
                    _logger.info('切换主题', module: '设置', extra: {'theme': style['name']});
                  },
                  child: Container(
                    width: 260,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? AppTheme.accentColor : AppTheme.textColor.withOpacity(0.05),
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: isSelected ? [
                        BoxShadow(color: AppTheme.accentColor.withOpacity(0.1), blurRadius: 15, spreadRadius: 2)
                      ] : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 120,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                            gradient: LinearGradient(
                              colors: style['colors'],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                right: 12,
                                bottom: 12,
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: style['accent'],
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Center(
                                  child: Icon(Icons.check_circle, color: Colors.white, size: 40),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(style['name'], style: TextStyle(color: AppTheme.textColor, fontSize: 15, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              Text(style['desc'], style: TextStyle(color: AppTheme.subTextColor, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
          
          const SizedBox(height: 60),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.textColor.withOpacity(0.02),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.dividerColor),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: AppTheme.accentColor.withOpacity(0.5), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '配置已实时自动保存。自定义皮肤功能正在内测中，敬请期待。',
                    style: TextStyle(color: AppTheme.subTextColor, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApiConfigurationForm() {
    // 根据不同的子标签显示不同的API配置表单
    Widget formContent;
    switch (_apiSubTabIndex) {
      case 0: // LLM模型
        formContent = _buildLLMForm();
        break;
      case 1: // 图片模型
        formContent = _buildImageForm();
        break;
      case 2: // 视频模型
        formContent = _buildVideoForm();
        break;
      case 3: // 上传设置
        formContent = _buildUploadForm();
        break;
      default:
        formContent = _buildPlaceholderView();
    }

    return Column(
      children: [
        // 顶部：4个模型标签
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.dividerColor)),
          ),
          child: Row(
            children: List.generate(_apiSubTabs.length, (index) {
              final isSelected = _apiSubTabIndex == index;
              return Padding(
                padding: const EdgeInsets.only(right: 24),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      FocusScope.of(context).unfocus();
                      setState(() => _apiSubTabIndex = index);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.sideBarItemHover : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected ? AppTheme.accentColor.withValues(alpha: 0.5) : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        _apiSubTabs[index],
                        style: TextStyle(
                          color: isSelected ? AppTheme.textColor : AppTheme.subTextColor,
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        // 表单内容区域
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(40),
            child: formContent,
          ),
        ),
      ],
    );
  }

  Widget _buildLLMForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('API 服务商'),
        const SizedBox(height: 10),
        _buildProviderDropdown(
          value: _llmProvider,
          onChanged: (v) {
            setState(() => _llmProvider = v);
            _llmBaseUrlController.text = _getDefaultBaseUrl(v);
            _saveLLMConfig();
          },
        ),
        
        const SizedBox(height: 30),
        _buildFieldLabel('API Key'),
        const SizedBox(height: 10),
        _buildEditableTextField(
          _llmApiKeyController, 
          '请输入您的 API 密钥...', 
          isPassword: true,
          isVisible: _llmApiKeyVisible,
          onToggleVisibility: () => setState(() => _llmApiKeyVisible = !_llmApiKeyVisible),
          onCopy: () async {
            await Clipboard.setData(ClipboardData(text: _llmApiKeyController.text));
            _showMessage('API Key 已复制', isError: false);
          },
          onSave: () => _debouncedSave(_saveLLMConfig), // ✅ 自动保存（带防抖）
        ),
        
        const SizedBox(height: 30),
        _buildFieldLabel('Base URL (API 地址)'),
        const SizedBox(height: 10),
        _buildEditableTextField(
          _llmBaseUrlController, 
          'https://api.openai.com/v1',
          onSave: () => _debouncedSave(_saveLLMConfig), // ✅ 自动保存（带防抖）
        ),
        
        const SizedBox(height: 30),
        _buildFieldLabel('选择推理模型'),
        const SizedBox(height: 10),
        _buildModelSelector(
          provider: _llmProvider,
          modelType: 'llm',
          controller: _llmModelController,
          hint: '例如: gpt-4-turbo',
        ),
        
        const SizedBox(height: 40),
        _buildTestButton(() => _testLLMConnection()),
        
        const SizedBox(height: 20),
        Text(
          '* 提示：填写的 API 信息将加密自动保存在本地，仅用于模型推理。',
          style: TextStyle(color: AppTheme.subTextColor, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildImageForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('API 服务商'),
        const SizedBox(height: 10),
        _buildProviderDropdown(
          value: _imageProvider,
          onChanged: (v) {
            setState(() => _imageProvider = v);
            _imageBaseUrlController.text = _getDefaultBaseUrl(v);
            _saveImageConfig();
          },
        ),
        
        const SizedBox(height: 30),
        _buildFieldLabel('API Key'),
        const SizedBox(height: 10),
        _buildEditableTextField(
          _imageApiKeyController, 
          '请输入您的 API 密钥...', 
          isPassword: true,
          isVisible: _imageApiKeyVisible,
          onToggleVisibility: () => setState(() => _imageApiKeyVisible = !_imageApiKeyVisible),
          onCopy: () async {
            await Clipboard.setData(ClipboardData(text: _imageApiKeyController.text));
            _showMessage('API Key 已复制', isError: false);
          },
          onSave: () => _debouncedSave(_saveImageConfig), // ✅ 自动保存（带防抖）
        ),
        
        const SizedBox(height: 30),
        _buildFieldLabel('Base URL (API 地址)'),
        const SizedBox(height: 10),
        _buildEditableTextField(
          _imageBaseUrlController, 
          'https://api.openai.com/v1',
          onSave: () => _debouncedSave(_saveImageConfig), // ✅ 自动保存（带防抖）
        ),
        
        const SizedBox(height: 30),
        _buildFieldLabel('选择推理模型'),
        const SizedBox(height: 10),
        _buildModelSelector(
          provider: _imageProvider,
          modelType: 'image',
          controller: _imageModelController,
          hint: '例如: dall-e-3',
        ),
        
        const SizedBox(height: 40),
        _buildTestButton(() => _testImageConnection()),
        
        const SizedBox(height: 20),
        Text(
          '* 提示：填写的 API 信息将加密自动保存在本地，仅用于模型推理。',
          style: TextStyle(color: AppTheme.subTextColor, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildVideoForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('API 服务商'),
        const SizedBox(height: 10),
        _buildProviderDropdown(
          value: _videoProvider,
          onChanged: (v) {
            setState(() => _videoProvider = v);
            _videoBaseUrlController.text = _getDefaultBaseUrl(v);
            _saveVideoConfig();
          },
        ),
        
        const SizedBox(height: 30),
        _buildFieldLabel('API Key'),
        const SizedBox(height: 10),
        _buildEditableTextField(
          _videoApiKeyController, 
          '请输入您的 API 密钥...', 
          isPassword: true,
          isVisible: _videoApiKeyVisible,
          onToggleVisibility: () => setState(() => _videoApiKeyVisible = !_videoApiKeyVisible),
          onCopy: () async {
            await Clipboard.setData(ClipboardData(text: _videoApiKeyController.text));
            _showMessage('API Key 已复制', isError: false);
          },
          onSave: () => _debouncedSave(_saveVideoConfig), // ✅ 自动保存（带防抖）
        ),
        
        const SizedBox(height: 30),
        _buildFieldLabel('Base URL (API 地址)'),
        const SizedBox(height: 10),
        _buildEditableTextField(
          _videoBaseUrlController, 
          'https://api.openai.com/v1',
          onSave: () => _debouncedSave(_saveVideoConfig), // ✅ 自动保存（带防抖）
        ),
        
        const SizedBox(height: 30),
        _buildFieldLabel('选择推理模型'),
        const SizedBox(height: 10),
        _buildModelSelector(
          provider: _videoProvider,
          modelType: 'video',
          controller: _videoModelController,
          hint: '例如: veo_3_1 或 sora-2',
        ),
        
        const SizedBox(height: 40),
        _buildTestButton(() => _testVideoConnection()),
        
        const SizedBox(height: 20),
        Text(
          '* 提示：填写的 API 信息将加密自动保存在本地，仅用于模型推理。',
          style: TextStyle(color: AppTheme.subTextColor, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildUploadForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('API 服务商'),
        const SizedBox(height: 10),
        _buildProviderDropdown(
          value: _uploadProvider,
          onChanged: (v) {
            setState(() => _uploadProvider = v);
            _uploadBaseUrlController.text = _getDefaultBaseUrl(v);
            _saveUploadConfig();
          },
        ),
        
        const SizedBox(height: 30),
        _buildFieldLabel('API Key'),
        const SizedBox(height: 10),
        _buildEditableTextField(
          _uploadApiKeyController, 
          '请输入您的 API 密钥...', 
          isPassword: true,
          isVisible: _uploadApiKeyVisible,
          onToggleVisibility: () => setState(() => _uploadApiKeyVisible = !_uploadApiKeyVisible),
          onCopy: () async {
            await Clipboard.setData(ClipboardData(text: _uploadApiKeyController.text));
            _showMessage('API Key 已复制', isError: false);
          },
          onSave: () => _debouncedSave(_saveUploadConfig), // ✅ 自动保存（带防抖）
        ),
        
        const SizedBox(height: 30),
        _buildFieldLabel('Base URL (API 地址)'),
        const SizedBox(height: 10),
        _buildEditableTextField(
          _uploadBaseUrlController, 
          'https://api.openai.com/v1',
          onSave: () => _debouncedSave(_saveUploadConfig), // ✅ 自动保存（带防抖）
        ),
        
        const SizedBox(height: 40),
        _buildTestButton(() => _testUploadConnection()),
      ],
    );
  }


  Widget _buildProviderDropdown({required String value, required Function(String) onChanged}) {
    final providers = ['openai', 'geeknow', 'yunwu', 'azure', 'anthropic'];
    final displayNames = {
      'openai': 'OpenAI',
      'geeknow': 'GeekNow',
      'yunwu': 'Yunwu（云雾）',
      'azure': 'Azure',
      'anthropic': 'Anthropic',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textColor.withOpacity(0.05)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: AppTheme.surfaceBackground,
          icon: Icon(Icons.unfold_more_rounded, color: AppTheme.subTextColor, size: 20),
          items: providers.map((e) => DropdownMenuItem(
            value: e, 
            child: Text(displayNames[e] ?? e, style: TextStyle(color: AppTheme.textColor, fontSize: 14))
          )).toList(),
          onChanged: (v) {
            if (v != null) {
              onChanged(v);
            }
          },
        ),
      ),
    );
  }

  Widget _buildEditableTextField(
    TextEditingController controller, 
    String hint, {
    bool isPassword = false, 
    bool? isVisible,
    VoidCallback? onToggleVisibility,
    VoidCallback? onCopy,
    VoidCallback? onSave,
  }) {
    final shouldObscure = isPassword && (isVisible == null || !isVisible);
    
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textColor.withOpacity(0.05)),
      ),
      child: TextField(
        controller: controller,
        obscureText: shouldObscure,
        enabled: true,
        enableInteractiveSelection: true,
        enableSuggestions: true,
        autocorrect: false,
        keyboardType: TextInputType.url, // 🔧 使用 url 类型以获得更好的输入支持
        textInputAction: TextInputAction.done,
        style: TextStyle(color: AppTheme.textColor, fontSize: 14),
        // 🔧 添加自定义右键菜单，确保复制粘贴可用
        contextMenuBuilder: (context, editableTextState) {
          return AdaptiveTextSelectionToolbar.editableText(
            editableTextState: editableTextState,
          );
        },
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          hintText: hint,
          hintStyle: TextStyle(color: AppTheme.subTextColor),
          suffixIcon: isPassword
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 粘贴按钮（密码字段）
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () async {
                          try {
                            final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
                            if (clipboardData?.text != null && clipboardData!.text!.isNotEmpty) {
                              controller.text = clipboardData.text!;
                              controller.selection = TextSelection.collapsed(
                                offset: controller.text.length,
                              );
                              // 触发自动保存
                              onSave?.call();
                              _showMessage('已粘贴', isError: false);
                            } else {
                              _showMessage('剪贴板为空', isError: true);
                            }
                          } catch (e) {
                            _showMessage('粘贴失败: $e', isError: true);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Tooltip(
                            message: '粘贴',
                            child: Icon(Icons.content_paste, color: AppTheme.subTextColor, size: 18),
                          ),
                        ),
                      ),
                    ),
                    // 复制按钮
                    if (onCopy != null)
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: onCopy,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Tooltip(
                              message: '复制',
                              child: Icon(Icons.copy, color: AppTheme.subTextColor, size: 18),
                            ),
                          ),
                        ),
                      ),
                    // 查看/隐藏按钮
                    if (onToggleVisibility != null)
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: onToggleVisibility,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Tooltip(
                              message: (isVisible ?? false) ? '隐藏' : '显示',
                              child: Icon(
                                (isVisible ?? false) ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                                color: AppTheme.subTextColor,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                )
              // 🔧 为非密码字段添加粘贴按钮
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () async {
                          try {
                            final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
                            if (clipboardData?.text != null && clipboardData!.text!.isNotEmpty) {
                              final selection = controller.selection;
                              final text = controller.text;
                              final newText = text.replaceRange(
                                selection.start,
                                selection.end,
                                clipboardData.text!,
                              );
                              controller.text = newText;
                              controller.selection = TextSelection.collapsed(
                                offset: selection.start + clipboardData.text!.length,
                              );
                              // 触发自动保存
                              onSave?.call();
                            } else {
                              _showMessage('剪贴板为空', isError: true);
                            }
                          } catch (e) {
                            _showMessage('粘贴失败: $e', isError: true);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Tooltip(
                            message: '粘贴',
                            child: Icon(Icons.content_paste, color: AppTheme.subTextColor, size: 18),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        onChanged: (v) {
          // ✅ 触发自动保存（已在外部使用防抖包装）
          onSave?.call();
        },
      ),
    );
  }

  /// 智能模型选择器（支持 GeekNow 和 Yunwu）
  Widget _buildModelSelector({
    required String provider,
    required String modelType,
    required TextEditingController controller,
    required String hint,
  }) {
    // 根据服务商选择对应的模型列表
    List<String> models = [];
    
    if (provider == 'geeknow') {
      models = _geekNowModels[modelType] ?? [];
    } else if (provider == 'yunwu') {
      models = _yunwuModels[modelType] ?? [];
    } else {
      // 其他服务商使用普通文本输入
      return _buildEditableTextField(controller, hint);
    }

    // GeekNow 和 Yunwu 使用下拉选择器
    final currentModel = controller.text.isEmpty ? null : controller.text;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textColor.withOpacity(0.05)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: models.contains(currentModel) ? currentModel : null,
          hint: Text(hint, style: TextStyle(color: AppTheme.subTextColor)),
          isExpanded: true,
          dropdownColor: AppTheme.surfaceBackground,
          icon: Icon(Icons.unfold_more_rounded, color: AppTheme.subTextColor, size: 20),
          items: models.map((model) {
            return DropdownMenuItem(
              value: model,
              child: Text(model, style: TextStyle(color: AppTheme.textColor, fontSize: 14)),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() {
                controller.text = v;
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildSaveButton(VoidCallback onSave) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onSave,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF2AF598), Color(0xFF009EFD)]),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: const Color(0xFF2AF598).withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.save_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('保存配置', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTestButton(Future<void> Function() onTest) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTest,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.accentColor.withValues(alpha: 0.5), width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_find, color: AppTheme.textColor, size: 18),
              const SizedBox(width: 8),
              Text('测试', style: TextStyle(color: AppTheme.textColor, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _testLLMConnection() async {
    // 验证必填项
    if (_llmApiKeyController.text.trim().isEmpty) {
      _showTestResultDialog(
        title: 'LLM连接测试',
        success: false,
        message: '请先填写API Key',
      );
      return;
    }

    if (_llmBaseUrlController.text.trim().isEmpty) {
      _showTestResultDialog(
        title: 'LLM连接测试',
        success: false,
        message: '请先填写Base URL',
      );
      return;
    }

    _showTestResultDialog(
      title: 'LLM连接测试',
      success: null,
      message: '正在测试连接...\n\n服务商: $_llmProvider\nBase URL: ${_llmBaseUrlController.text}\nModel: ${_llmModelController.text}',
    );

    final startTime = DateTime.now();

    try {
      // 真实API测试
      final baseUrl = _llmBaseUrlController.text.trim();
      final apiKey = _llmApiKeyController.text.trim();
      final model = _llmModelController.text.trim().isEmpty ? 'gpt-3.5-turbo' : _llmModelController.text.trim();

      final response = await http.post(
        Uri.parse('$baseUrl/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'user', 'content': '测试连接'}
          ],
          'max_tokens': 10,
        }),
      ).timeout(const Duration(seconds: 10));

      final elapsed = DateTime.now().difference(startTime);
      
      if (mounted) {
        Navigator.pop(context);
        
        if (response.statusCode == 200) {
          // 连接成功，解析响应（不需要使用 data）
          _showTestResultDialog(
            title: 'LLM连接测试',
            success: true,
            message: '✅ 连接成功！\n\n服务商: $_llmProvider\nBase URL: $baseUrl\nModel: $model\n\n响应时间: ${elapsed.inMilliseconds}ms\n状态码: ${response.statusCode}',
          );
          _logger.success('LLM连接测试成功', module: '设置', extra: {'provider': _llmProvider, 'elapsed': elapsed.inMilliseconds});
        } else {
          _showTestResultDialog(
            title: 'LLM连接测试',
            success: false,
            message: '❌ 连接失败\n\n状态码: ${response.statusCode}\n错误: ${response.body}',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showTestResultDialog(
          title: 'LLM连接测试',
          success: false,
          message: '❌ 测试失败\n\n错误类型: ${e.runtimeType}\n错误信息: $e\n\n请检查：\n1. API Key是否正确\n2. Base URL是否正确\n3. 网络连接是否正常',
        );
      }
      _logger.error('LLM连接测试失败: $e', module: '设置');
    }
  }

  Future<void> _testImageConnection() async {
    if (_imageApiKeyController.text.trim().isEmpty) {
      _showTestResultDialog(
        title: '图片API连接测试',
        success: false,
        message: '请先填写API Key',
      );
      return;
    }

    if (_imageBaseUrlController.text.trim().isEmpty) {
      _showTestResultDialog(
        title: '图片API连接测试',
        success: false,
        message: '请先填写Base URL',
      );
      return;
    }

    _showTestResultDialog(
      title: '图片API连接测试',
      success: null,
      message: '正在测试连接...\n\n服务商: $_imageProvider',
    );

    final startTime = DateTime.now();

    try {
      final baseUrl = _imageBaseUrlController.text.trim();
      final apiKey = _imageApiKeyController.text.trim();

      // 测试端点可访问性
      final response = await http.get(
        Uri.parse(baseUrl),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      ).timeout(const Duration(seconds: 10));

      final elapsed = DateTime.now().difference(startTime);
      
      if (mounted) {
        Navigator.pop(context);
        
        if (response.statusCode < 500) {  // 任何非服务器错误都算连接成功
          _showTestResultDialog(
            title: '图片API连接测试',
            success: true,
            message: '✅ 连接成功！\n\n服务商: $_imageProvider\nBase URL: $baseUrl\nModel: ${_imageModelController.text}\n\n响应时间: ${elapsed.inMilliseconds}ms\n状态码: ${response.statusCode}',
          );
          _logger.success('图片API连接测试成功', module: '设置');
        } else {
          _showTestResultDialog(
            title: '图片API连接测试',
            success: false,
            message: '❌ 服务器错误\n\n状态码: ${response.statusCode}',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showTestResultDialog(
          title: '图片API连接测试',
          success: false,
          message: '❌ 连接失败\n\n错误: $e\n\n请检查API配置和网络连接',
        );
      }
    }
  }

  Future<void> _testVideoConnection() async {
    if (_videoApiKeyController.text.trim().isEmpty) {
      _showTestResultDialog(
        title: '视频API连接测试',
        success: false,
        message: '请先填写API Key',
      );
      return;
    }

    if (_videoBaseUrlController.text.trim().isEmpty) {
      _showTestResultDialog(
        title: '视频API连接测试',
        success: false,
        message: '请先填写Base URL',
      );
      return;
    }

    _showTestResultDialog(
      title: '视频API连接测试',
      success: null,
      message: '正在测试连接...\n\n服务商: $_videoProvider',
    );

    final startTime = DateTime.now();

    try {
      final baseUrl = _videoBaseUrlController.text.trim();
      final apiKey = _videoApiKeyController.text.trim();

      final response = await http.get(
        Uri.parse(baseUrl),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      ).timeout(const Duration(seconds: 10));

      final elapsed = DateTime.now().difference(startTime);
      
      if (mounted) {
        Navigator.pop(context);
        
        if (response.statusCode < 500) {
          _showTestResultDialog(
            title: '视频API连接测试',
            success: true,
            message: '✅ 连接成功！\n\n服务商: $_videoProvider\nBase URL: $baseUrl\nModel: ${_videoModelController.text}\n\n响应时间: ${elapsed.inMilliseconds}ms\n状态码: ${response.statusCode}',
          );
          _logger.success('视频API连接测试成功', module: '设置');
        } else {
          _showTestResultDialog(
            title: '视频API连接测试',
            success: false,
            message: '❌ 服务器错误\n\n状态码: ${response.statusCode}',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showTestResultDialog(
          title: '视频API连接测试',
          success: false,
          message: '❌ 连接失败\n\n错误: $e\n\n请检查API配置和网络连接',
        );
      }
    }
  }

  Future<void> _testUploadConnection() async {
    if (_uploadApiKeyController.text.trim().isEmpty) {
      _showTestResultDialog(
        title: '上传API连接测试',
        success: false,
        message: '请先填写API Key',
      );
      return;
    }

    if (_uploadBaseUrlController.text.trim().isEmpty) {
      _showTestResultDialog(
        title: '上传API连接测试',
        success: false,
        message: '请先填写Base URL',
      );
      return;
    }

    _showTestResultDialog(
      title: '上传API连接测试',
      success: null,
      message: '正在测试连接...\n\n服务商: $_uploadProvider',
    );

    final startTime = DateTime.now();

    try {
      final baseUrl = _uploadBaseUrlController.text.trim();
      final apiKey = _uploadApiKeyController.text.trim();

      final response = await http.get(
        Uri.parse(baseUrl),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      ).timeout(const Duration(seconds: 10));

      final elapsed = DateTime.now().difference(startTime);
      
      if (mounted) {
        Navigator.pop(context);
        
        if (response.statusCode < 500) {
          _showTestResultDialog(
            title: '上传API连接测试',
            success: true,
            message: '✅ 连接成功！\n\n服务商: $_uploadProvider\nBase URL: $baseUrl\n\n响应时间: ${elapsed.inMilliseconds}ms\n状态码: ${response.statusCode}',
          );
          _logger.success('上传API连接测试成功', module: '设置');
        } else {
          _showTestResultDialog(
            title: '上传API连接测试',
            success: false,
            message: '❌ 服务器错误\n\n状态码: ${response.statusCode}',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showTestResultDialog(
          title: '上传API连接测试',
          success: false,
          message: '❌ 连接失败\n\n错误: $e\n\n请检查API配置和网络连接',
        );
      }
    }
  }

  void _showTestResultDialog({
    required String title,
    required bool? success,  // null表示测试中
    required String message,
  }) {
    showDialog(
      context: context,
      barrierDismissible: success != null,  // 测试中不可关闭
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E20),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (success == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                color: success == null 
                    ? const Color(0xFF888888)
                    : success 
                        ? Colors.green 
                        : Colors.red,
                fontSize: 14,
              ),
            ),
          ],
        ),
        actions: success != null
            ? [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭', style: TextStyle(color: Color(0xFF888888))),
                ),
              ]
            : null,
      ),
    );
  }

  Widget _buildFormHeader(String title, {IconData icon = Icons.settings_input_component_rounded}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.accentColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppTheme.accentColor, size: 20),
        ),
        const SizedBox(width: 16),
        Text(
          title.contains('设置') ? title : '$title配置中心',
          style: TextStyle(color: AppTheme.textColor, fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(label, style: TextStyle(color: AppTheme.textColor.withOpacity(0.7), fontSize: 14, fontWeight: FontWeight.w500));
  }

  Widget _buildIconButton(IconData icon, String label, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: AppTheme.subTextColor, size: 18),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: AppTheme.subTextColor, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.construction_rounded, color: AppTheme.subTextColor, size: 64),
          const SizedBox(height: 16),
          Text(
            '${_mainTabs[_mainTabIndex]} 正在深度构建中...',
            style: TextStyle(color: AppTheme.subTextColor, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
