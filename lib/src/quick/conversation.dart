import '../client/lm_studio_client.dart';
import '../config/agents_core_config.dart';
import '../models/chat_completion_request.dart';
import '../models/chat_message.dart';

const _defaultModel = 'lmstudio-community/default';

/// A stateful multi-turn conversation backed by an [LmStudioClient].
///
/// Manages a growing message history so every [send] or [sendStream]
/// call automatically includes all previous context.
///
/// ```dart
/// final conv = Conversation(config: config, model: 'llama3');
/// final reply = await conv.send('What is 2 + 2?');
/// print(reply); // "4"
///
/// await for (final delta in conv.sendStream('Explain that.')) {
///   stdout.write(delta);
/// }
/// ```
class Conversation {
  /// Creates a [Conversation].
  ///
  /// [config] is required and provides the HTTP connection settings.
  /// [model] defaults to a built-in fallback if omitted.
  /// [systemPrompt], when provided, is prepended to every request as a
  /// `system` message.
  Conversation({
    required AgentsCoreConfig config,
    String? model,
    String? systemPrompt,
  })  : _client = LmStudioClient(config),
        _model = model ?? _defaultModel {
    if (systemPrompt != null) {
      _history.add(
        ChatMessage(role: ChatMessageRole.system, content: systemPrompt),
      );
    }
  }

  final LmStudioClient _client;
  final String _model;
  final List<ChatMessage> _history = [];

  // ── History ───────────────────────────────────────────────────────────────

  /// The current conversation history.
  ///
  /// Returns an unmodifiable view — mutating the returned list has no effect
  /// on the conversation's internal state.
  List<ChatMessage> get history => List.unmodifiable(_history);

  // ── send() ────────────────────────────────────────────────────────────────

  /// Sends [prompt] to the model and returns the assistant's reply.
  ///
  /// Appends [prompt] as a user message and the reply as an assistant
  /// message to the history before returning.
  ///
  /// Throws [LmStudioHttpException] on non-2xx responses.
  /// Throws [LmStudioConnectionException] if the server cannot be reached.
  /// On any error, the assistant message is NOT appended to history.
  Future<String> send(String prompt) async {
    _history.add(ChatMessage(role: ChatMessageRole.user, content: prompt));
    final request = ChatCompletionRequest(
      model: _model,
      messages: List.from(_history),
    );
    final response = await _client.chatCompletion(request);
    final content = response.choices.first.message.content ?? '';
    _history.add(
      ChatMessage(role: ChatMessageRole.assistant, content: content),
    );
    return content;
  }

  // ── sendStream() ──────────────────────────────────────────────────────────

  /// Sends [prompt] and streams incremental text deltas from the model.
  ///
  /// Appends [prompt] as a user message immediately, then yields each
  /// content delta as it arrives. Once the stream is fully consumed, the
  /// assembled reply is appended to history as an assistant message.
  ///
  /// The caller must consume the full stream for the assistant message to
  /// be recorded in history.
  Stream<String> sendStream(String prompt) async* {
    _history.add(ChatMessage(role: ChatMessageRole.user, content: prompt));
    final request = ChatCompletionRequest(
      model: _model,
      messages: List.from(_history),
    );
    final buffer = StringBuffer();
    await for (final delta in _client.chatCompletionStreamText(request)) {
      buffer.write(delta);
      yield delta;
    }
    _history.add(
      ChatMessage(
        role: ChatMessageRole.assistant,
        content: buffer.toString(),
      ),
    );
  }

  // ── setSystemPrompt() ─────────────────────────────────────────────────────

  /// Sets or replaces the system prompt.
  ///
  /// If a `system` message already exists at index 0, it is replaced.
  /// Otherwise the new message is inserted at position 0.
  void setSystemPrompt(String prompt) {
    final systemMsg =
        ChatMessage(role: ChatMessageRole.system, content: prompt);
    if (_history.isNotEmpty && _history.first.role == ChatMessageRole.system) {
      _history[0] = systemMsg;
    } else {
      _history.insert(0, systemMsg);
    }
  }

  // ── clearHistory() ────────────────────────────────────────────────────────

  /// Clears all conversation history.
  ///
  /// If a `system` message is at index 0, it is preserved so the assistant
  /// behaviour is retained for subsequent turns.
  void clearHistory() {
    if (_history.isNotEmpty && _history.first.role == ChatMessageRole.system) {
      final systemMsg = _history.first;
      _history.clear();
      _history.add(systemMsg);
    } else {
      _history.clear();
    }
  }
}
