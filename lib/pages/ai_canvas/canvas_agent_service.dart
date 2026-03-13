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

/// 聊天消息
class AgentMessage {
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  final DesignPlan? plan; // 如果是设计方案回复，附带方案数据
  final DateTime timestamp;

  AgentMessage({
    required this.role,
    required this.content,
    this.plan,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// 画布 Agent 服务 — 通过 LLM 分析用户意图并生成设计方案
class CanvasAgentService {
  final ApiRepository _apiRepository = ApiRepository();
  final SecureStorageManager _storage = SecureStorageManager();

  /// 系统提示词 — 定义 Agent 的角色和输出格式
  static const String _systemPrompt = '''你是一个专业的AI设计助手。用户会告诉你他想要设计什么，你需要：

1. 分析用户的设计意图
2. 规划设计布局，生成一个包含多个元素的设计方案
3. 为每个图片/视频元素编写详细的AI生成提示词（英文，适用于AI图像生成模型）
4. 合理安排元素在画布上的位置和大小

你必须以严格的JSON格式回复，格式如下：
{
  "summary": "方案描述（中文）",
  "style": "整体风格描述（中文）",
  "elements": [
    {
      "type": "image",
      "prompt": "A professional product photo of a running shoe, white background, studio lighting, 4K quality, hyper-realistic",
      "x": 100,
      "y": 100,
      "width": 400,
      "height": 400,
      "ratio": "1:1"
    },
    {
      "type": "text",
      "prompt": "产品标题文字内容",
      "x": 550,
      "y": 100,
      "width": 300,
      "height": 60
    },
    {
      "type": "video",
      "prompt": "A cinematic slow-motion video of a runner in action, wearing the shoes, dynamic lighting",
      "x": 100,
      "y": 550,
      "width": 640,
      "height": 360,
      "ratio": "16:9",
      "duration": "5s"
    }
  ]
}

规则：
- 图片和视频的prompt必须是英文，高质量、详细的AI生成提示词
- 文本节点的prompt是要显示的中文文字内容
- 坐标系：左上角为(0,0)，x轴向右，y轴向下
- 合理安排元素位置，避免重叠，保持美观的间距(至少30px间隔)
- 图片建议尺寸：300-600px，视频建议尺寸：480-800px
- 支持的比例：1:1, 16:9, 9:16, 4:3, 3:4
- 视频时长：5s, 8s, 10s, 15s
- 每个方案最多生成8个元素
- 只回复JSON，不要添加任何其他文字、代码块标记或解释''';

  /// 发送消息给 Agent，获取设计方案
  Future<AgentMessage> chat(
    List<AgentMessage> history,
    String userMessage, {
    String? imageModel,
    String? videoModel,
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
      if (imageModel != null || videoModel != null) {
        enhancedMessage +=
            '\n\n[可用模型信息] 图片模型: ${imageModel ?? "默认"}, 视频模型: ${videoModel ?? "默认"}';
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

      final text = response.data!.text.trim();
      debugPrint('🤖 [CanvasAgent] 收到回复 (${text.length} 字符)');

      // 尝试解析为设计方案
      final plan = _tryParsePlan(text);

      if (plan != null) {
        return AgentMessage(
          role: 'assistant',
          content: plan.summary,
          plan: plan,
        );
      }

      // 不是设计方案，作为普通文本回复
      return AgentMessage(role: 'assistant', content: text);
    } catch (e) {
      debugPrint('💥 [CanvasAgent] 异常: $e');
      return AgentMessage(role: 'assistant', content: '发生错误：$e');
    }
  }

  /// 尝试将文本解析为设计方案
  DesignPlan? _tryParsePlan(String text) {
    try {
      // 去掉可能的 ```json 代码块标记
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
      if (json.containsKey('elements')) {
        return DesignPlan.fromJson(json);
      }
    } catch (e) {
      debugPrint('⚠️ [CanvasAgent] JSON解析失败: $e');
    }
    return null;
  }
}
