package gemini

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"

	"backend/internal/config"

	"google.golang.org/genai"
)

var aiClient *genai.Client

func InitVertexClient() error {
	ctx := context.Background()

	saJSON := config.GetEnv("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", "")
	if saJSON == "" {
		return fmt.Errorf("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is not configured")
	}

	var saData struct {
		ProjectID string `json:"project_id"`
	}
	if err := json.Unmarshal([]byte(saJSON), &saData); err != nil {
		return fmt.Errorf("error leyendo service account json: %w", err)
	}

	tmpFile, err := os.CreateTemp("", "gcp-credentials-*.json")
	if err != nil {
		return fmt.Errorf("error creando archivo temporal: %w", err)
	}

	if _, err := tmpFile.Write([]byte(saJSON)); err != nil {
		return fmt.Errorf("error escribiendo credenciales: %w", err)
	}
	tmpFile.Close()

	os.Setenv("GOOGLE_APPLICATION_CREDENTIALS", tmpFile.Name())

	client, err := genai.NewClient(ctx, &genai.ClientConfig{
		Backend:  genai.BackendEnterprise,
		Project:  saData.ProjectID,
		Location: "us-central1",
	})
	if err != nil {
		return fmt.Errorf("error creando cliente Enterprise: %w", err)
	}

	aiClient = client
	log.Println("✅ Cliente Gemini Enterprise Agent Platform inicializado correctamente para Producción.")
	return nil
}

// NormalizeLanguage limpia códigos como "pt_BR", "pt-PT", "en-US", "en_GB", "fr_CA", "es_MX" a "es", "pt", "en", "fr"
func NormalizeLanguage(raw string) string {
	clean := strings.ToLower(strings.TrimSpace(raw))
	if strings.HasPrefix(clean, "pt") {
		return "pt"
	}
	if strings.HasPrefix(clean, "en") {
		return "en"
	}
	if strings.HasPrefix(clean, "fr") {
		return "fr"
	}
	return "es"
}

func buildDraftPrompt(mainRole, secondaryRole, autofillRole, gameMode, otpChampions, lang string, excludeChampions ...string) string {
	isPC := strings.EqualFold(strings.TrimSpace(gameMode), "lol_pc") || strings.EqualFold(strings.TrimSpace(gameMode), "pc")

	excludeList := ""
	if len(excludeChampions) > 0 && strings.TrimSpace(excludeChampions[0]) != "" {
		excludeList = strings.TrimSpace(excludeChampions[0])
	}

	roleClauseEs := "detectando automáticamente la posición asignada y las necesidades de la composición"
	if mainRole != "" && !strings.EqualFold(mainRole, "Auto") {
		roleClauseEs = fmt.Sprintf("considerando los roles preferidos: %s, %s, %s", mainRole, secondaryRole, autofillRole)
	}

	roleClausePt := "detectando automaticamente a rota atribuída e as necessidades da composição"
	if mainRole != "" && !strings.EqualFold(mainRole, "Auto") {
		roleClausePt = fmt.Sprintf("considerando as rotas preferidas: %s, %s, %s", mainRole, secondaryRole, autofillRole)
	}

	roleClauseEn := "automatically detecting the assigned role and composition needs"
	if mainRole != "" && !strings.EqualFold(mainRole, "Auto") {
		roleClauseEn = fmt.Sprintf("considering preferred roles: %s, %s, %s", mainRole, secondaryRole, autofillRole)
	}

	roleClauseFr := "en détectant automatiquement le rôle assigné et les besoins de la composition"
	if mainRole != "" && !strings.EqualFold(mainRole, "Auto") {
		roleClauseFr = fmt.Sprintf("en tenant compte des rôles préférés : %s, %s, %s", mainRole, secondaryRole, autofillRole)
	}

	var excludeClauseEs, excludeClausePt, excludeClauseEn, excludeClauseFr string
	if excludeList != "" {
		excludeClauseEs = fmt.Sprintf("\n\nAVISO DE RECONSULTA: El jugador ya vio las siguientes opciones y solicita nuevas alternativas: %s. ESTÁ ESTRICTAMENTE PROHIBIDO repetir cualquiera de esos campeones. Brinda un nuevo PLAN A óptimo diferente y dos recomendaciones similares distintas.", excludeList)
		excludeClausePt = fmt.Sprintf("\n\nAVISO DE ATUALIZAÇÃO: O jogador já viu as siguientes opções e solicita novas alternativas: %s. É ESTRITAMENTE PROIBIDO repetir qualquer um desses campeões. Forneça um novo PLANO A ótimo diferente e duas recomendações semelhantes distintas.", excludeList)
		excludeClauseEn = fmt.Sprintf("\n\nREFRESH NOTICE: The player has already seen these options and requests new alternatives: %s. You are STRICTLY FORBIDDEN from repeating any of these champions. Provide a new, different optimal PLAN A and two different similar recommendations.", excludeList)
		excludeClauseFr = fmt.Sprintf("\n\nAVIS D'ACTUALISATION : Le joueur a déjà vu ces options et demande de nouvelles alternatives : %s. Il est STRICTEMENT INTERDIT de répéter l'un de ces champions. Fournis un nouveau PLAN A optimal différent et deux recommandations similaires distinctes.", excludeList)
	}

	var otpClauseEs, otpClausePt, otpClauseEn, otpClauseFr string
	if cleanOtp := strings.TrimSpace(otpChampions); cleanOtp != "" {
		targetRole := mainRole
		if targetRole == "" || strings.EqualFold(targetRole, "Auto") {
			targetRole = "detectada"
		}
		otpClauseEs = fmt.Sprintf(`

REGLA ESPECIAL DE JUGADOR OTP (%s) Y FALLBACK POR AUTOFILL:
- El jugador es especialista / OTP con: %s.
- VIABILIDAD POR ROL Y REGLA DE AUTOFILL:
  1. Si la línea asignada (o fijada: %s) es una posición estándar y VIABLE para su OTP (%s), dale máxima prioridad como PLAN A o explica cómo jugarlo en este emparejamiento.
  2. Si la línea asignada NO es viable para su OTP (por ejemplo: Autofill a Soporte, ADC, Jungla o Top donde dicho campeón no cumple el rol ni es estándar), ESTÁ ESTRICTAMENTE PROHIBIDO FORZAR SU OTP.
     En la línea de 'Situación' advierte brevemente entre paréntesis: '(Tu OTP %s no es viable en la línea de %s)'.
     En el 'PLAN A' recomienda el mejor campeón counter/meta estándar para ganar esa posición asignada.
     En 'Recomendaciones similares' incluye opciones cómodas y naturales para dicho rol.`, cleanOtp, cleanOtp, targetRole, cleanOtp, cleanOtp, targetRole)

		otpClausePt = fmt.Sprintf(`

REGRA ESPECIAL DE JOGADOR OTP (%s) E FALLBACK POR AUTOFILL:
- O jogador é especialista / OTP com: %s.
- VIABILIDADE POR ROTA E REGRA DE AUTOFILL:
  1. Se a rota atribuída (ou selecionada: %s) for VIÁVEL para seu OTP (%s), dê prioridade máxima como PLANO A ou explique como jogá-lo nesta partida.
  2. Se a rota atribuída NÃO for viável para seu OTP (exemplo: caiu Autofill como Suporte, ADC ou Selva onde esse campeão não cumpre a função), É PROIBIDO FORÇAR SEU OTP.
     Na linha de 'Situação' alerte brevemente entre parênteses: '(Seu OTP %s não é viável na rota de %s)'.
     No 'PLANO A' recomende o melhor campeão ótimo padrão para vencer nessa rota.`, cleanOtp, cleanOtp, targetRole, cleanOtp, cleanOtp, targetRole)

		otpClauseEn = fmt.Sprintf(`

SPECIAL OTP PLAYER RULE (%s) & AUTOFILL FALLBACK:
- The player is a dedicated OTP / specialist on: %s.
- ROLE VIABILITY & AUTOFILL RULE:
  1. If the assigned (or selected: %s) lane is a standard and VIABLE role for their OTP champion (%s), give it top priority as PLAN A or explain how to pilot it into this matchup.
  2. If the assigned lane is NOT viable for their OTP champion (for example: autofilled into Support, ADC, Jungle, or Top where this champion does not fit), DO NOT FORCE THE OTP.
     In the 'Situation' line, briefly add in parentheses: '(Your OTP %s is not viable in the %s role)'.
     In 'PLAN A', recommend the best optimal standard counter champion to secure the win in that assigned lane.`, cleanOtp, cleanOtp, targetRole, cleanOtp, cleanOtp, targetRole)

		otpClauseFr = fmt.Sprintf(`

RÈGLE SPÉCIALE JOUEUR OTP (%s) ET GESTION DE L'AUTOFILL :
- Le joueur est spécialiste / OTP sur : %s.
- VIABILITÉ DU RÔLE ET AUTOFILL :
  1. Si le rôle assigné (ou sélectionné : %s) est standard et VIABLE pour son champion OTP (%s), donne-lui priorité absolue en PLAN A.
  2. Si le rôle assigné N'EST PAS viable pour son champion OTP (ex: autofill Support, ADC ou Jungle où cet OTP ne fonctionne pas), IL EST STRICTEMENT INTERDIT DE FORCER L'OTP.
     Dans la ligne 'Situation', indique brièvement entre parenthèses : '(Ton OTP %s n'est pas viable comme %s)'.
     En 'PLAN A', recommande le meilleur champion adapté et performant pour cette voie.`, cleanOtp, cleanOtp, targetRole, cleanOtp, cleanOtp, targetRole)
	}

	switch NormalizeLanguage(lang) {
	case "pt":
		if isPC {
			return fmt.Sprintf(`Você é um Analista Mestre e Challenger de League of Legends (PC).
Analise a captura de tela durante a seleção de campeões (draft) %s.

REGRAS CRÍTICAS DE CONCISÃO (30 SEGUNDOS):
- O jogador tem apenas 30 segundos. Seja direto, tático e conciso.
- PROIBIDO TERMINANTEMENTE escrever introduções como 'Vamos analisar...', saudações ou listar nomes de aliados e jogadores.
- PROIBIDO USAR ASTERISCOS (**) OU ESTILOS MARKDOWN. Apenas texto limpo e tópicos com ponto (•).
- SUA RESPOSTA DEVE COMEÇAR DIRETA E IMEDIATAMENTE COM 'Situação:'.

ESTRUTURA EXATA (OBRIGATÓRIA):
Situação: [Diagnóstico breve da partida: o que o rival ameaça e do que sua equipe precisa]
Por que esta escolha: [Explicação clara e tática do porquê recomendamos este campeão para vencer esta partida]

PLANO A: [Nome do Campeão]
• Feitiços: [Feitiços recomendados, ex: Flash + Incendiar / Teleporte]
• Runas: [Runa essencial + runas secundárias]
• Plano de ação: [Quem focar/anular no time rival e melhor sinergia com sua equipe]

Recomendações semelhantes:
• [Campeão 2]: [Por que compartilha kit similar ou cumpre função similar em 1 linha]
• [Campeão 3]: [Por que compartilha kit similar ou cumpre função similar em 1 linha]%s%s`, roleClausePt, excludeClausePt, otpClausePt)
		}
		return fmt.Sprintf(`Você é um Analista Mestre e Challenger de League of Legends: Wild Rift.
Analise a tela de seleção de campeões (draft) considerando as rotas preferidas: %s, %s, %s.

REGRAS CRÍTICAS DE CONCISÃO (30 SEGUNDOS):
- O jogador tem apenas 30 segundos. Seja direto, tático e conciso.
- PROIBIDO TERMINANTEMENTE escrever introduções como 'Vamos analisar...', saudações ou listar nomes de aliados e jogadores.
- PROIBIDO USAR ASTERISCOS (**) OU ESTILOS MARKDOWN. Apenas texto limpo e tópicos com ponto (•).
- SUA RESPOSTA DEVE COMEÇAR DIRETA E IMEDIATAMENTE COM 'Situação:'.

ESTRUTURA EXATA (OBRIGATÓRIA):
Situação: [Diagnóstico breve da partida: o que o rival ameaça e do que sua equipe precisa]
Por que esta escolha: [Explicação clara e tática do porquê recomendamos este campeão para vencer esta partida]

PLANO A: [Nome do Campeão]
• Feitiços: [Feitiços recomendados]
• Runas: [Runa essencial + runas secundárias]
• Plano de ação: [Quem focar/anular no time rival e melhor sinergia com sua equipe]

Recomendações semelhantes:
• [Campeão 2]: [Por que compartilha kit similar ou cumpre função similar em 1 linha]
• [Campeão 3]: [Por que compartilha kit similar ou cumpre função similar em 1 linha]%s%s`, mainRole, secondaryRole, autofillRole, excludeClausePt, otpClausePt)

	case "en":
		if isPC {
			return fmt.Sprintf(`You are a Master and Challenger Analyst for League of Legends (PC).
Analyze the screenshot during champion select (draft) %s.

CRITICAL CONCISENESS RULES (30 SECONDS):
- The player only has 30 seconds. Be sharp, direct, and actionable.
- STRICTLY FORBIDDEN from writing intros like 'Let us analyze...', greetings, or listing teammates and players.
- DO NOT USE ASTERISKS (**) OR MARKDOWN STYLES. Plain text and bullet points (•) only.
- YOUR RESPONSE MUST START DIRECTLY AND IMMEDIATELY WITH 'Situation:'.

EXACT STRUCTURE (MANDATORY):
Situation: [Brief match analysis: what the enemy threatens and what your team needs]
Why this pick: [Clear tactical explanation of why we recommend this champion to win]

PLAN A: [Champion Name]
• Spells: [Recommended summoner spells, e.g. Flash + Ignite / Teleport]
• Runes: [Keystone + key secondary runes]
• Action plan: [Which enemy to counter/target and key synergy with your team]

Similar recommendations:
• [Champion 2]: [Why it fits well or serves a similar purpose in 1 line]
• [Champion 3]: [Why it fits well or serves a similar purpose in 1 line]%s%s`, roleClauseEn, excludeClauseEn, otpClauseEn)
		}
		return fmt.Sprintf(`You are a Master and Challenger Analyst for League of Legends: Wild Rift.
Analyze the champion select (draft) screen considering the preferred roles: %s, %s, %s.

CRITICAL CONCISENESS RULES (30 SECONDS):
- The player only has 30 seconds. Be sharp, direct, and actionable.
- STRICTLY FORBIDDEN from writing intros like 'Let us analyze...', greetings, or listing teammates and players.
- DO NOT USE ASTERISKS (**) OR MARKDOWN STYLES. Plain text and bullet points (•) only.
- YOUR RESPONSE MUST START DIRECTLY AND IMMEDIATELY WITH 'Situation:'.

EXACT STRUCTURE (MANDATORY):
Situation: [Brief match analysis: what the enemy threatens and what your team needs]
Why this pick: [Clear tactical explanation of why we recommend this champion to win]

PLAN A: [Champion Name]
• Spells: [Recommended summoner spells]
• Runes: [Keystone + key secondary runes]
• Action plan: [Which enemy to counter/target and key synergy with your team]

Similar recommendations:
• [Champion 2]: [Why it fits well or serves a similar purpose in 1 line]
• [Champion 3]: [Why it fits well or serves a similar purpose in 1 line]%s%s`, mainRole, secondaryRole, autofillRole, excludeClauseEn, otpClauseEn)

	case "fr":
		if isPC {
			return fmt.Sprintf(`Tu es un Analyste Maître et Challenger de League of Legends (PC).
Analyse la capture d'écran pendant la sélection des champions (draft) %s.

RÈGLES CRITIQUES DE CONCISION (30 SECONDES) :
- Le joueur n'a que 30 secondes. Sois direct, tactique et concis.
- INTERDICTION STRICTE d'écrire des introductions comme 'Analysons...', des salutations ou de lister les alliés et joueurs.
- INTERDICTION D'UTILISER DES ASTÉRISQUES (**) OU DU MARKDOWN. Texte brut et puces (•) uniquement.
- TA RÉPONSE DOIT COMMENCER DIRECTEMENT ET IMMÉDIATEMENT PAR 'Situation :'.

STRUCTURE EXACTE (OBLIGATOIRE) :
Situation : [Bref diagnostic de la partie : menaces adverses et besoins de ton équipe]
Pourquoi ce choix : [Explication claire et tactique de la raison pour laquelle nous recommandons ce champion]

PLAN A : [Nom du Champion]
• Sorts : [Sorts d'invocateur recommandés, ex: Saut éclair + Embrasement / Téléportation]
• Runes : [Rune fondamentale + runes secondaires]
• Plan d'action : [Quel ennemi contrer/cibler et meilleure synergie avec ton équipe]

Recommandations similaires :
• [Champion 2] : [Pourquoi il convient bien ou remplit un rôle similaire en 1 ligne]
• [Champion 3] : [Pourquoi il convient bien ou remplit un rôle similaire en 1 ligne]%s%s`, roleClauseFr, excludeClauseFr, otpClauseFr)
		}
		return fmt.Sprintf(`Tu es un Analyste Maître et Challenger de League of Legends: Wild Rift.
Analyse l'écran de sélection des champions (draft) en tenant compte des rôles préférés : %s, %s, %s.

RÈGLES CRITIQUES DE CONCISION (30 SECONDES) :
- Le joueur n'a que 30 secondes. Sois direct, tactique et concis.
- INTERDICTION STRICTE d'écrire des introductions comme 'Analysons...', des salutations ou de lister les alliés et joueurs.
- INTERDICTION D'UTILISER DES ASTÉRISQUES (**) OU DU MARKDOWN. Texte brut et puces (•) únicamente.
- TA RÉPONSE DOIT COMMENCER DIRECTEMENT ET IMMÉDIATEMENT PAR 'Situation :'.

STRUCTURE EXACTE (OBLIGATOIRE) :
Situation : [Bref diagnostic de la partie : menaces adverses et besoins de ton équipe]
Pourquoi ce choix : [Explication claire et tactique de la raison pour laquelle nous recommandons ce champion]

PLAN A : [Nom du Champion]
• Sorts : [Sorts d'invocateur recommandés]
• Runes : [Rune fondamentale + runes secondaires]
• Plan d'action : [Quel ennemi contrer/cibler et meilleure synergie avec ton équipe]

Recommandations similaires :
• [Champion 2] : [Pourquoi il convient bien ou remplit un rôle similaire en 1 ligne]
• [Champion 3] : [Pourquoi il convient bien ou remplit un rôle similaire en 1 ligne]%s%s`, mainRole, secondaryRole, autofillRole, excludeClauseFr, otpClauseFr)

	default:
		if isPC {
			return fmt.Sprintf(`Eres un Analista Maestro y Challenger de League of Legends (PC).
Analiza la captura de pantalla durante la selección de campeones (draft) %s.

REGLAS CRÍTICAS DE CONCISIÓN (30 SEGUNDOS):
- El jugador solo tiene 30 segundos. Sé directo, táctico y accionable.
- PROHIBIDO TERMINANTEMENTE escribir introducciones como 'Analicemos...', saludar o listar a los aliados o jugadores.
- PROHIBIDO USAR ASTERISCOS (**) O NEGRITAS MARKDOWN. Solo texto limpio y viñetas con punto (•).
- TU RESPUESTA DEBE COMENZAR DIRECTA E INMEDIATAMENTE CON LA PALABRA 'Situación:'.

ESTRUCTURA EXACTA (OBLIGATORIA):
Situación: [Análisis breve de la partida: qué plantea o amenaza el rival y qué carencia o ventaja tiene tu equipo]
Por qué este pick: [Explicación clara y táctica de por qué recomendamos a este campeón para ganar esta partida]

PLAN A: [Nombre del Campeón]
• Hechizos: [Hechizos de invocador recomendados, ej: Destello + Prender / Teleportación]
• Runas: [Rama principal + Runa clave + 2 runas secundarias prioritarias]
• Plan de acción: [A qué campeón rival priorizar o contrarrestar y tu mejor sinergia con el equipo]

Recomendaciones similares:
• [Campeón 2]: [Por qué comparte kit similar o cumple la misma función en 1 línea]
• [Campeón 3]: [Por qué comparte kit similar o cumple la misma función en 1 línea]%s%s`, roleClauseEs, excludeClauseEs, otpClauseEs)
		}
		return fmt.Sprintf(`Eres un Analista Maestro y Challenger de League of Legends: Wild Rift.
Analiza la pantalla de selección de campeones (draft) considerando los roles preferidos: %s, %s, %s.

REGLAS CRÍTICAS DE CONCISIÓN (30 SEGUNDOS):
- El jugador solo tiene 30 segundos. Sé directo, táctico y accionable.
- PROHIBIDO TERMINANTEMENTE escribir introducciones como 'Analicemos...', saludar o listar a los aliados o jugadores.
- PROHIBIDO USAR ASTERISCOS (**) O NEGRITAS MARKDOWN. Solo texto limpio y viñetas con punto (•).
- TU RESPUESTA DEBE COMENZAR DIRECTA E INMEDIATAMENTE CON LA PALABRA 'Situación:'.

ESTRUCTURA EXACTA (OBLIGATORIA):
Situación: [Análisis breve de la partida: qué plantea o amenaza el rival y qué carencia o ventaja tiene tu equipo]
Por qué este pick: [Explicación clara y táctica de por qué recomendamos a este campeón para ganar esta partida]

PLAN A: [Nombre del Campeón]
• Hechizos: [Hechizos recomendados]
• Runas: [Runa clave + runas secundarias prioritarias]
• Plan de acción: [A qué campeón rival priorizar o contrarrestar y tu mejor sinergia con el equipo]

Recomendaciones similares:
• [Campeón 2]: [Por qué comparte kit similar o cumple la misma función en 1 línea]
• [Campeón 3]: [Por qué comparte kit similar o cumple la misma función en 1 línea]%s%s`, mainRole, secondaryRole, autofillRole, excludeClauseEs, otpClauseEs)
	}
}

func AnalyzeDraft(ctx context.Context, base64Image string, mainRole, secondaryRole, autofillRole string, gameMode string, otpChampions string, lang string, excludeChampions ...string) (string, int32, error) {
	if aiClient == nil {
		return "", 0, fmt.Errorf("el cliente de IA no ha sido inicializado")
	}

	// Decode base64 image
	imgData, err := base64.StdEncoding.DecodeString(base64Image)
	if err != nil {
		log.Printf("Error decoding base64 image: %v", err)
		return "", 0, fmt.Errorf("invalid image format")
	}

	selectedLang := "es"
	if strings.TrimSpace(lang) != "" {
		selectedLang = NormalizeLanguage(lang)
	}

	prompt := buildDraftPrompt(mainRole, secondaryRole, autofillRole, gameMode, otpChampions, selectedLang, excludeChampions...)

	contents := []*genai.Content{
		{
			Role: "user",
			Parts: []*genai.Part{
				{Text: prompt},
				{InlineData: &genai.Blob{Data: imgData, MIMEType: "image/jpeg"}},
			},
		},
	}

	maxTokens := int32(3000)
	thinkingBudget := int32(1024) // Razonamiento visual profundo: inspecciona con rigor nombres de texto, casillas de campeones y composición sin alucinaciones

	models := []string{"gemini-2.5-flash"}
	var lastErr error
	var resp *genai.GenerateContentResponse
	var usedModel string

	for _, model := range models {
		config := &genai.GenerateContentConfig{
			MaxOutputTokens: maxTokens,
		}
		// Gemini 2.5 soporta thinking_config; desactivamos el pensamiento para draft en tiempo real
		if strings.Contains(model, "2.5") {
			config.ThinkingConfig = &genai.ThinkingConfig{
				ThinkingBudget: &thinkingBudget,
			}
		}

		resp, lastErr = aiClient.Models.GenerateContent(ctx, model, contents, config)
		if lastErr == nil && resp != nil {
			usedModel = model
			log.Printf("✅ Recomendación generada exitosamente con modelo: %s (lang=%s)", usedModel, selectedLang)
			break
		}
		log.Printf("⚠️ Modelo '%s' falló: %v. Intentando siguiente modelo...", model, lastErr)
	}

	if lastErr != nil || resp == nil {
		return "", 0, fmt.Errorf("falló generación con modelos IA: %w", lastErr)
	}

	if resp.Text() != "" {
		var tokens int32 = 0
		if resp.UsageMetadata != nil {
			tokens = resp.UsageMetadata.TotalTokenCount
			log.Printf("📊 [%s] Tokens - Prompt: %d, Salida: %d, Total: %d",
				usedModel,
				resp.UsageMetadata.PromptTokenCount,
				resp.UsageMetadata.CandidatesTokenCount,
				resp.UsageMetadata.TotalTokenCount,
			)
		}

		outText := resp.Text()

		// Recortar cualquier divagación o introducción antes de "Situación:" o "PLAN A:"
		if idx := strings.Index(outText, "Situación:"); idx > 0 {
			outText = outText[idx:]
		} else if idx := strings.Index(outText, "Situacion:"); idx > 0 {
			outText = outText[idx:]
		} else if idx := strings.Index(outText, "Situação:"); idx > 0 {
			outText = outText[idx:]
		} else if idx := strings.Index(outText, "Situation:"); idx > 0 {
			outText = outText[idx:]
		} else if idx := strings.Index(outText, "PLAN A:"); idx > 0 {
			outText = outText[idx:]
		} else if idx := strings.Index(outText, "PLANO A:"); idx > 0 {
			outText = outText[idx:]
		}

		// Eliminar todo rastro de asteriscos y títulos markdown
		outText = strings.ReplaceAll(outText, "**", "")
		outText = strings.ReplaceAll(outText, "###", "")
		outText = strings.ReplaceAll(outText, "##", "")
		outText = strings.TrimSpace(outText)

		return outText, tokens, nil
	}

	return "No clear recommendation could be generated.", 0, nil
}

func buildManualDraftPrompt(mainRole, myChampion, enemyChampion, gameMode, lang string, excludeChampions ...string) string {
	isPC := strings.EqualFold(strings.TrimSpace(gameMode), "lol_pc") || strings.EqualFold(strings.TrimSpace(gameMode), "pc")
	gameTitle := "League of Legends: Wild Rift"
	if isPC {
		gameTitle = "League of Legends (PC)"
	}

	excludeList := ""
	if len(excludeChampions) > 0 && strings.TrimSpace(excludeChampions[0]) != "" {
		excludeList = strings.TrimSpace(excludeChampions[0])
	}

	normalizedLang := NormalizeLanguage(lang)
	hasMyChamp := strings.TrimSpace(myChampion) != ""

	switch normalizedLang {
	case "pt":
		if hasMyChamp {
			return fmt.Sprintf(`Você é um Treinador e Analista Mestre/Challenger de %s.
O jogador está na rota '%s' e jogará com '%s' enfrentando '%s' na rota.

Forneça um guia tático direto, rápido e acionável para os próximos 30 segundos:
- PROIBIDO USAR ASTERISCOS (**) OU ESTILOS MARKDOWN. Apenas texto limpo e tópicos com ponto (•).

ESTRUTURA EXATA:
Situação: [Diagnóstico em 1 frase curta do confronto %s vs %s]

PLANO DE JOGO:
• Feitiços: [Feitiços de invocador ideais contra este rival]
• Runas: [Runa essencial + runas secundárias defensivas/ofensivas necessárias]
• Itens e Build: [Primeiros 3 itens prioritários, corta-cura ou penetração se necessário]
• Tática de Linha: [Como punir o rival, níveis de pico de poder e cuidados principais]`, gameTitle, mainRole, myChampion, enemyChampion, myChampion, enemyChampion)
		}
		excludeClause := ""
		if excludeList != "" {
			excludeClause = fmt.Sprintf("\nPROIBIDO sugerir qualquer um destes campeões já visualizados: %s.", excludeList)
		}
		return fmt.Sprintf(`Você é um Treinador e Analista Mestre/Challenger de %s.
O jogador joga na rota '%s' e o adversário direto escolheu '%s'.
Recomende o melhor campeão para contra-atacar (Counter) e vencer a rota.%s
- PROIBIDO USAR ASTERISCOS (**) OU ESTILOS MARKDOWN. Apenas texto limpo e tópicos com ponto (•).

ESTRUTURA EXATA:
Situação: [Diagnóstico em 1 frase curta das fraquezas de %s]

PLANO A: [Nome do Melhor Counter na rota %s]
• Por que vence: [Vantagem direta do kit de habilidades sobre %s]
• Feitiços: [Feitiços de invocador recomendados]
• Runas: [Runa essencial e secundárias prioritárias]
• Itens essenciais: [Primeiros 2 itens recomendados contra %s]
• Tática de Linha: [Como jogar o confronto nos primeiros 5 minutos]

Recomendações semelhantes:
• [Campeão 2]: [Por que é uma boa alternativa contra %s]
• [Campeão 3]: [Por que é uma boa alternativa contra %s]`, gameTitle, mainRole, enemyChampion, excludeClause, enemyChampion, mainRole, enemyChampion, enemyChampion, enemyChampion, enemyChampion)

	case "en":
		if hasMyChamp {
			return fmt.Sprintf(`You are a Master and Challenger Coach/Analyst for %s.
The player is in lane '%s' playing as '%s' facing '%s'.

Provide a direct, concise, and tactical guide for champion select (under 30s):
- DO NOT USE ASTERISKS (**) OR MARKDOWN STYLES. Plain text and bullet points (•) only.

EXACT STRUCTURE:
Situation: [1 short sentence diagnosing %s vs %s matchup]

TACTICAL PLAN:
• Spells: [Optimal summoner spells against this rival]
• Runes: [Keystone + crucial secondary defensive/offensive runes]
• Core Build: [First 3 core items, anti-heal or armor pen if necessary]
• Lane Strategy: [How to trade, power spikes, and what to watch out for]`, gameTitle, mainRole, myChampion, enemyChampion, myChampion, enemyChampion)
		}
		excludeClause := ""
		if excludeList != "" {
			excludeClause = fmt.Sprintf("\nSTRICTLY FORBIDDEN to suggest these champions already shown: %s.", excludeList)
		}
		return fmt.Sprintf(`You are a Master and Challenger Coach/Analyst for %s.
The player plays in '%s' lane and the direct lane opponent picked '%s'.
Recommend the optimal counter-pick champion to win lane.%s
- DO NOT USE ASTERISKS (**) OR MARKDOWN STYLES. Plain text and bullet points (•) only.

EXACT STRUCTURE:
Situation: [1 short sentence diagnosing %s's main weaknesses]

PLAN A: [Best Counter Champion for %s lane]
• Why it counters: [Direct kit advantage over %s]
• Spells: [Recommended summoner spells]
• Runes: [Optimal keystone and secondary runes]
• Core Build: [First 2 items to counter %s]
• Lane Strategy: [How to dominate the matchup early game]

Similar recommendations:
• [Champion 2]: [Why it is a strong alternative against %s]
• [Champion 3]: [Why it is a strong alternative against %s]`, gameTitle, mainRole, enemyChampion, excludeClause, enemyChampion, mainRole, enemyChampion, enemyChampion, enemyChampion, enemyChampion)

	case "fr":
		if hasMyChamp {
			return fmt.Sprintf(`Tu es un Coach et Analyste Maître/Challenger de %s.
Le joueur est sur la voie '%s' avec '%s' contre '%s'.

Donne un guide tactique direct et clair pour les 30 prochaines secondes :
- INTERDICTION D'UTILISER DES ASTÉRISQUES (**) OU DU MARKDOWN. Texte brut et puces (•) uniquement.

STRUCTURE EXACTE :
Situation : [Diagnostic en 1 phrase courte du match %s vs %s]

PLAN TACTIQUE :
• Sorts : [Sorts d'invocateur idéaux contre ce rival]
• Runes : [Rune fondamentale + runes secondaires clés]
• Objets essentiels : [3 premiers objets prioritaires, anti-soin ou pénétration si nécessaire]
• Tactique de voie : [Comment punir le rival et gérer les pics de puissance]`, gameTitle, mainRole, myChampion, enemyChampion, myChampion, enemyChampion)
		}
		excludeClause := ""
		if excludeList != "" {
			excludeClause = fmt.Sprintf("\nINTERDICTION de suggérer ces champions déjà vus : %s.", excludeList)
		}
		return fmt.Sprintf(`Tu es un Coach et Analyste Maître/Challenger de %s.
Le joueur joue sur la voie '%s' et l'adversaire direct a choisi '%s'.
Recommande le meilleur champion pour contrer (Counter) et remporter la voie.%s
- INTERDICTION D'UTILISER DES ASTÉRISQUES (**) OU DU MARKDOWN. Texte brut et puces (•) uniquement.

STRUCTURE EXACTE :
Situation : [Diagnostic en 1 phrase courte des faiblesses de %s]

PLAN A : [Meilleur Champion Counter sur la voie %s]
• Pourquoi il gagne : [Avantage direct du kit contre %s]
• Sorts : [Sorts d'invocateur recommandés]
• Runes : [Rune fondamentale et secondaires prioritaires]
• Objets essentiels : [2 premiers objets recommandés contre %s]
• Tactique de voie : [Comment dominer le face-à-face]

Recommandations similaires :
• [Champion 2] : [Pourquoi c'est une bonne alternative contre %s]
• [Champion 3] : [Pourquoi c'est une bonne alternative contre %s]`, gameTitle, mainRole, enemyChampion, excludeClause, enemyChampion, mainRole, enemyChampion, enemyChampion, enemyChampion, enemyChampion)

	default: // "es"
		if hasMyChamp {
			return fmt.Sprintf(`Eres un Entrenador y Analista Maestro/Challenger de %s.
El jugador va en la línea '%s' jugando con '%s' contra '%s'.

Genera una guía táctica directa, clara y accionable para los 30 segundos del draft:
- FORMATO OBLIGATORIO: PROHIBIDO USAR ASTERISCOS (**) O ESTILOS MARKDOWN. Solo texto limpio y viñetas con punto (•).

ESTRUCTURA EXACTA:
Situación: [Diagnóstico en 1 frase corta del matchup %s vs %s]

PLAN TÁCTICO:
• Hechizos: [Hechizos de invocador óptimos contra este rival]
• Runas: [Runa clave indispensable + secundarias defensivas u ofensivas clave]
• Build de Objetos: [Primeros 3 objetos prioritarios, corta-curas o penetración si aplica]
• Táctica de Línea: [Cómo tradear, niveles de ventaja y principales precauciones]`, gameTitle, mainRole, myChampion, enemyChampion, myChampion, enemyChampion)
		}
		excludeClause := ""
		if excludeList != "" {
			excludeClause = fmt.Sprintf("\nPROHIBIDO sugerir cualquiera de estos campeones ya visualizados: %s.", excludeList)
		}
		return fmt.Sprintf(`Eres un Entrenador y Analista Maestro/Challenger de %s.
El jugador va en la línea '%s' y el rival directo ya seleccionó a '%s'.
Recomienda el mejor contra-pick (Counter) para ganar la línea.%s
- FORMATO OBLIGATORIO: PROHIBIDO USAR ASTERISCOS (**) O ESTILOS MARKDOWN. Solo texto limpio y viñetas con punto (•).

ESTRUCTURA EXACTA:
Situación: [Diagnóstico en 1 frase corta de las debilidades de %s]

PLAN A: [Mejor Campeón Counter en %s]
• Por qué le gana: [Ventaja directa de habilidades sobre %s explicada con sencillez]
• Hechizos: [Hechizos de invocador recomendados]
• Runas: [Runa clave + secundarias prioritarias]
• Build clave: [Primeros 2 objetos recomendados contra %s]
• Táctica de Línea: [Cómo castigarlo en los primeros niveles]

Recomendaciones similares:
• [Campeón 2]: [Por qué funciona bien contra %s]
• [Campeón 3]: [Por qué funciona bien contra %s]`, gameTitle, mainRole, enemyChampion, excludeClause, enemyChampion, mainRole, enemyChampion, enemyChampion, enemyChampion, enemyChampion)
	}
}

func AnalyzeManualDraft(ctx context.Context, mainRole, myChampion, enemyChampion, gameMode, lang string, excludeChampions ...string) (string, int32, error) {
	if aiClient == nil {
		return "", 0, fmt.Errorf("el cliente de IA no ha sido inicializado")
	}

	selectedLang := "es"
	if strings.TrimSpace(lang) != "" {
		selectedLang = NormalizeLanguage(lang)
	}

	prompt := buildManualDraftPrompt(mainRole, myChampion, enemyChampion, gameMode, selectedLang, excludeChampions...)

	contents := []*genai.Content{
		{
			Role: "user",
			Parts: []*genai.Part{
				{Text: prompt},
			},
		},
	}

	maxTokens := int32(1800)
	thinkingBudget := int32(0) // Ultra rápido (1 segundo) y sin costo de razonamiento extendido

	models := []string{"gemini-2.5-flash"}
	var lastErr error
	var resp *genai.GenerateContentResponse
	var usedModel string

	for _, model := range models {
		config := &genai.GenerateContentConfig{
			MaxOutputTokens: maxTokens,
		}
		if strings.Contains(model, "2.5") {
			config.ThinkingConfig = &genai.ThinkingConfig{
				ThinkingBudget: &thinkingBudget,
			}
		}

		resp, lastErr = aiClient.Models.GenerateContent(ctx, model, contents, config)
		if lastErr == nil && resp != nil {
			usedModel = model
			log.Printf("✅ Análisis manual generado exitosamente con modelo: %s (lang=%s)", usedModel, selectedLang)
			break
		}
		log.Printf("⚠️ Modelo '%s' falló en manual draft: %v. Intentando siguiente modelo...", model, lastErr)
	}

	if lastErr != nil || resp == nil {
		return "", 0, fmt.Errorf("falló generación manual con modelos IA: %w", lastErr)
	}

	if resp.Text() != "" {
		var tokens int32 = 0
		if resp.UsageMetadata != nil {
			tokens = resp.UsageMetadata.TotalTokenCount
			log.Printf("📊 [Manual %s] Tokens - Prompt: %d, Salida: %d, Total: %d",
				usedModel,
				resp.UsageMetadata.PromptTokenCount,
				resp.UsageMetadata.CandidatesTokenCount,
				resp.UsageMetadata.TotalTokenCount,
			)
		}
		outText := resp.Text()
		outText = strings.ReplaceAll(outText, "**", "")
		outText = strings.ReplaceAll(outText, "###", "")
		outText = strings.ReplaceAll(outText, "##", "")
		outText = strings.TrimSpace(outText)
		return outText, tokens, nil
	}

	return "No se pudo generar recomendación manual.", 0, nil
}
