/// Exception thrown when an SSE data payload cannot be decoded as JSON.
///
/// Contains the raw [data] string and the underlying [cause] from
/// [json.decode] for diagnostics.
///
/// ```dart
/// try {
///   final events = rawLines.transform(const SseParser());
/// } on SseParseException catch (e) {
///   print('Bad SSE payload: ${e.data}');
/// }
/// ```
class SseParseException implements Exception {
  /// Creates an [SseParseException].
  const SseParseException({required this.data, required this.cause});

  /// The raw data string that could not be parsed as JSON.
  final String data;

  /// The underlying [FormatException] from [json.decode].
  final Object cause;

  @override
  String toString() =>
      'SseParseException: Failed to parse SSE data as JSON: $data';
}
