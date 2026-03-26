// Orchestrator pipeline with AgentLoopStep example.
//
// Demonstrates a 3-step Orchestrator pipeline that combines single-agent steps
// with a produce-review loop step:
//
// 1. Researcher (AgentStep) — generates a specification for a Stack data
//    structure.
// 2. Developer + QA (AgentLoopStep) — a ReActAgent developer implements the
//    Stack and saves `solution.dart` to the shared workspace; a QA reviewer
//    iterates until it approves or maxIterations is reached.
// 3. Documentation writer (AgentStep.dynamic) — reads `solution.dart` from the
//    shared workspace via a dynamic prompt and produces API documentation.
//
// Key concepts shown:
//
// - Building a multi-step Orchestrator pipeline
// - Mixing AgentStep and AgentLoopStep in a single pipeline
// - Using AgentStep.dynamic to build prompts from workspace state
// - Sharing FileContext across all steps (researcher → developer → writer)
// - Using ReActAgent with file-context tools inside an AgentLoopStep
// - Inspecting OrchestratorResult with type-checked StepResult subtypes
// - Using OrchestratorErrorPolicy.continueOnError for resilient pipelines
//
// ## Prerequisites
//
// - LM Studio running on localhost:1234 (the default)
// - A model loaded in LM Studio (e.g. llama-3-8b)
//
// ## Run
//
//   dart run example/orchestrator_with_agent_loop.dart
import 'dart:io';

import 'package:agents_core/agents_core.dart';

Future<void> main() async {
  final config = AgentsCoreConfig(
    logger: const StderrLogger(level: LogLevel.info),
  );

  // Shared workspace — all pipeline steps read/write files here.
  final workspacePath =
      '${Directory.systemTemp.path}/agents_core_example_orchestrator_loop';
  final context = FileContext(workspacePath: workspacePath);

  print('Shared workspace: ${context.workspacePath}\n');

  final client = LmStudioClient(config);

  try {
    // ── Step 1: Researcher (SimpleAgent, static prompt) ──────────────────
    final researcher = SimpleAgent(
      name: 'researcher',
      client: client,
      config: config,
      model: 'llama-3-8b',
      systemPrompt: 'You are a software architect. '
          'Produce concise, structured specifications for Dart data '
          'structures. Include: class name, generic type parameter, '
          'public API methods with signatures, edge-case notes, and '
          'complexity targets. Output only the specification — no code.',
    );

    // ── Step 2: Developer + QA (AgentLoopStep) ───────────────────────────
    // The developer is a ReActAgent with file-context tools so it can write
    // solution.dart to the shared workspace during the produce-review loop.
    final developer = ReActAgent(
      name: 'developer',
      client: client,
      config: config,
      model: 'llama-3-8b',
      systemPrompt: 'You are a senior Dart developer. '
          'Implement clean, idiomatic Dart code with doc comments. '
          'Always save your implementation to "solution.dart" in the '
          'workspace using the write_file tool. '
          'When given review feedback, revise your code to address every '
          'issue raised by the reviewer.',
      tools: [writeFileTool, readFileTool, listFilesTool],
      toolHandlers: createHandlers(context),
      maxIterations: 5,
    );

    final qa = SimpleAgent(
      name: 'qa-reviewer',
      client: client,
      config: config,
      model: 'llama-3-8b',
      systemPrompt: 'You are a strict Dart code reviewer. '
          'Evaluate the code for correctness, edge-case handling, '
          'documentation, and idiomatic style. '
          'If the code meets all criteria, begin your response with '
          '"APPROVED". Otherwise, list the issues that must be fixed.',
    );

    // ── Step 3: Documentation writer (SimpleAgent, dynamic prompt) ───────
    final docsWriter = SimpleAgent(
      name: 'docs-writer',
      client: client,
      config: config,
      model: 'llama-3-8b',
      systemPrompt: 'You are a technical writer specialising in Dart API '
          'documentation. Write clear, concise API docs with usage examples. '
          'Use Dart doc-comment style (///).',
    );

    // ── Build the Orchestrator pipeline ──────────────────────────────────
    final orchestrator = Orchestrator(
      context: context,
      onError: OrchestratorErrorPolicy.continueOnError,
      steps: [
        // Step 1: Researcher generates a specification (static prompt).
        AgentStep(
          agent: researcher,
          taskPrompt: 'Create a specification for a generic Stack<T> data '
              'structure in Dart. It should support: push, pop, peek, '
              'isEmpty, size, clear, and toList. '
              'Include edge-case notes for pop/peek on empty stack.',
        ),

        // Step 2: Developer implements the Stack, QA reviews in a loop.
        // Uses a static prompt — the developer's system prompt instructs
        // it to save code to solution.dart via file-context tools.
        AgentLoopStep(
          producer: developer,
          reviewer: qa,
          isAccepted: (AgentResult reviewerResult, int iteration) {
            return reviewerResult.output
                .trim()
                .toUpperCase()
                .startsWith('APPROVED');
          },
          taskPrompt: 'Implement a generic Stack<T> class in Dart with the '
              'following methods: push(T), T pop(), T peek(), bool isEmpty, '
              'int size, void clear(), List<T> toList(). '
              'Throw StateError on pop/peek when empty. '
              'Include doc comments for every public member. '
              'Save the implementation to "solution.dart" using write_file.',
          maxIterations: 3,
        ),

        // Step 3: Docs writer reads solution.dart via a dynamic prompt.
        AgentStep.dynamic(
          agent: docsWriter,
          taskPrompt: (FileContext ctx) async {
            if (!ctx.exists('solution.dart')) {
              return 'Write API documentation for a generic Stack<T> class '
                  'in Dart with methods: push, pop, peek, isEmpty, size, '
                  'clear, toList. Include usage examples.';
            }
            final code = ctx.read('solution.dart');
            return 'Write comprehensive API documentation for the following '
                'Dart code. Include a brief overview, method descriptions, '
                'and a usage example.\n\n'
                '```dart\n$code\n```';
          },
          // Only run if Step 2 didn't fail catastrophically.
          condition: (FileContext ctx) async => true,
        ),
      ],
    );

    // ── Run the pipeline ─────────────────────────────────────────────────
    print('=== Starting Orchestrator Pipeline ===\n');
    print('Steps: ${orchestrator.steps.length}');
    print('Error policy: continueOnError\n');

    final result = await orchestrator.run();

    // ── Inspect step results ─────────────────────────────────────────────
    print('=== Step Results ===\n');

    for (var i = 0; i < result.stepResults.length; i++) {
      final stepResult = result.stepResults[i];

      print('--- Step ${i + 1} ---');

      if (stepResult is AgentStepResult) {
        // Single-agent step (Steps 1 and 3).
        final preview = stepResult.output.length > 300
            ? '${stepResult.output.substring(0, 300)}...'
            : stepResult.output;
        print('Type:   AgentStepResult');
        print('Tokens: ${stepResult.tokensUsed}');
        print('Output:\n$preview\n');
      } else if (stepResult is AgentLoopStepResult) {
        // Produce-review loop step (Step 2).
        print('Type:       AgentLoopStepResult');
        print('Accepted:   ${stepResult.accepted}');
        print('Iterations: ${stepResult.iterationCount}');
        print('Tokens:     ${stepResult.tokensUsed}');

        // Print each iteration's summary.
        final loopResult = stepResult.agentLoopResult;
        for (final iteration in loopResult.iterations) {
          final producerPreview = iteration.producerResult.output.length > 150
              ? '${iteration.producerResult.output.substring(0, 150)}...'
              : iteration.producerResult.output;
          final reviewerPreview = iteration.reviewerResult.output.length > 150
              ? '${iteration.reviewerResult.output.substring(0, 150)}...'
              : iteration.reviewerResult.output;

          print('');
          print('  Iteration ${iteration.index}:');
          print('    Producer (${iteration.producerResult.tokensUsed} tokens): '
              '$producerPreview');
          print('    Reviewer (${iteration.reviewerResult.tokensUsed} tokens): '
              '$reviewerPreview');
        }
        print('');
      }
    }

    // ── Pipeline summary ─────────────────────────────────────────────────
    print('=== Pipeline Summary ===\n');
    print('Duration:      ${result.duration.inMilliseconds} ms');
    print('Steps run:     ${result.stepResults.length}');
    print('Has errors:    ${result.hasErrors}');

    if (result.hasErrors) {
      print('Errors:');
      for (final error in result.errors) {
        print('  - $error');
      }
    }

    // Total tokens across all steps.
    final totalTokens =
        result.stepResults.fold<int>(0, (sum, r) => sum + r.tokensUsed);
    print('Total tokens:  $totalTokens');

    // ── Workspace files ──────────────────────────────────────────────────
    print('\nWorkspace files:');
    final files = context.listFiles();
    if (files.isEmpty) {
      print('  (none)');
    } else {
      for (final file in files) {
        print('  $file');
      }
    }

    // ── Final output from each step ──────────────────────────────────────
    if (context.exists('solution.dart')) {
      print('\n=== solution.dart ===\n');
      print(context.read('solution.dart'));
    }
  } on LmStudioConnectionException catch (e) {
    stderr.writeln('Connection error: ${e.message}');
    stderr.writeln('Make sure LM Studio is running on localhost:1234.');
    exit(1);
  } finally {
    client.dispose();
  }
}
