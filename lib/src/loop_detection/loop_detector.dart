import '../models/tool_call.dart';
import 'loop_detection_config.dart';

/// The result of a loop-detection check.
///
/// When [isLooping] is `true`, [reason] describes what pattern was detected
/// (e.g. repeated tool calls or repeated outputs).
class LoopCheckResult {
  /// Creates a [LoopCheckResult].
  const LoopCheckResult({required this.isLooping, this.reason});

  /// A result indicating no loop was detected.
  static const ok = LoopCheckResult(isLooping: false);

  /// Whether a loop pattern was detected.
  final bool isLooping;

  /// A human-readable description of the detected loop pattern.
  ///
  /// `null` when [isLooping] is `false`.
  final String? reason;

  @override
  String toString() =>
      'LoopCheckResult(isLooping: $isLooping${reason != null ? ', reason: $reason' : ''})';
}

/// Detects when an LLM agent is stuck in a repetitive loop.
///
/// Tracks consecutive identical tool-call sequences and consecutive
/// near-identical text outputs. Call [recordToolCalls] and [recordOutput]
/// after each LLM iteration, then [check] to see if a loop has been
/// detected.
///
/// ```dart
/// final detector = LoopDetector(config: LoopDetectionConfig());
///
/// // After each LLM iteration:
/// detector.recordToolCalls(response.toolCalls);
/// detector.recordOutput(response.content);
///
/// final result = detector.check();
/// if (result.isLooping) {
///   print('Loop detected: ${result.reason}');
/// }
/// ```
class LoopDetector {
  /// Creates a [LoopDetector] with the given [config].
  LoopDetector({required this.config});

  /// The configuration controlling detection thresholds.
  final LoopDetectionConfig config;

  /// History of tool-call sequence fingerprints, most recent last.
  final List<String> _toolCallHistory = [];

  /// History of LLM text outputs, most recent last.
  final List<String> _outputHistory = [];

  /// Records a list of tool calls from a single LLM response.
  ///
  /// The tool calls are normalised into a deterministic fingerprint
  /// (sorted by function name, then arguments) so that reordering
  /// within a single response does not affect detection.
  ///
  /// Pass an empty list or `null` to record that no tool calls were made.
  void recordToolCalls(List<ToolCall>? toolCalls) {
    if (toolCalls == null || toolCalls.isEmpty) {
      _toolCallHistory.add('');
      return;
    }

    // Build a sorted fingerprint of the tool-call sequence.
    final fingerprints = toolCalls.map((tc) {
      final name = tc.function?.name ?? '';
      final args = tc.function?.arguments ?? '';
      return '$name:$args';
    }).toList()
      ..sort();

    _toolCallHistory.add(fingerprints.join('|'));
  }

  /// Records a text output from a single LLM response.
  ///
  /// Pass an empty string or `null` to record that no text was produced.
  void recordOutput(String? output) {
    _outputHistory.add(output ?? '');
  }

  /// Checks whether a loop pattern has been detected.
  ///
  /// Returns a [LoopCheckResult] with [LoopCheckResult.isLooping] set to
  /// `true` if either:
  ///
  /// - The last [LoopDetectionConfig.maxConsecutiveIdenticalToolCalls]
  ///   tool-call fingerprints are identical (and non-empty).
  /// - The last [LoopDetectionConfig.maxConsecutiveIdenticalOutputs]
  ///   outputs are similar above [LoopDetectionConfig.similarityThreshold]
  ///   (and non-empty).
  LoopCheckResult check() {
    // ── Check tool-call repetition ──────────────────────────────────────
    final toolThreshold = config.maxConsecutiveIdenticalToolCalls;
    if (toolThreshold > 0 && _toolCallHistory.length >= toolThreshold) {
      final recent =
          _toolCallHistory.sublist(_toolCallHistory.length - toolThreshold);
      final last = recent.last;
      if (last.isNotEmpty && recent.every((fp) => fp == last)) {
        return LoopCheckResult(
          isLooping: true,
          reason: 'Detected $toolThreshold consecutive identical '
              'tool-call sequences',
        );
      }
    }

    // ── Check output repetition ─────────────────────────────────────────
    final outputThreshold = config.maxConsecutiveIdenticalOutputs;
    if (outputThreshold > 0 && _outputHistory.length >= outputThreshold) {
      final recent =
          _outputHistory.sublist(_outputHistory.length - outputThreshold);
      final reference = recent.last;
      if (reference.isNotEmpty &&
          recent.every((output) =>
              bigramSimilarity(output, reference) >=
              config.similarityThreshold)) {
        return LoopCheckResult(
          isLooping: true,
          reason: 'Detected $outputThreshold consecutive near-identical '
              'outputs (similarity >= ${config.similarityThreshold})',
        );
      }
    }

    return LoopCheckResult.ok;
  }

  /// Resets all recorded history.
  ///
  /// Call this when starting a new task or after recovering from a loop.
  void reset() {
    _toolCallHistory.clear();
    _outputHistory.clear();
  }

  /// Computes the bigram similarity between two strings.
  ///
  /// Returns a value between 0.0 (completely different) and 1.0 (identical
  /// bigram sets). This is a variant of the Sørensen–Dice coefficient
  /// computed over character bigrams.
  ///
  /// Two empty strings are considered identical (returns 1.0). If exactly
  /// one string is empty, returns 0.0. Strings shorter than 2 characters
  /// are compared by equality.
  ///
  /// ```dart
  /// LoopDetector.bigramSimilarity('hello', 'hello'); // 1.0
  /// LoopDetector.bigramSimilarity('hello', 'world'); // ~0.0
  /// LoopDetector.bigramSimilarity('night', 'nacht'); // ~0.25
  /// ```
  static double bigramSimilarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    if (a.length < 2 || b.length < 2) return a == b ? 1.0 : 0.0;

    final bigramsA = _buildBigramMultiset(a);
    final bigramsB = _buildBigramMultiset(b);

    // Count shared bigrams (intersection of multisets).
    var intersectionSize = 0;
    for (final entry in bigramsA.entries) {
      final countInB = bigramsB[entry.key] ?? 0;
      if (countInB > 0) {
        intersectionSize += entry.value < countInB ? entry.value : countInB;
      }
    }

    final totalSize = a.length - 1 + b.length - 1;
    return (2 * intersectionSize) / totalSize;
  }

  /// Builds a multiset (frequency map) of character bigrams from [s].
  static Map<String, int> _buildBigramMultiset(String s) {
    final bigrams = <String, int>{};
    for (var i = 0; i < s.length - 1; i++) {
      final bigram = s.substring(i, i + 2);
      bigrams[bigram] = (bigrams[bigram] ?? 0) + 1;
    }
    return bigrams;
  }
}
