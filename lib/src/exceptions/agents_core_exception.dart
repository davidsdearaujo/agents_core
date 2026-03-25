/// Base exception class for the `agents_core` library.
///
/// All domain-specific exceptions in this package extend [AgentsCoreException]
/// so callers can catch the entire hierarchy with a single `on AgentsCoreException`.
///
/// Usage:
/// ```dart
/// throw AgentsCoreException('something went wrong');
/// ```
///
/// Subclassing:
/// ```dart
/// class MyException extends AgentsCoreException {
///   MyException(super.message);
/// }
/// ```
class AgentsCoreException implements Exception {
  /// Creates an [AgentsCoreException] with the given [message].
  const AgentsCoreException(this.message);

  /// A human-readable description of the error.
  final String message;

  @override
  String toString() => 'AgentsCoreException: $message';
}
