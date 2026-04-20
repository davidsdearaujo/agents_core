// ignore_for_file: avoid_implementing_value_types

import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

import '../helpers/fake_agents.dart';

/// Creates a [FileContext] backed by a temporary directory.
({FileContext ctx, Directory dir}) _tempContext() {
  final dir = Directory.systemTemp.createTempSync('orchestrator_example_test_');
  final ctx = FileContext(workspacePath: dir.path);
  return (ctx: ctx, dir: dir);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Orchestrator with AgentLoopStep', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    // ── 1. Full pipeline — happy path ────────────────────────────────────────

    test(
      'full pipeline: AgentStep → AgentLoopStep (accepted on iteration 2) → AgentStep.dynamic',
      () async {
        // Step 1: researcher returns a spec string.
        final researcher = FakeAgent.single(
          name: 'researcher',
          result: const AgentResult(
            output: 'Research spec: feature X — implement OAuth2',
            tokensUsed: 10,
          ),
        );

        // Step 2: producer/reviewer loop.
        // Reviewer rejects on iteration 0, approves on iteration 1.
        final producer = FakeAgent(
          name: 'producer',
          results: [
            const AgentResult(output: 'code v1 — incomplete', tokensUsed: 20),
            const AgentResult(output: 'code v2 — complete', tokensUsed: 20),
          ],
        );
        final reviewer = FakeAgent(
          name: 'reviewer',
          results: [
            const AgentResult(
              output: 'REJECTED: missing error handling',
              tokensUsed: 10,
            ),
            const AgentResult(output: 'APPROVED: looks good', tokensUsed: 10),
          ],
        );

        // Step 3: docs agent, receives a dynamic prompt built from FileContext.
        final docsAgent = FakeAgent.single(
          name: 'docs',
          result: const AgentResult(
            output: 'Documentation for feature X generated',
            tokensUsed: 15,
          ),
        );

        final orch = Orchestrator(
          context: ctx,
          steps: [
            AgentStep(
              agent: researcher,
              taskPrompt: 'Research feature X requirements',
            ),
            AgentLoopStep(
              producer: producer,
              reviewer: reviewer,
              taskPrompt: 'Implement feature X',
              isAccepted: (r, i) => r.output.contains('APPROVED'),
            ),
            AgentStep.dynamic(
              agent: docsAgent,
              taskPrompt: (c) async =>
                  'Generate docs for workspace at: ${c.workspacePath}',
            ),
          ],
        );

        final result = await orch.run();

        // Exactly 3 step results — one per executed step.
        expect(result.stepResults, hasLength(3));

        // Step-result types at each index.
        expect(result.stepResults[0], isA<AgentStepResult>());
        expect(result.stepResults[1], isA<AgentLoopStepResult>());
        expect(result.stepResults[2], isA<AgentStepResult>());

        // Step 1 output.
        expect(
          result.stepResults[0].output,
          'Research spec: feature X — implement OAuth2',
        );

        // Step 2 — accepted on second iteration.
        final loopStepResult = result.stepResults[1] as AgentLoopStepResult;
        expect(loopStepResult.accepted, isTrue);
        expect(loopStepResult.iterationCount, 2);
        expect(loopStepResult.output, 'code v2 — complete');

        // Step 3 output.
        expect(
          result.stepResults[2].output,
          'Documentation for feature X generated',
        );

        // No errors.
        expect(result.errors, isEmpty);
        expect(result.hasErrors, isFalse);

        // Duration is non-negative.
        expect(result.duration.inMicroseconds, greaterThanOrEqualTo(0));
      },
    );

    // ── 2. AgentLoopStep reaches maxIterations ──────────────────────────────

    test(
      'AgentLoopStep reaches maxIterations (3) without acceptance',
      () async {
        // Reviewer always rejects — loop must stop at maxIterations.
        final producer = FakeAgent(
          name: 'producer',
          results: [
            const AgentResult(output: 'attempt 1'),
            const AgentResult(output: 'attempt 2'),
            const AgentResult(output: 'attempt 3'),
          ],
        );
        final reviewer = FakeAgent(
          name: 'reviewer',
          results: [
            const AgentResult(output: 'REJECTED'),
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
              taskPrompt: 'Implement feature',
              isAccepted: (r, i) => r.output.contains('APPROVED'),
              maxIterations: 3,
            ),
          ],
        );

        final result = await orch.run();

        expect(result.stepResults, hasLength(1));
        final loopStepResult = result.stepResults.first as AgentLoopStepResult;
        expect(loopStepResult.accepted, isFalse);
        expect(loopStepResult.iterationCount, 3);
      },
    );

    // ── 3. Conditional step skipped ─────────────────────────────────────────

    test(
      'step 3 with condition: false is skipped — stepResults has only 2 entries',
      () async {
        final researcher = FakeAgent.single(
          name: 'researcher',
          result: const AgentResult(output: 'spec output'),
        );
        final producer = FakeAgent.single(
          name: 'producer',
          result: const AgentResult(output: 'code output'),
        );
        final reviewer = FakeAgent.single(
          name: 'reviewer',
          result: const AgentResult(output: 'APPROVED'),
        );
        final docsAgent = FakeAgent.single(name: 'docs');

        final orch = Orchestrator(
          context: ctx,
          steps: [
            AgentStep(agent: researcher, taskPrompt: 'Research task'),
            AgentLoopStep(
              producer: producer,
              reviewer: reviewer,
              taskPrompt: 'Implement task',
              isAccepted: (r, i) => r.output.contains('APPROVED'),
            ),
            AgentStep(
              agent: docsAgent,
              taskPrompt: 'Generate docs',
              condition: (_) async => false, // always skip
            ),
          ],
        );

        final result = await orch.run();

        // Step 3 skipped — only 2 results.
        expect(result.stepResults, hasLength(2));
        // Docs agent was never called.
        expect(docsAgent.callCount, 0);
        // Step 1 and step 2 ran.
        expect(researcher.callCount, 1);
        expect(producer.callCount, 1);
      },
    );

    // ── 4. Dynamic prompt reads from FileContext ────────────────────────────

    test(
      'dynamic prompt in step 3 receives content written to FileContext by step 1 agent',
      () async {
        // Step 1: writes 'spec.txt' into the shared FileContext.
        final researcher = WritingFakeAgent(
          name: 'researcher',
          fileName: 'spec.txt',
          fileContent: 'Feature spec: implement auth with JWT tokens',
          result: const AgentResult(output: 'spec written to context'),
        );

        // Step 2: approve immediately so we reach step 3.
        final producer = FakeAgent.single(
          name: 'producer',
          result: const AgentResult(output: 'auth implementation code'),
        );
        final reviewer = FakeAgent.single(
          name: 'reviewer',
          result: const AgentResult(output: 'APPROVED'),
        );

        // Step 3: dynamic prompt reads 'spec.txt' written by step 1.
        final docsAgent = FakeAgent.single(
          name: 'docs',
          result: const AgentResult(output: 'docs generated'),
        );

        final orch = Orchestrator(
          context: ctx,
          steps: [
            AgentStep(agent: researcher, taskPrompt: 'Write spec to context'),
            AgentLoopStep(
              producer: producer,
              reviewer: reviewer,
              taskPrompt: 'Implement feature from spec',
              isAccepted: (r, i) => r.output.contains('APPROVED'),
            ),
            AgentStep.dynamic(
              agent: docsAgent,
              taskPrompt: (c) async {
                final spec = c.read('spec.txt');
                return 'Document the following specification: $spec';
              },
            ),
          ],
        );

        await orch.run();

        // Docs agent called exactly once.
        expect(docsAgent.capturedTasks, hasLength(1));
        // The task prompt contains the file content written by the researcher.
        expect(
          docsAgent.capturedTasks.first,
          contains('Feature spec: implement auth with JWT tokens'),
        );
      },
    );

    // ── 5. Error policy — continueOnError ───────────────────────────────────

    test(
      'step 2 loop throws — continueOnError lets step 3 execute and captures error',
      () async {
        final researcher = FakeAgent.single(
          name: 'researcher',
          result: const AgentResult(output: 'spec'),
        );

        // Producer throws on its first call — the loop will propagate the error.
        final producer = FakeAgent.throwing(
          name: 'producer',
          error: Exception('loop producer crashed'),
        );
        final reviewer = FakeAgent(name: 'reviewer');

        final docsAgent = FakeAgent.single(
          name: 'docs',
          result: const AgentResult(
            output: 'docs generated despite loop error',
          ),
        );

        final orch = Orchestrator(
          context: ctx,
          onError: OrchestratorErrorPolicy.continueOnError,
          steps: [
            AgentStep(agent: researcher, taskPrompt: 'Research task'),
            AgentLoopStep(
              producer: producer,
              reviewer: reviewer,
              taskPrompt: 'Implement task',
              isAccepted: (r, i) => r.output.contains('APPROVED'),
            ),
            AgentStep(agent: docsAgent, taskPrompt: 'Generate docs'),
          ],
        );

        final result = await orch.run();

        // Step 3 still executes.
        expect(docsAgent.callCount, 1);

        // Step 1 (success) + step 3 (success) = 2 results; step 2 is absent.
        expect(result.stepResults, hasLength(2));
        expect(result.stepResults[0].output, 'spec');
        expect(
          result.stepResults[1].output,
          'docs generated despite loop error',
        );

        // Exactly one error captured — from step 2.
        expect(result.hasErrors, isTrue);
        expect(result.errors.length, 1);
        expect(result.errors.first, isA<Exception>());
      },
    );
  });
}
