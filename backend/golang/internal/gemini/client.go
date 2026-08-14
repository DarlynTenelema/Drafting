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

	prompt := fmt.Sprintf(`Eres un analista experto de Wild Rift. Analiza la imagen del draft.
Tareas:
1. Identifica el rol asignado al jugador en la imagen (ícono bajo su campeón/selección).
2. Identifica aliados, enemigos y baneos visibles.
3. Roles preferidos del usuario: Principal: %s, Secundario: %s, Comodín: %s.

Reglas CRÍTICAS:
- IDIOMA: Responde SIEMPRE y ÚNICAMENTE en español.
- FORMATO: NO uses formato Markdown. NO uses asteriscos (**), ni texto en negrita, ni cursivas. Genera únicamente texto plano normal.
- ROLES: Si el rol asignado en la imagen NO es uno de sus preferidos, está en "Autofill". Recomienda campeones exclusivamente para el ROL ASIGNADO en la imagen, priorizando opciones seguras.
- Analiza la composición para buscar sinergias (si es early pick) o counters (si es late pick).

Tu respuesta DEBE seguir estrictamente este formato de texto plano (máximo 15 palabras de justificación por opción):
1. [Campeón A]: [Justificación]
2. [Campeón B]: [Justificación]
3. [Campeón C]: [Justificación]`, mainRole, secondaryRole, autofillRole)

	contents := []*genai.Content{
		{
			Role: "user",
			Parts: []*genai.Part{
				{Text: prompt},
				{InlineData: &genai.Blob{Data: imgData, MIMEType: "image/jpeg"}},
			},
		},
	}
	
	resp, err := aiClient.Models.GenerateContent(ctx, "gemini-2.5-flash-lite", contents, nil)
	
	if err != nil {
		return "", fmt.Errorf("failed to generate content: %w", err)
	}

	if resp.Text() != "" {
		return resp.Text(), nil
	}

	return "No clear recommendation could be generated.", nil
}
