import 'package:test/test.dart';
import '../lib/services/api/providers/openai_service.dart';
import '../lib/services/api/base/api_config.dart';

/// OpenAI 对话格式生图 - 单元测试
void main() {
  group('ChatMessage 数据模型测试', () {
    test('创建简单文本消息', () {
      final message = ChatMessage(
        role: 'user',
        content: [ChatMessageContent.text(text: '测试消息')],
      );

      expect(message.role, equals('user'));
      expect(message.content, isA<List<ChatMessageContent>>());
    });

    test('创建图片消息', () {
      final message = ChatMessage(
        role: 'user',
        content: [
          ChatMessageContent.image(
            imageUrl: 'https://example.com/image.jpg',
            detail: 'high',
          ),
        ],
      );

      expect(message.role, equals('user'));
      expect(message.content, isA<List<ChatMessageContent>>());
      
      final content = (message.content as List<ChatMessageContent>).first;
      expect(content.type, equals('image_url'));
      expect(content.imageUrl?.url, equals('https://example.com/image.jpg'));
      expect(content.imageUrl?.detail, equals('high'));
    });

    test('创建混合内容消息', () {
      final message = ChatMessage(
        role: 'user',
        content: [
          ChatMessageContent.image(
            imageUrl: 'https://example.com/image.jpg',
          ),
          ChatMessageContent.text(text: '描述这张图片'),
        ],
      );

      expect(message.content, isA<List<ChatMessageContent>>());
      expect((message.content as List).length, equals(2));
    });

    test('JSON 序列化 - 文本消息', () {
      final message = ChatMessage(
        role: 'user',
        content: [ChatMessageContent.text(text: '测试')],
      );

      final json = message.toJson();
      expect(json['role'], equals('user'));
      expect(json['content'], isA<List>());
      expect(json['content'][0]['type'], equals('text'));
      expect(json['content'][0]['text'], equals('测试'));
    });

    test('JSON 序列化 - 图片消息', () {
      final message = ChatMessage(
        role: 'user',
        content: [
          ChatMessageContent.image(
            imageUrl: 'https://example.com/image.jpg',
            detail: 'low',
          ),
        ],
      );

      final json = message.toJson();
      expect(json['content'][0]['type'], equals('image_url'));
      expect(json['content'][0]['image_url']['url'], 
          equals('https://example.com/image.jpg'));
      expect(json['content'][0]['image_url']['detail'], equals('low'));
    });

    test('JSON 反序列化 - 文本消息', () {
      final json = {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': '生成的图片URL'}
        ],
      };

      final message = ChatMessage.fromJson(json);
      expect(message.role, equals('assistant'));
      expect(message.content, isA<List<ChatMessageContent>>());
      
      final content = (message.content as List<ChatMessageContent>).first;
      expect(content.type, equals('text'));
      expect(content.text, equals('生成的图片URL'));
    });

    test('JSON 反序列化 - 图片消息', () {
      final json = {
        'role': 'user',
        'content': [
          {
            'type': 'image_url',
            'image_url': {
              'url': 'https://example.com/image.jpg',
              'detail': 'high'
            }
          }
        ],
      };

      final message = ChatMessage.fromJson(json);
      expect(message.role, equals('user'));
      
      final content = (message.content as List<ChatMessageContent>).first;
      expect(content.type, equals('image_url'));
      expect(content.imageUrl?.url, equals('https://example.com/image.jpg'));
    });
  });

  group('ChatImageResponse 数据模型测试', () {
    test('解析完整响应', () {
      final json = {
        'id': 'chatcmpl-123',
        'object': 'chat.completion',
        'created': 1677652288,
        'model': 'gpt-4o',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': 'https://example.com/generated-image.jpg',
            },
            'finish_reason': 'stop',
          }
        ],
        'usage': {
          'prompt_tokens': 100,
          'completion_tokens': 50,
          'total_tokens': 150,
        },
      };

      final response = ChatImageResponse.fromJson(json);
      
      expect(response.id, equals('chatcmpl-123'));
      expect(response.object, equals('chat.completion'));
      expect(response.created, equals(1677652288));
      expect(response.model, equals('gpt-4o'));
      expect(response.choices.length, equals(1));
      expect(response.usage, isNotNull);
      expect(response.usage!.totalTokens, equals(150));
    });

    test('提取图片 URL', () {
      final json = {
        'id': 'test-id',
        'object': 'chat.completion',
        'created': 1234567890,
        'model': 'gpt-4o',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': 'https://example.com/image1.jpg',
            },
            'finish_reason': 'stop',
          },
          {
            'index': 1,
            'message': {
              'role': 'assistant',
              'content': 'https://example.com/image2.jpg',
            },
            'finish_reason': 'stop',
          }
        ],
      };

      final response = ChatImageResponse.fromJson(json);
      
      expect(response.imageUrls.length, equals(2));
      expect(response.imageUrls[0], equals('https://example.com/image1.jpg'));
      expect(response.imageUrls[1], equals('https://example.com/image2.jpg'));
      expect(response.firstImageUrl, equals('https://example.com/image1.jpg'));
    });

    test('从图片内容中提取 URL', () {
      final json = {
        'id': 'test-id',
        'object': 'chat.completion',
        'created': 1234567890,
        'model': 'gpt-4o',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': [
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'https://example.com/generated.jpg'
                  }
                }
              ],
            },
            'finish_reason': 'stop',
          }
        ],
      };

      final response = ChatImageResponse.fromJson(json);
      
      expect(response.imageUrls.length, equals(1));
      expect(response.firstImageUrl, equals('https://example.com/generated.jpg'));
    });
  });

  group('ChatImageUsage 数据模型测试', () {
    test('解析 Token 使用统计', () {
      final json = {
        'prompt_tokens': 150,
        'completion_tokens': 75,
        'total_tokens': 225,
      };

      final usage = ChatImageUsage.fromJson(json);
      
      expect(usage.promptTokens, equals(150));
      expect(usage.completionTokens, equals(75));
      expect(usage.totalTokens, equals(225));
    });
  });

  group('ChatMessageContent 工厂方法测试', () {
    test('创建文本内容', () {
      final content = ChatMessageContent.text(text: '测试文本');
      
      expect(content.type, equals('text'));
      expect(content.text, equals('测试文本'));
      expect(content.imageUrl, isNull);
    });

    test('创建图片内容', () {
      final content = ChatMessageContent.image(
        imageUrl: 'https://example.com/image.jpg',
        detail: 'high',
      );
      
      expect(content.type, equals('image_url'));
      expect(content.text, isNull);
      expect(content.imageUrl, isNotNull);
      expect(content.imageUrl!.url, equals('https://example.com/image.jpg'));
      expect(content.imageUrl!.detail, equals('high'));
    });
  });

  group('OpenAIChatImageHelper 测试', () {
    late OpenAIService service;
    late OpenAIChatImageHelper helper;

    setUp(() {
      final config = ApiConfig(
        provider: 'GeekNow',
        baseUrl: 'https://api.example.com',
        apiKey: 'test-api-key',
        model: 'gpt-4o',
      );
      service = OpenAIService(config);
      helper = OpenAIChatImageHelper(service);
    });

    test('Helper 实例创建', () {
      expect(helper, isNotNull);
      expect(helper.service, equals(service));
    });

    // 注意：以下测试需要实际的 API 连接，在单元测试中可能需要 mock
    // 这里仅作为结构示例
  });

  group('边界情况测试', () {
    test('空消息列表', () {
      final message = ChatMessage(role: 'user', content: []);
      final json = message.toJson();
      
      expect(json['content'], isEmpty);
    });

    test('处理 null detail', () {
      final content = ChatMessageContent.image(
        imageUrl: 'https://example.com/image.jpg',
      );
      
      expect(content.imageUrl!.detail, isNull);
      
      final json = content.toJson();
      expect(json['image_url']['detail'], isNull);
    });

    test('响应中没有 usage 信息', () {
      final json = {
        'id': 'test',
        'object': 'chat.completion',
        'created': 1234567890,
        'model': 'gpt-4o',
        'choices': [],
      };

      final response = ChatImageResponse.fromJson(json);
      expect(response.usage, isNull);
    });

    test('空的 choices 数组', () {
      final json = {
        'id': 'test',
        'object': 'chat.completion',
        'created': 1234567890,
        'model': 'gpt-4o',
        'choices': [],
      };

      final response = ChatImageResponse.fromJson(json);
      expect(response.choices, isEmpty);
      expect(response.imageUrls, isEmpty);
      expect(response.firstImageUrl, isNull);
    });
  });
}
