package models_test

import (
	"backend/internal/models"
	"testing"
	"time"

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

	// 4. Si el usuario tiene >= 3 consultas totales (aquí tiene 10), RefreshDailyQueries NO regala consultas gratuitas
	refreshed := user.RefreshDailyQueries("2026-10-25")
	if refreshed {
		t.Errorf("Expected RefreshDailyQueries to return false when user already has >= 3 queries")
	}
	if user.AvailableQueries != 10 {
		t.Errorf("Expected AvailableQueries to remain 10, got %d", user.AvailableQueries)
	}

	// 5. Consumir hasta dejarle solo 1 consulta disponible y verificar que al día siguiente le regala exactamente 2 para completar 3
	for i := 0; i < 9; i++ {
		user.ConsumeQuery()
	}
	if user.AvailableQueries != 1 {
		t.Fatalf("Expected AvailableQueries to be 1, got %d", user.AvailableQueries)
	}
	refreshedLow := user.RefreshDailyQueries("2026-10-26")
	if !refreshedLow {
		t.Errorf("Expected RefreshDailyQueries to return true when AvailableQueries < 3 on new day")
	}
	if user.AvailableQueries != 3 {
		t.Errorf("Expected AvailableQueries to top up to strictly 3, got %d", user.AvailableQueries)
	}

	// 6. Calling Refresh again on same day should do nothing
	refreshedAgain := user.RefreshDailyQueries("2026-10-26")
	if refreshedAgain {
		t.Errorf("Expected RefreshDailyQueries to return false on same date")
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

func TestIndependentModelWalletsAndCooldowns(t *testing.T) {
	now := time.Now().UTC()
	today := now.Format("2006-01-02")

	user := models.User{
		ID:                    uuid.New(),
		ClassicDaily:          3,
		ClassicAd:             0,
		ClassicPurchased:      0,
		ClassicLastRechargeAt: &now,
		FlakeAd:               0,
		FlakePurchased:        0,
		AureonAd:              0,
		AureonPurchased:       0,
	}
	user.SyncModelWalletsToTotals()

	// 1. Classic queries CANNOT be used for Flake or Aureon
	if user.ConsumeModelQuery(models.ModelFlake, now) {
		t.Fatalf("Flake no debe poder consumir consultas de Classic")
	}
	if user.ConsumeModelQuery(models.ModelAureon, now) {
		t.Fatalf("Aureon no debe poder consumir consultas de Classic")
	}

	// 2. Classic: gastar 2 consultas -> queda 1 -> tras 24h rellena +2 (tope 3, nunca 4)
	if !user.ConsumeModelQuery(models.ModelClassic, now) || !user.ConsumeModelQuery(models.ModelClassic, now) {
		t.Fatalf("Classic debió permitir consumir 2 consultas")
	}
	if user.ClassicDaily != 1 {
		t.Fatalf("Esperaba ClassicDaily=1, obtenido=%d", user.ClassicDaily)
	}
	if user.RefreshClassicDaily(now.Add(12 * time.Hour)) {
		t.Fatalf("No debe recargar antes de 24h")
	}
	if !user.RefreshClassicDaily(now.Add(24*time.Hour + time.Minute)) {
		t.Fatalf("Debió recargar tras 24h")
	}
	if user.ClassicDaily != 3 {
		t.Fatalf("Esperaba ClassicDaily=3 tras recarga, obtenido=%d", user.ClassicDaily)
	}

	// 3. AdMob Classic: +2 por anuncio
	added, ok := user.GrantAdRewardForModel(models.ModelClassic, today)
	if !ok || added != 2 || user.ClassicAd != 2 {
		t.Fatalf("Esperaba +2 en ClassicAd, obtenido added=%d ok=%v classicAd=%d", added, ok, user.ClassicAd)
	}

	// 4. AdMob Flake: +1 por anuncio, máximo 2 veces al día -> 3ra vez entra en enfriamiento
	if a1, ok1 := user.GrantAdRewardForModel(models.ModelFlake, today); !ok1 || a1 != 1 {
		t.Fatalf("Flake ad #1 falló: added=%d ok=%v", a1, ok1)
	}
	if a2, ok2 := user.GrantAdRewardForModel(models.ModelFlake, today); !ok2 || a2 != 1 {
		t.Fatalf("Flake ad #2 falló: added=%d ok=%v", a2, ok2)
	}
	if _, ok3 := user.GrantAdRewardForModel(models.ModelFlake, today); ok3 {
		t.Fatalf("Flake ad #3 debió bloquearse en enfriamiento")
	}
	if user.FlakeQueries() != 2 || user.RemainingAdsForModel(models.ModelFlake, today) != 0 {
		t.Fatalf("Esperaba FlakeQueries=2 y remaining=0, obtenido=%d / %d", user.FlakeQueries(), user.RemainingAdsForModel(models.ModelFlake, today))
	}

	// 5. AdMob Aureon: +1 por anuncio, máximo 1 vez al día -> 2da vez entra en enfriamiento
	if a1, ok1 := user.GrantAdRewardForModel(models.ModelAureon, today); !ok1 || a1 != 1 {
		t.Fatalf("Aureon ad #1 falló: added=%d ok=%v", a1, ok1)
	}
	if _, ok2 := user.GrantAdRewardForModel(models.ModelAureon, today); ok2 {
		t.Fatalf("Aureon ad #2 debió bloquearse en enfriamiento")
	}
	if user.AureonQueries() != 1 || user.RemainingAdsForModel(models.ModelAureon, today) != 0 {
		t.Fatalf("Esperaba AureonQueries=1 y remaining=0")
	}

	// 6. Al día siguiente, los límites de anuncios se reinician
	tomorrow := now.Add(24 * time.Hour).Format("2006-01-02")
	if user.RemainingAdsForModel(models.ModelFlake, tomorrow) != 2 {
		t.Fatalf("Esperaba 2 anuncios disponibles para Flake al día siguiente")
	}
	if user.RemainingAdsForModel(models.ModelAureon, tomorrow) != 1 {
		t.Fatalf("Esperaba 1 anuncio disponible para Aureon al día siguiente")
	}
}

func TestWalletV2ConsistencyAndRefund(t *testing.T) {
	now := time.Now().UTC()
	user := models.User{
		ID:                    uuid.New(),
		ClassicDaily:          1,
		ClassicAd:             0,
		ClassicPurchased:      0,
		ClassicLastRechargeAt: &now,
		GiftQueries:           2,
	}

	// Acreditar donación / referido en billeteras V2 y verificar que SyncModelWalletsToTotals no las borra
	user.AddPurchasedModelQueries(models.ModelClassic, 10)
	user.AddAdModelQueries(models.ModelClassic, 5)
	user.SyncModelWalletsToTotals()

	if user.ClassicPurchased != 10 || user.PurchasedQueries != 10 {
		t.Fatalf("Esperaba 10 compradas sincronizadas, got classic=%d legacy=%d", user.ClassicPurchased, user.PurchasedQueries)
	}
	if user.ClassicAd != 5 || user.AdQueries != 5 {
		t.Fatalf("Esperaba 5 ad sincronizadas, got classic=%d legacy=%d", user.ClassicAd, user.AdQueries)
	}
	if user.AvailableQueries != 16 {
		t.Fatalf("Esperaba 16 disponibles (1+10+5), got %d", user.AvailableQueries)
	}

	// Reservar 1 consulta y reembolsarla si falla la IA
	src, ok := user.ConsumeModelQueryWithSource(models.ModelClassic, now)
	if !ok || src != models.QuerySourceClassicDaily || user.ClassicDaily != 0 {
		t.Fatalf("Esperaba consumo de ClassicDaily, got src=%s ok=%v daily=%d", src, ok, user.ClassicDaily)
	}
	user.RefundModelQuery(src)
	if user.ClassicDaily != 1 || user.AvailableQueries != 16 {
		t.Fatalf("Esperaba reembolso exacto a ClassicDaily=1 y AvailableQueries=16, got daily=%d avail=%d", user.ClassicDaily, user.AvailableQueries)
	}

	// Transferencia V2: consume primero GiftQueries (2), luego ClassicPurchased (3)
	if !user.DeductTransferModelQueries(5) {
		t.Fatalf("Esperaba transferencia exitosa de 5 consultas")
	}
	if user.GiftQueries != 0 || user.ClassicPurchased != 7 || user.PurchasedQueries != 7 {
		t.Fatalf("Saldo post-transferencia inesperado: gift=%d classicPurchased=%d legacyPurchased=%d",
			user.GiftQueries, user.ClassicPurchased, user.PurchasedQueries)
	}
}

