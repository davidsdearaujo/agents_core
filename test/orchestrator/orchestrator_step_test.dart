import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

import '../helpers/fake_agents.dart';

/// Creates a [FileContext] backed by a temporary directory.
({FileContext ctx, Directory dir}) _tempContext() {
  final dir = Directory.systemTemp.createTempSync('orchestrator_step_test_');
  final ctx = FileContext(workspacePath: dir.path);
  return (ctx: ctx, dir: dir);
}

/// Builds a minimal [AgentLoopResult] for unit-testing [AgentLoopStepResult]
/// without running a real [AgentLoop].
AgentLoopResult _makeLoopResult({
  required String lastProducerOutput,
  bool accepted = true,
  int totalTokens = 50,
  int iterationCount = 1,
}) {
  final iterations = <AgentLoopIteration>[];
  for (var i = 0; i < iterationCount; i++) {
    iterations.add(
      AgentLoopIteration(
        index: i,
        producerResult: AgentResult(
          output: i == iterationCount - 1
              ? lastProducerOutput
              : 'prev output $i',
          tokensUsed: 10,
        ),
        reviewerResult: const AgentResult(output: 'reviewed', tokensUsed: 5),
      ),
    );
  }
  return AgentLoopResult(
    iterations: iterations,
    accepted: accepted,
    duration: Duration.zero,
    totalTokensUsed: totalTokens,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── AgentLoopStep construction ─────────────────────────────────────────────

  group('AgentLoopStep construction', () {
    test('stores producer agent reference', () {
      final producer = FakeAgent(name: 'producer');
      final step = AgentLoopStep(
        producer: producer,
        reviewer: FakeAgent(name: 'reviewer'),
        taskPrompt: 'write code',
        isAccepted: (r, i) => false,
      );
      expect(step.producer, same(producer));
    });

    test('stores reviewer agent reference', () {
      final reviewer = FakeAgent(name: 'reviewer');
      final step = AgentLoopStep(
        producer: FakeAgent(name: 'producer'),
        reviewer: reviewer,
        taskPrompt: 'write code',
        isAccepted: (r, i) => false,
      );
      expect(step.reviewer, same(reviewer));
    });

    test('wraps static String taskPrompt in StaticPrompt', () {
      final step = AgentLoopStep(
        producer: FakeAgent(),
        reviewer: FakeAgent(),
        taskPrompt: 'implement feature X',
        isAccepted: (r, i) => false,
      );
      expect(step.taskPrompt, isA<StaticPrompt>());
      expect((step.taskPrompt as StaticPrompt).value, 'implement feature X');
    });

    test(
      'AgentLoopStep.dynamic wraps function taskPrompt in DynamicPrompt',
      () {
        Future<String> promptFn(FileContext ctx) async => 'dynamic task';
        final step = AgentLoopStep.dynamic(
          producer: FakeAgent(),
          reviewer: FakeAgent(),
          taskPrompt: promptFn,
          isAccepted: (r, i) => false,
        );
        expect(step.taskPrompt, isA<DynamicPrompt>());
        expect((step.taskPrompt as DynamicPrompt).resolver, same(promptFn));
      },
    );

    test('stores isAccepted callback', () {
      bool myAcceptance(AgentResult r, int i) => r.output == 'LGTM';
      final step = AgentLoopStep(
        producer: FakeAgent(),
        reviewer: FakeAgent(),
        taskPrompt: 'task',
        isAccepted: myAcceptance,
      );
      expect(step.isAccepted, same(myAcceptance));
    });

    test('maxIterations defaults to 5', () {
      final step = AgentLoopStep(
        producer: FakeAgent(),
        reviewer: FakeAgent(),
        taskPrompt: 'task',
        isAccepted: (r, i) => false,
      );
      expect(step.maxIterations, 5);
    });

    test('stores custom maxIterations', () {
      final step = AgentLoopStep(
        producer: FakeAgent(),
        reviewer: FakeAgent(),
        taskPrompt: 'task',
        isAccepted: (r, i) => false,
        maxIterations: 3,
      );
      expect(step.maxIterations, 3);
    });

    test('condition is null by default', () {
      final step = AgentLoopStep(
        producer: FakeAgent(),
        reviewer: FakeAgent(),
        taskPrompt: 'task',
        isAccepted: (r, i) => false,
      );
      expect(step.condition, isNull);
    });

    test('stores custom condition', () {
      Future<bool> cond(FileContext ctx) async => true;
      final step = AgentLoopStep(
        producer: FakeAgent(),
        reviewer: FakeAgent(),
        taskPrompt: 'task',
        isAccepted: (r, i) => false,
        condition: cond,
      );
      expect(step.condition, same(cond));
    });

    test('buildProducerPrompt is null by default', () {
      final step = AgentLoopStep(
        producer: FakeAgent(),
        reviewer: FakeAgent(),
        taskPrompt: 'task',
        isAccepted: (r, i) => false,
      );
      expect(step.buildProducerPrompt, isNull);
    });

    test('stores custom buildProducerPrompt', () {
      Future<String> builder(
        String t,
        FileContext c,
        int i,
        AgentResult? r,
      ) async => t;
      final step = AgentLoopStep(
        producer: FakeAgent(),
        reviewer: FakeAgent(),
        taskPrompt: 'task',
        isAccepted: (r, i) => false,
        buildProducerPrompt: builder,
      );
      expect(step.buildProducerPrompt, same(builder));
    });

    test('buildReviewerPrompt is null by default', () {
      final step = AgentLoopStep(
        producer: FakeAgent(),
        reviewer: FakeAgent(),
        taskPrompt: 'task',
        isAccepted: (r, i) => false,
      );
      expect(step.buildReviewerPrompt, isNull);
    });

    test('stores custom buildReviewerPrompt', () {
      Future<String> builder(
        String t,
        FileContext c,
        int i,
        AgentResult r,
      ) async => t;
      final step = AgentLoopStep(
        producer: FakeAgent(),
        reviewer: FakeAgent(),
        taskPrompt: 'task',
        isAccepted: (r, i) => false,
        buildReviewerPrompt: builder,
      );
      expect(step.buildReviewerPrompt, same(builder));
    });
  });

  // ── StepResult hierarchy — AgentStepResult ────────────────────────────────

  group('AgentStepResult', () {
    test('output delegates to AgentResult.output', () {
      const agentResult = AgentResult(output: 'agent output', tokensUsed: 42);
      const stepResult = AgentStepResult(agentResult: agentResult);
      expect(stepResult.output, 'agent output');
    });

    test('tokensUsed delegates to AgentResult.tokensUsed', () {
      const agentResult = AgentResult(output: 'out', tokensUsed: 100);
      const stepResult = AgentStepResult(agentResult: agentResult);
      expect(stepResult.tokensUsed, 100);
    });

    test('agentResult exposes the wrapped AgentResult', () {
      const agentResult = AgentResult(output: 'out');
      const stepResult = AgentStepResult(agentResult: agentResult);
      expect(stepResult.agentResult, same(agentResult));
    });

    test('is a StepResult', () {
      const agentResult = AgentResult(output: 'out');
      const stepResult = AgentStepResult(agentResult: agentResult);
      expect(stepResult, isA<StepResult>());
    });
  });

  // ── StepResult hierarchy — AgentLoopStepResult ───────────────────────────

  group('AgentLoopStepResult', () {
    test('output returns lastProducerResult.output', () {
      final loopResult = _makeLoopResult(lastProducerOutput: 'final code');
      final stepResult = AgentLoopStepResult(agentLoopResult: loopResult);
      expect(stepResult.output, 'final code');
    });

    test(
      'output returns the LAST iteration producer output when multi-iteration',
      () {
        final loopResult = _makeLoopResult(
          lastProducerOutput: 'final output',
          iterationCount: 3,
        );
        final stepResult = AgentLoopStepResult(agentLoopResult: loopResult);
        expect(stepResult.output, 'final output');
      },
    );

    test('tokensUsed returns totalTokensUsed', () {
      final loopResult = _makeLoopResult(
        lastProducerOutput: 'out',
        totalTokens: 250,
      );
      final stepResult = AgentLoopStepResult(agentLoopResult: loopResult);
      expect(stepResult.tokensUsed, 250);
    });

    test('accepted delegates to AgentLoopResult.accepted when true', () {
      final loopResult = _makeLoopResult(
        lastProducerOutput: 'out',
        accepted: true,
      );
      final stepResult = AgentLoopStepResult(agentLoopResult: loopResult);
      expect(stepResult.accepted, isTrue);
    });

    test('accepted delegates to AgentLoopResult.accepted when false', () {
      final loopResult = _makeLoopResult(
        lastProducerOutput: 'out',
        accepted: false,
      );
      final stepResult = AgentLoopStepResult(agentLoopResult: loopResult);
      expect(stepResult.accepted, isFalse);
    });

    test('iterationCount delegates to AgentLoopResult.iterationCount', () {
      final loopResult = _makeLoopResult(
        lastProducerOutput: 'out',
        iterationCount: 3,
      );
      final stepResult = AgentLoopStepResult(agentLoopResult: loopResult);
      expect(stepResult.iterationCount, 3);
    });

    test('agentLoopResult exposes the wrapped AgentLoopResult', () {
      final loopResult = _makeLoopResult(lastProducerOutput: 'out');
      final stepResult = AgentLoopStepResult(agentLoopResult: loopResult);
      expect(stepResult.agentLoopResult, same(loopResult));
    });

    test('is a StepResult', () {
      final loopResult = _makeLoopResult(lastProducerOutput: 'out');
      final stepResult = AgentLoopStepResult(agentLoopResult: loopResult);
      expect(stepResult, isA<StepResult>());
    });
  });

  // ── Orchestrator + AgentLoopStep integration ──────────────────────────────

  group('Orchestrator + AgentLoopStep integration', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    // ── Happy path ──────────────────────────────────────────────────────────

    test(
      'single AgentLoopStep executes producer/reviewer loop and returns AgentLoopStepResult',
      () async {
        final producer = FakeAgent.single(
          name: 'producer',
          result: const AgentResult(output: 'produced code', tokensUsed: 20),
        );
        final reviewer = FakeAgent.single(
          name: 'reviewer',
          result: const AgentResult(output: 'APPROVED', tokensUsed: 10),
        );

        final orch = Orchestrator(
          context: ctx,
          steps: [
            AgentLoopStep(
              producer: producer,
              reviewer: reviewer,
              taskPrompt: 'implement login',
              isAccepted: (r, i) => r.output.contains('APPROVED'),
            ),
          ],
        );
        final result = await orch.run();

        expect(result.stepResults, hasLength(1));
        expect(result.stepResults.first, isA<AgentLoopStepResult>());
        final loopStepResult = result.stepResults.first as AgentLoopStepResult;
        expect(loopStepResult.output, 'produced code');
        expect(loopStepResult.accepted, isTrue);
        expect(loopStepResult.iterationCount, 1);
      },
    );

    // ── Condition skip ──────────────────────────────────────────────────────

    test('AgentLoopStep with condition: false is skipped entirely', () async {
      final producer = FakeAgent(name: 'producer');
      final reviewer = FakeAgent(name: 'reviewer');

      final orch = Orchestrator(
        context: ctx,
        steps: [
          AgentLoopStep(
            producer: producer,
            reviewer: reviewer,
            taskPrompt: 'task',
            isAccepted: (r, i) => true,
            condition: (_) async => false,
          ),
        ],
      );
      final result = await orch.run();

      expect(result.stepResults, isEmpty);
      expect(producer.callCount, 0);
      expect(reviewer.callCount, 0);
    });

    // ── Dynamic prompt ──────────────────────────────────────────────────────

    test('AgentLoopStep.dynamic resolves prompt from FileContext', () async {
      ctx.write('task.txt', 'build the parser');

      final producer = FakeAgent.single(
        name: 'producer',
        result: const AgentResult(output: 'parser code'),
      );
      final reviewer = FakeAgent.single(
        name: 'reviewer',
        result: const AgentResult(output: 'LGTM'),
      );

      final orch = Orchestrator(
        context: ctx,
        steps: [
          AgentLoopStep.dynamic(
            producer: producer,
            reviewer: reviewer,
            taskPrompt: (c) async => c.read('task.txt'),
            isAccepted: (r, i) => r.output.contains('LGTM'),
          ),
        ],
      );
      await orch.run();

      // Producer's first prompt should start with the resolved task text.
      expect(producer.capturedTasks.first, contains('build the parser'));
    });

    // ── Mixed pipeline ──────────────────────────────────────────────────────

    test(
      'AgentStep → AgentLoopStep → AgentStep executes in order with correct types',
      () async {
        final agent1 = FakeAgent.single(
          name: 'a1',
          result: const AgentResult(output: 'step1 out', tokensUsed: 5),
        );
        final producer = FakeAgent.single(
          name: 'producer',
          result: const AgentResult(output: 'loop out', tokensUsed: 15),
        );
        final reviewer = FakeAgent.single(
          name: 'reviewer',
          result: const AgentResult(output: 'OK', tokensUsed: 5),
        );
        final agent3 = FakeAgent.single(
          name: 'a3',
          result: const AgentResult(output: 'step3 out', tokensUsed: 10),
        );

        final orch = Orchestrator(
          context: ctx,
          steps: [
            AgentStep(agent: agent1, taskPrompt: 'first task'),
            AgentLoopStep(
              producer: producer,
              reviewer: reviewer,
              taskPrompt: 'loop task',
              isAccepted: (r, i) => r.output.contains('OK'),
            ),
            AgentStep(agent: agent3, taskPrompt: 'third task'),
          ],
        );

        final result = await orch.run();

        expect(result.stepResults, hasLength(3));
        expect(result.stepResults[0], isA<AgentStepResult>());
        expect(result.stepResults[1], isA<AgentLoopStepResult>());
        expect(result.stepResults[2], isA<AgentStepResult>());

        // Common accessor works for all types.
        expect(result.stepResults[0].output, 'step1 out');
        expect(result.stepResults[1].output, 'loop out');
        expect(result.stepResults[2].output, 'step3 out');

        expect(agent1.callCount, 1);
        expect(producer.callCount, 1);
        expect(reviewer.callCount, 1);
        expect(agent3.callCount, 1);
      },
    );

    // ── Error handling ──────────────────────────────────────────────────────

    test('exception in AgentLoopStep propagates when policy is stop', () async {
      final producer = FakeAgent.throwing(
        name: 'producer',
        error: Exception('producer crashed'),
      );
      final reviewer = FakeAgent(name: 'reviewer');

      final orch = Orchestrator(
        context: ctx,
        steps: [
          AgentLoopStep(
            producer: producer,
            reviewer: reviewer,
            taskPrompt: 'task',
            isAccepted: (r, i) => false,
          ),
        ],
      );
      await expectLater(orch.run(), throwsException);
    });

    test(
      'exception in AgentLoopStep is captured when policy is continueOnError',
      () async {
        final producer = FakeAgent.throwing(
          name: 'producer',
          error: Exception('loop error'),
        );
        final reviewer = FakeAgent(name: 'reviewer');
        final afterAgent = FakeAgent.single(
          name: 'after',
          result: const AgentResult(output: 'after output'),
        );

        final orch = Orchestrator(
          context: ctx,
          onError: OrchestratorErrorPolicy.continueOnError,
          steps: [
            AgentLoopStep(
              producer: producer,
              reviewer: reviewer,
              taskPrompt: 'task',
              isAccepted: (r, i) => false,
            ),
            AgentStep(agent: afterAgent, taskPrompt: 'after task'),
          ],
        );

        final result = await orch.run();

        expect(result.stepResults, hasLength(1));
        expect(result.stepResults.first.output, 'after output');
        expect(result.hasErrors, isTrue);
        expect(afterAgent.callCount, 1);
      },
    );

    test(
      'subsequent steps execute after AgentLoopStep failure with continueOnError',
      () async {
        final producer = FakeAgent.throwing(
          name: 'producer',
          error: Exception('loop error'),
        );
        final afterAgent = FakeAgent.single(name: 'after');

        final orch = Orchestrator(
          context: ctx,
          onError: OrchestratorErrorPolicy.continueOnError,
          steps: [
            AgentLoopStep(
              producer: producer,
              reviewer: FakeAgent(),
              taskPrompt: 'task',
              isAccepted: (r, i) => false,
            ),
            AgentStep(agent: afterAgent, taskPrompt: 'after'),
          ],
        );
        await orch.run();
        expect(afterAgent.callCount, 1);
      },
    );

    // ── Context sharing ─────────────────────────────────────────────────────

    test(
      'orchestrator FileContext is passed to producer and reviewer',
      () async {
        final producer = FakeAgent.single(
          name: 'producer',
          result: const AgentResult(output: 'produced'),
        );
        final reviewer = FakeAgent.single(
          name: 'reviewer',
          result: const AgentResult(output: 'ACCEPTED'),
        );

        final orch = Orchestrator(
          context: ctx,
          steps: [
            AgentLoopStep(
              producer: producer,
              reviewer: reviewer,
              taskPrompt: 'context test',
              isAccepted: (r, i) => r.output.contains('ACCEPTED'),
            ),
          ],
        );
        await orch.run();

        expect(producer.capturedContexts, isNotEmpty);
        expect(producer.capturedContexts.first, same(ctx));
        expect(reviewer.capturedContexts, isNotEmpty);
        expect(reviewer.capturedContexts.first, same(ctx));
      },
    );

    // ── AgentLoop config forwarding ─────────────────────────────────────────

    test(
      'maxIterations from AgentLoopStep limits the number of loop iterations',
      () async {
        // isAccepted never returns true — loop stops only at maxIterations.
        final producer = FakeAgent(
          name: 'producer',
          results: [
            const AgentResult(output: 'attempt 1'),
            const AgentResult(output: 'attempt 2'),
          ],
        );
        final reviewer = FakeAgent(
          name: 'reviewer',
          results: [
            const AgentResult(output: 'REJECTED'),
            const AgentResult(output: 'REJECTED'),
          ],
        );

        final orch = Orchestrator(
          context: ctx,
          steps: [
            AgentLoopStep(
              producer: producer,
              reviewer: reviewer,
              taskPrompt: 'task',
              isAccepted: (r, i) => r.output.contains('APPROVED'),
              maxIterations: 2,
            ),
          ],
        );
        final result = await orch.run();

        expect(producer.callCount, 2);
        expect(reviewer.callCount, 2);

        final loopStepResult = result.stepResults.first as AgentLoopStepResult;
        expect(loopStepResult.accepted, isFalse);
        expect(loopStepResult.iterationCount, 2);
      },
    );

    test(
      'isAccepted from AgentLoopStep controls when the loop terminates early',
      () async {
        // Reviewer approves on the 2nd iteration.
        final producer = FakeAgent(
          name: 'producer',
          results: [
            const AgentResult(output: 'v1'),
            const AgentResult(output: 'v2'),
          ],
        );
        final reviewer = FakeAgent(
          name: 'reviewer',
          results: [
            const AgentResult(output: 'REJECTED'),
            const AgentResult(output: 'APPROVED'),
          ],
        );

        final orch = Orchestrator(
          context: ctx,
          steps: [
            AgentLoopStep(
              producer: producer,
              reviewer: reviewer,
              taskPrompt: 'task',
              isAccepted: (r, i) => r.output.contains('APPROVED'),
              maxIterations: 5,
            ),
          ],
        );
        final result = await orch.run();

        expect(producer.callCount, 2);
        expect(reviewer.callCount, 2);

        final loopStepResult = result.stepResults.first as AgentLoopStepResult;
        expect(loopStepResult.accepted, isTrue);
        expect(loopStepResult.iterationCount, 2);
        expect(loopStepResult.output, 'v2');
      },
    );

    test(
      'custom buildProducerPrompt from AgentLoopStep is forwarded to AgentLoop',
      () async {
        var customPromptCalled = false;

        final producer = FakeAgent.single(
          name: 'producer',
          result: const AgentResult(output: 'produced'),
        );
        final reviewer = FakeAgent.single(
          name: 'reviewer',
          result: const AgentResult(output: 'ACCEPTED'),
        );

        final orch = Orchestrator(
          context: ctx,
          steps: [
            AgentLoopStep(
              producer: producer,
              reviewer: reviewer,
              taskPrompt: 'task',
              isAccepted: (r, i) => r.output.contains('ACCEPTED'),
              buildProducerPrompt: (task, c, i, prev) async {
                customPromptCalled = true;
                return 'custom producer prompt: $task';
              },
            ),
          ],
        );
        await orch.run();

        expect(customPromptCalled, isTrue);
        expect(producer.capturedTasks.first, 'custom producer prompt: task');
      },
    );

    test(
      'custom buildReviewerPrompt from AgentLoopStep is forwarded to AgentLoop',
      () async {
        var customReviewerPromptCalled = false;

        final producer = FakeAgent.single(
          name: 'producer',
          result: const AgentResult(output: 'produced'),
        );
        final reviewer = FakeAgent.single(
          name: 'reviewer',
          result: const AgentResult(output: 'ACCEPTED'),
        );

        final orch = Orchestrator(
          context: ctx,
          steps: [
            AgentLoopStep(
              producer: producer,
              reviewer: reviewer,
              taskPrompt: 'task',
              isAccepted: (r, i) => r.output.contains('ACCEPTED'),
              buildReviewerPrompt: (task, c, i, prod) async {
                customReviewerPromptCalled = true;
                return 'custom reviewer prompt';
              },
            ),
          ],
        );
        await orch.run();

        expect(customReviewerPromptCalled, isTrue);
        expect(reviewer.capturedTasks.first, 'custom reviewer prompt');
      },
    );
  });

  // ── OrchestratorResult — StepResult type hierarchy ─────────────────────────

  group('OrchestratorResult — StepResult type hierarchy', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test(
      'AgentStep execution produces AgentStepResult in stepResults',
      () async {
        final orch = Orchestrator(
          context: ctx,
          steps: [AgentStep(agent: FakeAgent(), taskPrompt: 'task')],
        );
        final result = await orch.run();
        expect(result.stepResults.first, isA<AgentStepResult>());
      },
    );

    test(
      'AgentStepResult.agentResult holds the original AgentResult',
      () async {
        const agentResult = AgentResult(
          output: 'precise output',
          tokensUsed: 77,
        );
        final orch = Orchestrator(
          context: ctx,
          steps: [
            AgentStep(
              agent: FakeAgent.single(result: agentResult),
              taskPrompt: 'task',
            ),
          ],
        );
        final result = await orch.run();
        final stepResult = result.stepResults.first as AgentStepResult;
        expect(stepResult.agentResult.output, 'precise output');
        expect(stepResult.agentResult.tokensUsed, 77);
      },
    );

    test(
      'common StepResult.output accessor works for AgentStep results',
      () async {
        final r1 = const AgentResult(output: 'out1', tokensUsed: 10);
        final r2 = const AgentResult(output: 'out2', tokensUsed: 20);
        final orch = Orchestrator(
          context: ctx,
          steps: [
            AgentStep(
              agent: FakeAgent.single(result: r1),
              taskPrompt: 'task1',
            ),
            AgentStep(
              agent: FakeAgent.single(result: r2),
              taskPrompt: 'task2',
            ),
          ],
        );
        final result = await orch.run();
        // Common accessor — no cast needed.
        expect(result.stepResults[0].output, 'out1');
        expect(result.stepResults[0].tokensUsed, 10);
        expect(result.stepResults[1].output, 'out2');
        expect(result.stepResults[1].tokensUsed, 20);
      },
    );

    test(
      'common StepResult.output accessor works for AgentLoopStep results',
      () async {
        final producer = FakeAgent.single(
          name: 'producer',
          result: const AgentResult(output: 'loop output', tokensUsed: 30),
        );
        final reviewer = FakeAgent.single(
          name: 'reviewer',
          result: const AgentResult(output: 'OK', tokensUsed: 5),
        );
        final orch = Orchestrator(
          context: ctx,
          steps: [
            AgentLoopStep(
              producer: producer,
              reviewer: reviewer,
              taskPrompt: 'task',
              isAccepted: (r, i) => r.output.contains('OK'),
            ),
          ],
        );
        final result = await orch.run();
        // Common accessor — no cast needed.
        expect(result.stepResults.first.output, 'loop output');
      },
    );

    test(
      'mixed pipeline stepResults contains correct StepResult subtypes at each index',
      () async {
        final agent = FakeAgent.single(
          result: const AgentResult(output: 'agent out'),
        );
        final producer = FakeAgent.single(
          name: 'producer',
          result: const AgentResult(output: 'loop out'),
        );
        final reviewer = FakeAgent.single(
          name: 'reviewer',
          result: const AgentResult(output: 'APPROVED'),
        );
        final orch = Orchestrator(
          context: ctx,
          steps: [
            AgentStep(agent: agent, taskPrompt: 'agent task'),
            AgentLoopStep(
              producer: producer,
              reviewer: reviewer,
              taskPrompt: 'loop task',
              isAccepted: (r, i) => r.output.contains('APPROVED'),
            ),
          ],
        );
        final result = await orch.run();

        expect(result.stepResults[0], isA<AgentStepResult>());
        expect(result.stepResults[1], isA<AgentLoopStepResult>());

        // Type-specific access via cast.
        final agentStepResult = result.stepResults[0] as AgentStepResult;
        expect(agentStepResult.agentResult.output, 'agent out');

        final loopStepResult = result.stepResults[1] as AgentLoopStepResult;
        expect(loopStepResult.agentLoopResult.accepted, isTrue);
      },
    );
  });
}
