package middleware

import (
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

type rateLimitEntry struct {
	count     int
	resetTime time.Time
}

// RateLimitByIP aplica un límite de peticiones por ventana de tiempo por IP con limpieza periódica.
func RateLimitByIP(maxRequests int, window time.Duration) func(http.Handler) http.Handler {
	var (
		mu      sync.Mutex
		entries = make(map[string]*rateLimitEntry)
	)

	go func() {
		ticker := time.NewTicker(5 * time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			now := time.Now()
			mu.Lock()
			for k, v := range entries {
				if now.After(v.resetTime) {
					delete(entries, k)
				}
			}
			mu.Unlock()
		}
	}()

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ip := extractClientIP(r)
			now := time.Now()

			mu.Lock()
			entry, exists := entries[ip]
			if !exists || now.After(entry.resetTime) {
				entries[ip] = &rateLimitEntry{
					count:     1,
					resetTime: now.Add(window),
				}
				mu.Unlock()
				next.ServeHTTP(w, r)
				return
			}
			entry.count++
			exceeded := entry.count > maxRequests
			mu.Unlock()

			if exceeded {
				http.Error(w, "Demasiadas solicitudes. Por favor espera un momento.", http.StatusTooManyRequests)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

func extractClientIP(r *http.Request) string {
	if xff := strings.TrimSpace(r.Header.Get("X-Forwarded-For")); xff != "" {
		if idx := strings.Index(xff, ","); idx != -1 {
			return strings.TrimSpace(xff[:idx])
		}
		return xff
	}
	if xri := strings.TrimSpace(r.Header.Get("X-Real-IP")); xri != "" {
		return xri
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
