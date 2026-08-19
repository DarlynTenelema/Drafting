package handlers

import (
	"encoding/json"
	"net/http"
	"os"

	"github.com/stripe/stripe-go/v78"
	"github.com/stripe/stripe-go/v78/account"
	"github.com/stripe/stripe-go/v78/accountlink"
)

func init() {
	stripe.Key = os.Getenv("STRIPE_SECRET_KEY")
}

type StripeOnboardingResponse struct {
	URL string `json:"url"`
}

// GenerateStripeOnboardingLink generates a Stripe Connect Express onboarding URL.
func GenerateStripeOnboardingLink(w http.ResponseWriter, r *http.Request) {
	// In production, fetch the user's stripe_account_id from models.Group or models.OTPProfile
	// For now, we simulate the creation of an express account.
	
	// Ensure we have a Stripe key configured before attempting API calls
	if stripe.Key == "" {
		// Return a mock URL for development until Stripe keys are available
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(StripeOnboardingResponse{
			URL: "https://connect.stripe.com/express/oauth/authorize?mock=true",
		})
		return
	}

	params := &stripe.AccountParams{
		Type: stripe.String(string(stripe.AccountTypeExpress)),
	}
	acct, err := account.New(params)
	if err != nil {
		http.Error(w, "Failed to create Stripe Account: "+err.Error(), http.StatusInternalServerError)
		return
	}

	// Link the account to the onboarding flow
	linkParams := &stripe.AccountLinkParams{
		Account:    stripe.String(acct.ID),
		RefreshURL: stripe.String("https://example.com/reauth"), // Replace with app deep link
		ReturnURL:  stripe.String("https://example.com/return"), // Replace with app deep link
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
