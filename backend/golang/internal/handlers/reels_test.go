package handlers

import (
	"math"
	"testing"
	"time"

	"backend/internal/models"

	"github.com/google/uuid"
)

func TestViewTokenSignAndVerify(t *testing.T) {
	payload := viewTokenPayload{
		ReelID:          "11111111-1111-1111-1111-111111111111",
		UserID:          "22222222-2222-2222-2222-222222222222",
		DurationSeconds: 20,
		StartedAt:       time.Now().UTC().Unix() - 18,
	}

	token, err := signViewToken(payload)
	if err != nil {
		t.Fatalf("expected no error signing view token, got %v", err)
	}

	parsed, ok := verifyViewToken(token)
	if !ok || parsed == nil {
		t.Fatalf("expected valid view token")
	}
	if parsed.ReelID != payload.ReelID || parsed.UserID != payload.UserID || parsed.DurationSeconds != 20 {
		t.Fatalf("unexpected parsed payload: %+v", parsed)
	}

	// Token manipulado debe ser rechazado
	if _, ok := verifyViewToken(token + "tampered"); ok {
		t.Fatalf("expected tampered token to be rejected")
	}
}

func TestCreatorPayoutRate(t *testing.T) {
	// Modelo de negocio: $0.01 por cada 1,000 vistas verificadas y mínimo $100 USD
	earned1k := math.Round(1000*CreatorPayoutPerViewUSD*10000) / 10000
	if earned1k != 0.01 {
		t.Fatalf("expected $0.01 per 1,000 views, got %.6f", earned1k)
	}
	if MinCreatorPayoutUSD != 100.0 {
		t.Fatalf("expected $100 minimum payout, got %.2f", MinCreatorPayoutUSD)
	}
}

func TestFeedCompositeCursor(t *testing.T) {
	id := uuid.New()
	now := time.Now().UTC().Truncate(time.Microsecond)
	cursor := encodeFeedCursor(42.125, now, id)
	score, ts, parsedID, isComp, ok := decodeFeedCursor(cursor)
	if !ok || !isComp {
		t.Fatalf("expected valid composite cursor")
	}
	if math.Abs(score-42.125) > 1e-6 || !ts.Equal(now) || parsedID != id {
		t.Fatalf("cursor mismatch: score=%v ts=%v id=%v", score, ts, parsedID)
	}
}

func TestDetectVideoOrientation(t *testing.T) {
	if got := detectVideoOrientation(1280, 720, ""); got != "landscape" {
		t.Fatalf("expected landscape for 1280x720, got %s", got)
	}
	if got := detectVideoOrientation(720, 1280, ""); got != "portrait" {
		t.Fatalf("expected portrait for 720x1280, got %s", got)
	}
	if got := detectVideoOrientation(0, 0, "landscape"); got != "landscape" {
		t.Fatalf("expected landscape fallback, got %s", got)
	}
}

func TestValidateSocialURL(t *testing.T) {
	if u, err := validateSocialURL("twitch.tv/faker", []string{"twitch.tv"}); err != nil || u != "https://twitch.tv/faker" {
		t.Fatalf("expected valid twitch URL, got %q err=%v", u, err)
	}
	if _, err := validateSocialURL("https://evil.com/twitch.tv", []string{"twitch.tv"}); err == nil {
		t.Fatalf("expected non-whitelisted host to fail")
	}
}

func TestCalculateReportWeightAntiBrigading(t *testing.T) {
	now := time.Now().UTC()

	freshUser := &models.User{CreatedAt: now.Add(-2 * time.Hour), ReportTrustScore: 1.0}
	if w := calculateReportWeight(freshUser, now); w != 0.25 {
		t.Fatalf("expected 0.25 weight for <24h account, got %.2f", w)
	}

	veteranUser := &models.User{CreatedAt: now.Add(-30 * 24 * time.Hour), ReportTrustScore: 1.0}
	if w := calculateReportWeight(veteranUser, now); w != 1.0 {
		t.Fatalf("expected 1.0 weight for veteran account, got %.2f", w)
	}

	falseReporter := &models.User{CreatedAt: now.Add(-30 * 24 * time.Hour), ReportTrustScore: 0.2}
	if w := calculateReportWeight(falseReporter, now); w != 0.2 {
		t.Fatalf("expected 0.20 weight for penalized reporter, got %.2f", w)
	}
}

func TestShouldQuarantineReelRules(t *testing.T) {
	// Bajo en vistas: 3.0 puntos ponderados bastan para cuarentena inmediata
	if !shouldQuarantineReel(3.0, 50, ModerationStatusApproved, "harassment_hate") {
		t.Fatalf("expected quarantine at 3.0 weighted score for low-view reel")
	}
	// Por debajo del umbral no silencia
	if shouldQuarantineReel(2.5, 50, ModerationStatusApproved, "harassment_hate") {
		t.Fatalf("did not expect quarantine below 3.0 weighted score")
	}
	// Video viral (1,000 vistas): 3 reportes (0.3%) NO deben silenciar (anti-brigading)
	if shouldQuarantineReel(3.0, 1000, ModerationStatusApproved, "harassment_hate") {
		t.Fatalf("did not expect viral reel to be quarantined by 3 reports")
	}
	// Video verificado por admin (verified_safe): inmune a brigading de insultos, pero responde a consenso fuerte NSFW/Gore
	if shouldQuarantineReel(4.0, 50, ModerationStatusVerifiedSafe, "harassment_hate") {
		t.Fatalf("verified_safe reel should resist non-NSFW brigading")
	}
	if !shouldQuarantineReel(5.0, 1000, ModerationStatusVerifiedSafe, "nsfw_gore") {
		t.Fatalf("verified_safe reel should quarantine on strong nsfw_gore consensus")
	}
}

func TestNormalizeReportReason(t *testing.T) {
	if got := normalizeReportReason("nsfw_gore"); got != "nsfw_gore" {
		t.Fatalf("expected nsfw_gore, got %s", got)
	}
	if got := normalizeReportReason("offensive"); got != "harassment_hate" {
		t.Fatalf("expected harassment_hate for legacy offensive, got %s", got)
	}
	if got := normalizeReportReason("misleading"); got != "impersonation_stolen" {
		t.Fatalf("expected impersonation_stolen for legacy misleading, got %s", got)
	}
}

func TestReelsFeedCacheIsolationAndInvalidation(t *testing.T) {
	invalidateReelsFeedCache()
	key := buildReelsFeedCacheKey("es", "jugadas", "wild_rift", "", 10)

	reelID := uuid.New()
	creatorID := uuid.New()
	input := []models.Reel{
		{
			ID:        reelID,
			CreatorID: creatorID,
			Title:     "Pentakill",
			HasLiked:  true,
			HasSaved:  true,
		},
	}
	setCachedFeedPage(key, input, "cursor-1")

	got1, cursor1, ok := getCachedFeedPage(key)
	if !ok || cursor1 != "cursor-1" || len(got1) != 1 {
		t.Fatalf("expected cache hit with 1 reel, got ok=%v cursor=%q len=%d", ok, cursor1, len(got1))
	}
	// Las banderas privadas nunca deben guardarse ni filtrarse entre usuarios
	if got1[0].HasLiked || got1[0].HasSaved || got1[0].IsFollowing {
		t.Fatalf("expected user-specific flags to be stripped in cache")
	}

	// Mutar la copia devuelta no debe contaminar futuras lecturas de otros usuarios
	got1[0].HasLiked = true
	got2, _, ok := getCachedFeedPage(key)
	if !ok || got2[0].HasLiked {
		t.Fatalf("expected cached slice to be isolated across callers")
	}

	invalidateReelsFeedCache()
	if _, _, ok := getCachedFeedPage(key); ok {
		t.Fatalf("expected cache miss after invalidation")
	}
}

func TestReelMetaCacheHitAndInvalidation(t *testing.T) {
	reelID := uuid.New()
	creatorID := uuid.New()
	setCachedReelMeta(reelID, creatorID, 22)

	gotCreator, gotDur, ok := getCachedReelMeta(reelID)
	if !ok || gotCreator != creatorID || gotDur != 22 {
		t.Fatalf("expected meta cache hit, got ok=%v creator=%v dur=%d", ok, gotCreator, gotDur)
	}

	invalidateReelMeta(reelID)
	if _, _, ok := getCachedReelMeta(reelID); ok {
		t.Fatalf("expected meta cache miss after invalidation")
	}
}

func TestModerationConcurrencySemaphore(t *testing.T) {
	sem := getModerationSem()
	capacity := cap(sem)
	if capacity < 1 {
		t.Fatalf("expected semaphore capacity >= 1, got %d", capacity)
	}

	releases := make([]func(), 0, capacity)
	for i := 0; i < capacity; i++ {
		rel, ok := acquireModerationSlot(100 * time.Millisecond)
		if !ok {
			t.Fatalf("expected to acquire slot %d", i)
		}
		releases = append(releases, rel)
	}

	// Con todos los slots ocupados, una nueva solicitud debe esperar y expirar con timeout corto
	if _, ok := acquireModerationSlot(25 * time.Millisecond); ok {
		t.Fatalf("expected semaphore to block when full")
	}

	// Liberar un slot y confirmar que vuelve a aceptar trabajo
	releases[0]()
	relExtra, ok := acquireModerationSlot(100 * time.Millisecond)
	if !ok {
		t.Fatalf("expected to acquire slot after release")
	}
	relExtra()
	for i := 1; i < len(releases); i++ {
		releases[i]()
	}
}

func TestUploadQuotaDefaults(t *testing.T) {
	veteran := &models.User{CreatedAt: time.Now().UTC().Add(-48 * time.Hour)}
	if got := getUserDailyReelLimit(veteran); got != MaxReelsPerDayPerCreator {
		t.Fatalf("expected daily limit %d, got %d", MaxReelsPerDayPerCreator, got)
	}
	fresh := &models.User{CreatedAt: time.Now().UTC().Add(-2 * time.Hour)}
	if got := getUserDailyReelLimit(fresh); got != NewAccountMaxReelsPerDay {
		t.Fatalf("expected new-account daily limit %d, got %d", NewAccountMaxReelsPerDay, got)
	}
	if got := getUserWeeklyReelLimit(); got != DefaultMaxReelsPerWeekPerCreator {
		t.Fatalf("expected weekly limit %d, got %d", DefaultMaxReelsPerWeekPerCreator, got)
	}
	if got := getGlobalDailyReelLimit(); got != DefaultMaxGlobalReelsPerDay {
		t.Fatalf("expected global daily limit %d, got %d", DefaultMaxGlobalReelsPerDay, got)
	}
}
