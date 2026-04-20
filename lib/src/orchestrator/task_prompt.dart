import '../context/file_context.dart';

/// Sealed discriminated union for the task prompt carried by an
/// [OrchestratorStep].
///
/// Use [StaticPrompt] for compile-time-known strings and [DynamicPrompt] for
/// prompts that must be computed at runtime from the orchestrator's
/// [FileContext].
///
/// Because [TaskPrompt] is sealed, every exhaustive `switch` on it is
/// verified by the Dart compiler — no `default` branch is required and no
/// runtime cast is ever needed.
///
/// ```dart
/// final resolved = switch (step.taskPrompt) {
///   StaticPrompt(:final value) => value,
///   DynamicPrompt(:final resolver) => await resolver(context),
/// };
/// ```
sealed class TaskPrompt {
  /// Const constructor for subclasses.
  const TaskPrompt();
}

/// A static, compile-time-known task prompt.
///
/// ```dart
/// const prompt = StaticPrompt('Summarise the report');
/// print(prompt.value); // 'Summarise the report'
/// ```
final class StaticPrompt extends TaskPrompt {
  /// Creates a [StaticPrompt] wrapping [value].
  const StaticPrompt(this.value);

  /// The literal prompt string.
  final String value;
}

/// A dynamic task prompt resolved at runtime from the orchestrator's
/// [FileContext].
///
/// ```dart
/// final prompt = DynamicPrompt(
///   (ctx) async => 'Fix: ${ctx.read("errors.log")}',
/// );
/// ```
final class DynamicPrompt extends TaskPrompt {
  /// Creates a [DynamicPrompt] with the given [resolver].
  const DynamicPrompt(this.resolver);

  /// The function that produces the prompt string given a [FileContext].
  final Future<String> Function(FileContext) resolver;
}
