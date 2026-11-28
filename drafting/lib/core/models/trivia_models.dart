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

  factory TriviaQuestion.fromJson(
    Map<String, dynamic> json, {
    required String fallbackCategory,
  }) {
    final rawOptions =
        (json['options'] is List) ? json['options'] as List<dynamic> : const [];
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
  bool get isCounter => category == 'counter';
  bool get isPowerSpike => category == 'power_spike';
  bool get isLevelDuel => category == 'level_duel';
  bool get isBestRune => category == 'best_rune';
  bool get isBestItem => category == 'best_item';

  /// Indica si las opciones de respuesta representan nombres de campeones.
  bool get optionsAreChampions =>
      isCounter || isLevelDuel || isBestRune || isBestItem;

  /// Extrae los 2 campeones enfrentados en preguntas de tipo `level_duel` ("A vs B").
  List<String> get duelChampions {
    final parts = targetName.split(RegExp(r'\s+vs\.?\s+', caseSensitive: false));
    if (parts.length == 2) {
      return [parts[0].trim(), parts[1].trim()];
    }
    if (options.length >= 2) {
      return [options[0], options[1]];
    }
    return [targetName];
  }
}
