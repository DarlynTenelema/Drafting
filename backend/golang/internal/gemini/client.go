package gemini

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"

	"backend/internal/config"

	"google.golang.org/genai"
)

var aiClient *genai.Client

func InitVertexClient() error {
	ctx := context.Background()

	saJSON := config.GetEnv("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", "")
	if saJSON == "" {
		return fmt.Errorf("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is not configured")
	}

	var saData struct {
		ProjectID string `json:"project_id"`
	}
	if err := json.Unmarshal([]byte(saJSON), &saData); err != nil {
		return fmt.Errorf("error leyendo service account json: %w", err)
	}

	tmpFile, err := os.CreateTemp("", "gcp-credentials-*.json")
	if err != nil {
		return fmt.Errorf("error creando archivo temporal: %w", err)
	}

	if _, err := tmpFile.Write([]byte(saJSON)); err != nil {
		return fmt.Errorf("error escribiendo credenciales: %w", err)
	}
	tmpFile.Close()

	os.Setenv("GOOGLE_APPLICATION_CREDENTIALS", tmpFile.Name())

	client, err := genai.NewClient(ctx, &genai.ClientConfig{
		Backend:  genai.BackendEnterprise,
		Project:  saData.ProjectID,
		Location: "us-central1",
	})
	if err != nil {
		return fmt.Errorf("error creando cliente Enterprise: %w", err)
	}

	aiClient = client
	log.Println("✅ Cliente Gemini Enterprise Agent Platform inicializado correctamente para Producción.")
	return nil
}

// NormalizeLanguage limpia códigos como "pt_BR", "pt-PT", "en-US", "en_GB", "fr_CA", "es_MX" a "es", "pt", "en", "fr"
func NormalizeLanguage(raw string) string {
	clean := strings.ToLower(strings.TrimSpace(raw))
	if strings.HasPrefix(clean, "pt") {
		return "pt"
	}
	if strings.HasPrefix(clean, "en") {
		return "en"
	}
	if strings.HasPrefix(clean, "fr") {
		return "fr"
	}
	return "es"
}

func buildDraftPrompt(mainRole, secondaryRole, autofillRole, lang string) string {
	switch NormalizeLanguage(lang) {
	case "pt":
		return fmt.Sprintf(`Você é um Analista Mestre e Challenger de League of Legends: Wild Rift.
Analise a tela de seleção de campeões (draft) considerando as rotas preferidas: %s, %s, %s.

Seu objetivo é recomendar os 3 melhores campeões ideais para counterar a equipe inimiga e complementar a equipe aliada.

Regras CRÍTICAS:
- IDIOMA: Português (natural e profissional para jogadores do Brasil e Portugal).
- FORMATO: PROIBIDO USAR ASTERISCOS (**) OU ESTILOS MARKDOWN. Apenas texto limpo e tópicos com ponto (•).
- CONCISÃO: O jogador tem apenas 30 segundos. Seja claro, direto e objetivo sem enrolação.

ESTRUTURA EXATA:
Situação: [Diagnóstico em 1 frase curta do draft inimigo e do que sua equipe precisa]

1. [Campeão 1]
• Contribuição: [Por que countera o inimigo ou tem sinergia com sua equipe em 1 única frase]

2. [Campeão 2]
• Contribuição: [Por que countera o inimigo ou tem sinergia com sua equipe em 1 única frase]

3. [Campeão 3]
• Contribuição: [Por que countera o inimigo ou tem sinergia com sua equipe em 1 única frase]`, mainRole, secondaryRole, autofillRole)

	case "en":
		return fmt.Sprintf(`You are a Master and Challenger Analyst for League of Legends: Wild Rift.
Analyze the champion select (draft) screen considering the preferred roles: %s, %s, %s.

Your goal is to recommend the top 3 ideal champions to counter the enemy team and complement the allied team.

CRITICAL Rules:
- LANGUAGE: English (natural and professional for US & UK players).
- FORMAT: DO NOT USE ASTERISKS (**) OR MARKDOWN STYLES. Plain text and bullet points (•) only.
- CONCISENESS: The player only has 30 seconds. Be sharp, direct, and actionable without fluff.

EXACT STRUCTURE:
Situation: [1 short sentence diagnosing the enemy draft and what your team needs]

1. [Champion 1]
• Key Impact: [Why it counters the enemy or synergizes with your team in 1 single sentence]

2. [Champion 2]
• Key Impact: [Why it counters the enemy or synergizes with your team in 1 single sentence]

3. [Champion 3]
• Key Impact: [Why it counters the enemy or synergizes with your team in 1 single sentence]`, mainRole, secondaryRole, autofillRole)

	case "fr":
		return fmt.Sprintf(`Tu es un Analyste Maître et Challenger de League of Legends: Wild Rift.
Analyse l'écran de sélection des champions (draft) en tenant compte des rôles préférés : %s, %s, %s.

Ton objectif est de recommander les 3 meilleurs champions idéaux pour contrer l'équipe ennemie et compléter l'équipe alliée.

Règles CRITIQUES :
- LANGUE : Français (naturel et professionnel pour les joueurs du Canada et francophones).
- FORMAT : INTERDICTION D'UTILISER DES ASTÉRISQUES (**) OU DU MARKDOWN. Texte brut et puces (•) uniquement.
- CONCISION : Le joueur n'a que 30 secondes. Sois clair, direct et précis sans détour.

STRUCTURE EXACTE :
Situation : [Diagnostic en 1 phrase courte de la draft adverse et des besoins de ton équipe]

1. [Champion 1]
• Apport : [Pourquoi il contre l'adversaire ou complète ton équipe en 1 seule phrase]

2. [Champion 2]
• Apport : [Pourquoi il contre l'adversaire ou complète ton équipe en 1 seule phrase]

3. [Champion 3]
• Apport : [Pourquoi il contre l'adversaire ou complète ton équipe en 1 seule phrase]`, mainRole, secondaryRole, autofillRole)

	default:
		return fmt.Sprintf(`Eres un Analista Maestro y Challenger de League of Legends: Wild Rift.
Analiza la pantalla de selección de campeones (draft) considerando los roles preferidos: %s, %s, %s.

Tu objetivo es recomendar los 3 mejores campeones ideales para contrarrestar al equipo rival y complementar al equipo aliado.

Reglas CRÍTICAS:
- IDIOMA: Español.
- FORMATO: PROHIBIDO USAR ASTERISCOS (**) O ESTILOS MARKDOWN. Solo texto limpio y viñetas con punto (•).
- CONCISIÓN: El jugador solo tiene 30 segundos. Sé claro, directo y accionable sin rodeos.

ESTRUCTURA EXACTA:
Situación: [Diagnóstico en 1 frase corta del draft rival y qué necesita tu equipo]

1. [Campeón 1]
• Aporte: [Por qué contrarresta al rival o sinergiza con tu equipo en 1 sola frase]

2. [Campeón 2]
• Aporte: [Por qué contrarresta al rival o sinergiza con tu equipo en 1 sola frase]

3. [Campeón 3]
• Aporte: [Por qué contrarresta al rival o sinergiza con tu equipo en 1 sola frase]`, mainRole, secondaryRole, autofillRole)
	}
}

func AnalyzeDraft(ctx context.Context, base64Image string, mainRole, secondaryRole, autofillRole string, lang ...string) (string, int32, error) {
	if aiClient == nil {
		return "", 0, fmt.Errorf("el cliente de IA no ha sido inicializado")
	}

	// Decode base64 image
	imgData, err := base64.StdEncoding.DecodeString(base64Image)
	if err != nil {
		log.Printf("Error decoding base64 image: %v", err)
		return "", 0, fmt.Errorf("invalid image format")
	}

	selectedLang := "es"
	if len(lang) > 0 && strings.TrimSpace(lang[0]) != "" {
		selectedLang = NormalizeLanguage(lang[0])
	}

	prompt := buildDraftPrompt(mainRole, secondaryRole, autofillRole, selectedLang)

	contents := []*genai.Content{
		{
			Role: "user",
			Parts: []*genai.Part{
				{Text: prompt},
				{InlineData: &genai.Blob{Data: imgData, MIMEType: "image/jpeg"}},
			},
		},
	}

	maxTokens := int32(2500)
	thinkingBudget := int32(0) // Desactiva tokens de razonamiento interno: respuesta ultra rápida (1-2s), sin consumir tokens ocultos y sin truncar

	models := []string{"gemini-2.5-flash"}
	var lastErr error
	var resp *genai.GenerateContentResponse
	var usedModel string

	for _, model := range models {
		config := &genai.GenerateContentConfig{
			MaxOutputTokens: maxTokens,
		}
		// Gemini 2.5 soporta thinking_config; desactivamos el pensamiento para draft en tiempo real
		if strings.Contains(model, "2.5") {
			config.ThinkingConfig = &genai.ThinkingConfig{
				ThinkingBudget: &thinkingBudget,
			}
		}

		resp, lastErr = aiClient.Models.GenerateContent(ctx, model, contents, config)
		if lastErr == nil && resp != nil {
			usedModel = model
			log.Printf("✅ Recomendación generada exitosamente con modelo: %s (lang=%s)", usedModel, selectedLang)
			break
		}
		log.Printf("⚠️ Modelo '%s' falló: %v. Intentando siguiente modelo...", model, lastErr)
	}

	if lastErr != nil || resp == nil {
		return "", 0, fmt.Errorf("falló generación con modelos IA: %w", lastErr)
	}

	if resp.Text() != "" {
		var tokens int32 = 0
		if resp.UsageMetadata != nil {
			tokens = resp.UsageMetadata.TotalTokenCount
			log.Printf("📊 [%s] Tokens - Prompt: %d, Salida: %d, Total: %d",
				usedModel,
				resp.UsageMetadata.PromptTokenCount,
				resp.UsageMetadata.CandidatesTokenCount,
				resp.UsageMetadata.TotalTokenCount,
			)
		}
		return resp.Text(), tokens, nil
	}

	return "No clear recommendation could be generated.", 0, nil
}
