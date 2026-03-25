// Multi-agent orchestration example.
//
// Demonstrates two agents collaborating via a shared FileContext:
//
// 1. Researcher — generates a research outline and saves it to the workspace.
// 2. Writer — reads the researcher's output and expands it into a full article.
//
// Both agents share the same FileContext so the writer can read files
// produced by the researcher. This is a simple sequential pipeline — for
// conditional branching and parallel execution, a higher-level
// orchestrator can be built on top of this pattern.
//
// ## Prerequisites
//
// - LM Studio running on localhost:1234 (the default)
// - A model loaded in LM Studio (e.g. llama-3-8b)
//
// ## Run
//
//   dart run example/multi_agent.dart
import 'dart:io';

import 'package:agents_core/agents_core.dart';

Future<void> main() async {
  final config = AgentsCoreConfig(
    logger: const StderrLogger(level: LogLevel.info),
  );

  // Shared workspace for both agents.
  final workspacePath =
      '${Directory.systemTemp.path}/agents_core_example_multi';
  final context = FileContext(workspacePath: workspacePath);

  print('Shared workspace: ${context.workspacePath}\n');

  final client = LmStudioClient(config);

  try {
    // ── Agent 1: Researcher ──────────────────────────────────────────
    final researcher = SimpleAgent(
      name: 'researcher',
      client: client,
      config: config,
      model: 'llama-3-8b',
      systemPrompt: 'You are a research analyst. '
          'Produce structured outlines with key points. '
          'Use bullet points and section headers.',
    );

    print('--- Step 1: Running researcher agent ---\n');

    final researchResult = await researcher.run(
      'Create a research outline about the impact of AI agents on '
      'software development. Include 3-4 sections with 2-3 key points each.',
      context: context,
    );

    // Save research output to the shared workspace.
    context.write('research_outline.md', researchResult.output);
    print('Researcher output saved (${researchResult.tokensUsed} tokens)');
    print('File: research_outline.md\n');

    // ── Agent 2: Writer ──────────────────────────────────────────────
    final writer = SimpleAgent(
      name: 'writer',
      client: client,
      config: config,
      model: 'llama-3-8b',
      systemPrompt: 'You are a technical writer. '
          'Expand outlines into well-written articles. '
          'Use clear language and concrete examples.',
    );

    print('--- Step 2: Running writer agent ---\n');

    // Read the researcher's output from the shared workspace.
    final outline = context.read('research_outline.md');

    final writerResult = await writer.run(
      'Expand this research outline into a short article '
      '(3-4 paragraphs):\n\n$outline',
      context: context,
    );

    // Save the final article.
    context.write('article.md', writerResult.output);
    print('Writer output saved (${writerResult.tokensUsed} tokens)');
    print('File: article.md\n');

    // ── Summary ──────────────────────────────────────────────────────
    final totalTokens = researchResult.tokensUsed + writerResult.tokensUsed;

    print('=== Pipeline Summary ===');
    print('Total tokens used: $totalTokens');
    print('Workspace files:');
    for (final file in context.listFiles()) {
      print('  $file');
    }

    print('\n=== Final Article ===\n');
    print(context.read('article.md'));
  } on LmStudioConnectionException catch (e) {
    stderr.writeln('Connection error: ${e.message}');
    stderr.writeln('Make sure LM Studio is running on localhost:1234.');
    exit(1);
  } finally {
    client.dispose();
  }
}
