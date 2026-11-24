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
	"backend/internal/storage"
	"backend/internal/tts"

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

	// Initialize Storage (S3-compatible / Cloudflare R2 con fallback local para videos y thumbnails)
	storage.InitStorage()

	// Iniciar worker periódico en lote para trend_score de Reels (evita sobrecarga por vista)
	handlers.StartReelsTrendWorker()

	// Initialize Vertex AI (Agent Platform) Client
	if err := gemini.InitVertexClient(); err != nil {
		log.Fatalf("Failed to initialize Vertex AI client: %v", err)
	}

	// Initialize Google Cloud Text-to-Speech (WaveNet) for Aureon 1.0 (non-fatal fallback)
	_ = tts.InitWaveNetClient()

	// 3. Setup Router
	r := chi.NewRouter()

	// CORS middleware for Web Ecosystem & Mobile Clients (configurable via ALLOWED_ORIGINS, default "*")
	allowedOrigins := config.GetEnv("ALLOWED_ORIGINS", "*")
	r.Use(func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			origin := r.Header.Get("Origin")
			if allowedOrigins == "*" {
				w.Header().Set("Access-Control-Allow-Origin", "*")
			} else if origin != "" {
				w.Header().Set("Access-Control-Allow-Origin", allowedOrigins)
				w.Header().Set("Vary", "Origin")
			}
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

	// Servidor de archivos multimedia locales (fallback cuando no se usa Cloudflare R2)
	r.Handle("/uploads/*", http.StripPrefix("/uploads/", http.FileServer(http.Dir("./uploads"))))

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
	authRateLimit := middleware.RateLimitByIP(30, time.Minute)
	publicWriteRateLimit := middleware.RateLimitByIP(20, time.Minute)
	reelsViewRateLimit := middleware.RateLimitByIP(120, time.Minute)
	reelsWriteRateLimit := middleware.RateLimitByIP(40, time.Minute)

	registerAppRoutes := func(r chi.Router) {
		// Public Routes (con rate limiting en autenticación y formularios públicos)
		r.Group(func(r chi.Router) {
			r.Use(authRateLimit)
			r.Post("/auth/google", handlers.GoogleLogin)
			r.Post("/auth/register", handlers.ManualRegister)
			r.Post("/auth/login", handlers.ManualLogin)
		})
		r.Get("/app/version", handlers.GetAppVersion)
		r.Post("/app/version", handlers.SetAppVersion)

		// Events, Live Stream Alerts & Official Social Networks Hub
		r.Get("/events", handlers.GetEventsHub)

		// Public Ecosystem Routes (Web & App Phase 2: Streamers, Sponsors, Tournament C.L.A & Community)
		r.Get("/ecosystem/overview", handlers.GetEcosystemOverview)
		r.Get("/ecosystem/streamers/stats", handlers.GetStreamerStats)
		r.Get("/ecosystem/streamers/leaderboard", handlers.GetStreamersLeaderboard)
		r.Get("/ecosystem/tournament/info", handlers.GetTournamentInfo)
		r.Get("/ecosystem/community/polls", handlers.GetCommunityPolls)
		r.Group(func(r chi.Router) {
			r.Use(publicWriteRateLimit)
			r.Post("/ecosystem/streamers/apply", handlers.ApplyAsStreamer)
			r.Post("/ecosystem/sponsors/inquire", handlers.CreateSponsorInquiry)
			r.Post("/ecosystem/tournament/register", handlers.RegisterForTournament)
			r.Post("/ecosystem/community/vote", handlers.CastCommunityVote)
			r.Post("/ecosystem/community/subscribe", handlers.SubscribeNewsletter)
		})

		// Reels Tácticos: Feed público, detalle, comentarios, vistas verificadas y perfiles públicos
		r.Group(func(r chi.Router) {
			r.Use(middleware.OptionalAuth)
			r.Get("/reels/feed", handlers.GetReelsFeed)
			r.Get("/reels/{id}", handlers.GetReelByID)
			r.Get("/reels/{id}/comments", handlers.GetReelComments)
			r.Get("/reels/users/{user_id}", handlers.GetUserReelsProfile)
			r.Group(func(r chi.Router) {
				r.Use(reelsViewRateLimit)
				r.Post("/reels/{id}/view/start", handlers.StartReelViewSession)
				r.Post("/reels/{id}/view", handlers.RecordReelView)
			})
		})

		// Authenticated Routes
		r.Group(func(r chi.Router) {
			r.Use(middleware.Auth)
			r.Get("/auth/me", handlers.Me)
			r.Put("/auth/me", handlers.UpdateProfile)
			r.Post("/user/obtain-queries", handlers.ObtainQueries)
			r.Post("/user/redeem-referral", handlers.RedeemReferral)
			r.Post("/draft/analyze", handlers.AnalyzeDraft)
			r.Post("/draft/reconsult", handlers.ReconsultDraft)
			r.Post("/draft/chat", handlers.ChatDraft)
			r.Post("/draft/manual", handlers.AnalyzeManualDraft)
			r.Post("/draft/extract-vision", handlers.ExtractDraftVision)

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

			// Reels Tácticos: Creación, subida directa prefirmada, likes, guardados, seguidores, reportes y moderación
			r.Group(func(r chi.Router) {
				r.Use(reelsWriteRateLimit)
				r.Post("/reels", handlers.CreateReel)
				r.Post("/reels/presign-upload", handlers.PresignReelUpload)
				r.Post("/reels/upload", handlers.UploadReelMedia)
				r.Post("/reels/{id}/like", handlers.ToggleLikeReel)
				r.Post("/reels/{id}/save", handlers.ToggleSaveReel)
				r.Post("/reels/{id}/report", handlers.ReportReel)
				r.Post("/reels/{id}/comments", handlers.CreateReelComment)
				r.Post("/reels/users/{user_id}/follow", handlers.ToggleFollowCreator)
				r.Post("/reels/users/{user_id}/block", handlers.ToggleBlockUser)
				r.Post("/reels/me/payouts", handlers.RequestCreatorPayout)
			})
			r.Delete("/reels/comments/{comment_id}", handlers.DeleteReelComment)
			r.Delete("/reels/{id}", handlers.DeleteMyReel)
			r.Get("/reels/me/blocked", handlers.GetBlockedUsers)

			// Moderación Admin de Reels reportados y retiros de creadores
			r.Get("/reels/admin/reported", handlers.AdminListReportedReels)
			r.Post("/reels/admin/{id}/moderate", handlers.AdminModerateReel)
			r.Get("/reels/admin/payouts", handlers.AdminListPayoutRequests)
			r.Post("/reels/admin/payouts/{id}/review", handlers.AdminReviewPayoutRequest)

			// Perfil de Reels del Usuario (Videos subidos con métricas, retiros, likes y guardados)
			r.Get("/reels/me/uploaded", handlers.GetMyUploadedReels)
			r.Get("/reels/me/liked", handlers.GetMyLikedReels)
			r.Get("/reels/me/saved", handlers.GetMySavedReels)
			r.Get("/reels/me/payouts", handlers.GetMyPayoutRequests)
		})
	}

	// Mount on /api/v1, /api, and root /
	r.Route("/api/v1", registerAppRoutes)
	r.Route("/api", registerAppRoutes)
	r.Group(registerAppRoutes)

	port := config.GetEnv("PORT", "8080")
	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           r,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       60 * time.Second,
		WriteTimeout:      90 * time.Second,
		IdleTimeout:       120 * time.Second,
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
