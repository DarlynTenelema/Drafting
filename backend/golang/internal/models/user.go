package models

import (
	"strings"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

const (
	ModelClassic = "classic"
	ModelFlake   = "flake"
	ModelAureon  = "aureon"

	ClassicDailyCap  = 3
	ClassicAdReward  = 2
	FlakeAdReward    = 1
	FlakeMaxAdsDay   = 2
	AureonAdReward   = 1
	AureonMaxAdsDay  = 1
)

// NormalizeModelTier normaliza el identificador del modelo de IA ("classic", "flake", "aureon").
func NormalizeModelTier(raw string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "flake", "flake_1", "flake_1.0", "flake1":
		return ModelFlake
	case "aureon", "aureon_1", "aureon_1.0", "aureon1":
		return ModelAureon
	default:
		return ModelClassic
	}
}

type User struct {
	ID                     uuid.UUID      `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	GoogleID               *string        `gorm:"type:varchar(255);unique" json:"google_id,omitempty"`
	Email                  string         `gorm:"type:varchar(255);not null" json:"email"`
	Username               string         `gorm:"type:varchar(255)" json:"username"`
	ProfilePic             string         `gorm:"type:varchar(255)" json:"profile_pic"`
	Bio                    string         `gorm:"type:varchar(220);default:''" json:"bio"`
	TwitchURL              string         `gorm:"type:varchar(255);default:''" json:"twitch_url"`
	TikTokURL              string         `gorm:"type:varchar(255);default:''" json:"tiktok_url"`
	YouTubeURL             string         `gorm:"type:varchar(255);default:''" json:"youtube_url"`
	InstagramURL           string         `gorm:"type:varchar(255);default:''" json:"instagram_url"`
	KickURL                string         `gorm:"type:varchar(255);default:''" json:"kick_url"`
	LifetimeVerifiedViews  int64          `gorm:"default:0" json:"lifetime_verified_views"`
	PasswordHash           string         `gorm:"type:varchar(255)" json:"-"`
	DeviceID               string         `gorm:"type:varchar(255)" json:"device_id,omitempty"`
	SessionToken           string         `gorm:"type:varchar(255)" json:"-"`
	Role                   string         `gorm:"type:varchar(50);default:'consumer'" json:"role"`
	Banned                 bool           `gorm:"default:false" json:"banned"`
	ModerationStrikes      int            `gorm:"default:0" json:"moderation_strikes"`
	ReportTrustScore       float64        `gorm:"default:1.0" json:"report_trust_score"`
	ActivePlan             *string        `gorm:"type:varchar(50);default:'freemium'" json:"active_plan"` // 'freemium', 'plus', 'pro'

	// Consultas disponibles y sus fuentes (legacy / totales)
	AvailableQueries       int            `gorm:"default:3" json:"available_queries"`
	BonusQueries           int            `gorm:"default:0" json:"bonus_queries"`           // Legacy bono
	DailyQueries           int            `gorm:"default:3" json:"daily_queries"`             // Legacy diarias (espejo de ClassicDaily)
	AdQueries              int            `gorm:"default:0" json:"ad_queries"`               // Legacy anuncios (espejo de ClassicAd)
	PurchasedQueries       int            `gorm:"default:0" json:"purchased_queries"`        // Legacy compradas (espejo de suma compradas)
	SubscriptionQueries    int            `gorm:"default:0" json:"subscription_queries"`     // Legacy suscripción
	GiftQueries            int            `gorm:"default:0" json:"gift_queries"`             // Consultas exclusivas para regalar a amigos
	TriviaLives            int            `gorm:"default:5" json:"trivia_lives"`            // Vidas para el minijuego de trivia (5 iniciales)

	// Billeteras independientes por modelo de IA (Classic, Flake 1.0, Aureon 1.0)
	ClassicDaily           int            `gorm:"default:3" json:"classic_daily"`
	ClassicAd              int            `gorm:"default:0" json:"classic_ad"`
	ClassicPurchased       int            `gorm:"default:0" json:"classic_purchased"`
	ClassicLastRechargeAt  *time.Time     `json:"classic_last_recharge_at,omitempty"`

	FlakeAd                int            `gorm:"default:0" json:"flake_ad"`
	FlakePurchased         int            `gorm:"default:0" json:"flake_purchased"`
	FlakeAdsToday          int            `gorm:"default:0" json:"flake_ads_today"`
	FlakeLastAdDate        string         `gorm:"type:varchar(10);default:''" json:"flake_last_ad_date"`

	AureonAd               int            `gorm:"default:0" json:"aureon_ad"`
	AureonPurchased        int            `gorm:"default:0" json:"aureon_purchased"`
	AureonAdsToday         int            `gorm:"default:0" json:"aureon_ads_today"`
	AureonLastAdDate       string         `gorm:"type:varchar(10);default:''" json:"aureon_last_ad_date"`

	ModelsV2Migrated       bool           `gorm:"default:false" json:"-"`

	// Suscripción mensual
	SubscriptionPlan       string         `gorm:"type:varchar(50);default:'none'" json:"subscription_plan"` // 'none', 'plus', 'pro', 'ultra'
	SubscriptionEndsAt     *time.Time     `json:"subscription_ends_at"`
	HasPurchasedStarter    bool           `gorm:"default:false" json:"has_purchased_starter"` // True tras comprar Pack Starter $0.19 (desaparece)

	// Sistema de compartir consultas (Máximo 10 por día para suscriptores)
	DailyTransferredToday  int            `gorm:"default:0" json:"daily_transferred_today"`
	LastTransferDate       string         `gorm:"type:varchar(10);default:''" json:"last_transfer_date"`
	DailyReceivedToday     int            `gorm:"default:0" json:"daily_received_today"`
	LastReceivedDate       string         `gorm:"type:varchar(10);default:''" json:"last_received_date"`

	LastDailyRewardDate    string         `gorm:"type:varchar(10);default:''" json:"last_daily_reward_date"`
	ReferralCode           string         `gorm:"type:varchar(16);index" json:"referral_code"`
	ReferredByID           *uuid.UUID     `gorm:"type:uuid;index" json:"referred_by_id,omitempty"`
	ReferredByStreamerCode string         `gorm:"type:varchar(32);default:'';index" json:"referred_by_streamer_code,omitempty"`
	ReferralCount          int            `gorm:"default:0" json:"referral_count"`
	ReferralRewardsClaimed int            `gorm:"default:0" json:"referral_rewards_claimed"`
	LastDraftAt            time.Time      `json:"last_draft_at"`
	CreatedAt              time.Time      `json:"created_at"`
	UpdatedAt              time.Time      `json:"updated_at"`
	DeletedAt              gorm.DeletedAt `gorm:"index" json:"-"`
}

func GenerateReferralCode(id uuid.UUID) string {
	clean := strings.ToUpper(strings.ReplaceAll(id.String(), "-", ""))
	if len(clean) >= 6 {
		return "WR" + clean[:6]
	}
	return "WR" + clean
}

// CheckSubscriptionExpiry verifica y actualiza el plan si ya venció el ciclo de suscripción
func (user *User) CheckSubscriptionExpiry() bool {
	if user.SubscriptionEndsAt != nil && time.Now().After(*user.SubscriptionEndsAt) {
		user.SubscriptionPlan = "none"
		// Las consultas no caducan al acabar el mes; se conservan y acumulan
		user.SubscriptionEndsAt = nil
		user.RecalculateAvailableQueries()
		return true
	}
	return false
}

// IsSubscribed indica si el usuario tiene una suscripción activa vigente
func (user *User) IsSubscribed() bool {
	user.CheckSubscriptionExpiry()
	return user.SubscriptionPlan != "" && user.SubscriptionPlan != "none" && user.SubscriptionEndsAt != nil && time.Now().Before(*user.SubscriptionEndsAt)
}

// CanTransfer indica si el usuario tiene permisos para compartir consultas con amigos
// (Todos los paquetes comprados, usuarios con Pack Starter o suscriptores pueden compartir)
func (user *User) CanTransfer() bool {
	return user.IsSubscribed() || user.HasPurchasedStarter || user.PurchasedQueries > 0 || user.GiftQueries > 0
}

// RecalculateAvailableQueries actualiza la suma total de consultas disponibles
func (user *User) RecalculateAvailableQueries() {
	user.AvailableQueries = user.DailyQueries + user.BonusQueries + user.AdQueries + user.PurchasedQueries + user.SubscriptionQueries
	if user.AvailableQueries < 0 {
		user.AvailableQueries = 0
	}
}

// ConsumeQuery descuenta 1 consulta con el orden de prioridad más conveniente para el usuario:
// 1) Diarias (vencen hoy si no se usan)
// 2) Suscripción (se renuevan/vencen mensualmente)
// 3) Bono de bienvenida
// 4) Recargas por anuncios / referidos
// 5) Consultas compradas en paquetes (permanentes, se guardan al final)
func (user *User) ConsumeQuery() bool {
	user.CheckSubscriptionExpiry()
	user.RecalculateAvailableQueries()
	if user.AvailableQueries <= 0 {
		return false
	}
	if user.DailyQueries > 0 {
		user.DailyQueries--
	} else if user.SubscriptionQueries > 0 {
		user.SubscriptionQueries--
	} else if user.BonusQueries > 0 {
		user.BonusQueries--
	} else if user.AdQueries > 0 {
		user.AdQueries--
	} else if user.PurchasedQueries > 0 {
		user.PurchasedQueries--
	}
	user.RecalculateAvailableQueries()
	return true
}

// DeductTransferQueries descuenta consultas para compartir con un amigo,
// priorizando las GiftQueries (exclusivas de regalo), luego Suscripción, Compradas, Anuncios, Bono y Diarias.
func (user *User) DeductTransferQueries(amount int) bool {
	if amount <= 0 {
		return false
	}
	user.CheckSubscriptionExpiry()
	user.RecalculateAvailableQueries()
	if user.GiftQueries+user.AvailableQueries < amount {
		return false
	}

	remaining := amount
	buckets := []*int{
		&user.GiftQueries,
		&user.SubscriptionQueries,
		&user.PurchasedQueries,
		&user.AdQueries,
		&user.BonusQueries,
		&user.DailyQueries,
	}

	for _, bucket := range buckets {
		if remaining <= 0 {
			break
		}
		if *bucket > 0 {
			if *bucket >= remaining {
				*bucket -= remaining
				remaining = 0
			} else {
				remaining -= *bucket
				*bucket = 0
			}
		}
	}

	user.RecalculateAvailableQueries()
	return remaining == 0
}

// AddAdQueries suma consultas por ver anuncios o logros de referidos
func (user *User) AddAdQueries(amount int) {
	user.AdQueries += amount
	user.RecalculateAvailableQueries()
}

// AddPurchasedQueries agrega consultas compradas de forma permanente
func (user *User) AddPurchasedQueries(amount int) {
	user.PurchasedQueries += amount
	user.RecalculateAvailableQueries()
}

// RefreshDailyQueries (Ajuste de control 2027):
// Solo si el sistema detecta que el usuario tiene MENOS de 3 consultas totales disponibles y han pasado 24 horas (nuevo día),
// le regala únicamente las que hagan falta para completar las 3 (ej. si tiene 1 le da 2, si tiene 2 le da 1, si tiene >= 3 no le da nada).
func (user *User) RefreshDailyQueries(today string) bool {
	user.CheckSubscriptionExpiry()
	user.RecalculateAvailableQueries()
	if user.LastDailyRewardDate != today {
		user.LastDailyRewardDate = today
		if user.AvailableQueries < 3 {
			needed := 3 - user.AvailableQueries
			user.DailyQueries += needed
			if user.DailyQueries > 3 {
				user.DailyQueries = 3
			}
			user.RecalculateAvailableQueries()
			return true
		}
	}
	return false
}

// ResetDailyLimitsIfNewDay reinicia los contadores diarios de transferencias recibidas y enviadas
func (user *User) ResetDailyLimitsIfNewDay(today string) {
	if user.LastTransferDate != today {
		user.DailyTransferredToday = 0
		user.LastTransferDate = today
	}
	if user.LastReceivedDate != today {
		user.DailyReceivedToday = 0
		user.LastReceivedDate = today
	}
}

// ConsumeTriviaLife descuenta 1 vida de trivia si el usuario tiene vidas disponibles
func (user *User) ConsumeTriviaLife() bool {
	if user.TriviaLives <= 0 {
		return false
	}
	user.TriviaLives--
	return true
}

// AddTriviaLives suma vidas de trivia (por anuncios o compras de paquetes)
func (user *User) AddTriviaLives(amount int) {
	if amount > 0 {
		user.TriviaLives += amount
	}
}

// ClassicQueries retorna el saldo total del modelo Classic
func (user *User) ClassicQueries() int {
	total := user.ClassicDaily + user.ClassicAd + user.ClassicPurchased
	if total < 0 {
		return 0
	}
	return total
}

// FlakeQueries retorna el saldo total del modelo Flake 1.0
func (user *User) FlakeQueries() int {
	total := user.FlakeAd + user.FlakePurchased
	if total < 0 {
		return 0
	}
	return total
}

// AureonQueries retorna el saldo total del modelo Aureon 1.0
func (user *User) AureonQueries() int {
	total := user.AureonAd + user.AureonPurchased
	if total < 0 {
		return 0
	}
	return total
}

// QueriesForModel retorna las consultas disponibles estrictamente para el modelo solicitado
func (user *User) QueriesForModel(tier string) int {
	switch NormalizeModelTier(tier) {
	case ModelFlake:
		return user.FlakeQueries()
	case ModelAureon:
		return user.AureonQueries()
	default:
		return user.ClassicQueries()
	}
}

// SyncModelWalletsToTotals sincroniza los campos agregados con las 3 billeteras independientes
func (user *User) SyncModelWalletsToTotals() {
	if user.ClassicDaily < 0 {
		user.ClassicDaily = 0
	}
	if user.ClassicDaily > ClassicDailyCap {
		user.ClassicDaily = ClassicDailyCap
	}
	if user.ClassicAd < 0 {
		user.ClassicAd = 0
	}
	if user.ClassicPurchased < 0 {
		user.ClassicPurchased = 0
	}
	if user.FlakeAd < 0 {
		user.FlakeAd = 0
	}
	if user.FlakePurchased < 0 {
		user.FlakePurchased = 0
	}
	if user.AureonAd < 0 {
		user.AureonAd = 0
	}
	if user.AureonPurchased < 0 {
		user.AureonPurchased = 0
	}

	user.DailyQueries = user.ClassicDaily
	user.AdQueries = user.ClassicAd + user.FlakeAd + user.AureonAd
	user.PurchasedQueries = user.ClassicPurchased + user.FlakePurchased + user.AureonPurchased
	user.AvailableQueries = user.ClassicQueries() + user.FlakeQueries() + user.AureonQueries()
}

// RefreshClassicDaily rellena únicamente las consultas diarias faltantes de Classic hasta el tope de 3
// una vez transcurridas 24 horas desde que el usuario gastó (o desde el reset). Nunca supera 3.
func (user *User) RefreshClassicDaily(now time.Time) bool {
	if user.ClassicDaily >= ClassicDailyCap {
		user.ClassicDaily = ClassicDailyCap
		return false
	}
	if user.ClassicLastRechargeAt == nil {
		t := now.UTC()
		user.ClassicLastRechargeAt = &t
		return false
	}
	if now.UTC().Sub(user.ClassicLastRechargeAt.UTC()) >= 24*time.Hour {
		user.ClassicDaily = ClassicDailyCap
		t := now.UTC()
		user.ClassicLastRechargeAt = &t
		user.LastDailyRewardDate = t.Format("2006-01-02")
		user.SyncModelWalletsToTotals()
		return true
	}
	return false
}

// ResetModelAdLimitsIfNewDay reinicia los contadores diarios de anuncios de Flake (max 2/día) y Aureon (max 1/día)
func (user *User) ResetModelAdLimitsIfNewDay(today string) bool {
	changed := false
	if user.FlakeLastAdDate != today {
		if user.FlakeAdsToday != 0 {
			changed = true
		}
		user.FlakeAdsToday = 0
		user.FlakeLastAdDate = today
	}
	if user.AureonLastAdDate != today {
		if user.AureonAdsToday != 0 {
			changed = true
		}
		user.AureonAdsToday = 0
		user.AureonLastAdDate = today
	}
	return changed
}

// RemainingAdsForModel retorna cuántos anuncios bonificados le quedan hoy al usuario para un modelo (-1 = ilimitado)
func (user *User) RemainingAdsForModel(tier, today string) int {
	user.ResetModelAdLimitsIfNewDay(today)
	switch NormalizeModelTier(tier) {
	case ModelFlake:
		rem := FlakeMaxAdsDay - user.FlakeAdsToday
		if rem < 0 {
			return 0
		}
		return rem
	case ModelAureon:
		rem := AureonMaxAdsDay - user.AureonAdsToday
		if rem < 0 {
			return 0
		}
		return rem
	default:
		return -1
	}
}

// GrantAdRewardForModel otorga la recompensa de AdMob del modelo indicado respetando topes diarios:
// - Classic: +2 (sin tope diario, cooldown de 15s en handler)
// - Flake 1.0: +1 (máximo 2 veces al día)
// - Aureon 1.0: +1 (máximo 1 vez al día)
func (user *User) GrantAdRewardForModel(tier, today string) (added int, ok bool) {
	user.ResetModelAdLimitsIfNewDay(today)
	switch NormalizeModelTier(tier) {
	case ModelFlake:
		if user.FlakeAdsToday >= FlakeMaxAdsDay {
			return 0, false
		}
		user.FlakeAdsToday++
		user.FlakeLastAdDate = today
		user.FlakeAd += FlakeAdReward
		user.SyncModelWalletsToTotals()
		return FlakeAdReward, true
	case ModelAureon:
		if user.AureonAdsToday >= AureonMaxAdsDay {
			return 0, false
		}
		user.AureonAdsToday++
		user.AureonLastAdDate = today
		user.AureonAd += AureonAdReward
		user.SyncModelWalletsToTotals()
		return AureonAdReward, true
	default:
		user.ClassicAd += ClassicAdReward
		user.SyncModelWalletsToTotals()
		return ClassicAdReward, true
	}
}

// AddPurchasedModelQueries acredita consultas compradas en la billetera exclusiva del modelo
func (user *User) AddPurchasedModelQueries(tier string, amount int) {
	if amount <= 0 {
		return
	}
	switch NormalizeModelTier(tier) {
	case ModelFlake:
		user.FlakePurchased += amount
	case ModelAureon:
		user.AureonPurchased += amount
	default:
		user.ClassicPurchased += amount
	}
	user.SyncModelWalletsToTotals()
}

// AddAdModelQueries acredita consultas de bonificación/anuncio/referido en la billetera del modelo indicado
func (user *User) AddAdModelQueries(tier string, amount int) {
	if amount <= 0 {
		return
	}
	switch NormalizeModelTier(tier) {
	case ModelFlake:
		user.FlakeAd += amount
	case ModelAureon:
		user.AureonAd += amount
	default:
		user.ClassicAd += amount
	}
	user.SyncModelWalletsToTotals()
}

// DeductTransferModelQueries descuenta consultas para compartir con un amigo manteniendo sincronizadas
// las billeteras V2 (prioridad: GiftQueries -> ClassicPurchased -> ClassicAd -> ClassicDaily -> Flake/Aureon).
func (user *User) DeductTransferModelQueries(amount int) bool {
	if amount <= 0 {
		return false
	}
	user.CheckSubscriptionExpiry()
	user.SyncModelWalletsToTotals()
	if user.GiftQueries+user.AvailableQueries < amount {
		return false
	}

	remaining := amount
	buckets := []*int{
		&user.GiftQueries,
		&user.ClassicPurchased,
		&user.ClassicAd,
		&user.ClassicDaily,
		&user.FlakePurchased,
		&user.FlakeAd,
		&user.AureonPurchased,
		&user.AureonAd,
	}

	for _, bucket := range buckets {
		if remaining <= 0 {
			break
		}
		if *bucket > 0 {
			if *bucket >= remaining {
				*bucket -= remaining
				remaining = 0
			} else {
				remaining -= *bucket
				*bucket = 0
			}
		}
	}

	user.SyncModelWalletsToTotals()
	return remaining == 0
}

// ConsumeModelQuerySource indica exactamente de qué bolsa se descontó una consulta para poder reembolsarla si falla la IA.
type ConsumeModelQuerySource string

const (
	QuerySourceNone            ConsumeModelQuerySource = ""
	QuerySourceClassicDaily    ConsumeModelQuerySource = "classic_daily"
	QuerySourceClassicAd       ConsumeModelQuerySource = "classic_ad"
	QuerySourceClassicPurchase ConsumeModelQuerySource = "classic_purchased"
	QuerySourceFlakeAd         ConsumeModelQuerySource = "flake_ad"
	QuerySourceFlakePurchase   ConsumeModelQuerySource = "flake_purchased"
	QuerySourceAureonAd        ConsumeModelQuerySource = "aureon_ad"
	QuerySourceAureonPurchase  ConsumeModelQuerySource = "aureon_purchased"
)

// ConsumeModelQueryWithSource descuenta 1 consulta del modelo elegido y retorna la fuente exacta para reembolso atómico si la IA falla.
func (user *User) ConsumeModelQueryWithSource(tier string, now time.Time) (ConsumeModelQuerySource, bool) {
	switch NormalizeModelTier(tier) {
	case ModelFlake:
		if user.FlakeQueries() <= 0 {
			return QuerySourceNone, false
		}
		src := QuerySourceNone
		if user.FlakeAd > 0 {
			user.FlakeAd--
			src = QuerySourceFlakeAd
		} else if user.FlakePurchased > 0 {
			user.FlakePurchased--
			src = QuerySourceFlakePurchase
		}
		user.SyncModelWalletsToTotals()
		return src, src != QuerySourceNone

	case ModelAureon:
		if user.AureonQueries() <= 0 {
			return QuerySourceNone, false
		}
		src := QuerySourceNone
		if user.AureonAd > 0 {
			user.AureonAd--
			src = QuerySourceAureonAd
		} else if user.AureonPurchased > 0 {
			user.AureonPurchased--
			src = QuerySourceAureonPurchase
		}
		user.SyncModelWalletsToTotals()
		return src, src != QuerySourceNone

	default:
		if user.ClassicQueries() <= 0 {
			return QuerySourceNone, false
		}
		src := QuerySourceNone
		if user.ClassicDaily > 0 {
			wasFull := user.ClassicDaily >= ClassicDailyCap
			user.ClassicDaily--
			src = QuerySourceClassicDaily
			if wasFull || user.ClassicLastRechargeAt == nil {
				t := now.UTC()
				user.ClassicLastRechargeAt = &t
			}
		} else if user.ClassicAd > 0 {
			user.ClassicAd--
			src = QuerySourceClassicAd
		} else if user.ClassicPurchased > 0 {
			user.ClassicPurchased--
			src = QuerySourceClassicPurchase
		}
		user.SyncModelWalletsToTotals()
		return src, src != QuerySourceNone
	}
}

// RefundModelQuery devuelve 1 consulta a la bolsa exacta de la que se descontó (por ejemplo si Vertex AI falla).
func (user *User) RefundModelQuery(src ConsumeModelQuerySource) {
	switch src {
	case QuerySourceClassicDaily:
		if user.ClassicDaily < ClassicDailyCap {
			user.ClassicDaily++
		} else {
			user.ClassicAd++
		}
	case QuerySourceClassicAd:
		user.ClassicAd++
	case QuerySourceClassicPurchase:
		user.ClassicPurchased++
	case QuerySourceFlakeAd:
		user.FlakeAd++
	case QuerySourceFlakePurchase:
		user.FlakePurchased++
	case QuerySourceAureonAd:
		user.AureonAd++
	case QuerySourceAureonPurchase:
		user.AureonPurchased++
	default:
		return
	}
	user.SyncModelWalletsToTotals()
}

// ConsumeModelQuery descuenta estrictamente 1 consulta del modelo elegido (sin cruzar saldos entre modelos).
// Prioridad: Diarias (solo Classic) -> Anuncios -> Compradas.
func (user *User) ConsumeModelQuery(tier string, now time.Time) bool {
	_, ok := user.ConsumeModelQueryWithSource(tier, now)
	return ok
}

func (user *User) BeforeCreate(tx *gorm.DB) (err error) {
	if user.ID == uuid.Nil {
		user.ID = uuid.New()
	}
	if user.TriviaLives == 0 {
		user.TriviaLives = 5
	}
	if !user.ModelsV2Migrated && user.ClassicDaily == 0 && user.ClassicAd == 0 && user.ClassicPurchased == 0 && user.AvailableQueries == 0 {
		now := time.Now().UTC()
		user.ClassicDaily = ClassicDailyCap
		user.ClassicLastRechargeAt = &now
		user.DailyQueries = ClassicDailyCap
		user.BonusQueries = 0
		user.AdQueries = 0
		user.PurchasedQueries = 0
		user.SubscriptionQueries = 0
		user.SubscriptionPlan = "none"
		user.AvailableQueries = ClassicDailyCap
		user.LastDailyRewardDate = now.Format("2006-01-02")
		user.ModelsV2Migrated = true
	} else if user.AvailableQueries == 0 {
		user.RecalculateAvailableQueries()
	}
	if user.ReferralCode == "" {
		user.ReferralCode = GenerateReferralCode(user.ID)
	}
	return
}
