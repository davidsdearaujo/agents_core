import '../models/chat_completion_chunk.dart';
import '../models/chat_completion_request.dart';
import '../models/chat_completion_response.dart';

/// Abstract interface for LLM chat-completion backends.
///
/// Implement this interface to support alternative LLM providers (OpenAI,
/// Anthropic, Ollama, etc.) alongside the built-in [LmStudioClient].
/// Agents and orchestrators depend on [LlmClient], not on any concrete
/// implementation, enabling Dependency Inversion.
///
/// The minimal contract required by [Agent] subclasses consists of:
/// - [chatCompletion] — single-shot, buffered response
/// - [chatCompletionStream] — incremental SSE-style chunks
/// - [chatCompletionStreamText] — convenience text-only stream
/// - [dispose] — lifecycle teardown
///
/// ```dart
/// class MyOpenAiClient implements LlmClient {
///   @override
///   Future<ChatCompletionResponse> chatCompletion(
///       ChatCompletionRequest request) async { ... }
///
///   @override
///   Stream<ChatCompletionChunk> chatCompletionStream(
///       ChatCompletionRequest request) { ... }
///
///   @override
///   Stream<String> chatCompletionStreamText(
///       ChatCompletionRequest request) { ... }
///
///   @override
///   void dispose() { ... }
/// }
/// ```
abstract interface class LlmClient {
  /// Sends a chat completion request and returns the full buffered response.
  ///
  /// Implementations must POST to the provider's chat-completions endpoint
  /// with `stream` disabled (or equivalent) and decode the JSON body into a
  /// [ChatCompletionResponse].
  ///
  /// Throws an appropriate exception if the network request fails or the
  /// provider returns a non-success status.
  Future<ChatCompletionResponse> chatCompletion(ChatCompletionRequest request);

  /// Sends a streaming chat completion request and returns a stream of chunks.
  ///
  /// Implementations must POST to the provider's chat-completions endpoint
  /// with `stream` enabled and emit one [ChatCompletionChunk] per SSE event
  /// (or equivalent incremental payload). The stream should close cleanly
  /// after the final chunk and must not emit the `[DONE]` sentinel as a
  /// chunk.
  ///
  /// Throws an appropriate exception if the connection cannot be established.
  Stream<ChatCompletionChunk> chatCompletionStream(
    ChatCompletionRequest request,
  );

  /// Convenience stream that emits only the non-empty text content deltas.
  ///
  /// Implementations should delegate to [chatCompletionStream] and project
  /// each chunk to its first-choice delta content, filtering out null and
  /// empty strings.
  ///
  /// ```dart
  /// await for (final text in client.chatCompletionStreamText(request)) {
  ///   stdout.write(text);
  /// }
  /// ```
  Stream<String> chatCompletionStreamText(ChatCompletionRequest request);

  /// Releases any resources held by this client (sockets, connection pools,
  /// etc.).
  ///
  /// After [dispose] is called, no further requests should be made on this
  /// instance. Implementations must be idempotent — calling [dispose] more
  /// than once must not throw.
  void dispose();
}
