import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

import '../helpers/mock_lm_studio_server.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Builds an [AgentsCoreConfig] that points at [server].
AgentsCoreConfig configFor(MockLmStudioServer server) => AgentsCoreConfig(
  lmStudioBaseUrl: Uri.parse(server.baseUrl),
  logger: const SilentLogger(),
);

/// A minimal valid chat completion response JSON.
Map<String, dynamic> chatResponseJson({
  String id = 'chatcmpl-test',
  String content = 'Hello!',
  String finishReason = 'stop',
  int promptTokens = 10,
  int completionTokens = 5,
  int totalTokens = 15,
}) => {
  'id': id,
  'object': 'chat.completion',
  'choices': [
    {
      'index': 0,
      'message': {'role': 'assistant', 'content': content},
      'finish_reason': finishReason,
    },
  ],
  'usage': {
    'prompt_tokens': promptTokens,
    'completion_tokens': completionTokens,
    'total_tokens': totalTokens,
  },
};

/// A minimal valid text completion response JSON.
Map<String, dynamic> completionResponseJson({
  String id = 'cmpl-test',
  String text = 'Once upon a time',
  String finishReason = 'stop',
  int promptTokens = 8,
  int completionTokens = 4,
  int totalTokens = 12,
}) => {
  'id': id,
  'object': 'text_completion',
  'choices': [
    {'text': text, 'index': 0, 'finish_reason': finishReason},
  ],
  'usage': {
    'prompt_tokens': promptTokens,
    'completion_tokens': completionTokens,
    'total_tokens': totalTokens,
  },
};

/// A single chat completion SSE chunk JSON.
Map<String, dynamic> chunkJson({
  String id = 'chatcmpl-stream',
  String? role,
  String? content,
  String? finishReason,
}) => {
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

/// A minimal [ChatCompletionRequest] for use in tests.
ChatCompletionRequest simpleRequest({
  String model = 'test-model',
  String userContent = 'Hello',
}) => ChatCompletionRequest(
  model: model,
  messages: [ChatMessage(role: ChatMessageRole.user, content: userContent)],
);

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late MockLmStudioServer server;
  late LmStudioClient client;

  setUp(() async {
    server = await MockLmStudioServer.start();
    client = LmStudioClient(configFor(server));
  });

  tearDown(() async {
    client.dispose();
    await server.close();
  });

  // ── listModels ─────────────────────────────────────────────────────────────

  group('LmStudioClient.listModels()', () {
    test('sends GET request to /v1/models', () async {
      server.enqueue(
        method: 'GET',
        path: '/v1/models',
        response: MockResponse.json(body: {'data': []}),
      );

      await client.listModels();

      expect(server.requests, hasLength(1));
      expect(server.requests.first.method, equals('GET'));
      expect(server.requests.first.path, equals('/v1/models'));
    });

    test('returns empty list when data is empty', () async {
      server.enqueue(response: MockResponse.json(body: {'data': []}));

      final models = await client.listModels();
      expect(models, isEmpty);
    });

    test('returns parsed LmModel list', () async {
      server.enqueue(
        response: MockResponse.json(
          body: {
            'data': [
              {'id': 'llama-3-8b', 'owned_by': 'lmstudio'},
              {'id': 'mistral-7b', 'owned_by': 'community'},
            ],
          },
        ),
      );

      final models = await client.listModels();

      expect(models, hasLength(2));
      expect(models[0].id, equals('llama-3-8b'));
      expect(models[0].ownedBy, equals('lmstudio'));
      expect(models[1].id, equals('mistral-7b'));
      expect(models[1].ownedBy, equals('community'));
    });

    test('returns single-element list correctly', () async {
      server.enqueue(
        response: MockResponse.json(
          body: {
            'data': [
              {'id': 'gpt2', 'owned_by': 'openai'},
            ],
          },
        ),
      );

      final models = await client.listModels();
      expect(models, hasLength(1));
      expect(models.first, isA<LmModel>());
    });

    test('throws LmStudioHttpException on 4xx response', () async {
      server.enqueue(
        response: MockResponse.error(
          statusCode: 404,
          body: {'error': 'not found'},
        ),
      );

      expect(client.listModels(), throwsA(isA<LmStudioHttpException>()));
    });

    test('throws LmStudioHttpException on 5xx response', () async {
      server.enqueue(
        response: MockResponse.error(
          statusCode: 500,
          body: {'error': 'internal server error'},
        ),
      );

      expect(client.listModels(), throwsA(isA<LmStudioHttpException>()));
    });

    test(
      'throws LmStudioConnectionException when server is unreachable',
      () async {
        await server.close();
        // Create client pointing at a port that is definitely not listening.
        final deadConfig = AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse('http://127.0.0.1:1'),
          logger: const SilentLogger(),
        );
        final deadClient = LmStudioClient(deadConfig);
        addTearDown(deadClient.dispose);

        expect(
          deadClient.listModels(),
          throwsA(isA<LmStudioConnectionException>()),
        );
      },
    );
  });

  // ── chatCompletion ─────────────────────────────────────────────────────────

  group('LmStudioClient.chatCompletion()', () {
    test('sends POST request to /v1/chat/completions', () async {
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: chatResponseJson()),
      );

      await client.chatCompletion(simpleRequest());

      expect(server.requests, hasLength(1));
      expect(server.requests.first.method, equals('POST'));
      expect(server.requests.first.path, equals('/v1/chat/completions'));
    });

    test('request body contains model field', () async {
      server.enqueue(response: MockResponse.json(body: chatResponseJson()));

      await client.chatCompletion(
        ChatCompletionRequest(
          model: 'llama-3-8b',
          messages: [ChatMessage(role: ChatMessageRole.user, content: 'Hi')],
        ),
      );

      final body = server.requests.first.jsonBody;
      expect(body['model'], equals('llama-3-8b'));
    });

    test('request body contains messages field', () async {
      server.enqueue(response: MockResponse.json(body: chatResponseJson()));

      await client.chatCompletion(
        simpleRequest(userContent: 'What time is it?'),
      );

      final body = server.requests.first.jsonBody;
      final messages = body['messages'] as List;
      expect(messages, hasLength(1));
      expect(messages[0]['role'], equals('user'));
      expect(messages[0]['content'], equals('What time is it?'));
    });

    test('does NOT include stream field in request body', () async {
      server.enqueue(response: MockResponse.json(body: chatResponseJson()));

      await client.chatCompletion(simpleRequest());

      final body = server.requests.first.jsonBody;
      expect(body.containsKey('stream'), isFalse);
    });

    test('request body uses snake_case for max_tokens', () async {
      server.enqueue(response: MockResponse.json(body: chatResponseJson()));

      await client.chatCompletion(
        ChatCompletionRequest(
          model: 'model',
          messages: [ChatMessage(role: ChatMessageRole.user, content: 'Hi')],
          maxTokens: 256,
        ),
      );

      final body = server.requests.first.jsonBody;
      expect(body['max_tokens'], equals(256));
      expect(body.containsKey('maxTokens'), isFalse);
    });

    test('request body includes temperature when set', () async {
      server.enqueue(response: MockResponse.json(body: chatResponseJson()));

      await client.chatCompletion(
        ChatCompletionRequest(
          model: 'model',
          messages: [ChatMessage(role: ChatMessageRole.user, content: 'Hi')],
          temperature: 0.7,
        ),
      );

      final body = server.requests.first.jsonBody;
      expect(body['temperature'], closeTo(0.7, 0.001));
    });

    test('request body includes tool definitions in OpenAI format', () async {
      server.enqueue(response: MockResponse.json(body: chatResponseJson()));

      final tool = ToolDefinition(
        name: 'get_weather',
        description: 'Get the weather for a city',
        parameters: {
          'type': 'object',
          'properties': {
            'city': {'type': 'string'},
          },
          'required': ['city'],
        },
      );

      await client.chatCompletion(
        ChatCompletionRequest(
          model: 'model',
          messages: [ChatMessage(role: ChatMessageRole.user, content: 'Hi')],
          tools: [tool],
        ),
      );

      final body = server.requests.first.jsonBody;
      final tools = body['tools'] as List;
      expect(tools, hasLength(1));
      expect(tools[0]['type'], equals('function'));
      expect(tools[0]['function']['name'], equals('get_weather'));
      expect(
        tools[0]['function']['description'],
        equals('Get the weather for a city'),
      );
    });

    test('request body includes tool_choice when set', () async {
      server.enqueue(response: MockResponse.json(body: chatResponseJson()));

      await client.chatCompletion(
        ChatCompletionRequest(
          model: 'model',
          messages: [ChatMessage(role: ChatMessageRole.user, content: 'Hi')],
          toolChoice: 'auto',
        ),
      );

      final body = server.requests.first.jsonBody;
      expect(body['tool_choice'], equals('auto'));
    });

    test('returns parsed ChatCompletionResponse', () async {
      server.enqueue(
        response: MockResponse.json(
          body: chatResponseJson(
            id: 'chatcmpl-xyz',
            content: 'I am doing well!',
            finishReason: 'stop',
            promptTokens: 20,
            completionTokens: 10,
            totalTokens: 30,
          ),
        ),
      );

      final response = await client.chatCompletion(simpleRequest());

      expect(response, isA<ChatCompletionResponse>());
      expect(response.id, equals('chatcmpl-xyz'));
      expect(response.choices, hasLength(1));
      expect(
        response.choices.first.message.role,
        equals(ChatMessageRole.assistant),
      );
      expect(
        response.choices.first.message.content,
        equals('I am doing well!'),
      );
      expect(response.choices.first.finishReason, equals('stop'));
      expect(response.usage.promptTokens, equals(20));
      expect(response.usage.completionTokens, equals(10));
      expect(response.usage.totalTokens, equals(30));
    });

    test('response with length finish_reason is handled correctly', () async {
      server.enqueue(
        response: MockResponse.json(
          body: chatResponseJson(finishReason: 'length'),
        ),
      );

      final response = await client.chatCompletion(simpleRequest());
      expect(response.choices.first.finishReason, equals('length'));
    });

    test('throws LmStudioHttpException on 422 response', () async {
      server.enqueue(
        response: MockResponse.error(
          statusCode: 422,
          body: {'error': 'Unprocessable Entity'},
        ),
      );

      expect(
        client.chatCompletion(simpleRequest()),
        throwsA(isA<LmStudioHttpException>()),
      );
    });

    test('throws LmStudioHttpException on 429 response', () async {
      server.enqueue(
        response: MockResponse.error(
          statusCode: 429,
          body: {'error': 'Too Many Requests'},
        ),
      );

      expect(
        client.chatCompletion(simpleRequest()),
        throwsA(isA<LmStudioHttpException>()),
      );
    });

    test('LmStudioHttpException has correct statusCode on 404', () async {
      server.enqueue(
        response: MockResponse.error(
          statusCode: 404,
          body: {'error': 'Not Found'},
        ),
      );

      try {
        await client.chatCompletion(simpleRequest());
        fail('Expected LmStudioHttpException');
      } on LmStudioHttpException catch (e) {
        expect(e.statusCode, equals(404));
      }
    });

    test('multi-message conversation is serialized correctly', () async {
      server.enqueue(response: MockResponse.json(body: chatResponseJson()));

      await client.chatCompletion(
        ChatCompletionRequest(
          model: 'model',
          messages: [
            ChatMessage(
              role: ChatMessageRole.system,
              content: 'You are helpful.',
            ),
            ChatMessage(role: ChatMessageRole.user, content: 'Hello'),
            ChatMessage(role: ChatMessageRole.assistant, content: 'Hi there!'),
            ChatMessage(role: ChatMessageRole.user, content: 'What is Dart?'),
          ],
        ),
      );

      final body = server.requests.first.jsonBody;
      final messages = body['messages'] as List;
      expect(messages, hasLength(4));
      expect(messages[0]['role'], equals('system'));
      expect(messages[1]['role'], equals('user'));
      expect(messages[2]['role'], equals('assistant'));
      expect(messages[3]['role'], equals('user'));
    });
  });

  // ── chatCompletionStream ───────────────────────────────────────────────────

  group('LmStudioClient.chatCompletionStream()', () {
    test('sends POST request to /v1/chat/completions', () async {
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.sse(chunks: [chunkJson(content: 'Hello')]),
      );

      await client.chatCompletionStream(simpleRequest()).toList();

      expect(server.requests.first.method, equals('POST'));
      expect(server.requests.first.path, equals('/v1/chat/completions'));
    });

    test('request body includes stream: true', () async {
      server.enqueue(
        response: MockResponse.sse(chunks: [chunkJson(content: 'Hi')]),
      );

      await client.chatCompletionStream(simpleRequest()).toList();

      final body = server.requests.first.jsonBody;
      expect(body['stream'], isTrue);
    });

    test('returns Stream<ChatCompletionChunk>', () async {
      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            chunkJson(role: 'assistant', content: null),
            chunkJson(content: 'Hello'),
            chunkJson(content: ' World'),
            chunkJson(content: null, finishReason: 'stop'),
          ],
        ),
      );

      final chunks = await client
          .chatCompletionStream(simpleRequest())
          .toList();

      expect(chunks, isA<List<ChatCompletionChunk>>());
      expect(chunks, hasLength(4));
    });

    test('stream emits chunks with correct content', () async {
      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            chunkJson(content: 'Hello'),
            chunkJson(content: ' there'),
            chunkJson(content: '!'),
            chunkJson(content: null, finishReason: 'stop'),
          ],
        ),
      );

      final chunks = await client
          .chatCompletionStream(simpleRequest())
          .toList();

      expect(chunks[0].choices.first.delta.content, equals('Hello'));
      expect(chunks[1].choices.first.delta.content, equals(' there'));
      expect(chunks[2].choices.first.delta.content, equals('!'));
      expect(chunks[3].choices.first.finishReason, equals('stop'));
    });

    test('first chunk typically contains role delta', () async {
      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            chunkJson(role: 'assistant', content: null),
            chunkJson(content: 'Hi'),
          ],
        ),
      );

      final chunks = await client
          .chatCompletionStream(simpleRequest())
          .toList();

      expect(chunks.first.choices.first.delta.role, equals('assistant'));
    });

    test('chunk id is parsed correctly', () async {
      server.enqueue(
        response: MockResponse.sse(
          chunks: [chunkJson(id: 'chatcmpl-stream-001', content: 'test')],
        ),
      );

      final chunks = await client
          .chatCompletionStream(simpleRequest())
          .toList();

      expect(chunks.first.id, equals('chatcmpl-stream-001'));
    });

    test('stream completes after [DONE] sentinel', () async {
      server.enqueue(
        response: MockResponse.sse(
          chunks: [chunkJson(content: 'only one chunk')],
        ),
      );

      final chunks = await client
          .chatCompletionStream(simpleRequest())
          .toList();
      // Stream should complete (not hang) and contain just the one chunk.
      expect(chunks, hasLength(1));
    });

    test('request body contains model', () async {
      server.enqueue(
        response: MockResponse.sse(chunks: [chunkJson(content: 'ok')]),
      );

      await client
          .chatCompletionStream(simpleRequest(model: 'llama-stream'))
          .toList();

      final body = server.requests.first.jsonBody;
      expect(body['model'], equals('llama-stream'));
    });

    test('throws LmStudioHttpException on 4xx response', () async {
      server.enqueue(
        response: MockResponse.error(
          statusCode: 422,
          body: {'error': 'bad request'},
        ),
      );

      expect(
        client.chatCompletionStream(simpleRequest()).toList(),
        throwsA(isA<LmStudioHttpException>()),
      );
    });
  });

  // ── chatCompletionStreamText ───────────────────────────────────────────────

  group('LmStudioClient.chatCompletionStreamText()', () {
    test('returns only non-null, non-empty content strings', () async {
      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            chunkJson(role: 'assistant', content: null), // null → filtered
            chunkJson(content: 'Hello'),
            chunkJson(content: ' World'),
            chunkJson(content: null, finishReason: 'stop'), // null → filtered
          ],
        ),
      );

      final texts = await client
          .chatCompletionStreamText(simpleRequest())
          .toList();

      expect(texts, equals(['Hello', ' World']));
    });

    test('returns Stream<String>', () async {
      server.enqueue(
        response: MockResponse.sse(chunks: [chunkJson(content: 'Dart')]),
      );

      final stream = client.chatCompletionStreamText(simpleRequest());
      expect(stream, isA<Stream<String>>());
    });

    test('filters empty string content', () async {
      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            chunkJson(content: ''), // empty → filtered
            chunkJson(content: 'hi'),
            chunkJson(content: ''), // empty → filtered
          ],
        ),
      );

      final texts = await client
          .chatCompletionStreamText(simpleRequest())
          .toList();

      // Only 'hi' should be emitted
      expect(texts, equals(['hi']));
    });

    test('concatenated text matches full response', () async {
      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            chunkJson(content: 'The'),
            chunkJson(content: ' answer'),
            chunkJson(content: ' is'),
            chunkJson(content: ' 42'),
            chunkJson(content: null, finishReason: 'stop'),
          ],
        ),
      );

      final texts = await client
          .chatCompletionStreamText(simpleRequest())
          .toList();

      expect(texts.join(), equals('The answer is 42'));
    });

    test('returns empty list when all deltas are null/empty', () async {
      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            chunkJson(role: 'assistant', content: null),
            chunkJson(content: null, finishReason: 'stop'),
          ],
        ),
      );

      final texts = await client
          .chatCompletionStreamText(simpleRequest())
          .toList();

      expect(texts, isEmpty);
    });
  });

  // ── completion ─────────────────────────────────────────────────────────────

  group('LmStudioClient.completion()', () {
    test('sends POST request to /v1/completions', () async {
      server.enqueue(
        method: 'POST',
        path: '/v1/completions',
        response: MockResponse.json(body: completionResponseJson()),
      );

      await client.completion(
        CompletionRequest(model: 'gpt2', prompt: 'Once upon'),
      );

      expect(server.requests, hasLength(1));
      expect(server.requests.first.method, equals('POST'));
      expect(server.requests.first.path, equals('/v1/completions'));
    });

    test('request body contains model field', () async {
      server.enqueue(
        response: MockResponse.json(body: completionResponseJson()),
      );

      await client.completion(
        CompletionRequest(model: 'gpt2-xl', prompt: 'Hello'),
      );

      final body = server.requests.first.jsonBody;
      expect(body['model'], equals('gpt2-xl'));
    });

    test('request body contains prompt field', () async {
      server.enqueue(
        response: MockResponse.json(body: completionResponseJson()),
      );

      await client.completion(
        CompletionRequest(model: 'gpt2', prompt: 'Once upon a time'),
      );

      final body = server.requests.first.jsonBody;
      expect(body['prompt'], equals('Once upon a time'));
    });

    test('request body uses snake_case max_tokens', () async {
      server.enqueue(
        response: MockResponse.json(body: completionResponseJson()),
      );

      await client.completion(
        CompletionRequest(model: 'gpt2', prompt: 'Hi', maxTokens: 128),
      );

      final body = server.requests.first.jsonBody;
      expect(body['max_tokens'], equals(128));
      expect(body.containsKey('maxTokens'), isFalse);
    });

    test('returns parsed CompletionResponse', () async {
      server.enqueue(
        response: MockResponse.json(
          body: completionResponseJson(
            id: 'cmpl-abc',
            text: 'a long time ago',
            finishReason: 'stop',
            promptTokens: 3,
            completionTokens: 4,
            totalTokens: 7,
          ),
        ),
      );

      final response = await client.completion(
        CompletionRequest(model: 'gpt2', prompt: 'Once upon'),
      );

      expect(response, isA<CompletionResponse>());
      expect(response.id, equals('cmpl-abc'));
      expect(response.choices, hasLength(1));
      expect(response.choices.first.text, equals('a long time ago'));
      expect(response.choices.first.finishReason, equals('stop'));
      expect(response.usage.promptTokens, equals(3));
      expect(response.usage.completionTokens, equals(4));
      expect(response.usage.totalTokens, equals(7));
    });

    test('throws LmStudioHttpException on 4xx response', () async {
      server.enqueue(
        response: MockResponse.error(
          statusCode: 400,
          body: {'error': 'Bad Request'},
        ),
      );

      expect(
        client.completion(CompletionRequest(model: 'gpt2', prompt: 'Hi')),
        throwsA(isA<LmStudioHttpException>()),
      );
    });
  });

  // ── completionStream ───────────────────────────────────────────────────────

  group('LmStudioClient.completionStream()', () {
    test('sends POST request to /v1/completions', () async {
      server.enqueue(
        method: 'POST',
        path: '/v1/completions',
        response: MockResponse.sse(
          chunks: [
            {
              'id': 'cmpl-1',
              'choices': [
                {'text': ' world', 'finish_reason': null},
              ],
            },
          ],
        ),
      );

      await client
          .completionStream(CompletionRequest(model: 'gpt2', prompt: 'Hello'))
          .toList();

      expect(server.requests.first.method, equals('POST'));
      expect(server.requests.first.path, equals('/v1/completions'));
    });

    test('request body includes stream: true', () async {
      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            {
              'id': 'cmpl-1',
              'choices': [
                {'text': 'x', 'finish_reason': null},
              ],
            },
          ],
        ),
      );

      await client
          .completionStream(CompletionRequest(model: 'gpt2', prompt: 'Hi'))
          .toList();

      final body = server.requests.first.jsonBody;
      expect(body['stream'], isTrue);
    });

    test('returns Stream<Map<String, dynamic>>', () async {
      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            {
              'id': 'c1',
              'choices': [
                {'text': 'Hello', 'finish_reason': null},
              ],
            },
            {
              'id': 'c2',
              'choices': [
                {'text': '!', 'finish_reason': 'stop'},
              ],
            },
          ],
        ),
      );

      final items = await client
          .completionStream(CompletionRequest(model: 'gpt2', prompt: 'Hi'))
          .toList();

      expect(items, isA<List<Map<String, dynamic>>>());
      expect(items, hasLength(2));
    });

    test('stream emits raw JSON maps', () async {
      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            {
              'id': 'cmpl-raw',
              'choices': [
                {'text': ' foo', 'finish_reason': null},
              ],
            },
          ],
        ),
      );

      final items = await client
          .completionStream(CompletionRequest(model: 'gpt2', prompt: 'Hi'))
          .toList();

      expect(items.first['id'], equals('cmpl-raw'));
      final choices = items.first['choices'] as List;
      expect((choices.first as Map)['text'], equals(' foo'));
    });

    test('throws LmStudioHttpException on non-2xx response', () async {
      server.enqueue(
        response: MockResponse.error(
          statusCode: 500,
          body: {'error': 'Internal Server Error'},
        ),
      );

      expect(
        client
            .completionStream(CompletionRequest(model: 'gpt2', prompt: 'Hi'))
            .toList(),
        throwsA(isA<LmStudioHttpException>()),
      );
    });
  });

  // ── dispose ────────────────────────────────────────────────────────────────

  group('LmStudioClient.dispose()', () {
    test('does not throw when called once', () {
      final disposable = LmStudioClient(configFor(server));
      expect(() => disposable.dispose(), returnsNormally);
    });

    test('can be called independently of server lifecycle', () async {
      final anotherServer = await MockLmStudioServer.start();
      final anotherClient = LmStudioClient(configFor(anotherServer));
      await anotherServer.close();
      // Disposing after the server is closed should still be fine.
      expect(() => anotherClient.dispose(), returnsNormally);
    });
  });

  // ── request serialization edge cases ──────────────────────────────────────

  group('LmStudioClient — request serialization edge cases', () {
    test('chatCompletion omits optional fields when not set', () async {
      server.enqueue(response: MockResponse.json(body: chatResponseJson()));

      await client.chatCompletion(
        ChatCompletionRequest(
          model: 'model',
          messages: [ChatMessage(role: ChatMessageRole.user, content: 'Hi')],
        ),
      );

      final body = server.requests.first.jsonBody;
      expect(body.containsKey('temperature'), isFalse);
      expect(body.containsKey('max_tokens'), isFalse);
      expect(body.containsKey('tools'), isFalse);
      expect(body.containsKey('tool_choice'), isFalse);
      expect(body.containsKey('stream'), isFalse);
    });

    test(
      'chatCompletionStream always has stream: true regardless of request stream field',
      () async {
        server.enqueue(
          response: MockResponse.sse(chunks: [chunkJson(content: 'ok')]),
        );

        // Request explicitly says stream: false — but the method should override it to true.
        await client
            .chatCompletionStream(
              ChatCompletionRequest(
                model: 'model',
                messages: [
                  ChatMessage(role: ChatMessageRole.user, content: 'Hi'),
                ],
                stream: false,
              ),
            )
            .toList();

        final body = server.requests.first.jsonBody;
        expect(body['stream'], isTrue);
      },
    );

    test('completion omits optional fields when not set', () async {
      server.enqueue(
        response: MockResponse.json(body: completionResponseJson()),
      );

      await client.completion(CompletionRequest(model: 'gpt2', prompt: 'Hi'));

      final body = server.requests.first.jsonBody;
      expect(body.containsKey('max_tokens'), isFalse);
      expect(body.containsKey('temperature'), isFalse);
    });

    test(
      'tool message with toolCallId is serialized in chatCompletion',
      () async {
        server.enqueue(response: MockResponse.json(body: chatResponseJson()));

        await client.chatCompletion(
          ChatCompletionRequest(
            model: 'model',
            messages: [
              ChatMessage(role: ChatMessageRole.user, content: 'Use a tool'),
              ChatMessage(
                role: ChatMessageRole.tool,
                content: '{"result": "42"}',
                toolCallId: 'call_123',
              ),
            ],
          ),
        );

        final body = server.requests.first.jsonBody;
        final messages = body['messages'] as List;
        final toolMsg = messages[1] as Map;
        expect(toolMsg['role'], equals('tool'));
        expect(toolMsg['tool_call_id'], equals('call_123'));
        expect(toolMsg['content'], equals('{"result": "42"}'));
      },
    );
  });

  // ── JSON content-type header ───────────────────────────────────────────────

  group('LmStudioClient — request headers', () {
    test('chatCompletion sends Content-Type: application/json', () async {
      server.enqueue(response: MockResponse.json(body: chatResponseJson()));

      await client.chatCompletion(simpleRequest());

      final req = server.requests.first;
      expect(req.headers['content-type']?.first, contains('application/json'));
    });

    test('listModels GET request has Accept: application/json', () async {
      server.enqueue(response: MockResponse.json(body: {'data': []}));

      await client.listModels();

      final req = server.requests.first;
      expect(req.headers['accept']?.first, contains('application/json'));
    });
  });
}
