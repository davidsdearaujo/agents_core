// AgentLoop produce-review loop example.
//
// Demonstrates using AgentLoop to orchestrate a producer–reviewer feedback
// loop. A "developer" agent writes a Dart function and a "QA" agent reviews
// it. The loop iterates until the reviewer approves or maxIterations is
// reached.
//
// Key concepts shown:
//
// - Instantiating AgentLoop with producer and reviewer agents
// - Defining an acceptance predicate via isAccepted
// - Inspecting AgentLoopIteration records (index, producerResult, reviewerResult)
// - Reading AgentLoopResult summary (accepted, iterationCount, totalTokensUsed)
// - Using maxIterations as a safety limit
//
// ## Prerequisites
//
// - LM Studio running on localhost:1234 (the default)
// - A model loaded in LM Studio (e.g. llama-3-8b)
//
// ## Run
//
//   dart run example/agent_loop.dart
import 'dart:io';

import 'package:agents_core/agents_core.dart';

Future<void> main() async {
  final config = AgentsCoreConfig(
    logger: const StderrLogger(level: LogLevel.info),
  );

  // Shared workspace — both agents can read/write files here.
  final workspacePath = '${Directory.systemTemp.path}/agents_core_example_loop';
  final context = FileContext(workspacePath: workspacePath);

  print('Shared workspace: ${context.workspacePath}\n');

  final client = LmStudioClient(config);

  try {
    // ── Producer: developer agent ──────────────────────────────────────
    final developer = SimpleAgent(
      name: 'developer',
      client: client,
      config: config,
      model: 'llama-3-8b',
      systemPrompt:
          'You are a senior Dart developer. '
          'Write clean, idiomatic Dart code with doc comments. '
          'When given review feedback, revise your code to address every '
          'issue raised by the reviewer.',
    );

    // ── Reviewer: QA agent ─────────────────────────────────────────────
    final qa = SimpleAgent(
      name: 'qa-reviewer',
      client: client,
      config: config,
      model: 'llama-3-8b',
      systemPrompt:
          'You are a strict code reviewer for Dart projects. '
          'Evaluate the code for correctness, edge-case handling, '
          'documentation, and idiomatic style. '
          'If the code meets all criteria, begin your response with '
          '"APPROVED". Otherwise, list the issues that must be fixed.',
    );

    // ── AgentLoop: iterate until QA approves ───────────────────────────
    final loop = AgentLoop(
      context: context,
      producer: developer,
      reviewer: qa,
      // Accept when the reviewer's output starts with "APPROVED".
      isAccepted: (AgentResult reviewerResult, int iteration) {
        return reviewerResult.output.trim().toUpperCase().startsWith(
          'APPROVED',
        );
      },
      // Allow up to 4 produce-review rounds before giving up.
      maxIterations: 4,
    );

    print('=== Starting AgentLoop ===\n');
    print('Task: Implement a Dart function to compute Fibonacci numbers.');
    print('Max iterations: ${loop.maxIterations}\n');

    final result = await loop.run(
      'Write a Dart function `int fibonacci(int n)` that returns the n-th '
      'Fibonacci number. Handle negative inputs by throwing '
      'an ArgumentError. Include a doc comment.',
    );

    // ── Inspect each iteration ─────────────────────────────────────────
    print('=== Iteration Details ===\n');

    for (final iteration in result.iterations) {
      print('--- Iteration ${iteration.index} ---');

      // Producer output (truncated for readability).
      final producerOutput = iteration.producerResult.output;
      final producerPreview = producerOutput.length > 200
          ? '${producerOutput.substring(0, 200)}...'
          : producerOutput;
      print('Producer (${iteration.producerResult.tokensUsed} tokens):');
      print(producerPreview);
      print('');

      // Reviewer verdict.
      final reviewerOutput = iteration.reviewerResult.output;
      final reviewerPreview = reviewerOutput.length > 200
          ? '${reviewerOutput.substring(0, 200)}...'
          : reviewerOutput;
      print('Reviewer (${iteration.reviewerResult.tokensUsed} tokens):');
      print(reviewerPreview);
      print('');
    }

    // ── Loop summary ───────────────────────────────────────────────────
    print('=== Loop Summary ===\n');
    print('Accepted:           ${result.accepted}');
    print('Iterations:         ${result.iterationCount}');
    print('Total tokens used:  ${result.totalTokensUsed}');
    print('Duration:           ${result.duration.inMilliseconds} ms');
    print('Reached max iter:   ${result.reachedMaxIterations}');
    print('');

    // ── Final output ───────────────────────────────────────────────────
    print('=== Final Producer Output ===\n');
    print(result.lastProducerResult.output);

    // Save final code to workspace for further use.
    context.write('fibonacci.dart', result.lastProducerResult.output);
    print('\nSaved to workspace: fibonacci.dart');
  } on LmStudioConnectionException catch (e) {
    stderr.writeln('Connection error: ${e.message}');
    stderr.writeln('Make sure LM Studio is running on localhost:1234.');
    exit(1);
  } finally {
    client.dispose();
  }
}
