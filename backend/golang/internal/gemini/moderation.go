package gemini

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"google.golang.org/genai"
)

// ModerationVerdict representa el resultado estructurado del análisis de seguridad de un Brief/Reel.
type ModerationVerdict struct {
	Safe       bool    `json:"safe"`
	Category   string  `json:"category"`   // "safe", "nsfw", "gore", "hate_harassment", "spam"
	Confidence float64 `json:"confidence"` // 0.0 - 1.0
	Reason     string  `json:"reason"`
}

// IsModerationAvailable indica si el cliente Vertex AI / Gemini está listo para moderar.
func IsModerationAvailable() bool {
	return aiClient != nil
}

// ModerateReelFrames analiza 1 a 5 fotogramas clave + título/descripción con Gemini Flash (ThinkingBudget=0)
// para detectar contenido +18 explícito, pornografía, gore real o violencia gráfica antes de publicar.
// Distingue explícitamente violencia de videojuego (League of Legends / Wild Rift) de gore real.
func ModerateReelFrames(ctx context.Context, title, description string, jpegFrames [][]byte) (*ModerationVerdict, error) {
	if aiClient == nil {
		return nil, fmt.Errorf("vertex AI client no inicializado")
	}

	prompt := fmt.Sprintf(`Eres un sistema experto de moderación de contenido (Trust & Safety) para una app de clips cortos de videojuegos (League of Legends y Wild Rift).
Analiza el título, la descripción y los fotogramas adjuntos del video.

REGLAS CRÍTICAS DE CLASIFICACIÓN:
1. "nsfw": Pornografía, desnudez explícita, actos sexuales, contenido +18 explícito o sexualización de menores. (NO marques skins normales de campeones de LoL/Wild Rift).
2. "gore": Violencia real extrema, sangre real, mutilación, cadáveres reales, autolesiones reales o maltrato animal real. (NO marques combate de videojuego, habilidades de campeones ni sangre animada de LoL).
3. "hate_harassment": Discurso de odio severo en texto/imagen (nazismo, racismo explícito, amenazas de muerte reales, doxxing).
4. "safe": Jugadas de League of Legends, Wild Rift, memes de gaming, caras de streamers, clips normales.

Título del video: %q
Descripción: %q

Responde ÚNICAMENTE con un objeto JSON válido con este formato exacto:
{"safe": true|false, "category": "safe"|"nsfw"|"gore"|"hate_harassment", "confidence": 0.00, "reason": "explicación breve en español (máx 100 caracteres)"}`, title, description)

	parts := make([]*genai.Part, 0, len(jpegFrames)+1)
	parts = append(parts, genai.NewPartFromText(prompt))
	for _, frame := range jpegFrames {
		if len(frame) > 0 {
			parts = append(parts, genai.NewPartFromBytes(frame, "image/jpeg"))
		}
	}

	return runModerationPrompt(ctx, parts)
}

// ModerateReelAudioOnDemand analiza el audio extraído de un video SOLO bajo demanda cuando
// un reel entra en cuarentena por reportes de insultos, discriminación o acoso.
func ModerateReelAudioOnDemand(ctx context.Context, title, description string, audioBytes []byte, mimeType string) (*ModerationVerdict, error) {
	if aiClient == nil {
		return nil, fmt.Errorf("vertex AI client no inicializado")
	}
	if len(audioBytes) == 0 {
		return nil, fmt.Errorf("audio vacío")
	}
	if strings.TrimSpace(mimeType) == "" {
		mimeType = "audio/mpeg"
	}

	prompt := fmt.Sprintf(`Eres un moderador de seguridad (Trust & Safety) para una comunidad de jugadores de League of Legends / Wild Rift.
Escucha el audio de este clip corto reportado por usuarios por posibles insultos, discriminación o acoso.

REGLAS:
- Marca "hate_harassment" (safe=false) SOLO si hay discurso de odio real (racismo, homofobia, xenofobia, incitación al suicidio, amenazas reales o acoso severo dirigido a una persona).
- Marca "safe" (safe=true) si solo es jerga normal de videojuegos, frustración leve por una partida ("qué malo ese jungla", "me robaron el barón") o música/efectos del juego.

Título: %q
Descripción: %q

Responde ÚNICAMENTE con un JSON válido:
{"safe": true|false, "category": "safe"|"hate_harassment", "confidence": 0.00, "reason": "explicación breve en español (máx 100 caracteres)"}`, title, description)

	parts := []*genai.Part{
		genai.NewPartFromText(prompt),
		genai.NewPartFromBytes(audioBytes, mimeType),
	}

	return runModerationPrompt(ctx, parts)
}

func runModerationPrompt(ctx context.Context, parts []*genai.Part) (*ModerationVerdict, error) {
	thinkingBudget := int32(0)
	temp := float32(0.0)
	cfg := &genai.GenerateContentConfig{
		MaxOutputTokens:  220,
		Temperature:      &temp,
		ResponseMIMEType: "application/json",
		ThinkingConfig: &genai.ThinkingConfig{
			ThinkingBudget: &thinkingBudget,
		},
	}

	contents := []*genai.Content{
		genai.NewContentFromParts(parts, genai.RoleUser),
	}

	resp, err := aiClient.Models.GenerateContent(ctx, "gemini-2.5-flash", contents, cfg)
	if err != nil {
		// Si Vertex AI bloqueó la petición por filtros de seguridad duros (NSFW/Gore extremo)
		errLower := strings.ToLower(err.Error())
		if strings.Contains(errLower, "safety") || strings.Contains(errLower, "prohibited") || strings.Contains(errLower, "blocked") {
			return &ModerationVerdict{
				Safe:       false,
				Category:   "nsfw",
				Confidence: 0.98,
				Reason:     "Bloqueado por filtro de seguridad estricto de IA",
			}, nil
		}
		return nil, fmt.Errorf("error llamando a Gemini moderation: %w", err)
	}

	if resp == nil || len(resp.Candidates) == 0 {
		return &ModerationVerdict{
			Safe:       false,
			Category:   "nsfw",
			Confidence: 0.90,
			Reason:     "Contenido bloqueado sin candidatos por políticas de seguridad",
		}, nil
	}

	cand := resp.Candidates[0]
	if cand.FinishReason == genai.FinishReasonSafety ||
		cand.FinishReason == genai.FinishReasonProhibitedContent ||
		cand.FinishReason == genai.FinishReasonSPII {
		return &ModerationVerdict{
			Safe:       false,
			Category:   "nsfw",
			Confidence: 0.99,
			Reason:     "Bloqueado automáticamente por filtro de seguridad (" + string(cand.FinishReason) + ")",
		}, nil
	}

	rawText := strings.TrimSpace(resp.Text())
	rawText = strings.TrimPrefix(rawText, "```json")
	rawText = strings.TrimPrefix(rawText, "```")
	rawText = strings.TrimSuffix(rawText, "```")
	rawText = strings.TrimSpace(rawText)

	var verdict ModerationVerdict
	if err := json.Unmarshal([]byte(rawText), &verdict); err != nil {
		return nil, fmt.Errorf("respuesta JSON inválida de moderación (%q): %w", rawText, err)
	}

	verdict.Category = strings.ToLower(strings.TrimSpace(verdict.Category))
	if verdict.Category == "" {
		if verdict.Safe {
			verdict.Category = "safe"
		} else {
			verdict.Category = "nsfw"
		}
	}
	if verdict.Confidence < 0 {
		verdict.Confidence = 0
	}
	if verdict.Confidence > 1 {
		verdict.Confidence = 1
	}
	if len(verdict.Reason) > 150 {
		verdict.Reason = verdict.Reason[:150]
	}

	return &verdict, nil
}
