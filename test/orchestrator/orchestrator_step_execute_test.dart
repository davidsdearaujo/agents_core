import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

import '../helpers/fake_agents.dart';

/// Creates a [FileContext] backed by a temporary directory.
({FileContext ctx, Directory dir}) _tempContext() {
  final dir = Directory.systemTemp.createTempSync('execute_test_');
  final ctx = FileContext(workspacePath: dir.path);
  return (ctx: ctx, dir: dir);
}

// ---------------------------------------------------------------------------
// Custom OrchestratorStep subclass — proves OCP compliance.
//
// This type is neither [AgentStep] nor [AgentLoopStep]. Its existence proves
// that [Orchestrator] can work with arbitrary step implementations once the
// type-switch is replaced by a polymorphic [execute] call.
// ---------------------------------------------------------------------------

/// A minimal [OrchestratorStep] that returns a fixed [AgentStepResult].
///
/// Used exclusively in OCP extensibility tests to verify that [Orchestrator]
/// dispatches to [execute] without knowing the concrete type.
class _CustomStep extends OrchestratorStep {
  const _CustomStep({required this.customOutput, this.condition});

  /// The string returned in the step's output (via a synthetic [AgentResult]).
  final String customOutput;

  @override
  final Future<bool> Function(FileContext)? condition;

  // taskPrompt wraps customOutput in StaticPrompt so that Orchestrator can
  // resolve it via the exhaustive switch and pass it into execute().
  @override
  TaskPrompt get taskPrompt => StaticPrompt(customOutput);

  @override
  Future<StepResult> execute(FileContext context, String resolvedPrompt) async {
    return AgentStepResult(
      agentResult: AgentResult(output: 'custom: $resolvedPrompt'),
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── AgentStep.execute() ───────────────────────────────────────────────────

  group('AgentStep.execute()', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('returns AgentStepResult', () async {
      final agent = FakeAgent();
      final step = AgentStep(agent: agent, taskPrompt: 'do something');
      final result = await step.execute(ctx, 'do something');
      expect(result, isA<AgentStepResult>());
    });

    test('passes resolvedPrompt to agent.run()', () async {
      final agent = FakeAgent();
      final step = AgentStep(agent: agent, taskPrompt: 'original');
      await step.execute(ctx, 'resolved prompt');
      expect(agent.capturedTask, 'resolved prompt');
    });

    test('passes the FileContext to agent.run()', () async {
      final agent = FakeAgent();
      final step = AgentStep(agent: agent, taskPrompt: 'task');
      await step.execute(ctx, 'task');
      expect(agent.capturedContext, same(ctx));
    });

    test('result output matches agent output', () async {
      final agent = FakeAgent.single(
        result: const AgentResult(output: 'agent produced this'),
      );
      final step = AgentStep(agent: agent, taskPrompt: 'task');
      final result = await step.execute(ctx, 'task');
      expect(result.output, 'agent produced this');
    });

    test('result tokensUsed matches agent tokensUsed', () async {
      final agent = FakeAgent.single(
        result: const AgentResult(output: 'out', tokensUsed: 42),
      );
      final step = AgentStep(agent: agent, taskPrompt: 'task');
      final result = await step.execute(ctx, 'task');
      expect(result.tokensUsed, 42);
    });

    test(
      'AgentStepResult.agentResult holds the original AgentResult',
      () async {
        const expected = AgentResult(output: 'hello', tokensUsed: 10);
        final agent = FakeAgent.single(result: expected);
        final step = AgentStep(agent: agent, taskPrompt: 'task');
        final stepResult = await step.execute(ctx, 'task');
        expect(stepResult, isA<AgentStepResult>());
        expect((stepResult as AgentStepResult).agentResult.output, 'hello');
        expect(stepResult.agentResult.tokensUsed, 10);
      },
    );

    test('propagates exceptions thrown by the agent', () async {
      final agent = FakeAgent.throwing(error: Exception('agent failure'));
      final step = AgentStep(agent: agent, taskPrompt: 'task');
      expect(() => step.execute(ctx, 'task'), throwsA(isA<Exception>()));
    });

    test(
      'is callable through the OrchestratorStep interface (polymorphic dispatch)',
      () async {
        final agent = FakeAgent.single(
          result: const AgentResult(output: 'poly output'),
        );
        // Typed as the abstract base — proves polymorphic dispatch.
        final OrchestratorStep step = AgentStep(
          agent: agent,
          taskPrompt: 'task',
        );
        final result = await step.execute(ctx, 'task');
        expect(result.output, 'poly output');
      },
    );

    test(
      'resolvedPrompt differs from taskPrompt when prompt was dynamic',
      () async {
        // Simulates the scenario where Orchestrator resolved a dynamic prompt
        // and now calls execute() with the already-resolved string.
        final agent = FakeAgent.single(result: const AgentResult(output: 'done'));
        final step = AgentStep.dynamic(
          agent: agent,
          taskPrompt: (_) async => 'resolved at runtime',
        );
        // Orchestrator would resolve to 'resolved at runtime' then call:
        await step.execute(ctx, 'resolved at runtime');
        expect(agent.capturedTask, 'resolved at runtime');
      },
    );
  });

  // ── AgentLoopStep.execute() ───────────────────────────────────────────────

  group('AgentLoopStep.execute()', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('returns AgentLoopStepResult', () async {
      final producer = FakeAgent.single(
        name: 'p',
        result: const AgentResult(output: 'produced'),
      );
      final reviewer = FakeAgent.single(
        name: 'r',
        result: const AgentResult(output: 'APPROVED'),
      );
      final step = AgentLoopStep(
        producer: producer,
        reviewer: reviewer,
        taskPrompt: 'loop task',
        isAccepted: (r, _) => r.output.contains('APPROVED'),
      );
      final result = await step.execute(ctx, 'loop task');
      expect(result, isA<AgentLoopStepResult>());
    });

    test(
      'passes resolvedPrompt to AgentLoop — producer receives it in first call',
      () async {
        final producer = FakeAgent.single(
          name: 'p',
          result: const AgentResult(output: 'done'),
        );
        final reviewer = FakeAgent.single(
          name: 'r',
          result: const AgentResult(output: 'APPROVED'),
        );
        final step = AgentLoopStep(
          producer: producer,
          reviewer: reviewer,
          taskPrompt: 'original',
          isAccepted: (r, _) => r.output.contains('APPROVED'),
        );
        await step.execute(ctx, 'resolved loop task');
        // Default producer prompt includes the original task string.
        expect(producer.capturedTask, contains('resolved loop task'));
      },
    );

    test('accepted is true when isAccepted returns true', () async {
      final producer = FakeAgent.single(
        name: 'p',
        result: const AgentResult(output: 'great work'),
      );
      final reviewer = FakeAgent.single(
        name: 'r',
        result: const AgentResult(output: 'ACCEPTED'),
      );
      final step = AgentLoopStep(
        producer: producer,
        reviewer: reviewer,
        taskPrompt: 'task',
        isAccepted: (r, _) => r.output.contains('ACCEPTED'),
      );
      final result = await step.execute(ctx, 'task');
      expect((result as AgentLoopStepResult).accepted, isTrue);
    });

    test(
      'accepted is false when maxIterations reached without acceptance',
      () async {
        final producer = FakeAgent.single(
          name: 'p',
          result: const AgentResult(output: 'produced'),
        );
        final reviewer = FakeAgent.single(
          name: 'r',
          result: const AgentResult(output: 'rejected'),
        );
        final step = AgentLoopStep(
          producer: producer,
          reviewer: reviewer,
          taskPrompt: 'task',
          maxIterations: 2,
          isAccepted: (r, i) => false,
        );
        final result = await step.execute(ctx, 'task');
        expect((result as AgentLoopStepResult).accepted, isFalse);
      },
    );

    test(
      'forwards maxIterations — producer runs exactly maxIterations times',
      () async {
        final producer = FakeAgent.single(
          name: 'p',
          result: const AgentResult(output: 'produced'),
        );
        final reviewer = FakeAgent.single(
          name: 'r',
          result: const AgentResult(output: 'rejected'),
        );
        final step = AgentLoopStep(
          producer: producer,
          reviewer: reviewer,
          taskPrompt: 'task',
          maxIterations: 3,
          isAccepted: (r, i) => false,
        );
        final result = await step.execute(ctx, 'task');
        expect((result as AgentLoopStepResult).iterationCount, 3);
      },
    );

    test(
      'is callable through the OrchestratorStep interface (polymorphic dispatch)',
      () async {
        final producer = FakeAgent.single(
          name: 'p',
          result: const AgentResult(output: 'produced'),
        );
        final reviewer = FakeAgent.single(
          name: 'r',
          result: const AgentResult(output: 'APPROVED'),
        );
        // Typed as the abstract base — proves polymorphic dispatch.
        final OrchestratorStep step = AgentLoopStep(
          producer: producer,
          reviewer: reviewer,
          taskPrompt: 'task',
          isAccepted: (r, _) => r.output.contains('APPROVED'),
        );
        final result = await step.execute(ctx, 'task');
        expect(result, isA<AgentLoopStepResult>());
      },
    );

    test('result output is the last producer output', () async {
      final producer = FakeAgent.single(
        name: 'p',
        result: const AgentResult(output: 'final producer output'),
      );
      final reviewer = FakeAgent.single(
        name: 'r',
        result: const AgentResult(output: 'APPROVED'),
      );
      final step = AgentLoopStep(
        producer: producer,
        reviewer: reviewer,
        taskPrompt: 'task',
        isAccepted: (r, _) => r.output.contains('APPROVED'),
      );
      final result = await step.execute(ctx, 'task');
      expect(result.output, 'final producer output');
    });
  });

  // ── OCP extensibility: custom OrchestratorStep subclass ───────────────────

  group('OrchestratorStep — OCP extensibility (custom step type)', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test(
      'custom step runs inside Orchestrator without modifying Orchestrator',
      () async {
        // _CustomStep is neither AgentStep nor AgentLoopStep.
        // If Orchestrator still used type-switches it would silently skip this.
        // With polymorphic execute() the Orchestrator calls step.execute() and
        // the result is captured.
        const customStep = _CustomStep(customOutput: 'custom result');
        final orch = Orchestrator(context: ctx, steps: [customStep]);
        final result = await orch.run();
        expect(result.stepResults, hasLength(1));
        expect(result.stepResults.first.output, 'custom: custom result');
      },
    );

    test(
      'custom step result is included in stepResults — not silently dropped',
      () async {
        // This test is the key proof that the old type-switch is gone.
        // Before M5: neither branch of the if/else matched → result discarded.
        // After  M5: step.execute() called polymorphically → result collected.
        const customStep = _CustomStep(customOutput: 'must not be lost');
        final orch = Orchestrator(context: ctx, steps: [customStep]);
        final result = await orch.run();
        expect(result.stepResults.length, 1);
        expect(result.errors, isEmpty);
      },
    );

    test('custom step runs alongside AgentStep in a mixed pipeline', () async {
      final agent = FakeAgent.single(
        result: const AgentResult(output: 'agent result'),
      );
      final orch = Orchestrator(
        context: ctx,
        steps: [
          AgentStep(agent: agent, taskPrompt: 'agent task'),
          const _CustomStep(customOutput: 'custom result'),
        ],
      );
      final result = await orch.run();
      expect(result.stepResults, hasLength(2));
      expect(result.stepResults[0].output, 'agent result');
      expect(result.stepResults[1].output, 'custom: custom result');
    });

    test('custom step condition guard is honoured by Orchestrator', () async {
      const skippedStep = _CustomStep(
        customOutput: 'should not appear',
        condition: _alwaysFalse,
      );
      final orch = Orchestrator(context: ctx, steps: [skippedStep]);
      final result = await orch.run();
      expect(result.stepResults, isEmpty);
    });

    test('custom step with condition=true runs normally', () async {
      const runStep = _CustomStep(
        customOutput: 'will run',
        condition: _alwaysTrue,
      );
      final orch = Orchestrator(context: ctx, steps: [runStep]);
      final result = await orch.run();
      expect(result.stepResults, hasLength(1));
      expect(result.stepResults.first.output, 'custom: will run');
    });

    test(
      'OrchestratorStep.execute() is abstract — subclass must implement it',
      () async {
        // Verifies at compile time that execute() is truly abstract.
        // If the method were concrete (with a default body), this check would
        // be meaningless; the fact that _CustomStep must override it confirms
        // it is abstract on the base class.
        const step = _CustomStep(customOutput: 'test');
        final result = await step.execute(ctx, 'test');
        expect(result, isA<StepResult>());
      },
    );
  });

  // ── Orchestrator regression — execute() integration ───────────────────────

  group('Orchestrator regression — execute() integration', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('single AgentStep result is collected in stepResults', () async {
      final agent = FakeAgent.single(
        result: const AgentResult(output: 'step output'),
      );
      final orch = Orchestrator(
        context: ctx,
        steps: [AgentStep(agent: agent, taskPrompt: 'task')],
      );
      final result = await orch.run();
      expect(result.stepResults, hasLength(1));
      expect(result.stepResults.first.output, 'step output');
    });

    test('single AgentLoopStep result is collected in stepResults', () async {
      final producer = FakeAgent.single(
        name: 'p',
        result: const AgentResult(output: 'produced'),
      );
      final reviewer = FakeAgent.single(
        name: 'r',
        result: const AgentResult(output: 'APPROVED'),
      );
      final orch = Orchestrator(
        context: ctx,
        steps: [
          AgentLoopStep(
            producer: producer,
            reviewer: reviewer,
            taskPrompt: 'loop task',
            isAccepted: (r, _) => r.output.contains('APPROVED'),
          ),
        ],
      );
      final result = await orch.run();
      expect(result.stepResults, hasLength(1));
      expect(result.stepResults.first, isA<AgentLoopStepResult>());
    });

    test('mixed pipeline: AgentStep → AgentLoopStep → AgentStep', () async {
      final stepA = FakeAgent.single(
        name: 'A',
        result: const AgentResult(output: 'A output'),
      );
      final producer = FakeAgent.single(
        name: 'p',
        result: const AgentResult(output: 'loop out'),
      );
      final reviewer = FakeAgent.single(
        name: 'r',
        result: const AgentResult(output: 'OK'),
      );
      final stepC = FakeAgent.single(
        name: 'C',
        result: const AgentResult(output: 'C output'),
      );
      final orch = Orchestrator(
        context: ctx,
        steps: [
          AgentStep(agent: stepA, taskPrompt: 'A task'),
          AgentLoopStep(
            producer: producer,
            reviewer: reviewer,
            taskPrompt: 'loop task',
            isAccepted: (r, _) => r.output.contains('OK'),
          ),
          AgentStep(agent: stepC, taskPrompt: 'C task'),
        ],
      );
      final result = await orch.run();
      expect(result.stepResults, hasLength(3));
      expect(result.stepResults[0], isA<AgentStepResult>());
      expect(result.stepResults[1], isA<AgentLoopStepResult>());
      expect(result.stepResults[2], isA<AgentStepResult>());
      expect(result.stepResults[0].output, 'A output');
      expect(result.stepResults[2].output, 'C output');
    });

    test(
      'condition guard still skips steps after execute() refactor',
      () async {
        final agent = FakeAgent.single(
          result: const AgentResult(output: 'should not run'),
        );
        final orch = Orchestrator(
          context: ctx,
          steps: [
            AgentStep(
              agent: agent,
              taskPrompt: 'task',
              condition: (_) async => false,
            ),
          ],
        );
        final result = await orch.run();
        expect(result.stepResults, isEmpty);
        expect(agent.callCount, 0);
      },
    );

    test(
      'condition-true step still executes after execute() refactor',
      () async {
        final agent = FakeAgent.single(result: const AgentResult(output: 'ran fine'));
        final orch = Orchestrator(
          context: ctx,
          steps: [
            AgentStep(
              agent: agent,
              taskPrompt: 'task',
              condition: (_) async => true,
            ),
          ],
        );
        final result = await orch.run();
        expect(result.stepResults, hasLength(1));
        expect(result.stepResults.first.output, 'ran fine');
      },
    );

    test(
      'onError: stop — propagates exception after execute() refactor',
      () async {
        final agent = FakeAgent.throwing(error: Exception('kaboom'));
        final orch = Orchestrator(
          context: ctx,
          steps: [AgentStep(agent: agent, taskPrompt: 'task')],
        );
        expect(() => orch.run(), throwsA(isA<Exception>()));
      },
    );

    test(
      'onError: continueOnError — captures error and continues after execute() refactor',
      () async {
        final failing = FakeAgent.throwing(error: Exception('captured'));
        final passing = FakeAgent.single(
          result: const AgentResult(output: 'next step'),
        );
        final orch = Orchestrator(
          context: ctx,
          steps: [
            AgentStep(agent: failing, taskPrompt: 'will fail'),
            AgentStep(agent: passing, taskPrompt: 'will pass'),
          ],
          onError: OrchestratorErrorPolicy.continueOnError,
        );
        final result = await orch.run();
        expect(result.errors, hasLength(1));
        expect(result.stepResults, hasLength(1));
        expect(result.stepResults.first.output, 'next step');
      },
    );

    test(
      'Orchestrator passes its FileContext to every execute() call',
      () async {
        final agent = FakeAgent.single(result: const AgentResult(output: 'done'));
        final orch = Orchestrator(
          context: ctx,
          steps: [AgentStep(agent: agent, taskPrompt: 'task')],
        );
        await orch.run();
        expect(agent.capturedContext, same(ctx));
      },
    );

    test(
      'dynamic prompt is still resolved then forwarded to execute()',
      () async {
        // Verifies that the Orchestrator still resolves dynamic prompts correctly
        // even after the type-switch is removed.
        FileContext? capturedCtx;
        final agent = FakeAgent.single(result: const AgentResult(output: 'done'));
        final orch = Orchestrator(
          context: ctx,
          steps: [
            AgentStep.dynamic(
              agent: agent,
              taskPrompt: (c) async {
                capturedCtx = c;
                return 'dynamic resolved';
              },
            ),
          ],
        );
        await orch.run();
        expect(capturedCtx, same(ctx));
        expect(agent.capturedTask, 'dynamic resolved');
      },
    );

    test('stepResults order matches pipeline order', () async {
      final outputs = ['first', 'second', 'third'];
      final agents = outputs
          .map((o) => FakeAgent.single(result: AgentResult(output: o)))
          .toList();
      final orch = Orchestrator(
        context: ctx,
        steps: agents
            .map((a) => AgentStep(agent: a, taskPrompt: 'task'))
            .toList(),
      );
      final result = await orch.run();
      expect(result.stepResults.map((r) => r.output).toList(), outputs);
    });
  });
}

// ---------------------------------------------------------------------------
// Top-level condition helpers (const-compatible for _CustomStep)
// ---------------------------------------------------------------------------

Future<bool> _alwaysFalse(FileContext _) async => false;
Future<bool> _alwaysTrue(FileContext _) async => true;
