import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

void main() {
  // Typical streaming chunk JSON shape
  Map<String, dynamic> buildChunkJson({
    String id = 'chatcmpl-abc123',
    String? role,
    String? content,
    String? finishReason,
  }) {
    return {
      'id': id,
      'object': 'chat.completion.chunk',
      'choices': [
        {
          'index': 0,
          'delta': {'role': ?role, 'content': ?content},
          'finish_reason': finishReason,
        },
      ],
    };
  }

  group('ChatCompletionDelta — construction', () {
    test('creates with role and content', () {
      final delta = ChatCompletionDelta(role: 'assistant', content: 'Hello');
      expect(delta.role, equals('assistant'));
      expect(delta.content, equals('Hello'));
    });

    test('role is optional (null)', () {
      final delta = ChatCompletionDelta(role: null, content: ' world');
      expect(delta.role, isNull);
    });

    test('content is optional (null)', () {
      final delta = ChatCompletionDelta(role: 'assistant', content: null);
      expect(delta.content, isNull);
    });

    test('both can be null for terminal chunk', () {
      final delta = ChatCompletionDelta(role: null, content: null);
      expect(delta.role, isNull);
      expect(delta.content, isNull);
    });

    test('accepts empty string content', () {
      final delta = ChatCompletionDelta(role: null, content: '');
      expect(delta.content, equals(''));
    });
  });

  group('ChatCompletionDelta — fromJson()', () {
    test('parses role and content', () {
      final json = <String, dynamic>{'role': 'assistant', 'content': 'Hi'};
      final delta = ChatCompletionDelta.fromJson(json);
      expect(delta.role, equals('assistant'));
      expect(delta.content, equals('Hi'));
    });

    test('parses content-only chunk (no role)', () {
      final json = <String, dynamic>{'content': ' there'};
      final delta = ChatCompletionDelta.fromJson(json);
      expect(delta.role, isNull);
      expect(delta.content, equals(' there'));
    });

    test('parses empty delta {}', () {
      final json = <String, dynamic>{};
      final delta = ChatCompletionDelta.fromJson(json);
      expect(delta.role, isNull);
      expect(delta.content, isNull);
    });
  });

  group('ChatCompletionDelta — toJson()', () {
    test('serializes role and content when both present', () {
      final delta = ChatCompletionDelta(role: 'assistant', content: 'Hello');
      final json = delta.toJson();
      expect(json['role'], equals('assistant'));
      expect(json['content'], equals('Hello'));
    });

    test('omits role from JSON when null', () {
      final delta = ChatCompletionDelta(role: null, content: ' next');
      final json = delta.toJson();
      expect(json.containsKey('role'), isFalse);
      expect(json['content'], equals(' next'));
    });

    test('omits content from JSON when null', () {
      final delta = ChatCompletionDelta(role: 'assistant', content: null);
      final json = delta.toJson();
      expect(json['role'], equals('assistant'));
      expect(json.containsKey('content'), isFalse);
    });

    test('empty map when both null', () {
      final delta = ChatCompletionDelta(role: null, content: null);
      final json = delta.toJson();
      expect(json.containsKey('role'), isFalse);
      expect(json.containsKey('content'), isFalse);
    });
  });

  group('ChatCompletionChunkChoice — construction', () {
    test('creates with delta and null finishReason', () {
      final delta = ChatCompletionDelta(role: 'assistant', content: 'Hi');
      final choice = ChatCompletionChunkChoice(
        delta: delta,
        finishReason: null,
      );
      expect(choice.delta.content, equals('Hi'));
      expect(choice.finishReason, isNull);
    });

    test('creates with finishReason = stop', () {
      final delta = ChatCompletionDelta(role: null, content: null);
      final choice = ChatCompletionChunkChoice(
        delta: delta,
        finishReason: 'stop',
      );
      expect(choice.finishReason, equals('stop'));
    });
  });

  group('ChatCompletionChunkChoice — fromJson()', () {
    test('parses delta and null finish_reason', () {
      final json = <String, dynamic>{
        'index': 0,
        'delta': {'role': 'assistant', 'content': 'Hello'},
        'finish_reason': null,
      };
      final choice = ChatCompletionChunkChoice.fromJson(json);
      expect(choice.delta.role, equals('assistant'));
      expect(choice.delta.content, equals('Hello'));
      expect(choice.finishReason, isNull);
    });

    test('parses finish_reason = stop', () {
      final json = <String, dynamic>{
        'index': 0,
        'delta': <String, dynamic>{},
        'finish_reason': 'stop',
      };
      final choice = ChatCompletionChunkChoice.fromJson(json);
      expect(choice.finishReason, equals('stop'));
    });
  });

  group('ChatCompletionChunk — construction', () {
    test('creates with id and choices', () {
      final delta = ChatCompletionDelta(role: 'assistant', content: 'Hi');
      final choice = ChatCompletionChunkChoice(
        delta: delta,
        finishReason: null,
      );
      final chunk = ChatCompletionChunk(id: 'chatcmpl-xyz', choices: [choice]);
      expect(chunk.id, equals('chatcmpl-xyz'));
      expect(chunk.choices.length, equals(1));
    });
  });

  group('ChatCompletionChunk — fromJson()', () {
    test('parses first streaming chunk with role', () {
      final json = buildChunkJson(role: 'assistant', content: 'Hello');
      final chunk = ChatCompletionChunk.fromJson(json);
      expect(chunk.id, equals('chatcmpl-abc123'));
      expect(chunk.choices.length, equals(1));
      expect(chunk.choices[0].delta.role, equals('assistant'));
      expect(chunk.choices[0].delta.content, equals('Hello'));
      expect(chunk.choices[0].finishReason, isNull);
    });

    test('parses mid-stream chunk without role', () {
      final json = buildChunkJson(content: ' world');
      final chunk = ChatCompletionChunk.fromJson(json);
      expect(chunk.choices[0].delta.role, isNull);
      expect(chunk.choices[0].delta.content, equals(' world'));
      expect(chunk.choices[0].finishReason, isNull);
    });

    test('parses terminal chunk with finish_reason = stop', () {
      final json = buildChunkJson(finishReason: 'stop');
      final chunk = ChatCompletionChunk.fromJson(json);
      expect(chunk.choices[0].delta.content, isNull);
      expect(chunk.choices[0].finishReason, equals('stop'));
    });

    test('parses terminal chunk with finish_reason = length', () {
      final json = buildChunkJson(finishReason: 'length');
      final chunk = ChatCompletionChunk.fromJson(json);
      expect(chunk.choices[0].finishReason, equals('length'));
    });

    test('parses chunk with different id', () {
      final json = buildChunkJson(id: 'chatcmpl-zzz', content: 'test');
      final chunk = ChatCompletionChunk.fromJson(json);
      expect(chunk.id, equals('chatcmpl-zzz'));
    });
  });

  group('ChatCompletionChunk — toJson()', () {
    test('serializes id and choices', () {
      final json = buildChunkJson(role: 'assistant', content: 'Hi');
      final chunk = ChatCompletionChunk.fromJson(json);
      final output = chunk.toJson();
      expect(output['id'], equals('chatcmpl-abc123'));
      expect(output['choices'], isA<List>());
    });

    test('choices contain serialized delta', () {
      final json = buildChunkJson(content: 'token');
      final chunk = ChatCompletionChunk.fromJson(json);
      final output = chunk.toJson();
      final choices = output['choices'] as List;
      final choice = choices[0] as Map<String, dynamic>;
      expect(choice['delta'], isA<Map<String, dynamic>>());
      expect((choice['delta'] as Map)['content'], equals('token'));
    });
  });

  group('ChatCompletionChunk — round-trip', () {
    test('first chunk round-trips', () {
      final json = buildChunkJson(role: 'assistant', content: 'Hello');
      final original = ChatCompletionChunk.fromJson(json);
      final restored = ChatCompletionChunk.fromJson(original.toJson());
      expect(restored.id, equals(original.id));
      expect(
        restored.choices[0].delta.role,
        equals(original.choices[0].delta.role),
      );
      expect(
        restored.choices[0].delta.content,
        equals(original.choices[0].delta.content),
      );
    });

    test('terminal chunk round-trips', () {
      final json = buildChunkJson(finishReason: 'stop');
      final original = ChatCompletionChunk.fromJson(json);
      final restored = ChatCompletionChunk.fromJson(original.toJson());
      expect(restored.choices[0].finishReason, equals('stop'));
    });
  });
}
