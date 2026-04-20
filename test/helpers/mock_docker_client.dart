import 'dart:collection';

import 'package:agents_core/agents_core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Recorded call types
// ─────────────────────────────────────────────────────────────────────────────

/// A recorded call to [MockDockerClient.runContainer].
///
/// Captures all parameters exactly as passed, so tests can assert on image,
/// command, volumes, working directory, timeout, and environment variables.
class RecordedRunContainerCall {
  const RecordedRunContainerCall({
    required this.image,
    required this.command,
    required this.volumes,
    required this.workingDir,
    required this.timeout,
    required this.environment,
  });

  /// The Docker image used.
  final String image;

  /// The command and arguments executed inside the container.
  final List<String> command;

  /// Volume mounts: host path → container path.
  final Map<String, String> volumes;

  /// Working directory inside the container, or `null` if not specified.
  final String? workingDir;

  /// Timeout for the container run.
  final Duration timeout;

  /// Environment variables set inside the container.
  final Map<String, String> environment;

  @override
  String toString() =>
      'RecordedRunContainerCall(image: $image, command: $command, '
      'volumes: $volumes, workingDir: $workingDir, timeout: $timeout, '
      'environment: $environment)';
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal response slot (result or exception)
// ─────────────────────────────────────────────────────────────────────────────

class _RunResponse {
  _RunResponse.result(this._result) : _exception = null;
  _RunResponse.exception(this._exception) : _result = null;

  final DockerRunResult? _result;
  final Exception? _exception;

  bool get isException => _exception != null;

  DockerRunResult get result => _result!;
  Exception get exception => _exception!;
}

// ─────────────────────────────────────────────────────────────────────────────
// MockDockerClient
// ─────────────────────────────────────────────────────────────────────────────

/// A fake [DockerClient] for unit and integration tests.
///
/// Replaces real Docker subprocess calls with configurable canned responses.
/// No Docker daemon is required when using this mock.
///
/// ## Features
///
/// - **Canned results** — queue [DockerRunResult] values returned by
///   [runContainer] in FIFO order.
/// - **Canned exceptions** — queue exceptions to simulate Docker failures.
/// - **Docker unavailable** — set [isDockerAvailable] to `false` to make
///   [isAvailable] return `false` and [runContainer] throw
///   [DockerNotAvailableException].
/// - **Image availability** — control which images are "locally cached"
///   via [imageAvailability].
/// - **Call recording** — inspect [runContainerCalls], [isImageAvailableCalls],
///   and [pullImageCalls] to verify interactions.
///
/// ## Basic usage
///
/// ```dart
/// final docker = MockDockerClient();
///
/// // Queue a successful result
/// docker.enqueueResult(DockerRunResult(
///   stdout: 'Hello from Python!',
///   stderr: '',
///   exitCode: 0,
/// ));
///
/// final result = await docker.runContainer(
///   image: 'python:3.12-slim',
///   command: ['python', '-c', 'print("Hello from Python!")'],
/// );
/// print(result.stdout); // Hello from Python!
/// print(docker.runContainerCalls.length); // 1
/// ```
///
/// ## Simulating Docker unavailable
///
/// ```dart
/// final docker = MockDockerClient(isDockerAvailable: false);
///
/// expect(await docker.isAvailable(), isFalse);
///
/// // runContainer throws DockerNotAvailableException when unavailable
/// expect(
///   () => docker.runContainer(image: 'python:3.12-slim', command: ['python']),
///   throwsA(isA<DockerNotAvailableException>()),
/// );
/// ```
///
/// ## Simulating execution failures
///
/// ```dart
/// docker.enqueueException(DockerExecutionException(
///   message: 'Failed to create container',
///   exitCode: 125,
///   stderr: 'Error response from daemon: ...',
/// ));
/// ```
class MockDockerClient extends DockerClient {
  /// Creates a [MockDockerClient].
  ///
  /// [isDockerAvailable] controls whether [isAvailable] returns `true`
  /// or `false`. When `false`, [runContainer] also throws
  /// [DockerNotAvailableException] regardless of any queued results.
  /// Defaults to `true`.
  ///
  /// [imageAvailability] maps image names to their local availability.
  /// Images not listed here default to `true` (locally available) unless
  /// [defaultImageAvailable] is set to `false`.
  ///
  /// [defaultImageAvailable] is the fallback for images not found in
  /// [imageAvailability]. Defaults to `true`.
  MockDockerClient({
    this.isDockerAvailable = true,
    Map<String, bool> imageAvailability = const {},
    bool defaultImageAvailable = true,
  }) : _imageAvailability = Map<String, bool>.from(imageAvailability),
       _defaultImageAvailable = defaultImageAvailable,
       // Pass a fake dockerPath so the real constructor won't accidentally
       // resolve to a real docker binary.
       super(dockerPath: 'mock-docker');

  // ── Configuration ────────────────────────────────────────────────────────

  /// Whether the Docker daemon is simulated as available.
  ///
  /// Setting this to `false` makes [isAvailable] return `false` and causes
  /// [runContainer] / [pullImage] to throw [DockerNotAvailableException].
  bool isDockerAvailable;

  /// Per-image local availability map.
  ///
  /// Modify at any time during a test to change what [isImageAvailable]
  /// returns for specific images.
  final Map<String, bool> _imageAvailability;

  final bool _defaultImageAvailable;

  // ── Response queue ────────────────────────────────────────────────────────

  final Queue<_RunResponse> _runQueue = Queue();

  // ── Recorded calls ────────────────────────────────────────────────────────

  /// All calls made to [runContainer], in chronological order.
  final List<RecordedRunContainerCall> runContainerCalls = [];

  /// All image names passed to [isImageAvailable], in order.
  final List<String> isImageAvailableCalls = [];

  /// All image names passed to [pullImage], in order.
  final List<String> pullImageCalls = [];

  // ── Queue helpers ─────────────────────────────────────────────────────────

  /// Queues a successful [DockerRunResult] to be returned by the next
  /// [runContainer] call.
  void enqueueResult(DockerRunResult result) =>
      _runQueue.addLast(_RunResponse.result(result));

  /// Queues an [exception] to be thrown by the next [runContainer] call.
  ///
  /// Typically used with [DockerExecutionException] or
  /// [DockerNotAvailableException].
  void enqueueException(Exception exception) =>
      _runQueue.addLast(_RunResponse.exception(exception));

  /// Convenience: queues a [DockerNotAvailableException] for the next
  /// [runContainer] call.
  void enqueueNotAvailable({String message = 'Docker is not available'}) =>
      enqueueException(DockerNotAvailableException(message: message));

  /// Convenience: queues a successful result with common fields.
  ///
  /// [stdout] defaults to empty string. [exitCode] defaults to 0.
  void enqueueSuccess({
    String stdout = '',
    String stderr = '',
    int exitCode = 0,
  }) => enqueueResult(
    DockerRunResult(stdout: stdout, stderr: stderr, exitCode: exitCode),
  );

  /// How many responses are still waiting in the queue.
  int get pendingResponseCount => _runQueue.length;

  // ── Image availability helpers ────────────────────────────────────────────

  /// Marks [image] as locally available (or unavailable when [available] is
  /// `false`).
  void setImageAvailable(String image, {bool available = true}) =>
      _imageAvailability[image] = available;

  // ── DockerClient overrides ────────────────────────────────────────────────

  @override
  Future<DockerRunResult> runContainer({
    required String image,
    required List<String> command,
    Map<String, String> volumes = const {},
    String? workingDir,
    Duration timeout = const Duration(seconds: 60),
    Map<String, String> environment = const {},
  }) async {
    runContainerCalls.add(
      RecordedRunContainerCall(
        image: image,
        command: List.unmodifiable(command),
        volumes: Map.unmodifiable(volumes),
        workingDir: workingDir,
        timeout: timeout,
        environment: Map.unmodifiable(environment),
      ),
    );

    if (!isDockerAvailable) {
      throw DockerNotAvailableException(
        message: 'MockDockerClient: Docker is simulated as unavailable.',
      );
    }

    if (_runQueue.isEmpty) {
      throw StateError(
        'MockDockerClient: runContainer() was called but the response queue '
        'is empty. Call enqueueResult() or enqueueException() before invoking '
        'runContainer().',
      );
    }

    final response = _runQueue.removeFirst();
    if (response.isException) {
      throw response.exception;
    }
    return response.result;
  }

  @override
  Future<bool> isAvailable() async => isDockerAvailable;

  @override
  Future<bool> isImageAvailable(String image) async {
    isImageAvailableCalls.add(image);
    return _imageAvailability[image] ?? _defaultImageAvailable;
  }

  @override
  Future<void> pullImage(String image) async {
    pullImageCalls.add(image);

    if (!isDockerAvailable) {
      throw DockerNotAvailableException(
        message: 'MockDockerClient: Docker is simulated as unavailable.',
      );
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Clears all recorded calls and the pending response queue.
  ///
  /// Useful between subtests that share a single mock instance.
  void reset() {
    runContainerCalls.clear();
    isImageAvailableCalls.clear();
    pullImageCalls.clear();
    _runQueue.clear();
  }

  /// The most recent [runContainer] call, or `null` if none have been made.
  RecordedRunContainerCall? get lastRunContainerCall =>
      runContainerCalls.isEmpty ? null : runContainerCalls.last;
}
