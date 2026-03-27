// ignore_for_file: avoid_implementing_value_types

import 'dart:io';

import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Queue-based [Agent] fake that supports multiple sequential calls.
///
/// Each call returns the next result from [results] (cycling on wrap-around).
/// If [errors] are provided, throws the error at the matching call index.
class _FakeAgent extends Agent {
  _FakeAgent({
    super.name = 'fake',
    List<AgentResult>? results,
    List<Object>? errors,
  })  : _results = results ?? const [],
        _errors = errors ?? const [],
        super(
          client: LmStudioClient(
            AgentsCoreConfig(logger: const SilentLogger()),
          ),
          config: AgentsCoreConfig(logger: const SilentLogger()),
        );

  /// Convenience: always return one fixed result regardless of call count.
  _FakeAgent.single({
    String name = 'fake',
    AgentResult result = const AgentResult(output: 'fake output'),
  }) : this(name: name, results: [result]);

  /// Convenience: throw [error] on the first call.
  _FakeAgent.throwing({String name = 'fake', required Object error})
      : this(name: name, errors: [error]);

  final List<AgentResult> _results;
  final List<Object> _errors;

  final List<String> capturedTasks = [];
  final List<FileContext?> capturedContexts = [];
  int callCount = 0;

  @override
  Future<AgentResult> run(String task, {FileContext? context}) async {
    final index = callCount;
    callCount++;
    capturedTasks.add(task);
    capturedContexts.add(context);

    if (_errors.isNotEmpty && index < _errors.length) {
      throw _errors[index];
    }

    if (_results.isNotEmpty) {
      return _results[index % _results.length];
    }
    return const AgentResult(output: 'fake output');
  }
}

/// An [Agent] that writes a named file to the shared [FileContext] when it runs.
///
/// Models agents (e.g. the triager) whose primary artefact is a workspace file
/// rather than a plain text output.
class _WritingFakeAgent extends Agent {
  _WritingFakeAgent({
    super.name = 'writing-fake',
    required this.fileName,
    required this.fileContent,
    AgentResult? result,
  })  : _result = result ?? AgentResult(output: fileContent),
        super(
          client: LmStudioClient(
            AgentsCoreConfig(logger: const SilentLogger()),
          ),
          config: AgentsCoreConfig(logger: const SilentLogger()),
        );

  final String fileName;
  final String fileContent;
  final AgentResult _result;

  String? capturedTask;
  FileContext? capturedContext;
  int callCount = 0;

  @override
  Future<AgentResult> run(String task, {FileContext? context}) async {
    callCount++;
    capturedTask = task;
    capturedContext = context;
    context?.write(fileName, fileContent);
    return _result;
  }
}

/// Creates a [FileContext] backed by a temporary directory.
({FileContext ctx, Directory dir}) _tempContext() {
  final dir = Directory.systemTemp.createTempSync('bugfix_pipeline_test_');
  final ctx = FileContext(workspacePath: dir.path);
  return (ctx: ctx, dir: dir);
}

/// Builds the 5-step bugfix pipeline for testing.
///
/// Pipeline stages:
///   1. [AgentStep]     — Triager produces triage.md
///   2. [AgentLoopStep] — Investigator proposes root causes; senior engineer confirms
///   3. [AgentLoopStep] — Developer writes fix; reviewer approves/rejects (conditional)
///   4. [AgentStep]     — Test writer produces regression tests (conditional)
///   5. [AgentStep]     — PR writer summarises the change (conditional)
///
/// Steps 3–5 are conditional: they only run when [ctx] contains `root_cause.md`.
/// That file is written inside [AgentLoopStep.isAccepted] at step 2, but only
/// when the senior engineer's response contains "CONFIRMED".
///
/// Mechanism for capturing the investigator's output inside [isAccepted]:
///   - [AgentLoopStep.buildReviewerPrompt] is called with the producer's result
///     before the reviewer runs, so we capture it in a closure variable
///     [lastInvestigatorOutput] that [isAccepted] can then persist.
Orchestrator _buildBugfixPipeline({
  required FileContext ctx,
  required Agent triager,
  required Agent investigator,
  required Agent seniorEngineer,
  required Agent developer,
  required Agent fixReviewer,
  required Agent testWriter,
  required Agent prWriter,
  OrchestratorErrorPolicy onError = OrchestratorErrorPolicy.stop,
}) {
  // Closure variable: captures the investigator's last output so isAccepted
  // can persist it to root_cause.md when the senior engineer confirms.
  var lastInvestigatorOutput = '';

  return Orchestrator(
    context: ctx,
    onError: onError,
    steps: [
      // ── Step 1: Triage ──────────────────────────────────────────────────
      //
      // The triager is a _WritingFakeAgent that auto-writes triage.md to the
      // shared workspace, simulating an agent that saves its structured output.
      AgentStep(
        agent: triager,
        taskPrompt: 'Triage the following bug report and provide a '
            'structured analysis with severity, affected components, and '
            'recommended next steps.',
      ),

      // ── Step 2: Root Cause Investigation (produce-review loop) ──────────
      //
      // The investigator proposes root cause hypotheses; the senior engineer
      // confirms or rejects each hypothesis.
      //
      // When confirmed, root_cause.md is written inside isAccepted via the
      // captured lastInvestigatorOutput from buildReviewerPrompt.
      AgentLoopStep(
        producer: investigator,
        reviewer: seniorEngineer,
        taskPrompt: 'Investigate the root cause of the bug and propose a '
            'detailed hypothesis with evidence.',
        maxIterations: 3,

        // Capture the investigator's output BEFORE the reviewer runs so that
        // isAccepted (called after the reviewer) can write it to root_cause.md.
        buildReviewerPrompt: (task, reviewCtx, i, producerResult) async {
          lastInvestigatorOutput = producerResult.output;
          return 'Review the following root cause hypothesis and respond with '
              '"CONFIRMED — ..." if correct, or '
              '"NOT CONFIRMED — ..." with reasons otherwise.\n\n'
              '${producerResult.output}';
        },

        // Write root_cause.md ONLY when the senior engineer confirms.
        // This keeps root_cause.md absent on acceptance failure, which
        // acts as a natural gate for downstream conditional steps.
        //
        // Uses startsWith('CONFIRMED') — not contains — so that a response
        // beginning with "NOT CONFIRMED" is never mistakenly accepted.
        isAccepted: (reviewerResult, iteration) {
          if (reviewerResult.output.trim().startsWith('CONFIRMED')) {
            ctx.write('root_cause.md', lastInvestigatorOutput);
            return true;
          }
          return false;
        },
      ),

      // ── Step 3: Fix Development (produce-review loop, conditional) ───────
      //
      // Runs only when root_cause.md exists (i.e. step 2 was accepted).
      // The developer's prompt is dynamically constructed from triage.md and
      // root_cause.md so the agent has full context for each iteration.
      AgentLoopStep(
        producer: developer,
        reviewer: fixReviewer,
        taskPrompt: 'Implement a fix for the identified root cause.',
        maxIterations: 3,
        condition: (condCtx) async => condCtx.exists('root_cause.md'),
        isAccepted: (reviewerResult, iteration) =>
            reviewerResult.output.trim().startsWith('APPROVED'),

        // Dynamic producer prompt: injects triage and root cause context.
        buildProducerPrompt: (task, prodCtx, i, prev) async {
          final triage =
              prodCtx.exists('triage.md') ? prodCtx.read('triage.md') : '';
          final rootCause = prodCtx.exists('root_cause.md')
              ? prodCtx.read('root_cause.md')
              : '';

          final buffer = StringBuffer()
            ..writeln(task)
            ..writeln()
            ..writeln('## Bug Triage')
            ..writeln()
            ..writeln(triage)
            ..writeln()
            ..writeln('## Root Cause')
            ..writeln()
            ..writeln(rootCause);

          // From iteration 1+, append the reviewer's feedback.
          if (prev != null) {
            buffer
              ..writeln()
              ..writeln('## Review Feedback (iteration $i)')
              ..writeln()
              ..writeln(prev.output)
              ..writeln()
              ..writeln('Address every issue above and revise the fix.');
          }

          return buffer.toString();
        },
      ),

      // ── Step 4: Regression Tests (conditional) ──────────────────────────
      AgentStep(
        agent: testWriter,
        taskPrompt: 'Write regression tests that verify the bug is fixed '
            'and guard against regressions.',
        condition: (condCtx) async => condCtx.exists('root_cause.md'),
      ),

      // ── Step 5: PR Summary (conditional) ────────────────────────────────
      AgentStep(
        agent: prWriter,
        taskPrompt: 'Write a pull request description summarising the bug, '
            'root cause, fix, and tests added.',
        condition: (condCtx) async => condCtx.exists('root_cause.md'),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Bugfix Pipeline', () {
    late Directory tempDir;
    late FileContext ctx;

    setUp(() {
      final result = _tempContext();
      tempDir = result.dir;
      ctx = result.ctx;
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    // ── 1. Full happy path ──────────────────────────────────────────────────

    test(
        'full happy path: all 5 steps execute with correct types and results',
        () async {
      // Step 1: triager writes triage.md and returns a summary.
      final triager = _WritingFakeAgent(
        name: 'triager',
        fileName: 'triage.md',
        fileContent: 'Severity: HIGH — NullPointerException in UserService',
        result: const AgentResult(
          output: 'Triage complete: HIGH severity, affects UserService',
          tokensUsed: 10,
        ),
      );

      // Step 2: investigator proposes root cause; senior engineer confirms on
      // first try → iterationCount == 1, accepted == true.
      final investigator = _FakeAgent.single(
        name: 'investigator',
        result: const AgentResult(
          output: 'Root cause: userRepository was not initialized',
          tokensUsed: 20,
        ),
      );
      final seniorEngineer = _FakeAgent.single(
        name: 'senior-engineer',
        result: const AgentResult(
          output: 'CONFIRMED — the root cause is correct',
          tokensUsed: 10,
        ),
      );

      // Step 3: developer writes fix; reviewer rejects once then approves →
      // iterationCount == 2, accepted == true.
      final developer = _FakeAgent(
        name: 'developer',
        results: [
          const AgentResult(
            output: 'fix v1 — adds null guard but forgets to init',
            tokensUsed: 30,
          ),
          const AgentResult(
            output: 'fix v2 — initializes repo in constructor',
            tokensUsed: 30,
          ),
        ],
      );
      final fixReviewer = _FakeAgent(
        name: 'fix-reviewer',
        results: [
          const AgentResult(
            output: 'REJECTED — missing initialization in constructor',
            tokensUsed: 10,
          ),
          const AgentResult(
            output: 'APPROVED — fix is complete and correct',
            tokensUsed: 10,
          ),
        ],
      );

      // Steps 4 and 5: simple single-result agents.
      final testWriter = _FakeAgent.single(
        name: 'test-writer',
        result: const AgentResult(
          output: 'Regression test: testUserServiceLoginNoNPE()',
          tokensUsed: 15,
        ),
      );
      final prWriter = _FakeAgent.single(
        name: 'pr-writer',
        result: const AgentResult(
          output: 'PR: Fix NPE in UserService.login() — closes #42',
          tokensUsed: 10,
        ),
      );

      final orch = _buildBugfixPipeline(
        ctx: ctx,
        triager: triager,
        investigator: investigator,
        seniorEngineer: seniorEngineer,
        developer: developer,
        fixReviewer: fixReviewer,
        testWriter: testWriter,
        prWriter: prWriter,
      );

      final result = await orch.run();

      // All 5 steps must have executed.
      expect(result.stepResults, hasLength(5));

      // Correct StepResult subtypes at each index.
      expect(result.stepResults[0], isA<AgentStepResult>());
      expect(result.stepResults[1], isA<AgentLoopStepResult>());
      expect(result.stepResults[2], isA<AgentLoopStepResult>());
      expect(result.stepResults[3], isA<AgentStepResult>());
      expect(result.stepResults[4], isA<AgentStepResult>());

      // Step 1: triage output.
      expect(result.stepResults[0].output,
          'Triage complete: HIGH severity, affects UserService');

      // Step 2: confirmed on first iteration.
      final step2 = result.stepResults[1] as AgentLoopStepResult;
      expect(step2.accepted, isTrue);
      expect(step2.iterationCount, 1);

      // Step 3: approved on second iteration.
      final step3 = result.stepResults[2] as AgentLoopStepResult;
      expect(step3.accepted, isTrue);
      expect(step3.iterationCount, 2);
      expect(step3.output, 'fix v2 — initializes repo in constructor');

      // Step 4: regression tests.
      expect(result.stepResults[3].output,
          'Regression test: testUserServiceLoginNoNPE()');

      // Step 5: PR summary.
      expect(result.stepResults[4].output,
          'PR: Fix NPE in UserService.login() — closes #42');

      // No errors.
      expect(result.hasErrors, isFalse);
      expect(result.errors, isEmpty);
    });

    // ── 2. Root cause rejected then confirmed ───────────────────────────────

    test(
        'root cause: first hypothesis rejected, second confirmed — '
        'iterationCount == 2, accepted == true',
        () async {
      final triager = _WritingFakeAgent(
        name: 'triager',
        fileName: 'triage.md',
        fileContent: 'Bug: NPE in auth module on login',
        result: const AgentResult(output: 'Triage done'),
      );

      // Investigator proposes two different hypotheses across two iterations.
      final investigator = _FakeAgent(
        name: 'investigator',
        results: [
          const AgentResult(output: 'Hypothesis 1: wrong config path'),
          const AgentResult(output: 'Hypothesis 2: missing null check in repo'),
        ],
      );
      // Senior engineer rejects first, confirms second.
      final seniorEngineer = _FakeAgent(
        name: 'senior-engineer',
        results: [
          const AgentResult(
            output: 'NOT CONFIRMED — the root cause is deeper, check DB layer',
          ),
          const AgentResult(
            output: 'CONFIRMED — the missing null check is the root cause',
          ),
        ],
      );

      final developer = _FakeAgent.single(
        name: 'developer',
        result: const AgentResult(output: 'fix implementation'),
      );
      final fixReviewer = _FakeAgent.single(
        name: 'fix-reviewer',
        result: const AgentResult(output: 'APPROVED — fix is correct'),
      );
      final testWriter = _FakeAgent.single(name: 'test-writer');
      final prWriter = _FakeAgent.single(name: 'pr-writer');

      final orch = _buildBugfixPipeline(
        ctx: ctx,
        triager: triager,
        investigator: investigator,
        seniorEngineer: seniorEngineer,
        developer: developer,
        fixReviewer: fixReviewer,
        testWriter: testWriter,
        prWriter: prWriter,
      );

      final result = await orch.run();

      // Step 2: 2 iterations required before confirmation.
      final step2 = result.stepResults[1] as AgentLoopStepResult;
      expect(step2.accepted, isTrue);
      expect(step2.iterationCount, 2);

      // root_cause.md was written with the second hypothesis's output.
      expect(ctx.exists('root_cause.md'), isTrue);
      expect(ctx.read('root_cause.md'), contains('Hypothesis 2'));

      // All 5 steps ran since root_cause.md exists.
      expect(result.stepResults, hasLength(5));

      // Both investigator calls fired.
      expect(investigator.callCount, 2);
      expect(seniorEngineer.callCount, 2);
    });

    // ── 3. Fix rejected then approved ───────────────────────────────────────

    test(
        'fix: developer rejected on iteration 1, approved on iteration 2 — '
        'iterationCount == 2, accepted == true',
        () async {
      final triager = _WritingFakeAgent(
        name: 'triager',
        fileName: 'triage.md',
        fileContent: 'Bug: memory leak in connection pool',
        result: const AgentResult(output: 'Triage done'),
      );

      // Root cause confirmed on first try.
      final investigator = _FakeAgent.single(
        name: 'investigator',
        result: const AgentResult(output: 'Connections not closed in finally'),
      );
      final seniorEngineer = _FakeAgent.single(
        name: 'senior-engineer',
        result: const AgentResult(output: 'CONFIRMED — connections not closed'),
      );

      // Developer submits two fix attempts; reviewer rejects first, approves second.
      final developer = _FakeAgent(
        name: 'developer',
        results: [
          const AgentResult(output: 'fix attempt 1 — closes in catch only'),
          const AgentResult(output: 'fix attempt 2 — closes in finally block'),
        ],
      );
      final fixReviewer = _FakeAgent(
        name: 'fix-reviewer',
        results: [
          const AgentResult(output: 'REJECTED — missing null check in close()'),
          const AgentResult(output: 'APPROVED — fix is correct and complete'),
        ],
      );

      final testWriter = _FakeAgent.single(name: 'test-writer');
      final prWriter = _FakeAgent.single(name: 'pr-writer');

      final orch = _buildBugfixPipeline(
        ctx: ctx,
        triager: triager,
        investigator: investigator,
        seniorEngineer: seniorEngineer,
        developer: developer,
        fixReviewer: fixReviewer,
        testWriter: testWriter,
        prWriter: prWriter,
      );

      final result = await orch.run();

      // Step 3: approved on second iteration.
      final step3 = result.stepResults[2] as AgentLoopStepResult;
      expect(step3.accepted, isTrue);
      expect(step3.iterationCount, 2);
      expect(step3.output, 'fix attempt 2 — closes in finally block');

      // Developer and fix-reviewer each called twice.
      expect(developer.callCount, 2);
      expect(fixReviewer.callCount, 2);

      // All 5 steps ran.
      expect(result.stepResults, hasLength(5));
    });

    // ── 4. Root cause fails → Steps 3–5 skipped ────────────────────────────

    test(
        'root cause not confirmed at maxIterations: steps 3-5 skipped, '
        'stepResults.length == 2, accepted == false',
        () async {
      final triager = _WritingFakeAgent(
        name: 'triager',
        fileName: 'triage.md',
        fileContent: 'Bug: timeout on heavy queries',
        result: const AgentResult(
          output: 'Triage complete: MEDIUM severity timeout issue',
          tokensUsed: 8,
        ),
      );

      // Investigator makes 3 proposals; none are confirmed.
      final investigator = _FakeAgent(
        name: 'investigator',
        results: [
          const AgentResult(output: 'Hypothesis 1: slow index'),
          const AgentResult(output: 'Hypothesis 2: missing cache'),
          const AgentResult(output: 'Hypothesis 3: n+1 query'),
        ],
      );
      // Senior engineer never returns "CONFIRMED".
      final seniorEngineer = _FakeAgent(
        name: 'senior-engineer',
        results: [
          const AgentResult(output: 'NOT CONFIRMED — keep looking'),
          const AgentResult(output: 'NOT CONFIRMED — still incorrect'),
          const AgentResult(output: 'NOT CONFIRMED — no clear root cause yet'),
        ],
      );

      final developer = _FakeAgent.single(name: 'developer');
      final fixReviewer = _FakeAgent.single(name: 'fix-reviewer');
      final testWriter = _FakeAgent.single(name: 'test-writer');
      final prWriter = _FakeAgent.single(name: 'pr-writer');

      final orch = _buildBugfixPipeline(
        ctx: ctx,
        triager: triager,
        investigator: investigator,
        seniorEngineer: seniorEngineer,
        developer: developer,
        fixReviewer: fixReviewer,
        testWriter: testWriter,
        prWriter: prWriter,
      );

      final result = await orch.run();

      // Only 2 step results: triage (step 1) + exhausted loop (step 2).
      expect(result.stepResults, hasLength(2));

      // Step 1: triage result.
      expect(result.stepResults[0], isA<AgentStepResult>());
      expect(result.stepResults[0].output,
          'Triage complete: MEDIUM severity timeout issue');

      // Step 2: loop ended without acceptance.
      final step2 = result.stepResults[1] as AgentLoopStepResult;
      expect(step2.accepted, isFalse);
      expect(step2.iterationCount, 3);

      // root_cause.md was never written — isAccepted never returned true.
      expect(ctx.exists('root_cause.md'), isFalse);

      // Steps 3–5 conditions evaluated to false → none ran.
      expect(developer.callCount, 0);
      expect(testWriter.callCount, 0);
      expect(prWriter.callCount, 0);

      // No exception was thrown — an unaccepted loop is not an error.
      expect(result.hasErrors, isFalse);
      expect(result.errors, isEmpty);
    });

    // ── 5. continueOnError — Step 2 throws ─────────────────────────────────

    test(
        'continueOnError: step 2 throws — error captured, steps 3-5 skipped, '
        'stepResults.length == 1',
        () async {
      final triager = _WritingFakeAgent(
        name: 'triager',
        fileName: 'triage.md',
        fileContent: 'Bug: crash on startup',
        result: const AgentResult(output: 'Triage complete', tokensUsed: 5),
      );

      // Investigator crashes on its first call.
      final investigator = _FakeAgent.throwing(
        name: 'investigator',
        error: Exception('investigator service unavailable'),
      );
      final seniorEngineer = _FakeAgent.single(name: 'senior-engineer');

      final developer = _FakeAgent.single(name: 'developer');
      final fixReviewer = _FakeAgent.single(name: 'fix-reviewer');
      final testWriter = _FakeAgent.single(name: 'test-writer');
      final prWriter = _FakeAgent.single(name: 'pr-writer');

      final orch = _buildBugfixPipeline(
        ctx: ctx,
        triager: triager,
        investigator: investigator,
        seniorEngineer: seniorEngineer,
        developer: developer,
        fixReviewer: fixReviewer,
        testWriter: testWriter,
        prWriter: prWriter,
        onError: OrchestratorErrorPolicy.continueOnError,
      );

      final result = await orch.run();

      // Exactly one error captured — from the step 2 crash.
      expect(result.hasErrors, isTrue);
      expect(result.errors.length, 1);
      expect(result.errors.first, isA<Exception>());

      // Only step 1 (triage) is in stepResults.
      // Step 2 failed (excluded). Steps 3–5 conditions are false (excluded).
      expect(result.stepResults, hasLength(1));
      expect(result.stepResults[0].output, 'Triage complete');

      // root_cause.md was never written — step 2 threw before isAccepted ran.
      expect(ctx.exists('root_cause.md'), isFalse);

      // Steps 3–5 never ran.
      expect(developer.callCount, 0);
      expect(testWriter.callCount, 0);
      expect(prWriter.callCount, 0);
    });

    // ── 6. Dynamic prompt reads from FileContext ────────────────────────────

    test(
        'step 3 developer prompt contains content from triage.md and root_cause.md',
        () async {
      // Use distinguishable content strings to confirm both files appear in
      // the developer's captured task.
      const triageContent =
          'NullPointerException in UserService.login() at line 42';
      const rootCauseContent =
          'Root cause: userRepository was not initialized before first use';

      final triager = _WritingFakeAgent(
        name: 'triager',
        fileName: 'triage.md',
        fileContent: triageContent,
        result: const AgentResult(output: 'Triage written to context'),
      );

      // Investigator output becomes root_cause.md content on confirmation.
      final investigator = _FakeAgent.single(
        name: 'investigator',
        result: AgentResult(output: rootCauseContent),
      );
      final seniorEngineer = _FakeAgent.single(
        name: 'senior-engineer',
        result: const AgentResult(
          output: 'CONFIRMED — root cause validated by senior engineer',
        ),
      );

      // Developer: approve immediately so we can inspect its captured prompt.
      final developer = _FakeAgent.single(
        name: 'developer',
        result: const AgentResult(output: 'fix implementation'),
      );
      final fixReviewer = _FakeAgent.single(
        name: 'fix-reviewer',
        result: const AgentResult(output: 'APPROVED — fix is complete'),
      );

      final testWriter = _FakeAgent.single(name: 'test-writer');
      final prWriter = _FakeAgent.single(name: 'pr-writer');

      final orch = _buildBugfixPipeline(
        ctx: ctx,
        triager: triager,
        investigator: investigator,
        seniorEngineer: seniorEngineer,
        developer: developer,
        fixReviewer: fixReviewer,
        testWriter: testWriter,
        prWriter: prWriter,
      );

      await orch.run();

      // Developer must have been called exactly once.
      expect(developer.capturedTasks, hasLength(1));

      final developerPrompt = developer.capturedTasks.first;

      // The prompt must embed content from both workspace files.
      expect(
        developerPrompt,
        contains(triageContent),
        reason: 'prompt should include triage.md content',
      );
      expect(
        developerPrompt,
        contains(rootCauseContent),
        reason: 'prompt should include root_cause.md content',
      );
    });
  });
}
