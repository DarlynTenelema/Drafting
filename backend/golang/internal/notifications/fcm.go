package notifications

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"golang.org/x/oauth2/google"
)

var (
	fcmClient     *http.Client
	fcmProjectID  string
	fcmInitOnce   sync.Once
	fcmInitError  error
)

type serviceAccountJSON struct {
	ProjectID string `json:"project_id"`
}

func initFCMClient() error {
	fcmInitOnce.Do(func() {
		var credentialsBytes []byte

		// 1. Intentar leer desde variable de entorno en bruto (Ideal para Railway)
		rawEnv := strings.TrimSpace(os.Getenv("FIREBASE_CREDENTIALS_JSON"))
		if rawEnv != "" {
			credentialsBytes = []byte(rawEnv)
		}

		// 2. Intentar leer desde archivo especificado en entorno
		if len(credentialsBytes) == 0 {
			filePath := strings.TrimSpace(os.Getenv("FIREBASE_CREDENTIALS_FILE"))
			if filePath != "" {
				if b, err := os.ReadFile(filePath); err == nil {
					credentialsBytes = b
				}
			}
		}

		// 3. Fallbacks de archivos locales ignorados en Git
		if len(credentialsBytes) == 0 {
			candidatePaths := []string{
				"firebase-credentials.json",
				"internal/notifications/firebase-credentials.json",
				"../firebase-credentials.json",
				"../../project-793e159d-7403-492f-969-firebase-adminsdk-fbsvc-f6ebdad304.json",
				"project-793e159d-7403-492f-969-firebase-adminsdk-fbsvc-f6ebdad304.json",
			}
			for _, p := range candidatePaths {
				if b, err := os.ReadFile(p); err == nil {
					credentialsBytes = b
					break
				}
			}
		}

		if len(credentialsBytes) == 0 {
			fcmInitError = fmt.Errorf("no se encontraron credenciales de Firebase (FIREBASE_CREDENTIALS_JSON o firebase-credentials.json)")
			slog.Warn("FCM no configurado aún", "error", fcmInitError)
			return
		}

		var sa serviceAccountJSON
		if err := json.Unmarshal(credentialsBytes, &sa); err != nil || sa.ProjectID == "" {
			fcmInitError = fmt.Errorf("credenciales de Firebase no contienen un project_id válido: %v", err)
			return
		}
		fcmProjectID = sa.ProjectID

		jwtConfig, err := google.JWTConfigFromJSON(credentialsBytes, "https://www.googleapis.com/auth/firebase.messaging")
		if err != nil {
			fcmInitError = fmt.Errorf("error construyendo JWT OAuth2 para FCM: %w", err)
			return
		}

		fcmClient = jwtConfig.Client(context.Background())
		slog.Info("FCM Push Notifications inicializado correctamente", "project_id", fcmProjectID)
	})

	return fcmInitError
}

type fcmPayload struct {
	Message fcmMessage `json:"message"`
}

type fcmMessage struct {
	Topic        string            `json:"topic"`
	Notification *fcmNotification `json:"notification,omitempty"`
	Data         map[string]string `json:"data,omitempty"`
	Android      *fcmAndroid       `json:"android,omitempty"`
}

type fcmNotification struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

type fcmAndroid struct {
	Priority     string                 `json:"priority"`
	Notification *fcmAndroidNotification `json:"notification,omitempty"`
}

type fcmAndroidNotification struct {
	ChannelID            string `json:"channel_id"`
	DefaultSound         bool   `json:"default_sound"`
	NotificationPriority string `json:"notification_priority"`
}

// SendLiveStreamPush despacha un mensaje push masivo e instantáneo al tópico 'live_events'
func SendLiveStreamPush(title, body, actionURL, platform string, isLive bool) error {
	// Ejecutar en goroutine desacoplada para no retrasar la respuesta HTTP del admin
	go func() {
		if err := initFCMClient(); err != nil {
			slog.Warn("FCM SendLiveStreamPush omitido: credenciales pendientes", "error", err)
			return
		}

		if fcmClient == nil || fcmProjectID == "" {
			return
		}

		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		if title == "" {
			title = "🔴 ¡Drafting está en Directo!"
		}
		if body == "" {
			body = "Toca para unirte a la transmisión en vivo ahora mismo."
		}

		payload := fcmPayload{
			Message: fcmMessage{
				Topic: "live_events",
				Notification: &fcmNotification{
					Title: title,
					Body:  body,
				},
				Data: map[string]string{
					"title":      title,
					"subtitle":   body,
					"action_url": actionURL,
					"platform":   platform,
					"is_live":    fmt.Sprintf("%t", isLive),
				},
				Android: &fcmAndroid{
					Priority: "HIGH",
					Notification: &fcmAndroidNotification{
						ChannelID:            "DraftingLiveEventsChannel",
						DefaultSound:         true,
						NotificationPriority: "PRIORITY_MAX",
					},
				},
			},
		}

		bodyBytes, err := json.Marshal(payload)
		if err != nil {
			slog.Error("Error codificando payload FCM", "error", err)
			return
		}

		url := fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", fcmProjectID)
		req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(bodyBytes))
		if err != nil {
			slog.Error("Error creando solicitud HTTP FCM", "error", err)
			return
		}
		req.Header.Set("Content-Type", "application/json; UTF-8")

		resp, err := fcmClient.Do(req)
		if err != nil {
			slog.Error("Error enviando push a Firebase FCM", "error", err)
			return
		}
		defer resp.Body.Close()

		respBytes, _ := io.ReadAll(resp.Body)
		if resp.StatusCode >= 200 && resp.StatusCode < 300 {
			slog.Info("🚀 Push Notification enviada exitosamente vía FCM", "topic", "live_events", "status", resp.Status, "response", string(respBytes))
		} else {
			slog.Error("Error devuelto por Firebase FCM", "status", resp.Status, "body", string(respBytes))
		}
	}()

	return nil
}

