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

	prompt := fmt.Sprintf(`Eres un analista de Wild Rift. Roles preferidos del usuario: Principal: %s, Secundario: %s, Comodín: %s.

Instrucciones de visión artificial (Analiza internamente, NO lo escribas):
1. LOCALIZA EL ROL ASIGNADO: Busca el texto en amarillo en la esquina inferior izquierda (ej. "APOYO", "JUNGLA", "CARRIL CENTRAL", "CARRIL SUPERIOR", "TIRADOR"). Confía ciegamente en este texto de la imagen para saber qué rol le tocó.
2. ESTRATEGIA: Observa campeones aliados y enemigos visibles para buscar counters o sinergias.
3. ADAPTACIÓN: Recomienda campeones que pertenezcan EXACTAMENTE al rol asignado que leíste en la imagen.

Reglas CRÍTICAS para tu respuesta:
- IDIOMA: Únicamente Español.
- FORMATO ESTRICTO: NO uses Markdown (ni asteriscos **).
- DIRECTO AL GRANO: Cero introducciones. NO saludes, NO digas qué rol viste, NO listes a los enemigos.

Tu salida DEBE contener EXACTAMENTE estas 3 líneas (una oración corta explicando el "por qué"):
1. [Campeón A]: [Razón directa basada en la composición]
2. [Campeón B]: [Razón directa basada en la composición]
3. [Campeón C]: [Razón directa basada en la composición]`, mainRole, secondaryRole, autofillRole)

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
