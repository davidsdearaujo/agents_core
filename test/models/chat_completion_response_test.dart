import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

void main() {
  // Minimal valid JSON response from the OpenAI-compatible API
  Map<String, dynamic> buildResponseJson({
    String id = 'chatcmpl-abc123',
    String role = 'assistant',
    String content = 'Hello! How can I help?',
    String? finishReason = 'stop',
    int promptTokens = 10,
    int completionTokens = 8,
    int totalTokens = 18,
  }) {
    return {
      'id': id,
      'object': 'chat.completion',
      'choices': [
        {
          'index': 0,
          'message': {'role': role, 'content': content},
          'finish_reason': finishReason,
        },
      ],
      'usage': {
        'prompt_tokens': promptTokens,
        'completion_tokens': completionTokens,
        'total_tokens': totalTokens,
      },
    };
  }

  group('CompletionUsage — construction', () {
    test('creates with all fields', () {
      final usage = CompletionUsage(
        promptTokens: 10,
        completionTokens: 5,
        totalTokens: 15,
      );
      expect(usage.promptTokens, equals(10));
      expect(usage.completionTokens, equals(5));
      expect(usage.totalTokens, equals(15));
    });

    test('accepts zero values', () {
      final usage = CompletionUsage(
        promptTokens: 0,
        completionTokens: 0,
        totalTokens: 0,
      );
      expect(usage.promptTokens, equals(0));
      expect(usage.completionTokens, equals(0));
      expect(usage.totalTokens, equals(0));
    });
  });

  group('CompletionUsage — fromJson()', () {
    test('parses from snake_case JSON', () {
      final json = <String, dynamic>{
        'prompt_tokens': 20,
        'completion_tokens': 10,
        'total_tokens': 30,
      };
      final usage = CompletionUsage.fromJson(json);
      expect(usage.promptTokens, equals(20));
      expect(usage.completionTokens, equals(10));
      expect(usage.totalTokens, equals(30));
    });
  });

  group('CompletionUsage — toJson()', () {
    test('serializes to snake_case keys', () {
      final usage = CompletionUsage(
        promptTokens: 5,
        completionTokens: 3,
        totalTokens: 8,
      );
      final json = usage.toJson();
      expect(json['prompt_tokens'], equals(5));
      expect(json['completion_tokens'], equals(3));
      expect(json['total_tokens'], equals(8));
      expect(json.containsKey('promptTokens'), isFalse);
      expect(json.containsKey('completionTokens'), isFalse);
      expect(json.containsKey('totalTokens'), isFalse);
    });
  });

  group('CompletionUsage — round-trip', () {
    test('round-trips through toJson/fromJson', () {
      final original = CompletionUsage(
        promptTokens: 100,
        completionTokens: 50,
        totalTokens: 150,
      );
      final restored = CompletionUsage.fromJson(original.toJson());
      expect(restored.promptTokens, equals(original.promptTokens));
      expect(restored.completionTokens, equals(original.completionTokens));
      expect(restored.totalTokens, equals(original.totalTokens));
    });
  });

  group('ChatCompletionChoice — construction', () {
    test('creates with message and finishReason', () {
      final msg = ChatMessage(role: ChatMessageRole.assistant, content: 'Hi');
      final choice = ChatCompletionChoice(message: msg, finishReason: 'stop');
      expect(choice.message.role, equals(ChatMessageRole.assistant));
      expect(choice.message.content, equals('Hi'));
      expect(choice.finishReason, equals('stop'));
    });

    test('finishReason can be null', () {
      final msg = ChatMessage(role: ChatMessageRole.assistant, content: 'Partial');
      final choice = ChatCompletionChoice(message: msg, finishReason: null);
      expect(choice.finishReason, isNull);
    });

    test('accepts length finishReason', () {
      final msg = ChatMessage(role: ChatMessageRole.assistant, content: '...');
      final choice = ChatCompletionChoice(message: msg, finishReason: 'length');
      expect(choice.finishReason, equals('length'));
    });

    test('accepts tool_calls finishReason', () {
      final msg = ChatMessage(role: ChatMessageRole.assistant, content: '');
      final choice = ChatCompletionChoice(message: msg, finishReason: 'tool_calls');
      expect(choice.finishReason, equals('tool_calls'));
    });
  });

  group('ChatCompletionChoice — fromJson()', () {
    test('parses message and finish_reason', () {
      final json = <String, dynamic>{
        'index': 0,
        'message': {'role': 'assistant', 'content': 'Hello!'},
        'finish_reason': 'stop',
      };
      final choice = ChatCompletionChoice.fromJson(json);
      expect(choice.message.role, equals(ChatMessageRole.assistant));
      expect(choice.message.content, equals('Hello!'));
      expect(choice.finishReason, equals('stop'));
    });

    test('parses null finish_reason', () {
      final json = <String, dynamic>{
        'index': 0,
        'message': {'role': 'assistant', 'content': ''},
        'finish_reason': null,
      };
      final choice = ChatCompletionChoice.fromJson(json);
      expect(choice.finishReason, isNull);
    });
  });

  group('ChatCompletionChoice — toJson()', () {
    test('serializes message and finish_reason', () {
      final msg = ChatMessage(role: ChatMessageRole.assistant, content: 'Done');
      final choice = ChatCompletionChoice(message: msg, finishReason: 'stop');
      final json = choice.toJson();
      expect(json['message'], isA<Map<String, dynamic>>());
      expect((json['message'] as Map)['role'], equals('assistant'));
      expect(json['finish_reason'], equals('stop'));
    });

    test('finish_reason is null in JSON when not set', () {
      final msg = ChatMessage(role: ChatMessageRole.assistant, content: '');
      final choice = ChatCompletionChoice(message: msg, finishReason: null);
      final json = choice.toJson();
      expect(json['finish_reason'], isNull);
    });
  });

  group('ChatCompletionResponse — construction', () {
    test('creates with id, choices, and usage', () {
      final msg = ChatMessage(role: ChatMessageRole.assistant, content: 'Hi');
      final choice = ChatCompletionChoice(message: msg, finishReason: 'stop');
      final usage = CompletionUsage(promptTokens: 10, completionTokens: 5, totalTokens: 15);
      final response = ChatCompletionResponse(
        id: 'chatcmpl-xyz',
        choices: [choice],
        usage: usage,
      );
      expect(response.id, equals('chatcmpl-xyz'));
      expect(response.choices.length, equals(1));
      expect(response.usage.totalTokens, equals(15));
    });

    test('accepts multiple choices (n > 1)', () {
      final msg1 = ChatMessage(role: ChatMessageRole.assistant, content: 'Option A');
      final msg2 = ChatMessage(role: ChatMessageRole.assistant, content: 'Option B');
      final choice1 = ChatCompletionChoice(message: msg1, finishReason: 'stop');
      final choice2 = ChatCompletionChoice(message: msg2, finishReason: 'stop');
      final usage = CompletionUsage(promptTokens: 5, completionTokens: 10, totalTokens: 15);
      final response = ChatCompletionResponse(
        id: 'chatcmpl-multi',
        choices: [choice1, choice2],
        usage: usage,
      );
      expect(response.choices.length, equals(2));
    });
  });

  group('ChatCompletionResponse — fromJson()', () {
    test('parses standard response', () {
      final json = buildResponseJson();
      final response = ChatCompletionResponse.fromJson(json);
      expect(response.id, equals('chatcmpl-abc123'));
      expect(response.choices.length, equals(1));
      expect(response.choices[0].message.role, equals(ChatMessageRole.assistant));
      expect(response.choices[0].message.content, equals('Hello! How can I help?'));
      expect(response.choices[0].finishReason, equals('stop'));
      expect(response.usage.promptTokens, equals(10));
      expect(response.usage.completionTokens, equals(8));
      expect(response.usage.totalTokens, equals(18));
    });

    test('parses response with null finish_reason', () {
      final json = buildResponseJson(finishReason: null);
      final response = ChatCompletionResponse.fromJson(json);
      expect(response.choices[0].finishReason, isNull);
    });

    test('parses response with length finish_reason', () {
      final json = buildResponseJson(finishReason: 'length');
      final response = ChatCompletionResponse.fromJson(json);
      expect(response.choices[0].finishReason, equals('length'));
    });

    test('parses response with different id', () {
      final json = buildResponseJson(id: 'chatcmpl-differentid');
      final response = ChatCompletionResponse.fromJson(json);
      expect(response.id, equals('chatcmpl-differentid'));
    });

    test('parses zero-token usage', () {
      final json = buildResponseJson(promptTokens: 0, completionTokens: 0, totalTokens: 0);
      final response = ChatCompletionResponse.fromJson(json);
      expect(response.usage.promptTokens, equals(0));
      expect(response.usage.completionTokens, equals(0));
      expect(response.usage.totalTokens, equals(0));
    });
  });

  group('ChatCompletionResponse — toJson()', () {
    test('serializes id, choices, and usage', () {
      final json = buildResponseJson();
      final response = ChatCompletionResponse.fromJson(json);
      final output = response.toJson();
      expect(output['id'], equals('chatcmpl-abc123'));
      expect(output['choices'], isA<List>());
      expect(output['usage'], isA<Map<String, dynamic>>());
    });

    test('choices serialized as list of maps', () {
      final json = buildResponseJson();
      final response = ChatCompletionResponse.fromJson(json);
      final output = response.toJson();
      final choices = output['choices'] as List;
      expect(choices[0], isA<Map<String, dynamic>>());
    });

    test('usage serialized with snake_case keys', () {
      final json = buildResponseJson(promptTokens: 7, completionTokens: 3, totalTokens: 10);
      final response = ChatCompletionResponse.fromJson(json);
      final output = response.toJson();
      final usage = output['usage'] as Map<String, dynamic>;
      expect(usage['prompt_tokens'], equals(7));
      expect(usage['completion_tokens'], equals(3));
      expect(usage['total_tokens'], equals(10));
    });
  });

  group('ChatCompletionResponse — round-trip', () {
    test('round-trips through toJson/fromJson', () {
      final json = buildResponseJson();
      final original = ChatCompletionResponse.fromJson(json);
      final restored = ChatCompletionResponse.fromJson(original.toJson());
      expect(restored.id, equals(original.id));
      expect(restored.choices.length, equals(original.choices.length));
      expect(restored.choices[0].message.content, equals(original.choices[0].message.content));
      expect(restored.choices[0].finishReason, equals(original.choices[0].finishReason));
      expect(restored.usage.promptTokens, equals(original.usage.promptTokens));
      expect(restored.usage.completionTokens, equals(original.usage.completionTokens));
      expect(restored.usage.totalTokens, equals(original.usage.totalTokens));
    });
  });
}
