# API服务使用示例

## 📋 完整集成示例

### 1. 在设置页面保存API配置

```dart
// settings_page.dart
import 'package:xinghe_new/services/api/api_repository.dart';
import 'package:xinghe_new/services/api/secure_storage_manager.dart';

class _SettingsPageState extends State<SettingsPage> {
  final ApiRepository _apiRepo = ApiRepository();
  final SecureStorageManager _storage = SecureStorageManager();
  
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController();
  
  String _selectedProvider = 'openai';
  
  // 保存API配置
  Future<void> _saveApiConfig() async {
    try {
      await _apiRepo.saveConfig(
        provider: _selectedProvider,
        apiKey: _apiKeyController.text.trim(),
        baseUrl: _baseUrlController.text.trim(),
      );
      
      // 测试连接
      final testResult = await _apiRepo.testConnection(
        provider: _selectedProvider,
      );
      
      if (testResult.success) {
        _showMessage('API配置成功', isError: false);
      } else {
        _showMessage('API连接失败: ${testResult.error}', isError: true);
      }
    } catch (e) {
      _showMessage('保存失败: $e', isError: true);
    }
  }
  
  // 加载已保存的配置
  Future<void> _loadApiConfig() async {
    final apiKey = await _storage.getApiKey(provider: _selectedProvider);
    final baseUrl = await _storage.getBaseUrl(provider: _selectedProvider);
    
    setState(() {
      _apiKeyController.text = apiKey ?? '';
      _baseUrlController.text = baseUrl ?? '';
    });
  }
}
```

### 2. 在绘图空间使用API生成图片

```dart
// drawing_space.dart
import 'package:xinghe_new/services/api/api_repository.dart';

class _DrawingSpaceState extends State<DrawingSpace> {
  final ApiRepository _apiRepo = ApiRepository();
  
  String _currentProvider = 'openai'; // 从设置中读取
  
  Future<void> _generateImage() async {
    if (_promptController.text.trim().isEmpty) {
      _showMessage('请输入提示词', isError: true);
      return;
    }
    
    setState(() => _isGenerating = true);
    
    try {
      // 检查是否已配置API
      final hasConfig = await _apiRepo.hasProvider(
        provider: _currentProvider,
      );
      
      if (!hasConfig) {
        _showMessage('请先在设置中配置API', isError: true);
        return;
      }
      
      // 批量生成图片
      _showMessage('开始生成 $_batchCount 张图片...', isError: false);
      
      final response = await _apiRepo.generateImages(
        provider: _currentProvider,
        prompt: _promptController.text.trim(),
        model: _selectedModel,
        count: _batchCount,
        ratio: _selectedRatio,
        quality: _selectedQuality,
        referenceImages: _insertedImages.map((f) => f.path).toList(),
      );
      
      if (response.success && response.data != null) {
        setState(() {
          // 添加生成的图片到列表
          for (var image in response.data!) {
            _generatedImages.insert(0, image.imageUrl);
          }
        });
        
        _showMessage('成功生成 ${response.data!.length} 张图片', isError: false);
        
        // TODO: 保存到本地 imageSavePathNotifier.value
      } else {
        _showMessage('生成失败: ${response.error}', isError: true);
      }
    } catch (e) {
      _showMessage('生成错误: $e', isError: true);
    } finally {
      setState(() => _isGenerating = false);
    }
  }
}
```

### 3. 在视频空间使用API生成视频

```dart
// video_space.dart
import 'package:xinghe_new/services/api/api_repository.dart';

class _VideoSpaceState extends State<VideoSpace> {
  final ApiRepository _apiRepo = ApiRepository();
  
  String _currentProvider = 'runway'; // 从设置中读取
  
  Future<void> _generateVideo() async {
    if (_promptController.text.trim().isEmpty) {
      _showMessage('请输入提示词', isError: true);
      return;
    }
    
    setState(() => _isGenerating = true);
    
    try {
      _showMessage('开始生成 $_batchCount 个视频...', isError: false);
      
      final response = await _apiRepo.generateVideos(
        provider: _currentProvider,
        prompt: _promptController.text.trim(),
        model: _selectedModel,
        count: _batchCount,
        ratio: _selectedRatio,
        quality: _selectedQuality,
        referenceImages: _insertedImages.map((f) => f.path).toList(),
      );
      
      if (response.success && response.data != null) {
        setState(() {
          for (var video in response.data!) {
            _generatedVideos.insert(0, video.videoUrl);
          }
        });
        
        _showMessage('成功生成 ${response.data!.length} 个视频', isError: false);
        
        // TODO: 保存到本地 videoSavePathNotifier.value
      } else {
        _showMessage('生成失败: ${response.error}', isError: true);
      }
    } catch (e) {
      _showMessage('生成错误: $e', isError: true);
    } finally {
      setState(() => _isGenerating = false);
    }
  }
}
```

### 4. 在素材库上传素材

```dart
// asset_library.dart
import 'package:xinghe_new/services/api/api_repository.dart';

class _AssetLibraryState extends State<AssetLibrary> {
  final ApiRepository _apiRepo = ApiRepository();
  
  String _currentProvider = 'openai'; // 从设置中读取
  
  Future<void> _uploadAsset(AssetItem asset) async {
    setState(() => asset.isUploading = true);
    
    try {
      final response = await _apiRepo.uploadAsset(
        provider: _currentProvider,
        filePath: asset.path,
        assetType: _getCategoryType(), // 'character', 'scene', 'item'
      );
      
      if (response.success && response.data != null) {
        setState(() {
          asset.isUploaded = true;
          asset.uploadedId = response.data!.uploadId;
          asset.isUploading = false;
        });
        
        _showMessage('上传成功: ${asset.uploadedId}', isError: false);
      } else {
        setState(() => asset.isUploading = false);
        _showMessage('上传失败: ${response.error}', isError: true);
      }
    } catch (e) {
      setState(() => asset.isUploading = false);
      _showMessage('上传错误: $e', isError: true);
    }
  }
  
  String _getCategoryType() {
    switch (_selectedCategoryIndex) {
      case 0:
        return 'character';
      case 1:
        return 'scene';
      case 2:
        return 'item';
      default:
        return 'other';
    }
  }
}
```

### 5. 获取和显示可用模型

```dart
// settings_page.dart
Future<void> _loadAvailableModels() async {
  try {
    final response = await _apiRepo.getAvailableModels(
      provider: _selectedProvider,
      modelType: 'image', // 'llm', 'image', 'video'
    );
    
    if (response.success && response.data != null) {
      setState(() {
        _availableModels = response.data!;
      });
    }
  } catch (e) {
    print('加载模型列表失败: $e');
  }
}
```

### 6. 切换API服务商

```dart
// 在设置页面，让用户选择不同的服务商
class _SettingsPageState extends State<SettingsPage> {
  final List<Map<String, String>> _providers = [
    {'id': 'openai', 'name': 'OpenAI', 'description': 'GPT-4, DALL-E'},
    {'id': 'anthropic', 'name': 'Anthropic', 'description': 'Claude'},
    {'id': 'midjourney', 'name': 'Midjourney', 'description': '高质量图片生成'},
    {'id': 'runway', 'name': 'Runway', 'description': '专业视频生成'},
    {'id': 'pika', 'name': 'Pika', 'description': '快速视频生成'},
  ];
  
  String _selectedProvider = 'openai';
  
  // 保存当前使用的服务商到SharedPreferences
  Future<void> _saveCurrentProvider(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_image_provider', provider);
    await prefs.setString('current_video_provider', provider);
    await prefs.setString('current_llm_provider', provider);
  }
}
```

## 🔐 安全性最佳实践

### 1. 永远不要在代码中硬编码API密钥

❌ **错误示例：**
```dart
const String API_KEY = 'sk-xxxxxxxxxxxxx'; // 绝对不要这样做！
```

✅ **正确示例：**
```dart
// 从用户输入获取
final apiKey = userInputController.text;
await _apiRepo.saveConfig(provider: 'openai', apiKey: apiKey, ...);
```

### 2. 检查API配置状态

```dart
Future<bool> _checkApiConfigured() async {
  final hasConfig = await _apiRepo.hasProvider(provider: _currentProvider);
  
  if (!hasConfig) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('未配置API'),
        content: const Text('请先在设置中配置API密钥'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // 跳转到设置页面
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
    return false;
  }
  
  return true;
}
```

### 3. 处理API错误

```dart
Future<void> _handleApiCall() async {
  try {
    final response = await _apiRepo.generateImages(...);
    
    if (response.success) {
      // 成功处理
    } else {
      // 根据错误类型提供友好提示
      String errorMessage = response.error ?? '未知错误';
      
      if (response.statusCode == 401) {
        errorMessage = 'API密钥无效，请检查设置';
      } else if (response.statusCode == 429) {
        errorMessage = 'API请求过于频繁，请稍后再试';
      } else if (response.statusCode == 500) {
        errorMessage = 'API服务器错误';
      }
      
      _showMessage(errorMessage, isError: true);
    }
  } catch (e) {
    _showMessage('网络连接失败', isError: true);
  }
}
```

## 📝 完整工作流程

1. **用户首次使用**
   - 打开设置 → 选择API服务商 → 输入API密钥和Base URL → 保存
   - 系统自动测试连接 → 加载可用模型列表

2. **生成内容**
   - 用户在绘图/视频空间输入提示词
   - 选择参数（模型、比例、清晰度、批量）
   - 点击生成 → ApiRepository路由到对应服务 → 返回结果
   - 自动保存到本地指定文件夹

3. **上传素材**
   - 用户在素材库添加图片
   - 点击上传 → ApiRepository调用上传接口 → 获得素材ID
   - 保存ID，后续生成时可以引用

## 🎯 总结

这个API架构的核心优势：

1. ✅ **安全性**：API密钥加密存储，用户无法互相访问
2. ✅ **解耦性**：每个服务商独立实现，互不影响
3. ✅ **扩展性**：添加新服务商只需实现接口并注册
4. ✅ **统一性**：所有API调用通过ApiRepository统一管理
5. ✅ **易用性**：简单的API，清晰的错误处理
