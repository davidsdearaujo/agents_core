import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

void main() {
  group('AgentsCoreException', () {
    group('construction', () {
      test('can be instantiated with a message', () {
        final exception = AgentsCoreException('something went wrong');
        expect(exception, isNotNull);
      });

      test('can be instantiated with an empty message', () {
        final exception = AgentsCoreException('');
        expect(exception, isNotNull);
      });

      test('stores the provided message', () {
        const message = 'an error occurred in agents_core';
        final exception = AgentsCoreException(message);
        expect(exception.message, equals(message));
      });
    });

    group('implements Exception', () {
      test('is an instance of Exception', () {
        final exception = AgentsCoreException('test');
        expect(exception, isA<Exception>());
      });

      test('can be caught as Exception', () {
        expect(
          () => throw AgentsCoreException('thrown'),
          throwsA(isA<Exception>()),
        );
      });

      test('can be caught as AgentsCoreException', () {
        expect(
          () => throw AgentsCoreException('thrown'),
          throwsA(isA<AgentsCoreException>()),
        );
      });
    });

    group('toString()', () {
      test('includes the message in string representation', () {
        const message = 'descriptive error message';
        final exception = AgentsCoreException(message);
        expect(exception.toString(), contains(message));
      });

      test('returns a non-empty string', () {
        final exception = AgentsCoreException('any message');
        expect(exception.toString(), isNotEmpty);
      });
    });

    group('subclassing', () {
      test('can be extended by a concrete exception subclass', () {
        final sub = _ConcreteException('sub error');
        expect(sub, isA<AgentsCoreException>());
        expect(sub, isA<Exception>());
        expect(sub.message, equals('sub error'));
      });

      test('subclass can be caught as AgentsCoreException', () {
        expect(
          () => throw _ConcreteException('thrown by subclass'),
          throwsA(isA<AgentsCoreException>()),
        );
      });

      test('subclass can be caught as Exception', () {
        expect(
          () => throw _ConcreteException('thrown by subclass'),
          throwsA(isA<Exception>()),
        );
      });

      test('subclass can override toString()', () {
        final sub = _ConcreteExceptionWithOverride('custom msg');
        expect(sub.toString(), contains('ConcreteOverride'));
        expect(sub.toString(), contains('custom msg'));
      });
    });

    group('equality and identity', () {
      test('two exceptions with the same message are distinct instances', () {
        const message = 'same message';
        final e1 = AgentsCoreException(message);
        final e2 = AgentsCoreException(message);
        expect(identical(e1, e2), isFalse);
      });
    });
  });
}

/// A minimal concrete subclass used only in tests.
class _ConcreteException extends AgentsCoreException {
  _ConcreteException(super.message);
}

/// A concrete subclass that overrides [toString] — used to verify
/// that subclasses are free to customise their string representation.
class _ConcreteExceptionWithOverride extends AgentsCoreException {
  _ConcreteExceptionWithOverride(super.message);

  @override
  String toString() => 'ConcreteOverride: $message';
}
