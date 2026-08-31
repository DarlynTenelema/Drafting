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
		
		// Stripe Webhook (Public)
		r.Post("/stripe/webhook", handlers.StripeWebhook)
		
		r.Group(func(r chi.Router) {
			r.Use(middleware.Auth)
			r.Get("/auth/me", handlers.Me)
			r.Put("/auth/me", handlers.UpdateProfile)
		})

		// Protected Routes
		r.Group(func(r chi.Router) {
			r.Use(middleware.Auth)
			
			// Subscription management
			r.Get("/subscription/status", handlers.GetSubscriptionStatus)
			r.Post("/subscription/verify", handlers.VerifyPurchase)

			// Economy & Groups (Version 2)
			r.Post("/finance/recharge-coins", handlers.RechargeCoins)
			r.Get("/finance/leaderboard", handlers.GetLeaderboard)
			r.Post("/finance/subscribe-group", handlers.SubscribeToGroup)
			
			// Stripe Connect & Payments
			r.Post("/stripe/onboarding", handlers.GenerateStripeOnboardingLink)
			r.Get("/stripe/return", handlers.StripeReturn)
			r.Get("/stripe/refresh", handlers.StripeRefresh)
			r.Post("/stripe/checkout", handlers.CreateCheckoutSession)

			// Draft analysis requires both active subscription and cooldown
			r.Group(func(r chi.Router) {
				r.Use(middleware.SubscriptionCheck)
				r.Use(middleware.Cooldown)
				
				r.Post("/draft/analyze", handlers.AnalyzeDraft)

				// Chat Coach Routes (Also require active plan resolution and cooldown)
				r.Get("/chat-coach/matches", handlers.GetChatCoachMatches)
				r.Delete("/chat-coach/matches/{id}", handlers.DeleteChatCoachMatch)
				r.Post("/chat-coach/matches/{id}/threads", handlers.CreateChatCoachThread)
				r.Get("/chat-coach/threads/{id}/messages", handlers.GetChatCoachMessages)
				r.Post("/chat-coach/threads/{id}/message", handlers.PostChatCoachMessage)
				r.Post("/chat-coach/threads/{id}/video-message", handlers.PostChatCoachVideoMessage)
				r.Post("/chat-coach/threads/{id}/tutor-message", handlers.PostTutorMessage)
				r.Delete("/chat-coach/threads/{id}", handlers.DeleteChatCoachThread)
			})

			// Group/Entrepreneur Routes (Version 2)
			r.Get("/group/champions", handlers.GetMyChampions)
			r.Get("/groups/champions", handlers.GetMyChampions)
			r.Post("/group/champion", handlers.SaveChampionData)
			r.Post("/groups/champion", handlers.SaveChampionData)
			r.Post("/group/create", handlers.CreateGroup)
			r.Post("/groups/create", handlers.CreateGroup)
			r.Post("/group/otp/create", handlers.CreateOTPProfile)
			r.Post("/creator/ai-model", handlers.SaveAIModel)
			r.Post("/creator/profile", handlers.CreateCreatorProfile)
			r.Get("/creator/profile", handlers.GetCreatorProfile)
			r.Get("/creator/eligibility", handlers.CheckEligibility)

			// Store
			r.Get("/store/products", handlers.ListStoreProducts)
			r.Get("/store/my_packages", handlers.GetMyPackages)

			// Content & Moderation (Version 2)
			r.Post("/content/channel", handlers.CreateChannel)
			r.Get("/content/channel/me", handlers.GetMyChannel)
			r.Put("/content/channel", handlers.UpdateChannel)
			r.Post("/content/video", handlers.SubmitVideo)
			r.Get("/content/video/me", handlers.GetMyVideos)
			r.Put("/content/video", handlers.UpdateVideo)
			r.Delete("/content/video", handlers.DeleteVideo)
			r.Post("/content/fanart", handlers.UploadFanart)
			r.Get("/content/my_fanarts", handlers.GetMyFanarts)
			r.Put("/content/fanart", handlers.UpdateFanart)
			r.Delete("/content/fanart", handlers.DeleteFanart)
			r.Get("/content/approved", handlers.ListApprovedContent)

			// Interactions
			r.Post("/interaction/comment", handlers.PostComment)
			r.Put("/interaction/comment", handlers.UpdateComment)
			r.Delete("/interaction/comment", handlers.DeleteComment)
			r.Get("/interaction/comments", handlers.GetComments)
			r.Post("/interaction/like", handlers.ToggleVideoLike)
			r.Post("/interaction/fanart/like", handlers.ToggleFanartLike)
			r.Post("/interaction/view", handlers.ViewVideo)
			r.Post("/interaction/subscribe", handlers.ToggleSubscribe)
			r.Get("/interaction/subscription_status", handlers.GetChannelSubscriptionStatus)

			// Finance
			r.Post("/finance/donate", handlers.DonateVideo)
			r.Get("/finance/dashboard", handlers.GetFinancialDashboard)
			// Moderation & Admin
			r.Post("/moderation/verify_identity", handlers.VerifyIdentity)
			r.Post("/moderation/report", handlers.ReportContent)
			r.Post("/finance/withdraw", handlers.WithdrawFunds)
			r.Post("/finance/recharge_coins", handlers.RechargeCoins)
			r.Post("/finance/subscribe_group", handlers.SubscribeToGroup)
			r.Post("/finance/subscribe_creator", handlers.SubscribeToCreator)
			r.Post("/finance/fanart/purchase", handlers.PurchaseFanart)
			r.Get("/finance/fanart/check_purchase", handlers.CheckFanartPurchase)

			// User Support & Feedback
			r.Get("/support/tickets", handlers.GetMyTickets)
			r.Post("/support/ticket", handlers.SubmitTicket)
			r.Get("/support/tickets/{id}/messages", handlers.GetMyTicketMessages)
			r.Post("/support/tickets/{id}/reply", handlers.UserReplyTicket)
			r.Post("/support/suggestion", handlers.SubmitSuggestion)
			r.Post("/support/appeal", handlers.SubmitAppeal)

			// Admin Panel Routes
			r.Group(func(r chi.Router) {
				r.Use(middleware.AdminCheck)
				r.Get("/admin_panel/dashboard_stats", handlers.GetAdminDashboardStats)
				
				// Tickets (Reportes, Bugs, Fraude, Soporte)
				r.Get("/admin_panel/tickets", handlers.GetTickets)
				r.Get("/admin_panel/tickets/{id}/messages", handlers.GetTicketMessages)
				r.Put("/admin_panel/tickets/{id}/status", handlers.UpdateTicketStatus)
				r.Post("/admin_panel/tickets/{id}/reply", handlers.ReplyTicket)

				// Sugerencias
				r.Get("/admin_panel/suggestions", handlers.GetSuggestions)
				r.Put("/admin_panel/suggestions/{id}/status", handlers.UpdateSuggestionStatus)
				r.Post("/admin_panel/suggestions/group_ai", handlers.GroupSuggestionsWithAI)

				// Moderación de Contenido (Cola)
				r.Get("/admin_panel/moderation/pending", handlers.GetPendingContent)
				r.Post("/admin_panel/moderation/video/{id}", handlers.ModerateVideo)
				r.Post("/admin_panel/moderation/fanart/{id}", handlers.ModerateFanart)

				// Gestor de Usuarios (Modo Dios)
				r.Get("/admin_panel/users", handlers.SearchUsers)
				r.Get("/admin_panel/users/{id}", handlers.GetUserDetail)
				r.Put("/admin_panel/users/{id}/ban", handlers.ToggleBan)
				r.Post("/admin_panel/users/{id}/strike", handlers.AddStrike)

				// Fraude Financiero
				r.Get("/admin_panel/finance/suspicious", handlers.GetSuspiciousTransactions)
				r.Put("/admin_panel/finance/suspicious/{id}", handlers.ResolveSuspiciousTransaction)

				// Apelaciones
				r.Get("/admin_panel/appeals", handlers.GetAppeals)
				r.Put("/admin_panel/appeals/{id}/resolve", handlers.ResolveAppeal)
			})
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
