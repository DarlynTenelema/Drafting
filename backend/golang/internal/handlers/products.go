package handlers

import (
	"strings"
	"time"
)

var productToPlan = map[string]string{
	"plus_1d": "plus", "plus_1w": "plus", "plus_1m": "plus", "plus_1y": "plus",
	"pro_1d": "pro", "pro_1w": "pro", "pro_1m": "pro", "pro_1y": "pro",
	"ultra_1d": "ultra", "ultra_1w": "ultra", "ultra_1m": "ultra", "ultra_1y": "ultra",
	"creator_plus_1d": "creator_plus", "creator_plus_1w": "creator_plus", "creator_plus_1m": "creator_plus", "creator_plus_1y": "creator_plus",
	"creator_pro_1d": "creator_pro", "creator_pro_1w": "creator_pro", "creator_pro_1m": "creator_pro", "creator_pro_1y": "creator_pro",
	"creator_ultra_1d": "creator_ultra", "creator_ultra_1w": "creator_ultra", "creator_ultra_1m": "creator_ultra", "creator_ultra_1y": "creator_ultra",
}

var productPrices = map[string]float64{
	"plus_1d": 0.24, "plus_1w": 1.59, "plus_1m": 5.99, "plus_1y": 59.99,
	"pro_1d": 0.49, "pro_1w": 2.99, "pro_1m": 9.99, "pro_1y": 99.99,
	"ultra_1d": 0.99, "ultra_1w": 5.99, "ultra_1m": 19.99, "ultra_1y": 199.99,
	//Para los planes de creadores/emprendedores son los mismos precios
	"creator_plus_1d": 0.24, "creator_plus_1w": 1.59, "creator_plus_1m": 5.99, "creator_plus_1y": 59.99,
	"creator_pro_1d": 0.49, "creator_pro_1w": 2.99, "creator_pro_1m": 9.99, "creator_pro_1y": 99.99,
	"creator_ultra_1d": 0.99, "creator_ultra_1w": 5.99, "creator_ultra_1m": 19.99, "creator_ultra_1y": 199.99,
	//Modelo económico diario
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
