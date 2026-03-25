/// Exception thrown when the Docker daemon is not available.
///
/// Indicates that the `docker` CLI could not be found or the Docker daemon
/// is not running. This is an infrastructure failure — the caller should
/// ensure Docker is installed and running before retrying.
///
/// ```dart
/// try {
///   await dockerClient.runContainer(...);
/// } on DockerNotAvailableException catch (e) {
///   print('Docker is not running: ${e.message}');
/// }
/// ```
class DockerNotAvailableException implements Exception {
  /// Creates a [DockerNotAvailableException].
  const DockerNotAvailableException({required this.message, this.cause});

  /// A human-readable description of why Docker is unavailable.
  final String message;

  /// The underlying exception that triggered this error, if any.
  final Object? cause;

  @override
  String toString() => 'DockerNotAvailableException: $message';
}

/// Exception thrown when Docker fails to execute a container operation.
///
/// Represents an infrastructure-level failure — the container could not be
/// created, started, or the Docker CLI returned an unexpected error. This
/// is distinct from a non-zero exit code **inside** the container (which
/// represents application-level errors and is returned as tool output).
///
/// Common causes:
/// - Image pull failure (network issues, non-existent image)
/// - Volume mount errors (invalid path, permission denied)
/// - Resource exhaustion (out of memory, no disk space)
/// - Docker daemon errors
///
/// ```dart
/// try {
///   await dockerClient.runContainer(...);
/// } on DockerExecutionException catch (e) {
///   print('Docker failed: ${e.message}');
///   print('Exit code: ${e.exitCode}');
///   print('Stderr: ${e.stderr}');
/// }
/// ```
class DockerExecutionException implements Exception {
  /// Creates a [DockerExecutionException].
  const DockerExecutionException({
    required this.message,
    required this.exitCode,
    this.stderr = '',
  });

  /// A human-readable description of the Docker failure.
  final String message;

  /// The exit code returned by the `docker` CLI process.
  ///
  /// Non-zero values indicate Docker infrastructure problems (not
  /// application-level errors inside the container).
  final int exitCode;

  /// The stderr output from the `docker` CLI process.
  final String stderr;

  @override
  String toString() =>
      'DockerExecutionException: $message (exitCode=$exitCode)';
}

/// Exception thrown when a Docker image is not found locally or in the
/// registry.
///
/// Indicates that the requested image could not be located. The caller
/// should verify the image name/tag and ensure the image is available
/// (e.g. via `docker pull`).
///
/// ```dart
/// try {
///   await dockerClient.runContainer(image: 'nonexistent:latest', ...);
/// } on DockerImageNotFoundException catch (e) {
///   print('Image not found: ${e.image}');
/// }
/// ```
class DockerImageNotFoundException implements Exception {
  /// Creates a [DockerImageNotFoundException].
  const DockerImageNotFoundException({
    required this.message,
    required this.image,
  });

  /// A human-readable description of the error.
  final String message;

  /// The Docker image name that was not found.
  final String image;

  @override
  String toString() =>
      'DockerImageNotFoundException: $message (image=$image)';
}
