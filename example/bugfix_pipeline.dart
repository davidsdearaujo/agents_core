// Bugfix Pipeline — 5-step Orchestrator example.
//
// Demonstrates a realistic end-to-end bugfix workflow using [Orchestrator]
// with a mix of [AgentStep], [AgentStep.dynamic], and [AgentLoopStep.dynamic].
// All agents are [ReActAgent]s with file-context tools, so each step writes its
// output to the shared [FileContext] workspace as part of execution — enabling
// a single [Orchestrator.run()] call to produce all artifacts end-to-end.
//
// ## Pipeline overview
//
// Five stages run sequentially inside a single [Orchestrator.run()] call:
//
//  Step 1 — Bug Triage              (AgentStep, static prompt)
//  Step 2 — Root Cause Analysis     (AgentLoopStep.dynamic, produce-review)
//  Step 3 — Fix Implementation      (AgentLoopStep.dynamic, produce-review)
//  Step 4 — Regression Tests        (AgentStep.dynamic, conditional)
//  Step 5 — PR Summary              (AgentStep.dynamic, conditional)
//
// ## Key concepts shown
//
// - ReActAgent with file-context tools for inter-step communication
// - AgentStep with a static prompt (step 1)
// - AgentLoopStep.dynamic with FileContext-based prompt resolution (steps 2, 3)
// - AgentStep.dynamic with conditional execution (steps 4, 5)
// - Custom buildProducerPrompt injecting reviewer feedback on iteration 1+
// - Condition callbacks creating a fail-fast cascade (no root cause → no fix →
//   no tests → no PR)
// - OrchestratorErrorPolicy.continueOnError for resilient pipelines
// - StepResult pattern matching (AgentStepResult vs AgentLoopStepResult)
// - Post-run inspection: step summaries, pipeline stats, workspace manifest
//
// ## Prerequisites
//
// - LM Studio running on localhost:1234 (the default)
// - A model loaded in LM Studio (e.g. llama-3-8b)
//
// ## Run
//
//   dart run example/bugfix_pipeline.dart
import 'dart:io';

import 'package:agents_core/agents_core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Workspace file names — inter-step communication channels
// ─────────────────────────────────────────────────────────────────────────────

/// Structured triage produced by step 1.
const _triageFile = 'triage.md';

/// Root cause analysis produced by step 2.
const _rootCauseFile = 'root_cause.md';

/// Minimal targeted fix produced by step 3.
const _fixFile = 'fix.dart';

/// Regression tests produced by step 4.
const _testsFile = 'regression_tests.dart';

/// PR description produced by step 5.
const _prSummaryFile = 'pr_summary.md';

/// The raw bug report that drives the entire pipeline.
const _bugReport = '''
Bug: Dashboard export fails with "TypeError: Cannot read property 'map' of undefined"
when clicking "Export as CSV" on a dashboard with no data widgets.
Reported by 3 users. Happens consistently on Chrome and Firefox.''';

/// Human-readable step labels for output formatting.
const _stepLabels = [
  'Bug Triage',
  'Root Cause Analysis',
  'Fix Implementation',
  'Regression Tests',
  'PR Summary',
];

// ─────────────────────────────────────────────────────────────────────────────
// Agent creation
// ─────────────────────────────────────────────────────────────────────────────

/// File-context tool definitions shared by all ReActAgents.
const _fileTools = [readFileTool, writeFileTool, listFilesTool];

/// Creates the seven specialised agents used across the five pipeline steps.
///
/// Every agent is a [ReActAgent] with file-context tools so it can read
/// upstream artifacts and write its own output to the workspace.
({
  ReActAgent triager,
  ReActAgent investigator,
  ReActAgent seniorEngineer,
  ReActAgent fixDeveloper,
  ReActAgent fixReviewer,
  ReActAgent testWriter,
  ReActAgent prWriter,
}) _createAgents({
  required LmStudioClient client,
  required AgentsCoreConfig config,
  required FileContext context,
  required String model,
}) {
  final handlers = createHandlers(context);

  // ── Step 1: Bug Triage ──────────────────────────────────────────────────
  final triager = ReActAgent(
    name: 'bug-triager',
    client: client,
    config: config,
    model: model,
    tools: _fileTools,
    toolHandlers: handlers,
    maxIterations: 5,
    systemPrompt: 'You are a senior QA engineer specialising in bug triage. '
        'Given a raw bug report, produce a structured triage document with:\n'
        '- Severity (P0-P4)\n'
        '- Affected component\n'
        '- Reproduction steps\n'
        '- Expected vs actual behaviour\n'
        '- Initial hypotheses (ranked by likelihood)\n\n'
        'Write your output to "$_triageFile" using the write_file tool. '
        'Use Markdown formatting.',
  );

  // ── Step 2: Root Cause Analysis (producer + reviewer) ───────────────────
  final investigator = ReActAgent(
    name: 'investigator',
    client: client,
    config: config,
    model: model,
    tools: _fileTools,
    toolHandlers: handlers,
    maxIterations: 5,
    systemPrompt: 'You are a senior software engineer investigating bugs. '
        'Analyse the triage report and propose a root cause with supporting '
        'evidence. Structure your analysis as:\n'
        '- Root cause statement\n'
        '- Evidence / reasoning\n'
        '- Affected code paths\n'
        '- Confidence level (high / medium / low)\n\n'
        'Write your analysis to "$_rootCauseFile" using the write_file tool. '
        'Use Markdown formatting.',
  );

  final seniorEngineer = ReActAgent(
    name: 'senior-engineer',
    client: client,
    config: config,
    model: model,
    tools: _fileTools,
    toolHandlers: handlers,
    maxIterations: 5,
    systemPrompt: 'You are a principal engineer validating root cause analyses. '
        'Review the proposed root cause against the triage report. Check:\n'
        '- Is the hypothesis consistent with all symptoms?\n'
        '- Are there alternative explanations?\n'
        '- Is the evidence sufficient?\n\n'
        'If the root cause is sound, begin your response with "CONFIRMED" '
        'followed by a brief justification. Otherwise, list the gaps and '
        'suggest what to investigate next.',
  );

  // ── Step 3: Fix Implementation (producer + reviewer) ────────────────────
  final fixDeveloper = ReActAgent(
    name: 'fix-developer',
    client: client,
    config: config,
    model: model,
    tools: _fileTools,
    toolHandlers: handlers,
    maxIterations: 5,
    systemPrompt: 'You are a senior Dart developer writing targeted bugfixes. '
        'Given a root cause analysis and triage, write a minimal fix that:\n'
        '- Addresses the root cause directly\n'
        '- Has minimal scope (no unrelated refactors)\n'
        '- Handles edge cases mentioned in the triage\n'
        '- Includes doc comments on changed methods\n\n'
        'Write your fix to "$_fixFile" using the write_file tool. '
        'Output only the Dart source code.',
  );

  final fixReviewer = ReActAgent(
    name: 'fix-reviewer',
    client: client,
    config: config,
    model: model,
    tools: _fileTools,
    toolHandlers: handlers,
    maxIterations: 5,
    systemPrompt: 'You are a strict code reviewer for bugfix PRs. '
        'Evaluate the fix against the root cause and triage. Check:\n'
        '- Does the fix actually address the root cause?\n'
        '- Is the scope minimal (no unnecessary changes)?\n'
        '- Are edge cases handled?\n'
        '- Is the code clean and well-documented?\n\n'
        'If the fix is correct and complete, begin your response with '
        '"APPROVED". Otherwise, list numbered issues that must be addressed.',
  );

  // ── Step 4: Regression Tests ────────────────────────────────────────────
  final testWriter = ReActAgent(
    name: 'test-writer',
    client: client,
    config: config,
    model: model,
    tools: _fileTools,
    toolHandlers: handlers,
    maxIterations: 5,
    systemPrompt: 'You are a QA engineer writing regression tests in Dart. '
        'Given a bugfix and its root cause, write unit tests that:\n'
        '- Reproduce the original bug (test should fail without the fix)\n'
        '- Verify the fix works correctly\n'
        '- Cover edge cases from the triage report\n'
        '- Use the `package:test` framework\n\n'
        'Write your tests to "$_testsFile" using the write_file tool.',
  );

  // ── Step 5: PR Summary ─────────────────────────────────────────────────
  final prWriter = ReActAgent(
    name: 'pr-writer',
    client: client,
    config: config,
    model: model,
    tools: _fileTools,
    toolHandlers: handlers,
    maxIterations: 5,
    systemPrompt: 'You are a developer writing pull request descriptions. '
        'Read all workspace artifacts and produce a PR description with:\n'
        '- Title (concise, under 72 chars)\n'
        '- Summary (1-3 sentences)\n'
        '- Root cause explanation\n'
        '- Changes made\n'
        '- Test coverage summary\n'
        '- Follow-up items (if any)\n\n'
        'Write your PR description to "$_prSummaryFile" using the '
        'write_file tool. Use Markdown formatting.',
  );

  return (
    triager: triager,
    investigator: investigator,
    seniorEngineer: seniorEngineer,
    fixDeveloper: fixDeveloper,
    fixReviewer: fixReviewer,
    testWriter: testWriter,
    prWriter: prWriter,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Pipeline definition
// ─────────────────────────────────────────────────────────────────────────────

/// Builds the five-step bugfix orchestrator pipeline.
///
/// | Step | Type                    | Agent(s)                          | Output file          |
/// |------|-------------------------|-----------------------------------|----------------------|
/// | 1    | [AgentStep]             | bug-triager                       | triage.md            |
/// | 2    | [AgentLoopStep.dynamic] | investigator + senior-engineer    | root_cause.md        |
/// | 3    | [AgentLoopStep.dynamic] | fix-developer + fix-reviewer      | fix.dart             |
/// | 4    | [AgentStep.dynamic]     | test-writer                       | regression_tests.dart|
/// | 5    | [AgentStep.dynamic]     | pr-writer                         | pr_summary.md        |
Orchestrator _buildPipeline({
  required FileContext context,
  required ReActAgent triager,
  required ReActAgent investigator,
  required ReActAgent seniorEngineer,
  required ReActAgent fixDeveloper,
  required ReActAgent fixReviewer,
  required ReActAgent testWriter,
  required ReActAgent prWriter,
}) {
  return Orchestrator(
    context: context,
    onError: OrchestratorErrorPolicy.continueOnError,
    steps: [
      // ── Step 1: Bug Triage (AgentStep — static prompt) ──────────────────
      //
      // Takes the raw bug report and produces a structured triage document.
      // The ReActAgent writes triage.md to the workspace via file-context tools.
      AgentStep(
        agent: triager,
        taskPrompt: 'Triage the following bug report. Produce a structured '
            'analysis and save it to "$_triageFile" using the write_file tool.'
            '\n\n$_bugReport',
      ),

      // ── Step 2: Root Cause Analysis (AgentLoopStep.dynamic) ─────────────
      //
      // The investigator reads triage.md and proposes a root cause.
      // The senior engineer validates the hypothesis. Loop until CONFIRMED
      // or maxIterations (3) is reached.
      AgentLoopStep.dynamic(
        producer: investigator,
        reviewer: seniorEngineer,
        taskPrompt: (FileContext ctx) async {
          final triage = ctx.read(_triageFile);
          return 'Analyse the following triage report and determine the root '
              'cause. Save your analysis to "$_rootCauseFile" using the '
              'write_file tool.\n\n'
              '## Triage Report\n\n$triage';
        },
        maxIterations: 3,
        isAccepted: (AgentResult result, int iteration) {
          return result.output.trim().toUpperCase().startsWith('CONFIRMED');
        },
      ),

      // ── Step 3: Fix Implementation (AgentLoopStep.dynamic) ──────────────
      //
      // The fix-developer writes a minimal targeted fix.
      // The fix-reviewer checks correctness, scope, and edge cases.
      // Loop until APPROVED or maxIterations (4) is reached.
      // Only runs if root_cause.md exists (step 2 succeeded).
      AgentLoopStep.dynamic(
        producer: fixDeveloper,
        reviewer: fixReviewer,
        taskPrompt: (FileContext ctx) async {
          final triage = ctx.read(_triageFile);
          final rootCause = ctx.read(_rootCauseFile);
          return 'Implement a minimal fix for the bug. Save your code to '
              '"$_fixFile" using the write_file tool.\n\n'
              '## Triage Report\n\n$triage\n\n'
              '## Root Cause Analysis\n\n$rootCause';
        },
        maxIterations: 4,
        isAccepted: (AgentResult result, int iteration) {
          return result.output.trim().toUpperCase().startsWith('APPROVED');
        },
        buildProducerPrompt: (
          String originalTask,
          FileContext ctx,
          int iteration,
          AgentResult? previousReview,
        ) async {
          if (iteration == 0) return originalTask;

          final buffer = StringBuffer()
            ..writeln(originalTask)
            ..writeln()
            ..writeln('---')
            ..writeln('## Reviewer Feedback (iteration $iteration)')
            ..writeln()
            ..writeln(previousReview?.output ?? '')
            ..writeln()
            ..writeln('Address every issue above and produce the revised fix. '
                'Save the updated code to "$_fixFile" using write_file.');

          return buffer.toString();
        },
        condition: (FileContext ctx) async => ctx.exists(_rootCauseFile),
      ),

      // ── Step 4: Regression Tests (AgentStep.dynamic, conditional) ───────
      //
      // Writes Dart unit tests reproducing the original bug and verifying
      // the fix. Only runs if fix.dart exists (step 3 succeeded).
      AgentStep.dynamic(
        agent: testWriter,
        taskPrompt: (FileContext ctx) async {
          final triage = ctx.read(_triageFile);
          final rootCause = ctx.read(_rootCauseFile);
          final fix = ctx.read(_fixFile);
          return 'Write regression tests for the following bugfix. Save them '
              'to "$_testsFile" using the write_file tool.\n\n'
              '## Triage Report\n\n$triage\n\n'
              '## Root Cause Analysis\n\n$rootCause\n\n'
              '## Fix Implementation\n\n```dart\n$fix\n```';
        },
        condition: (FileContext ctx) async => ctx.exists(_fixFile),
      ),

      // ── Step 5: PR Summary (AgentStep.dynamic, conditional) ─────────────
      //
      // Generates a PR description from all workspace artifacts.
      // Only runs if regression_tests.dart exists (step 4 succeeded).
      AgentStep.dynamic(
        agent: prWriter,
        taskPrompt: (FileContext ctx) async {
          final triage = ctx.read(_triageFile);
          final rootCause = ctx.read(_rootCauseFile);
          final fix = ctx.read(_fixFile);
          final tests = ctx.read(_testsFile);
          return 'Generate a PR description for this bugfix. Read all context '
              'below and save the PR description to "$_prSummaryFile" using '
              'the write_file tool.\n\n'
              '## Triage Report\n\n$triage\n\n'
              '## Root Cause Analysis\n\n$rootCause\n\n'
              '## Fix Implementation\n\n```dart\n$fix\n```\n\n'
              '## Regression Tests\n\n```dart\n$tests\n```';
        },
        condition: (FileContext ctx) async => ctx.exists(_testsFile),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Result processing
// ─────────────────────────────────────────────────────────────────────────────

/// Prints a step-by-step summary of the orchestrator run.
void _printStepSummary(OrchestratorResult result) {
  _printHeader('Step-by-Step Summary');

  for (var i = 0; i < result.stepResults.length; i++) {
    final stepResult = result.stepResults[i];
    final label = i < _stepLabels.length ? _stepLabels[i] : 'Step ${i + 1}';

    print('--- Step ${i + 1}: $label ---');

    if (stepResult is AgentStepResult) {
      print('  Type:    AgentStepResult');
      print('  Tokens:  ${stepResult.tokensUsed}');
      print('  Output:  ${_truncate(stepResult.output, 100)}');
    } else if (stepResult is AgentLoopStepResult) {
      print('  Type:       AgentLoopStepResult');
      print('  Accepted:   ${stepResult.accepted}');
      print('  Iterations: ${stepResult.iterationCount}');
      print('  Tokens:     ${stepResult.tokensUsed}');

      // Per-iteration reviewer feedback summaries.
      final loopResult = stepResult.agentLoopResult;
      for (final iter in loopResult.iterations) {
        print('    [${iter.index}] producer=${iter.producerResult.tokensUsed}'
            ', reviewer=${iter.reviewerResult.tokensUsed} tokens');
        print('         reviewer: '
            '${_truncate(iter.reviewerResult.output, 80)}');
      }
    }

    print('');
  }
}

/// Prints aggregate pipeline stats.
void _printPipelineStats(OrchestratorResult result) {
  _printHeader('Pipeline Stats');

  final totalTokens =
      result.stepResults.fold<int>(0, (sum, r) => sum + r.tokensUsed);

  print('Duration:     ${_formatDuration(result.duration)}');
  print('Total tokens: $totalTokens');
  print('Steps run:    ${result.stepResults.length} / ${_stepLabels.length}');
  print('Errors:       ${result.errors.length}');

  if (result.hasErrors) {
    print('');
    for (var i = 0; i < result.errors.length; i++) {
      print('  [$i] ${result.errors[i]}');
    }
  }

  print('');
}

/// Prints the workspace file manifest with sizes.
void _printWorkspaceManifest(FileContext context) {
  _printHeader('Workspace Manifest');

  final files = context.listFiles();
  if (files.isEmpty) {
    print('  (no files)');
  } else {
    for (final file in files) {
      final content = context.read(file);
      print('  $file (${content.length} bytes)');
    }
  }

  print('');
}

/// Prints the final PR summary or a message that the pipeline stopped early.
void _printFinalPrSummary(FileContext context) {
  _printHeader('Final PR Summary');

  if (context.exists(_prSummaryFile)) {
    print(context.read(_prSummaryFile));
  } else {
    print('Pipeline stopped before PR summary was generated.');
    print('Check the step results above for details.');
  }

  print('');
}

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

Future<void> main() async {
  final config = AgentsCoreConfig(
    logger: const StderrLogger(level: LogLevel.info),
  );

  // ── Workspace ─────────────────────────────────────────────────────────
  final workspacePath =
      '${Directory.systemTemp.path}/agents_core_bugfix_pipeline';
  final context = FileContext(workspacePath: workspacePath);

  print('Bugfix Pipeline');
  print('===============\n');
  print('Workspace: ${context.workspacePath}');
  print('Bug report:');
  print('  $_bugReport\n');

  final client = LmStudioClient(config);

  try {
    // ── Create agents ───────────────────────────────────────────────────
    const model = 'llama-3-8b';
    final agents = _createAgents(
      client: client,
      config: config,
      context: context,
      model: model,
    );

    print('Agents:');
    print('  bug-triager         -> $_triageFile');
    print('  investigator        -> $_rootCauseFile (producer in loop)');
    print('  senior-engineer     (reviewer in loop)');
    print('  fix-developer       -> $_fixFile (producer in loop)');
    print('  fix-reviewer        (reviewer in loop)');
    print('  test-writer         -> $_testsFile');
    print('  pr-writer           -> $_prSummaryFile');
    print('');

    // ── Build and run the pipeline ──────────────────────────────────────
    final pipeline = _buildPipeline(
      context: context,
      triager: agents.triager,
      investigator: agents.investigator,
      seniorEngineer: agents.seniorEngineer,
      fixDeveloper: agents.fixDeveloper,
      fixReviewer: agents.fixReviewer,
      testWriter: agents.testWriter,
      prWriter: agents.prWriter,
    );

    print('Pipeline: ${pipeline.steps.length} steps');
    print('Error policy: ${pipeline.onError.name}\n');

    _printHeader('Running Pipeline');

    final result = await pipeline.run();

    print('Pipeline complete (${_formatDuration(result.duration)})\n');

    // ── Post-run output ─────────────────────────────────────────────────
    _printStepSummary(result);
    _printPipelineStats(result);
    _printWorkspaceManifest(context);
    _printFinalPrSummary(context);

    print('All artifacts saved to: ${context.workspacePath}');
  } on LmStudioConnectionException catch (e) {
    stderr.writeln('Connection error: ${e.message}');
    stderr.writeln('Make sure LM Studio is running on localhost:1234.');
    exit(1);
  } finally {
    client.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Formatting helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Prints a section header.
void _printHeader(String title) {
  print('=== $title ===\n');
}

/// Truncates [text] to [maxLength] characters for single-line previews.
String _truncate(String text, int maxLength) {
  final singleLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (singleLine.length <= maxLength) return singleLine;
  return '${singleLine.substring(0, maxLength)}...';
}

/// Formats a [Duration] as a human-readable string.
String _formatDuration(Duration d) {
  if (d.inMinutes > 0) {
    return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  }
  if (d.inSeconds > 0) {
    return '${d.inSeconds}.${d.inMilliseconds.remainder(1000) ~/ 100}s';
  }
  return '${d.inMilliseconds}ms';
}
