import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

import '../helpers/mock_llm_client.dart';

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
        message: ChatMessage(role: ChatMessageRole.assistant, content: content),
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
    parameters: {'type': 'object', 'properties': {}, 'required': <String>[]},
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
          client: MockLlmClient([]),
          config: _silentConfig(),
          toolHandlers: {},
        );
        expect(agent, isA<ReActAgent>());
        expect(agent, isA<Agent>());
      });

      test('name is stored correctly', () {
        final agent = ReActAgent(
          name: 'my-react',
          client: MockLlmClient([]),
          config: _silentConfig(),
          toolHandlers: {},
        );
        expect(agent.name, equals('my-react'));
      });

      test('maxIterations defaults to 10', () {
        final agent = ReActAgent(
          name: 'a',
          client: MockLlmClient([]),
          config: _silentConfig(),
          toolHandlers: {},
        );
        expect(agent.maxIterations, equals(10));
      });

      test('maxIterations can be customised', () {
        final agent = ReActAgent(
          name: 'a',
          client: MockLlmClient([]),
          config: _silentConfig(),
          toolHandlers: {},
          maxIterations: 3,
        );
        expect(agent.maxIterations, equals(3));
      });

      test('maxTotalTokens defaults to null', () {
        final agent = ReActAgent(
          name: 'a',
          client: MockLlmClient([]),
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
      test('returns AgentResult with stoppedReason completed', () async {
        final agent = ReActAgent(
          name: 'react',
          client: MockLlmClient([_textResponse(content: 'Done!')]),
          config: _silentConfig(),
          toolHandlers: {},
        );
        final result = await agent.run('Task');
        expect(result.stoppedReason, equals(AgentStopReason.completed));
      });

      test('output matches model response content', () async {
        final agent = ReActAgent(
          name: 'react',
          client: MockLlmClient([_textResponse(content: 'My answer.')]),
          config: _silentConfig(),
          toolHandlers: {},
        );
        final result = await agent.run('Task');
        expect(result.output, equals('My answer.'));
      });

      test(
        'sends exactly one request when model responds with no tool calls',
        () async {
          final client = MockLlmClient([_textResponse()]);
          final agent = ReActAgent(
            name: 'react',
            client: client,
            config: _silentConfig(),
            toolHandlers: {},
          );
          await agent.run('Task');
          expect(client.capturedRequests, hasLength(1));
        },
      );

      test('toolCallsMade is empty for a pure text response', () async {
        final agent = ReActAgent(
          name: 'react',
          client: MockLlmClient([_textResponse()]),
          config: _silentConfig(),
          toolHandlers: {},
        );
        final result = await agent.run('Task');
        expect(result.toolCallsMade, isEmpty);
      });

      test('tokensUsed is the total from the single iteration', () async {
        final agent = ReActAgent(
          name: 'react',
          client: MockLlmClient([
            _textResponse(promptTokens: 20, completionTokens: 10),
          ]),
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
      test('stoppedReason is completed after tool call + text', () async {
        final client = MockLlmClient([
          _toolCallResponse(toolCalls: [_toolCall(name: 'my_tool')]),
          _textResponse(content: 'All done!'),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {'my_tool': (args) async => 'tool result'},
        );
        final result = await agent.run('Task');
        expect(result.stoppedReason, equals(AgentStopReason.completed));
      });

      test('output is content of final (text) response', () async {
        final client = MockLlmClient([
          _toolCallResponse(toolCalls: [_toolCall(name: 'my_tool')]),
          _textResponse(content: 'Final answer!'),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {'my_tool': (args) async => 'tool result'},
        );
        final result = await agent.run('Task');
        expect(result.output, equals('Final answer!'));
      });

      test('sends exactly 2 requests (one per iteration)', () async {
        final client = MockLlmClient([
          _toolCallResponse(toolCalls: [_toolCall(name: 'my_tool')]),
          _textResponse(),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {'my_tool': (args) async => 'result'},
        );
        await agent.run('Task');
        expect(client.capturedRequests, hasLength(2));
      });

      test('toolCallsMade has exactly 1 entry', () async {
        final client = MockLlmClient([
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'my_tool', id: 'call_001')],
          ),
          _textResponse(),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {'my_tool': (args) async => 'result'},
        );
        final result = await agent.run('Task');
        expect(result.toolCallsMade, hasLength(1));
        expect(result.toolCallsMade.first.id, equals('call_001'));
      });

      test('second request includes tool result message', () async {
        final client = MockLlmClient([
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'echo', id: 'c1')],
          ),
          _textResponse(),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {'echo': (args) async => 'echoed'},
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
        final client = MockLlmClient([
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
          toolHandlers: {'my_tool': (args) async => 'result'},
        );
        final result = await agent.run('Task');
        expect(result.tokensUsed, equals(45)); // 15 + 30
      });

      test('tool handler receives parsed arguments', () async {
        Map<String, dynamic>? capturedArgs;
        final client = MockLlmClient([
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
      test('stoppedReason is maxIterations when limit is reached', () async {
        // 3 tool-call responses but maxIterations = 2 → stops after 2
        final client = MockLlmClient([
          _toolCallResponse(toolCalls: [_toolCall(name: 'my_tool')]),
          _toolCallResponse(toolCalls: [_toolCall(name: 'my_tool')]),
          _toolCallResponse(toolCalls: [_toolCall(name: 'my_tool')]),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {'my_tool': (args) async => 'result'},
          maxIterations: 2,
        );
        final result = await agent.run('Task');
        expect(result.stoppedReason, equals(AgentStopReason.maxIterations));
      });

      test('sends exactly maxIterations requests', () async {
        final client = MockLlmClient([
          _toolCallResponse(toolCalls: [_toolCall(name: 'my_tool')]),
          _toolCallResponse(toolCalls: [_toolCall(name: 'my_tool')]),
          _toolCallResponse(toolCalls: [_toolCall(name: 'my_tool')]),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {'my_tool': (args) async => 'result'},
          maxIterations: 2,
        );
        await agent.run('Task');
        expect(client.capturedRequests, hasLength(2));
      });

      test('accumulates all tool calls made before stopping', () async {
        final client = MockLlmClient([
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
          toolHandlers: {'my_tool': (args) async => 'result'},
          maxIterations: 2,
        );
        final result = await agent.run('Task');
        expect(result.toolCallsMade, hasLength(2));
      });

      test('maxIterations = 1 stops after first iteration', () async {
        final client = MockLlmClient([
          _toolCallResponse(toolCalls: [_toolCall(name: 'my_tool')]),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {'my_tool': (args) async => 'result'},
          maxIterations: 1,
        );
        final result = await agent.run('Task');
        expect(result.stoppedReason, equals(AgentStopReason.maxIterations));
        expect(client.capturedRequests, hasLength(1));
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Unregistered tool — returns error string to LLM
    // ─────────────────────────────────────────────────────────────────────────
    group('unregistered tool', () {
      test('does not throw — continues the loop', () async {
        final client = MockLlmClient([
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
        final client = MockLlmClient([
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
        final client = MockLlmClient([
          _toolCallResponse(toolCalls: [_toolCall(name: 'nonexistent')]),
          _textResponse(),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {'real_tool': (args) async => 'result'},
        );
        await agent.run('Task');
        final secondReqMessages = client.capturedRequests[1].messages;
        final toolMsg = secondReqMessages.firstWhere(
          (m) => m.role == ChatMessageRole.tool,
        );
        // The error should mention the available tool
        expect(toolMsg.content, contains('real_tool'));
      });

      test('stoppedReason is still completed when loop recovers', () async {
        final client = MockLlmClient([
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
        expect(result.stoppedReason, equals(AgentStopReason.completed));
        expect(result.output, equals('I recovered.'));
      });

      test(
        'unregistered tool call is still recorded in toolCallsMade',
        () async {
          final client = MockLlmClient([
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
        },
      );
    });

    // ─────────────────────────────────────────────────────────────────────────
    // maxTotalTokens budget
    // ─────────────────────────────────────────────────────────────────────────
    group('maxTotalTokens budget', () {
      test('stoppedReason is maxTotalTokens when budget is exceeded', () async {
        // Each response uses 100 tokens; budget is 50 → should stop after iter 1
        final client = MockLlmClient([
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
          toolHandlers: {'my_tool': (args) async => 'result'},
          maxTotalTokens: 50,
        );
        final result = await agent.run('Task');
        expect(result.stoppedReason, equals(AgentStopReason.maxTotalTokens));
      });

      test('tokensUsed reflects usage up to the point it stopped', () async {
        final client = MockLlmClient([
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
          toolHandlers: {'my_tool': (args) async => 'result'},
          maxTotalTokens: 50,
        );
        final result = await agent.run('Task');
        expect(result.tokensUsed, equals(100)); // 60 + 40
      });

      test('null maxTotalTokens never stops for token reason', () async {
        // 3 iterations, each with tool calls; last is text
        final client = MockLlmClient([
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
          toolHandlers: {'tool': (args) async => 'result'},
          maxTotalTokens: null,
          maxIterations: 10,
        );
        final result = await agent.run('Task');
        // Should complete naturally, not be stopped by token budget
        expect(result.stoppedReason, equals(AgentStopReason.completed));
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Multiple tool calls per iteration
    // ─────────────────────────────────────────────────────────────────────────
    group('multiple tool calls per iteration', () {
      test('all tool calls in one response are executed', () async {
        final executedTools = <String>[];
        final client = MockLlmClient([
          _toolCallResponse(
            toolCalls: [
              _toolCall(name: 'tool_a', id: 'c_a'),
              _toolCall(name: 'tool_b', id: 'c_b'),
            ],
          ),
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
        final client = MockLlmClient([
          _toolCallResponse(
            toolCalls: [
              _toolCall(name: 'tool_a', id: 'c_a'),
              _toolCall(name: 'tool_b', id: 'c_b'),
            ],
          ),
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

      test(
        'second request contains tool result messages for all tool calls',
        () async {
          final client = MockLlmClient([
            _toolCallResponse(
              toolCalls: [
                _toolCall(name: 'tool_a', id: 'c_a'),
                _toolCall(name: 'tool_b', id: 'c_b'),
              ],
            ),
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
          final toolMessages = secondReqMessages
              .where((m) => m.role == ChatMessageRole.tool)
              .toList();
          expect(toolMessages, hasLength(2));
        },
      );
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Request building
    // ─────────────────────────────────────────────────────────────────────────
    group('request building', () {
      test('uses defaultModel when model is null', () async {
        final client = MockLlmClient([_textResponse()]);
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
        final client = MockLlmClient([_textResponse()]);
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
        final client = MockLlmClient([_textResponse()]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {},
        );
        await agent.run('My specific task');
        final messages = client.capturedRequests.first.messages;
        final userMsg = messages.firstWhere(
          (m) => m.role == ChatMessageRole.user,
        );
        expect(userMsg.content, equals('My specific task'));
      });

      test('system message is included when systemPrompt is set', () async {
        final client = MockLlmClient([_textResponse()]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          systemPrompt: 'You are a researcher.',
          toolHandlers: {},
        );
        await agent.run('Task');
        final messages = client.capturedRequests.first.messages;
        final sysMsg = messages.firstWhere(
          (m) => m.role == ChatMessageRole.system,
        );
        expect(sysMsg.content, equals('You are a researcher.'));
      });

      test('tools are passed in the request when agent has tools', () async {
        final client = MockLlmClient([_textResponse()]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          tools: [_toolDef('my_tool')],
          toolHandlers: {'my_tool': (args) async => 'ok'},
        );
        await agent.run('Task');
        expect(client.capturedRequests.first.tools, isNotNull);
        expect(
          client.capturedRequests.first.tools!.first.name,
          equals('my_tool'),
        );
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Tool handler error handling
    // ─────────────────────────────────────────────────────────────────────────
    group('tool handler exceptions', () {
      test(
        'handler exception is caught and returned as error string',
        () async {
          final client = MockLlmClient([
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
        },
      );

      test('invalid JSON arguments are handled gracefully', () async {
        final badToolCall = ToolCall(
          id: 'c1',
          type: 'function',
          function: ToolCallFunction(
            name: 'json_tool',
            arguments: 'NOT_VALID_JSON',
          ),
        );
        final client = MockLlmClient([
          _toolCallResponse(toolCalls: [badToolCall]),
          _textResponse(),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {'json_tool': (args) async => 'ok'},
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
        final client = MockLlmClient([
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

    // ─────────────────────────────────────────────────────────────────────────
    // Loop detection
    // ─────────────────────────────────────────────────────────────────────────
    group('loop detection', () {
      test('3 identical tool-call signatures → stoppedReason loopDetected '
          'with exactly 3 requests', () async {
        final client = MockLlmClient([
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'search', arguments: '{"q":"dart"}')],
          ),
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'search', arguments: '{"q":"dart"}')],
          ),
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'search', arguments: '{"q":"dart"}')],
          ),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {'search': (args) async => 'no results'},
          maxIterations: 10,
          loopDetectionConfig: const LoopDetectionConfig(
            maxConsecutiveIdenticalToolCalls: 3,
          ),
        );
        final result = await agent.run('Find info');
        expect(result.stoppedReason, equals(AgentStopReason.loopDetected));
        expect(client.capturedRequests, hasLength(3));
      });

      test('3 different tool calls → normal completion', () async {
        final client = MockLlmClient([
          _toolCallResponse(
            toolCalls: [
              _toolCall(name: 'search', arguments: '{"q":"a"}', id: 'c1'),
            ],
          ),
          _toolCallResponse(
            toolCalls: [
              _toolCall(name: 'fetch', arguments: '{"url":"b"}', id: 'c2'),
            ],
          ),
          _toolCallResponse(
            toolCalls: [
              _toolCall(name: 'parse', arguments: '{"data":"c"}', id: 'c3'),
            ],
          ),
          _textResponse(content: 'Done'),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'search': (args) async => 'result a',
            'fetch': (args) async => 'result b',
            'parse': (args) async => 'result c',
          },
          maxIterations: 10,
          loopDetectionConfig: const LoopDetectionConfig(
            maxConsecutiveIdenticalToolCalls: 3,
          ),
        );
        final result = await agent.run('Task');
        expect(result.stoppedReason, equals(AgentStopReason.completed));
      });

      test('3 identical output texts → stoppedReason loopDetected', () async {
        // Tool calls are different each iteration, but the assistant content
        // text is identical — the output-repetition detector should trigger.
        final client = MockLlmClient([
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'tool_a', id: 'c1')],
            content: 'I will try again',
          ),
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'tool_b', id: 'c2')],
            content: 'I will try again',
          ),
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'tool_c', id: 'c3')],
            content: 'I will try again',
          ),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'tool_a': (args) async => 'result a',
            'tool_b': (args) async => 'result b',
            'tool_c': (args) async => 'result c',
          },
          maxIterations: 10,
          loopDetectionConfig: const LoopDetectionConfig(
            maxConsecutiveIdenticalOutputs: 3,
          ),
        );
        final result = await agent.run('Task');
        expect(result.stoppedReason, equals(AgentStopReason.loopDetected));
      });

      test(
        'null loopDetectionConfig → falls through to max_iterations',
        () async {
          // Same tool calls repeated, but no loop detection configured.
          final client = MockLlmClient([
            _toolCallResponse(
              toolCalls: [_toolCall(name: 'search', arguments: '{"q":"dart"}')],
            ),
            _toolCallResponse(
              toolCalls: [_toolCall(name: 'search', arguments: '{"q":"dart"}')],
            ),
            _toolCallResponse(
              toolCalls: [_toolCall(name: 'search', arguments: '{"q":"dart"}')],
            ),
          ]);
          final agent = ReActAgent(
            name: 'react',
            client: client,
            config: _silentConfig(),
            toolHandlers: {'search': (args) async => 'no results'},
            maxIterations: 3,
            loopDetectionConfig: null,
          );
          final result = await agent.run('Find info');
          expect(result.stoppedReason, equals(AgentStopReason.maxIterations));
          expect(client.capturedRequests, hasLength(3));
        },
      );

      test('threshold 0 → detection disabled '
          '(falls through to max_iterations)', () async {
        // With both consecutive-identical thresholds set to 0, loop
        // detection is effectively disabled — identical patterns should
        // not trigger early termination.
        final client = MockLlmClient([
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'search', arguments: '{"q":"dart"}')],
          ),
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'search', arguments: '{"q":"dart"}')],
          ),
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'search', arguments: '{"q":"dart"}')],
          ),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {'search': (args) async => 'no results'},
          maxIterations: 3,
          loopDetectionConfig: const LoopDetectionConfig(
            maxConsecutiveIdenticalToolCalls: 0,
            maxConsecutiveIdenticalOutputs: 0,
          ),
        );
        final result = await agent.run('Find info');
        expect(result.stoppedReason, equals(AgentStopReason.maxIterations));
        expect(client.capturedRequests, hasLength(3));
      });

      test('default LoopDetectionConfig() with identical tool calls → '
          'stoppedReason loopDetected after 3 iterations', () async {
        // Manual verification: construct a ReActAgent with the default
        // LoopDetectionConfig() (no arguments) and a mock client that
        // returns the same tool call every iteration. The agent must stop
        // with stoppedReason loopDetected after exactly 3 requests —
        // matching the default maxConsecutiveIdenticalToolCalls of 3.
        final identicalToolCall = _toolCall(
          name: 'lookup',
          arguments: '{"key":"value"}',
        );

        final client = MockLlmClient([
          _toolCallResponse(toolCalls: [identicalToolCall]),
          _toolCallResponse(toolCalls: [identicalToolCall]),
          _toolCallResponse(toolCalls: [identicalToolCall]),
        ]);

        final agent = ReActAgent(
          name: 'verifier',
          client: client,
          config: _silentConfig(),
          toolHandlers: {'lookup': (args) async => 'result'},
          maxIterations: 10,
          loopDetectionConfig:
              const LoopDetectionConfig(), // all defaults (threshold = 3)
        );

        final result = await agent.run('Do the task');

        expect(
          result.stoppedReason,
          equals(AgentStopReason.loopDetected),
          reason: 'Should stop due to loop, not max_iterations',
        );
        expect(
          client.capturedRequests,
          hasLength(3),
          reason: 'Loop detected after exactly 3 identical tool calls',
        );
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // Terminal tools
    // ─────────────────────────────────────────────────────────────────────────
    group('terminal tools', () {
      test('terminalTools defaults to an empty set', () {
        final agent = ReActAgent(
          name: 'a',
          client: MockLlmClient([]),
          config: _silentConfig(),
          toolHandlers: {},
        );
        expect(agent.terminalTools, isEmpty);
      });

      test('terminalTools can be set via constructor', () {
        final agent = ReActAgent(
          name: 'a',
          client: MockLlmClient([]),
          config: _silentConfig(),
          toolHandlers: {},
          terminalTools: {'submit_result', 'done'},
        );
        expect(agent.terminalTools, containsAll(['submit_result', 'done']));
      });

      test(
        'stoppedReason is terminalTool when a terminal tool is called',
        () async {
          final client = MockLlmClient([
            _toolCallResponse(
              toolCalls: [_toolCall(name: 'submit_result', id: 'c1')],
            ),
          ]);
          final agent = ReActAgent(
            name: 'react',
            client: client,
            config: _silentConfig(),
            toolHandlers: {'submit_result': (args) async => 'submitted'},
            terminalTools: {'submit_result'},
            maxIterations: 10,
          );
          final result = await agent.run('Task');
          expect(result.stoppedReason, equals(AgentStopReason.terminalTool));
        },
      );

      test('terminal tool handler is executed before stopping', () async {
        var handlerCalled = false;
        final client = MockLlmClient([
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'submit', id: 'c1')],
          ),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'submit': (args) async {
              handlerCalled = true;
              return 'done';
            },
          },
          terminalTools: {'submit'},
          maxIterations: 10,
        );
        await agent.run('Task');
        expect(handlerCalled, isTrue);
      });

      test(
        'loop stops after 1 iteration when terminal tool is called',
        () async {
          final client = MockLlmClient([
            _toolCallResponse(
              toolCalls: [_toolCall(name: 'finish', id: 'c1')],
            ),
            // This response should never be reached.
            _textResponse(content: 'Should not see this'),
          ]);
          final agent = ReActAgent(
            name: 'react',
            client: client,
            config: _silentConfig(),
            toolHandlers: {'finish': (args) async => 'finished'},
            terminalTools: {'finish'},
            maxIterations: 10,
          );
          await agent.run('Task');
          expect(client.capturedRequests, hasLength(1));
        },
      );

      test('terminal tool call is recorded in toolCallsMade', () async {
        final client = MockLlmClient([
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'submit', id: 'submit_1')],
          ),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {'submit': (args) async => 'ok'},
          terminalTools: {'submit'},
          maxIterations: 10,
        );
        final result = await agent.run('Task');
        expect(result.toolCallsMade, hasLength(1));
        expect(result.toolCallsMade.first.id, equals('submit_1'));
      });

      test('non-terminal tool calls proceed normally', () async {
        final client = MockLlmClient([
          _toolCallResponse(
            toolCalls: [_toolCall(name: 'search', id: 'c1')],
          ),
          _textResponse(content: 'Done searching'),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {'search': (args) async => 'results'},
          terminalTools: {'submit'}, // 'search' is NOT terminal
          maxIterations: 10,
        );
        final result = await agent.run('Task');
        expect(result.stoppedReason, equals(AgentStopReason.completed));
        expect(client.capturedRequests, hasLength(2));
      });

      test('terminal tool among multiple tool calls in same iteration '
          'stops the loop', () async {
        final client = MockLlmClient([
          _toolCallResponse(
            toolCalls: [
              _toolCall(name: 'search', id: 'c1'),
              _toolCall(name: 'submit', id: 'c2'),
            ],
          ),
          // Should never be reached.
          _textResponse(content: 'unreachable'),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'search': (args) async => 'results',
            'submit': (args) async => 'submitted',
          },
          terminalTools: {'submit'},
          maxIterations: 10,
        );
        final result = await agent.run('Task');
        expect(result.stoppedReason, equals(AgentStopReason.terminalTool));
        expect(result.toolCallsMade, hasLength(2));
        expect(client.capturedRequests, hasLength(1));
      });

      test('all tool handlers in the iteration are executed even when '
          'one is terminal', () async {
        final executedTools = <String>[];
        final client = MockLlmClient([
          _toolCallResponse(
            toolCalls: [
              _toolCall(name: 'gather', id: 'c1'),
              _toolCall(name: 'submit', id: 'c2'),
            ],
          ),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {
            'gather': (args) async {
              executedTools.add('gather');
              return 'gathered';
            },
            'submit': (args) async {
              executedTools.add('submit');
              return 'submitted';
            },
          },
          terminalTools: {'submit'},
          maxIterations: 10,
        );
        await agent.run('Task');
        expect(executedTools, equals(['gather', 'submit']));
      });

      test(
        'normal iterations followed by terminal tool stops correctly',
        () async {
          final client = MockLlmClient([
            _toolCallResponse(
              toolCalls: [_toolCall(name: 'search', id: 'c1')],
            ),
            _toolCallResponse(
              toolCalls: [_toolCall(name: 'analyze', id: 'c2')],
            ),
            _toolCallResponse(
              toolCalls: [_toolCall(name: 'submit', id: 'c3')],
            ),
            // Should not be reached.
            _textResponse(content: 'unreachable'),
          ]);
          final agent = ReActAgent(
            name: 'react',
            client: client,
            config: _silentConfig(),
            toolHandlers: {
              'search': (args) async => 'found',
              'analyze': (args) async => 'analyzed',
              'submit': (args) async => 'submitted',
            },
            terminalTools: {'submit'},
            maxIterations: 10,
          );
          final result = await agent.run('Task');
          expect(result.stoppedReason, equals(AgentStopReason.terminalTool));
          expect(client.capturedRequests, hasLength(3));
          expect(result.toolCallsMade, hasLength(3));
        },
      );

      test(
        'tokensUsed accumulates up to the terminal tool iteration',
        () async {
          final client = MockLlmClient([
            _toolCallResponse(
              toolCalls: [_toolCall(name: 'search', id: 'c1')],
              promptTokens: 10,
              completionTokens: 5,
            ),
            _toolCallResponse(
              toolCalls: [_toolCall(name: 'submit', id: 'c2')],
              promptTokens: 20,
              completionTokens: 10,
            ),
          ]);
          final agent = ReActAgent(
            name: 'react',
            client: client,
            config: _silentConfig(),
            toolHandlers: {
              'search': (args) async => 'found',
              'submit': (args) async => 'done',
            },
            terminalTools: {'submit'},
            maxIterations: 10,
          );
          final result = await agent.run('Task');
          expect(result.tokensUsed, equals(45)); // 15 + 30
        },
      );

      test('empty terminalTools set has no effect on normal flow', () async {
        final client = MockLlmClient([
          _toolCallResponse(toolCalls: [_toolCall(name: 'my_tool')]),
          _textResponse(content: 'Done'),
        ]);
        final agent = ReActAgent(
          name: 'react',
          client: client,
          config: _silentConfig(),
          toolHandlers: {'my_tool': (args) async => 'result'},
          terminalTools: {},
          maxIterations: 10,
        );
        final result = await agent.run('Task');
        expect(result.stoppedReason, equals(AgentStopReason.completed));
      });
    });
  });
}
