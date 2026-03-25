import '../models/tool_call.dart';

/// The outcome of an [Agent.run] invocation.
///
/// Captures everything produced during a single agent execution round:
/// the textual [output], any [toolCallsMade], token consumption, file
/// mutations, and the reason the model stopped generating.
///
/// ```dart
/// final result = await agent.run('Summarise the README');
/// print(result.output);
/// print('Tokens: ${result.tokensUsed}');
/// ```
class AgentResult {
  /// Creates an [AgentResult].
  ///
  /// [output] is the assistant's final text content (may be empty).
  ///
  /// [toolCallsMade] lists every tool invocation the model requested during
  /// the run. Defaults to an empty list for simple completions.
  ///
  /// [tokensUsed] is the total token count (prompt + completion) reported
  /// by the server. `0` when the information is unavailable.
  ///
  /// [filesModified] lists workspace-relative paths of files written or
  /// changed during the run. Defaults to an empty list.
  ///
  /// [stoppedReason] is the finish reason reported by the model (e.g.
  /// `"stop"`, `"length"`, `"tool_calls"`). May be `null` if the server
  /// did not provide one.
  const AgentResult({
    required this.output,
    this.toolCallsMade = const [],
    this.tokensUsed = 0,
    this.filesModified = const [],
    this.stoppedReason,
  });

  /// The assistant's final text response.
  ///
  /// For a single-round agent this is the content of the first choice's
  /// message. May be empty if the model returned no text content (e.g.
  /// when only tool calls were produced).
  final String output;

  /// Tool calls the model requested during this run.
  ///
  /// Empty for pure text completions. In a multi-round agent loop each
  /// invocation's tool calls would be accumulated here.
  final List<ToolCall> toolCallsMade;

  /// Total tokens consumed (prompt + completion).
  ///
  /// `0` when token usage data is unavailable (e.g. streaming-only runs).
  final int tokensUsed;

  /// Workspace-relative paths of files written or modified during the run.
  ///
  /// Populated when the agent has a [FileContext] and performs file
  /// operations. Empty by default.
  final List<String> filesModified;

  /// The finish reason reported by the model for the final generation.
  ///
  /// Common values: `"stop"` (natural end), `"length"` (token limit hit),
  /// `"tool_calls"` (model requested tool invocations).
  ///
  /// May be `null` if the server did not report a reason.
  final String? stoppedReason;

  @override
  String toString() =>
      'AgentResult(output: ${output.length > 80 ? '${output.substring(0, 80)}...' : output}, '
      'toolCalls: ${toolCallsMade.length}, '
      'tokens: $tokensUsed, '
      'files: ${filesModified.length}, '
      'stopped: $stoppedReason)';
}
