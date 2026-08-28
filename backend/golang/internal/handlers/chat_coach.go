package handlers

import (
	"encoding/json"
	"io"
	"log"
	"net/http"
	"encoding/base64"
	"time"

	"backend/internal/database"
	"backend/internal/gemini"
	"backend/internal/middleware"
	"backend/internal/models"

	"github.com/go-chi/chi/v5"
)

// GetChatCoachMatches returns a list of match sessions and their screenshots
func GetChatCoachMatches(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// 24H Cleanup Logic (Lazy Deletion)
	cleanupTime := time.Now().Add(-24 * time.Hour)
	var oldSessions []models.MatchSession
	if err := database.DB.Where("created_at < ?", cleanupTime).Find(&oldSessions).Error; err == nil && len(oldSessions) > 0 {
		for _, oldSess := range oldSessions {
			// Optional: delete from Supabase via HTTP call
			// For now we just cascade delete from DB, Supabase will be cleaned if we had the API keys configured for deletion.
			database.DB.Delete(&oldSess)
		}
	}

	var sessions []models.MatchSession
	// Preload the screenshots and threads
	if err := database.DB.Preload("Screenshots").Preload("Threads").Where("user_id = ?", user.ID).Order("created_at desc").Find(&sessions).Error; err != nil {
		http.Error(w, "Failed to load match sessions", http.StatusInternalServerError)
		return
	}

	if len(sessions) == 0 {
		// Create a default session so the user has a place to start chatting
		defaultSession := models.MatchSession{
			UserID: user.ID.String(),
			Status: "active",
		}
		if err := database.DB.Create(&defaultSession).Error; err == nil {
			defaultThread := models.MatchChatThread{
				MatchSessionID: defaultSession.ID,
				Title:          "Chat Coach",
			}
			if err := database.DB.Create(&defaultThread).Error; err == nil {
				defaultSession.Threads = []models.MatchChatThread{defaultThread}
			}
			sessions = append(sessions, defaultSession)
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(sessions)
}

// CreateChatCoachThread creates a new empty chat thread for a match
func CreateChatCoachThread(w http.ResponseWriter, r *http.Request) {
	matchID := chi.URLParam(r, "id")
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Verify match exists and belongs to user
	var session models.MatchSession
	if err := database.DB.Where("id = ? AND user_id = ?", matchID, user.ID).First(&session).Error; err != nil {
		http.Error(w, "Match session not found", http.StatusNotFound)
		return
	}

	thread := models.MatchChatThread{
		MatchSessionID: matchID,
		Title:          "Nuevo Chat",
	}
	if err := database.DB.Create(&thread).Error; err != nil {
		http.Error(w, "Failed to create thread", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(thread)
}

// GetChatCoachMessages returns the chat history of a specific match chat thread
func GetChatCoachMessages(w http.ResponseWriter, r *http.Request) {
	threadID := chi.URLParam(r, "id")

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Verify the thread exists and belongs to the user
	var thread models.MatchChatThread
	if err := database.DB.Where("id = ?", threadID).First(&thread).Error; err != nil {
		http.Error(w, "Thread not found", http.StatusNotFound)
		return
	}
	var session models.MatchSession
	if err := database.DB.Where("id = ? AND user_id = ?", thread.MatchSessionID, user.ID).First(&session).Error; err != nil {
		http.Error(w, "Unauthorized thread access", http.StatusUnauthorized)
		return
	}

	var messages []models.MatchChatMessage
	if err := database.DB.Where("thread_id = ?", threadID).Order("created_at asc").Find(&messages).Error; err != nil {
		http.Error(w, "Failed to load messages", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(messages)
}

type ChatCoachMessageRequest struct {
	Content string `json:"content"`
}

// PostChatCoachMessage sends a message from the user to the Chat Coach
func PostChatCoachMessage(w http.ResponseWriter, r *http.Request) {
	threadID := chi.URLParam(r, "id")

	var req ChatCoachMessageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Content == "" {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// 1. Fetch Thread and Match Session
	var thread models.MatchChatThread
	if err := database.DB.Where("id = ?", threadID).First(&thread).Error; err != nil {
		http.Error(w, "Thread not found", http.StatusNotFound)
		return
	}

	var session models.MatchSession
	if err := database.DB.Preload("Screenshots").Where("id = ? AND user_id = ?", thread.MatchSessionID, user.ID).First(&session).Error; err != nil {
		http.Error(w, "Unauthorized or Match not found", http.StatusUnauthorized)
		return
	}

	// 2. Fetch Chat History
	var history []models.MatchChatMessage
	if err := database.DB.Where("thread_id = ?", threadID).Order("created_at asc").Find(&history).Error; err != nil {
		http.Error(w, "Failed to load chat history", http.StatusInternalServerError)
		return
	}

	// 3. Save User Message
	userMsg := models.MatchChatMessage{
		ThreadID:       threadID,
		Role:           "user",
		Content:        req.Content,
	}
	if err := database.DB.Create(&userMsg).Error; err != nil {
		http.Error(w, "Failed to save message", http.StatusInternalServerError)
		return
	}

	// 4. Download images from Supabase to send to Gemini
	var imagesBase64 []string
	for _, screenshot := range session.Screenshots {
		base64Str, err := downloadImageAsBase64Handler(screenshot.ImageURL)
		if err == nil {
			imagesBase64 = append(imagesBase64, base64Str)
		} else {
			log.Printf("ChatCoachHandler: Error downloading image %s: %v", screenshot.ImageURL, err)
		}
	}

	// 5. Prepare chat history for Gemini
	var geminiHistory []gemini.ChatCoachChatMessage
	for _, msg := range history {
		geminiHistory = append(geminiHistory, gemini.ChatCoachChatMessage{
			Role:    msg.Role,
			Content: msg.Content,
		})
	}

	// 6. Call Gemini API
	aiResponseText, err := gemini.ChatCoachConverse(r.Context(), imagesBase64, geminiHistory, req.Content, user.CurrentGoal)
	if err != nil {
		log.Printf("ChatCoachHandler: Gemini Error: %v", err)
		http.Error(w, "Ups, el coach no pudo responder. Intenta de nuevo.", http.StatusInternalServerError)
		return
	}

	// 7. Save AI Message
	aiMsg := models.MatchChatMessage{
		ThreadID:       threadID,
		Role:           "model",
		Content:        aiResponseText,
	}
	if err := database.DB.Create(&aiMsg).Error; err != nil {
		http.Error(w, "Failed to save AI response", http.StatusInternalServerError)
		return
	}

	// 8. Async Title Generation (if first message)
	if len(history) == 0 {
		go func(t models.MatchChatThread, userMsgText string) {
			// Create context for background
			bgCtx := r.Context()
			title, err := gemini.GenerateChatTitle(bgCtx, userMsgText)
			if err == nil && title != "" {
				t.Title = title
				database.DB.Save(&t)
			}
		}(thread, req.Content)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(aiMsg)
}

// downloadImageAsBase64Handler helper to download images
func downloadImageAsBase64Handler(url string) (string, error) {
	resp, err := http.Get(url)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	buf, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	return base64.StdEncoding.EncodeToString(buf), nil
}

// PostChatCoachVideoMessage accepts a multipart form with a video and a text prompt
func PostChatCoachVideoMessage(w http.ResponseWriter, r *http.Request) {
	threadID := chi.URLParam(r, "id")

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// 1. Validate File Size (Limit to 50MB to save costs and time)
	r.Body = http.MaxBytesReader(w, r.Body, 50<<20) // 50 MB
	if err := r.ParseMultipartForm(50 << 20); err != nil {
		http.Error(w, "Video too large. Maximum size is 50MB (approx 5 minutos).", http.StatusBadRequest)
		return
	}

	file, header, err := r.FormFile("video")
	if err != nil {
		http.Error(w, "Missing video file", http.StatusBadRequest)
		return
	}
	defer file.Close()

	content := r.FormValue("content")
	if content == "" {
		content = "Analiza este clip."
	}

	// 2. Fetch Thread and History (Similar to text message)
	var thread models.MatchChatThread
	if err := database.DB.Where("id = ?", threadID).First(&thread).Error; err != nil {
		http.Error(w, "Thread not found", http.StatusNotFound)
		return
	}

	var history []models.MatchChatMessage
	database.DB.Where("thread_id = ?", threadID).Order("created_at asc").Find(&history)

	// Save User Message
	userMsg := models.MatchChatMessage{
		ThreadID: threadID,
		Role:     "user",
		Content:  content + "\n[Video Adjunto]",
	}
	database.DB.Create(&userMsg)

	// Prepare history
	var geminiHistory []gemini.ChatCoachChatMessage
	for _, msg := range history {
		geminiHistory = append(geminiHistory, gemini.ChatCoachChatMessage{
			Role:    msg.Role,
			Content: msg.Content,
		})
	}

	// 3. Call Gemini API for Video (We need to implement this in gemini package)
	// For now, we will read the file into bytes
	videoBytes, _ := io.ReadAll(file)
	aiResponseText, err := gemini.ChatCoachConverseVideo(r.Context(), videoBytes, header.Header.Get("Content-Type"), geminiHistory, content, user.CurrentGoal)
	if err != nil {
		log.Printf("ChatCoachHandler: Gemini Video Error: %v", err)
		http.Error(w, "Error al analizar el video.", http.StatusInternalServerError)
		return
	}

	// 4. Save AI Message
	aiMsg := models.MatchChatMessage{
		ThreadID: threadID,
		Role:     "model",
		Content:  aiResponseText,
	}
	database.DB.Create(&aiMsg)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(aiMsg)
}

type TutorMessageRequest struct {
	Content   string `json:"content"`
	ProductID string `json:"product_id"` // Group ID or Creator Profile ID
}

// PostTutorMessage handles strict JSON-based Q&A for a purchased product
func PostTutorMessage(w http.ResponseWriter, r *http.Request) {
	threadID := chi.URLParam(r, "id")

	var req TutorMessageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Content == "" || req.ProductID == "" {
		http.Error(w, "Invalid request body. Content and product_id are required.", http.StatusBadRequest)
		return
	}

	_, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// 1. Fetch Product Data (JSON Grounding)
	var productJSON string
	var group models.Group
	if err := database.DB.Where("id = ?", req.ProductID).First(&group).Error; err == nil {
		productJSON = group.PrivateJSONData
	} else {
		var profile models.CreatorProfile
		if err := database.DB.Where("id = ?", req.ProductID).First(&profile).Error; err == nil {
			var aiModels []models.AIModel
			if err := database.DB.Where("creator_id = ?", profile.UserID).Find(&aiModels).Error; err == nil && len(aiModels) > 0 {
				customRules, _ := json.Marshal(aiModels)
				productJSON = string(customRules)
			}
		}
	}

	if productJSON == "" {
		http.Error(w, "Product JSON not found or empty", http.StatusNotFound)
		return
	}

	// 2. Fetch Thread and History
	var history []models.MatchChatMessage
	database.DB.Where("thread_id = ?", threadID).Order("created_at asc").Find(&history)

	// Save User Message
	userMsg := models.MatchChatMessage{
		ThreadID: threadID,
		Role:     "user",
		Content:  req.Content,
	}
	database.DB.Create(&userMsg)

	// Prepare history
	var geminiHistory []gemini.ChatCoachChatMessage
	for _, msg := range history {
		geminiHistory = append(geminiHistory, gemini.ChatCoachChatMessage{
			Role:    msg.Role,
			Content: msg.Content,
		})
	}

	// 3. Call Gemini API for Tutor
	aiResponseText, err := gemini.ProductTutorConverse(r.Context(), productJSON, geminiHistory, req.Content)
	if err != nil {
		log.Printf("ChatCoachHandler: Gemini Tutor Error: %v", err)
		http.Error(w, "Error al procesar la respuesta del tutor.", http.StatusInternalServerError)
		return
	}

	// 4. Save AI Message
	aiMsg := models.MatchChatMessage{
		ThreadID: threadID,
		Role:     "model",
		Content:  aiResponseText,
	}
	database.DB.Create(&aiMsg)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(aiMsg)
}

