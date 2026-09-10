package gemini

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"

	"google.golang.org/genai"
)

// DetermineMatchContinuityResponse is the structured output from Gemini
type DetermineMatchContinuityResponse struct {
	IsSameMatch bool   `json:"is_same_match"`
	Reasoning   string `json:"reasoning"`
}

// DetermineMatchContinuity analyzes if the new screenshot belongs to the same match as the previous screenshot
func DetermineMatchContinuity(ctx context.Context, previousImageBase64 string, newImageBase64 string) (DetermineMatchContinuityResponse, int64, error) {
	var response DetermineMatchContinuityResponse

	if aiClient == nil {
		return response, 0, fmt.Errorf("AI client not initialized")
	}

	prevImgData, err := base64.StdEncoding.DecodeString(previousImageBase64)
	if err != nil {
		return response, 0, fmt.Errorf("invalid previous image base64: %v", err)
	}

	newImgData, err := base64.StdEncoding.DecodeString(newImageBase64)
	if err != nil {
		return response, 0, fmt.Errorf("invalid new image base64: %v", err)
	}

	prompt := `Analiza estas dos imágenes tomadas de un juego de Wild Rift.
Tu objetivo es determinar si la IMAGEN 2 (la segunda) pertenece a la MISMA partida que la IMAGEN 1 (la primera).

Regla de deducción (AND / OR):
1. Revisa los campeones elegidos por los Aliados y Enemigos.
2. Revisa detenidamente los BANs (bloqueos) de ambos equipos.
3. Si los bloqueos no coinciden en absoluto, ES UNA PARTIDA DIFERENTE (posiblemente un dodge o remake).
4. Si los campeones elegidos son totalmente diferentes, ES UNA PARTIDA DIFERENTE.
5. Si los campeones y los baneos son idénticos o muy similares, ES LA MISMA PARTIDA.
6. Si la primera imagen es un draft y la segunda imagen ya es dentro del juego (in_game) con los mismos campeones, ES LA MISMA PARTIDA.

Responde ÚNICAMENTE en formato JSON plano sin markdown, con la siguiente estructura:
{
  "is_same_match": true o false,
  "reasoning": "Tu razonamiento paso a paso"
}
`
	config := &genai.GenerateContentConfig{
		ResponseMIMEType: "application/json",
	}

	contents := []*genai.Content{
		{
			Role: "user",
			Parts: []*genai.Part{
				genai.NewPartFromText(prompt),
				genai.NewPartFromBytes(prevImgData, "image/jpeg"),
				genai.NewPartFromBytes(newImgData, "image/jpeg"),
			},
		},
	}

	resp, err := aiClient.Models.GenerateContent(ctx, "gemini-2.5-flash", contents, config)
	if err != nil {
		log.Printf("Gemini DetermineMatchContinuity error: %v", err)
		return response, 0, err
	}

	var tokens int64
	if resp.UsageMetadata != nil {
		tokens = int64(resp.UsageMetadata.TotalTokenCount)
	}

	if len(resp.Candidates) == 0 || len(resp.Candidates[0].Content.Parts) == 0 {
		return response, tokens, fmt.Errorf("no response from model")
	}

	var jsonStr string
	for _, part := range resp.Candidates[0].Content.Parts {
		if part.Text != "" {
			jsonStr += part.Text
		}
	}

	err = json.Unmarshal([]byte(jsonStr), &response)
	if err != nil {
		log.Printf("Error unmarshaling json from gemini: %s, err: %v", jsonStr, err)
		return response, tokens, err
	}

	return response, tokens, nil
}

// ChatCoachChatMessage is a message struct for the AI conversation
type ChatCoachChatMessage struct {
	Role    string // 'user' or 'model'
	Content string
}

// ChatCoachConverse handles the conversation between the user and Chat Coach
func ChatCoachConverse(ctx context.Context, imagesBase64 []string, chatHistory []ChatCoachChatMessage, userMessage string, currentGoal *string) (string, int32, error) {
	if aiClient == nil {
		return "", 0, fmt.Errorf("AI client not initialized")
	}

	prompt := `Eres un "Chat Coach" (CC) experto de Wild Rift. 
El usuario ha terminado su partida y quiere hablar contigo sobre ella.
Te proporciono capturas de pantalla de la partida (draft o in-game) y el historial reciente de chat.
Responde a su mensaje final de forma útil, estratégica y analítica.
`
	if currentGoal != nil && *currentGoal != "" {
		prompt += fmt.Sprintf("\n\nRecordatorio oculto del sistema: La meta actual de este jugador a largo plazo es '%s'. Usa esta meta para guiar tus consejos si aplica.\n", *currentGoal)
	}

	var contents []*genai.Content

	// 1. Initial Prompt with Images
	var initParts []*genai.Part
	initParts = append(initParts, genai.NewPartFromText(prompt))
	for _, imgBase64 := range imagesBase64 {
		imgData, err := base64.StdEncoding.DecodeString(imgBase64)
		if err == nil {
			initParts = append(initParts, genai.NewPartFromBytes(imgData, "image/jpeg"))
		}
	}
	contents = append(contents, &genai.Content{
		Role:  "user",
		Parts: initParts,
	})
	
	// Add initial model acknowledgement conditionally
	if len(imagesBase64) > 0 {
		contents = append(contents, &genai.Content{
			Role: "model",
			Parts: []*genai.Part{genai.NewPartFromText("Entendido. Analicé las capturas de la partida. ¿En qué te puedo ayudar?")},
		})
	} else if len(chatHistory) == 0 {
		contents = append(contents, &genai.Content{
			Role: "model",
			Parts: []*genai.Part{genai.NewPartFromText("¡Hola! ¿En qué te puedo ayudar con tus partidas hoy?")},
		})
	}

	// 2. Chat History (limit to 12 messages max)
	if len(chatHistory) > 12 {
		chatHistory = chatHistory[len(chatHistory)-12:]
	}

	for _, msg := range chatHistory {
		role := "user"
		if msg.Role == "model" || msg.Role == "system" {
			role = "model"
		}
		contents = append(contents, &genai.Content{
			Role:  role,
			Parts: []*genai.Part{genai.NewPartFromText(msg.Content)},
		})
	}

	// 3. Current User Message
	contents = append(contents, &genai.Content{
		Role:  "user",
		Parts: []*genai.Part{genai.NewPartFromText(userMessage)},
	})

	resp, err := aiClient.Models.GenerateContent(ctx, "gemini-2.5-flash", contents, nil)
	if err != nil {
		log.Printf("Gemini ChatCoachConverse error: %v", err)
		return "", 0, err
	}

	if len(resp.Candidates) == 0 || len(resp.Candidates[0].Content.Parts) == 0 {
		return "", 0, fmt.Errorf("no response from model")
	}

	var tokens int32 = 0
	if resp.UsageMetadata != nil {
		tokens = resp.UsageMetadata.TotalTokenCount
	}

	var responseText string
	for _, part := range resp.Candidates[0].Content.Parts {
		if part.Text != "" {
			responseText += part.Text
		}
	}

	return responseText, tokens, nil
}

// GenerateChatTitle generates a very short title based on the first user message
func GenerateChatTitle(ctx context.Context, firstMessage string) (string, error) {
	if aiClient == nil {
		return "", fmt.Errorf("AI client not initialized")
	}

	prompt := fmt.Sprintf(`Lee el siguiente mensaje con el que un jugador de Wild Rift inició la conversación con su Chat Coach.
Escribe un título corto y directo (máximo 4 palabras) que describa de qué trata este chat.
No uses comillas, ni símbolos. Solo las palabras.
Ejemplos: "Estrategia de Rammus", "Dudas sobre la build", "Early game", "Quejas del equipo".

Mensaje:
%s`, firstMessage)

	contents := []*genai.Content{
		{
			Role: "user",
			Parts: []*genai.Part{
				genai.NewPartFromText(prompt),
			},
		},
	}

	resp, err := aiClient.Models.GenerateContent(ctx, "gemini-2.5-flash", contents, nil)
	if err != nil {
		return "", err
	}
	
	if len(resp.Candidates) == 0 || len(resp.Candidates[0].Content.Parts) == 0 {
		return "Chat", nil
	}

	var responseText string
	for _, part := range resp.Candidates[0].Content.Parts {
		if part.Text != "" {
			responseText += part.Text
		}
	}
	
	// Limpiar saltos de linea y comillas extrañas
	// Para hacerlo rápido, asumimos texto plano
	return responseText, nil
}


