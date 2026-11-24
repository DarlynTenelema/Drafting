"""
Tarea 1.1 — Generador de Dataset Sintético de Wild Rift para Fine-Tuning QLoRA.

Genera ejemplos en formato ChatML JSONL compatibles con Unsloth / Axolotl / TRL:
  - local_ai/data/wr_draft_train.jsonl (2,300 ejemplos)
  - local_ai/data/wr_draft_val.jsonl   (200 ejemplos)

Cada ejemplo usa DraftMathEngine (poda por rol + vectores de 143 campeones) como fuente
de verdad táctica para garantizar 0% alucinaciones de campeones/runas.
"""

from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

from draft_math_engine import DraftMathEngine

ROOT = Path(__file__).resolve().parent.parent
CHAMPS_PATH = ROOT / "backend" / "json" / "wr_champions.json"
TRAIN_OUT = ROOT / "local_ai" / "data" / "wr_draft_train.jsonl"
VAL_OUT = ROOT / "local_ai" / "data" / "wr_draft_val.jsonl"

SYSTEM_PROMPT = (
    "Eres Drafting Local, analista táctico de Wild Rift. "
    "Recibes un JSON con el estado del draft y el Top 3 calculado. "
    "Responde SIN saludos ni asteriscos (**), de forma concisa (máx. 140 tokens), usando EXACTAMENTE este formato:\n"
    "PLAN A: [Campeón 1]\n"
    "• Por qué: [Razón táctica breve y directa]\n"
    "• Runas: [Runas exactas del JSON]\n"
    "• [Campeón 2]: [Por qué encaja en 1 línea]\n"
    "• [Campeón 3]: [Por qué encaja en 1 línea]"
)

REASON_PHRASES_MAIN = {
    "locked_champion_gameplan": [
        "con equipos completos en {role}, juega alrededor de tus picos de poder y castiga a {enemies_short} en objetivos",
        "draft cerrado en {role}: prioriza posicionamiento en 5v5, controla visión y enfoca tu combo sobre {enemies_short}",
        "partida lista en {role}: mantén presión de oleadas y coordina iniciaciones contra {enemies_short}",
    ],
    "ban_read_tanks_expected": [
        "los bans ({bans_short}) delatan que el rival teme anti-tanques y buscará frontline pesada",
        "al bloquear ({bans_short}), el enemigo prepara tanques; este pick los castiga desde el inicio",
    ],
    "ban_read_mobility_expected": [
        "los bloqueos ({bans_short}) indican que el rival planea jugar asesinos móviles; tu CC los frenará en seco",
        "el enemigo baneó control ({bans_short}) para entrar con movilidad; aquí los neutralizas por completo",
    ],
    "ban_read_carries_exposed": [
        "al banear asesinos ({bans_short}), el rival jugará carries inmóviles que puedes presionar y alcanzar fácil",
        "los bans ({bans_short}) dejan libres a tus iniciaciones contra posibles magos o tiradores sin escape",
    ],
    "ban_read_dive_expected": [
        "el bloqueo de protectores ({bans_short}) anticipa una composición agresiva rival; respondes con supervivencia y control",
        "los bans ({bans_short}) muestran intención de dive enemigo; este campeón aguanta y contragolpea con ventaja",
    ],
    "otp_priority": [
        "es tu OTP viable en {role} y te permite carrear con comodidad",
        "prioriza tu dominio como OTP en {role} sin comprometer el draft",
        "tu OTP encaja perfecto en {role} y maximiza tu impacto",
    ],
    "ap_needed": [
        "aporta el daño mágico (AP) que le falta a tu equipo",
        "evita que el rival acumule armadura al sumar daño AP clave",
        "equilibra el daño mágico de la composición",
    ],
    "ad_needed": [
        "suma daño físico (AD) necesario para equilibrar la composición",
        "castiga la resistencia mágica rival aportando daño AD constante",
        "cubre la falta de daño físico de tus aliados",
    ],
    "frontline_needed": [
        "brinda la línea frontal que tu equipo necesita en peleas",
        "absorbe el daño inicial y da espacio a tus carries",
        "cubre la falta de aguante y resistencia en el equipo",
    ],
    "cc_needed": [
        "añade control de masas decisivo para asegurar eliminaciones",
        "aporta el CC duro que le falta a tu composición",
        "bloquea objetivos clave en peleas de equipo",
    ],
    "anti_tank_shred": [
        "derrite la línea frontal de tanques del rival ({enemies_short})",
        "destruye tanques enemigos con daño sostenido y porcentual",
        "rompe fácilmente a los tanques rivales en peleas largas",
    ],
    "hard_anti_mobility": [
        "frena en seco los desplazamientos de {enemies_short}",
        "castiga directamente la alta movilidad enemiga con control",
        "corta los saltos e iniciaciones rivales en seco",
    ],
    "lockdown_vs_mobility": [
        "inmoviliza a los enemigos móviles ({enemies_short}) antes de que escapen",
        "asegura control puntual sobre la movilidad rival",
        "detiene las entradas rápidas del equipo enemigo",
    ],
    "anti_burst_peel": [
        "neutraliza el daño explosivo enemigo y protege las peleas",
        "aguanta el burst rival y evita que borren a tu equipo",
        "corta la ráfaga asesina de {enemies_short}",
    ],
    "hard_anti_ad": [
        "domina por completo contra una composición mayormente AD",
        "escala armadura y castiga el exceso de daño físico rival",
        "anula el daño físico enemigo durante toda la partida",
    ],
    "hard_anti_ap": [
        "mitiga el daño mágico enemigo y domina los intercambios AP",
        "anula el exceso de magos rivales en línea y peleas",
        "resiste el daño AP de {enemies_short} sin problemas",
    ],
    "anti_cc_shield": [
        "anula el exceso de control de masas enemigo",
        "ignora o limpia el CC rival para pelear libremente",
        "contrarresta las cadenas de aturdimiento de {enemies_short}",
    ],
    "punish_immobile": [
        "castiga sin piedad a los enemigos sin movilidad ({enemies_short})",
        "aprovecha la poca movilidad rival para iniciar y eliminar",
        "abusa de objetivos inmóviles en peleas por objetivos",
    ],
    "knockup_synergy": [
        "combina su definitiva con los levantamientos de tus aliados ({allies_short})",
        "aprovecha los derribos aéreos aliados para combos devastadores",
    ],
    "combo_with_yasuo": [
        "habilita directamente la definitiva de Yasuo aliado con levantamiento",
        "crea un combo letal en área junto a Yasuo",
    ],
    "protect_hypercarry": [
        "protege y potencia a tu hiper-carry aliado ({allies_short})",
        "mantiene vivo a tu carry para ganar cualquier pelea tardía",
    ],
    "enchanter_hypercarry_combo": [
        "escala de forma imparable con el soporte protector aliado ({allies_short})",
        "aprovecha los escudos y peel aliado para arrasar en peleas",
    ],
    "safe_blind_pick": [
        "es un primer pick muy seguro sin counters duros en {role}",
        "garantiza fase de líneas estable incluso eligiendo a ciegas",
        "se adapta a cualquier composición rival desde el primer pick",
    ],
    "balanced_meta_pick": [
        "ofrece el perfil más sólido y consistente para {role} en este draft",
        "mantiene presión constante y buena presencia en peleas de equipo",
        "encaja de forma equilibrada frente a las opciones disponibles",
    ],
}

REASON_PHRASES_ALT = {
    "locked_champion_gameplan": "Plan alternativo de línea y peleas 5v5 en {role}",
    "ban_read_tanks_expected": "Castiga la probable frontline rival deducida por los bans",
    "ban_read_mobility_expected": "Frena a los asesinos móviles que anticipan los bloqueos",
    "ban_read_carries_exposed": "Presiona a carries rivales sin escape tras los bans",
    "ban_read_dive_expected": "Resiste el all-in enemigo que delatan los bloqueos",
    "otp_priority": "Tu OTP viable en {role} para maximizar dominio mecánico",
    "ap_needed": "Alternativa AP sólida para balancear el daño del equipo",
    "ad_needed": "Aporta daño físico clave y presión constante en {role}",
    "frontline_needed": "Suma aguante y línea frontal para aguantar las peleas",
    "cc_needed": "Agrega control de masas confiable para iniciar o proteger",
    "anti_tank_shred": "Excelente opción para derretir a los tanques rivales",
    "hard_anti_mobility": "Castiga directamente los saltos y movilidad del rival",
    "lockdown_vs_mobility": "Control puntual muy efectivo contra enemigos ágiles",
    "anti_burst_peel": "Resiste el burst enemigo y da seguridad en peleas",
    "hard_anti_ad": "Muy fuerte escalando armadura contra tanto daño AD",
    "hard_anti_ap": "Neutraliza el daño mágico enemigo en línea y 5v5",
    "anti_cc_shield": "Te protege frente al exceso de CC de la composición rival",
    "punish_immobile": "Fácil acceso para castigar a rivales sin movilidad",
    "knockup_synergy": "Gran sinergia con los levantamientos de tu equipo",
    "combo_with_yasuo": "Habilita combos directos con Yasuo aliado",
    "protect_hypercarry": "Gran protección para que tu carry domine la partida",
    "enchanter_hypercarry_combo": "Combina perfecto con tu soporte para carrear",
    "safe_blind_pick": "Primer pick blindado si aún faltan rivales por salir",
    "balanced_meta_pick": "Opción muy estable y versátil para dominar {role}",
}

PHASE_LABELS = {
    "first_pick": "[PRIMER PICK]",
    "mid_draft": "[MITAD DE DRAFT]",
    "last_pick": "[ÚLTIMO PICK]",
    "full_locked": "[ESTRATEGIA DE PARTIDA]",
}


def compact_runes(full_runes: str) -> str:
    """Resume una página de runas para las opciones 2 y 3 sin perder la clave ni las ramas."""
    parts = [p.strip() for p in full_runes.split("|")]
    if len(parts) < 3:
        return full_runes
    keystone = parts[0]
    p_list = [x.strip() for x in parts[1].split(":", 1)[-1].split(",")]
    sec = parts[2].split(":", 1)[-1].strip()
    return f"{keystone} + {', '.join(p_list[:2])} + {sec}"


def sample_realistic_draft(engine: DraftMathEngine, rng: random.Random, role: str) -> dict:
    all_champs = list(engine.champions.keys())
    used: set[str] = set()

    # 0 a 10 bans (15% pocos bans 1..4, 85% bans completos 5..10)
    if rng.random() < 0.15:
        n_bans = rng.randint(1, 4)
    else:
        n_bans = rng.randint(5, 10)
    bans = rng.sample(all_champs, n_bans)
    used.update(bans)

    # Etapa del draft:
    # 22% First Pick (0 enemigos, lectura de bans),
    # 40% Mid-Draft (1..3 enemigos),
    # 23% Last Pick (4..5 enemigos, counter letal),
    # 15% Full Locked / 2da Foto (equipos completos y campeón propio ya elegido)
    stage_roll = rng.random()
    my_pick = ""
    if stage_roll < 0.22:
        draft_phase = "first_pick"
        n_allies = rng.randint(0, 1)
        n_enemies = 0
    elif stage_roll < 0.62:
        draft_phase = "mid_draft"
        n_allies = rng.randint(1, 3)
        n_enemies = rng.randint(1, 3)
    elif stage_roll < 0.85:
        draft_phase = "last_pick"
        n_allies = rng.randint(3, 4)
        n_enemies = rng.randint(4, 5)
    else:
        draft_phase = "full_locked"
        n_allies = 4
        n_enemies = 5
        lane_pool_init = [c for c in engine.lanes[role] if c not in used]
        if lane_pool_init:
            my_pick = rng.choice(lane_pool_init)
            used.add(my_pick)

    other_roles = [r for r in ["Baron", "Jungle", "Mid", "Dragon", "Support"] if r != role]
    rng.shuffle(other_roles)

    allies: list[str] = []
    for r in other_roles[:n_allies]:
        pool = [c for c in engine.lanes[r] if c not in used]
        if pool:
            pick = rng.choice(pool)
            allies.append(pick)
            used.add(pick)

    enemy_roles = ["Baron", "Jungle", "Mid", "Dragon", "Support"]
    rng.shuffle(enemy_roles)
    enemies: list[str] = []
    for r in enemy_roles[:n_enemies]:
        pool = [c for c in engine.lanes[r] if c not in used]
        if pool:
            pick = rng.choice(pool)
            enemies.append(pick)
            used.add(pick)

    # OTP: 15% viable en el rol, 10% autofill (no viable), 75% sin OTP
    otp = ""
    otp_roll = rng.random()
    if not my_pick and otp_roll < 0.15:
        lane_avail = [c for c in engine.lanes[role] if c not in used]
        if lane_avail:
            otp = rng.choice(lane_avail)
    elif not my_pick and otp_roll < 0.25:
        non_lane = [c for c in all_champs if c not in engine.lanes[role] and c not in used]
        if non_lane:
            otp = rng.choice(non_lane)

    # Reconsulta (exclude): 15% de los casos (cuando aún no ha lockeado)
    exclude: list[str] = []
    if not my_pick and rng.random() < 0.15:
        first_pass = engine.recommend(
            role=role, bans=bans, allies=allies, enemies=enemies, otp=otp, draft_phase=draft_phase
        )
        exclude = [p["name"] for p in first_pass["top3"]]

    return {
        "role": role,
        "draft_phase": draft_phase,
        "my_pick": my_pick,
        "bans": bans,
        "allies": allies,
        "enemies": enemies,
        "otp": otp,
        "exclude": exclude,
    }


def format_assistant_response(
    result: dict,
    rng: random.Random,
    style_hints: dict[str, str],
) -> str:
    top3 = result["top3"]
    p1, p2, p3 = top3[0], top3[1], top3[2]

    role = result["role"]
    phase = result.get("draft_phase", "mid_draft")
    phase_tag = PHASE_LABELS.get(phase, "[MITAD DE DRAFT]")
    enemies_short = ", ".join(result["enemies"][:2]) if result["enemies"] else "el equipo rival"
    allies_short = ", ".join(result["allies"][:2]) if result["allies"] else "tu equipo"
    bans_short = ", ".join(result["bans"][:3]) if result["bans"] else "los bans"

    fmt_vars = {
        "role": role,
        "enemies_short": enemies_short,
        "allies_short": allies_short,
        "bans_short": bans_short,
    }

    r1_keys = p1["reasons"][:2]
    clauses = []
    for rk in r1_keys:
        templates = REASON_PHRASES_MAIN.get(rk, REASON_PHRASES_MAIN["balanced_meta_pick"])
        clauses.append(rng.choice(templates).format(**fmt_vars))

    if len(clauses) == 2:
        why_body = f"{phase_tag} {clauses[0][0].upper() + clauses[0][1:]} y {clauses[1]}."
    else:
        why_body = f"{phase_tag} {clauses[0][0].upper() + clauses[0][1:]}."

    if result["otp"] and not result["otp_viable"]:
        why_body = f"(Tu OTP {result['otp']} no es viable en {role}). {why_body}"

    def alt_line(pick: dict) -> str:
        rk = pick["reasons"][0]
        strat = REASON_PHRASES_ALT.get(rk, REASON_PHRASES_ALT["balanced_meta_pick"]).format(**fmt_vars)
        short_r = compact_runes(pick["runes"])
        return f"{strat}. Runas: {short_r}."

    lines = [
        f"PLAN A: {p1['name']}",
        f"• Por qué: {why_body}",
        f"• Runas: {p1['runes']}.",
        f"• {p2['name']}: {alt_line(p2)}",
        f"• {p3['name']}: {alt_line(p3)}",
    ]
    return "\n".join(lines)


def build_user_payload(result: dict, exclude: list[str]) -> str:
    compact = {
        "lang": "es",
        "role": result["role"],
        "draft_phase": result.get("draft_phase", "mid_draft"),
        "my_pick": result.get("my_pick", ""),
        "otp": result["otp"],
        "otp_viable": result["otp_viable"],
        "allies": result["allies"],
        "enemies": result["enemies"],
        "bans": result["bans"],
        "exclude": exclude,
        "top3": [
            {
                "name": p["name"],
                "runes": p["runes"],
                "reasons": p["reasons"],
            }
            for p in result["top3"]
        ],
    }
    return json.dumps(compact, ensure_ascii=False, separators=(",", ":"))


def generate_dataset(total: int = 2500, val_size: int = 200, seed: int = 42) -> None:
    rng = random.Random(seed)
    engine = DraftMathEngine()
    champs_raw = json.loads(CHAMPS_PATH.read_text(encoding="utf-8"))
    style_hints = {c["name"]: c["style"] for c in champs_raw["champions"]}

    roles = ["Baron", "Jungle", "Mid", "Dragon", "Support"]
    records: list[dict] = []

    for i in range(total):
        role = roles[i % len(roles)]
        draft = sample_realistic_draft(engine, rng, role)
        res = engine.recommend(
            role=draft["role"],
            bans=draft["bans"],
            allies=draft["allies"],
            enemies=draft["enemies"],
            otp=draft["otp"],
            my_pick=draft["my_pick"],
            draft_phase=draft["draft_phase"],
            exclude=draft["exclude"],
        )
        if len(res["top3"]) < 3:
            continue

        user_json = build_user_payload(res, draft["exclude"])
        assistant_text = format_assistant_response(res, rng, style_hints)

        records.append({
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_json},
                {"role": "assistant", "content": assistant_text},
            ]
        })

    rng.shuffle(records)
    val_records = records[:val_size]
    train_records = records[val_size:]

    TRAIN_OUT.parent.mkdir(parents=True, exist_ok=True)
    with TRAIN_OUT.open("w", encoding="utf-8") as f:
        for r in train_records:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    with VAL_OUT.open("w", encoding="utf-8") as f:
        for r in val_records:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    print(f"OK: Dataset generado -> train={len(train_records)} ({TRAIN_OUT.stat().st_size/1024:.1f} KB), val={len(val_records)} ({VAL_OUT.stat().st_size/1024:.1f} KB)")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--total", type=int, default=2500)
    parser.add_argument("--val", type=int, default=200)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()
    generate_dataset(total=args.total, val_size=args.val, seed=args.seed)


if __name__ == "__main__":
    main()
