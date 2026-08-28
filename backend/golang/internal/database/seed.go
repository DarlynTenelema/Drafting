package database

import (
	"log"

	"backend/internal/models"
)

func seedSubscriptionPlans() {
	plans := []models.SubscriptionPlan{
		// Plus
		{ID: "plus_1d", Price: 0.24, DurationHours: 24},
		{ID: "plus_1w", Price: 1.58, DurationHours: 168},
		{ID: "plus_1m", Price: 5.99, DurationHours: 720},
		{ID: "plus_1y", Price: 59.99, DurationHours: 8760},
		// Pro
		{ID: "pro_1d", Price: 0.49, DurationHours: 24},
		{ID: "pro_1w", Price: 2.99, DurationHours: 168},
		{ID: "pro_1m", Price: 9.99, DurationHours: 720},
		{ID: "pro_1y", Price: 99.99, DurationHours: 8760},
		// Ultra
		{ID: "ultra_1d", Price: 0.99, DurationHours: 24},
		{ID: "ultra_1w", Price: 5.99, DurationHours: 168},
		{ID: "ultra_1m", Price: 19.99, DurationHours: 720},
		{ID: "ultra_1y", Price: 199.99, DurationHours: 8760},
	}

	for _, plan := range plans {
		if err := DB.Where("id = ?", plan.ID).FirstOrCreate(&plan).Error; err != nil {
			log.Printf("Warning: failed to seed plan %s: %v", plan.ID, err)
		}
	}
}
