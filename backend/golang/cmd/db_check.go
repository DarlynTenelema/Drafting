package main

import (
	"fmt"

	"backend/internal/database"
	"backend/internal/models"
)

func main() {
	database.Connect()

	var count int64
	var totalTokens int64

	// Get total API usage requests
	database.GetDB().Model(&models.ApiUsage{}).Count(&count)

	// Get total tokens used
	type Result struct {
		TotalTokens int64
	}
	var res Result
	database.GetDB().Model(&models.ApiUsage{}).Select("sum(tokens_used) as total_tokens").Scan(&res)
	totalTokens = res.TotalTokens

	// Get top users
	type UserUsage struct {
		UserID     string
		Requests   int64
		TokensUsed int64
	}
	var topUsers []UserUsage
	database.GetDB().Model(&models.ApiUsage{}).
		Select("user_id, count(*) as requests, sum(tokens_used) as tokens_used").
		Group("user_id").
		Order("requests DESC").
		Limit(10).
		Scan(&topUsers)

	fmt.Println("=== REPORTE DE USO DE API ===")
	fmt.Printf("Total de peticiones a la IA: %d\n", count)
	fmt.Printf("Total de tokens consumidos: %d\n", totalTokens)
	fmt.Println("\nTop Usuarios:")
	for _, u := range topUsers {
		fmt.Printf("Usuario: %s | Peticiones: %d | Tokens: %d\n", u.UserID, u.Requests, u.TokensUsed)
	}
}
