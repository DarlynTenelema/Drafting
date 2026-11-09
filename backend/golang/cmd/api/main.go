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

	// CORS middleware for Web Ecosystem & Mobile Clients
	r.Use(func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Access-Control-Allow-Origin", "*")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Accept, Authorization, Content-Type, X-CSRF-Token")
			if r.Method == http.MethodOptions {
				w.WriteHeader(http.StatusNoContent)
				return
			}
			next.ServeHTTP(w, r)
		})
	})

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

	// Google AdMob Verification (app-ads.txt) servido directamente desde Railway
	r.Get("/app-ads.txt", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.Header().Set("Cache-Control", "public, max-age=3600")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("google.com, pub-6984024121811101, DIRECT, f08c47fec0942fa0\n"))
	})

	// Landing / Root endpoint para calentamiento de servidor y verificación de dominio
	r.Get("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("<!DOCTYPE html><html lang=\"es\"><head><meta charset=\"UTF-8\"><title>Drafting</title></head><body><h1>Drafting</h1><p>Asistente inteligente para Wild Rift.</p></body></html>"))
	})

	// Routes Definition
	registerAppRoutes := func(r chi.Router) {
		// Public Routes
		r.Post("/auth/google", handlers.GoogleLogin)
		r.Post("/auth/register", handlers.ManualRegister)
		r.Post("/auth/login", handlers.ManualLogin)
		r.Get("/app/version", handlers.GetAppVersion)
		r.Post("/app/version", handlers.SetAppVersion)

		// Events, Live Stream Alerts & Official Social Networks Hub
		r.Get("/events", handlers.GetEventsHub)

		// Public Ecosystem Routes (Web & App Phase 2: Streamers, Sponsors, Tournament C.L.A & Community)
		r.Get("/ecosystem/overview", handlers.GetEcosystemOverview)
		r.Post("/ecosystem/streamers/apply", handlers.ApplyAsStreamer)
		r.Get("/ecosystem/streamers/stats", handlers.GetStreamerStats)
		r.Get("/ecosystem/streamers/leaderboard", handlers.GetStreamersLeaderboard)
		r.Post("/ecosystem/sponsors/inquire", handlers.CreateSponsorInquiry)
		r.Get("/ecosystem/tournament/info", handlers.GetTournamentInfo)
		r.Post("/ecosystem/tournament/register", handlers.RegisterForTournament)
		r.Get("/ecosystem/community/polls", handlers.GetCommunityPolls)
		r.Post("/ecosystem/community/vote", handlers.CastCommunityVote)
		r.Post("/ecosystem/community/subscribe", handlers.SubscribeNewsletter)

		// Authenticated Routes
		r.Group(func(r chi.Router) {
			r.Use(middleware.Auth)
			r.Get("/auth/me", handlers.Me)
			r.Put("/auth/me", handlers.UpdateProfile)
			r.Post("/user/obtain-queries", handlers.ObtainQueries)
			r.Post("/user/redeem-referral", handlers.RedeemReferral)
			r.Post("/draft/analyze", handlers.AnalyzeDraft)

			// Store, Packs, Subscriptions & Query Transfers
			r.Get("/store/catalog", handlers.GetStoreCatalog)
			r.Post("/store/purchase-pack", handlers.PurchasePack)
			r.Post("/store/subscribe", handlers.Subscribe)
			r.Post("/store/transfer-queries", handlers.TransferQueries)

			// Donations & Streamer Supporters Ranking ($0.10 - $0.99)
			r.Get("/donations/ranking", handlers.GetDonationsRanking)
			r.Post("/donations/contribute", handlers.ContributeDonation)
			r.Put("/donations/profile", handlers.UpdateDonorProfile)

			// Exclusive Admin Control Panel for Events & Live Alerts (0805409802d@gmail.com only)
			r.Post("/events/manage", handlers.ManageEventsHub)

			// Minijuego Trivia: Preguntas Aleatorias, Respuestas y Vidas
			r.Get("/trivia/status", handlers.GetTriviaStatus)
			r.Get("/trivia/question", handlers.GetTriviaQuestion)
			r.Post("/trivia/answer", handlers.SubmitTriviaAnswer)
			r.Post("/trivia/reward-ad", handlers.RewardAdLives)
			r.Delete("/trivia/progress/reset", handlers.ResetCategoryProgress)

			// Panel de Administración de Trivia (Carga mensual por lote y edición)
			r.Post("/trivia/admin/batch", handlers.AdminBatchUpsertQuestions)
			r.Get("/trivia/admin/questions", handlers.AdminListQuestions)
			r.Put("/trivia/admin/questions/{id}", handlers.AdminUpdateQuestion)
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
