/// Modelo POO para una pregunta de Trivia y su respuesta de validación.
class TriviaQuestion {
  final dynamic id;
  final String category;
  final String questionText;
  final String targetName;
  final String clues;
  final List<String> options;

  const TriviaQuestion({
    required this.id,
    required this.category,
    required this.questionText,
    required this.targetName,
    required this.clues,
    required this.options,
  });

  factory TriviaQuestion.fromJson(Map<String, dynamic> json, {required String fallbackCategory}) {
    final rawOptions = (json['options'] is List) ? json['options'] as List<dynamic> : const [];
    return TriviaQuestion(
      id: json['id'],
      category: (json['category'] ?? fallbackCategory).toString(),
      questionText: (json['question_text'] ?? '').toString(),
      targetName: (json['target_name'] ?? '').toString(),
      clues: (json['clues'] ?? '').toString(),
      options: rawOptions.map((e) => e.toString()).toList(),
    );
  }

  bool get isItemCost => category == 'item_cost';
  bool get isBuildPath => category == 'build_path';
}
