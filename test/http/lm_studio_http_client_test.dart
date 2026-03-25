import 'dart:convert';
import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helper: spin up a one-shot local HTTP server that responds with a fixed
// status code and JSON body, then closes.
// ---------------------------------------------------------------------------

/// Starts a bound [HttpServer] on a random port and wires it to respond to
/// every incoming request with [statusCode] and [responseBody] as JSON.
///
/// Returns a [_TestServer] that exposes the port and a teardown handle.
Future<_TestServer> _startServer(
  int statusCode,
  Map<String, dynamic> responseBody,
) async {
  final server = await HttpServer.bind('127.0.0.1', 0);
  server.listen((request) async {
    // Drain the request body (needed before writing the response).
    await request.drain<void>();
    request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(responseBody));
    await request.response.close();
  });
  return _TestServer(server);
}

class _TestServer {
  _TestServer(this._server);
  final HttpServer _server;
  int get port => _server.port;
  Future<void> close() => _server.close(force: true);
}

// ---------------------------------------------------------------------------
// LM Studio error response shapes
// ---------------------------------------------------------------------------

/// Builds a typical LM Studio API error body for a given [type] and [message].
Map<String, dynamic> _apiError(String type, String message) => {
      'error': {
        'type': type,
        'message': message,
      },
    };

/// Builds an LM Studio success body (e.g. minimal chat completion).
Map<String, dynamic> get _successBody => {
      'id': 'cmpl-123',
      'object': 'chat.completion',
      'choices': [
        {
          'message': {'role': 'assistant', 'content': 'Hello!'},
          'finish_reason': 'stop',
          'index': 0,
        }
      ],
    };

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('LmStudioHttpClient — non-2xx response handling', () {
    // -----------------------------------------------------------------------
    // 404 — model not found
    // -----------------------------------------------------------------------
    group('404 response', () {
      late _TestServer testServer;
      late LmStudioHttpClient client;

      setUp(() async {
        testServer = await _startServer(
          404,
          _apiError('model_not_found', 'The requested model was not found'),
        );
        client = LmStudioHttpClient(
          baseUrl: 'http://127.0.0.1:${testServer.port}',
        );
      });

      tearDown(() => testServer.close());

      test('throws LmStudioApiException', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(isA<LmStudioApiException>()),
        );
      });

      test('thrown exception has statusCode 404', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(
            isA<LmStudioApiException>()
                .having((e) => e.statusCode, 'statusCode', 404),
          ),
        );
      });

      test('thrown exception has isModelNotFound=true', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(
            isA<LmStudioApiException>()
                .having((e) => e.isModelNotFound, 'isModelNotFound', isTrue),
          ),
        );
      });

      test('thrown exception carries errorType from response', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(
            isA<LmStudioApiException>().having(
              (e) => e.errorType,
              'errorType',
              'model_not_found',
            ),
          ),
        );
      });

      test('thrown exception carries errorMessage from response', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(
            isA<LmStudioApiException>().having(
              (e) => e.errorMessage,
              'errorMessage',
              'The requested model was not found',
            ),
          ),
        );
      });

      test('thrown exception is also an AgentsCoreException', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(isA<AgentsCoreException>()),
        );
      });
    });

    // -----------------------------------------------------------------------
    // 400 — context length exceeded (bad request)
    // -----------------------------------------------------------------------
    group('400 response', () {
      late _TestServer testServer;
      late LmStudioHttpClient client;

      setUp(() async {
        testServer = await _startServer(
          400,
          _apiError(
            'context_length_exceeded',
            'This model maximum context length is 4096 tokens',
          ),
        );
        client = LmStudioHttpClient(
          baseUrl: 'http://127.0.0.1:${testServer.port}',
        );
      });

      tearDown(() => testServer.close());

      test('throws LmStudioApiException', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(isA<LmStudioApiException>()),
        );
      });

      test('thrown exception has statusCode 400', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(
            isA<LmStudioApiException>()
                .having((e) => e.statusCode, 'statusCode', 400),
          ),
        );
      });

      test('thrown exception has isContextLengthExceeded=true', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(
            isA<LmStudioApiException>().having(
              (e) => e.isContextLengthExceeded,
              'isContextLengthExceeded',
              isTrue,
            ),
          ),
        );
      });

      test('thrown exception has isModelNotFound=false', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(
            isA<LmStudioApiException>()
                .having((e) => e.isModelNotFound, 'isModelNotFound', isFalse),
          ),
        );
      });

      test('thrown exception has isRateLimited=false', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(
            isA<LmStudioApiException>()
                .having((e) => e.isRateLimited, 'isRateLimited', isFalse),
          ),
        );
      });
    });

    // -----------------------------------------------------------------------
    // 429 — rate limited
    // -----------------------------------------------------------------------
    group('429 response', () {
      late _TestServer testServer;
      late LmStudioHttpClient client;

      setUp(() async {
        testServer = await _startServer(
          429,
          _apiError('rate_limit_exceeded', 'Too many requests'),
        );
        client = LmStudioHttpClient(
          baseUrl: 'http://127.0.0.1:${testServer.port}',
        );
      });

      tearDown(() => testServer.close());

      test('throws LmStudioApiException', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(isA<LmStudioApiException>()),
        );
      });

      test('thrown exception has statusCode 429', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(
            isA<LmStudioApiException>()
                .having((e) => e.statusCode, 'statusCode', 429),
          ),
        );
      });

      test('thrown exception has isRateLimited=true', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(
            isA<LmStudioApiException>()
                .having((e) => e.isRateLimited, 'isRateLimited', isTrue),
          ),
        );
      });

      test('thrown exception has isModelNotFound=false', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(
            isA<LmStudioApiException>()
                .having((e) => e.isModelNotFound, 'isModelNotFound', isFalse),
          ),
        );
      });

      test('thrown exception has isContextLengthExceeded=false', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(
            isA<LmStudioApiException>().having(
              (e) => e.isContextLengthExceeded,
              'isContextLengthExceeded',
              isFalse,
            ),
          ),
        );
      });
    });

    // -----------------------------------------------------------------------
    // 500 — internal server error
    // -----------------------------------------------------------------------
    group('500 response', () {
      late _TestServer testServer;
      late LmStudioHttpClient client;

      setUp(() async {
        testServer = await _startServer(
          500,
          _apiError('internal_server_error', 'An unexpected error occurred'),
        );
        client = LmStudioHttpClient(
          baseUrl: 'http://127.0.0.1:${testServer.port}',
        );
      });

      tearDown(() => testServer.close());

      test('throws LmStudioApiException', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(isA<LmStudioApiException>()),
        );
      });

      test('thrown exception has statusCode 500', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(
            isA<LmStudioApiException>()
                .having((e) => e.statusCode, 'statusCode', 500),
          ),
        );
      });

      test('no convenience getters are true for 500', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(
            isA<LmStudioApiException>()
                .having((e) => e.isModelNotFound, 'isModelNotFound', isFalse)
                .having(
                  (e) => e.isContextLengthExceeded,
                  'isContextLengthExceeded',
                  isFalse,
                )
                .having((e) => e.isRateLimited, 'isRateLimited', isFalse),
          ),
        );
      });
    });

    // -----------------------------------------------------------------------
    // 503 — service unavailable
    // -----------------------------------------------------------------------
    group('503 response', () {
      late _TestServer testServer;
      late LmStudioHttpClient client;

      setUp(() async {
        testServer = await _startServer(
          503,
          _apiError('service_unavailable', 'Service temporarily unavailable'),
        );
        client = LmStudioHttpClient(
          baseUrl: 'http://127.0.0.1:${testServer.port}',
        );
      });

      tearDown(() => testServer.close());

      test('throws LmStudioApiException', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(isA<LmStudioApiException>()),
        );
      });

      test('thrown exception has statusCode 503', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(
            isA<LmStudioApiException>()
                .having((e) => e.statusCode, 'statusCode', 503),
          ),
        );
      });
    });

    // -----------------------------------------------------------------------
    // 401 — unauthorized
    // -----------------------------------------------------------------------
    group('401 response', () {
      late _TestServer testServer;
      late LmStudioHttpClient client;

      setUp(() async {
        testServer = await _startServer(
          401,
          _apiError('unauthorized', 'Unauthorized access'),
        );
        client = LmStudioHttpClient(
          baseUrl: 'http://127.0.0.1:${testServer.port}',
        );
      });

      tearDown(() => testServer.close());

      test('throws LmStudioApiException for 401', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(isA<LmStudioApiException>()),
        );
      });

      test('thrown exception has statusCode 401', () async {
        await expectLater(
          () => client.post('/v1/chat/completions', {}),
          throwsA(
            isA<LmStudioApiException>()
                .having((e) => e.statusCode, 'statusCode', 401),
          ),
        );
      });
    });

    // -----------------------------------------------------------------------
    // 2xx — should NOT throw
    // -----------------------------------------------------------------------
    group('2xx response — success (no exception)', () {
      late _TestServer testServer;
      late LmStudioHttpClient client;

      setUp(() async {
        testServer = await _startServer(200, _successBody);
        client = LmStudioHttpClient(
          baseUrl: 'http://127.0.0.1:${testServer.port}',
        );
      });

      tearDown(() => testServer.close());

      test('does NOT throw on 200 response', () async {
        // Use `completes` (not `returnsNormally`) because post() is async —
        // `returnsNormally` only checks synchronous throws.
        await expectLater(
          client.post('/v1/chat/completions', {}),
          completes,
        );
      });

      test('returns a Map on 200 response', () async {
        final result = await client.post('/v1/chat/completions', {});
        expect(result, isA<Map<String, dynamic>>());
      });

      test('returned Map contains expected keys from response', () async {
        final result = await client.post('/v1/chat/completions', {});
        expect(result, contains('id'));
        expect(result, contains('choices'));
      });
    });

    // -----------------------------------------------------------------------
    // GET method — non-2xx
    // -----------------------------------------------------------------------
    group('GET — non-2xx response', () {
      late _TestServer testServer;
      late LmStudioHttpClient client;

      setUp(() async {
        testServer = await _startServer(
          404,
          _apiError('not_found', 'Resource not found'),
        );
        client = LmStudioHttpClient(
          baseUrl: 'http://127.0.0.1:${testServer.port}',
        );
      });

      tearDown(() => testServer.close());

      test('get() throws LmStudioApiException on 404', () async {
        await expectLater(
          () => client.get('/v1/models'),
          throwsA(isA<LmStudioApiException>()),
        );
      });

      test('get() thrown exception has statusCode 404', () async {
        await expectLater(
          () => client.get('/v1/models'),
          throwsA(
            isA<LmStudioApiException>()
                .having((e) => e.statusCode, 'statusCode', 404),
          ),
        );
      });
    });
  });
}
