// Quick ask + askStream usage example.
//
// Demonstrates the simplest way to interact with an LLM via agents_core:
// the `ask` one-shot function and the `askStream` streaming counterpart.
//
// ## Prerequisites
//
// - LM Studio running on localhost:1234 (the default)
// - A model loaded in LM Studio (e.g. llama-3-8b)
//
// ## Run
//
//   dart run example/quick_ask.dart
import 'dart:io';

import 'package:agents_core/agents_core.dart';

Future<void> main() async {
  // ── Configuration ──────────────────────────────────────────────────────
  // Default config connects to localhost:1234.
  // Customise if your LM Studio server is elsewhere.
  final config = AgentsCoreConfig(
    logger: const StderrLogger(level: LogLevel.info),
  );

  // ── One-shot ask ───────────────────────────────────────────────────────
  print('=== One-shot ask() ===\n');

  try {
    final answer = await ask(
      'What is the capital of France? Reply in one sentence.',
      config: config,
      model: 'llama-3-8b',
      systemPrompt: 'You are a helpful geography assistant.',
      temperature: 0.3,
    );
    print('Answer: $answer\n');
  } on LmStudioConnectionException catch (e) {
    stderr.writeln('Connection error: ${e.message}');
    stderr.writeln('Make sure LM Studio is running on localhost:1234.');
    exit(1);
  }

  // ── Streaming askStream ────────────────────────────────────────────────
  print('=== Streaming askStream() ===\n');

  try {
    stdout.write('Streaming: ');
    await for (final delta in askStream(
      'List three interesting facts about the Eiffel Tower.',
      config: config,
      model: 'llama-3-8b',
      systemPrompt: 'You are a concise tour guide.',
    )) {
      stdout.write(delta);
    }
    print('\n');
  } on LmStudioConnectionException catch (e) {
    stderr.writeln('\nConnection error: ${e.message}');
    exit(1);
  }

  print('Done!');
}
