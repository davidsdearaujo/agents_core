// SimpleAgent with FileContext example.
//
// Demonstrates using a SimpleAgent to process a task and write its
// output to a sandboxed FileContext workspace. The agent performs a
// single chat completion round and the result is persisted to a file.
//
// ## Prerequisites
//
// - LM Studio running on localhost:1234 (the default)
// - A model loaded in LM Studio (e.g. llama-3-8b)
//
// ## Run
//
//   dart run example/simple_agent.dart
import 'dart:io';

import 'package:agents_core/agents_core.dart';

Future<void> main() async {
  final config = AgentsCoreConfig(
    logger: const StderrLogger(level: LogLevel.info),
  );

  // Create a sandboxed workspace for the agent.
  final workspacePath =
      '${Directory.systemTemp.path}/agents_core_example_simple';
  final context = FileContext(workspacePath: workspacePath);

  print('Workspace: ${context.workspacePath}\n');

  final client = LmStudioClient(config);

  try {
    // ── Create and run the agent ───────────────────────────────────────
    final agent = SimpleAgent(
      name: 'writer',
      client: client,
      config: config,
      model: 'llama-3-8b',
      systemPrompt:
          'You are a technical writer. '
          'Write clear, concise documentation. '
          'Use Markdown formatting.',
    );

    print('Running agent "${agent.name}"...\n');

    final result = await agent.run(
      'Write a brief README.md for a Dart library called "agents_core" '
      'that orchestrates AI agents. Include sections for Installation, '
      'Quick Start, and Features.',
      context: context,
    );

    // ── Display the result ─────────────────────────────────────────────
    print('=== Agent Result ===');
    print('Tokens used:    ${result.tokensUsed}');
    print('Stopped reason: ${result.stoppedReason}');
    print('Tool calls:     ${result.toolCallsMade.length}');
    print('');

    // ── Save output to the workspace ───────────────────────────────────
    context.write('README.md', result.output);
    print('Saved output to workspace: README.md');
    print('');

    // ── Read it back to verify ─────────────────────────────────────────
    final saved = context.read('README.md');
    print('=== Generated README.md ===');
    print(saved);

    // ── List workspace files ───────────────────────────────────────────
    print('\n=== Workspace files ===');
    for (final file in context.listFiles()) {
      print('  $file');
    }
  } on LmStudioConnectionException catch (e) {
    stderr.writeln('Connection error: ${e.message}');
    stderr.writeln('Make sure LM Studio is running on localhost:1234.');
    exit(1);
  } finally {
    client.dispose();
  }
}
