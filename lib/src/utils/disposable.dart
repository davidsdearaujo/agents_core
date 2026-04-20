import 'package:meta/meta.dart';

/// Mixin that adds an explicit, analyzer-enforced lifecycle contract to any
/// class that holds resources (sockets, HTTP connections, streams).
///
/// Apply [Disposable] to resource-owning classes to make their cleanup
/// obligation visible to both developers and the Dart analyzer.
///
/// ## Usage
///
/// ```dart
/// class MyClient with Disposable {
///   final _socket = Socket();
///
///   @override
///   @mustCallSuper
///   void dispose() {
///     _socket.close(); // release owned resources first
///     super.dispose(); // marks isDisposed = true
///   }
/// }
/// ```
///
/// ## Consumers
///
/// Always call [dispose] when a disposable object is no longer needed.
/// Use a `try/finally` block to guarantee cleanup even on error:
///
/// ```dart
/// final client = LmStudioClient(config);
/// try {
///   final result = await client.chatCompletion(request);
/// } finally {
///   client.dispose();
/// }
/// ```
///
/// When working with agents, dispose their client after [Agent.run] returns:
///
/// ```dart
/// final client = LmStudioClient(config);
/// final agent = ReactAgent(name: 'bot', client: client, config: config);
/// final result = await agent.run('task');
/// client.dispose(); // or agent.client.dispose()
/// ```
mixin Disposable {
  bool _disposed = false;

  /// Whether [dispose] has been called on this object.
  ///
  /// Once `true`, the object must not be used for further operations.
  bool get isDisposed => _disposed;

  /// Releases all resources held by this object and marks it as disposed.
  ///
  /// Subclasses that override [dispose] **must** call `super.dispose()` as
  /// their last statement to ensure [isDisposed] is set to `true`.
  ///
  /// Calling [dispose] more than once is safe — subsequent calls are
  /// silently ignored.
  ///
  /// ```dart
  /// @override
  /// @mustCallSuper
  /// void dispose() {
  ///   _resource.close();
  ///   super.dispose(); // always last
  /// }
  /// ```
  @mustCallSuper
  void dispose() {
    _disposed = true;
  }
}
