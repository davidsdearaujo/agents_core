import 'dart:io';

/// Severity levels for log messages, ordered from least to most severe.
///
/// The logger will only emit messages at or above its configured [LogLevel].
enum LogLevel {
  /// Fine-grained diagnostic information.
  debug,

  /// General operational messages.
  info,

  /// Potentially harmful situations that deserve attention.
  warn,

  /// Serious failures that require immediate investigation.
  error,
}

/// A pluggable logging abstraction for agents_core.
///
/// Implement this interface to integrate with your preferred logging
/// framework (e.g., `package:logging`, `package:logger`, or a custom sink).
///
/// The default implementation [StderrLogger] writes timestamped messages
/// to stderr. For suppressed output (e.g., in tests), use [SilentLogger].
abstract class Logger {
  /// Creates a [Logger] instance.
  const Logger();

  /// The minimum severity level this logger will emit.
  LogLevel get level;

  /// Logs a [message] at [LogLevel.debug] severity.
  void debug(String message);

  /// Logs a [message] at [LogLevel.info] severity.
  void info(String message);

  /// Logs a [message] at [LogLevel.warn] severity.
  void warn(String message);

  /// Logs a [message] at [LogLevel.error] severity.
  void error(String message);
}

/// Default [Logger] implementation that writes timestamped messages to stderr.
///
/// Only messages at or above the configured [level] are emitted. Each line
/// is formatted as:
/// ```
/// 2026-03-25T12:30:45.123Z [INFO] Your message here
/// ```
class StderrLogger extends Logger {
  /// Creates a [StderrLogger] with the given minimum [level].
  ///
  /// Defaults to [LogLevel.info] so that debug noise is suppressed
  /// in production.
  const StderrLogger({this.level = LogLevel.info});

  @override
  final LogLevel level;

  @override
  void debug(String message) => _log(LogLevel.debug, message);

  @override
  void info(String message) => _log(LogLevel.info, message);

  @override
  void warn(String message) => _log(LogLevel.warn, message);

  @override
  void error(String message) => _log(LogLevel.error, message);

  void _log(LogLevel messageLevel, String message) {
    if (messageLevel.index < level.index) return;
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final label = messageLevel.name.toUpperCase();
    stderr.writeln('$timestamp [$label] $message');
  }
}

/// A no-op [Logger] that silently discards all messages.
///
/// Useful for tests or any context where log output is unwanted.
class SilentLogger extends Logger {
  /// Creates a [SilentLogger].
  const SilentLogger();

  @override
  LogLevel get level => LogLevel.error;

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}
