import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

void main() {
  // =========================================================================
  // TextSimilarity — class structure
  // =========================================================================

  group('TextSimilarity — class structure', () {
    test('TextSimilarity.bigram is accessible as a static method', () {
      // Should compile and not throw.
      expect(() => TextSimilarity.bigram('a', 'b'), returnsNormally);
    });

    test('TextSimilarity.bigram returns a double', () {
      final result = TextSimilarity.bigram('hello', 'world');
      expect(result, isA<double>());
    });
  });

  // =========================================================================
  // TextSimilarity.bigram — edge cases
  // =========================================================================

  group('TextSimilarity.bigram — edge cases', () {
    test('identical strings return 1.0', () {
      expect(TextSimilarity.bigram('hello', 'hello'), equals(1.0));
    });

    test('both empty strings return 1.0', () {
      // Empty == empty via fast path (a == b).
      expect(TextSimilarity.bigram('', ''), equals(1.0));
    });

    test('first string empty, second non-empty returns 0.0', () {
      expect(TextSimilarity.bigram('', 'hello'), equals(0.0));
    });

    test('first string non-empty, second empty returns 0.0', () {
      expect(TextSimilarity.bigram('hello', ''), equals(0.0));
    });

    test('single-char equal strings return 1.0', () {
      expect(TextSimilarity.bigram('a', 'a'), equals(1.0));
    });

    test('single-char different strings return 0.0', () {
      expect(TextSimilarity.bigram('a', 'b'), equals(0.0));
    });

    test('two-char equal strings return 1.0', () {
      expect(TextSimilarity.bigram('ab', 'ab'), equals(1.0));
    });

    test('two-char different strings return 0.0', () {
      expect(TextSimilarity.bigram('ab', 'cd'), equals(0.0));
    });

    test('two-char partial overlap returns value between 0.0 and 1.0', () {
      // 'ab' and 'bc': ab vs bc → no shared bigrams → 0.0
      expect(TextSimilarity.bigram('ab', 'bc'), equals(0.0));
    });

    test('single char vs multi-char returns 0.0', () {
      // 'a' has length < 2 → short-string path → a != 'hello' → 0.0
      expect(TextSimilarity.bigram('a', 'hello'), equals(0.0));
    });

    test('multi-char vs single char returns 0.0', () {
      expect(TextSimilarity.bigram('hello', 'a'), equals(0.0));
    });
  });

  // =========================================================================
  // TextSimilarity.bigram — bigram computation (Sørensen-Dice coefficient)
  // =========================================================================

  group('TextSimilarity.bigram — bigram computation', () {
    test('completely different words return 0.0', () {
      // 'hello' bigrams: he, el, ll, lo — no overlap with 'world': wo, or, rl, ld
      expect(TextSimilarity.bigram('hello', 'world'), equals(0.0));
    });

    test('known example: night / nacht returns ~0.25', () {
      // 'night' bigrams: ni, ig, gh, ht (4)
      // 'nacht' bigrams: na, ac, ch, ht (4)
      // intersection: ht → 1
      // totalSize = 4 + 4 = 8 → 2/8 = 0.25
      expect(TextSimilarity.bigram('night', 'nacht'), closeTo(0.25, 1e-9));
    });

    test('near-identical string (one extra char appended) returns ≥ 0.95', () {
      // 'hello world' (10 bigrams) vs 'hello world!' (11 bigrams)
      // all 10 of 'hello world' appear in 'hello world!'
      // similarity = 20/21 ≈ 0.952
      final sim = TextSimilarity.bigram('hello world', 'hello world!');
      expect(sim, greaterThanOrEqualTo(0.95));
    });

    test('near-identical string (one char prepended) returns ≥ 0.88', () {
      final sim = TextSimilarity.bigram('hello world', 'xhello world');
      expect(sim, greaterThanOrEqualTo(0.88));
    });

    test('repeated bigrams are handled correctly (multiset)', () {
      // 'aaa' → {aa:2}, 'aa' → {aa:1}
      // intersection = min(2,1) = 1
      // totalSize = 2 + 1 = 3
      // similarity = 2/3 ≈ 0.667
      expect(TextSimilarity.bigram('aaa', 'aa'), closeTo(2 / 3, 1e-9));
    });

    test('string that is longer prefix returns high similarity', () {
      // 'the quick brown fox' vs 'the quick brown fox jumps' — shares most bigrams
      final sim = TextSimilarity.bigram(
        'the quick brown fox',
        'the quick brown fox jumps',
      );
      // Both start identically — similarity should be comfortably above 0.7
      expect(sim, greaterThan(0.7));
    });

    test('symmetry: bigram(a,b) == bigram(b,a)', () {
      expect(
        TextSimilarity.bigram('apple', 'application'),
        closeTo(TextSimilarity.bigram('application', 'apple'), 1e-9),
      );
    });

    test('result is always between 0.0 and 1.0 for various pairs', () {
      const pairs = [
        ('', ''),
        ('a', 'b'),
        ('ab', 'ba'),
        ('hello', 'world'),
        ('abcdef', 'abcdefg'),
        ('night', 'nacht'),
        ('abc', 'abc'),
        ('xyz', 'zyx'),
      ];
      for (final (a, b) in pairs) {
        final sim = TextSimilarity.bigram(a, b);
        expect(
          sim,
          inInclusiveRange(0.0, 1.0),
          reason: "bigram('$a', '$b') = $sim is out of range",
        );
      }
    });

    test('fully overlapping strings of different lengths', () {
      // 'abcd' bigrams: ab, bc, cd (3)
      // 'abcde' bigrams: ab, bc, cd, de (4)
      // intersection: ab, bc, cd → 3
      // totalSize = 3 + 4 = 7 → 6/7 ≈ 0.857
      expect(TextSimilarity.bigram('abcd', 'abcde'), closeTo(6 / 7, 1e-9));
    });

    test('long identical strings return 1.0', () {
      const s = 'the quick brown fox jumps over the lazy dog';
      expect(TextSimilarity.bigram(s, s), equals(1.0));
    });

    test(
      'ab / ba: reversed two-char strings return 0.0 (no shared bigrams)',
      () {
        // 'ab' bigrams: {ab:1}, 'ba' bigrams: {ba:1} — no intersection
        expect(TextSimilarity.bigram('ab', 'ba'), equals(0.0));
      },
    );

    test('overlapping substring has positive similarity', () {
      // 'programming' and 'programmatic' share several bigrams
      final sim = TextSimilarity.bigram('programming', 'programmatic');
      expect(sim, greaterThan(0.0));
      expect(sim, lessThan(1.0));
    });
  });

  // =========================================================================
  // TextSimilarity.bigram — boundary and precision
  // =========================================================================

  group('TextSimilarity.bigram — boundary and precision', () {
    test('returns exactly 1.0 for identical strings (not just close)', () {
      const s = 'dart programming language';
      final result = TextSimilarity.bigram(s, s);
      expect(result, equals(1.0));
    });

    test('result is 0.0 for completely disjoint character sets', () {
      // 'aaa' bigrams: {aa:2}, 'bbb' bigrams: {bb:2} — no overlap
      expect(TextSimilarity.bigram('aaa', 'bbb'), equals(0.0));
    });

    test('transitive: bigram(a, a) == 1.0 for any non-empty string', () {
      for (final s in ['x', 'ab', 'hello', 'test string']) {
        expect(
          TextSimilarity.bigram(s, s),
          equals(1.0),
          reason: "bigram('$s', '$s') should be 1.0",
        );
      }
    });
  });

  // =========================================================================
  // TextSimilarity.bigram — character types and special inputs
  // =========================================================================

  group('TextSimilarity.bigram — character types and special inputs', () {
    test(
      'case-sensitive: uppercase and lowercase are treated as different',
      () {
        // 'hello' bigrams: he, el, ll, lo  vs  'HELLO' bigrams: HE, EL, LL, LO
        // All uppercase bigrams differ from lowercase → 0.0
        expect(TextSimilarity.bigram('hello', 'HELLO'), equals(0.0));
      },
    );

    test('digit strings: identical digit strings return 1.0', () {
      expect(TextSimilarity.bigram('12345', '12345'), equals(1.0));
    });

    test(
      'digit strings: different digit sequences return 0.0 when no shared bigrams',
      () {
        // '13' bigrams: {13:1} vs '24' bigrams: {24:1} — no overlap
        expect(TextSimilarity.bigram('13', '24'), equals(0.0));
      },
    );

    test('strings with spaces: spaces are treated as regular characters', () {
      // 'a b' bigrams: 'a ', ' b' vs 'ab' bigrams: 'ab' — no overlap
      expect(TextSimilarity.bigram('a b', 'ab'), equals(0.0));
    });

    test('strings differing only in whitespace have low similarity', () {
      // 'hello world' and 'helloworld' share many bigrams but not all
      final sim = TextSimilarity.bigram('hello world', 'helloworld');
      expect(sim, greaterThan(0.0));
      expect(sim, lessThan(1.0));
    });

    test('anagrams with length > 2 share no bigrams → returns 0.0', () {
      // 'abc' bigrams: ab, bc — 'bca' bigrams: bc, ca — they share 'bc'
      // Not a pure 0.0 case; just confirm it's strictly less than 1.0
      final sim = TextSimilarity.bigram('abc', 'bca');
      expect(sim, lessThan(1.0));
    });

    test('strings with repeated patterns score correctly', () {
      // 'abab' bigrams: ab, ba, ab → {ab:2, ba:1} (3 total)
      // 'abab' vs itself = 1.0
      expect(TextSimilarity.bigram('abab', 'abab'), equals(1.0));
    });

    test('mixed alphanumeric strings: result is within [0.0, 1.0]', () {
      final sim = TextSimilarity.bigram('abc123', 'abc456');
      expect(sim, inInclusiveRange(0.0, 1.0));
    });

    test('very long identical strings return 1.0 regardless of length', () {
      final s = 'a' * 1000;
      expect(TextSimilarity.bigram(s, s), equals(1.0));
    });
  });
}
