/// Token usage statistics returned by the LM Studio API.
///
/// Reports how many tokens were consumed by the prompt, the completion,
/// and in total. Useful for monitoring cost and context-window headroom.
///
/// ```dart
/// final usage = CompletionUsage.fromJson({
///   'prompt_tokens': 20,
///   'completion_tokens': 10,
///   'total_tokens': 30,
/// });
/// print(usage.totalTokens); // 30
/// ```
class CompletionUsage {
  /// Creates a [CompletionUsage].
  const CompletionUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });

  /// Deserializes a [CompletionUsage] from a JSON map with snake_case keys.
  factory CompletionUsage.fromJson(Map<String, dynamic> json) {
    return CompletionUsage(
      promptTokens: json['prompt_tokens'] as int,
      completionTokens: json['completion_tokens'] as int,
      totalTokens: json['total_tokens'] as int,
    );
  }

  /// The number of tokens in the input prompt.
  final int promptTokens;

  /// The number of tokens generated in the completion.
  final int completionTokens;

  /// The total number of tokens used (prompt + completion).
  final int totalTokens;

  /// Serializes this usage to a JSON-compatible map with snake_case keys.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'prompt_tokens': promptTokens,
    'completion_tokens': completionTokens,
    'total_tokens': totalTokens,
  };
}
