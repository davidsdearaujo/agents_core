/// Configuration for Docker-based sandboxed code execution.
///
/// Encapsulates the Docker image and workspace path used when running
/// code inside isolated containers via [DockerClient].
///
/// ```dart
/// final dockerConfig = DockerConfig(
///   image: 'python:3.11-slim',
///   workspacePath: '/tmp/my_workspace',
/// );
/// ```
///
/// Use [copyWith] to derive a modified configuration without mutating the
/// original:
///
/// ```dart
/// final ciConfig = dockerConfig.copyWith(image: 'python:3.12-slim');
/// ```
class DockerConfig {
  /// Creates a [DockerConfig].
  ///
  /// [image] is the Docker image used for sandboxed code execution.
  /// Defaults to `'python:3.12-slim'`.
  ///
  /// [workspacePath] is the host path mounted as the container workspace.
  /// Defaults to `'/tmp/agents_workspace'`.
  const DockerConfig({
    this.image = 'python:3.12-slim',
    this.workspacePath = '/tmp/agents_workspace',
  });

  /// The Docker image used for sandboxed code execution.
  ///
  /// Defaults to `'python:3.12-slim'`.
  final String image;

  /// The host path mounted into the container as the agent workspace.
  ///
  /// Agent file operations that target the container are mapped to this
  /// directory on the host filesystem.
  /// Defaults to `'/tmp/agents_workspace'`.
  final String workspacePath;

  /// Returns a copy of this configuration with the specified fields replaced.
  ///
  /// Unspecified fields retain their current values.
  DockerConfig copyWith({String? image, String? workspacePath}) {
    return DockerConfig(
      image: image ?? this.image,
      workspacePath: workspacePath ?? this.workspacePath,
    );
  }

  /// Two [DockerConfig] instances are equal when [image] and [workspacePath]
  /// both match.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DockerConfig &&
        other.image == image &&
        other.workspacePath == workspacePath;
  }

  @override
  int get hashCode => Object.hash(image, workspacePath);

  @override
  String toString() =>
      'DockerConfig('
      'image: $image, '
      'workspacePath: $workspacePath'
      ')';
}
