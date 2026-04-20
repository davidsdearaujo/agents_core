import 'dart:math';

import '../agent/react_agent.dart';
import '../config/logger.dart';
import '../context/file_context.dart';
import '../docker/docker_client.dart';
import '../exceptions/docker_exceptions.dart';
import '../models/tool_definition.dart';

/// The [ToolDefinition] for the `execute_python` tool.
///
/// Describes a tool that executes arbitrary Python code inside a sandboxed
/// Docker container. The model provides `code` (the Python source) and
/// optionally `requirements` (a list of pip packages to install before
/// execution).
///
/// ```dart
/// final agent = ReActAgent(
///   tools: [executePythonToolDefinition],
///   toolHandlers: {
///     'execute_python': createExecutePythonHandler(
///       context: fileContext,
///       dockerClient: dockerClient,
///     ),
///   },
///   ...
/// );
/// ```
final ToolDefinition executePythonToolDefinition = ToolDefinition(
  name: 'execute_python',
  description:
      'Executes Python code in a sandboxed Docker container. '
      'Returns stdout, stderr, and exit code. '
      'Use this to run data analysis, computations, or scripts.',
  parameters: <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'code': <String, dynamic>{
        'type': 'string',
        'description': 'The Python source code to execute.',
      },
      'requirements': <String, dynamic>{
        'type': 'array',
        'items': <String, dynamic>{'type': 'string'},
        'description':
            'Optional list of pip packages to install before execution '
            '(e.g. ["numpy", "pandas==2.1.0"]).',
      },
    },
    'required': <String>['code'],
  },
);

/// Creates a [ToolHandler] that executes Python code in a Docker container.
///
/// The returned handler:
///
/// 1. Writes the provided code to a temporary `.py` file in the workspace.
/// 2. If `requirements` are specified, prepends a `pip install` step.
/// 3. Runs the code via [DockerClient.runContainer] using the
///    `python:3.12-slim` image.
/// 4. Returns a formatted string with stdout, stderr, and exit code.
/// 5. Cleans up the temporary file.
///
/// **Error handling:**
/// - Python errors (non-zero exit code inside the container) are returned as
///   tool output strings so the LLM can self-correct.
/// - Docker infrastructure failures ([DockerNotAvailableException],
///   [DockerExecutionException]) are **re-thrown** as exceptions so the
///   agent loop can surface them appropriately.
///
/// [context] is the sandboxed workspace where temporary files are created.
///
/// [dockerClient] is used to run the container.
///
/// [logger] is used for diagnostic output. When `null`, logging is
/// suppressed.
///
/// [image] overrides the Docker image. Defaults to `'python:3.12-slim'`.
///
/// [timeout] limits how long the container may run. Defaults to 120 seconds.
///
/// ```dart
/// final handler = createExecutePythonHandler(
///   context: FileContext(workspacePath: '/tmp/agent-workspace'),
///   dockerClient: DockerClient(),
///   logger: const StderrLogger(),
/// );
///
/// final output = await handler({
///   'code': 'print("Hello, world!")',
///   'requirements': ['requests'],
/// });
/// print(output);
/// ```
ToolHandler createExecutePythonHandler({
  required FileContext context,
  required DockerClient dockerClient,
  Logger? logger,
  String image = 'python:3.12-slim',
  Duration timeout = const Duration(seconds: 120),
}) {
  final log = logger ?? const SilentLogger();

  return (Map<String, dynamic> arguments) async {
    final code = arguments['code'] as String? ?? '';
    final requirements = _parseRequirements(arguments['requirements']);

    if (code.trim().isEmpty) {
      return 'Error: "code" parameter is required and must not be empty.';
    }

    // Generate a unique temp filename to avoid collisions.
    final tempFileName = _generateTempFileName();

    log.debug(
      'execute_python: writing temp file $tempFileName '
      '(${code.length} chars, ${requirements.length} requirements)',
    );

    try {
      // Step 1: Write code to a temp file in the workspace.
      context.write(tempFileName, code);

      // Step 2: Build the container command.
      // If requirements are specified, chain pip install && python script.
      final containerCommand = _buildCommand(
        tempFileName: tempFileName,
        requirements: requirements,
      );

      // Step 3: Run the container.
      log.debug('execute_python: running container ($image)');

      final result = await dockerClient.runContainer(
        image: image,
        command: containerCommand,
        volumes: {context.workspacePath: '/workspace'},
        workingDir: '/workspace',
        timeout: timeout,
      );

      log.debug('execute_python: exitCode=${result.exitCode}');

      // Step 4: Format and return the result.
      // Non-zero exit codes are Python-level errors — return as tool output.
      return _formatResult(
        stdout: result.stdout,
        stderr: result.stderr,
        exitCode: result.exitCode,
      );
    } on DockerNotAvailableException {
      // Infrastructure failure — re-throw so the agent loop surfaces it.
      rethrow;
    } on DockerExecutionException {
      // Infrastructure failure — re-throw so the agent loop surfaces it.
      rethrow;
    } finally {
      // Step 5: Clean up the temp file.
      _cleanupTempFile(context, tempFileName, log);
    }
  };
}

/// Parses the `requirements` argument into a list of package strings.
///
/// Handles both `List<String>` and `List<dynamic>` (from JSON decoding).
/// Returns an empty list if the argument is `null` or not a list.
List<String> _parseRequirements(Object? raw) {
  if (raw == null) return const [];
  if (raw is List) {
    return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }
  return const [];
}

/// Builds the shell command to run inside the container.
///
/// When [requirements] are provided, prepends `pip install --quiet` before
/// executing the Python script. Uses `sh -c` to chain commands.
List<String> _buildCommand({
  required String tempFileName,
  required List<String> requirements,
}) {
  if (requirements.isEmpty) {
    return ['python', '/workspace/$tempFileName'];
  }

  // Chain: pip install --quiet <packages> && python <script>
  final pipInstall =
      'pip install --quiet --disable-pip-version-check ${requirements.join(' ')}';
  final pythonRun = 'python /workspace/$tempFileName';

  return ['sh', '-c', '$pipInstall && $pythonRun'];
}

/// Generates a unique temporary filename for the Python script.
String _generateTempFileName() {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final random = Random().nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
  return '.tmp_exec_${timestamp}_$random.py';
}

/// Formats the container output into a structured string for the LLM.
String _formatResult({
  required String stdout,
  required String stderr,
  required int exitCode,
}) {
  final buffer = StringBuffer();

  if (exitCode == 0) {
    buffer.writeln('[OK] exit_code=0');
  } else {
    buffer.writeln('[ERROR] exit_code=$exitCode');
  }

  if (stdout.isNotEmpty) {
    buffer.writeln('--- stdout ---');
    buffer.writeln(stdout);
  }

  if (stderr.isNotEmpty) {
    buffer.writeln('--- stderr ---');
    buffer.writeln(stderr);
  }

  if (stdout.isEmpty && stderr.isEmpty) {
    buffer.writeln('(no output)');
  }

  return buffer.toString().trimRight();
}

/// Safely deletes the temporary Python script from the workspace.
void _cleanupTempFile(FileContext context, String fileName, Logger log) {
  try {
    if (context.exists(fileName)) {
      context.delete(fileName);
      log.debug('execute_python: cleaned up $fileName');
    }
  } on Exception catch (e) {
    // Cleanup failure is non-fatal — log and continue.
    log.warn('execute_python: failed to clean up $fileName: $e');
  }
}
