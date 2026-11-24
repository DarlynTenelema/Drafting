package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// Reel representa un video corto vertical en Drafting (10 a 30 segundos, 720p comprimido)
type Reel struct {
	ID              uuid.UUID      `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	CreatorID       uuid.UUID      `gorm:"type:uuid;not null;index" json:"creator_id"`
	Creator         User           `gorm:"foreignKey:CreatorID" json:"creator,omitempty"`
	Title           string         `gorm:"type:varchar(180);not null" json:"title"`
	Description     string         `gorm:"type:text;default:''" json:"description"`
	VideoURL        string         `gorm:"type:text;not null" json:"video_url"`
	VideoKey        string         `gorm:"type:text;default:''" json:"video_key,omitempty"`
	ThumbnailURL    string         `gorm:"type:text;default:''" json:"thumbnail_url"`
	DurationSeconds int            `gorm:"default:15" json:"duration_seconds"`
	FileSizeBytes   int64          `gorm:"default:0" json:"file_size_bytes"`
	Width           int            `gorm:"default:0" json:"width"`
	Height          int            `gorm:"default:0" json:"height"`
	Orientation     string         `gorm:"type:varchar(16);default:'portrait'" json:"orientation"` // 'portrait' o 'landscape'
	GameMode        string         `gorm:"type:varchar(32);default:'wild_rift';index" json:"game_mode"` // 'wild_rift', 'lol_pc'
	Category        string         `gorm:"type:varchar(32);default:'jugadas';index" json:"category"`    // 'combos', 'micro', 'macro', 'jugadas', 'memes'
	Language        string         `gorm:"type:varchar(10);default:'universal';index" json:"language"`  // 'es', 'en', 'fr', 'pt', 'universal'
	ChampionName    string         `gorm:"type:varchar(64);default:''" json:"champion_name"`

	// Contadores cacheados en DB para alta concurrencia
	LikesCount         int     `gorm:"default:0" json:"likes_count"`
	CommentsCount      int     `gorm:"default:0" json:"comments_count"`
	SavesCount         int     `gorm:"default:0" json:"saves_count"`
	ViewsCount         int     `gorm:"default:0" json:"views_count"`
	VerifiedViewsCount int     `gorm:"default:0" json:"verified_views_count"`
	ReportsCount       int     `gorm:"default:0" json:"reports_count"`
	TrendScore         float64 `gorm:"default:0.0;index" json:"trend_score"`

	// Moderación y estado
	Active               bool           `gorm:"default:true;index" json:"active"`
	SilencedByReports    bool           `gorm:"default:false;index" json:"silenced_by_reports"`
	ModerationStatus     string         `gorm:"type:varchar(32);default:'approved';index" json:"moderation_status"` // 'pending_scan', 'approved', 'quarantined', 'rejected', 'verified_safe'
	ModerationReason     string         `gorm:"type:varchar(160);default:''" json:"moderation_reason,omitempty"`
	ModerationScore      float64        `gorm:"default:0.0" json:"moderation_score,omitempty"`
	ModerationCheckedAt  *time.Time     `json:"moderation_checked_at,omitempty"`
	ContentHash          string         `gorm:"type:varchar(128);default:'';index" json:"-"`
	WeightedReportsScore float64        `gorm:"default:0.0" json:"weighted_reports_score,omitempty"`
	CreatedAt            time.Time      `gorm:"index" json:"created_at"`
	UpdatedAt            time.Time      `json:"updated_at"`
	DeletedAt            gorm.DeletedAt `gorm:"index" json:"-"`

	// Campos dinámicos / virtuales para el cliente
	HasLiked              bool   `gorm:"-" json:"has_liked"`
	HasSaved              bool   `gorm:"-" json:"has_saved"`
	IsFollowing           bool   `gorm:"-" json:"is_following"`
	CreatorUsername       string `gorm:"-" json:"creator_username,omitempty"`
	CreatorAvatar         string `gorm:"-" json:"creator_avatar,omitempty"`
	CreatorFollowersCount int64  `gorm:"-" json:"creator_followers_count"`
}

// ReelLike registra el me gusta de un usuario a un reel
type ReelLike struct {
	ID        uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	ReelID    uuid.UUID `gorm:"type:uuid;not null;index;uniqueIndex:uq_reel_user_like" json:"reel_id"`
	UserID    uuid.UUID `gorm:"type:uuid;not null;index;uniqueIndex:uq_reel_user_like" json:"user_id"`
	CreatedAt time.Time `json:"created_at"`
}

// ReelSave registra un reel guardado en favoritos por un usuario
type ReelSave struct {
	ID        uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	ReelID    uuid.UUID `gorm:"type:uuid;not null;index;uniqueIndex:uq_reel_user_save" json:"reel_id"`
	UserID    uuid.UUID `gorm:"type:uuid;not null;index;uniqueIndex:uq_reel_user_save" json:"user_id"`
	CreatedAt time.Time `json:"created_at"`
}

// ReelComment registra los comentarios en los reels
type ReelComment struct {
	ID        uuid.UUID      `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	ReelID    uuid.UUID      `gorm:"type:uuid;not null;index" json:"reel_id"`
	UserID    uuid.UUID      `gorm:"type:uuid;not null;index" json:"user_id"`
	User      User           `gorm:"foreignKey:UserID" json:"user,omitempty"`
	Content   string         `gorm:"type:varchar(400);not null" json:"content"`
	CreatedAt time.Time      `gorm:"index" json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`

	// Campos virtuales
	Username   string `gorm:"-" json:"username"`
	ProfilePic string `gorm:"-" json:"profile_pic"`
}

// ReelView registra visualizaciones únicas para estadísticas y verificación de monetización (>=90% visto)
type ReelView struct {
	ID             uuid.UUID  `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	ReelID         uuid.UUID  `gorm:"type:uuid;not null;index" json:"reel_id"`
	UserID         *uuid.UUID `gorm:"type:uuid;index" json:"user_id,omitempty"`
	IPHash         string     `gorm:"type:varchar(64)" json:"-"`
	DeviceID       string     `gorm:"type:varchar(255);default:''" json:"-"`
	WatchedSeconds int        `gorm:"default:0" json:"watched_seconds"`
	WatchedPercent int        `gorm:"default:0" json:"watched_percent"`
	Verified       bool       `gorm:"default:false;index" json:"verified"`
	CreatedAt      time.Time  `gorm:"index" json:"created_at"`
}

// ReelReport registra denuncias de usuarios para moderación comunitaria anti-brigading
type ReelReport struct {
	ID        uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	ReelID    uuid.UUID `gorm:"type:uuid;not null;index;uniqueIndex:uq_reel_user_report" json:"reel_id"`
	UserID    uuid.UUID `gorm:"type:uuid;not null;index;uniqueIndex:uq_reel_user_report" json:"user_id"`
	Reason    string    `gorm:"type:varchar(64);not null;default:'other'" json:"reason"`
	Details   string    `gorm:"type:varchar(300);default:''" json:"details"`
	Weight    float64   `gorm:"default:1.0" json:"weight"`
	CreatedAt time.Time `gorm:"index" json:"created_at"`
}

// BannedContentHash almacena hashes perceptuales (dHash) de fotogramas eliminados por +18/gore
// para impedir re-subidas con costo $0 de IA.
type BannedContentHash struct {
	ID           uuid.UUID  `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	FrameHash    string     `gorm:"type:varchar(64);not null;uniqueIndex" json:"frame_hash"`
	Reason       string     `gorm:"type:varchar(64);not null;default:'nsfw_gore'" json:"reason"`
	SourceReelID *uuid.UUID `gorm:"type:uuid" json:"source_reel_id,omitempty"`
	CreatedAt    time.Time  `json:"created_at"`
}

// UserBlock registra usuarios bloqueados por un jugador (requisito UGC Play Store / App Store)
type UserBlock struct {
	ID        uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	BlockerID uuid.UUID `gorm:"type:uuid;not null;index;uniqueIndex:uq_user_block_pair" json:"blocker_id"`
	BlockedID uuid.UUID `gorm:"type:uuid;not null;index;uniqueIndex:uq_user_block_pair" json:"blocked_id"`
	CreatedAt time.Time `json:"created_at"`
}

// UserFollow registra relaciones reales de seguimiento entre usuarios
type UserFollow struct {
	ID          uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	FollowerID  uuid.UUID `gorm:"type:uuid;not null;index;uniqueIndex:uq_user_follow_pair" json:"follower_id"`
	FollowingID uuid.UUID `gorm:"type:uuid;not null;index;uniqueIndex:uq_user_follow_pair" json:"following_id"`
	CreatedAt   time.Time `json:"created_at"`
}

// CreatorPayoutRequest registra solicitudes de retiro de creadores (mínimo $100 USD)
type CreatorPayoutRequest struct {
	ID                    uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()" json:"id"`
	UserID                uuid.UUID `gorm:"type:uuid;not null;index" json:"user_id"`
	User                  User      `gorm:"foreignKey:UserID" json:"user,omitempty"`
	AmountUSD             float64   `gorm:"type:numeric(12,4);not null" json:"amount_usd"`
	VerifiedViewsSnapshot int64     `gorm:"default:0" json:"verified_views_snapshot"`
	PayoutMethod          string    `gorm:"type:varchar(32);not null;default:'paypal'" json:"payout_method"`
	PayoutDestination     string    `gorm:"type:varchar(255);not null" json:"payout_destination"`
	Status                string    `gorm:"type:varchar(32);not null;default:'pending';index" json:"status"` // pending, approved, paid, rejected
	AdminNotes            string    `gorm:"type:varchar(300);default:''" json:"admin_notes"`
	CreatedAt             time.Time `gorm:"index" json:"created_at"`
	UpdatedAt             time.Time `json:"updated_at"`
}

// UserReelsProfileStats resume las interacciones y monetización del perfil de un usuario
type UserReelsProfileStats struct {
	TotalReels            int64   `json:"total_reels"`
	TotalViews            int64   `json:"total_views"`
	TotalVerifiedViews    int64   `json:"total_verified_views"`
	LifetimeVerifiedViews int64   `json:"lifetime_verified_views"`
	TotalLikes            int64   `json:"total_likes"`
	TotalComments         int64   `json:"total_comments"`
	TotalSaves            int64   `json:"total_saves"`
	FollowersCount        int64   `json:"followers_count"`
	FollowingCount        int64   `json:"following_count"`
	EstimatedEarningsUSD  float64 `json:"estimated_earnings_usd"`
	PendingPayoutUSD      float64 `json:"pending_payout_usd"`
	PaidOutUSD            float64 `json:"paid_out_usd"`
	AvailableBalanceUSD   float64 `json:"available_balance_usd"`
	MinPayoutUSD          float64 `json:"min_payout_usd"`
	CanWithdraw           bool    `json:"can_withdraw"`
}
