/// The function details within a [ToolCall].
///
/// Contains the function [name] and its serialized [arguments] string.
/// Fields are nullable to support streaming deltas where only partial
/// data arrives in each chunk.
///
/// ```dart
/// final fn = ToolCallFunction.fromJson({
///   'name': 'get_weather',
///   'arguments': '{"city": "NYC"}',
/// });
/// print(fn.name); // "get_weather"
/// ```
class ToolCallFunction {
  /// Creates a [ToolCallFunction].
  const ToolCallFunction({this.name, this.arguments});

  /// Deserializes a [ToolCallFunction] from a JSON map.
  ///
  /// Both fields are optional to support streaming deltas where only
  /// partial data is present.
  factory ToolCallFunction.fromJson(Map<String, dynamic> json) {
    return ToolCallFunction(
      name: json['name'] as String?,
      arguments: json['arguments'] as String?,
    );
  }

  /// The name of the function to call (e.g. `"get_weather"`).
  final String? name;

  /// The serialized JSON arguments string for the function call.
  ///
  /// This is a raw JSON string that should be decoded by the caller.
  /// In streaming mode, partial argument strings arrive across multiple
  /// chunks and must be concatenated before parsing.
  final String? arguments;

  /// Serializes this function to a JSON-compatible map.
  ///
  /// Keys with `null` values are omitted.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (name != null) json['name'] = name;
    if (arguments != null) json['arguments'] = arguments;
    return json;
  }
}

/// A tool call requested by the model during a chat completion.
///
/// Represents a single function invocation the model wants to execute.
/// In non-streaming responses, all fields are fully populated. In
/// streaming deltas, only partial data may be present — [index] identifies
/// which tool call the delta belongs to so the caller can merge incremental
/// updates.
///
/// ```dart
/// final toolCall = ToolCall.fromJson({
///   'id': 'call_abc123',
///   'type': 'function',
///   'function': {'name': 'get_weather', 'arguments': '{"city": "NYC"}'},
/// });
/// print(toolCall.id);              // "call_abc123"
/// print(toolCall.function?.name);  // "get_weather"
/// ```
class ToolCall {
  /// Creates a [ToolCall].
  const ToolCall({this.id, this.type, this.function, this.index});

  /// Deserializes a [ToolCall] from the OpenAI tool call JSON format.
  ///
  /// All fields are optional to support both full responses and streaming
  /// deltas. The [index] field is only present in streaming chunks.
  factory ToolCall.fromJson(Map<String, dynamic> json) {
    return ToolCall(
      id: json['id'] as String?,
      type: json['type'] as String?,
      function: json['function'] != null
          ? ToolCallFunction.fromJson(json['function'] as Map<String, dynamic>)
          : null,
      index: json['index'] as int?,
    );
  }

  /// The unique identifier for this tool call (e.g. `"call_abc123"`).
  ///
  /// Used to match tool results back to the originating call via
  /// [ChatMessage.toolCallId].
  final String? id;

  /// The type of tool call — always `"function"` in the current API.
  final String? type;

  /// The function name and arguments for this tool call.
  final ToolCallFunction? function;

  /// The zero-based index of this tool call in the array.
  ///
  /// Only present in streaming deltas, where it identifies which tool call
  /// a partial update belongs to so the caller can merge chunks correctly.
  final int? index;

  /// Serializes this tool call to a JSON-compatible map.
  ///
  /// Keys with `null` values are omitted.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (id != null) json['id'] = id;
    if (type != null) json['type'] = type;
    if (function != null) json['function'] = function!.toJson();
    if (index != null) json['index'] = index;
    return json;
  }
}
