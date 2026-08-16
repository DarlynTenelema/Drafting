package config

import (
	"log"
	"os"
	"strings"
	"time"

	"github.com/joho/godotenv"
)

func Load() {
	// Priority 1: If ENV_FILE is provided, try to load it (useful for local testing)
	if envPath := os.Getenv("ENV_FILE"); envPath != "" {
		if err := godotenv.Load(envPath); err != nil {
			log.Printf("Warning: failed to load env file %s: %v", envPath, err)
		} else {
			log.Printf("Loaded env file: %s", envPath)
		}
		return
	}

	// Default: try to load backend/.env relative to project root (convenience for local dev)
	if err := godotenv.Load("../../.env"); err == nil {
		log.Println("Loaded .env from backend/.env")
	} else {
		log.Println("No .env file loaded; using system environment variables.")
	}
}

func GetEnv(key, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}

// ValidateRequired will fatal in production if required variables are missing.
func ValidateRequired(keys ...string) {
	if os.Getenv("ENV") != "production" {
		// only enforce in production
		return
	}
	for _, k := range keys {
		if os.Getenv(k) == "" {
			log.Fatalf("Required env var %s is not set", k)
		}
	}
}

func ValidateTimeWindow(startKey, endKey string) {
	startStr := os.Getenv(startKey)
	endStr := os.Getenv(endKey)
	if endStr == "" {
		return
	}

	end, err := time.Parse(time.RFC3339, endStr)
	if err != nil {
		log.Fatalf("Environment variable %s invalid ISO 8601: %v", endKey, err)
	}

	if startStr == "" {
		return
	}

	start, err := time.Parse(time.RFC3339, startStr)
	if err != nil {
		log.Fatalf("Environment variable %s invalid ISO 8601: %v", startKey, err)
	}

	if !start.Before(end) {
		log.Fatalf("%s must be before %s", startKey, endKey)
	}
}

// ValidateGooglePlay ensures Play Store verification settings are complete in production.
func ValidateGooglePlay() {
	if os.Getenv("ENV") != "production" {
		return
	}
	if !strings.EqualFold(os.Getenv("GOOGLE_PLAY_VERIFICATION_ENABLED"), "true") {
		log.Fatalf("GOOGLE_PLAY_VERIFICATION_ENABLED must be true in production")
	}
	for _, key := range []string{"GOOGLE_PLAY_PACKAGE_NAME", "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"} {
		if strings.TrimSpace(os.Getenv(key)) == "" {
			log.Fatalf("Required env var %s is not set for production Play verification", key)
		}
	}
}
