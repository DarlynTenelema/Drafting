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

	prompt := fmt.Sprintf("Analyze this screen of a mobile MOBA game draft. Based on the situation, what champion should I pick? Here are my roles:\nMain: %s\nSecondary: %s\nAutofill: %s\nKeep the answer short and direct. Your response MUST strictly follow this exact format:\nSi vas:\n%s: [champion name]\n%s: [champion name]\n%s: [champion name]", mainRole, secondaryRole, autofillRole, mainRole, secondaryRole, autofillRole)

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
