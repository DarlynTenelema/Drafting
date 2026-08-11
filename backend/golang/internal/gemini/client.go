package gemini

import (
	"context"
	"encoding/base64"
	"fmt"
	"log"

	"backend/internal/config"

	"github.com/google/generative-ai-go/genai"
	"google.golang.org/api/option"
)

func AnalyzeDraft(ctx context.Context, base64Image string, mainRole, secondaryRole, autofillRole string) (string, error) {
	apiKey := config.GetEnv("GEMINI_API_KEY", "")
	if apiKey == "" {
		return "", fmt.Errorf("GEMINI_API_KEY is not configured")
	}

	client, err := genai.NewClient(ctx, option.WithAPIKey(apiKey))
	if err != nil {
		return "", fmt.Errorf("failed to create gemini client: %w", err)
	}
	defer client.Close()

	model := client.GenerativeModel("gemini-3.5-flash-lite") // Using the flash-lite model.

	// Decode base64 image
	imgData, err := base64.StdEncoding.DecodeString(base64Image)
	if err != nil {
		log.Printf("Error decoding base64 image: %v", err)
		return "", fmt.Errorf("invalid image format")
	}

	prompt := fmt.Sprintf("Analyze this screen of a mobile MOBA game draft. Based on the situation, what champion should I pick? Here are my roles:\nMain: %s\nSecondary: %s\nAutofill: %s\nKeep the answer short and direct. Your response MUST strictly follow this exact format:\nSi vas:\n%s: [champion name]\n%s: [champion name]\n%s: [champion name]", mainRole, secondaryRole, autofillRole, mainRole, secondaryRole, autofillRole)

	resp, err := model.GenerateContent(ctx, 
		genai.ImageData("image/jpeg", imgData), // Assuming JPEG, ideally mobile should send format or we detect it.
		genai.Text(prompt),
	)
	
	if err != nil {
		return "", fmt.Errorf("failed to generate content: %w", err)
	}

	if len(resp.Candidates) > 0 && len(resp.Candidates[0].Content.Parts) > 0 {
		if part, ok := resp.Candidates[0].Content.Parts[0].(genai.Text); ok {
			return string(part), nil
		}
	}

	return "No clear recommendation could be generated.", nil
}
