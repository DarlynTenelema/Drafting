"""Convierte los 143 retratos oficiales de Wild Rift a WebP 128x128 en drafting/assets/champions/."""
from __future__ import annotations

import json
import unicodedata
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = ROOT / "local_ai" / "data" / "wr_icons_cache"
DST_DIR = ROOT / "drafting" / "assets" / "champions"
CHAMPS_PATH = ROOT / "backend" / "json" / "wr_champions.json"


def norm(text: str) -> str:
    nfkd = unicodedata.normalize("NFKD", text.lower().strip())
    cleaned = "".join(ch for ch in nfkd if not unicodedata.combining(ch))
    return cleaned.replace("'", "").replace(".", "").replace(" ", "").replace("-", "").replace("_", "")


def main() -> None:
    DST_DIR.mkdir(parents=True, exist_ok=True)
    total_bytes = 0
    count = 0

    for p in sorted(SRC_DIR.glob("*.png")):
        out = DST_DIR / f"{p.stem}.webp"
        with Image.open(p) as im:
            im = im.convert("RGBA").resize((128, 128), Image.Resampling.LANCZOS)
            im.save(out, "WEBP", quality=82, method=6)
        total_bytes += out.stat().st_size
        count += 1

    champs = json.loads(CHAMPS_PATH.read_text(encoding="utf-8"))["champions"]
    missing = []
    for c in champs:
        slug = norm(c["name"])
        if not (DST_DIR / f"{slug}.webp").exists():
            missing.append((c["name"], slug))

    print(f"Converted: {count} files | Total: {total_bytes / 1024:.1f} KB ({total_bytes / (1024 * 1024):.2f} MB)")
    print(f"Missing matches: {missing}")


if __name__ == "__main__":
    main()
