import 'chat_message.dart';
import 'completion_usage.dart';

/// A single choice in a chat completion response.
///
/// Each choice contains the assistant's [message] and an optional
/// [finishReason] indicating why generation stopped.
class ChatCompletionChoice {
  /// Creates a [ChatCompletionChoice].
  const ChatCompletionChoice({
    required this.message,
    required this.finishReason,
  });

  /// Deserializes a [ChatCompletionChoice] from a JSON map.
  ///
  /// Reads `message` and `finish_reason`; ignores `index` and other fields.
  factory ChatCompletionChoice.fromJson(Map<String, dynamic> json) {
    return ChatCompletionChoice(
      message:
          ChatMessage.fromJson(json['message'] as Map<String, dynamic>),
      finishReason: json['finish_reason'] as String?,
    );
  }

  /// The assistant's response message.
  final ChatMessage message;

  /// The reason generation stopped (e.g. `"stop"`, `"length"`,
  /// `"tool_calls"`).
  ///
  /// May be `null` if generation is still in progress.
  final String? finishReason;

  /// Serializes this choice to a JSON-compatible map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'message': message.toJson(),
        'finish_reason': finishReason,
      };
}

/// The response from `POST /v1/chat/completions` (non-streaming).
///
/// Contains a unique [id], one or more [choices], and token [usage]
/// statistics.
///
/// ```dart
/// final response = ChatCompletionResponse.fromJson(jsonBody);
/// final text = response.choices.first.message.content;
/// print('Tokens used: ${response.usage.totalTokens}');
/// ```
class ChatCompletionResponse {
  /// Creates a [ChatCompletionResponse].
  const ChatCompletionResponse({
    required this.id,
    required this.choices,
    required this.usage,
  });

  /// Deserializes a [ChatCompletionResponse] from the OpenAI JSON format.
  factory ChatCompletionResponse.fromJson(Map<String, dynamic> json) {
    final rawChoices = json['choices'] as List;
    return ChatCompletionResponse(
      id: json['id'] as String,
      choices: rawChoices
          .map((c) =>
              ChatCompletionChoice.fromJson(c as Map<String, dynamic>))
          .toList(),
      usage:
          CompletionUsage.fromJson(json['usage'] as Map<String, dynamic>),
    );
  }

  /// The unique identifier for this completion.
  final String id;

  /// The list of completion choices.
  final List<ChatCompletionChoice> choices;

  /// Token usage statistics for this completion.
  final CompletionUsage usage;

  /// Serializes this response to a JSON-compatible map.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'choices': choices.map((c) => c.toJson()).toList(),
        'usage': usage.toJson(),
      };
}
