/// Utility functions for computing text similarity metrics.
library;

/// Provides static methods for measuring similarity between strings.
///
/// This class cannot be instantiated — all functionality is available via
/// static methods.
///
/// ## Available metrics
///
/// - [bigram]: Sørensen–Dice coefficient computed over character bigrams.
///
/// ## Example
///
/// ```dart
/// final score = TextSimilarity.bigram('night', 'nacht');
/// print(score); // ~0.25
/// ```
abstract final class TextSimilarity {
  /// Computes the bigram similarity between two strings using the
  /// Sørensen–Dice coefficient over character bigrams.
  ///
  /// Returns a value in the range `[0.0, 1.0]`, where:
  /// - `1.0` means the two strings are identical (or both empty).
  /// - `0.0` means the strings share no bigrams (or exactly one is empty).
  ///
  /// ## Algorithm
  ///
  /// A *character bigram* is a pair of consecutive characters. The method
  /// builds a multiset of bigrams for each string, counts the size of their
  /// intersection, and applies the Sørensen–Dice formula:
  ///
  /// ```
  /// similarity = (2 × |intersection|) / (|bigrams(a)| + |bigrams(b)|)
  /// ```
  ///
  /// ## Edge cases
  ///
  /// | Condition | Result |
  /// |-----------|--------|
  /// | Both strings equal | `1.0` |
  /// | Both strings empty | `1.0` |
  /// | Exactly one string empty | `0.0` |
  /// | Either string has length < 2 | `1.0` if equal, `0.0` otherwise |
  ///
  /// ## Examples
  ///
  /// ```dart
  /// TextSimilarity.bigram('hello', 'hello'); // 1.0 — identical
  /// TextSimilarity.bigram('', '');           // 1.0 — both empty
  /// TextSimilarity.bigram('hi', '');         // 0.0 — one empty
  /// TextSimilarity.bigram('night', 'nacht'); // ~0.25
  /// TextSimilarity.bigram('hello', 'world'); // ~0.0
  /// ```
  static double bigram(String a, String b) {
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
  ///
  /// Each key is a two-character substring; the value is the number of times
  /// that bigram appears in [s].
  static Map<String, int> _buildBigramMultiset(String s) {
    final bigrams = <String, int>{};
    for (var i = 0; i < s.length - 1; i++) {
      final bigram = s.substring(i, i + 2);
      bigrams[bigram] = (bigrams[bigram] ?? 0) + 1;
    }
    return bigrams;
  }
}
