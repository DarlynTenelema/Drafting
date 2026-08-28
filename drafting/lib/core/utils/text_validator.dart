class TextValidator {
  /// Checks if a text contains words of 2 or more letters with no vowels.
  /// Ignores numbers, punctuation, and allows specific exceptions like "xd" and "gg".
  static bool hasHiddenAbbreviations(String text) {
    // Split text into words
    final words = text.split(RegExp(r'\s+'));

    final exceptions = {
      'xd', 'gg', 'wp', 'ff', 'afk', 'fps', 'ms'
    };

    final vowelRegExp = RegExp(r'[aeiouáéíóúäëïöüAEIOUÁÉÍÓÚÄËÏÖÜ]');
    final letterRegExp = RegExp(r'[a-zA-ZáéíóúñÁÉÍÓÚÑ]');

    for (var word in words) {
      // Clean word from punctuation
      String cleanWord = '';
      for (int i = 0; i < word.length; i++) {
        if (letterRegExp.hasMatch(word[i])) {
          cleanWord += word[i].toLowerCase();
        }
      }

      if (cleanWord.length < 2) continue;

      if (exceptions.contains(cleanWord)) continue;

      if (!vowelRegExp.hasMatch(cleanWord)) {
        return true;
      }
    }

    return false;
  }
}
