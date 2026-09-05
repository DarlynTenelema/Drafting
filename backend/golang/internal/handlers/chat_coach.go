package handlers

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
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

	plan, _ := r.Context().Value("active_plan").(string)
	if !strings.Contains(plan, "ultra") {
		http.Error(w, "Upgrade to Ultra to access Chat Coach", http.StatusForbidden)
		return
	}

	// 24H Cleanup Logic (Lazy Deletion)
	cleanupTime := time.Now().Add(-24 * time.Hour)
	var oldSessions []models.MatchSession
	if err := database.DB.Preload("Screenshots").Where("created_at < ?", cleanupTime).Find(&oldSessions).Error; err == nil && len(oldSessions) > 0 {
		supabaseURL := os.Getenv("SUPABASE_URL")
		supabaseKey := os.Getenv("SUPABASE_SERVICE_ROLE_KEY")

		for _, oldSess := range oldSessions {
			// Delete images from Supabase
			if supabaseURL != "" && supabaseKey != "" {
				for _, shot := range oldSess.Screenshots {
					deleteURL := strings.Replace(shot.ImageURL, "/public/", "/", 1)
					
					req, err := http.NewRequest("DELETE", deleteURL, nil)
					if err == nil {
						req.Header.Set("Authorization", "Bearer "+supabaseKey)
						client := &http.Client{Timeout: 10 * time.Second}
						resp, err := client.Do(req)
						if err == nil && resp != nil {
							resp.Body.Close()
						}
					}
				}
			}
			
			// Cascade delete from DB
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

	plan, _ := r.Context().Value("active_plan").(string)
	if !strings.Contains(plan, "ultra") {
		http.Error(w, "Upgrade to Ultra to access Chat Coach", http.StatusForbidden)
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

	plan, _ := r.Context().Value("active_plan").(string)
	if !strings.Contains(plan, "ultra") {
		http.Error(w, "Upgrade to Ultra to access Chat Coach", http.StatusForbidden)
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

	if len(req.Content) > 1500 {
		http.Error(w, "El mensaje excede el límite permitido (máx 1500 caracteres).", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	plan, _ := r.Context().Value("active_plan").(string)
	if !strings.Contains(plan, "ultra") {
		http.Error(w, "Upgrade to Ultra to access Chat Coach", http.StatusForbidden)
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

	// 4. Download images from Supabase to send to Gemini in parallel
	var imagesBase64 []string
	var mu sync.Mutex
	var wg sync.WaitGroup

	for _, screenshot := range session.Screenshots {
		wg.Add(1)
		go func(url string) {
			defer wg.Done()
			base64Str, err := downloadImageAsBase64Handler(url)
			if err == nil {
				mu.Lock()
				imagesBase64 = append(imagesBase64, base64Str)
				mu.Unlock()
			} else {
				log.Printf("ChatCoachHandler: Error downloading image %s: %v", url, err)
			}
		}(screenshot.ImageURL)
	}
	wg.Wait()

	// 5. Prepare chat history for Gemini
	var geminiHistory []gemini.ChatCoachChatMessage
	for _, msg := range history {
		geminiHistory = append(geminiHistory, gemini.ChatCoachChatMessage{
			Role:    msg.Role,
			Content: msg.Content,
		})
	}

	// 6. Call Gemini API
	aiResponseText, tokens, err := gemini.ChatCoachConverse(r.Context(), imagesBase64, geminiHistory, req.Content, user.CurrentGoal)
	if err != nil {
		log.Printf("ChatCoachHandler: Gemini Error: %v", err)
		http.Error(w, "Ups, el coach no pudo responder. Intenta de nuevo.", http.StatusInternalServerError)
		return
	}

	// 6.5 Record API Usage to trigger Cooldown properly
	database.DB.Create(&models.ApiUsage{UserID: user.ID, TokensUsed: int(tokens), CreatedAt: time.Now()})

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
			// Create context for background (do not use r.Context() inside goroutine)
			bgCtx := context.Background()
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


// DeleteChatCoachThread deletes a chat thread and all its messages
func DeleteChatCoachThread(w http.ResponseWriter, r *http.Request) {
	threadID := chi.URLParam(r, "id")

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	plan, _ := r.Context().Value("active_plan").(string)
	if !strings.Contains(plan, "ultra") {
		http.Error(w, "Upgrade to Ultra to access Chat Coach", http.StatusForbidden)
		return
	}

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

	database.DB.Where("thread_id = ?", threadID).Delete(&models.MatchChatMessage{})
	database.DB.Delete(&thread)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"success": true})
}

// DeleteChatCoachMatch deletes a full match session, its threads, messages, and screenshots (including Supabase)
func DeleteChatCoachMatch(w http.ResponseWriter, r *http.Request) {
	matchID := chi.URLParam(r, "id")

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	plan, _ := r.Context().Value("active_plan").(string)
	if !strings.Contains(plan, "ultra") {
		http.Error(w, "Upgrade to Ultra to access Chat Coach", http.StatusForbidden)
		return
	}

	var session models.MatchSession
	if err := database.DB.Preload("Screenshots").Preload("Threads").Where("id = ? AND user_id = ?", matchID, user.ID).First(&session).Error; err != nil {
		http.Error(w, "Match not found or unauthorized", http.StatusNotFound)
		return
	}

	// 1. Delete images from Supabase
	supabaseURL := os.Getenv("SUPABASE_URL")
	supabaseKey := os.Getenv("SUPABASE_SERVICE_ROLE_KEY")
	if supabaseURL != "" && supabaseKey != "" {
		for _, shot := range session.Screenshots {
			deleteURL := strings.Replace(shot.ImageURL, "/public/", "/", 1)
			req, err := http.NewRequest("DELETE", deleteURL, nil)
			if err == nil {
				req.Header.Set("Authorization", "Bearer "+supabaseKey)
				client := &http.Client{Timeout: 10 * time.Second}
				resp, err := client.Do(req)
				if err == nil && resp != nil {
					resp.Body.Close()
				}
			}
		}
	}

	// 2. Cascade delete records in DB
	// Delete Messages for all threads
	var threadIDs []string
	for _, thread := range session.Threads {
		threadIDs = append(threadIDs, thread.ID)
	}
	if len(threadIDs) > 0 {
		database.DB.Where("thread_id IN ?", threadIDs).Delete(&models.MatchChatMessage{})
	}
	
	// Delete Threads
	database.DB.Where("match_session_id = ?", session.ID).Delete(&models.MatchChatThread{})
	
	// Delete Screenshots
	database.DB.Where("match_session_id = ?", session.ID).Delete(&models.MatchScreenshot{})
	
	// Delete Session
	database.DB.Delete(&session)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"success": true})
}

