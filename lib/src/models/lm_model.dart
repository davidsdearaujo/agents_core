/// Information about a model available on the LM Studio server.
///
/// Corresponds to a single entry in the `data` array returned by
/// `GET /v1/models`.
///
/// ```dart
/// final model = LmModel.fromJson({
///   'id': 'llama-3-8b',
///   'object': 'model',
///   'owned_by': 'lmstudio',
/// });
/// print(model.id); // "llama-3-8b"
/// ```
class LmModel {
  /// Creates an [LmModel].
  const LmModel({required this.id, required this.ownedBy});

  /// Deserializes an [LmModel] from the OpenAI model JSON format.
  ///
  /// Reads `id` and `owned_by`; ignores `object` and other extra fields.
  factory LmModel.fromJson(Map<String, dynamic> json) {
    return LmModel(
      id: json['id'] as String,
      ownedBy: json['owned_by'] as String,
    );
  }

  /// The model identifier (e.g. `"lmstudio-community/Meta-Llama-3-8B"`).
  final String id;

  /// The owner of the model (e.g. `"lmstudio"`, `"community"`).
  final String ownedBy;

  /// Serializes this model to a JSON-compatible map with snake_case keys.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'owned_by': ownedBy,
      };
}
