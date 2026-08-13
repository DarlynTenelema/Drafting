package main

import (
	"context"
	"fmt"
	"log"
	"os"
	
	"backend/internal/config"
	"backend/internal/gemini"
)

func main() {
	config.Load() // Loads from system env if .env is missing
	// mock for test if empty
	os.Setenv("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", `{"project_id": "drafting-project"}`)
	// Actually we can just run it from the root or load the explicit file.
	err := gemini.InitVertexClient()
	if err != nil {
		log.Fatalf("Init error: %v", err)
	}

	// Try a dummy image base64 (1x1 transparent pixel)
	dummyBase64 := "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="

	res, err := gemini.AnalyzeDraft(context.Background(), dummyBase64, "Top", "Mid", "Support")
	if err != nil {
		log.Fatalf("Analyze error: %v", err)
	}
	fmt.Println("Result:", res)
}
