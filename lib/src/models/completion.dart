import 'completion_usage.dart';

/// A request to the `POST /v1/completions` (text completion) endpoint.
///
/// This is the legacy/text completion API — for chat, use
/// [ChatCompletionRequest] instead.
///
/// ```dart
/// final req = CompletionRequest(
///   model: 'llama-3-8b',
///   prompt: 'Once upon a time',
///   maxTokens: 128,
/// );
/// ```
class CompletionRequest {
  /// Creates a [CompletionRequest].
  const CompletionRequest({
    required this.model,
    required this.prompt,
    this.maxTokens,
    this.temperature,
    this.stream,
  });

  /// Deserializes a [CompletionRequest] from a JSON map.
  ///
  /// Reads `max_tokens` (snake_case) and maps it to [maxTokens].
  factory CompletionRequest.fromJson(Map<String, dynamic> json) {
    return CompletionRequest(
      model: json['model'] as String,
      prompt: json['prompt'] as String,
      maxTokens: json['max_tokens'] as int?,
      temperature: (json['temperature'] as num?)?.toDouble(),
      stream: json['stream'] as bool?,
    );
  }

  /// The model ID to use for the completion.
  final String model;

  /// The text prompt to complete.
  final String prompt;

  /// The maximum number of tokens to generate.
  final int? maxTokens;

  /// Sampling temperature between 0.0 and 2.0.
  final double? temperature;

  /// Whether to stream the response via SSE.
  final bool? stream;

  /// Serializes this request to a JSON-compatible map.
  ///
  /// Optional fields are omitted when `null`. Keys use snake_case.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'model': model, 'prompt': prompt};
    if (maxTokens != null) json['max_tokens'] = maxTokens;
    if (temperature != null) json['temperature'] = temperature;
    if (stream != null) json['stream'] = stream;
    return json;
  }
}

/// A single choice in a text completion response.
///
/// Each choice contains the generated [text] and an optional
/// [finishReason] indicating why generation stopped.
class CompletionChoice {
  /// Creates a [CompletionChoice].
  const CompletionChoice({required this.text, required this.finishReason});

  /// Deserializes a [CompletionChoice] from a JSON map.
  ///
  /// Reads `text` and `finish_reason`; ignores `index`.
  factory CompletionChoice.fromJson(Map<String, dynamic> json) {
    return CompletionChoice(
      text: json['text'] as String,
      finishReason: json['finish_reason'] as String?,
    );
  }

  /// The generated completion text.
  final String text;

  /// The reason generation stopped (e.g. `"stop"`, `"length"`).
  final String? finishReason;

  /// Serializes this choice to a JSON-compatible map.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'text': text,
    'finish_reason': finishReason,
  };
}

/// The response from `POST /v1/completions` (text completion).
///
/// Contains a unique [id], one or more [choices], and token [usage]
/// statistics.
///
/// ```dart
/// final response = CompletionResponse.fromJson(jsonBody);
/// final text = response.choices.first.text;
/// ```
class CompletionResponse {
  /// Creates a [CompletionResponse].
  const CompletionResponse({
    required this.id,
    required this.choices,
    required this.usage,
  });

  /// Deserializes a [CompletionResponse] from the OpenAI JSON format.
  factory CompletionResponse.fromJson(Map<String, dynamic> json) {
    final rawChoices = json['choices'] as List;
    return CompletionResponse(
      id: json['id'] as String,
      choices: rawChoices
          .map((c) => CompletionChoice.fromJson(c as Map<String, dynamic>))
          .toList(),
      usage: CompletionUsage.fromJson(json['usage'] as Map<String, dynamic>),
    );
  }

  /// The unique identifier for this completion.
  final String id;

  /// The list of completion choices.
  final List<CompletionChoice> choices;

  /// Token usage statistics for this completion.
  final CompletionUsage usage;

  /// Serializes this response to a JSON-compatible map.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'choices': choices.map((c) => c.toJson()).toList(),
    'usage': usage.toJson(),
  };
}
