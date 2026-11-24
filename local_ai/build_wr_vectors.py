"""
Construye la base matemática compacta (wr_vectors.json) para los 143 campeones de Wild Rift
a partir de backend/json/wr_champions.json y backend/json/wr_runes.json.

Cada campeón recibe:
- roles: lista de líneas oficiales en Wild Rift
- vec: vector de 10 atributos [0..3]:
  [ad, ap, tank, cc, engage, peel, mobility, burst, anti_tank, blind_safe]
- tags: etiquetas tácticas ligeras (ej. knockup, hypercarry, anti_ap, anti_ad, anti_dash, anti_heal_needed)
- runes: página de runas 100% válida según backend/json/wr_runes.json
"""

from __future__ import annotations

import json
import re
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHAMPS_PATH = ROOT / "backend" / "json" / "wr_champions.json"
RUNES_PATH = ROOT / "backend" / "json" / "wr_runes.json"
OUT_PATH = ROOT / "local_ai" / "data" / "wr_vectors.json"

DIMS = [
    "ad",
    "ap",
    "tank",
    "cc",
    "engage",
    "peel",
    "mobility",
    "burst",
    "anti_tank",
    "blind_safe",
]

# Plantillas de runas 100% verificadas contra backend/json/wr_runes.json
# Formato: 1 Clave + 3 Rama Principal + 1 Secundaria
RUNE_PROFILES = {
    "fighter_ad": "Conquistador | Precisión: Triunfo, Último esfuerzo, Leyenda: Presteza | Valor: Revestimiento de huesos",
    "fighter_ap": "Conquistador | Precisión: Triunfo, Último esfuerzo, Leyenda: Velocidad | Valor: Revestimiento de huesos",
    "tank_engage": "Soberano gélido | Valor: Coraje del coloso, Revestimiento de huesos, Sobrecrecimiento | Inspiración: Trascendencia",
    "tank_top": "Garras del inmortal | Valor: Demoler, Fuerzas renovadas, Sobrecrecimiento | Precisión: Triunfo",
    "assassin_ad": "Electrocutar | Dominación: Impacto repentino, Tirano, Colección de globos oculares | Valor: Revestimiento de huesos",
    "assassin_ap": "Electrocutar | Dominación: Impacto repentino, Tirano, Colección de globos oculares | Inspiración: Trascendencia",
    "mage_burst": "Electrocutar | Dominación: Golpe bajo, Asalto encadenado, Colección de globos oculares | Inspiración: Banda de maná",
    "mage_poke": "Cometa arcano | Inspiración: Banda de maná, Trascendencia, Piroláser | Dominación: Golpe bajo",
    "mage_control": "Irrupción de fase | Inspiración: Banda de maná, Trascendencia, Se avecina tormenta | Valor: Revestimiento de huesos",
    "adc_dps": "Compás letal | Precisión: Brutal, Derribado, Leyenda: Presteza | Valor: Orbe anulador",
    "adc_burst": "Fortalecimiento | Precisión: Brutal, Golpe de gracia, Leyenda: Linaje | Valor: Revestimiento de huesos",
    "adc_fleet": "Pies veloces | Precisión: Brutal, Golpe de gracia, Leyenda: Linaje | Valor: Orbe anulador",
    "adc_poke": "Primer golpe | Inspiración: Banda de maná, Trascendencia, Piroláser | Precisión: Golpe de gracia",
    "enchanter": "Aery | Inspiración: Banda de maná, Trascendencia, Piroláser | Valor: Revitalizar",
    "warden": "Guardián | Valor: Fuente de vida, Revestimiento de huesos, Revitalizar | Inspiración: Trascendencia",
}

# Overrides curados para el meta real de Wild Rift (100% runas de wr_runes.json)
CHAMPION_RUNE_OVERRIDES = {
    # Auto-attackers / Crit / On-hit melee y tiradores
    "Yasuo": "adc_dps",
    "Yone": "adc_dps",
    "Maestro Yi": "adc_dps",
    "Tryndamere": "adc_dps",
    "Kayle": "adc_dps",
    "Nocturne": "adc_dps",
    "Kindred": "adc_dps",
    "Varus": "adc_dps",
    # Usuarios de Pies veloces en Wild Rift
    "Jhin": "adc_fleet",
    "Senna": "adc_fleet",
    "Graves": "adc_fleet",
    "Twisted Fate": "adc_fleet",
    # Usuarios de Fortalecimiento / Conquistador específicos
    "Samira": "fighter_ad",
    "Aatrox": "fighter_ad",
    "Fiora": "fighter_ad",
    "Sett": "fighter_ad",
    "Pantheon": "fighter_ad",
    "Akshan": "adc_burst",
    "Teemo": "adc_burst",
    # Magos de desgaste / batalla / AP luchadores
    "Brand": "mage_poke",
    "Vel'Koz": "mage_poke",
    "Lillia": "fighter_ap",
    "Swain": "fighter_ap",
    "Gwen": "fighter_ap",
    "Mordekaiser": "fighter_ap",
    "Sylas": "fighter_ap",
    "Vladimir": "mage_control",
    "Singed": "mage_control",
    "Nidalee": "assassin_ap",
    "Jayce": "adc_poke",
    "Miss Fortune": "adc_poke",
    # Tanques top puros
    "Malphite": "tank_top",
    "Ornn": "tank_top",
    "Sion": "tank_top",
}

# Etiquetas tácticas curadas para sinergias y counters de alto impacto en Wild Rift
KNOCKUP_CHAMPS = {
    "Alistar", "Blitzcrank", "Braum", "Cho'Gath", "Diana", "Galio", "Gnar", "Gragas",
    "Janna", "Jarvan IV", "Lee Sin", "Malphite", "Nami", "Nautilus", "Orianna",
    "Ornn", "Poppy", "Rakan", "Rell", "Sett", "Sion", "Thresh", "Vi", "Wukong",
    "Xin Zhao", "Yasuo", "Yone", "Zyra",
}

HYPERCARRY_CHAMPS = {
    "Jinx", "Kai'Sa", "Kog'Maw", "Twitch", "Vayne", "Zeri", "Tristana", "Smolder",
    "Kayle", "Maestro Yi", "Nilah", "Yunara",
}

HIGH_MOBILITY_CHAMPS = {
    "Ahri", "Akali", "Ambessa", "Aurora", "Camille", "Diana", "Ekko", "Ezreal",
    "Fiora", "Fizz", "Gwen", "Hecarim", "Irelia", "Jarvan IV", "Kai'Sa", "Kalista",
    "Kassadin", "Katarina", "Kayn", "Kha'Zix", "Kindred", "Lee Sin", "Lillia",
    "Lucian", "Nidalee", "Pyke", "Rakan", "Renekton", "Rengar", "Riven", "Samira",
    "Talon", "Tristana", "Tryndamere", "Vayne", "Vi", "Viego", "Wukong", "Yasuo",
    "Yone", "Zed", "Zeri",
}

PEEL_SPECIALISTS = {
    "Lulu", "Janna", "Braum", "Milio", "Nami", "Soraka", "Thresh", "Galio",
    "Morgana", "Alistar", "Shen", "Poppy", "Zilean", "Bardo", "Karma", "Seraphine",
}

ANTI_DASH_CHAMPS = {"Poppy", "Vex", "Taliyah", "Singed", "Lissandra", "Maokai", "Galio"}
ANTI_AP_CHAMPS = {"Galio", "Kassadin", "Dr. Mundo"}
ANTI_AD_CHAMPS = {"Malphite", "Rammus", "Shen", "Poppy", "Jax", "Teemo", "Braum"}
ANTI_TANK_CHAMPS = {
    "Fiora", "Gwen", "Vayne", "Kog'Maw", "Brand", "Lillia", "Vel'Koz", "Varus",
    "Mordekaiser", "Sett", "Camille", "Norra", "Trundle", "Darius", "Kayn",
}
ANTI_CC_CHAMPS = {"Morgana", "Olaf", "Milio", "Sivir", "Fiora", "Dr. Mundo", "K'Sante"}
BLIND_SAFE_CHAMPS = {
    "Ahri", "Orianna", "Syndra", "Karma", "Viktor", "Norra", "Mel",
    "Lee Sin", "Vi", "Jarvan IV", "Xin Zhao", "Wukong", "Maokai",
    "Gnar", "Renekton", "Ornn", "Aatrox", "Shen", "Camille",
    "Ezreal", "Caitlyn", "Xayah", "Varus", "Kai'Sa", "Ashe",
    "Thresh", "Nautilus", "Nami", "Lulu", "Braum", "Rakan", "Karma",
}


def norm(text: str) -> str:
    nfkd = unicodedata.normalize("NFKD", text.lower().strip())
    return "".join(ch for ch in nfkd if not unicodedata.combining(ch))


def infer_vector_and_runes(champ: dict) -> tuple[list[int], str, list[str]]:
    name = champ["name"]
    roles = champ["roles"]
    dmg = champ["damage"]
    style = norm(champ["style"])

    # [ad, ap, tank, cc, engage, peel, mobility, burst, anti_tank, blind_safe]
    ad = 0
    ap = 0
    tank = 0
    cc = 1
    engage = 1
    peel = 1
    mobility = 1
    burst = 1
    anti_tank = 1
    blind_safe = 1

    # 1. Tipo de daño y aguante base
    if "AD" in dmg:
        ad = 3 if dmg == "AD" else 2
    if "AP" in dmg:
        ap = 3 if dmg == "AP" else 2
    if "Hybrid" in dmg:
        ad = max(ad, 2)
        ap = max(ap, 2)
    if "Tank" in dmg:
        tank = 3 if dmg == "Tank" else 2
        if ad == 0 and ap == 0:
            ap = 1
    if "Utility" in dmg:
        peel = 3
        ap = max(ap, 1)

    # 2. Heurística sobre el texto táctico oficial de Wild Rift
    # Limpiar menciones de "anti-tanques", "contra tanques", "estanque", "guardianes" (wards)
    # para no marcar por error como tanques a Brand, Vayne, Vel'Koz, Vladimir o Lee Sin.
    style_for_tank = re.sub(
        r"(anti-tanques?|contra\s+[^,.;]*tanques?|cazadora\s+de\s+tanques?|desintegra\s+tanques?|estanque|guardianes)",
        "",
        style,
    )
    if re.search(r"\b(tanque|coloso|vanguardia|guardian)\b", style_for_tank):
        tank = max(tank, 2)
        if re.search(r"\b(tanque|vanguardia)\b", style_for_tank):
            tank = 3
    if any(k in style for k in ("aturd", "inmovil", "provoc", "supres", "encantamiento", "silencio", "miedo", "levantamiento", "destierro", "jaula", "ancla")):
        cc = 3
    elif any(k in style for k in ("ralentiz", "desplazamiento", "control")):
        cc = max(cc, 2)

    if any(k in style for k in ("iniciacion", "iniciador", "enganche", "salto en area", "cataclismo", "fuerza imparable", "emboscada", "atracci")):
        engage = 3
    elif "luchador" in style or "tanque" in style:
        engage = max(engage, 2)

    if name in PEEL_SPECIALISTS:
        peel = 3
    elif any(k in style for k in ("desenganche", "protectora", "sanadora", "rescate", "anti-asesinos", "anti-dive", "anti-proyectiles", "limpia todo el cc")):
        peel = 3
    elif any(k in style for k in ("escudo", "curacion", "protege", "soporte", "utilidad")):
        peel = max(peel, 2)

    if name in HIGH_MOBILITY_CHAMPS:
        mobility = 3
    elif any(k in style for k in ("movilidad", "deslizamiento", "salto", "sigilo", "camuflaje", "parkour", "veloz", "agil", "portales")):
        mobility = 3 if any(k in style for k in ("alta movilidad", "altisima", "hiper-movilidad", "constante", "deslizamientos", "saltos")) else 2
    elif any(k in style for k in ("inmovil", "artilleria", "coloso")):
        mobility = 0

    if any(k in style for k in ("asesino", "rafaga", "explosion", "ejecucion", "instantaneamente", "eliminar")):
        burst = 3
    elif any(k in style for k in ("mago", "maga", "tirador", "tiradora")):
        burst = max(burst, 2)

    if name in ANTI_TANK_CHAMPS or any(k in style for k in ("anti-tanques", "vida maxima", "dano verdadero", "porcentual")):
        anti_tank = 3
    elif "hiper-carry" in style or "dps" in style or "duelista" in style:
        anti_tank = max(anti_tank, 2)

    if name in BLIND_SAFE_CHAMPS:
        blind_safe = 3
    elif any(k in style for k in ("versatil", "seguro", "rango", "alcance", "utilidad")):
        blind_safe = 2
    elif any(k in style for k in ("debil", "hiper-escalado", "aislado")):
        blind_safe = 1

    # 3. Selección de perfil de runas verificado
    if name in CHAMPION_RUNE_OVERRIDES:
        rune_key = CHAMPION_RUNE_OVERRIDES[name]
    elif "Support" in roles and "Utility" in dmg:
        rune_key = "enchanter"
    elif "Support" in roles and tank >= 2 and peel == 3 and engage < 3:
        rune_key = "warden"
    elif "Support" in roles and tank >= 2:
        rune_key = "tank_engage"
    elif "Dragon" in roles:
        if name in {"Ezreal", "Jhin", "Miss Fortune", "Varus", "Corki", "Smolder"}:
            rune_key = "adc_poke" if name in {"Ezreal", "Corki"} else "adc_burst"
        elif name in {"Lucian", "Draven", "Samira"}:
            rune_key = "adc_burst"
        else:
            rune_key = "adc_dps"
    elif "asesino" in style or "asesina" in style:
        rune_key = "assassin_ap" if ap >= ad else "assassin_ad"
    elif tank == 3:
        rune_key = "tank_top" if "Baron" in roles and engage < 3 else "tank_engage"
    elif ap >= 2 and ("mago" in style or "maga" in style or "Mid" in roles):
        if any(k in style for k in ("artilleria", "desgaste", "larga distancia", "hostigamiento", "torretas", "plantas")):
            rune_key = "mage_poke"
        elif any(k in style for k in ("control", "batalla", "portales", "zona")):
            rune_key = "mage_control"
        else:
            rune_key = "mage_burst"
    else:
        rune_key = "fighter_ap" if ap > ad else "fighter_ad"

    # 4. Etiquetas tácticas especiales
    tags: list[str] = []
    if name in KNOCKUP_CHAMPS:
        tags.append("knockup")
    if name in HYPERCARRY_CHAMPS:
        tags.append("hypercarry")
    if name in ANTI_DASH_CHAMPS:
        tags.append("anti_dash")
    if name in ANTI_AP_CHAMPS:
        tags.append("anti_ap")
    if name in ANTI_AD_CHAMPS:
        tags.append("anti_ad")
    if name in ANTI_TANK_CHAMPS:
        tags.append("anti_tank")
    if name in ANTI_CC_CHAMPS:
        tags.append("anti_cc")
    if "curacion" in style or "robo de vida" in style or "drenaje" in style or "regenerativo" in style:
        tags.append("heavy_heal")

    vec = [ad, ap, tank, cc, engage, peel, mobility, burst, anti_tank, blind_safe]
    return vec, RUNE_PROFILES[rune_key], tags


def verify_runes_exist(runes_data: dict) -> None:
    valid_names = {norm(k["name"]) for k in runes_data["keystones"]}
    for tree_slots in runes_data["trees"].values():
        for slot_list in tree_slots.values():
            for item in slot_list:
                valid_names.add(norm(item["name"]))

    for key, page in RUNE_PROFILES.items():
        # formato: "Keystone | Rama: r1, r2, r3 | RamaSec: r4"
        parts = [p.strip() for p in page.split("|")]
        keystone = parts[0]
        primary_list = [x.strip() for x in parts[1].split(":", 1)[1].split(",")]
        secondary = parts[2].split(":", 1)[1].strip()
        for rname in [keystone, *primary_list, secondary]:
            if norm(rname) not in valid_names:
                raise ValueError(f"Runa inválida en perfil '{key}': {rname}")


def main() -> None:
    champs_data = json.loads(CHAMPS_PATH.read_text(encoding="utf-8"))
    runes_data = json.loads(RUNES_PATH.read_text(encoding="utf-8"))
    verify_runes_exist(runes_data)

    champions_out = {}
    for c in champs_data["champions"]:
        vec, runes_str, tags = infer_vector_and_runes(c)
        champions_out[c["name"]] = {
            "roles": c["roles"],
            "vec": vec,
            "tags": tags,
            "runes": runes_str,
        }

    payload = {
        "version": champs_data.get("version", "2027.1"),
        "total_champions": len(champions_out),
        "dims": DIMS,
        "lanes": champs_data["lanes"],
        "champions": champions_out,
    }

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    size_kb = OUT_PATH.stat().st_size / 1024.0
    print(f"OK: {OUT_PATH} generado ({len(champions_out)} campeones, {size_kb:.1f} KB, runas 100% verificadas).")


if __name__ == "__main__":
    main()
