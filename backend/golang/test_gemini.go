package main

import (
	"context"
	"fmt"
	"log"

	"google.golang.org/genai"
)

func main() {
	ctx := context.Background()
	apiKey := "AQ.Ab8RN6Lyd8ETjV2OfYorwbfjMEgrCOR8hltqMFxehJxAwCIGzg"

	client, err := genai.NewClient(ctx, &genai.ClientConfig{
		APIKey:  apiKey,
		Backend: genai.BackendGeminiAPI,
	})
	if err != nil {
		log.Fatalf("failed to create client: %v", err)
	}

	contents := []*genai.Content{
		{
			Parts: []*genai.Part{
				{Text: "Hello, world!"},
			},
		},
	}
	resp, err := client.Models.GenerateContent(ctx, "gemini-2.5-flash", contents, nil)
	if err != nil {
		log.Fatalf("failed to generate content: %v", err)
	}

	fmt.Println(resp.Text())
}
