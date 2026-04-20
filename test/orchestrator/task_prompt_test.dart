import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

import '../helpers/fake_agents.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a [FileContext] backed by a temporary directory.
({FileContext ctx, Directory dir}) _tempContext() {
  final dir = Directory.systemTemp.createTempSync('task_prompt_test_');
  final ctx = FileContext(workspacePath: dir.path);
  return (ctx: ctx, dir: dir);
}


// ---------------------------------------------------------------------------
// Tests — TaskPrompt sealed class unit tests
// ---------------------------------------------------------------------------

void main() {
  // ── StaticPrompt ───────────────────────────────────────────────────────────

  group('StaticPrompt', () {
    test('stores the String value', () {
      const prompt = StaticPrompt('hello world');
      expect(prompt.value, 'hello world');
    });

    test('is a TaskPrompt', () {
      const prompt = StaticPrompt('hello');
      expect(prompt, isA<TaskPrompt>());
    });

    test('value can be an empty string', () {
      const prompt = StaticPrompt('');
      expect(prompt.value, isEmpty);
    });

    test('value preserves leading and trailing whitespace', () {
      const prompt = StaticPrompt('  spaces  ');
      expect(prompt.value, '  spaces  ');
    });

    test('value preserves multiline strings', () {
      const multiline = 'line one\nline two\nline three';
      const prompt = StaticPrompt(multiline);
      expect(prompt.value, multiline);
    });

    test('two StaticPrompts with the same value are not the same instance', () {
      final a = StaticPrompt('x');
      final b = StaticPrompt('x');
      expect(identical(a, b), isFalse);
    });
  });

  // ── DynamicPrompt ──────────────────────────────────────────────────────────

  group('DynamicPrompt', () {
    test('stores the resolver function', () {
      Future<String> resolver(FileContext ctx) async => 'resolved';
      final prompt = DynamicPrompt(resolver);
      expect(prompt.resolver, same(resolver));
    });

    test('is a TaskPrompt', () {
      final prompt = DynamicPrompt((_) async => 'hello');
      expect(prompt, isA<TaskPrompt>());
    });

    test('resolver is not null after construction', () {
      final prompt = DynamicPrompt((_) async => 'x');
      expect(prompt.resolver, isNotNull);
    });

    test('resolver receives FileContext and returns expected string', () async {
      final (:ctx, :dir) = _tempContext();
      try {
        FileContext? receivedCtx;
        final prompt = DynamicPrompt((c) async {
          receivedCtx = c;
          return 'from context';
        });
        final result = await prompt.resolver(ctx);
        expect(result, 'from context');
        expect(receivedCtx, same(ctx));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('resolver can read FileContext to build a prompt string', () async {
      final (:ctx, :dir) = _tempContext();
      try {
        ctx.write('config.txt', 'model: gpt-4');
        final prompt = DynamicPrompt(
          (c) async => 'Use: ${c.read("config.txt")}',
        );
        final result = await prompt.resolver(ctx);
        expect(result, 'Use: model: gpt-4');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('resolver function identity is preserved', () {
      Future<String> fn(FileContext ctx) async => 'y';
      final prompt = DynamicPrompt(fn);
      // The resolver stored must be the exact same function object.
      expect(prompt.resolver, same(fn));
    });
  });

  // ── TaskPrompt sealed class pattern matching ───────────────────────────────

  group('TaskPrompt — sealed class exhaustive pattern matching', () {
    test('StaticPrompt resolves to its value in an exhaustive switch', () {
      const TaskPrompt prompt = StaticPrompt('static value');
      final result = switch (prompt) {
        StaticPrompt(:final value) => value,
        DynamicPrompt() => 'should not reach',
      };
      expect(result, 'static value');
    });

    test('DynamicPrompt is matched correctly in an exhaustive switch', () {
      final TaskPrompt prompt = DynamicPrompt((_) async => 'dyn');
      final matched = switch (prompt) {
        StaticPrompt() => false,
        DynamicPrompt() => true,
      };
      expect(matched, isTrue);
    });

    test('exhaustive switch covers all variants without a default branch', () {
      // Compile-time verification: this helper must compile without a default
      // case because TaskPrompt is a sealed class.
      String resolveSync(TaskPrompt p) => switch (p) {
        StaticPrompt(:final value) => value,
        DynamicPrompt() => '<dynamic>',
      };

      expect(resolveSync(const StaticPrompt('hello')), 'hello');
      expect(resolveSync(DynamicPrompt((_) async => 'x')), '<dynamic>');
    });

    test('StaticPrompt is a StaticPrompt but not a DynamicPrompt', () {
      const TaskPrompt p = StaticPrompt('x');
      expect(p, isA<StaticPrompt>());
      expect(p, isNot(isA<DynamicPrompt>()));
    });

    test('DynamicPrompt is a DynamicPrompt but not a StaticPrompt', () {
      final TaskPrompt p = DynamicPrompt((_) async => 'x');
      expect(p, isA<DynamicPrompt>());
      expect(p, isNot(isA<StaticPrompt>()));
    });
  });

  // ── AgentStep integration: taskPrompt returns TaskPrompt ──────────────────

  group('AgentStep.taskPrompt returns TaskPrompt', () {
    test('static constructor wraps string in StaticPrompt', () {
      final step = AgentStep(agent: FakeAgent(), taskPrompt: 'write a report');
      expect(step.taskPrompt, isA<StaticPrompt>());
      expect((step.taskPrompt as StaticPrompt).value, 'write a report');
    });

    test('dynamic constructor wraps function in DynamicPrompt', () {
      Future<String> fn(FileContext ctx) async => 'dynamic task';
      final step = AgentStep.dynamic(agent: FakeAgent(), taskPrompt: fn);
      expect(step.taskPrompt, isA<DynamicPrompt>());
      expect((step.taskPrompt as DynamicPrompt).resolver, same(fn));
    });

    test('StaticPrompt value matches the string passed to constructor', () {
      final step = AgentStep(agent: FakeAgent(), taskPrompt: 'exact prompt');
      final tp = step.taskPrompt;
      expect(tp, isA<StaticPrompt>());
      expect((tp as StaticPrompt).value, 'exact prompt');
    });

    test(
      'DynamicPrompt resolver is the function passed to dynamic constructor',
      () {
        Future<String> resolver(FileContext ctx) async => 'resolved prompt';
        final step = AgentStep.dynamic(
          agent: FakeAgent(),
          taskPrompt: resolver,
        );
        final tp = step.taskPrompt;
        expect(tp, isA<DynamicPrompt>());
        expect((tp as DynamicPrompt).resolver, same(resolver));
      },
    );
  });

  // ── AgentLoopStep integration: taskPrompt returns TaskPrompt ──────────────

  group('AgentLoopStep.taskPrompt returns TaskPrompt', () {
    test('static constructor wraps string in StaticPrompt', () {
      final step = AgentLoopStep(
        producer: FakeAgent(name: 'producer'),
        reviewer: FakeAgent(name: 'reviewer'),
        taskPrompt: 'implement feature X',
        isAccepted: (r, i) => false,
      );
      expect(step.taskPrompt, isA<StaticPrompt>());
      expect((step.taskPrompt as StaticPrompt).value, 'implement feature X');
    });

    test('dynamic constructor wraps function in DynamicPrompt', () {
      Future<String> fn(FileContext ctx) async => 'dynamic loop task';
      final step = AgentLoopStep.dynamic(
        producer: FakeAgent(name: 'producer'),
        reviewer: FakeAgent(name: 'reviewer'),
        taskPrompt: fn,
        isAccepted: (r, i) => false,
      );
      expect(step.taskPrompt, isA<DynamicPrompt>());
      expect((step.taskPrompt as DynamicPrompt).resolver, same(fn));
    });

    test('StaticPrompt value matches the string passed to constructor', () {
      final step = AgentLoopStep(
        producer: FakeAgent(name: 'producer'),
        reviewer: FakeAgent(name: 'reviewer'),
        taskPrompt: 'loop task prompt',
        isAccepted: (r, i) => false,
      );
      final tp = step.taskPrompt;
      expect(tp, isA<StaticPrompt>());
      expect((tp as StaticPrompt).value, 'loop task prompt');
    });

    test(
      'DynamicPrompt resolver is the function passed to dynamic constructor',
      () {
        Future<String> resolver(FileContext ctx) async => 'loop dynamic';
        final step = AgentLoopStep.dynamic(
          producer: FakeAgent(name: 'producer'),
          reviewer: FakeAgent(name: 'reviewer'),
          taskPrompt: resolver,
          isAccepted: (r, i) => false,
        );
        final tp = step.taskPrompt;
        expect(tp, isA<DynamicPrompt>());
        expect((tp as DynamicPrompt).resolver, same(resolver));
      },
    );
  });

  // ── Orchestrator resolves TaskPrompt correctly ────────────────────────────

  group('Orchestrator resolves TaskPrompt', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test(
      'StaticPrompt is passed directly to agent.run() without a function call',
      () async {
        final agent = FakeAgent();
        final orch = Orchestrator(
          context: ctx,
          steps: [AgentStep(agent: agent, taskPrompt: 'static task')],
        );
        await orch.run();
        expect(agent.capturedTask, 'static task');
      },
    );

    test(
      'DynamicPrompt resolver is called with the orchestrator FileContext',
      () async {
        FileContext? capturedCtx;
        final agent = FakeAgent();
        final orch = Orchestrator(
          context: ctx,
          steps: [
            AgentStep.dynamic(
              agent: agent,
              taskPrompt: (c) async {
                capturedCtx = c;
                return 'resolved dynamic task';
              },
            ),
          ],
        );
        await orch.run();
        expect(capturedCtx, same(ctx));
        expect(agent.capturedTask, 'resolved dynamic task');
      },
    );

    test(
      'no runtime cast needed in Orchestrator.run() — switch is exhaustive',
      () async {
        // This test verifies that both prompt types are handled by the
        // switch without falling through — proved by the fact that the
        // agent receives the correctly resolved string in both cases.
        final staticAgent = FakeAgent(name: 'static');
        final dynamicAgent = FakeAgent(name: 'dynamic');

        final orch = Orchestrator(
          context: ctx,
          steps: [
            AgentStep(agent: staticAgent, taskPrompt: 'from static'),
            AgentStep.dynamic(
              agent: dynamicAgent,
              taskPrompt: (_) async => 'from dynamic',
            ),
          ],
        );
        await orch.run();

        expect(staticAgent.capturedTask, 'from static');
        expect(dynamicAgent.capturedTask, 'from dynamic');
      },
    );

    test('AgentLoopStep with StaticPrompt resolves correctly', () async {
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
            taskPrompt: 'loop static task',
            isAccepted: (r, i) => r.output.contains('ACCEPTED'),
          ),
        ],
      );
      await orch.run();

      // The first prompt sent to the producer must contain the static task.
      expect(producer.capturedTask, contains('loop static task'));
    });

    test(
      'AgentLoopStep with DynamicPrompt resolves from FileContext',
      () async {
        ctx.write('task.txt', 'dynamic loop task');

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
            AgentLoopStep.dynamic(
              producer: producer,
              reviewer: reviewer,
              taskPrompt: (c) async => c.read('task.txt'),
              isAccepted: (r, i) => r.output.contains('ACCEPTED'),
            ),
          ],
        );
        await orch.run();

        expect(producer.capturedTask, contains('dynamic loop task'));
      },
    );
  });
}
