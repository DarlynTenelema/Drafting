package handlers

import (
	"strings"
	"time"
)

var productToPlan = map[string]string{
	"sub_plus_1d": "plus", "sub_plus_1w": "plus", "sub_plus_1m": "plus", "sub_plus_1y": "plus",
	"sub_pro_1d": "pro", "sub_pro_1w": "pro", "sub_pro_1m": "pro", "sub_pro_1y": "pro",
	"sub_ultra_1d": "ultra", "sub_ultra_1w": "ultra", "sub_ultra_1m": "ultra", "sub_ultra_1y": "ultra",
	"sub_creator_plus_1d": "creator_plus", "sub_creator_plus_1w": "creator_plus", "sub_creator_plus_1m": "creator_plus", "sub_creator_plus_1y": "creator_plus",
	"sub_creator_pro_1d": "creator_pro", "sub_creator_pro_1w": "creator_pro", "sub_creator_pro_1m": "creator_pro", "sub_creator_pro_1y": "creator_pro",
	"sub_creator_ultra_1d": "creator_ultra", "sub_creator_ultra_1w": "creator_ultra", "sub_creator_ultra_1m": "creator_ultra", "sub_creator_ultra_1y": "creator_ultra",
	
	// Planes de emprendedores
	"emp_otp_basico_10": "emp_otp_basico",
	"emp_otp_pro_30": "emp_otp_pro",
	"emp_otp_enterprise_50": "emp_otp_enterprise",
	"emp_grupo_basico_100": "emp_grupo_basico",
	"emp_grupo_pro_300": "emp_grupo_pro",
	"emp_grupo_enterprise_500": "emp_grupo_enterprise",
	
	// Paquetes de esencias
	"essence_pack_250": "essence_250",
	"essence_pack_500": "essence_500",
	"essence_pack_1000": "essence_1000",
	"essence_pack_3000": "essence_3000",
	"essence_pack_5000": "essence_5000",
}

var productPrices = map[string]float64{
	"sub_plus_1d": 0.24, "sub_plus_1w": 1.59, "sub_plus_1m": 5.99, "sub_plus_1y": 59.99,
	"sub_pro_1d": 0.49, "sub_pro_1w": 2.99, "sub_pro_1m": 9.99, "sub_pro_1y": 99.99,
	"sub_ultra_1d": 0.99, "sub_ultra_1w": 5.99, "sub_ultra_1m": 19.99, "sub_ultra_1y": 199.99,
	//Para los planes de creadores/emprendedores son los mismos precios
	"sub_creator_plus_1d": 0.24, "sub_creator_plus_1w": 1.59, "sub_creator_plus_1m": 5.99, "sub_creator_plus_1y": 59.99,
	"sub_creator_pro_1d": 0.49, "sub_creator_pro_1w": 2.99, "sub_creator_pro_1m": 9.99, "sub_creator_pro_1y": 99.99,
	"sub_creator_ultra_1d": 0.99, "sub_creator_ultra_1w": 5.99, "sub_creator_ultra_1m": 19.99, "sub_creator_ultra_1y": 199.99,

	// Planes de emprendedores
	"emp_otp_basico_10": 10.00,
	"emp_otp_pro_30": 30.00,
	"emp_otp_enterprise_50": 50.00,
	"emp_grupo_basico_100": 100.00,
	"emp_grupo_pro_300": 300.00,
	"emp_grupo_enterprise_500": 500.00,
	
	// Paquetes de esencias (precios aproximados, ajustalos según tu consola)
	"essence_pack_250": 2.50,
	"essence_pack_500": 5.00,
	"essence_pack_1000": 10.00,
	"essence_pack_3000": 30.00,
	"essence_pack_5000": 50.00,
}

func getDurationForProduct(productID string) time.Duration {
	// Esencias no tienen expiración (producto único)
	if strings.HasPrefix(productID, "essence_pack_") {
		return 0
	}

	// Planes de emprendedores mensuales
	if strings.HasPrefix(productID, "emp_otp_") || strings.HasPrefix(productID, "emp_grupo_") {
		return 30 * 24 * time.Hour
	}

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
