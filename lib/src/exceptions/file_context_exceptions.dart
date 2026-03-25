/// Exception thrown when a file is not found in the workspace.
///
/// Carries the resolved [path] that was looked up so callers can provide
/// actionable diagnostics.
///
/// ```dart
/// if (!file.existsSync()) {
///   throw FileNotFoundException(path: file.path);
/// }
/// ```
class FileNotFoundException implements Exception {
  /// Creates a [FileNotFoundException] for the given [path].
  const FileNotFoundException({required this.path});

  /// The absolute path that was not found.
  final String path;

  @override
  String toString() => 'FileNotFoundException: $path';
}

/// Exception thrown when a file path attempts to escape the workspace root.
///
/// Any path containing `..` segments that would resolve outside the
/// configured workspace directory is rejected with this exception.
///
/// ```dart
/// throw PathTraversalException(path: '../etc/passwd');
/// ```
class PathTraversalException implements Exception {
  /// Creates a [PathTraversalException] for the offending [path].
  const PathTraversalException({required this.path});

  /// The untrusted path that attempted a traversal escape.
  final String path;

  @override
  String toString() =>
      'PathTraversalException: path "$path" escapes the workspace root';
}
