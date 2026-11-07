package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// StreamerApplication almacena los creadores/streamers afiliados y su rendimiento de comisiones
type StreamerApplication struct {
	ID               uuid.UUID      `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	Name             string         `gorm:"type:varchar(120);not null" json:"name"`
	Email            string         `gorm:"type:varchar(255);not null;index" json:"email"`
	Platform         string         `gorm:"type:varchar(50);not null" json:"platform"` // tiktok, twitch, youtube, facebook, kick
	ChannelURL       string         `gorm:"type:varchar(500);not null" json:"channel_url"`
	FollowersCount   int            `gorm:"default:0" json:"followers_count"`
	PromoCode        string         `gorm:"type:varchar(32);uniqueIndex;not null" json:"promo_code"`
	WantsCaster      bool           `gorm:"default:false" json:"wants_caster"`
	PaymentMethod    string         `gorm:"type:varchar(100);default:'paypal'" json:"payment_method"`
	PaymentDetails   string         `gorm:"type:varchar(255);default:''" json:"payment_details,omitempty"`
	Status           string         `gorm:"type:varchar(32);default:'approved'" json:"status"` // approved, pending, paused
	CommissionRate   float64        `gorm:"type:decimal(5,2);default:0.25" json:"commission_rate"`
	TotalReferrals   int            `gorm:"default:0" json:"total_referrals"`
	TotalSalesCount  int            `gorm:"default:0" json:"total_sales_count"`
	TotalEarningsUSD float64        `gorm:"type:decimal(10,2);default:0.00" json:"total_earnings_usd"`
	CreatedAt        time.Time      `json:"created_at"`
	UpdatedAt        time.Time      `json:"updated_at"`
	DeletedAt        gorm.DeletedAt `gorm:"index" json:"-"`
}

func (s *StreamerApplication) BeforeCreate(tx *gorm.DB) (err error) {
	if s.ID == uuid.Nil {
		s.ID = uuid.New()
	}
	return
}

// StreamerCommission registra cada venta en la tienda que generó comisión para un streamer
type StreamerCommission struct {
	ID              uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	StreamerID      uuid.UUID `gorm:"type:uuid;index;not null" json:"streamer_id"`
	PromoCode       string    `gorm:"type:varchar(32);index;not null" json:"promo_code"`
	BuyerUserID     uuid.UUID `gorm:"type:uuid;index;not null" json:"buyer_user_id"`
	TransactionID   uuid.UUID `gorm:"type:uuid;index;not null" json:"transaction_id"`
	ItemKey         string    `gorm:"type:varchar(50);not null" json:"item_key"`
	SaleAmountUSD   float64   `gorm:"type:decimal(10,2);not null" json:"sale_amount_usd"`
	CommissionUSD   float64   `gorm:"type:decimal(10,2);not null" json:"commission_usd"`
	Status          string    `gorm:"type:varchar(32);default:'credited'" json:"status"` // credited, paid
	CreatedAt       time.Time `json:"created_at"`
}

func (c *StreamerCommission) BeforeCreate(tx *gorm.DB) (err error) {
	if c.ID == uuid.Nil {
		c.ID = uuid.New()
	}
	return
}

// SponsorInquiry almacena solicitudes de patrocinadores, marcas o streamers que quieren anunciarse en la App o Torneo C.L.A
type SponsorInquiry struct {
	ID                 uuid.UUID      `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	BrandName          string         `gorm:"type:varchar(150);not null" json:"brand_name"`
	ContactName        string         `gorm:"type:varchar(120);not null" json:"contact_name"`
	ContactEmail       string         `gorm:"type:varchar(255);not null" json:"contact_email"`
	WhatsappOrDiscord  string         `gorm:"type:varchar(120);not null" json:"whatsapp_or_discord"`
	PlanType           string         `gorm:"type:varchar(64);not null" json:"plan_type"` // streamer_slot, cla_video_exchange, cla_sponsor, app_banner
	Modality           string         `gorm:"type:varchar(50);default:'paid'" json:"modality"` // paid, video_exchange
	BudgetUSD          float64        `gorm:"type:decimal(10,2);default:0.00" json:"budget_usd"`
	TargetURL          string         `gorm:"type:varchar(500);default:''" json:"target_url"`
	Message            string         `gorm:"type:text" json:"message"`
	Status             string         `gorm:"type:varchar(32);default:'pending'" json:"status"`
	CreatedAt          time.Time      `json:"created_at"`
	DeletedAt          gorm.DeletedAt `gorm:"index" json:"-"`
}

func (s *SponsorInquiry) BeforeCreate(tx *gorm.DB) (err error) {
	if s.ID == uuid.Nil {
		s.ID = uuid.New()
	}
	return
}

// TournamentRegistration almacena inscripciones de Escuadras (Equipos) y Casters para la Copa Latino Americana Anónima "C.L.A"
type TournamentRegistration struct {
	ID               uuid.UUID      `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	RegistrationType string         `gorm:"type:varchar(32);not null;default:'team'" json:"registration_type"` // team, caster
	TeamName         string         `gorm:"type:varchar(120);not null" json:"team_name"`
	TeamTag          string         `gorm:"type:varchar(16);default:''" json:"team_tag"`
	CaptainName      string         `gorm:"type:varchar(120);not null" json:"captain_name"`
	ContactDiscord   string         `gorm:"type:varchar(120);not null" json:"contact_discord"`
	ContactWhatsapp  string         `gorm:"type:varchar(120);default:''" json:"contact_whatsapp"`
	AverageRank      string         `gorm:"type:varchar(64);default:'Diamante'" json:"average_rank"`
	ServerRegion     string         `gorm:"type:varchar(64);default:'LAN / LAS'" json:"server_region"`
	RosterNotes      string         `gorm:"type:text" json:"roster_notes"`
	DraftingCode     string         `gorm:"type:varchar(32);default:''" json:"drafting_code"`
	Status           string         `gorm:"type:varchar(32);default:'registered'" json:"status"` // registered, verified
	CreatedAt        time.Time      `json:"created_at"`
	DeletedAt        gorm.DeletedAt `gorm:"index" json:"-"`
}

func (t *TournamentRegistration) BeforeCreate(tx *gorm.DB) (err error) {
	if t.ID == uuid.Nil {
		t.ID = uuid.New()
	}
	return
}

// CommunityVote almacena los votos de los usuarios sobre qué actualización quieren primero en Drafting
type CommunityVote struct {
	ID              uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	FeatureKey      string    `gorm:"type:varchar(64);index;not null" json:"feature_key"`
	VoterIdentifier string    `gorm:"type:varchar(255);index;not null" json:"voter_identifier"`
	SuggestionText  string    `gorm:"type:text;default:''" json:"suggestion_text,omitempty"`
	CreatedAt       time.Time `json:"created_at"`
}

func (v *CommunityVote) BeforeCreate(tx *gorm.DB) (err error) {
	if v.ID == uuid.Nil {
		v.ID = uuid.New()
	}
	return
}

// NewsletterSubscriber almacena usuarios suscritos a noticias, parches y avisos de la Copa C.L.A
type NewsletterSubscriber struct {
	ID           uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	Email        string    `gorm:"type:varchar(255);uniqueIndex;not null" json:"email"`
	PlayerCode   string    `gorm:"type:varchar(32);default:''" json:"player_code"`
	FavoriteRole string    `gorm:"type:varchar(50);default:'Mid'" json:"favorite_role"`
	Source       string    `gorm:"type:varchar(50);default:'web'" json:"source"`
	CreatedAt    time.Time `json:"created_at"`
}

func (n *NewsletterSubscriber) BeforeCreate(tx *gorm.DB) (err error) {
	if n.ID == uuid.Nil {
		n.ID = uuid.New()
	}
	return
}

// FeaturedPromotion almacena los streamers o patrocinadores destacados activos en la App y Web
type FeaturedPromotion struct {
	ID        uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	Title     string    `gorm:"type:varchar(120);not null" json:"title"`
	Subtitle  string    `gorm:"type:varchar(255);not null" json:"subtitle"`
	Platform  string    `gorm:"type:varchar(50);not null" json:"platform"`
	StreamURL string    `gorm:"type:varchar(500);not null" json:"stream_url"`
	AvatarURL string    `gorm:"type:varchar(500);default:''" json:"avatar_url"`
	BadgeText string    `gorm:"type:varchar(64);default:'STREAMER DESTACADO'" json:"badge_text"`
	PromoCode string    `gorm:"type:varchar(32);default:''" json:"promo_code"`
	IsLive    bool      `gorm:"default:true" json:"is_live"`
	Active    bool      `gorm:"default:true;index" json:"active"`
	Priority  int       `gorm:"default:1" json:"priority"`
	CreatedAt time.Time `json:"created_at"`
}

func (f *FeaturedPromotion) BeforeCreate(tx *gorm.DB) (err error) {
	if f.ID == uuid.Nil {
		f.ID = uuid.New()
	}
	return
}

