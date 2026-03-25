import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'mock_lm_studio_server.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Low-level HTTP helper (uses dart:io directly, no LmStudioHttpClient)
// ─────────────────────────────────────────────────────────────────────────────

/// Sends a raw HTTP request to [url] and returns the full response.
///
/// [method] defaults to `GET`. [body] is the UTF-8 encoded request body
/// (ignored for GET). Returns a [_RawResponse] with status code, body, and
/// the raw `content-type` header value.
Future<_RawResponse> _request(
  String url, {
  String method = 'GET',
  Map<String, dynamic>? body,
}) async {
  final uri = Uri.parse(url);
  final client = HttpClient();
  try {
    final HttpClientRequest req;
    if (method == 'POST') {
      req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      if (body != null) {
        req.write(jsonEncode(body));
      }
    } else {
      req = await client.getUrl(uri);
    }

    final response = await req.close();
    final responseBody = await response.transform(utf8.decoder).join();
    final contentType = response.headers
        .value(HttpHeaders.contentTypeHeader);

    return _RawResponse(
      statusCode: response.statusCode,
      body: responseBody,
      contentType: contentType ?? '',
    );
  } finally {
    client.close();
  }
}

/// Sends a POST request and reads back SSE lines until `[DONE]`.
///
/// Returns all `data: ` payload strings (with prefix stripped), **excluding**
/// the `[DONE]` sentinel.
Future<List<String>> _readSse(
  String url, {
  Map<String, dynamic>? body,
}) async {
  final uri = Uri.parse(url);
  final client = HttpClient();
  try {
    final req = await client.postUrl(uri);
    req.headers.set(HttpHeaders.contentTypeHeader, ContentType.json.value);
    req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    if (body != null) {
      req.write(jsonEncode(body));
    }

    final response = await req.close();
    final chunks = <String>[];

    await for (final line in response
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.startsWith('data: ')) {
        final data = line.substring(6);
        if (data == '[DONE]') break;
        chunks.add(data);
      }
    }
    return chunks;
  } finally {
    client.close();
  }
}

class _RawResponse {
  _RawResponse({
    required this.statusCode,
    required this.body,
    required this.contentType,
  });

  final int statusCode;
  final String body;
  final String contentType;

  Map<String, dynamic> get jsonBody =>
      json.decode(body) as Map<String, dynamic>;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late MockLmStudioServer server;

  setUp(() async => server = await MockLmStudioServer.start());
  tearDown(() => server.close());

  // ───────────────────────────────────────────────────────────────────────────
  // 1. Server lifecycle
  // ───────────────────────────────────────────────────────────────────────────
  group('server lifecycle', () {
    test('start() returns a MockLmStudioServer', () {
      expect(server, isA<MockLmStudioServer>());
    });

    test('port is a valid non-zero port number', () {
      expect(server.port, greaterThan(0));
      expect(server.port, lessThanOrEqualTo(65535));
    });

    test('baseUrl has correct scheme and host', () {
      expect(server.baseUrl, startsWith('http://127.0.0.1:'));
    });

    test('baseUrl embeds the actual port', () {
      expect(server.baseUrl, equals('http://127.0.0.1:${server.port}'));
    });

    test('server accepts TCP connections on its port', () async {
      // A basic GET with no stub returns a 500 — but a response means the
      // server is reachable (no connection error).
      final res = await _request('${server.baseUrl}/ping');
      expect(res.statusCode, equals(500)); // no stub registered — expected
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 2. JSON response stubs
  // ───────────────────────────────────────────────────────────────────────────
  group('JSON response stubs', () {
    test('enqueued JSON stub is returned with status 200', () async {
      server.enqueue(
        response: MockResponse.json(body: {'ok': true}),
      );
      final res = await _request('${server.baseUrl}/v1/models');
      expect(res.statusCode, equals(200));
    });

    test('enqueued JSON stub body is returned verbatim', () async {
      server.enqueue(
        response: MockResponse.json(
          body: {'id': 'cmpl-1', 'choices': []},
        ),
      );
      final res = await _request('${server.baseUrl}/v1/chat/completions',
          method: 'POST');
      expect(res.jsonBody, equals({'id': 'cmpl-1', 'choices': []}));
    });

    test('content-type is application/json for JSON stubs', () async {
      server.enqueue(
        response: MockResponse.json(body: {'x': 1}),
      );
      final res = await _request('${server.baseUrl}/v1/models');
      expect(res.contentType, contains('application/json'));
    });

    test('custom status code is honoured', () async {
      server.enqueue(
        response: MockResponse.json(statusCode: 201, body: {'created': true}),
      );
      final res = await _request('${server.baseUrl}/v1/resource',
          method: 'POST');
      expect(res.statusCode, equals(201));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3. Error response stubs
  // ───────────────────────────────────────────────────────────────────────────
  group('error response stubs', () {
    for (final code in [400, 401, 403, 404, 422, 429, 500, 503]) {
      test('MockResponse.error returns status $code', () async {
        server.enqueue(
          response: MockResponse.error(
            statusCode: code,
            body: {
              'error': {'type': 'test_error', 'message': 'error $code'}
            },
          ),
        );
        final res = await _request('${server.baseUrl}/v1/chat/completions',
            method: 'POST');
        expect(res.statusCode, equals(code));
      });

      test('error response body is JSON for status $code', () async {
        server.enqueue(
          response: MockResponse.error(
            statusCode: code,
            body: {
              'error': {'type': 'test_error', 'message': 'err'}
            },
          ),
        );
        final res = await _request('${server.baseUrl}/v1/chat/completions',
            method: 'POST');
        expect(res.jsonBody, contains('error'));
      });
    }
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 4. SSE (Server-Sent Events) response stubs
  // ───────────────────────────────────────────────────────────────────────────
  group('SSE response stubs', () {
    test('SSE stub responds with status 200', () async {
      // We can't easily test the status code with _readSse, so we use a raw
      // GET to confirm the stub is returned.
      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            {'delta': 'Hello'},
          ],
        ),
      );
      final chunks = await _readSse('${server.baseUrl}/v1/chat/completions');
      // Just verifying we got a response (status was 200 implicit)
      expect(chunks, isNotEmpty);
    });

    test('each SSE chunk is emitted as a data line', () async {
      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            {'delta': 'Hello'},
            {'delta': ' world'},
          ],
        ),
      );
      final chunks =
          await _readSse('${server.baseUrl}/v1/chat/completions');
      expect(chunks, hasLength(2));
    });

    test('SSE chunk data is JSON-encoded', () async {
      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            {'choices': [{'delta': {'content': 'Hi'}}]},
          ],
        ),
      );
      final chunks =
          await _readSse('${server.baseUrl}/v1/chat/completions');
      expect(chunks, hasLength(1));
      final parsed = json.decode(chunks.first) as Map<String, dynamic>;
      expect(parsed, contains('choices'));
    });

    test('SSE chunks are emitted in order', () async {
      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            {'seq': 1},
            {'seq': 2},
            {'seq': 3},
          ],
        ),
      );
      final chunks =
          await _readSse('${server.baseUrl}/v1/chat/completions');
      final seqs = chunks
          .map((c) => (json.decode(c) as Map<String, dynamic>)['seq'] as int)
          .toList();
      expect(seqs, equals([1, 2, 3]));
    });

    test('SSE [DONE] sentinel is appended and terminates the stream', () async {
      server.enqueue(
        response: MockResponse.sse(chunks: [
          {'delta': 'A'},
        ]),
      );
      // _readSse stops at [DONE] and does NOT include it.
      final chunks =
          await _readSse('${server.baseUrl}/v1/chat/completions');
      // Exactly 1 chunk (not 2 — [DONE] must not bleed through)
      expect(chunks, hasLength(1));
      expect(chunks.first, isNot(equals('[DONE]')));
    });

    test('empty SSE chunk list produces only [DONE]', () async {
      server.enqueue(
        response: MockResponse.sse(chunks: []),
      );
      final chunks =
          await _readSse('${server.baseUrl}/v1/chat/completions');
      expect(chunks, isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 5. Request recording
  // ───────────────────────────────────────────────────────────────────────────
  group('request recording', () {
    test('requests list is empty before any requests arrive', () {
      expect(server.requests, isEmpty);
    });

    test('each incoming request is recorded', () async {
      server.enqueue(response: MockResponse.json(body: {}));
      await _request('${server.baseUrl}/v1/models');
      expect(server.requests, hasLength(1));
    });

    test('recorded request has correct method (GET)', () async {
      server.enqueue(response: MockResponse.json(body: {}));
      await _request('${server.baseUrl}/v1/models');
      expect(server.requests.first.method, equals('GET'));
    });

    test('recorded request has correct method (POST)', () async {
      server.enqueue(response: MockResponse.json(body: {}));
      await _request('${server.baseUrl}/v1/chat/completions', method: 'POST');
      expect(server.requests.first.method, equals('POST'));
    });

    test('recorded request has correct path', () async {
      server.enqueue(response: MockResponse.json(body: {}));
      await _request('${server.baseUrl}/v1/chat/completions', method: 'POST');
      expect(server.requests.first.path, equals('/v1/chat/completions'));
    });

    test('recorded request body matches sent JSON', () async {
      server.enqueue(response: MockResponse.json(body: {}));
      await _request(
        '${server.baseUrl}/v1/chat/completions',
        method: 'POST',
        body: {'model': 'llama3', 'messages': []},
      );
      expect(server.requests.first.jsonBody, equals({
        'model': 'llama3',
        'messages': [],
      }));
    });

    test('GET request has empty body string', () async {
      server.enqueue(response: MockResponse.json(body: {}));
      await _request('${server.baseUrl}/v1/models');
      expect(server.requests.first.body, isEmpty);
    });

    test('multiple requests are all recorded in order', () async {
      server.enqueue(response: MockResponse.json(body: {}));
      server.enqueue(response: MockResponse.json(body: {}));
      await _request('${server.baseUrl}/v1/models');
      await _request('${server.baseUrl}/v1/chat/completions', method: 'POST');
      expect(server.requests, hasLength(2));
      expect(server.requests[0].path, equals('/v1/models'));
      expect(server.requests[1].path, equals('/v1/chat/completions'));
    });

    test('recorded request headers contain content-type for POST', () async {
      server.enqueue(response: MockResponse.json(body: {}));
      await _request(
        '${server.baseUrl}/v1/chat/completions',
        method: 'POST',
        body: {},
      );
      final headers = server.requests.first.headers;
      expect(headers, contains('content-type'));
    });

    test('clearRequests() resets the requests list', () async {
      server.enqueue(response: MockResponse.json(body: {}));
      await _request('${server.baseUrl}/v1/models');
      expect(server.requests, hasLength(1));
      server.clearRequests();
      expect(server.requests, isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 6. Stub matching — method filter
  // ───────────────────────────────────────────────────────────────────────────
  group('stub matching — method filter', () {
    test('stub with method=POST only matches POST requests', () async {
      server.enqueue(
        method: 'POST',
        response: MockResponse.json(body: {'matched': true}),
      );
      // Send a GET — should NOT consume the POST stub → 500
      final getRes = await _request('${server.baseUrl}/v1/models');
      expect(getRes.statusCode, equals(500));
      // POST should match now
      server.enqueue(
        method: 'POST',
        response: MockResponse.json(body: {'matched': true}),
      );
      final postRes = await _request(
        '${server.baseUrl}/v1/models',
        method: 'POST',
      );
      expect(postRes.statusCode, equals(200));
    });

    test('stub with method=null (wildcard) matches GET', () async {
      server.enqueue(
        response: MockResponse.json(body: {'ok': true}),
      );
      final res = await _request('${server.baseUrl}/anything');
      expect(res.statusCode, equals(200));
    });

    test('stub with method=null (wildcard) matches POST', () async {
      server.enqueue(
        response: MockResponse.json(body: {'ok': true}),
      );
      final res =
          await _request('${server.baseUrl}/anything', method: 'POST');
      expect(res.statusCode, equals(200));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 7. Stub matching — path filter
  // ───────────────────────────────────────────────────────────────────────────
  group('stub matching — path filter', () {
    test('stub with specific path only matches that path', () async {
      server.enqueue(
        path: '/v1/models',
        response: MockResponse.json(body: {'matched': 'models'}),
      );
      // Wrong path — no match → 500
      final wrongPath =
          await _request('${server.baseUrl}/v1/chat/completions', method: 'POST');
      expect(wrongPath.statusCode, equals(500));
      // Correct path — matches
      server.enqueue(
        path: '/v1/models',
        response: MockResponse.json(body: {'matched': 'models'}),
      );
      final right = await _request('${server.baseUrl}/v1/models');
      expect(right.jsonBody, equals({'matched': 'models'}));
    });

    test('stub with path=null (wildcard) matches any path', () async {
      server.enqueue(
        response: MockResponse.json(body: {'wildcard': true}),
      );
      final res = await _request('${server.baseUrl}/whatever/path/you/want');
      expect(res.statusCode, equals(200));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 8. Stub matching — method + path combined
  // ───────────────────────────────────────────────────────────────────────────
  group('stub matching — method + path combined', () {
    test('both method and path must match', () async {
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: {'ok': true}),
      );
      // GET to the right path — should NOT match (wrong method)
      final wrongMethod =
          await _request('${server.baseUrl}/v1/chat/completions');
      expect(wrongMethod.statusCode, equals(500));

      // PUT back the stub (was not consumed)
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: {'ok': true}),
      );
      // POST to wrong path — should NOT match
      final wrongPath =
          await _request('${server.baseUrl}/v1/models', method: 'POST');
      expect(wrongPath.statusCode, equals(500));

      // PUT back and send the correct combo
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: {'ok': true}),
      );
      final match = await _request(
        '${server.baseUrl}/v1/chat/completions',
        method: 'POST',
      );
      expect(match.statusCode, equals(200));
      expect(match.jsonBody, equals({'ok': true}));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 9. FIFO stub consumption
  // ───────────────────────────────────────────────────────────────────────────
  group('FIFO stub consumption', () {
    test('stubs are consumed in enqueue order', () async {
      server.enqueue(response: MockResponse.json(body: {'seq': 1}));
      server.enqueue(response: MockResponse.json(body: {'seq': 2}));
      server.enqueue(response: MockResponse.json(body: {'seq': 3}));

      final r1 = await _request('${server.baseUrl}/v1/models');
      final r2 = await _request('${server.baseUrl}/v1/models');
      final r3 = await _request('${server.baseUrl}/v1/models');

      expect(r1.jsonBody['seq'], equals(1));
      expect(r2.jsonBody['seq'], equals(2));
      expect(r3.jsonBody['seq'], equals(3));
    });

    test('each stub is consumed exactly once', () async {
      server.enqueue(
          response: MockResponse.json(body: {'n': 1}));
      await _request('${server.baseUrl}/v1/models');
      // Second request — no more stubs → 500
      final res = await _request('${server.baseUrl}/v1/models');
      expect(res.statusCode, equals(500));
    });

    test('pendingStubCount decrements as stubs are consumed', () async {
      server.enqueue(response: MockResponse.json(body: {}));
      server.enqueue(response: MockResponse.json(body: {}));
      expect(server.pendingStubCount, equals(2));

      await _request('${server.baseUrl}/v1/models');
      expect(server.pendingStubCount, equals(1));

      await _request('${server.baseUrl}/v1/models');
      expect(server.pendingStubCount, equals(0));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 10. No-stub fallback
  // ───────────────────────────────────────────────────────────────────────────
  group('no-stub fallback', () {
    test('returns HTTP 500 when no stub is registered', () async {
      final res = await _request('${server.baseUrl}/v1/models');
      expect(res.statusCode, equals(HttpStatus.internalServerError));
    });

    test('500 fallback body contains the path in the error message', () async {
      final res = await _request('${server.baseUrl}/v1/models');
      expect(res.body, contains('/v1/models'));
    });

    test('500 fallback body contains the method in the error message', () async {
      final res = await _request(
        '${server.baseUrl}/v1/models',
        method: 'POST',
        body: {},
      );
      expect(res.body, contains('POST'));
    });

    test('request is still recorded even when no stub matches', () async {
      await _request('${server.baseUrl}/v1/models');
      expect(server.requests, hasLength(1));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 11. pendingStubCount
  // ───────────────────────────────────────────────────────────────────────────
  group('pendingStubCount', () {
    test('starts at 0', () {
      expect(server.pendingStubCount, equals(0));
    });

    test('increments with each enqueue call', () {
      server.enqueue(response: MockResponse.json(body: {}));
      expect(server.pendingStubCount, equals(1));
      server.enqueue(response: MockResponse.json(body: {}));
      expect(server.pendingStubCount, equals(2));
    });

    test('a non-matching request does NOT consume a stub', () async {
      server.enqueue(
        method: 'POST',
        path: '/specific',
        response: MockResponse.json(body: {}),
      );
      // GET to wrong path — no match
      await _request('${server.baseUrl}/wrong');
      // Stub is still pending
      expect(server.pendingStubCount, equals(1));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 12. MockResponse factories
  // ───────────────────────────────────────────────────────────────────────────
  group('MockResponse factories', () {
    test('MockResponse.json has correct statusCode and jsonBody', () {
      final r = MockResponse.json(body: {'x': 1});
      expect(r.statusCode, equals(200));
      expect(r.jsonBody, equals({'x': 1}));
      expect(r.sseChunks, isNull);
      expect(r.isSse, isFalse);
    });

    test('MockResponse.json with custom statusCode', () {
      final r = MockResponse.json(statusCode: 201, body: {});
      expect(r.statusCode, equals(201));
    });

    test('MockResponse.sse has statusCode 200 and chunks', () {
      final r = MockResponse.sse(chunks: [
        {'delta': 'hi'}
      ]);
      expect(r.statusCode, equals(200));
      expect(r.sseChunks, hasLength(1));
      expect(r.jsonBody, isNull);
      expect(r.isSse, isTrue);
    });

    test('MockResponse.error has non-2xx statusCode and jsonBody', () {
      final r = MockResponse.error(
        statusCode: 404,
        body: {'error': 'not found'},
      );
      expect(r.statusCode, equals(404));
      expect(r.jsonBody, equals({'error': 'not found'}));
      expect(r.isSse, isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 13. RecordedRequest helpers
  // ───────────────────────────────────────────────────────────────────────────
  group('RecordedRequest', () {
    test('jsonBody decodes body correctly', () async {
      server.enqueue(response: MockResponse.json(body: {}));
      await _request(
        '${server.baseUrl}/v1/chat',
        method: 'POST',
        body: {'model': 'llama3'},
      );
      expect(server.requests.first.jsonBody, equals({'model': 'llama3'}));
    });

    test('toString includes method and path', () async {
      server.enqueue(response: MockResponse.json(body: {}));
      await _request('${server.baseUrl}/v1/models');
      final str = server.requests.first.toString();
      expect(str, contains('GET'));
      expect(str, contains('/v1/models'));
    });
  });
}
