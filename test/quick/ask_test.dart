// ignore_for_file: lines_longer_than_80_chars

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

import '../helpers/mock_lm_studio_server.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Builds a minimal valid chat completion JSON response body.
Map<String, dynamic> _chatCompletionJson({
  String id = 'chatcmpl-test',
  String content = 'Hello from AI!',
  String model = 'llama3',
  String finishReason = 'stop',
}) => {
  'id': id,
  'object': 'chat.completion',
  'created': 1700000000,
  'model': model,
  'choices': [
    {
      'index': 0,
      'message': {'role': 'assistant', 'content': content},
      'finish_reason': finishReason,
    },
  ],
  'usage': {'prompt_tokens': 10, 'completion_tokens': 5, 'total_tokens': 15},
};

/// Builds an SSE chunk for streaming responses.
Map<String, dynamic> _sseChunk({
  String id = 'chatcmpl-stream',
  String? content,
  String? role,
  String? finishReason,
}) => {
  'id': id,
  'object': 'chat.completion.chunk',
  'created': 1700000000,
  'model': 'llama3',
  'choices': [
    {
      'index': 0,
      'delta': {'role': ?role, 'content': ?content},
      'finish_reason': finishReason,
    },
  ],
};

/// Builds a response with multiple choices (n > 1).
Map<String, dynamic> _multiChoiceJson({required List<String> contents}) => {
  'id': 'chatcmpl-multi',
  'object': 'chat.completion',
  'created': 1700000000,
  'model': 'llama3',
  'choices': [
    for (int i = 0; i < contents.length; i++)
      {
        'index': i,
        'message': {'role': 'assistant', 'content': contents[i]},
        'finish_reason': 'stop',
      },
  ],
  'usage': {'prompt_tokens': 10, 'completion_tokens': 5, 'total_tokens': 15},
};

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late MockLmStudioServer server;
  late AgentsCoreConfig config;

  setUp(() async {
    server = await MockLmStudioServer.start();
    config = AgentsCoreConfig(
      lmStudioBaseUrl: Uri.parse(server.baseUrl),
      logger: const SilentLogger(),
    );
  });

  tearDown(() => server.close());

  // ── Happy path ─────────────────────────────────────────────────────────────

  group('ask() — happy path', () {
    test('returns the first choice assistant content', () async {
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(
          body: _chatCompletionJson(content: 'Hello from AI!'),
        ),
      );

      final result = await ask('Say hello', config: config, model: 'llama3');

      expect(result, equals('Hello from AI!'));
    });

    test('returns multi-line content verbatim', () async {
      const multiline = 'Line one\nLine two\nLine three';
      server.enqueue(
        response: MockResponse.json(
          body: _chatCompletionJson(content: multiline),
        ),
      );

      final result = await ask('Tell me', config: config, model: 'llama3');

      expect(result, equals(multiline));
    });

    test(
      'returns empty string when assistant replies with empty content',
      () async {
        server.enqueue(
          response: MockResponse.json(body: _chatCompletionJson(content: '')),
        );

        final result = await ask('Prompt', config: config, model: 'llama3');

        expect(result, equals(''));
      },
    );

    test(
      'returns only first choice when multiple choices are present',
      () async {
        server.enqueue(
          response: MockResponse.json(
            body: _multiChoiceJson(
              contents: ['First choice', 'Second choice', 'Third choice'],
            ),
          ),
        );

        final result = await ask('Hello', config: config, model: 'llama3');

        expect(result, equals('First choice'));
      },
    );

    test('returns unicode content correctly', () async {
      const unicode = '你好世界 🌍 ñoño Привет';
      server.enqueue(
        response: MockResponse.json(
          body: _chatCompletionJson(content: unicode),
        ),
      );

      final result = await ask(
        'Say hello in multiple languages',
        config: config,
        model: 'llama3',
      );

      expect(result, equals(unicode));
    });
  });

  // ── HTTP endpoint & method ─────────────────────────────────────────────────

  group('ask() — HTTP request target', () {
    test('sends exactly one POST request', () async {
      server.enqueue(response: MockResponse.json(body: _chatCompletionJson()));

      await ask('Hello', config: config, model: 'llama3');

      expect(server.requests, hasLength(1));
      expect(server.requests.first.method, equals('POST'));
    });

    test('sends request to /v1/chat/completions', () async {
      server.enqueue(response: MockResponse.json(body: _chatCompletionJson()));

      await ask('Hello', config: config, model: 'llama3');

      expect(server.requests.first.path, equals('/v1/chat/completions'));
    });
  });

  // ── Message structure ──────────────────────────────────────────────────────

  group('ask() — message structure', () {
    test('includes user message with prompt text', () async {
      server.enqueue(response: MockResponse.json(body: _chatCompletionJson()));

      await ask('What is the weather?', config: config, model: 'llama3');

      final body = server.requests.first.jsonBody;
      final messages = body['messages'] as List;
      final userMessages = messages.where((m) => m['role'] == 'user').toList();
      expect(userMessages, hasLength(1));
      expect(userMessages.first['content'], equals('What is the weather?'));
    });

    test(
      'sends exactly one message when no systemPrompt is provided',
      () async {
        server.enqueue(
          response: MockResponse.json(body: _chatCompletionJson()),
        );

        await ask('Hello', config: config, model: 'llama3');

        final body = server.requests.first.jsonBody;
        final messages = body['messages'] as List;
        expect(messages, hasLength(1));
        expect(messages.first['role'], equals('user'));
      },
    );

    test('sends two messages when systemPrompt is provided', () async {
      server.enqueue(response: MockResponse.json(body: _chatCompletionJson()));

      await ask(
        'Hello',
        config: config,
        model: 'llama3',
        systemPrompt: 'You are helpful.',
      );

      final body = server.requests.first.jsonBody;
      final messages = body['messages'] as List;
      expect(messages, hasLength(2));
    });

    test('system message appears before user message', () async {
      server.enqueue(response: MockResponse.json(body: _chatCompletionJson()));

      await ask(
        'My prompt',
        config: config,
        model: 'llama3',
        systemPrompt: 'You are concise.',
      );

      final body = server.requests.first.jsonBody;
      final messages = body['messages'] as List;
      expect(messages[0]['role'], equals('system'));
      expect(messages[1]['role'], equals('user'));
    });

    test('system message contains correct systemPrompt text', () async {
      server.enqueue(response: MockResponse.json(body: _chatCompletionJson()));

      await ask(
        'Hello',
        config: config,
        model: 'llama3',
        systemPrompt: 'You are a helpful assistant.',
      );

      final body = server.requests.first.jsonBody;
      final messages = body['messages'] as List;
      expect(messages[0]['role'], equals('system'));
      expect(messages[0]['content'], equals('You are a helpful assistant.'));
    });

    test(
      'user message content matches prompt when systemPrompt present',
      () async {
        server.enqueue(
          response: MockResponse.json(body: _chatCompletionJson()),
        );

        await ask(
          'Explain quantum physics',
          config: config,
          model: 'llama3',
          systemPrompt: 'You are a physicist.',
        );

        final body = server.requests.first.jsonBody;
        final messages = body['messages'] as List;
        expect(messages[1]['role'], equals('user'));
        expect(messages[1]['content'], equals('Explain quantum physics'));
      },
    );
  });

  // ── Model parameter ────────────────────────────────────────────────────────

  group('ask() — model parameter', () {
    test('sends provided model in request body', () async {
      server.enqueue(response: MockResponse.json(body: _chatCompletionJson()));

      await ask('Hello', config: config, model: 'custom-model-v2');

      final body = server.requests.first.jsonBody;
      expect(body['model'], equals('custom-model-v2'));
    });

    test('sends different model strings correctly', () async {
      const models = [
        'llama-3-8b',
        'mistral-7b',
        'gpt-3.5-turbo',
        'local/custom-model',
      ];

      for (final model in models) {
        server.enqueue(
          response: MockResponse.json(body: _chatCompletionJson()),
        );

        await ask('Hello', config: config, model: model);

        final body = server.requests.last.jsonBody;
        expect(body['model'], equals(model), reason: 'model=$model');
      }
    });

    test('uses a non-empty default model when model is null', () async {
      server.enqueue(response: MockResponse.json(body: _chatCompletionJson()));

      // ask() must still send a valid, non-empty model string when null is passed
      await ask('Hello', config: config);

      final body = server.requests.first.jsonBody;
      expect(body['model'], isA<String>());
      expect((body['model'] as String).isNotEmpty, isTrue);
    });
  });

  // ── Temperature parameter ──────────────────────────────────────────────────

  group('ask() — temperature parameter', () {
    test('includes temperature in request when provided', () async {
      server.enqueue(response: MockResponse.json(body: _chatCompletionJson()));

      await ask('Hello', config: config, model: 'llama3', temperature: 0.7);

      final body = server.requests.first.jsonBody;
      expect(body['temperature'], closeTo(0.7, 0.001));
    });

    test('sends temperature 0.0 when explicitly zero', () async {
      server.enqueue(response: MockResponse.json(body: _chatCompletionJson()));

      await ask('Hello', config: config, model: 'llama3', temperature: 0.0);

      final body = server.requests.first.jsonBody;
      expect(body.containsKey('temperature'), isTrue);
      expect(body['temperature'], closeTo(0.0, 0.001));
    });

    test('sends temperature 1.0 for max standard value', () async {
      server.enqueue(response: MockResponse.json(body: _chatCompletionJson()));

      await ask('Hello', config: config, model: 'llama3', temperature: 1.0);

      final body = server.requests.first.jsonBody;
      expect(body['temperature'], closeTo(1.0, 0.001));
    });

    test('sends temperature 2.0 for maximum allowed value', () async {
      server.enqueue(response: MockResponse.json(body: _chatCompletionJson()));

      await ask('Hello', config: config, model: 'llama3', temperature: 2.0);

      final body = server.requests.first.jsonBody;
      expect(body['temperature'], closeTo(2.0, 0.001));
    });

    test('omits temperature from request when null', () async {
      server.enqueue(response: MockResponse.json(body: _chatCompletionJson()));

      await ask('Hello', config: config, model: 'llama3');

      final body = server.requests.first.jsonBody;
      expect(body.containsKey('temperature'), isFalse);
    });
  });

  // ── Config parameter ───────────────────────────────────────────────────────

  group('ask() — config parameter', () {
    test('uses provided config base URL to reach the mock server', () async {
      server.enqueue(response: MockResponse.json(body: _chatCompletionJson()));

      await ask('Hello', config: config, model: 'llama3');

      // The mock server received the request, proving the config URL was used
      expect(server.requests, hasLength(1));
    });

    test('works with SilentLogger config (no stderr output)', () async {
      final silentConfig = AgentsCoreConfig(
        lmStudioBaseUrl: Uri.parse(server.baseUrl),
        logger: const SilentLogger(),
      );
      server.enqueue(
        response: MockResponse.json(body: _chatCompletionJson(content: 'ok')),
      );

      final result = await ask('Hello', config: silentConfig, model: 'llama3');

      expect(result, equals('ok'));
    });

    test('uses custom requestTimeout from config', () async {
      final customConfig = AgentsCoreConfig(
        lmStudioBaseUrl: Uri.parse(server.baseUrl),
        requestTimeout: const Duration(seconds: 30),
        logger: const SilentLogger(),
      );
      server.enqueue(response: MockResponse.json(body: _chatCompletionJson()));

      // Should complete without error when custom timeout is set
      final result = await ask('Hello', config: customConfig, model: 'llama3');
      expect(result, isA<String>());
    });
  });

  // ── Error propagation ──────────────────────────────────────────────────────

  group('ask() — error propagation', () {
    test('throws LmStudioApiException on 500 Internal Server Error', () async {
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.error(
          statusCode: 500,
          body: {
            'error': {'message': 'Internal server error'},
          },
        ),
      );

      await expectLater(
        ask('Hello', config: config, model: 'llama3'),
        throwsA(isA<LmStudioApiException>()),
      );
    });

    test('throws LmStudioApiException on 400 Bad Request', () async {
      server.enqueue(
        response: MockResponse.error(
          statusCode: 400,
          body: {
            'error': {'message': 'Bad request'},
          },
        ),
      );

      await expectLater(
        ask('Hello', config: config, model: 'llama3'),
        throwsA(isA<LmStudioApiException>()),
      );
    });

    test('throws LmStudioApiException on 401 Unauthorized', () async {
      server.enqueue(
        response: MockResponse.error(
          statusCode: 401,
          body: {
            'error': {'message': 'Unauthorized'},
          },
        ),
      );

      await expectLater(
        ask('Hello', config: config, model: 'llama3'),
        throwsA(isA<LmStudioApiException>()),
      );
    });

    test('throws LmStudioApiException on 422 Unprocessable Entity', () async {
      server.enqueue(
        response: MockResponse.error(
          statusCode: 422,
          body: {
            'error': {'message': 'Unprocessable'},
          },
        ),
      );

      await expectLater(
        ask('Hello', config: config, model: 'llama3'),
        throwsA(isA<LmStudioApiException>()),
      );
    });

    test('LmStudioApiException carries correct status code', () async {
      server.enqueue(
        response: MockResponse.error(
          statusCode: 429,
          body: {
            'error': {'message': 'Rate limited'},
          },
        ),
      );

      try {
        await ask('Hello', config: config, model: 'llama3');
        fail('Expected LmStudioApiException to be thrown');
      } on LmStudioApiException catch (e) {
        expect(e.statusCode, equals(429));
      }
    });

    test(
      'throws LmStudioConnectionException when server is unreachable',
      () async {
        // Port 1 always refuses connections on loopback
        final badConfig = AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse('http://127.0.0.1:1'),
          logger: const SilentLogger(),
        );

        await expectLater(
          ask('Hello', config: badConfig, model: 'llama3'),
          throwsA(isA<LmStudioConnectionException>()),
        );
      },
    );

    test(
      'LmStudioConnectionException isSocketError for refused connections',
      () async {
        final badConfig = AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse('http://127.0.0.1:1'),
          logger: const SilentLogger(),
        );

        try {
          await ask('Hello', config: badConfig, model: 'llama3');
          fail('Expected LmStudioConnectionException to be thrown');
        } on LmStudioConnectionException catch (e) {
          expect(e.isSocketError, isTrue);
        }
      },
    );
  });

  // ── Edge cases ─────────────────────────────────────────────────────────────

  group('ask() — edge cases', () {
    test('handles prompt with special/escaped characters', () async {
      server.enqueue(
        response: MockResponse.json(body: _chatCompletionJson(content: 'ok')),
      );

      const specialPrompt = r'Hello "world" & <html> \n \\';
      final result = await ask(specialPrompt, config: config, model: 'llama3');

      expect(result, equals('ok'));
      final body = server.requests.first.jsonBody;
      final messages = body['messages'] as List;
      expect(messages.first['content'], equals(specialPrompt));
    });

    test('handles empty prompt string', () async {
      server.enqueue(
        response: MockResponse.json(
          body: _chatCompletionJson(content: 'response'),
        ),
      );

      final result = await ask('', config: config, model: 'llama3');

      expect(result, equals('response'));
      final body = server.requests.first.jsonBody;
      final messages = body['messages'] as List;
      expect(messages.first['content'], equals(''));
    });

    test('handles very long prompt (10 000 chars)', () async {
      final longPrompt = 'x' * 10000;
      server.enqueue(
        response: MockResponse.json(body: _chatCompletionJson(content: 'done')),
      );

      final result = await ask(longPrompt, config: config, model: 'llama3');

      expect(result, equals('done'));
      final body = server.requests.first.jsonBody;
      final messages = body['messages'] as List;
      expect(messages.first['content'], equals(longPrompt));
    });

    test(
      'request does not include stream:true (one-shot, not streaming)',
      () async {
        server.enqueue(
          response: MockResponse.json(body: _chatCompletionJson()),
        );

        await ask('Hello', config: config, model: 'llama3');

        final body = server.requests.first.jsonBody;
        // stream should be absent or explicitly false
        final stream = body['stream'];
        expect(stream == null || stream == false, isTrue);
      },
    );

    test('successive calls each send an independent request', () async {
      server
        ..enqueue(
          response: MockResponse.json(
            body: _chatCompletionJson(content: 'First'),
          ),
        )
        ..enqueue(
          response: MockResponse.json(
            body: _chatCompletionJson(content: 'Second'),
          ),
        );

      final first = await ask('Q1', config: config, model: 'llama3');
      final second = await ask('Q2', config: config, model: 'llama3');

      expect(first, equals('First'));
      expect(second, equals('Second'));
      expect(server.requests, hasLength(2));
      expect(
        server.requests[0].jsonBody['messages'][0]['content'],
        equals('Q1'),
      );
      expect(
        server.requests[1].jsonBody['messages'][0]['content'],
        equals('Q2'),
      );
    });

    test('handles JSON in prompt without corrupting request body', () async {
      server.enqueue(
        response: MockResponse.json(body: _chatCompletionJson(content: 'ok')),
      );

      const jsonPrompt = '{"key": "value", "number": 42}';
      await ask(jsonPrompt, config: config, model: 'llama3');

      final body = server.requests.first.jsonBody;
      final messages = body['messages'] as List;
      expect(messages.first['content'], equals(jsonPrompt));
    });

    test(
      'handles newlines in systemPrompt without breaking message structure',
      () async {
        server.enqueue(
          response: MockResponse.json(body: _chatCompletionJson()),
        );

        const multilineSystem =
            'You are helpful.\nAlways be concise.\nBe polite.';
        await ask(
          'Hello',
          config: config,
          model: 'llama3',
          systemPrompt: multilineSystem,
        );

        final body = server.requests.first.jsonBody;
        final messages = body['messages'] as List;
        expect(messages[0]['content'], equals(multilineSystem));
      },
    );
  });

  // ── askStream() ────────────────────────────────────────────────────────────

  group('askStream() — happy path', () {
    test('emits text deltas from the stream', () async {
      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            _sseChunk(role: 'assistant'),
            _sseChunk(content: 'Hello'),
            _sseChunk(content: ' World'),
            _sseChunk(finishReason: 'stop'),
          ],
        ),
      );

      final texts = await askStream(
        'Say hello',
        config: config,
        model: 'llama3',
      ).toList();

      expect(texts, equals(['Hello', ' World']));
    });

    test('returns Stream<String>', () {
      server.enqueue(
        response: MockResponse.sse(chunks: [_sseChunk(content: 'hi')]),
      );

      final stream = askStream('Hello', config: config, model: 'llama3');
      expect(stream, isA<Stream<String>>());
    });

    test('concatenated stream output equals full response text', () async {
      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            _sseChunk(content: 'The'),
            _sseChunk(content: ' quick'),
            _sseChunk(content: ' brown'),
            _sseChunk(content: ' fox'),
            _sseChunk(finishReason: 'stop'),
          ],
        ),
      );

      final texts = await askStream(
        'Write a sentence',
        config: config,
        model: 'llama3',
      ).toList();

      expect(texts.join(), equals('The quick brown fox'));
    });

    test('stream completes after [DONE] sentinel', () async {
      server.enqueue(
        response: MockResponse.sse(chunks: [_sseChunk(content: 'done')]),
      );

      final texts = await askStream(
        'Hello',
        config: config,
        model: 'llama3',
      ).toList();

      expect(texts, hasLength(1));
    });

    test('emits single-element stream for a single chunk', () async {
      server.enqueue(
        response: MockResponse.sse(chunks: [_sseChunk(content: 'only this')]),
      );

      final texts = await askStream(
        'Hello',
        config: config,
        model: 'llama3',
      ).toList();

      expect(texts, hasLength(1));
      expect(texts.first, equals('only this'));
    });

    test('returns unicode content correctly', () async {
      const unicode = '你好世界 🌍 Привет';
      server.enqueue(
        response: MockResponse.sse(chunks: [_sseChunk(content: unicode)]),
      );

      final texts = await askStream(
        'Say hi',
        config: config,
        model: 'llama3',
      ).toList();

      expect(texts.join(), equals(unicode));
    });
  });

  group('askStream() — HTTP request target', () {
    test('sends POST to /v1/chat/completions', () async {
      server.enqueue(
        response: MockResponse.sse(chunks: [_sseChunk(content: 'ok')]),
      );

      await askStream('Hello', config: config, model: 'llama3').toList();

      expect(server.requests, hasLength(1));
      expect(server.requests.first.method, equals('POST'));
      expect(server.requests.first.path, equals('/v1/chat/completions'));
    });

    test('sends stream: true in request body', () async {
      server.enqueue(
        response: MockResponse.sse(chunks: [_sseChunk(content: 'ok')]),
      );

      await askStream('Hello', config: config, model: 'llama3').toList();

      final body = server.requests.first.jsonBody;
      expect(body['stream'], isTrue);
    });
  });

  group('askStream() — message structure', () {
    test('includes user message with prompt text', () async {
      server.enqueue(
        response: MockResponse.sse(chunks: [_sseChunk(content: 'ok')]),
      );

      await askStream(
        'What is the weather?',
        config: config,
        model: 'llama3',
      ).toList();

      final body = server.requests.first.jsonBody;
      final messages = body['messages'] as List;
      final userMessages = messages.where((m) => m['role'] == 'user').toList();
      expect(userMessages, hasLength(1));
      expect(userMessages.first['content'], equals('What is the weather?'));
    });

    test(
      'sends exactly one message when no systemPrompt is provided',
      () async {
        server.enqueue(
          response: MockResponse.sse(chunks: [_sseChunk(content: 'ok')]),
        );

        await askStream('Hello', config: config, model: 'llama3').toList();

        final body = server.requests.first.jsonBody;
        final messages = body['messages'] as List;
        expect(messages, hasLength(1));
        expect(messages.first['role'], equals('user'));
      },
    );

    test('sends two messages when systemPrompt is provided', () async {
      server.enqueue(
        response: MockResponse.sse(chunks: [_sseChunk(content: 'ok')]),
      );

      await askStream(
        'Hello',
        config: config,
        model: 'llama3',
        systemPrompt: 'You are helpful.',
      ).toList();

      final body = server.requests.first.jsonBody;
      final messages = body['messages'] as List;
      expect(messages, hasLength(2));
    });

    test('system message appears before user message', () async {
      server.enqueue(
        response: MockResponse.sse(chunks: [_sseChunk(content: 'ok')]),
      );

      await askStream(
        'My prompt',
        config: config,
        model: 'llama3',
        systemPrompt: 'You are concise.',
      ).toList();

      final body = server.requests.first.jsonBody;
      final messages = body['messages'] as List;
      expect(messages[0]['role'], equals('system'));
      expect(messages[0]['content'], equals('You are concise.'));
      expect(messages[1]['role'], equals('user'));
    });

    test('system message contains correct systemPrompt text', () async {
      server.enqueue(
        response: MockResponse.sse(chunks: [_sseChunk(content: 'ok')]),
      );

      await askStream(
        'Hello',
        config: config,
        model: 'llama3',
        systemPrompt: 'You are a helpful assistant.',
      ).toList();

      final body = server.requests.first.jsonBody;
      final messages = body['messages'] as List;
      expect(messages[0]['content'], equals('You are a helpful assistant.'));
    });
  });

  group('askStream() — model parameter', () {
    test('sends provided model in request body', () async {
      server.enqueue(
        response: MockResponse.sse(chunks: [_sseChunk(content: 'ok')]),
      );

      await askStream(
        'Hello',
        config: config,
        model: 'custom-model-v2',
      ).toList();

      final body = server.requests.first.jsonBody;
      expect(body['model'], equals('custom-model-v2'));
    });

    test('uses a non-empty default model when model is null', () async {
      server.enqueue(
        response: MockResponse.sse(chunks: [_sseChunk(content: 'ok')]),
      );

      await askStream('Hello', config: config).toList();

      final body = server.requests.first.jsonBody;
      expect(body['model'], isA<String>());
      expect((body['model'] as String).isNotEmpty, isTrue);
    });

    test('sends different model strings correctly', () async {
      const models = ['llama-3-8b', 'mistral-7b', 'local/custom-model'];

      for (final model in models) {
        server.enqueue(
          response: MockResponse.sse(chunks: [_sseChunk(content: 'ok')]),
        );

        await askStream('Hello', config: config, model: model).toList();

        final body = server.requests.last.jsonBody;
        expect(body['model'], equals(model), reason: 'model=$model');
      }
    });
  });

  group('askStream() — temperature parameter', () {
    test('includes temperature in request when provided', () async {
      server.enqueue(
        response: MockResponse.sse(chunks: [_sseChunk(content: 'ok')]),
      );

      await askStream(
        'Hello',
        config: config,
        model: 'llama3',
        temperature: 0.7,
      ).toList();

      final body = server.requests.first.jsonBody;
      expect(body['temperature'], closeTo(0.7, 0.001));
    });

    test('sends temperature 0.0 when explicitly zero', () async {
      server.enqueue(
        response: MockResponse.sse(chunks: [_sseChunk(content: 'ok')]),
      );

      await askStream(
        'Hello',
        config: config,
        model: 'llama3',
        temperature: 0.0,
      ).toList();

      final body = server.requests.first.jsonBody;
      expect(body.containsKey('temperature'), isTrue);
      expect(body['temperature'], closeTo(0.0, 0.001));
    });

    test('omits temperature from request when null', () async {
      server.enqueue(
        response: MockResponse.sse(chunks: [_sseChunk(content: 'ok')]),
      );

      await askStream('Hello', config: config, model: 'llama3').toList();

      final body = server.requests.first.jsonBody;
      expect(body.containsKey('temperature'), isFalse);
    });
  });

  group('askStream() — content filtering', () {
    test('filters null content deltas from stream', () async {
      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            _sseChunk(role: 'assistant', content: null), // null → filtered
            _sseChunk(content: 'real text'),
            _sseChunk(content: null, finishReason: 'stop'), // null → filtered
          ],
        ),
      );

      final texts = await askStream(
        'Hello',
        config: config,
        model: 'llama3',
      ).toList();

      expect(texts, equals(['real text']));
    });

    test('filters empty string content deltas from stream', () async {
      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            _sseChunk(content: ''), // empty → filtered
            _sseChunk(content: 'hello'),
            _sseChunk(content: ''), // empty → filtered
          ],
        ),
      );

      final texts = await askStream(
        'Hello',
        config: config,
        model: 'llama3',
      ).toList();

      expect(texts, equals(['hello']));
    });

    test('returns empty list when all deltas are null or empty', () async {
      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            _sseChunk(role: 'assistant', content: null),
            _sseChunk(content: ''),
            _sseChunk(finishReason: 'stop'),
          ],
        ),
      );

      final texts = await askStream(
        'Hello',
        config: config,
        model: 'llama3',
      ).toList();

      expect(texts, isEmpty);
    });
  });

  group('askStream() — error propagation', () {
    test('throws LmStudioApiException on 500 as stream error', () async {
      server.enqueue(
        response: MockResponse.error(
          statusCode: 500,
          body: {
            'error': {'message': 'Internal server error'},
          },
        ),
      );

      await expectLater(
        askStream('Hello', config: config, model: 'llama3').toList(),
        throwsA(isA<LmStudioApiException>()),
      );
    });

    test('throws LmStudioApiException on 400 as stream error', () async {
      server.enqueue(
        response: MockResponse.error(
          statusCode: 400,
          body: {
            'error': {'message': 'Bad request'},
          },
        ),
      );

      await expectLater(
        askStream('Hello', config: config, model: 'llama3').toList(),
        throwsA(isA<LmStudioApiException>()),
      );
    });

    test('throws LmStudioApiException on 422 as stream error', () async {
      server.enqueue(
        response: MockResponse.error(
          statusCode: 422,
          body: {
            'error': {'message': 'Unprocessable'},
          },
        ),
      );

      await expectLater(
        askStream('Hello', config: config, model: 'llama3').toList(),
        throwsA(isA<LmStudioApiException>()),
      );
    });

    test('LmStudioApiException carries correct status code', () async {
      server.enqueue(
        response: MockResponse.error(
          statusCode: 429,
          body: {
            'error': {'message': 'Rate limited'},
          },
        ),
      );

      try {
        await askStream('Hello', config: config, model: 'llama3').toList();
        fail('Expected LmStudioApiException to be thrown');
      } on LmStudioApiException catch (e) {
        expect(e.statusCode, equals(429));
      }
    });

    test(
      'throws LmStudioConnectionException when server is unreachable',
      () async {
        final badConfig = AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse('http://127.0.0.1:1'),
          logger: const SilentLogger(),
        );

        await expectLater(
          askStream('Hello', config: badConfig, model: 'llama3').toList(),
          throwsA(isA<LmStudioConnectionException>()),
        );
      },
    );
  });

  group('askStream() — edge cases', () {
    test('handles empty prompt string', () async {
      server.enqueue(
        response: MockResponse.sse(chunks: [_sseChunk(content: 'response')]),
      );

      final texts = await askStream(
        '',
        config: config,
        model: 'llama3',
      ).toList();

      expect(texts, equals(['response']));
      final body = server.requests.first.jsonBody;
      final messages = body['messages'] as List;
      expect(messages.first['content'], equals(''));
    });

    test('handles special characters in prompt', () async {
      server.enqueue(
        response: MockResponse.sse(chunks: [_sseChunk(content: 'ok')]),
      );

      const special = r'Hello "world" & <html> \n \\';
      await askStream(special, config: config, model: 'llama3').toList();

      final body = server.requests.first.jsonBody;
      final messages = body['messages'] as List;
      expect(messages.first['content'], equals(special));
    });

    test('handles JSON in prompt without corrupting request body', () async {
      server.enqueue(
        response: MockResponse.sse(chunks: [_sseChunk(content: 'ok')]),
      );

      const jsonPrompt = '{"key": "value", "number": 42}';
      await askStream(jsonPrompt, config: config, model: 'llama3').toList();

      final body = server.requests.first.jsonBody;
      final messages = body['messages'] as List;
      expect(messages.first['content'], equals(jsonPrompt));
    });

    test('successive calls each send independent requests', () async {
      server
        ..enqueue(
          response: MockResponse.sse(chunks: [_sseChunk(content: 'First')]),
        )
        ..enqueue(
          response: MockResponse.sse(chunks: [_sseChunk(content: 'Second')]),
        );

      final first = await askStream(
        'Q1',
        config: config,
        model: 'llama3',
      ).toList();
      final second = await askStream(
        'Q2',
        config: config,
        model: 'llama3',
      ).toList();

      expect(first.join(), equals('First'));
      expect(second.join(), equals('Second'));
      expect(server.requests, hasLength(2));
      expect(
        server.requests[0].jsonBody['messages'][0]['content'],
        equals('Q1'),
      );
      expect(
        server.requests[1].jsonBody['messages'][0]['content'],
        equals('Q2'),
      );
    });
  });
}
