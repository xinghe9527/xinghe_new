import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/api/api_repository.dart';
import '../../../services/api/secure_storage_manager.dart';
import '../../../core/logger/log_manager.dart';
import '../domain/models/script_line.dart';
import '../domain/models/entity.dart';

/// 真实 AI 服务（调用实际的 API）
class RealAIService {
  final ApiRepository _apiRepository = ApiRepository();
  final SecureStorageManager _storage = SecureStorageManager();
  final LogManager _logger = LogManager();
  final Random _random = Random();

  /// 获取配置的 provider 和 model
  Future<Map<String, String?>> _getLLMConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('llm_provider') ?? 'openai';
      final model = await _storage.getModel(provider: provider, modelType: 'llm');
      return {'provider': provider, 'model': model};
    } catch (e) {
      return {'provider': 'openai', 'model': null};
    }
  }

  Future<Map<String, String?>> _getImageConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('image_provider') ?? 'openai';
      final model = await _storage.getModel(provider: provider, modelType: 'image');
      return {'provider': provider, 'model': model};
    } catch (e) {
      return {'provider': 'openai', 'model': null};
    }
  }

  Future<Map<String, String?>> _getVideoConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('video_provider') ?? 'openai';
      final model = await _storage.getModel(provider: provider, modelType: 'video');
      return {'provider': provider, 'model': model};
    } catch (e) {
      return {'provider': 'openai', 'model': null};
    }
  }

  /// 生成中文剧本
  Future<List<ScriptLine>> generateScript({
    required String theme,
    String? presetPrompt,  // ✅ 新增：剧本提示词预设
  }) async {
    _logger.info('🎬 开始生成剧本', module: 'RealAIService', extra: {'theme': theme});
    
    final config = await _getLLMConfig();
    final provider = config['provider']!;
    final model = config['model'];
    
    // 读取完整配置用于日志
    final apiKey = await _storage.getApiKey(provider: provider, modelType: 'llm');
    final baseUrl = await _storage.getBaseUrl(provider: provider, modelType: 'llm');
    
    _logger.info('📋 LLM配置信息', module: 'RealAIService', extra: {
      'provider': provider,
      'model': model ?? '未设置',
      'baseUrl': baseUrl ?? '未配置',
      'apiKey': apiKey != null ? '${apiKey.substring(0, 10)}...' : '未配置',
    });

    // ✅ 简洁的提示词，不添加任何额外要求
    final prompt = '''请根据以下主题创作一个动画剧本。

主题：$theme

格式要求：
- 使用中文创作
- 每个场景用【场景】或【对白】标注

现在开始创作：''';

    _logger.info('📝 提示词长度', module: 'RealAIService', extra: {'length': prompt.length});

    try {
      final startTime = DateTime.now();
      _logger.info('🚀 开始调用 API', module: 'RealAIService');
      
      // ✅ 清除缓存，确保使用最新配置
      _apiRepository.clearCache();
      _logger.info('🔄 已清除 API 缓存', module: 'RealAIService');
      
      // ✅ 构建 messages 数组（提示词预设融入 user message 前面）
      final messages = <Map<String, String>>[];
      
      // ✅ 将提示词预设作为用户消息的一部分（而不是 system message）
      String fullUserPrompt = '';
      
      if (presetPrompt != null && presetPrompt.isNotEmpty) {
        // 提示词预设放在最前面，作为强制指令
        fullUserPrompt = '''【重要指令 - 必须严格遵守】
$presetPrompt

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

$prompt''';
        
        _logger.info('✨ 使用提示词预设（融入用户消息）', module: 'RealAIService', extra: {'preset': presetPrompt});
        print('\n🎨 提示词预设（作为强制指令）:');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print(presetPrompt);
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      } else {
        fullUserPrompt = prompt;
        _logger.info('⚠️ 没有提示词预设', module: 'RealAIService');
      }
      
      // 添加用户消息（包含提示词预设）
      messages.add({
        'role': 'user',
        'content': fullUserPrompt,
      });
      
      print('📨 完整 Messages 数组:');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      for (int i = 0; i < messages.length; i++) {
        print('Message ${i + 1}:');
        print('  Role: ${messages[i]['role']}');
        print('  Content: ${messages[i]['content']!.substring(0, messages[i]['content']!.length > 200 ? 200 : messages[i]['content']!.length)}...');
      }
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      
      // 调用 LLM API（直接传递 messages）
      final response = await _apiRepository.generateTextWithMessages(
        provider: provider,
        messages: messages,
        model: model,
        parameters: {
          'temperature': 0.7,
          'max_tokens': 8000,  // ✅ 增加到 8000
        },
      );
      
      final elapsed = DateTime.now().difference(startTime).inSeconds;
      _logger.info('⏱️ API 响应时间', module: 'RealAIService', extra: {'seconds': elapsed});

      if (response.isSuccess && response.data != null) {
        final responseText = response.data!.text;
        
        _logger.success('✅ API 调用成功', module: 'RealAIService', extra: {
          'responseLength': responseText.length,
          'tokensUsed': response.data!.tokensUsed ?? 0,
        });
        
        // 📄 打印 API 实际返回的完整内容
        print('\n📄 API 返回的原始文本:');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print(responseText);
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
        
        // ✅ 检查是否因为 max_tokens 被截断
        final metadata = response.data!.metadata;
        if (metadata != null && metadata['choices'] != null) {
          final finishReason = metadata['choices'][0]['finish_reason'];
          if (finishReason == 'length') {
            print('⚠️ 警告：剧本被截断（达到 max_tokens 限制）\n');
            _logger.warning('剧本被截断', module: 'RealAIService', extra: {
              'finishReason': 'length',
              'tokensUsed': response.data!.tokensUsed,
            });
            // ✅ 抛出特定异常，让界面显示提示
            throw Exception('CONTENT_TOO_LONG');
          } else {
            print('✅ 剧本生成完整，finish_reason: $finishReason\n');
          }
        }
        
        // 解析响应文本，提取剧本行
        final scriptLines = _parseScriptFromResponse(responseText);
        _logger.success('🎉 剧本生成成功', module: 'RealAIService', extra: {'lines': scriptLines.length});
        
        return scriptLines;
      } else {
        final errorDetail = response.error ?? '未知错误';
        _logger.error('❌ API 返回错误', module: 'RealAIService', extra: {
          'error': errorDetail,
          'statusCode': response.statusCode ?? 0,
          'provider': provider,
          'baseUrl': baseUrl,
          'model': model ?? '未设置',
        });
        
        // ✅ 抛出包含详细调试信息的异常
        throw Exception(
          '生成剧本失败\n\n'
          '【配置信息】\n'
          'Provider: $provider\n'
          'Model: ${model ?? "未设置"}\n'
          'Base URL: $baseUrl\n\n'
          '【错误详情】\n'
          '$errorDetail'
        );
      }
    } catch (e) {
      _logger.error('💥 调用 API 异常', module: 'RealAIService', extra: {'exception': e.toString()});
      throw Exception('调用 API 失败: $e');
    }
  }

  /// ✅ 简化解析：直接返回 API 原始文本，不做任何解析
  List<ScriptLine> _parseScriptFromResponse(String responseText) {
    print('✅ 使用 API 原始文本作为剧本（不做任何解析和修改）\n');
    
    // ✅ 直接返回原始文本，不做任何解析、拆分或修改
    return [
      ScriptLine(
        id: _generateId(),
        content: responseText,  // ✅ 完整的原始文本
        type: ScriptLineType.action,
        aiPrompt: '',  // 不需要 AI 提示词
        contextTags: [],  // 不需要标签
      ),
    ];
  }


  /// 扩写剧本（在指定位置插入新内容）
  Future<ScriptLine> expandScript({
    required String previousContext,
    required String nextContext,
  }) async {
    final config = await _getLLMConfig();
    final provider = config['provider']!;
    final model = config['model'];

    final prompt = '''你是一个专业的编剧。请在以下两个场景之间，补充一个过渡场景。

前一个场景：$previousContext

后一个场景：$nextContext

要求：
1. 创作一个合理的过渡场景（动作描述或对白）
2. 生成 AI 绘画提示词（英文）
3. 添加相关标签

格式：
场景内容：...
AI提示词：...
标签：...''';

    try {
      final response = await _apiRepository.generateText(
        provider: provider,
        prompt: prompt,
        model: model,
        parameters: {'temperature': 0.7, 'max_tokens': 500},
      );

      if (response.isSuccess && response.data != null) {
        final lines = _parseScriptFromResponse(response.data!.text);
        return lines.isNotEmpty ? lines.first : _getDefaultExpandedLine();
      } else {
        return _getDefaultExpandedLine();
      }
    } catch (e) {
      return _getDefaultExpandedLine();
    }
  }

  ScriptLine _getDefaultExpandedLine() {
    return ScriptLine(
      id: _generateId(),
      content: '镜头切换，时间流逝。',
      type: ScriptLineType.action,
      aiPrompt: 'Transition scene, time passing',
      contextTags: ['过渡'],
    );
  }

  /// 从剧本提取实体
  Future<List<Entity>> extractEntities({
    required List<ScriptLine> scriptLines,
  }) async {
    final config = await _getLLMConfig();
    final provider = config['provider']!;
    final model = config['model'];

    // 将剧本内容合并
    final scriptContent = scriptLines.map((line) => line.content).join('\n');

    final prompt = '''分析以下剧本，提取关键实体（角色、场景、物品）。

剧本：
$scriptContent

要求：
1. 识别所有重要角色（人物）
2. 识别主要场景（地点）
3. 识别关键物品
4. 为每个实体生成详细的 AI 绘画描述（英文，统一风格）

输出格式（每个实体一组）：
类型：角色/场景/物品
名称：...
描述：...（英文，适合 AI 绘画）

---

示例：
类型：角色
名称：主角
描述：Young protagonist, silver hair, blue eyes, black cyberpunk jacket, anime style

类型：场景
名称：未来都市
描述：Futuristic cyberpunk city, tall buildings, holographic billboards, purple-blue tone

现在开始分析：''';

    try {
      final response = await _apiRepository.generateText(
        provider: provider,
        prompt: prompt,
        model: model,
        parameters: {'temperature': 0.5, 'max_tokens': 1500},
      );

      if (response.isSuccess && response.data != null) {
        return _parseEntitiesFromResponse(response.data!.text);
      } else {
        return _getDefaultEntities();
      }
    } catch (e) {
      return _getDefaultEntities();
    }
  }

  /// 解析实体响应
  List<Entity> _parseEntitiesFromResponse(String responseText) {
    final entities = <Entity>[];
    final sections = responseText.split('---');

    for (final section in sections) {
      String? type;
      String? name;
      String? description;

      for (final line in section.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        if (trimmed.startsWith('类型：') || trimmed.toLowerCase().startsWith('type:')) {
          type = trimmed.replaceFirst(RegExp(r'类型：|type:', caseSensitive: false), '').trim();
        } else if (trimmed.startsWith('名称：') || trimmed.toLowerCase().startsWith('name:')) {
          name = trimmed.replaceFirst(RegExp(r'名称：|name:', caseSensitive: false), '').trim();
        } else if (trimmed.startsWith('描述：') || trimmed.toLowerCase().startsWith('description:')) {
          description = trimmed.replaceFirst(RegExp(r'描述：|description:', caseSensitive: false), '').trim();
        }
      }

      if (name != null && description != null) {
        EntityType entityType = EntityType.scene; // 默认为场景
        if (type != null) {
          if (type.contains('角色') || type.toLowerCase().contains('character')) {
            entityType = EntityType.character;
          } else if (type.contains('场景') || type.toLowerCase().contains('scene')) {
            entityType = EntityType.scene;
          }
          // 如果是物品类型，也归类为场景元素
        }

        entities.add(Entity(
          id: _generateId(),
          type: entityType,
          name: name,
          fixedPrompt: description,
          isLocked: false,
        ));
      }
    }

    return entities.isEmpty ? _getDefaultEntities() : entities;
  }

  List<Entity> _getDefaultEntities() {
    return [
      Entity(
        id: _generateId(),
        type: EntityType.character,
        name: '主角',
        fixedPrompt: 'Main character, anime style',
        isLocked: false,
      ),
    ];
  }

  /// 生成分镜图片（返回图片URL）
  Future<String> generateStoryboardImage({
    required String prompt,
  }) async {
    final config = await _getImageConfig();
    final provider = config['provider']!;
    final model = config['model'];

    try {
      final response = await _apiRepository.generateImages(
        provider: provider,
        prompt: prompt,
        model: model,
        count: 1,
        parameters: {
          'quality': 'standard',
          'size': '1024x1024',
        },
      );

      if (response.isSuccess && response.data != null && response.data!.isNotEmpty) {
        return response.data!.first.imageUrl;
      } else {
        throw Exception('生成图片失败: ${response.error ?? "未知错误"}');
      }
    } catch (e) {
      throw Exception('调用图片 API 失败: $e');
    }
  }

  /// 生成视频片段（返回视频URL）
  Future<String> generateVideoClip({
    required String prompt,
    String? imageUrl,
    String? startFrameUrl,
    String? endFrameUrl,
  }) async {
    final config = await _getVideoConfig();
    final provider = config['provider']!;
    final model = config['model'];

    try {
      final referenceImages = <String>[];
      if (imageUrl != null) referenceImages.add(imageUrl);
      if (startFrameUrl != null) referenceImages.add(startFrameUrl);
      if (endFrameUrl != null) referenceImages.add(endFrameUrl);

      final response = await _apiRepository.generateVideos(
        provider: provider,
        prompt: prompt,
        model: model,
        count: 1,
        referenceImages: referenceImages.isNotEmpty ? referenceImages : null,
        parameters: {
          'duration': 5,
          'quality': 'standard',
        },
      );

      if (response.isSuccess && response.data != null && response.data!.isNotEmpty) {
        return response.data!.first.videoUrl;
      } else {
        throw Exception('生成视频失败: ${response.error ?? "未知错误"}');
      }
    } catch (e) {
      throw Exception('调用视频 API 失败: $e');
    }
  }

  /// 拼接最终提示词
  String buildFinalPrompt({
    required String sceneDescription,
    required List<Entity> involvedEntities,
    required String scriptContent,
  }) {
    final parts = <String>[];

    // 场景描述
    parts.add('Scene: $sceneDescription');

    // 角色固定描述
    for (final entity in involvedEntities) {
      if (entity.type == EntityType.character && entity.isLocked) {
        parts.add('${entity.name}: ${entity.fixedPrompt}');
      }
    }

    // 当前剧本意图
    parts.add('Action: $scriptContent');

    return parts.join(', ');
  }

  /// 生成唯一ID
  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        _random.nextInt(1000).toString();
  }
}
