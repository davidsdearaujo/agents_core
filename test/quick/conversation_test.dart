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

  // ── Construction ──────────────────────────────────────────────────────────

  group('Conversation — construction', () {
    test('creates with config and model', () {
      final conversation = Conversation(config: config, model: 'llama3');

      expect(conversation, isNotNull);
    });

    test('creates with optional systemPrompt', () {
      final conversation = Conversation(
        config: config,
        model: 'llama3',
        systemPrompt: 'You are helpful.',
      );

      expect(conversation, isNotNull);
    });

    test('creates with default model when model is not specified', () async {
      final conversation = Conversation(config: config);

      server.enqueue(response: MockResponse.json(body: _chatCompletionJson()));

      await conversation.send('Hello');

      final body = server.requests.first.jsonBody;
      expect(body['model'], isA<String>());
      expect((body['model'] as String).isNotEmpty, isTrue);
    });

    test('history is empty when no systemPrompt is provided', () {
      final conversation = Conversation(config: config, model: 'llama3');

      expect(conversation.history, isEmpty);
    });

    test('history contains system message when systemPrompt is provided', () {
      final conversation = Conversation(
        config: config,
        model: 'llama3',
        systemPrompt: 'You are a pirate.',
      );

      expect(conversation.history, hasLength(1));
      expect(conversation.history.first.role, equals(ChatMessageRole.system));
      expect(conversation.history.first.content, equals('You are a pirate.'));
    });
  });

  // ── send() — happy path ──────────────────────────────────────────────────

  group('Conversation.send() — happy path', () {
    test('returns assistant reply text', () async {
      final conversation = Conversation(config: config, model: 'llama3');

      server.enqueue(
        response: MockResponse.json(
          body: _chatCompletionJson(content: 'Hi there!'),
        ),
      );

      final reply = await conversation.send('Hello');

      expect(reply, equals('Hi there!'));
    });

    test('returns empty string when assistant content is empty', () async {
      final conversation = Conversation(config: config, model: 'llama3');

      server.enqueue(
        response: MockResponse.json(body: _chatCompletionJson(content: '')),
      );

      final reply = await conversation.send('Hello');

      expect(reply, equals(''));
    });

    test('returns unicode content correctly', () async {
      final conversation = Conversation(config: config, model: 'llama3');
      const unicode = '你好世界 🌍 Привет';

      server.enqueue(
        response: MockResponse.json(
          body: _chatCompletionJson(content: unicode),
        ),
      );

      final reply = await conversation.send('Say hi');

      expect(reply, equals(unicode));
    });

    test('returns multi-line content verbatim', () async {
      final conversation = Conversation(config: config, model: 'llama3');
      const multiline = 'Line 1\nLine 2\nLine 3';

      server.enqueue(
        response: MockResponse.json(
          body: _chatCompletionJson(content: multiline),
        ),
      );

      final reply = await conversation.send('Tell me');

      expect(reply, equals(multiline));
    });
  });

  // ── send() — message accumulation ────────────────────────────────────────

  group('Conversation.send() — message accumulation', () {
    test('appends user message to history before sending', () async {
      final conversation = Conversation(config: config, model: 'llama3');

      server.enqueue(
        response: MockResponse.json(
          body: _chatCompletionJson(content: 'Reply'),
        ),
      );

      await conversation.send('User question');

      // History should contain both user message and assistant reply
      final userMsgs = conversation.history
          .where((m) => m.role == ChatMessageRole.user)
          .toList();
      expect(userMsgs, hasLength(1));
      expect(userMsgs.first.content, equals('User question'));
    });

    test('appends assistant response to history after receiving', () async {
      final conversation = Conversation(config: config, model: 'llama3');

      server.enqueue(
        response: MockResponse.json(
          body: _chatCompletionJson(content: 'AI reply'),
        ),
      );

      await conversation.send('Hello');

      final assistantMsgs = conversation.history
          .where((m) => m.role == ChatMessageRole.assistant)
          .toList();
      expect(assistantMsgs, hasLength(1));
      expect(assistantMsgs.first.content, equals('AI reply'));
    });

    test('history grows with each send() call', () async {
      final conversation = Conversation(config: config, model: 'llama3');

      server
        ..enqueue(
          response: MockResponse.json(
            body: _chatCompletionJson(content: 'Reply 1'),
          ),
        )
        ..enqueue(
          response: MockResponse.json(
            body: _chatCompletionJson(content: 'Reply 2'),
          ),
        )
        ..enqueue(
          response: MockResponse.json(
            body: _chatCompletionJson(content: 'Reply 3'),
          ),
        );

      await conversation.send('Msg 1');
      await conversation.send('Msg 2');
      await conversation.send('Msg 3');

      // 3 user + 3 assistant = 6 messages
      expect(conversation.history, hasLength(6));
    });

    test('messages appear in user-assistant alternating order', () async {
      final conversation = Conversation(config: config, model: 'llama3');

      server
        ..enqueue(
          response: MockResponse.json(body: _chatCompletionJson(content: 'A1')),
        )
        ..enqueue(
          response: MockResponse.json(body: _chatCompletionJson(content: 'A2')),
        );

      await conversation.send('U1');
      await conversation.send('U2');

      expect(conversation.history[0].role, equals(ChatMessageRole.user));
      expect(conversation.history[0].content, equals('U1'));
      expect(conversation.history[1].role, equals(ChatMessageRole.assistant));
      expect(conversation.history[1].content, equals('A1'));
      expect(conversation.history[2].role, equals(ChatMessageRole.user));
      expect(conversation.history[2].content, equals('U2'));
      expect(conversation.history[3].role, equals(ChatMessageRole.assistant));
      expect(conversation.history[3].content, equals('A2'));
    });

    test('system prompt stays at index 0 with accumulated messages', () async {
      final conversation = Conversation(
        config: config,
        model: 'llama3',
        systemPrompt: 'You are helpful.',
      );

      server.enqueue(
        response: MockResponse.json(
          body: _chatCompletionJson(content: 'Reply'),
        ),
      );

      await conversation.send('Hello');

      // System prompt at 0, user at 1, assistant at 2
      expect(conversation.history, hasLength(3));
      expect(conversation.history[0].role, equals(ChatMessageRole.system));
      expect(conversation.history[0].content, equals('You are helpful.'));
      expect(conversation.history[1].role, equals(ChatMessageRole.user));
      expect(conversation.history[2].role, equals(ChatMessageRole.assistant));
    });
  });

  // ── send() — HTTP request structure ──────────────────────────────────────

  group('Conversation.send() — HTTP request structure', () {
    test('sends POST to /v1/chat/completions', () async {
      final conversation = Conversation(config: config, model: 'llama3');

      server.enqueue(response: MockResponse.json(body: _chatCompletionJson()));

      await conversation.send('Hello');

      expect(server.requests, hasLength(1));
      expect(server.requests.first.method, equals('POST'));
      expect(server.requests.first.path, equals('/v1/chat/completions'));
    });

    test('sends specified model in request body', () async {
      final conversation = Conversation(
        config: config,
        model: 'custom-model-v2',
      );

      server.enqueue(response: MockResponse.json(body: _chatCompletionJson()));

      await conversation.send('Hello');

      final body = server.requests.first.jsonBody;
      expect(body['model'], equals('custom-model-v2'));
    });

    test('sends full conversation history in each request', () async {
      final conversation = Conversation(
        config: config,
        model: 'llama3',
        systemPrompt: 'Be concise.',
      );

      server
        ..enqueue(
          response: MockResponse.json(body: _chatCompletionJson(content: 'A1')),
        )
        ..enqueue(
          response: MockResponse.json(body: _chatCompletionJson(content: 'A2')),
        );

      await conversation.send('U1');
      await conversation.send('U2');

      // Second request should contain full history
      final body = server.requests[1].jsonBody;
      final messages = body['messages'] as List;
      // system + U1 + A1 + U2 = 4 messages
      expect(messages, hasLength(4));
      expect(messages[0]['role'], equals('system'));
      expect(messages[0]['content'], equals('Be concise.'));
      expect(messages[1]['role'], equals('user'));
      expect(messages[1]['content'], equals('U1'));
      expect(messages[2]['role'], equals('assistant'));
      expect(messages[2]['content'], equals('A1'));
      expect(messages[3]['role'], equals('user'));
      expect(messages[3]['content'], equals('U2'));
    });

    test(
      'first request contains only user message when no system prompt',
      () async {
        final conversation = Conversation(config: config, model: 'llama3');

        server.enqueue(
          response: MockResponse.json(body: _chatCompletionJson()),
        );

        await conversation.send('Hello');

        final body = server.requests.first.jsonBody;
        final messages = body['messages'] as List;
        expect(messages, hasLength(1));
        expect(messages[0]['role'], equals('user'));
        expect(messages[0]['content'], equals('Hello'));
      },
    );

    test(
      'first request contains system + user when system prompt set',
      () async {
        final conversation = Conversation(
          config: config,
          model: 'llama3',
          systemPrompt: 'You are a chef.',
        );

        server.enqueue(
          response: MockResponse.json(body: _chatCompletionJson()),
        );

        await conversation.send('What can I cook?');

        final body = server.requests.first.jsonBody;
        final messages = body['messages'] as List;
        expect(messages, hasLength(2));
        expect(messages[0]['role'], equals('system'));
        expect(messages[0]['content'], equals('You are a chef.'));
        expect(messages[1]['role'], equals('user'));
        expect(messages[1]['content'], equals('What can I cook?'));
      },
    );

    test('request does not include stream:true for send()', () async {
      final conversation = Conversation(config: config, model: 'llama3');

      server.enqueue(response: MockResponse.json(body: _chatCompletionJson()));

      await conversation.send('Hello');

      final body = server.requests.first.jsonBody;
      final stream = body['stream'];
      expect(stream == null || stream == false, isTrue);
    });
  });

  // ── send() — multi-turn conversation ─────────────────────────────────────

  group('Conversation.send() — multi-turn conversation', () {
    test(
      'three-turn conversation sends all prior messages in last request',
      () async {
        final conversation = Conversation(
          config: config,
          model: 'llama3',
          systemPrompt: 'You answer questions.',
        );

        server
          ..enqueue(
            response: MockResponse.json(
              body: _chatCompletionJson(content: 'Paris.'),
            ),
          )
          ..enqueue(
            response: MockResponse.json(
              body: _chatCompletionJson(content: 'About 2.1 million.'),
            ),
          )
          ..enqueue(
            response: MockResponse.json(
              body: _chatCompletionJson(content: 'The Eiffel Tower.'),
            ),
          );

        final r1 = await conversation.send('Capital of France?');
        final r2 = await conversation.send('What is its population?');
        final r3 = await conversation.send('Most famous landmark?');

        expect(r1, equals('Paris.'));
        expect(r2, equals('About 2.1 million.'));
        expect(r3, equals('The Eiffel Tower.'));

        // Third request should contain full history
        final body = server.requests[2].jsonBody;
        final messages = body['messages'] as List;
        // system + U1 + A1 + U2 + A2 + U3 = 6 messages
        expect(messages, hasLength(6));
      },
    );

    test('each send() issues exactly one HTTP request', () async {
      final conversation = Conversation(config: config, model: 'llama3');

      server
        ..enqueue(
          response: MockResponse.json(body: _chatCompletionJson(content: 'R1')),
        )
        ..enqueue(
          response: MockResponse.json(body: _chatCompletionJson(content: 'R2')),
        );

      await conversation.send('Q1');
      expect(server.requests, hasLength(1));

      await conversation.send('Q2');
      expect(server.requests, hasLength(2));
    });
  });

  // ── sendStream() ─────────────────────────────────────────────────────────

  group('Conversation.sendStream() — happy path', () {
    test('yields text deltas from streaming response', () async {
      final conversation = Conversation(config: config, model: 'llama3');

      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            _sseChunk(role: 'assistant', content: 'Hello'),
            _sseChunk(content: ' world'),
            _sseChunk(content: '!'),
            _sseChunk(finishReason: 'stop'),
          ],
        ),
      );

      final chunks = await conversation.sendStream('Hi').toList();

      // Filter to non-empty content chunks
      expect(chunks.where((c) => c.isNotEmpty).join(), equals('Hello world!'));
    });

    test('appends user message to history', () async {
      final conversation = Conversation(config: config, model: 'llama3');

      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            _sseChunk(role: 'assistant', content: 'Reply'),
            _sseChunk(finishReason: 'stop'),
          ],
        ),
      );

      await conversation.sendStream('Question').toList();

      final userMsgs = conversation.history
          .where((m) => m.role == ChatMessageRole.user)
          .toList();
      expect(userMsgs, hasLength(1));
      expect(userMsgs.first.content, equals('Question'));
    });

    test(
      'appends assembled assistant message to history after stream completes',
      () async {
        final conversation = Conversation(config: config, model: 'llama3');

        server.enqueue(
          response: MockResponse.sse(
            chunks: [
              _sseChunk(role: 'assistant', content: 'Part 1'),
              _sseChunk(content: ' Part 2'),
              _sseChunk(finishReason: 'stop'),
            ],
          ),
        );

        await conversation.sendStream('Hello').toList();

        final assistantMsgs = conversation.history
            .where((m) => m.role == ChatMessageRole.assistant)
            .toList();
        expect(assistantMsgs, hasLength(1));
        expect(assistantMsgs.first.content, equals('Part 1 Part 2'));
      },
    );

    test('sends full history in streaming request', () async {
      final conversation = Conversation(
        config: config,
        model: 'llama3',
        systemPrompt: 'You are helpful.',
      );

      // First send (non-streaming) to build some history
      server.enqueue(
        response: MockResponse.json(
          body: _chatCompletionJson(content: 'First reply'),
        ),
      );
      await conversation.send('First question');

      // Second send (streaming)
      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            _sseChunk(role: 'assistant', content: 'Second'),
            _sseChunk(content: ' reply'),
            _sseChunk(finishReason: 'stop'),
          ],
        ),
      );
      await conversation.sendStream('Second question').toList();

      // The streaming request should have the full history
      final body = server.requests[1].jsonBody;
      final messages = body['messages'] as List;
      // system + U1 + A1 + U2 = 4 messages
      expect(messages, hasLength(4));
      expect(messages[0]['role'], equals('system'));
      expect(messages[3]['role'], equals('user'));
      expect(messages[3]['content'], equals('Second question'));
    });

    test('streaming request includes stream:true', () async {
      final conversation = Conversation(config: config, model: 'llama3');

      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            _sseChunk(role: 'assistant', content: 'Ok'),
            _sseChunk(finishReason: 'stop'),
          ],
        ),
      );

      await conversation.sendStream('Hello').toList();

      final body = server.requests.first.jsonBody;
      expect(body['stream'], isTrue);
    });
  });

  // ── setSystemPrompt() ────────────────────────────────────────────────────

  group('Conversation.setSystemPrompt()', () {
    test('sets system prompt when none was provided at construction', () {
      final conversation = Conversation(config: config, model: 'llama3');

      expect(conversation.history, isEmpty);

      conversation.setSystemPrompt('You are a poet.');

      expect(conversation.history, hasLength(1));
      expect(conversation.history.first.role, equals(ChatMessageRole.system));
      expect(conversation.history.first.content, equals('You are a poet.'));
    });

    test('replaces existing system prompt', () {
      final conversation = Conversation(
        config: config,
        model: 'llama3',
        systemPrompt: 'Old prompt',
      );

      conversation.setSystemPrompt('New prompt');

      expect(conversation.history.first.role, equals(ChatMessageRole.system));
      expect(conversation.history.first.content, equals('New prompt'));
    });

    test('replaces system prompt without affecting other messages', () async {
      final conversation = Conversation(
        config: config,
        model: 'llama3',
        systemPrompt: 'Original',
      );

      server.enqueue(
        response: MockResponse.json(
          body: _chatCompletionJson(content: 'Reply'),
        ),
      );
      await conversation.send('Question');

      // History: system(Original) + user + assistant = 3
      expect(conversation.history, hasLength(3));

      conversation.setSystemPrompt('Updated');

      // Still 3 messages, but system prompt is updated
      expect(conversation.history, hasLength(3));
      expect(conversation.history[0].role, equals(ChatMessageRole.system));
      expect(conversation.history[0].content, equals('Updated'));
      expect(conversation.history[1].role, equals(ChatMessageRole.user));
      expect(conversation.history[1].content, equals('Question'));
      expect(conversation.history[2].role, equals(ChatMessageRole.assistant));
      expect(conversation.history[2].content, equals('Reply'));
    });

    test('system prompt is sent in subsequent requests', () async {
      final conversation = Conversation(config: config, model: 'llama3');

      conversation.setSystemPrompt('Be brief.');

      server.enqueue(response: MockResponse.json(body: _chatCompletionJson()));

      await conversation.send('Hello');

      final body = server.requests.first.jsonBody;
      final messages = body['messages'] as List;
      expect(messages[0]['role'], equals('system'));
      expect(messages[0]['content'], equals('Be brief.'));
    });

    test('replaced system prompt is used in next request', () async {
      final conversation = Conversation(
        config: config,
        model: 'llama3',
        systemPrompt: 'First prompt',
      );

      server.enqueue(
        response: MockResponse.json(body: _chatCompletionJson(content: 'R1')),
      );
      await conversation.send('Q1');

      conversation.setSystemPrompt('Second prompt');

      server.enqueue(
        response: MockResponse.json(body: _chatCompletionJson(content: 'R2')),
      );
      await conversation.send('Q2');

      final body = server.requests[1].jsonBody;
      final messages = body['messages'] as List;
      expect(messages[0]['content'], equals('Second prompt'));
    });

    test('handles empty string system prompt', () {
      final conversation = Conversation(config: config, model: 'llama3');

      conversation.setSystemPrompt('');

      expect(conversation.history, hasLength(1));
      expect(conversation.history.first.content, equals(''));
    });

    test('handles multi-line system prompt', () {
      final conversation = Conversation(config: config, model: 'llama3');

      const multiline =
          'Rule 1: Be helpful.\nRule 2: Be concise.\nRule 3: Be polite.';
      conversation.setSystemPrompt(multiline);

      expect(conversation.history.first.content, equals(multiline));
    });
  });

  // ── clearHistory() ───────────────────────────────────────────────────────

  group('Conversation.clearHistory()', () {
    test('clears all messages when no system prompt', () async {
      final conversation = Conversation(config: config, model: 'llama3');

      server.enqueue(
        response: MockResponse.json(
          body: _chatCompletionJson(content: 'Reply'),
        ),
      );
      await conversation.send('Question');
      expect(conversation.history, hasLength(2)); // user + assistant

      conversation.clearHistory();

      expect(conversation.history, isEmpty);
    });

    test('keeps system prompt and removes other messages', () async {
      final conversation = Conversation(
        config: config,
        model: 'llama3',
        systemPrompt: 'You are helpful.',
      );

      server
        ..enqueue(
          response: MockResponse.json(body: _chatCompletionJson(content: 'R1')),
        )
        ..enqueue(
          response: MockResponse.json(body: _chatCompletionJson(content: 'R2')),
        );

      await conversation.send('Q1');
      await conversation.send('Q2');

      // system + 2*(user+assistant) = 5
      expect(conversation.history, hasLength(5));

      conversation.clearHistory();

      // Only system prompt remains
      expect(conversation.history, hasLength(1));
      expect(conversation.history.first.role, equals(ChatMessageRole.system));
      expect(conversation.history.first.content, equals('You are helpful.'));
    });

    test('clears history after setSystemPrompt, keeps new system prompt', () {
      final conversation = Conversation(config: config, model: 'llama3');

      conversation.setSystemPrompt('Custom prompt');

      conversation.clearHistory();

      expect(conversation.history, hasLength(1));
      expect(conversation.history.first.content, equals('Custom prompt'));
    });

    test('conversation can continue after clearHistory()', () async {
      final conversation = Conversation(
        config: config,
        model: 'llama3',
        systemPrompt: 'You are concise.',
      );

      server.enqueue(
        response: MockResponse.json(
          body: _chatCompletionJson(content: 'Old reply'),
        ),
      );

      await conversation.send('Old question');
      conversation.clearHistory();

      server.enqueue(
        response: MockResponse.json(
          body: _chatCompletionJson(content: 'New reply'),
        ),
      );

      final reply = await conversation.send('New question');

      expect(reply, equals('New reply'));

      // History should be: system + user + assistant = 3
      expect(conversation.history, hasLength(3));
    });

    test('request after clear does not include old history', () async {
      final conversation = Conversation(
        config: config,
        model: 'llama3',
        systemPrompt: 'Be brief.',
      );

      server.enqueue(
        response: MockResponse.json(body: _chatCompletionJson(content: 'R1')),
      );
      await conversation.send('Q1');

      conversation.clearHistory();

      server.enqueue(
        response: MockResponse.json(body: _chatCompletionJson(content: 'R2')),
      );
      await conversation.send('Q2');

      // Second request should only have system + user (Q2), no old history
      final body = server.requests[1].jsonBody;
      final messages = body['messages'] as List;
      expect(messages, hasLength(2));
      expect(messages[0]['role'], equals('system'));
      expect(messages[1]['role'], equals('user'));
      expect(messages[1]['content'], equals('Q2'));
    });

    test('clearHistory on already empty conversation is a no-op', () {
      final conversation = Conversation(config: config, model: 'llama3');

      expect(conversation.history, isEmpty);
      conversation.clearHistory();
      expect(conversation.history, isEmpty);
    });

    test('clearHistory on conversation with only system prompt keeps it', () {
      final conversation = Conversation(
        config: config,
        model: 'llama3',
        systemPrompt: 'Keep me.',
      );

      expect(conversation.history, hasLength(1));
      conversation.clearHistory();
      expect(conversation.history, hasLength(1));
      expect(conversation.history.first.content, equals('Keep me.'));
    });
  });

  // ── history getter ───────────────────────────────────────────────────────

  group('Conversation.history', () {
    test('returns empty list for fresh conversation without system prompt', () {
      final conversation = Conversation(config: config, model: 'llama3');

      expect(conversation.history, isEmpty);
      expect(conversation.history, isA<List<ChatMessage>>());
    });

    test(
      'returns list with system message for conversation with system prompt',
      () {
        final conversation = Conversation(
          config: config,
          model: 'llama3',
          systemPrompt: 'Test prompt',
        );

        expect(conversation.history, hasLength(1));
        expect(conversation.history.first, isA<ChatMessage>());
      },
    );

    test(
      'returns correct message types and contents after multi-turn',
      () async {
        final conversation = Conversation(
          config: config,
          model: 'llama3',
          systemPrompt: 'Sys',
        );

        server
          ..enqueue(
            response: MockResponse.json(
              body: _chatCompletionJson(content: 'A1'),
            ),
          )
          ..enqueue(
            response: MockResponse.json(
              body: _chatCompletionJson(content: 'A2'),
            ),
          );

        await conversation.send('U1');
        await conversation.send('U2');

        final history = conversation.history;

        expect(history, hasLength(5)); // sys + U1 + A1 + U2 + A2
        expect(history[0].role, equals(ChatMessageRole.system));
        expect(history[0].content, equals('Sys'));
        expect(history[1].role, equals(ChatMessageRole.user));
        expect(history[1].content, equals('U1'));
        expect(history[2].role, equals(ChatMessageRole.assistant));
        expect(history[2].content, equals('A1'));
        expect(history[3].role, equals(ChatMessageRole.user));
        expect(history[3].content, equals('U2'));
        expect(history[4].role, equals(ChatMessageRole.assistant));
        expect(history[4].content, equals('A2'));
      },
    );

    test('history is not modifiable externally (defensive copy)', () {
      final conversation = Conversation(
        config: config,
        model: 'llama3',
        systemPrompt: 'Test',
      );

      final history = conversation.history;

      // Attempting to modify the returned list should either throw
      // or not affect the conversation's internal state
      try {
        history.add(
          ChatMessage(role: ChatMessageRole.user, content: 'injected'),
        );
        // If it didn't throw, verify internal state was not affected
        expect(conversation.history, hasLength(1));
      } on UnsupportedError {
        // Unmodifiable list — this is also acceptable
        expect(conversation.history, hasLength(1));
      }
    });
  });

  // ── Error propagation ────────────────────────────────────────────────────

  group('Conversation — error propagation', () {
    test('send() throws LmStudioApiException on 500', () async {
      final conversation = Conversation(config: config, model: 'llama3');

      server.enqueue(
        response: MockResponse.error(
          statusCode: 500,
          body: {
            'error': {'message': 'Internal server error'},
          },
        ),
      );

      await expectLater(
        conversation.send('Hello'),
        throwsA(isA<LmStudioApiException>()),
      );
    });

    test('send() throws LmStudioApiException on 400', () async {
      final conversation = Conversation(config: config, model: 'llama3');

      server.enqueue(
        response: MockResponse.error(
          statusCode: 400,
          body: {
            'error': {'message': 'Bad request'},
          },
        ),
      );

      await expectLater(
        conversation.send('Hello'),
        throwsA(isA<LmStudioApiException>()),
      );
    });

    test('send() does not append messages on error', () async {
      final conversation = Conversation(config: config, model: 'llama3');

      server.enqueue(
        response: MockResponse.error(
          statusCode: 500,
          body: {
            'error': {'message': 'Server error'},
          },
        ),
      );

      try {
        await conversation.send('Hello');
      } catch (_) {
        // expected
      }

      // User message should NOT have been appended on error
      // (or at least assistant message should not be appended)
      // Depending on implementation: history may have the user msg or be empty
      // The key is that no assistant message was appended
      final assistantMsgs = conversation.history
          .where((m) => m.role == ChatMessageRole.assistant)
          .toList();
      expect(assistantMsgs, isEmpty);
    });

    test(
      'send() throws LmStudioConnectionException when server unreachable',
      () async {
        final badConfig = AgentsCoreConfig(
          lmStudioBaseUrl: Uri.parse('http://127.0.0.1:1'),
          logger: const SilentLogger(),
        );
        final conversation = Conversation(config: badConfig, model: 'llama3');

        await expectLater(
          conversation.send('Hello'),
          throwsA(isA<LmStudioConnectionException>()),
        );
      },
    );

    test('conversation recovers after an error', () async {
      final conversation = Conversation(config: config, model: 'llama3');

      // First request fails
      server.enqueue(
        response: MockResponse.error(
          statusCode: 500,
          body: {
            'error': {'message': 'Temporary error'},
          },
        ),
      );

      try {
        await conversation.send('Failing request');
      } catch (_) {
        // expected
      }

      // Second request succeeds
      server.enqueue(
        response: MockResponse.json(
          body: _chatCompletionJson(content: 'Success!'),
        ),
      );

      final reply = await conversation.send('Retry');

      expect(reply, equals('Success!'));
    });

    test('LmStudioApiException carries correct status code', () async {
      final conversation = Conversation(config: config, model: 'llama3');

      server.enqueue(
        response: MockResponse.error(
          statusCode: 429,
          body: {
            'error': {'message': 'Rate limited'},
          },
        ),
      );

      try {
        await conversation.send('Hello');
        fail('Expected LmStudioApiException to be thrown');
      } on LmStudioApiException catch (e) {
        expect(e.statusCode, equals(429));
      }
    });
  });

  // ── Edge cases ───────────────────────────────────────────────────────────

  group('Conversation — edge cases', () {
    test('handles special characters in user message', () async {
      final conversation = Conversation(config: config, model: 'llama3');

      server.enqueue(
        response: MockResponse.json(body: _chatCompletionJson(content: 'ok')),
      );

      const special = r'Hello "world" & <html> \n \\';
      final reply = await conversation.send(special);

      expect(reply, equals('ok'));
      final body = server.requests.first.jsonBody;
      final messages = body['messages'] as List;
      expect(messages.last['content'], equals(special));
    });

    test('handles empty user message', () async {
      final conversation = Conversation(config: config, model: 'llama3');

      server.enqueue(
        response: MockResponse.json(
          body: _chatCompletionJson(content: 'response'),
        ),
      );

      final reply = await conversation.send('');

      expect(reply, equals('response'));
    });

    test('handles very long user message (10 000 chars)', () async {
      final conversation = Conversation(config: config, model: 'llama3');
      final longMsg = 'x' * 10000;

      server.enqueue(
        response: MockResponse.json(body: _chatCompletionJson(content: 'done')),
      );

      final reply = await conversation.send(longMsg);

      expect(reply, equals('done'));
      final body = server.requests.first.jsonBody;
      final messages = body['messages'] as List;
      expect(messages.first['content'], equals(longMsg));
    });

    test(
      'handles JSON in user message without corrupting request body',
      () async {
        final conversation = Conversation(config: config, model: 'llama3');

        server.enqueue(
          response: MockResponse.json(body: _chatCompletionJson(content: 'ok')),
        );

        const jsonMsg = '{"key": "value", "number": 42}';
        await conversation.send(jsonMsg);

        final body = server.requests.first.jsonBody;
        final messages = body['messages'] as List;
        expect(messages.first['content'], equals(jsonMsg));
      },
    );

    test('multiple clearHistory calls are safe', () {
      final conversation = Conversation(
        config: config,
        model: 'llama3',
        systemPrompt: 'Test',
      );

      conversation.clearHistory();
      conversation.clearHistory();
      conversation.clearHistory();

      expect(conversation.history, hasLength(1));
      expect(conversation.history.first.content, equals('Test'));
    });

    test('setSystemPrompt after clearHistory works correctly', () async {
      final conversation = Conversation(
        config: config,
        model: 'llama3',
        systemPrompt: 'Old',
      );

      server.enqueue(
        response: MockResponse.json(body: _chatCompletionJson(content: 'R1')),
      );
      await conversation.send('Q1');

      conversation.clearHistory();
      conversation.setSystemPrompt('New');

      expect(conversation.history, hasLength(1));
      expect(conversation.history.first.content, equals('New'));

      server.enqueue(
        response: MockResponse.json(body: _chatCompletionJson(content: 'R2')),
      );
      await conversation.send('Q2');

      final body = server.requests[1].jsonBody;
      final messages = body['messages'] as List;
      expect(messages[0]['content'], equals('New'));
    });

    test('interleaved send and sendStream maintain correct history', () async {
      final conversation = Conversation(config: config, model: 'llama3');

      // send()
      server.enqueue(
        response: MockResponse.json(
          body: _chatCompletionJson(content: 'Non-streamed reply'),
        ),
      );
      await conversation.send('First');

      // sendStream()
      server.enqueue(
        response: MockResponse.sse(
          chunks: [
            _sseChunk(role: 'assistant', content: 'Streamed'),
            _sseChunk(content: ' reply'),
            _sseChunk(finishReason: 'stop'),
          ],
        ),
      );
      await conversation.sendStream('Second').toList();

      // send() again
      server.enqueue(
        response: MockResponse.json(
          body: _chatCompletionJson(content: 'Third reply'),
        ),
      );
      await conversation.send('Third');

      expect(conversation.history, hasLength(6));

      // Verify ordering
      expect(conversation.history[0].content, equals('First'));
      expect(conversation.history[1].content, equals('Non-streamed reply'));
      expect(conversation.history[2].content, equals('Second'));
      expect(conversation.history[3].content, equals('Streamed reply'));
      expect(conversation.history[4].content, equals('Third'));
      expect(conversation.history[5].content, equals('Third reply'));
    });
  });
}
