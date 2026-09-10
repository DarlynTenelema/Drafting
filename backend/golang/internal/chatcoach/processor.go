package chatcoach

import (
	"bytes"
	"context"
	"encoding/base64"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"backend/internal/database"
	"backend/internal/gemini"
	"backend/internal/models"

	"github.com/google/uuid"
)

// ProcessCapturedImage is meant to be run asynchronously as a goroutine
func ProcessCapturedImage(userID string, imageBase64 string, queryType string) {
	// Query type could be 'otp', 'in_game', etc. We'll map it to scene_type
	sceneType := "draft"
	if queryType == "in_game" {
		sceneType = "in_game"
	}

	// 1. Find the active match session for the user
	var session models.MatchSession
	// Get the most recent session
	err := database.DB.Where("user_id = ?", userID).Order("created_at desc").First(&session).Error

	isNewSession := false
	if err != nil {
		// No session exists, create a new one
		isNewSession = true
	} else if session.Status == "completed" {
		isNewSession = true
	} else {
		// We have an active session.
		// Check how many screenshots it has
		var count int64
		database.DB.Model(&models.MatchScreenshot{}).Where("match_session_id = ?", session.ID).Count(&count)

		if count >= 5 {
			// Limit reached for this match. We don't save more.
			// The user asked to limit to 5 images per match.
			log.Printf("ChatCoach: User %s reached 5 images limit for match %s", userID, session.ID)
			return
		}

		// We need to check if this image belongs to the same match
		// Get the most recent screenshot of this session
		var lastScreenshot models.MatchScreenshot
		err = database.DB.Where("match_session_id = ?", session.ID).Order("created_at desc").First(&lastScreenshot).Error
		if err == nil {
			// Download the last screenshot from Supabase? No, we don't have its base64.
			// Wait, the Gemini prompt requires the base64 of the previous image.
			// If we don't have it, we must fetch it from the URL.
			prevBase64, err := downloadImageAsBase64(lastScreenshot.ImageURL)
			if err == nil {
				ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
				defer cancel()

				continuityResp, tokens, err := gemini.DetermineMatchContinuity(ctx, prevBase64, imageBase64)
				
				if tokens > 0 {
					userIdUUID, _ := uuid.Parse(userID)
					database.DB.Create(&models.ApiUsage{UserID: userIdUUID, TokensUsed: int(tokens), CreatedAt: time.Now()})
				}

				if err == nil {
					log.Printf("ChatCoach: Continuity Check: IsSameMatch=%v, Reasoning=%s", continuityResp.IsSameMatch, continuityResp.Reasoning)
					if !continuityResp.IsSameMatch {
						// It's a different match (e.g. dodge, remake)
						// Mark previous as completed
						session.Status = "completed"
						database.DB.Save(&session)
						isNewSession = true
					}
				} else {
					log.Printf("ChatCoach: Error checking continuity: %v", err)
					// If error, we'll assume it's the same match to avoid creating orphans,
					// or we could assume it's new. Let's assume same match to be safe.
				}
			} else {
				log.Printf("ChatCoach: Error downloading previous image: %v", err)
			}
		}
	}

	if isNewSession {
		session = models.MatchSession{
			UserID: userID,
			Status: "active",
		}
		if err := database.DB.Create(&session).Error; err != nil {
			log.Printf("ChatCoach: Error creating new match session: %v", err)
			return
		}
	}

	// 2. Upload the new image to Supabase
	imageURL, err := uploadToSupabase(userID, imageBase64)
	if err != nil {
		log.Printf("ChatCoach: Error uploading image to supabase: %v", err)
		return
	}

	// 3. Save the MatchScreenshot
	screenshot := models.MatchScreenshot{
		MatchSessionID: session.ID,
		ImageURL:       imageURL,
		SceneType:      sceneType,
	}
	if err := database.DB.Create(&screenshot).Error; err != nil {
		log.Printf("ChatCoach: Error saving screenshot: %v", err)
	}
}

func downloadImageAsBase64(url string) (string, error) {
	resp, err := http.Get(url)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	buf := new(bytes.Buffer)
	_, err = buf.ReadFrom(resp.Body)
	if err != nil {
		return "", err
	}

	return base64.StdEncoding.EncodeToString(buf.Bytes()), nil
}

func uploadToSupabase(userID string, imageBase64 string) (string, error) {
	supabaseURL := os.Getenv("SUPABASE_URL")
	supabaseKey := os.Getenv("SUPABASE_SERVICE_ROLE_KEY")

	if supabaseURL == "" || supabaseKey == "" {
		return "", fmt.Errorf("supabase credentials not set")
	}

	imgData, err := base64.StdEncoding.DecodeString(imageBase64)
	if err != nil {
		return "", fmt.Errorf("invalid base64 image: %v", err)
	}

	fileName := fmt.Sprintf("%s_%s.jpg", userID, uuid.New().String())
	uploadURL := fmt.Sprintf("%s/storage/v1/object/chat_coach/%s", supabaseURL, fileName)

	reqUpload, err := http.NewRequest("POST", uploadURL, bytes.NewReader(imgData))
	if err != nil {
		return "", err
	}

	reqUpload.Header.Set("Authorization", "Bearer "+supabaseKey)
	reqUpload.Header.Set("Content-Type", "image/jpeg")

	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Do(reqUpload)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return "", fmt.Errorf("supabase upload failed with status: %d", resp.StatusCode)
	}

	publicURL := fmt.Sprintf("%s/storage/v1/object/public/chat_coach/%s", supabaseURL, fileName)
	return publicURL, nil
}
