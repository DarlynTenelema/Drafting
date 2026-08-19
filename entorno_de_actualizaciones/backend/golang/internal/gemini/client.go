package gemini

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"os"

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

func AnalyzeDraft(ctx context.Context, base64Image string, mainRole, secondaryRole, autofillRole string) (string, error) {
	if aiClient == nil {
		return "", fmt.Errorf("el cliente de IA no ha sido inicializado")
	}

	// Decode base64 image
	imgData, err := base64.StdEncoding.DecodeString(base64Image)
	if err != nil {
		log.Printf("Error decoding base64 image: %v", err)
		return "", fmt.Errorf("invalid image format")
	}

	prompt := fmt.Sprintf(`Eres un Analista Experto de Wild Rift.
Roles preferidos: Principal: %s, Secundario: %s, Comodín: %s. (Úsalos de contexto; el rol REAL es el de la imagen).

Instrucciones de visión artificial (Analiza internamente, NO lo escribas):
1. ROL: Identifica tu rol por el texto dorado en la esquina inferior izquierda. Solo recomienda para este rol.
2. BANEOS: Revisa las esquinas superiores. NUNCA recomiendes un campeón baneado.
3. EQUIPO ALIADO: Lee los pequeños iconos de rol bajo los hechizos. Evalúa qué falta (Tanque, Daño AP o AD) para balancear la composición.
4. ENEMIGOS Y TURNO: Identifica a tu rival directo a la derecha para hacerle Counter. Si eres de los primeros en elegir, busca selecciones seguras.
5. ADAPTACIÓN: Elige 3 campeones ideales basados en este análisis.

Reglas CRÍTICAS:
- IDIOMA: Únicamente Español.
- FORMATO: NO uses Markdown, ni asteriscos. Cero saludos o introducciones.
- CONCISIÓN EXTREMA: Ahorra tokens. Explicaciones directas al grano, máximo 15 palabras por campeón.

Tu salida DEBE tener EXACTAMENTE estas 3 líneas:
1. [Campeón A]: [Razón de máximo 15 palabras]
2. [Campeón B]: [Razón de máximo 15 palabras]
3. [Campeón C]: [Razón de máximo 15 palabras]`, mainRole, secondaryRole, autofillRole)

	contents := []*genai.Content{
		{
			Role: "user",
			Parts: []*genai.Part{
				{Text: prompt},
				{InlineData: &genai.Blob{Data: imgData, MIMEType: "image/jpeg"}},
			},
		},
	}
	
	resp, err := aiClient.Models.GenerateContent(ctx, "gemini-2.5-flash", contents, nil)
	
	if err != nil {
		return "", fmt.Errorf("failed to generate content: %w", err)
	}

	if resp.Text() != "" {
		return resp.Text(), nil
	}

	return "No clear recommendation could be generated.", nil
}
