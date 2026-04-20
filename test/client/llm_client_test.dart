import 'dart:collection';
import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Fake infrastructure — implements LlmClient directly, NOT via LmStudioClient
// ═══════════════════════════════════════════════════════════════════════════════

/// A minimal [LlmClient] implementation that does not depend on [LmStudioClient].
///
/// This is the key test helper for M7: it proves that [Agent] subtypes accept
/// *any* [LlmClient] — not just [LmStudioClient].
class _FakeLlmClient implements LlmClient {
  _FakeLlmClient(List<ChatCompletionResponse> responses)
    : _queue = Queue.of(responses);

  final Queue<ChatCompletionResponse> _queue;
  final List<ChatCompletionRequest> capturedRequests = [];
  bool _disposed = false;

  bool get isDisposed => _disposed;

  @override
  Future<ChatCompletionResponse> chatCompletion(
    ChatCompletionRequest request,
  ) async {
    capturedRequests.add(request);
    if (_queue.isEmpty) throw StateError('_FakeLlmClient: no more responses');
    return _queue.removeFirst();
  }

  @override
  Stream<ChatCompletionChunk> chatCompletionStream(
    ChatCompletionRequest request,
  ) {
    return const Stream.empty();
  }

  @override
  Stream<String> chatCompletionStreamText(ChatCompletionRequest request) {
    return const Stream.empty();
  }

  @override
  void dispose() {
    _disposed = true;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Response / config builders
// ─────────────────────────────────────────────────────────────────────────────

ChatCompletionResponse _response({
  String? content = 'Hello!',
  String? finishReason = 'stop',
  int promptTokens = 10,
  int completionTokens = 5,
  List<ToolCall>? toolCalls,
}) {
  return ChatCompletionResponse(
    id: 'chatcmpl-test',
    choices: [
      ChatCompletionChoice(
        message: ChatMessage(
          role: ChatMessageRole.assistant,
          content: content,
          toolCalls: toolCalls,
        ),
        finishReason: finishReason,
      ),
    ],
    usage: CompletionUsage(
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: promptTokens + completionTokens,
    ),
  );
}

ToolCall _toolCall({
  String id = 'call_1',
  String name = 'my_tool',
  String arguments = '{"x": 1}',
}) => ToolCall(
  id: id,
  type: 'function',
  function: ToolCallFunction(name: name, arguments: arguments),
);

AgentsCoreConfig _silentConfig() => AgentsCoreConfig(logger: SilentLogger());

// ═══════════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // AC1: LlmClient interface is exported from the barrel
  // ───────────────────────────────────────────────────────────────────────────
  group('LlmClient — barrel export', () {
    test('LlmClient is accessible from package:agents_core/agents_core.dart', () {
      // If LlmClient were not exported, this test file itself would not compile.
      // This test acts as a compile-time proof of the export.
      final fake = _FakeLlmClient([]);
      expect(fake, isA<LlmClient>());
    });

    test('LmStudioClient is still exported alongside LlmClient', () {
      // LmStudioClient must remain in the public API as a concrete
      // implementation, so existing consumers continue to work without
      // code changes.
      final client = LmStudioClient(AgentsCoreConfig(logger: SilentLogger()));
      expect(client, isA<LmStudioClient>());
      client.dispose();
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // AC2: LlmClient interface methods
  // ───────────────────────────────────────────────────────────────────────────
  group('LlmClient — interface contract', () {
    test('implements chatCompletion()', () async {
      final client = _FakeLlmClient([_response(content: 'ok')]);
      final req = ChatCompletionRequest(
        model: 'test-model',
        messages: [ChatMessage(role: ChatMessageRole.user, content: 'Hello')],
      );
      final result = await client.chatCompletion(req);
      expect(result, isA<ChatCompletionResponse>());
      expect(result.choices.first.message.content, equals('ok'));
    });

    test('implements chatCompletionStream()', () {
      final client = _FakeLlmClient([]);
      final req = ChatCompletionRequest(
        model: 'test-model',
        messages: [ChatMessage(role: ChatMessageRole.user, content: 'Hello')],
      );
      final stream = client.chatCompletionStream(req);
      expect(stream, isA<Stream<ChatCompletionChunk>>());
    });

    test('implements chatCompletionStreamText()', () {
      final client = _FakeLlmClient([]);
      final req = ChatCompletionRequest(
        model: 'test-model',
        messages: [ChatMessage(role: ChatMessageRole.user, content: 'Hello')],
      );
      final stream = client.chatCompletionStreamText(req);
      expect(stream, isA<Stream<String>>());
    });

    test('implements dispose()', () {
      final client = _FakeLlmClient([]);
      expect(() => client.dispose(), returnsNormally);
      expect(client.isDisposed, isTrue);
    });

    test('multiple calls to chatCompletion work sequentially', () async {
      final client = _FakeLlmClient([
        _response(content: 'first'),
        _response(content: 'second'),
      ]);
      final req = ChatCompletionRequest(
        model: 'test-model',
        messages: [ChatMessage(role: ChatMessageRole.user, content: 'Hi')],
      );
      final r1 = await client.chatCompletion(req);
      final r2 = await client.chatCompletion(req);
      expect(r1.choices.first.message.content, equals('first'));
      expect(r2.choices.first.message.content, equals('second'));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // AC3: LmStudioClient implements LlmClient
  // ───────────────────────────────────────────────────────────────────────────
  group('LmStudioClient — implements LlmClient', () {
    test('LmStudioClient is assignable to LlmClient', () {
      final LlmClient client = LmStudioClient(
        AgentsCoreConfig(logger: SilentLogger()),
      );
      expect(client, isA<LlmClient>());
      client.dispose();
    });

    test('LmStudioClient passes isA<LlmClient> check', () {
      final client = LmStudioClient(AgentsCoreConfig(logger: SilentLogger()));
      expect(client, isA<LlmClient>());
      client.dispose();
    });

    test('LmStudioClient still passes isA<LmStudioClient> check', () {
      // LmStudioClient must not lose its own identity — consumers that type
      // it as LmStudioClient must continue to work.
      final client = LmStudioClient(AgentsCoreConfig(logger: SilentLogger()));
      expect(client, isA<LmStudioClient>());
      client.dispose();
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // AC4 & AC5: Agent, SimpleAgent, ReActAgent, PythonToolAgent accept LlmClient
  // ───────────────────────────────────────────────────────────────────────────
  group('Agent — depends on LlmClient (DIP)', () {
    test('Agent.client field is typed as LlmClient', () {
      final fake = _FakeLlmClient([]);
      final agent = SimpleAgent(
        name: 'test',
        client: fake,
        config: _silentConfig(),
      );
      // If Agent.client were LmStudioClient, this assignment would fail
      // to compile.
      final LlmClient extracted = agent.client;
      expect(extracted, isA<LlmClient>());
    });

    test('a custom LlmClient (non-LmStudioClient) can be passed to Agent', () {
      final fake = _FakeLlmClient([]);
      expect(
        () => SimpleAgent(name: 'test', client: fake, config: _silentConfig()),
        returnsNormally,
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // AC4: SimpleAgent works with a custom LlmClient
  // ───────────────────────────────────────────────────────────────────────────
  group('SimpleAgent — with LlmClient', () {
    test('can be constructed with a _FakeLlmClient', () {
      final agent = SimpleAgent(
        name: 'simple',
        client: _FakeLlmClient([]),
        config: _silentConfig(),
      );
      expect(agent, isA<SimpleAgent>());
    });

    test('run() calls chatCompletion() on the LlmClient', () async {
      final fake = _FakeLlmClient([_response(content: 'Done!')]);
      final agent = SimpleAgent(
        name: 'simple',
        client: fake,
        config: _silentConfig(),
      );
      await agent.run('Do something');
      expect(fake.capturedRequests, hasLength(1));
    });

    test('run() returns output from LlmClient.chatCompletion()', () async {
      final fake = _FakeLlmClient([_response(content: 'Custom answer')]);
      final agent = SimpleAgent(
        name: 'simple',
        client: fake,
        config: _silentConfig(),
      );
      final result = await agent.run('Task');
      expect(result.output, equals('Custom answer'));
    });

    test('run() records correct token usage from LlmClient', () async {
      final fake = _FakeLlmClient([
        _response(promptTokens: 30, completionTokens: 20),
      ]);
      final agent = SimpleAgent(
        name: 'simple',
        client: fake,
        config: _silentConfig(),
      );
      final result = await agent.run('Task');
      expect(result.tokensUsed, equals(50));
    });

    test(
      'stoppedReason is null for SimpleAgent (no orchestration loop)',
      () async {
        // SimpleAgent does not run a loop — stoppedReason is always null.
        // The raw finishReason string from the LLM is not mapped to AgentStopReason.
        final fake = _FakeLlmClient([_response(finishReason: 'length')]);
        final agent = SimpleAgent(
          name: 'simple',
          client: fake,
          config: _silentConfig(),
        );
        final result = await agent.run('Task');
        expect(result.stoppedReason, isNull);
      },
    );

    test('model override is forwarded to chatCompletion() request', () async {
      final fake = _FakeLlmClient([_response()]);
      final agent = SimpleAgent(
        name: 'simple',
        client: fake,
        config: _silentConfig(),
        model: 'gpt-4o',
      );
      await agent.run('Task');
      expect(fake.capturedRequests.first.model, equals('gpt-4o'));
    });

    test(
      'LmStudioClient (which implements LlmClient) still works as client',
      () {
        // Regression: existing code passing LmStudioClient to SimpleAgent must
        // continue to compile and work unchanged.
        expect(
          () => SimpleAgent(
            name: 'test',
            client: LmStudioClient(AgentsCoreConfig(logger: SilentLogger())),
            config: _silentConfig(),
          ),
          returnsNormally,
        );
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // AC5: ReActAgent works with a custom LlmClient
  // ───────────────────────────────────────────────────────────────────────────
  group('ReActAgent — with LlmClient', () {
    test('can be constructed with a _FakeLlmClient', () {
      final agent = ReActAgent(
        name: 'react',
        client: _FakeLlmClient([]),
        config: _silentConfig(),
        toolHandlers: {},
      );
      expect(agent, isA<ReActAgent>());
    });

    test('run() completes naturally with a custom LlmClient', () async {
      final fake = _FakeLlmClient([_response(content: 'Final answer')]);
      final agent = ReActAgent(
        name: 'react',
        client: fake,
        config: _silentConfig(),
        toolHandlers: {},
      );
      final result = await agent.run('Simple task');
      expect(result.stoppedReason, equals(AgentStopReason.completed));
      expect(result.output, equals('Final answer'));
    });

    test('run() calls chatCompletion() on the LlmClient', () async {
      final fake = _FakeLlmClient([_response(content: 'Done')]);
      final agent = ReActAgent(
        name: 'react',
        client: fake,
        config: _silentConfig(),
        toolHandlers: {},
      );
      await agent.run('Task');
      expect(fake.capturedRequests, hasLength(1));
    });

    test('run() executes tool via LlmClient and completes', () async {
      final toolCallResponse = _response(
        toolCalls: [_toolCall(name: 'my_tool')],
        finishReason: 'tool_calls',
        content: null,
      );
      final finalResponse = _response(content: 'Tool result processed');

      final fake = _FakeLlmClient([toolCallResponse, finalResponse]);
      final agent = ReActAgent(
        name: 'react',
        client: fake,
        config: _silentConfig(),
        toolHandlers: {'my_tool': (args) async => 'result: ${args['x']}'},
        tools: [
          ToolDefinition(
            name: 'my_tool',
            description: 'A test tool',
            parameters: {
              'type': 'object',
              'properties': {
                'x': {'type': 'integer'},
              },
            },
          ),
        ],
      );

      final result = await agent.run('Use my tool');
      expect(result.stoppedReason, equals(AgentStopReason.completed));
      expect(fake.capturedRequests, hasLength(2));
    });

    test(
      'LmStudioClient (implements LlmClient) still works with ReActAgent',
      () {
        expect(
          () => ReActAgent(
            name: 'test',
            client: LmStudioClient(AgentsCoreConfig(logger: SilentLogger())),
            config: _silentConfig(),
            toolHandlers: {},
          ),
          returnsNormally,
        );
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // AC5: PythonToolAgent works with a custom LlmClient
  // ───────────────────────────────────────────────────────────────────────────
  group('PythonToolAgent — with LlmClient', () {
    late Directory tmpDir;
    late DockerClient fakeDocker;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('pta_llmclient_test_');
      fakeDocker = DockerClient(logger: SilentLogger());
    });

    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('can be constructed with a _FakeLlmClient', () {
      final agent = PythonToolAgent(
        name: 'python',
        client: _FakeLlmClient([]),
        config: _silentConfig(),
        dockerClient: fakeDocker,
        fileContext: FileContext(workspacePath: tmpDir.path),
      );
      expect(agent, isA<PythonToolAgent>());
    });

    test('PythonToolAgent is a subtype of Agent', () {
      final agent = PythonToolAgent(
        name: 'python',
        client: _FakeLlmClient([]),
        config: _silentConfig(),
        dockerClient: fakeDocker,
        fileContext: FileContext(workspacePath: tmpDir.path),
      );
      expect(agent, isA<Agent>());
    });

    test('PythonToolAgent.client field is typed as LlmClient', () {
      final fake = _FakeLlmClient([]);
      final agent = PythonToolAgent(
        name: 'python',
        client: fake,
        config: _silentConfig(),
        dockerClient: fakeDocker,
        fileContext: FileContext(workspacePath: tmpDir.path),
      );
      // If client were still LmStudioClient, assigning to LlmClient would
      // fail at compile time.
      final LlmClient extracted = agent.client;
      expect(extracted, isA<LlmClient>());
    });

    test(
      'LmStudioClient (implements LlmClient) still works with PythonToolAgent',
      () {
        expect(
          () => PythonToolAgent(
            name: 'python',
            client: LmStudioClient(AgentsCoreConfig(logger: SilentLogger())),
            config: _silentConfig(),
            dockerClient: fakeDocker,
            fileContext: FileContext(workspacePath: tmpDir.path),
          ),
          returnsNormally,
        );
      },
    );
  });

  // ───────────────────────────────────────────────────────────────────────────
  // AC6: LlmClient in barrel — export verification
  // ───────────────────────────────────────────────────────────────────────────
  group('LlmClient — export via barrel', () {
    test('LlmClient type can be used as a variable type annotation', () {
      // This test compiles only if LlmClient is exported from the barrel.
      LlmClient client = _FakeLlmClient([]);
      expect(client, isNotNull);
    });

    test('LlmClient can be used as a return type', () {
      LlmClient makeClient() => _FakeLlmClient([]);
      final c = makeClient();
      expect(c, isA<LlmClient>());
    });

    test('LlmClient can be used as a parameter type', () {
      void accept(LlmClient c) => expect(c, isA<LlmClient>());
      accept(_FakeLlmClient([]));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // Regression: existing agent tests using LmStudioClient still work
  // ───────────────────────────────────────────────────────────────────────────
  group('Regression — LmStudioClient as LlmClient in existing patterns', () {
    test('_FakeLmStudioClient subclass still assignable to LlmClient', () {
      // The existing test helpers in simple_agent_test.dart and
      // react_agent_test.dart extend LmStudioClient. Those helpers must still
      // work with Agent after M7 because LmStudioClient implements LlmClient.
      final fakeViaSubclass = _FakeViaLmStudioSubclass([_response()]);
      final agent = SimpleAgent(
        name: 'regression',
        client: fakeViaSubclass,
        config: _silentConfig(),
      );
      expect(agent.client, isA<LlmClient>());
      expect(agent.client, isA<LmStudioClient>());
    });

    test('LmStudioClient subclass run() produces correct output', () async {
      final fake = _FakeViaLmStudioSubclass([
        _response(content: 'Backwards compat'),
      ]);
      final agent = SimpleAgent(
        name: 'test',
        client: fake,
        config: _silentConfig(),
      );
      final result = await agent.run('Task');
      expect(result.output, equals('Backwards compat'));
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Regression helper — extends LmStudioClient (old pattern, still valid)
// ─────────────────────────────────────────────────────────────────────────────

/// Mimics the `_FakeClient extends LmStudioClient` pattern used in existing
/// agent tests, verifying that subclasses of [LmStudioClient] remain compatible
/// with [Agent] after M7.
class _FakeViaLmStudioSubclass extends LmStudioClient {
  _FakeViaLmStudioSubclass(List<ChatCompletionResponse> responses)
    : _queue = Queue.of(responses),
      super(AgentsCoreConfig(logger: SilentLogger()));

  final Queue<ChatCompletionResponse> _queue;

  @override
  Future<ChatCompletionResponse> chatCompletion(
    ChatCompletionRequest request,
  ) async {
    if (_queue.isEmpty) throw StateError('no more responses');
    return _queue.removeFirst();
  }
}
