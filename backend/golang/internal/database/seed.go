package database

import (
	"log"

	"backend/internal/models"
)

func seedSubscriptionPlans() {
	plans := []models.SubscriptionPlan{
		// Plus
		{ID: "sub_plus_1d", Price: 0.24, DurationHours: 24},
		{ID: "sub_plus_1w", Price: 1.58, DurationHours: 168},
		{ID: "sub_plus_1m", Price: 5.99, DurationHours: 720},
		{ID: "sub_plus_1y", Price: 59.99, DurationHours: 8760},
		// Pro
		{ID: "sub_pro_1d", Price: 0.49, DurationHours: 24},
		{ID: "sub_pro_1w", Price: 2.99, DurationHours: 168},
		{ID: "sub_pro_1m", Price: 9.99, DurationHours: 720},
		{ID: "sub_pro_1y", Price: 99.99, DurationHours: 8760},
		// Ultra
		{ID: "sub_ultra_1d", Price: 0.99, DurationHours: 24},
		{ID: "sub_ultra_1w", Price: 5.99, DurationHours: 168},
		{ID: "sub_ultra_1m", Price: 19.99, DurationHours: 720},
		{ID: "sub_ultra_1y", Price: 199.99, DurationHours: 8760},
	}

	for _, plan := range plans {
		if err := DB.Where("id = ?", plan.ID).FirstOrCreate(&plan).Error; err != nil {
			log.Printf("Warning: failed to seed plan %s: %v", plan.ID, err)
		}
	}
}
