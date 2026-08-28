package models

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

type Comment struct {
	ID          uuid.UUID  `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	ContentID   uuid.UUID  `gorm:"type:uuid;not null;index"`
	ContentType string     `gorm:"type:varchar(50);not null;default:'video'"` // 'video' or 'fanart'
	UserID      uuid.UUID  `gorm:"type:uuid;not null;index"`
	ParentID    *uuid.UUID `gorm:"type:uuid;index"` // Nullable for top-level comments
	Content   string    `gorm:"type:text;not null"`
	Likes     int       `gorm:"default:0"`
	CreatedAt time.Time
	UpdatedAt time.Time
	
	// Relations (not strictly DB columns, used for preloading)
	User      User      `gorm:"foreignKey:UserID"`
}

func (c *Comment) BeforeCreate(tx *gorm.DB) (err error) {
	if c.ID == uuid.Nil {
		c.ID = uuid.New()
	}
	return
}

type VideoLike struct {
	ID        uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	VideoID   uuid.UUID `gorm:"type:uuid;not null;uniqueIndex:idx_user_video"`
	UserID    uuid.UUID `gorm:"type:uuid;not null;uniqueIndex:idx_user_video"`
	CreatedAt time.Time
}

func (vl *VideoLike) BeforeCreate(tx *gorm.DB) (err error) {
	if vl.ID == uuid.Nil {
		vl.ID = uuid.New()
	}
	return
}

type Subscription struct {
	ID                  uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	SubscriberID        uuid.UUID `gorm:"type:uuid;not null;uniqueIndex:idx_sub_channel"`
	ChannelID           uuid.UUID `gorm:"type:uuid;not null;uniqueIndex:idx_sub_channel"`
	NotificationsEnabled bool      `gorm:"default:false"`
	CreatedAt           time.Time
}

func (s *Subscription) BeforeCreate(tx *gorm.DB) (err error) {
	if s.ID == uuid.Nil {
		s.ID = uuid.New()
	}
	return
}

type FanartLike struct {
	ID        uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	FanartID  uuid.UUID `gorm:"type:uuid;not null;uniqueIndex:idx_user_fanart"`
	UserID    uuid.UUID `gorm:"type:uuid;not null;uniqueIndex:idx_user_fanart"`
	CreatedAt time.Time
}

func (fl *FanartLike) BeforeCreate(tx *gorm.DB) (err error) {
	if fl.ID == uuid.Nil {
		fl.ID = uuid.New()
	}
	return
}
