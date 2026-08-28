package utils

import (
	"strings"
	"unicode"
)

// HasHiddenAbbreviations checks if a text contains words of 2 or more letters with no vowels.
// It ignores numbers and punctuation, and allows specific exceptions like "xd" and "gg".
func HasHiddenAbbreviations(text string) bool {
	// Split text into words based on spaces
	words := strings.Fields(text)

	exceptions := map[string]bool{
		"xd": true,
		"gg": true,
		"wp": true, // often used with gg
		"ff": true, // forfeit in lol
		"afk": true,
		"fps": true,
		"ms": true,
	}

	for _, w := range words {
		// Clean the word of punctuation
		var cleaned strings.Builder
		for _, r := range w {
			if unicode.IsLetter(r) {
				cleaned.WriteRune(unicode.ToLower(r))
			}
		}

		cleanWord := cleaned.String()

		// If it's less than 2 letters, it's safe (or empty due to punctuation)
		if len(cleanWord) < 2 {
			continue
		}

		// Check exceptions
		if exceptions[cleanWord] {
			continue
		}

		// Check for vowels
		hasVowel := false
		for _, r := range cleanWord {
			switch r {
			case 'a', 'e', 'i', 'o', 'u', 'á', 'é', 'í', 'ó', 'ú', 'ä', 'ë', 'ï', 'ö', 'ü':
				hasVowel = true
				break
			}
		}

		if !hasVowel {
			return true // Found a word with 2+ letters and no vowels
		}
	}

	return false
}
