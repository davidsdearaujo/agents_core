import 'dart:convert';

import 'package:meta/meta.dart';

import '../config/agents_core_config.dart';
import '../config/lm_studio_config.dart';
import '../models/chat_completion_chunk.dart';
import '../models/chat_completion_request.dart';
import '../models/chat_completion_response.dart';
import '../models/completion.dart';
import '../models/lm_model.dart';
import '../utils/disposable.dart';
import 'llm_client.dart';
import 'lm_studio_http_client.dart';

/// High-level client for the LM Studio OpenAI-compatible API.
///
/// Provides typed methods for every supported endpoint — models listing,
/// chat completions (sync and streaming), and text completions.
///
/// Built on top of [LmStudioHttpClient] for HTTP transport. Streaming
/// methods use [LmStudioHttpClient.postStream] which handles SSE framing
/// and the `[DONE]` sentinel internally.
///
/// Always call [dispose] when the client is no longer needed.
///
/// ```dart
/// final client = LmStudioClient(AgentsCoreConfig());
///
/// // List available models
/// final models = await client.listModels();
///
/// // Chat completion
/// final response = await client.chatCompletion(
///   ChatCompletionRequest(
///     model: 'llama-3-8b',
///     messages: [ChatMessage(role: ChatMessageRole.user, content: 'Hi!')],
///   ),
/// );
///
/// // Streaming chat completion
/// await for (final chunk in client.chatCompletionStream(request)) {
///   stdout.write(chunk.choices.first.delta.content ?? '');
/// }
///
/// client.dispose();
/// ```
class LmStudioClient with Disposable implements LlmClient {
  /// Creates an [LmStudioClient] configured from [config].
  ///
  /// Optionally accepts an existing [httpClient] for testing or reuse.
  /// If omitted, a new [LmStudioHttpClient] is created from [config].
  LmStudioClient(AgentsCoreConfig config, {LmStudioHttpClient? httpClient})
    : _config = config,
      _httpClient = httpClient ?? LmStudioHttpClient(config: config);

  /// Creates an [LmStudioClient] configured from a specialised
  /// [LmStudioConfig].
  ///
  /// This is the preferred constructor when the consumer has already built
  /// an [LmStudioConfig] independently.
  ///
  /// ```dart
  /// final client = LmStudioClient.fromLmStudioConfig(
  ///   LmStudioConfig(
  ///     baseUrl: Uri.parse('http://localhost:1234'),
  ///     defaultModel: 'llama-3-8b',
  ///   ),
  /// );
  /// ```
  factory LmStudioClient.fromLmStudioConfig(LmStudioConfig lmStudioConfig) {
    final config = AgentsCoreConfig(
      lmStudioBaseUrl: lmStudioConfig.baseUrl,
      defaultModel: lmStudioConfig.defaultModel,
      requestTimeout: lmStudioConfig.requestTimeout,
      apiKey: lmStudioConfig.apiKey,
    );
    return LmStudioClient(config);
  }

  final AgentsCoreConfig _config;
  final LmStudioHttpClient _httpClient;

  // ── Models ────────────────────────────────────────────────────────────────

  /// Lists all models available on the LM Studio server.
  ///
  /// Calls `GET /v1/models` and returns a [List<LmModel>].
  /// Returns an empty list if the server reports zero models.
  ///
  /// Throws [LmStudioConnectionException] if the server cannot be reached.
  /// Throws [LmStudioHttpException] if the response status is not 2xx.
  Future<List<LmModel>> listModels() async {
    _config.logger.debug('Listing models');
    final json = await _httpClient.get('/v1/models');
    final data = json['data'] as List? ?? [];
    return data
        .map((m) => LmModel.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  // ── Chat Completions ──────────────────────────────────────────────────────

  /// Sends a chat completion request and returns the full response.
  ///
  /// Calls `POST /v1/chat/completions` with the given [request].
  /// The `stream` field is forced to `false` (or omitted) for this method.
  ///
  /// ```dart
  /// final response = await client.chatCompletion(request);
  /// print(response.choices.first.message.content);
  /// ```
  @override
  Future<ChatCompletionResponse> chatCompletion(
    ChatCompletionRequest request,
  ) async {
    _config.logger.debug('Chat completion: model=${request.model}');
    final body = request.toJson()..remove('stream');
    final json = await _httpClient.post('/v1/chat/completions', body);
    return ChatCompletionResponse.fromJson(json);
  }

  /// Sends a streaming chat completion request and returns a stream of chunks.
  ///
  /// Calls `POST /v1/chat/completions` with `stream: true`. Each emitted
  /// [ChatCompletionChunk] contains an incremental delta.
  ///
  /// The underlying [LmStudioHttpClient.postStream] handles SSE framing
  /// and the `[DONE]` sentinel, so each element in the returned stream
  /// is a fully-parsed JSON payload decoded into a [ChatCompletionChunk].
  ///
  /// ```dart
  /// await for (final chunk in client.chatCompletionStream(request)) {
  ///   final content = chunk.choices.first.delta.content;
  ///   if (content != null) stdout.write(content);
  /// }
  /// ```
  @override
  Stream<ChatCompletionChunk> chatCompletionStream(
    ChatCompletionRequest request,
  ) {
    _config.logger.debug('Chat completion stream: model=${request.model}');
    final body = request.toJson()..['stream'] = true;

    return _httpClient
        .postStream('/v1/chat/completions', body)
        .map((data) => json.decode(data) as Map<String, dynamic>)
        .map(ChatCompletionChunk.fromJson);
  }

  /// Convenience method that streams only the text content deltas.
  ///
  /// Returns a `Stream<String>` where each element is the `content` field
  /// from the first choice's delta. Empty/null deltas are filtered out.
  ///
  /// ```dart
  /// await for (final text in client.chatCompletionStreamText(request)) {
  ///   stdout.write(text);
  /// }
  /// ```
  @override
  Stream<String> chatCompletionStreamText(ChatCompletionRequest request) {
    return chatCompletionStream(request)
        .map((chunk) => chunk.choices.first.delta.content)
        .where((content) => content != null && content.isNotEmpty)
        .cast<String>();
  }

  // ── Text Completions ──────────────────────────────────────────────────────

  /// Sends a text completion request and returns the full response.
  ///
  /// Calls `POST /v1/completions` with the given [request].
  ///
  /// ```dart
  /// final response = await client.completion(request);
  /// print(response.choices.first.text);
  /// ```
  Future<CompletionResponse> completion(CompletionRequest request) async {
    _config.logger.debug('Text completion: model=${request.model}');
    final json = await _httpClient.post('/v1/completions', request.toJson());
    return CompletionResponse.fromJson(json);
  }

  /// Sends a streaming text completion request and returns a stream of
  /// raw JSON objects.
  ///
  /// Calls `POST /v1/completions` with `stream: true`. Each emitted map
  /// is a decoded JSON object from the SSE stream.
  ///
  /// For chat-style streaming with typed objects, use
  /// [chatCompletionStream] instead.
  Stream<Map<String, dynamic>> completionStream(CompletionRequest request) {
    _config.logger.debug('Text completion stream: model=${request.model}');
    final body = request.toJson()..['stream'] = true;

    return _httpClient
        .postStream('/v1/completions', body)
        .map((data) => json.decode(data) as Map<String, dynamic>);
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Closes the underlying HTTP client and frees its resources.
  ///
  /// After calling [dispose], no further requests can be made with
  /// this instance. Subsequent calls are a no-op.
  @override
  @mustCallSuper
  void dispose() {
    if (isDisposed) return;
    _config.logger.debug('Disposing LmStudioClient');
    _httpClient.dispose();
    super.dispose();
  }
}
