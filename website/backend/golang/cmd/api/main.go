package main

import (
	"context"
	"log"
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
	// 1. Load configuration
	config.Load()

	// In production, ensure critical environment variables are present
	config.ValidateRequired("DATABASE_URL", "GOOGLE_CLIENT_ID", "JWT_SECRET")
	config.ValidateTimeWindow("GLOBAL_FREE_TRIAL_START_DATE", "GLOBAL_FREE_TRIAL_END_DATE")
	config.ValidateGooglePlay()

	// 2. Connect to database
	database.Connect()

	// Initialize Vertex AI (Agent Platform) Client
	if err := gemini.InitVertexClient(); err != nil {
		log.Fatalf("Failed to initialize Vertex AI client: %v", err)
	}

	handlers.InitSubscriptionHandlers()

	// 3. Setup Router
	r := chi.NewRouter()

	// Standard chi middlewares
	r.Use(chimiddleware.Logger)
	r.Use(chimiddleware.Recoverer)

	// Health endpoint
	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	// Routes
	r.Route("/api/v1", func(r chi.Router) {
		// Public Routes
		r.Post("/auth/google", handlers.GoogleLogin)
		r.Post("/auth/register", handlers.ManualRegister)
		r.Post("/auth/login", handlers.ManualLogin)

		// Protected Routes
		r.Group(func(r chi.Router) {
			r.Use(middleware.Auth)
			
			// Subscription management
			r.Get("/subscription/status", handlers.GetSubscriptionStatus)
			r.Post("/subscription/verify", handlers.VerifyPurchase)

			// Draft analysis requires both active subscription and cooldown
			r.Group(func(r chi.Router) {
				r.Use(middleware.SubscriptionCheck)
				r.Use(middleware.Cooldown)
				r.Post("/draft/analyze", handlers.AnalyzeDraft)
			})
		})
	})

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
