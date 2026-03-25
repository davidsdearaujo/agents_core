import 'package:agents_core/agents_core.dart';
import 'package:test/test.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────────
  // LmModel
  // OpenAI list-models response: {"id": "...", "object": "model", "owned_by": "..."}
  // ─────────────────────────────────────────────────────────────────────────────

  group('LmModel — construction', () {
    test('creates with id and ownedBy', () {
      final model = LmModel(id: 'llama-3-8b', ownedBy: 'lmstudio');
      expect(model.id, equals('llama-3-8b'));
      expect(model.ownedBy, equals('lmstudio'));
    });

    test('accepts empty ownedBy', () {
      final model = LmModel(id: 'some-model', ownedBy: '');
      expect(model.ownedBy, equals(''));
    });

    test('accepts long model id strings', () {
      const longId = 'lmstudio-community/Meta-Llama-3-8B-Instruct-GGUF';
      final model = LmModel(id: longId, ownedBy: 'community');
      expect(model.id, equals(longId));
    });
  });

  group('LmModel — fromJson()', () {
    test('parses id and owned_by from OpenAI format', () {
      final json = <String, dynamic>{
        'id': 'mistral-7b-instruct',
        'object': 'model',
        'owned_by': 'lmstudio',
      };
      final model = LmModel.fromJson(json);
      expect(model.id, equals('mistral-7b-instruct'));
      expect(model.ownedBy, equals('lmstudio'));
    });

    test('parses model without object field', () {
      final json = <String, dynamic>{
        'id': 'llama3',
        'owned_by': 'user',
      };
      final model = LmModel.fromJson(json);
      expect(model.id, equals('llama3'));
      expect(model.ownedBy, equals('user'));
    });

    test('parses empty ownedBy', () {
      final json = <String, dynamic>{
        'id': 'test-model',
        'owned_by': '',
      };
      final model = LmModel.fromJson(json);
      expect(model.ownedBy, equals(''));
    });
  });

  group('LmModel — toJson()', () {
    test('serializes id and owned_by (snake_case)', () {
      final model = LmModel(id: 'llama3', ownedBy: 'lmstudio');
      final json = model.toJson();
      expect(json['id'], equals('llama3'));
      expect(json['owned_by'], equals('lmstudio'));
    });

    test('does not include camelCase ownedBy key', () {
      final model = LmModel(id: 'test', ownedBy: 'owner');
      final json = model.toJson();
      expect(json.containsKey('ownedBy'), isFalse);
    });

    test('returns Map<String, dynamic>', () {
      final model = LmModel(id: 'test', ownedBy: 'owner');
      expect(model.toJson(), isA<Map<String, dynamic>>());
    });
  });

  group('LmModel — round-trip', () {
    test('round-trips through toJson/fromJson', () {
      final original = LmModel(id: 'lmstudio-community/mistral', ownedBy: 'community');
      final restored = LmModel.fromJson(original.toJson());
      expect(restored.id, equals(original.id));
      expect(restored.ownedBy, equals(original.ownedBy));
    });

    test('multiple models in list parse correctly', () {
      final jsons = [
        {'id': 'model-a', 'owned_by': 'owner-1'},
        {'id': 'model-b', 'owned_by': 'owner-2'},
        {'id': 'model-c', 'owned_by': 'owner-3'},
      ];
      final models = jsons.map(LmModel.fromJson).toList();
      expect(models.length, equals(3));
      expect(models[0].id, equals('model-a'));
      expect(models[1].id, equals('model-b'));
      expect(models[2].ownedBy, equals('owner-3'));
    });
  });
}
