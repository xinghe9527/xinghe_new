# API服务架构文档

## 📁 目录结构

```
lib/services/api/
├── base/
│   ├── api_config.dart          # API配置模型
│   ├── api_response.dart        # 统一响应模型
│   └── api_service_base.dart    # API服务抽象基类
├── providers/
│   ├── openai_service.dart      # OpenAI实现（已完成）
│   └── custom_service.dart      # 自定义服务模板
├── api_factory.dart             # 服务工厂
├── api_repository.dart          # API仓库（统一入口）
├── secure_storage_manager.dart  # 安全存储管理器
└── README.md                    # 本文档
```

## 🔒 安全性

### API密钥加密存储
- 使用 `flutter_secure_storage` 加密存储所有敏感信息
- API密钥永远不会明文存储在本地文件或代码中
- 用户无法通过软件界面或文件系统直接访问其他用户的API密钥

### 存储规则
```dart
// API密钥存储格式
key: xinghe_api_{provider}_key
value: {encrypted_api_key}

// Base URL存储格式
key: xinghe_api_{provider}_url
value: {base_url}

// 模型配置存储格式
key: xinghe_api_{provider}_{modelType}_model
value: {model_name}
```

## 🏗️ 架构设计

### 解耦原则
每个API服务商都是独立的实现，互不影响：
```
应用层 → ApiRepository → ApiFactory → 具体服务实现
```

### 抽象基类
所有服务商必须实现 `ApiServiceBase` 接口：
- `testConnection()` - 测试API连接
- `generateText()` - LLM文本生成
- `generateImages()` - 图片生成
- `generateVideos()` - 视频生成
- `uploadAsset()` - 素材上传
- `getAvailableModels()` - 获取模型列表

## 🚀 如何添加新的API服务商

### 步骤1: 创建服务实现类

在 `providers/` 目录下创建新文件，例如 `anthropic_service.dart`:

```dart
import '../base/api_service_base.dart';
import '../base/api_config.dart';
import '../base/api_response.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AnthropicService extends ApiServiceBase {
  AnthropicService(super.config);

  @override
  String get providerName => 'Anthropic';

  @override
  Future<ApiResponse<bool>> testConnection() async {
    // 实现连接测试逻辑
  }

  @override
  Future<ApiResponse<LlmResponse>> generateText({
    required String prompt,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    // 根据Anthropic API文档实现
  }

  // ... 实现其他方法
}
```

### 步骤2: 在工厂中注册

编辑 `api_factory.dart`，添加新服务商：

```dart
ApiServiceBase createService(String provider, ApiConfig config) {
  switch (provider.toLowerCase()) {
    case 'openai':
      return OpenAIService(config);
    
    case 'anthropic':  // ← 添加这里
      return AnthropicService(config);
    
    // ...
  }
}
```

### 步骤3: 完成！

现在可以使用新的API服务商：

```dart
final repository = ApiRepository();

// 保存配置
await repository.saveConfig(
  provider: 'anthropic',
  apiKey: 'sk-ant-xxx',
  baseUrl: 'https://api.anthropic.com/v1',
);

// 使用服务
final response = await repository.generateText(
  provider: 'anthropic',
  prompt: '你好',
  model: 'claude-3-opus',
);
```

## 💡 使用示例

### 基础使用

```dart
import 'package:xinghe_new/services/api/api_repository.dart';

final apiRepo = ApiRepository();

// 1. 保存API配置（通常在设置页面）
await apiRepo.saveConfig(
  provider: 'openai',
  apiKey: userInput.apiKey,
  baseUrl: userInput.baseUrl,
);

// 2. 测试连接
final testResult = await apiRepo.testConnection(provider: 'openai');
if (testResult.success) {
  print('API连接成功');
}

// 3. 生成图片
final imageResult = await apiRepo.generateImages(
  provider: 'openai',
  prompt: '一个可爱的动漫少女',
  count: 4,
  ratio: '1:1',
  quality: '2K',
);

if (imageResult.success) {
  for (var image in imageResult.data!) {
    print('图片URL: ${image.imageUrl}');
  }
}

// 4. 生成视频
final videoResult = await apiRepo.generateVideos(
  provider: 'runway',
  prompt: '镜头缓缓推进',
  count: 2,
  referenceImages: ['path/to/image.png'],
);

// 5. 上传素材
final uploadResult = await apiRepo.uploadAsset(
  provider: 'openai',
  filePath: 'path/to/character.png',
  assetType: 'character',
);
```

### 在UI中使用

```dart
// 绘图空间生成示例
Future<void> _generateImage() async {
  final apiRepo = ApiRepository();
  
  // 从设置中获取当前选择的服务商
  final provider = await prefs.getString('image_provider') ?? 'openai';
  
  setState(() => _isGenerating = true);
  
  try {
    final response = await apiRepo.generateImages(
      provider: provider,
      prompt: _promptController.text,
      model: _selectedModel,
      count: _batchCount,
      ratio: _selectedRatio,
      quality: _selectedQuality,
    );
    
    if (response.success) {
      setState(() {
        _generatedImages.addAll(response.data!);
      });
      _showMessage('成功生成 ${response.data!.length} 张图片');
    } else {
      _showMessage('生成失败: ${response.error}', isError: true);
    }
  } finally {
    setState(() => _isGenerating = false);
  }
}
```

## 🔧 扩展性

### 添加新的功能
如果需要添加新功能（如音频生成），在基类中添加方法：

```dart
// api_service_base.dart
abstract class ApiServiceBase {
  // 现有方法...
  
  /// 音频生成（新功能）
  Future<ApiResponse<AudioResponse>> generateAudio({
    required String text,
    String? voice,
    Map<String, dynamic>? parameters,
  });
}
```

然后所有服务实现都需要实现这个方法。

### 自定义参数
使用 `parameters` 参数传递服务商特定的选项：

```dart
await apiRepo.generateImages(
  provider: 'midjourney',
  prompt: '测试',
  parameters: {
    'chaos': 50,        // Midjourney特有参数
    'stylize': 100,     // Midjourney特有参数
    'version': '5.2',
  },
);
```

## ⚠️ 注意事项

1. **永远不要硬编码API密钥**
   - 所有密钥必须从用户输入获取
   - 使用 `SecureStorageManager` 存储

2. **错误处理**
   - 所有API调用都返回 `ApiResponse<T>`
   - 始终检查 `response.success` 状态
   - 向用户友好地展示 `response.error`

3. **服务商差异**
   - 不同服务商的API可能不支持所有功能
   - 返回相应的错误消息（如 "OpenAI暂不支持视频生成"）

4. **性能优化**
   - `ApiRepository` 会缓存服务实例
   - 避免频繁创建新实例
   - 使用 `forceRefresh` 参数在必要时刷新

## 📝 开发清单

添加新API服务商时的检查清单：

- [ ] 创建服务实现类 (extends `ApiServiceBase`)
- [ ] 实现所有必需方法
- [ ] 在 `ApiFactory` 中注册
- [ ] 测试API连接
- [ ] 测试所有功能（文本、图片、视频、上传）
- [ ] 处理特殊错误情况
- [ ] 更新文档
