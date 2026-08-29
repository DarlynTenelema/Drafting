package handlers

import (
	"strings"
	"time"
)

var productToPlan = map[string]string{
	"plus_1d": "plus", "plus_1w": "plus", "plus_1m": "plus", "plus_1y": "plus",
	"pro_1d": "pro", "pro_1w": "pro", "pro_1m": "pro", "pro_1y": "pro",
	"ultra_1d": "ultra", "ultra_1w": "ultra", "ultra_1m": "ultra", "ultra_1y": "ultra",
}

var productPrices = map[string]float64{
	"plus_1d": 0.99, "plus_1w": 2.99, "plus_1m": 4.99, "plus_1y": 49.99,
	"pro_1d": 1.99, "pro_1w": 4.99, "pro_1m": 9.99, "pro_1y": 99.99,
	"ultra_1d": 2.99, "ultra_1w": 7.99, "ultra_1m": 19.99, "ultra_1y": 199.99,
}

func getDurationForProduct(productID string) time.Duration {
	if strings.HasSuffix(productID, "_1y") {
		return 365 * 24 * time.Hour
	} else if strings.HasSuffix(productID, "_1m") {
		return 30 * 24 * time.Hour
	} else if strings.HasSuffix(productID, "_1w") {
		return 7 * 24 * time.Hour
	} else if strings.HasSuffix(productID, "_1d") {
		return 24 * time.Hour
	}
	return 30 * 24 * time.Hour // fallback
}

func getPlanIDForProduct(productID string) (string, bool) {
	planID, ok := productToPlan[productID]
	return planID, ok
}

func getPriceForProduct(productID string) float64 {
	return productPrices[productID]
}
