package utils

import (
	"regexp"
	"strings"
	"unicode"
)

var urlRegex = regexp.MustCompile(`(?i)(https?://|www\.|[a-z0-9-]+\.(com|net|org|gg|io|me|tv|co|xyz|app|link|ly|be)(/|\b))`)

var offensiveWords = []string{
	// Español
	"puto", "puta", "putos", "putas", "mierda", "pendejo", "pendeja", "cabron", "cabrón",
	"marica", "maricon", "maricón", "verga", "chinga", "chingar", "culero", "idiota",
	"imbecil", "imbécil", "estupido", "estúpido", "zorra", "malparido", "gonorrea",
	"hijueputa", "hdp", "ctm", "ptm", "spcrf", "alv", "mmg", "mamaguevo", "coño",
	"gilipollas", "subnormal", "retrasado", "pelotudo", "boludo", "conchudo", "pajero",
	// Portugués
	"porra", "caralho", "merda", "buceta", "viado", "fdp", "arrombado", "babaca",
	"vagabunda", "corno", "otario", "otário", "desgracado", "desgraçado", "vtmnc",
	// Inglés
	"fuck", "fucking", "shit", "bitch", "asshole", "bastard", "dick", "pussy",
	"cunt", "retard", "faggot", "nigger", "nigga", "whore", "slut", "stfu", "gtfo", "kys",
	// Francés
	"merde", "putain", "connard", "salope", "encule", "enculé", "batard", "bâtard", "ntm", "fdp",
}

// HasHiddenAbbreviations checks if a text contains words of 2 or more letters with no vowels.
// It ignores numbers and punctuation, and allows specific gaming/LoL exceptions like "jg", "cc", "cd", "mr", "vs".
func HasHiddenAbbreviations(text string) bool {
	words := strings.Fields(text)

	exceptions := map[string]bool{
		"xd":  true,
		"gg":  true,
		"wp":  true,
		"ff":  true,
		"afk": true,
		"fps": true,
		"ms":  true,
		"jg":  true,
		"cc":  true,
		"cd":  true,
		"cdr": true,
		"hp":  true,
		"mr":  true,
		"vs":  true,
		"wr":  true,
		"pc":  true,
		"tp":  true,
		"qss": true,
		"dps": true,
		"lvl": true,
	}

	for _, w := range words {
		var cleaned strings.Builder
		for _, r := range w {
			if unicode.IsLetter(r) {
				cleaned.WriteRune(unicode.ToLower(r))
			}
		}

		cleanWord := cleaned.String()
		if len(cleanWord) < 2 {
			continue
		}

		if exceptions[cleanWord] {
			continue
		}

		hasVowel := false
		for _, r := range cleanWord {
			switch r {
			case 'a', 'e', 'i', 'o', 'u', 'y', 'á', 'é', 'í', 'ó', 'ú', 'ä', 'ë', 'ï', 'ö', 'ü':
				hasVowel = true
				break
			}
		}

		if !hasVowel {
			return true
		}
	}

	return false
}

// ContainsProfanity verifica si el texto contiene insultos o palabras groseras
func ContainsProfanity(text string) bool {
	lower := strings.ToLower(text)
	replacer := strings.NewReplacer(
		"0", "o", "1", "i", "3", "e", "4", "a", "@", "a", "$", "s", "!", "i",
		".", " ", ",", " ", ";", " ", ":", " ", "?", " ", "¡", " ", "¿", " ",
		"-", " ", "_", " ", "(", " ", ")", " ", "[", " ", "]", " ",
	)
	normalized := " " + replacer.Replace(lower) + " "

	for _, bad := range offensiveWords {
		if strings.Contains(normalized, " "+bad+" ") {
			return true
		}
		if len(bad) >= 5 && strings.Contains(normalized, bad) {
			return true
		}
	}
	return false
}

// ValidateDraftChatMessage actúa como el Segundo Asistente Puente del Chat (Punto 1.8):
// - Bloquea links/URLs
// - Bloquea mensajes de más de 50 palabras
// - Bloquea insultos, groserías o mensajes de solo iniciales como SPCRF
// Devuelve (esValido, mensajeRespuestaPuente)
func ValidateDraftChatMessage(message, lang string) (bool, string) {
	trimmed := strings.TrimSpace(message)
	cleanLang := strings.ToLower(strings.TrimSpace(lang))
	if len(cleanLang) >= 2 {
		cleanLang = cleanLang[:2]
	}

	if trimmed == "" {
		switch cleanLang {
		case "pt":
			return false, "Por favor, escreva uma pergunta sobre a partida, runas ou itens."
		case "en":
			return false, "Please enter a question about the match, runes, or items."
		case "fr":
			return false, "Veuillez écrire une question sur la partie, les runes ou les objets."
		default:
			return false, "Por favor escribe una pregunta sobre la partida, runas u objetos."
		}
	}

	// 1. Prohibir enlaces / URLs
	if urlRegex.MatchString(trimmed) {
		switch cleanLang {
		case "pt":
			return false, "Não é permitido enviar links no chat. Faça apenas perguntas sobre Wild Rift."
		case "en":
			return false, "Links are not allowed in chat. Please ask only about Wild Rift."
		case "fr":
			return false, "Les liens ne sont pas autorisés dans le chat. Posez uniquement des questions sur Wild Rift."
		default:
			return false, "No está permitido enviar enlaces (links) en el chat. Consulta solo sobre Wild Rift."
		}
	}

	// 2. Máximo 50 palabras
	words := strings.Fields(trimmed)
	if len(words) > 50 {
		switch cleanLang {
		case "pt":
			return false, "Sua mensagem excede o limite máximo de 50 palavras. Seja mais breve."
		case "en":
			return false, "Your message exceeds the 50-word maximum limit. Please keep it concise."
		case "fr":
			return false, "Votre message dépasse la limite maximale de 50 mots. Soyez plus concis."
		default:
			return false, "Tu mensaje supera el límite máximo de 50 palabras. Por favor sé más breve."
		}
	}

	// 3. Asistente Puente: Detector de insultos o mensajes de solo iniciales (como SPCRF)
	if ContainsProfanity(trimmed) || HasHiddenAbbreviations(trimmed) {
		switch cleanLang {
		case "pt":
			return false, "Não podemos permitir palavras ofensivas, por favor seja educado."
		case "en":
			return false, "We cannot allow offensive words, please be polite."
		case "fr":
			return false, "Nous ne pouvons pas autoriser les mots offensants, veuillez être poli."
		default:
			return false, "No podemos permitir palabras ofensivas, por favor sé educado."
		}
	}

	return true, ""
}
