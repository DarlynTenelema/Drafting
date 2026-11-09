package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math/rand"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
	"google.golang.org/genai"
)

type RiotItem struct {
	Name        string   `json:"name"`
	Description string   `json:"description"`
	Gold        RiotGold `json:"gold"`
	From        []string `json:"from"`
	Into        []string `json:"into"`
	Tags        []string `json:"tags"`
	InStore     *bool    `json:"inStore"`
}

type RiotGold struct {
	Base        int  `json:"base"`
	Purchasable bool `json:"purchasable"`
	Total       int  `json:"total"`
	Sell        int  `json:"sell"`
}

type RiotItemData struct {
	Version string              `json:"version"`
	Data    map[string]RiotItem `json:"data"`
}

type RiotChampionData struct {
	Version string                          `json:"version"`
	Data    map[string]struct{ Name string } `json:"data"`
}

type TriviaQuestionExport struct {
	ID            string   `json:"id"`
	Category      string   `json:"category"`      // item_cost, build_path, counter
	Game          string   `json:"game"`          // wild_rift
	QuestionText  string   `json:"question_text"`
	TargetName    string   `json:"target_name"`
	Clues         string   `json:"clues"`
	Options       []string `json:"options"`
	CorrectAnswer string   `json:"correct_answer"`
	Tolerance     int      `json:"tolerance"`
	MonthTag      string   `json:"month_tag"`
}

var langConfig = map[string]struct {
	riotLocale       string
	itemCostQuestion string
	buildQuestion    string
	counterQuestion  string
	cluePrefix       string
}{
	"es": {
		riotLocale:       "es_ES",
		itemCostQuestion: "¿Cuánto cuesta este objeto?",
		buildQuestion:    "¿Qué se está armando?",
		counterQuestion:  "¿Cuál es el counter de este campeón?",
		cluePrefix:       "Componentes",
	},
	"en": {
		riotLocale:       "en_US",
		itemCostQuestion: "How much does this item cost?",
		buildQuestion:    "What is being built?",
		counterQuestion:  "Who is the counter to this champion?",
		cluePrefix:       "Components",
	},
	"pt": {
		riotLocale:       "pt_BR",
		itemCostQuestion: "Quanto custa este item?",
		buildQuestion:    "O que está sendo construído?",
		counterQuestion:  "Qual é o counter deste campeão?",
		cluePrefix:       "Componentes",
	},
	"fr": {
		riotLocale:       "fr_FR",
		itemCostQuestion: "Combien coûte cet objet ?",
		buildQuestion:    "Que fabrique-t-il ?",
		counterQuestion:  "Quel est le counter de ce champion ?",
		cluePrefix:       "Composants",
	},
}

func fetchJSON(url string, target interface{}) error {
	resp, err := http.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	return json.Unmarshal(body, target)
}

func main() {
	rand.Seed(time.Now().UnixNano())
	log.Println("🚀 Iniciando generador de 600 encuestas de Trivia...")

	// 1. Obtener última versión de Data Dragon
	var versions []string
	if err := fetchJSON("https://ddragon.leagueoflegends.com/api/versions.json", &versions); err != nil || len(versions) == 0 {
		log.Fatalf("Error obteniendo versión de Data Dragon: %v", err)
	}
	version := versions[0]
	log.Printf("📦 Versión oficial más reciente de Riot: %s", version)

	// 2. Cargar lista de campeones oficiales
	var champData RiotChampionData
	champURL := fmt.Sprintf("https://ddragon.leagueoflegends.com/cdn/%s/data/es_ES/champion.json", version)
	if err := fetchJSON(champURL, &champData); err != nil {
		log.Fatalf("Error cargando campeones de Riot: %v", err)
	}
	var champNames []string
	for _, c := range champData.Data {
		clean := strings.TrimSpace(c.Name)
		if clean != "" {
			champNames = append(champNames, clean)
		}
	}
	log.Printf("🛡️ Cargados %d campeones oficiales de Riot Games.", len(champNames))

	// 3. Inicializar Gemini para los counters usando glassy-508419-c57039b8dad3.json
	saPath := `../../glassy-508419-c57039b8dad3.json`
	saDataRaw, err := os.ReadFile(saPath)
	if err != nil {
		log.Fatalf("Error leyendo credenciales de service account: %v", err)
	}
	var sa struct {
		ProjectID string `json:"project_id"`
	}
	json.Unmarshal(saDataRaw, &sa)

	os.Setenv("GOOGLE_APPLICATION_CREDENTIALS", saPath)
	ctx := context.Background()
	aiClient, err := genai.NewClient(ctx, &genai.ClientConfig{
		Backend:  genai.BackendEnterprise,
		Project:  sa.ProjectID,
		Location: "us-central1",
	})
	if err != nil {
		log.Fatalf("Error conectando con Gemini Enterprise: %v", err)
	}

	// 4. Generar lote de counters con Gemini (200 matchups)
	log.Println("🧠 Generando 200 matchups de counters con Gemini 2.5 Flash...")
	counterQuestions := generateCountersWithGemini(ctx, aiClient, champNames)
	log.Printf("✅ %d preguntas de counters generadas exitosamente.", len(counterQuestions))

	// 5. Para cada idioma (es, en, pt, fr), construir los archivos JSON de preguntas
	monthTag := time.Now().UTC().Format("2006-01")

	for langCode, cfg := range langConfig {
		log.Printf("🌍 Procesando preguntas para idioma [%s - %s]...", langCode, cfg.riotLocale)
		itemURL := fmt.Sprintf("https://ddragon.leagueoflegends.com/cdn/%s/data/%s/item.json", version, cfg.riotLocale)
		var itemData RiotItemData
		if err := fetchJSON(itemURL, &itemData); err != nil {
			log.Printf("⚠️ Error descargando items en %s: %v", cfg.riotLocale, err)
			continue
		}

		// Filtrar items comprables reales
		var validItems []ItemInfo
		var compositeItems []ItemInfo

		itemMap := make(map[string]string)
		for id, item := range itemData.Data {
			name := strings.TrimSpace(item.Name)
			if name == "" || strings.HasPrefix(name, "Gangplank") || strings.Contains(name, "Quick Charge") {
				continue
			}
			if item.Gold.Purchasable && item.Gold.Total > 0 {
				itemMap[id] = name
				info := ItemInfo{
					ID:    id,
					Name:  name,
					Total: item.Gold.Total,
					From:  item.From,
				}
				validItems = append(validItems, info)
				if len(item.From) >= 2 {
					compositeItems = append(compositeItems, info)
				}
			}
		}

		var allQuestions []TriviaQuestionExport

		// A) Sub-pantalla 1: ¿Cuánto cuesta este objeto? (200 preguntas)
		log.Printf("  • Creando 200 preguntas de costo...")
		costCount := 0
		shuffledItems := make([]ItemInfo, len(validItems))
		copy(shuffledItems, validItems)
		rand.Shuffle(len(shuffledItems), func(i, j int) {
			shuffledItems[i], shuffledItems[j] = shuffledItems[j], shuffledItems[i]
		})

		for _, item := range shuffledItems {
			if costCount >= 200 {
				break
			}
			allQuestions = append(allQuestions, TriviaQuestionExport{
				ID:            uuid.New().String(),
				Category:      "item_cost",
				Game:          "wild_rift",
				QuestionText:  cfg.itemCostQuestion,
				TargetName:    item.Name,
				Clues:         "",
				Options:       []string{},
				CorrectAnswer: fmt.Sprintf("%d", item.Total),
				Tolerance:     0,
				MonthTag:      monthTag,
			})
			costCount++
		}

		// Si faltan para llegar a 200, rellenamos con variantes
		for costCount < 200 && len(shuffledItems) > 0 {
			item := shuffledItems[costCount%len(shuffledItems)]
			allQuestions = append(allQuestions, TriviaQuestionExport{
				ID:            uuid.New().String(),
				Category:      "item_cost",
				Game:          "wild_rift",
				QuestionText:  cfg.itemCostQuestion,
				TargetName:    item.Name,
				Clues:         "",
				Options:       []string{},
				CorrectAnswer: fmt.Sprintf("%d", item.Total),
				Tolerance:     0,
				MonthTag:      monthTag,
			})
			costCount++
		}

		// B) Sub-pantalla 2: ¿Qué se está armando? (200 preguntas)
		log.Printf("  • Creando 200 preguntas de red de armado...")
		buildCount := 0
		shuffledComposite := make([]ItemInfo, len(compositeItems))
		copy(shuffledComposite, compositeItems)
		rand.Shuffle(len(shuffledComposite), func(i, j int) {
			shuffledComposite[i], shuffledComposite[j] = shuffledComposite[j], shuffledComposite[i]
		})

		for _, comp := range shuffledComposite {
			if buildCount >= 200 {
				break
			}
			// Obtener nombres de los componentes
			var compNames []string
			for _, fID := range comp.From {
				if fName, ok := itemMap[fID]; ok {
					compNames = append(compNames, fName)
				}
			}
			if len(compNames) < 2 {
				continue
			}

			clueText := strings.Join(compNames, " + ")

			// Elegir 3 distractores aleatorios
			distractors := pickDistractors(comp.Name, validItems, 3)
			opts := append([]string{comp.Name}, distractors...)
			rand.Shuffle(len(opts), func(i, j int) { opts[i], opts[j] = opts[j], opts[i] })

			allQuestions = append(allQuestions, TriviaQuestionExport{
				ID:            uuid.New().String(),
				Category:      "build_path",
				Game:          "wild_rift",
				QuestionText:  cfg.buildQuestion,
				TargetName:    "Armado",
				Clues:         clueText,
				Options:       opts,
				CorrectAnswer: comp.Name,
				Tolerance:     0,
				MonthTag:      monthTag,
			})
			buildCount++
		}

		for buildCount < 200 && len(shuffledComposite) > 0 {
			comp := shuffledComposite[buildCount%len(shuffledComposite)]
			var compNames []string
			for _, fID := range comp.From {
				if fName, ok := itemMap[fID]; ok {
					compNames = append(compNames, fName)
				}
			}
			clueText := strings.Join(compNames, " + ")
			distractors := pickDistractors(comp.Name, validItems, 3)
			opts := append([]string{comp.Name}, distractors...)
			rand.Shuffle(len(opts), func(i, j int) { opts[i], opts[j] = opts[j], opts[i] })

			allQuestions = append(allQuestions, TriviaQuestionExport{
				ID:            uuid.New().String(),
				Category:      "build_path",
				Game:          "wild_rift",
				QuestionText:  cfg.buildQuestion,
				TargetName:    "Armado",
				Clues:         clueText,
				Options:       opts,
				CorrectAnswer: comp.Name,
				Tolerance:     0,
				MonthTag:      monthTag,
			})
			buildCount++
		}

		// C) Sub-pantalla 3: ¿Cuál es el counter? (200 preguntas)
		log.Printf("  • Integrando 200 preguntas de counters para %s...", langCode)
		for _, cq := range counterQuestions {
			localizedQ := cq
			localizedQ.ID = uuid.New().String()
			localizedQ.QuestionText = cfg.counterQuestion
			localizedQ.MonthTag = monthTag
			allQuestions = append(allQuestions, localizedQ)
		}

		// Guardar archivo JSON
		filename := fmt.Sprintf("trivia_questions_%s.json", langCode)
		outPath := filepath.Join("..", "..", filename)
		fileBytes, err := json.MarshalIndent(allQuestions, "", "  ")
		if err != nil {
			log.Printf("Error formateando JSON: %v", err)
			continue
		}
		if err := os.WriteFile(outPath, fileBytes, 0644); err != nil {
			log.Printf("Error escribiendo archivo %s: %v", outPath, err)
		} else {
			log.Printf("🎉 ¡Archivo creado exitosamente con %d preguntas!: %s", len(allQuestions), filename)
		}

		// Si es español, también guardamos como trivia_questions.json por defecto
		if langCode == "es" {
			defaultPath := filepath.Join("..", "..", "trivia_questions.json")
			os.WriteFile(defaultPath, fileBytes, 0644)
			log.Printf("⭐ Archivo maestro generado: trivia_questions.json")
		}
	}

	log.Println("✨ ¡Proceso completado al 100%! Todas las encuestas están listas y son 100% editables.")
}

type ItemInfo struct {
	ID    string
	Name  string
	Total int
	From  []string
}

func pickDistractors(correct string, pool []ItemInfo, count int) []string {
	var res []string
	seen := map[string]bool{correct: true}

	for i := 0; i < 50 && len(res) < count; i++ {
		idx := rand.Intn(len(pool))
		cand := pool[idx].Name
		if !seen[cand] && cand != "" {
			seen[cand] = true
			res = append(res, cand)
		}
	}
	return res
}

type CounterJSON struct {
	TargetChampion string   `json:"target_champion"`
	Counter        string   `json:"counter"`
	Options        []string `json:"options"`
}

func generateCountersWithGemini(ctx context.Context, client *genai.Client, champions []string) []TriviaQuestionExport {
	var questions []TriviaQuestionExport

	// Haremos 4 tandas de 50 campeones cada una para obtener exactamente 200 matchups de counters
	batchSize := 50
	totalTarget := 200

	promptTemplate := `Eres un analista Challenger de League of Legends y Wild Rift.
Genera exactamente %d preguntas de Trivia para identificar el CHAMPION COUNTER (campeón que contrarresta a otro en fase de líneas o peleas de equipo).

Elige %d campeones de esta lista oficial:
%s

Devuelve ÚNICAMENTE un array JSON válido sin texto adicional, con este esquema exacto:
[
  {
    "target_champion": "Darius",
    "counter": "Vayne",
    "options": ["Vayne", "Garen", "Nasus", "Sion"]
  }
]
Reglas:
- Cada objeto debe tener 4 opciones (1 counter real y 3 distractores que NO sean counters fuertes).
- "counter" debe estar incluido dentro del array "options".
- Devuelve SOLO el JSON.`

	for len(questions) < totalTarget {
		needed := totalTarget - len(questions)
		if needed > batchSize {
			needed = batchSize
		}

		rand.Shuffle(len(champions), func(i, j int) { champions[i], champions[j] = champions[j], champions[i] })
		subset := champions[:needed]
		prompt := fmt.Sprintf(promptTemplate, needed, needed, strings.Join(subset, ", "))

		budget := int32(0)
		resp, err := client.Models.GenerateContent(ctx, "gemini-2.5-flash", []*genai.Content{
			{
				Role:  "user",
				Parts: []*genai.Part{{Text: prompt}},
			},
		}, &genai.GenerateContentConfig{
			ThinkingConfig: &genai.ThinkingConfig{
				ThinkingBudget: &budget,
			},
		})

		if err != nil {
			log.Printf("⚠️ Error llamando a Gemini para lote de counters: %v", err)
			break
		}

		respText := resp.Text()
		respText = strings.TrimPrefix(respText, "```json")
		respText = strings.TrimPrefix(respText, "```")
		respText = strings.TrimSuffix(respText, "```")
		respText = strings.TrimSpace(respText)

		var parsed []CounterJSON
		if err := json.Unmarshal([]byte(respText), &parsed); err != nil {
			log.Printf("⚠️ Error decodificando JSON de Gemini: %v. Raw: %s", err, respText)
			// Continuar con los que tengamos
			continue
		}

		for _, item := range parsed {
			opts := item.Options
			rand.Shuffle(len(opts), func(i, j int) { opts[i], opts[j] = opts[j], opts[i] })
			questions = append(questions, TriviaQuestionExport{
				ID:            uuid.New().String(),
				Category:      "counter",
				Game:          "wild_rift",
				QuestionText:  "¿Cuál es el counter de este campeón?",
				TargetName:    item.TargetChampion,
				Clues:         "",
				Options:       opts,
				CorrectAnswer: item.Counter,
				Tolerance:     0,
				MonthTag:      time.Now().UTC().Format("2006-01"),
			})
			if len(questions) >= totalTarget {
				break
			}
		}
		log.Printf("  -> Acumulados %d / %d counters con Gemini...", len(questions), totalTarget)
	}

	return questions
}
