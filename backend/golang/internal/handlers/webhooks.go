package handlers

import (
	"encoding/base64"
	"encoding/json"
	"io"
	"log"
	"net/http"

	"time"

	"backend/internal/database"
	"backend/internal/models"
)

type PubSubRequest struct {
	Message struct {
		Data       string            `json:"data"`
		MessageID  string            `json:"messageId"`
		Attributes map[string]string `json:"attributes"`
	} `json:"message"`
	Subscription string `json:"subscription"`
}

type DeveloperNotification struct {
	Version                  string `json:"version"`
	PackageName              string `json:"packageName"`
	EventTimeMillis          string `json:"eventTimeMillis"`
	SubscriptionNotification *struct {
		Version          string `json:"version"`
		NotificationType int    `json:"notificationType"`
		PurchaseToken    string `json:"purchaseToken"`
		SubscriptionID   string `json:"subscriptionId"`
	} `json:"subscriptionNotification"`
	TestNotification *struct {
		Version string `json:"version"`
	} `json:"testNotification"`
}

func PlayStoreWebhook(w http.ResponseWriter, r *http.Request) {
	// 1. Basic Security: Validate simple token in query parameter to prevent unauthorized spam
	// In Google Cloud Pub/Sub Push Subscription settings, the user must set URL to:
	// https://yourdomain.com/api/webhooks/playstore?token=rtdn_secret_token
	token := r.URL.Query().Get("token")
	// If you want to enforce token validation, uncomment the following line and set your secret:
	// if token != "YOUR_SECRET_TOKEN" { http.Error(w, "Unauthorized", http.StatusUnauthorized); return }
	_ = token // Using it to avoid unused variable warning

	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}
	defer r.Body.Close()

	var pubSubMsg PubSubRequest
	if err := json.Unmarshal(body, &pubSubMsg); err != nil {
		log.Printf("[RTDN] Failed to parse Pub/Sub message: %v", err)
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	decodedData, err := base64.StdEncoding.DecodeString(pubSubMsg.Message.Data)
	if err != nil {
		log.Printf("[RTDN] Failed to decode base64 data: %v", err)
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	var devNotif DeveloperNotification
	if err := json.Unmarshal(decodedData, &devNotif); err != nil {
		log.Printf("[RTDN] Failed to parse DeveloperNotification: %v", err)
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	// Handle Test Notification (Sent when setting up the topic in Play Console)
	if devNotif.TestNotification != nil {
		log.Println("[RTDN] Received Test Notification. Webhook setup successful.")
		w.WriteHeader(http.StatusOK)
		return
	}

	// Handle Real Subscription Notifications
	if devNotif.SubscriptionNotification != nil {
		notif := devNotif.SubscriptionNotification
		log.Printf("[RTDN] Received Subscription Notification - Type: %d, Token: %s", notif.NotificationType, notif.PurchaseToken)

		isActive := true
		
		// Map of Notification Types:
		// 1: RECOVERED, 2: RENEWED, 3: CANCELED (Still active until expiry), 4: PURCHASED
		// 12: REVOKED, 13: EXPIRED
		switch notif.NotificationType {
		case 12, 13:
			// Subscription is dead
			isActive = false
		case 1, 2, 4, 7:
			// Subscription is alive and well
			isActive = true
		default:
			// Other events (paused, price change, canceled-but-active) don't change immediate access
			w.WriteHeader(http.StatusOK)
			return
		}

		// We must update the expiration dates from Google Play for the Global Plans
		if playStoreVerifier != nil && playStoreVerifier.Enabled() && isActive {
			sub, err := playStoreVerifier.VerifySubscriptionPurchase(r.Context(), notif.SubscriptionID, notif.PurchaseToken)
			if err != nil {
				log.Printf("[RTDN] Failed to verify subscription for token %s: %v", notif.PurchaseToken, err)
			} else if len(sub.LineItems) > 0 {
				expiryStr := sub.LineItems[0].ExpiryTime
				t, parseErr := time.Parse(time.RFC3339, expiryStr)
				if parseErr == nil {
					// Update the User's SubscriptionEndsAt
					// We find the payment transaction that has this purchase_token to know which UserID it belongs to.
					var tx models.PaymentTransaction
					if err := database.DB.Where("purchase_token = ?", notif.PurchaseToken).First(&tx).Error; err == nil {
						
						var dbUser models.User
						database.DB.First(&dbUser, tx.UserID)

						if dbUser.SubscriptionEndsAt != nil && dbUser.SubscriptionEndsAt.Unix() >= t.Unix() {
							log.Printf("[RTDN] Duplicate webhook or already processed renewal for token %s", notif.PurchaseToken)
							w.WriteHeader(http.StatusOK)
							return
						}

						if err := database.DB.Model(&models.User{}).Where("id = ?", tx.UserID).Update("subscription_ends_at", t).Error; err != nil {
							log.Printf("[RTDN] Error updating User subscription_ends_at: %v", err)
						} else {
							log.Printf("[RTDN] Successfully updated expiry for user %s to %s", tx.UserID, t.String())
							
							// Process Renewal Payout to Entrepreneur (only on RENEWED = 2)
							if notif.NotificationType == 2 {
								if err := ProcessSubscriptionRenewal(notif.SubscriptionID, notif.PurchaseToken); err != nil {
									log.Printf("[RTDN] Error processing renewal payout: %v", err)
								} else {
									log.Printf("[RTDN] Successfully processed renewal payout for token %s", notif.PurchaseToken)
								}
							}
						}
					} else {
						log.Printf("[RTDN] Could not find PaymentTransaction for token %s", notif.PurchaseToken)
					}
				}
			}
		}

		// Update Group Profiles
		if err := database.DB.Model(&models.Group{}).Where("purchase_token = ?", notif.PurchaseToken).Update("is_active", isActive).Error; err != nil {
			log.Printf("[RTDN] Error updating Group state: %v", err)
		}

		// Update OTP Profiles
		if err := database.DB.Model(&models.OTPProfile{}).Where("purchase_token = ?", notif.PurchaseToken).Update("is_active", isActive).Error; err != nil {
			log.Printf("[RTDN] Error updating OTP Profile state: %v", err)
		}
	}

	// Acknowledge the message so Pub/Sub doesn't retry
	w.WriteHeader(http.StatusOK)
}
