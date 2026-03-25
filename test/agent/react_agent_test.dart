import 'dart:collection';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Fake / Mock infrastructure
// ═══════════════════════════════════════════════════════════════════════════════

/// A fake [LmStudioClient] that returns pre-configured [ChatCompletionResponse]
/// objects in order, without performing any real HTTP requests.
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
  void dispose() {}
}

/// Builds a minimal [ChatCompletionResponse] — text only (no tool calls).
ChatCompletionResponse _textResponse({
  String content = 'Final answer.',
  String? finishReason = 'stop',
  int promptTokens = 10,
  int completionTokens = 5,
}) {
  return ChatCompletionResponse(
    id: 'chatcmpl-text',
    choices: [
      ChatCompletionChoice(
        message: ChatMessage(
          role: ChatMessageRole.assistant,
          content: content,
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

/// Builds a [ChatCompletionResponse] that includes one or more tool calls.
ChatCompletionResponse _toolCallResponse({
  required List<ToolCall> toolCalls,
  String? content,
  String? finishReason = 'tool_calls',
  int promptTokens = 10,
  int completionTokens = 5,
}) {
  return ChatCompletionResponse(
    id: 'chatcmpl-tool',
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

/// Creates a simple [ToolCall] for the given [name] and JSON [arguments].
ToolCall _toolCall({
  required String name,
  String arguments = '{}',
  String id = 'call_001',
}) {
  return ToolCall(
    id: id,
    type: 'function',
    function: ToolCallFunction(name: name, arguments: arguments),
  );
}

/// Creates a [ToolDefinition] with minimal JSON schema.
ToolDefinition _toolDef(String name, {String description = 'A tool'}) {
  return ToolDefinition(
    name: name,
    description: description,
    parameters: {
      'type': 'object',
      'properties': {},
      'required': <String>[],
    },
  );
}

AgentsCoreConfig _silentConfig() => AgentsCoreConfig(logger: SilentLogger());

// ═══════════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  group('ReActAgent', () {
    // ─────────────────────────────────────────────────────────────────────────
    // Construction
    // ─────────────────────────────────────────────────────────────────────────
    group('construction', () {
      test('can be instantiated with required parameters', () {
        final agent = ReActAgent(
          name: 'react',
          client: _FakeClient([]),
          config: _silentConfig(),
          toolHandlers: {},
        );
        expect(agent, isA<ReActAgent>());
        expect(agent, isA<Agent>());
      });

      test('name is stored correctly', () {
        final agent = ReActAgent(
          name: 'my-react',
          client: _FakeClient([]),
          config: _silentConfig(),
          toolHandlers: {},
        );
        expect(agent.name, equals('my-react'));
      });

      test('maxIterations defaults to 10', () {
        final agent = ReActAgent(
          name: 'a',
          client: _FakeClient([]),
          config: _silentConfig(),
          toolHandlers: {},
        );
        expect(agent.maxIterations, equals(10));
      });

      test('maxIterations can be customised', () {
        final agent = ReActAgent(
          name: 'a',
          client: _FakeClient([]),
          config: _silentConfig(),
          toolHandlers: {},
          maxIterations: 3,
        );
        expect(agent.maxIterations, equals(3));
      });

      test('maxTotalTokens defaults to null', () {
        final agent = ReActAgent(
          name: 'a',
          client: _FakeClient([]),
          config: _silentConfig(),
          toolHandlers: {},
        );
        expect(agent.maxTotalTokens, isNull);
      });

      test('defaultModel constant is non-empty', () {
        expect(ReActAgent.defaultModel, isNotEmpty);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Natural completion (no tool calls)
    // ─────────────────────────────────────────────────────────────────────────
    group('natural completion', () {
      test('returns AgentResult with stoppedReason "completed"', () async {
        final agent = ReActAgent(
          name: 'react',
          client: _FakeClient([_textResponse(content: 'Done!')]),
          config: _silentConfig(),
          toolHandlers: {},
        );
        final result = await agent.run('Task');
        expect(result.stoppedReason, equals('completed'));
      });

      test('output matches model response content', () async {
        final agent = ReActAgent(
          name: 'react',
          client: _FakeClient([_textResponse(content: 'My answer.')]),
          config: _silentConfig(),
          toolHandlers: {},
        );
        final result = await agent.run('Task');
        expect(result.output, equals('My answer.'));
      });

      test('sends exactly one request when model responds with no tool calls',
          () async {
        final client = _FakeClient([_textResponse()]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {},
        );
        await agent.run('Task');
        expect(client.capturedRequests, hasLength(1));
      });

      test('toolCallsMade is empty for a pure text response', () async {
        final agent = ReActAgent(
          name: 'react',
          client: _FakeClient([_textResponse()]),
          config: _silentConfig(),
          toolHandlers: {},
        );
        final result = await agent.run('Task');
        expect(result.toolCallsMade, isEmpty);
      });

      test('tokensUsed is the total from the single iteration', () async {
        final agent = ReActAgent(
          name: 'react',
          client: _FakeClient([_textResponse(promptTokens: 20, completionTokens: 10)]),
          config: _silentConfig(),
          toolHandlers: {},
        );
        final result = await agent.run('Task');
        expect(result.tokensUsed, equals(30));
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Tool call then text — 2 iterations
    // ─────────────────────────────────────────────────────────────────────────
    group('tool call then text (2 iterations)', () {
      test('stoppedReason is "completed" after tool call + text', () async {
        final client = _FakeClient([
          _toolCallResponse(toolCalls: [_toolCall(name: 'my_tool')]),
          _textResponse(content: 'All done!'),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'my_tool': (args) async => 'tool result',
          },
        );
        final result = await agent.run('Task');
        expect(result.stoppedReason, equals('completed'));
      });

      test('output is content of final (text) response', () async {
        final client = _FakeClient([
          _toolCallResponse(toolCalls: [_toolCall(name: 'my_tool')]),
          _textResponse(content: 'Final answer!'),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'my_tool': (args) async => 'tool result',
          },
        );
        final result = await agent.run('Task');
        expect(result.output, equals('Final answer!'));
      });

      test('sends exactly 2 requests (one per iteration)', () async {
        final client = _FakeClient([
          _toolCallResponse(toolCalls: [_toolCall(name: 'my_tool')]),
          _textResponse(),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'my_tool': (args) async => 'result',
          },
        );
        await agent.run('Task');
        expect(client.capturedRequests, hasLength(2));
      });

      test('toolCallsMade has exactly 1 entry', () async {
        final client = _FakeClient([
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'my_tool', id: 'call_001')],
          ),
          _textResponse(),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'my_tool': (args) async => 'result',
          },
        );
        final result = await agent.run('Task');
        expect(result.toolCallsMade, hasLength(1));
        expect(result.toolCallsMade.first.id, equals('call_001'));
      });

      test('second request includes tool result message', () async {
        final client = _FakeClient([
          _toolCallResponse(toolCalls: [_toolCall(name: 'echo', id: 'c1')]),
          _textResponse(),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'echo': (args) async => 'echoed',
          },
        );
        await agent.run('Task');
        final secondReqMessages = client.capturedRequests[1].messages;
        final toolMessages = secondReqMessages
            .where((m) => m.role == ChatMessageRole.tool)
            .toList();
        expect(toolMessages, hasLength(1));
        expect(toolMessages.first.content, equals('echoed'));
        expect(toolMessages.first.toolCallId, equals('c1'));
      });

      test('tokensUsed accumulates across both iterations', () async {
        final client = _FakeClient([
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'my_tool')],
            promptTokens: 10,
            completionTokens: 5,
          ),
          _textResponse(promptTokens: 20, completionTokens: 10),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'my_tool': (args) async => 'result',
          },
        );
        final result = await agent.run('Task');
        expect(result.tokensUsed, equals(45)); // 15 + 30
      });

      test('tool handler receives parsed arguments', () async {
        Map<String, dynamic>? capturedArgs;
        final client = _FakeClient([
          _toolCallResponse(
            toolCalls: [
              _toolCall(name: 'greet', arguments: '{"name":"Alice"}'),
            ],
          ),
          _textResponse(),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'greet': (args) async {
              capturedArgs = args;
              return 'Hello, ${args['name']}!';
            },
          },
        );
        await agent.run('Task');
        expect(capturedArgs, isNotNull);
        expect(capturedArgs!['name'], equals('Alice'));
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // maxIterations stops the loop
    // ─────────────────────────────────────────────────────────────────────────
    group('maxIterations limit', () {
      test('stoppedReason is "max_iterations" when limit is reached', () async {
        // 3 tool-call responses but maxIterations = 2 → stops after 2
        final client = _FakeClient([
          _toolCallResponse(toolCalls: [_toolCall(name: 'my_tool')]),
          _toolCallResponse(toolCalls: [_toolCall(name: 'my_tool')]),
          _toolCallResponse(toolCalls: [_toolCall(name: 'my_tool')]),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'my_tool': (args) async => 'result',
          },
          maxIterations: 2,
        );
        final result = await agent.run('Task');
        expect(result.stoppedReason, equals('max_iterations'));
      });

      test('sends exactly maxIterations requests', () async {
        final client = _FakeClient([
          _toolCallResponse(toolCalls: [_toolCall(name: 'my_tool')]),
          _toolCallResponse(toolCalls: [_toolCall(name: 'my_tool')]),
          _toolCallResponse(toolCalls: [_toolCall(name: 'my_tool')]),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'my_tool': (args) async => 'result',
          },
          maxIterations: 2,
        );
        await agent.run('Task');
        expect(client.capturedRequests, hasLength(2));
      });

      test('accumulates all tool calls made before stopping', () async {
        final client = _FakeClient([
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'my_tool', id: 'c1')],
          ),
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'my_tool', id: 'c2')],
          ),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'my_tool': (args) async => 'result',
          },
          maxIterations: 2,
        );
        final result = await agent.run('Task');
        expect(result.toolCallsMade, hasLength(2));
      });

      test('maxIterations = 1 stops after first iteration', () async {
        final client = _FakeClient([
          _toolCallResponse(toolCalls: [_toolCall(name: 'my_tool')]),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'my_tool': (args) async => 'result',
          },
          maxIterations: 1,
        );
        final result = await agent.run('Task');
        expect(result.stoppedReason, equals('max_iterations'));
        expect(client.capturedRequests, hasLength(1));
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Unregistered tool — returns error string to LLM
    // ─────────────────────────────────────────────────────────────────────────
    group('unregistered tool', () {
      test('does not throw — continues the loop', () async {
        final client = _FakeClient([
          _toolCallResponse(toolCalls: [_toolCall(name: 'unknown_tool')]),
          _textResponse(content: 'Recovered.'),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {}, // no handlers registered
        );
        // Should complete normally, not throw
        final result = await agent.run('Task');
        expect(result, isA<AgentResult>());
      });

      test('error string fed back contains the unknown tool name', () async {
        final client = _FakeClient([
          _toolCallResponse(toolCalls: [_toolCall(name: 'phantom_tool')]),
          _textResponse(),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {},
        );
        await agent.run('Task');
        // The second request should contain a tool result message with an error.
        final secondReqMessages = client.capturedRequests[1].messages;
        final toolMsg = secondReqMessages.firstWhere(
          (m) => m.role == ChatMessageRole.tool,
        );
        expect(toolMsg.content?.toLowerCase(), contains('error'));
        expect(toolMsg.content, contains('phantom_tool'));
      });

      test('error string mentions available tools', () async {
        final client = _FakeClient([
          _toolCallResponse(toolCalls: [_toolCall(name: 'nonexistent')]),
          _textResponse(),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'real_tool': (args) async => 'result',
          },
        );
        await agent.run('Task');
        final secondReqMessages = client.capturedRequests[1].messages;
        final toolMsg = secondReqMessages.firstWhere(
          (m) => m.role == ChatMessageRole.tool,
        );
        // The error should mention the available tool
        expect(toolMsg.content, contains('real_tool'));
      });

      test('stoppedReason is still "completed" when loop recovers', () async {
        final client = _FakeClient([
          _toolCallResponse(toolCalls: [_toolCall(name: 'no_such_tool')]),
          _textResponse(content: 'I recovered.'),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {},
        );
        final result = await agent.run('Task');
        expect(result.stoppedReason, equals('completed'));
        expect(result.output, equals('I recovered.'));
      });

      test('unregistered tool call is still recorded in toolCallsMade', () async {
        final client = _FakeClient([
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'ghost_tool', id: 'ghost_1')],
          ),
          _textResponse(),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {},
        );
        final result = await agent.run('Task');
        expect(result.toolCallsMade, hasLength(1));
        expect(result.toolCallsMade.first.id, equals('ghost_1'));
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // maxTotalTokens budget
    // ─────────────────────────────────────────────────────────────────────────
    group('maxTotalTokens budget', () {
      test('stoppedReason is "max_total_tokens" when budget is exceeded', () async {
        // Each response uses 100 tokens; budget is 50 → should stop after iter 1
        final client = _FakeClient([
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'my_tool')],
            promptTokens: 60,
            completionTokens: 40,
          ),
          _textResponse(),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'my_tool': (args) async => 'result',
          },
          maxTotalTokens: 50,
        );
        final result = await agent.run('Task');
        expect(result.stoppedReason, equals('max_total_tokens'));
      });

      test('tokensUsed reflects usage up to the point it stopped', () async {
        final client = _FakeClient([
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'my_tool')],
            promptTokens: 60,
            completionTokens: 40,
          ),
          _textResponse(),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'my_tool': (args) async => 'result',
          },
          maxTotalTokens: 50,
        );
        final result = await agent.run('Task');
        expect(result.tokensUsed, equals(100)); // 60 + 40
      });

      test('null maxTotalTokens never stops for token reason', () async {
        // 3 iterations, each with tool calls; last is text
        final client = _FakeClient([
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'tool')],
            promptTokens: 1000,
            completionTokens: 1000,
          ),
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'tool')],
            promptTokens: 1000,
            completionTokens: 1000,
          ),
          _textResponse(promptTokens: 1000, completionTokens: 1000),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'tool': (args) async => 'result',
          },
          maxTotalTokens: null,
          maxIterations: 10,
        );
        final result = await agent.run('Task');
        // Should complete naturally, not be stopped by token budget
        expect(result.stoppedReason, equals('completed'));
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Multiple tool calls per iteration
    // ─────────────────────────────────────────────────────────────────────────
    group('multiple tool calls per iteration', () {
      test('all tool calls in one response are executed', () async {
        final executedTools = <String>[];
        final client = _FakeClient([
          _toolCallResponse(toolCalls: [
            _toolCall(name: 'tool_a', id: 'c_a'),
            _toolCall(name: 'tool_b', id: 'c_b'),
          ]),
          _textResponse(),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'tool_a': (args) async {
              executedTools.add('tool_a');
              return 'result_a';
            },
            'tool_b': (args) async {
              executedTools.add('tool_b');
              return 'result_b';
            },
          },
        );
        await agent.run('Task');
        expect(executedTools, containsAll(['tool_a', 'tool_b']));
      });

      test('all tool calls are recorded in toolCallsMade', () async {
        final client = _FakeClient([
          _toolCallResponse(toolCalls: [
            _toolCall(name: 'tool_a', id: 'c_a'),
            _toolCall(name: 'tool_b', id: 'c_b'),
          ]),
          _textResponse(),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'tool_a': (args) async => 'a',
            'tool_b': (args) async => 'b',
          },
        );
        final result = await agent.run('Task');
        expect(result.toolCallsMade, hasLength(2));
      });

      test('second request contains tool result messages for all tool calls',
          () async {
        final client = _FakeClient([
          _toolCallResponse(toolCalls: [
            _toolCall(name: 'tool_a', id: 'c_a'),
            _toolCall(name: 'tool_b', id: 'c_b'),
          ]),
          _textResponse(),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'tool_a': (args) async => 'result_a',
            'tool_b': (args) async => 'result_b',
          },
        );
        await agent.run('Task');
        final secondReqMessages = client.capturedRequests[1].messages;
        final toolMessages =
            secondReqMessages.where((m) => m.role == ChatMessageRole.tool).toList();
        expect(toolMessages, hasLength(2));
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Request building
    // ─────────────────────────────────────────────────────────────────────────
    group('request building', () {
      test('uses defaultModel when model is null', () async {
        final client = _FakeClient([_textResponse()]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {},
        );
        await agent.run('Task');
        expect(
          client.capturedRequests.first.model,
          equals(ReActAgent.defaultModel),
        );
      });

      test('uses provided model identifier', () async {
        final client = _FakeClient([_textResponse()]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {},
          model: 'llama-3-8b',
        );
        await agent.run('Task');
        expect(client.capturedRequests.first.model, equals('llama-3-8b'));
      });

      test('first request contains user message with task content', () async {
        final client = _FakeClient([_textResponse()]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {},
        );
        await agent.run('My specific task');
        final messages = client.capturedRequests.first.messages;
        final userMsg =
            messages.firstWhere((m) => m.role == ChatMessageRole.user);
        expect(userMsg.content, equals('My specific task'));
      });

      test('system message is included when systemPrompt is set', () async {
        final client = _FakeClient([_textResponse()]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          systemPrompt: 'You are a researcher.',
          toolHandlers: {},
        );
        await agent.run('Task');
        final messages = client.capturedRequests.first.messages;
        final sysMsg =
            messages.firstWhere((m) => m.role == ChatMessageRole.system);
        expect(sysMsg.content, equals('You are a researcher.'));
      });

      test('tools are passed in the request when agent has tools', () async {
        final client = _FakeClient([_textResponse()]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          tools: [_toolDef('my_tool')],
          toolHandlers: {
            'my_tool': (args) async => 'ok',
          },
        );
        await agent.run('Task');
        expect(client.capturedRequests.first.tools, isNotNull);
        expect(client.capturedRequests.first.tools!.first.name,
            equals('my_tool'));
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Tool handler error handling
    // ─────────────────────────────────────────────────────────────────────────
    group('tool handler exceptions', () {
      test('handler exception is caught and returned as error string', () async {
        final client = _FakeClient([
          _toolCallResponse(toolCalls: [_toolCall(name: 'bad_tool')]),
          _textResponse(),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'bad_tool': (args) async {
              throw Exception('Something went wrong!');
            },
          },
        );
        // Should not throw
        final result = await agent.run('Task');
        expect(result, isA<AgentResult>());
        // The error should be fed back as a tool message
        final secondReqMessages = client.capturedRequests[1].messages;
        final toolMsg = secondReqMessages.firstWhere(
          (m) => m.role == ChatMessageRole.tool,
        );
        expect(toolMsg.content?.toLowerCase(), contains('error'));
      });

      test('invalid JSON arguments are handled gracefully', () async {
        final badToolCall = ToolCall(
          id: 'c1',
          type: 'function',
          function: ToolCallFunction(
            name: 'json_tool',
            arguments: 'NOT_VALID_JSON',
          ),
        );
        final client = _FakeClient([
          _toolCallResponse(toolCalls: [badToolCall]),
          _textResponse(),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'json_tool': (args) async => 'ok',
          },
        );
        // Must not throw
        final result = await agent.run('Task');
        expect(result, isA<AgentResult>());
        final secondReqMessages = client.capturedRequests[1].messages;
        final toolMsg = secondReqMessages.firstWhere(
          (m) => m.role == ChatMessageRole.tool,
        );
        expect(toolMsg.content?.toLowerCase(), contains('error'));
      });

      test('empty arguments string is treated as empty map', () async {
        Map<String, dynamic>? receivedArgs;
        final emptyArgToolCall = ToolCall(
          id: 'c1',
          type: 'function',
          function: ToolCallFunction(name: 'no_arg_tool', arguments: ''),
        );
        final client = _FakeClient([
          _toolCallResponse(toolCalls: [emptyArgToolCall]),
          _textResponse(),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'no_arg_tool': (args) async {
              receivedArgs = args;
              return 'ok';
            },
          },
        );
        await agent.run('Task');
        expect(receivedArgs, equals(<String, dynamic>{}));
      });
    });
  });
}
