// ignore_for_file: avoid_catching_errors

import 'dart:async';
import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Test helpers
// ═══════════════════════════════════════════════════════════════════════════════

/// Configurable fake [_HttpSendFn].
///
/// Each invocation of [call] consumes the next entry from [_responses].
/// An entry may be:
/// - `({int statusCode, String body})` — returned as a normal HTTP response
/// - an [Exception] — thrown to simulate a network error
class _FakeHttpSend {
  _FakeHttpSend(List<Object> responses) : _responses = List.of(responses);

  final List<Object> _responses;
  int callCount = 0;

  Future<({int statusCode, String body})> call(
    String method,
    Uri url, {
    String? body,
  }) async {
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

/// [Logger] implementation that records all emitted messages.
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

// ── Convenience response factories ────────────────────────────────────────────

/// Returns a 200-OK response with a valid JSON body.
({int statusCode, String body}) _ok([String body = '{"ok":true}']) =>
    (statusCode: 200, body: body);

/// Returns a response with the given [code] and optional [body].
({int statusCode, String body}) _status(int code, [String body = '{}']) =>
    (statusCode: code, body: body);

/// Convenience getter for a [SocketException].
SocketException get _socketEx =>
    const SocketException('Connection refused by host');

/// Convenience getter for a [TimeoutException].
TimeoutException get _timeoutEx =>
    TimeoutException('Request timed out after 60 s');

// ═══════════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  late _RecordingLogger logger;
  late _RecordingDelay delay;
  late AgentsCoreConfig config;

  setUp(() {
    logger = _RecordingLogger();
    delay = _RecordingDelay();
    config = AgentsCoreConfig(
      lmStudioBaseUrl: Uri.parse('http://localhost:1234'),
      logger: logger,
    );
  });

  /// Builds an [LmStudioHttpClient] that uses [responses] as its HTTP
  /// implementation and [delay] to simulate backoff without real sleeps.
  LmStudioHttpClient makeClient(List<Object> responses, {int maxRetries = 3}) =>
      LmStudioHttpClient(
        config: config,
        maxRetries: maxRetries,
        httpSend: _FakeHttpSend(responses).call,
        delay: delay.call,
      );

  // ─────────────────────────────────────────────────────────────────────────────
  // 1. Construction
  // ─────────────────────────────────────────────────────────────────────────────
  group('construction', () {
    test(
      'default maxRetries of 3 — construction succeeds without arguments',
      () {
        expect(() => LmStudioHttpClient(config: config), returnsNormally);
      },
    );

    test('custom maxRetries accepted without error', () {
      expect(
        () => LmStudioHttpClient(config: config, maxRetries: 5),
        returnsNormally,
      );
    });

    test('maxRetries=0 accepted without error', () {
      expect(
        () => LmStudioHttpClient(config: config, maxRetries: 0),
        returnsNormally,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 2. Happy path — no retry required
  // ─────────────────────────────────────────────────────────────────────────────
  group('happy path — no retry required', () {
    test('GET 200 returns decoded JSON body on first attempt', () async {
      final client = makeClient([_ok('{"models":["llama3"]}')]);
      final result = await client.get('/v1/models');
      expect(
        result,
        equals({
          'models': ['llama3'],
        }),
      );
      expect(delay.delays, isEmpty, reason: 'No backoff on immediate success');
    });

    test('POST 200 returns decoded JSON body on first attempt', () async {
      final client = makeClient([_ok('{"id":"cmpl-abc","choices":[]}')]);
      final result = await client.post('/v1/completions', {'prompt': 'Hello'});
      expect(result, equals({'id': 'cmpl-abc', 'choices': []}));
      expect(delay.delays, isEmpty);
    });

    test('no warn or error logged on immediate success', () async {
      final client = makeClient([_ok()]);
      await client.get('/v1/models');
      expect(logger.warnMessages, isEmpty);
      expect(logger.errorMessages, isEmpty);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 3. Retry on SocketException
  // ─────────────────────────────────────────────────────────────────────────────
  group('retry on SocketException', () {
    test('retries once and succeeds on 2nd attempt', () async {
      final client = makeClient([_socketEx, _ok()]);
      final result = await client.get('/v1/models');
      expect(result, equals({'ok': true}));
    });

    test('retries twice and succeeds on 3rd attempt', () async {
      final client = makeClient([_socketEx, _socketEx, _ok()]);
      final result = await client.get('/v1/models');
      expect(result, equals({'ok': true}));
    });

    test('retries three times and succeeds on 4th attempt', () async {
      final client = makeClient([_socketEx, _socketEx, _socketEx, _ok()]);
      final result = await client.get('/v1/models');
      expect(result, equals({'ok': true}));
    });

    test(
      'throws LmStudioConnectionException after all retries exhausted',
      () async {
        // maxRetries=3: 4 total attempts, all failing → wrapped in
        // LmStudioConnectionException with isSocketError=true.
        final client = makeClient([_socketEx, _socketEx, _socketEx, _socketEx]);
        await expectLater(
          () => client.get('/v1/models'),
          throwsA(
            isA<LmStudioConnectionException>().having(
              (e) => e.isSocketError,
              'isSocketError',
              isTrue,
            ),
          ),
        );
      },
    );

    test('makes exactly maxRetries+1 calls when every attempt fails', () async {
      final fake = _FakeHttpSend(
        List.filled(4, _socketEx as Object),
      ); // 1 original + 3 retries
      final client = LmStudioHttpClient(
        config: config,
        maxRetries: 3,
        httpSend: fake.call,
        delay: delay.call,
      );
      await expectLater(
        () => client.get('/v1/models'),
        throwsA(isA<LmStudioConnectionException>()),
      );
      expect(fake.callCount, equals(4));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 4. Retry on TimeoutException
  // ─────────────────────────────────────────────────────────────────────────────
  group('retry on TimeoutException', () {
    test('retries once and succeeds on 2nd attempt', () async {
      final client = makeClient([_timeoutEx, _ok()]);
      final result = await client.get('/v1/models');
      expect(result, equals({'ok': true}));
    });

    test(
      'throws LmStudioConnectionException after all retries exhausted',
      () async {
        final client = makeClient([
          _timeoutEx,
          _timeoutEx,
          _timeoutEx,
          _timeoutEx,
        ]);
        await expectLater(
          () => client.get('/v1/models'),
          throwsA(
            isA<LmStudioConnectionException>().having(
              (e) => e.isTimeout,
              'isTimeout',
              isTrue,
            ),
          ),
        );
      },
    );

    test('makes exactly maxRetries+1 calls when all timeout', () async {
      final fake = _FakeHttpSend(List.filled(4, _timeoutEx as Object));
      final client = LmStudioHttpClient(
        config: config,
        maxRetries: 3,
        httpSend: fake.call,
        delay: delay.call,
      );
      await expectLater(
        () => client.get('/v1/models'),
        throwsA(isA<LmStudioConnectionException>()),
      );
      expect(fake.callCount, equals(4));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 5. No retry on HTTP 429 (rate-limited) — immediate failure
  //
  // Production code throws LmStudioApiException immediately for ALL non-2xx
  // responses, including 429. No retry is attempted for HTTP-level errors.
  // ─────────────────────────────────────────────────────────────────────────────
  group('no retry on HTTP 429 (rate-limited)', () {
    test(
      'throws LmStudioApiException(429) immediately — only 1 call',
      () async {
        final fake = _FakeHttpSend([_status(429)]);
        final client = LmStudioHttpClient(
          config: config,
          maxRetries: 3,
          httpSend: fake.call,
          delay: delay.call,
        );
        await expectLater(
          () => client.get('/v1/models'),
          throwsA(
            isA<LmStudioApiException>().having(
              (e) => e.statusCode,
              'statusCode',
              429,
            ),
          ),
        );
        expect(fake.callCount, equals(1));
        expect(delay.delays, isEmpty);
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 6. No retry on HTTP 5xx — immediate failure
  //
  // Production code throws LmStudioApiException immediately for ALL non-2xx
  // responses. Server errors (500, 502, 503) are not retried.
  // ─────────────────────────────────────────────────────────────────────────────
  group('no retry on HTTP 5xx', () {
    for (final code in [500, 502, 503]) {
      test(
        'throws LmStudioApiException($code) immediately — only 1 call',
        () async {
          final fake = _FakeHttpSend([_status(code)]);
          final client = LmStudioHttpClient(
            config: config,
            maxRetries: 3,
            httpSend: fake.call,
            delay: delay.call,
          );
          await expectLater(
            () => client.get('/v1/models'),
            throwsA(
              isA<LmStudioApiException>().having(
                (e) => e.statusCode,
                'statusCode',
                code,
              ),
            ),
          );
          expect(fake.callCount, equals(1));
          expect(delay.delays, isEmpty);
        },
      );
    }
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 7. No retry on non-retryable 4xx errors
  // ─────────────────────────────────────────────────────────────────────────────
  group('no retry on non-retryable 4xx errors', () {
    // Production throws LmStudioApiException (which implements
    // LmStudioHttpException) immediately for ALL non-2xx responses.
    for (final code in [400, 401, 403, 404, 422]) {
      test('fails immediately on HTTP $code — only 1 HTTP call made', () async {
        final fake = _FakeHttpSend([_status(code)]);
        final client = LmStudioHttpClient(
          config: config,
          maxRetries: 3,
          httpSend: fake.call,
          delay: delay.call,
        );

        await expectLater(
          () => client.get('/v1/models'),
          throwsA(
            isA<LmStudioHttpException>().having(
              (e) => e.statusCode,
              'statusCode',
              code,
            ),
          ),
        );

        expect(
          fake.callCount,
          equals(1),
          reason: 'Non-retryable 4xx must not trigger retry',
        );
        expect(
          delay.delays,
          isEmpty,
          reason: 'No backoff delay applied on non-retryable error',
        );
      });
    }
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 8. Exponential backoff
  // ─────────────────────────────────────────────────────────────────────────────
  group('exponential backoff — delays double starting at 1 s', () {
    test('no delay applied when request succeeds immediately', () async {
      final client = makeClient([_ok()]);
      await client.get('/v1/models');
      expect(delay.delays, isEmpty);
    });

    test('1 retry → one delay of 1 s', () async {
      final client = makeClient([_socketEx, _ok()]);
      await client.get('/v1/models');
      expect(delay.delays, equals([const Duration(seconds: 1)]));
    });

    test('2 retries → delays of 1 s then 2 s', () async {
      final client = makeClient([_socketEx, _socketEx, _ok()]);
      await client.get('/v1/models');
      expect(
        delay.delays,
        equals([const Duration(seconds: 1), const Duration(seconds: 2)]),
      );
    });

    test('3 retries → delays of 1 s, 2 s, 4 s', () async {
      final client = makeClient([_socketEx, _socketEx, _socketEx, _ok()]);
      await client.get('/v1/models');
      expect(
        delay.delays,
        equals([
          const Duration(seconds: 1),
          const Duration(seconds: 2),
          const Duration(seconds: 4),
        ]),
      );
    });

    test('no backoff on HTTP errors (5xx throws immediately)', () async {
      final client = makeClient([_status(503)]);
      await expectLater(
        () => client.get('/v1/models'),
        throwsA(isA<LmStudioApiException>()),
      );
      expect(
        delay.delays,
        isEmpty,
        reason: 'HTTP errors are not retried — no backoff',
      );
    });

    test('no backoff on HTTP 429 (throws immediately)', () async {
      final client = makeClient([_status(429)]);
      await expectLater(
        () => client.get('/v1/models'),
        throwsA(isA<LmStudioApiException>()),
      );
      expect(delay.delays, isEmpty);
    });

    test('backoff applied even when retries are exhausted', () async {
      final client = makeClient([_socketEx, _socketEx, _socketEx, _socketEx]);
      await expectLater(
        () => client.get('/v1/models'),
        throwsA(isA<LmStudioConnectionException>()),
      );
      // 3 retries → 3 delays
      expect(
        delay.delays,
        equals([
          const Duration(seconds: 1),
          const Duration(seconds: 2),
          const Duration(seconds: 4),
        ]),
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 9. Retry logging
  // ─────────────────────────────────────────────────────────────────────────────
  group('retry logging via Logger', () {
    test('no warn messages on immediate success', () async {
      final client = makeClient([_ok()]);
      await client.get('/v1/models');
      expect(logger.warnMessages, isEmpty);
    });

    test('one warn message logged per retry attempt', () async {
      final client = makeClient([_socketEx, _socketEx, _ok()]);
      await client.get('/v1/models');
      expect(logger.warnMessages, hasLength(2));
    });

    test('warn messages include the retry attempt number', () async {
      final client = makeClient([_socketEx, _socketEx, _ok()]);
      await client.get('/v1/models');
      // Attempt numbers 1 and 2 should appear in the messages
      expect(logger.warnMessages[0], contains('1'));
      expect(logger.warnMessages[1], contains('2'));
    });

    test('warn message includes the request path', () async {
      final client = makeClient([_socketEx, _ok()]);
      await client.get('/v1/models');
      expect(logger.warnMessages.first, contains('/v1/models'));
    });

    test('error logged when all retries exhausted', () async {
      final client = makeClient([_socketEx, _socketEx, _socketEx, _socketEx]);
      await expectLater(
        () => client.get('/v1/models'),
        throwsA(isA<LmStudioConnectionException>()),
      );
      expect(logger.errorMessages, isNotEmpty);
    });

    test(
      'no error logged for HTTP 503 — fails immediately without retry',
      () async {
        final client = makeClient([_status(503)]);
        await expectLater(
          () => client.get('/v1/models'),
          throwsA(isA<LmStudioApiException>()),
        );
        // HTTP errors are not retried, so no retry-exhaustion error log is emitted.
        expect(logger.errorMessages, isEmpty);
      },
    );

    test(
      'no warn logged for non-retryable 4xx — fails fast silently',
      () async {
        final client = makeClient([_status(404)]);
        await expectLater(
          () => client.get('/v1/models'),
          throwsA(isA<LmStudioHttpException>()),
        );
        expect(logger.warnMessages, isEmpty);
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 10. maxRetries edge cases
  // ─────────────────────────────────────────────────────────────────────────────
  group('maxRetries edge cases', () {
    test(
      'maxRetries=0 — no retries, wraps SocketException immediately',
      () async {
        final fake = _FakeHttpSend([_socketEx]);
        final client = LmStudioHttpClient(
          config: config,
          maxRetries: 0,
          httpSend: fake.call,
          delay: delay.call,
        );
        await expectLater(
          () => client.get('/v1/models'),
          throwsA(isA<LmStudioConnectionException>()),
        );
        expect(
          fake.callCount,
          equals(1),
          reason: 'maxRetries=0 means zero retries — only the original call',
        );
        expect(delay.delays, isEmpty);
      },
    );

    test('maxRetries=0 — no retries on HTTP 503', () async {
      final fake = _FakeHttpSend([_status(503)]);
      final client = LmStudioHttpClient(
        config: config,
        maxRetries: 0,
        httpSend: fake.call,
        delay: delay.call,
      );
      await expectLater(
        () => client.get('/v1/models'),
        throwsA(isA<LmStudioApiException>()),
      );
      expect(fake.callCount, equals(1));
    });

    test('maxRetries=1 — exactly 2 calls when all attempts fail', () async {
      final fake = _FakeHttpSend([_socketEx, _socketEx]);
      final client = LmStudioHttpClient(
        config: config,
        maxRetries: 1,
        httpSend: fake.call,
        delay: delay.call,
      );
      await expectLater(
        () => client.get('/v1/models'),
        throwsA(isA<LmStudioConnectionException>()),
      );
      expect(fake.callCount, equals(2));
    });

    test('maxRetries=5 — exactly 6 calls when all attempts fail', () async {
      final fake = _FakeHttpSend(List.filled(6, _socketEx as Object));
      final client = LmStudioHttpClient(
        config: config,
        maxRetries: 5,
        httpSend: fake.call,
        delay: delay.call,
      );
      await expectLater(
        () => client.get('/v1/models'),
        throwsA(isA<LmStudioConnectionException>()),
      );
      expect(fake.callCount, equals(6));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 11. POST method retry behaviour
  // ─────────────────────────────────────────────────────────────────────────────
  group('POST retry behaviour mirrors GET', () {
    test('POST retries on SocketException and succeeds', () async {
      final client = makeClient([_socketEx, _ok('{"result":"ok"}')]);
      final result = await client.post('/v1/chat', {'message': 'hello'});
      expect(result, equals({'result': 'ok'}));
    });

    test('POST fails immediately on non-retryable 404 — only 1 call', () async {
      final fake = _FakeHttpSend([_status(404)]);
      final client = LmStudioHttpClient(
        config: config,
        maxRetries: 3,
        httpSend: fake.call,
        delay: delay.call,
      );
      await expectLater(
        () => client.post('/v1/chat', {'message': 'hello'}),
        throwsA(
          isA<LmStudioHttpException>().having(
            (e) => e.statusCode,
            'statusCode',
            404,
          ),
        ),
      );
      expect(fake.callCount, equals(1));
    });

    test('POST throws immediately on HTTP 503 — no retry', () async {
      final fake = _FakeHttpSend([_status(503)]);
      final client = LmStudioHttpClient(
        config: config,
        maxRetries: 3,
        httpSend: fake.call,
        delay: delay.call,
      );
      await expectLater(
        () => client.post('/v1/chat', {'message': 'hello'}),
        throwsA(isA<LmStudioApiException>()),
      );
      expect(fake.callCount, equals(1));
    });

    test('POST applies exponential backoff on retry', () async {
      final client = makeClient([_socketEx, _socketEx, _ok()]);
      await client.post('/v1/chat', {'message': 'hello'});
      expect(
        delay.delays,
        equals([const Duration(seconds: 1), const Duration(seconds: 2)]),
      );
    });

    test(
      'POST exhausts retries and throws LmStudioConnectionException',
      () async {
        final client = makeClient([_socketEx, _socketEx, _socketEx, _socketEx]);
        await expectLater(
          () => client.post('/v1/chat', {'message': 'hello'}),
          throwsA(isA<LmStudioConnectionException>()),
        );
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 12. LmStudioApiException fields on HTTP error failure
  //
  // ALL non-2xx responses throw LmStudioApiException (which implements
  // LmStudioHttpException). This group verifies the exception carries the
  // correct statusCode, body, method, path, errorType, and errorMessage.
  // ─────────────────────────────────────────────────────────────────────────────
  group('LmStudioApiException fields on HTTP error failure', () {
    test(
      'GET exception carries correct statusCode, errorType, and body',
      () async {
        LmStudioApiException? captured;
        try {
          await makeClient([
            _status(
              404,
              '{"error":{"type":"not_found","message":"model not found"}}',
            ),
          ]).get('/v1/models');
        } on LmStudioApiException catch (e) {
          captured = e;
        }
        expect(captured, isNotNull);
        expect(captured!.statusCode, equals(404));
        expect(captured.errorType, equals('not_found'));
        expect(captured.errorMessage, equals('model not found'));
        // LmStudioApiException implements LmStudioHttpException — check those fields:
        expect(captured.method, equals('GET'));
        expect(captured.path, equals('/v1/models'));
      },
    );

    test(
      'POST exception carries correct statusCode, method, and path',
      () async {
        LmStudioApiException? captured;
        try {
          await makeClient([
            _status(
              422,
              '{"error":{"type":"invalid_request","message":"invalid body"}}',
            ),
          ]).post('/v1/completions', {'model': 'unknown'});
        } on LmStudioApiException catch (e) {
          captured = e;
        }
        expect(captured, isNotNull);
        expect(captured!.statusCode, equals(422));
        expect(captured.errorType, equals('invalid_request'));
        expect(captured.errorMessage, equals('invalid body'));
        expect(captured.method, equals('POST'));
        expect(captured.path, equals('/v1/completions'));
      },
    );

    test('toString includes statusCode and errorType', () async {
      LmStudioApiException? captured;
      try {
        await makeClient([
          _status(
            403,
            '{"error":{"type":"forbidden","message":"access denied"}}',
          ),
        ]).get('/v1/models');
      } on LmStudioApiException catch (e) {
        captured = e;
      }
      expect(captured, isNotNull);
      final str = captured!.toString();
      expect(str, contains('403'));
      expect(str, contains('forbidden'));
      // Verify HTTP-level fields are available even if not in toString:
      expect(captured.method, equals('GET'));
      expect(captured.path, equals('/v1/models'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 13. Mixed error sequences
  // ─────────────────────────────────────────────────────────────────────────────
  group('mixed error sequences', () {
    test('SocketException then success — succeeds on 2nd attempt', () async {
      final client = makeClient([_socketEx, _ok()]);
      final result = await client.get('/v1/models');
      expect(result, equals({'ok': true}));
    });

    test('SocketException then HTTP 429 — throws LmStudioApiException(429) '
        'on 2nd attempt (no retry on HTTP error)', () async {
      final fake = _FakeHttpSend([_socketEx, _status(429)]);
      final client = LmStudioHttpClient(
        config: config,
        maxRetries: 3,
        httpSend: fake.call,
        delay: delay.call,
      );
      await expectLater(
        () => client.get('/v1/models'),
        throwsA(
          isA<LmStudioApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            429,
          ),
        ),
      );
      // 2 calls: original SocketException + 1 retry that got 429
      expect(fake.callCount, equals(2));
    });

    test('SocketException then HTTP 503 — throws immediately on 503', () async {
      final fake = _FakeHttpSend([_socketEx, _status(503)]);
      final client = LmStudioHttpClient(
        config: config,
        maxRetries: 3,
        httpSend: fake.call,
        delay: delay.call,
      );
      await expectLater(
        () => client.get('/v1/models'),
        throwsA(
          isA<LmStudioApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            503,
          ),
        ),
      );
      expect(fake.callCount, equals(2));
    });
  });
}
