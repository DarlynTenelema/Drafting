package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"

	"backend/internal/database"
	"backend/internal/middleware"
	"backend/internal/models"
)

type StoreProductResponse struct {
	ID           string  `json:"id"`
	Title        string  `json:"title"`
	Subtitle     string  `json:"subtitle"`
	Champion     string  `json:"champion"`
	IsGroup      bool    `json:"is_group"`
	Author       string  `json:"author"`
	Price        float64 `json:"price"`
	PrimaryColor string  `json:"primary_color"`
	ImageURL     string  `json:"image_url"`
}

// ListStoreProducts retrieves all creator profiles and active groups to display in the store
func ListStoreProducts(w http.ResponseWriter, r *http.Request) {
	var otpProfiles []models.OTPProfile
	if err := database.DB.Where("is_active = ?", true).Find(&otpProfiles).Error; err != nil {
		// Ignore
	}

	var groups []models.Group
	if err := database.DB.Where("is_active = ?", true).Find(&groups).Error; err != nil {
		// Ignore
	}

	products := []StoreProductResponse{}

	// Map Creator profiles (OTP)
	for _, p := range otpProfiles {
		color := "0xFFE91E63" // Default magenta
		if p.ChampionName == "Lee Sin" || p.ChampionName == "Zed" {
			color = "0xFFD32F2F" // Red
		} else if p.ChampionName == "Ahri" || p.ChampionName == "Lux" {
			color = "0xFF9C27B0" // Purple
		} else if p.ChampionName == "Yasuo" || p.ChampionName == "Akali" {
			color = "0xFF00BCD4" // Cyan
		}

		price := 10.0
		if parsed, err := strconv.ParseFloat(p.SubscriptionPlan, 64); err == nil && parsed > 0 {
			price = parsed
		}

		title := p.ProductName
		if title == "" {
			title = p.ChampionName + " Leyenda"
		}

		products = append(products, StoreProductResponse{
			ID:           p.ID.String(),
			Title:        title,
			Subtitle:     p.Description,
			Champion:     p.ChampionName,
			IsGroup:      false,
			Author:       p.ChampionName + " Master", // Since author is not explicitly saved yet in OTPProfile, we mock it
			Price:        price,
			PrimaryColor: color,
			ImageURL:     p.ProductImage,
		})
	}

	// Map Groups
	for _, g := range groups {
		sub := g.Description
		if sub == "" {
			sub = "Estrategias de equipo avanzadas y cobertura integral de campeones."
		}

		price := 100.0
		if parsed, err := strconv.ParseFloat(g.SubscriptionPlan, 64); err == nil && parsed > 0 {
			price = parsed
		}

		title := g.ProductName
		if title == "" {
			title = g.Name
		}

		products = append(products, StoreProductResponse{
			ID:           g.ID.String(),
			Title:        title,
			Subtitle:     sub,
			Champion:     "Multi-Rol",
			IsGroup:      true,
			Author:       g.Name,
			Price:        price,
			PrimaryColor: "0xFFFFD700", // Gold
			ImageURL:     g.ProductImage,
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(products)
}

// GetMyPackages retrieves all AI Packages the user has purchased
func GetMyPackages(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var transactions []models.Transaction
	if err := database.DB.Where("user_id = ? AND type = 'purchase_ai_package' AND status = 'completed'", user.ID).Find(&transactions).Error; err != nil {
		http.Error(w, "Error fetching packages", http.StatusInternalServerError)
		return
	}

	var creatorIDs []string
	for _, tx := range transactions {
		if tx.RelatedEntityID != nil {
			creatorIDs = append(creatorIDs, tx.RelatedEntityID.String())
		}
	}

	products := []StoreProductResponse{}

	if len(creatorIDs) > 0 {
		var otpProfiles []models.OTPProfile
		database.DB.Where("id IN ?", creatorIDs).Find(&otpProfiles)

		for _, p := range otpProfiles {
			color := "0xFFE91E63"
			if p.ChampionName == "Lee Sin" || p.ChampionName == "Zed" {
				color = "0xFFD32F2F"
			} else if p.ChampionName == "Ahri" || p.ChampionName == "Lux" {
				color = "0xFF9C27B0"
			} else if p.ChampionName == "Yasuo" || p.ChampionName == "Akali" {
				color = "0xFF00BCD4"
			}

			price := 10.0
			if parsed, err := strconv.ParseFloat(p.SubscriptionPlan, 64); err == nil && parsed > 0 {
				price = parsed
			}
			title := p.ProductName
			if title == "" { title = p.ChampionName + " Leyenda" }

			products = append(products, StoreProductResponse{
				ID:           p.ID.String(),
				Title:        title,
				Subtitle:     p.Description,
				Champion:     p.ChampionName,
				IsGroup:      false,
				Author:       p.ChampionName,
				Price:        price,
				PrimaryColor: color,
				ImageURL:     p.ProductImage,
			})
		}

		var groups []models.Group
		database.DB.Where("id IN ?", creatorIDs).Find(&groups)

		for _, g := range groups {
			price := 100.0
			if parsed, err := strconv.ParseFloat(g.SubscriptionPlan, 64); err == nil && parsed > 0 {
				price = parsed
			}
			title := g.ProductName
			if title == "" { title = g.Name }

			products = append(products, StoreProductResponse{
				ID:           g.ID.String(),
				Title:        title,
				Subtitle:     g.Description,
				Champion:     "Multi-Rol",
				IsGroup:      true,
				Author:       g.Name,
				Price:        price,
				PrimaryColor: "0xFFFFD700",
				ImageURL:     g.ProductImage,
			})
		}
	}

	if products == nil {
		products = []StoreProductResponse{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(products)
}
