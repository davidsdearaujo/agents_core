import 'dart:async';
import 'dart:convert';

import '../exceptions/sse_exceptions.dart';

/// A [StreamTransformer] that parses Server-Sent Event (SSE) lines into
/// decoded JSON objects.
///
/// Transforms a `Stream<String>` of raw HTTP response lines (as produced by
/// [LineSplitter]) into a `Stream<Map<String, dynamic>>` of parsed JSON
/// payloads.
///
/// ## SSE features supported
///
/// - **Single-line data:** `data: {"key": "value"}` is parsed and emitted
///   as a single JSON object.
/// - **Multi-line data:** Multiple consecutive `data:` lines within the same
///   event are concatenated with `\n` before parsing, per the
///   [SSE specification](https://html.spec.whatwg.org/multipage/server-sent-events.html).
/// - **Done sentinel:** The `data: [DONE]` payload (used by OpenAI-compatible
///   APIs) closes the output stream gracefully.
/// - **Comments:** Lines starting with `:` are silently ignored.
/// - **Non-data fields:** `event:`, `id:`, and `retry:` fields are ignored
///   since they are not needed for LLM streaming responses.
///
/// Empty lines delimit events per the SSE specification. An event is
/// dispatched (its accumulated `data:` payload is parsed and emitted) when
/// a blank line is encountered.
///
/// ```dart
/// final jsonStream = rawLines.transform(const SseParser());
/// await for (final obj in jsonStream) {
///   print(obj['choices']);
/// }
/// ```
class SseParser implements StreamTransformer<String, Map<String, dynamic>> {
  /// Creates a const [SseParser].
  const SseParser();

  /// The sentinel value that signals the end of the SSE stream.
  static const doneSentinel = '[DONE]';

  @override
  Stream<Map<String, dynamic>> bind(Stream<String> stream) {
    final controller = StreamController<Map<String, dynamic>>();
    final dataBuffer = StringBuffer();
    var isDone = false;

    final subscription = stream.listen(
      (line) {
        if (isDone) return;

        // Blank line: dispatch the accumulated event.
        if (line.isEmpty) {
          _dispatchEvent(dataBuffer, controller);
          return;
        }

        // Comment lines are ignored per the SSE spec.
        if (line.startsWith(':')) return;

        // Parse "field: value" or "field:value".
        final colonIndex = line.indexOf(':');
        if (colonIndex < 0) return;

        final field = line.substring(0, colonIndex);
        // Per SSE spec, strip one leading space from value if present.
        var value = line.substring(colonIndex + 1);
        if (value.startsWith(' ')) {
          value = value.substring(1);
        }

        if (field == 'data') {
          // Check for the done sentinel before buffering.
          if (value == doneSentinel) {
            isDone = true;
            dataBuffer.clear();
            controller.close();
            return;
          }

          // Multi-line data: join with newlines.
          if (dataBuffer.isNotEmpty) {
            dataBuffer.write('\n');
          }
          dataBuffer.write(value);
        }
        // event:, id:, retry: fields are intentionally ignored.
      },
      onError: controller.addError,
      onDone: () {
        // Flush any remaining buffered data when the source stream closes.
        if (!isDone && dataBuffer.isNotEmpty) {
          _dispatchEvent(dataBuffer, controller);
        }
        if (!controller.isClosed) {
          controller.close();
        }
      },
    );

    controller.onCancel = () {
      subscription.cancel();
    };

    return controller.stream;
  }

  @override
  StreamTransformer<RS, RT> cast<RS, RT>() =>
      StreamTransformer.castFrom<String, Map<String, dynamic>, RS, RT>(this);

  /// Parses the accumulated [buffer] as JSON, emits it through [controller],
  /// and clears the buffer.
  ///
  /// If the buffer is empty, this is a no-op. If the JSON is malformed,
  /// an [SseParseException] is added to the controller as an error.
  static void _dispatchEvent(
    StringBuffer buffer,
    StreamController<Map<String, dynamic>> controller,
  ) {
    if (buffer.isEmpty) return;

    final raw = buffer.toString();
    buffer.clear();

    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        controller.add(decoded);
      } else {
        controller.addError(
          SseParseException(
            data: raw,
            cause: FormatException(
              'Expected a JSON object but got ${decoded.runtimeType}',
            ),
          ),
        );
      }
    } on FormatException catch (e) {
      controller.addError(SseParseException(data: raw, cause: e));
    }
  }
}
