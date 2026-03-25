import 'tool_call.dart';

/// The role of a participant in a chat conversation.
///
/// Maps to the `role` field in the OpenAI-compatible chat API.
///
/// ```dart
/// final role = ChatMessageRole.user;
/// print(role.value); // "user"
/// ```
enum ChatMessageRole {
  /// The system prompt that sets assistant behavior.
  system('system'),

  /// A message from the human user.
  user('user'),

  /// A response from the AI assistant.
  assistant('assistant'),

  /// A result returned by a tool invocation.
  tool('tool');

  const ChatMessageRole(this.value);

  /// The wire-format string value (e.g. `"system"`, `"user"`).
  final String value;

  /// Parses a [ChatMessageRole] from its string [value].
  ///
  /// Throws [ArgumentError] if [value] does not match any known role.
  ///
  /// ```dart
  /// final role = ChatMessageRole.fromString('assistant');
  /// assert(role == ChatMessageRole.assistant);
  /// ```
  static ChatMessageRole fromString(String value) {
    for (final role in values) {
      if (role.value == value) return role;
    }
    throw ArgumentError.value(value, 'value', 'Unknown ChatMessageRole');
  }
}

/// A single message in a chat conversation.
///
/// Each message has a [role] and optional text [content]. Assistant messages
/// may include [toolCalls] when the model requests function invocations.
/// Tool-result messages carry a [toolCallId] that links the result back to
/// the tool invocation that produced it.
///
/// ```dart
/// final msg = ChatMessage(role: ChatMessageRole.user, content: 'Hello!');
/// final json = msg.toJson(); // {"role": "user", "content": "Hello!"}
/// ```
class ChatMessage {
  /// Creates a [ChatMessage].
  ///
  /// [content] is nullable because assistant messages that contain
  /// [toolCalls] may have `null` content.
  ///
  /// [toolCallId] is only relevant for [ChatMessageRole.tool] messages.
  ///
  /// [toolCalls] is only relevant for [ChatMessageRole.assistant] messages
  /// where the model requests one or more function invocations.
  const ChatMessage({
    required this.role,
    this.content,
    this.toolCallId,
    this.toolCalls,
  });

  /// Deserializes a [ChatMessage] from a JSON map.
  ///
  /// Expects `role` and optionally `content`, `tool_call_id`, and
  /// `tool_calls` keys. The `tool_calls` list, if present, is deserialized
  /// as [ToolCall] objects.
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawToolCalls = json['tool_calls'] as List?;

    return ChatMessage(
      role: ChatMessageRole.fromString(json['role'] as String),
      content: json['content'] as String?,
      toolCallId: json['tool_call_id'] as String?,
      toolCalls: rawToolCalls
          ?.map((t) => ToolCall.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }

  /// The role of the message author.
  final ChatMessageRole role;

  /// The text content of the message.
  ///
  /// May be `null` for assistant messages that contain only [toolCalls].
  final String? content;

  /// The ID of the tool call this message is responding to.
  ///
  /// Only present for [ChatMessageRole.tool] messages.
  final String? toolCallId;

  /// The tool calls requested by the assistant in this message.
  ///
  /// Only present for [ChatMessageRole.assistant] messages where the model
  /// invokes one or more functions. Each [ToolCall] contains the function
  /// name, arguments, and a unique ID for matching results.
  final List<ToolCall>? toolCalls;

  /// Serializes this message to a JSON-compatible map.
  ///
  /// The `tool_call_id` and `tool_calls` keys are omitted when their
  /// respective fields are `null`.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'role': role.value,
      'content': content,
    };
    if (toolCallId != null) {
      json['tool_call_id'] = toolCallId;
    }
    if (toolCalls != null) {
      json['tool_calls'] = toolCalls!.map((t) => t.toJson()).toList();
    }
    return json;
  }
}
