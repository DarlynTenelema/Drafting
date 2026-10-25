package models_test

import (
	"backend/internal/models"
	"testing"

	"github.com/google/uuid"
)

func TestUserQueryAccounting(t *testing.T) {
	user := models.User{
		ID:                  uuid.New(),
		BonusQueries:        10,
		DailyQueries:        3,
		AdQueries:           0,
		AvailableQueries:    13,
		LastDailyRewardDate: "2026-10-24",
	}

	// 1. Consume 3 daily queries first
	for i := 0; i < 3; i++ {
		ok := user.ConsumeQuery()
		if !ok {
			t.Fatalf("Expected ConsumeQuery to succeed at step %d", i)
		}
	}
	if user.DailyQueries != 0 {
		t.Errorf("Expected DailyQueries to be 0, got %d", user.DailyQueries)
	}
	if user.BonusQueries != 10 {
		t.Errorf("Expected BonusQueries to remain 10, got %d", user.BonusQueries)
	}
	if user.AvailableQueries != 10 {
		t.Errorf("Expected AvailableQueries to be 10, got %d", user.AvailableQueries)
	}

	// 2. Consume bonus queries next
	for i := 0; i < 5; i++ {
		user.ConsumeQuery()
	}
	if user.BonusQueries != 5 {
		t.Errorf("Expected BonusQueries to be 5, got %d", user.BonusQueries)
	}
	if user.AvailableQueries != 5 {
		t.Errorf("Expected AvailableQueries to be 5, got %d", user.AvailableQueries)
	}

	// 3. Add Ad/Referral Queries (+5)
	user.AddAdQueries(5)
	if user.AdQueries != 5 {
		t.Errorf("Expected AdQueries to be 5, got %d", user.AdQueries)
	}
	if user.AvailableQueries != 10 {
		t.Errorf("Expected AvailableQueries to be 10 (5 bonus + 5 ad), got %d", user.AvailableQueries)
	}

	// 4. Daily Refresh should hard cap at 3 (never stack beyond 3)
	refreshed := user.RefreshDailyQueries("2026-10-25")
	if !refreshed {
		t.Errorf("Expected RefreshDailyQueries to return true on new date")
	}
	if user.DailyQueries != 3 {
		t.Errorf("Expected DailyQueries to be strictly 3, got %d", user.DailyQueries)
	}
	if user.AvailableQueries != 13 {
		t.Errorf("Expected AvailableQueries to be 13 (3 daily + 5 bonus + 5 ad), got %d", user.AvailableQueries)
	}

	// 5. Calling Refresh again on same day should do nothing
	refreshedAgain := user.RefreshDailyQueries("2026-10-25")
	if refreshedAgain {
		t.Errorf("Expected RefreshDailyQueries to return false on same date")
	}
	if user.DailyQueries != 3 {
		t.Errorf("Expected DailyQueries to remain 3, got %d", user.DailyQueries)
	}
}

func TestReferralCodeGeneration(t *testing.T) {
	id := uuid.MustParse("1f497722-3d69-4c89-8410-5c7f489d67dc")
	code := models.GenerateReferralCode(id)

	if code == "" {
		t.Fatalf("Expected non-empty referral code")
	}
	if len(code) < 4 {
		t.Fatalf("Referral code too short: %s", code)
	}
	if code[:2] != "WR" {
		t.Fatalf("Expected referral code to start with 'WR', got %s", code)
	}
}

func TestZeroQueriesExhaustionAndNoInfiniteTokens(t *testing.T) {
	user := models.User{
		ID:                  uuid.New(),
		BonusQueries:        0,
		DailyQueries:        2,
		AdQueries:           1,
		AvailableQueries:    3,
		LastDailyRewardDate: "2026-10-25",
	}

	// 1. Consumir exactamente las 3 disponibles
	for i := 1; i <= 3; i++ {
		ok := user.ConsumeQuery()
		if !ok {
			t.Fatalf("Se esperaba éxito en consumo #%d", i)
		}
	}

	if user.AvailableQueries != 0 {
		t.Fatalf("Se esperaba que AvailableQueries fuera 0, quedó en %d", user.AvailableQueries)
	}

	// 2. Intentar consumir 20 veces cuando ya es 0 (no debe permitirlo ni volverse negativo)
	for i := 1; i <= 20; i++ {
		ok := user.ConsumeQuery()
		if ok {
			t.Fatalf("FALLO DE SEGURIDAD: ConsumeQuery() permitió descontar sin saldo disponible en iteración %d", i)
		}
		if user.AvailableQueries < 0 {
			t.Fatalf("FALLO DE DESBORDAMIENTO: AvailableQueries se volvió negativo: %d", user.AvailableQueries)
		}
		if user.AvailableQueries != 0 {
			t.Fatalf("AvailableQueries debería mantenerse en 0, pero es: %d", user.AvailableQueries)
		}
	}

	// 3. Comprobar que llamadas repetidas a RefreshDailyQueries en el mismo día no regalan tokens
	for i := 1; i <= 10; i++ {
		refreshed := user.RefreshDailyQueries("2026-10-25")
		if refreshed {
			t.Fatalf("FALLO DE SEGURIDAD: Se otorgaron tokens infinitos en llamada repetida a RefreshDailyQueries #%d", i)
		}
		if user.AvailableQueries != 0 {
			t.Fatalf("AvailableQueries cambió inesperadamente a %d", user.AvailableQueries)
		}
	}

	// 4. Agregar recarga de 3 consultas por anuncio y verificar agotamiento
	user.AddAdQueries(3)
	if user.AvailableQueries != 3 || user.AdQueries != 3 {
		t.Fatalf("Se esperaban exactamente 3 consultas recargadas, obtenido: %d", user.AvailableQueries)
	}

	// Consumir las 3 recargadas
	for i := 1; i <= 3; i++ {
		if !user.ConsumeQuery() {
			t.Fatalf("Error al consumir recarga #%d", i)
		}
	}

	if user.AvailableQueries != 0 {
		t.Fatalf("AvailableQueries debería volver a 0 tras agotar recargas, quedó en %d", user.AvailableQueries)
	}

	if user.ConsumeQuery() {
		t.Fatalf("ConsumeQuery no debería permitir consumir tras agotar recargas")
	}
}

