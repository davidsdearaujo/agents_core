import '../client/lm_studio_client.dart';
import '../config/agents_core_config.dart';
import '../models/chat_completion_request.dart';
import '../models/chat_message.dart';

/// The default model identifier used when no [model] is specified.
const _defaultModel = 'lmstudio-community/default';

/// Builds the message list from a [prompt] and optional [systemPrompt].
List<ChatMessage> _buildMessages(String prompt, String? systemPrompt) {
  return [
    if (systemPrompt != null)
      ChatMessage(role: ChatMessageRole.system, content: systemPrompt),
    ChatMessage(role: ChatMessageRole.user, content: prompt),
  ];
}

/// Sends a one-shot chat completion request and returns the assistant's reply.
///
/// This is a convenience function that handles client creation, request
/// building, and resource cleanup in a single call. For more control, use
/// [LmStudioClient] directly.
///
/// [prompt] is sent as the user message content.
///
/// [config] configures the LM Studio server URL, timeout, and logger.
/// When `null`, a default [AgentsCoreConfig] is used (localhost:1234).
///
/// [model] is the model identifier to use. Defaults to
/// `'lmstudio-community/default'` when `null`.
///
/// [systemPrompt], if provided, is prepended as a system message before
/// the user prompt.
///
/// [temperature] controls sampling randomness (0.0 to 2.0). When `null`,
/// the server's default is used.
///
/// Returns the text content of the first choice's assistant message.
///
/// Throws [LmStudioConnectionException] if the server cannot be reached.
/// Throws [LmStudioHttpException] if the response status is not 2xx.
///
/// ```dart
/// final answer = await ask(
///   'What is the capital of France?',
///   model: 'llama-3-8b',
/// );
/// print(answer); // "The capital of France is Paris."
/// ```
Future<String> ask(
  String prompt, {
  AgentsCoreConfig? config,
  String? model,
  String? systemPrompt,
  double? temperature,
}) async {
  final effectiveConfig = config ?? AgentsCoreConfig();
  final client = LmStudioClient(effectiveConfig);

  try {
    final request = ChatCompletionRequest(
      model: model ?? _defaultModel,
      messages: _buildMessages(prompt, systemPrompt),
      temperature: temperature,
    );

    final response = await client.chatCompletion(request);
    return response.choices.first.message.content ?? '';
  } finally {
    client.dispose();
  }
}

/// Sends a streaming chat completion request and yields content deltas.
///
/// This is the streaming counterpart of [ask]. Each element in the returned
/// stream is a text fragment (content delta) from the assistant's reply.
/// Concatenating all emitted strings produces the full response.
///
/// The function handles client creation and disposes it after the stream
/// is fully consumed or an error occurs.
///
/// All parameters match [ask]:
///
/// [prompt] is sent as the user message content.
///
/// [config] configures the LM Studio server URL, timeout, and logger.
/// When `null`, a default [AgentsCoreConfig] is used (localhost:1234).
///
/// [model] is the model identifier to use. Defaults to
/// `'lmstudio-community/default'` when `null`.
///
/// [systemPrompt], if provided, is prepended as a system message before
/// the user prompt.
///
/// [temperature] controls sampling randomness (0.0 to 2.0). When `null`,
/// the server's default is used.
///
/// Errors from the underlying HTTP transport surface as stream errors
/// (i.e. they are thrown when listening to the stream).
///
/// ```dart
/// final buffer = StringBuffer();
/// await for (final delta in askStream(
///   'Tell me a story',
///   model: 'llama-3-8b',
/// )) {
///   stdout.write(delta);
///   buffer.write(delta);
/// }
/// print('\nFull response: $buffer');
/// ```
Stream<String> askStream(
  String prompt, {
  AgentsCoreConfig? config,
  String? model,
  String? systemPrompt,
  double? temperature,
}) async* {
  final effectiveConfig = config ?? AgentsCoreConfig();
  final client = LmStudioClient(effectiveConfig);

  try {
    final request = ChatCompletionRequest(
      model: model ?? _defaultModel,
      messages: _buildMessages(prompt, systemPrompt),
      temperature: temperature,
    );

    yield* client.chatCompletionStreamText(request);
  } finally {
    client.dispose();
  }
}
