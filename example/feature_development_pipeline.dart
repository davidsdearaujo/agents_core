// Software Feature Development Pipeline — Orchestrator example.
//
// Demonstrates a realistic multi-agent software development pipeline using
// [Orchestrator] with a mix of [AgentStep], [AgentStep.dynamic], and
// [AgentLoopStep]. This is the go-to reference for building real workflows
// with agents_core.
//
// ## Pipeline overview
//
// Five stages run sequentially inside a single [Orchestrator.run()] call.
// Each stage's output is auto-persisted to the shared [FileContext] so that
// downstream stages can read upstream artifacts via dynamic prompts.
//
//  Stage 1 — Requirements Analysis     (AgentStep, static prompt)
//  Stage 2 — Architecture Design       (AgentStep.dynamic, reads requirements)
//  Stage 3 — Implementation            (AgentLoopStep, produce-review loop)
//  Stage 4 — Documentation             (AgentStep.dynamic, conditional)
//  Stage 5 — Security Audit            (AgentStep.dynamic, conditional)
//
// ## Key concepts shown
//
// - PersistingAgent decorator: wraps any Agent to auto-save output to a file
//   in the FileContext after each run, enabling inter-step communication
// - AgentStep with a static prompt (stage 1)
// - AgentStep.dynamic with FileContext-based prompt resolution (stages 2, 4, 5)
// - AgentLoopStep with custom buildProducerPrompt / buildReviewerPrompt (stage 3)
// - Conditional steps via condition callbacks (stages 4, 5)
// - OrchestratorErrorPolicy.continueOnError for resilient pipelines
// - StepResult pattern matching (AgentStepResult vs AgentLoopStepResult)
// - OrchestratorResult inspection: duration, token totals, per-step details
//
// ## Prerequisites
//
// - LM Studio running on localhost:1234 (the default)
// - A model loaded in LM Studio (e.g. llama-3-8b)
//
// ## Run
//
//   dart run example/feature_development_pipeline.dart
import 'dart:io';

import 'package:agents_core/agents_core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PersistingAgent — decorator that auto-saves output to FileContext
// ─────────────────────────────────────────────────────────────────────────────

/// An [Agent] decorator that writes its output to a workspace file after
/// each [run].
///
/// This bridges the gap between the Orchestrator (which collects results in
/// memory) and dynamic prompts in downstream steps (which read from the
/// shared [FileContext]). Wrap any agent with [PersistingAgent] to make its
/// output available to later pipeline stages.
///
/// ```dart
/// final agent = PersistingAgent(
///   delegate: mySimpleAgent,
///   outputFile: 'stage_output.md',
/// );
/// // After agent.run(), the output is in both the AgentResult AND
/// // the FileContext at 'stage_output.md'.
/// ```
class PersistingAgent extends Agent {
  /// Creates a [PersistingAgent].
  ///
  /// [delegate] is the wrapped agent that performs the actual work.
  /// [outputFile] is the workspace-relative path where output is saved.
  PersistingAgent({required this.delegate, required this.outputFile})
    : super(
        name: delegate.name,
        client: delegate.client,
        config: delegate.config,
        systemPrompt: delegate.systemPrompt,
        tools: delegate.tools,
        model: delegate.model,
      );

  /// The wrapped agent that performs the actual work.
  final Agent delegate;

  /// The workspace-relative file path where output is persisted.
  final String outputFile;

  @override
  Future<AgentResult> run(String task, {FileContext? context}) async {
    final result = await delegate.run(task, context: context);
    if (context != null) {
      context.write(outputFile, result.output);
    }
    return result;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pipeline configuration
// ─────────────────────────────────────────────────────────────────────────────

/// The feature request that drives the entire pipeline.
const _featureRequest = '''
Feature: User Authentication API

As a backend developer, I need a REST API endpoint for user authentication
that supports:
- Email/password login with JWT token generation
- Input validation (email format, password minimum length)
- Rate limiting (max 5 attempts per minute per IP)
- Proper HTTP status codes (200, 400, 401, 429)

The implementation should be in Dart using the shelf package.
''';

/// Workspace file names used as inter-step communication channels.
const _requirementsFile = 'requirements.md';
const _designFile = 'architecture.md';
const _implementationFile = 'implementation.dart';
const _documentationFile = 'api_documentation.md';
const _securityReportFile = 'security_report.md';

/// Marker the code reviewer uses to signal approval.
const _approvalMarker = 'APPROVED';

/// Status file written by the AgentLoopStep's producer. Downstream
/// conditional steps read this to decide whether to run.
const _implementationStatusFile = '.pipeline/implementation_accepted';

/// Human-readable stage labels for output formatting.
const _stageLabels = [
  'Requirements Analysis',
  'Architecture Design',
  'Implementation',
  'Documentation',
  'Security Audit',
];

// ─────────────────────────────────────────────────────────────────────────────
// Agent creation
// ─────────────────────────────────────────────────────────────────────────────

/// Creates the six specialised agents used in the pipeline.
///
/// Stages 1 and 2 are wrapped in [PersistingAgent] so their output is
/// auto-saved to the workspace for downstream dynamic prompts.
///
/// Stage 3 (AgentLoopStep) handles its own persistence via the custom
/// [buildProducerPrompt] / [buildReviewerPrompt] callbacks — the producer
/// and reviewer are used as-is.
({
  Agent analyst,
  Agent architect,
  SimpleAgent developer,
  SimpleAgent reviewer,
  Agent techWriter,
  Agent securityAuditor,
})
_createAgents({
  required LlmClient client,
  required AgentsCoreConfig config,
  required String model,
}) {
  // ── Stage 1: Requirements Analysis ──────────────────────────────────────
  final analyst = SimpleAgent(
    name: 'product-analyst',
    client: client,
    config: config,
    model: model,
    systemPrompt:
        'You are a senior product analyst. '
        'Given a feature request, produce a structured requirements '
        'document with:\n'
        '- Functional requirements (numbered FR-001, FR-002, ...)\n'
        '- Non-functional requirements (NFR-001, NFR-002, ...)\n'
        '- Acceptance criteria for each requirement\n'
        '- Edge cases and error scenarios\n'
        'Be thorough but concise. Use Markdown formatting.',
  );

  // ── Stage 2: Architecture Design ────────────────────────────────────────
  final architect = SimpleAgent(
    name: 'software-architect',
    client: client,
    config: config,
    model: model,
    systemPrompt:
        'You are a senior software architect. '
        'Given requirements, produce a technical design document with:\n'
        '- High-level architecture (components, data flow)\n'
        '- API contract (endpoints, request/response schemas)\n'
        '- Key design decisions and trade-offs\n'
        '- Dependencies and technology choices\n'
        'Output clean Markdown. Reference requirement IDs where applicable.',
  );

  // ── Stage 3: Implementation (producer + reviewer) ───────────────────────
  final developer = SimpleAgent(
    name: 'senior-developer',
    client: client,
    config: config,
    model: model,
    systemPrompt:
        'You are a senior Dart developer. '
        'Write clean, production-ready Dart code with:\n'
        '- Doc comments on all public APIs\n'
        '- Proper error handling\n'
        '- Input validation\n'
        '- Idiomatic Dart style (effective_dart conventions)\n'
        'When given review feedback, address every issue raised. '
        'Output only the Dart source code.',
  );

  final reviewer = SimpleAgent(
    name: 'code-reviewer',
    client: client,
    config: config,
    model: model,
    systemPrompt:
        'You are a strict code reviewer for Dart projects. '
        'Evaluate code against the design document and requirements. '
        'Check for:\n'
        '- Correctness and completeness\n'
        '- Error handling and edge cases\n'
        '- Security vulnerabilities\n'
        '- Code style and documentation\n'
        'If all criteria are met, begin your response with '
        '"$_approvalMarker". '
        'Otherwise, list numbered issues that must be fixed.',
  );

  // ── Stage 4: Documentation ──────────────────────────────────────────────
  final techWriter = SimpleAgent(
    name: 'tech-writer',
    client: client,
    config: config,
    model: model,
    systemPrompt:
        'You are a technical documentation specialist. '
        'Given source code and a design document, produce API '
        'documentation with:\n'
        '- Endpoint descriptions\n'
        '- Request/response examples (curl + JSON)\n'
        '- Error codes and meanings\n'
        '- Authentication flow diagram (ASCII)\n'
        'Use clean Markdown formatting.',
  );

  // ── Stage 5: Security Audit ─────────────────────────────────────────────
  final securityAuditor = SimpleAgent(
    name: 'security-auditor',
    client: client,
    config: config,
    model: model,
    systemPrompt:
        'You are an application security engineer. '
        'Review source code for vulnerabilities including:\n'
        '- Injection attacks (SQL, NoSQL, command)\n'
        '- Authentication/authorization flaws\n'
        '- Sensitive data exposure\n'
        '- Rate limiting bypass vectors\n'
        '- Dependency vulnerabilities\n'
        'Classify findings as CRITICAL / HIGH / MEDIUM / LOW. '
        'If no issues are found, state "No vulnerabilities identified."',
  );

  // Wrap stages 1, 2, 4, 5 with PersistingAgent for auto-save.
  return (
    analyst: PersistingAgent(delegate: analyst, outputFile: _requirementsFile),
    architect: PersistingAgent(delegate: architect, outputFile: _designFile),
    developer: developer,
    reviewer: reviewer,
    techWriter: PersistingAgent(
      delegate: techWriter,
      outputFile: _documentationFile,
    ),
    securityAuditor: PersistingAgent(
      delegate: securityAuditor,
      outputFile: _securityReportFile,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Pipeline definition
// ─────────────────────────────────────────────────────────────────────────────

/// Builds the five-stage orchestrator pipeline.
///
/// Each [OrchestratorStep] variant is demonstrated:
///
/// | Stage | Step Type               | Prompt       | Condition |
/// |-------|-------------------------|--------------|-----------|
/// | 1     | [AgentStep]             | static       | none      |
/// | 2     | [AgentStep.dynamic]     | from context | none      |
/// | 3     | [AgentLoopStep]         | static       | none      |
/// | 4     | [AgentStep.dynamic]     | from context | yes       |
/// | 5     | [AgentStep.dynamic]     | from context | yes       |
Orchestrator _buildPipeline({
  required FileContext context,
  required Agent analyst,
  required Agent architect,
  required SimpleAgent developer,
  required SimpleAgent reviewer,
  required Agent techWriter,
  required Agent securityAuditor,
}) {
  return Orchestrator(
    context: context,
    // Continue on error so partial results are still available.
    onError: OrchestratorErrorPolicy.continueOnError,
    steps: [
      // ── Stage 1: Requirements Analysis (AgentStep — static prompt) ──────
      //
      // The feature request is a compile-time constant, so we use the
      // simplest step type: AgentStep with a plain String prompt.
      // The PersistingAgent wrapper auto-saves output to requirements.md.
      AgentStep(
        agent: analyst,
        taskPrompt:
            'Analyze the following feature request and produce a '
            'structured requirements document.\n\n$_featureRequest',
      ),

      // ── Stage 2: Architecture Design (AgentStep.dynamic) ───────────────
      //
      // Reads requirements.md from the workspace (written by stage 1's
      // PersistingAgent) and builds the prompt at runtime.
      AgentStep.dynamic(
        agent: architect,
        taskPrompt: (FileContext ctx) async {
          final requirements = ctx.read(_requirementsFile);
          return 'Based on the following requirements, produce a technical '
              'design document.\n\n'
              '## Requirements\n\n$requirements';
        },
      ),

      // ── Stage 3: Implementation (AgentLoopStep — produce-review loop) ──
      //
      // The developer agent writes code; the code reviewer evaluates it.
      // The loop continues until the reviewer begins with "APPROVED" or
      // maxIterations (3) is reached.
      //
      // Custom prompt builders inject workspace artifacts (requirements +
      // design) into each round so agents have full context.
      AgentLoopStep(
        producer: developer,
        reviewer: reviewer,
        taskPrompt:
            'Implement the authentication API endpoint in Dart '
            'based on the design document and requirements.',
        maxIterations: 3,

        // Acceptance predicate: look for the APPROVED marker.
        isAccepted: (AgentResult reviewerResult, int iteration) {
          return reviewerResult.output.trim().toUpperCase().startsWith(
            _approvalMarker,
          );
        },

        // Custom producer prompt: full context + review feedback.
        buildProducerPrompt:
            (
              String originalTask,
              FileContext ctx,
              int iteration,
              AgentResult? previousReview,
            ) async {
              final design = ctx.read(_designFile);
              final requirements = ctx.read(_requirementsFile);

              final buffer = StringBuffer()
                ..writeln(originalTask)
                ..writeln()
                ..writeln('## Design Document')
                ..writeln()
                ..writeln(design)
                ..writeln()
                ..writeln('## Requirements')
                ..writeln()
                ..writeln(requirements);

              // From iteration 1+, include the reviewer's feedback.
              if (previousReview != null) {
                buffer
                  ..writeln()
                  ..writeln('---')
                  ..writeln('## Review Feedback (iteration $iteration)')
                  ..writeln()
                  ..writeln(previousReview.output)
                  ..writeln()
                  ..writeln(
                    'Address every issue above and produce the revised '
                    'implementation.',
                  );
              }

              return buffer.toString();
            },

        // Custom reviewer prompt: requirements + design + code.
        buildReviewerPrompt:
            (
              String originalTask,
              FileContext ctx,
              int iteration,
              AgentResult producerResult,
            ) async {
              final design = ctx.read(_designFile);
              final requirements = ctx.read(_requirementsFile);

              return 'Review the following Dart implementation against the '
                  'requirements and design document.\n\n'
                  '## Requirements\n\n$requirements\n\n'
                  '## Design Document\n\n$design\n\n'
                  '## Implementation (iteration $iteration)\n\n'
                  '```dart\n${producerResult.output}\n```\n\n'
                  'If the code meets all criteria, begin your response with '
                  '"$_approvalMarker". Otherwise, list the issues.';
            },
      ),

      // ── Stage 4: Documentation (AgentStep.dynamic, conditional) ────────
      //
      // Only runs if the implementation was approved (stage 3 writes a
      // status flag to the workspace). Reads the implementation and design
      // to produce API documentation.
      AgentStep.dynamic(
        agent: techWriter,
        taskPrompt: (FileContext ctx) async {
          final code = ctx.read(_implementationFile);
          final design = ctx.read(_designFile);

          return 'Generate API documentation for the following '
              'implementation.\n\n'
              '## Design Document\n\n$design\n\n'
              '## Source Code\n\n```dart\n$code\n```';
        },
        condition: (FileContext ctx) async {
          return ctx.exists(_implementationStatusFile) &&
              ctx.read(_implementationStatusFile) == 'true';
        },
      ),

      // ── Stage 5: Security Audit (AgentStep.dynamic, conditional) ───────
      //
      // Only runs if the implementation was approved. Reviews the code
      // for common vulnerability patterns.
      AgentStep.dynamic(
        agent: securityAuditor,
        taskPrompt: (FileContext ctx) async {
          final code = ctx.read(_implementationFile);
          final requirements = ctx.read(_requirementsFile);

          return 'Perform a security audit on the following Dart code.\n\n'
              '## Requirements\n\n$requirements\n\n'
              '## Source Code\n\n```dart\n$code\n```';
        },
        condition: (FileContext ctx) async {
          return ctx.exists(_implementationStatusFile) &&
              ctx.read(_implementationStatusFile) == 'true';
        },
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Result processing
// ─────────────────────────────────────────────────────────────────────────────

/// Processes the [AgentLoopStepResult] from stage 3 and writes status files
/// to the workspace so conditional stages 4 and 5 can decide whether to run.
///
/// This is called via a callback after stage 3 completes. In a production
/// system you might use an Orchestrator middleware/hook; here we process
/// results after [Orchestrator.run()] completes and re-run conditional
/// stages, or wire it into a custom orchestrator subclass.
void _persistLoopStatus(FileContext context, OrchestratorResult result) {
  // Find the implementation step result (stage 3 = index 2 if all ran).
  for (final stepResult in result.stepResults) {
    if (stepResult is AgentLoopStepResult) {
      // Save the final implementation to the workspace.
      context.write(_implementationFile, stepResult.output);

      // Write the acceptance flag for conditional stages.
      context.write(_implementationStatusFile, stepResult.accepted.toString());
      return;
    }
  }
}

/// Prints a detailed report of the orchestrator run.
void _printReport(OrchestratorResult result) {
  _printHeader('Pipeline Results');

  print('Steps executed:  ${result.stepResults.length} / 5');
  print('Duration:        ${_formatDuration(result.duration)}');
  print('Errors:          ${result.errors.length}');
  print('');

  // ── Per-step breakdown ──────────────────────────────────────────────────
  for (var i = 0; i < result.stepResults.length; i++) {
    final stepResult = result.stepResults[i];
    final label = i < _stageLabels.length ? _stageLabels[i] : 'Step $i';

    print('--- Stage ${i + 1}: $label ---');
    print('  Tokens:  ${stepResult.tokensUsed}');
    print('  Output:  ${stepResult.output.length} chars');

    // Pattern match on concrete StepResult type for extra details.
    switch (stepResult) {
      case AgentStepResult(:final agentResult):
        print('  Stopped: ${agentResult.stoppedReason ?? 'n/a'}');
      case AgentLoopStepResult(:final accepted, :final iterationCount):
        print('  Accepted:    $accepted');
        print('  Iterations:  $iterationCount');

        // Per-iteration token breakdown.
        final loopResult = stepResult.agentLoopResult;
        for (final iter in loopResult.iterations) {
          print(
            '    [${iter.index}] producer=${iter.producerResult.tokensUsed}'
            ', reviewer=${iter.reviewerResult.tokensUsed} tokens',
          );
        }
    }

    // Preview the output (first 200 chars, single line).
    print('  Preview: ${_truncate(stepResult.output, 200)}');
    print('');
  }

  // ── Aggregate token usage ───────────────────────────────────────────────
  final totalTokens = result.stepResults.fold<int>(
    0,
    (sum, r) => sum + r.tokensUsed,
  );
  print('Total tokens: $totalTokens');

  // ── Errors ──────────────────────────────────────────────────────────────
  if (result.hasErrors) {
    print('');
    _printHeader('Errors (continueOnError)');
    for (var i = 0; i < result.errors.length; i++) {
      print('  [$i] ${result.errors[i]}');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

Future<void> main() async {
  final config = AgentsCoreConfig(
    logger: const StderrLogger(level: LogLevel.info),
  );

  // ── Workspace ───────────────────────────────────────────────────────────
  final workspacePath =
      '${Directory.systemTemp.path}/agents_core_feature_pipeline';
  final context = FileContext(workspacePath: workspacePath);

  print('Feature Development Pipeline');
  print('============================\n');
  print('Workspace: ${context.workspacePath}\n');

  final client = LmStudioClient(config);

  try {
    // ── Create agents ─────────────────────────────────────────────────────
    const model = 'llama-3-8b';
    final agents = _createAgents(client: client, config: config, model: model);

    print('Agents:');
    print('  product-analyst       -> $_requirementsFile (auto-persist)');
    print('  software-architect    -> $_designFile (auto-persist)');
    print('  senior-developer      (producer in loop)');
    print('  code-reviewer         (reviewer in loop)');
    print('  tech-writer           -> $_documentationFile (auto-persist)');
    print('  security-auditor      -> $_securityReportFile (auto-persist)');
    print('');

    // ── Build the Orchestrator ────────────────────────────────────────────
    final pipeline = _buildPipeline(
      context: context,
      analyst: agents.analyst,
      architect: agents.architect,
      developer: agents.developer,
      reviewer: agents.reviewer,
      techWriter: agents.techWriter,
      securityAuditor: agents.securityAuditor,
    );

    print('Pipeline: ${pipeline.steps.length} stages');
    print('Error policy: ${pipeline.onError.name}');
    print('');

    // ── Phase 1: Run stages 1-3 ──────────────────────────────────────────
    //
    // Stages 1-2 auto-persist via PersistingAgent. Stage 3 (AgentLoopStep)
    // produces results that we persist manually before running conditional
    // stages 4-5 (which need the implementation file + acceptance flag).
    //
    // We build a two-phase pipeline: first run stages 1-3, persist loop
    // results, then run stages 4-5 conditionally.
    _printHeader('Phase 1: Stages 1-3');

    final phase1Pipeline = Orchestrator(
      context: context,
      onError: OrchestratorErrorPolicy.continueOnError,
      steps: pipeline.steps.sublist(0, 3), // stages 1, 2, 3
    );

    final phase1Result = await phase1Pipeline.run();

    // Persist the implementation loop's output + acceptance status.
    _persistLoopStatus(context, phase1Result);

    print('Phase 1 complete (${_formatDuration(phase1Result.duration)})\n');

    // ── Phase 2: Run stages 4-5 (conditional) ────────────────────────────
    _printHeader('Phase 2: Stages 4-5 (conditional)');

    final accepted =
        context.exists(_implementationStatusFile) &&
        context.read(_implementationStatusFile) == 'true';
    print('Implementation accepted: $accepted');

    if (accepted) {
      final phase2Pipeline = Orchestrator(
        context: context,
        onError: OrchestratorErrorPolicy.continueOnError,
        steps: pipeline.steps.sublist(3), // stages 4, 5
      );

      final phase2Result = await phase2Pipeline.run();
      print('Phase 2 complete (${_formatDuration(phase2Result.duration)})\n');

      // Combine results for the full report.
      final combinedResult = OrchestratorResult(
        stepResults: [...phase1Result.stepResults, ...phase2Result.stepResults],
        duration: phase1Result.duration + phase2Result.duration,
        errors: [...phase1Result.errors, ...phase2Result.errors],
      );

      _printReport(combinedResult);
    } else {
      print('Stages 4-5 skipped (implementation not approved).\n');
      _printReport(phase1Result);
    }

    // ── Workspace listing ─────────────────────────────────────────────────
    _printHeader('Workspace Artifacts');
    for (final file in context.listFiles()) {
      print('  $file');
    }
    print('');

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
