# Gemini 3 Pro 图像生成 - 快速开始

## 🚀 5分钟快速上手

### 步骤 1: 配置 API Key

在您的项目中配置 API Key(选择以下任一方式):

#### 方式 A: 使用环境变量(.env 文件)

```env
# .env
YUNWU_API_KEY=your_api_key_here
```

```dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

// 加载环境变量
await dotenv.load();
final apiKey = dotenv.env['YUNWU_API_KEY'] ?? '';
```

#### 方式 B: 使用安全存储

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final storage = FlutterSecureStorage();

// 保存 API Key(只需要做一次)
await storage.write(key: 'yunwu_api_key', value: 'your_api_key_here');

// 读取 API Key
final apiKey = await storage.read(key: 'yunwu_api_key') ?? '';
```

### 步骤 2: 创建服务实例

```dart
import 'package:xinghe_new/services/api/api_factory.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';

// 方式 A: 直接创建
import 'package:xinghe_new/services/api/providers/gemini_pro_image_service.dart';

final config = ApiConfig(
  provider: 'yunwu',
  apiKey: 'YOUR_API_KEY',
  baseUrl: 'https://yunwu.ai',
  model: 'gemini-3-pro-image-preview',
);

final service = GeminiProImageService(config);

// 方式 B: 使用工厂(推荐)
final factory = ApiFactory();
final service = factory.createService('yunwu', config);
```

### 步骤 3: 生成图片

```dart
// 简单文本生图
final result = await service.generateImages(
  prompt: 'A beautiful sunset over the ocean',
);

if (result.isSuccess && result.data != null) {
  final image = result.data!.first;
  final base64Data = image.base64Data;
  
  // 在 Flutter 中显示
  Image.memory(base64Decode(base64Data!));
}
```

## 📋 完整示例

```dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:xinghe_new/services/api/api_factory.dart';
import 'package:xinghe_new/services/api/base/api_config.dart';

class QuickStartExample extends StatefulWidget {
  @override
  _QuickStartExampleState createState() => _QuickStartExampleState();
}

class _QuickStartExampleState extends State<QuickStartExample> {
  String? _imageBase64;
  bool _loading = false;

  Future<void> _generateImage() async {
    setState(() => _loading = true);

    // 1. 创建服务
    final config = ApiConfig(
      provider: 'yunwu',
      apiKey: 'YOUR_API_KEY',
      baseUrl: 'https://yunwu.ai',
      model: 'gemini-3-pro-image-preview',
    );
    
    final factory = ApiFactory();
    final service = factory.createService('yunwu', config);

    // 2. 生成图片
    final result = await service.generateImages(
      prompt: 'A cute cat playing with a ball',
      ratio: '1:1',
      quality: '2K',
    );

    // 3. 处理结果
    if (result.isSuccess && result.data != null) {
      setState(() {
        _imageBase64 = result.data!.first.metadata?['base64Data'];
      });
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('快速开始')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_loading)
              CircularProgressIndicator()
            else if (_imageBase64 != null)
              Image.memory(base64Decode(_imageBase64!))
            else
              Text('点击按钮生成图片'),
            
            SizedBox(height: 20),
            
            ElevatedButton(
              onPressed: _generateImage,
              child: Text('生成图片'),
            ),
          ],
        ),
      ),
    );
  }
}
```

## 🎨 常用配置

### 不同宽高比

```dart
// 正方形 - 适合头像、图标
await service.generateImages(
  prompt: 'Logo design',
  ratio: '1:1',
);

// 横屏 - 适合电脑壁纸
await service.generateImages(
  prompt: 'Desktop wallpaper',
  ratio: '16:9',
);

// 竖屏 - 适合手机壁纸
await service.generateImages(
  prompt: 'Phone wallpaper',
  ratio: '9:16',
);
```

### 不同清晰度

```dart
// 快速预览 - 1K
await service.generateImages(
  prompt: 'Quick preview',
  quality: '1K',
);

// 标准质量 - 2K
await service.generateImages(
  prompt: 'Standard quality',
  quality: '2K',
);

// 高清 - 4K
await service.generateImages(
  prompt: 'High resolution',
  quality: '4K',
);
```

### 图生图

```dart
await service.generateImages(
  prompt: 'Transform this into a watercolor painting',
  referenceImages: ['/path/to/your/image.jpg'],
  ratio: '1:1',
);
```

## 💾 保存图片到文件

```dart
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

Future<void> saveImage(String base64Data) async {
  // 解码 Base64
  final bytes = base64Decode(base64Data);
  
  // 获取应用文档目录
  final directory = await getApplicationDocumentsDirectory();
  
  // 保存文件
  final file = File('${directory.path}/generated_image.jpg');
  await file.writeAsBytes(bytes);
  
  print('图片已保存到: ${file.path}');
}
```

## ⚡ 使用技巧

### 1. 测试连接

```dart
final connectionTest = await service.testConnection();
if (connectionTest.isSuccess) {
  print('API 连接正常');
}
```

### 2. 错误处理

```dart
final result = await service.generateImages(prompt: prompt);

if (!result.isSuccess) {
  print('错误: ${result.error}');
  print('状态码: ${result.statusCode}');
}
```

### 3. 获取元数据

```dart
if (result.isSuccess && result.data != null) {
  final image = result.data!.first;
  
  print('完成原因: ${image.metadata?['finishReason']}');
  print('安全评级: ${image.metadata?['safetyRatings']}');
  print('MIME 类型: ${image.metadata?['mimeType']}');
}
```

## 📱 在 UI 中集成

### 在列表中显示

```dart
ListView.builder(
  itemCount: images.length,
  itemBuilder: (context, index) {
    final base64 = images[index].metadata?['base64Data'];
    return Image.memory(
      base64Decode(base64!),
      fit: BoxFit.cover,
    );
  },
)
```

### 在网格中显示

```dart
GridView.builder(
  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    crossAxisSpacing: 8,
    mainAxisSpacing: 8,
  ),
  itemCount: images.length,
  itemBuilder: (context, index) {
    final base64 = images[index].metadata?['base64Data'];
    return Image.memory(base64Decode(base64!));
  },
)
```

## 🔧 常见问题

### Q: API Key 从哪里获取?
A: 需要在云雾 API 平台注册并获取 API Key。

### Q: 返回的是 URL 还是 Base64?
A: 返回的是 Base64 编码的图片数据,不是 URL。

### Q: 如何显示生成的图片?
A: 使用 `Image.memory(base64Decode(base64Data))`

### Q: 支持批量生成吗?
A: 可以通过循环调用 `generateImages` 实现批量生成。

### Q: 生成速度有多快?
A: 取决于网络状况和图片尺寸,通常 2K 图片需要 5-10 秒。

## 📚 更多资源

- [完整使用文档](GEMINI_PRO_IMAGE_USAGE.md)
- [示例代码](../../../examples/gemini_pro_image_example.dart)
- [API 配置](../base/api_config.dart)
- [API 工厂](../api_factory.dart)

## 🎯 下一步

1. ✅ 配置 API Key
2. ✅ 运行快速示例
3. 📖 阅读完整文档
4. 🚀 集成到您的应用中
5. 🎨 尝试不同的参数组合

Happy coding! 🎉
