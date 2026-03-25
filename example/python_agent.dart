// PythonToolAgent example.
//
// Demonstrates using PythonToolAgent to run Python code in a sandboxed
// Docker container. The agent uses the ReAct loop to reason about a task,
// write Python code, execute it, and interpret the results.
//
// ## Prerequisites
//
// - LM Studio running on localhost:1234 (the default)
// - A model loaded in LM Studio (e.g. llama-3-8b)
// - Docker installed and running
//   - macOS/Windows: open Docker Desktop
//   - Linux: sudo systemctl start docker
// - The python:3.12-slim image will be pulled automatically on first run
//
// ## Run
//
//   dart run example/python_agent.dart
import 'dart:io';

import 'package:agents_core/agents_core.dart';

Future<void> main() async {
  final config = AgentsCoreConfig(
    logger: const StderrLogger(level: LogLevel.info),
  );

  // Shared workspace — files produced by Python are accessible here.
  final workspacePath =
      '${Directory.systemTemp.path}/agents_core_example_python';
  final fileContext = FileContext(workspacePath: workspacePath);

  print('Workspace: ${fileContext.workspacePath}\n');

  final client = LmStudioClient(config);
  final dockerClient = DockerClient(logger: config.logger);

  try {
    // ── Create the PythonToolAgent ───────────────────────────────────
    final agent = PythonToolAgent(
      name: 'data-analyst',
      client: client,
      config: config,
      dockerClient: dockerClient,
      fileContext: fileContext,
      model: 'llama-3-8b',
      enableFileTools: true,
      maxIterations: 10,
    );

    // ── Run a data analysis task ─────────────────────────────────────
    print('Running PythonToolAgent...\n');

    final result = await agent.run(
      'Using Python, compute the first 20 numbers in the Fibonacci sequence '
      'and calculate their mean. Print each step clearly. '
      'Save the results to a file called "fibonacci.txt" in the workspace.',
    );

    // ── Display results ──────────────────────────────────────────────
    print('\n=== Agent Result ===');
    print('Output:\n${result.output}\n');
    print('Tokens used:     ${result.tokensUsed}');
    print('Tool calls made: ${result.toolCallsMade.length}');
    print('Stopped reason:  ${result.stoppedReason}');

    // ── Show tool calls ──────────────────────────────────────────────
    if (result.toolCallsMade.isNotEmpty) {
      print('\n=== Tool Calls ===');
      for (final call in result.toolCallsMade) {
        final name = call.function?.name ?? 'unknown';
        final argsPreview = call.function?.arguments ?? '';
        final preview = argsPreview.length > 80
            ? '${argsPreview.substring(0, 80)}...'
            : argsPreview;
        print('  $name($preview)');
      }
    }

    // ── Show workspace files ─────────────────────────────────────────
    final files = fileContext.listFiles();
    if (files.isNotEmpty) {
      print('\n=== Workspace Files ===');
      for (final file in files) {
        print('  $file');
      }

      // Print the saved result file if it exists.
      if (fileContext.exists('fibonacci.txt')) {
        print('\n=== fibonacci.txt ===');
        print(fileContext.read('fibonacci.txt'));
      }
    }
  } on DockerNotAvailableException catch (e) {
    stderr.writeln('Docker error: ${e.message}');
    stderr.writeln(
      'Make sure Docker is installed and running. '
      'On macOS/Windows, open Docker Desktop. '
      'On Linux: sudo systemctl start docker',
    );
    exit(1);
  } on DockerExecutionException catch (e) {
    stderr.writeln('Docker execution error: ${e.message}');
    stderr.writeln('Stderr: ${e.stderr}');
    exit(1);
  } on LmStudioConnectionException catch (e) {
    stderr.writeln('LM Studio connection error: ${e.message}');
    stderr.writeln('Make sure LM Studio is running on localhost:1234.');
    exit(1);
  } finally {
    client.dispose();
  }
}
