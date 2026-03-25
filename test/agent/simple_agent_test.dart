import 'dart:collection';
import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Fake / Mock infrastructure
// ═══════════════════════════════════════════════════════════════════════════════

/// A fake [LmStudioClient] that returns pre-configured [ChatCompletionResponse]
/// objects in order, without performing any real HTTP requests.
///
/// Captured requests can be inspected via [capturedRequests].
class _FakeClient extends LmStudioClient {
  _FakeClient(List<ChatCompletionResponse> responses)
      : _queue = Queue.of(responses),
        super(AgentsCoreConfig(logger: SilentLogger()));

  final Queue<ChatCompletionResponse> _queue;

  /// Every [ChatCompletionRequest] passed to [chatCompletion] is recorded here.
  final List<ChatCompletionRequest> capturedRequests = [];

  @override
  Future<ChatCompletionResponse> chatCompletion(
    ChatCompletionRequest request,
  ) async {
    capturedRequests.add(request);
    if (_queue.isEmpty) throw StateError('_FakeClient: no more responses');
    return _queue.removeFirst();
  }

  @override
  void dispose() {} // no-op — nothing to close
}

/// Builds a minimal [ChatCompletionResponse] for testing.
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

AgentsCoreConfig _silentConfig() => AgentsCoreConfig(logger: SilentLogger());

// ═══════════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  group('SimpleAgent', () {
    // ─────────────────────────────────────────────────────────────────────────
    // Construction
    // ─────────────────────────────────────────────────────────────────────────
    group('construction', () {
      test('can be instantiated with required parameters', () {
        final agent = SimpleAgent(
          name: 'test-agent',
          client: _FakeClient([]),
          config: _silentConfig(),
        );
        expect(agent, isA<SimpleAgent>());
        expect(agent, isA<Agent>());
      });

      test('name is stored correctly', () {
        final agent = SimpleAgent(
          name: 'my-agent',
          client: _FakeClient([]),
          config: _silentConfig(),
        );
        expect(agent.name, equals('my-agent'));
      });

      test('tools default to empty list', () {
        final agent = SimpleAgent(
          name: 'a',
          client: _FakeClient([]),
          config: _silentConfig(),
        );
        expect(agent.tools, isEmpty);
      });

      test('model defaults to null', () {
        final agent = SimpleAgent(
          name: 'a',
          client: _FakeClient([]),
          config: _silentConfig(),
        );
        expect(agent.model, isNull);
      });

      test('systemPrompt defaults to null', () {
        final agent = SimpleAgent(
          name: 'a',
          client: _FakeClient([]),
          config: _silentConfig(),
        );
        expect(agent.systemPrompt, isNull);
      });

      test('defaultModel constant is non-empty', () {
        expect(SimpleAgent.defaultModel, isNotEmpty);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // run() — result fields
    // ─────────────────────────────────────────────────────────────────────────
    group('run() result', () {
      test('returns an AgentResult', () async {
        final agent = SimpleAgent(
          name: 'test',
          client: _FakeClient([_response(content: 'Hi there!')]),
          config: _silentConfig(),
        );
        final result = await agent.run('Say hi');
        expect(result, isA<AgentResult>());
      });

      test('output matches model response content', () async {
        final agent = SimpleAgent(
          name: 'test',
          client: _FakeClient([_response(content: 'Great answer!')]),
          config: _silentConfig(),
        );
        final result = await agent.run('Question?');
        expect(result.output, equals('Great answer!'));
      });

      test('output is empty string when model returns null content', () async {
        final agent = SimpleAgent(
          name: 'test',
          client: _FakeClient([_response(content: null)]),
          config: _silentConfig(),
        );
        final result = await agent.run('Task');
        expect(result.output, equals(''));
      });

      test('tokensUsed equals promptTokens + completionTokens', () async {
        final agent = SimpleAgent(
          name: 'test',
          client: _FakeClient([_response(promptTokens: 20, completionTokens: 10)]),
          config: _silentConfig(),
        );
        final result = await agent.run('Task');
        expect(result.tokensUsed, equals(30));
      });

      test('stoppedReason matches finishReason from response', () async {
        final agent = SimpleAgent(
          name: 'test',
          client: _FakeClient([_response(finishReason: 'stop')]),
          config: _silentConfig(),
        );
        final result = await agent.run('Task');
        expect(result.stoppedReason, equals('stop'));
      });

      test('stoppedReason is null when finishReason is null', () async {
        final agent = SimpleAgent(
          name: 'test',
          client: _FakeClient([_response(finishReason: null)]),
          config: _silentConfig(),
        );
        final result = await agent.run('Task');
        expect(result.stoppedReason, isNull);
      });

      test('filesModified is empty (SimpleAgent performs no file ops)', () async {
        final agent = SimpleAgent(
          name: 'test',
          client: _FakeClient([_response()]),
          config: _silentConfig(),
        );
        final result = await agent.run('Task');
        expect(result.filesModified, isEmpty);
      });

      test('toolCallsMade contains tool calls from response', () async {
        final toolCall = ToolCall(
          id: 'call_1',
          type: 'function',
          function: ToolCallFunction(
            name: 'get_weather',
            arguments: '{"city": "NYC"}',
          ),
        );
        final agent = SimpleAgent(
          name: 'test',
          client: _FakeClient([_response(toolCalls: [toolCall])]),
          config: _silentConfig(),
        );
        final result = await agent.run('Task');
        expect(result.toolCallsMade, hasLength(1));
        expect(result.toolCallsMade.first.id, equals('call_1'));
      });

      test('toolCallsMade is empty when response has no tool calls', () async {
        final agent = SimpleAgent(
          name: 'test',
          client: _FakeClient([_response()]),
          config: _silentConfig(),
        );
        final result = await agent.run('Task');
        expect(result.toolCallsMade, isEmpty);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // run() — request building
    // ─────────────────────────────────────────────────────────────────────────
    group('run() request building', () {
      test('sends exactly one request per run() call', () async {
        final client = _FakeClient([_response()]);
        final agent = SimpleAgent(
          name: 'test',
          client: client,
          config: _silentConfig(),
        );
        await agent.run('Task');
        expect(client.capturedRequests, hasLength(1));
      });

      test('uses SimpleAgent.defaultModel when model is null', () async {
        final client = _FakeClient([_response()]);
        final agent = SimpleAgent(
          name: 'test',
          client: client,
          config: _silentConfig(),
        );
        await agent.run('Task');
        expect(
          client.capturedRequests.first.model,
          equals(SimpleAgent.defaultModel),
        );
      });

      test('uses the provided model identifier', () async {
        final client = _FakeClient([_response()]);
        final agent = SimpleAgent(
          name: 'test',
          client: client,
          config: _silentConfig(),
          model: 'llama-3-8b',
        );
        await agent.run('Task');
        expect(client.capturedRequests.first.model, equals('llama-3-8b'));
      });

      test('user message content matches the task string', () async {
        final client = _FakeClient([_response()]);
        final agent = SimpleAgent(
          name: 'test',
          client: client,
          config: _silentConfig(),
        );
        await agent.run('My specific task');
        final messages = client.capturedRequests.first.messages;
        final userMsg = messages.firstWhere(
          (m) => m.role == ChatMessageRole.user,
        );
        expect(userMsg.content, equals('My specific task'));
      });

      test('no system message when systemPrompt is null', () async {
        final client = _FakeClient([_response()]);
        final agent = SimpleAgent(
          name: 'test',
          client: client,
          config: _silentConfig(),
        );
        await agent.run('Task');
        final messages = client.capturedRequests.first.messages;
        final sysMessages =
            messages.where((m) => m.role == ChatMessageRole.system).toList();
        expect(sysMessages, isEmpty);
      });

      test('system message is included when systemPrompt is set', () async {
        final client = _FakeClient([_response()]);
        final agent = SimpleAgent(
          name: 'test',
          client: client,
          config: _silentConfig(),
          systemPrompt: 'You are a helpful assistant.',
        );
        await agent.run('Task');
        final messages = client.capturedRequests.first.messages;
        final sysMsg = messages.firstWhere(
          (m) => m.role == ChatMessageRole.system,
        );
        expect(sysMsg.content, equals('You are a helpful assistant.'));
      });

      test('system message precedes user message in the list', () async {
        final client = _FakeClient([_response()]);
        final agent = SimpleAgent(
          name: 'test',
          client: client,
          config: _silentConfig(),
          systemPrompt: 'Be concise.',
        );
        await agent.run('Task');
        final messages = client.capturedRequests.first.messages;
        expect(messages[0].role, equals(ChatMessageRole.system));
        expect(messages[1].role, equals(ChatMessageRole.user));
      });

      test('request has exactly 2 messages when systemPrompt is set', () async {
        final client = _FakeClient([_response()]);
        final agent = SimpleAgent(
          name: 'test',
          client: client,
          config: _silentConfig(),
          systemPrompt: 'System prompt.',
        );
        await agent.run('Task');
        expect(client.capturedRequests.first.messages, hasLength(2));
      });

      test('request has exactly 1 message when systemPrompt is null', () async {
        final client = _FakeClient([_response()]);
        final agent = SimpleAgent(
          name: 'test',
          client: client,
          config: _silentConfig(),
        );
        await agent.run('Task');
        expect(client.capturedRequests.first.messages, hasLength(1));
      });

      test('tools are included in request when agent has tools', () async {
        final tool = ToolDefinition(
          name: 'get_weather',
          description: 'Get weather for a city',
          parameters: {
            'type': 'object',
            'properties': {'city': {'type': 'string'}},
            'required': ['city'],
          },
        );
        final client = _FakeClient([_response()]);
        final agent = SimpleAgent(
          name: 'test',
          client: client,
          config: _silentConfig(),
          tools: [tool],
        );
        await agent.run('Task');
        expect(client.capturedRequests.first.tools, isNotNull);
        expect(client.capturedRequests.first.tools, hasLength(1));
        expect(client.capturedRequests.first.tools!.first.name,
            equals('get_weather'));
      });

      test('tools field is null in request when agent has no tools', () async {
        final client = _FakeClient([_response()]);
        final agent = SimpleAgent(
          name: 'test',
          client: client,
          config: _silentConfig(),
        );
        await agent.run('Task');
        expect(client.capturedRequests.first.tools, isNull);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // run() — context parameter
    // ─────────────────────────────────────────────────────────────────────────
    group('run() context parameter', () {
      late Directory tmpDir;

      setUp(() {
        tmpDir = Directory.systemTemp.createTempSync('simple_agent_ctx_');
      });

      tearDown(() => tmpDir.deleteSync(recursive: true));

      test('accepts FileContext without error', () async {
        final ctx = FileContext(workspacePath: tmpDir.path);
        final agent = SimpleAgent(
          name: 'test',
          client: _FakeClient([_response()]),
          config: _silentConfig(),
        );
        final result = await agent.run('Task', context: ctx);
        expect(result, isA<AgentResult>());
      });

      test('output is the same whether context is provided or not', () async {
        final ctx = FileContext(workspacePath: tmpDir.path);

        final agentWithout = SimpleAgent(
          name: 'a',
          client: _FakeClient([_response(content: 'answer')]),
          config: _silentConfig(),
        );
        final agentWith = SimpleAgent(
          name: 'b',
          client: _FakeClient([_response(content: 'answer')]),
          config: _silentConfig(),
        );

        final r1 = await agentWithout.run('Task');
        final r2 = await agentWith.run('Task', context: ctx);
        expect(r1.output, equals(r2.output));
      });

      test('filesModified is empty even with context', () async {
        final ctx = FileContext(workspacePath: tmpDir.path);
        final agent = SimpleAgent(
          name: 'test',
          client: _FakeClient([_response()]),
          config: _silentConfig(),
        );
        final result = await agent.run('Task', context: ctx);
        expect(result.filesModified, isEmpty);
      });
    });
  });
}
