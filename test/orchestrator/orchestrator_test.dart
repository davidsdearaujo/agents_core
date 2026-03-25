// ignore_for_file: avoid_implementing_value_types

import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// A fake [Agent] that never makes real HTTP calls.
///
/// Records the task and context it was called with, and either returns
/// [_result] or throws [_throwError], depending on configuration.
class _FakeAgent extends Agent {
  _FakeAgent({
    super.name = 'fake',
    AgentResult? result,
    Object? throwError,
  })  : _result = result ?? const AgentResult(output: 'fake output'),
        _throwError = throwError,
        super(
          client: LmStudioClient(
            AgentsCoreConfig(logger: const SilentLogger()),
          ),
          config: AgentsCoreConfig(logger: const SilentLogger()),
        );

  final AgentResult _result;
  final Object? _throwError;

  String? capturedTask;
  FileContext? capturedContext;
  int callCount = 0;

  @override
  Future<AgentResult> run(String task, {FileContext? context}) async {
    callCount++;
    capturedTask = task;
    capturedContext = context;
    if (_throwError != null) throw _throwError;
    return _result;
  }
}

/// Creates a [FileContext] backed by a temp directory.
({FileContext ctx, Directory dir}) _tempContext() {
  final dir = Directory.systemTemp.createTempSync('orchestrator_test_');
  final ctx = FileContext(workspacePath: dir.path);
  return (ctx: ctx, dir: dir);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── AgentStep ─────────────────────────────────────────────────────────────

  group('AgentStep', () {
    test('stores agent reference', () {
      final agent = _FakeAgent(name: 'writer');
      final step = AgentStep(agent: agent, taskPrompt: 'do work');
      expect(step.agent, same(agent));
    });

    test('stores static String taskPrompt', () {
      final step = AgentStep(
        agent: _FakeAgent(),
        taskPrompt: 'write a report',
      );
      expect(step.taskPrompt, isA<String>());
      expect(step.taskPrompt, 'write a report');
    });

    test('condition is null by default', () {
      final step = AgentStep(agent: _FakeAgent(), taskPrompt: 'task');
      expect(step.condition, isNull);
    });

    test('stores provided condition', () {
      Future<bool> cond(FileContext ctx) async => true;
      final step = AgentStep(
        agent: _FakeAgent(),
        taskPrompt: 'task',
        condition: cond,
      );
      expect(step.condition, same(cond));
    });

    test('AgentStep.dynamic stores function taskPrompt', () {
      Future<String> promptFn(FileContext ctx) async => 'dynamic task';
      final step = AgentStep.dynamic(
        agent: _FakeAgent(),
        taskPrompt: promptFn,
      );
      expect(
        step.taskPrompt,
        isA<Future<String> Function(FileContext)>(),
      );
    });

    test('AgentStep.dynamic stores agent reference', () {
      final agent = _FakeAgent(name: 'dyn-agent');
      final step = AgentStep.dynamic(
        agent: agent,
        taskPrompt: (ctx) async => 'task',
      );
      expect(step.agent, same(agent));
    });

    test('AgentStep.dynamic condition is null by default', () {
      final step = AgentStep.dynamic(
        agent: _FakeAgent(),
        taskPrompt: (ctx) async => 'task',
      );
      expect(step.condition, isNull);
    });

    test('AgentStep.dynamic stores provided condition', () {
      Future<bool> cond(FileContext ctx) async => false;
      final step = AgentStep.dynamic(
        agent: _FakeAgent(),
        taskPrompt: (ctx) async => 'task',
        condition: cond,
      );
      expect(step.condition, same(cond));
    });
  });

  // ── Orchestrator construction ─────────────────────────────────────────────

  group('Orchestrator construction', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('accepts context and empty steps list', () {
      expect(
        () => Orchestrator(context: ctx, steps: const []),
        returnsNormally,
      );
    });

    test('accepts context and non-empty steps list', () {
      final step = AgentStep(agent: _FakeAgent(), taskPrompt: 'task');
      expect(
        () => Orchestrator(context: ctx, steps: [step]),
        returnsNormally,
      );
    });

    test('exposes context', () {
      final orch = Orchestrator(context: ctx, steps: const []);
      expect(orch.context, same(ctx));
    });

    test('exposes steps list', () {
      final step = AgentStep(agent: _FakeAgent(), taskPrompt: 'task');
      final orch = Orchestrator(context: ctx, steps: [step]);
      expect(orch.steps, hasLength(1));
      expect(orch.steps.first, same(step));
    });
  });

  // ── Orchestrator.run() — basic execution ──────────────────────────────────

  group('Orchestrator.run() — basic execution', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('empty steps list completes without error', () async {
      final orch = Orchestrator(context: ctx, steps: const []);
      await expectLater(orch.run(), completes);
    });

    test('calls agent.run() with the static taskPrompt', () async {
      final agent = _FakeAgent();
      final orch = Orchestrator(
        context: ctx,
        steps: [AgentStep(agent: agent, taskPrompt: 'hello task')],
      );
      await orch.run();
      expect(agent.capturedTask, 'hello task');
    });

    test('passes orchestrator FileContext to agent.run()', () async {
      final agent = _FakeAgent();
      final orch = Orchestrator(
        context: ctx,
        steps: [AgentStep(agent: agent, taskPrompt: 'task')],
      );
      await orch.run();
      expect(agent.capturedContext, same(ctx));
    });

    test('executes multiple steps sequentially', () async {
      final order = <String>[];
      final agent1 = _FakeAgent(
        name: 'a1',
        result: AgentResult(
          output: 'result1',
          filesModified: const [],
        ),
      );
      final agent2 = _FakeAgent(
        name: 'a2',
        result: const AgentResult(output: 'result2'),
      );

      // Use condition to track order
      final orch = Orchestrator(
        context: ctx,
        steps: [
          AgentStep(
            agent: agent1,
            taskPrompt: 'step 1',
            condition: (c) async {
              order.add('step1');
              return true;
            },
          ),
          AgentStep(
            agent: agent2,
            taskPrompt: 'step 2',
            condition: (c) async {
              order.add('step2');
              return true;
            },
          ),
        ],
      );
      await orch.run();

      expect(order, ['step1', 'step2']);
      expect(agent1.capturedTask, 'step 1');
      expect(agent2.capturedTask, 'step 2');
    });

    test('agent.run() is called exactly once per step', () async {
      final agent = _FakeAgent();
      final orch = Orchestrator(
        context: ctx,
        steps: [AgentStep(agent: agent, taskPrompt: 'task')],
      );
      await orch.run();
      expect(agent.callCount, 1);
    });
  });

  // ── Orchestrator.run() — dynamic taskPrompt ───────────────────────────────

  group('Orchestrator.run() — dynamic taskPrompt', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('calls dynamic prompt function with orchestrator FileContext',
        () async {
      FileContext? capturedCtx;
      final agent = _FakeAgent();
      final orch = Orchestrator(
        context: ctx,
        steps: [
          AgentStep.dynamic(
            agent: agent,
            taskPrompt: (c) async {
              capturedCtx = c;
              return 'dynamic task';
            },
          ),
        ],
      );
      await orch.run();
      expect(capturedCtx, isNotNull);
      expect(capturedCtx, same(ctx));
    });

    test('resolved dynamic prompt is passed to agent.run()', () async {
      final agent = _FakeAgent();
      final orch = Orchestrator(
        context: ctx,
        steps: [
          AgentStep.dynamic(
            agent: agent,
            taskPrompt: (c) async => 'computed prompt',
          ),
        ],
      );
      await orch.run();
      expect(agent.capturedTask, 'computed prompt');
    });

    test('dynamic prompt can read FileContext to build task string', () async {
      ctx.write('config.txt', 'model: gpt-4');

      final agent = _FakeAgent();
      final orch = Orchestrator(
        context: ctx,
        steps: [
          AgentStep.dynamic(
            agent: agent,
            taskPrompt: (c) async {
              final config = c.read('config.txt');
              return 'Use config: $config';
            },
          ),
        ],
      );
      await orch.run();
      expect(agent.capturedTask, 'Use config: model: gpt-4');
    });

    test('prompt function is awaited before agent.run() is called', () async {
      var promptResolved = false;
      final agent = _FakeAgent();

      final orch = Orchestrator(
        context: ctx,
        steps: [
          AgentStep.dynamic(
            agent: agent,
            taskPrompt: (c) async {
              await Future<void>.delayed(Duration.zero);
              promptResolved = true;
              return 'async prompt';
            },
          ),
        ],
      );
      await orch.run();
      expect(promptResolved, isTrue);
      expect(agent.capturedTask, 'async prompt');
    });
  });

  // ── Orchestrator.run() — condition handling ───────────────────────────────

  group('Orchestrator.run() — condition handling', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('step with no condition is always executed', () async {
      final agent = _FakeAgent();
      final orch = Orchestrator(
        context: ctx,
        steps: [AgentStep(agent: agent, taskPrompt: 'task')],
      );
      await orch.run();
      expect(agent.callCount, 1);
    });

    test('step is executed when condition returns true', () async {
      final agent = _FakeAgent();
      final orch = Orchestrator(
        context: ctx,
        steps: [
          AgentStep(
            agent: agent,
            taskPrompt: 'task',
            condition: (c) async => true,
          ),
        ],
      );
      await orch.run();
      expect(agent.callCount, 1);
    });

    test('step is skipped when condition returns false', () async {
      final agent = _FakeAgent();
      final orch = Orchestrator(
        context: ctx,
        steps: [
          AgentStep(
            agent: agent,
            taskPrompt: 'task',
            condition: (c) async => false,
          ),
        ],
      );
      await orch.run();
      expect(agent.callCount, 0);
    });

    test('condition receives the orchestrator FileContext', () async {
      FileContext? capturedCtx;
      final agent = _FakeAgent();
      final orch = Orchestrator(
        context: ctx,
        steps: [
          AgentStep(
            agent: agent,
            taskPrompt: 'task',
            condition: (c) async {
              capturedCtx = c;
              return true;
            },
          ),
        ],
      );
      await orch.run();
      expect(capturedCtx, isNotNull);
      expect(capturedCtx, same(ctx));
    });

    test('condition can inspect FileContext to decide skip', () async {
      // Write flag file — step should execute
      ctx.write('run_step.flag', '1');

      final agent = _FakeAgent();
      final orch = Orchestrator(
        context: ctx,
        steps: [
          AgentStep(
            agent: agent,
            taskPrompt: 'task',
            condition: (c) async => c.exists('run_step.flag'),
          ),
        ],
      );
      await orch.run();
      expect(agent.callCount, 1);
    });

    test('skipped step does not appear in stepResults', () async {
      final skipped = _FakeAgent(name: 'skipped');
      final executed = _FakeAgent(name: 'executed');
      final orch = Orchestrator(
        context: ctx,
        steps: [
          AgentStep(
            agent: skipped,
            taskPrompt: 'task A',
            condition: (c) async => false,
          ),
          AgentStep(agent: executed, taskPrompt: 'task B'),
        ],
      );
      final result = await orch.run();
      expect(result.stepResults, hasLength(1));
      expect(result.stepResults.first.output, 'fake output');
      expect(skipped.callCount, 0);
      expect(executed.callCount, 1);
    });

    test('mix of skipped and executed steps preserves execution order',
        () async {
      final executionLog = <String>[];

      final a1 = _FakeAgent(
          name: 'a1',
          result: AgentResult(
            output: 'a1',
            filesModified: const [],
          ));
      final a2 = _FakeAgent(
          name: 'a2',
          result: const AgentResult(output: 'a2'));
      final a3 = _FakeAgent(
          name: 'a3',
          result: const AgentResult(output: 'a3'));

      final orch = Orchestrator(
        context: ctx,
        steps: [
          AgentStep(
            agent: a1,
            taskPrompt: 'first',
            condition: (c) async {
              executionLog.add('check-a1');
              return true;
            },
          ),
          AgentStep(
            agent: a2,
            taskPrompt: 'second',
            condition: (c) async {
              executionLog.add('check-a2');
              return false;
            },
          ),
          AgentStep(
            agent: a3,
            taskPrompt: 'third',
            condition: (c) async {
              executionLog.add('check-a3');
              return true;
            },
          ),
        ],
      );

      final result = await orch.run();

      // All conditions checked in order
      expect(executionLog, ['check-a1', 'check-a2', 'check-a3']);
      // Only a1 and a3 ran
      expect(a1.callCount, 1);
      expect(a2.callCount, 0);
      expect(a3.callCount, 1);
      // stepResults has a1 and a3 outputs
      expect(result.stepResults, hasLength(2));
      expect(result.stepResults[0].output, 'a1');
      expect(result.stepResults[1].output, 'a3');
    });
  });

  // ── OrchestratorResult structure ──────────────────────────────────────────

  group('OrchestratorResult', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('stepResults contains AgentResult from each executed step', () async {
      final r1 = const AgentResult(output: 'out1', tokensUsed: 10);
      final r2 = const AgentResult(output: 'out2', tokensUsed: 20);

      final orch = Orchestrator(
        context: ctx,
        steps: [
          AgentStep(agent: _FakeAgent(result: r1), taskPrompt: 'task1'),
          AgentStep(agent: _FakeAgent(result: r2), taskPrompt: 'task2'),
        ],
      );
      final result = await orch.run();
      expect(result.stepResults, hasLength(2));
      expect(result.stepResults[0].output, 'out1');
      expect(result.stepResults[0].tokensUsed, 10);
      expect(result.stepResults[1].output, 'out2');
      expect(result.stepResults[1].tokensUsed, 20);
    });

    test('duration is non-negative', () async {
      final orch = Orchestrator(
        context: ctx,
        steps: [AgentStep(agent: _FakeAgent(), taskPrompt: 'task')],
      );
      final result = await orch.run();
      expect(result.duration.inMicroseconds, greaterThanOrEqualTo(0));
    });

    test('duration covers the entire run including all steps', () async {
      // Simulate two fake agents; duration should reflect their combined time
      final orch = Orchestrator(
        context: ctx,
        steps: [
          AgentStep(agent: _FakeAgent(), taskPrompt: 'step1'),
          AgentStep(agent: _FakeAgent(), taskPrompt: 'step2'),
        ],
      );
      final before = DateTime.now();
      final result = await orch.run();
      final after = DateTime.now();

      final wallTime = after.difference(before);
      // Duration reported must not exceed wall time (with 100ms headroom)
      expect(
        result.duration.inMicroseconds,
        lessThanOrEqualTo(wallTime.inMicroseconds + 100000),
      );
    });

    test('empty steps list returns empty stepResults', () async {
      final orch = Orchestrator(context: ctx, steps: const []);
      final result = await orch.run();
      expect(result.stepResults, isEmpty);
    });

    test('errors is empty when all steps succeed', () async {
      final orch = Orchestrator(
        context: ctx,
        steps: [AgentStep(agent: _FakeAgent(), taskPrompt: 'task')],
      );
      final result = await orch.run();
      expect(result.errors, isEmpty);
    });

    test('hasErrors is false when all steps succeed', () async {
      final orch = Orchestrator(
        context: ctx,
        steps: [AgentStep(agent: _FakeAgent(), taskPrompt: 'task')],
      );
      final result = await orch.run();
      expect(result.hasErrors, isFalse);
    });
  });

  // ── onError: stop (default) ───────────────────────────────────────────────

  group('Orchestrator.run() — onError: stop (default)', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('propagates exception when agent throws', () async {
      final error = Exception('agent blew up');
      final orch = Orchestrator(
        context: ctx,
        steps: [
          AgentStep(
            agent: _FakeAgent(throwError: error),
            taskPrompt: 'task',
          ),
        ],
      );
      await expectLater(orch.run(), throwsA(same(error)));
    });

    test('stops execution after failing step', () async {
      final afterAgent = _FakeAgent(name: 'after');
      final orch = Orchestrator(
        context: ctx,
        steps: [
          AgentStep(
            agent: _FakeAgent(throwError: Exception('oops')),
            taskPrompt: 'step1',
          ),
          AgentStep(agent: afterAgent, taskPrompt: 'step2'),
        ],
      );

      await expectLater(orch.run(), throwsException);
      expect(afterAgent.callCount, 0);
    });

    test('stop is the default policy (no explicit onError needed)', () async {
      final error = StateError('state error');
      // No onError parameter — default behaviour is stop
      final orch = Orchestrator(
        context: ctx,
        steps: [
          AgentStep(
            agent: _FakeAgent(throwError: error),
            taskPrompt: 'task',
          ),
        ],
      );
      await expectLater(orch.run(), throwsA(isA<StateError>()));
    });
  });

  // ── onError: continue ─────────────────────────────────────────────────────

  group('Orchestrator.run() — onError: continueOnError', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('does not throw when an agent fails', () async {
      final orch = Orchestrator(
        context: ctx,
        onError: OrchestratorErrorPolicy.continueOnError,
        steps: [
          AgentStep(
            agent: _FakeAgent(throwError: Exception('fail')),
            taskPrompt: 'task',
          ),
        ],
      );
      await expectLater(orch.run(), completes);
    });

    test('continues executing subsequent steps after a failure', () async {
      final afterAgent = _FakeAgent(name: 'after');
      final orch = Orchestrator(
        context: ctx,
        onError: OrchestratorErrorPolicy.continueOnError,
        steps: [
          AgentStep(
            agent: _FakeAgent(throwError: Exception('fail')),
            taskPrompt: 'step1',
          ),
          AgentStep(agent: afterAgent, taskPrompt: 'step2'),
        ],
      );
      await orch.run();
      expect(afterAgent.callCount, 1);
    });

    test('failed step is excluded from stepResults', () async {
      final orch = Orchestrator(
        context: ctx,
        onError: OrchestratorErrorPolicy.continueOnError,
        steps: [
          AgentStep(
            agent: _FakeAgent(throwError: Exception('fail')),
            taskPrompt: 'step1',
          ),
          AgentStep(
            agent: _FakeAgent(result: const AgentResult(output: 'ok')),
            taskPrompt: 'step2',
          ),
        ],
      );
      final result = await orch.run();
      expect(result.stepResults, hasLength(1));
      expect(result.stepResults.first.output, 'ok');
    });

    test('errors list contains captured exceptions', () async {
      final error = Exception('agent error');
      final orch = Orchestrator(
        context: ctx,
        onError: OrchestratorErrorPolicy.continueOnError,
        steps: [
          AgentStep(
            agent: _FakeAgent(throwError: error),
            taskPrompt: 'step1',
          ),
        ],
      );
      final result = await orch.run();
      expect(result.errors, hasLength(1));
      expect(result.errors.first, same(error));
    });

    test('hasErrors is true when at least one step fails', () async {
      final orch = Orchestrator(
        context: ctx,
        onError: OrchestratorErrorPolicy.continueOnError,
        steps: [
          AgentStep(
            agent: _FakeAgent(throwError: Exception('fail')),
            taskPrompt: 'task',
          ),
        ],
      );
      final result = await orch.run();
      expect(result.hasErrors, isTrue);
    });

    test('multiple failures captured in errors list', () async {
      final e1 = Exception('fail 1');
      final e2 = Exception('fail 2');
      final orch = Orchestrator(
        context: ctx,
        onError: OrchestratorErrorPolicy.continueOnError,
        steps: [
          AgentStep(
            agent: _FakeAgent(throwError: e1),
            taskPrompt: 'step1',
          ),
          AgentStep(
            agent: _FakeAgent(throwError: e2),
            taskPrompt: 'step2',
          ),
        ],
      );
      final result = await orch.run();
      expect(result.errors, hasLength(2));
      expect(result.errors, containsAllInOrder([e1, e2]));
    });

    test('mix of success and failure: correct stepResults and errors', () async {
      final e = Exception('mid-fail');
      final orch = Orchestrator(
        context: ctx,
        onError: OrchestratorErrorPolicy.continueOnError,
        steps: [
          AgentStep(
            agent: _FakeAgent(result: const AgentResult(output: 'step1-ok')),
            taskPrompt: 'step1',
          ),
          AgentStep(
            agent: _FakeAgent(throwError: e),
            taskPrompt: 'step2',
          ),
          AgentStep(
            agent: _FakeAgent(result: const AgentResult(output: 'step3-ok')),
            taskPrompt: 'step3',
          ),
        ],
      );
      final result = await orch.run();
      expect(result.stepResults, hasLength(2));
      expect(result.stepResults[0].output, 'step1-ok');
      expect(result.stepResults[1].output, 'step3-ok');
      expect(result.errors, hasLength(1));
      expect(result.errors.first, same(e));
    });
  });
}
