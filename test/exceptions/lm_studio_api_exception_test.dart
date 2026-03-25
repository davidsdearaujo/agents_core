import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

void main() {
  group('LmStudioApiException', () {
    // ---------------------------------------------------------------------------
    // Construction
    // ---------------------------------------------------------------------------
    group('construction', () {
      test('can be instantiated with all required fields', () {
        final exception = LmStudioApiException(
          statusCode: 404,
          errorType: 'model_not_found',
          errorMessage: 'The requested model was not found',
        );
        expect(exception, isNotNull);
      });

      test('stores statusCode', () {
        final exception = LmStudioApiException(
          statusCode: 404,
          errorType: 'model_not_found',
          errorMessage: 'Not found',
        );
        expect(exception.statusCode, equals(404));
      });

      test('stores errorType', () {
        final exception = LmStudioApiException(
          statusCode: 400,
          errorType: 'context_length_exceeded',
          errorMessage: 'Context length exceeded',
        );
        expect(exception.errorType, equals('context_length_exceeded'));
      });

      test('stores errorMessage', () {
        final exception = LmStudioApiException(
          statusCode: 429,
          errorType: 'rate_limit_exceeded',
          errorMessage: 'Too many requests',
        );
        expect(exception.errorMessage, equals('Too many requests'));
      });

      test('accepts statusCode 400', () {
        final exception = LmStudioApiException(
          statusCode: 400,
          errorType: 'bad_request',
          errorMessage: 'Bad request',
        );
        expect(exception.statusCode, equals(400));
      });

      test('accepts statusCode 429', () {
        final exception = LmStudioApiException(
          statusCode: 429,
          errorType: 'rate_limited',
          errorMessage: 'Rate limited',
        );
        expect(exception.statusCode, equals(429));
      });

      test('accepts statusCode 500', () {
        final exception = LmStudioApiException(
          statusCode: 500,
          errorType: 'internal_server_error',
          errorMessage: 'Internal error',
        );
        expect(exception.statusCode, equals(500));
      });

      test('accepts empty errorType', () {
        final exception = LmStudioApiException(
          statusCode: 502,
          errorType: '',
          errorMessage: 'Bad gateway',
        );
        expect(exception.errorType, equals(''));
      });

      test('accepts empty errorMessage', () {
        final exception = LmStudioApiException(
          statusCode: 503,
          errorType: 'service_unavailable',
          errorMessage: '',
        );
        expect(exception.errorMessage, equals(''));
      });
    });

    // ---------------------------------------------------------------------------
    // Extends AgentsCoreException (and implements Exception)
    // ---------------------------------------------------------------------------
    group('extends AgentsCoreException', () {
      test('is an instance of AgentsCoreException', () {
        final exception = LmStudioApiException(
          statusCode: 400,
          errorType: 'bad_request',
          errorMessage: 'Bad request',
        );
        expect(exception, isA<AgentsCoreException>());
      });

      test('is an instance of Exception', () {
        final exception = LmStudioApiException(
          statusCode: 500,
          errorType: 'server_error',
          errorMessage: 'Internal error',
        );
        expect(exception, isA<Exception>());
      });

      test('is an instance of LmStudioApiException', () {
        final exception = LmStudioApiException(
          statusCode: 404,
          errorType: 'not_found',
          errorMessage: 'Not found',
        );
        expect(exception, isA<LmStudioApiException>());
      });

      test('can be caught as Exception', () {
        expect(
          () => throw LmStudioApiException(
            statusCode: 500,
            errorType: 'server_error',
            errorMessage: 'Internal error',
          ),
          throwsA(isA<Exception>()),
        );
      });

      test('can be caught as AgentsCoreException', () {
        expect(
          () => throw LmStudioApiException(
            statusCode: 500,
            errorType: 'server_error',
            errorMessage: 'Internal error',
          ),
          throwsA(isA<AgentsCoreException>()),
        );
      });

      test('can be caught as LmStudioApiException', () {
        expect(
          () => throw LmStudioApiException(
            statusCode: 404,
            errorType: 'model_not_found',
            errorMessage: 'Not found',
          ),
          throwsA(isA<LmStudioApiException>()),
        );
      });
    });

    // ---------------------------------------------------------------------------
    // message field (inherited from AgentsCoreException)
    // ---------------------------------------------------------------------------
    group('message field (inherited from AgentsCoreException)', () {
      test('message is non-empty', () {
        final exception = LmStudioApiException(
          statusCode: 404,
          errorType: 'model_not_found',
          errorMessage: 'Model xyz not found',
        );
        expect(exception.message, isNotEmpty);
      });

      test('message includes errorMessage content', () {
        const errorMsg = 'The model lmstudio-xyz was not found';
        final exception = LmStudioApiException(
          statusCode: 404,
          errorType: 'model_not_found',
          errorMessage: errorMsg,
        );
        expect(exception.message, contains(errorMsg));
      });
    });

    // ---------------------------------------------------------------------------
    // isModelNotFound getter
    // ---------------------------------------------------------------------------
    group('isModelNotFound getter', () {
      test('returns true for statusCode 404', () {
        final exception = LmStudioApiException(
          statusCode: 404,
          errorType: 'model_not_found',
          errorMessage: 'Model not found',
        );
        expect(exception.isModelNotFound, isTrue);
      });

      test('returns false for statusCode 400', () {
        final exception = LmStudioApiException(
          statusCode: 400,
          errorType: 'bad_request',
          errorMessage: 'Bad request',
        );
        expect(exception.isModelNotFound, isFalse);
      });

      test('returns false for statusCode 429', () {
        final exception = LmStudioApiException(
          statusCode: 429,
          errorType: 'rate_limited',
          errorMessage: 'Rate limited',
        );
        expect(exception.isModelNotFound, isFalse);
      });

      test('returns false for statusCode 500', () {
        final exception = LmStudioApiException(
          statusCode: 500,
          errorType: 'server_error',
          errorMessage: 'Internal error',
        );
        expect(exception.isModelNotFound, isFalse);
      });

      test('returns false for other non-404 status codes', () {
        for (final code in [401, 403, 422, 503]) {
          final exception = LmStudioApiException(
            statusCode: code,
            errorType: 'other_error',
            errorMessage: 'Error',
          );
          expect(
            exception.isModelNotFound,
            isFalse,
            reason: 'Expected isModelNotFound=false for status $code',
          );
        }
      });
    });

    // ---------------------------------------------------------------------------
    // isContextLengthExceeded getter
    // ---------------------------------------------------------------------------
    group('isContextLengthExceeded getter', () {
      test('returns true for statusCode 400', () {
        final exception = LmStudioApiException(
          statusCode: 400,
          errorType: 'context_length_exceeded',
          errorMessage: 'Context too long',
        );
        expect(exception.isContextLengthExceeded, isTrue);
      });

      test('returns false for statusCode 404', () {
        final exception = LmStudioApiException(
          statusCode: 404,
          errorType: 'model_not_found',
          errorMessage: 'Not found',
        );
        expect(exception.isContextLengthExceeded, isFalse);
      });

      test('returns false for statusCode 429', () {
        final exception = LmStudioApiException(
          statusCode: 429,
          errorType: 'rate_limited',
          errorMessage: 'Rate limited',
        );
        expect(exception.isContextLengthExceeded, isFalse);
      });

      test('returns false for statusCode 500', () {
        final exception = LmStudioApiException(
          statusCode: 500,
          errorType: 'server_error',
          errorMessage: 'Internal error',
        );
        expect(exception.isContextLengthExceeded, isFalse);
      });

      test('returns false for other non-400 status codes', () {
        for (final code in [401, 403, 404, 422, 429, 503]) {
          final exception = LmStudioApiException(
            statusCode: code,
            errorType: 'other_error',
            errorMessage: 'Error',
          );
          expect(
            exception.isContextLengthExceeded,
            isFalse,
            reason: 'Expected isContextLengthExceeded=false for status $code',
          );
        }
      });
    });

    // ---------------------------------------------------------------------------
    // isRateLimited getter
    // ---------------------------------------------------------------------------
    group('isRateLimited getter', () {
      test('returns true for statusCode 429', () {
        final exception = LmStudioApiException(
          statusCode: 429,
          errorType: 'rate_limit_exceeded',
          errorMessage: 'Too many requests',
        );
        expect(exception.isRateLimited, isTrue);
      });

      test('returns false for statusCode 400', () {
        final exception = LmStudioApiException(
          statusCode: 400,
          errorType: 'bad_request',
          errorMessage: 'Bad request',
        );
        expect(exception.isRateLimited, isFalse);
      });

      test('returns false for statusCode 404', () {
        final exception = LmStudioApiException(
          statusCode: 404,
          errorType: 'not_found',
          errorMessage: 'Not found',
        );
        expect(exception.isRateLimited, isFalse);
      });

      test('returns false for statusCode 500', () {
        final exception = LmStudioApiException(
          statusCode: 500,
          errorType: 'server_error',
          errorMessage: 'Internal error',
        );
        expect(exception.isRateLimited, isFalse);
      });

      test('returns false for other non-429 status codes', () {
        for (final code in [400, 401, 403, 404, 500, 503]) {
          final exception = LmStudioApiException(
            statusCode: code,
            errorType: 'other_error',
            errorMessage: 'Error',
          );
          expect(
            exception.isRateLimited,
            isFalse,
            reason: 'Expected isRateLimited=false for status $code',
          );
        }
      });
    });

    // ---------------------------------------------------------------------------
    // Convenience getter exclusivity
    // ---------------------------------------------------------------------------
    group('convenience getter exclusivity', () {
      test('only isContextLengthExceeded is true for 400', () {
        final exception = LmStudioApiException(
          statusCode: 400,
          errorType: 'bad_request',
          errorMessage: 'Bad request',
        );
        expect(exception.isContextLengthExceeded, isTrue);
        expect(exception.isModelNotFound, isFalse);
        expect(exception.isRateLimited, isFalse);
      });

      test('only isModelNotFound is true for 404', () {
        final exception = LmStudioApiException(
          statusCode: 404,
          errorType: 'not_found',
          errorMessage: 'Not found',
        );
        expect(exception.isModelNotFound, isTrue);
        expect(exception.isContextLengthExceeded, isFalse);
        expect(exception.isRateLimited, isFalse);
      });

      test('only isRateLimited is true for 429', () {
        final exception = LmStudioApiException(
          statusCode: 429,
          errorType: 'rate_limited',
          errorMessage: 'Rate limited',
        );
        expect(exception.isRateLimited, isTrue);
        expect(exception.isModelNotFound, isFalse);
        expect(exception.isContextLengthExceeded, isFalse);
      });

      test('no convenience getters are true for 500', () {
        final exception = LmStudioApiException(
          statusCode: 500,
          errorType: 'server_error',
          errorMessage: 'Internal error',
        );
        expect(exception.isModelNotFound, isFalse);
        expect(exception.isContextLengthExceeded, isFalse);
        expect(exception.isRateLimited, isFalse);
      });

      test('no convenience getters are true for 503', () {
        final exception = LmStudioApiException(
          statusCode: 503,
          errorType: 'service_unavailable',
          errorMessage: 'Service unavailable',
        );
        expect(exception.isModelNotFound, isFalse);
        expect(exception.isContextLengthExceeded, isFalse);
        expect(exception.isRateLimited, isFalse);
      });
    });

    // ---------------------------------------------------------------------------
    // toString()
    // ---------------------------------------------------------------------------
    group('toString()', () {
      test('returns a non-empty string', () {
        final exception = LmStudioApiException(
          statusCode: 500,
          errorType: 'error',
          errorMessage: 'msg',
        );
        expect(exception.toString(), isNotEmpty);
      });

      test('includes statusCode in string representation', () {
        final exception = LmStudioApiException(
          statusCode: 404,
          errorType: 'model_not_found',
          errorMessage: 'Not found',
        );
        expect(exception.toString(), contains('404'));
      });

      test('includes errorType in string representation', () {
        final exception = LmStudioApiException(
          statusCode: 400,
          errorType: 'context_length_exceeded',
          errorMessage: 'Too long',
        );
        expect(exception.toString(), contains('context_length_exceeded'));
      });

      test('includes errorMessage in string representation', () {
        const errorMsg = 'Internal server error occurred';
        final exception = LmStudioApiException(
          statusCode: 500,
          errorType: 'server_error',
          errorMessage: errorMsg,
        );
        expect(exception.toString(), contains(errorMsg));
      });

      test('different status codes produce different toString output', () {
        final e404 = LmStudioApiException(
          statusCode: 404,
          errorType: 'type',
          errorMessage: 'msg',
        );
        final e500 = LmStudioApiException(
          statusCode: 500,
          errorType: 'type',
          errorMessage: 'msg',
        );
        expect(e404.toString(), isNot(equals(e500.toString())));
      });
    });

    // ---------------------------------------------------------------------------
    // Identity and equality
    // ---------------------------------------------------------------------------
    group('identity', () {
      test('two exceptions with identical fields are distinct instances', () {
        final e1 = LmStudioApiException(
          statusCode: 404,
          errorType: 'model_not_found',
          errorMessage: 'Not found',
        );
        final e2 = LmStudioApiException(
          statusCode: 404,
          errorType: 'model_not_found',
          errorMessage: 'Not found',
        );
        expect(identical(e1, e2), isFalse);
      });
    });
  });
}
