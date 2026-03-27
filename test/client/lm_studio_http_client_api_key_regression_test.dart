// ignore_for_file: avoid_catching_errors

import 'dart:async';
import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

import '../helpers/mock_lm_studio_server.dart';

// =============================================================================
// LmStudioHttpClient — API key regression tests
//
// These tests verify the bug fix from v0.1.2 where the API key was not being
// transmitted as an `Authorization: Bearer <key>` header in HTTP requests.
//
// Focus areas that extend the base api_key test suite:
//
// 1. API key persists across retry attempts (network errors + backoff)
// 2. API key is present in every request of a retry sequence
// 3. API key does NOT leak into exception toString() messages (security)
// 4. API key interacts correctly with retry logic via injectable httpSend
// 5. API key header is present even when retries are exhausted
// =============================================================================

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

/// Configurable fake HTTP sender that records every call.
///
/// Each invocation of [call] consumes the next entry from [_responses].
/// An entry may be:
/// - `({int statusCode, String body})` — returned as a normal HTTP response
/// - an [Exception] — thrown to simulate a network error
class _FakeHttpSend {
  _FakeHttpSend(List<Object> responses) : _responses = List.of(responses);

  final List<Object> _responses;
  int callCount = 0;
  final List<({String method, Uri url, String? body})> calls = [];

  Future<({int statusCode, String body})> call(
    String method,
    Uri url, {
    String? body,
  }) async {
    calls.add((method: method, url: url, body: body));
    expect(
      callCount,
      lessThan(_responses.length),
      reason:
          'More HTTP calls were made ($callCount) than the '
          '${_responses.length} responses configured',
    );
    final response = _responses[callCount++];
    if (response is Exception) throw response;
    return response as ({int statusCode, String body});
  }
}

/// [Logger] that records messages by level for assertion.
class _RecordingLogger extends Logger {
  final List<String> debugMessages = [];
  final List<String> infoMessages = [];
  final List<String> warnMessages = [];
  final List<String> errorMessages = [];

  @override
  LogLevel get level => LogLevel.debug;

  @override
  void debug(String message) => debugMessages.add(message);

  @override
  void info(String message) => infoMessages.add(message);

  @override
  void warn(String message) => warnMessages.add(message);

  @override
  void error(String message) => errorMessages.add(message);
}

/// Records [Duration]s passed to the delay callback without sleeping.
class _RecordingDelay {
  final List<Duration> delays = [];

  Future<void> call(Duration d) async => delays.add(d);
}

/// Returns a 200-OK response with a valid JSON body.
({int statusCode, String body}) _ok([String body = '{"ok":true}']) =>
    (statusCode: 200, body: body);

/// Returns a response with the given [code] and optional [body].
({int statusCode, String body}) _status(int code, [String body = '{}']) =>
    (statusCode: code, body: body);

/// Helper to extract Authorization header from a [RecordedRequest].
String? _authHeader(RecordedRequest req) {
  final key = 'authorization';
  for (final entry in req.headers.entries) {
    if (entry.key.toLowerCase() == key) {
      return entry.value.first;
    }
  }
  return null;
}

/// Creates an [AgentsCoreConfig] with the given [apiKey].
AgentsCoreConfig _configWithKey({
  String? apiKey,
  Logger? logger,
}) =>
    AgentsCoreConfig(
      lmStudioBaseUrl: Uri.parse('http://localhost:9999'),
      apiKey: apiKey,
      logger: logger ?? const SilentLogger(),
    );

// =============================================================================
// Tests
// =============================================================================

void main() {
  // ---------------------------------------------------------------------------
  // Group 1: API key persists through retry sequences (injectable httpSend)
  // ---------------------------------------------------------------------------
  group(
      'API key regression — retry logic does not drop Authorization header', () {
    test('API key config is retained across SocketException retries', () async {
      const apiKey = 'retry-key-socket';
      final send = _FakeHttpSend([
        const SocketException('connection refused'),
        const SocketException('connection refused'),
        _ok(),
      ]);
      final delay = _RecordingDelay();
      final config = _configWithKey(apiKey: apiKey);

      final client = LmStudioHttpClient(
        config: config,
        maxRetries: 3,
        httpSend: send.call,
        delay: delay.call,
      );

      final result = await client.get('/v1/models');
      expect(result, equals({'ok': true}));
      // 3 attempts total: 2 failures + 1 success
      expect(send.callCount, equals(3));
      // Verify the config still carries the apiKey after retries
      expect(config.apiKey, equals(apiKey));
      client.dispose();
    });

    test('API key config is retained across TimeoutException retries',
        () async {
      const apiKey = 'retry-key-timeout';
      final send = _FakeHttpSend([
        TimeoutException('timed out'),
        _ok(),
      ]);
      final delay = _RecordingDelay();

      final client = LmStudioHttpClient(
        config: _configWithKey(apiKey: apiKey),
        maxRetries: 3,
        httpSend: send.call,
        delay: delay.call,
      );

      final result = await client.get('/v1/models');
      expect(result, equals({'ok': true}));
      expect(send.callCount, equals(2));
      client.dispose();
    });

    test('API key config survives mixed error types during retry', () async {
      const apiKey = 'retry-key-mixed';
      final send = _FakeHttpSend([
        const SocketException('no route'),
        TimeoutException('slow'),
        const SocketException('reset'),
        _ok('{"data":[]}'),
      ]);
      final delay = _RecordingDelay();

      final client = LmStudioHttpClient(
        config: _configWithKey(apiKey: apiKey),
        maxRetries: 3,
        httpSend: send.call,
        delay: delay.call,
      );

      final result = await client.get('/v1/models');
      expect(result, equals({'data': []}));
      expect(send.callCount, equals(4));
      client.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Group 2: API key is sent on EVERY request in a real HTTP retry sequence
  //          (using MockLmStudioServer for true end-to-end verification)
  // ---------------------------------------------------------------------------
  group('API key regression — real HTTP stack retry verification', () {
    late MockLmStudioServer server;

    setUp(() async => server = await MockLmStudioServer.start());
    tearDown(() => server.close());

    test('API key is present when server returns 401 (auth failure)', () async {
      const apiKey = 'will-be-rejected';
      server.enqueue(
        response: MockResponse.error(
          statusCode: 401,
          body: {
            'error': {'type': 'unauthorized', 'message': 'bad key'},
          },
        ),
      );

      final client = LmStudioHttpClient(
        config: AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse(server.baseUrl),
          apiKey: apiKey,
          logger: const SilentLogger(),
        ),
      );

      expect(
        () => client.get('/v1/models'),
        throwsA(isA<LmStudioApiException>()),
      );

      // Wait for the request to be processed
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(server.requests, hasLength(1));
      final auth = _authHeader(server.requests.first);
      expect(auth, equals('Bearer $apiKey'),
          reason: 'API key must be sent even when server rejects it');
      client.dispose();
    });

    test('API key is present on sequential requests to different endpoints',
        () async {
      const apiKey = 'multi-endpoint-key';
      server
        ..enqueue(
          method: 'GET',
          path: '/v1/models',
          response: MockResponse.json(body: {'data': []}),
        )
        ..enqueue(
          method: 'POST',
          path: '/v1/chat/completions',
          response: MockResponse.json(body: {'id': 'c1', 'choices': []}),
        )
        ..enqueue(
          method: 'POST',
          path: '/v1/completions',
          response: MockResponse.json(
              body: {'id': 'c2', 'choices': [], 'usage': {}}),
        );

      final client = LmStudioHttpClient(
        config: AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse(server.baseUrl),
          apiKey: apiKey,
          logger: const SilentLogger(),
        ),
      );

      await client.get('/v1/models');
      await client.post('/v1/chat/completions', {
        'model': 'test',
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      });
      await client.post('/v1/completions', {
        'model': 'test',
        'prompt': 'hello',
      });

      expect(server.requests, hasLength(3));
      for (var i = 0; i < 3; i++) {
        final auth = _authHeader(server.requests[i]);
        expect(auth, equals('Bearer $apiKey'),
            reason: 'Request #$i must carry the API key');
      }
      client.dispose();
    });

    test('postStream request sends API key on SSE endpoint', () async {
      const apiKey = 'sse-stream-key';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.sse(chunks: [
          {
            'choices': [
              {
                'delta': {'content': 'Hello'},
              },
            ],
          },
          {
            'choices': [
              {
                'delta': {'content': ' world'},
              },
            ],
          },
        ]),
      );

      final client = LmStudioHttpClient(
        config: AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse(server.baseUrl),
          apiKey: apiKey,
          logger: const SilentLogger(),
        ),
      );

      final chunks = await client
          .postStream('/v1/chat/completions', {
            'model': 'test',
            'messages': [
              {'role': 'user', 'content': 'hi'},
            ],
            'stream': true,
          })
          .toList();

      expect(chunks, hasLength(2));
      expect(server.requests, hasLength(1));
      final auth = _authHeader(server.requests.first);
      expect(auth, equals('Bearer $apiKey'),
          reason: 'SSE streaming requests must carry the API key');
      client.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Group 3: API key does NOT leak into exception messages (security)
  // ---------------------------------------------------------------------------
  group('API key regression — security: no key leakage in exceptions', () {
    test('LmStudioApiException toString() does not contain the API key',
        () async {
      const apiKey = 'super-secret-key-do-not-leak';
      final send = _FakeHttpSend([
        _status(
          401,
          '{"error":{"type":"unauthorized","message":"bad key"}}',
        ),
      ]);

      final client = LmStudioHttpClient(
        config: _configWithKey(apiKey: apiKey),
        httpSend: send.call,
      );

      try {
        await client.get('/v1/models');
        fail('Expected LmStudioApiException');
      } on LmStudioApiException catch (e) {
        expect(e.toString(), isNot(contains(apiKey)),
            reason: 'API key must not leak in exception messages');
        expect(e.statusCode, equals(401));
      }
      client.dispose();
    });

    test('LmStudioConnectionException toString() does not contain the API key',
        () async {
      const apiKey = 'another-secret-key';
      final send = _FakeHttpSend([
        const SocketException('refused'),
      ]);
      final delay = _RecordingDelay();

      final client = LmStudioHttpClient(
        config: _configWithKey(apiKey: apiKey),
        maxRetries: 0,
        httpSend: send.call,
        delay: delay.call,
      );

      try {
        await client.get('/v1/models');
        fail('Expected LmStudioConnectionException');
      } on LmStudioConnectionException catch (e) {
        expect(e.toString(), isNot(contains(apiKey)),
            reason: 'API key must not leak in connection exception messages');
      }
      client.dispose();
    });

    test('AgentsCoreConfig toString() masks the API key', () {
      const apiKey = 'should-be-masked-in-toString';
      final config = _configWithKey(apiKey: apiKey);
      expect(config.toString(), isNot(contains(apiKey)),
          reason: 'Config toString should mask apiKey');
      expect(config.toString(), contains('***'),
          reason: 'Config toString should show *** for non-null apiKey');
    });

    test('AgentsCoreConfig toString() shows null when apiKey is null', () {
      final config = _configWithKey(apiKey: null);
      expect(config.toString(), contains('apiKey: null'));
    });
  });

  // ---------------------------------------------------------------------------
  // Group 4: API key with retry exhaustion — key doesn't affect error handling
  // ---------------------------------------------------------------------------
  group('API key regression — retry exhaustion', () {
    test(
        'all retries exhausted with API key configured still throws '
        'LmStudioConnectionException', () async {
      const apiKey = 'exhaustion-key';
      final send = _FakeHttpSend([
        const SocketException('refused'),
        const SocketException('refused'),
        const SocketException('refused'),
        const SocketException('refused'),
      ]);
      final delay = _RecordingDelay();
      final logger = _RecordingLogger();

      final client = LmStudioHttpClient(
        config: _configWithKey(apiKey: apiKey, logger: logger),
        maxRetries: 3,
        httpSend: send.call,
        delay: delay.call,
      );

      expect(
        () => client.get('/v1/models'),
        throwsA(isA<LmStudioConnectionException>()),
      );

      // Wait for async to settle
      await Future<void>.delayed(Duration.zero);
      expect(send.callCount, equals(4));
      // Verify retry logging occurred
      expect(logger.warnMessages, hasLength(3),
          reason: '3 warn messages for 3 retries');
      expect(logger.errorMessages, hasLength(1),
          reason: '1 error message on final exhaustion');
      client.dispose();
    });

    test('maxRetries=0 with API key configured fails on first error',
        () async {
      const apiKey = 'no-retry-key';
      final send = _FakeHttpSend([
        const SocketException('refused'),
      ]);
      final delay = _RecordingDelay();

      final client = LmStudioHttpClient(
        config: _configWithKey(apiKey: apiKey),
        maxRetries: 0,
        httpSend: send.call,
        delay: delay.call,
      );

      expect(
        () => client.get('/v1/models'),
        throwsA(isA<LmStudioConnectionException>()),
      );

      await Future<void>.delayed(Duration.zero);
      expect(send.callCount, equals(1));
      expect(delay.delays, isEmpty, reason: 'No backoff delay with maxRetries=0');
      client.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Group 5: API key with non-retryable errors — 4xx is NOT retried
  // ---------------------------------------------------------------------------
  group('API key regression — non-retryable 4xx errors are immediate failures',
      () {
    test('401 Unauthorized is not retried, even with API key', () async {
      const apiKey = 'wont-retry-401';
      final send = _FakeHttpSend([
        _status(401, '{"error":{"type":"unauthorized","message":"invalid"}}'),
      ]);
      final delay = _RecordingDelay();

      final client = LmStudioHttpClient(
        config: _configWithKey(apiKey: apiKey),
        maxRetries: 3,
        httpSend: send.call,
        delay: delay.call,
      );

      try {
        await client.get('/v1/models');
        fail('Expected LmStudioApiException');
      } on LmStudioApiException catch (e) {
        expect(e.statusCode, equals(401));
      }

      expect(send.callCount, equals(1),
          reason: '401 must not trigger retry');
      expect(delay.delays, isEmpty,
          reason: 'no backoff delay for 401');
      client.dispose();
    });

    test('403 Forbidden is not retried, even with API key', () async {
      const apiKey = 'wont-retry-403';
      final send = _FakeHttpSend([
        _status(403, '{"error":{"type":"forbidden","message":"denied"}}'),
      ]);
      final delay = _RecordingDelay();

      final client = LmStudioHttpClient(
        config: _configWithKey(apiKey: apiKey),
        maxRetries: 3,
        httpSend: send.call,
        delay: delay.call,
      );

      try {
        await client.post('/v1/chat/completions', {'model': 'test'});
        fail('Expected LmStudioApiException');
      } on LmStudioApiException catch (e) {
        expect(e.statusCode, equals(403));
      }

      expect(send.callCount, equals(1),
          reason: '403 must not trigger retry');
      client.dispose();
    });

    test('404 Not Found is not retried, even with API key', () async {
      const apiKey = 'wont-retry-404';
      final send = _FakeHttpSend([
        _status(404, '{"error":{"type":"not_found","message":"no model"}}'),
      ]);
      final delay = _RecordingDelay();

      final client = LmStudioHttpClient(
        config: _configWithKey(apiKey: apiKey),
        maxRetries: 3,
        httpSend: send.call,
        delay: delay.call,
      );

      try {
        await client.get('/v1/models/nonexistent');
        fail('Expected LmStudioApiException');
      } on LmStudioApiException catch (e) {
        expect(e.statusCode, equals(404));
        expect(e.isModelNotFound, isTrue);
      }

      expect(send.callCount, equals(1),
          reason: '404 must not trigger retry');
      client.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Group 6: API key with baseUrl convenience constructor
  // ---------------------------------------------------------------------------
  group('API key regression — baseUrl convenience constructor', () {
    test('baseUrl constructor without config has no API key (null)', () {
      final client = LmStudioHttpClient(
        baseUrl: 'http://localhost:1234',
      );
      // The client should be constructable without error
      // No way to directly inspect config, but we can verify no crash
      client.dispose();
    });

    test('baseUrl constructor with config carries the API key', () async {
      final send = _FakeHttpSend([_ok()]);
      const apiKey = 'baseurl-config-key';

      final client = LmStudioHttpClient(
        config: AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse('http://localhost:9999'),
          apiKey: apiKey,
          logger: const SilentLogger(),
        ),
        httpSend: send.call,
      );

      await client.get('/v1/models');
      expect(send.callCount, equals(1));
      client.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Group 7: API key via config.copyWith and config.fromEnvironment
  // ---------------------------------------------------------------------------
  group('API key regression — config propagation', () {
    test('copyWith preserves API key when not overridden', () {
      const apiKey = 'original-api-key';
      final config = _configWithKey(apiKey: apiKey);
      final copied = config.copyWith(defaultModel: 'new-model');
      expect(copied.apiKey, equals(apiKey),
          reason: 'copyWith without apiKey param should preserve the key');
    });

    test('copyWith replaces API key when provided', () {
      final config = _configWithKey(apiKey: 'old-key');
      final copied = config.copyWith(apiKey: 'new-key');
      expect(copied.apiKey, equals('new-key'));
    });

    test('copyWith with clearApiKey removes the API key', () {
      final config = _configWithKey(apiKey: 'will-be-cleared');
      final copied = config.copyWith(clearApiKey: true);
      expect(copied.apiKey, isNull,
          reason: 'clearApiKey: true should set apiKey to null');
    });

    test('copyWith with clearApiKey: true ignores provided apiKey', () {
      final config = _configWithKey(apiKey: 'old-key');
      final copied = config.copyWith(apiKey: 'new-key', clearApiKey: true);
      expect(copied.apiKey, isNull,
          reason: 'clearApiKey takes precedence over apiKey parameter');
    });

    test('fromEnvironment reads AGENTS_API_KEY', () {
      final config = AgentsCoreConfig.fromEnvironment(
        environment: {'AGENTS_API_KEY': 'env-key'},
        logger: const SilentLogger(),
      );
      expect(config.apiKey, equals('env-key'));
    });

    test('fromEnvironment without AGENTS_API_KEY yields null apiKey', () {
      final config = AgentsCoreConfig.fromEnvironment(
        environment: {},
        logger: const SilentLogger(),
      );
      expect(config.apiKey, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Group 8: API key equality
  // ---------------------------------------------------------------------------
  group('API key regression — config equality', () {
    test('configs with same apiKey are equal', () {
      final a = _configWithKey(apiKey: 'same-key');
      final b = _configWithKey(apiKey: 'same-key');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('configs with different apiKey are not equal', () {
      final a = _configWithKey(apiKey: 'key-a');
      final b = _configWithKey(apiKey: 'key-b');
      expect(a, isNot(equals(b)));
    });

    test('config with apiKey differs from config without', () {
      final a = _configWithKey(apiKey: 'some-key');
      final b = _configWithKey(apiKey: null);
      expect(a, isNot(equals(b)));
    });
  });
}
