import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

/// Tests for the legacy/text Completion models:
///   - [CompletionRequest]  → POST /v1/completions
///   - [CompletionResponse] → response body from /v1/completions
///
/// These mirror the OpenAI text-completion (non-chat) API that LM Studio
/// exposes for compatibility.
void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // CompletionRequest
  // ─────────────────────────────────────────────────────────────────────────

  group('CompletionRequest — construction', () {
    test('creates with required fields only', () {
      final req = CompletionRequest(
        model: 'lmstudio-community/mistral-7b',
        prompt: 'Once upon a time',
      );
      expect(req.model, equals('lmstudio-community/mistral-7b'));
      expect(req.prompt, equals('Once upon a time'));
      expect(req.maxTokens, isNull);
      expect(req.temperature, isNull);
    });

    test('creates with all optional fields', () {
      final req = CompletionRequest(
        model: 'model-x',
        prompt: 'Tell me a joke',
        maxTokens: 128,
        temperature: 0.8,
      );
      expect(req.maxTokens, equals(128));
      expect(req.temperature, equals(0.8));
    });

    test('accepts empty prompt', () {
      final req = CompletionRequest(model: 'model', prompt: '');
      expect(req.prompt, equals(''));
    });

    test('accepts maxTokens = 1', () {
      final req = CompletionRequest(model: 'model', prompt: 'hi', maxTokens: 1);
      expect(req.maxTokens, equals(1));
    });

    test('accepts temperature = 0.0', () {
      final req = CompletionRequest(
        model: 'model',
        prompt: 'hi',
        temperature: 0.0,
      );
      expect(req.temperature, equals(0.0));
    });

    test('accepts temperature = 2.0 (max)', () {
      final req = CompletionRequest(
        model: 'model',
        prompt: 'hi',
        temperature: 2.0,
      );
      expect(req.temperature, equals(2.0));
    });
  });

  group('CompletionRequest — toJson()', () {
    test('serializes required fields', () {
      final req = CompletionRequest(
        model: 'test-model',
        prompt: 'Complete this',
      );
      final json = req.toJson();
      expect(json['model'], equals('test-model'));
      expect(json['prompt'], equals('Complete this'));
    });

    test('optional fields omitted from JSON when null', () {
      final req = CompletionRequest(model: 'model', prompt: 'test');
      final json = req.toJson();
      expect(json.containsKey('max_tokens'), isFalse);
      expect(json.containsKey('temperature'), isFalse);
    });

    test('maxTokens serialized as max_tokens (snake_case)', () {
      final req = CompletionRequest(
        model: 'model',
        prompt: 'test',
        maxTokens: 64,
      );
      final json = req.toJson();
      expect(json['max_tokens'], equals(64));
      expect(json.containsKey('maxTokens'), isFalse);
    });

    test('temperature serialized correctly', () {
      final req = CompletionRequest(
        model: 'model',
        prompt: 'test',
        temperature: 0.5,
      );
      final json = req.toJson();
      expect(json['temperature'], equals(0.5));
    });

    test('returns Map<String, dynamic>', () {
      final req = CompletionRequest(model: 'model', prompt: 'hi');
      expect(req.toJson(), isA<Map<String, dynamic>>());
    });

    test('all fields present when all set', () {
      final req = CompletionRequest(
        model: 'full-model',
        prompt: 'The sky is',
        maxTokens: 50,
        temperature: 1.0,
      );
      final json = req.toJson();
      expect(json['model'], equals('full-model'));
      expect(json['prompt'], equals('The sky is'));
      expect(json['max_tokens'], equals(50));
      expect(json['temperature'], equals(1.0));
    });
  });

  group('CompletionRequest — fromJson()', () {
    test('parses required fields', () {
      final json = <String, dynamic>{
        'model': 'my-model',
        'prompt': 'Say hello',
      };
      final req = CompletionRequest.fromJson(json);
      expect(req.model, equals('my-model'));
      expect(req.prompt, equals('Say hello'));
    });

    test('parses max_tokens as maxTokens', () {
      final json = <String, dynamic>{
        'model': 'model',
        'prompt': 'hi',
        'max_tokens': 100,
      };
      final req = CompletionRequest.fromJson(json);
      expect(req.maxTokens, equals(100));
    });

    test('parses temperature', () {
      final json = <String, dynamic>{
        'model': 'model',
        'prompt': 'hi',
        'temperature': 0.7,
      };
      final req = CompletionRequest.fromJson(json);
      expect(req.temperature, equals(0.7));
    });

    test('optional fields are null when absent', () {
      final json = <String, dynamic>{'model': 'model', 'prompt': 'hi'};
      final req = CompletionRequest.fromJson(json);
      expect(req.maxTokens, isNull);
      expect(req.temperature, isNull);
    });
  });

  group('CompletionRequest — round-trip', () {
    test('round-trips required fields', () {
      final original = CompletionRequest(
        model: 'round-trip-model',
        prompt: 'Hello!',
      );
      final restored = CompletionRequest.fromJson(original.toJson());
      expect(restored.model, equals(original.model));
      expect(restored.prompt, equals(original.prompt));
    });

    test('round-trips all fields', () {
      final original = CompletionRequest(
        model: 'full',
        prompt: 'The quick brown fox',
        maxTokens: 32,
        temperature: 0.6,
      );
      final restored = CompletionRequest.fromJson(original.toJson());
      expect(restored.model, equals(original.model));
      expect(restored.prompt, equals(original.prompt));
      expect(restored.maxTokens, equals(original.maxTokens));
      expect(restored.temperature, equals(original.temperature));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // CompletionChoice
  // ─────────────────────────────────────────────────────────────────────────

  group('CompletionChoice — construction', () {
    test('creates with text and finishReason', () {
      final choice = CompletionChoice(
        text: 'jumped over the lazy dog',
        finishReason: 'stop',
      );
      expect(choice.text, equals('jumped over the lazy dog'));
      expect(choice.finishReason, equals('stop'));
    });

    test('finishReason can be null', () {
      final choice = CompletionChoice(
        text: 'partial output',
        finishReason: null,
      );
      expect(choice.finishReason, isNull);
    });

    test('finishReason can be length', () {
      final choice = CompletionChoice(
        text: 'truncated',
        finishReason: 'length',
      );
      expect(choice.finishReason, equals('length'));
    });
  });

  group('CompletionChoice — fromJson()', () {
    test('parses text and finish_reason', () {
      final json = <String, dynamic>{
        'index': 0,
        'text': 'Hello world',
        'finish_reason': 'stop',
      };
      final choice = CompletionChoice.fromJson(json);
      expect(choice.text, equals('Hello world'));
      expect(choice.finishReason, equals('stop'));
    });

    test('parses null finish_reason', () {
      final json = <String, dynamic>{
        'index': 0,
        'text': 'partial',
        'finish_reason': null,
      };
      final choice = CompletionChoice.fromJson(json);
      expect(choice.finishReason, isNull);
    });
  });

  group('CompletionChoice — toJson()', () {
    test('serializes text and finish_reason', () {
      final choice = CompletionChoice(text: 'output', finishReason: 'stop');
      final json = choice.toJson();
      expect(json['text'], equals('output'));
      expect(json['finish_reason'], equals('stop'));
    });

    test('finish_reason is null when not set', () {
      final choice = CompletionChoice(text: 'output', finishReason: null);
      final json = choice.toJson();
      expect(json['finish_reason'], isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // CompletionResponse
  // ─────────────────────────────────────────────────────────────────────────

  Map<String, dynamic> buildCompletionResponseJson({
    String id = 'cmpl-abc123',
    String text = 'jumped over the lazy dog',
    String? finishReason = 'stop',
    int promptTokens = 8,
    int completionTokens = 6,
    int totalTokens = 14,
  }) {
    return {
      'id': id,
      'object': 'text_completion',
      'choices': [
        {'index': 0, 'text': text, 'finish_reason': finishReason},
      ],
      'usage': {
        'prompt_tokens': promptTokens,
        'completion_tokens': completionTokens,
        'total_tokens': totalTokens,
      },
    };
  }

  group('CompletionResponse — construction', () {
    test('creates with id, choices, and usage', () {
      final choice = CompletionChoice(text: 'result', finishReason: 'stop');
      final usage = CompletionUsage(
        promptTokens: 5,
        completionTokens: 3,
        totalTokens: 8,
      );
      final response = CompletionResponse(
        id: 'cmpl-xyz',
        choices: [choice],
        usage: usage,
      );
      expect(response.id, equals('cmpl-xyz'));
      expect(response.choices.length, equals(1));
      expect(response.usage.totalTokens, equals(8));
    });

    test('accepts multiple choices', () {
      final choices = [
        CompletionChoice(text: 'option A', finishReason: 'stop'),
        CompletionChoice(text: 'option B', finishReason: 'stop'),
      ];
      final usage = CompletionUsage(
        promptTokens: 5,
        completionTokens: 10,
        totalTokens: 15,
      );
      final response = CompletionResponse(
        id: 'cmpl-multi',
        choices: choices,
        usage: usage,
      );
      expect(response.choices.length, equals(2));
    });
  });

  group('CompletionResponse — fromJson()', () {
    test('parses standard response', () {
      final json = buildCompletionResponseJson();
      final response = CompletionResponse.fromJson(json);
      expect(response.id, equals('cmpl-abc123'));
      expect(response.choices.length, equals(1));
      expect(response.choices[0].text, equals('jumped over the lazy dog'));
      expect(response.choices[0].finishReason, equals('stop'));
      expect(response.usage.promptTokens, equals(8));
      expect(response.usage.completionTokens, equals(6));
      expect(response.usage.totalTokens, equals(14));
    });

    test('parses response with null finish_reason', () {
      final json = buildCompletionResponseJson(finishReason: null);
      final response = CompletionResponse.fromJson(json);
      expect(response.choices[0].finishReason, isNull);
    });

    test('parses response with length finish_reason', () {
      final json = buildCompletionResponseJson(finishReason: 'length');
      final response = CompletionResponse.fromJson(json);
      expect(response.choices[0].finishReason, equals('length'));
    });

    test('parses response with different id', () {
      final json = buildCompletionResponseJson(id: 'cmpl-other');
      final response = CompletionResponse.fromJson(json);
      expect(response.id, equals('cmpl-other'));
    });

    test('parses usage with large token counts', () {
      final json = buildCompletionResponseJson(
        promptTokens: 4096,
        completionTokens: 2048,
        totalTokens: 6144,
      );
      final response = CompletionResponse.fromJson(json);
      expect(response.usage.promptTokens, equals(4096));
      expect(response.usage.completionTokens, equals(2048));
      expect(response.usage.totalTokens, equals(6144));
    });
  });

  group('CompletionResponse — toJson()', () {
    test('serializes id, choices, and usage', () {
      final json = buildCompletionResponseJson();
      final response = CompletionResponse.fromJson(json);
      final output = response.toJson();
      expect(output['id'], equals('cmpl-abc123'));
      expect(output['choices'], isA<List>());
      expect(output['usage'], isA<Map<String, dynamic>>());
    });

    test('choices serialized as list of maps with text', () {
      final json = buildCompletionResponseJson(text: 'hello');
      final response = CompletionResponse.fromJson(json);
      final output = response.toJson();
      final choices = output['choices'] as List;
      final choice = choices[0] as Map<String, dynamic>;
      expect(choice['text'], equals('hello'));
    });
  });

  group('CompletionResponse — round-trip', () {
    test('round-trips through toJson/fromJson', () {
      final json = buildCompletionResponseJson();
      final original = CompletionResponse.fromJson(json);
      final restored = CompletionResponse.fromJson(original.toJson());
      expect(restored.id, equals(original.id));
      expect(restored.choices.length, equals(original.choices.length));
      expect(restored.choices[0].text, equals(original.choices[0].text));
      expect(
        restored.choices[0].finishReason,
        equals(original.choices[0].finishReason),
      );
      expect(restored.usage.promptTokens, equals(original.usage.promptTokens));
      expect(
        restored.usage.completionTokens,
        equals(original.usage.completionTokens),
      );
      expect(restored.usage.totalTokens, equals(original.usage.totalTokens));
    });
  });
}
