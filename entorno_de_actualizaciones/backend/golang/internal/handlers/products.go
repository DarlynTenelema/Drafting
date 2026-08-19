package handlers

import "time"

var productToPlan = map[string]string{
	"sub_micro_24h":   "micro_24h",
	"sub_micro_72h":   "micro_72h",
	"sub_micro_120h":  "micro_120h",
	"sub_medium_30d":  "medium_30d",
	"sub_medium_90d":  "medium_90d",
	"sub_medium_150d": "medium_150d",
	"sub_max_180d":    "max_180d",
	"sub_max_240d":    "max_240d",
	"sub_max_365d":    "max_365d",
}

var productPrices = map[string]float64{
	"sub_micro_24h":   0.49,
	"sub_micro_72h":   1.47,
	"sub_micro_120h":  2.45,
	"sub_medium_30d":  9.99,
	"sub_medium_90d":  29.97,
	"sub_medium_150d": 49.95,
	"sub_max_180d":    49.99,
	"sub_max_240d":    79.99,
	"sub_max_365d":    99.99,
}

func getDurationForProduct(productID string) time.Duration {
	switch productID {
	case "sub_micro_24h":
		return 24 * time.Hour
	case "sub_micro_72h":
		return 72 * time.Hour
	case "sub_micro_120h":
		return 120 * time.Hour
	case "sub_medium_30d":
		return 30 * 24 * time.Hour
	case "sub_medium_90d":
		return 90 * 24 * time.Hour
	case "sub_medium_150d":
		return 150 * 24 * time.Hour
	case "sub_max_180d":
		return 180 * 24 * time.Hour
	case "sub_max_240d":
		return 240 * 24 * time.Hour
	case "sub_max_365d":
		return 365 * 24 * time.Hour
	default:
		return 0
	}
}

func getPlanIDForProduct(productID string) (string, bool) {
	planID, ok := productToPlan[productID]
	return planID, ok
}

func getPriceForProduct(productID string) float64 {
	return productPrices[productID]
}
