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
	initWRKnowledge()
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

	wrCatalog := ""
	if !isPC {
		wrCatalog = GetWildRiftChampionsContext()
	}

	var excludeClauseEs, excludeClausePt, excludeClauseEn, excludeClauseFr string
	if excludeList != "" {
		excludeClauseEs = fmt.Sprintf("\n\nAVISO DE RECONSULTA: El jugador ya vio las siguientes opciones y solicita nuevas alternativas: %s. ESTÁ ESTRICTAMENTE PROHIBIDO repetir cualquiera de esos campeones. Brinda un nuevo PLAN A óptimo diferente y dos recomendaciones similares distintas.", excludeList)
		excludeClausePt = fmt.Sprintf("\n\nAVISO DE ATUALIZAÇÃO: O jogador já viu as seguintes opções e solicita novas alternativas: %s. É ESTRITAMENTE PROIBIDO repetir qualquer um desses campeões. Forneça um novo PLANO A ótimo diferente e duas recomendações semelhantes distintas.", excludeList)
		excludeClauseEn = fmt.Sprintf("\n\nREFRESH NOTICE: The player has already seen these options and requests new alternatives: %s. You are STRICTLY FORBIDDEN from repeating any of these champions. Provide a new, different optimal PLAN A and two different similar recommendations.", excludeList)
		excludeClauseFr = fmt.Sprintf("\n\nAVIS D'ACTUALISATION : Le joueur a déjà vu ces options et demande de nouvelles alternatives : %s. Il est STRICTEMENT INTERDIT de répéter l'un de ces champions. Fournis un nouveau PLAN A optimal différent et deux recommandations similaires distinctes.", excludeList)
	}

	var otpClauseEs, otpClausePt, otpClauseEn, otpClauseFr string
	if cleanOtp := strings.TrimSpace(otpChampions); cleanOtp != "" {
		otpClauseEs = fmt.Sprintf(`

REGLA ESPECIAL DE JUGADOR OTP (%s) Y DETECCIÓN AUTOMÁTICA DE ROL:
- El jugador es especialista / OTP con: %s.
- VIABILIDAD POR ROL Y REGLA DE AUTOFILL:
  1. Si la línea asignada en pantalla es una posición estándar y VIABLE para su OTP (%s) y no está baneado ni elegido, dale máxima prioridad como PLAN A o explica cómo jugarlo en este emparejamiento.
  2. Si la línea asignada NO es viable para su OTP (por ejemplo: Autofill a Soporte, ADC, Jungla o Top donde dicho campeón no cumple el rol), ESTÁ ESTRICTAMENTE PROHIBIDO FORZAR SU OTP. En 'Situación' advierte brevemente: '(Tu OTP %s no es viable en el rol asignado)' y recomienda el mejor campeón counter/meta estándar.`, cleanOtp, cleanOtp, cleanOtp, cleanOtp)

		otpClausePt = fmt.Sprintf(`

REGRA ESPECIAL DE JOGADOR OTP (%s) E DETECÇÃO AUTOMÁTICA DE ROTA:
- O jogador é especialista / OTP com: %s.
- VIABILIDADE POR ROTA:
  1. Se a rota atribuída na tela for VIÁVEL para seu OTP (%s) e ele estiver disponível, dê prioridade máxima como PLANO A.
  2. Se a rota atribuída NÃO for viável para seu OTP, É PROIBIDO FORÇAR SEU OTP. Na linha de 'Situação' alerte brevemente: '(Seu OTP %s não é viável na rota atribuída)' e recomende o melhor campeão ótimo padrão.`, cleanOtp, cleanOtp, cleanOtp, cleanOtp)

		otpClauseEn = fmt.Sprintf(`

SPECIAL OTP PLAYER RULE (%s) & AUTOMATIC ROLE DETECTION:
- The player is a dedicated OTP / specialist on: %s.
- ROLE VIABILITY:
  1. If the assigned lane on screen is a standard and VIABLE role for their OTP champion (%s) and it is available, give it top priority as PLAN A.
  2. If the assigned lane is NOT viable for their OTP champion, DO NOT FORCE THE OTP. In 'Situation', briefly add: '(Your OTP %s is not viable in the assigned role)' and recommend the best optimal standard counter champion.`, cleanOtp, cleanOtp, cleanOtp, cleanOtp)

		otpClauseFr = fmt.Sprintf(`

RÈGLE SPÉCIALE JOUEUR OTP (%s) ET DÉTECTION AUTOMATIQUE DU RÔLE :
- Le joueur est spécialiste / OTP sur : %s.
- VIABILITÉ DU RÔLE :
  1. Si le rôle assigné à l'écran est VIABLE pour son champion OTP (%s) et qu'il est disponible, donne-lui priorité absolue en PLAN A.
  2. Si le rôle assigné N'EST PAS viable pour son champion OTP, IL EST INTERDIT DE FORCER L'OTP. Dans 'Situation', indique brièvement : '(Ton OTP %s n'est pas viable sur ce rôle)' et recommande le meilleur champion adapté.`, cleanOtp, cleanOtp, cleanOtp, cleanOtp)
	}

	gameTitle := "League of Legends: Wild Rift"
	if isPC {
		gameTitle = "League of Legends (PC)"
	}

	switch NormalizeLanguage(lang) {
	case "pt":
		return fmt.Sprintf(`Você é um Analista Mestre e Challenger de %s.
Analise a captura de tela durante a seleção de campeões (draft) detectando AUTOMATICAMENTE:
1) A rota atribuída ao jogador (Baron/Top, Jungle, Mid, Dragon/ADC ou Support)
2) Os campeões banidos (bloqueados)
3) Os campeões já selecionados pelos aliados e inimigos.%s

REGRAS CRÍTICAS DE CONCISÃO E FORMATO (30 SEGUNDOS):
- O jogador tem apenas 30 segundos. Seja direto, tático e conciso.
- PROIBIDO TERMINANTEMENTE recomendar runas ou feitiços nesta resposta (apenas campeões e por que são as melhores opções).
- PROIBIDO escrever introduções, saudações ou usar asteriscos (**). Apenas texto limpo e tópicos com ponto (•).
- SUA RESPOSTA DEVE COMEÇAR DIRETA E IMEDIATAMENTE COM 'Situação:'.
- Na última linha, inclua obrigatoriamente a tag de contexto interno: CONTEXTO_DRAFT: {"role":"...","bans":["..."],"allies":["..."],"enemies":["..."],"suggested":["..."]}

ESTRUTURA EXATA (OBRIGATÓRIA):
Situação: [Rota detectada + diagnóstico breve do que o rival ameaça e do que sua equipe precisa]
Por que esta escolha: [Explicação clara e tática de por que este campeão é a melhor opção para vencer esta partida]

PLANO A: [Nome do Campeão]
• Plano de ação: [Quem focar/anular no time rival e melhor sinergia com sua equipe]

Recomendações semelhantes:
• [Campeão 2]: [Por que é uma excelente alternativa tática nesta partida em 1 linha]
• [Campeão 3]: [Por que é uma excelente alternativa tática nesta partida em 1 linha]%s%s
CONTEXTO_DRAFT: {"role":"RotaDetectada","bans":[],"allies":[],"enemies":[],"suggested":[]}`, gameTitle, wrCatalog, excludeClausePt, otpClausePt)

	case "en":
		return fmt.Sprintf(`You are a Master and Challenger Analyst for %s.
Analyze the champion select (draft) screenshot by AUTOMATICALLY detecting:
1) The player's assigned role (Baron/Top, Jungle, Mid, Dragon/ADC, or Support)
2) Banned champions
3) Allied and enemy selected champions.%s

CRITICAL CONCISENESS & FORMAT RULES (30 SECONDS):
- The player only has 30 seconds. Be sharp, direct, and actionable.
- STRICTLY FORBIDDEN from giving rune or summoner spell advice here (only champions and why they are the best options).
- DO NOT write intros, greetings, or use asterisks (**). Plain text and bullet points (•) only.
- YOUR RESPONSE MUST START DIRECTLY AND IMMEDIATELY WITH 'Situation:'.
- On the very last line, always include the internal context tag: CONTEXTO_DRAFT: {"role":"...","bans":["..."],"allies":["..."],"enemies":["..."],"suggested":["..."]}

EXACT STRUCTURE (MANDATORY):
Situation: [Detected role + brief match analysis: what the enemy threatens and what your team needs]
Why this pick: [Clear tactical explanation of why this champion is the best option to win this match]

PLAN A: [Champion Name]
• Action plan: [Which enemy to counter/target and key synergy with your team]

Similar recommendations:
• [Champion 2]: [Why it is a strong tactical alternative in this match in 1 line]
• [Champion 3]: [Why it is a strong tactical alternative in this match in 1 line]%s%s
CONTEXTO_DRAFT: {"role":"DetectedRole","bans":[],"allies":[],"enemies":[],"suggested":[]}`, gameTitle, wrCatalog, excludeClauseEn, otpClauseEn)

	case "fr":
		return fmt.Sprintf(`Tu es un Analyste Maître et Challenger de %s.
Analyse la capture d'écran de sélection des champions (draft) en détectant AUTOMATIQUEMENT :
1) Le rôle assigné au joueur (Baron/Top, Jungle, Mid, Dragon/ADC ou Support)
2) Les champions bannis
3) Les champions sélectionnés par les alliés et les ennemis.%s

RÈGLES CRITIQUES DE CONCISION ET FORMAT (30 SECONDES) :
- Le joueur n'a que 30 secondes. Sois direct, tactique et concis.
- INTERDICTION STRICTE de donner des conseils sur les runes ou les sorts d'invocateur ici (uniquement les champions et pourquoi ce sont les meilleures options).
- INTERDICTION d'utiliser des astérisques (**) ou d'écrire des introductions. Texte brut et puces (•) uniquement.
- TA RÉPONSE DOIT COMMENCER DIRECTEMENT ET IMMÉDIATEMENT PAR 'Situation :'.
- Sur la toute dernière ligne, inclus obligatoirement : CONTEXTO_DRAFT: {"role":"...","bans":["..."],"allies":["..."],"enemies":["..."],"suggested":["..."]}

STRUCTURE EXACTE (OBLIGATOIRE) :
Situation : [Rôle détecté + bref diagnostic : menaces adverses et besoins de ton équipe]
Pourquoi ce choix : [Explication claire et tactique de pourquoi ce champion est la meilleure option pour gagner]

PLAN A : [Nom du Champion]
• Plan d'action : [Quel ennemi contrer/cibler et meilleure synergie avec ton équipe]

Recommandations similaires :
• [Champion 2] : [Pourquoi c'est une excellente alternative tactique en 1 ligne]
• [Champion 3] : [Pourquoi c'est une excellente alternative tactique en 1 ligne]%s%s
CONTEXTO_DRAFT: {"role":"RoleDetecte","bans":[],"allies":[],"enemies":[],"suggested":[]}`, gameTitle, wrCatalog, excludeClauseFr, otpClauseFr)

	default:
		return fmt.Sprintf(`Eres un Analista Maestro y Challenger de %s.
Analiza la captura de pantalla de selección de campeones (draft) detectando AUTOMÁTICAMENTE:
1) El rol asignado al jugador (Baron/Top, Jungla, Mid, Dragon/ADC o Soporte)
2) Los campeones bloqueados (baneados)
3) Los campeones ya seleccionados por aliados y enemigos.%s

REGLAS CRÍTICAS DE CONCISIÓN Y FORMATO (30 SEGUNDOS):
- El jugador solo tiene 30 segundos. Sé directo, táctico y accionable.
- PROHIBIDO TERMINANTEMENTE dar consejos sobre runas o hechizos de invocador en esta respuesta (solo los campeones y explicando por qué son las mejores opciones).
- PROHIBIDO escribir introducciones como 'Analicemos...', saludar o usar asteriscos (**). Solo texto limpio y viñetas con punto (•).
- TU RESPUESTA DEBE COMENZAR DIRECTA E INMEDIATAMENTE CON LA PALABRA 'Situación:'.
- En la última línea incluye obligatoriamente el resumen estructurado para reconsultas: CONTEXTO_DRAFT: {"role":"...","bans":["..."],"allies":["..."],"enemies":["..."],"suggested":["..."]}

ESTRUCTURA EXACTA (OBLIGATORIA):
Situación: [Rol detectado + análisis breve de qué amenaza el rival y qué necesita tu equipo]
Por qué este pick: [Explicación clara y táctica de por qué recomendamos a este campeón como la mejor opción para ganar]

PLAN A: [Nombre del Campeón]
• Plan de acción: [A qué campeón rival priorizar o contrarrestar y tu mejor sinergia con el equipo]

Recomendaciones similares:
• [Campeón 2]: [Por qué es una excelente opción alternativa para esta partida en 1 línea]
• [Campeón 3]: [Por qué es una excelente opción alternativa para esta partida en 1 línea]%s%s
CONTEXTO_DRAFT: {"role":"RolDetectado","bans":[],"allies":[],"enemies":[],"suggested":[]}`, gameTitle, wrCatalog, excludeClauseEs, otpClauseEs)
	}
}

func extractTextAndDraftContext(raw string) (string, string) {
	outText := raw
	draftCtx := ""

	if idx := strings.Index(outText, "CONTEXTO_DRAFT:"); idx != -1 {
		draftCtx = strings.TrimSpace(outText[idx+len("CONTEXTO_DRAFT:"):])
		if nl := strings.IndexAny(draftCtx, "\r\n"); nl != -1 {
			draftCtx = strings.TrimSpace(draftCtx[:nl])
		}
		outText = strings.TrimSpace(outText[:idx])
	}

	// Recortar cualquier divagación antes de "Situación:" o "PLAN A:"
	if idx := strings.Index(outText, "Situación:"); idx > 0 {
		outText = outText[idx:]
	} else if idx := strings.Index(outText, "Situacion:"); idx > 0 {
		outText = outText[idx:]
	} else if idx := strings.Index(outText, "Situação:"); idx > 0 {
		outText = outText[idx:]
	} else if idx := strings.Index(outText, "Situation:"); idx > 0 {
		outText = outText[idx:]
	} else if idx := strings.Index(outText, "Situation :"); idx > 0 {
		outText = outText[idx:]
	} else if idx := strings.Index(outText, "PLAN A:"); idx > 0 {
		outText = outText[idx:]
	} else if idx := strings.Index(outText, "PLANO A:"); idx > 0 {
		outText = outText[idx:]
	}

	outText = strings.ReplaceAll(outText, "**", "")
	outText = strings.ReplaceAll(outText, "###", "")
	outText = strings.ReplaceAll(outText, "##", "")
	outText = strings.TrimSpace(outText)

	return outText, draftCtx
}

// DraftAIResult encapsula la salida estructurada de los modelos Classic, Flake 1.0 y Aureon 1.0
type DraftAIResult struct {
	ScreenText   string
	VoiceScript  string
	DraftContext string
	Tokens       int32
}

func buildClassicPrompt(gameMode, otpChampions, lang, excludeList string) string {
	isPC := strings.EqualFold(strings.TrimSpace(gameMode), "lol_pc") || strings.EqualFold(strings.TrimSpace(gameMode), "pc")
	gameTitle := "League of Legends: Wild Rift"
	if isPC {
		gameTitle = "League of Legends (PC)"
	}

	excludeClause := ""
	if excludeList != "" {
		excludeClause = fmt.Sprintf("\nPROHIBIDO repetir estos campeones ya mostrados: %s.", excludeList)
	}
	otpClause := ""
	if cleanOtp := strings.TrimSpace(otpChampions); cleanOtp != "" {
		otpClause = fmt.Sprintf("\nOTP del jugador: %s (úsalo solo si es viable en el rol detectado).", cleanOtp)
	}

	switch NormalizeLanguage(lang) {
	case "pt":
		return fmt.Sprintf(`Você é um assistente rápido de %s (Modelo Classic).
Analise a captura de tela do draft, identifique a rota do jogador e dê uma resposta direta e rápida.
PROIBIDO usar asteriscos (**) ou saudações. Apenas texto limpo e tópicos (•).
Na última linha inclua: CONTEXTO_DRAFT: {"role":"...","bans":[],"allies":[],"enemies":[],"suggested":[]}

ESTRUTURA EXATA:
CAMPEÃO: [Melhor campeão para a rota]
• Runas: [Runa essencial + runas principais]
• Estratégia rápida: [Como jogar a rota em 2 linhas curtas]
Alternativas: [Campeão 2], [Campeão 3]%s%s`, gameTitle, excludeClause, otpClause)

	case "en":
		return fmt.Sprintf(`You are a fast draft assistant for %s (Classic Model).
Analyze the draft screenshot, detect the player's assigned lane, and give a quick, direct answer.
NO asterisks (**) or greetings. Plain text and bullet points (•) only.
On the last line include: CONTEXTO_DRAFT: {"role":"...","bans":[],"allies":[],"enemies":[],"suggested":[]}

EXACT STRUCTURE:
CHAMPION: [Best champion for the lane]
• Runes: [Keystone + core runes]
• Quick strategy: [How to play the lane in 2 short lines]
Alternatives: [Champion 2], [Champion 3]%s%s`, gameTitle, excludeClause, otpClause)

	case "fr":
		return fmt.Sprintf(`Tu es un assistant rapide de %s (Modèle Classic).
Analyse la capture du draft, détecte le rôle assigné et donne une réponse directe et rapide.
PAS d'astérisques (**) ni de salutations. Texte brut et puces (•) uniquement.
Sur la dernière ligne inclus : CONTEXTO_DRAFT: {"role":"...","bans":[],"allies":[],"enemies":[],"suggested":[]}

STRUCTURE EXACTE :
CHAMPION : [Meilleur champion pour la voie]
• Runes : [Rune fondamentale + runes principales]
• Stratégie rapide : [Comment jouer la voie en 2 lignes courtes]
Alternatives : [Champion 2], [Champion 3]%s%s`, gameTitle, excludeClause, otpClause)

	default:
		return fmt.Sprintf(`Eres un asistente rápido de %s (Modelo Classic).
Analiza la captura de pantalla del draft, detecta el rol asignado al jugador y da una respuesta directa y rápida.
PROHIBIDO usar asteriscos (**) ni saludos. Solo texto limpio y viñetas (•).
En la última línea incluye: CONTEXTO_DRAFT: {"role":"...","bans":[],"allies":[],"enemies":[],"suggested":[]}

ESTRUCTURA EXACTA:
CAMPEÓN: [Mejor campeón para la línea]
• Runas: [Runa clave + runas principales]
• Estrategia rápida: [Cómo jugar la línea y ganar en 2 líneas cortas]
Alternativas: [Campeón 2], [Campeón 3]%s%s`, gameTitle, excludeClause, otpClause)
	}
}

func buildFlakePrompt(gameMode, otpChampions, lang, excludeList string) string {
	isPC := strings.EqualFold(strings.TrimSpace(gameMode), "lol_pc") || strings.EqualFold(strings.TrimSpace(gameMode), "pc")
	gameTitle := "League of Legends: Wild Rift"
	wrKnowledge := ""
	if isPC {
		gameTitle = "League of Legends (PC)"
	} else {
		wrKnowledge = GetWildRiftChampionsContext() + "\n" + GetWildRiftChatContext("", "")
	}

	excludeClause := ""
	if excludeList != "" {
		excludeClause = fmt.Sprintf("\nESTRÍCTAMENTE PROHIBIDO repetir estos campeones ya mostrados: %s.", excludeList)
	}
	otpClause := ""
	if cleanOtp := strings.TrimSpace(otpChampions); cleanOtp != "" {
		otpClause = fmt.Sprintf("\nOTP del jugador: %s (priorízalo solo si es viable en el rol asignado; si no, avisa brevemente).", cleanOtp)
	}

	switch NormalizeLanguage(lang) {
	case "pt":
		return fmt.Sprintf(`Você é o Flake 1.0, Analista Tático Challenger de %s.
Analise com precisão a captura de tela do draft detectando: 1) Rota atribuída, 2) Campeões banidos pelo time inimigo, 3) Campeões escolhidos pelos inimigos, 4) Campeões escolhidos pelos aliados.
%s
REGRAS:
- PROIBIDO usar asteriscos (**) ou saudações. Apenas texto limpo e tópicos (•).
- Use exclusivamente campeões e runas reais do banco acima.
- Na última linha inclua: CONTEXTO_DRAFT: {"role":"...","bans":[],"allies":[],"enemies":[],"suggested":[]}

ESTRUTURA EXATA:
Razonamiento: [Explique por que estas escolhas vencem o draft analisando: o que o inimigo baniu (ex. baniu campeão de duelo), o que o inimigo escolheu e o que seus aliados já escolheram]

PLANO A: [Melhor Campeão]
• [Campeão 2]: [Por que encaixa nesta situação em 1 linha]
• [Campeão 3]: [Por que encaixa nesta situação em 1 linha]

Runas recomendadas (PLANO A):
• [1 Runa Essencial + 3 Runas da Árvore Principal + 1 Secundária]%s%s`, gameTitle, wrKnowledge, excludeClause, otpClause)

	case "en":
		return fmt.Sprintf(`You are Flake 1.0, a Challenger Tactical Analyst for %s.
Accurately analyze the draft screenshot detecting: 1) Assigned role, 2) Enemy banned champions, 3) Enemy picked champions, 4) Allied picked champions.
%s
RULES:
- NO asterisks (**) or greetings. Plain text and bullet points (•) only.
- Use ONLY real champions and runes from the database above.
- On the last line include: CONTEXTO_DRAFT: {"role":"...","bans":[],"allies":[],"enemies":[],"suggested":[]}

EXACT STRUCTURE:
Reasoning: [Explain why these picks win the draft based on enemy bans (what they fear), enemy picks, and allied picks]

PLAN A: [Best Champion]
• [Champion 2]: [Why it fits this draft in 1 line]
• [Champion 3]: [Why it fits this draft in 1 line]

Recommended Runes (PLAN A):
• [1 Keystone + 3 Primary Tree Runes + 1 Secondary Rune]%s%s`, gameTitle, wrKnowledge, excludeClause, otpClause)

	case "fr":
		return fmt.Sprintf(`Tu es Flake 1.0, Analyste Tactique Challenger de %s.
Analyse précisément la capture du draft : 1) Rôle assigné, 2) Champions bannis par l'ennemi, 3) Champions pris par l'ennemi, 4) Champions alliés.
%s
RÈGLES :
- PAS d'astérisques (**) ni de salutations. Texte brut et puces (•) uniquement.
- Utilise uniquement les vrais champions et runes de la base ci-dessus.
- Sur la dernière ligne inclus : CONTEXTO_DRAFT: {"role":"...","bans":[],"allies":[],"enemies":[],"suggested":[]}

STRUCTURE EXACTE :
Raisonnement : [Explique pourquoi ces choix gagnent le draft en tenant compte des bans ennemis, des picks ennemis et des picks alliés]

PLAN A : [Meilleur Champion]
• [Champion 2] : [Pourquoi il convient dans cette situation en 1 ligne]
• [Champion 3] : [Pourquoi il convient dans cette situation en 1 ligne]

Runes recommandées (PLAN A) :
• [1 Rune Fondamentale + 3 Runes Principales + 1 Secondaire]%s%s`, gameTitle, wrKnowledge, excludeClause, otpClause)

	default:
		return fmt.Sprintf(`Eres Flake 1.0, Analista Táctico Challenger de %s.
Analiza con máxima precisión la captura de pantalla del draft detectando: 1) Rol asignado, 2) Campeones bloqueados (baneados) por el equipo enemigo, 3) Campeones pickeados por el equipo enemigo, 4) Campeones pickeados por tu equipo aliado.
%s
REGLAS:
- PROHIBIDO usar asteriscos (**) ni saludos. Solo texto limpio y viñetas (•).
- Usa exclusivamente campeones y runas reales de la base de datos de arriba.
- En la última línea incluye: CONTEXTO_DRAFT: {"role":"...","bans":[],"allies":[],"enemies":[],"suggested":[]}

ESTRUCTURA EXACTA:
Razonamiento: [Explica con detalle táctico por qué das estas opciones tomando en cuenta lo que el enemigo bloqueó (ej. si baneó Darius, teme combates extendidos), lo que el enemigo pickeó y lo que tu equipo aliado ya pickeó]

PLAN A: [Mejor Campeón para tu línea]
• [Campeón 2]: [Por qué encaja en esta situación en 1 línea]
• [Campeón 3]: [Por qué encaja en esta situación en 1 línea]

Runas recomendadas (PLAN A):
• [1 Runa Clave + 3 Runas de Rama Principal + 1 Runa Secundaria]%s%s`, gameTitle, wrKnowledge, excludeClause, otpClause)
	}
}

func buildAureonPrompt(gameMode, otpChampions, lang, excludeList string) string {
	isPC := strings.EqualFold(strings.TrimSpace(gameMode), "lol_pc") || strings.EqualFold(strings.TrimSpace(gameMode), "pc")
	gameTitle := "League of Legends: Wild Rift"
	wrKnowledge := ""
	if isPC {
		gameTitle = "League of Legends (PC)"
	} else {
		wrKnowledge = GetWildRiftChampionsContext() + "\n" + GetWildRiftChatContext("", "")
	}

	excludeClause := ""
	if excludeList != "" {
		excludeClause = fmt.Sprintf("\nESTRICTAMENTE PROHIBIDO repetir estos campeones: %s.", excludeList)
	}
	otpClause := ""
	if cleanOtp := strings.TrimSpace(otpChampions); cleanOtp != "" {
		otpClause = fmt.Sprintf("\nOTP del jugador: %s (inclúyelo si es viable en el rol asignado).", cleanOtp)
	}

	switch NormalizeLanguage(lang) {
	case "pt":
		return fmt.Sprintf(`Você é Aureon 1.0, a IA ultra avançada de Draft para %s.
Analise a captura de tela com precisão absoluta (rota atribuída, bans inimigos, picks inimigos e picks aliados).
%s
REGRAS CRÍTICAS:
- Todos os 3 campeões sugeridos DEVEM compartilhar o MESMO propósito tático na partida (ex: engaje pesado, poke à distância, splitpush ou anti-assassino) para que a explicação de voz cubra todos de forma unificada.
- PROIBIDO usar asteriscos (**).
- Divida sua resposta EXATAMENTE nestes 3 blocos com as tags exatas SCREEN_START, SCREEN_END, VOICE_START, VOICE_END e CONTEXTO_DRAFT:

SCREEN_START
PLANO A: [Campeão 1]
Alternativas (mesmo propósito): [Campeão 2], [Campeão 3]
Runas: [1 Runa Essencial + 3 Principais + 1 Secundária]
SCREEN_END

VOICE_START
[Explicação falada natural, fluida e sem símbolos (máximo 130 palavras, ~700 caracteres) explicando por que esses campeões vencem este Draft considerando bans inimigos, picks rivais e aliados, e qual é o propósito comum que eles cumprem na partida sem explicar campeão por campeão.]
VOICE_END

CONTEXTO_DRAFT: {"role":"...","bans":[],"allies":[],"enemies":[],"suggested":[]}%s%s`, gameTitle, wrKnowledge, excludeClause, otpClause)

	case "en":
		return fmt.Sprintf(`You are Aureon 1.0, the ultra-advanced Draft AI for %s.
Analyze the screenshot with absolute precision (assigned role, enemy bans, enemy picks, and allied picks).
%s
CRITICAL RULES:
- All 3 recommended champions MUST share the SAME tactical purpose in the match so the voice explanation covers all of them cohesively instead of going champion by champion.
- NO asterisks (**).
- Split your output into these EXACT blocks using the exact tags SCREEN_START, SCREEN_END, VOICE_START, VOICE_END, and CONTEXTO_DRAFT:

SCREEN_START
PLAN A: [Champion 1]
Alternatives (same purpose): [Champion 2], [Champion 3]
Runes: [1 Keystone + 3 Primary + 1 Secondary]
SCREEN_END

VOICE_START
[Natural, fluent spoken explanation with no symbols (max 130 words, ~700 characters) explaining why these champions win this Draft considering enemy bans, enemy picks, and allied picks, and the shared tactical purpose they fulfill together.]
VOICE_END

CONTEXTO_DRAFT: {"role":"...","bans":[],"allies":[],"enemies":[],"suggested":[]}%s%s`, gameTitle, wrKnowledge, excludeClause, otpClause)

	case "fr":
		return fmt.Sprintf(`Tu es Aureon 1.0, l'IA de Draft ultra avancée pour %s.
Analyse la capture avec une précision absolue (rôle assigné, bans ennemis, picks ennemis et alliés).
%s
RÈGLES CRITIQUES :
- Les 3 champions recommandés DOIVENT partager le MÊME objectif tactique dans la partie afin que l'explication vocale les couvre ensemble sans détailler champion par champion.
- PAS d'astérisques (**).
- Divise ta réponse EXACTEMENT avec les balises SCREEN_START, SCREEN_END, VOICE_START, VOICE_END et CONTEXTO_DRAFT :

SCREEN_START
PLAN A : [Champion 1]
Alternatives (même objectif) : [Champion 2], [Champion 3]
Runes : [1 Rune Fondamentale + 3 Principales + 1 Secondaire]
SCREEN_END

VOICE_START
[Explication orale naturelle et fluide sans symboles (max 130 mots, ~700 caractères) expliquant pourquoi ces champions gagnent ce Draft selon les bans, les ennemis et les alliés, et leur rôle commun dans la partie.]
VOICE_END

CONTEXTO_DRAFT: {"role":"...","bans":[],"allies":[],"enemies":[],"suggested":[]}%s%s`, gameTitle, wrKnowledge, excludeClause, otpClause)

	default:
		return fmt.Sprintf(`Eres Aureon 1.0, la IA ultra avanzada de Draft para %s.
Analiza la captura de pantalla con precisión absoluta (rol asignado, bans enemigos, picks enemigos y picks aliados).
%s
REGLAS CRÍTICAS:
- Los 3 campeones recomendados DEBEN compartir el MISMO propósito táctico dentro de la partida (ej. combate extendido, iniciación en equipo, anti-asesinos o poke a distancia) para que la explicación de voz abarque a todos de forma unificada sin explicar campeón por campeón.
- PROHIBIDO usar asteriscos (**).
- Divide tu respuesta EXACTAMENTE con las etiquetas SCREEN_START, SCREEN_END, VOICE_START, VOICE_END y CONTEXTO_DRAFT:

SCREEN_START
PLAN A: [Campeón 1]
Alternativas (mismo propósito): [Campeón 2], [Campeón 3]
Runas: [1 Runa Clave + 3 Rama Principal + 1 Secundaria]
SCREEN_END

VOICE_START
[Explicación hablada natural, fluida y sin símbolos ni viñetas (máximo 130 palabras, ~700 caracteres) explicando por qué estos campeones dominan este Draft tomando en cuenta los bans enemigos, los picks rivales y aliados, y el propósito táctico común que cumplen en la partida sin ir campeón por campeón.]
VOICE_END

CONTEXTO_DRAFT: {"role":"...","bans":[],"allies":[],"enemies":[],"suggested":[]}%s%s`, gameTitle, wrKnowledge, excludeClause, otpClause)
	}
}

func parseAureonSections(raw string) (screenText, voiceScript, draftCtx string) {
	working := raw
	if idx := strings.Index(working, "CONTEXTO_DRAFT:"); idx != -1 {
		draftCtx = strings.TrimSpace(working[idx+len("CONTEXTO_DRAFT:"):])
		if nl := strings.IndexAny(draftCtx, "\r\n"); nl != -1 {
			draftCtx = strings.TrimSpace(draftCtx[:nl])
		}
		working = strings.TrimSpace(working[:idx])
	}

	extractTag := func(src, startTag, endTag string) string {
		sIdx := strings.Index(src, startTag)
		if sIdx == -1 {
			return ""
		}
		after := src[sIdx+len(startTag):]
		eIdx := strings.Index(after, endTag)
		if eIdx == -1 {
			return strings.TrimSpace(after)
		}
		return strings.TrimSpace(after[:eIdx])
	}

	screenText = extractTag(working, "SCREEN_START", "SCREEN_END")
	voiceScript = extractTag(working, "VOICE_START", "VOICE_END")

	clean := func(s string) string {
		s = strings.ReplaceAll(s, "**", "")
		s = strings.ReplaceAll(s, "###", "")
		s = strings.ReplaceAll(s, "##", "")
		return strings.TrimSpace(s)
	}

	screenText = clean(screenText)
	voiceScript = clean(voiceScript)

	if screenText == "" {
		fallback, ctx := extractTextAndDraftContext(raw)
		screenText = fallback
		if draftCtx == "" {
			draftCtx = ctx
		}
	}
	if voiceScript == "" {
		voiceScript = screenText
	}
	return screenText, voiceScript, draftCtx
}

// AnalyzeDraftByModel ejecuta el análisis del Draft usando la arquitectura del modelo solicitado:
// - "classic": sin JSONs, respuesta rápida (Campeón + Runas + estrategia), voz local.
// - "flake": con JSONs de Wild Rift, razonamiento de bans/picks aliados y enemigos + runas, voz local.
// - "aureon": con JSONs de Wild Rift, salida dividida (pantalla rápida + guion de voz extendido para WaveNet).
func AnalyzeDraftByModel(ctx context.Context, modelTier string, base64Image string, mainRole, secondaryRole, autofillRole string, gameMode string, otpChampions string, lang string, excludeChampions ...string) (DraftAIResult, error) {
	if aiClient == nil {
		return DraftAIResult{}, fmt.Errorf("el cliente de IA no ha sido inicializado")
	}

	imgData, err := base64.StdEncoding.DecodeString(base64Image)
	if err != nil {
		log.Printf("Error decoding base64 image: %v", err)
		return DraftAIResult{}, fmt.Errorf("invalid image format")
	}

	selectedLang := "es"
	if strings.TrimSpace(lang) != "" {
		selectedLang = NormalizeLanguage(lang)
	}

	excludeList := ""
	if len(excludeChampions) > 0 && strings.TrimSpace(excludeChampions[0]) != "" {
		excludeList = strings.TrimSpace(excludeChampions[0])
	}

	tier := strings.ToLower(strings.TrimSpace(modelTier))
	var prompt string
	var maxTokens int32
	switch tier {
	case "flake":
		prompt = buildFlakePrompt(gameMode, otpChampions, selectedLang, excludeList)
		maxTokens = 1100
	case "aureon":
		prompt = buildAureonPrompt(gameMode, otpChampions, selectedLang, excludeList)
		maxTokens = 1300
	default:
		tier = "classic"
		prompt = buildClassicPrompt(gameMode, otpChampions, selectedLang, excludeList)
		maxTokens = 550
	}

	contents := []*genai.Content{
		{
			Role: "user",
			Parts: []*genai.Part{
				{Text: prompt},
				{InlineData: &genai.Blob{Data: imgData, MIMEType: "image/jpeg"}},
			},
		},
	}

	thinkingBudget := int32(0)
	cfg := &genai.GenerateContentConfig{
		MaxOutputTokens: maxTokens,
		ThinkingConfig: &genai.ThinkingConfig{
			ThinkingBudget: &thinkingBudget,
		},
	}

	resp, err := aiClient.Models.GenerateContent(ctx, "gemini-2.5-flash", contents, cfg)
	if err != nil || resp == nil {
		return DraftAIResult{}, fmt.Errorf("falló generación con modelo %s: %w", tier, err)
	}

	var tokens int32 = 0
	if resp.UsageMetadata != nil {
		tokens = resp.UsageMetadata.TotalTokenCount
		log.Printf("📊 [%s / gemini-2.5-flash] Tokens - Prompt: %d, Salida: %d, Total: %d",
			tier,
			resp.UsageMetadata.PromptTokenCount,
			resp.UsageMetadata.CandidatesTokenCount,
			resp.UsageMetadata.TotalTokenCount,
		)
	}

	rawText := resp.Text()
	if strings.TrimSpace(rawText) == "" {
		return DraftAIResult{ScreenText: "No clear recommendation could be generated.", Tokens: tokens}, nil
	}

	if tier == "aureon" {
		screenText, voiceScript, draftCtx := parseAureonSections(rawText)
		if draftCtx == "" {
			draftCtx = fmt.Sprintf(`{"role":"Auto","summary":%q}`, screenText)
		}
		return DraftAIResult{
			ScreenText:   screenText,
			VoiceScript:  voiceScript,
			DraftContext: draftCtx,
			Tokens:       tokens,
		}, nil
	}

	cleanText, draftCtx := extractTextAndDraftContext(rawText)
	if draftCtx == "" {
		draftCtx = fmt.Sprintf(`{"role":"Auto","summary":%q}`, cleanText)
	}
	return DraftAIResult{
		ScreenText:   cleanText,
		DraftContext: draftCtx,
		Tokens:       tokens,
	}, nil
}

func AnalyzeDraft(ctx context.Context, base64Image string, mainRole, secondaryRole, autofillRole string, gameMode string, otpChampions string, lang string, excludeChampions ...string) (string, string, int32, error) {
	res, err := AnalyzeDraftByModel(ctx, "classic", base64Image, mainRole, secondaryRole, autofillRole, gameMode, otpChampions, lang, excludeChampions...)
	return res.ScreenText, res.DraftContext, res.Tokens, err
}

// ReconsultDraftFromContext (Puntos 1.2 y 1.6):
// Reconsulta alternativas usando ÚNICAMENTE los datos internos que dejó la primera captura (sin reenviar imagen).
func ReconsultDraftFromContext(ctx context.Context, draftContext string, otpChampions string, gameMode string, lang string, excludeChampions string) (string, string, int32, error) {
	if aiClient == nil {
		return "", "", 0, fmt.Errorf("el cliente de IA no ha sido inicializado")
	}

	selectedLang := NormalizeLanguage(lang)
	isPC := strings.EqualFold(strings.TrimSpace(gameMode), "lol_pc") || strings.EqualFold(strings.TrimSpace(gameMode), "pc")
	gameTitle := "League of Legends: Wild Rift"
	wrCatalog := ""
	if isPC {
		gameTitle = "League of Legends (PC)"
	} else {
		wrCatalog = GetWildRiftChampionsContext()
	}

	var prompt string
	switch selectedLang {
	case "pt":
		prompt = fmt.Sprintf(`Você é um Analista Mestre e Challenger de %s.
Dados extraídos da captura do draft atual: %s
Campeões já sugeridos anteriormente (PROIBIDO REPETIR QUALQUER UM DELES): %s
OTP do jogador (se aplicável): %s
%s
Pense em uma NOVA resposta alternativa com campeões diferentes para a mesma rota e partida.
PROIBIDO incluir runas ou feitiços. Sem asteriscos (**).

ESTRUTURA EXATA:
Situação: [Breve foco tático para esta nova alternativa na mesma rota]
Por que esta escolha: [Por que este novo campeão vence a composição inimiga]

PLANO A: [Novo Campeão Principal]
• Plano de ação: [Quem focar/anular e como jogar a partida]

Recomendações semelhantes:
• [Novo Campeão 2]: [Por que é uma ótima opção alternativa em 1 linha]
• [Novo Campeão 3]: [Por que é uma ótima opção alternativa em 1 linha]`, gameTitle, draftContext, excludeChampions, otpChampions, wrCatalog)

	case "en":
		prompt = fmt.Sprintf(`You are a Master and Challenger Analyst for %s.
Data extracted from the current draft screenshot: %s
Previously suggested champions (STRICTLY FORBIDDEN TO REPEAT ANY OF THESE): %s
Player OTP (if any): %s
%s
Think of a NEW alternative response with different champions for the exact same role and match.
DO NOT include runes or summoner spells. No asterisks (**).

EXACT STRUCTURE:
Situation: [Brief tactical focus for this new alternative in the same role]
Why this pick: [Why this new champion counters the enemy composition]

PLAN A: [New Main Champion]
• Action plan: [Which enemy to target/counter and how to play the match]

Similar recommendations:
• [New Champion 2]: [Why it is a strong alternative in 1 line]
• [New Champion 3]: [Why it is a strong alternative in 1 line]`, gameTitle, draftContext, excludeChampions, otpChampions, wrCatalog)

	case "fr":
		prompt = fmt.Sprintf(`Tu es un Analyste Maître et Challenger de %s.
Données extraites de la capture du draft actuel : %s
Champions déjà suggérés (INTERDICTION STRICTE DE LES RÉPÉTER) : %s
OTP du joueur : %s
%s
Propose une NOUVELLE réponse alternative avec des champions différents pour le même rôle.
INTERDICTION d'inclure des runes ou des sorts. Pas d'astérisques (**).

STRUCTURE EXACTE :
Situation : [Bref angle tactique pour cette nouvelle alternative]
Pourquoi ce choix : [Pourquoi ce nouveau champion gagne contre la composition adverse]

PLAN A : [Nouveau Champion Principal]
• Plan d'action : [Quel ennemi cibler/contrer et comment jouer]

Recommandations similaires :
• [Nouveau Champion 2] : [Pourquoi c'est une bonne alternative en 1 ligne]
• [Nouveau Champion 3] : [Pourquoi c'est une bonne alternative en 1 ligne]`, gameTitle, draftContext, excludeChampions, otpChampions, wrCatalog)

	default:
		prompt = fmt.Sprintf(`Eres un Analista Maestro y Challenger de %s.
Datos extraídos de la captura de pantalla del draft actual: %s
Campeones ya recomendados anteriormente (ESTÁ ESTRICTAMENTE PROHIBIDO REPETIR CUALQUIERA DE ELLOS): %s
OTP del jugador (si aplica): %s
%s
Con estos datos de la partida, piensa en una NUEVA respuesta alternativa con campeones distintos para el mismo rol asignado.
PROHIBIDO dar consejos de runas o hechizos. PROHIBIDO usar asteriscos (**).

ESTRUCTURA EXACTA:
Situación: [Enfoque táctico breve para esta nueva alternativa en el mismo rol]
Por qué este pick: [Explicación clara de por qué este nuevo campeón es excelente opción en esta partida]

PLAN A: [Nuevo Campeón Principal]
• Plan de acción: [A qué rival priorizar o contrarrestar y sinergia con tu equipo]

Recomendaciones similares:
• [Nuevo Campeón 2]: [Por qué es una gran alternativa en 1 línea]
• [Nuevo Campeón 3]: [Por qué es una gran alternativa en 1 línea]`, gameTitle, draftContext, excludeChampions, otpChampions, wrCatalog)
	}

	contents := []*genai.Content{
		{
			Role: "user",
			Parts: []*genai.Part{
				{Text: prompt},
			},
		},
	}

	maxTokens := int32(900)
	thinkingBudget := int32(0)

	cfg := &genai.GenerateContentConfig{
		MaxOutputTokens: maxTokens,
		ThinkingConfig: &genai.ThinkingConfig{
			ThinkingBudget: &thinkingBudget,
		},
	}

	resp, err := aiClient.Models.GenerateContent(ctx, "gemini-2.5-flash", contents, cfg)
	if err != nil || resp == nil {
		return "", draftContext, 0, fmt.Errorf("falló reconsulta IA: %w", err)
	}

	var tokens int32 = 0
	if resp.UsageMetadata != nil {
		tokens = resp.UsageMetadata.TotalTokenCount
		log.Printf("📊 [Reconsulta Sin Imagen] Tokens - Prompt: %d, Salida: %d, Total: %d",
			resp.UsageMetadata.PromptTokenCount,
			resp.UsageMetadata.CandidatesTokenCount,
			resp.UsageMetadata.TotalTokenCount,
		)
	}

	cleanText, _ := extractTextAndDraftContext(resp.Text())
	return cleanText, draftContext, tokens, nil
}

// AnalyzeDraftChat (Puntos 1.8 y 2):
// Chatbot en tiempo real entrenado con los JSONs oficiales de Runas, Objetos y Campeones de Wild Rift.
func AnalyzeDraftChat(ctx context.Context, userMessage string, draftContext string, otpChampions string, gameMode string, lang string) (string, int32, error) {
	if aiClient == nil {
		return "", 0, fmt.Errorf("el cliente de IA no ha sido inicializado")
	}

	selectedLang := NormalizeLanguage(lang)
	isPC := strings.EqualFold(strings.TrimSpace(gameMode), "lol_pc") || strings.EqualFold(strings.TrimSpace(gameMode), "pc")
	gameTitle := "League of Legends: Wild Rift"
	wrKnowledge := ""
	if isPC {
		gameTitle = "League of Legends (PC)"
	} else {
		wrKnowledge = GetWildRiftChatContext(userMessage, draftContext)
	}

	if strings.TrimSpace(draftContext) == "" {
		draftContext = "Sin captura previa activa (consulta directa del jugador)."
	}

	var prompt string
	switch selectedLang {
	case "pt":
		prompt = fmt.Sprintf(`Você é o Coach Tático em tempo real de %s dentro do app Drafting.
Contexto atual da partida (extraído da captura): %s
%s
Pergunta do jogador: "%s"

REGRAS CRÍTICAS:
- Responda de forma direta, ultra concisa (máximo 80-100 palavras) e 100%% fiel ao Wild Rift atual.
- Se o jogador perguntar sobre runas, indique: 1 Runa Essencial + 3 Runas da Árvore Principal + 1 Runa Secundária que realmente existam na base acima.
- Se perguntar sobre itens/build, recomende apenas itens e botas nível 3 reais do Wild Rift.
- PROIBIDO usar asteriscos (**). Use apenas texto limpo e tópicos (•).`, gameTitle, draftContext, wrKnowledge, userMessage)

	case "en":
		prompt = fmt.Sprintf(`You are the real-time Tactical Coach for %s inside the Drafting app.
Current match context (from screenshot): %s
%s
Player question: "%s"

CRITICAL RULES:
- Answer directly, concisely (max 80-100 words), and 100%% accurately for current Wild Rift.
- If asked about runes, specify: 1 Keystone + 3 Primary Tree Runes + 1 Secondary Rune from the official Wild Rift database above.
- If asked about items/builds, only recommend real Wild Rift items and Tier 3 boots.
- DO NOT use asterisks (**). Use plain text and bullet points (•) only.`, gameTitle, draftContext, wrKnowledge, userMessage)

	case "fr":
		prompt = fmt.Sprintf(`Tu es le Coach Tactique en temps réel de %s dans l'application Drafting.
Contexte actuel de la partie : %s
%s
Question du joueur : "%s"

RÈGLES CRITIQUES :
- Réponds directement, de façon très concise (max 80-100 mots) et 100%% fidèle à Wild Rift.
- Si le joueur demande des runes, indique : 1 Rune Fondamentale + 3 Runes Principales + 1 Rune Secondaire existant dans Wild Rift.
- INTERDICTION d'utiliser des astérisques (**). Texte brut et puces (•) uniquement.`, gameTitle, draftContext, wrKnowledge, userMessage)

	default:
		prompt = fmt.Sprintf(`Eres el Entrenador Táctico en tiempo real de %s dentro de Drafting.
Contexto actual de la partida (detectado en la captura): %s
%s
Pregunta del jugador: "%s"

REGLAS CRÍTICAS:
- Responde directo al grano, muy conciso (máximo 80-100 palabras, lectura rápida en partida) y 100%% apegado a lo que existe realmente en Wild Rift (PROHIBIDO mezclar con LoL PC).
- Si pregunta por runas, dale exactamente el formato de Wild Rift: 1 Runa Clave + 3 Runas de Rama Principal + 1 Runa Secundaria usando solo las runas reales de la base de datos.
- Si pregunta por objetos o build, recomienda solo objetos y botas mejoradas reales de Wild Rift.
- PROHIBIDO usar asteriscos (**). Usa solo texto limpio y viñetas con punto (•).`, gameTitle, draftContext, wrKnowledge, userMessage)
	}

	contents := []*genai.Content{
		{
			Role: "user",
			Parts: []*genai.Part{
				{Text: prompt},
			},
		},
	}

	maxTokens := int32(700)
	thinkingBudget := int32(0)

	cfg := &genai.GenerateContentConfig{
		MaxOutputTokens: maxTokens,
		ThinkingConfig: &genai.ThinkingConfig{
			ThinkingBudget: &thinkingBudget,
		},
	}

	resp, err := aiClient.Models.GenerateContent(ctx, "gemini-2.5-flash", contents, cfg)
	if err != nil || resp == nil {
		return "", 0, fmt.Errorf("falló chat IA: %w", err)
	}

	var tokens int32 = 0
	if resp.UsageMetadata != nil {
		tokens = resp.UsageMetadata.TotalTokenCount
		log.Printf("📊 [Chat Tiempo Real] Tokens - Prompt: %d, Salida: %d, Total: %d",
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

func buildManualDraftPrompt(mainRole, myChampion, enemyChampion, gameMode, lang string, excludeChampions ...string) string {
	isPC := strings.EqualFold(strings.TrimSpace(gameMode), "lol_pc") || strings.EqualFold(strings.TrimSpace(gameMode), "pc")
	gameTitle := "League of Legends: Wild Rift"
	wrContext := ""
	if isPC {
		gameTitle = "League of Legends (PC)"
	} else {
		wrContext = "\n" + GetWildRiftChampionsContext() + "\n" + GetWildRiftChatContext(myChampion+" "+enemyChampion, mainRole)
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
O jogador está na rota '%s' e jogará com '%s' enfrentando '%s' na rota.%s

Forneça um guia tático direto, rápido e acionável para os próximos 30 segundos:
- PROIBIDO USAR ASTERISCOS (**) OU ESTILOS MARKDOWN. Apenas texto limpo e tópicos com ponto (•).

ESTRUTURA EXATA:
Situação: [Diagnóstico em 1 frase curta do confronto %s vs %s]

PLANO DE JOGO:
• Feitiços: [Feitiços de invocador ideais contra este rival]
• Runas: [Runa essencial + 3 runas principais + 1 secundária do Wild Rift]
• Itens e Build: [Primeiros 3 itens prioritários e botas do Wild Rift]
• Tática de Linha: [Como punir o rival, níveis de pico de poder e cuidados principais]`, gameTitle, mainRole, myChampion, enemyChampion, wrContext, myChampion, enemyChampion)
		}
		excludeClause := ""
		if excludeList != "" {
			excludeClause = fmt.Sprintf("\nPROIBIDO sugerir qualquer um destes campeões já visualizados: %s.", excludeList)
		}
		return fmt.Sprintf(`Você é um Treinador e Analista Mestre/Challenger de %s.
O jogador joga na rota '%s' e o adversário direto escolheu '%s'.%s
Recomende o melhor campeão para contra-atacar (Counter) e vencer a rota.%s
- PROIBIDO USAR ASTERISCOS (**) OU ESTILOS MARKDOWN. Apenas texto limpo e tópicos com ponto (•).

ESTRUTURA EXATA:
Situação: [Diagnóstico em 1 frase curta das fraquezas de %s]

PLANO A: [Nome do Melhor Counter na rota %s]
• Por que vence: [Vantagem direta do kit de habilidades sobre %s]
• Feitiços: [Feitiços de invocador recomendados]
• Runas: [Runa essencial e secundárias prioritárias do Wild Rift]
• Itens essenciais: [Primeiros 2 itens recomendados contra %s]
• Tática de Linha: [Como jogar o confronto nos primeiros 5 minutos]

Recomendações semelhantes:
• [Campeão 2]: [Por que é uma boa alternativa contra %s]
• [Campeão 3]: [Por que é uma boa alternativa contra %s]`, gameTitle, mainRole, enemyChampion, wrContext, excludeClause, enemyChampion, mainRole, enemyChampion, enemyChampion, enemyChampion, enemyChampion)

	case "en":
		if hasMyChamp {
			return fmt.Sprintf(`You are a Master and Challenger Coach/Analyst for %s.
The player is in lane '%s' playing as '%s' facing '%s'.%s

Provide a direct, concise, and tactical guide for champion select (under 30s):
- DO NOT USE ASTERISKS (**) OR MARKDOWN STYLES. Plain text and bullet points (•) only.

EXACT STRUCTURE:
Situation: [1 short sentence diagnosing %s vs %s matchup]

TACTICAL PLAN:
• Spells: [Optimal summoner spells against this rival]
• Runes: [Keystone + 3 primary runes + 1 secondary rune from Wild Rift]
• Core Build: [First 3 core items and boots from Wild Rift]
• Lane Strategy: [How to trade, power spikes, and what to watch out for]`, gameTitle, mainRole, myChampion, enemyChampion, wrContext, myChampion, enemyChampion)
		}
		excludeClause := ""
		if excludeList != "" {
			excludeClause = fmt.Sprintf("\nSTRICTLY FORBIDDEN to suggest these champions already shown: %s.", excludeList)
		}
		return fmt.Sprintf(`You are a Master and Challenger Coach/Analyst for %s.
The player plays in '%s' lane and the direct lane opponent picked '%s'.%s
Recommend the optimal counter-pick champion to win lane.%s
- DO NOT USE ASTERISKS (**) OR MARKDOWN STYLES. Plain text and bullet points (•) only.

EXACT STRUCTURE:
Situation: [1 short sentence diagnosing %s's main weaknesses]

PLAN A: [Best Counter Champion for %s lane]
• Why it counters: [Direct kit advantage over %s]
• Spells: [Recommended summoner spells]
• Runes: [Optimal keystone and secondary runes from Wild Rift]
• Core Build: [First 2 items to counter %s]
• Lane Strategy: [How to dominate the matchup early game]

Similar recommendations:
• [Champion 2]: [Why it is a strong alternative against %s]
• [Champion 3]: [Why it is a strong alternative against %s]`, gameTitle, mainRole, enemyChampion, wrContext, excludeClause, enemyChampion, mainRole, enemyChampion, enemyChampion, enemyChampion, enemyChampion)

	case "fr":
		if hasMyChamp {
			return fmt.Sprintf(`Tu es un Coach et Analyste Maître/Challenger de %s.
Le joueur est sur la voie '%s' avec '%s' contre '%s'.%s

Donne un guide tactique direct et clair pour les 30 prochaines secondes :
- INTERDICTION D'UTILISER DES ASTÉRISQUES (**) OU DU MARKDOWN. Texte brut et puces (•) uniquement.

STRUCTURE EXACTE :
Situation : [Diagnostic en 1 phrase courte du match %s vs %s]

PLAN TACTIQUE :
• Sorts : [Sorts d'invocateur idéaux contre ce rival]
• Runes : [Rune fondamentale + runes secondaires de Wild Rift]
• Objets essentiels : [3 premiers objets prioritaires de Wild Rift]
• Tactique de voie : [Comment punir le rival et gérer les pics de puissance]`, gameTitle, mainRole, myChampion, enemyChampion, wrContext, myChampion, enemyChampion)
		}
		excludeClause := ""
		if excludeList != "" {
			excludeClause = fmt.Sprintf("\nINTERDICTION de suggérer ces champions déjà vus : %s.", excludeList)
		}
		return fmt.Sprintf(`Tu es un Coach et Analyste Maître/Challenger de %s.
Le joueur joue sur la voie '%s' et l'adversaire direct a choisi '%s'.%s
Recommande le meilleur champion pour contrer (Counter) et remporter la voie.%s
- INTERDICTION D'UTILISER DES ASTÉRISQUES (**) OU DU MARKDOWN. Texte brut et puces (•) uniquement.

STRUCTURE EXACTE :
Situation : [Diagnostic en 1 phrase courte des faiblesses de %s]

PLAN A : [Meilleur Champion Counter sur la voie %s]
• Pourquoi il gagne : [Avantage direct du kit contre %s]
• Sorts : [Sorts d'invocateur recommandés]
• Runes : [Rune fondamentale et secondaires prioritaires de Wild Rift]
• Objets essentiels : [2 premiers objets recommandés contre %s]
• Tactique de voie : [Comment dominer le face-à-face]

Recommandations similaires :
• [Champion 2] : [Pourquoi c'est une bonne alternative contre %s]
• [Champion 3] : [Pourquoi c'est une bonne alternative contre %s]`, gameTitle, mainRole, enemyChampion, wrContext, excludeClause, enemyChampion, mainRole, enemyChampion, enemyChampion, enemyChampion, enemyChampion)

	default: // "es"
		if hasMyChamp {
			return fmt.Sprintf(`Eres un Entrenador y Analista Maestro/Challenger de %s.
El jugador va en la línea '%s' jugando con '%s' contra '%s'.%s

Genera una guía táctica directa, clara y accionable para los 30 segundos del draft:
- FORMATO OBLIGATORIO: PROHIBIDO USAR ASTERISCOS (**) O ESTILOS MARKDOWN. Solo texto limpio y viñetas con punto (•).

ESTRUCTURA EXACTA:
Situación: [Diagnóstico en 1 frase corta del matchup %s vs %s]

PLAN TÁCTICO:
• Hechizos: [Hechizos de invocador óptimos de Wild Rift contra este rival]
• Runas: [1 Runa clave + 3 de rama principal + 1 secundaria reales de Wild Rift]
• Build de Objetos: [Primeros 3 objetos prioritarios y botas reales de Wild Rift]
• Táctica de Línea: [Cómo tradear, niveles de ventaja y principales precauciones]`, gameTitle, mainRole, myChampion, enemyChampion, wrContext, myChampion, enemyChampion)
		}
		excludeClause := ""
		if excludeList != "" {
			excludeClause = fmt.Sprintf("\nPROHIBIDO sugerir cualquiera de estos campeones ya visualizados: %s.", excludeList)
		}
		return fmt.Sprintf(`Eres un Entrenador y Analista Maestro/Challenger de %s.
El jugador va en la línea '%s' y el rival directo ya seleccionó a '%s'.%s
Recomienda el mejor contra-pick (Counter) para ganar la línea.%s
- FORMATO OBLIGATORIO: PROHIBIDO USAR ASTERISCOS (**) O ESTILOS MARKDOWN. Solo texto limpio y viñetas con punto (•).

ESTRUCTURA EXACTA:
Situación: [Diagnóstico en 1 frase corta de las debilidades de %s]

PLAN A: [Mejor Campeón Counter en %s]
• Por qué le gana: [Ventaja directa de habilidades sobre %s explicada con sencillez]
• Hechizos: [Hechizos de invocador recomendados en Wild Rift]
• Runas: [1 Runa clave + 3 principales + 1 secundaria reales de Wild Rift]
• Build clave: [Primeros 2 objetos y botas recomendados en Wild Rift contra %s]
• Táctica de Línea: [Cómo castigarlo en los primeros niveles]

Recomendaciones similares:
• [Campeón 2]: [Por qué funciona bien contra %s]
• [Campeón 3]: [Por qué funciona bien contra %s]`, gameTitle, mainRole, enemyChampion, wrContext, excludeClause, enemyChampion, mainRole, enemyChampion, enemyChampion, enemyChampion, enemyChampion)
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
	thinkingBudget := int32(0)

	models := []string{"gemini-2.5-flash"}
	var lastErr error
	var resp *genai.GenerateContentResponse
	var usedModel string

	for _, model := range models {
		cfg := &genai.GenerateContentConfig{
			MaxOutputTokens: maxTokens,
		}
		if strings.Contains(model, "2.5") {
			cfg.ThinkingConfig = &genai.ThinkingConfig{
				ThinkingBudget: &thinkingBudget,
			}
		}

		resp, lastErr = aiClient.Models.GenerateContent(ctx, model, contents, cfg)
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

// DraftVisionState representa el contrato DraftVisionJSON (Tarea 0.1) extraído de una captura de Wild Rift.
type DraftVisionState struct {
	Role       string   `json:"role"`
	DraftPhase string   `json:"draft_phase"` // "first_pick" | "mid_draft" | "last_pick" | "full_locked"
	MyPick     string   `json:"my_pick"`
	Bans       []string `json:"bans"`
	Allies     []string `json:"allies"`
	Enemies    []string `json:"enemies"`
}

func normalizeVisionRole(raw string, fallbackRole ...string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "baron", "top", "solo":
		return "Baron"
	case "jungle", "jungla", "jg":
		return "Jungle"
	case "dragon", "adc", "bot", "duo":
		return "Dragon"
	case "support", "soporte", "supp", "sup":
		return "Support"
	case "mid", "medio":
		return "Mid"
	}
	if len(fallbackRole) > 0 && strings.TrimSpace(fallbackRole[0]) != "" && !strings.EqualFold(strings.TrimSpace(fallbackRole[0]), "auto") {
		return normalizeVisionRole(fallbackRole[0])
	}
	return "Mid"
}

func inferVisionPhase(rawPhase string, myPick string, allies []string, enemies []string) string {
	p := strings.ToLower(strings.TrimSpace(rawPhase))
	if strings.TrimSpace(myPick) != "" || p == "full_locked" || p == "locked" || (len(allies) >= 4 && len(enemies) >= 5) {
		return "full_locked"
	}
	if len(enemies) == 0 || p == "first_pick" {
		return "first_pick"
	}
	if len(enemies) >= 4 || p == "last_pick" {
		return "last_pick"
	}
	return "mid_draft"
}

func parseDraftVisionJSON(raw string, fallbackRole ...string) (DraftVisionState, error) {
	cleaned := strings.TrimSpace(raw)
	cleaned = strings.TrimPrefix(cleaned, "```json")
	cleaned = strings.TrimPrefix(cleaned, "```")
	cleaned = strings.TrimSuffix(cleaned, "```")
	cleaned = strings.TrimSpace(cleaned)

	if start := strings.Index(cleaned, "{"); start != -1 {
		if end := strings.LastIndex(cleaned, "}"); end > start {
			cleaned = cleaned[start : end+1]
		}
	}

	var state DraftVisionState
	if err := json.Unmarshal([]byte(cleaned), &state); err != nil {
		return DraftVisionState{}, err
	}
	state.Role = normalizeVisionRole(state.Role, fallbackRole...)
	state.MyPick = strings.TrimSpace(state.MyPick)
	if state.Bans == nil {
		state.Bans = []string{}
	}
	if state.Allies == nil {
		state.Allies = []string{}
	}
	if state.Enemies == nil {
		state.Enemies = []string{}
	}
	state.DraftPhase = inferVisionPhase(state.DraftPhase, state.MyPick, state.Allies, state.Enemies)
	return state, nil
}

// ExtractDraftVision extrae únicamente el JSON compacto del estado del draft desde una captura de Wild Rift
// (~90% menos tokens que AnalyzeDraftByModel). Usa gemini-2.5-flash-lite con fallback a gemini-2.5-flash.
func ExtractDraftVision(ctx context.Context, base64Image string, fallbackRole ...string) (DraftVisionState, int32, error) {
	if aiClient == nil {
		return DraftVisionState{}, 0, fmt.Errorf("el cliente de IA no ha sido inicializado")
	}

	imgData, err := base64.StdEncoding.DecodeString(base64Image)
	if err != nil {
		return DraftVisionState{}, 0, fmt.Errorf("invalid image format")
	}

	const visionPrompt = `Extract the Wild Rift champion select state from this screenshot.
Return ONLY valid JSON with this exact schema:
{"role":"Baron|Jungle|Mid|Dragon|Support","draft_phase":"first_pick|mid_draft|last_pick|full_locked","my_pick":"","bans":[],"allies":[],"enemies":[]}
Rules:
- role: the local player's assigned lane.
- draft_phase: "first_pick" if 0 enemies picked yet; "mid_draft" if 1-3 enemies picked; "last_pick" if 4-5 enemies picked and local player hasn't locked; "full_locked" if the local player already locked their champion or all 10 champions are selected.
- my_pick: champion name already locked by the local player ("" if not picked yet).
- bans: 0 to 10 banned champion names (empty array if none/skipped).
- allies: 0 to 4 other allied picked champion names (excluding my_pick).
- enemies: 0 to 5 enemy picked champion names.
- Use official Wild Rift champion names only. No explanations.`

	contents := []*genai.Content{
		{
			Role: "user",
			Parts: []*genai.Part{
				{Text: visionPrompt},
				{InlineData: &genai.Blob{Data: imgData, MIMEType: "image/jpeg"}},
			},
		},
	}

	thinkingBudget := int32(0)
	models := []string{"gemini-2.5-flash", "gemini-2.5-flash-lite"}
	var resp *genai.GenerateContentResponse
	var lastErr error
	var usedModel string

	for attempt, m := range models {
		cfg := &genai.GenerateContentConfig{
			MaxOutputTokens:  512,
			ResponseMIMEType: "application/json",
		}
		if m == "gemini-2.5-flash" {
			cfg.ThinkingConfig = &genai.ThinkingConfig{
				ThinkingBudget: &thinkingBudget,
			}
		}

		resp, lastErr = aiClient.Models.GenerateContent(ctx, m, contents, cfg)
		if lastErr == nil && resp != nil && strings.TrimSpace(resp.Text()) != "" {
			usedModel = m
			break
		}
		log.Printf("⚠️ [extract-vision intento %d] %s falló: %v", attempt+1, m, lastErr)
	}

	if lastErr != nil || resp == nil {
		return DraftVisionState{}, 0, fmt.Errorf("falló extracción de visión: %w", lastErr)
	}

	var tokens int32 = 0
	if resp.UsageMetadata != nil {
		tokens = resp.UsageMetadata.TotalTokenCount
		log.Printf("📊 [extract-vision / %s] Tokens - Prompt: %d, Salida: %d, Total: %d",
			usedModel,
			resp.UsageMetadata.PromptTokenCount,
			resp.UsageMetadata.CandidatesTokenCount,
			resp.UsageMetadata.TotalTokenCount,
		)
	}

	rawText := resp.Text()
	state, err := parseDraftVisionJSON(rawText, fallbackRole...)
	if err != nil {
		log.Printf("⚠️ [extract-vision] JSON inválido recibido de %s: %q | err=%v", usedModel, rawText, err)
		return DraftVisionState{}, tokens, fmt.Errorf("JSON de visión inválido: %w", err)
	}
	return state, tokens, nil
}
