package handlers

import (
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"

	"backend/internal/database"
	"backend/internal/middleware"
	"backend/internal/models"

	"github.com/google/uuid"
	"gorm.io/gorm"
	"github.com/stripe/stripe-go/v78"
	"github.com/stripe/stripe-go/v78/account"
	"github.com/stripe/stripe-go/v78/accountlink"
	"github.com/stripe/stripe-go/v78/checkout/session"
	"github.com/stripe/stripe-go/v78/webhook"
)

func init() {
	stripe.Key = os.Getenv("STRIPE_SECRET_KEY")
}

type StripeOnboardingResponse struct {
	URL string `json:"url"`
}

// GenerateStripeOnboardingLink generates a Stripe Connect Express onboarding URL.
func GenerateStripeOnboardingLink(w http.ResponseWriter, r *http.Request) {
	if stripe.Key == "" {
		http.Error(w, "Stripe is not configured on the server", http.StatusInternalServerError)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var accountID string
	if user.StripeAccountID != nil && *user.StripeAccountID != "" {
		accountID = *user.StripeAccountID
	} else {
		params := &stripe.AccountParams{
			Type: stripe.String(string(stripe.AccountTypeExpress)),
			Email: stripe.String(user.Email),
		}
		acct, err := account.New(params)
		if err != nil {
			http.Error(w, "Failed to create Stripe Account: "+err.Error(), http.StatusInternalServerError)
			return
		}
		accountID = acct.ID
		user.StripeAccountID = &accountID
		if err := database.DB.Save(user).Error; err != nil {
			http.Error(w, "Failed to save Stripe Account to DB", http.StatusInternalServerError)
			return
		}
	}

	backendURL := os.Getenv("FRONTEND_URL") // Used for redirection. Defaults to localhost for dev.
	if backendURL == "" {
		backendURL = "http://localhost:8080"
	}

	// Link the account to the onboarding flow
	linkParams := &stripe.AccountLinkParams{
		Account:    stripe.String(accountID),
		RefreshURL: stripe.String(backendURL + "/api/v1/stripe/refresh"),
		ReturnURL:  stripe.String(backendURL + "/api/v1/stripe/return"),
		Type:       stripe.String("account_onboarding"),
	}

	link, err := accountlink.New(linkParams)
	if err != nil {
		http.Error(w, "Failed to create Account Link: "+err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(StripeOnboardingResponse{
		URL: link.URL,
	})
}

// StripeReturn handles the success redirection from Stripe onboarding.
func StripeReturn(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html")
	w.Write([]byte(`<html><body><h2>Onboarding Completado con Éxito</h2><p>Ya puedes cerrar esta ventana y regresar a la aplicación.</p></body></html>`))
}

// StripeRefresh handles the case where the user didn't complete the onboarding and the link expired.
func StripeRefresh(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html")
	w.Write([]byte(`<html><body><h2>El enlace de Stripe expiró</h2><p>Por favor, vuelve a la aplicación y solicita un nuevo enlace de configuración.</p></body></html>`))
}

type CheckoutSessionRequest struct {
	PackageID string  `json:"package_id"`
	PriceUSD  float64 `json:"price_usd"`
}

// CreateCheckoutSession creates a Stripe Checkout session to purchase Esencias Azules
func CreateCheckoutSession(w http.ResponseWriter, r *http.Request) {
	if stripe.Key == "" {
		http.Error(w, "Stripe is not configured", http.StatusInternalServerError)
		return
	}

	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req CheckoutSessionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	backendURL := os.Getenv("FRONTEND_URL")
	if backendURL == "" {
		backendURL = "http://localhost:8080"
	}

	params := &stripe.CheckoutSessionParams{
		PaymentMethodTypes: stripe.StringSlice([]string{"card"}),
		LineItems: []*stripe.CheckoutSessionLineItemParams{
			{
				PriceData: &stripe.CheckoutSessionLineItemPriceDataParams{
					Currency: stripe.String("usd"),
					ProductData: &stripe.CheckoutSessionLineItemPriceDataProductDataParams{
						Name: stripe.String("Paquete " + req.PackageID),
					},
					UnitAmount: stripe.Int64(int64(req.PriceUSD * 100)),
				},
				Quantity: stripe.Int64(1),
			},
		},
		Mode: stripe.String(string(stripe.CheckoutSessionModePayment)),
		SuccessURL: stripe.String(backendURL + "/api/v1/stripe/return"),
		CancelURL:  stripe.String(backendURL + "/api/v1/stripe/refresh"),
		ClientReferenceID: stripe.String(user.ID.String()),
		Metadata: map[string]string{
			"package_id": req.PackageID,
		},
	}

	s, err := session.New(params)
	if err != nil {
		http.Error(w, "Failed to create checkout session: "+err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"url": s.URL})
}

// StripeWebhook handles asynchronous Stripe events
func StripeWebhook(w http.ResponseWriter, r *http.Request) {
	const MaxBodyBytes = int64(65536)
	r.Body = http.MaxBytesReader(w, r.Body, MaxBodyBytes)
	payload, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "Error reading request body", http.StatusServiceUnavailable)
		return
	}

	endpointSecret := os.Getenv("STRIPE_WEBHOOK_SECRET")
	event, err := webhook.ConstructEvent(payload, r.Header.Get("Stripe-Signature"), endpointSecret)
	if err != nil {
		log.Printf("Webhook signature verification failed. %v", err)
		http.Error(w, "Webhook signature verification failed", http.StatusBadRequest)
		return
	}

	switch event.Type {
	case "checkout.session.completed":
		var session stripe.CheckoutSession
		if err := json.Unmarshal(event.Data.Raw, &session); err != nil {
			log.Printf("Error parsing webhook JSON: %v", err)
			return
		}
		
		// Security Check: Prevent double-processing of the same session
		var count int64
		database.DB.Model(&models.Transaction{}).Where("purchase_token = ?", session.ID).Count(&count)
		if count > 0 {
			log.Printf("Stripe session %s already processed. Ignoring.", session.ID)
			w.WriteHeader(http.StatusOK)
			return
		}
		
		userID := session.ClientReferenceID
		packageID := session.Metadata["package_id"]
		log.Printf("Payment received for User %s, Package %s", userID, packageID)
		
		essenceToAdd := getEssenceForProduct(packageID)
		if essenceToAdd > 0 {
			uid, err := uuid.Parse(userID)
			if err == nil {
				tx := database.DB.Begin()
				var wallet models.Wallet
				if err := tx.Where("user_id = ?", uid).First(&wallet).Error; err != nil {
					wallet = models.Wallet{UserID: uid, BalanceEssence: 0}
					tx.Create(&wallet)
				}
				tx.Model(&wallet).UpdateColumn("balance_essence", gorm.Expr("balance_essence + ?", essenceToAdd))

				txRec := models.Transaction{
					UserID:     uid,
					Type:       "recharge_essence",
					AmountEssence: essenceToAdd,
					Status:     "completed_stripe",
					PurchaseToken: &session.ID,
				}
				tx.Create(&txRec)
				tx.Commit()
				log.Printf("Added %f Esencias Azules to User %s", essenceToAdd, userID)
			}
		}

	case "account.updated":
		var acct stripe.Account
		if err := json.Unmarshal(event.Data.Raw, &acct); err != nil {
			log.Printf("Error parsing webhook JSON: %v", err)
			return
		}
		
		if acct.DetailsSubmitted {
			log.Printf("Account %s has submitted details", acct.ID)
			// (Opcional) Activar algo específico en el usuario si fuera necesario,
			// pero el dashboard ya puede consultar a Stripe o simplemente confiar en este flag.
			// Por ahora solo logeamos el éxito para mantener un registro de auditoría.
		}

	default:
		log.Printf("Unhandled event type: %s", event.Type)
	}

	w.WriteHeader(http.StatusOK)
}
