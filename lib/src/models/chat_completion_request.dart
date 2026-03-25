import 'chat_message.dart';
import 'tool_definition.dart';

/// A request to the `POST /v1/chat/completions` endpoint.
///
/// Wraps all parameters accepted by the OpenAI-compatible chat API.
/// Optional fields are omitted from the JSON payload when `null`.
///
/// ```dart
/// final req = ChatCompletionRequest(
///   model: 'llama-3-8b',
///   messages: [
///     ChatMessage(role: ChatMessageRole.user, content: 'Hello!'),
///   ],
///   temperature: 0.7,
///   maxTokens: 512,
/// );
/// ```
class ChatCompletionRequest {
  /// Creates a [ChatCompletionRequest].
  const ChatCompletionRequest({
    required this.model,
    required this.messages,
    this.temperature,
    this.maxTokens,
    this.tools,
    this.toolChoice,
    this.stream,
  });

  /// Deserializes a [ChatCompletionRequest] from a JSON map.
  ///
  /// Reads `max_tokens` (snake_case) and maps it to [maxTokens].
  /// The `tools` list, if present, is deserialized as [ToolDefinition] objects.
  factory ChatCompletionRequest.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] as List;
    final rawTools = json['tools'] as List?;

    return ChatCompletionRequest(
      model: json['model'] as String,
      messages: rawMessages
          .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
          .toList(),
      temperature: (json['temperature'] as num?)?.toDouble(),
      maxTokens: json['max_tokens'] as int?,
      tools: rawTools
          ?.map((t) => ToolDefinition.fromJson(t as Map<String, dynamic>))
          .toList(),
      toolChoice: json['tool_choice'],
      stream: json['stream'] as bool?,
    );
  }

  /// The model ID to use for the completion.
  final String model;

  /// The conversation messages.
  final List<ChatMessage> messages;

  /// Sampling temperature between 0.0 and 2.0.
  final double? temperature;

  /// The maximum number of tokens to generate.
  final int? maxTokens;

  /// Tool (function) definitions the model may call.
  final List<ToolDefinition>? tools;

  /// Controls which tool the model should call.
  ///
  /// Can be a [String] (`"auto"`, `"none"`) or a [Map] specifying a
  /// particular function.
  final Object? toolChoice;

  /// Whether to stream the response via SSE.
  final bool? stream;

  /// Serializes this request to a JSON-compatible map.
  ///
  /// Optional fields are omitted when `null`. Keys use snake_case to
  /// match the OpenAI wire format.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'model': model,
      'messages': messages.map((m) => m.toJson()).toList(),
    };
    if (temperature != null) json['temperature'] = temperature;
    if (maxTokens != null) json['max_tokens'] = maxTokens;
    if (tools != null) {
      json['tools'] = tools!.map((t) => t.toJson()).toList();
    }
    if (toolChoice != null) json['tool_choice'] = toolChoice;
    if (stream != null) json['stream'] = stream;
    return json;
  }
}
