package database

import (
	"log"

	"backend/internal/models"
)

func seedSubscriptionPlans() {
	plans := []models.SubscriptionPlan{
		{ID: "micro_24h", Price: 0.49, DurationHours: 24},
		{ID: "micro_72h", Price: 1.47, DurationHours: 72},
		{ID: "micro_120h", Price: 2.45, DurationHours: 120},
		{ID: "medium_30d", Price: 9.99, DurationHours: 720},
		{ID: "medium_90d", Price: 29.97, DurationHours: 2160},
		{ID: "medium_150d", Price: 49.95, DurationHours: 3600},
		{ID: "max_180d", Price: 49.99, DurationHours: 4320},
		{ID: "max_240d", Price: 79.99, DurationHours: 5760},
		{ID: "max_365d", Price: 99.99, DurationHours: 8760},
	}

	for _, plan := range plans {
		if err := DB.Where("id = ?", plan.ID).FirstOrCreate(&plan).Error; err != nil {
			log.Printf("Warning: failed to seed plan %s: %v", plan.ID, err)
		}
	}
}
