package tts

import (
	"context"
	"fmt"
	"log"
	"strings"
	"sync"

	texttospeech "google.golang.org/api/texttospeech/v1"
)

var (
	ttsOnce   sync.Once
	ttsClient *texttospeech.Service
	ttsErr    error
)

// InitWaveNetClient inicializa el cliente de Google Cloud Text-to-Speech usando
// GOOGLE_APPLICATION_CREDENTIALS (ya configurado por gemini.InitVertexClient).
func InitWaveNetClient() error {
	ttsOnce.Do(func() {
		ctx := context.Background()
		svc, err := texttospeech.NewService(ctx)
		if err != nil {
			ttsErr = fmt.Errorf("error inicializando Google Cloud TTS WaveNet: %w", err)
			log.Printf("⚠️ WaveNet TTS no disponible: %v", err)
			return
		}
		ttsClient = svc
		log.Println("✅ Cliente Google Cloud Text-to-Speech (WaveNet) inicializado correctamente.")
	})
	return ttsErr
}

func selectWaveNetVoice(lang string) (languageCode string, voiceName string) {
	switch strings.ToLower(strings.TrimSpace(lang)) {
	case "pt":
		return "pt-BR", "pt-BR-Wavenet-B"
	case "en":
		return "en-US", "en-US-Wavenet-D"
	case "fr":
		return "fr-FR", "fr-FR-Wavenet-B"
	default:
		return "es-US", "es-US-Wavenet-B"
	}
}

// SynthesizeWaveNet convierte texto a audio MP3 base64 usando exclusivamente voces WaveNet ($4 / 1M chars).
// Si el texto supera 1400 caracteres, se recorta de forma segura para controlar costos y latencia.
func SynthesizeWaveNet(ctx context.Context, text string, lang string) (string, int, error) {
	clean := strings.TrimSpace(text)
	if clean == "" {
		return "", 0, nil
	}

	if ttsClient == nil {
		if err := InitWaveNetClient(); err != nil || ttsClient == nil {
			return "", 0, fmt.Errorf("WaveNet TTS no inicializado: %w", err)
		}
	}

	// Límite duro de seguridad para mantener latencia y costo bajo control
	runes := []rune(clean)
	if len(runes) > 1400 {
		clean = string(runes[:1400])
	}
	charCount := len([]rune(clean))

	langCode, voiceName := selectWaveNetVoice(lang)

	req := &texttospeech.SynthesizeSpeechRequest{
		Input: &texttospeech.SynthesisInput{
			Text: clean,
		},
		Voice: &texttospeech.VoiceSelectionParams{
			LanguageCode: langCode,
			Name:         voiceName,
		},
		AudioConfig: &texttospeech.AudioConfig{
			AudioEncoding: "MP3",
			SpeakingRate:  1.08,
			Pitch:         0.0,
		},
	}

	resp, err := ttsClient.Text.Synthesize(req).Context(ctx).Do()
	if err != nil {
		return "", charCount, fmt.Errorf("falló síntesis WaveNet (%s): %w", voiceName, err)
	}

	log.Printf("🔊 [WaveNet %s] Audio sintetizado (%d caracteres)", voiceName, charCount)
	return resp.AudioContent, charCount, nil
}
