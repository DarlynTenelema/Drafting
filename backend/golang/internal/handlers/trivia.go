package handlers

import (
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math"
	"math/rand"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"backend/internal/database"
	"backend/internal/gemini"
	"backend/internal/middleware"
	"backend/internal/models"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

// TriviaQuestionJSON representa una pregunta cargada directamente desde el archivo JSON editable
type TriviaQuestionJSON struct {
	ID            string   `json:"id"`
	Category      string   `json:"category"`
	Game          string   `json:"game"`
	QuestionText  string   `json:"question_text"`
	TargetName    string   `json:"target_name"`
	Clues         string   `json:"clues"`
	Options       []string `json:"options"`
	CorrectAnswer string   `json:"correct_answer"`
	Tolerance     int      `json:"tolerance"`
	MonthTag      string   `json:"month_tag"`
}

var (
	triviaCacheLock sync.RWMutex
	triviaFileCache = make(map[string][]TriviaQuestionJSON)
	triviaFileMod   = make(map[string]time.Time)
)

func findTriviaJSONPath(lang string) string {
	cleanLang := gemini.NormalizeLanguage(lang)
	candidates := []string{
		fmt.Sprintf("trivia_questions_%s.json", cleanLang),
		fmt.Sprintf("../../trivia_questions_%s.json", cleanLang),
		fmt.Sprintf("../trivia_questions_%s.json", cleanLang),
		fmt.Sprintf("backend/json/trivia_questions_%s.json", cleanLang),
		fmt.Sprintf("../json/trivia_questions_%s.json", cleanLang),
		fmt.Sprintf("../../backend/json/trivia_questions_%s.json", cleanLang),
		fmt.Sprintf("json/trivia_questions_%s.json", cleanLang),
		"trivia_questions.json",
		"../../trivia_questions.json",
		"../trivia_questions.json",
		"backend/json/trivia_questions.json",
		"../json/trivia_questions.json",
		"../../backend/json/trivia_questions.json",
		"json/trivia_questions.json",
	}
	for _, p := range candidates {
		if fi, err := os.Stat(p); err == nil && !fi.IsDir() {
			return p
		}
	}
	return ""
}

// loadQuestionsForLang carga las preguntas desde el archivo JSON y las recarga automáticamente si el archivo se edita
func loadQuestionsForLang(lang string) []TriviaQuestionJSON {
	path := findTriviaJSONPath(lang)
	if path == "" {
		return nil
	}

	fi, err := os.Stat(path)
	if err != nil {
		return nil
	}

	triviaCacheLock.RLock()
	cached, ok := triviaFileCache[path]
	lastMod := triviaFileMod[path]
	triviaCacheLock.RUnlock()

	if ok && !fi.ModTime().After(lastMod) {
		return cached
	}

	triviaCacheLock.Lock()
	defer triviaCacheLock.Unlock()

	data, err := os.ReadFile(path)
	if err != nil {
		return cached
	}

	var list []TriviaQuestionJSON
	if err := json.Unmarshal(data, &list); err != nil {
		log.Printf("⚠️ Error parseando JSON de trivia %s: %v", path, err)
		return cached
	}

	triviaFileCache[path] = list
	triviaFileMod[path] = fi.ModTime()
	log.Printf("📖 [TRIVIA] %d preguntas cargadas desde el archivo JSON editable: %s", len(list), path)
	return list
}

func findQuestionInJSON(qID string, lang string) *TriviaQuestionJSON {
	langs := []string{lang, "es", "en", "pt", "fr"}
	for _, l := range langs {
		questions := loadQuestionsForLang(l)
		for _, q := range questions {
			if q.ID == qID {
				return &q
			}
		}
	}
	return nil
}

// TriviaAnswerRequest payload enviado por el usuario al responder una pregunta
type TriviaAnswerRequest struct {
	QuestionID string `json:"question_id"`
	UserAnswer string `json:"user_answer"`
}

// GetTriviaStatus devuelve las vidas actuales y el progreso del usuario en cada categoría
func GetTriviaStatus(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	lang := r.URL.Query().Get("lang")
	if lang == "" {
		lang = r.Header.Get("Accept-Language")
	}
	jsonQuestions := loadQuestionsForLang(lang)

	categories := []models.TriviaCategory{
		models.TriviaCategoryItemCost,
		models.TriviaCategoryBuildPath,
		models.TriviaCategoryCounter,
	}

	type CategoryProgress struct {
		Category  string `json:"category"`
		Total     int64  `json:"total"`
		Completed int64  `json:"completed"`
	}

	var progressList []CategoryProgress
	for _, cat := range categories {
		var total int64
		var completed int64

		if len(jsonQuestions) > 0 {
			for _, q := range jsonQuestions {
				if q.Category == string(cat) {
					total++
				}
			}
		} else {
			database.DB.Model(&models.TriviaQuestion{}).Where("category = ? AND active = ?", cat, true).Count(&total)
		}

		database.DB.Model(&models.TriviaUserProgress{}).Where("user_id = ? AND category = ? AND is_correct = ?", user.ID, cat, true).Count(&completed)
		progressList = append(progressList, CategoryProgress{
			Category:  string(cat),
			Total:     total,
			Completed: completed,
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"trivia_lives": user.TriviaLives,
		"categories":   progressList,
	})
}

// GetTriviaQuestion obtiene una pregunta aleatoria que el usuario NO haya respondido correctamente aún
func GetTriviaQuestion(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	categoryRaw := strings.TrimSpace(r.URL.Query().Get("category"))
	if categoryRaw == "" {
		categoryRaw = string(models.TriviaCategoryItemCost)
	}
	category := models.TriviaCategory(categoryRaw)

	if category != models.TriviaCategoryItemCost &&
		category != models.TriviaCategoryBuildPath &&
		category != models.TriviaCategoryCounter {
		http.Error(w, "Categoría no válida. Usar: item_cost, build_path, counter", http.StatusBadRequest)
		return
	}

	lang := r.URL.Query().Get("lang")
	if lang == "" {
		lang = r.Header.Get("Accept-Language")
	}
	jsonQuestions := loadQuestionsForLang(lang)

	if len(jsonQuestions) > 0 {
		// Modo JSON: filtrar desde el archivo JSON editable
		var completedIDs []string
		database.DB.Model(&models.TriviaUserProgress{}).
			Where("user_id = ? AND category = ? AND is_correct = ?", user.ID, category, true).
			Pluck("question_id", &completedIDs)

		completedMap := make(map[string]bool)
		for _, cid := range completedIDs {
			completedMap[cid] = true
		}

		var eligible []TriviaQuestionJSON
		for _, q := range jsonQuestions {
			if q.Category == string(category) && !completedMap[q.ID] {
				eligible = append(eligible, q)
			}
		}

		if len(eligible) == 0 {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]interface{}{
				"completed_all": true,
				"message":       "¡Felicitaciones! Has completado todas las preguntas disponibles en esta modalidad.",
				"category":      category,
				"trivia_lives":  user.TriviaLives,
			})
			return
		}

		rand.Seed(time.Now().UnixNano())
		chosen := eligible[rand.Intn(len(eligible))]

		options := make([]string, len(chosen.Options))
		copy(options, chosen.Options)
		if len(options) > 1 {
			rand.Shuffle(len(options), func(i, j int) {
				options[i], options[j] = options[j], options[i]
			})
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]interface{}{
			"id":            chosen.ID,
			"category":      chosen.Category,
			"game":          chosen.Game,
			"question_text": chosen.QuestionText,
			"target_name":   chosen.TargetName,
			"clues":         chosen.Clues,
			"options":       options,
			"trivia_lives":  user.TriviaLives,
			"completed_all": false,
		})
		return
	}

	// Fallback a Base de Datos si no existe archivo JSON
	var question models.TriviaQuestion
	query := database.DB.Where("active = ? AND category = ? AND id NOT IN (SELECT question_id FROM trivia_user_progress WHERE user_id = ? AND is_correct = ?)",
		true, category, user.ID, true,
	).Order("RANDOM()").First(&question)

	if query.Error != nil {
		if errors.Is(query.Error, gorm.ErrRecordNotFound) {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]interface{}{
				"completed_all": true,
				"message":       "¡Felicitaciones! Has completado todas las preguntas disponibles en esta modalidad.",
				"category":      category,
				"trivia_lives":  user.TriviaLives,
			})
			return
		}
		http.Error(w, "Error obteniendo pregunta: "+query.Error.Error(), http.StatusInternalServerError)
		return
	}

	options := question.GetOptions()
	if len(options) > 1 {
		rand.Seed(time.Now().UnixNano())
		rand.Shuffle(len(options), func(i, j int) {
			options[i], options[j] = options[j], options[i]
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"id":            question.ID,
		"category":      question.Category,
		"game":          question.Game,
		"question_text": question.QuestionText,
		"target_name":   question.TargetName,
		"clues":         question.Clues,
		"options":       options,
		"trivia_lives":  user.TriviaLives,
		"completed_all": false,
	})
}

// SubmitTriviaAnswer valida la respuesta del usuario de forma segura y descuenta vida si se equivoca
func SubmitTriviaAnswer(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req TriviaAnswerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Cuerpo de solicitud inválido", http.StatusBadRequest)
		return
	}

	qIDStr := strings.TrimSpace(req.QuestionID)
	if qIDStr == "" {
		http.Error(w, "ID de pregunta requerido", http.StatusBadRequest)
		return
	}

	// 1. Verificar si el usuario tiene vidas disponibles
	if user.TriviaLives <= 0 {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusForbidden)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"error":        "no_lives",
			"message":      "No tienes vidas disponibles para jugar. Mira un anuncio de video para recibir 3 vidas o recarga en la tienda.",
			"trivia_lives": 0,
		})
		return
	}

	cleanUserAns := strings.TrimSpace(req.UserAnswer)
	var cleanCorrectAns string
	var questionCategory string
	var tolerance int

	// 2. Buscar primero en los archivos JSON editables
	lang := r.Header.Get("Accept-Language")
	jsonQ := findQuestionInJSON(qIDStr, lang)

	var questionUUID uuid.UUID
	parsedUUID, errUUID := uuid.Parse(qIDStr)
	if errUUID == nil {
		questionUUID = parsedUUID
	} else {
		questionUUID = uuid.NewMD5(uuid.NameSpaceDNS, []byte(qIDStr))
	}

	if jsonQ != nil {
		cleanCorrectAns = strings.TrimSpace(jsonQ.CorrectAnswer)
		questionCategory = jsonQ.Category
		tolerance = jsonQ.Tolerance
	} else {
		// Fallback a Base de Datos
		var question models.TriviaQuestion
		if err := database.DB.Where("id = ? AND active = ?", questionUUID, true).First(&question).Error; err != nil {
			http.Error(w, "Pregunta no encontrada o inactiva", http.StatusNotFound)
			return
		}
		cleanCorrectAns = strings.TrimSpace(question.CorrectAnswer)
		questionCategory = string(question.Category)
		tolerance = question.Tolerance
	}

	// 3. Evaluar si la respuesta es correcta
	isCorrect := false

	if questionCategory == string(models.TriviaCategoryItemCost) {
		re := regexp.MustCompile(`[0-9]+`)
		userDigits := re.FindString(cleanUserAns)
		correctDigits := re.FindString(cleanCorrectAns)

		if userDigits != "" && correctDigits != "" {
			uVal, err1 := strconv.Atoi(userDigits)
			cVal, err2 := strconv.Atoi(correctDigits)
			if err1 == nil && err2 == nil {
				diff := int(math.Abs(float64(uVal - cVal)))
				isCorrect = diff <= tolerance
			}
		}
		if !isCorrect {
			isCorrect = strings.EqualFold(cleanUserAns, cleanCorrectAns)
		}
	} else {
		isCorrect = strings.EqualFold(cleanUserAns, cleanCorrectAns)
	}

	// 4. Actualizar o insertar el progreso del usuario
	var progress models.TriviaUserProgress
	err := database.DB.Where("user_id = ? AND question_id = ?", user.ID, questionUUID).First(&progress).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		progress = models.TriviaUserProgress{
			UserID:        user.ID,
			QuestionID:    questionUUID,
			Category:      models.TriviaCategory(questionCategory),
			IsCorrect:     isCorrect,
			AttemptsCount: 1,
			LastAttemptAt: time.Now().UTC(),
		}
		database.DB.Create(&progress)
	} else {
		progress.AttemptsCount++
		progress.IsCorrect = isCorrect
		progress.LastAttemptAt = time.Now().UTC()
		database.DB.Save(&progress)
	}

	// 5. Aplicar lógica de vidas: si falló, descontar 1 vida
	feedbackMsg := "¡Excelente! Respuesta correcta."
	if !isCorrect {
		user.ConsumeTriviaLife()
		database.DB.Model(user).Update("trivia_lives", user.TriviaLives)
		feedbackMsg = fmt.Sprintf("Incorrecto. La respuesta correcta era: %s", cleanCorrectAns)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"is_correct":     isCorrect,
		"correct_answer": cleanCorrectAns,
		"message":        feedbackMsg,
		"trivia_lives":   user.TriviaLives,
	})
}

// RewardAdLives otorga +3 vidas al usuario tras visualizar un anuncio de video recompensado
func RewardAdLives(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	user.AddTriviaLives(3)
	if err := database.DB.Model(user).Update("trivia_lives", user.TriviaLives).Error; err != nil {
		http.Error(w, "Error actualizando vidas: "+err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":      true,
		"message":      "¡Has recibido +3 vidas de Trivia!",
		"lives_added":  3,
		"trivia_lives": user.TriviaLives,
	})
}

// ResetCategoryProgress reinicia las respuestas de una categoría para que el usuario pueda volver a jugar
func ResetCategoryProgress(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	categoryRaw := strings.TrimSpace(r.URL.Query().Get("category"))
	if categoryRaw == "" {
		http.Error(w, "category query parameter es requerido", http.StatusBadRequest)
		return
	}

	database.DB.Where("user_id = ? AND category = ?", user.ID, categoryRaw).Delete(&models.TriviaUserProgress{})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":  true,
		"message":  "Progreso de categoría reiniciado. Todas las preguntas están disponibles nuevamente.",
		"category": categoryRaw,
	})
}

// --- Endpoints Administrativos para Configurar y Editar Lotes Mensuales ---

type BatchUpsertQuestionsRequest struct {
	MonthTag   string                  `json:"month_tag"`
	ReplaceAll bool                    `json:"replace_all"` // Si es true, borra las preguntas activas anteriores del mismo tag
	Questions  []models.TriviaQuestion `json:"questions"`
}

// AdminBatchUpsertQuestions permite al administrador subir o renovar el lote mensual de preguntas
func AdminBatchUpsertQuestions(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil || user.Email != AuthorizedAdminEmail {
		http.Error(w, "Acceso restringido para administrador autorizado", http.StatusForbidden)
		return
	}

	var req BatchUpsertQuestionsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "JSON inválido: "+err.Error(), http.StatusBadRequest)
		return
	}

	if len(req.Questions) == 0 {
		http.Error(w, "La lista de preguntas no puede estar vacía", http.StatusBadRequest)
		return
	}

	monthTag := strings.TrimSpace(req.MonthTag)
	if monthTag == "" {
		monthTag = time.Now().UTC().Format("2006-01")
	}

	tx := database.DB.Begin()
	if req.ReplaceAll {
		if err := tx.Where("month_tag = ?", monthTag).Delete(&models.TriviaQuestion{}).Error; err != nil {
			tx.Rollback()
			http.Error(w, "Error limpiando preguntas anteriores: "+err.Error(), http.StatusInternalServerError)
			return
		}
	}

	insertedCount := 0
	for _, q := range req.Questions {
		q.MonthTag = monthTag
		q.Active = true
		if q.Game == "" {
			q.Game = "wild_rift"
		}
		if err := tx.Create(&q).Error; err != nil {
			tx.Rollback()
			http.Error(w, fmt.Sprintf("Error insertando pregunta '%s': %v", q.TargetName, err), http.StatusInternalServerError)
			return
		}
		insertedCount++
	}

	if err := tx.Commit().Error; err != nil {
		http.Error(w, "Error confirmando transacción: "+err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success":        true,
		"inserted_count": insertedCount,
		"month_tag":      monthTag,
		"message":        fmt.Sprintf("Se han configurado %d preguntas exitosamente para el lote %s", insertedCount, monthTag),
	})
}

// AdminListQuestions permite listar y filtrar preguntas para editar
func AdminListQuestions(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil || user.Email != AuthorizedAdminEmail {
		http.Error(w, "Acceso restringido", http.StatusForbidden)
		return
	}

	cat := r.URL.Query().Get("category")
	month := r.URL.Query().Get("month_tag")

	q := database.DB.Model(&models.TriviaQuestion{})
	if cat != "" {
		q = q.Where("category = ?", cat)
	}
	if month != "" {
		q = q.Where("month_tag = ?", month)
	}

	var questions []models.TriviaQuestion
	if err := q.Order("created_at DESC").Limit(300).Find(&questions).Error; err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(questions)
}

// AdminUpdateQuestion permite editar una pregunta específica existente
func AdminUpdateQuestion(w http.ResponseWriter, r *http.Request) {
	user, ok := r.Context().Value(middleware.UserContextKey).(*models.User)
	if !ok || user == nil || user.Email != AuthorizedAdminEmail {
		http.Error(w, "Acceso restringido", http.StatusForbidden)
		return
	}

	idStr := chi.URLParam(r, "id")
	qID, err := uuid.Parse(idStr)
	if err != nil {
		http.Error(w, "ID inválido", http.StatusBadRequest)
		return
	}

	var updateData map[string]interface{}
	if err := json.NewDecoder(r.Body).Decode(&updateData); err != nil {
		http.Error(w, "JSON inválido", http.StatusBadRequest)
		return
	}

	delete(updateData, "id")
	delete(updateData, "created_at")

	if err := database.DB.Model(&models.TriviaQuestion{}).Where("id = ?", qID).Updates(updateData).Error; err != nil {
		http.Error(w, "Error actualizando pregunta: "+err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"message": "Pregunta actualizada correctamente",
	})
}


