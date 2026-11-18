package gemini

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

type WRChampionsFile struct {
	TotalChampions int                 `json:"total_champions"`
	StrictRule     string              `json:"strict_rule"`
	Lanes          map[string][]string `json:"lanes"`
	Exclusive      map[string]struct {
		Name        string   `json:"name"`
		Title       string   `json:"title"`
		Roles       []string `json:"roles"`
		Class       string   `json:"class"`
		DamageType  string   `json:"damage_type"`
		Abilities   map[string]struct {
			Name        string `json:"name"`
			Type        string `json:"type"`
			Cooldown    string `json:"cooldown"`
			Description string `json:"description"`
		} `json:"abilities"`
		TacticalNotes string `json:"tactical_notes"`
	} `json:"exclusive_and_special_champions"`
	Champions []struct {
		Name   string   `json:"name"`
		Roles  []string `json:"roles"`
		Damage string   `json:"damage"`
		Style  string   `json:"style"`
	} `json:"champions"`
}

type WRRunesFile struct {
	RuneSystemRules string `json:"rune_system_rules"`
	SummonerSpells  []struct {
		Name   string `json:"name"`
		Effect string `json:"effect"`
	} `json:"summoner_spells"`
	Keystones []struct {
		Name     string `json:"name"`
		Category string `json:"category"`
		Effect   string `json:"effect"`
	} `json:"keystones"`
	Trees map[string]map[string][]struct {
		Name   string `json:"name"`
		Effect string `json:"effect"`
	} `json:"trees"`
}

type WRItemsFile struct {
	ItemSystemRules string `json:"item_system_rules"`
	Categories      map[string]map[string][]struct {
		Name   string `json:"name"`
		Cost   int    `json:"cost"`
		Active bool   `json:"active,omitempty"`
		Effect string `json:"effect"`
	} `json:"categories"`
}

var (
	wrOnce               sync.Once
	cachedChampPrompt    string
	cachedChatKnowledge  string
	cachedNorraKnowledge string
	champStyleMap        map[string]string
)

func findJSONFile(filename string) ([]byte, error) {
	candidates := []string{
		filepath.Join("..", "json", filename),
		filepath.Join("backend", "json", filename),
		filepath.Join("json", filename),
		filepath.Join("..", "..", "json", filename),
	}
	for _, path := range candidates {
		if data, err := os.ReadFile(path); err == nil {
			return data, nil
		}
	}
	return nil, fmt.Errorf("no se encontró %s", filename)
}

func initWRKnowledge() {
	wrOnce.Do(func() {
		champStyleMap = make(map[string]string)

		// 1. Cargar wr_champions.json
		if data, err := findJSONFile("wr_champions.json"); err == nil {
			var champs WRChampionsFile
			if err := json.Unmarshal(data, &champs); err == nil {
				var sb strings.Builder
				sb.WriteString("\nCATÁLOGO OFICIAL DE CAMPEONES DE WILD RIFT (143 CAMPEONES - PROHIBIDO SUGERIR CAMPEONES DE LOL PC FUERA DE ESTA LISTA):\n")
				for _, lane := range []string{"Baron", "Jungle", "Mid", "Dragon", "Support"} {
					if list, ok := champs.Lanes[lane]; ok {
						sb.WriteString(fmt.Sprintf("- %s: %s\n", lane, strings.Join(list, ", ")))
					}
				}
				sb.WriteString("- Nota especial Wild Rift: Norra (Maga Mid/Support exclusiva de Wild Rift: Q Estallido de Recuerdos inflige % vida máx a objetivos agrandados, W Travesía sin Destino envía enemigos 1.5s a otra dimensión sin poder atacar ni usar habilidades, E Hilos del Regreso ralentiza y agranda enemigos, R ¡Portales a Raudales! crea círculo de portales), Mel (Maga Mid con escudo reflector y proyección solar), Yunara (Tiradora Dragon Lane).\n")
				cachedChampPrompt = sb.String()

				for _, c := range champs.Champions {
					champStyleMap[strings.ToLower(c.Name)] = fmt.Sprintf("%s (%s - %s): %s", c.Name, strings.Join(c.Roles, "/"), c.Damage, c.Style)
				}

				if norra, ok := champs.Exclusive["Norra"]; ok {
					cachedNorraKnowledge = fmt.Sprintf(
						"HABILIDADES EXACTAS DE NORRA (EXCLUSIVA DE WILD RIFT - %s):\n- Pasiva (%s, %s): %s\n- Q (%s, %s): %s\n- W (%s, %s): %s\n- E (%s, %s): %s\n- R (%s, %s): %s\n- Táctica: %s\n",
						norra.Title,
						norra.Abilities["passive"].Name, norra.Abilities["passive"].Cooldown, norra.Abilities["passive"].Description,
						norra.Abilities["q"].Name, norra.Abilities["q"].Cooldown, norra.Abilities["q"].Description,
						norra.Abilities["w"].Name, norra.Abilities["w"].Cooldown, norra.Abilities["w"].Description,
						norra.Abilities["e"].Name, norra.Abilities["e"].Cooldown, norra.Abilities["e"].Description,
						norra.Abilities["r"].Name, norra.Abilities["r"].Cooldown, norra.Abilities["r"].Description,
						norra.TacticalNotes,
					)
				}
				log.Printf("✅ Catálogo de %d campeones de Wild Rift cargado en memoria.", champs.TotalChampions)
			}
		}

		if cachedChampPrompt == "" {
			cachedChampPrompt = `
CATÁLOGO OFICIAL DE CAMPEONES DE WILD RIFT (143 CAMPEONES - PROHIBIDO MEZCLAR CON LOL PC):
- Baron: Aatrox, Akali, Ambessa, Aurora, Camille, Cho'Gath, Darius, Dr. Mundo, Fiora, Garen, Gnar, Gragas, Gwen, Irelia, Jarvan IV, Jax, Jayce, Kayle, Kennen, K'Sante, Malphite, Maokai, Mordekaiser, Nasus, Nautilus, Nidalee, Olaf, Ornn, Pantheon, Poppy, Renekton, Riven, Rumble, Ryze, Sett, Shen, Singed, Sion, Skarner, Swain, Sylas, Teemo, Tryndamere, Urgot, Viego, Vladimir, Volibear, Warwick, Wukong, Yasuo, Yone
- Jungle: Aatrox, Ambessa, Amumu, Camille, Cho'Gath, Darius, Diana, Dr. Mundo, Ekko, Evelynn, Fiddlesticks, Fizz, Gragas, Graves, Gwen, Hecarim, Jarvan IV, Jax, Kayn, Kha'Zix, Kindred, Lee Sin, Lillia, Maestro Yi, Maokai, Morgana, Nautilus, Nidalee, Nilah, Nocturne, Nunu y Willump, Olaf, Pantheon, Poppy, Rammus, Rengar, Riven, Shen, Shyvana, Skarner, Sylas, Taliyah, Talon, Tryndamere, Vi, Viego, Volibear, Warwick, Wukong, Xin Zhao, Yone, Zed
- Mid: Ahri, Akali, Akshan, Annie, Aurelion Sol, Aurora, Brand, Corki, Diana, Ekko, Fizz, Galio, Heimerdinger, Hwei, Irelia, Jayce, Karma, Kassadin, Katarina, Kayle, Kennen, Lissandra, Lux, Mel, Morgana, Norra, Orianna, Rumble, Ryze, Seraphine, Swain, Sylas, Syndra, Taliyah, Talon, Teemo, Twisted Fate, Veigar, Vel'Koz, Vex, Viktor, Vladimir, Yasuo, Yone, Zed, Ziggs, Zoe, Zyra
- Dragon (ADC): Ashe, Caitlyn, Corki, Draven, Ezreal, Jhin, Jinx, Kai'Sa, Kalista, Kog'Maw, Lucian, Miss Fortune, Samira, Senna, Sivir, Smolder, Tristana, Twitch, Varus, Vayne, Xayah, Yunara, Zeri
- Support: Alistar, Bardo, Blitzcrank, Brand, Braum, Galio, Hwei, Janna, Karma, Leona, Lulu, Lux, Malphite, Maokai, Milio, Morgana, Nami, Nautilus, Ornn, Pyke, Rakan, Rell, Senna, Seraphine, Sona, Soraka, Swain, Thresh, Veigar, Vel'Koz, Yuumi, Zilean, Zyra
`
		}

		// 2. Cargar wr_runes.json y wr_items.json para el Chatbot
		var chatSB strings.Builder
		chatSB.WriteString("BASE DE DATOS OFICIAL DE WILD RIFT (PROHIBIDO MEZCLAR CON LOL PC):\n")

		if rData, err := findJSONFile("wr_runes.json"); err == nil {
			var runes WRRunesFile
			if err := json.Unmarshal(rData, &runes); err == nil {
				chatSB.WriteString("1. REGLA DE RUNAS EN WILD RIFT: 1 Runa Clave + 3 Runas de Rama Principal (1 por fila) + 1 Runa Secundaria.\n")
				var ksNames []string
				for _, k := range runes.Keystones {
					ksNames = append(ksNames, fmt.Sprintf("%s (%s)", k.Name, k.Category))
				}
				chatSB.WriteString("- Runas Clave disponibles: " + strings.Join(ksNames, ", ") + ".\n")
				for treeName, slots := range runes.Trees {
					var s1, s2, s3 []string
					for _, r := range slots["slot_1"] {
						s1 = append(s1, r.Name)
					}
					for _, r := range slots["slot_2"] {
						s2 = append(s2, r.Name)
					}
					for _, r := range slots["slot_3"] {
						s3 = append(s3, r.Name)
					}
					chatSB.WriteString(fmt.Sprintf("- Rama %s: Fila1[%s] | Fila2[%s] | Fila3[%s]\n",
						treeName, strings.Join(s1, ", "), strings.Join(s2, ", "), strings.Join(s3, ", ")))
				}
				var spells []string
				for _, sp := range runes.SummonerSpells {
					spells = append(spells, sp.Name)
				}
				chatSB.WriteString("- Hechizos de invocador en WR: " + strings.Join(spells, ", ") + ".\n")
			}
		}

		if iData, err := findJSONFile("wr_items.json"); err == nil {
			var items WRItemsFile
			if err := json.Unmarshal(iData, &items); err == nil {
				chatSB.WriteString("2. OBJETOS Y BOTAS EN WILD RIFT ACTUAL: " + items.ItemSystemRules + "\n")
				for cat, tiers := range items.Categories {
					var names []string
					for _, tierName := range []string{"mejoradas", "mejorado", "nivel_medio", "iniciales"} {
						if list, ok := tiers[tierName]; ok {
							for _, it := range list {
								act := ""
								if it.Active {
									act = " [ACTIVA]"
								}
								names = append(names, fmt.Sprintf("%s (%dg%s)", it.Name, it.Cost, act))
							}
						}
					}
					if len(names) > 0 {
						chatSB.WriteString(fmt.Sprintf("- Objetos %s: %s\n", cat, strings.Join(names, ", ")))
					}
				}
			}
		}

		cachedChatKnowledge = chatSB.String()
		log.Println("✅ Base de conocimiento de Runas y Objetos de Wild Rift cargada en memoria.")
	})
}

func GetWildRiftChampionsContext() string {
	initWRKnowledge()
	return cachedChampPrompt
}

func GetWildRiftChatContext(userMessage string, draftContext string) string {
	initWRKnowledge()
	var sb strings.Builder
	sb.WriteString(cachedChatKnowledge)

	lowerMsg := strings.ToLower(userMessage + " " + draftContext)
	if strings.Contains(lowerMsg, "norra") && cachedNorraKnowledge != "" {
		sb.WriteString("\n" + cachedNorraKnowledge)
	}

	// Añadir detalles tácticos de cualquier campeón mencionado en la pregunta o en el draft
	var matchedChamps []string
	for champKey, desc := range champStyleMap {
		if len(champKey) >= 3 && strings.Contains(lowerMsg, champKey) {
			matchedChamps = append(matchedChamps, desc)
		}
	}
	if len(matchedChamps) > 0 {
		sb.WriteString("\nDATOS TÁCTICOS DE CAMPEONES EN ESTA PARTIDA:\n- " + strings.Join(matchedChamps, "\n- ") + "\n")
	}

	return sb.String()
}
