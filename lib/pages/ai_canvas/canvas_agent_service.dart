import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xinghe_new/services/api/api_repository.dart';
import 'package:xinghe_new/services/api/secure_storage_manager.dart';

/// Agent 设计方案中的单个元素
class DesignElement {
  final String type; // 'image' | 'video' | 'text'
  final String prompt; // 生成提示词或文本内容
  final double x; // 画布X位置
  final double y; // 画布Y位置
  final double width;
  final double height;
  final String? ratio; // 图片/视频比例
  final String? duration; // 视频时长
  final Map<String, dynamic> extra; // 额外参数

  DesignElement({
    required this.type,
    required this.prompt,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.ratio,
    this.duration,
    this.extra = const {},
  });

  factory DesignElement.fromJson(Map<String, dynamic> json) {
    return DesignElement(
      type: json['type'] as String? ?? 'image',
      prompt: json['prompt'] as String? ?? '',
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      width: (json['width'] as num?)?.toDouble() ?? 300,
      height: (json['height'] as num?)?.toDouble() ?? 300,
      ratio: json['ratio'] as String?,
      duration: json['duration'] as String?,
      extra: Map<String, dynamic>.from(json['extra'] as Map? ?? {}),
    );
  }
}

/// Agent 设计方案
class DesignPlan {
  final String summary; // 方案描述
  final List<DesignElement> elements; // 设计元素列表
  final String style; // 整体风格描述

  DesignPlan({required this.summary, required this.elements, this.style = ''});

  factory DesignPlan.fromJson(Map<String, dynamic> json) {
    final elementsJson = json['elements'] as List? ?? [];
    return DesignPlan(
      summary: json['summary'] as String? ?? '',
      elements: elementsJson
          .map((e) => DesignElement.fromJson(e as Map<String, dynamic>))
          .toList(),
      style: json['style'] as String? ?? '',
    );
  }
}

/// 画布助手动作元信息
class AgentActionMeta {
  final bool needConfirm;
  final double? confidence;
  final String? reason;

  const AgentActionMeta({
    this.needConfirm = false,
    this.confidence,
    this.reason,
  });

  factory AgentActionMeta.fromJson(Map<String, dynamic> json) {
    final confidence = json['confidence'];
    return AgentActionMeta(
      needConfirm: json['need_confirm'] as bool? ?? false,
      confidence: confidence is num ? confidence.toDouble() : null,
      reason: json['reason'] as String?,
    );
  }
}

/// 单个画布动作
class AgentAction {
  final String type;
  final String target;
  final String? nodeId;
  final Map<String, dynamic> payload;
  final Map<String, dynamic> position;
  final Map<String, dynamic> options;

  const AgentAction({
    required this.type,
    this.target = 'canvas',
    this.nodeId,
    this.payload = const {},
    this.position = const {},
    this.options = const {},
  });

  factory AgentAction.fromJson(Map<String, dynamic> json) {
    return AgentAction(
      type: json['type'] as String? ?? 'suggestion',
      target: json['target'] as String? ?? 'canvas',
      nodeId: json['nodeId'] as String?,
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
      position: Map<String, dynamic>.from(json['position'] as Map? ?? {}),
      options: Map<String, dynamic>.from(json['options'] as Map? ?? {}),
    );
  }

  bool get isDangerous => const {
    'delete_node',
    'clear_canvas',
    'replace_node_content',
  }.contains(type);

  bool get isExecutable => const {
    'generate_image',
    'generate_video',
    'create_text_node',
    'create_note_node',
    'update_node',
    'move_node',
    'delete_node',
  }.contains(type);
}

/// 画布助手的结构化返回
class AgentActionBundle {
  final String reply;
  final String intent;
  final List<AgentAction> actions;
  final AgentActionMeta meta;

  const AgentActionBundle({
    required this.reply,
    required this.intent,
    this.actions = const [],
    this.meta = const AgentActionMeta(),
  });

  factory AgentActionBundle.fromJson(Map<String, dynamic> json) {
    final actionsJson = json['actions'] as List? ?? const [];
    return AgentActionBundle(
      reply: (json['reply'] as String?)?.trim().isNotEmpty == true
          ? (json['reply'] as String).trim()
          : ((json['summary'] as String?)?.trim().isNotEmpty == true
                ? (json['summary'] as String).trim()
                : '我已经整理好了下一步操作。'),
      intent: json['intent'] as String? ?? 'chat',
      actions: actionsJson
          .map((e) => AgentAction.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      meta: AgentActionMeta.fromJson(
        Map<String, dynamic>.from(json['meta'] as Map? ?? {}),
      ),
    );
  }

  factory AgentActionBundle.fromDesignPlan(
    DesignPlan plan, {
    String? imageProvider,
    String? imageModel,
    String? videoProvider,
    String? videoModel,
  }) {
    final actions = plan.elements.map((element) {
      switch (element.type) {
        case 'video':
          return AgentAction(
            type: 'generate_video',
            payload: {
              'prompt': element.prompt,
              if (videoProvider != null) 'provider': videoProvider,
              if (videoModel != null) 'model': videoModel,
              if (element.ratio != null) 'ratio': element.ratio,
              if (element.duration != null) 'duration': element.duration,
            },
            position: {'x': element.x, 'y': element.y},
            options: {'width': element.width, 'height': element.height},
          );
        case 'text':
          return AgentAction(
            type: 'create_text_node',
            payload: {'text': element.prompt},
            position: {'x': element.x, 'y': element.y},
            options: {'width': element.width, 'height': element.height},
          );
        default:
          return AgentAction(
            type: 'generate_image',
            payload: {
              'prompt': element.prompt,
              if (imageProvider != null) 'provider': imageProvider,
              if (imageModel != null) 'model': imageModel,
              if (element.ratio != null) 'ratio': element.ratio,
            },
            position: {'x': element.x, 'y': element.y},
            options: {'width': element.width, 'height': element.height},
          );
      }
    }).toList();

    return AgentActionBundle(
      reply: plan.summary.isNotEmpty ? plan.summary : '我整理了一套画布方案。',
      intent: 'mixed',
      actions: actions,
      meta: AgentActionMeta(needConfirm: actions.length > 4, confidence: 0.8),
    );
  }

  bool get hasActions => actions.isNotEmpty;

  bool get hasExecutableActions => actions.any((action) => action.isExecutable);

  bool get requiresConfirmation =>
      meta.needConfirm ||
      actions.any((action) => action.isDangerous) ||
      actions.length > 4;
}

/// 聊天消息
class AgentMessage {
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  final DesignPlan? plan; // 如果是设计方案回复，附带方案数据
  final AgentActionBundle? actionBundle; // 如果有结构化动作，附带动作数据
  final bool actionApplied; // 动作是否已执行
  final String? actionStatus; // 动作执行状态
  final DateTime timestamp;

  AgentMessage({
    required this.role,
    required this.content,
    this.plan,
    this.actionBundle,
    this.actionApplied = false,
    this.actionStatus,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  AgentMessage copyWith({
    String? role,
    String? content,
    DesignPlan? plan,
    AgentActionBundle? actionBundle,
    bool? actionApplied,
    String? actionStatus,
    DateTime? timestamp,
  }) {
    return AgentMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      plan: plan ?? this.plan,
      actionBundle: actionBundle ?? this.actionBundle,
      actionApplied: actionApplied ?? this.actionApplied,
      actionStatus: actionStatus ?? this.actionStatus,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

class _ParsedAgentResponse {
  final DesignPlan? plan;
  final AgentActionBundle? actionBundle;

  const _ParsedAgentResponse({this.plan, this.actionBundle});
}

/// 画布 Agent 服务 — 通过 LLM 分析用户意图并生成设计方案
class CanvasAgentService {
  final ApiRepository _apiRepository = ApiRepository();
  final SecureStorageManager _storage = SecureStorageManager();

  /// 系统提示词 — 定义 Agent 的角色和输出格式
  static const String _systemPrompt = '''你是一个嵌入在创意画布工具中的 AI 设计助手。你的目标有两个：
1. 像正常助手一样和用户自然聊天、讨论创意、分析画面。
2. 当用户明确要求执行画布操作时，返回结构化动作，让系统自动在画布上执行。

你应该优先理解用户意图，而不是生硬地只返回指令。无论是否执行动作，都要给用户一段自然中文回复。

请优先返回一个 JSON 对象，格式如下：
{
  "reply": "给用户看的自然中文回复",
  "intent": "chat | generate_image | generate_video | edit_canvas | mixed",
  "actions": [
    {
      "type": "generate_image | generate_video | create_text_node | create_note_node | update_node | move_node | delete_node | layout_suggestion | suggestion",
      "target": "canvas | node",
      "nodeId": "可选，修改或删除已有节点时填写",
      "payload": {},
      "position": {"x": 0, "y": 0},
      "options": {}
    }
  ],
  "meta": {
    "need_confirm": false,
    "confidence": 0.0,
    "reason": "可选，说明为什么这样做"
  }
}

动作规则：
- 如果只是聊天、分析、建议、讨论，不需要执行动作，actions 必须返回 []。
- generate_image：payload 至少包含 prompt，可选 provider/model/ratio/count/referenceImages。
- generate_video：payload 至少包含 prompt，可选 provider/model/ratio/duration/referenceImages。
- create_text_node：payload 至少包含 text，可选 fontSize/color/bold/italic/underline。
- create_note_node：用于备注、便签、说明。
- update_node：必须提供 nodeId；payload 可包含 text/prompt/provider/model/ratio/duration/referenceImages/changes 等。
- move_node：必须提供 nodeId；position 必须包含 x/y。
- delete_node：必须提供 nodeId，并且 meta.need_confirm 必须为 true。
- layout_suggestion / suggestion：只作为建议，不自动执行。

提示词与内容规则：
- 图片和视频的 prompt 必须写成高质量、详细、适合 AI 生成的中文提示词。
- 文本节点的 text 必须是最终要显示在画布上的中文内容。
- 如果用户没有指定 provider/model，优先使用当前系统提供的配置，不要随意编造不存在的模型。
- 如果用户想修改或删除现有元素，优先根据提供的 nodeId 和画布上下文来操作。
- 如果无法确定应该操作哪个节点，就不要伪造 nodeId，改为给出建议，并把 need_confirm 设为 true。

容错规则：
- 如果你无法可靠地生成结构化动作，也至少返回自然中文回复。
- 不要输出 markdown，不要输出代码块，不要在 JSON 外再包任何额外说明。
- 如果只是普通闲聊，reply 正常聊天即可，actions 返回 []。''';

  /// 发送消息给 Agent，获取设计方案
  Future<AgentMessage> chat(
    List<AgentMessage> history,
    String userMessage, {
    String? imageProvider,
    String? imageModel,
    String? videoProvider,
    String? videoModel,
    String? canvasContext,
  }) async {
    try {
      // 获取 LLM 服务商配置
      final prefs = await SharedPreferences.getInstance();
      final provider = prefs.getString('llm_provider') ?? 'openai';

      // 获取模型名
      final model = await _storage.getModel(
        provider: provider,
        modelType: 'llm',
      );

      // 构建消息历史
      final messages = <Map<String, String>>[
        {'role': 'system', 'content': _systemPrompt},
      ];

      // 添加历史消息（最近10条）
      final recentHistory = history.length > 10
          ? history.sublist(history.length - 10)
          : history;
      for (final msg in recentHistory) {
        if (msg.role == 'user' || msg.role == 'assistant') {
          messages.add({'role': msg.role, 'content': msg.content});
        }
      }

      // 添加当前用户消息，附带可用模型信息
      String enhancedMessage = userMessage;
      final contextBlocks = <String>[];
      if (imageProvider != null ||
          imageModel != null ||
          videoProvider != null ||
          videoModel != null) {
        contextBlocks.add(
          '[当前系统配置]\n'
          '图片服务商: ${imageProvider ?? "默认"}\n'
          '图片模型: ${imageModel ?? "默认"}\n'
          '视频服务商: ${videoProvider ?? "默认"}\n'
          '视频模型: ${videoModel ?? "默认"}',
        );
      }
      if (canvasContext != null && canvasContext.isNotEmpty) {
        contextBlocks.add('[当前画布上下文]\n$canvasContext');
      }
      if (contextBlocks.isNotEmpty) {
        enhancedMessage += '\n\n${contextBlocks.join('\n\n')}';
      }
      messages.add({'role': 'user', 'content': enhancedMessage});

      debugPrint('🤖 [CanvasAgent] 发送请求到 $provider, 模型: $model');
      debugPrint('   消息数: ${messages.length}');

      // 调用 LLM API
      final response = await _apiRepository.generateTextWithMessages(
        provider: provider,
        messages: messages,
        model: model,
        parameters: {'temperature': 0.7, 'max_tokens': 4000},
      );

      if (!response.isSuccess || response.data == null) {
        debugPrint('❌ [CanvasAgent] API调用失败: ${response.error}');
        return AgentMessage(
          role: 'assistant',
          content: '抱歉，设计助手暂时无法响应：${response.error ?? "未知错误"}',
        );
      }

      final rawText = response.data!.text.trim();
      final text = _normalizeResponseText(rawText);
      debugPrint('🤖 [CanvasAgent] 收到回复 (${text.length} 字符)');

      // 优先解析结构化响应；失败则退回普通聊天
      final parsed = _tryParseStructuredResponse(
        text,
        imageProvider: imageProvider,
        imageModel: imageModel,
        videoProvider: videoProvider,
        videoModel: videoModel,
      );

      if (parsed != null) {
        final bundle = parsed.actionBundle;
        final plan = parsed.plan;
        return AgentMessage(
          role: 'assistant',
          content: bundle?.reply.isNotEmpty == true
              ? bundle!.reply
              : plan?.summary.isNotEmpty == true
              ? plan!.summary
              : text,
          plan: plan,
          actionBundle: bundle,
        );
      }

      // 不是设计方案，作为普通文本回复
      return AgentMessage(role: 'assistant', content: text);
    } catch (e) {
      debugPrint('💥 [CanvasAgent] 异常: $e');
      return AgentMessage(role: 'assistant', content: '发生错误：$e');
    }
  }

  String _normalizeResponseText(String text) {
    final repaired = _repairMojibake(text);
    return repaired.trim();
  }

  String _repairMojibake(String text) {
    try {
      final repaired = utf8.decode(latin1.encode(text));
      if (repaired != text && _containsCjk(repaired)) {
        return repaired;
      }
    } catch (_) {}
    return text;
  }

  bool _containsCjk(String text) {
    return RegExp(r'[\u4E00-\u9FFF]').hasMatch(text);
  }

  /// 尝试将文本解析为结构化响应；失败时返回 null，前端退化成普通聊天
  _ParsedAgentResponse? _tryParseStructuredResponse(
    String text, {
    String? imageProvider,
    String? imageModel,
    String? videoProvider,
    String? videoModel,
  }) {
    try {
      String cleaned = text;
      if (cleaned.contains('```')) {
        final jsonMatch = RegExp(
          r'```(?:json)?\s*([\s\S]*?)```',
        ).firstMatch(cleaned);
        if (jsonMatch != null) {
          cleaned = jsonMatch.group(1)!.trim();
        }
      }

      // 尝试找到 JSON 对象
      final startIndex = cleaned.indexOf('{');
      final endIndex = cleaned.lastIndexOf('}');
      if (startIndex >= 0 && endIndex > startIndex) {
        cleaned = cleaned.substring(startIndex, endIndex + 1);
      }

      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      if (json.containsKey('reply') || json.containsKey('actions')) {
        final bundle = AgentActionBundle.fromJson(json);
        return _ParsedAgentResponse(actionBundle: bundle);
      }
      if (json.containsKey('elements')) {
        final plan = DesignPlan.fromJson(json);
        final bundle = AgentActionBundle.fromDesignPlan(
          plan,
          imageProvider: imageProvider,
          imageModel: imageModel,
          videoProvider: videoProvider,
          videoModel: videoModel,
        );
        return _ParsedAgentResponse(plan: plan, actionBundle: bundle);
      }
    } catch (e) {
      debugPrint('⚠️ [CanvasAgent] JSON解析失败: $e');
    }
    return null;
  }
}
