#!/usr/bin/env python3
"""Composição reprodutível dos papéis de parede 2K assinados do Vanta (GPL-3.0-only).

Recebe as 3 artes-base sem assinatura (2752x1536, em `tools/art/bases/`) e produz:
1. Os 3 papéis de parede 2K finalistas (2560x1440, JPEG q=95) em `--output-dir`;
2. Opcionalmente (`--repo-assets <pasta>` ou `--sync-repo`), os 5 derivados embarcados no
   repositório (`app/resources/wallpapers/vanta-{wallpaper,lockscreen}-dark.png` e
   `app/assets/tools/bg/{torii,nebulosa,eclipse}.jpg`).

A assinatura (`V A N T A`, barra `#7C4EE0` e numeração `01`/`02`/`03`) é renderizada
programaticamente apenas com `app/assets/fonts/Geist-Regular.ttf` e `Geist-Medium.ttf` (OFL-1.1).
"""

from __future__ import annotations

import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BASES = REPO_ROOT / "tools" / "art" / "bases"
FONT_REGULAR = REPO_ROOT / "app" / "assets" / "fonts" / "Geist-Regular.ttf"
FONT_MEDIUM = REPO_ROOT / "app" / "assets" / "fonts" / "Geist-Medium.ttf"

SPECS = [
    ("01-torii-nevoa-base", "torii", "vanta-01-torii-nevoa.jpg", "01", "TORII NÉVOA"),
    ("02-pico-nebulosa-base", "nebulosa", "vanta-02-pico-nebulosa.jpg", "02", "PICO NEBULOSA"),
    ("03-eclipse-violeta-base", "eclipse", "vanta-03-eclipse-violeta.jpg", "03", "ECLIPSE VIOLETA"),
]


def measure_tracked(font: ImageFont.FreeTypeFont, text: str, tracking: float) -> float:
    return sum(font.getlength(ch) for ch in text) + tracking * max(len(text) - 1, 0)


def draw_tracked(
    draw: ImageDraw.ImageDraw,
    x: float,
    y: float,
    text: str,
    font: ImageFont.FreeTypeFont,
    tracking: float,
    fill: tuple[int, int, int, int],
) -> None:
    cur_x = x
    for i, ch in enumerate(text):
        draw.text((cur_x, y), ch, font=font, fill=fill)
        cur_x += font.getlength(ch) + (tracking if i < len(text) - 1 else 0)


def crop_16_9_qhd(im: Image.Image) -> Image.Image:
    w, h = im.size
    target = 16 / 9
    ratio = w / h
    if ratio > target:
        new_w = int(round(h * target))
        left = (w - new_w) // 2
        im = im.crop((left, 0, left + new_w, h))
    elif ratio < target:
        new_h = int(round(w / target))
        top = (h - new_h) // 2
        im = im.crop((0, top, w, top + new_h))
    return im.resize((2560, 1440), Image.Resampling.LANCZOS)


def apply_signature(im_rgb: Image.Image, number: str, label: str) -> Image.Image:
    base = crop_16_9_qhd(im_rgb).convert("RGBA")
    w, h = base.size
    s = 2  # supersampling 2x para tipografia e barra nítidas
    overlay = Image.new("RGBA", (w * s, h * s), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (w * s, h * s), (0, 0, 0, 0))
    d_ov = ImageDraw.Draw(overlay)
    d_sh = ImageDraw.Draw(shadow)

    f_title = ImageFont.truetype(str(FONT_REGULAR), 38 * s)
    f_sub = ImageFont.truetype(str(FONT_MEDIUM), 14 * s)
    title = "VANTA"
    sub = f"N° {number}  ·  {label}"
    w_title = measure_tracked(f_title, title, 22 * s)
    w_sub = measure_tracked(f_sub, sub, 2.6 * s)
    block_w = max(w_title, w_sub)
    block_h = (38 + 16 + 3 + 13 + 14) * s

    x0 = w * s - 88 * s - block_w
    y_title = h * s - 86 * s - block_h
    y_bar = y_title + (38 + 16) * s
    bar_w = int(w_title * 0.36)
    bar_h = 3 * s
    y_sub = y_bar + bar_h + 13 * s

    sh = (6, 5, 10, 165)
    draw_tracked(d_sh, x0, y_title + 2 * s, title, f_title, 22 * s, sh)
    d_sh.rectangle([x0, y_bar + s, x0 + bar_w, y_bar + bar_h + s], fill=(6, 5, 10, 140))
    draw_tracked(d_sh, x0, y_sub + s, sub, f_sub, 2.6 * s, sh)
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=4 * s))

    draw_tracked(d_ov, x0, y_title, title, f_title, 22 * s, (244, 242, 250, 238))
    d_ov.rectangle([x0, y_bar, x0 + bar_w, y_bar + bar_h], fill=(124, 78, 224, 255))
    draw_tracked(d_ov, x0, y_sub, sub, f_sub, 2.6 * s, (244, 242, 250, 198))

    comp = Image.alpha_composite(base, shadow.resize((w, h), Image.Resampling.LANCZOS))
    comp = Image.alpha_composite(comp, overlay.resize((w, h), Image.Resampling.LANCZOS))
    return comp.convert("RGB")


def main() -> None:
    parser = argparse.ArgumentParser(description="Compõe os papéis de parede 2K assinados do Vanta.")
    parser.add_argument(
        "--input-dir",
        default=DEFAULT_BASES,
        type=Path,
        help="Pasta com as 3 artes-base sem assinatura (padrão: tools/art/bases).",
    )
    parser.add_argument("--output-dir", required=True, type=Path, help="Pasta de destino dos 3 JPGs 2K finais.")
    parser.add_argument(
        "--repo-assets",
        type=Path,
        default=None,
        help="Opcional: raiz onde gravar os 5 derivados do repositório (app/resources/wallpapers e app/assets/tools/bg).",
    )
    parser.add_argument(
        "--sync-repo",
        action="store_true",
        help="Grava os 5 derivados diretamente na árvore do repositório.",
    )
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    generated: dict[str, Path] = {}
    for stem, key, out_name, num, label in SPECS:
        matches = sorted(args.input_dir.glob(f"*{stem}*"))
        if not matches:
            raise FileNotFoundError(f"Arte-base não encontrada para {stem} em {args.input_dir}")
        signed = apply_signature(Image.open(matches[0]), num, label)
        out_path = args.output_dir / out_name
        signed.save(out_path, "JPEG", quality=95, subsampling=0, optimize=True)
        generated[key] = out_path
        print(f"OK {out_path} ({signed.size[0]}x{signed.size[1]}, {out_path.stat().st_size} B)")

    repo_root = REPO_ROOT if args.sync_repo else args.repo_assets
    if repo_root is not None:
        wp_dir = repo_root / "app" / "resources" / "wallpapers"
        bg_dir = repo_root / "app" / "assets" / "tools" / "bg"
        wp_dir.mkdir(parents=True, exist_ok=True)
        bg_dir.mkdir(parents=True, exist_ok=True)

        eclipse = Image.open(generated["eclipse"])
        torii = Image.open(generated["torii"])
        nebulosa = Image.open(generated["nebulosa"])

        wp_path = wp_dir / "vanta-wallpaper-dark.png"
        ls_path = wp_dir / "vanta-lockscreen-dark.png"
        eclipse.save(wp_path, "PNG", optimize=True)
        torii.save(ls_path, "PNG", optimize=True)
        print(f"OK {wp_path} ({eclipse.size[0]}x{eclipse.size[1]}, {wp_path.stat().st_size} B)")
        print(f"OK {ls_path} ({torii.size[0]}x{torii.size[1]}, {ls_path.stat().st_size} B)")

        for key, im in (("eclipse", eclipse), ("nebulosa", nebulosa), ("torii", torii)):
            bg_path = bg_dir / f"{key}.jpg"
            im.save(bg_path, "JPEG", quality=90, optimize=True)
            print(f"OK {bg_path} ({im.size[0]}x{im.size[1]}, {bg_path.stat().st_size} B)")


if __name__ == "__main__":
    main()
