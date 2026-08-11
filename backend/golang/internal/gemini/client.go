package gemini

import (
	"context"
	"encoding/base64"
	"fmt"
	"log"

	"backend/internal/config"

	"google.golang.org/genai"
)

func AnalyzeDraft(ctx context.Context, base64Image string, mainRole, secondaryRole, autofillRole string) (string, error) {
	apiKey := config.GetEnv("GEMINI_API_KEY", "")
	if apiKey == "" {
		return "", fmt.Errorf("GEMINI_API_KEY is not configured")
	}

	client, err := genai.NewClient(ctx, &genai.ClientConfig{
		APIKey:  apiKey,
		Backend: genai.BackendGeminiAPI,
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
	resp, err := client.Models.GenerateContent(ctx, "gemini-2.5-flash-lite", contents, nil)
	
	if err != nil {
		return "", fmt.Errorf("failed to generate content: %w", err)
	}

	if resp.Text() != "" {
		return resp.Text(), nil
	}

	return "No clear recommendation could be generated.", nil
}
