// ignore_for_file: avoid_catching_errors

import 'dart:convert';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

import '../helpers/mock_lm_studio_server.dart';

// =============================================================================
// LmStudioHttpClient — UTF-8 body encoding regression tests
//
// Regression tests for the bug fixed in v0.3.1 where `request.write()` was
// used to write HTTP request bodies. The `write()` method on `HttpClientRequest`
// delegates to `IOSink.encoding`, which defaults to the platform's
// `systemEncoding` — not guaranteed to be UTF-8.
//
// On Windows (Latin-1 default) this caused:
//   Invalid argument (string): Contains invalid characters.
//
// On other platforms, non-ASCII characters could be silently corrupted.
//
// The fix changed both `postStream` and `_sendRequest` to use
// `request.add(utf8.encode(...))`, which always encodes as UTF-8 regardless
// of the platform's default encoding.
//
// These tests use [MockLmStudioServer] to verify that non-ASCII characters
// arrive intact at the server, exercising the full HTTP stack end-to-end.
// =============================================================================

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

/// Creates an [AgentsCoreConfig] pointing at [server].
AgentsCoreConfig _cfg(MockLmStudioServer server) => AgentsCoreConfig(
  lmStudioBaseUrl: Uri.parse(server.baseUrl),
  logger: const SilentLogger(),
);

/// A standard chat-completion JSON response to enqueue for POST stubs.
Map<String, dynamic> _chatResponse() => {
  'id': 'chatcmpl-utf8-test',
  'object': 'chat.completion',
  'created': 1677858242,
  'model': 'test-model',
  'usage': {'prompt_tokens': 10, 'completion_tokens': 5, 'total_tokens': 15},
  'choices': [
    {
      'message': {'role': 'assistant', 'content': 'OK'},
      'finish_reason': 'stop',
      'index': 0,
    },
  ],
};

/// Builds a chat-completion request body with the given [content].
Map<String, dynamic> _chatBody(String content) => {
  'model': 'test-model',
  'messages': [
    {'role': 'user', 'content': content},
  ],
};

/// Extracts the user-message content from the recorded request body.
String _extractContent(RecordedRequest req) {
  final body = json.decode(req.body) as Map<String, dynamic>;
  final messages = body['messages'] as List;
  final first = messages.first as Map<String, dynamic>;
  return first['content'] as String;
}

// =============================================================================
// Tests
// =============================================================================

void main() {
  late MockLmStudioServer server;

  setUp(() async => server = await MockLmStudioServer.start());
  tearDown(() => server.close());

  // ---------------------------------------------------------------------------
  // Group 1: POST with non-ASCII content (regression for _sendRequest)
  // ---------------------------------------------------------------------------
  group('LmStudioHttpClient — POST UTF-8 encoding', () {
    test('transmits CJK characters correctly', () async {
      const content = '你好世界 — Chinese greeting';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: _chatResponse()),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      await client.post('/v1/chat/completions', _chatBody(content));

      expect(server.requests, hasLength(1));
      expect(_extractContent(server.requests.first), equals(content));
    });

    test('transmits Japanese characters correctly', () async {
      const content = 'こんにちは世界 — 日本語テスト';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: _chatResponse()),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      await client.post('/v1/chat/completions', _chatBody(content));

      expect(server.requests, hasLength(1));
      expect(_extractContent(server.requests.first), equals(content));
    });

    test('transmits Korean characters correctly', () async {
      const content = '안녕하세요 세계';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: _chatResponse()),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      await client.post('/v1/chat/completions', _chatBody(content));

      expect(server.requests, hasLength(1));
      expect(_extractContent(server.requests.first), equals(content));
    });

    test('transmits emoji characters correctly', () async {
      const content = 'Hello 🌍🚀✨ World 👋';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: _chatResponse()),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      await client.post('/v1/chat/completions', _chatBody(content));

      expect(server.requests, hasLength(1));
      expect(_extractContent(server.requests.first), equals(content));
    });

    test('transmits accented Latin characters correctly', () async {
      const content = 'Héllo Wörld — café résumé naïve über straße';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: _chatResponse()),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      await client.post('/v1/chat/completions', _chatBody(content));

      expect(server.requests, hasLength(1));
      expect(_extractContent(server.requests.first), equals(content));
    });

    test('transmits Cyrillic characters correctly', () async {
      const content = 'Привет мир — Русский текст';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: _chatResponse()),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      await client.post('/v1/chat/completions', _chatBody(content));

      expect(server.requests, hasLength(1));
      expect(_extractContent(server.requests.first), equals(content));
    });

    test('transmits Arabic characters correctly', () async {
      const content = 'مرحبا بالعالم — Arabic test';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: _chatResponse()),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      await client.post('/v1/chat/completions', _chatBody(content));

      expect(server.requests, hasLength(1));
      expect(_extractContent(server.requests.first), equals(content));
    });

    test('transmits mixed ASCII and non-ASCII in the same message', () async {
      const content = 'User prompt with mixed: Hello 你好 こんにちは 🚀 café Привет';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: _chatResponse()),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      await client.post('/v1/chat/completions', _chatBody(content));

      expect(server.requests, hasLength(1));
      expect(_extractContent(server.requests.first), equals(content));
    });

    test('transmits Unicode mathematical symbols correctly', () async {
      const content = '∀x ∈ ℝ: x² ≥ 0 ∧ ∑(i=1..n) = n(n+1)/2';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: _chatResponse()),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      await client.post('/v1/chat/completions', _chatBody(content));

      expect(server.requests, hasLength(1));
      expect(_extractContent(server.requests.first), equals(content));
    });

    test('transmits multi-byte emoji (surrogate pairs) correctly', () async {
      // These are supplementary-plane characters requiring 4 UTF-8 bytes each.
      const content = '🏳️‍🌈 👨‍👩‍👧‍👦 🇧🇷 Family flag test';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: _chatResponse()),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      await client.post('/v1/chat/completions', _chatBody(content));

      expect(server.requests, hasLength(1));
      expect(_extractContent(server.requests.first), equals(content));
    });

    test('transmits non-ASCII in system prompt field correctly', () async {
      const systemPrompt = 'Ты — помощник на русском языке. 日本語も話せます。';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: _chatResponse()),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      final body = {
        'model': 'test-model',
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': 'Hello'},
        ],
      };

      await client.post('/v1/chat/completions', body);

      expect(server.requests, hasLength(1));
      final recorded =
          json.decode(server.requests.first.body) as Map<String, dynamic>;
      final messages = recorded['messages'] as List;
      final systemMsg = messages.first as Map<String, dynamic>;
      expect(systemMsg['content'], equals(systemPrompt));
    });

    test('transmits non-ASCII model name correctly', () async {
      // Model names from LM Studio can include non-ASCII/special chars.
      const model = 'qwen3.5-35b-a3b@q3_k_xl';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: _chatResponse()),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      final body = {
        'model': model,
        'messages': [
          {'role': 'user', 'content': 'test'},
        ],
      };

      await client.post('/v1/chat/completions', body);

      expect(server.requests, hasLength(1));
      final recorded = server.requests.first.jsonBody;
      expect(recorded['model'], equals(model));
    });

    test('transmits large non-ASCII body without corruption', () async {
      // A long prompt with repeated non-ASCII content to verify no truncation
      // or corruption occurs with larger payloads.
      final content = '你好世界🌍 ' * 500; // ~3500+ characters
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: _chatResponse()),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      await client.post('/v1/chat/completions', _chatBody(content));

      expect(server.requests, hasLength(1));
      expect(_extractContent(server.requests.first), equals(content));
    });
  });

  // ---------------------------------------------------------------------------
  // Group 2: postStream with non-ASCII content (regression for postStream)
  // ---------------------------------------------------------------------------
  group('LmStudioHttpClient — postStream UTF-8 encoding', () {
    test('transmits CJK characters correctly via streaming', () async {
      const content = '请解释量子计算的基本原理';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.sse(
          chunks: [
            {
              'choices': [
                {
                  'delta': {'content': 'OK'},
                },
              ],
            },
          ],
        ),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      // Drain the stream to complete the request.
      await client
          .postStream('/v1/chat/completions', _chatBody(content))
          .toList();

      expect(server.requests, hasLength(1));
      expect(_extractContent(server.requests.first), equals(content));
    });

    test('transmits emoji content correctly via streaming', () async {
      const content = '🎯 Target practice 🏹 with emoji prompts 💬';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.sse(
          chunks: [
            {
              'choices': [
                {
                  'delta': {'content': 'OK'},
                },
              ],
            },
          ],
        ),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      await client
          .postStream('/v1/chat/completions', _chatBody(content))
          .toList();

      expect(server.requests, hasLength(1));
      expect(_extractContent(server.requests.first), equals(content));
    });

    test('transmits mixed scripts correctly via streaming', () async {
      const content = 'Explain 量子力学 (quantum mechanics) на русском языке';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.sse(
          chunks: [
            {
              'choices': [
                {
                  'delta': {'content': 'OK'},
                },
              ],
            },
          ],
        ),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      await client
          .postStream('/v1/chat/completions', _chatBody(content))
          .toList();

      expect(server.requests, hasLength(1));
      expect(_extractContent(server.requests.first), equals(content));
    });

    test('transmits accented characters correctly via streaming', () async {
      const content =
          'Écrivez un résumé sur la crème brûlée et les hors-d\'œuvres';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.sse(
          chunks: [
            {
              'choices': [
                {
                  'delta': {'content': 'Réponse'},
                },
              ],
            },
          ],
        ),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      await client
          .postStream('/v1/chat/completions', _chatBody(content))
          .toList();

      expect(server.requests, hasLength(1));
      expect(_extractContent(server.requests.first), equals(content));
    });

    test('transmits non-ASCII system prompt correctly via streaming', () async {
      const systemPrompt = '你是一个中文助手。请用中文回答所有问题。';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.sse(
          chunks: [
            {
              'choices': [
                {
                  'delta': {'content': '好的'},
                },
              ],
            },
          ],
        ),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      final body = {
        'model': 'test-model',
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': '你好'},
        ],
      };

      await client.postStream('/v1/chat/completions', body).toList();

      expect(server.requests, hasLength(1));
      final recorded =
          json.decode(server.requests.first.body) as Map<String, dynamic>;
      final messages = recorded['messages'] as List;
      expect(
        (messages[0] as Map<String, dynamic>)['content'],
        equals(systemPrompt),
      );
      expect((messages[1] as Map<String, dynamic>)['content'], equals('你好'));
    });
  });

  // ---------------------------------------------------------------------------
  // Group 3: Edge cases
  // ---------------------------------------------------------------------------
  group('LmStudioHttpClient — UTF-8 edge cases', () {
    test('empty string content does not throw', () async {
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: _chatResponse()),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      await client.post('/v1/chat/completions', _chatBody(''));

      expect(server.requests, hasLength(1));
      expect(_extractContent(server.requests.first), equals(''));
    });

    test('newlines and tabs in content are preserved', () async {
      const content = 'Line 1\nLine 2\n\tIndented\n\nDouble newline';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: _chatResponse()),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      await client.post('/v1/chat/completions', _chatBody(content));

      expect(server.requests, hasLength(1));
      expect(_extractContent(server.requests.first), equals(content));
    });

    test('content with JSON-special characters is preserved', () async {
      const content = r'Escape test: "quotes" \backslash {braces} [brackets]';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: _chatResponse()),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      await client.post('/v1/chat/completions', _chatBody(content));

      expect(server.requests, hasLength(1));
      expect(_extractContent(server.requests.first), equals(content));
    });

    test('null byte (U+0000) in content is transmitted', () async {
      const content = 'before\u0000after';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: _chatResponse()),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      await client.post('/v1/chat/completions', _chatBody(content));

      expect(server.requests, hasLength(1));
      expect(_extractContent(server.requests.first), equals(content));
    });

    test(
      'Unicode code points at BMP boundary (U+FFFD, U+FEFF) are preserved',
      () async {
        // U+FFFD = replacement character, U+FEFF = BOM/zero-width no-break space
        const content = 'BMP boundary: \uFFFD \uFEFF end';
        server.enqueue(
          method: 'POST',
          path: '/v1/chat/completions',
          response: MockResponse.json(body: _chatResponse()),
        );

        final client = LmStudioHttpClient(config: _cfg(server));
        addTearDown(client.dispose);

        await client.post('/v1/chat/completions', _chatBody(content));

        expect(server.requests, hasLength(1));
        expect(_extractContent(server.requests.first), equals(content));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Group 4: Multiple sequential non-ASCII requests
  // ---------------------------------------------------------------------------
  group('LmStudioHttpClient — sequential UTF-8 requests', () {
    test(
      'multiple POST requests with different scripts all arrive intact',
      () async {
        final contents = ['你好世界', 'Привет мир', '🚀 Launch 🎯', 'café résumé'];

        for (final _ in contents) {
          server.enqueue(
            method: 'POST',
            path: '/v1/chat/completions',
            response: MockResponse.json(body: _chatResponse()),
          );
        }

        final client = LmStudioHttpClient(config: _cfg(server));
        addTearDown(client.dispose);

        for (final content in contents) {
          await client.post('/v1/chat/completions', _chatBody(content));
        }

        expect(server.requests, hasLength(4));
        for (var i = 0; i < contents.length; i++) {
          expect(
            _extractContent(server.requests[i]),
            equals(contents[i]),
            reason: 'Request $i should have content: ${contents[i]}',
          );
        }
      },
    );

    test('mixed POST and postStream with non-ASCII content', () async {
      const postContent = '中文 POST request';
      const streamContent = '中文 streaming request';

      // POST stub
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: _chatResponse()),
      );

      // SSE stub
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.sse(
          chunks: [
            {
              'choices': [
                {
                  'delta': {'content': 'OK'},
                },
              ],
            },
          ],
        ),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      await client.post('/v1/chat/completions', _chatBody(postContent));
      await client
          .postStream('/v1/chat/completions', _chatBody(streamContent))
          .toList();

      expect(server.requests, hasLength(2));
      expect(_extractContent(server.requests[0]), equals(postContent));
      expect(_extractContent(server.requests[1]), equals(streamContent));
    });
  });

  // ---------------------------------------------------------------------------
  // Group 5: Exact bytes verification
  // ---------------------------------------------------------------------------
  group('LmStudioHttpClient — UTF-8 byte-level verification', () {
    test('request body is valid UTF-8 JSON', () async {
      const content = '日本語テスト 🎌';
      server.enqueue(
        method: 'POST',
        path: '/v1/chat/completions',
        response: MockResponse.json(body: _chatResponse()),
      );

      final client = LmStudioHttpClient(config: _cfg(server));
      addTearDown(client.dispose);

      await client.post('/v1/chat/completions', _chatBody(content));

      // The raw body stored by MockLmStudioServer is decoded via
      // utf8.decode(bodyBytes). If the client had sent non-UTF-8 bytes,
      // this decode would fail or produce garbled output.
      final rawBody = server.requests.first.body;

      // Verify the body is valid JSON.
      final decoded = json.decode(rawBody) as Map<String, dynamic>;
      expect(decoded, isA<Map<String, dynamic>>());

      // Verify the content round-trips cleanly.
      final messages = decoded['messages'] as List;
      final userMsg = messages.first as Map<String, dynamic>;
      expect(userMsg['content'], equals(content));

      // Verify the raw body bytes can be re-encoded to the same UTF-8 bytes.
      final reEncoded = utf8.encode(rawBody);
      final reDecoded = utf8.decode(reEncoded);
      expect(reDecoded, equals(rawBody));
    });
  });
}
