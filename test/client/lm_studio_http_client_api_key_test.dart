// ignore_for_file: avoid_catching_errors

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

import '../helpers/mock_lm_studio_server.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// LmStudioHttpClient — api_key transmission tests
//
// Verifies that the `apiKey` from [AgentsCoreConfig] is correctly transmitted
// as a `Bearer` token in the `Authorization` header for all HTTP request types:
// GET, POST, and postStream.
//
// Also verifies that NO `Authorization` header is sent when `apiKey` is null.
//
// Uses [MockLmStudioServer] to inspect the exact headers received by the
// server, providing true end-to-end verification through the real HTTP stack.
// ═══════════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Creates an [AgentsCoreConfig] pointing at [server] with the given [apiKey].
AgentsCoreConfig _cfg(MockLmStudioServer server, {String? apiKey}) =>
    AgentsCoreConfig(
      lmStudioBaseUrl: Uri.parse(server.baseUrl),
      apiKey: apiKey,
      logger: const SilentLogger(),
    );

/// Returns the first value of [headerName] from a [RecordedRequest]'s headers,
/// or `null` if absent. Header name matching is case-insensitive.
String? _headerValue(RecordedRequest req, String headerName) {
  final key = headerName.toLowerCase();
  for (final entry in req.headers.entries) {
    if (entry.key.toLowerCase() == key) {
      return entry.value.first;
    }
  }
  return null;
}

/// A minimal chat-completion request body.
Map<String, dynamic> _chatBody({String model = 'llama3'}) => {
      'model': model,
      'messages': [
        {'role': 'user', 'content': 'Hello'},
      ],
    };

// ═══════════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  late MockLmStudioServer server;

  setUp(() async => server = await MockLmStudioServer.start());
  tearDown(() => server.close());

  // ─────────────────────────────────────────────────────────────────────────────
  // 1. GET requests — api_key is transmitted as Authorization header
  // ─────────────────────────────────────────────────────────────────────────────
  group('GET requests — api_key transmitted as Authorization header', () {
    test('Authorization header is present when apiKey is configured', () async {
      server.enqueue(
        method: 'GET',
        path: '/v1/models',
        response: MockResponse.json(body: {'data': []}),
      );
      final client = LmStudioHttpClient(
        config: _cfg(server, apiKey: 'test-key-123'),
      );

      await client.get('/v1/models');

      expect(server.requests, hasLength(1));
      final authHeader = _headerValue(server.requests.first, 'authorization');
      expect(authHeader, isNotNull);
      client.dispose();
    });

    test('Authorization header uses Bearer scheme', () async {
      server.enqueue(
        method: 'GET',
        path: '/v1/models',
        response: MockResponse.json(body: {'data': []}),
      );
      final client = LmStudioHttpClient(
        config: _cfg(server, apiKey: 'my-api-key'),
      );

      await client.get('/v1/models');

      final authHeader = _headerValue(server.requests.first, 'authorization');
      expect(authHeader, startsWith('Bearer '));
      client.dispose();
    });

    test('Authorization header contains the exact api_key value', () async {
      const apiKey = 'lm-studio-secret-key-abc123';
      server.enqueue(
        method: 'GET',
        path: '/v1/models',
        response: MockResponse.json(body: {'data': []}),
      );
      final client = LmStudioHttpClient(
        config: _cfg(server, apiKey: apiKey),
      );

      await client.get('/v1/models');

      final authHeader = _headerValue(server.requests.first, 'authorization');
      expect(authHeader, equals('Bearer $apiKey'));
      client.dispose();
    });

    test('Authorization header format is "Bearer <key>" with single space',
        () async {
      const apiKey = 'sk-test-1234';
      server.enqueue(
        response: MockResponse.json(body: {'ok': true}),
      );
      final client = LmStudioHttpClient(
        config: _cfg(server, apiKey: apiKey),
      );

      await client.get('/v1/models');

      final authHeader = _headerValue(server.requests.first, 'authorization');
      // Verify exact format: "Bearer" + space + key, nothing extra
      expect(authHeader, equals('Bearer sk-test-1234'));
      client.dispose();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 2. POST requests — api_key is transmitted as Authorization header
  // ─────────────────────────────────────────────────────────────────────────────
  group('POST requests — api_key transmitted as Authorization header', () {
    test('Authorization header is present when apiKey is configured', () async {
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: {'id': 'cmpl-1', 'choices': []}),
      );
      final client = LmStudioHttpClient(
        config: _cfg(server, apiKey: 'post-test-key'),
      );

      await client.post('/v1/chat/completions', _chatBody());

      expect(server.requests, hasLength(1));
      final authHeader = _headerValue(server.requests.first, 'authorization');
      expect(authHeader, isNotNull);
      client.dispose();
    });

    test('Authorization header contains exact Bearer token for POST',
        () async {
      const apiKey = 'lm-post-key-xyz789';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: {'id': 'cmpl-1', 'choices': []}),
      );
      final client = LmStudioHttpClient(
        config: _cfg(server, apiKey: apiKey),
      );

      await client.post('/v1/chat/completions', _chatBody());

      final authHeader = _headerValue(server.requests.first, 'authorization');
      expect(authHeader, equals('Bearer $apiKey'));
      client.dispose();
    });

    test('same apiKey is sent in both GET and POST requests', () async {
      const apiKey = 'shared-key-between-methods';
      server
        ..enqueue(
          method: 'GET',
          path: '/v1/models',
          response: MockResponse.json(body: {'data': []}),
        )
        ..enqueue(
          method: 'POST',
          path: '/v1/chat/completions',
          response: MockResponse.json(body: {'id': 'cmpl-1', 'choices': []}),
        );
      final client = LmStudioHttpClient(
        config: _cfg(server, apiKey: apiKey),
      );

      await client.get('/v1/models');
      await client.post('/v1/chat/completions', _chatBody());

      expect(server.requests, hasLength(2));
      final getAuth = _headerValue(server.requests[0], 'authorization');
      final postAuth = _headerValue(server.requests[1], 'authorization');
      expect(getAuth, equals('Bearer $apiKey'));
      expect(postAuth, equals('Bearer $apiKey'));
      client.dispose();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 3. postStream requests — api_key is transmitted as Authorization header
  // ─────────────────────────────────────────────────────────────────────────────
  group('postStream requests — api_key transmitted as Authorization header',
      () {
    test('Authorization header is present for SSE streaming requests',
        () async {
      const apiKey = 'stream-key-456';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.sse(chunks: [
          {
            'choices': [
              {
                'delta': {'content': 'Hi'},
              },
            ],
          },
        ]),
      );
      final client = LmStudioHttpClient(
        config: _cfg(server, apiKey: apiKey),
      );

      await client
          .postStream('/v1/chat/completions', {..._chatBody(), 'stream': true})
          .toList();

      expect(server.requests, hasLength(1));
      final authHeader = _headerValue(server.requests.first, 'authorization');
      expect(authHeader, equals('Bearer $apiKey'));
      client.dispose();
    });

    test('postStream sends same api_key format as POST', () async {
      const apiKey = 'consistent-key-789';
      // First: regular POST
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: {'id': 'cmpl-1', 'choices': []}),
      );
      // Second: SSE POST
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.sse(chunks: []),
      );
      final client = LmStudioHttpClient(
        config: _cfg(server, apiKey: apiKey),
      );

      await client.post('/v1/chat/completions', _chatBody());
      await client
          .postStream('/v1/chat/completions', {..._chatBody(), 'stream': true})
          .toList();

      final postAuth = _headerValue(server.requests[0], 'authorization');
      final streamAuth = _headerValue(server.requests[1], 'authorization');
      expect(postAuth, equals(streamAuth),
          reason: 'Regular POST and postStream should send identical auth');
      client.dispose();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 4. No api_key configured (null) — no Authorization header sent
  // ─────────────────────────────────────────────────────────────────────────────
  group('no api_key configured — no Authorization header', () {
    test('GET sends no Authorization header when apiKey is null', () async {
      server.enqueue(
        method: 'GET',
        path: '/v1/models',
        response: MockResponse.json(body: {'data': []}),
      );
      final client = LmStudioHttpClient(
        config: _cfg(server, apiKey: null),
      );

      await client.get('/v1/models');

      final authHeader = _headerValue(server.requests.first, 'authorization');
      expect(authHeader, isNull,
          reason: 'No Authorization header when apiKey is null');
      client.dispose();
    });

    test('POST sends no Authorization header when apiKey is null', () async {
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: {'id': 'cmpl-1', 'choices': []}),
      );
      final client = LmStudioHttpClient(
        config: _cfg(server),
      );

      await client.post('/v1/chat/completions', _chatBody());

      final authHeader = _headerValue(server.requests.first, 'authorization');
      expect(authHeader, isNull,
          reason: 'No Authorization header when apiKey is null');
      client.dispose();
    });

    test('postStream sends no Authorization header when apiKey is null',
        () async {
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.sse(chunks: []),
      );
      final client = LmStudioHttpClient(
        config: _cfg(server),
      );

      await client
          .postStream('/v1/chat/completions', {..._chatBody(), 'stream': true})
          .toList();

      final authHeader = _headerValue(server.requests.first, 'authorization');
      expect(authHeader, isNull,
          reason: 'No Authorization header when apiKey is null');
      client.dispose();
    });

    test('default AgentsCoreConfig (no apiKey) sends no Authorization header',
        () async {
      server.enqueue(
        response: MockResponse.json(body: {'ok': true}),
      );
      // Default config — apiKey is null
      final client = LmStudioHttpClient(
        config: AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse(server.baseUrl),
          logger: const SilentLogger(),
        ),
      );

      await client.get('/v1/models');

      final authHeader = _headerValue(server.requests.first, 'authorization');
      expect(authHeader, isNull);
      client.dispose();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 5. api_key format edge cases
  // ─────────────────────────────────────────────────────────────────────────────
  group('api_key format edge cases', () {
    test('empty string apiKey sends Authorization header with empty bearer',
        () async {
      server.enqueue(
        response: MockResponse.json(body: {'ok': true}),
      );
      final client = LmStudioHttpClient(
        config: _cfg(server, apiKey: ''),
      );

      await client.get('/v1/models');

      final authHeader = _headerValue(server.requests.first, 'authorization');
      // Empty string is non-null, so the header IS sent.
      // HTTP header serialisation trims trailing whitespace, so
      // "Bearer " becomes "Bearer".
      expect(authHeader, isNotNull);
      expect(authHeader, startsWith('Bearer'));
      client.dispose();
    });

    test('apiKey with special characters is transmitted verbatim', () async {
      const apiKey = 'sk-abc_123.def+ghi/jkl=mno!@#\$%^&*';
      server.enqueue(
        response: MockResponse.json(body: {'ok': true}),
      );
      final client = LmStudioHttpClient(
        config: _cfg(server, apiKey: apiKey),
      );

      await client.get('/v1/models');

      final authHeader = _headerValue(server.requests.first, 'authorization');
      expect(authHeader, equals('Bearer $apiKey'));
      client.dispose();
    });

    test('long apiKey (255 chars) is transmitted in full', () async {
      final apiKey = 'sk-${'a' * 252}'; // 3 + 252 = 255 chars
      server.enqueue(
        response: MockResponse.json(body: {'ok': true}),
      );
      final client = LmStudioHttpClient(
        config: _cfg(server, apiKey: apiKey),
      );

      await client.get('/v1/models');

      final authHeader = _headerValue(server.requests.first, 'authorization');
      expect(authHeader, equals('Bearer $apiKey'));
      // "Bearer " (7 chars) + 255-char key = 262 total
      expect(authHeader!.length, equals('Bearer '.length + apiKey.length));
      client.dispose();
    });

    test('apiKey with dashes (OpenAI-style sk-xxx) is sent correctly',
        () async {
      const apiKey = 'sk-proj-abc123def456ghi789jkl012mno345';
      server.enqueue(
        response: MockResponse.json(body: {'ok': true}),
      );
      final client = LmStudioHttpClient(
        config: _cfg(server, apiKey: apiKey),
      );

      await client.get('/v1/models');

      final authHeader = _headerValue(server.requests.first, 'authorization');
      expect(authHeader, equals('Bearer $apiKey'));
      client.dispose();
    });

    test('apiKey with spaces is transmitted as-is', () async {
      const apiKey = 'key with spaces';
      server.enqueue(
        response: MockResponse.json(body: {'ok': true}),
      );
      final client = LmStudioHttpClient(
        config: _cfg(server, apiKey: apiKey),
      );

      await client.get('/v1/models');

      final authHeader = _headerValue(server.requests.first, 'authorization');
      expect(authHeader, equals('Bearer $apiKey'));
      client.dispose();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 6. api_key via fromEnvironment — env var flows through to HTTP requests
  // ─────────────────────────────────────────────────────────────────────────────
  group('api_key from AgentsCoreConfig.fromEnvironment', () {
    test('AGENTS_API_KEY env var is sent in Authorization header', () async {
      const envKey = 'env-api-key-from-environment';
      server.enqueue(
        response: MockResponse.json(body: {'ok': true}),
      );
      final config = AgentsCoreConfig.fromEnvironment(
        environment: {
          'LM_STUDIO_BASE_URL': server.baseUrl,
          'AGENTS_API_KEY': envKey,
        },
        logger: const SilentLogger(),
      );
      final client = LmStudioHttpClient(config: config);

      await client.get('/v1/models');

      final authHeader = _headerValue(server.requests.first, 'authorization');
      expect(authHeader, equals('Bearer $envKey'));
      client.dispose();
    });

    test('missing AGENTS_API_KEY env var sends no Authorization header',
        () async {
      server.enqueue(
        response: MockResponse.json(body: {'ok': true}),
      );
      final config = AgentsCoreConfig.fromEnvironment(
        environment: {
          'LM_STUDIO_BASE_URL': server.baseUrl,
          // No AGENTS_API_KEY
        },
        logger: const SilentLogger(),
      );
      final client = LmStudioHttpClient(config: config);

      await client.get('/v1/models');

      final authHeader = _headerValue(server.requests.first, 'authorization');
      expect(authHeader, isNull,
          reason: 'Missing AGENTS_API_KEY means no auth');
      client.dispose();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 7. api_key via copyWith — updated key flows through to requests
  // ─────────────────────────────────────────────────────────────────────────────
  group('api_key via copyWith', () {
    test('copyWith(apiKey:) changes the key sent in requests', () async {
      const originalKey = 'original-key';
      const updatedKey = 'updated-key';
      server
        ..enqueue(response: MockResponse.json(body: {'ok': true}))
        ..enqueue(response: MockResponse.json(body: {'ok': true}));

      // First client with original key
      final config1 = _cfg(server, apiKey: originalKey);
      final client1 = LmStudioHttpClient(config: config1);
      await client1.get('/v1/models');

      // Second client with copyWith-updated key
      final config2 = config1.copyWith(apiKey: updatedKey);
      final client2 = LmStudioHttpClient(config: config2);
      await client2.get('/v1/models');

      expect(server.requests, hasLength(2));
      final auth1 = _headerValue(server.requests[0], 'authorization');
      final auth2 = _headerValue(server.requests[1], 'authorization');
      expect(auth1, equals('Bearer $originalKey'));
      expect(auth2, equals('Bearer $updatedKey'));
      client1.dispose();
      client2.dispose();
    });

    test('copyWith(clearApiKey: true) removes Authorization header', () async {
      server
        ..enqueue(response: MockResponse.json(body: {'ok': true}))
        ..enqueue(response: MockResponse.json(body: {'ok': true}));

      // Client with key
      final configWithKey = _cfg(server, apiKey: 'will-be-removed');
      final client1 = LmStudioHttpClient(config: configWithKey);
      await client1.get('/v1/models');

      // Client after clearing key
      final configCleared = configWithKey.copyWith(clearApiKey: true);
      final client2 = LmStudioHttpClient(config: configCleared);
      await client2.get('/v1/models');

      final auth1 = _headerValue(server.requests[0], 'authorization');
      final auth2 = _headerValue(server.requests[1], 'authorization');
      expect(auth1, equals('Bearer will-be-removed'));
      expect(auth2, isNull,
          reason: 'After clearApiKey, no Authorization header');
      client1.dispose();
      client2.dispose();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 8. api_key sent on every request — consistency across multiple calls
  // ─────────────────────────────────────────────────────────────────────────────
  group('api_key consistent across multiple requests', () {
    test('same api_key is sent in every request via the same client',
        () async {
      const apiKey = 'persistent-key';
      server
        ..enqueue(response: MockResponse.json(body: {'data': []}))
        ..enqueue(
            response: MockResponse.json(body: {'id': 'c1', 'choices': []}))
        ..enqueue(response: MockResponse.json(body: {'data': []}));
      final client = LmStudioHttpClient(
        config: _cfg(server, apiKey: apiKey),
      );

      await client.get('/v1/models');
      await client.post('/v1/chat/completions', _chatBody());
      await client.get('/v1/models');

      expect(server.requests, hasLength(3));
      for (var i = 0; i < 3; i++) {
        final auth = _headerValue(server.requests[i], 'authorization');
        expect(auth, equals('Bearer $apiKey'),
            reason: 'Request #$i should carry the same Bearer token');
      }
      client.dispose();
    });

    test('api_key is sent alongside other standard headers', () async {
      const apiKey = 'alongside-headers';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: {'id': 'c1', 'choices': []}),
      );
      final client = LmStudioHttpClient(
        config: _cfg(server, apiKey: apiKey),
      );

      await client.post('/v1/chat/completions', _chatBody());

      final req = server.requests.first;
      // Verify auth header
      expect(_headerValue(req, 'authorization'), equals('Bearer $apiKey'));
      // Verify other standard headers are still present
      expect(_headerValue(req, 'content-type'), contains('application/json'));
      expect(_headerValue(req, 'accept'), isNotNull);
      client.dispose();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 9. api_key with baseUrl string constructor
  // ─────────────────────────────────────────────────────────────────────────────
  group('api_key with baseUrl string constructor', () {
    test('apiKey from config is sent even when using baseUrl shorthand',
        () async {
      const apiKey = 'baseurl-constructor-key';
      server.enqueue(
        response: MockResponse.json(body: {'ok': true}),
      );
      // Use the baseUrl + config combo — config carries the apiKey
      final client = LmStudioHttpClient(
        config: AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse(server.baseUrl),
          apiKey: apiKey,
          logger: const SilentLogger(),
        ),
      );

      await client.get('/v1/models');

      final authHeader = _headerValue(server.requests.first, 'authorization');
      expect(authHeader, equals('Bearer $apiKey'));
      client.dispose();
    });

    test('no apiKey in config means no Authorization with baseUrl constructor',
        () async {
      server.enqueue(
        response: MockResponse.json(body: {'ok': true}),
      );
      final client = LmStudioHttpClient(
        baseUrl: server.baseUrl,
      );

      await client.get('/v1/models');

      final authHeader = _headerValue(server.requests.first, 'authorization');
      expect(authHeader, isNull);
      client.dispose();
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 10. api_key on error responses — header is still sent even when server
  //     returns an error
  // ─────────────────────────────────────────────────────────────────────────────
  group('api_key sent on error responses', () {
    test('Authorization header is present even when server returns 401',
        () async {
      const apiKey = 'bad-key-but-still-sent';
      server.enqueue(
        response: MockResponse.error(
          statusCode: 401,
          body: {
            'error': {'type': 'unauthorized', 'message': 'Invalid API key'},
          },
        ),
      );
      final client = LmStudioHttpClient(
        config: _cfg(server, apiKey: apiKey),
      );

      try {
        await client.get('/v1/models');
      } on LmStudioApiException {
        // Expected — the server returned 401
      }

      // Even though the server rejected the key, verify it was SENT
      expect(server.requests, hasLength(1));
      final authHeader = _headerValue(server.requests.first, 'authorization');
      expect(authHeader, equals('Bearer $apiKey'));
      client.dispose();
    });

    test('Authorization header is present even when server returns 403',
        () async {
      const apiKey = 'forbidden-key';
      server.enqueue(
        response: MockResponse.error(
          statusCode: 403,
          body: {
            'error': {'type': 'forbidden', 'message': 'Access denied'},
          },
        ),
      );
      final client = LmStudioHttpClient(
        config: _cfg(server, apiKey: apiKey),
      );

      try {
        await client.post('/v1/chat/completions', _chatBody());
      } on LmStudioApiException {
        // Expected
      }

      final authHeader = _headerValue(server.requests.first, 'authorization');
      expect(authHeader, equals('Bearer $apiKey'));
      client.dispose();
    });
  });
}
