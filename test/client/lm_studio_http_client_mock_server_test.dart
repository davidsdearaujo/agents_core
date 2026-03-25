// ignore_for_file: avoid_catching_errors

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

import '../helpers/mock_lm_studio_server.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// LmStudioHttpClient — MockLmStudioServer integration tests
//
// These tests use [MockLmStudioServer] as the HTTP backend, exercising the full
// request/response lifecycle with realistic LM Studio data shapes.
//
// Gaps addressed (not covered by lm_studio_http_client_request_test.dart):
//   1. Realistic LM Studio chat-completion and model-list payloads
//   2. LM Studio-formatted error bodies ({"error": {"type": ..., "message": ...}})
//   3. SSE / postStream full round-trip
//   4. Multiple sequential requests via the same client instance
//   5. Request body field-level assertions using server.requests.first.jsonBody
//   6. HttpException wrapping → LmStudioConnectionException.isHttpError
//   7. Timeout wrapping via a non-reachable address
//   8. 2xx codes other than 200 do NOT throw
// ═══════════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────────
// Helper: AgentsCoreConfig pointing at the mock server
// ─────────────────────────────────────────────────────────────────────────────

AgentsCoreConfig _cfg(MockLmStudioServer server) => AgentsCoreConfig(
  lmStudioBaseUrl: Uri.parse(server.baseUrl),
  logger: const SilentLogger(),
);

// ─────────────────────────────────────────────────────────────────────────────
// Realistic LM Studio payloads
// ─────────────────────────────────────────────────────────────────────────────

/// Minimal chat completion request body.
Map<String, dynamic> _chatRequest({
  String model = 'llama3',
  List<Map<String, dynamic>>? messages,
  double? temperature,
  int? maxTokens,
  bool? stream,
}) => {
  'model': model,
  'messages':
      messages ??
      [
        {'role': 'user', 'content': 'Hello'},
      ],
  'temperature': ?temperature,
  'max_tokens': ?maxTokens,
  'stream': ?stream,
};

/// A realistic non-streaming chat completion response.
Map<String, dynamic> _chatResponse({
  String id = 'chatcmpl-abc123',
  String content = 'Hello! How can I help you today?',
}) => {
  'id': id,
  'object': 'chat.completion',
  'created': 1677858242,
  'model': 'llama3',
  'usage': {'prompt_tokens': 13, 'completion_tokens': 7, 'total_tokens': 20},
  'choices': [
    {
      'message': {'role': 'assistant', 'content': content},
      'finish_reason': 'stop',
      'index': 0,
    },
  ],
};

/// A realistic LM Studio model-list response.
Map<String, dynamic> get _modelsResponse => {
  'object': 'list',
  'data': [
    {
      'id': 'llama3',
      'object': 'model',
      'created': 1677858242,
      'owned_by': 'user',
    },
    {
      'id': 'mistral-7b',
      'object': 'model',
      'created': 1677858200,
      'owned_by': 'user',
    },
  ],
};

/// LM Studio error body shape: `{"error": {"type": ..., "message": ...}}`.
Map<String, dynamic> _apiError(String type, String message) => {
  'error': {'type': type, 'message': message},
};

// ═══════════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  late MockLmStudioServer server;
  late LmStudioHttpClient client;

  setUp(() async {
    server = await MockLmStudioServer.start();
    client = LmStudioHttpClient(config: _cfg(server));
  });

  tearDown(() async {
    client.dispose();
    await server.close();
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 1. GET /v1/models — model listing
  // ───────────────────────────────────────────────────────────────────────────
  group('GET /v1/models — list models', () {
    setUp(() {
      server.enqueue(
        method: 'GET',
        path: '/v1/models',
        response: MockResponse.json(body: _modelsResponse),
      );
    });

    test('returns a Map<String, dynamic>', () async {
      final result = await client.get('/v1/models');
      expect(result, isA<Map<String, dynamic>>());
    });

    test('object field is "list"', () async {
      final result = await client.get('/v1/models');
      expect(result['object'], equals('list'));
    });

    test('data field contains two model entries', () async {
      final result = await client.get('/v1/models');
      expect((result['data'] as List).length, equals(2));
    });

    test('first model has id "llama3"', () async {
      final result = await client.get('/v1/models');
      final first = (result['data'] as List).first as Map<String, dynamic>;
      expect(first['id'], equals('llama3'));
    });

    test('server records the GET method', () async {
      await client.get('/v1/models');
      expect(server.requests.first.method, equals('GET'));
    });

    test('server records the correct path', () async {
      await client.get('/v1/models');
      expect(server.requests.first.path, equals('/v1/models'));
    });

    test('GET request body is empty', () async {
      await client.get('/v1/models');
      expect(server.requests.first.body, isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 2. POST /v1/chat/completions — chat completion
  // ───────────────────────────────────────────────────────────────────────────
  group('POST /v1/chat/completions — chat completion', () {
    setUp(() {
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: _chatResponse()),
      );
    });

    test('returns a Map<String, dynamic>', () async {
      final result = await client.post('/v1/chat/completions', _chatRequest());
      expect(result, isA<Map<String, dynamic>>());
    });

    test('id field matches response', () async {
      final result = await client.post('/v1/chat/completions', _chatRequest());
      expect(result['id'], equals('chatcmpl-abc123'));
    });

    test('choices contains one item', () async {
      final result = await client.post('/v1/chat/completions', _chatRequest());
      expect((result['choices'] as List).length, equals(1));
    });

    test('assistant message content is returned correctly', () async {
      final result = await client.post('/v1/chat/completions', _chatRequest());
      final message =
          (result['choices'] as List).first['message'] as Map<String, dynamic>;
      expect(message['role'], equals('assistant'));
      expect(message['content'], isA<String>());
      expect((message['content'] as String).isNotEmpty, isTrue);
    });

    test('server receives POST method', () async {
      await client.post('/v1/chat/completions', _chatRequest());
      expect(server.requests.first.method, equals('POST'));
    });

    test('server receives correct path', () async {
      await client.post('/v1/chat/completions', _chatRequest());
      expect(server.requests.first.path, equals('/v1/chat/completions'));
    });

    test('server receives model field in body', () async {
      await client.post('/v1/chat/completions', _chatRequest(model: 'llama3'));
      expect(server.requests.first.jsonBody['model'], equals('llama3'));
    });

    test('server receives messages field in body', () async {
      final messages = [
        {'role': 'system', 'content': 'You are a helpful assistant.'},
        {'role': 'user', 'content': 'What is 2+2?'},
      ];
      await client.post(
        '/v1/chat/completions',
        _chatRequest(messages: messages),
      );
      final body = server.requests.first.jsonBody;
      expect((body['messages'] as List).length, equals(2));
    });

    test('server receives temperature field when provided', () async {
      await client.post('/v1/chat/completions', _chatRequest(temperature: 0.7));
      expect(server.requests.first.jsonBody['temperature'], equals(0.7));
    });

    test('server receives max_tokens field when provided', () async {
      await client.post('/v1/chat/completions', _chatRequest(maxTokens: 256));
      expect(server.requests.first.jsonBody['max_tokens'], equals(256));
    });

    test('body is valid JSON parseable by server', () async {
      await client.post('/v1/chat/completions', _chatRequest());
      // If jsonBody doesn't throw, the body was valid JSON.
      expect(() => server.requests.first.jsonBody, returnsNormally);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3. Error responses — LM Studio error body format
  // ───────────────────────────────────────────────────────────────────────────
  group('Error responses with LM Studio error body format', () {
    for (final scenario in [
      (
        code: 404,
        type: 'model_not_found',
        message: 'The model llama4 was not found on this server',
      ),
      (
        code: 400,
        type: 'context_length_exceeded',
        message: 'This model maximum context length is 4096 tokens',
      ),
      (
        code: 429,
        type: 'rate_limit_exceeded',
        message: 'Too many requests — slow down',
      ),
      (
        code: 500,
        type: 'internal_server_error',
        message: 'An unexpected error occurred',
      ),
      (
        code: 503,
        type: 'service_unavailable',
        message: 'LM Studio is busy, try again later',
      ),
    ]) {
      group('HTTP ${scenario.code} (${scenario.type})', () {
        setUp(() {
          server.enqueue(
            response: MockResponse.error(
              statusCode: scenario.code,
              body: _apiError(scenario.type, scenario.message),
            ),
          );
        });

        test('POST throws LmStudioApiException', () async {
          await expectLater(
            () => client.post('/v1/chat/completions', {}),
            throwsA(isA<LmStudioApiException>()),
          );
        });

        test('exception statusCode is ${scenario.code}', () async {
          await expectLater(
            () => client.post('/v1/chat/completions', {}),
            throwsA(
              isA<LmStudioApiException>().having(
                (e) => e.statusCode,
                'statusCode',
                scenario.code,
              ),
            ),
          );
        });

        test('exception carries parsed LM Studio error fields', () async {
          LmStudioApiException? captured;
          try {
            await client.post('/v1/chat/completions', {});
          } on LmStudioApiException catch (e) {
            captured = e;
          }
          expect(captured, isNotNull);
          expect(captured!.errorType, equals(scenario.type));
          expect(captured.errorMessage, contains(scenario.message));
        });

        test(
          'GET also throws LmStudioApiException for ${scenario.code}',
          () async {
            // Re-enqueue for the GET test (tearDown/setUp won't re-enqueue).
            server.enqueue(
              response: MockResponse.error(
                statusCode: scenario.code,
                body: _apiError(scenario.type, scenario.message),
              ),
            );
            await expectLater(
              () => client.get('/v1/models'),
              throwsA(isA<LmStudioApiException>()),
            );
          },
        );
      });
    }
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 4. postStream — SSE round-trip
  // ───────────────────────────────────────────────────────────────────────────
  group('postStream — SSE streaming round-trip', () {
    test('returns a Stream of strings', () async {
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.sse(
          chunks: [
            {
              'choices': [
                {
                  'delta': {'content': 'Hello'},
                  'index': 0,
                },
              ],
            },
          ],
        ),
      );
      final stream = client.postStream(
        '/v1/chat/completions',
        _chatRequest(stream: true),
      );
      expect(stream, isA<Stream<String>>());
    });

    test('stream emits one element per SSE chunk', () async {
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.sse(
          chunks: [
            {'choices': []},
            {'choices': []},
            {'choices': []},
          ],
        ),
      );
      final events = await client
          .postStream('/v1/chat/completions', _chatRequest(stream: true))
          .toList();
      expect(events.length, equals(3));
    });

    test('stream data is parseable JSON', () async {
      const content = 'Hi there!';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.sse(
          chunks: [
            {
              'choices': [
                {
                  'delta': {'content': content},
                  'index': 0,
                },
              ],
            },
          ],
        ),
      );
      final events = await client
          .postStream('/v1/chat/completions', _chatRequest(stream: true))
          .toList();
      expect(events, hasLength(1));
      final parsed = json.decode(events.first) as Map<String, dynamic>;
      final choices = parsed['choices'] as List;
      final delta =
          (choices.first as Map<String, dynamic>)['delta']
              as Map<String, dynamic>;
      expect(delta['content'], equals(content));
    });

    test('stream terminates cleanly (does not hang) after [DONE]', () async {
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.sse(
          chunks: [
            {'choices': []},
            {'choices': []},
          ],
        ),
      );
      // If the stream doesn't terminate, this will hang.
      final events = await client
          .postStream('/v1/chat/completions', _chatRequest(stream: true))
          .toList();
      expect(events, hasLength(2));
    });

    test('postStream sends POST method to server', () async {
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.sse(chunks: []),
      );
      await client
          .postStream('/v1/chat/completions', _chatRequest(stream: true))
          .toList();
      expect(server.requests.first.method, equals('POST'));
    });

    test('postStream sends to correct path', () async {
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.sse(chunks: []),
      );
      await client
          .postStream('/v1/chat/completions', _chatRequest(stream: true))
          .toList();
      expect(server.requests.first.path, equals('/v1/chat/completions'));
    });

    test(
      'non-2xx response from postStream throws LmStudioApiException',
      () async {
        server.enqueue(
          response: MockResponse.error(
            statusCode: 503,
            body: _apiError('service_unavailable', 'Service busy'),
          ),
        );
        await expectLater(
          () => client
              .postStream('/v1/chat/completions', _chatRequest(stream: true))
              .toList(),
          throwsA(isA<LmStudioApiException>()),
        );
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 5. Multiple sequential requests via the same client
  // ───────────────────────────────────────────────────────────────────────────
  group('multiple sequential requests via the same client', () {
    test(
      'two sequential GETs both succeed and return distinct results',
      () async {
        server
          ..enqueue(
            method: 'GET',
            path: '/v1/models',
            response: MockResponse.json(body: {'index': 1}),
          )
          ..enqueue(
            method: 'GET',
            path: '/v1/models',
            response: MockResponse.json(body: {'index': 2}),
          );

        final first = await client.get('/v1/models');
        final second = await client.get('/v1/models');

        expect(first['index'], equals(1));
        expect(second['index'], equals(2));
      },
    );

    test('two sequential POSTs both succeed', () async {
      server
        ..enqueue(
          method: 'POST',
          path: '/v1/chat/completions',
          response: MockResponse.json(body: _chatResponse(id: 'cmpl-1')),
        )
        ..enqueue(
          method: 'POST',
          path: '/v1/chat/completions',
          response: MockResponse.json(body: _chatResponse(id: 'cmpl-2')),
        );

      final first = await client.post('/v1/chat/completions', _chatRequest());
      final second = await client.post('/v1/chat/completions', _chatRequest());

      expect(first['id'], equals('cmpl-1'));
      expect(second['id'], equals('cmpl-2'));
    });

    test('GET then POST then GET — all succeed in order', () async {
      server
        ..enqueue(
          method: 'GET',
          path: '/v1/models',
          response: MockResponse.json(body: {'step': 1}),
        )
        ..enqueue(
          method: 'POST',
          path: '/v1/chat/completions',
          response: MockResponse.json(body: {'step': 2}),
        )
        ..enqueue(
          method: 'GET',
          path: '/v1/models',
          response: MockResponse.json(body: {'step': 3}),
        );

      final r1 = await client.get('/v1/models');
      final r2 = await client.post('/v1/chat/completions', {});
      final r3 = await client.get('/v1/models');

      expect(r1['step'], equals(1));
      expect(r2['step'], equals(2));
      expect(r3['step'], equals(3));
    });

    test('server records all requests in arrival order', () async {
      server
        ..enqueue(
          method: 'GET',
          path: '/v1/models',
          response: MockResponse.json(body: {}),
        )
        ..enqueue(
          method: 'POST',
          path: '/v1/chat/completions',
          response: MockResponse.json(body: {}),
        );

      await client.get('/v1/models');
      await client.post('/v1/chat/completions', {});

      expect(server.requests, hasLength(2));
      expect(server.requests[0].method, equals('GET'));
      expect(server.requests[1].method, equals('POST'));
    });

    test('success then error — first returns result, second throws', () async {
      server
        ..enqueue(
          method: 'GET',
          path: '/v1/models',
          response: MockResponse.json(body: {'ok': true}),
        )
        ..enqueue(
          method: 'GET',
          path: '/v1/models',
          response: MockResponse.error(
            statusCode: 503,
            body: _apiError('service_unavailable', 'Down for maintenance'),
          ),
        );

      final success = await client.get('/v1/models');
      expect(success['ok'], isTrue);

      await expectLater(
        () => client.get('/v1/models'),
        throwsA(isA<LmStudioApiException>()),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 6. 2xx codes other than 200 do NOT throw
  // ───────────────────────────────────────────────────────────────────────────
  group('2xx status codes other than 200 do not throw', () {
    test('GET with 201 returns normally', () async {
      server.enqueue(
        method: 'GET',
        path: '/v1/models',
        response: MockResponse.json(statusCode: 201, body: {'ok': true}),
      );
      // Use `completes` (not `returnsNormally`) because get() is async —
      // `returnsNormally` only checks synchronous throws.
      await expectLater(client.get('/v1/models'), completes);
    });

    test('POST with 201 returns normally', () async {
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(statusCode: 201, body: {'ok': true}),
      );
      await expectLater(client.post('/v1/chat/completions', {}), completes);
    });

    test('GET with 204 returns normally', () async {
      server.enqueue(
        method: 'GET',
        path: '/v1/models',
        response: MockResponse.json(statusCode: 204, body: {'ok': true}),
      );
      await expectLater(client.get('/v1/models'), completes);
    });

    test('GET with 204 returns empty map', () async {
      server.enqueue(
        method: 'GET',
        path: '/v1/models',
        response: MockResponse.json(statusCode: 204, body: {'ok': true}),
      );
      final result = await client.get('/v1/models');
      expect(result, isA<Map<String, dynamic>>());
      expect(result, isEmpty);
    });

    test('POST with 204 returns normally', () async {
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(statusCode: 204, body: {'ok': true}),
      );
      await expectLater(client.post('/v1/chat/completions', {}), completes);
    });

    test('POST with 204 returns empty map', () async {
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(statusCode: 204, body: {'ok': true}),
      );
      final result = await client.post('/v1/chat/completions', {});
      expect(result, isA<Map<String, dynamic>>());
      expect(result, isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 7. Connection error wrapping — refused connection via bad URL
  // ───────────────────────────────────────────────────────────────────────────
  group('connection error wrapping — refused connection', () {
    // Use a port that nothing is listening on to reliably trigger SocketException.
    late int closedPort;

    setUp(() async {
      final s = await HttpServer.bind('127.0.0.1', 0);
      closedPort = s.port;
      await s.close(force: true);
    });

    test(
      'GET to a refused-connection host throws LmStudioConnectionException',
      () async {
        final badClient = LmStudioHttpClient(
          config: AgentsCoreConfig(
            lmStudioBaseUrl: Uri.parse('http://127.0.0.1:$closedPort'),
            logger: const SilentLogger(),
          ),
        );
        await expectLater(
          () => badClient.get('/v1/models'),
          throwsA(isA<LmStudioConnectionException>()),
        );
        badClient.dispose();
      },
    );

    test(
      'POST to a refused-connection host throws LmStudioConnectionException',
      () async {
        final badClient = LmStudioHttpClient(
          config: AgentsCoreConfig(
            lmStudioBaseUrl: Uri.parse('http://127.0.0.1:$closedPort'),
            logger: const SilentLogger(),
          ),
        );
        await expectLater(
          () => badClient.post('/v1/chat/completions', _chatRequest()),
          throwsA(isA<LmStudioConnectionException>()),
        );
        badClient.dispose();
      },
    );

    test('exception has isSocketError=true for refused connection', () async {
      final badClient = LmStudioHttpClient(
        config: AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse('http://127.0.0.1:$closedPort'),
          logger: const SilentLogger(),
        ),
      );
      await expectLater(
        () => badClient.get('/v1/models'),
        throwsA(
          isA<LmStudioConnectionException>().having(
            (e) => e.isSocketError,
            'isSocketError',
            isTrue,
          ),
        ),
      );
      badClient.dispose();
    });

    test('exception has isTimeout=false for refused connection', () async {
      final badClient = LmStudioHttpClient(
        config: AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse('http://127.0.0.1:$closedPort'),
          logger: const SilentLogger(),
        ),
      );
      await expectLater(
        () => badClient.get('/v1/models'),
        throwsA(
          isA<LmStudioConnectionException>().having(
            (e) => e.isTimeout,
            'isTimeout',
            isFalse,
          ),
        ),
      );
      badClient.dispose();
    });

    test('exception.cause is a SocketException', () async {
      final badClient = LmStudioHttpClient(
        config: AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse('http://127.0.0.1:$closedPort'),
          logger: const SilentLogger(),
        ),
      );
      LmStudioConnectionException? captured;
      try {
        await badClient.get('/v1/models');
      } on LmStudioConnectionException catch (e) {
        captured = e;
      }
      expect(captured?.cause, isA<SocketException>());
      badClient.dispose();
    });

    test('exception.message mentions the host', () async {
      final badClient = LmStudioHttpClient(
        config: AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse('http://127.0.0.1:$closedPort'),
          logger: const SilentLogger(),
        ),
      );
      LmStudioConnectionException? captured;
      try {
        await badClient.get('/v1/models');
      } on LmStudioConnectionException catch (e) {
        captured = e;
      }
      expect(captured?.message, isNotEmpty);
      expect(captured?.message, contains('127.0.0.1'));
      badClient.dispose();
    });

    test('exception.uri references the correct host and port', () async {
      final badClient = LmStudioHttpClient(
        config: AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse('http://127.0.0.1:$closedPort'),
          logger: const SilentLogger(),
        ),
      );
      LmStudioConnectionException? captured;
      try {
        await badClient.get('/v1/models');
      } on LmStudioConnectionException catch (e) {
        captured = e;
      }
      expect(captured?.uri.host, equals('127.0.0.1'));
      expect(captured?.uri.port, equals(closedPort));
      badClient.dispose();
    });

    test(
      'postStream also wraps SocketException into LmStudioConnectionException',
      () async {
        final badClient = LmStudioHttpClient(
          config: AgentsCoreConfig(
            lmStudioBaseUrl: Uri.parse('http://127.0.0.1:$closedPort'),
            logger: const SilentLogger(),
          ),
        );
        await expectLater(
          () => badClient
              .postStream('/v1/chat/completions', _chatRequest(stream: true))
              .toList(),
          throwsA(isA<LmStudioConnectionException>()),
        );
        badClient.dispose();
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 8. LmStudioHttpException field contracts
  // ───────────────────────────────────────────────────────────────────────────
  group('LmStudioApiException field contracts (thrown by client)', () {
    test('exception is thrown on GET error response', () async {
      server.enqueue(
        response: MockResponse.error(
          statusCode: 404,
          body: _apiError('model_not_found', 'Not found'),
        ),
      );
      LmStudioApiException? captured;
      try {
        await client.get('/v1/models');
      } on LmStudioApiException catch (e) {
        captured = e;
      }
      expect(captured, isNotNull);
      expect(captured!.statusCode, equals(404));
    });

    test('exception is thrown on POST error response', () async {
      server.enqueue(
        response: MockResponse.error(
          statusCode: 500,
          body: _apiError('internal_server_error', 'Server error'),
        ),
      );
      LmStudioApiException? captured;
      try {
        await client.post('/v1/chat/completions', {});
      } on LmStudioApiException catch (e) {
        captured = e;
      }
      expect(captured, isNotNull);
      expect(captured!.statusCode, equals(500));
    });

    test('exception.errorType is parsed from LM Studio error JSON', () async {
      server.enqueue(
        response: MockResponse.error(
          statusCode: 404,
          body: _apiError('not_found', 'Not found'),
        ),
      );
      LmStudioApiException? captured;
      try {
        await client.get('/v1/chat/completions');
      } on LmStudioApiException catch (e) {
        captured = e;
      }
      expect(captured?.errorType, equals('not_found'));
    });

    test(
      'exception.statusCode matches HTTP status returned by server',
      () async {
        server.enqueue(
          response: MockResponse.error(
            statusCode: 422,
            body: _apiError('unprocessable_entity', 'Invalid request body'),
          ),
        );
        LmStudioApiException? captured;
        try {
          await client.post('/v1/chat/completions', {});
        } on LmStudioApiException catch (e) {
          captured = e;
        }
        expect(captured?.statusCode, equals(422));
      },
    );

    test(
      'exception.errorMessage is parsed from LM Studio error JSON',
      () async {
        server.enqueue(
          response: MockResponse.error(
            statusCode: 400,
            body: _apiError('context_length_exceeded', 'Too many tokens'),
          ),
        );
        LmStudioApiException? captured;
        try {
          await client.post('/v1/chat/completions', _chatRequest());
        } on LmStudioApiException catch (e) {
          captured = e;
        }
        expect(captured, isNotNull);
        expect(captured!.errorType, equals('context_length_exceeded'));
        expect(captured.errorMessage, contains('Too many tokens'));
      },
    );

    test('exception.toString() is informative and non-empty', () async {
      server.enqueue(
        response: MockResponse.error(
          statusCode: 503,
          body: _apiError('service_unavailable', 'Down'),
        ),
      );
      LmStudioApiException? captured;
      try {
        await client.get('/v1/models');
      } on LmStudioApiException catch (e) {
        captured = e;
      }
      final str = captured?.toString() ?? '';
      expect(str, isNotEmpty);
      expect(str, contains('503'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 9. LmStudioConnectionException field contracts — isHttp/isSocket/isTimeout
  // ───────────────────────────────────────────────────────────────────────────
  group('LmStudioConnectionException field contracts', () {
    test('isSocketError=true when cause is SocketException', () {
      final exception = LmStudioConnectionException.socketError(
        uri: Uri.parse('http://localhost:1234'),
        cause: const SocketException('Connection refused'),
      );
      expect(exception.isSocketError, isTrue);
      expect(exception.isHttpError, isFalse);
      expect(exception.isTimeout, isFalse);
    });

    test('isHttpError=true when cause is HttpException', () {
      final exception = LmStudioConnectionException.httpError(
        uri: Uri.parse('http://localhost:1234'),
        cause: const HttpException('Bad request'),
      );
      expect(exception.isHttpError, isTrue);
      expect(exception.isSocketError, isFalse);
      expect(exception.isTimeout, isFalse);
    });

    test('isTimeout=true when cause is TimeoutException', () {
      final exception = LmStudioConnectionException.timeout(
        uri: Uri.parse('http://localhost:1234'),
        cause: TimeoutException('Timed out', const Duration(seconds: 30)),
      );
      expect(exception.isTimeout, isTrue);
      expect(exception.isSocketError, isFalse);
      expect(exception.isHttpError, isFalse);
    });

    test('fromException factory wraps SocketException', () {
      final exception = LmStudioConnectionException.fromException(
        uri: Uri.parse('http://localhost:1234'),
        exception: const SocketException('refused'),
      );
      expect(exception.isSocketError, isTrue);
      expect(exception.cause, isA<SocketException>());
    });

    test('fromException factory wraps HttpException', () {
      final exception = LmStudioConnectionException.fromException(
        uri: Uri.parse('http://localhost:1234'),
        exception: const HttpException('http error'),
      );
      expect(exception.isHttpError, isTrue);
      expect(exception.cause, isA<HttpException>());
    });

    test('fromException factory wraps TimeoutException', () {
      final exception = LmStudioConnectionException.fromException(
        uri: Uri.parse('http://localhost:1234'),
        exception: TimeoutException('timeout'),
      );
      expect(exception.isTimeout, isTrue);
      expect(exception.cause, isA<TimeoutException>());
    });

    test(
      'fromException factory wraps unknown exception with generic message',
      () {
        final unknownError = Exception('something weird happened');
        final exception = LmStudioConnectionException.fromException(
          uri: Uri.parse('http://localhost:1234'),
          exception: unknownError,
        );
        expect(exception.message, isNotEmpty);
        expect(exception.cause, equals(unknownError));
      },
    );

    test('socketError message mentions the host', () {
      const uri = 'http://my-lmstudio.local:1234';
      final exception = LmStudioConnectionException.socketError(
        uri: Uri.parse(uri),
        cause: const SocketException('refused'),
      );
      expect(exception.message, contains('my-lmstudio.local'));
    });

    test('timeout message includes duration when available', () {
      final exception = LmStudioConnectionException.timeout(
        uri: Uri.parse('http://localhost:1234'),
        cause: TimeoutException('timeout', const Duration(seconds: 60)),
      );
      // Duration is 60s — message should include "60s" or similar.
      expect(exception.message, contains('60'));
    });

    test('toString() starts with LmStudioConnectionException', () {
      final exception = LmStudioConnectionException.socketError(
        uri: Uri.parse('http://localhost:1234'),
        cause: const SocketException('refused'),
      );
      expect(exception.toString(), startsWith('LmStudioConnectionException'));
    });

    test('uri field matches the constructor argument', () {
      final uri = Uri.parse('http://my-server.local:5678');
      final exception = LmStudioConnectionException(message: 'Error', uri: uri);
      expect(exception.uri, equals(uri));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 10. LmStudioHttpException — contract (standalone construction)
  // ───────────────────────────────────────────────────────────────────────────
  group('LmStudioHttpException contract', () {
    test('can be constructed with all required fields', () {
      expect(
        () => LmStudioHttpException(
          statusCode: 404,
          body: '{"error":"not found"}',
          method: 'GET',
          path: '/v1/models',
        ),
        returnsNormally,
      );
    });

    test('statusCode field is stored correctly', () {
      final e = LmStudioHttpException(
        statusCode: 503,
        body: '{}',
        method: 'GET',
        path: '/v1/models',
      );
      expect(e.statusCode, equals(503));
    });

    test('body field is stored correctly', () {
      const body = '{"error":"server error"}';
      final e = LmStudioHttpException(
        statusCode: 500,
        body: body,
        method: 'POST',
        path: '/v1/chat/completions',
      );
      expect(e.body, equals(body));
    });

    test('method field is stored correctly', () {
      final e = LmStudioHttpException(
        statusCode: 422,
        body: '{}',
        method: 'POST',
        path: '/v1/chat/completions',
      );
      expect(e.method, equals('POST'));
    });

    test('path field is stored correctly', () {
      const path = '/v1/chat/completions';
      final e = LmStudioHttpException(
        statusCode: 400,
        body: '{}',
        method: 'POST',
        path: path,
      );
      expect(e.path, equals(path));
    });

    test('toString() includes method, path, and statusCode', () {
      final e = LmStudioHttpException(
        statusCode: 404,
        body: '{"error":"not found"}',
        method: 'GET',
        path: '/v1/models',
      );
      final str = e.toString();
      expect(str, contains('GET'));
      expect(str, contains('/v1/models'));
      expect(str, contains('404'));
    });

    test('implements Exception', () {
      final e = LmStudioHttpException(
        statusCode: 500,
        body: '{}',
        method: 'GET',
        path: '/v1/models',
      );
      expect(e, isA<Exception>());
    });

    test('can be caught as Exception', () {
      expect(
        () => throw LmStudioHttpException(
          statusCode: 500,
          body: '{}',
          method: 'GET',
          path: '/v1/models',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
