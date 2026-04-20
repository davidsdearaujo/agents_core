// Tests for the AgentStopReason enum (P1 migration — magic-string elimination).
//
// Verifies:
//  - All expected enum cases exist with the correct names.
//  - The enum is exported from the barrel and usable via package import.
//  - AgentResult.stoppedReason is typed AgentStopReason? (not String).
//  - ReActAgent.run() assigns the correct enum value for every stop path.
//  - SimpleAgent.run() always returns null stoppedReason (no loop managed).

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

import '../helpers/mock_llm_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Response builders
// ─────────────────────────────────────────────────────────────────────────────

ChatCompletionResponse _text({String content = 'Done', int tokens = 10}) =>
    ChatCompletionResponse(
      id: 'cmpl-t',
      choices: [
        ChatCompletionChoice(
          message: ChatMessage(
            role: ChatMessageRole.assistant,
            content: content,
          ),
          finishReason: 'stop',
        ),
      ],
      usage: CompletionUsage(
        promptTokens: tokens ~/ 2,
        completionTokens: tokens ~/ 2,
        totalTokens: tokens,
      ),
    );

ChatCompletionResponse _toolCall({
  String toolName = 'my_tool',
  String args = '{}',
  int tokens = 10,
}) => ChatCompletionResponse(
  id: 'cmpl-tc',
  choices: [
    ChatCompletionChoice(
      message: ChatMessage(
        role: ChatMessageRole.assistant,
        content: null,
        toolCalls: [
          ToolCall(
            id: 'call_1',
            type: 'function',
            function: ToolCallFunction(name: toolName, arguments: args),
          ),
        ],
      ),
      finishReason: 'tool_calls',
    ),
  ],
  usage: CompletionUsage(
    promptTokens: tokens ~/ 2,
    completionTokens: tokens ~/ 2,
    totalTokens: tokens,
  ),
);

AgentsCoreConfig _config() => AgentsCoreConfig(logger: SilentLogger());

// ═══════════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════════

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // Enum definition
  // ─────────────────────────────────────────────────────────────────────────
  group('AgentStopReason enum', () {
    group('barrel export', () {
      test('AgentStopReason is accessible from package:agents_core', () {
        const reason = AgentStopReason.completed;
        expect(reason, isA<AgentStopReason>());
      });
    });

    group('enum values', () {
      test('completed value exists', () {
        expect(AgentStopReason.completed, isA<AgentStopReason>());
      });

      test('maxIterations value exists', () {
        expect(AgentStopReason.maxIterations, isA<AgentStopReason>());
      });

      test('maxTotalTokens value exists', () {
        expect(AgentStopReason.maxTotalTokens, isA<AgentStopReason>());
      });

      test('terminalTool value exists', () {
        expect(AgentStopReason.terminalTool, isA<AgentStopReason>());
      });

      test('loopDetected value exists', () {
        expect(AgentStopReason.loopDetected, isA<AgentStopReason>());
      });

      test('accepted value exists', () {
        // accepted is used by AgentLoop (reviewer accepting output)
        expect(AgentStopReason.accepted, isA<AgentStopReason>());
      });

      test('has exactly 6 values', () {
        expect(AgentStopReason.values, hasLength(6));
      });

      test('values are all distinct', () {
        final set = AgentStopReason.values.toSet();
        expect(set.length, equals(AgentStopReason.values.length));
      });
    });

    group('identity and equality', () {
      test('same value is equal to itself', () {
        expect(AgentStopReason.completed, equals(AgentStopReason.completed));
      });

      test('different values are not equal', () {
        expect(
          AgentStopReason.completed,
          isNot(equals(AgentStopReason.maxIterations)),
        );
      });

      test('enum is not equal to its name string', () {
        // The whole point of the P1 migration: enum != raw String.
        // ignore: unrelated_type_equality_checks
        expect(AgentStopReason.completed == 'completed', isFalse);
      });

      test('switch is exhaustive — all cases handled without default', () {
        // This test verifies Dart compiles a switch statement that covers
        // every AgentStopReason value. If a new value were added without
        // updating callers, the Dart compiler would emit a warning (with
        // sealed types or exhaustiveness checking enabled).
        String describe(AgentStopReason r) {
          return switch (r) {
            AgentStopReason.completed => 'completed',
            AgentStopReason.maxIterations => 'maxIterations',
            AgentStopReason.maxTotalTokens => 'maxTotalTokens',
            AgentStopReason.terminalTool => 'terminalTool',
            AgentStopReason.loopDetected => 'loopDetected',
            AgentStopReason.accepted => 'accepted',
          };
        }

        for (final r in AgentStopReason.values) {
          expect(describe(r), isNotEmpty);
        }
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // AgentResult.stoppedReason is typed AgentStopReason? (not String)
  // ─────────────────────────────────────────────────────────────────────────
  group('AgentResult.stoppedReason type', () {
    test('accepts AgentStopReason.completed', () {
      const result = AgentResult(
        output: 'ok',
        stoppedReason: AgentStopReason.completed,
      );
      expect(result.stoppedReason, equals(AgentStopReason.completed));
    });

    test('accepts null', () {
      const result = AgentResult(output: 'ok');
      expect(result.stoppedReason, isNull);
    });

    test('stoppedReason is AgentStopReason? (not String?)', () {
      const result = AgentResult(
        output: 'ok',
        stoppedReason: AgentStopReason.maxIterations,
      );
      // Type-safe: can only be AgentStopReason or null, never a bare String.
      final AgentStopReason? typed = result.stoppedReason;
      expect(typed, equals(AgentStopReason.maxIterations));
    });

    test('toString includes the enum value name', () {
      const result = AgentResult(
        output: 'hello',
        stoppedReason: AgentStopReason.loopDetected,
      );
      expect(result.toString(), contains('loopDetected'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // ReActAgent assigns correct enum values for each stop path
  // ─────────────────────────────────────────────────────────────────────────
  group('ReActAgent stoppedReason — enum values', () {
    test('completed — model returns text without tool calls', () async {
      final agent = ReActAgent(
        name: 'a',
        client: MockLlmClient([_text(content: 'Done')]),
        config: _config(),
        toolHandlers: {},
      );
      final result = await agent.run('task');
      expect(result.stoppedReason, equals(AgentStopReason.completed));
      expect(result.stoppedReason, isA<AgentStopReason>());
    });

    test('maxIterations — tool calls exhaust the limit', () async {
      final agent = ReActAgent(
        name: 'a',
        client: MockLlmClient([_toolCall(), _toolCall(), _toolCall()]),
        config: _config(),
        toolHandlers: {'my_tool': (_) async => 'result'},
        maxIterations: 2,
      );
      final result = await agent.run('task');
      expect(result.stoppedReason, equals(AgentStopReason.maxIterations));
    });

    test('maxTotalTokens — cumulative token budget exceeded', () async {
      final agent = ReActAgent(
        name: 'a',
        // Each tool-call response costs 20 tokens → first iteration hits 20,
        // which exceeds the budget of 15.
        client: MockLlmClient([_toolCall(tokens: 20), _toolCall(tokens: 20)]),
        config: _config(),
        toolHandlers: {'my_tool': (_) async => 'result'},
        maxTotalTokens: 15,
      );
      final result = await agent.run('task');
      expect(result.stoppedReason, equals(AgentStopReason.maxTotalTokens));
    });

    test('terminalTool — loop stops after a terminal tool is called', () async {
      final agent = ReActAgent(
        name: 'a',
        client: MockLlmClient([_toolCall(toolName: 'submit')]),
        config: _config(),
        toolHandlers: {'submit': (_) async => 'submitted'},
        terminalTools: {'submit'},
        tools: [
          ToolDefinition(
            name: 'submit',
            description: 'Submit final answer',
            parameters: {'type': 'object', 'properties': <String, dynamic>{}},
          ),
        ],
      );
      final result = await agent.run('task');
      expect(result.stoppedReason, equals(AgentStopReason.terminalTool));
    });

    test(
      'loopDetected — identical tool calls trigger loop detection',
      () async {
        // Feed 5 identical tool calls; LoopDetectionConfig defaults to
        // maxConsecutiveIdenticalToolCalls = 3, so should stop on 3rd.
        final agent = ReActAgent(
          name: 'a',
          client: MockLlmClient([
            _toolCall(args: '{"q":"dart"}'),
            _toolCall(args: '{"q":"dart"}'),
            _toolCall(args: '{"q":"dart"}'),
            _toolCall(args: '{"q":"dart"}'),
            _toolCall(args: '{"q":"dart"}'),
          ]),
          config: _config(),
          toolHandlers: {'my_tool': (_) async => 'result'},
          maxIterations: 10,
          loopDetectionConfig: LoopDetectionConfig(),
        );
        final result = await agent.run('task');
        expect(result.stoppedReason, equals(AgentStopReason.loopDetected));
      },
    );

    test(
      'stoppedReason is AgentStopReason? — not assignable to String',
      () async {
        final agent = ReActAgent(
          name: 'a',
          client: MockLlmClient([_text()]),
          config: _config(),
          toolHandlers: {},
        );
        final result = await agent.run('task');
        // Compile-time check: this assignment only compiles if stoppedReason
        // is AgentStopReason?, not String?.
        final AgentStopReason? typed = result.stoppedReason;
        expect(typed, isNotNull);
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // SimpleAgent always returns null stoppedReason
  // ─────────────────────────────────────────────────────────────────────────
  group('SimpleAgent stoppedReason', () {
    test(
      'stoppedReason is null — SimpleAgent does not manage a loop',
      () async {
        final agent = SimpleAgent(
          name: 'simple',
          client: MockLlmClient([_text()]),
          config: _config(),
        );
        final result = await agent.run('task');
        expect(result.stoppedReason, isNull);
      },
    );

    test('stoppedReason is null even when finishReason is "length"', () async {
      // finishReason is a raw OpenAI string, not mapped to AgentStopReason
      // in SimpleAgent because there is no orchestration loop.
      final client = MockLlmClient([
        ChatCompletionResponse(
          id: 'id',
          choices: [
            ChatCompletionChoice(
              message: ChatMessage(
                role: ChatMessageRole.assistant,
                content: 'truncated',
              ),
              finishReason: 'length',
            ),
          ],
          usage: CompletionUsage(
            promptTokens: 5,
            completionTokens: 5,
            totalTokens: 10,
          ),
        ),
      ]);
      final agent = SimpleAgent(
        name: 'simple',
        client: client,
        config: _config(),
      );
      final result = await agent.run('task');
      expect(result.stoppedReason, isNull);
    });

    test('stoppedReason is null regardless of tool calls returned', () async {
      final client = MockLlmClient([
        ChatCompletionResponse(
          id: 'id',
          choices: [
            ChatCompletionChoice(
              message: ChatMessage(
                role: ChatMessageRole.assistant,
                content: null,
                toolCalls: [
                  ToolCall(
                    id: 'c1',
                    type: 'function',
                    function: ToolCallFunction(name: 'f', arguments: '{}'),
                  ),
                ],
              ),
              finishReason: 'tool_calls',
            ),
          ],
          usage: CompletionUsage(
            promptTokens: 5,
            completionTokens: 5,
            totalTokens: 10,
          ),
        ),
      ]);
      final agent = SimpleAgent(
        name: 'simple',
        client: client,
        config: _config(),
      );
      final result = await agent.run('task');
      expect(result.stoppedReason, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Regression: no magic strings anywhere in stoppedReason assignments
  // ─────────────────────────────────────────────────────────────────────────
  group('Regression — no magic strings', () {
    test('completed is not the String "completed"', () {
      // ignore: unrelated_type_equality_checks
      expect(AgentStopReason.completed == 'completed', isFalse);
    });

    test('maxIterations is not the String "max_iterations"', () {
      // ignore: unrelated_type_equality_checks
      expect(AgentStopReason.maxIterations == 'max_iterations', isFalse);
    });

    test('maxTotalTokens is not the String "max_total_tokens"', () {
      // ignore: unrelated_type_equality_checks
      expect(AgentStopReason.maxTotalTokens == 'max_total_tokens', isFalse);
    });

    test('terminalTool is not the String "terminal_tool"', () {
      // ignore: unrelated_type_equality_checks
      expect(AgentStopReason.terminalTool == 'terminal_tool', isFalse);
    });

    test('loopDetected is not the String "loop_detected"', () {
      // ignore: unrelated_type_equality_checks
      expect(AgentStopReason.loopDetected == 'loop_detected', isFalse);
    });
  });
}
