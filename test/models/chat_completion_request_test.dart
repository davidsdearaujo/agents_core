import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

void main() {
  final userMsg = ChatMessage(role: ChatMessageRole.user, content: 'Hello');
  final systemMsg = ChatMessage(role: ChatMessageRole.system, content: 'You are helpful.');

  final sampleTool = ToolDefinition(
    name: 'get_weather',
    description: 'Get weather',
    parameters: <String, dynamic>{
      'type': 'object',
      'properties': {'city': <String, dynamic>{'type': 'string'}},
    },
  );

  group('ChatCompletionRequest — construction', () {
    test('creates with required fields only', () {
      final req = ChatCompletionRequest(
        model: 'lmstudio-community/mistral',
        messages: [userMsg],
      );
      expect(req.model, equals('lmstudio-community/mistral'));
      expect(req.messages, equals([userMsg]));
      expect(req.temperature, isNull);
      expect(req.maxTokens, isNull);
      expect(req.tools, isNull);
      expect(req.toolChoice, isNull);
      expect(req.stream, isNull);
    });

    test('creates with all optional fields', () {
      final req = ChatCompletionRequest(
        model: 'test-model',
        messages: [systemMsg, userMsg],
        temperature: 0.7,
        maxTokens: 512,
        tools: [sampleTool],
        toolChoice: 'auto',
        stream: false,
      );
      expect(req.model, equals('test-model'));
      expect(req.messages.length, equals(2));
      expect(req.temperature, equals(0.7));
      expect(req.maxTokens, equals(512));
      expect(req.tools, hasLength(1));
      expect(req.toolChoice, equals('auto'));
      expect(req.stream, isFalse);
    });

    test('accepts empty messages list', () {
      final req = ChatCompletionRequest(model: 'model', messages: []);
      expect(req.messages, isEmpty);
    });

    test('accepts temperature of 0.0', () {
      final req = ChatCompletionRequest(
        model: 'model',
        messages: [userMsg],
        temperature: 0.0,
      );
      expect(req.temperature, equals(0.0));
    });

    test('accepts temperature of 2.0 (max for OpenAI)', () {
      final req = ChatCompletionRequest(
        model: 'model',
        messages: [userMsg],
        temperature: 2.0,
      );
      expect(req.temperature, equals(2.0));
    });

    test('accepts toolChoice as Map for specific tool', () {
      final req = ChatCompletionRequest(
        model: 'model',
        messages: [userMsg],
        toolChoice: {'type': 'function', 'function': {'name': 'get_weather'}},
      );
      expect(req.toolChoice, isA<Map>());
    });

    test('stream defaults to null when not specified', () {
      final req = ChatCompletionRequest(model: 'model', messages: [userMsg]);
      expect(req.stream, isNull);
    });
  });

  group('ChatCompletionRequest — toJson()', () {
    test('serializes required fields', () {
      final req = ChatCompletionRequest(
        model: 'test-model',
        messages: [userMsg],
      );
      final json = req.toJson();
      expect(json['model'], equals('test-model'));
      expect(json['messages'], isA<List>());
      expect((json['messages'] as List).length, equals(1));
    });

    test('messages are serialized as list of maps', () {
      final req = ChatCompletionRequest(
        model: 'model',
        messages: [systemMsg, userMsg],
      );
      final json = req.toJson();
      final messages = json['messages'] as List;
      expect(messages[0], isA<Map<String, dynamic>>());
      expect(messages[0]['role'], equals('system'));
      expect(messages[1]['role'], equals('user'));
    });

    test('optional fields omitted when null', () {
      final req = ChatCompletionRequest(model: 'model', messages: [userMsg]);
      final json = req.toJson();
      expect(json.containsKey('temperature'), isFalse);
      expect(json.containsKey('max_tokens'), isFalse);
      expect(json.containsKey('tools'), isFalse);
      expect(json.containsKey('tool_choice'), isFalse);
      expect(json.containsKey('stream'), isFalse);
    });

    test('temperature serialized as double', () {
      final req = ChatCompletionRequest(
        model: 'model',
        messages: [userMsg],
        temperature: 0.9,
      );
      final json = req.toJson();
      expect(json['temperature'], equals(0.9));
    });

    test('maxTokens serialized as max_tokens (snake_case)', () {
      final req = ChatCompletionRequest(
        model: 'model',
        messages: [userMsg],
        maxTokens: 256,
      );
      final json = req.toJson();
      expect(json['max_tokens'], equals(256));
      expect(json.containsKey('maxTokens'), isFalse);
    });

    test('tools serialized as list of tool maps', () {
      final req = ChatCompletionRequest(
        model: 'model',
        messages: [userMsg],
        tools: [sampleTool],
      );
      final json = req.toJson();
      expect(json['tools'], isA<List>());
      final tools = json['tools'] as List;
      expect(tools.length, equals(1));
      expect(tools[0], isA<Map<String, dynamic>>());
    });

    test('toolChoice serialized as tool_choice (snake_case)', () {
      final req = ChatCompletionRequest(
        model: 'model',
        messages: [userMsg],
        toolChoice: 'auto',
      );
      final json = req.toJson();
      expect(json['tool_choice'], equals('auto'));
      expect(json.containsKey('toolChoice'), isFalse);
    });

    test('stream serialized when true', () {
      final req = ChatCompletionRequest(
        model: 'model',
        messages: [userMsg],
        stream: true,
      );
      final json = req.toJson();
      expect(json['stream'], isTrue);
    });

    test('stream serialized when false', () {
      final req = ChatCompletionRequest(
        model: 'model',
        messages: [userMsg],
        stream: false,
      );
      final json = req.toJson();
      expect(json['stream'], isFalse);
    });

    test('returns Map<String, dynamic>', () {
      final req = ChatCompletionRequest(model: 'model', messages: [userMsg]);
      expect(req.toJson(), isA<Map<String, dynamic>>());
    });
  });

  group('ChatCompletionRequest — fromJson()', () {
    test('parses required fields', () {
      final json = <String, dynamic>{
        'model': 'my-model',
        'messages': [
          {'role': 'user', 'content': 'Hi'},
        ],
      };
      final req = ChatCompletionRequest.fromJson(json);
      expect(req.model, equals('my-model'));
      expect(req.messages.length, equals(1));
      expect(req.messages[0].role, equals(ChatMessageRole.user));
      expect(req.messages[0].content, equals('Hi'));
    });

    test('parses temperature', () {
      final json = <String, dynamic>{
        'model': 'model',
        'messages': [],
        'temperature': 0.5,
      };
      final req = ChatCompletionRequest.fromJson(json);
      expect(req.temperature, equals(0.5));
    });

    test('parses max_tokens as maxTokens', () {
      final json = <String, dynamic>{
        'model': 'model',
        'messages': [],
        'max_tokens': 100,
      };
      final req = ChatCompletionRequest.fromJson(json);
      expect(req.maxTokens, equals(100));
    });

    test('optional fields are null when absent', () {
      final json = <String, dynamic>{'model': 'model', 'messages': []};
      final req = ChatCompletionRequest.fromJson(json);
      expect(req.temperature, isNull);
      expect(req.maxTokens, isNull);
      expect(req.tools, isNull);
      expect(req.toolChoice, isNull);
      expect(req.stream, isNull);
    });
  });

  group('ChatCompletionRequest — round-trip', () {
    test('round-trips required fields', () {
      final original = ChatCompletionRequest(
        model: 'test-model',
        messages: [systemMsg, userMsg],
      );
      final restored = ChatCompletionRequest.fromJson(original.toJson());
      expect(restored.model, equals(original.model));
      expect(restored.messages.length, equals(original.messages.length));
    });

    test('round-trips all fields', () {
      final original = ChatCompletionRequest(
        model: 'full-model',
        messages: [userMsg],
        temperature: 0.3,
        maxTokens: 64,
        tools: [sampleTool],
        toolChoice: 'none',
        stream: true,
      );
      final restored = ChatCompletionRequest.fromJson(original.toJson());
      expect(restored.model, equals(original.model));
      expect(restored.temperature, equals(original.temperature));
      expect(restored.maxTokens, equals(original.maxTokens));
      expect(restored.toolChoice, equals(original.toolChoice));
      expect(restored.stream, equals(original.stream));
    });
  });
}
