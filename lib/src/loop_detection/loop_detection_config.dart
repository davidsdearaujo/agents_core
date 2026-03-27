/// Configuration for loop detection in agent tool-calling loops.
///
/// Controls the thresholds that determine when an LLM is considered
/// "stuck" — repeatedly making the same tool calls or producing the same
/// outputs. All defaults are intentionally conservative to minimise false
/// positives while still catching obvious loops.
///
/// ```dart
/// const config = LoopDetectionConfig(
///   maxConsecutiveIdenticalToolCalls: 3,
///   maxConsecutiveIdenticalOutputs: 3,
///   similarityThreshold: 0.9,
/// );
/// ```
class LoopDetectionConfig {
  /// Creates a [LoopDetectionConfig].
  ///
  /// [maxConsecutiveIdenticalToolCalls] — the number of consecutive identical
  /// tool-call sequences before the detector flags a loop. Defaults to 3.
  ///
  /// [maxConsecutiveIdenticalOutputs] — the number of consecutive identical
  /// (or near-identical) LLM text outputs before the detector flags a loop.
  /// Defaults to 3.
  ///
  /// [similarityThreshold] — the bigram-similarity score (0.0–1.0) above
  /// which two outputs are considered "identical" for loop detection purposes.
  /// Defaults to 0.85.
  const LoopDetectionConfig({
    this.maxConsecutiveIdenticalToolCalls = 3,
    this.maxConsecutiveIdenticalOutputs = 3,
    this.similarityThreshold = 0.85,
  });

  /// Maximum consecutive identical tool-call sequences before a loop is
  /// detected.
  ///
  /// A "tool-call sequence" is the sorted list of `functionName:arguments`
  /// strings produced by a single LLM response. When the detector sees this
  /// many identical sequences in a row, it reports a loop.
  ///
  /// Defaults to 3.
  final int maxConsecutiveIdenticalToolCalls;

  /// Maximum consecutive identical (or near-identical) LLM text outputs
  /// before a loop is detected.
  ///
  /// Similarity is measured with [LoopDetector.bigramSimilarity] and
  /// compared against [similarityThreshold].
  ///
  /// Defaults to 3.
  final int maxConsecutiveIdenticalOutputs;

  /// The bigram-similarity threshold (0.0–1.0) used to decide whether two
  /// LLM outputs are "identical" for loop-detection purposes.
  ///
  /// A value of 1.0 requires exact matches; lower values catch near-copies
  /// such as outputs that differ only in whitespace or punctuation.
  ///
  /// Defaults to 0.85.
  final double similarityThreshold;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LoopDetectionConfig &&
        other.maxConsecutiveIdenticalToolCalls ==
            maxConsecutiveIdenticalToolCalls &&
        other.maxConsecutiveIdenticalOutputs ==
            maxConsecutiveIdenticalOutputs &&
        other.similarityThreshold == similarityThreshold;
  }

  @override
  int get hashCode => Object.hash(
        maxConsecutiveIdenticalToolCalls,
        maxConsecutiveIdenticalOutputs,
        similarityThreshold,
      );

  @override
  String toString() =>
      'LoopDetectionConfig('
      'maxConsecutiveIdenticalToolCalls: $maxConsecutiveIdenticalToolCalls, '
      'maxConsecutiveIdenticalOutputs: $maxConsecutiveIdenticalOutputs, '
      'similarityThreshold: $similarityThreshold)';
}
