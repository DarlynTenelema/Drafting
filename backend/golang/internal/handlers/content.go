package handlers

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"regexp"
	"strings"
	"time"

	"backend/internal/database"
	"backend/internal/gemini"
	"backend/internal/middleware"
	"backend/internal/models"
)

type CreateChannelRequest struct {
	Name    string `json:"name"`
	LogoURL string `json:"logo_url"`
}

// CreateChannel creates a new channel for the user, pending admin approval
func CreateChannel(w http.ResponseWriter, r *http.Request) {
	var req CreateChannelRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	channel := models.Channel{
		OwnerID: user.ID,
		Name:    req.Name,
		LogoURL: req.LogoURL,
		Status:  "approved",
	}

	if err := database.DB.Create(&channel).Error; err != nil {
		http.Error(w, "Failed to create channel: "+err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(channel)
}

type SubmitVideoRequest struct {
	ChannelID   string `json:"channel_id"`
	Title       string `json:"title"`
	Description string `json:"description"`
	VideoURL    string `json:"video_url"`
	Tags        string `json:"tags"`
}

func extractYouTubeID(videoURL string) string {
	// e.g. https://www.youtube.com/watch?v=dQw4w9WgXcQ -> dQw4w9WgXcQ
	// e.g. https://youtu.be/dQw4w9WgXcQ -> dQw4w9WgXcQ
	re := regexp.MustCompile(`(?:v=|youtu\.be/)([^&]+)`)
	matches := re.FindStringSubmatch(videoURL)
	if len(matches) > 1 {
		return matches[1]
	}
	return ""
}

func fetchYouTubeMetadata(videoID string) (title, description, tags, channelID string, err error) {
	apiKey := os.Getenv("YOUTUBE_API_KEY")
	if apiKey == "" {
		return "", "", "", "", fmt.Errorf("YOUTUBE_API_KEY not set")
	}

	url := fmt.Sprintf("https://www.googleapis.com/youtube/v3/videos?part=snippet&id=%s&key=%s", videoID, apiKey)
	resp, err := http.Get(url)
	if err != nil {
		return "", "", "", "", err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", "", "", "", err
	}

	var ytResponse struct {
		Items []struct {
			Snippet struct {
				Title       string   `json:"title"`
				Description string   `json:"description"`
				Tags        []string `json:"tags"`
				ChannelId   string   `json:"channelId"`
			} `json:"snippet"`
		} `json:"items"`
	}

	if err := json.Unmarshal(body, &ytResponse); err != nil {
		return "", "", "", "", err
	}

	if len(ytResponse.Items) == 0 {
		return "", "", "", "", fmt.Errorf("video not found")
	}

	snippet := ytResponse.Items[0].Snippet
	return snippet.Title, snippet.Description, strings.Join(snippet.Tags, ","), snippet.ChannelId, nil
}

func fetchYouTubeChannelSubscribers(channelID string) (int, error) {
	apiKey := os.Getenv("YOUTUBE_API_KEY")
	if apiKey == "" {
		return 0, fmt.Errorf("YOUTUBE_API_KEY not set")
	}

	url := fmt.Sprintf("https://www.googleapis.com/youtube/v3/channels?part=statistics&id=%s&key=%s", channelID, apiKey)
	resp, err := http.Get(url)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return 0, err
	}

	var ytResponse struct {
		Items []struct {
			Statistics struct {
				SubscriberCount string `json:"subscriberCount"`
			} `json:"statistics"`
		} `json:"items"`
	}

	if err := json.Unmarshal(body, &ytResponse); err != nil {
		return 0, err
	}

	if len(ytResponse.Items) == 0 {
		return 0, fmt.Errorf("channel not found")
	}

	var subs int
	fmt.Sscanf(ytResponse.Items[0].Statistics.SubscriberCount, "%d", &subs)
	return subs, nil
}

// SubmitVideo adds a new YouTube/Twitch video to a channel, pending admin approval
func SubmitVideo(w http.ResponseWriter, r *http.Request) {
	var req SubmitVideoRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	if user.Banned {
		http.Error(w, "Cuenta suspendida permanentemente por múltiples infracciones", http.StatusForbidden)
		return
	}

	// Verify user owns the channel
	var channel models.Channel
	if err := database.DB.Where("id = ? AND owner_id = ?", req.ChannelID, user.ID).First(&channel).Error; err != nil {
		http.Error(w, "Channel not found or unauthorized", http.StatusNotFound)
		return
	}

	title := req.Title
	description := req.Description
	tags := req.Tags

	videoStatus := "approved"
	ytID := extractYouTubeID(req.VideoURL)
	if ytID != "" {
		t, d, tg, ytChanID, err := fetchYouTubeMetadata(ytID)
		if err == nil {
			if title == "" {
				title = t
			}
			if description == "" {
				description = d
			}
			if tags == "" {
				tags = tg
			}
			if ytChanID != "" && !channel.Verified {
				// Check subscriber count
				subs, err := fetchYouTubeChannelSubscribers(ytChanID)
				if err == nil {
					channel.SubscriberCount = subs
					if subs > 10000 {
						videoStatus = "pending_verification"
						channel.Status = "pending_verification"
					}
					database.DB.Save(&channel)
				} else {
					log.Printf("Failed to fetch YT subs: %v", err)
				}
			}
		} else {
			log.Printf("Failed to fetch YT metadata: %v", err)
		}
	}

	if title == "" {
		title = "Video sin título"
	}

	// Moderate YouTube Content if it's a YouTube video
	if ytID != "" {
		thumbURL := fmt.Sprintf("https://img.youtube.com/vi/%s/hqdefault.jpg", ytID)
		thumbResp, err := http.Get(thumbURL)
		if err != nil {
			http.Error(w, "No se pudo obtener la miniatura del video para moderación.", http.StatusServiceUnavailable)
			return
		}
		defer thumbResp.Body.Close()
		imgData, err := io.ReadAll(thumbResp.Body)
		if err != nil {
			http.Error(w, "Error al procesar la miniatura del video.", http.StatusServiceUnavailable)
			return
		}
		base64Thumb := base64.StdEncoding.EncodeToString(imgData)
		approved, reason, err := gemini.ModerateYouTubeContent(r.Context(), title, description, tags, base64Thumb)
		if err != nil {
			http.Error(w, "El servicio de moderación de IA no está disponible.", http.StatusServiceUnavailable)
			return
		}
		
		if !approved {
					user.Strikes++
					if user.Strikes >= 5 {
						user.Banned = true
					}
					database.DB.Save(user)

					msg := fmt.Sprintf("Video rechazado. Razón: %s. Strike %d/5.", reason, user.Strikes)
					if user.Banned {
						msg = "Cuenta suspendida permanentemente por acumular 5 strikes."
					}

					w.Header().Set("Content-Type", "application/json")
					w.WriteHeader(http.StatusBadRequest)
					json.NewEncoder(w).Encode(map[string]interface{}{
						"error":   true,
						"message": msg,
						"strikes": user.Strikes,
						"banned":  user.Banned,
					})
					return
				}
	}

	video := models.VideoEmbed{
		ChannelID:   channel.ID,
		Title:       title,
		Description: description,
		VideoURL:    req.VideoURL,
		Tags:        tags,
		Status:      videoStatus,
	}

	if err := database.DB.Create(&video).Error; err != nil {
		if strings.Contains(err.Error(), "duplicate key value violates unique constraint") || strings.Contains(err.Error(), "UNIQUE constraint failed") || strings.Contains(err.Error(), "idx_video_embeds_video_url") {
			http.Error(w, "Este video ya ha sido subido a la plataforma por otro creador.", http.StatusConflict)
			return
		}
		http.Error(w, "Failed to submit video", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(video)
}

type FanartResponse struct {
	models.Fanart
	CreatorName   string `json:"creator_name"`
	CreatorAvatar string `json:"creator_avatar"`
}

type UploadFanartRequest struct {
	Title     string  `json:"title"`
	ImageURL  string  `json:"image_url"`
	PriceCoin float64 `json:"price_coin"`
}

// UploadFanart allows a creator to upload art for sale, pending admin approval
func UploadFanart(w http.ResponseWriter, r *http.Request) {
	err := r.ParseMultipartForm(10 << 20) // 10 MB limit
	if err != nil {
		http.Error(w, "Invalid multipart form", http.StatusBadRequest)
		return
	}

	title := r.FormValue("title")
	priceCoinStr := r.FormValue("price_coin")
	
	var priceCoin float64
	fmt.Sscanf(priceCoinStr, "%f", &priceCoin)
	if priceCoin < 0 {
		priceCoin = 0
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	if user.Banned {
		http.Error(w, "Cuenta suspendida permanentemente por múltiples infracciones", http.StatusForbidden)
		return
	}

	// Require CreatorProfile
	var creatorProfile models.CreatorProfile
	if err := database.DB.Where("user_id = ?", user.ID).First(&creatorProfile).Error; err != nil {
		http.Error(w, "Must create a Creator Space first", http.StatusForbidden)
		return
	}

	file, header, err := r.FormFile("image")
	if err != nil {
		http.Error(w, "Missing image file", http.StatusBadRequest)
		return
	}
	defer file.Close()

	contentType := header.Header.Get("Content-Type")
	if contentType != "image/jpeg" && contentType != "image/png" && contentType != "image/webp" {
		http.Error(w, "Formato de archivo no permitido. Solo JPG, PNG y WEBP.", http.StatusBadRequest)
		return
	}
	
	ext := ".jpg"
	if contentType == "image/png" {
		ext = ".png"
	} else if contentType == "image/webp" {
		ext = ".webp"
	}

	imgData, err := io.ReadAll(file)
	if err != nil {
		http.Error(w, "Error reading image", http.StatusInternalServerError)
		return
	}

	// Moderate image
	base64Img := base64.StdEncoding.EncodeToString(imgData)
	approved, reason, err := gemini.ModerateImage(r.Context(), base64Img)
	if err != nil {
		http.Error(w, "Servicio de moderación de IA no disponible", http.StatusServiceUnavailable)
		return
	}
	if !approved {
		user.Strikes++
		if user.Strikes >= 5 {
			user.Banned = true
		}
		database.DB.Save(user)

		msg := fmt.Sprintf("Imagen rechazada. Razón: %s. Strike %d/5.", reason, user.Strikes)
		if user.Banned {
			msg = "Cuenta suspendida permanentemente por acumular 5 strikes."
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"error":   true,
			"message": msg,
			"strikes": user.Strikes,
			"banned":  user.Banned,
		})
		return
	}

	// Upload to Supabase Storage
	supabaseURL := os.Getenv("SUPABASE_URL")
	supabaseKey := os.Getenv("SUPABASE_SERVICE_ROLE_KEY")

	if supabaseURL == "" || supabaseKey == "" {
		http.Error(w, "Supabase Storage is not configured", http.StatusInternalServerError)
		return
	}

	fileName := fmt.Sprintf("%s_%d%s", user.ID, time.Now().UnixNano(), ext)
	uploadURL := fmt.Sprintf("%s/storage/v1/object/fanarts/%s", supabaseURL, fileName)
	
	reqUpload, err := http.NewRequest("POST", uploadURL, bytes.NewReader(imgData))
	if err != nil {
		http.Error(w, "Error creating upload request", http.StatusInternalServerError)
		return
	}

	reqUpload.Header.Set("Authorization", "Bearer "+supabaseKey)
	reqUpload.Header.Set("Content-Type", header.Header.Get("Content-Type"))

	client := &http.Client{}
	resp, err := client.Do(reqUpload)
	if err != nil {
		http.Error(w, fmt.Sprintf("Error uploading to Supabase: %v", err), http.StatusInternalServerError)
		return
	}
	if resp.StatusCode >= 400 {
		bodyBytes, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		http.Error(w, fmt.Sprintf("Supabase rejected upload (Status %d): %s", resp.StatusCode, string(bodyBytes)), http.StatusInternalServerError)
		return
	}
	resp.Body.Close()

	publicURL := fmt.Sprintf("%s/storage/v1/object/public/fanarts/%s", supabaseURL, fileName)

	tags := r.FormValue("tags")

	fanart := models.Fanart{
		CreatorID: user.ID,
		Title:     title,
		ImageURL:  publicURL,
		PriceEssence: priceCoin,
		Status:    "approved", // Auto-approved since Gemini ModerateImage passed
		Tags:      tags,
	}

	if err := database.DB.Create(&fanart).Error; err != nil {
		http.Error(w, fmt.Sprintf("Failed to save fanart to DB: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(fanart)
}

// ListApprovedContent returns approved channels, videos, and fanarts for consumers
func ListApprovedContent(w http.ResponseWriter, r *http.Request) {
	contentType := r.URL.Query().Get("type") // "channels", "videos", "fanarts"
	
	w.Header().Set("Content-Type", "application/json")

	switch contentType {
	case "channels":
		channels := make([]models.Channel, 0)
		database.DB.Where("status = ?", "approved").Find(&channels)
		json.NewEncoder(w).Encode(channels)
	case "videos":
		videos := make([]models.VideoEmbed, 0)
		query := database.DB.Where("status = ?", "approved")
		searchQuery := r.URL.Query().Get("q")
		if searchQuery != "" {
			query = query.Where("title ILIKE ? OR description ILIKE ? OR tags ILIKE ?", "%"+searchQuery+"%", "%"+searchQuery+"%", "%"+searchQuery+"%")
		}
		query.Find(&videos)
		json.NewEncoder(w).Encode(videos)
	case "fanarts":
		fanarts := make([]models.Fanart, 0)
		database.DB.Where("status = ?", "approved").Find(&fanarts)
		
		fanartResponses := make([]FanartResponse, 0)
		for _, f := range fanarts {
			var creator models.User
			database.DB.Where("id = ?", f.CreatorID).First(&creator)
			name := creator.Username
			if name == "" {
				name = "Creator"
			}
			avatar := creator.ProfilePic
			if avatar == "" {
				avatar = "https://i.pravatar.cc/150?img=1"
			}
			fanartResponses = append(fanartResponses, FanartResponse{
				Fanart:        f,
				CreatorName:   name,
				CreatorAvatar: avatar,
			})
		}
		json.NewEncoder(w).Encode(fanartResponses)
	default:
		http.Error(w, "Invalid content type. Use ?type=channels|videos|fanarts", http.StatusBadRequest)
	}
}
func GetMyChannel(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var channel models.Channel
	if err := database.DB.Where("owner_id = ?", user.ID).First(&channel).Error; err != nil {
		http.Error(w, "Channel not found", http.StatusNotFound)
		return
	}

	var totalViews int64
	// Sum views from all videos belonging to this channel
	database.DB.Model(&models.VideoEmbed{}).Where("channel_id = ?", channel.ID).Select("COALESCE(SUM(views), 0)").Scan(&totalViews)

	var totalSubscribers int64
	database.DB.Model(&models.Subscription{}).Where("channel_id = ?", channel.ID).Count(&totalSubscribers)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"channel": channel,
		"total_views": totalViews,
		"total_subscribers": totalSubscribers,
	})
}

type UpdateChannelRequest struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	LogoURL     string `json:"logo_url"`
	BannerURL   string `json:"banner_url"`
}

func UpdateChannel(w http.ResponseWriter, r *http.Request) {
	var req UpdateChannelRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var channel models.Channel
	if err := database.DB.Where("owner_id = ?", user.ID).First(&channel).Error; err != nil {
		http.Error(w, "Channel not found", http.StatusNotFound)
		return
	}

	channel.Name = req.Name
	channel.Description = req.Description
	channel.LogoURL = req.LogoURL
	channel.BannerURL = req.BannerURL

	if err := database.DB.Save(&channel).Error; err != nil {
		http.Error(w, "Failed to update channel", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(channel)
}

func GetMyVideos(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var channel models.Channel
	if err := database.DB.Where("owner_id = ?", user.ID).First(&channel).Error; err != nil {
		http.Error(w, "Channel not found", http.StatusNotFound)
		return
	}

	var videos []models.VideoEmbed
	database.DB.Where("channel_id = ?", channel.ID).Order("created_at desc").Find(&videos)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(videos)
}

func GetMyFanarts(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var fanarts []models.Fanart
	database.DB.Where("creator_id = ?", user.ID).Order("created_at desc").Find(&fanarts)

	var fanartResponses []FanartResponse
	name := user.Username
	if name == "" {
		name = "Creator"
	}
	avatar := user.ProfilePic
	if avatar == "" {
		avatar = "https://i.pravatar.cc/150?img=1"
	}
	
	for _, f := range fanarts {
		fanartResponses = append(fanartResponses, FanartResponse{
			Fanart:        f,
			CreatorName:   name,
			CreatorAvatar: avatar,
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(fanartResponses)
}

type UpdateVideoRequest struct {
	VideoID     string `json:"video_id"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Tags        string `json:"tags"`
}

func UpdateVideo(w http.ResponseWriter, r *http.Request) {
	var req UpdateVideoRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var video models.VideoEmbed
	if err := database.DB.Where("id = ?", req.VideoID).First(&video).Error; err != nil {
		http.Error(w, "Video not found", http.StatusNotFound)
		return
	}

	var channel models.Channel
	if err := database.DB.Where("id = ? AND owner_id = ?", video.ChannelID, user.ID).First(&channel).Error; err != nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	video.Title = req.Title
	video.Description = req.Description
	video.Tags = req.Tags

	if err := database.DB.Save(&video).Error; err != nil {
		http.Error(w, "Failed to update video", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(video)
}

func DeleteVideo(w http.ResponseWriter, r *http.Request) {
	videoID := r.URL.Query().Get("id")
	if videoID == "" {
		http.Error(w, "Missing video id", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var video models.VideoEmbed
	if err := database.DB.Where("id = ?", videoID).First(&video).Error; err != nil {
		http.Error(w, "Video not found", http.StatusNotFound)
		return
	}

	var channel models.Channel
	if err := database.DB.Where("id = ? AND owner_id = ?", video.ChannelID, user.ID).First(&channel).Error; err != nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	if err := database.DB.Delete(&video).Error; err != nil {
		http.Error(w, "Failed to delete video", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"success": true})
}

type UpdateFanartRequest struct {
	FanartID string `json:"fanart_id"`
	Title    string `json:"title"`
	Tags     string `json:"tags"`
}

func UpdateFanart(w http.ResponseWriter, r *http.Request) {
	var req UpdateFanartRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var fanart models.Fanart
	if err := database.DB.Where("id = ?", req.FanartID).First(&fanart).Error; err != nil {
		http.Error(w, "Fanart not found", http.StatusNotFound)
		return
	}

	if fanart.CreatorID != user.ID {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	fanart.Title = req.Title
	fanart.Tags = req.Tags

	if err := database.DB.Save(&fanart).Error; err != nil {
		http.Error(w, "Failed to update fanart", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(fanart)
}

func DeleteFanart(w http.ResponseWriter, r *http.Request) {
	fanartID := r.URL.Query().Get("id")
	if fanartID == "" {
		http.Error(w, "Missing fanart id", http.StatusBadRequest)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var fanart models.Fanart
	if err := database.DB.Where("id = ?", fanartID).First(&fanart).Error; err != nil {
		http.Error(w, "Fanart not found", http.StatusNotFound)
		return
	}

	if fanart.CreatorID != user.ID {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Delete from Supabase Storage to prevent orphan files
	supabaseURL := os.Getenv("SUPABASE_URL")
	supabaseKey := os.Getenv("SUPABASE_SERVICE_ROLE_KEY")
	if supabaseURL != "" && supabaseKey != "" && fanart.ImageURL != "" {
		deleteURL := strings.Replace(fanart.ImageURL, "/public/", "/", 1)
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

	if err := database.DB.Delete(&fanart).Error; err != nil {
		http.Error(w, "Failed to delete fanart", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"success": true})
}
