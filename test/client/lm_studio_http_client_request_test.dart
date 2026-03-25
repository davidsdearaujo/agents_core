import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Test server infrastructure
// ═══════════════════════════════════════════════════════════════════════════════

/// A captured HTTP request from the test server.
class _CapturedRequest {
  _CapturedRequest({
    required this.method,
    required this.path,
    required this.headers,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, List<String>> headers;
  final String body;

  /// Returns the first value of the given [header] name (case-insensitive).
  String? header(String name) {
    final key = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == key) {
        return entry.value.first;
      }
    }
    return null;
  }
}

/// A local test HTTP server that captures incoming requests and responds
/// with a configurable status code and JSON body.
class _CapturingServer {
  _CapturingServer._(this._server, this._requests);

  final HttpServer _server;
  final List<_CapturedRequest> _requests;

  int get port => _server.port;
  List<_CapturedRequest> get captured => List.unmodifiable(_requests);
  _CapturedRequest get last => _requests.last;

  Future<void> close() => _server.close(force: true);

  static Future<_CapturingServer> start({
    int statusCode = 200,
    Map<String, dynamic>? responseBody,
    /// Optional delay before responding — useful for timeout testing.
    Duration responseDelay = Duration.zero,
  }) async {
    final requests = <_CapturedRequest>[];
    final server = await HttpServer.bind('127.0.0.1', 0);

    server.listen((req) async {
      // Collect headers.
      final headers = <String, List<String>>{};
      req.headers.forEach((name, values) => headers[name] = values);

      // Read body (cast Uint8List → List<int> for utf8.decoder).
      final body = await utf8.decoder.bind(req.cast<List<int>>()).join();

      requests.add(_CapturedRequest(
        method: req.method,
        path: req.uri.path,
        headers: headers,
        body: body,
      ));

      if (responseDelay > Duration.zero) {
        await Future<void>.delayed(responseDelay);
      }

      req.response
        ..statusCode = statusCode
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(responseBody ?? {'ok': true}));
      await req.response.close();
    });

    return _CapturingServer._(server, requests);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════════

/// Creates an [AgentsCoreConfig] pointing at [baseUrl] with a silent logger.
AgentsCoreConfig _config(String baseUrl, {Duration? timeout}) =>
    AgentsCoreConfig(
      lmStudioBaseUrl: Uri.parse(baseUrl),
      requestTimeout: timeout ?? const Duration(seconds: 30),
      logger: const SilentLogger(),
    );

/// Binds a server, records its port, closes it immediately, then returns the
/// port. Connecting to this port will raise a [SocketException] reliably.
Future<int> _closedPort() async {
  final s = await HttpServer.bind('127.0.0.1', 0);
  final port = s.port;
  await s.close(force: true);
  return port;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // 1. Construction
  // ───────────────────────────────────────────────────────────────────────────
  group('LmStudioHttpClient — construction', () {
    test('can be instantiated with an AgentsCoreConfig', () {
      expect(
        () => LmStudioHttpClient(
          config: _config('http://localhost:1234'),
        ),
        returnsNormally,
      );
    });

    test('dispose() does not throw', () {
      final client = LmStudioHttpClient(config: _config('http://localhost:1234'));
      expect(client.dispose, returnsNormally);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 2. GET — request construction
  // ───────────────────────────────────────────────────────────────────────────
  group('LmStudioHttpClient — GET request construction', () {
    late _CapturingServer server;
    late LmStudioHttpClient client;

    setUp(() async {
      server = await _CapturingServer.start();
      client = LmStudioHttpClient(
        config: _config('http://127.0.0.1:${server.port}'),
      );
    });

    tearDown(() async {
      client.dispose();
      await server.close();
    });

    test('sends HTTP GET method', () async {
      await client.get('/v1/models');
      expect(server.last.method, equals('GET'));
    });

    test('sends to the correct path', () async {
      await client.get('/v1/models');
      expect(server.last.path, equals('/v1/models'));
    });

    test('sends Accept: application/json header', () async {
      await client.get('/v1/models');
      expect(
        server.last.header('accept'),
        contains('application/json'),
      );
    });

    test('sends Content-Type: application/json header', () async {
      await client.get('/v1/models');
      expect(
        server.last.header('content-type'),
        contains('application/json'),
      );
    });

    test('path is resolved relative to configured baseUrl', () async {
      await client.get('/v1/chat/completions');
      expect(server.last.path, equals('/v1/chat/completions'));
    });

    test('GET sends no request body', () async {
      await client.get('/v1/models');
      // Body should be empty for a GET request.
      expect(server.last.body, isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3. POST — request construction
  // ───────────────────────────────────────────────────────────────────────────
  group('LmStudioHttpClient — POST request construction', () {
    late _CapturingServer server;
    late LmStudioHttpClient client;

    setUp(() async {
      server = await _CapturingServer.start();
      client = LmStudioHttpClient(
        config: _config('http://127.0.0.1:${server.port}'),
      );
    });

    tearDown(() async {
      client.dispose();
      await server.close();
    });

    test('sends HTTP POST method', () async {
      await client.post('/v1/chat/completions', {'model': 'llama3'});
      expect(server.last.method, equals('POST'));
    });

    test('sends to the correct path', () async {
      await client.post('/v1/chat/completions', {'model': 'llama3'});
      expect(server.last.path, equals('/v1/chat/completions'));
    });

    test('sends Content-Type: application/json header', () async {
      await client.post('/v1/chat/completions', {'model': 'llama3'});
      expect(
        server.last.header('content-type'),
        contains('application/json'),
      );
    });

    test('sends Accept: application/json header', () async {
      await client.post('/v1/chat/completions', {'model': 'llama3'});
      expect(
        server.last.header('accept'),
        contains('application/json'),
      );
    });

    test('encodes body as valid JSON', () async {
      await client.post('/v1/chat/completions', {'model': 'llama3'});
      final decoded = jsonDecode(server.last.body) as Map<String, dynamic>;
      expect(decoded, equals({'model': 'llama3'}));
    });

    test('encodes nested body fields correctly', () async {
      await client.post('/v1/chat/completions', {
        'model': 'llama3',
        'messages': [
          {'role': 'user', 'content': 'Hello'},
        ],
        'temperature': 0.7,
        'max_tokens': 512,
      });

      final decoded = jsonDecode(server.last.body) as Map<String, dynamic>;
      expect(decoded['model'], equals('llama3'));
      expect((decoded['messages'] as List).length, equals(1));
      expect(decoded['temperature'], equals(0.7));
      expect(decoded['max_tokens'], equals(512));
    });

    test('encodes empty body as empty JSON object {}', () async {
      await client.post('/v1/chat/completions', {});
      final decoded = jsonDecode(server.last.body) as Map<String, dynamic>;
      expect(decoded, isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 4. GET — happy-path response parsing
  // ───────────────────────────────────────────────────────────────────────────
  group('LmStudioHttpClient — GET happy-path response parsing', () {
    test('returns decoded JSON map on 200', () async {
      final server = await _CapturingServer.start(
        responseBody: {
          'object': 'list',
          'data': [
            {'id': 'llama3', 'object': 'model'},
          ],
        },
      );
      final client =
          LmStudioHttpClient(config: _config('http://127.0.0.1:${server.port}'));

      final result = await client.get('/v1/models');

      expect(result['object'], equals('list'));
      expect((result['data'] as List).length, equals(1));
      expect((result['data'] as List).first['id'], equals('llama3'));

      client.dispose();
      await server.close();
    });

    test('returns a Map<String, dynamic>', () async {
      final server = await _CapturingServer.start(
        responseBody: {'ok': true},
      );
      final client =
          LmStudioHttpClient(config: _config('http://127.0.0.1:${server.port}'));

      final result = await client.get('/v1/models');
      expect(result, isA<Map<String, dynamic>>());

      client.dispose();
      await server.close();
    });

    test('does NOT throw on 200', () async {
      final server = await _CapturingServer.start(statusCode: 200);
      final client =
          LmStudioHttpClient(config: _config('http://127.0.0.1:${server.port}'));

      // Use `completes` (not `returnsNormally`) because the method is async
      // and `returnsNormally` only checks synchronous returns.
      await expectLater(client.get('/v1/models'), completes);

      client.dispose();
      await server.close();
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 5. POST — happy-path response parsing
  // ───────────────────────────────────────────────────────────────────────────
  group('LmStudioHttpClient — POST happy-path response parsing', () {
    test('returns decoded JSON map on 200', () async {
      final server = await _CapturingServer.start(
        responseBody: {
          'id': 'cmpl-abc',
          'object': 'chat.completion',
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'Hi!'},
              'finish_reason': 'stop',
              'index': 0,
            }
          ],
        },
      );
      final client =
          LmStudioHttpClient(config: _config('http://127.0.0.1:${server.port}'));

      final result = await client.post('/v1/chat/completions', {
        'model': 'llama3',
        'messages': [
          {'role': 'user', 'content': 'Hello'},
        ],
      });

      expect(result['id'], equals('cmpl-abc'));
      expect(result['object'], equals('chat.completion'));
      expect((result['choices'] as List).length, equals(1));

      client.dispose();
      await server.close();
    });

    test('does NOT throw on 200', () async {
      final server = await _CapturingServer.start(statusCode: 200);
      final client =
          LmStudioHttpClient(config: _config('http://127.0.0.1:${server.port}'));

      // Use `completes` (not `returnsNormally`) because the method is async.
      await expectLater(
        client.post('/v1/chat/completions', {}),
        completes,
      );

      client.dispose();
      await server.close();
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 6. Non-2xx — LmStudioApiException wrapping
  // ───────────────────────────────────────────────────────────────────────────
  group('LmStudioHttpClient — non-2xx throws LmStudioApiException', () {
    for (final statusCode in [400, 401, 403, 404, 422, 500, 502, 503]) {
      group('HTTP $statusCode', () {
        late _CapturingServer server;
        late LmStudioHttpClient client;

        setUp(() async {
          server = await _CapturingServer.start(
            statusCode: statusCode,
            responseBody: {'error': 'simulated error for $statusCode'},
          );
          client =
              LmStudioHttpClient(config: _config('http://127.0.0.1:${server.port}'));
        });

        tearDown(() async {
          client.dispose();
          await server.close();
        });

        test('GET $statusCode throws LmStudioApiException', () async {
          await expectLater(
            () => client.get('/v1/models'),
            throwsA(isA<LmStudioApiException>()),
          );
        });

        test('GET $statusCode exception carries statusCode=$statusCode',
            () async {
          await expectLater(
            () => client.get('/v1/models'),
            throwsA(
              isA<LmStudioApiException>()
                  .having((e) => e.statusCode, 'statusCode', statusCode),
            ),
          );
        });

        test('POST $statusCode throws LmStudioApiException', () async {
          await expectLater(
            () => client.post('/v1/chat/completions', {}),
            throwsA(isA<LmStudioApiException>()),
          );
        });
      });
    }

    test('GET exception carries correct statusCode', () async {
      final server = await _CapturingServer.start(statusCode: 404);
      final client =
          LmStudioHttpClient(config: _config('http://127.0.0.1:${server.port}'));

      LmStudioApiException? captured;
      try {
        await client.get('/v1/models');
      } on LmStudioApiException catch (e) {
        captured = e;
      }

      expect(captured, isNotNull);
      expect(captured!.statusCode, equals(404));
      client.dispose();
      await server.close();
    });

    test('POST exception carries correct statusCode', () async {
      final server = await _CapturingServer.start(statusCode: 500);
      final client =
          LmStudioHttpClient(config: _config('http://127.0.0.1:${server.port}'));

      LmStudioApiException? captured;
      try {
        await client.post('/v1/chat/completions', {});
      } on LmStudioApiException catch (e) {
        captured = e;
      }

      expect(captured, isNotNull);
      expect(captured!.statusCode, equals(500));
      client.dispose();
      await server.close();
    });

    test('exception parses errorMessage from structured error body', () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((req) async {
        await req.drain<void>();
        req.response
          ..statusCode = 404
          ..headers.contentType = ContentType.json
          ..write('{"error":{"type":"not_found","message":"model not loaded"}}');
        await req.response.close();
      });

      final client =
          LmStudioHttpClient(config: _config('http://127.0.0.1:${server.port}'));

      LmStudioApiException? captured;
      try {
        await client.get('/v1/models');
      } on LmStudioApiException catch (e) {
        captured = e;
      }

      expect(captured, isNotNull);
      expect(captured!.statusCode, equals(404));
      expect(captured.errorType, equals('not_found'));
      expect(captured.errorMessage, equals('model not loaded'));
      client.dispose();
      await server.close(force: true);
    });

    test('exception falls back to empty strings for malformed error body',
        () async {
      final server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((req) async {
        await req.drain<void>();
        req.response
          ..statusCode = 500
          ..headers.contentType = ContentType.json
          ..write('not valid json');
        await req.response.close();
      });

      final client =
          LmStudioHttpClient(config: _config('http://127.0.0.1:${server.port}'));

      LmStudioApiException? captured;
      try {
        await client.get('/v1/models');
      } on LmStudioApiException catch (e) {
        captured = e;
      }

      expect(captured, isNotNull);
      expect(captured!.statusCode, equals(500));
      expect(captured.errorType, isEmpty);
      expect(captured.errorMessage, isEmpty);
      client.dispose();
      await server.close(force: true);
    });

    test('exception toString includes statusCode', () async {
      final server = await _CapturingServer.start(statusCode: 500);
      final client =
          LmStudioHttpClient(config: _config('http://127.0.0.1:${server.port}'));

      LmStudioApiException? captured;
      try {
        await client.get('/v1/models');
      } on LmStudioApiException catch (e) {
        captured = e;
      }

      final str = captured?.toString() ?? '';
      expect(str, contains('500'));

      client.dispose();
      await server.close();
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 7. Connection errors — LmStudioConnectionException wrapping
  // ───────────────────────────────────────────────────────────────────────────
  group('LmStudioHttpClient — connection errors → LmStudioConnectionException',
      () {
    test('GET on refused-connection port throws LmStudioConnectionException',
        () async {
      final port = await _closedPort();
      final client = LmStudioHttpClient(config: _config('http://127.0.0.1:$port'));

      await expectLater(
        () => client.get('/v1/models'),
        throwsA(isA<LmStudioConnectionException>()),
      );
      client.dispose();
    });

    test('POST on refused-connection port throws LmStudioConnectionException',
        () async {
      final port = await _closedPort();
      final client = LmStudioHttpClient(config: _config('http://127.0.0.1:$port'));

      await expectLater(
        () => client.post('/v1/chat/completions', {}),
        throwsA(isA<LmStudioConnectionException>()),
      );
      client.dispose();
    });

    test(
        'LmStudioConnectionException from SocketException has isSocketError=true',
        () async {
      final port = await _closedPort();
      final client = LmStudioHttpClient(config: _config('http://127.0.0.1:$port'));

      await expectLater(
        () => client.get('/v1/models'),
        throwsA(
          isA<LmStudioConnectionException>()
              .having((e) => e.isSocketError, 'isSocketError', isTrue),
        ),
      );
      client.dispose();
    });

    test(
        'LmStudioConnectionException from SocketException has isTimeout=false',
        () async {
      final port = await _closedPort();
      final client = LmStudioHttpClient(config: _config('http://127.0.0.1:$port'));

      await expectLater(
        () => client.get('/v1/models'),
        throwsA(
          isA<LmStudioConnectionException>()
              .having((e) => e.isTimeout, 'isTimeout', isFalse),
        ),
      );
      client.dispose();
    });

    test(
        'LmStudioConnectionException wraps the underlying cause (non-null)',
        () async {
      final port = await _closedPort();
      final client = LmStudioHttpClient(config: _config('http://127.0.0.1:$port'));

      LmStudioConnectionException? captured;
      try {
        await client.get('/v1/models');
      } on LmStudioConnectionException catch (e) {
        captured = e;
      }

      expect(captured?.cause, isNotNull);
      expect(captured?.cause, isA<SocketException>());
      client.dispose();
    });

    test('LmStudioConnectionException carries a non-empty message', () async {
      final port = await _closedPort();
      final client = LmStudioHttpClient(config: _config('http://127.0.0.1:$port'));

      LmStudioConnectionException? captured;
      try {
        await client.get('/v1/models');
      } on LmStudioConnectionException catch (e) {
        captured = e;
      }

      expect(captured?.message, isNotEmpty);
      client.dispose();
    });

    test('LmStudioConnectionException.toString() is non-empty', () async {
      final port = await _closedPort();
      final client = LmStudioHttpClient(config: _config('http://127.0.0.1:$port'));

      LmStudioConnectionException? captured;
      try {
        await client.get('/v1/models');
      } on LmStudioConnectionException catch (e) {
        captured = e;
      }

      expect(captured?.toString(), isNotEmpty);
      expect(captured?.toString(), contains('LmStudioConnectionException'));
      client.dispose();
    });

    test('LmStudioConnectionException carries the target URI', () async {
      final port = await _closedPort();
      final client = LmStudioHttpClient(config: _config('http://127.0.0.1:$port'));

      LmStudioConnectionException? captured;
      try {
        await client.get('/v1/models');
      } on LmStudioConnectionException catch (e) {
        captured = e;
      }

      // The URI in the exception should reference the host/port used.
      expect(captured?.uri.host, equals('127.0.0.1'));
      expect(captured?.uri.port, equals(port));
      client.dispose();
    });

    // NOTE: TimeoutException wrapping cannot be tested reliably with a real
    // localhost server because `HttpClient.connectionTimeout` only covers the
    // TCP handshake phase. On 127.0.0.1 the handshake completes in <1 ms
    // regardless of the configured timeout.
    //
    // The `LmStudioConnectionException.timeout(...)` factory and the
    // `isTimeout` getter are tested in the retry test suite
    // (test/client/lm_studio_http_client_retry_test.dart) via an injectable
    // `httpSend` parameter that can throw a `TimeoutException` directly.
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 8. postStream — request construction
  // ───────────────────────────────────────────────────────────────────────────
  group('LmStudioHttpClient — postStream request construction', () {
    test('sends HTTP POST method', () async {
      final server = await _CapturingServer.start(
        responseBody: {'object': 'text_completion'},
      );
      final client =
          LmStudioHttpClient(config: _config('http://127.0.0.1:${server.port}'));

      // postStream returns a Stream; consume it to ensure the request is sent.
      await client
          .postStream('/v1/completions', {'model': 'llama3', 'stream': true})
          .toList();

      expect(server.last.method, equals('POST'));

      client.dispose();
      await server.close();
    });

    test('sends to the correct path', () async {
      final server = await _CapturingServer.start();
      final client =
          LmStudioHttpClient(config: _config('http://127.0.0.1:${server.port}'));

      await client
          .postStream(
            '/v1/completions',
            {'model': 'llama3', 'stream': true},
          )
          .toList();

      expect(server.last.path, equals('/v1/completions'));

      client.dispose();
      await server.close();
    });

    test('non-2xx from postStream throws LmStudioApiException', () async {
      final server = await _CapturingServer.start(
        statusCode: 500,
        responseBody: {'error': 'server error'},
      );
      final client =
          LmStudioHttpClient(config: _config('http://127.0.0.1:${server.port}'));

      await expectLater(
        () => client
            .postStream('/v1/completions', {'stream': true})
            .toList(),
        throwsA(isA<LmStudioApiException>()),
      );

      client.dispose();
      await server.close();
    });

    test('postStream on refused port throws LmStudioConnectionException',
        () async {
      final port = await _closedPort();
      final client = LmStudioHttpClient(config: _config('http://127.0.0.1:$port'));

      await expectLater(
        () => client.postStream('/v1/completions', {'stream': true}).toList(),
        throwsA(isA<LmStudioConnectionException>()),
      );
      client.dispose();
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 9. URL resolution edge cases
  // ───────────────────────────────────────────────────────────────────────────
  group('LmStudioHttpClient — URL resolution', () {
    test('baseUrl with trailing slash resolves path correctly', () async {
      final server = await _CapturingServer.start();
      // baseUrl WITH trailing slash — Uri.resolve should still produce /v1/models
      final client = LmStudioHttpClient(
        config: _config('http://127.0.0.1:${server.port}/'),
      );

      await client.get('/v1/models');
      expect(server.last.path, equals('/v1/models'));

      client.dispose();
      await server.close();
    });

    test('different paths hit the correct endpoint', () async {
      const paths = [
        '/v1/models',
        '/v1/chat/completions',
        '/v1/completions',
        '/v1/embeddings',
      ];

      for (final path in paths) {
        final server = await _CapturingServer.start();
        final client =
            LmStudioHttpClient(config: _config('http://127.0.0.1:${server.port}'));

        await client.get(path);
        expect(server.last.path, equals(path),
            reason: 'Expected path $path to be sent');

        client.dispose();
        await server.close();
      }
    });
  });
}
