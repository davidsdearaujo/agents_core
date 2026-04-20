import 'tool_call.dart';

/// A delta object within a streaming chat completion chunk.
///
/// Contains the incremental [role], [content], and/or [toolCalls] for a
/// single token. All fields may be `null` — for example, the terminal
/// chunk typically has an empty delta.
///
/// ```dart
/// final delta = ChatCompletionDelta.fromJson({'content': ' world'});
/// print(delta.content); // " world"
/// ```
class ChatCompletionDelta {
  /// Creates a [ChatCompletionDelta].
  const ChatCompletionDelta({this.role, this.content, this.toolCalls});

  /// Deserializes a [ChatCompletionDelta] from a JSON map.
  ///
  /// All fields are optional — missing keys yield `null`. The `tool_calls`
  /// list, if present, is deserialized as [ToolCall] objects with streaming
  /// delta semantics (partial data per chunk, identified by [ToolCall.index]).
  factory ChatCompletionDelta.fromJson(Map<String, dynamic> json) {
    final rawToolCalls = json['tool_calls'] as List?;

    return ChatCompletionDelta(
      role: json['role'] as String?,
      content: json['content'] as String?,
      toolCalls: rawToolCalls
          ?.map((t) => ToolCall.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }

  /// The role of the message author, if present in this delta.
  ///
  /// Typically only set in the first chunk of a streaming response.
  final String? role;

  /// The incremental content token, if present in this delta.
  final String? content;

  /// Incremental tool call data, if present in this delta.
  ///
  /// In streaming mode, tool calls arrive across multiple chunks. Each
  /// [ToolCall] in the list has an [ToolCall.index] that identifies which
  /// tool call it belongs to, so the caller can merge partial updates:
  ///
  /// - The first chunk for a tool call includes [ToolCall.id],
  ///   [ToolCall.type], and the function [ToolCallFunction.name].
  /// - Subsequent chunks contain only partial [ToolCallFunction.arguments]
  ///   that must be concatenated.
  final List<ToolCall>? toolCalls;

  /// Serializes this delta to a JSON-compatible map.
  ///
  /// Keys with `null` values are omitted.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (role != null) json['role'] = role;
    if (content != null) json['content'] = content;
    if (toolCalls != null) {
      json['tool_calls'] = toolCalls!.map((t) => t.toJson()).toList();
    }
    return json;
  }
}

/// A single choice within a streaming chat completion chunk.
///
/// Each choice contains a [delta] with incremental content and an optional
/// [finishReason] that is set in the terminal chunk.
class ChatCompletionChunkChoice {
  /// Creates a [ChatCompletionChunkChoice].
  const ChatCompletionChunkChoice({
    required this.delta,
    required this.finishReason,
  });

  /// Deserializes a [ChatCompletionChunkChoice] from a JSON map.
  factory ChatCompletionChunkChoice.fromJson(Map<String, dynamic> json) {
    return ChatCompletionChunkChoice(
      delta: ChatCompletionDelta.fromJson(
        json['delta'] as Map<String, dynamic>,
      ),
      finishReason: json['finish_reason'] as String?,
    );
  }

  /// The incremental delta for this choice.
  final ChatCompletionDelta delta;

  /// The reason generation stopped, if this is the terminal chunk.
  ///
  /// `null` for all chunks except the last. When tool calls are present,
  /// this will be `"tool_calls"` in the final chunk.
  final String? finishReason;

  /// Serializes this choice to a JSON-compatible map.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'delta': delta.toJson(),
    'finish_reason': finishReason,
  };
}

/// A single Server-Sent Event chunk from a streaming chat completion.
///
/// The `POST /v1/chat/completions` endpoint with `stream: true` returns
/// a sequence of these chunks via SSE. Each chunk has a unique [id] and
/// one or more [choices] containing incremental deltas.
///
/// ```dart
/// await for (final chunk in chatStream) {
///   final delta = chunk.choices.first.delta;
///   // Text content
///   final content = delta.content;
///   if (content != null) stdout.write(content);
///   // Tool calls
///   final toolCalls = delta.toolCalls;
///   if (toolCalls != null) {
///     for (final tc in toolCalls) {
///       // Merge partial tool call data by index
///     }
///   }
/// }
/// ```
class ChatCompletionChunk {
  /// Creates a [ChatCompletionChunk].
  const ChatCompletionChunk({required this.id, required this.choices});

  /// Deserializes a [ChatCompletionChunk] from a JSON map.
  factory ChatCompletionChunk.fromJson(Map<String, dynamic> json) {
    final rawChoices = json['choices'] as List;
    return ChatCompletionChunk(
      id: json['id'] as String,
      choices: rawChoices
          .map(
            (c) =>
                ChatCompletionChunkChoice.fromJson(c as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  /// The unique identifier for this completion (same across all chunks).
  final String id;

  /// The list of streaming choices.
  final List<ChatCompletionChunkChoice> choices;

  /// Serializes this chunk to a JSON-compatible map.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'choices': choices.map((c) => c.toJson()).toList(),
  };
}
