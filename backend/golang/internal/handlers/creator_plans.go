package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"backend/internal/database"
	"backend/internal/models"
)

type CreatorPlan struct {
	Name           string   `json:"name"`
	Percentage     string   `json:"percentage"`
	Price          float64  `json:"price"`
	Period         string   `json:"period"`
	IsGroup        bool     `json:"isGroup"`
	TotalSlots     int      `json:"totalSlots"`
	AvailableSlots int      `json:"availableSlots"`
	Features       []string `json:"features"`
	PlanID         string   `json:"planId"`
}

func GetCreatorPlans(w http.ResponseWriter, r *http.Request) {
	// Define base plans statically
	basePlans := []CreatorPlan{
		{
			Name: "OTP Básico", Percentage: "50%", Price: 10, Period: "mes", IsGroup: false, TotalSlots: 100, PlanID: "10",
			Features: []string{"Empieza tu emprendimiento sin riesgo", "50% de ganancia por cada suscriptor", "Límite de 100 usuarios mensuales", "Sin costos de infraestructura cloud"},
		},
		{
			Name: "OTP Pro", Percentage: "70%", Price: 30, Period: "mes", IsGroup: false, TotalSlots: 45, PlanID: "30",
			Features: []string{"Maximiza tus ingresos como experto", "70% de ganancia por cada suscriptor", "Límite de 300 usuarios mensuales", "Insignia de 'Creador Pro' en Leaderboard", "Soporte prioritario para tu IA"},
		},
		{
			Name: "OTP Leyenda", Percentage: "90%", Price: 50, Period: "mes", IsGroup: false, TotalSlots: 50, PlanID: "50",
			Features: []string{"Conviértete en una leyenda de Drafting", "90% de ganancia (la comisión máxima)", "Límite de 500 usuarios mensuales", "Destacado automático en la tienda", "Acceso anticipado a nuevas funciones"},
		},
		{
			Name: "Grupo Start", Percentage: "50%", Price: 100, Period: "mes", IsGroup: true, TotalSlots: 20, PlanID: "100",
			Features: []string{"Ideal para academias y equipos amateur", "50% de ganancias distribuidas", "Límite de 1,000 suscriptores", "Entrena IAs para los 5 roles del juego", "Panel de control para múltiples analistas"},
		},
		{
			Name: "Grupo Avanzado", Percentage: "70%", Price: 300, Period: "mes", IsGroup: true, TotalSlots: 10, PlanID: "300",
			Features: []string{"Para organizaciones en crecimiento", "70% de ganancias para tu equipo", "Límite de 3,000 suscriptores", "Perfil de equipo verificado con logo", "Herramientas de análisis de rendimiento", "Algoritmo de recomendación prioritario"},
		},
		{
			Name: "Grupo Elite", Percentage: "90%", Price: 500, Period: "mes", IsGroup: true, TotalSlots: 5, PlanID: "500",
			Features: []string{"El plan definitivo para equipos Tier 1", "90% de ganancia (máxima rentabilidad)", "Límite masivo de 5,000 suscriptores", "Promoción destacada en la app principal", "Monetización global sin restricciones", "Insignia dorada de 'Equipo Elite'", "Soporte VIP 24/7 con ingenieros"},
		},
	}

	// Query DB to find taken slots
	var otpCounts []struct {
		SubscriptionPlan string
		Count            int
	}
	database.DB.Model(&models.OTPProfile{}).Select("subscription_plan, count(*) as count").Group("subscription_plan").Scan(&otpCounts)

	var groupCounts []struct {
		SubscriptionPlan string
		Count            int
	}
	database.DB.Model(&models.Group{}).Select("subscription_plan, count(*) as count").Group("subscription_plan").Scan(&groupCounts)

	taken := make(map[string]int)
	for _, oc := range otpCounts {
		taken["otp_"+oc.SubscriptionPlan] = oc.Count
	}
	for _, gc := range groupCounts {
		taken["group_"+gc.SubscriptionPlan] = gc.Count
	}

	// Assign available slots
	for i := range basePlans {
		key := "otp_"
		if basePlans[i].IsGroup {
			key = "group_"
		}
		
		totalTaken := 0
		for k, count := range taken {
			if strings.HasPrefix(k, key) && strings.Contains(k, basePlans[i].PlanID) {
				totalTaken += count
			}
		}

		basePlans[i].AvailableSlots = basePlans[i].TotalSlots - totalTaken
		if basePlans[i].AvailableSlots < 0 {
			basePlans[i].AvailableSlots = 0
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(basePlans)
}

type ValidateInviteRequest struct {
	Email string `json:"email"`
}

func ValidateGroupInvite(w http.ResponseWriter, r *http.Request) {
	var req ValidateInviteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	var count int64
	database.DB.Model(&models.User{}).Where("email = ?", req.Email).Count(&count)

	isValid := count > 0

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"valid": isValid})
}
