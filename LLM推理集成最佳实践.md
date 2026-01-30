# LLM 推理集成最佳实践总结

> **版本**: 1.0  
> **适用场景**: 集成 LLM API 进行内容生成（剧本、文本、对话等）  
> **经验来源**: 星橙AI动漫制作项目 - 故事生成剧本功能

---

## 📋 目录

1. [核心设计原则](#核心设计原则)
2. [API 集成架构](#api-集成架构)
3. [提示词预设机制](#提示词预设机制)
4. [常见问题和解决方案](#常见问题和解决方案)
5. [代码实现要点](#代码实现要点)
6. [最佳实践清单](#最佳实践清单)

---

## 1. 核心设计原则

### 1.1 完全尊重用户输入

**❌ 错误做法**:
```dart
// 代码中硬编码要求
final prompt = '''
要求：
1. 使用中文
2. 添加英文 AI 提示词  ← 用户没要求
3. 添加标签            ← 用户没要求
4. 赛博朋克风格        ← 强制风格
''';
```

**✅ 正确做法**:
```dart
// 最简洁的基础指令
final prompt = '''
请根据以下主题创作内容。

主题：$theme

格式要求：
- 使用中文创作
- {其他格式要求}

现在开始创作：
''';
```

**原则**: 代码只提供最基础的格式要求，所有风格、细节控制交给用户的提示词预设。

### 1.2 不做不必要的处理

**❌ 错误做法**:
```dart
// 解析、拆分、重组内容
final parsed = parseResponse(apiText);  // 可能丢失内容
final formatted = formatOutput(parsed); // 可能添加额外内容
return formatted;  // 不是原始内容
```

**✅ 正确做法**:
```dart
// 直接返回 API 原始内容
return apiText;  // 原封不动
```

**原则**: API 返回什么就显示什么，不解析、不拆分、不重组。

### 1.3 完全透明的日志

**❌ 错误做法**:
```dart
// 用户看不到实际发生了什么
await api.generate(prompt);  // 黑盒
```

**✅ 正确做法**:
```dart
print('📍 完整 URL: $fullUrl');
print('🎯 模型: $model');
print('📝 Messages: ${messages.length} 条');
print('📄 API 返回: $responseText');
print('✅ finish_reason: $finishReason');
```

**原则**: 让用户能看到完整的调试信息，方便排查问题。

---

## 2. API 集成架构

### 2.1 分层架构

```
┌─────────────────────────────────────┐
│   用户界面 (StoryInputPage)          │
│   - 收集用户输入                     │
│   - 显示生成结果                     │
│   - 处理错误提示                     │
└───────────────┬─────────────────────┘
                ↓
┌─────────────────────────────────────┐
│   业务逻辑 (RealAIService)           │
│   - 构建提示词                       │
│   - 处理提示词预设                   │
│   - 调用 API                        │
│   - 检测截断                        │
└───────────────┬─────────────────────┘
                ↓
┌─────────────────────────────────────┐
│   API 仓库 (ApiRepository)           │
│   - 管理服务实例                     │
│   - 读取用户配置                     │
│   - 统一调用接口                     │
└───────────────┬─────────────────────┘
                ↓
┌─────────────────────────────────────┐
│   具体服务 (GeekNowService 等)       │
│   - 构建 HTTP 请求                  │
│   - 发送请求                        │
│   - 解析响应                        │
└─────────────────────────────────────┘
```

### 2.2 配置读取机制

**关键**: 必须传递 `modelType` 参数！

```dart
// ❌ 错误：读取不到配置
final apiKey = await storage.getApiKey(provider: provider);  
// 存储 key: xinghe_api_llm_geeknow_key
// 读取 key: xinghe_api_geeknow_key  ← 不匹配！

// ✅ 正确：传递 modelType
final apiKey = await storage.getApiKey(
  provider: provider,
  modelType: 'llm',  // ← 必须指定
);
// 存储 key: xinghe_api_llm_geeknow_key
// 读取 key: xinghe_api_llm_geeknow_key  ✅ 匹配！
```

### 2.3 Base URL 处理

**原则**: 完全使用用户配置，不添加任何前缀！

```dart
// ✅ 正确处理
final cleanBaseUrl = config.baseUrl.endsWith('/') 
    ? config.baseUrl.substring(0, config.baseUrl.length - 1)
    : config.baseUrl;

final endpoint = '/chat/completions';  // ← 不添加 /v1
final fullUrl = '$cleanBaseUrl$endpoint';

// 用户配置: https://www.geeknow.top/v1
// 完整 URL: https://www.geeknow.top/v1/chat/completions  ✅
```

**常见错误**:
```dart
// ❌ 硬编码路径前缀
final endpoint = '/v1/chat/completions';  // 如果用户 Base URL 已包含 /v1 就会重复
```

---

## 3. 提示词预设机制

### 3.1 工作原理

**Messages 数组结构**:
```json
[
  {
    "role": "user",
    "content": "【重要指令 - 必须严格遵守】\n{用户的提示词预设}\n\n━━━━━━\n\n{基础生成指令}"
  }
]
```

**为什么不用 system message**:
- 有些 LLM（如 DeepSeek）会忽略 system message
- 放在 user message 最前面，用强调标记，效果更好

### 3.2 代码实现

```dart
// ✅ 正确实现
String fullUserPrompt = '';

if (presetPrompt != null && presetPrompt.isNotEmpty) {
  fullUserPrompt = '''【重要指令 - 必须严格遵守】
$presetPrompt

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

$prompt''';
} else {
  fullUserPrompt = prompt;
}

final messages = [
  {'role': 'user', 'content': fullUserPrompt}
];
```

### 3.3 基础指令的设计

**❌ 错误：添加太多要求**
```dart
final prompt = '''
要求：
1. 使用中文
2. 添加英文提示词  ← 多余
3. 添加标签        ← 多余
4. 赛博朋克风格    ← 限制了创作自由
5. 5-8个场景      ← 限制了长度
6. 详细的xxx      ← 限制了风格
''';
```

**✅ 正确：最简洁**
```dart
final prompt = '''
请根据以下主题创作内容。

主题：$theme

格式要求：
- 使用中文创作
- 用【场景】或【对白】标注

现在开始创作：
''';
```

**原则**: 基础指令越简单越好，让提示词预设完全控制细节。

---

## 4. 常见问题和解决方案

### 4.1 问题：生成内容与预期不符

**症状**:
- 设置了提示词预设，但 LLM 没有遵守
- 生成的内容风格不对

**排查步骤**:
1. 检查控制台日志，确认提示词预设是否被传递
2. 检查 Messages 数组是否正确构建
3. 检查是否有代码中的硬编码要求干扰

**解决方案**:
```dart
// 1. 确保提示词预设放在最前面
if (presetPrompt != null) {
  print('🎨 提示词预设: $presetPrompt');
}

// 2. 使用强调标记
fullPrompt = '【重要指令 - 必须严格遵守】\n$presetPrompt\n\n...';

// 3. 删除所有硬编码的要求
// ❌ 删除: "添加英文提示词"、"赛博朋克风格" 等
```

### 4.2 问题：显示内容与 API 返回不一致

**症状**:
- API 返回了正确内容（从日志看到）
- 但界面显示的不对

**常见原因**:
1. 解析逻辑错误，返回了默认内容
2. 显示代码自动添加了额外内容

**解决方案**:
```dart
// ❌ 不要解析
List<ScriptLine> _parseResponse(String text) {
  // 复杂的解析逻辑...
  if (parsed.isEmpty) {
    return _getDefaultScript();  // ← 错误的默认内容
  }
}

// ✅ 直接使用原始文本
List<ScriptLine> _parseResponse(String text) {
  return [
    ScriptLine(
      content: text,  // ← 原封不动
    )
  ];
}

// ✅ 显示时不添加额外内容
final display = scriptLines.map((line) => line.content).join('\n\n');
// 不要: '$prefix${line.content}\nAI提示词：...'
```

### 4.3 问题：重复的标签（如【场景】【场景】）

**症状**:
```
【场景】【场景】青竹村...
```

**原因**:
- API 返回的 content 已包含【场景】
- 代码又添加了一次

**解决方案**:
```dart
// ❌ 不要添加前缀
String prefix = '【场景】';
return '$prefix${line.content}';

// ✅ 直接使用内容
return line.content;
```

### 4.4 问题：剧本被截断

**症状**:
- 故事有后续情节，但剧本没有生成

**排查**:
```dart
// 检查 finish_reason
if (metadata['choices'][0]['finish_reason'] == 'length') {
  print('⚠️ 剧本被截断');
}
```

**解决方案**:
```dart
// 1. 增加 max_tokens
parameters: {
  'max_tokens': 8000,  // 根据需要调整
}

// 2. 提示用户精简内容
if (finishReason == 'length') {
  throw Exception('CONTENT_TOO_LONG');
}
```

### 4.5 问题：API 配置读取失败

**症状**:
- 测试连接成功
- 生成失败，返回 404 或其他错误

**常见原因**:
1. ApiFactory 未注册服务商
2. 端点路径错误
3. Base URL 处理错误

**解决方案**:
```dart
// 1. 在 ApiFactory 中注册
case 'geeknow':
  return GeekNowService(config);

// 2. 端点路径不硬编码 /v1
final endpoint = '/chat/completions';  // ✅
// 不要: '/v1/chat/completions'  ❌

// 3. 清理 Base URL 末尾斜杠
final cleanBaseUrl = baseUrl.endsWith('/') 
    ? baseUrl.substring(0, baseUrl.length - 1)
    : baseUrl;
```

---

## 5. 代码实现要点

### 5.1 服务类模板

```dart
class XxxService extends ApiServiceBase {
  @override
  Future<ApiResponse<LlmResponse>> generateTextWithMessages({
    required List<Map<String, String>> messages,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      final useModel = model ?? config.model ?? 'default-model';
      final requestBody = {
        'model': useModel,
        'messages': messages,  // ← 直接使用传入的 messages
        ...?parameters,
      };

      // ✅ 清理 Base URL
      final cleanBaseUrl = config.baseUrl.endsWith('/') 
          ? config.baseUrl.substring(0, config.baseUrl.length - 1)
          : config.baseUrl;
      
      final endpoint = '/chat/completions';  // ← 不添加 /v1
      final fullUrl = '$cleanBaseUrl$endpoint';
      
      // ✅ 详细日志
      print('📍 完整 URL: $fullUrl');
      print('🎯 模型: $useModel');
      
      final response = await http.post(
        Uri.parse(fullUrl),
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 60));
      
      // ✅ 接受所有 2xx 状态码
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        final text = data['choices'][0]['message']['content'];
        
        return ApiResponse.success(
          LlmResponse(text: text, ...),
        );
      } else {
        return ApiResponse.failure('生成失败: ${response.statusCode}');
      }
    } catch (e) {
      return ApiResponse.failure('生成错误: $e');
    }
  }

  // ✅ 提供兼容接口
  @override
  Future<ApiResponse<LlmResponse>> generateText({
    required String prompt,
    String? model,
    Map<String, dynamic>? parameters,
  }) async {
    return await generateTextWithMessages(
      messages: [{'role': 'user', 'content': prompt}],
      model: model,
      parameters: parameters,
    );
  }
}
```

### 5.2 提示词预设集成

```dart
Future<List<ScriptLine>> generateScript({
  required String theme,
  String? presetPrompt,  // ← 提示词预设
}) async {
  // ✅ 构建 messages
  final messages = <Map<String, String>>[];
  
  // 基础指令
  final basePrompt = '''请创作内容。主题：$theme''';
  
  // ✅ 融入提示词预设
  String fullPrompt = '';
  if (presetPrompt != null && presetPrompt.isNotEmpty) {
    fullPrompt = '''【重要指令 - 必须严格遵守】
$presetPrompt

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

$basePrompt''';
    
    print('🎨 提示词预设: $presetPrompt');
  } else {
    fullPrompt = basePrompt;
  }
  
  messages.add({'role': 'user', 'content': fullPrompt});
  
  // ✅ 打印完整 Messages
  print('📨 完整 Messages:');
  for (var msg in messages) {
    print('  Role: ${msg['role']}');
    print('  Content: ${msg['content']}');
  }
  
  // 调用 API
  final response = await apiRepository.generateTextWithMessages(
    messages: messages,
    model: model,
    parameters: {
      'temperature': 0.7,
      'max_tokens': 8000,
    },
  );
  
  // ✅ 打印原始返回
  print('📄 API 返回: ${response.data.text}');
  
  // ✅ 直接返回，不解析
  return [
    ScriptLine(
      content: response.data.text,  // ← 原封不动
    )
  ];
}
```

### 5.3 截断检测

```dart
// ✅ 检测并处理截断
final metadata = response.data.metadata;
if (metadata?['choices']?[0]?['finish_reason'] == 'length') {
  print('⚠️ 内容被截断');
  throw Exception('CONTENT_TOO_LONG');  // ← 特定异常
}

// 界面捕获
try {
  await generateScript(...);
} catch (e) {
  if (e.toString().contains('CONTENT_TOO_LONG')) {
    showDialog(...);  // 友好提示
  }
}
```

---

## 6. 常见坑和避坑指南

### 坑1: 缓存导致配置不生效

**问题**: 修改了配置，但仍使用旧配置

**原因**: ApiRepository 缓存了服务实例

**解决**:
```dart
// 每次调用前清除缓存
apiRepository.clearCache();
```

### 坑2: debugPrint 不显示

**问题**: debugPrint 的内容看不到

**解决**: 使用 print
```dart
// ❌ 可能不显示
debugPrint('调试信息');

// ✅ 一定显示
print('调试信息');
```

### 坑3: Base URL 末尾斜杠

**问题**: `https://api.xxx.com/` + `/chat/completions` = `https://api.xxx.com//chat/completions`

**解决**: 总是清理末尾斜杠
```dart
final cleanBaseUrl = baseUrl.endsWith('/') 
    ? baseUrl.substring(0, baseUrl.length - 1)
    : baseUrl;
```

### 坑4: 端点路径重复 /v1

**问题**: 
```
Base URL: https://api.xxx.com/v1
端点: /v1/chat/completions
结果: https://api.xxx.com/v1/v1/chat/completions  ❌
```

**解决**: 端点路径不包含 /v1，让用户在 Base URL 中配置
```dart
final endpoint = '/chat/completions';  // ✅ 不包含 /v1
```

### 坑5: 默认内容覆盖 API 返回

**问题**: 
```dart
if (parsed.isEmpty) {
  return getDefaultContent();  // ← 覆盖了真实内容
}
```

**解决**: 永远不要返回硬编码的默认内容
```dart
// ✅ 直接使用 API 返回
return [ScriptLine(content: apiText)];
```

---

## 7. 最佳实践清单

### ✅ 必须做的

- [x] 使用 `generateTextWithMessages` 支持完整 messages 数组
- [x] 清理 Base URL 末尾斜杠
- [x] 端点路径不硬编码 /v1
- [x] 传递 modelType 读取配置
- [x] 使用 print 输出关键日志
- [x] 直接返回 API 原始文本
- [x] 检测 finish_reason 判断截断
- [x] 清除缓存确保配置生效

### ❌ 不要做的

- [ ] 不要在代码中硬编码风格要求
- [ ] 不要解析、拆分 API 返回的内容
- [ ] 不要返回硬编码的默认内容
- [ ] 不要在显示时添加额外字段
- [ ] 不要在端点路径中硬编码 /v1
- [ ] 不要忽略用户的提示词预设

### 🔍 调试技巧

**关键日志输出**:
```dart
// 1. 配置信息
print('🔑 API Key: ${apiKey.substring(0, 10)}...');
print('🌐 Base URL: $baseUrl');

// 2. 请求信息
print('📍 完整 URL: $fullUrl');
print('📨 Messages: ${messages.length} 条');

// 3. 响应信息
print('📊 状态码: ${response.statusCode}');
print('📄 API 返回: $responseText');
print('✅ finish_reason: $finishReason');
```

---

## 8. 完整工作流程

### 用户操作流程
```
1. 用户输入故事
   ↓
2. 用户选择提示词预设（可选）
   ↓
3. 点击"生成剧本"
   ↓
4. 显示生成的剧本
```

### 代码执行流程
```
1. 读取配置 (provider, model, baseUrl, apiKey)
   ↓
2. 构建 Messages 数组
   - 如果有提示词预设: 放在最前面
   - 添加基础生成指令
   ↓
3. 清除 API 缓存
   ↓
4. 调用 API
   - generateTextWithMessages(messages, model, params)
   ↓
5. 获取响应
   - 检查 finish_reason
   - 打印原始文本
   ↓
6. 直接返回原始文本
   - 不解析、不修改
   ↓
7. 显示在界面
   - line.content (不添加前缀)
```

---

## 9. 新服务商集成步骤

### 步骤1: 创建服务类

```dart
// lib/services/api/providers/xxx_service.dart
class XxxService extends ApiServiceBase {
  XxxService(super.config);
  
  @override
  String get providerName => 'Xxx';
  
  // 实现 generateTextWithMessages
  // 实现 generateText (调用 generateTextWithMessages)
  // 实现其他方法...
}
```

### 步骤2: 注册到 ApiFactory

```dart
// lib/services/api/api_factory.dart
import 'providers/xxx_service.dart';

case 'xxx':
  return XxxService(config);
```

### 步骤3: 添加到设置界面

```dart
// lib/features/home/presentation/settings_page.dart

// 服务商列表
if (modelType == 'llm') {
  providers = [..., 'xxx'];
}

// 显示名称
displayNames = {
  ...,
  'xxx': 'Xxx服务商',
};

// 默认 Base URL
case 'xxx':
  return 'https://api.xxx.com';
```

### 步骤4: 添加模型列表（可选）

```dart
// 如果需要下拉选择
final Map<String, List<String>> _xxxModels = {
  'llm': ['model1', 'model2'],
};

// 或者允许手动输入
if (provider == 'xxx') {
  return _buildEditableTextField(controller, hint);
}
```

---

## 10. 关键经验总结

### 设计哲学

**"少即是多"**:
- 代码提供最简接口
- 用户通过提示词预设控制细节
- 不做不必要的处理

**"原汁原味"**:
- API 返回什么就显示什么
- 不解析、不修改、不添加

**"完全透明"**:
- 所有关键信息都输出到日志
- 用户能看到完整的调试过程

### 技术要点

1. **配置读取**: 必须传递 modelType
2. **URL 构建**: 完全使用用户配置，不添加前缀
3. **消息格式**: 支持完整 messages 数组
4. **提示词预设**: 放在 user message 最前面
5. **内容处理**: 不解析、不修改
6. **错误处理**: 检测截断，友好提示
7. **日志输出**: 使用 print，输出关键信息

### 避免的错误

1. ❌ 硬编码风格要求
2. ❌ 解析并重组内容
3. ❌ 返回默认内容
4. ❌ 添加额外字段
5. ❌ 硬编码 URL 路径
6. ❌ 忽略提示词预设
7. ❌ 使用 debugPrint（可能不显示）

---

## 11. 测试验证方法

### 测试1: 提示词预设是否生效

**步骤**:
1. 设置提示词预设: "无论我输入什么都显示111"
2. 生成内容
3. 检查是否返回 "111"

**预期**: 应该返回 "111"（说明提示词预设完全控制了输出）

### 测试2: 不添加额外内容

**步骤**:
1. 生成内容
2. 检查控制台"📄 API 返回"
3. 对比界面显示

**预期**: 界面显示应该与 API 返回完全一致

### 测试3: 配置正确读取

**步骤**:
1. 修改 Base URL
2. 查看控制台"📍 完整 URL"
3. 确认使用了新配置

**预期**: 应该使用最新配置，不是缓存

### 测试4: 截断检测

**步骤**:
1. 输入超长故事
2. 生成内容
3. 查看是否提示"内容过多"

**预期**: 应该检测到截断并提示

---

## 12. 故障排查流程

```
生成失败
    ↓
检查控制台日志
    ↓
┌────────────────┬─────────────────┬──────────────────┐
│ 没有"📍 URL"   │ 有 URL，404    │ 有 URL，401/403 │
├────────────────┼─────────────────┼──────────────────┤
│ 服务未注册      │ 端点路径错误    │ API Key 错误     │
│ 到 ApiFactory  │ Base URL 错误  │ 额度不足         │
│                │                 │ 权限不足         │
└────────────────┴─────────────────┴──────────────────┘
    ↓               ↓                 ↓
注册服务        修正 URL           检查 API Key
                清除缓存           充值/开通
```

---

## 附录 A: 完整的配置存储结构

```
SecureStorage 存储格式:

xinghe_api_{modelType}_{provider}_key     ← API Key
xinghe_api_{modelType}_{provider}_url     ← Base URL
xinghe_api_{provider}_{modelType}_model   ← 模型名称

示例:
xinghe_api_llm_geeknow_key
xinghe_api_llm_geeknow_url
xinghe_api_geeknow_llm_model
```

---

## 附录 B: 支持的服务商列表

| 服务商 | Base URL | 端点格式 | 兼容性 |
|--------|----------|----------|--------|
| OpenAI | `https://api.openai.com/v1` | OpenAI 标准 | 完全兼容 |
| GeekNow | `https://www.geeknow.top/v1` | OpenAI 兼容 | 完全兼容 |
| DeepSeek | `https://api.deepseek.com` | OpenAI 兼容 | 完全兼容 |
| 阿里云 | `https://dashscope.aliyuncs.com/compatible-mode/v1` | OpenAI 兼容 | 完全兼容 |
| Yunwu | `https://api.yunwu.ai/v1` | Gemini 格式 | 部分兼容 |

---

**文档结束**

> 本文档总结了在星橙AI项目中集成 LLM API 的所有经验教训和最佳实践。
> 
> 核心原则：**简单、透明、尊重用户**
> 
> 适用于任何需要集成 LLM API 进行内容生成的场景。

---

**版本历史**:
- v1.0 (2026-01-30): 初始版本，基于故事生成剧本功能的实践经验
