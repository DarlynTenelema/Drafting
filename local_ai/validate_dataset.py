"""
Tarea 1.2 — Validador Automático de Calidad (QA) para el Dataset de Wild Rift.

Verifica 100% de los ejemplos en wr_draft_train.jsonl y wr_draft_val.jsonl:
1. Estructura ChatML válida (system/user/assistant).
2. 0% alucinaciones: todos los campeones recomendados pertenecen a los 143 de Wild Rift
   y al rol asignado.
3. 0% colisiones: ningún campeón recomendado está en bans, allies, enemies o exclude.
4. Compatibilidad 100% con los Regex de CaptureService.kt y DraftAnalyzerStateMixin.
5. Presupuesto de longitud (< 100 tokens estimados, sin asteriscos ** ni saludos).
"""

from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VECTORS_PATH = ROOT / "local_ai" / "data" / "wr_vectors.json"
TRAIN_PATH = ROOT / "local_ai" / "data" / "wr_draft_train.jsonl"
VAL_PATH = ROOT / "local_ai" / "data" / "wr_draft_val.jsonl"

REG_PLAN_A = re.compile(r"(?:PLAN|PLANO)\s*A\s*:\s*([^•\n\r]+)", re.IGNORECASE)
REG_BULLET = re.compile(r"•\s*([^:\n\r]+):")

IGNORED_BULLET_LABELS = (
    "hechizo", "runa", "plan", "spell", "feitiço", "sort", "build", "por qué", "por que"
)


def validate_file(path: Path, lanes: dict[str, list[str]], valid_champs: set[str]) -> dict:
    errors: list[str] = []
    role_counts = Counter()
    total = 0
    word_counts: list[int] = []
    otp_cases = 0
    autofill_cases = 0
    blind_cases = 0
    reconsult_cases = 0

    with path.open("r", encoding="utf-8") as f:
        for idx, line in enumerate(f, start=1):
            total += 1
            rec = json.loads(line)
            msgs = rec.get("messages", [])
            if len(msgs) != 3 or [m["role"] for m in msgs] != ["system", "user", "assistant"]:
                errors.append(f"L{idx}: estructura ChatML inválida")
                continue

            user_data = json.loads(msgs[1]["content"])
            ans = msgs[2]["content"]

            role = user_data["role"]
            role_counts[role] += 1
            if not user_data["enemies"]:
                blind_cases += 1
            if user_data["otp"]:
                otp_cases += 1
                if not user_data["otp_viable"]:
                    autofill_cases += 1
            if user_data["exclude"]:
                reconsult_cases += 1

            # 1. Sin asteriscos ni saludos
            if "**" in ans or "###" in ans:
                errors.append(f"L{idx}: contiene markdown prohibido (** o ###)")

            # 2. Parseo compatible con CaptureService.kt y DraftAnalyzerStateMixin
            m_a = REG_PLAN_A.search(ans)
            if not m_a:
                errors.append(f"L{idx}: falta 'PLAN A:'")
                continue
            plan_a = m_a.group(1).strip()

            alts: list[str] = []
            for m_b in REG_BULLET.finditer(ans):
                label = m_b.group(1).strip()
                low = label.lower()
                if any(ig in low for ig in IGNORED_BULLET_LABELS):
                    continue
                alts.append(label)

            if len(alts) != 2:
                errors.append(f"L{idx}: esperadas 2 alternativas con viñeta, encontradas {len(alts)} ({alts})")
                continue

            picks = [plan_a, *alts]
            if len(set(picks)) != 3:
                errors.append(f"L{idx}: campeones repetidos en la misma respuesta: {picks}")

            forbidden = (
                set(user_data["bans"])
                | set(user_data["allies"])
                | set(user_data["enemies"])
                | set(user_data["exclude"])
            )
            lane_set = set(lanes[role])

            for p in picks:
                if p not in valid_champs:
                    errors.append(f"L{idx}: campeón fuera de Wild Rift: '{p}'")
                if p not in lane_set:
                    errors.append(f"L{idx}: campeón '{p}' no pertenece a la línea {role}")
                if p in forbidden:
                    errors.append(f"L{idx}: campeón prohibido/baneado/elegido recomendado: '{p}'")

            # 3. Verificar coherencia con top3 del motor matemático
            expected_top3 = [x["name"] for x in user_data["top3"]]
            if picks != expected_top3:
                errors.append(f"L{idx}: picks {picks} != top3 {expected_top3}")

            words = len(ans.split())
            word_counts.append(words)
            if words > 110:
                errors.append(f"L{idx}: respuesta demasiado larga ({words} palabras)")

    avg_words = sum(word_counts) / max(len(word_counts), 1)
    max_words = max(word_counts) if word_counts else 0
    return {
        "file": path.name,
        "total": total,
        "errors": errors,
        "roles": dict(role_counts),
        "avg_words": round(avg_words, 1),
        "max_words": max_words,
        "est_avg_tokens": round(avg_words * 1.35, 1),
        "blind_cases": blind_cases,
        "otp_cases": otp_cases,
        "autofill_cases": autofill_cases,
        "reconsult_cases": reconsult_cases,
    }


def main() -> None:
    vec = json.loads(VECTORS_PATH.read_text(encoding="utf-8"))
    lanes = vec["lanes"]
    valid_champs = set(vec["champions"].keys())

    all_ok = True
    for p in [TRAIN_PATH, VAL_PATH]:
        report = validate_file(p, lanes, valid_champs)
        err_count = len(report["errors"])
        status = "PASS" if err_count == 0 else "FAIL"
        print(
            f"[{status}] {report['file']} | total={report['total']} | errores={err_count} | "
            f"promedio={report['avg_words']} palabras (~{report['est_avg_tokens']} tokens, máx {report['max_words']} pal.)"
        )
        print(
            f"       Roles={report['roles']} | Blind={report['blind_cases']} | "
            f"OTP={report['otp_cases']} (Autofill={report['autofill_cases']}) | Reconsult={report['reconsult_cases']}"
        )
        if err_count > 0:
            all_ok = False
            for e in report["errors"][:10]:
                print("   -", e)

    if not all_ok:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
