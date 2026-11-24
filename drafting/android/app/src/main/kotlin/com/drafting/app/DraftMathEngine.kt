package com.drafting.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.text.Normalizer

/**
 * Motor Matemático de Draft con Poda por Rol (Port 1:1 de local_ai/draft_math_engine.py).
 *
 * Evalúa únicamente los candidatos válidos de la línea asignada:
 *   C_valido = Lanes[role] - (bans U allies U enemies U exclude)
 * Ejecuta en < 1 ms en CPU ARM (Infinix Hot 40 Pro / Helio G99) con 0% alucinaciones.
 */
object DraftMathEngine {

    private const val AD = 0
    private const val AP = 1
    private const val TANK = 2
    private const val CC = 3
    private const val ENGAGE = 4
    private const val PEEL = 5
    private const val MOBILITY = 6
    private const val BURST = 7
    private const val ANTI_TANK = 8
    private const val BLIND_SAFE = 9

    data class ChampionData(
        val name: String,
        val roles: List<String>,
        val vec: IntArray,
        val tags: Set<String>,
        val runes: String
    )

    data class PickRecommendation(
        val name: String,
        val score: Double,
        val runes: String,
        val reasons: List<String>
    )

    data class MathDraftResult(
        val lang: String,
        val role: String,
        val draftPhase: String,
        val myPick: String,
        val otp: String,
        val otpViable: Boolean,
        val allies: List<String>,
        val enemies: List<String>,
        val bans: List<String>,
        val exclude: List<String>,
        val evaluatedCandidates: Int,
        val latencyMs: Double,
        val top3: List<PickRecommendation>
    ) {
        fun toSlmInputJson(): String {
            val topArr = JSONArray()
            for (p in top3) {
                topArr.put(JSONObject().apply {
                    put("name", p.name)
                    put("runes", p.runes)
                    put("reasons", JSONArray(p.reasons))
                })
            }
            return JSONObject().apply {
                put("lang", lang)
                put("role", role)
                put("draft_phase", draftPhase)
                put("my_pick", myPick)
                put("otp", otp)
                put("otp_viable", otpViable)
                put("allies", JSONArray(allies))
                put("enemies", JSONArray(enemies))
                put("bans", JSONArray(bans))
                put("exclude", JSONArray(exclude))
                put("top3", topArr)
            }.toString()
        }

        fun toDraftContextJson(): String {
            val suggested = top3.map { it.name }
            return JSONObject().apply {
                put("role", role)
                put("draft_phase", draftPhase)
                put("my_pick", myPick)
                put("bans", JSONArray(bans))
                put("allies", JSONArray(allies))
                put("enemies", JSONArray(enemies))
                put("suggested", JSONArray(suggested))
            }.toString()
        }
    }

    private val roleAliases = mapOf(
        "baron" to "Baron", "top" to "Baron", "solo" to "Baron",
        "jungle" to "Jungle", "jungla" to "Jungle", "jg" to "Jungle",
        "mid" to "Mid", "medio" to "Mid",
        "dragon" to "Dragon", "adc" to "Dragon", "bot" to "Dragon", "duo" to "Dragon",
        "support" to "Support", "soporte" to "Support", "supp" to "Support", "sup" to "Support"
    )

    private val enchanterAllies = setOf("Lulu", "Milio", "Yuumi", "Janna", "Braum")

    @Volatile
    private var loaded = false
    private val lanes = mutableMapOf<String, List<String>>()
    private val champions = mutableMapOf<String, ChampionData>()
    private val lookup = mutableMapOf<String, String>()

    private fun norm(text: String): String {
        val nfkd = Normalizer.normalize(text.lowercase().trim(), Normalizer.Form.NFD)
        val noAccents = nfkd.replace(Regex("\\p{InCombiningDiacriticalMarks}+"), "")
        return noAccents.replace("'", "").replace(".", "").replace(" ", "")
    }

    @Synchronized
    fun ensureLoaded(context: Context) {
        if (loaded) return
        val jsonText = context.assets.open("wr_vectors.json").bufferedReader(Charsets.UTF_8).use { it.readText() }
        val root = JSONObject(jsonText)

        val lanesObj = root.getJSONObject("lanes")
        for (laneKey in lanesObj.keys()) {
            val arr = lanesObj.getJSONArray(laneKey)
            val list = ArrayList<String>(arr.length())
            for (i in 0 until arr.length()) list.add(arr.getString(i))
            lanes[laneKey] = list
        }

        val champsObj = root.getJSONObject("champions")
        for (champName in champsObj.keys()) {
            val cObj = champsObj.getJSONObject(champName)
            val rArr = cObj.getJSONArray("roles")
            val rList = ArrayList<String>(rArr.length())
            for (i in 0 until rArr.length()) rList.add(rArr.getString(i))

            val vArr = cObj.getJSONArray("vec")
            val vec = IntArray(10) { i -> vArr.getInt(i) }

            val tArr = cObj.getJSONArray("tags")
            val tags = HashSet<String>(tArr.length())
            for (i in 0 until tArr.length()) tags.add(tArr.getString(i))

            val runes = cObj.getString("runes")
            champions[champName] = ChampionData(champName, rList, vec, tags, runes)
            lookup[norm(champName)] = champName
        }

        lookup["masteryi"] = "Maestro Yi"
        lookup["bard"] = "Bardo"
        lookup["nunu"] = "Nunu y Willump"
        lookup["mundo"] = "Dr. Mundo"
        lookup["drmundo"] = "Dr. Mundo"
        lookup["tf"] = "Twisted Fate"
        lookup["mf"] = "Miss Fortune"
        lookup["j4"] = "Jarvan IV"
        lookup["aurelion"] = "Aurelion Sol"
        lookup["asol"] = "Aurelion Sol"

        loaded = true
    }

    fun normalizeRole(role: String?): String {
        if (role.isNullOrBlank()) return "Mid"
        return roleAliases[norm(role)] ?: "Mid"
    }

    fun normalizeChamp(name: String?): String? {
        if (name.isNullOrBlank()) return null
        return lookup[norm(name)]
    }

    private fun normalizeList(items: List<String>): List<String> {
        val out = ArrayList<String>()
        for (item in items) {
            val c = normalizeChamp(item)
            if (c != null && !out.contains(c)) out.add(c)
        }
        return out
    }

    private data class BanPsychology(
        val antiTankBanned: Int,
        val antiDashBanned: Int,
        val assassinsBanned: Int,
        val peelBanned: Int
    )

    private fun analyzeBanPsychology(normBans: List<String>): BanPsychology {
        var antiTank = 0
        var antiDash = 0
        var assassins = 0
        var peel = 0
        for (b in normBans) {
            val info = champions[b] ?: continue
            val v = info.vec
            val tags = info.tags
            if ("anti_tank" in tags || v[ANTI_TANK] >= 3) antiTank++
            if ("anti_dash" in tags || v[CC] >= 3) antiDash++
            if (v[BURST] >= 3 && v[MOBILITY] >= 3) assassins++
            if (v[PEEL] >= 3) peel++
        }
        return BanPsychology(antiTank, antiDash, assassins, peel)
    }

    private fun detectDraftPhase(
        normAllies: List<String>,
        normEnemies: List<String>,
        normMyPick: String?,
        explicitPhase: String
    ): String {
        val exp = norm(explicitPhase)
        if (!normMyPick.isNullOrBlank() || exp in setOf("fulllocked", "locked", "full", "ingame", "postpick")) {
            return "full_locked"
        }
        if (normAllies.size >= 4 && normEnemies.size >= 5) {
            return "full_locked"
        }
        if (normEnemies.isEmpty()) {
            return "first_pick"
        }
        if (normEnemies.size >= 4) {
            return "last_pick"
        }
        return "mid_draft"
    }

    fun recommend(
        context: Context,
        role: String,
        bans: List<String> = emptyList(),
        allies: List<String> = emptyList(),
        enemies: List<String> = emptyList(),
        otp: String = "",
        myPick: String = "",
        draftPhase: String = "",
        exclude: List<String> = emptyList(),
        lang: String = "es",
        topK: Int = 3
    ): MathDraftResult {
        ensureLoaded(context)
        val t0 = System.nanoTime()

        val normRole = normalizeRole(role)
        val normBans = normalizeList(bans)
        var normAllies = normalizeList(allies)
        val normEnemies = normalizeList(enemies)
        val normExclude = normalizeList(exclude)
        val normOtp = normalizeChamp(otp)
        val normMyPick = normalizeChamp(myPick)

        if (normMyPick != null && normAllies.contains(normMyPick)) {
            normAllies = normAllies.filter { it != normMyPick }
        }

        val detectedPhase = detectDraftPhase(normAllies, normEnemies, normMyPick, draftPhase)
        val banPsych = analyzeBanPsychology(normBans)

        val blocked = HashSet<String>().apply {
            addAll(normBans)
            addAll(normAllies)
            addAll(normEnemies)
            addAll(normExclude)
        }

        val lanePool = lanes[normRole] ?: lanes["Mid"] ?: emptyList()
        val candidates = lanePool.filter { it !in blocked && champions.containsKey(it) }.toMutableList()
        if (normMyPick != null && champions.containsKey(normMyPick) && !candidates.contains(normMyPick)) {
            candidates.add(0, normMyPick)
        }

        val otpViableInRole = normOtp != null && lanePool.contains(normOtp)
        val otpAvailable = otpViableInRole && normOtp !in blocked

        var allyAd = 0
        var allyAp = 0
        var allyTank = 0
        var allyCc = 0
        var allyHasKnockup = false
        var allyHasHypercarry = false
        for (a in normAllies) {
            val c = champions[a] ?: continue
            allyAd += c.vec[AD]
            allyAp += c.vec[AP]
            allyTank += c.vec[TANK]
            allyCc += c.vec[CC]
            if ("knockup" in c.tags) allyHasKnockup = true
            if ("hypercarry" in c.tags) allyHasHypercarry = true
        }

        var enemyAd = 0
        var enemyAp = 0
        var enemyTanks = 0
        var enemyHighMob = 0
        var enemyBurst = 0
        var enemyCc = 0
        var enemyImmobile = 0
        for (e in normEnemies) {
            val c = champions[e] ?: continue
            enemyAd += c.vec[AD]
            enemyAp += c.vec[AP]
            if (c.vec[TANK] >= 2) enemyTanks++
            if (c.vec[MOBILITY] >= 3) enemyHighMob++
            if (c.vec[BURST] >= 3) enemyBurst++
            if (c.vec[CC] >= 3) enemyCc++
            if (c.vec[MOBILITY] <= 1) enemyImmobile++
        }

        val isBlind = detectedPhase == "first_pick"
        val isLastPick = detectedPhase == "last_pick"
        val counterMult = if (isLastPick) 1.25 else 1.0
        val scored = ArrayList<PickRecommendation>(candidates.size)

        for (cand in candidates) {
            val info = champions[cand] ?: continue
            val v = info.vec
            val tags = info.tags
            var score = 0.0
            val reasons = ArrayList<Pair<Double, String>>()

            if (normMyPick != null && cand == normMyPick) {
                score += 100.0
                reasons.add(100.0 to "locked_champion_gameplan")
            }

            if (isBlind) {
                val pts = v[BLIND_SAFE] * 3.0
                score += pts
                if (v[BLIND_SAFE] >= 3) reasons.add(pts to "safe_blind_pick")

                if (banPsych.antiTankBanned >= 2 && (v[TANK] >= 2 || v[ANTI_TANK] >= 3)) {
                    score += 3.8
                    reasons.add(3.8 to "ban_read_tanks_expected")
                }
                if (banPsych.antiDashBanned >= 2 && ("anti_dash" in tags || v[CC] >= 3)) {
                    score += 4.0
                    reasons.add(4.0 to "ban_read_mobility_expected")
                }
                if (banPsych.assassinsBanned >= 2 && (v[ENGAGE] >= 3 || v[BURST] >= 2)) {
                    score += 3.4
                    reasons.add(3.4 to "ban_read_carries_exposed")
                }
                if (banPsych.peelBanned >= 2 && (v[PEEL] >= 2 || v[TANK] >= 2)) {
                    score += 3.5
                    reasons.add(3.5 to "ban_read_dive_expected")
                }
            } else if (normEnemies.size == 1) {
                score += v[BLIND_SAFE] * 1.2
                if (banPsych.antiTankBanned >= 2 && v[ANTI_TANK] >= 3) {
                    score += 2.2
                    reasons.add(2.2 to "ban_read_tanks_expected")
                } else if (banPsych.antiDashBanned >= 2 && ("anti_dash" in tags || v[CC] >= 3)) {
                    score += 2.2
                    reasons.add(2.2 to "ban_read_mobility_expected")
                }
            }

            if (normAllies.isNotEmpty()) {
                val dmgMult = if (normRole == "Support") 0.7 else 2.2
                if (allyAd >= 5 && allyAp <= 2 && v[AP] >= 2) {
                    val pts = v[AP] * dmgMult
                    score += pts
                    reasons.add(pts to "ap_needed")
                } else if (allyAp >= 5 && allyAd <= 2 && v[AD] >= 2) {
                    val pts = v[AD] * dmgMult
                    score += pts
                    reasons.add(pts to "ad_needed")
                }

                if (allyTank <= 1 && v[TANK] >= 2 && normRole in setOf("Baron", "Jungle", "Support")) {
                    val pts = v[TANK] * 1.8
                    score += pts
                    reasons.add(pts to "frontline_needed")
                }
                if (allyCc <= 2 && v[CC] >= 3) {
                    val pts = 2.6
                    score += pts
                    reasons.add(pts to "cc_needed")
                }
            }

            if (enemyTanks >= 2 && (v[ANTI_TANK] >= 3 || "anti_tank" in tags)) {
                val pts = (4.5 + enemyTanks * 1.2) * counterMult
                score += pts
                reasons.add(pts to "anti_tank_shred")
            }

            if (enemyHighMob >= 2) {
                if ("anti_dash" in tags) {
                    val pts = 5.5 * counterMult
                    score += pts
                    reasons.add(pts to "hard_anti_mobility")
                } else if (v[CC] >= 3) {
                    val pts = 3.2 * counterMult
                    score += pts
                    reasons.add(pts to "lockdown_vs_mobility")
                }
            }

            if (enemyBurst >= 2 && (v[PEEL] >= 3 || v[TANK] >= 3)) {
                val pts = 3.5 * counterMult
                score += pts
                reasons.add(pts to "anti_burst_peel")
            }

            if (enemyAd >= 6 && enemyAp <= 2 && "anti_ad" in tags) {
                val pts = 6.0 * counterMult
                score += pts
                reasons.add(pts to "hard_anti_ad")
            }

            if (enemyAp >= 6 && enemyAd <= 2 && "anti_ap" in tags) {
                val pts = 6.0 * counterMult
                score += pts
                reasons.add(pts to "hard_anti_ap")
            }

            if (enemyCc >= 2 && "anti_cc" in tags) {
                val pts = 4.2 * counterMult
                score += pts
                reasons.add(pts to "anti_cc_shield")
            }

            if (enemyImmobile >= 2 && (v[ENGAGE] >= 3 || v[BURST] >= 3)) {
                val pts = 2.8 * counterMult
                score += pts
                reasons.add(pts to "punish_immobile")
            }

            if (normEnemies.size == 1) {
                val e0 = champions[normEnemies[0]]?.vec
                if (e0 != null) {
                    if (e0[TANK] >= 3 && (v[ANTI_TANK] >= 3 || "anti_tank" in tags)) {
                        score += 3.2
                        reasons.add(3.2 to "anti_tank_shred")
                    } else if (e0[MOBILITY] >= 3 && ("anti_dash" in tags || v[CC] >= 3)) {
                        score += 3.2
                        reasons.add(3.2 to "lockdown_vs_mobility")
                    } else if (e0[BURST] >= 3 && (v[PEEL] >= 3 || v[TANK] >= 2)) {
                        score += 2.8
                        reasons.add(2.8 to "anti_burst_peel")
                    }
                }
            }

            if (cand == "Yasuo" && allyHasKnockup) {
                score += 5.0
                reasons.add(5.0 to "knockup_synergy")
            }
            if ("knockup" in tags && "Yasuo" in normAllies) {
                score += 4.5
                reasons.add(4.5 to "combo_with_yasuo")
            }
            if (allyHasHypercarry && normRole == "Support" && v[PEEL] >= 3) {
                score += 4.8
                reasons.add(4.8 to "protect_hypercarry")
            }
            if ("hypercarry" in tags && normAllies.any { it in enchanterAllies }) {
                score += 4.2
                reasons.add(4.2 to "enchanter_hypercarry_combo")
            }

            if (otpAvailable && cand == normOtp) {
                score += 9.0
                reasons.add(9.0 to "otp_priority")
            }

            score += v[BLIND_SAFE] * 0.15 + v[CC] * 0.10

            val topReasons = reasons.sortedByDescending { it.first }.map { it.second }.take(3)
                .ifEmpty { listOf("balanced_meta_pick") }

            scored.add(PickRecommendation(cand, score, info.runes, topReasons))
        }

        scored.sortWith(compareByDescending<PickRecommendation> { it.score }.thenBy { it.name })
        val elapsedMs = (System.nanoTime() - t0) / 1_000_000.0

        return MathDraftResult(
            lang = lang.lowercase().take(2),
            role = normRole,
            draftPhase = detectedPhase,
            myPick = normMyPick ?: "",
            otp = normOtp ?: "",
            otpViable = if (normOtp != null) otpViableInRole else true,
            allies = normAllies,
            enemies = normEnemies,
            bans = normBans,
            exclude = normExclude,
            evaluatedCandidates = candidates.size,
            latencyMs = elapsedMs,
            top3 = scored.take(topK)
        )
    }

    private fun compactRunes(fullRunes: String): String {
        val parts = fullRunes.split("|").map { it.trim() }
        if (parts.size < 3) return fullRunes
        val keystone = parts[0]
        val pList = parts[1].substringAfter(":").split(",").map { it.trim() }.take(2)
        val sec = parts[2].substringAfter(":").trim()
        return "$keystone + ${pList.joinToString(", ")} + $sec"
    }

    /**
     * Renderizador rápido determinístico (< 0.1 ms) en el formato exacto de Drafting.
     * Incluye etiqueta de fase, lectura de bans en First Pick, estrategia por campeón y runas en las 3 opciones.
     */
    fun renderFastTacticalText(res: MathDraftResult): String {
        if (res.top3.isEmpty()) {
            return "PLAN A: Orianna\n• Por qué: Opción estable para ${res.role}."
        }
        val p1 = res.top3[0]
        val enemiesShort = res.enemies.take(2).joinToString(", ").ifEmpty { "el equipo rival" }
        val alliesShort = res.allies.take(2).joinToString(", ").ifEmpty { "tu equipo" }
        val bansShort = res.bans.take(3).joinToString(", ").ifEmpty { "los bans" }

        val phaseTag = when (res.draftPhase) {
            "first_pick" -> "[PRIMER PICK]"
            "last_pick" -> "[ÚLTIMO PICK]"
            "full_locked" -> "[ESTRATEGIA DE PARTIDA]"
            else -> "[MITAD DE DRAFT]"
        }

        fun phraseFor(key: String): String = when (key) {
            "locked_champion_gameplan" -> "con equipos completos en ${res.role}, juega alrededor de tus picos de poder y castiga a $enemiesShort en objetivos"
            "ban_read_tanks_expected" -> "los bans ($bansShort) delatan que el rival teme anti-tanques y buscará frontline pesada"
            "ban_read_mobility_expected" -> "los bloqueos ($bansShort) indican que el rival planea jugar asesinos móviles; tu CC los frenará en seco"
            "ban_read_carries_exposed" -> "al banear asesinos ($bansShort), el rival jugará carries inmóviles que puedes presionar fácil"
            "ban_read_dive_expected" -> "el bloqueo de protectores ($bansShort) anticipa una composición agresiva rival; respondes con supervivencia y control"
            "otp_priority" -> "prioriza tu dominio como OTP en ${res.role}"
            "ap_needed" -> "aporta el daño mágico (AP) que le falta a tu equipo"
            "ad_needed" -> "suma daño físico (AD) clave para equilibrar la composición"
            "frontline_needed" -> "brinda la línea frontal que tu equipo necesita"
            "cc_needed" -> "añade control de masas decisivo en peleas"
            "anti_tank_shred" -> "derrite la línea frontal de tanques rivales ($enemiesShort)"
            "hard_anti_mobility" -> "frena en seco la alta movilidad de $enemiesShort"
            "lockdown_vs_mobility" -> "asegura control puntual sobre enemigos móviles ($enemiesShort)"
            "anti_burst_peel" -> "neutraliza el burst enemigo y protege las peleas"
            "hard_anti_ad" -> "escala armadura y castiga una composición mayormente AD"
            "hard_anti_ap" -> "mitiga el exceso de daño mágico enemigo ($enemiesShort)"
            "anti_cc_shield" -> "anula el exceso de control de masas rival"
            "punish_immobile" -> "castiga a los enemigos sin movilidad ($enemiesShort)"
            "knockup_synergy" -> "combina su definitiva con los levantamientos de $alliesShort"
            "combo_with_yasuo" -> "habilita combos directos con Yasuo aliado"
            "protect_hypercarry" -> "protege y potencia a tu hiper-carry ($alliesShort)"
            "enchanter_hypercarry_combo" -> "escala imparable junto a tu soporte protector ($alliesShort)"
            "safe_blind_pick" -> "es un primer pick muy seguro sin counters duros en ${res.role}"
            else -> "ofrece el perfil más sólido y equilibrado para ${res.role}"
        }

        val mainClauses = p1.reasons.take(2).map { phraseFor(it) }
        var why = if (mainClauses.size >= 2) {
            "$phaseTag ${mainClauses[0].replaceFirstChar { it.uppercase() }} y ${mainClauses[1]}."
        } else {
            "$phaseTag ${mainClauses[0].replaceFirstChar { it.uppercase() }}."
        }
        if (res.otp.isNotEmpty() && !res.otpViable) {
            why = "(Tu OTP ${res.otp} no es viable en ${res.role}). $why"
        }

        val sb = StringBuilder()
        sb.append("PLAN A: ${p1.name}\n")
        sb.append("• Por qué: $why\n")
        sb.append("• Runas: ${p1.runes}.")
        for (alt in res.top3.drop(1)) {
            val altReason = phraseFor(alt.reasons.firstOrNull() ?: "balanced_meta_pick")
                .replaceFirstChar { it.uppercase() }
            val shortRunes = compactRunes(alt.runes)
            sb.append("\n• ${alt.name}: $altReason. Runas: $shortRunes.")
        }
        return sb.toString()
    }
}
