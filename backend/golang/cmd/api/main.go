package main

import (
	"context"
	"log"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"backend/internal/config"
	"backend/internal/database"
	"backend/internal/gemini"
	"backend/internal/handlers"
	"backend/internal/middleware"

	"github.com/go-chi/chi/v5"
	chimiddleware "github.com/go-chi/chi/v5/middleware"
)

func main() {
	// Initialize JSON Logger for production readiness
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	// 1. Load configuration
	config.Load()

	// In production, ensure critical environment variables are present
	config.ValidateRequired("DATABASE_URL", "GOOGLE_CLIENT_ID", "JWT_SECRET")

	// 2. Connect to database
	database.Connect()

	// Initialize Vertex AI (Agent Platform) Client
	if err := gemini.InitVertexClient(); err != nil {
		log.Fatalf("Failed to initialize Vertex AI client: %v", err)
	}

	// 3. Setup Router
	r := chi.NewRouter()

	// Standard chi middlewares
	r.Use(func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			ww := chimiddleware.NewWrapResponseWriter(w, r.ProtoMajor)
			next.ServeHTTP(ww, r)
			slog.Info("Request Handled",
				"method", r.Method,
				"path", r.URL.Path,
				"status", ww.Status(),
				"duration", time.Since(start).String(),
			)
		})
	})
	r.Use(chimiddleware.Recoverer)

	// Health endpoint
	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	// Routes Definition
	registerAppRoutes := func(r chi.Router) {
		// Public Routes
		r.Post("/auth/google", handlers.GoogleLogin)
		r.Post("/auth/register", handlers.ManualRegister)
		r.Post("/auth/login", handlers.ManualLogin)

		// Authenticated Routes
		r.Group(func(r chi.Router) {
			r.Use(middleware.Auth)
			r.Get("/auth/me", handlers.Me)
			r.Put("/auth/me", handlers.UpdateProfile)
			r.Post("/user/obtain-queries", handlers.ObtainQueries)
			r.Post("/user/redeem-referral", handlers.RedeemReferral)
			r.Post("/draft/analyze", handlers.AnalyzeDraft)
		})
	}

	// Mount on /api/v1, /api, and root /
	r.Route("/api/v1", registerAppRoutes)
	r.Route("/api", registerAppRoutes)
	r.Group(registerAppRoutes)

	port := config.GetEnv("PORT", "8080")
	srv := &http.Server{
		Addr:    ":" + port,
		Handler: r,
	}

	// Start server in background
	go func() {
		log.Printf("Starting server on port %s...\n", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed to start: %v", err)
		}
	}()

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, os.Interrupt, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}
	log.Println("Server exiting")
}
