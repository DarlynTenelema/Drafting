"""Generador oficial de encuestas de Trivia 100% Wild Rift (con explicaciones educativas).

Categorías generadas (7 en total):
  1. item_cost   : Reemplazado 100% con objetos reales de backend/json/wr_items.json
  2. build_path  : Preservado del archivo existente (se añaden explicaciones si faltan)
  3. counter     : Reemplazado 100% con counters reales de Wild Rift (wr_coach_kb.json + wr_vectors.json)
  4. power_spike : Nuevo — Early / Mid / Late Game de los 143 campeones de Wild Rift
  5. level_duel  : Nuevo — Duelos 1v1 "¿Quién gana a este nivel?" (curados + vectoriales)
  6. best_rune   : Nuevo — "¿A quién le va mejor esta runa?" (runas clave reales de wr_runes.json)
  7. best_item   : Nuevo — "¿A quién le va mejor este objeto?" (objetos core reales de wr_items.json)
"""
from __future__ import annotations

import json
import random
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WR_ITEMS_PATH = ROOT / "backend" / "json" / "wr_items.json"
WR_RUNES_PATH = ROOT / "backend" / "json" / "wr_runes.json"
WR_KB_PATH = ROOT / "local_ai" / "coach" / "data" / "wr_coach_kb.json"
WR_VECTORS_PATH = ROOT / "local_ai" / "data" / "wr_vectors.json"
TRIVIA_ES_PATH = ROOT / "backend" / "json" / "trivia_questions_es.json"
TRIVIA_DEFAULT_PATH = ROOT / "backend" / "json" / "trivia_questions.json"
TRIVIA_EMBED_ES_PATH = ROOT / "backend" / "golang" / "internal" / "handlers" / "trivia_data" / "trivia_questions_es.json"

MONTH_TAG = "2026-11"
RNG = random.Random(20261127)

POWER_SPIKE_OPTIONS = [
    "Early Game (Niveles 1–5)",
    "Mid Game (1–2 objetos)",
    "Late Game (3+ objetos)",
]

TIER_LABELS = {
    "mejoradas": "Objeto completo",
    "nivel_medio": "Componente de nivel medio",
    "iniciales": "Objeto inicial",
    "basico": "Bota básica",
    "mejorado": "Bota mejorada (Nivel 3)",
}

# Duelos icónicos curados de Wild Rift con explicaciones de alto elo
CURATED_LEVEL_DUELS = [
    ("Darius", "Kayle", "Nivel 1", "Darius",
     "En nivel 1, Darius domina casi cualquier 1v1 cuerpo a cuerpo gracias a las 5 acumulaciones de su pasiva Hemorragia (+AD y sangrado), mientras Kayle es cuerpo a cuerpo y muy frágil antes de evolucionar."),
    ("Darius", "Kayle", "Nivel 15 (Full Build)", "Kayle",
     "A nivel 15 con build completa, Kayle tiene rango máximo, daño verdadero/mágico en área y su definitiva la hace invulnerable, derritiendo a Darius antes de que pueda apilar Hemorragia."),
    ("Renekton", "Nasus", "Nivel 3", "Renekton",
     "En nivel 3, Renekton tiene todo su combo potenciado con Furia (W aturdimiento + Q curación + E doble salto), mientras Nasus aún tiene muy pocas cargas en su Q."),
    ("Renekton", "Nasus", "Nivel 15 (Full Build)", "Nasus",
     "En juego tardío, Nasus supera ampliamente a Renekton en 1v1: su W reduce drásticamente la velocidad de ataque/movimiento, su R le da resistencias y su Q acumulada inflige daño masivo cada 2 segundos."),
    ("Lee Sin", "Amumu", "Nivel 3", "Lee Sin",
     "Lee Sin es uno de los mejores duelistas tempranos de la jungla por su doble set de habilidades y pasiva de velocidad de ataque; Amumu depende de su definitiva y de peleas en equipo."),
    ("Draven", "Jinx", "Nivel 2", "Draven",
     "Las Hachas Giratorias (Q) de Draven multiplican enormemente su daño básico desde nivel 1–2; Jinx necesita 2–3 objetos de crítico para superarlo en DPS."),
    ("Draven", "Vayne", "Nivel 15 (Full Build)", "Vayne",
     "A build completa, Vayne puede reposicionarse con invisibilidad en su R+Q y derretir a Draven con daño verdadero y ataques rápidos antes de recibir 3 hachas."),
    ("Zed", "Aurelion Sol", "Nivel 5 (Definitiva)", "Zed",
     "Al desbloquear Marca de la Muerte (R) en nivel 5, Zed tiene amenaza directa de asesinato sobre Aurelion Sol, quien todavía no ha acumulado suficiente Polvo Estelar ni defensas."),
    ("Zed", "Kassadin", "Nivel 15 (Full Build)", "Kassadin",
     "En nivel 15, Kassadin tiene enfriamiento mínimo en su R (Camino del Vacío), gran daño explosivo y movilidad constante para esquivar los shurikens de Zed y eliminarlo en un combo."),
    ("Olaf", "Mordekaiser", "Nivel 5 (Definitiva)", "Olaf",
     "Con Ragnarok (R), Olaf es inmune al control de adversario (incluso puede cancelar el Reino de la Muerte de Mordekaiser) y su pasiva le da velocidad de ataque y robo de vida brutales al bajar de vida."),
    ("Fiora", "Malphite", "Nivel 13 (3 objetos)", "Fiora",
     "Aunque Malphite acumule armadura, Fiora inflige daño verdadero porcentual por vida máxima con sus puntos vitales y se cura con su definitiva, ganando cualquier duelo extendido en línea lateral."),
    ("Pantheon", "Kassadin", "Nivel 3", "Pantheon",
     "Pantheon tiene uno de los mejores niveles 2–3 del juego con W potenciada + Q ejecutora + E invulnerable frontal; Kassadin es uno de los campeones más débiles en fase temprana."),
    ("Warwick", "Evelynn", "Nivel 3", "Warwick",
     "Warwick gana casi cualquier escaramuza temprana en jungla por su curación constante y reducción de daño en la E; Evelynn carece de camuflaje y burst real antes de nivel 5."),
    ("Caitlyn", "Kog'Maw", "Nivel 1", "Caitlyn",
     "Caitlyn tiene el mayor alcance base en nivel 1 y su pasiva Disparo a la Cabeza castiga cada intercambio; Kog'Maw necesita niveles en su W y objetos de velocidad de ataque para escalar."),
    ("Lucian", "Kai'Sa", "Nivel 2", "Lucian",
     "El combo de habilidad + doble disparo pasivo de Lucian le otorga el burst más fuerte en nivel 2 de Dragon Lane; Kai'Sa aún no tiene evoluciones de habilidades."),
    ("Talon", "Veigar", "Nivel 2", "Talon",
     "Talon puede activar su pasiva de sangrado en nivel 2 (W+Q+ataque) para sacar primera sangre; Veigar en nivel 2 apenas tiene daño y carece de movilidad."),
    ("Jax", "Garen", "Nivel 15 (Full Build)", "Jax",
     "En juego tardío, Contraataque (E) bloquea la Q de Garen, su R le da resistencias híbridas y el daño sostenido de Jax con 3+ objetos supera completamente el burst de Garen."),
    ("Fiora", "Aatrox", "Nivel 13 (3 objetos)", "Fiora",
     "Fiora puede bloquear cualquiera de las Q o la W de Aatrox con Estocada (W) convirtiéndolo en aturdimiento, además de esquivar los bordes dulces con su Q de bajo enfriamiento."),
    ("Sett", "Nasus", "Nivel 1", "Sett",
     "Sett domina el nivel 1 con su doble golpe pasivo y el escudo/daño verdadero de su W (o aturdimiento de E); Nasus no puede intercambiar hasta acumular cargas y comprar brillo."),
    ("Kha'Zix", "Amumu", "Nivel 5 (Definitiva)", "Kha'Zix",
     "En un 1v1 aislado en el río a nivel 5, la pasiva de Aislamiento de Kha'Zix multiplica el daño de su Q y le permite borrar a Amumu antes de que el tanque tenga armadura."),
    ("Xin Zhao", "Maestro Yi", "Nivel 3", "Xin Zhao",
     "En nivel 3, Xin Zhao tiene más daño base, derribo aéreo (Q) y curación constante en duelos cortos; Maestro Yi necesita objetos de impacto y su R escalada para superarlo."),
    ("Xin Zhao", "Maestro Yi", "Nivel 15 (Full Build)", "Maestro Yi",
     "Con build completa, Maestro Yi ignora ralentizaciones con Imparable (R), inflige daño verdadero constante con su E y esquiva el derribo con Golpe Fulgurante (Q)."),
    ("Jayce", "Vladimir", "Nivel 3", "Jayce",
     "En nivel 3, Jayce dispone de 6 habilidades entre forma de cañón y martillo con altísimo daño temprano; Vladimir tiene enfriamientos largos y poca curación en los primeros niveles."),
    ("Jayce", "Vladimir", "Nivel 15 (Full Build)", "Vladimir",
     "En nivel 15, Vladimir se vuelve un monstruo de daño en área, vida adicional y curación masiva con enfriamientos bajísimos, superando por completo el escalado de Jayce."),
    ("Riven", "Kayle", "Nivel 3", "Riven",
     "En nivel 3, Riven cuenta con triple Q, aturdimiento en W y escudo en E para castigar sin respuesta a Kayle, quien no tiene forma de mantener distancia antes de nivel 5."),
    ("Syndra", "Kassadin", "Nivel 3", "Syndra",
     "En niveles tempranos, Syndra abusa de su rango con Q+E para presionar y negar súbditos a Kassadin, quien es cuerpo a cuerpo y aún no tiene su definitiva."),
    ("Kalista", "Jinx", "Nivel 2", "Kalista",
     "Kalista domina el early game con saltos constantes y la acumulación de lanzas de Desgarrar (E), ganando cualquier intercambio prolongado en nivel 2 frente a Jinx."),
    ("Kalista", "Jinx", "Nivel 15 (Full Build)", "Jinx",
     "Con 3+ objetos de crítico, el alcance extra de los cohetes de Jinx y su daño crítico en área superan ampliamente el DPS de Kalista en juego tardío."),
    ("Gwen", "Dr. Mundo", "Nivel 13 (3 objetos)", "Gwen",
     "Gwen derrite tanques de mucha vida como Dr. Mundo gracias al daño mágico porcentual por vida máxima de su pasiva y el daño verdadero central de su Q."),
    ("Mordekaiser", "Malphite", "Nivel 5 (Definitiva)", "Mordekaiser",
     "Mordekaiser inflige daño mágico sostenido con su pasiva y roba estadísticas dentro de su definitiva, anulando la ventaja de armadura de Malphite en 1v1."),
    ("Akshan", "Veigar", "Nivel 2", "Akshan",
     "Akshan tiene un nivel 2 explosivo con doble disparo pasivo, escudo y balanceo (E); Veigar no tiene herramientas para responder a ese daño tan temprano."),
    ("Vayne", "Dr. Mundo", "Nivel 15 (Full Build)", "Vayne",
     "Los Proyectiles de Plata (W) de Vayne infligen daño verdadero porcentual por vida máxima, ignorando toda la vida y armadura acumuladas por Dr. Mundo."),
    ("Irelia", "Aurelion Sol", "Nivel 5 (Definitiva)", "Irelia",
     "Con 4 cargas de pasiva y su definitiva en nivel 5, Irelia cierra la distancia al instante sobre Aurelion Sol y gana el all-in sin dificultad."),
    ("Tryndamere", "Renekton", "Nivel 15 (Full Build)", "Tryndamere",
     "En nivel 15, los 5 segundos de Furia Inmortal (R) junto a 100% de crítico permiten a Tryndamere ganar el 1v1 puro contra Renekton, cuyo poder decae en late game."),
    ("Brand", "Braum", "Nivel 13 (3 objetos)", "Brand",
     "Con Tormento de Liandry y su pasiva de quemadura por vida máxima, Brand derrite la barra de vida de tanques como Braum en peleas prolongadas."),
    ("Kog'Maw", "Caitlyn", "Nivel 15 (Full Build)", "Kog'Maw",
     "A build completa con W activa, Kog'Maw supera el rango y triplica el DPS sostenido de Caitlyn gracias al daño mágico porcentual y efectos de impacto."),
]


def make_id(seed_str: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"drafting-wr-trivia:{seed_str}"))


def normalize_power_spike(raw: str) -> str:
    low = raw.lower()
    if low.startswith("early"):
        return POWER_SPIKE_OPTIONS[0]
    if low.startswith("late"):
        return POWER_SPIKE_OPTIONS[2]
    return POWER_SPIKE_OPTIONS[1]


def build_item_cost_questions(wr_items: dict) -> list[dict]:
    seen: dict[str, dict] = {}
    for cat_name, tiers in wr_items.get("categories", {}).items():
        for tier_key, items in tiers.items():
            for it in items:
                name = it["name"].strip()
                if not name or name in seen:
                    continue
                seen[name] = {
                    "name": name,
                    "cost": int(it["cost"]),
                    "effect": it.get("effect", "").strip(),
                    "category": cat_name,
                    "tier": TIER_LABELS.get(tier_key, tier_key),
                    "active": bool(it.get("active", False)),
                }

    questions = []
    for name, info in sorted(seen.items()):
        active_tag = " • Activo" if info["active"] else ""
        clue = f"{info['category']} • {info['tier']}{active_tag}"
        explanation = (
            f"{name} cuesta {info['cost']} de oro en Wild Rift "
            f"({info['tier']} de {info['category']}). {info['effect']}"
        )
        questions.append({
            "id": make_id(f"item_cost:{name}"),
            "category": "item_cost",
            "game": "wild_rift",
            "question_text": "¿Cuánto vale este objeto?",
            "target_name": name,
            "clues": clue,
            "options": [],
            "correct_answer": str(info["cost"]),
            "explanation": explanation,
            "tolerance": 0,
            "month_tag": MONTH_TAG,
        })
    return questions


def preserve_build_path_questions() -> list[dict]:
    if not TRIVIA_ES_PATH.exists():
        return []
    old = json.loads(TRIVIA_ES_PATH.read_text(encoding="utf-8"))
    kept = []
    for q in old:
        if q.get("category") == "build_path":
            if not q.get("explanation"):
                clues = q.get("clues", "")
                ans = q.get("correct_answer", "")
                q["explanation"] = f"Al combinar {clues} en la tienda se completa {ans}."
            kept.append(q)
    return kept


def build_counter_explanation(target: str, target_info: dict, counter: str, counter_info: dict) -> str:
    c_tags = set(counter_info.get("tags", []))
    t_tags = set(target_info.get("tags", []))
    c_traits = counter_info.get("traits", [])
    t_traits = target_info.get("traits", [])
    t_dmg = target_info.get("damage_type", "")

    if "anti_dash" in c_tags and "alta movilidad" in t_traits:
        return f"{counter} counterea a {target} porque castiga directamente los desplazamientos, frenando su alta movilidad en línea y peleas de equipo."
    if "anti_tank" in c_tags and "aguante/frontline" in t_traits:
        return f"{counter} counterea a {target} porque posee daño especializado para derretir tanques y superar su gran aguante frontal."
    if "anti_cc" in c_tags and ("alto CC" in t_traits or "iniciación fuerte" in t_traits):
        return f"{counter} counterea a {target} porque puede anular o limpiar su control de adversario (CC), quitándole su principal herramienta de iniciación."
    if "anti_ad" in c_tags and "AD" in t_dmg:
        return f"{counter} counterea a {target} porque escala con armadura y reduce fuertemente el impacto del daño físico (AD)."
    if "anti_ap" in c_tags and "AP" in t_dmg:
        return f"{counter} counterea a {target} porque mitiga eficazmente el daño mágico (AP) y castiga los intercambios de magos."
    if c_traits:
        return f"{counter} es un counter fuerte contra {target} en Wild Rift gracias a su perfil de {', '.join(c_traits[:2])}, que neutraliza el plan de juego de {target}."
    return f"{counter} contrarresta el estilo de juego de {target} en Wild Rift y domina los enfrentamientos directos en fase de líneas y peleas."


def build_counter_questions(kb_champs: dict, vectors_data: dict) -> list[dict]:
    all_names = sorted(kb_champs.keys())
    hard_counters = vectors_data.get("hard_counters", {})
    # Mapa inverso: target -> set of hard counters
    hard_countered_by: dict[str, set[str]] = {}
    for c, victims in hard_counters.items():
        for v in victims:
            hard_countered_by.setdefault(v, set()).add(c)

    questions = []
    for target in all_names:
        t_info = kb_champs[target]
        cands = [c for c in t_info.get("countered_by", []) if c in kb_champs and c != target]
        if not cands:
            continue

        # Priorizar un hard counter real si existe
        hc_set = hard_countered_by.get(target, set())
        preferred = [c for c in cands if c in hc_set]
        correct = preferred[0] if preferred else cands[0]

        # Elegir 3 distractores plausibles (preferiblemente de roles similares, nunca counters del objetivo)
        forbidden = set(cands) | hc_set | {target}
        target_roles = set(t_info.get("roles", []))
        same_role_pool = [
            n for n in all_names
            if n not in forbidden and (set(kb_champs[n].get("roles", [])) & target_roles)
        ]
        other_pool = [n for n in all_names if n not in forbidden and n not in same_role_pool]
        RNG.shuffle(same_role_pool)
        RNG.shuffle(other_pool)

        distractors = (same_role_pool[:2] + other_pool[:3])[:3]
        if len(distractors) < 3:
            continue

        options = [correct] + distractors
        RNG.shuffle(options)

        roles_str = " / ".join(t_info.get("roles", []))
        explanation = build_counter_explanation(target, t_info, correct, kb_champs[correct])

        questions.append({
            "id": make_id(f"counter:{target}:{correct}"),
            "category": "counter",
            "game": "wild_rift",
            "question_text": f"¿Cuál es el counter de: {target}?",
            "target_name": target,
            "clues": f"Carril: {roles_str}",
            "options": options,
            "correct_answer": correct,
            "explanation": explanation,
            "tolerance": 0,
            "month_tag": MONTH_TAG,
        })
    return questions


def build_power_spike_questions(kb_champs: dict) -> list[dict]:
    questions = []
    for name, info in sorted(kb_champs.items()):
        raw_spike = info.get("power_spike", "")
        correct = normalize_power_spike(raw_spike)
        roles_str = " / ".join(info.get("roles", []))
        dmg = info.get("damage_type", "")
        core_items = ", ".join(info.get("core_items", [])[:2])
        traits = ", ".join(info.get("traits", [])[:2])

        extra = f" Con objetos como {core_items}" if core_items else ""
        trait_part = f" Destaca por: {traits}." if traits else ""
        explanation = f"{name} ({roles_str}) tiene su pico principal en {correct}: {raw_spike}.{extra} maximiza su impacto en la partida.{trait_part}"

        questions.append({
            "id": make_id(f"power_spike:{name}"),
            "category": "power_spike",
            "game": "wild_rift",
            "question_text": f"¿Cuál es el power spike de: {name}?",
            "target_name": name,
            "clues": f"{roles_str} • {dmg}",
            "options": list(POWER_SPIKE_OPTIONS),
            "correct_answer": correct,
            "explanation": explanation,
            "tolerance": 0,
            "month_tag": MONTH_TAG,
        })
    return questions


def build_level_duel_questions(kb_champs: dict, vectors_data: dict) -> list[dict]:
    questions = []
    seen_keys: set[str] = set()

    # 1. Duelos curados de alta precisión
    for a, b, level_label, winner, explanation in CURATED_LEVEL_DUELS:
        if a not in kb_champs or b not in kb_champs:
            continue
        key = f"{a}:{b}:{level_label}"
        seen_keys.add(key)
        opts = [a, b]
        RNG.shuffle(opts)
        questions.append({
            "id": make_id(f"level_duel:{key}"),
            "category": "level_duel",
            "game": "wild_rift",
            "question_text": "¿Quién gana a este nivel?",
            "target_name": f"{a} vs {b}",
            "clues": level_label,
            "options": opts,
            "correct_answer": winner,
            "explanation": explanation,
            "tolerance": 0,
            "month_tag": MONTH_TAG,
        })

    # 2. Duelos adicionales por carril usando early_lane (dim 11) vs late_scaling (dim 12)
    vec_champs = vectors_data.get("champions", {})
    lanes = vectors_data.get("lanes", {})
    for lane in ["Baron", "Mid", "Dragon", "Jungle"]:
        members = [c for c in lanes.get(lane, []) if c in vec_champs and c in kb_champs]
        early_bullies = [c for c in members if vec_champs[c]["vec"][11] >= 3 and vec_champs[c]["vec"][12] <= 2]
        late_scalers = [c for c in members if vec_champs[c]["vec"][12] >= 3 and vec_champs[c]["vec"][11] <= 1]

        pairs = [(e, l) for e in early_bullies for l in late_scalers if e != l]
        RNG.shuffle(pairs)

        added_for_lane = 0
        for early_c, late_c in pairs:
            if added_for_lane >= 16:
                break
            # Alternar entre duelo temprano (Nivel 2-3) y duelo tardío (Nivel 15)
            if added_for_lane % 2 == 0:
                lvl = "Nivel 2" if lane == "Dragon" else "Nivel 3"
                winner = early_c
                expl = (
                    f"En {lvl} ({lane}), {early_c} tiene clara ventaja de daño base y presión temprana "
                    f"frente a {late_c}, que necesita 2–3 objetos completos para despertar su escalado."
                )
            else:
                lvl = "Nivel 15 (Full Build)"
                winner = late_c
                expl = (
                    f"En {lvl} ({lane}), {late_c} supera en escalado y DPS sostenido a {early_c}, "
                    f"quien depende de sacar ventaja en los primeros minutos de la partida."
                )

            key = f"{early_c}:{late_c}:{lvl}"
            rev_key = f"{late_c}:{early_c}:{lvl}"
            if key in seen_keys or rev_key in seen_keys:
                continue
            seen_keys.add(key)

            opts = [early_c, late_c]
            RNG.shuffle(opts)
            questions.append({
                "id": make_id(f"level_duel:{key}"),
                "category": "level_duel",
                "game": "wild_rift",
                "question_text": "¿Quién gana a este nivel?",
                "target_name": f"{opts[0]} vs {opts[1]}",
                "clues": lvl,
                "options": opts,
                "correct_answer": winner,
                "explanation": expl,
                "tolerance": 0,
                "month_tag": MONTH_TAG,
            })
            added_for_lane += 1

    return questions


def build_best_rune_questions(wr_runes: dict, kb_champs: dict) -> list[dict]:
    keystone_meta = {k["name"]: k for k in wr_runes.get("keystones", [])}
    keystone_users: dict[str, list[str]] = {}
    champ_keystone: dict[str, str] = {}

    for champ, info in kb_champs.items():
        raw_runes = info.get("core_runes", "")
        ks = raw_runes.split("|")[0].strip()
        if ks in keystone_meta:
            keystone_users.setdefault(ks, []).append(champ)
            champ_keystone[champ] = ks

    all_champs = sorted(champ_keystone.keys())
    questions = []

    for ks_name, users in sorted(keystone_meta.items()):
        matching = list(keystone_users.get(ks_name, []))
        if not matching:
            continue
        RNG.shuffle(matching)
        # Hasta 10 preguntas distintas por runa clave para buena variedad
        selected_users = matching[:10]
        non_users = [c for c in all_champs if champ_keystone.get(c) != ks_name]

        meta = keystone_meta[ks_name]
        cat = meta.get("category", "")
        effect = meta.get("effect", "")

        for correct in selected_users:
            RNG.shuffle(non_users)
            # Evitar distractores con roles/daño casi idénticos que también podrían llevarla situacionalmente
            c_roles = set(kb_champs[correct].get("roles", []))
            c_dmg = kb_champs[correct].get("damage_type", "")
            strict_dist = [
                c for c in non_users
                if kb_champs[c].get("damage_type", "") != c_dmg or not (set(kb_champs[c].get("roles", [])) & c_roles)
            ]
            distractors = (strict_dist[:3] if len(strict_dist) >= 3 else non_users[:3])
            if len(distractors) < 3:
                continue

            options = [correct] + distractors
            RNG.shuffle(options)

            roles_str = " / ".join(kb_champs[correct].get("roles", []))
            explanation = (
                f"{ks_name} ({cat}) es la runa clave ideal para {correct} ({roles_str}): "
                f"{effect} Su página core completa suele ser: {kb_champs[correct].get('core_runes', '')}."
            )

            questions.append({
                "id": make_id(f"best_rune:{ks_name}:{correct}"),
                "category": "best_rune",
                "game": "wild_rift",
                "question_text": "¿A quién le va mejor esta runa?",
                "target_name": ks_name,
                "clues": f"Runa Clave • {cat}",
                "options": options,
                "correct_answer": correct,
                "explanation": explanation,
                "tolerance": 0,
                "month_tag": MONTH_TAG,
            })

    return questions


def build_best_item_questions(wr_items: dict, kb_champs: dict) -> list[dict]:
    item_meta: dict[str, dict] = {}
    for cat_name, tiers in wr_items.get("categories", {}).items():
        for tier_key, items in tiers.items():
            for it in items:
                name = it["name"].strip()
                if name not in item_meta:
                    item_meta[name] = {
                        "cost": int(it["cost"]),
                        "effect": it.get("effect", "").strip(),
                        "category": cat_name,
                    }

    item_users: dict[str, list[str]] = {}
    for champ, info in kb_champs.items():
        for it in info.get("core_items", []):
            if it in item_meta:
                item_users.setdefault(it, []).append(champ)

    all_champs = sorted(kb_champs.keys())
    questions = []

    for item_name, users in sorted(item_users.items()):
        users_set = set(users)
        pool_users = list(users)
        RNG.shuffle(pool_users)
        # Hasta 5 preguntas por objeto para variedad sin repetir demasiado
        chosen_users = pool_users[:5]
        meta = item_meta[item_name]

        for correct in chosen_users:
            c_dmg = kb_champs[correct].get("damage_type", "")
            # Distractores que NO tengan este objeto ni el mismo tipo de daño (hace la respuesta inequívoca)
            diff_dmg = [
                c for c in all_champs
                if c not in users_set and kb_champs[c].get("damage_type", "") != c_dmg
            ]
            fallback = [c for c in all_champs if c not in users_set and c not in diff_dmg]
            RNG.shuffle(diff_dmg)
            RNG.shuffle(fallback)

            distractors = (diff_dmg[:3] + fallback[:3])[:3]
            if len(distractors) < 3:
                continue

            options = [correct] + distractors
            RNG.shuffle(options)

            roles_str = " / ".join(kb_champs[correct].get("roles", []))
            explanation = (
                f"{item_name} ({meta['cost']} de oro) es un objeto núcleo para {correct} ({roles_str} • {c_dmg}). "
                f"Efecto: {meta['effect']}"
            )

            questions.append({
                "id": make_id(f"best_item:{item_name}:{correct}"),
                "category": "best_item",
                "game": "wild_rift",
                "question_text": "¿A quién le va mejor este objeto?",
                "target_name": item_name,
                "clues": f"{meta['category']} • {meta['cost']} de oro",
                "options": options,
                "correct_answer": correct,
                "explanation": explanation,
                "tolerance": 0,
                "month_tag": MONTH_TAG,
            })

    return questions


def main() -> None:
    wr_items = json.loads(WR_ITEMS_PATH.read_text(encoding="utf-8"))
    wr_runes = json.loads(WR_RUNES_PATH.read_text(encoding="utf-8"))
    wr_kb = json.loads(WR_KB_PATH.read_text(encoding="utf-8"))
    wr_vectors = json.loads(WR_VECTORS_PATH.read_text(encoding="utf-8"))
    kb_champs = wr_kb["champions"]

    q_item_cost = build_item_cost_questions(wr_items)
    q_build_path = preserve_build_path_questions()
    q_counter = build_counter_questions(kb_champs, wr_vectors)
    q_power_spike = build_power_spike_questions(kb_champs)
    q_level_duel = build_level_duel_questions(kb_champs, wr_vectors)
    q_best_rune = build_best_rune_questions(wr_runes, kb_champs)
    q_best_item = build_best_item_questions(wr_items, kb_champs)

    all_questions = (
        q_item_cost
        + q_build_path
        + q_counter
        + q_power_spike
        + q_level_duel
        + q_best_rune
        + q_best_item
    )

    payload = json.dumps(all_questions, ensure_ascii=False, indent=2)
    TRIVIA_ES_PATH.write_text(payload, encoding="utf-8")
    TRIVIA_DEFAULT_PATH.write_text(payload, encoding="utf-8")
    TRIVIA_EMBED_ES_PATH.parent.mkdir(parents=True, exist_ok=True)
    TRIVIA_EMBED_ES_PATH.write_text(payload, encoding="utf-8")

    print("Resumen del nuevo dataset de Trivia Wild Rift (ES):")
    print(f"  - item_cost   : {len(q_item_cost)}")
    print(f"  - build_path  : {len(q_build_path)} (preservadas)")
    print(f"  - counter     : {len(q_counter)}")
    print(f"  - power_spike : {len(q_power_spike)}")
    print(f"  - level_duel  : {len(q_level_duel)}")
    print(f"  - best_rune   : {len(q_best_rune)}")
    print(f"  - best_item   : {len(q_best_item)}")
    print(f"  TOTAL         : {len(all_questions)} preguntas guardadas en {TRIVIA_ES_PATH.name}")


if __name__ == "__main__":
    main()
