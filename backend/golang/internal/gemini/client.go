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
		prompt = fmt.Sprintf(`Eres un Analista Maestro de Wild Rift.
El usuario es OTP y juega con: %s.
Adapta su campeón al draft enemigo visible en pantalla.

Reglas CRÍTICAS:
- IDIOMA: Español.
- FORMATO: PROHIBIDO USAR ASTERISCOS (**) O MARKDOWN. Texto limpio.
- CONCISO Y DIRECTO: El jugador tiene pocos segundos.

ESTRUCTURA EXACTA:
Campeón OTP: [Nombre]
• Estrategia: [Qué aportar o qué priorizar contra su equipo en 1 frase]
• Hechizos: [Hechizo 1], [Hechizo 2]
• Runas: [Runa Clave] + [Secundaria recomendada]
• Build Core: [Objeto 1], [Objeto 2], [Objeto 3]
• Situacional: [Objeto clave para contrarrestar a su mayor amenaza]

%s`, otpChampions, privateRulesContext)
	} else if queryType == "in_game" {
		prompt = fmt.Sprintf(`Eres un Analista Maestro de Wild Rift.
Partida en curso (tabulador / estado actual).

Reglas CRÍTICAS:
- IDIOMA: Español.
- FORMATO: PROHIBIDO USAR ASTERISCOS (**) O MARKDOWN. Texto limpio.

ESTRUCTURA EXACTA:
• Situación: [Quién tiene ventaja y por qué en 1 frase]
• Prioridad: [A quién enfocar o qué objetivo asegurar]
• Objetos Clave: [2 o 3 ítems indispensables para esta fase de juego]

%s`, privateRulesContext)
	} else {
		prompt = fmt.Sprintf(`Eres un Analista Maestro de League of Legends: Wild Rift.
Analiza la pantalla de selección de campeones (draft) considerando los roles preferidos: %s, %s, %s.

Recomienda los 3 mejores campeones explicando brevemente su aporte y qué runas llevar.

Reglas CRÍTICAS:
- IDIOMA: Español.
- FORMATO: PROHIBIDO USAR ASTERISCOS (**) O ESTILOS MARKDOWN. Solo viñetas limpias (•).
- CONCISIÓN: El jugador solo tiene 30 segundos. Sé claro, directo y accionable sin rodeos ni texto de relleno.

ESTRUCTURA EXACTA:
Situación: [Diagnóstico en 1 frase corta del draft rival]

1. [Campeón 1]
• Aporte: [Por qué elegirlo o qué aportará contra ellos en 1 sola frase]
• Runas: [Runa Clave] + [Secundaria recomendada]

2. [Campeón 2]
• Aporte: [Por qué elegirlo o qué aportará contra ellos en 1 sola frase]
• Runas: [Runa Clave] + [Secundaria recomendada]

3. [Campeón 3]
• Aporte: [Por qué elegirlo o qué aportará contra ellos en 1 sola frase]
• Runas: [Runa Clave] + [Secundaria recomendada]

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
	
	maxTokens := int32(1000)
	config := &genai.GenerateContentConfig{
		MaxOutputTokens: maxTokens,
	}

	models := []string{"gemini-2.5-flash", "gemini-2.0-flash", "gemini-1.5-flash"}
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



