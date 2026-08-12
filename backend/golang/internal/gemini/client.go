package gemini

import (
	"context"
	"encoding/base64"
	"fmt"
	"log"
	"os"

	"backend/internal/config"

	"google.golang.org/genai"
)

func AnalyzeDraft(ctx context.Context, base64Image string, mainRole, secondaryRole, autofillRole string) (string, error) {
	saJson := config.GetEnv("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", "")
	if saJson == "" {
		return "", fmt.Errorf("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is not configured")
	}

	// Create a temporary file for the SA JSON because the Go SDK's Application Default Credentials
	// reads from the GOOGLE_APPLICATION_CREDENTIALS environment variable.
	// In a serverless/Railway environment, we can write the env var string to a temp file on boot.
	tmpFile, err := os.CreateTemp("", "sa-*.json")
	if err != nil {
		return "", fmt.Errorf("failed to create temp SA file: %w", err)
	}
	defer os.Remove(tmpFile.Name()) // clean up
	if _, err := tmpFile.Write([]byte(saJson)); err != nil {
		return "", fmt.Errorf("failed to write SA file: %w", err)
	}
	tmpFile.Close()
	os.Setenv("GOOGLE_APPLICATION_CREDENTIALS", tmpFile.Name())

	client, err := genai.NewClient(ctx, &genai.ClientConfig{
		Backend:  genai.BackendVertexAI,
		Project:  "project-793e159d-7403-492f-969",
		Location: "us-central1",
	})
	if err != nil {
		return "", fmt.Errorf("failed to create gemini client: %w", err)
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
			Parts: []*genai.Part{
				{Text: prompt},
				{InlineData: &genai.Blob{Data: imgData, MIMEType: "image/jpeg"}},
			},
		},
	}
	// Note: Vertex AI usually has 'gemini-1.5-flash' instead of 'gemini-2.5-flash-lite' available broadly.
	resp, err := client.Models.GenerateContent(ctx, "gemini-1.5-flash", contents, nil)
	
	if err != nil {
		return "", fmt.Errorf("failed to generate content: %w", err)
	}

	if resp.Text() != "" {
		return resp.Text(), nil
	}

	return "No clear recommendation could be generated.", nil
}
