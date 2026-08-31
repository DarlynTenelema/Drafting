package auth

import (
	"context"
	"errors"
	"fmt"
	"time"

	"backend/internal/config"

	jwt "github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"google.golang.org/api/idtoken"
)

type GoogleClaims struct {
	GoogleID string
	Email    string
	Name     string
	Picture  string
}

func VerifyGoogleToken(ctx context.Context, token string) (*GoogleClaims, error) {
	clientID := config.GetEnv("GOOGLE_CLIENT_ID", "")
	if clientID == "" {
		return nil, errors.New("GOOGLE_CLIENT_ID is not configured")
	}

	payload, err := idtoken.Validate(ctx, token, clientID)
	if err != nil {
		return nil, err
	}

	claims := &GoogleClaims{
		GoogleID: payload.Subject,
	}

	if email, ok := payload.Claims["email"]; ok {
		claims.Email = email.(string)
	}
	if name, ok := payload.Claims["name"]; ok {
		claims.Name = name.(string)
	}
	if picture, ok := payload.Claims["picture"]; ok {
		picUrl := picture.(string)
		if len(picUrl) > 255 {
			picUrl = picUrl[:255]
		}
		claims.Picture = picUrl
	}

	return claims, nil
}

// GenerateJWT creates a signed JWT for the given Google ID and returns the token and jti.
func GenerateJWT(googleID string, ttl time.Duration) (string, string, error) {
	secret := config.GetEnv("JWT_SECRET", "")
	if secret == "" {
		return "", "", fmt.Errorf("JWT_SECRET is not configured")
	}

	jti := uuid.New().String()
	now := time.Now()
	claims := jwt.MapClaims{
		"sub": googleID,
		"jti": jti,
		"iat": now.Unix(),
		"exp": now.Add(ttl).Unix(),
		"iss": "drafting-api",
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString([]byte(secret))
	if err != nil {
		return "", "", err
	}
	return signed, jti, nil
}

// ValidateJWT parses and validates a JWT, returning the subject (googleID) and jti.
func ValidateJWT(tokenStr string) (string, string, error) {
	secret := config.GetEnv("JWT_SECRET", "")
	if secret == "" {
		return "", "", fmt.Errorf("JWT_SECRET is not configured")
	}

	token, err := jwt.Parse(tokenStr, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return []byte(secret), nil
	})
	if err != nil {
		return "", "", err
	}

	if claims, ok := token.Claims.(jwt.MapClaims); ok && token.Valid {
		sub, _ := claims["sub"].(string)
		jti, _ := claims["jti"].(string)
		return sub, jti, nil
	}
	return "", "", fmt.Errorf("invalid token")
}
