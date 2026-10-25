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

// CleanJSON safely removes markdown blocks from Gemini responses
func CleanJSON(text string) string {
	text = strings.TrimSpace(text)
	text = strings.TrimPrefix(text, "```json")
	text = strings.TrimPrefix(text, "```")
	text = strings.TrimSuffix(text, "```")
	return strings.TrimSpace(text)
}

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

func AnalyzeDraft(ctx context.Context, base64Image string, mainRole, secondaryRole, autofillRole, privateRulesJSON string, queryType string, otpChampions string) (string, int32, error) {
	if aiClient == nil {
		return "", 0, fmt.Errorf("el cliente de IA no ha sido inicializado")
	}

	// Decode base64 image
	imgData, err := base64.StdEncoding.DecodeString(base64Image)
	if err != nil {
		log.Printf("Error decoding base64 image: %v", err)
		return "", 0, fmt.Errorf("invalid image format")
	}

	privateRulesContext := ""
	if privateRulesJSON != "" {
		privateRulesContext = fmt.Sprintf("REGLAS ESPECÍFICAS DEL EMPRENDEDOR/GRUPO:\n%s\n", privateRulesJSON)
	}

	var prompt string

	if queryType == "otp" {
		prompt = fmt.Sprintf(`Eres un Analista Experto de Wild Rift.
El usuario es un OTP y domina a: %s.

Recomienda el mejor campeón OTP o adapta el ya elegido.

Reglas CRÍTICAS:
- IDIOMA: Español.
- FORMATO: PROHIBIDO USAR MARKDOWN. Texto limpio.
- RESPONDE ÚNICAMENTE CON LA ESTRUCTURA EXACTA (sin charla, sin incluir el título de la estructura).

ESTRUCTURA (Ya eligió):
Tu Campeón: [Nombre]
Hechizos: [Hechizo 1], [Hechizo 2]
Runas: [Runa 1], [Runa 2], [Runa 3]
Build Core: [Objeto 1], [Objeto 2], [Objeto 3]
Situacional: [Objeto 4], [Objeto 5]

%s`, otpChampions, privateRulesContext)
	} else if queryType == "in_game" {
		prompt = fmt.Sprintf(`Eres un Analista Experto de Wild Rift.
Partida en curso.

Reglas CRÍTICAS:
- IDIOMA: Español.
- FORMATO: PROHIBIDO USAR MARKDOWN.
- RESPONDE ÚNICAMENTE CON LA ESTRUCTURA EXACTA.

ESTRUCTURA:
Análisis: [5 palabras máximo de quién gana]
Objetos Recomendados: [Objeto 1], [Objeto 2], [Objeto 3]

%s`, privateRulesContext)
	} else {
		prompt = fmt.Sprintf(`Eres un Analista Experto de Wild Rift.
Roles preferidos: %s, %s, %s.

Reglas CRÍTICAS:
- IDIOMA: Español.
- FORMATO: PROHIBIDO USAR MARKDOWN para estilos, solo viñetas.
- RESPUESTAS DIRECTAS Y CORTAS.

ESTRUCTURA EXACTA:
[Explica un porqué muy corto, máx 15 palabras. Ej: Hay mucho CC del lado enemigo, usa:]
- [Campeón 1]
- [Campeón 2]
- [Campeón 3]

%s`, mainRole, secondaryRole, autofillRole, privateRulesContext)
	}

	contents := []*genai.Content{
		{
			Role: "user",
			Parts: []*genai.Part{
				{Text: prompt},
				{InlineData: &genai.Blob{Data: imgData, MIMEType: "image/jpeg"}},
			},
		},
	}
	
	maxTokens := int32(500)
	config := &genai.GenerateContentConfig{
		MaxOutputTokens: maxTokens,
	}

	models := []string{"gemini-2.5-flash-lite", "gemini-2.0-flash", "gemini-1.5-flash"}
	var lastErr error
	var resp *genai.GenerateContentResponse

	for _, model := range models {
		resp, lastErr = aiClient.Models.GenerateContent(ctx, model, contents, config)
		if lastErr == nil && resp != nil {
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
		}
		return resp.Text(), tokens, nil
	}

	return "No clear recommendation could be generated.", 0, nil
}



