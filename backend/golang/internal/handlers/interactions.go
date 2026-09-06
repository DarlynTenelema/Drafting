package handlers

import (
	"encoding/json"
	"net/http"

	"backend/internal/database"
	"backend/internal/gemini"
	"backend/internal/middleware"
	"backend/internal/models"
	"log"
	"strings"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type PostCommentRequest struct {
	ContentID   string  `json:"content_id"`
	VideoID     string  `json:"video_id"` // Fallback for video comments
	ContentType string  `json:"content_type"` // 'video' or 'fanart'
	Content     string  `json:"content"`
	ParentID    *string `json:"parent_id"`
}

func PostComment(w http.ResponseWriter, r *http.Request) {
	var req PostCommentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	rawID := req.ContentID
	if rawID == "" {
		rawID = req.VideoID
	}

	contentUUID, err := uuid.Parse(rawID)
	if err != nil {
		http.Error(w, "Invalid content ID", http.StatusBadRequest)
		return
	}

	contentType := req.ContentType
	if contentType == "" {
		contentType = "video"
	}

	var parentUUID *uuid.UUID
	if req.ParentID != nil && *req.ParentID != "" {
		p, err := uuid.Parse(*req.ParentID)
		if err == nil {
			parentUUID = &p
		}
	}

	if len(req.Content) > 2000 {
		http.Error(w, "El comentario no puede exceder los 2000 caracteres.", http.StatusBadRequest)
		return
	}

	// 1. Phishing / Scam check
	if strings.Contains(req.Content, "http://") || strings.Contains(req.Content, "https://") {
		isPhishing, reason, err := gemini.AnalyzePhishing(r.Context(), req.Content)
		if err == nil && isPhishing {
			log.Printf("Phishing detected from user %s. Reason: %s", user.ID, reason)
			newStrikes := user.Strikes + 1
			updates := map[string]interface{}{"strikes": newStrikes}
			if newStrikes >= 3 {
				updates["is_pending_ban"] = true
				banDate := time.Now().Add(7 * 24 * time.Hour)
				updates["pending_ban_until"] = &banDate
			}
			database.DB.Model(&user).Updates(updates)
			http.Error(w, "Enlace malicioso o de estafa bloqueado. Se te ha aplicado un strike.", http.StatusBadRequest)
			return
		}
	}

	// 2. Toxicity check
	action, reason, err := gemini.AnalyzeToxicity(r.Context(), req.Content)
	if err != nil {
		log.Printf("Toxicity analysis failed: %v", err)
		// Proceed if AI fails so we don't break the app, or default to REVIEW.
		action = "CLEAN"
	}

	if action == "STRIKE" {
		// Log the strike and update user
		log.Printf("AI Strike for user %s. Reason: %s", user.ID, reason)
		newStrikes := user.Strikes + 1
		updates := map[string]interface{}{
			"strikes": newStrikes,
		}
		if newStrikes >= 3 {
			updates["is_pending_ban"] = true
			banDate := time.Now().Add(7 * 24 * time.Hour)
			updates["pending_ban_until"] = &banDate
		}
		database.DB.Model(&user).Updates(updates)

		http.Error(w, "Tu comentario viola las reglas de la comunidad y se te ha aplicado un strike.", http.StatusBadRequest)
		return
	} else if action == "REVIEW" {
		// For now just allow it or flag it. We'll allow it but log it.
		log.Printf("AI flagged comment for REVIEW: %s", reason)
	}

	comment := models.Comment{
		ContentID:   contentUUID,
		ContentType: contentType,
		UserID:      user.ID,
		ParentID:    parentUUID,
		Content:     req.Content,
	}

	if err := database.DB.Create(&comment).Error; err != nil {
		http.Error(w, "Failed to post comment", http.StatusInternalServerError)
		return
	}

	// Preload user for response
	database.DB.Preload("User").First(&comment, comment.ID)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(comment)
}

func GetComments(w http.ResponseWriter, r *http.Request) {
	contentID := r.URL.Query().Get("content_id")
	contentType := r.URL.Query().Get("content_type")
	
	if contentID == "" {
		// Fallback for backwards compatibility
		contentID = r.URL.Query().Get("video_id")
		if contentID == "" {
			http.Error(w, "Missing content_id", http.StatusBadRequest)
			return
		}
	}
	
	if contentType == "" {
		contentType = "video"
	}

	var comments []models.Comment
	// We load all comments for the content, order by creation time
	database.DB.Preload("User").Where("content_id = ? AND content_type = ?", contentID, contentType).Order("created_at asc").Find(&comments)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(comments)
}

type UpdateCommentRequest struct {
	CommentID string `json:"comment_id"`
	Content   string `json:"content"`
}

func UpdateComment(w http.ResponseWriter, r *http.Request) {
	var req UpdateCommentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	commentUUID, err := uuid.Parse(req.CommentID)
	if err != nil {
		http.Error(w, "Invalid comment ID", http.StatusBadRequest)
		return
	}

	var comment models.Comment
	if err := database.DB.First(&comment, commentUUID).Error; err != nil {
		http.Error(w, "Comment not found", http.StatusNotFound)
		return
	}

	if comment.UserID != user.ID {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	if len(req.Content) > 2000 {
		http.Error(w, "El comentario no puede exceder los 2000 caracteres.", http.StatusBadRequest)
		return
	}

	// 1. Phishing / Scam check
	if strings.Contains(req.Content, "http://") || strings.Contains(req.Content, "https://") {
		isPhishing, reason, err := gemini.AnalyzePhishing(r.Context(), req.Content)
		if err == nil && isPhishing {
			log.Printf("Phishing detected from user %s on update. Reason: %s", user.ID, reason)
			newStrikes := user.Strikes + 1
			updates := map[string]interface{}{"strikes": newStrikes}
			if newStrikes >= 3 {
				updates["is_pending_ban"] = true
				banDate := time.Now().Add(7 * 24 * time.Hour)
				updates["pending_ban_until"] = &banDate
			}
			database.DB.Model(&user).Updates(updates)
			http.Error(w, "Enlace malicioso o de estafa bloqueado. Se te ha aplicado un strike.", http.StatusBadRequest)
			return
		}
	}

	// 2. Toxicity check
	action, reason, err := gemini.AnalyzeToxicity(r.Context(), req.Content)
	if err != nil {
		action = "CLEAN"
	}

	if action == "STRIKE" {
		log.Printf("AI Strike for user %s on update. Reason: %s", user.ID, reason)
		newStrikes := user.Strikes + 1
		updates := map[string]interface{}{
			"strikes": newStrikes,
		}
		if newStrikes >= 3 {
			updates["is_pending_ban"] = true
			banDate := time.Now().Add(7 * 24 * time.Hour)
			updates["pending_ban_until"] = &banDate
		}
		database.DB.Model(&user).Updates(updates)

		http.Error(w, "Tu comentario viola las reglas de la comunidad y se te ha aplicado un strike.", http.StatusBadRequest)
		return
	}

	comment.Content = req.Content
	if err := database.DB.Save(&comment).Error; err != nil {
		http.Error(w, "Failed to update comment", http.StatusInternalServerError)
		return
	}

	database.DB.Preload("User").First(&comment, comment.ID)
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(comment)
}

type DeleteCommentRequest struct {
	CommentID string `json:"comment_id"`
}

func DeleteComment(w http.ResponseWriter, r *http.Request) {
	var req DeleteCommentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	commentUUID, err := uuid.Parse(req.CommentID)
	if err != nil {
		http.Error(w, "Invalid comment ID", http.StatusBadRequest)
		return
	}

	var comment models.Comment
	if err := database.DB.First(&comment, commentUUID).Error; err != nil {
		http.Error(w, "Comment not found", http.StatusNotFound)
		return
	}

	if comment.UserID != user.ID {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	if err := database.DB.Delete(&comment).Error; err != nil {
		http.Error(w, "Failed to delete comment", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
}

type ToggleLikeRequest struct {
	VideoID string `json:"video_id"`
}

func ToggleVideoLike(w http.ResponseWriter, r *http.Request) {
	var req ToggleLikeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	vidUUID, err := uuid.Parse(req.VideoID)
	if err != nil {
		http.Error(w, "Invalid video ID", http.StatusBadRequest)
		return
	}

	var existingLike models.VideoLike
	err = database.DB.Where("video_id = ? AND user_id = ?", vidUUID, user.ID).First(&existingLike).Error

	isLiked := false

	if err == gorm.ErrRecordNotFound {
		// Not liked yet, create like
		newLike := models.VideoLike{
			VideoID: vidUUID,
			UserID:  user.ID,
		}
		database.DB.Create(&newLike)
		isLiked = true
	} else if err == nil {
		// Already liked, remove like
		database.DB.Delete(&existingLike)
		isLiked = false
	} else {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	// Get total likes
	var totalLikes int64
	database.DB.Model(&models.VideoLike{}).Where("video_id = ?", vidUUID).Count(&totalLikes)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"is_liked":    isLiked,
		"total_likes": totalLikes,
	})
}

type ToggleFanartLikeRequest struct {
	FanartID string `json:"fanart_id"`
}

func ToggleFanartLike(w http.ResponseWriter, r *http.Request) {
	var req ToggleFanartLikeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	fanartUUID, err := uuid.Parse(req.FanartID)
	if err != nil {
		http.Error(w, "Invalid fanart ID", http.StatusBadRequest)
		return
	}

	var existingLike models.FanartLike
	err = database.DB.Where("fanart_id = ? AND user_id = ?", fanartUUID, user.ID).First(&existingLike).Error

	isLiked := false

	if err == gorm.ErrRecordNotFound {
		// Not liked yet, create like
		newLike := models.FanartLike{
			FanartID: fanartUUID,
			UserID:   user.ID,
		}
		database.DB.Create(&newLike)
		isLiked = true
	} else if err == nil {
		// Already liked, remove like
		database.DB.Delete(&existingLike)
		isLiked = false
	} else {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	// Get total likes
	var totalLikes int64
	database.DB.Model(&models.FanartLike{}).Where("fanart_id = ?", fanartUUID).Count(&totalLikes)

	// Update the cached likes count on the fanart table
	database.DB.Model(&models.Fanart{}).Where("id = ?", fanartUUID).Update("likes", totalLikes)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"is_liked":    isLiked,
		"total_likes": totalLikes,
	})
}

type ViewVideoRequest struct {
	VideoID string `json:"video_id"`
}

func ViewVideo(w http.ResponseWriter, r *http.Request) {
	var req ViewVideoRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	vidUUID, err := uuid.Parse(req.VideoID)
	if err != nil {
		http.Error(w, "Invalid video ID", http.StatusBadRequest)
		return
	}

	// Atomically increment views
	database.DB.Model(&models.VideoEmbed{}).Where("id = ?", vidUUID).UpdateColumn("views", gorm.Expr("views + ?", 1))

	w.WriteHeader(http.StatusOK)
}

type SubscribeRequest struct {
	ChannelID string `json:"channel_id"`
	Notify    bool   `json:"notify"` // true if toggling the bell
}

func ToggleSubscribe(w http.ResponseWriter, r *http.Request) {
	var req SubscribeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	chanUUID, err := uuid.Parse(req.ChannelID)
	if err != nil {
		http.Error(w, "Invalid channel ID", http.StatusBadRequest)
		return
	}

	var sub models.Subscription
	err = database.DB.Where("subscriber_id = ? AND channel_id = ?", user.ID, chanUUID).First(&sub).Error

	isSubscribed := false
	hasNotifications := false

	if err == gorm.ErrRecordNotFound {
		// Create sub
		sub = models.Subscription{
			SubscriberID:        user.ID,
			ChannelID:           chanUUID,
			NotificationsEnabled: false,
		}
		database.DB.Create(&sub)
		isSubscribed = true
	} else if err == nil {
		if req.Notify {
			// Toggle notifications if requested
			sub.NotificationsEnabled = !sub.NotificationsEnabled
			database.DB.Save(&sub)
			isSubscribed = true
			hasNotifications = sub.NotificationsEnabled
		} else {
			// Unsubscribe
			database.DB.Delete(&sub)
		}
	}

	// Get total subs
	var totalSubs int64
	database.DB.Model(&models.Subscription{}).Where("channel_id = ?", chanUUID).Count(&totalSubs)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"is_subscribed": isSubscribed,
		"notifications_enabled": hasNotifications,
		"total_subscribers": totalSubs,
	})
}

func GetChannelSubscriptionStatus(w http.ResponseWriter, r *http.Request) {
	channelID := r.URL.Query().Get("channel_id")
	if channelID == "" {
		http.Error(w, "Missing channel_id", http.StatusBadRequest)
		return
	}

	chanUUID, err := uuid.Parse(channelID)
	if err != nil {
		http.Error(w, "Invalid channel ID", http.StatusBadRequest)
		return
	}

	var totalSubs int64
	database.DB.Model(&models.Subscription{}).Where("channel_id = ?", chanUUID).Count(&totalSubs)

	isSubscribed := false
	hasNotifications := false

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if ok {
		var sub models.Subscription
		err = database.DB.Where("subscriber_id = ? AND channel_id = ?", user.ID, chanUUID).First(&sub).Error
		if err == nil {
			isSubscribed = true
			hasNotifications = sub.NotificationsEnabled
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"is_subscribed": isSubscribed,
		"notifications_enabled": hasNotifications,
		"total_subscribers": totalSubs,
	})
}
