"""
VeilChat launcher-icon generator.

Renders the VeilChat brand mark (veil-shield + speech arc + lock node) into
lossless PNGs used by `flutter_launcher_icons`. Pure Pillow, no SVG rasterizer
required, so it runs anywhere Python + Pillow exist.

Usage:
    python tool/generate_icon.py

Outputs:
    assets/branding/veilchat_icon.png            (1024x1024, opaque, full mark)
    assets/branding/veilchat_icon_foreground.png (1024x1024, transparent, adaptive fg)
"""

from __future__ import annotations

import math
import os

from PIL import Image, ImageDraw, ImageFilter

# ── Brand palette ───────────────────────────────────────────────
BG_TOP = (11, 16, 32)      # #0B1020
BG_BOTTOM = (5, 7, 15)     # #05070F
GRAD_START = (99, 102, 241)   # indigo  #6366F1
GRAD_MID = (34, 211, 238)     # cyan    #22D3EE
GRAD_END = (45, 212, 191)     # teal    #2DD4BF

S = 1024          # final canvas
SS = 4            # supersample factor for smooth edges
W = S * SS


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def brand_gradient(size: int) -> Image.Image:
    """Diagonal indigo -> cyan -> teal gradient used for the mark."""
    g = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(g)
    for i in range(size):
        t = i / max(1, size - 1)
        c = lerp(GRAD_START, GRAD_MID, t / 0.55) if t < 0.55 else lerp(
            GRAD_MID, GRAD_END, (t - 0.55) / 0.45
        )
        # diagonal band
        d.line([(0, i), (i, 0)], fill=c)
        d.line([(size - 1, size - 1 - i), (size - 1 - i, size - 1)], fill=c)
    return g


def vertical_bg(size: int) -> Image.Image:
    bg = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(bg)
    for y in range(size):
        d.line([(0, y), (size, y)], fill=lerp(BG_TOP, BG_BOTTOM, y / (size - 1)))
    return bg


def shield_points(cx, cy, w, h, steps=90):
    """Rounded heraldic shield outline centred on (cx, cy)."""
    hw, hh = w / 2, h / 2
    pts = [(cx - hw, cy - hh), (cx + hw, cy - hh)]
    # right edge curving inward down to the tip
    for i in range(steps + 1):
        t = i / steps
        x = cx + hw * (1 - t ** 2.2)
        y = cy - hh + h * (0.30 + 0.70 * t)
        pts.append((x, y))
    # left edge back up
    for i in range(steps, -1, -1):
        t = i / steps
        x = cx - hw * (1 - t ** 2.2)
        y = cy - hh + h * (0.30 + 0.70 * t)
        pts.append((x, y))
    return pts


def build_mark(canvas: int, inset: float) -> Image.Image:
    """Return an RGBA image (canvas x canvas) holding the gradient mark only."""
    mask = Image.new("L", (canvas, canvas), 0)
    d = ImageDraw.Draw(mask)

    cx = cy = canvas / 2
    sw = canvas * inset            # shield width
    sh = canvas * inset * 1.16     # shield height
    stroke = max(2, int(canvas * 0.052))

    # Shield outline
    d.line(shield_points(cx, cy, sw, sh) + [ (cx - sw / 2, cy - sh / 2) ],
           fill=255, width=stroke, joint="curve")

    # Veil arc (the "veil" sweeping across the shield)
    arc_box = [cx - sw * 0.44, cy - sh * 0.42, cx + sw * 0.44, cy - sh * 0.02]
    d.arc(arc_box, start=200, end=340, fill=190, width=int(stroke * 0.72))

    # Lock shackle
    lw = sw * 0.30
    lh = sh * 0.20
    shackle = [cx - lw / 2, cy - sh * 0.02, cx + lw / 2, cy + lh]
    d.arc(shackle, start=180, end=360, fill=255, width=int(stroke * 0.80))

    # Lock body (rounded rect)
    bw = sw * 0.40
    bh = sh * 0.26
    body = [cx - bw / 2, cy + lh * 0.45, cx + bw / 2, cy + lh * 0.45 + bh]
    d.rounded_rectangle(body, radius=bh * 0.32, fill=255)

    grad = brand_gradient(canvas).convert("RGBA")
    grad.putalpha(mask)

    # Punch the keyhole back out so the lock body reads clearly
    keyhole = Image.new("L", (canvas, canvas), 0)
    kd = ImageDraw.Draw(keyhole)
    kcx = cx
    kcy = cy + lh * 0.45 + bh * 0.40
    r = bh * 0.16
    kd.ellipse([kcx - r, kcy - r, kcx + r, kcy + r], fill=255)
    kd.rounded_rectangle(
        [kcx - r * 0.55, kcy, kcx + r * 0.55, kcy + bh * 0.36],
        radius=r * 0.55, fill=255,
    )
    grad.paste((0, 0, 0, 0), (0, 0), keyhole)
    return grad


def neon_halo(canvas: int) -> Image.Image:
    """Soft cyan glow behind the mark."""
    halo = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    d = ImageDraw.Draw(halo)
    r = canvas * 0.40
    cx = canvas / 2
    cy = canvas * 0.45
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=GRAD_MID + (70,))
    return halo.filter(ImageFilter.GaussianBlur(canvas * 0.09))


def main() -> None:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "assets", "branding")
    os.makedirs(out_dir, exist_ok=True)

    # ── Full opaque icon ────────────────────────────────────────
    base = vertical_bg(W).convert("RGBA")
    base.alpha_composite(neon_halo(W))
    base.alpha_composite(build_mark(W, inset=0.62))
    icon = base.resize((S, S), Image.LANCZOS).convert("RGB")
    icon_path = os.path.join(out_dir, "veilchat_icon.png")
    icon.save(icon_path, format="PNG", optimize=True)

    # ── Adaptive foreground (transparent, extra safe-zone padding) ──
    fg = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    fg.alpha_composite(build_mark(W, inset=0.44))
    fg_path = os.path.join(out_dir, "veilchat_icon_foreground.png")
    fg.resize((S, S), Image.LANCZOS).save(fg_path, format="PNG", optimize=True)

    print(f"[ok] {icon_path}")
    print(f"[ok] {fg_path}")


if __name__ == "__main__":
    main()
