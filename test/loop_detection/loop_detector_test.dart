import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a [ToolCall] with the given [name] and optional [arguments].
ToolCall _tc(String name, {String arguments = '{}'}) => ToolCall(
  function: ToolCallFunction(name: name, arguments: arguments),
);

/// Creates a [LoopDetector] with the given thresholds (defaults match
/// [LoopDetectionConfig] defaults).
LoopDetector _detector({
  int toolThreshold = 3,
  int outputThreshold = 3,
  double similarity = 0.85,
}) => LoopDetector(
  config: LoopDetectionConfig(
    maxConsecutiveIdenticalToolCalls: toolThreshold,
    maxConsecutiveIdenticalOutputs: outputThreshold,
    similarityThreshold: similarity,
  ),
);

void main() {
  // =========================================================================
  // LoopCheckResult
  // =========================================================================

  group('LoopCheckResult', () {
    test('ok constant has isLooping = false', () {
      expect(LoopCheckResult.ok.isLooping, isFalse);
    });

    test('ok constant has reason = null', () {
      expect(LoopCheckResult.ok.reason, isNull);
    });

    test('loop result has isLooping = true', () {
      const result = LoopCheckResult(isLooping: true, reason: 'duplicate');
      expect(result.isLooping, isTrue);
    });

    test('loop result exposes reason', () {
      const result = LoopCheckResult(isLooping: true, reason: 'repeat');
      expect(result.reason, equals('repeat'));
    });

    test('non-loop result with no reason', () {
      const result = LoopCheckResult(isLooping: false);
      expect(result.isLooping, isFalse);
      expect(result.reason, isNull);
    });

    group('toString', () {
      test('ok includes isLooping=false and no reason', () {
        expect(LoopCheckResult.ok.toString(), contains('false'));
        expect(LoopCheckResult.ok.toString(), isNot(contains('reason')));
      });

      test('loop result includes isLooping=true and reason', () {
        const result = LoopCheckResult(isLooping: true, reason: 'repeated');
        final s = result.toString();
        expect(s, contains('true'));
        expect(s, contains('repeated'));
      });
    });
  });

  // =========================================================================
  // LoopDetector — constructor
  // =========================================================================

  group('LoopDetector — constructor', () {
    test('stores config', () {
      const config = LoopDetectionConfig(
        maxConsecutiveIdenticalToolCalls: 5,
        maxConsecutiveIdenticalOutputs: 2,
        similarityThreshold: 0.9,
      );
      final detector = LoopDetector(config: config);
      expect(detector.config, equals(config));
    });
  });

  // =========================================================================
  // TextSimilarity.bigram — edge cases (used internally by LoopDetector)
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
  });

  // =========================================================================
  // TextSimilarity.bigram — bigram computation
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

    test('near-identical string (one char prepended) returns ≥ 0.95', () {
      final sim = TextSimilarity.bigram('hello world', 'xhello world');
      expect(sim, greaterThanOrEqualTo(0.88));
    });

    test('repeated bigrams are handled (multiset)', () {
      // 'aaa' → {aa:2}, 'aa' → {aa:1}
      // intersection = min(2,1) = 1
      // totalSize = 2 + 1 = 3
      // similarity = 2/3 ≈ 0.667
      expect(TextSimilarity.bigram('aaa', 'aa'), closeTo(2 / 3, 1e-9));
    });

    test('string with whitespace difference has high similarity', () {
      // 'the quick fox' vs 'the  quick fox' (double space) — shares most bigrams
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

    test('result is always between 0.0 and 1.0', () {
      const pairs = [
        ('', ''),
        ('a', 'b'),
        ('ab', 'ba'),
        ('hello', 'world'),
        ('abcdef', 'abcdefg'),
        ('night', 'nacht'),
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
  });

  // =========================================================================
  // recordToolCalls
  // =========================================================================

  group('recordToolCalls', () {
    late LoopDetector detector;

    setUp(() => detector = _detector());

    test('null records empty fingerprint — no loop below threshold', () {
      // Record null twice and check: below threshold of 3.
      detector.recordToolCalls(null);
      detector.recordToolCalls(null);
      expect(detector.check().isLooping, isFalse);
    });

    test('empty list records empty fingerprint', () {
      // Even if 3 empty fingerprints are recorded, last.isNotEmpty is false.
      detector.recordToolCalls([]);
      detector.recordToolCalls([]);
      detector.recordToolCalls([]);
      final result = detector.check();
      expect(
        result.isLooping,
        isFalse,
        reason: 'empty fingerprints should not trigger loop detection',
      );
    });

    test('single tool call creates non-empty fingerprint', () {
      // Record the same single-call 3× → should trigger.
      final call = _tc('get_weather', arguments: '{"city":"NYC"}');
      detector.recordToolCalls([call]);
      detector.recordToolCalls([call]);
      detector.recordToolCalls([call]);
      expect(detector.check().isLooping, isTrue);
    });

    test('multiple tool calls create a combined fingerprint', () {
      final calls = [
        _tc('read_file', arguments: '{"path":"/tmp/x"}'),
        _tc('write_file', arguments: '{"path":"/tmp/y"}'),
      ];
      // Record same sequence 3×.
      detector.recordToolCalls(calls);
      detector.recordToolCalls(calls);
      detector.recordToolCalls(calls);
      expect(detector.check().isLooping, isTrue);
    });

    test('reordered tool calls produce the same fingerprint', () {
      final callsAB = [
        _tc('alpha', arguments: '1'),
        _tc('beta', arguments: '2'),
      ];
      final callsBA = [
        _tc('beta', arguments: '2'),
        _tc('alpha', arguments: '1'),
      ];
      // AB, BA, AB — all produce the same sorted fingerprint.
      detector.recordToolCalls(callsAB);
      detector.recordToolCalls(callsBA);
      detector.recordToolCalls(callsAB);
      expect(detector.check().isLooping, isTrue);
    });

    test('different tool-call sequences do not trigger loop', () {
      detector.recordToolCalls([_tc('func_a')]);
      detector.recordToolCalls([_tc('func_b')]);
      detector.recordToolCalls([_tc('func_a')]);
      expect(detector.check().isLooping, isFalse);
    });
  });

  // =========================================================================
  // recordOutput
  // =========================================================================

  group('recordOutput', () {
    late LoopDetector detector;

    setUp(() => detector = _detector());

    test('null records empty string — no loop even above threshold', () {
      // 3 null outputs → fingerprint is '' for each → last.isNotEmpty is false.
      detector.recordOutput(null);
      detector.recordOutput(null);
      detector.recordOutput(null);
      expect(detector.check().isLooping, isFalse);
    });

    test('empty string records empty fingerprint — no loop', () {
      detector.recordOutput('');
      detector.recordOutput('');
      detector.recordOutput('');
      expect(detector.check().isLooping, isFalse);
    });

    test('non-empty string is recorded', () {
      detector.recordOutput('some output');
      detector.recordOutput('some output');
      detector.recordOutput('some output');
      expect(detector.check().isLooping, isTrue);
    });
  });

  // =========================================================================
  // check() — tool-call threshold behaviour
  // =========================================================================

  group('check() — tool-call threshold', () {
    test('returns ok when history count is 0 (below threshold of 3)', () {
      final detector = _detector(toolThreshold: 3);
      // No records → ok.
      expect(detector.check(), equals(LoopCheckResult.ok));
    });

    test('returns ok when history is below threshold', () {
      final detector = _detector(toolThreshold: 3);
      final call = _tc('fn');
      detector.recordToolCalls([call]);
      detector.recordToolCalls([call]);
      // 2 records < threshold of 3 → ok.
      expect(detector.check().isLooping, isFalse);
    });

    test('detects loop at exactly the threshold', () {
      final detector = _detector(toolThreshold: 3);
      final call = _tc('fn');
      detector.recordToolCalls([call]);
      detector.recordToolCalls([call]);
      detector.recordToolCalls([call]);
      // Exactly 3 identical records == threshold → loop.
      expect(detector.check().isLooping, isTrue);
    });

    test('detects loop above threshold (uses last N entries)', () {
      final detector = _detector(toolThreshold: 3);
      final call = _tc('fn');
      // 5 identical records — last 3 are still identical.
      for (var i = 0; i < 5; i++) {
        detector.recordToolCalls([call]);
      }
      expect(detector.check().isLooping, isTrue);
    });

    test('no loop when recent window contains a different entry', () {
      final detector = _detector(toolThreshold: 3);
      detector.recordToolCalls([_tc('fn')]);
      detector.recordToolCalls([_tc('fn')]);
      detector.recordToolCalls([_tc('other')]); // breaks the run
      expect(detector.check().isLooping, isFalse);
    });

    test('detects loop after a break when last N are identical again', () {
      final detector = _detector(toolThreshold: 3);
      final call = _tc('fn');
      detector.recordToolCalls([_tc('other')]);
      detector.recordToolCalls([call]);
      detector.recordToolCalls([call]);
      detector.recordToolCalls([call]);
      // Last 3 are identical → loop.
      expect(detector.check().isLooping, isTrue);
    });

    test('threshold = 1: any single non-empty call triggers loop', () {
      final detector = _detector(toolThreshold: 1);
      detector.recordToolCalls([_tc('fn')]);
      expect(detector.check().isLooping, isTrue);
    });

    test('threshold = 2: two identical calls trigger, one does not', () {
      final detector = _detector(toolThreshold: 2);
      final call = _tc('fn');
      detector.recordToolCalls([call]);
      expect(detector.check().isLooping, isFalse);
      detector.recordToolCalls([call]);
      expect(detector.check().isLooping, isTrue);
    });

    test('reason message contains the threshold count', () {
      final detector = _detector(toolThreshold: 3);
      final call = _tc('fn');
      for (var i = 0; i < 3; i++) {
        detector.recordToolCalls([call]);
      }
      final result = detector.check();
      expect(result.reason, contains('3'));
    });

    test('reason mentions tool-call sequences', () {
      final detector = _detector(toolThreshold: 3);
      final call = _tc('fn');
      for (var i = 0; i < 3; i++) {
        detector.recordToolCalls([call]);
      }
      final result = detector.check();
      expect(result.reason, isNotNull);
      expect(result.reason, contains('tool'));
    });

    test('null function in ToolCall does not crash fingerprint building', () {
      // ToolCall without a function field.
      final noFunc = ToolCall(id: 'x');
      final detector = _detector(toolThreshold: 3);
      detector.recordToolCalls([noFunc]);
      detector.recordToolCalls([noFunc]);
      detector.recordToolCalls([noFunc]);
      // Fingerprint = ':' (empty name + empty args) joined → ':',
      // which IS non-empty → loop detected.
      expect(detector.check().isLooping, isTrue);
    });
  });

  // =========================================================================
  // check() — output threshold behaviour
  // =========================================================================

  group('check() — output threshold', () {
    test('returns ok when history count is 0 (below threshold of 3)', () {
      final detector = _detector(outputThreshold: 3);
      expect(detector.check(), equals(LoopCheckResult.ok));
    });

    test('returns ok when history is below threshold', () {
      final detector = _detector(outputThreshold: 3);
      detector.recordOutput('some output');
      detector.recordOutput('some output');
      expect(detector.check().isLooping, isFalse);
    });

    test('detects loop at exactly the threshold with identical outputs', () {
      final detector = _detector(outputThreshold: 3);
      detector.recordOutput('some output');
      detector.recordOutput('some output');
      detector.recordOutput('some output');
      expect(detector.check().isLooping, isTrue);
    });

    test('detects loop above threshold (uses last N outputs)', () {
      final detector = _detector(outputThreshold: 3);
      for (var i = 0; i < 5; i++) {
        detector.recordOutput('same output');
      }
      expect(detector.check().isLooping, isTrue);
    });

    test('no loop when last output is empty string', () {
      final detector = _detector(outputThreshold: 3);
      detector.recordOutput('text');
      detector.recordOutput('text');
      detector.recordOutput(''); // last is empty
      expect(detector.check().isLooping, isFalse);
    });

    test('detects loop with near-identical outputs above threshold', () {
      // Default similarity threshold is 0.85.
      // 'hello world' vs 'hello world!' has similarity ≈ 0.952 → above 0.85.
      final detector = _detector(outputThreshold: 3, similarity: 0.85);
      detector.recordOutput('hello world');
      detector.recordOutput('hello world!');
      detector.recordOutput('hello world');
      // Each pair: bigramSimilarity('hello world', 'hello world') = 1.0 ≥ 0.85
      // bigramSimilarity('hello world!', 'hello world') ≈ 0.952 ≥ 0.85
      expect(detector.check().isLooping, isTrue);
    });

    test('no loop when outputs are below similarity threshold', () {
      // Use high similarity threshold (0.99) → near-identical but not equal.
      final detector = _detector(outputThreshold: 3, similarity: 0.99);
      detector.recordOutput('hello world');
      detector.recordOutput('hello world!!'); // slightly different
      detector.recordOutput('hello world!!!'); // slightly different
      // bigramSimilarity of these strings < 0.99 → no loop.
      expect(detector.check().isLooping, isFalse);
    });

    test('no loop for completely different outputs even at threshold', () {
      final detector = _detector(outputThreshold: 3, similarity: 0.85);
      detector.recordOutput('hello world');
      detector.recordOutput('completely different');
      detector.recordOutput('totally unrelated text');
      expect(detector.check().isLooping, isFalse);
    });

    test('similarityThreshold = 0.0 matches any non-empty output', () {
      // With threshold 0.0: bigramSimilarity(a, b) >= 0.0 is always true.
      // Even completely different non-empty strings match.
      final detector = _detector(outputThreshold: 3, similarity: 0.0);
      detector.recordOutput('hello');
      detector.recordOutput('world');
      detector.recordOutput('foobar');
      expect(detector.check().isLooping, isTrue);
    });

    test('similarityThreshold = 0.0 does not match empty outputs', () {
      // reference.isNotEmpty guard still applies.
      final detector = _detector(outputThreshold: 3, similarity: 0.0);
      detector.recordOutput('hello');
      detector.recordOutput('world');
      detector.recordOutput(''); // last is empty → no loop
      expect(detector.check().isLooping, isFalse);
    });

    test('similarityThreshold = 1.0 only matches exact strings', () {
      final detector = _detector(outputThreshold: 3, similarity: 1.0);
      // Exact duplicates → loop.
      detector.recordOutput('exact');
      detector.recordOutput('exact');
      detector.recordOutput('exact');
      expect(detector.check().isLooping, isTrue);
    });

    test('similarityThreshold = 1.0 does not match near-identical strings', () {
      final detector = _detector(outputThreshold: 3, similarity: 1.0);
      detector.recordOutput('hello world');
      detector.recordOutput('hello world!'); // not identical
      detector.recordOutput(
        'hello world',
      ); // identical to first but not all same
      // 'hello world' vs 'hello world!': bigramSimilarity < 1.0 → no loop
      expect(detector.check().isLooping, isFalse);
    });

    test('threshold = 1: single non-empty output triggers loop', () {
      final detector = _detector(outputThreshold: 1, similarity: 0.85);
      detector.recordOutput('any output');
      expect(detector.check().isLooping, isTrue);
    });

    test('threshold = 2: two similar outputs trigger, one does not', () {
      final detector = _detector(outputThreshold: 2, similarity: 0.85);
      detector.recordOutput('same output');
      expect(detector.check().isLooping, isFalse);
      detector.recordOutput('same output');
      expect(detector.check().isLooping, isTrue);
    });

    test('reason message contains the threshold count', () {
      final detector = _detector(outputThreshold: 3, similarity: 0.85);
      for (var i = 0; i < 3; i++) {
        detector.recordOutput('same output');
      }
      final result = detector.check();
      expect(result.reason, contains('3'));
    });

    test('reason message contains the similarity threshold value', () {
      final detector = _detector(outputThreshold: 3, similarity: 0.85);
      for (var i = 0; i < 3; i++) {
        detector.recordOutput('same output');
      }
      final result = detector.check();
      expect(result.reason, contains('0.85'));
    });

    test('reason mentions output', () {
      final detector = _detector(outputThreshold: 3, similarity: 0.85);
      for (var i = 0; i < 3; i++) {
        detector.recordOutput('same output');
      }
      final result = detector.check();
      expect(result.reason, isNotNull);
      expect(result.reason, contains('output'));
    });
  });

  // =========================================================================
  // check() — tool calls vs outputs are independent
  // =========================================================================

  group('check() — tool-call and output tracking are independent', () {
    test('recording tool calls does not affect output history', () {
      final detector = _detector(toolThreshold: 3, outputThreshold: 3);
      final call = _tc('fn');
      // 3 identical tool-call sequences → tool-call loop.
      detector.recordToolCalls([call]);
      detector.recordToolCalls([call]);
      detector.recordToolCalls([call]);
      // But output history is empty → output loop not triggered.
      // Overall: loop detected (from tool calls).
      expect(detector.check().isLooping, isTrue);
      expect(detector.check().reason, contains('tool'));
    });

    test('recording outputs does not affect tool-call history', () {
      final detector = _detector(toolThreshold: 3, outputThreshold: 3);
      // 3 identical outputs → output loop.
      detector.recordOutput('same');
      detector.recordOutput('same');
      detector.recordOutput('same');
      // But tool-call history is empty → tool-call loop not triggered.
      // Overall: loop detected (from outputs).
      expect(detector.check().isLooping, isTrue);
      expect(detector.check().reason, contains('output'));
    });

    test('tool-call loop takes precedence over output loop', () {
      final detector = _detector(toolThreshold: 3, outputThreshold: 3);
      final call = _tc('fn');
      // Both conditions satisfied simultaneously.
      detector.recordToolCalls([call]);
      detector.recordToolCalls([call]);
      detector.recordToolCalls([call]);
      detector.recordOutput('same');
      detector.recordOutput('same');
      detector.recordOutput('same');
      // Tool-call check runs first in check().
      final result = detector.check();
      expect(result.isLooping, isTrue);
      expect(result.reason, contains('tool'));
    });
  });

  // =========================================================================
  // reset()
  // =========================================================================

  group('reset()', () {
    test('clears tool-call history — check returns ok after reset', () {
      final detector = _detector(toolThreshold: 3);
      final call = _tc('fn');
      detector.recordToolCalls([call]);
      detector.recordToolCalls([call]);
      detector.recordToolCalls([call]);
      expect(detector.check().isLooping, isTrue); // sanity

      detector.reset();
      expect(detector.check().isLooping, isFalse);
    });

    test('clears output history — check returns ok after reset', () {
      final detector = _detector(outputThreshold: 3);
      detector.recordOutput('same');
      detector.recordOutput('same');
      detector.recordOutput('same');
      expect(detector.check().isLooping, isTrue); // sanity

      detector.reset();
      expect(detector.check().isLooping, isFalse);
    });

    test('allows re-detection after a reset', () {
      final detector = _detector(toolThreshold: 3);
      final call = _tc('fn');

      // First loop detected.
      for (var i = 0; i < 3; i++) {
        detector.recordToolCalls([call]);
      }
      expect(detector.check().isLooping, isTrue);

      // Reset, then build up again.
      detector.reset();
      for (var i = 0; i < 3; i++) {
        detector.recordToolCalls([call]);
      }
      expect(detector.check().isLooping, isTrue);
    });

    test('reset on empty detector is a no-op', () {
      final detector = _detector();
      expect(() => detector.reset(), returnsNormally);
      expect(detector.check().isLooping, isFalse);
    });

    test('clears both tool-call and output history', () {
      final detector = _detector(toolThreshold: 3, outputThreshold: 3);
      final call = _tc('fn');

      for (var i = 0; i < 3; i++) {
        detector.recordToolCalls([call]);
        detector.recordOutput('same');
      }
      expect(detector.check().isLooping, isTrue); // sanity

      detector.reset();
      // Neither tool calls nor outputs trigger loop.
      expect(detector.check().isLooping, isFalse);

      // Now add < threshold entries to confirm history was truly cleared.
      detector.recordToolCalls([call]);
      detector.recordOutput('same');
      expect(detector.check().isLooping, isFalse);
    });
  });

  // =========================================================================
  // Integration: realistic multi-step scenario
  // =========================================================================

  group('integration — realistic agent loop scenario', () {
    test('gradually accumulating identical tool calls triggers detection', () {
      final detector = _detector(toolThreshold: 3, outputThreshold: 3);
      final call = _tc('search', arguments: '{"query":"dart"}');

      // First two calls — no loop yet.
      detector.recordToolCalls([call]);
      detector.recordOutput('Search result A');
      expect(detector.check().isLooping, isFalse);

      detector.recordToolCalls([call]);
      detector.recordOutput('Search result B'); // slightly different output
      expect(detector.check().isLooping, isFalse);

      // Third identical tool call — loop detected on tool calls.
      detector.recordToolCalls([call]);
      detector.recordOutput(
        'Search result C',
      ); // different output, no output loop
      expect(detector.check().isLooping, isTrue);
    });

    test('interleaved different calls delay or prevent detection', () {
      final detector = _detector(toolThreshold: 3);
      final callA = _tc('func_a');
      final callB = _tc('func_b');

      // A, A, B, A, A — last 3 are B, A, A (not identical).
      detector.recordToolCalls([callA]);
      detector.recordToolCalls([callA]);
      detector.recordToolCalls([callB]);
      detector.recordToolCalls([callA]);
      detector.recordToolCalls([callA]);
      // Last 3: B, A, A — not all equal → no loop.
      expect(detector.check().isLooping, isFalse);
    });

    test('output-based loop with high-similarity near-copies', () {
      final detector = _detector(outputThreshold: 3, similarity: 0.85);

      // Simulate an LLM churning out near-duplicate responses.
      const base = 'I need to search for information about Dart programming.';
      detector.recordOutput(base);
      detector.recordOutput('$base '); // trailing space
      detector.recordOutput('$base  '); // two trailing spaces

      // All three are very similar; expect loop detection.
      final result = detector.check();
      expect(result.isLooping, isTrue);
    });
  });
}
