import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

void main() {
  group('LoopDetectionConfig', () {
    // ── Defaults ──────────────────────────────────────────────────────────

    group('defaults', () {
      late LoopDetectionConfig config;

      setUp(() {
        config = const LoopDetectionConfig();
      });

      test('maxConsecutiveIdenticalToolCalls defaults to 3', () {
        expect(config.maxConsecutiveIdenticalToolCalls, equals(3));
      });

      test('maxConsecutiveIdenticalOutputs defaults to 3', () {
        expect(config.maxConsecutiveIdenticalOutputs, equals(3));
      });

      test('similarityThreshold defaults to 0.85', () {
        expect(config.similarityThreshold, equals(0.85));
      });

      test('can be instantiated with const', () {
        // Verify the const constructor works at compile time and runtime.
        const c1 = LoopDetectionConfig();
        const c2 = LoopDetectionConfig();
        expect(identical(c1, c2), isTrue,
            reason: 'const instances with same args should be identical');
      });
    });

    // ── Custom values ─────────────────────────────────────────────────────

    group('custom values', () {
      test('accepts custom maxConsecutiveIdenticalToolCalls', () {
        const config = LoopDetectionConfig(maxConsecutiveIdenticalToolCalls: 5);
        expect(config.maxConsecutiveIdenticalToolCalls, equals(5));
        // Other fields keep defaults.
        expect(config.maxConsecutiveIdenticalOutputs, equals(3));
        expect(config.similarityThreshold, equals(0.85));
      });

      test('accepts custom maxConsecutiveIdenticalOutputs', () {
        const config = LoopDetectionConfig(maxConsecutiveIdenticalOutputs: 7);
        expect(config.maxConsecutiveIdenticalOutputs, equals(7));
        // Other fields keep defaults.
        expect(config.maxConsecutiveIdenticalToolCalls, equals(3));
        expect(config.similarityThreshold, equals(0.85));
      });

      test('accepts custom similarityThreshold', () {
        const config = LoopDetectionConfig(similarityThreshold: 0.95);
        expect(config.similarityThreshold, equals(0.95));
        // Other fields keep defaults.
        expect(config.maxConsecutiveIdenticalToolCalls, equals(3));
        expect(config.maxConsecutiveIdenticalOutputs, equals(3));
      });

      test('accepts similarityThreshold of 0.0', () {
        const config = LoopDetectionConfig(similarityThreshold: 0.0);
        expect(config.similarityThreshold, equals(0.0));
      });

      test('accepts similarityThreshold of 1.0', () {
        const config = LoopDetectionConfig(similarityThreshold: 1.0);
        expect(config.similarityThreshold, equals(1.0));
      });

      test('accepts all custom values simultaneously', () {
        const config = LoopDetectionConfig(
          maxConsecutiveIdenticalToolCalls: 2,
          maxConsecutiveIdenticalOutputs: 4,
          similarityThreshold: 0.9,
        );
        expect(config.maxConsecutiveIdenticalToolCalls, equals(2));
        expect(config.maxConsecutiveIdenticalOutputs, equals(4));
        expect(config.similarityThreshold, equals(0.9));
      });

      test('accepts large threshold values', () {
        const config = LoopDetectionConfig(
          maxConsecutiveIdenticalToolCalls: 100,
          maxConsecutiveIdenticalOutputs: 50,
        );
        expect(config.maxConsecutiveIdenticalToolCalls, equals(100));
        expect(config.maxConsecutiveIdenticalOutputs, equals(50));
      });

      test('accepts threshold value of 1 (minimum meaningful threshold)', () {
        const config = LoopDetectionConfig(
          maxConsecutiveIdenticalToolCalls: 1,
          maxConsecutiveIdenticalOutputs: 1,
        );
        expect(config.maxConsecutiveIdenticalToolCalls, equals(1));
        expect(config.maxConsecutiveIdenticalOutputs, equals(1));
      });
    });

    // ── Equality ──────────────────────────────────────────────────────────

    group('equality (==)', () {
      test('an object is equal to itself', () {
        const config = LoopDetectionConfig();
        expect(config, equals(config));
      });

      test('two default configs are equal', () {
        const a = LoopDetectionConfig();
        const b = LoopDetectionConfig();
        expect(a, equals(b));
      });

      test('two configs with identical custom values are equal', () {
        const a = LoopDetectionConfig(
          maxConsecutiveIdenticalToolCalls: 5,
          maxConsecutiveIdenticalOutputs: 2,
          similarityThreshold: 0.9,
        );
        const b = LoopDetectionConfig(
          maxConsecutiveIdenticalToolCalls: 5,
          maxConsecutiveIdenticalOutputs: 2,
          similarityThreshold: 0.9,
        );
        expect(a, equals(b));
      });

      test('configs differ when maxConsecutiveIdenticalToolCalls differs', () {
        const a = LoopDetectionConfig(maxConsecutiveIdenticalToolCalls: 3);
        const b = LoopDetectionConfig(maxConsecutiveIdenticalToolCalls: 5);
        expect(a, isNot(equals(b)));
      });

      test('configs differ when maxConsecutiveIdenticalOutputs differs', () {
        const a = LoopDetectionConfig(maxConsecutiveIdenticalOutputs: 3);
        const b = LoopDetectionConfig(maxConsecutiveIdenticalOutputs: 5);
        expect(a, isNot(equals(b)));
      });

      test('configs differ when similarityThreshold differs', () {
        const a = LoopDetectionConfig(similarityThreshold: 0.85);
        const b = LoopDetectionConfig(similarityThreshold: 0.95);
        expect(a, isNot(equals(b)));
      });

      test('config is not equal to null', () {
        const config = LoopDetectionConfig();
        // ignore: unnecessary_null_comparison
        expect(config == null, isFalse);
      });

      test('config is not equal to an unrelated object', () {
        const config = LoopDetectionConfig();
        // ignore: unrelated_type_equality_checks
        expect(config == 'LoopDetectionConfig', isFalse);
      });
    });

    // ── hashCode ──────────────────────────────────────────────────────────

    group('hashCode', () {
      test('equal configs have the same hashCode', () {
        const a = LoopDetectionConfig(
          maxConsecutiveIdenticalToolCalls: 5,
          maxConsecutiveIdenticalOutputs: 2,
          similarityThreshold: 0.9,
        );
        const b = LoopDetectionConfig(
          maxConsecutiveIdenticalToolCalls: 5,
          maxConsecutiveIdenticalOutputs: 2,
          similarityThreshold: 0.9,
        );
        expect(a.hashCode, equals(b.hashCode));
      });

      test('default configs have consistent hashCode across calls', () {
        const config = LoopDetectionConfig();
        expect(config.hashCode, equals(config.hashCode));
      });

      test('different configs typically produce different hashCodes', () {
        const a = LoopDetectionConfig(maxConsecutiveIdenticalToolCalls: 3);
        const b = LoopDetectionConfig(maxConsecutiveIdenticalToolCalls: 5);
        // Hash collision is theoretically possible but extremely unlikely here.
        expect(a.hashCode, isNot(equals(b.hashCode)));
      });
    });

    // ── toString ──────────────────────────────────────────────────────────

    group('toString', () {
      test('contains the class name', () {
        const config = LoopDetectionConfig();
        expect(config.toString(), contains('LoopDetectionConfig'));
      });

      test('contains maxConsecutiveIdenticalToolCalls value', () {
        const config = LoopDetectionConfig(maxConsecutiveIdenticalToolCalls: 7);
        expect(config.toString(), contains('7'));
      });

      test('contains maxConsecutiveIdenticalOutputs value', () {
        const config = LoopDetectionConfig(maxConsecutiveIdenticalOutputs: 9);
        expect(config.toString(), contains('9'));
      });

      test('contains similarityThreshold value', () {
        const config = LoopDetectionConfig(similarityThreshold: 0.99);
        expect(config.toString(), contains('0.99'));
      });

      test('toString format matches expected pattern', () {
        const config = LoopDetectionConfig(
          maxConsecutiveIdenticalToolCalls: 3,
          maxConsecutiveIdenticalOutputs: 3,
          similarityThreshold: 0.85,
        );
        expect(
          config.toString(),
          equals(
            'LoopDetectionConfig('
            'maxConsecutiveIdenticalToolCalls: 3, '
            'maxConsecutiveIdenticalOutputs: 3, '
            'similarityThreshold: 0.85)',
          ),
        );
      });
    });
  });
}
