import 'dart:collection';

import 'package:agents_core/agents_core.dart';

/// A minimal [LlmClient] implementation for test isolation.
///
/// Does not make any real HTTP calls. All methods are implemented using
/// either a pre-configured queue of responses or no-op stubs.
///
/// ```dart
/// final client = MockLlmClient([
///   ChatCompletionResponse(id: 'r1', choices: [...], usage: ...),
/// ]);
/// final response = await client.chatCompletion(request);
/// expect(client.capturedRequests, hasLength(1));
/// ```
class MockLlmClient implements LlmClient {
  /// Creates a [MockLlmClient] that returns [responses] in FIFO order.
  ///
  /// If [chatCompletion] is called when the queue is empty, a [StateError]
  /// is thrown.
  MockLlmClient([List<ChatCompletionResponse>? responses])
    : _queue = Queue.of(responses ?? []);

  final Queue<ChatCompletionResponse> _queue;

  /// Every [ChatCompletionRequest] passed to [chatCompletion], in call order.
  final List<ChatCompletionRequest> capturedRequests = [];

  bool _disposed = false;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  @override
  Future<ChatCompletionResponse> chatCompletion(
    ChatCompletionRequest request,
  ) async {
    capturedRequests.add(request);
    if (_queue.isEmpty) {
      throw StateError('MockLlmClient: no more responses queued');
    }
    return _queue.removeFirst();
  }

  @override
  Stream<ChatCompletionChunk> chatCompletionStream(
    ChatCompletionRequest request,
  ) => const Stream.empty();

  @override
  Stream<String> chatCompletionStreamText(ChatCompletionRequest request) =>
      const Stream.empty();

  @override
  void dispose() {
    _disposed = true;
  }
}
