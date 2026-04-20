import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/logger.dart';
import '../config/logging_config.dart';
import '../exceptions/docker_exceptions.dart';

/// The result of running a command inside a Docker container.
///
/// Captures the [stdout], [stderr], and [exitCode] from the container
/// process. A zero [exitCode] indicates success; non-zero indicates an
/// application-level error inside the container.
///
/// When a timeout occurs, [timedOut] is `true`, [exitCode] is `-1`, and
/// [stderr] contains a diagnostic message.
class DockerRunResult {
  /// Creates a [DockerRunResult].
  const DockerRunResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    this.timedOut = false,
  });

  /// The standard output from the container process.
  final String stdout;

  /// The standard error output from the container process.
  final String stderr;

  /// The exit code from the container process.
  ///
  /// `0` indicates success. Non-zero values indicate application-level
  /// errors (e.g. a Python script raising an exception). `-1` is used
  /// when the process was killed due to a timeout.
  final int exitCode;

  /// Whether the container process was killed because it exceeded its
  /// timeout.
  ///
  /// When `true`, the process was sent `SIGTERM` and the results reflect
  /// whatever output was captured before termination.
  final bool timedOut;
}

/// A client for running commands inside Docker containers.
///
/// Wraps the `docker run` CLI command via [Process.run]. Containers are
/// created with `--rm` (auto-cleanup) and run non-interactively.
///
/// The client validates Docker availability on first use and throws
/// [DockerNotAvailableException] if the daemon is unreachable.
///
/// ```dart
/// final docker = DockerClient();
/// final result = await docker.runContainer(
///   image: 'python:3.12-slim',
///   command: ['python', '/workspace/script.py'],
///   volumes: {'/tmp/workspace': '/workspace'},
/// );
/// print(result.stdout);
/// ```
class DockerClient {
  /// Creates a [DockerClient].
  ///
  /// [dockerPath] is the path to the `docker` CLI executable. Defaults to
  /// `'docker'` which relies on `PATH` resolution.
  ///
  /// [loggingConfig] is the preferred way to supply a logger when using the
  /// specialised config API. [loggingConfig.effectiveLogger] is used, which
  /// respects the [LoggingConfig.loggingEnabled] gate automatically.
  ///
  /// [logger] is a legacy parameter for direct [Logger] injection. When
  /// [loggingConfig] is also provided, [loggingConfig] takes precedence.
  /// When both are omitted, a [SilentLogger] is used.
  DockerClient({
    this.dockerPath = 'docker',
    LoggingConfig? loggingConfig,
    Logger? logger,
  }) : _logger =
           loggingConfig?.effectiveLogger ?? logger ?? const SilentLogger();

  /// Path to the `docker` CLI executable.
  final String dockerPath;

  final Logger _logger;

  /// Runs a command inside a Docker container and returns the result.
  ///
  /// [image] is the Docker image to use (e.g. `'python:3.12-slim'`).
  ///
  /// [command] is the command and arguments to execute inside the container
  /// (e.g. `['python', '/workspace/script.py']`).
  ///
  /// [volumes] maps host paths to container mount paths. Each entry creates
  /// a `-v host:container` argument. Defaults to an empty map.
  ///
  /// [workingDir] sets the working directory inside the container via
  /// `--workdir`. When `null`, the image's default is used.
  ///
  /// [timeout] limits how long the container may run. When exceeded, the
  /// container process is killed and a [DockerExecutionException] is thrown.
  /// Defaults to 60 seconds.
  ///
  /// [environment] sets environment variables inside the container via
  /// `--env`. Defaults to an empty map.
  ///
  /// Returns a [DockerRunResult] with the container's stdout, stderr, and
  /// exit code. A non-zero exit code indicates an application-level error
  /// **inside** the container — it is **not** treated as an infrastructure
  /// failure.
  ///
  /// Throws [DockerNotAvailableException] if the `docker` CLI is not found
  /// or the daemon is not running.
  ///
  /// Throws [DockerExecutionException] if the Docker CLI itself fails
  /// (e.g. image pull error, volume mount error, or the process was killed
  /// due to [timeout]).
  Future<DockerRunResult> runContainer({
    required String image,
    required List<String> command,
    Map<String, String> volumes = const {},
    String? workingDir,
    Duration timeout = const Duration(seconds: 60),
    Map<String, String> environment = const {},
  }) async {
    _logger.debug('Docker: running $image with command: $command');

    final args = <String>['run', '--rm', '--network=none'];

    // Volume mounts.
    for (final entry in volumes.entries) {
      args.addAll(['-v', '${entry.key}:${entry.value}']);
    }

    // Working directory.
    if (workingDir != null) {
      args.addAll(['--workdir', workingDir]);
    }

    // Environment variables.
    for (final entry in environment.entries) {
      args.addAll(['--env', '${entry.key}=${entry.value}']);
    }

    // Image and command.
    args.add(image);
    args.addAll(command);

    _logger.debug('Docker: $dockerPath ${args.join(' ')}');

    Process process;
    try {
      process = await Process.start(dockerPath, args, runInShell: false);
    } on ProcessException catch (e) {
      // docker CLI not found or not executable.
      throw DockerNotAvailableException(
        message:
            'Could not execute "$dockerPath". '
            'Is Docker installed and in PATH?',
        cause: e,
      );
    } on StateError catch (e) {
      throw DockerNotAvailableException(
        message: 'Failed to start Docker process: $e',
        cause: e,
      );
    }

    // Collect stdout and stderr while the process runs.
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .forEach(stdoutBuffer.write);
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .forEach(stderrBuffer.write);

    bool didTimeout = false;
    int exitCode;

    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      // Timeout exceeded — kill the container process to avoid orphans.
      didTimeout = true;
      _logger.debug(
        'Docker: timeout exceeded (${timeout.inSeconds}s), '
        'killing process',
      );
      process.kill(ProcessSignal.sigterm);

      // Give the process a moment to exit after SIGTERM, then force-kill
      // if it hasn't stopped.
      try {
        exitCode = await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        exitCode = await process.exitCode;
      }
    }

    // Wait for stream drains to complete so we capture all output.
    await Future.wait([stdoutDone, stderrDone]);

    final stdout = stdoutBuffer.toString().trimRight();
    final stderr = stderrBuffer.toString().trimRight();

    _logger.debug(
      'Docker: exitCode=$exitCode, '
      'stdout=${stdout.length} chars, '
      'stderr=${stderr.length} chars'
      '${didTimeout ? ' (timed out)' : ''}',
    );

    if (didTimeout) {
      throw DockerExecutionException(
        message:
            'Container exceeded timeout of ${timeout.inSeconds}s '
            'and was killed. Image: $image',
        exitCode: exitCode,
        stderr: stderr,
      );
    }

    // Exit code 125 = Docker daemon error (container failed to run)
    // Exit code 126 = command cannot be invoked (permission)
    // Exit code 127 = command not found in container
    // Exit code 137 = killed (OOM)
    // We treat 125 as a Docker infra failure; all others are
    // application-level and returned to the caller.
    if (exitCode == 125) {
      throw DockerExecutionException(
        message:
            'Docker failed to create or start the container. '
            'Image: $image',
        exitCode: exitCode,
        stderr: stderr,
      );
    }

    return DockerRunResult(stdout: stdout, stderr: stderr, exitCode: exitCode);
  }

  /// Checks whether the Docker daemon is available and responsive.
  ///
  /// Runs `docker info` and returns `true` if it succeeds (exit code 0).
  /// Returns `false` if Docker is not installed, not running, or the
  /// current user does not have permission to use it.
  Future<bool> isAvailable() async {
    try {
      final result = await Process.run(dockerPath, ['info']);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  /// Checks whether a Docker [image] is available locally.
  ///
  /// Runs `docker image inspect` and returns `true` if the image exists
  /// in the local cache. Does **not** pull the image from a registry.
  ///
  /// ```dart
  /// if (!await docker.isImageAvailable('python:3.12-slim')) {
  ///   await docker.pullImage('python:3.12-slim');
  /// }
  /// ```
  Future<bool> isImageAvailable(String image) async {
    _logger.debug('Docker: checking if image "$image" is available locally');
    try {
      final result = await Process.run(dockerPath, ['image', 'inspect', image]);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  /// Pulls a Docker [image] from a registry.
  ///
  /// Runs `docker pull` and waits for completion. Throws
  /// [DockerExecutionException] if the pull fails (e.g. image not found
  /// on registry, network error).
  ///
  /// ```dart
  /// await docker.pullImage('python:3.12-slim');
  /// ```
  Future<void> pullImage(String image) async {
    _logger.info('Docker: pulling image "$image"');
    try {
      final result = await Process.run(dockerPath, ['pull', image]);
      if (result.exitCode != 0) {
        final stderr = (result.stderr as String).trimRight();
        throw DockerExecutionException(
          message: 'Failed to pull image "$image"',
          exitCode: result.exitCode,
          stderr: stderr,
        );
      }
      _logger.info('Docker: image "$image" pulled successfully');
    } on ProcessException catch (e) {
      throw DockerNotAvailableException(
        message:
            'Could not execute "$dockerPath pull $image". '
            'Is Docker installed and in PATH?',
        cause: e,
      );
    }
  }
}
