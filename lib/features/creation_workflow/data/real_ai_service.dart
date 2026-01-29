import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/api/api_repository.dart';
import '../../../services/api/secure_storage_manager.dart';
import '../domain/models/script_line.dart';
import '../domain/models/entity.dart';

/// 真实 AI 服务（调用实际的 API）
class RealAIService {
  final ApiRepository _apiRepository = ApiRepository();
  final SecureStorageManager _storage = SecureStorageManager();
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
  Future<List<ScriptLine>> generateScript({required String theme}) async {
    final config = await _getLLMConfig();
    final provider = config['provider']!;
    final model = config['model'];

    // 构建提示词
    final prompt = '''你是一个专业的编剧。请根据以下主题创作一个简短的动画剧本（5-8个场景）。

主题：$theme

要求：
1. 使用中文创作
2. 每个场景包含：场景描述（动作）或角色对白
3. 格式：每行一个场景，明确标注【场景】或【对白】
4. 为每个场景生成适合 AI 绘画的提示词（英文，赛博朋克/动漫风格）
5. 添加上下文标签，帮助理解剧情

示例格式：
【场景】黎明时分，紫色的天空下，一座未来都市的轮廓渐渐清晰。
AI提示词：Purple dawn sky, futuristic city silhouette, cyberpunk style
标签：开场,都市,黎明

【对白】主角：「又是新的一天，今天会发生什么呢？」
AI提示词：Young protagonist on balcony, overlooking city, thoughtful expression
标签：主角,独白,思考

现在开始创作：''';

    try {
      // 调用 LLM API
      final response = await _apiRepository.generateText(
        provider: provider,
        prompt: prompt,
        model: model,
        parameters: {
          'temperature': 0.7,
          'max_tokens': 2000,
        },
      );

      if (response.isSuccess && response.data != null) {
        // 解析响应文本，提取剧本行
        return _parseScriptFromResponse(response.data!.text);
      } else {
        throw Exception('生成剧本失败: ${response.error ?? "未知错误"}');
      }
    } catch (e) {
      throw Exception('调用 API 失败: $e');
    }
  }

  /// 解析 LLM 返回的剧本文本
  List<ScriptLine> _parseScriptFromResponse(String responseText) {
    final lines = <ScriptLine>[];
    final sections = responseText.split('\n\n');

    for (final section in sections) {
      if (section.trim().isEmpty) continue;

      final sectionLines = section.split('\n');
      String? content;
      String? aiPrompt;
      List<String> tags = [];
      ScriptLineType type = ScriptLineType.action;

      for (final line in sectionLines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        if (trimmed.startsWith('【场景】') || trimmed.startsWith('【动作】')) {
          content = trimmed.replaceFirst(RegExp(r'【[^】]+】'), '').trim();
          type = ScriptLineType.action;
        } else if (trimmed.startsWith('【对白】') || trimmed.contains('：「')) {
          content = trimmed.replaceFirst(RegExp(r'【[^】]+】'), '').trim();
          type = ScriptLineType.dialogue;
        } else if (trimmed.startsWith('AI提示词：') || trimmed.toLowerCase().startsWith('prompt:')) {
          aiPrompt = trimmed.replaceFirst(RegExp(r'AI提示词：|prompt:', caseSensitive: false), '').trim();
        } else if (trimmed.startsWith('标签：') || trimmed.toLowerCase().startsWith('tags:')) {
          final tagString = trimmed.replaceFirst(RegExp(r'标签：|tags:', caseSensitive: false), '').trim();
          tags = tagString.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        } else if (content == null) {
          // 如果还没有内容，将这行作为内容
          content = trimmed;
        }
      }

      if (content != null && content.isNotEmpty) {
        lines.add(ScriptLine(
          id: _generateId(),
          content: content,
          type: type,
          aiPrompt: aiPrompt ?? content,
          contextTags: tags.isEmpty ? ['未分类'] : tags,
        ));
      }
    }

    // 如果解析失败或结果太少，返回默认的简单剧本
    if (lines.length < 3) {
      return _getDefaultScript();
    }

    return lines;
  }

  /// 获取默认剧本（作为后备）
  List<ScriptLine> _getDefaultScript() {
    return [
      ScriptLine(
        id: _generateId(),
        content: '故事开始，镜头缓缓推进。',
        type: ScriptLineType.action,
        aiPrompt: 'Opening scene, camera slowly pushing forward, cinematic',
        contextTags: ['开场'],
      ),
      ScriptLine(
        id: _generateId(),
        content: '主角登场。',
        type: ScriptLineType.action,
        aiPrompt: 'Main character appears, dramatic entrance',
        contextTags: ['主角', '登场'],
      ),
      ScriptLine(
        id: _generateId(),
        content: '故事发展，情节推进。',
        type: ScriptLineType.action,
        aiPrompt: 'Story development, plot progression',
        contextTags: ['剧情'],
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
