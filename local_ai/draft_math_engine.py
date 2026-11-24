"""
Motor Matemático de Draft con Poda por Rol (Prototipo 1:1 para portar a Kotlin).

En lugar de evaluar 143x143 campeones, poda inmediatamente al rol asignado:
  C_valido = Lanes[role] - (bans U allies U enemies U exclude)
Evaluando solo 15..45 candidatos contra los <= 9 campeones presentes en pantalla (< 0.2 ms).
"""

from __future__ import annotations

import json
import time
import unicodedata
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
VECTORS_PATH = ROOT / "local_ai" / "data" / "wr_vectors.json"

# Índices del vector de 10 dimensiones
AD, AP, TANK, CC, ENGAGE, PEEL, MOBILITY, BURST, ANTI_TANK, BLIND_SAFE = range(10)

ROLE_ALIASES = {
    "baron": "Baron",
    "top": "Baron",
    "solo": "Baron",
    "jungle": "Jungle",
    "jungla": "Jungle",
    "jg": "Jungle",
    "mid": "Mid",
    "medio": "Mid",
    "dragon": "Dragon",
    "adc": "Dragon",
    "bot": "Dragon",
    "duo": "Dragon",
    "support": "Support",
    "soporte": "Support",
    "supp": "Support",
    "sup": "Support",
}


def norm(text: str) -> str:
    nfkd = unicodedata.normalize("NFKD", text.lower().strip())
    cleaned = "".join(ch for ch in nfkd if not unicodedata.combining(ch))
    return cleaned.replace("'", "").replace(".", "").replace(" ", "")


class DraftMathEngine:
    def __init__(self, vectors_path: Path = VECTORS_PATH) -> None:
        raw = json.loads(vectors_path.read_text(encoding="utf-8"))
        self.lanes: dict[str, list[str]] = raw["lanes"]
        self.champions: dict[str, dict[str, Any]] = raw["champions"]
        self._lookup: dict[str, str] = {norm(name): name for name in self.champions}
        # Alias comunes de OCR/visión
        self._lookup.update({
            "masteryi": "Maestro Yi",
            "bard": "Bardo",
            "nunu": "Nunu y Willump",
            "mundo": "Dr. Mundo",
            "drmundo": "Dr. Mundo",
            "tf": "Twisted Fate",
            "mf": "Miss Fortune",
            "j4": "Jarvan IV",
            "aurelion": "Aurelion Sol",
            "asol": "Aurelion Sol",
        })

    def normalize_role(self, role: str) -> str:
        return ROLE_ALIASES.get(norm(role), "Mid")

    def normalize_champ(self, name: str) -> str | None:
        if not name:
            return None
        return self._lookup.get(norm(name))

    def _normalize_list(self, items: list[str]) -> list[str]:
        out: list[str] = []
        for item in items:
            c = self.normalize_champ(item)
            if c and c not in out:
                out.append(c)
        return out

    def _analyze_ban_psychology(self, norm_bans: list[str]) -> dict[str, int]:
        """
        Analiza los campeones baneados para deducir qué teme el enemigo
        y qué tipo de composición planea jugar (vital en First Pick / Blind Pick).
        """
        anti_tank_banned = 0
        anti_dash_banned = 0
        assassins_banned = 0
        peel_banned = 0
        tanks_banned = 0

        for b in norm_bans:
            info = self.champions.get(b)
            if not info:
                continue
            v = info["vec"]
            tags = set(info["tags"])
            if "anti_tank" in tags or v[ANTI_TANK] >= 3:
                anti_tank_banned += 1
            if "anti_dash" in tags or v[CC] >= 3:
                anti_dash_banned += 1
            if v[BURST] >= 3 and v[MOBILITY] >= 3:
                assassins_banned += 1
            if v[PEEL] >= 3:
                peel_banned += 1
            if v[TANK] >= 3:
                tanks_banned += 1

        return {
            "anti_tank_banned": anti_tank_banned,
            "anti_dash_banned": anti_dash_banned,
            "assassins_banned": assassins_banned,
            "peel_banned": peel_banned,
            "tanks_banned": tanks_banned,
        }

    def detect_draft_phase(
        self,
        norm_allies: list[str],
        norm_enemies: list[str],
        norm_my_pick: str | None = None,
        explicit_phase: str = "",
    ) -> str:
        """
        Determina la fase exacta del draft:
        - 'full_locked': El usuario ya eligió su campeón (my_pick) o ya hay >=4 aliados y >=4 enemigos.
        - 'first_pick': 0 enemigos visibles (o <=1 pick total en pantalla).
        - 'last_pick': >=4 enemigos visibles (última rotación de picks).
        - 'mid_draft': 1 a 3 enemigos visibles (mitad del draft).
        """
        exp = norm(explicit_phase)
        if norm_my_pick or exp in {"fulllocked", "locked", "full", "ingame", "postpick"}:
            return "full_locked"
        if len(norm_allies) >= 4 and len(norm_enemies) >= 5:
            return "full_locked"
        if len(norm_enemies) == 0:
            return "first_pick"
        if len(norm_enemies) >= 4:
            return "last_pick"
        return "mid_draft"

    def recommend(
        self,
        role: str,
        bans: list[str] | None = None,
        allies: list[str] | None = None,
        enemies: list[str] | None = None,
        otp: str = "",
        my_pick: str = "",
        draft_phase: str = "",
        exclude: list[str] | None = None,
        lang: str = "es",
        top_k: int = 3,
    ) -> dict[str, Any]:
        t0 = time.perf_counter()

        norm_role = self.normalize_role(role)
        norm_bans = self._normalize_list(bans or [])
        norm_allies = self._normalize_list(allies or [])
        norm_enemies = self._normalize_list(enemies or [])
        norm_exclude = self._normalize_list(exclude or [])
        norm_otp = self.normalize_champ(otp)
        norm_my_pick = self.normalize_champ(my_pick)

        # Si my_pick viene incluido en allies, lo separamos para no duplicarlo
        if norm_my_pick and norm_my_pick in norm_allies:
            norm_allies = [a for a in norm_allies if a != norm_my_pick]

        detected_phase = self.detect_draft_phase(
            norm_allies=norm_allies,
            norm_enemies=norm_enemies,
            norm_my_pick=norm_my_pick,
            explicit_phase=draft_phase,
        )

        blocked = set(norm_bans) | set(norm_allies) | set(norm_enemies) | set(norm_exclude)
        lane_pool = self.lanes.get(norm_role, self.lanes["Mid"])
        candidates = [c for c in lane_pool if c not in blocked and c in self.champions]

        # Si el usuario ya lockeó su campeón (2da foto con draft completo), asegurar que sea evaluado
        if norm_my_pick and norm_my_pick in self.champions and norm_my_pick not in candidates:
            candidates.insert(0, norm_my_pick)

        otp_viable_in_role = bool(norm_otp and norm_otp in lane_pool)
        otp_available = bool(otp_viable_in_role and norm_otp not in blocked)

        # Psicología de baneos (clave para First Pick y lectura de intenciones enemigas)
        ban_psych = self._analyze_ban_psychology(norm_bans)

        # Perfil agregado del equipo aliado y enemigo (solo los presentes en pantalla)
        ally_ad = sum(self.champions[a]["vec"][AD] for a in norm_allies)
        ally_ap = sum(self.champions[a]["vec"][AP] for a in norm_allies)
        ally_tank = sum(self.champions[a]["vec"][TANK] for a in norm_allies)
        ally_cc = sum(self.champions[a]["vec"][CC] for a in norm_allies)
        ally_has_knockup = any("knockup" in self.champions[a]["tags"] for a in norm_allies)
        ally_has_hypercarry = any("hypercarry" in self.champions[a]["tags"] for a in norm_allies)

        enemy_ad = sum(self.champions[e]["vec"][AD] for e in norm_enemies)
        enemy_ap = sum(self.champions[e]["vec"][AP] for e in norm_enemies)
        enemy_tanks = sum(1 for e in norm_enemies if self.champions[e]["vec"][TANK] >= 2)
        enemy_high_mob = sum(1 for e in norm_enemies if self.champions[e]["vec"][MOBILITY] >= 3)
        enemy_burst = sum(1 for e in norm_enemies if self.champions[e]["vec"][BURST] >= 3)
        enemy_cc = sum(1 for e in norm_enemies if self.champions[e]["vec"][CC] >= 3)
        enemy_immobile = sum(1 for e in norm_enemies if self.champions[e]["vec"][MOBILITY] <= 1)

        is_blind = detected_phase == "first_pick"
        is_last_pick = detected_phase == "last_pick"
        counter_mult = 1.25 if is_last_pick else 1.0
        scored: list[tuple[float, str, list[str]]] = []

        for cand in candidates:
            info = self.champions[cand]
            v = info["vec"]
            tags = set(info["tags"])
            score = 0.0
            reasons: list[tuple[float, str]] = []

            # 0. Si el jugador ya seleccionó su campeón (full_locked), fijarlo como Top 1 para darle su plan de partida
            if norm_my_pick and cand == norm_my_pick:
                score += 100.0
                reasons.append((100.0, "locked_champion_gameplan"))

            # 1. Seguridad de Blind Pick + Lectura Psicológica de Baneos en First Pick
            if is_blind:
                pts = v[BLIND_SAFE] * 3.0
                score += pts
                if v[BLIND_SAFE] >= 3:
                    reasons.append((pts, "safe_blind_pick"))

                # Lectura de baneos cuando no hay enemigos visibles:
                if ban_psych["anti_tank_banned"] >= 2 and (v[TANK] >= 2 or v[ANTI_TANK] >= 3):
                    b_pts = 3.8
                    score += b_pts
                    reasons.append((b_pts, "ban_read_tanks_expected"))
                if ban_psych["anti_dash_banned"] >= 2 and ("anti_dash" in tags or v[CC] >= 3):
                    b_pts = 4.0
                    score += b_pts
                    reasons.append((b_pts, "ban_read_mobility_expected"))
                if ban_psych["assassins_banned"] >= 2 and (v[ENGAGE] >= 3 or v[BURST] >= 2):
                    b_pts = 3.4
                    score += b_pts
                    reasons.append((b_pts, "ban_read_carries_exposed"))
                if ban_psych["peel_banned"] >= 2 and (v[PEEL] >= 2 or v[TANK] >= 2):
                    b_pts = 3.5
                    score += b_pts
                    reasons.append((b_pts, "ban_read_dive_expected"))
            elif len(norm_enemies) == 1:
                pts = v[BLIND_SAFE] * 1.2
                score += pts
                if ban_psych["anti_tank_banned"] >= 2 and v[ANTI_TANK] >= 3:
                    score += 2.2
                    reasons.append((2.2, "ban_read_tanks_expected"))
                elif ban_psych["anti_dash_banned"] >= 2 and ("anti_dash" in tags or v[CC] >= 3):
                    score += 2.2
                    reasons.append((2.2, "ban_read_mobility_expected"))

            # 2. Balance de daño AP/AD del equipo aliado (solo para roles de daño; en Support pesa menos)
            if norm_allies:
                dmg_balance_mult = 0.7 if norm_role == "Support" else 2.2
                if ally_ad >= 5 and ally_ap <= 2 and v[AP] >= 2:
                    pts = v[AP] * dmg_balance_mult
                    score += pts
                    reasons.append((pts, "ap_needed"))
                elif ally_ap >= 5 and ally_ad <= 2 and v[AD] >= 2:
                    pts = v[AD] * dmg_balance_mult
                    score += pts
                    reasons.append((pts, "ad_needed"))

                # Necesidad de frontline / CC
                if ally_tank <= 1 and v[TANK] >= 2 and norm_role in {"Baron", "Jungle", "Support"}:
                    pts = v[TANK] * 1.8
                    score += pts
                    reasons.append((pts, "frontline_needed"))
                if ally_cc <= 2 and v[CC] >= 3:
                    pts = 2.6
                    score += pts
                    reasons.append((pts, "cc_needed"))

            # 3. Counters contra amenazas enemigas visibles (en Last Pick pesan 25% más)
            if enemy_tanks >= 2 and (v[ANTI_TANK] >= 3 or "anti_tank" in tags):
                pts = (4.5 + enemy_tanks * 1.2) * counter_mult
                score += pts
                reasons.append((pts, "anti_tank_shred"))

            if enemy_high_mob >= 2:
                if "anti_dash" in tags:
                    pts = 5.5 * counter_mult
                    score += pts
                    reasons.append((pts, "hard_anti_mobility"))
                elif v[CC] >= 3:
                    pts = 3.2 * counter_mult
                    score += pts
                    reasons.append((pts, "lockdown_vs_mobility"))

            if enemy_burst >= 2 and (v[PEEL] >= 3 or v[TANK] >= 3):
                pts = 3.5 * counter_mult
                score += pts
                reasons.append((pts, "anti_burst_peel"))

            if enemy_ad >= 6 and enemy_ap <= 2 and "anti_ad" in tags:
                pts = 6.0 * counter_mult
                score += pts
                reasons.append((pts, "hard_anti_ad"))

            if enemy_ap >= 6 and enemy_ad <= 2 and "anti_ap" in tags:
                pts = 6.0 * counter_mult
                score += pts
                reasons.append((pts, "hard_anti_ap"))

            if enemy_cc >= 2 and "anti_cc" in tags:
                pts = 4.2 * counter_mult
                score += pts
                reasons.append((pts, "anti_cc_shield"))

            if enemy_immobile >= 2 and (v[ENGAGE] >= 3 or v[BURST] >= 3):
                pts = 2.8 * counter_mult
                score += pts
                reasons.append((pts, "punish_immobile"))

            # Counter puntual de 1 enemigo visible en Mid-Draft
            if len(norm_enemies) == 1:
                e0 = self.champions[norm_enemies[0]]["vec"]
                if e0[TANK] >= 3 and (v[ANTI_TANK] >= 3 or "anti_tank" in tags):
                    pts = 3.2
                    score += pts
                    reasons.append((pts, "anti_tank_shred"))
                elif e0[MOBILITY] >= 3 and ("anti_dash" in tags or v[CC] >= 3):
                    pts = 3.2
                    score += pts
                    reasons.append((pts, "lockdown_vs_mobility"))
                elif e0[BURST] >= 3 and (v[PEEL] >= 3 or v[TANK] >= 2):
                    pts = 2.8
                    score += pts
                    reasons.append((pts, "anti_burst_peel"))

            # 4. Sinergias de alto valor con aliados visibles
            if cand == "Yasuo" and ally_has_knockup:
                pts = 5.0
                score += pts
                reasons.append((pts, "knockup_synergy"))
            if "knockup" in tags and "Yasuo" in norm_allies:
                pts = 4.5
                score += pts
                reasons.append((pts, "combo_with_yasuo"))
            if ally_has_hypercarry and norm_role == "Support" and v[PEEL] >= 3:
                pts = 4.8
                score += pts
                reasons.append((pts, "protect_hypercarry"))
            if "hypercarry" in tags and any(a in {"Lulu", "Milio", "Yuumi", "Janna", "Braum"} for a in norm_allies):
                pts = 4.2
                score += pts
                reasons.append((pts, "enchanter_hypercarry_combo"))

            # 5. Bono OTP (solo si es viable en la línea asignada y disponible)
            if otp_available and cand == norm_otp:
                pts = 9.0
                score += pts
                reasons.append((pts, "otp_priority"))

            # Desempate ligero por seguridad general
            score += v[BLIND_SAFE] * 0.15 + v[CC] * 0.10

            top_reasons = [r for _, r in sorted(reasons, key=lambda x: x[0], reverse=True)[:3]]
            if not top_reasons:
                top_reasons = ["balanced_meta_pick"]

            scored.append((round(score, 2), cand, top_reasons))

        scored.sort(key=lambda x: (-x[0], x[1]))
        top_picks = [
            {
                "name": name,
                "score": sc,
                "runes": self.champions[name]["runes"],
                "reasons": rsn,
            }
            for sc, name, rsn in scored[:top_k]
        ]

        elapsed_ms = (time.perf_counter() - t0) * 1000.0
        return {
            "lang": lang,
            "role": norm_role,
            "draft_phase": detected_phase,
            "my_pick": norm_my_pick or "",
            "otp": norm_otp or "",
            "otp_viable": otp_viable_in_role if norm_otp else True,
            "allies": norm_allies,
            "enemies": norm_enemies,
            "bans": norm_bans,
            "evaluated_candidates": len(candidates),
            "latency_ms": round(elapsed_ms, 3),
            "top3": top_picks,
        }


def run_demo_suite() -> None:
    engine = DraftMathEngine()
    scenarios = [
        (
            "1. Mid vs Alta Movilidad + Falta AP",
            dict(role="Mid", bans=["Zed", "Yuumi", "Darius"], allies=["Malphite", "Lee Sin", "Jinx"], enemies=["Ahri", "Vi", "Akali", "Ezreal"]),
        ),
        (
            "2. Baron First Pick (0 enemigos, 5 bans)",
            dict(role="Baron", bans=["Darius", "Aatrox", "Fiora", "Lux", "Lee Sin"], allies=[], enemies=[]),
        ),
        (
            "3. Dragon (ADC) vs Composición 3 Tanques",
            dict(role="Dragon", bans=["Vayne", "Yuumi"], allies=["Lulu", "Orianna"], enemies=["Ornn", "Amumu", "Leona", "Malphite"]),
        ),
        (
            "4. Support con Jinx aliada vs Asesinos",
            dict(role="Support", bans=["Blitzcrank", "Pyke"], allies=["Jinx", "Lee Sin"], enemies=["Zed", "Kha'Zix", "Kai'Sa"]),
        ),
        (
            "5. Jugador OTP Yasuo en Autofill Support (NO debe forzar Yasuo)",
            dict(role="Support", bans=["Lux"], allies=["Jinx"], enemies=["Leona", "Draven"], otp="Yasuo"),
        ),
        (
            "6. Reconsulta excluyendo los 3 anteriores del caso 1",
            dict(
                role="Mid",
                bans=["Zed", "Yuumi", "Darius"],
                allies=["Malphite", "Lee Sin", "Jinx"],
                enemies=["Ahri", "Vi", "Akali", "Ezreal"],
                exclude=["Vex", "Taliyah", "Lissandra"],
            ),
        ),
    ]

    for title, kwargs in scenarios:
        res = engine.recommend(**kwargs)
        picks = ", ".join(f"{p['name']} ({p['score']} | {p['reasons']})" for p in res["top3"])
        print(f"\n=== {title} ===")
        print(f"Candidatos evaluados: {res['evaluated_candidates']} | Tiempo: {res['latency_ms']:.3f} ms | OTP viable: {res['otp_viable']}")
        print(f"Top 3: {picks}")
        print(f"Runas PLAN A ({res['top3'][0]['name']}): {res['top3'][0]['runes']}")


if __name__ == "__main__":
    run_demo_suite()
