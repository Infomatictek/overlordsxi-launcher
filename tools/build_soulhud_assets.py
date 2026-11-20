#!/usr/bin/env python3
"""
SoulspireXI Soul HUD art builder (Crystal Job Gauge).

Generates 4x-supersampled, Lanczos-downsampled RGBA PNG sprites in the same facet-cut /
beveled-metal style as crystalsocket/assets/*.png and build_custom_status_dats.py into
addons/ashita4/soulspire_soulhud/assets/ui/, then syncs the shared crystal icons and custom
status icons into the addon's assets/ folder.

Sprites:
  socket_{tank,healer,support,damage}.png  72x72   medallion ring + dark facet backing
  gem_{empty,gold,crimson,azure,emerald,violet}.png  22x22   facet-cut stack pips
  bar_frame.png, bar_gloss_overlay.png     220x22  tapered metal gauge frame / glass gloss
  buff_ring_gold.png                       36x36   beveled gold frame for 28x28 status icons

Layout constants shared with soulhud_gauge.lua (keep in sync):
  bar trough rect inside 220x22 : x=15 y=5 w=190 h=12
  socket crystal window         : centered, ~44px diameter in the 72px sprite
  socket ABR plate              : x=22..50 y=59..70 in the 72px sprite

Usage:  python tools/build_soulhud_assets.py
"""

from __future__ import annotations

import math
import shutil
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 4  # supersample factor

REPO = Path(__file__).resolve().parent.parent
ADDON = REPO / "addons" / "ashita4" / "soulspire_soulhud"
UI_OUT = ADDON / "assets" / "ui"

RGB = tuple[int, int, int]


# --------------------------------------------------------------------------- helpers
def mix(a: RGB, b: RGB, t: float) -> RGB:
    t = max(0.0, min(1.0, t))
    return (int(a[0] + (b[0] - a[0]) * t), int(a[1] + (b[1] - a[1]) * t), int(a[2] + (b[2] - a[2]) * t))


def shade(c: RGB, f: float) -> RGB:
    """f<1 darkens toward black, f>1 lightens toward white."""
    if f <= 1.0:
        return mix((0, 0, 0), c, f)
    return mix(c, (255, 255, 255), f - 1.0)


def canvas(w: int, h: int) -> Image.Image:
    return Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))


def sc(pts):
    return [(x * S, y * S) for x, y in pts]


def vgrad_layer(size, y0: float, y1: float, c0: RGB, c1: RGB) -> Image.Image:
    """Vertical gradient RGBA layer; y0/y1 in supersampled px."""
    w, h = size
    layer = Image.new("RGBA", size, c1 + (255,))
    d = ImageDraw.Draw(layer)
    span = max(1.0, y1 - y0)
    for y in range(h):
        d.line([(0, y), (w, y)], fill=mix(c0, c1, (y - y0) / span) + (255,))
    return layer


def poly_fill(img: Image.Image, pts, color: RGB, alpha: int = 255) -> None:
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).polygon(sc(pts), fill=color + (alpha,))
    img.alpha_composite(layer)


def poly_grad(img: Image.Image, pts, c0: RGB, c1: RGB, y0: float, y1: float) -> None:
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon(sc(pts), fill=255)
    g = vgrad_layer(img.size, y0 * S, y1 * S, c0, c1)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    layer.paste(g, (0, 0), mask)
    img.alpha_composite(layer)


def poly_line(img: Image.Image, pts, color: RGB, width: float = 1.0, alpha: int = 255, closed: bool = True) -> None:
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    p = sc(pts)
    if closed:
        p = p + [p[0]]
    d.line(p, fill=color + (alpha,), width=max(1, int(width * S)), joint="curve")
    img.alpha_composite(layer)


def blurred(img: Image.Image, layer: Image.Image, radius: float) -> None:
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(radius * S)))


def finish(img: Image.Image, w: int, h: int, path: Path) -> None:
    out = img.resize((w, h), Image.LANCZOS)
    path.parent.mkdir(parents=True, exist_ok=True)
    out.save(path, optimize=True)


def circle_pts(cx, cy, r, n, start=0.0):
    return [(cx + r * math.cos(start + 2 * math.pi * i / n), cy + r * math.sin(start + 2 * math.pi * i / n)) for i in range(n)]


def sparkle(img: Image.Image, cx: float, cy: float, r: float, alpha: int = 255) -> None:
    """Four-point specular star."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    pts = [(cx, cy - r), (cx + r * 0.22, cy - r * 0.22), (cx + r, cy), (cx + r * 0.22, cy + r * 0.22),
           (cx, cy + r), (cx - r * 0.22, cy + r * 0.22), (cx - r, cy), (cx - r * 0.22, cy - r * 0.22)]
    d.polygon(sc(pts), fill=(255, 255, 255, alpha))
    img.alpha_composite(layer)


# --------------------------------------------------------------------------- palettes
# Role accents mirror crystalsocket/ui.lua's navy/silver/edge palette with role-specific metals.
ROLES = {
    #            body (gem/band)    deep backing        metal (burnished trim)
    "tank":    {"body": (62, 112, 214), "deep": (10, 22, 52),  "metal": (214, 172, 78)},    # cobalt/steel + burnished gold
    "healer":  {"body": (52, 196, 128), "deep": (8, 40, 30),   "metal": (222, 212, 160)},   # emerald/pearl + silver-gold
    "support": {"body": (150, 92, 220), "deep": (28, 14, 54),  "metal": (196, 152, 64)},    # royal violet/amber + brass
    "damage":  {"body": (214, 48, 66),  "deep": (44, 8, 16),   "metal": (232, 142, 54)},    # crimson/obsidian + ember gold
}

GEMS = {
    "gold":    {"light": (255, 236, 150), "mid": (232, 178, 56),  "dark": (130, 78, 14)},
    "crimson": {"light": (255, 140, 150), "mid": (214, 40, 62),   "dark": (96, 8, 24)},
    "azure":   {"light": (150, 214, 255), "mid": (50, 128, 232),  "dark": (14, 40, 120)},
    "emerald": {"light": (160, 255, 196), "mid": (36, 190, 108),  "dark": (6, 80, 46)},
    "violet":  {"light": (222, 176, 255), "mid": (140, 78, 214),  "dark": (52, 18, 110)},
}


# --------------------------------------------------------------------------- medallion socket
def build_socket(role: str) -> Image.Image:
    pal = ROLES[role]
    body, deep, metal = pal["body"], pal["deep"], pal["metal"]
    W = H = 72
    img = canvas(W, H)
    cx = cy = 36.0
    light_dir = math.radians(225)  # light from upper-left

    # soft drop shadow
    sh = canvas(W, H)
    ImageDraw.Draw(sh).ellipse([(cx - 35 + 0.5) * S, (cy - 35 + 1.5) * S, (cx + 35 + 0.5) * S, (cy + 35 + 1.5) * S], fill=(0, 0, 0, 150))
    blurred(img, sh, 1.2)

    # outer beveled metal ring, 24 facets
    n = 24
    for i in range(n):
        a0 = 2 * math.pi * i / n
        a1 = 2 * math.pi * (i + 1) / n
        am = (a0 + a1) / 2
        lit = (math.cos(am - light_dir) + 1) / 2
        f = 0.55 + 0.75 * lit + (0.06 if i % 2 else -0.04)
        col = shade(metal, f)
        pts = [(cx + 35 * math.cos(a0), cy + 35 * math.sin(a0)), (cx + 35 * math.cos(a1), cy + 35 * math.sin(a1)),
               (cx + 28.5 * math.cos(a1), cy + 28.5 * math.sin(a1)), (cx + 28.5 * math.cos(a0), cy + 28.5 * math.sin(a0))]
        poly_fill(img, pts, col)
        # thin facet edge for crisp cut
        poly_line(img, pts[0:2], shade(col, 1.18), 0.5, 140, closed=False)
    poly_line(img, circle_pts(cx, cy, 35, 96), shade(metal, 0.28), 1.0, 230)

    # inset inner bevel (lighting reversed -> reads as a groove)
    for i in range(n):
        a0 = 2 * math.pi * i / n
        a1 = 2 * math.pi * (i + 1) / n
        am = (a0 + a1) / 2
        lit = (math.cos(am - light_dir + math.pi) + 1) / 2
        col = shade(mix(metal, deep, 0.45), 0.5 + 0.7 * lit)
        pts = [(cx + 28.5 * math.cos(a0), cy + 28.5 * math.sin(a0)), (cx + 28.5 * math.cos(a1), cy + 28.5 * math.sin(a1)),
               (cx + 26 * math.cos(a1), cy + 26 * math.sin(a1)), (cx + 26 * math.cos(a0), cy + 26 * math.sin(a0))]
        poly_fill(img, pts, col)

    # role-colored glowing band
    glow = canvas(W, H)
    ImageDraw.Draw(glow).ellipse([(cx - 25.5) * S, (cy - 25.5) * S, (cx + 25.5) * S, (cy + 25.5) * S], outline=body + (255,), width=int(2.2 * S))
    blurred(img, glow, 1.4)
    for i in range(n):
        a0 = 2 * math.pi * i / n
        a1 = 2 * math.pi * (i + 1) / n
        lit = (math.cos((a0 + a1) / 2 - light_dir) + 1) / 2
        col = shade(body, 0.7 + 0.55 * lit)
        pts = [(cx + 26 * math.cos(a0), cy + 26 * math.sin(a0)), (cx + 26 * math.cos(a1), cy + 26 * math.sin(a1)),
               (cx + 24.2 * math.cos(a1), cy + 24.2 * math.sin(a1)), (cx + 24.2 * math.cos(a0), cy + 24.2 * math.sin(a0))]
        poly_fill(img, pts, col)

    # dark facet backing: 16-triangle fan around the crystal window
    m = 16
    ring = circle_pts(cx, cy, 24.2, m, start=math.radians(11.25))
    for i in range(m):
        p0, p1 = ring[i], ring[(i + 1) % m]
        am = math.atan2((p0[1] + p1[1]) / 2 - cy, (p0[0] + p1[0]) / 2 - cx)
        lit = (math.cos(am - light_dir) + 1) / 2
        col = mix(shade(deep, 0.55 + 0.5 * lit), (6, 6, 12), 0.18 if i % 2 else 0.0)
        poly_fill(img, [(cx, cy), p0, p1], col)
    # backlight so the crystal icon pops
    bl = canvas(W, H)
    ImageDraw.Draw(bl).ellipse([(cx - 15) * S, (cy - 15) * S, (cx + 15) * S, (cy + 15) * S], fill=mix(deep, body, 0.45) + (170,))
    blurred(img, bl, 6)
    # facet lines
    for i in range(m):
        poly_line(img, [(cx, cy), ring[i]], shade(body, 0.45), 0.5, 70, closed=False)
    poly_line(img, circle_pts(cx, cy, 24.2, 96), shade(body, 0.35), 0.8, 200)

    # N/E/S/W diamond studs
    for ang in (-90, 0, 90, 180):
        a = math.radians(ang)
        sx, sy = cx + 31.8 * math.cos(a), cy + 31.8 * math.sin(a)
        r = 2.5
        poly_fill(img, [(sx, sy - r), (sx + r, sy), (sx, sy + r), (sx - r, sy)], shade(metal, 1.35))
        poly_fill(img, [(sx, sy - r), (sx + r, sy), (sx, sy)], shade(metal, 0.7))
        poly_line(img, [(sx, sy - r), (sx + r, sy), (sx, sy + r), (sx - r, sy)], shade(metal, 0.3), 0.5, 220)

    # specular arc, upper left rim
    spec = canvas(W, H)
    ImageDraw.Draw(spec).arc([(cx - 33) * S, (cy - 33) * S, (cx + 33) * S, (cy + 33) * S], 195, 262, fill=(255, 255, 255, 190), width=int(1.3 * S))
    blurred(img, spec, 0.35)

    # ABR plate (bottom rim): chamfered metal bar with dark recessed text well
    plate = [(22, 61.5), (24.5, 59.5), (47.5, 59.5), (50, 61.5), (50, 67.5), (47.5, 70), (24.5, 70), (22, 67.5)]
    poly_grad(img, plate, shade(metal, 1.25), shade(metal, 0.5), 59.5, 70)
    poly_line(img, plate, shade(metal, 0.25), 0.8, 240)
    well = [(25, 62.4), (26.2, 61.3), (45.8, 61.3), (47, 62.4), (47, 66.6), (45.8, 68.2), (26.2, 68.2), (25, 66.6)]
    poly_grad(img, well, shade(deep, 0.55), shade(deep, 1.0), 61.3, 68.2)
    poly_line(img, well, shade(body, 0.55), 0.6, 220)
    poly_line(img, [(23.5, 60.8), (48.5, 60.8)], (255, 255, 255), 0.5, 120, closed=False)
    return img


# --------------------------------------------------------------------------- stack gems
def hex_pts(cx, cy, r, rot_deg=-90):
    return [(cx + r * math.cos(math.radians(rot_deg + 60 * i)), cy + r * math.sin(math.radians(rot_deg + 60 * i))) for i in range(6)]


def build_gem(kind: str) -> Image.Image:
    W = H = 22
    img = canvas(W, H)
    cx = cy = 11.0
    light_dir = math.radians(225)
    lit = kind != "empty"
    pal = GEMS.get(kind)

    # glow halo (lit only)
    if lit:
        halo = canvas(W, H)
        ImageDraw.Draw(halo).ellipse([(cx - 9.5) * S, (cy - 9.5) * S, (cx + 9.5) * S, (cy + 9.5) * S], fill=pal["mid"] + (200,))
        blurred(img, halo, 2.2)

    # drop shadow under bezel
    shd = canvas(W, H)
    poly_fill(shd, hex_pts(cx, cy + 0.8, 10.0), (0, 0, 0), 170)
    blurred(img, shd, 0.6)

    # bezel: 6 trapezoid facets (brass/steel)
    outer = hex_pts(cx, cy, 10.2)
    mid = hex_pts(cx, cy, 7.6)
    metal = (206, 168, 84) if lit else (120, 112, 104)
    for i in range(6):
        am = math.radians(-60 + 60 * i)  # facet centre angle
        l = (math.cos(am - light_dir) + 1) / 2
        col = shade(metal, 0.5 + 0.8 * l)
        poly_fill(img, [outer[i], outer[(i + 1) % 6], mid[(i + 1) % 6], mid[i]], col)
    poly_line(img, outer, shade(metal, 0.25), 0.7, 235)

    # gem body
    inner = hex_pts(cx, cy, 7.4)
    table = hex_pts(cx, cy, 3.5, rot_deg=-60)  # rotated table for a brilliant-cut look
    if lit:
        # crown triangles between hex and table
        for i in range(6):
            am = math.radians(-90 + 60 * i + 30)
            l = (math.cos(am - light_dir) + 1) / 2
            col = mix(pal["dark"], pal["light"], 0.12 + 0.88 * l)
            poly_fill(img, [inner[i], inner[(i + 1) % 6], table[(i + 1) % 6], table[i]], col)
        for i in range(6):  # alternating pavilion tint
            p0, p1 = inner[i], inner[(i + 1) % 6]
            am = math.atan2((p0[1] + p1[1]) / 2 - cy, (p0[0] + p1[0]) / 2 - cx)
            l = (math.cos(am - light_dir) + 1) / 2
            poly_fill(img, [table[i], table[(i + 1) % 6], (cx, cy)], mix(pal["mid"], pal["light"], 0.2 + 0.7 * l))
        for i in range(6):
            poly_line(img, [inner[i], table[i]], pal["light"], 0.45, 170, closed=False)
        poly_line(img, table, pal["light"], 0.45, 200)
        poly_line(img, inner, shade(pal["dark"], 0.7), 0.6, 255)
        # inner glow bloom + specular
        bloom = canvas(W, H)
        ImageDraw.Draw(bloom).ellipse([(cx - 4.2) * S, (cy - 4.2) * S, (cx + 4.2) * S, (cy + 4.2) * S], fill=pal["light"] + (200,))
        blurred(img, bloom, 1.6)
        sparkle(img, cx - 2.3, cy - 3.0, 2.6, 255)
        sparkle(img, cx + 3.6, cy + 2.8, 1.0, 190)
    else:
        # dark recessed socket: inner shadow top-left, faint facet cuts
        poly_grad(img, inner, (10, 10, 18), (30, 30, 44), cy - 7.4, cy + 7.4)
        for i in range(6):
            poly_line(img, [inner[i], table[i]], (60, 62, 84), 0.4, 110, closed=False)
        poly_line(img, table, (52, 54, 74), 0.4, 120)
        poly_line(img, inner, (4, 4, 10), 0.9, 255)
        sh2 = canvas(W, H)
        poly_fill(sh2, [(cx - 7.4, cy - 4), (cx, cy - 7.4), (cx + 5, cy - 6), (cx + 4, cy - 3), (cx - 3, cy - 3.5)], (0, 0, 0), 150)
        blurred(img, sh2, 0.8)
        poly_line(img, [(cx - 2.5, cy + 6.4), (cx + 2.5, cy + 6.4)], (150, 150, 180), 0.5, 90, closed=False)
    return img


# --------------------------------------------------------------------------- gauge bar
BAR_W, BAR_H = 220, 22
TROUGH = (15, 5, 205, 17)  # x0, y0, x1, y1


def bar_outline(inset=0.0):
    return [(0 + inset, 11), (7 + inset * 0.6, 1 + inset), (213 - inset * 0.6, 1 + inset), (220 - inset, 11),
            (213 - inset * 0.6, 21 - inset), (7 + inset * 0.6, 21 - inset)]


def build_bar_frame() -> Image.Image:
    img = canvas(BAR_W, BAR_H)
    metal = (200, 176, 130)  # neutral silver-gold; role tint arrives via the fill
    shd = canvas(BAR_W, BAR_H)
    poly_fill(shd, [(x, y + 1.0) for x, y in bar_outline()], (0, 0, 0), 190)
    blurred(img, shd, 0.7)

    outline = bar_outline()
    poly_grad(img, outline, shade(metal, 1.3), shade(metal, 0.42), 1, 21)
    # top/bottom bevel bands for the faceted look
    poly_grad(img, [(7, 1), (213, 1), (210, 3.2), (10, 3.2)], (255, 244, 214), shade(metal, 1.0), 1, 3.2)
    poly_fill(img, [(10, 18.8), (210, 18.8), (213, 21), (7, 21)], shade(metal, 0.32))
    # tapered end-cap facets
    poly_fill(img, [(0, 11), (7, 1), (10, 3.2), (6, 11)], shade(metal, 0.95))
    poly_fill(img, [(0, 11), (6, 11), (10, 18.8), (7, 21)], shade(metal, 0.5))
    poly_fill(img, [(220, 11), (214, 11), (210, 3.2), (213, 1)], shade(metal, 0.75))
    poly_fill(img, [(220, 11), (213, 21), (210, 18.8), (214, 11)], shade(metal, 0.4))
    poly_line(img, outline, shade(metal, 0.2), 0.9, 255)

    # dark body surrounding the trough, then carve a transparent rect for the fill to show through
    body_poly = [(5.5, 11), (10, 3.2), (210, 3.2), (214.5, 11), (210, 18.8), (10, 18.8)]
    poly_grad(img, body_poly, (30, 24, 28), (10, 8, 12), 3.2, 18.8)
    x0, y0, x1, y1 = TROUGH
    carve = Image.new("L", img.size, 255)
    ImageDraw.Draw(carve).rectangle([x0 * S, y0 * S, x1 * S - 1, y1 * S - 1], fill=0)
    img.putalpha(ImageChops.multiply(img.getchannel("A"), carve))

    # inner shadow baked onto trough edges (alpha), recess highlight on lower lip
    inner = canvas(BAR_W, BAR_H)
    d = ImageDraw.Draw(inner)
    for k in range(5):
        a = int(150 * (1 - k / 5))
        d.rectangle([x0 * S, (y0 + k * 0.7) * S, x1 * S - 1, (y0 + k * 0.7 + 0.7) * S - 1], fill=(0, 0, 0, a))
    for k in range(3):
        a = int(110 * (1 - k / 3))
        d.rectangle([(x0 + k * 0.6) * S, y0 * S, (x0 + k * 0.6 + 0.6) * S - 1, y1 * S - 1], fill=(0, 0, 0, a))
        d.rectangle([(x1 - k * 0.6 - 0.6) * S, y0 * S, (x1 - k * 0.6) * S - 1, y1 * S - 1], fill=(0, 0, 0, a))
    d.rectangle([x0 * S, (y1 - 0.7) * S, x1 * S - 1, y1 * S - 1], fill=(255, 240, 200, 70))
    img.alpha_composite(inner)

    # engraved gold hairlines + diamond studs at both tips
    poly_line(img, [(14, 2.1), (206, 2.1)], (255, 246, 220), 0.5, 170, closed=False)
    for sx in (7.5, 212.5):
        r = 2.2
        poly_fill(img, [(sx, 11 - r), (sx + r, 11), (sx, 11 + r), (sx - r, 11)], shade(metal, 1.45))
        poly_fill(img, [(sx, 11 - r), (sx + r, 11), (sx, 11)], shade(metal, 0.7))
        poly_line(img, [(sx, 11 - r), (sx + r, 11), (sx, 11 + r), (sx - r, 11)], shade(metal, 0.2), 0.5, 230)
    return img


def build_bar_gloss() -> Image.Image:
    img = canvas(BAR_W, BAR_H)
    x0, y0, x1, y1 = TROUGH
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    mid = (y0 + y1) / 2
    # glass highlight over top half of the trough
    rows = int((mid - y0) * S)
    for r in range(rows):
        t = r / max(1, rows - 1)
        d.rectangle([x0 * S, y0 * S + r, x1 * S - 1, y0 * S + r], fill=(255, 255, 255, int(120 * (1 - t) + 18 * t)))
    # soft shade over the bottom half
    rows = int((y1 - mid) * S)
    for r in range(rows):
        t = r / max(1, rows - 1)
        d.rectangle([x0 * S, mid * S + r, x1 * S - 1, mid * S + r], fill=(0, 0, 0, int(8 + 52 * t)))
    # diagonal specular streaks
    streaks = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(streaks)
    for sx, w in ((28, 9), (118, 5)):
        sd.polygon(sc([(sx, y0), (sx + w, y0), (sx + w - 4, y1), (sx - 4, y1)]), fill=(255, 255, 255, 52))
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rectangle([x0 * S, y0 * S, x1 * S - 1, y1 * S - 1], fill=255)
    streaks.putalpha(ImageChops.multiply(streaks.getchannel("A"), mask))
    img.alpha_composite(layer)
    img.alpha_composite(streaks)
    # bright rim along the top bevel of the frame
    rim = canvas(BAR_W, BAR_H)
    poly_line(rim, [(10, 2.0), (210, 2.0)], (255, 255, 255), 0.6, 150, closed=False)
    img.alpha_composite(rim)
    return img


# --------------------------------------------------------------------------- buff ring
def build_buff_ring() -> Image.Image:
    W = H = 36
    img = canvas(W, H)
    metal = (212, 172, 80)
    c = 4.0
    outer = [(c, 0.5), (W - c, 0.5), (W - 0.5, c), (W - 0.5, H - c), (W - c, H - 0.5), (c, H - 0.5), (0.5, H - c), (0.5, c)]
    inner = [(5.5, 4), (W - 5.5, 4), (W - 4, 5.5), (W - 4, H - 5.5), (W - 5.5, H - 4), (5.5, H - 4), (4, H - 5.5), (4, 5.5)]
    shd = canvas(W, H)
    poly_fill(shd, [(x, y + 0.6) for x, y in outer], (0, 0, 0), 150)
    blurred(img, shd, 0.5)
    # eight bevel facets between outer and inner octagon
    tones = [1.35, 1.0, 0.8, 0.55, 0.38, 0.5, 0.75, 1.1]
    for i in range(8):
        poly_fill(img, [outer[i], outer[(i + 1) % 8], inner[(i + 1) % 8], inner[i]], shade(metal, tones[i]))
    poly_line(img, outer, shade(metal, 0.22), 0.7, 255)
    carve = Image.new("L", img.size, 255)
    ImageDraw.Draw(carve).polygon(sc(inner), fill=0)
    inner_edge = canvas(W, H)
    poly_line(inner_edge, inner, (20, 12, 6), 0.9, 230)
    poly_line(inner_edge, [(5.5, 4.8), (W - 5.5, 4.8)], (0, 0, 0), 0.6, 120, closed=False)
    img.alpha_composite(inner_edge)
    img.putalpha(ImageChops.multiply(img.getchannel("A"), carve))
    # diamond studs on the corners and a top specular
    for sx, sy in ((c - 0.6, c - 0.6), (W - c + 0.6, c - 0.6), (W - c + 0.6, H - c + 0.6), (c - 0.6, H - c + 0.6)):
        r = 1.5
        poly_fill(img, [(sx, sy - r), (sx + r, sy), (sx, sy + r), (sx - r, sy)], shade(metal, 1.5))
    poly_line(img, [(8, 1.6), (W - 8, 1.6)], (255, 255, 255), 0.5, 170, closed=False)
    return img


# --------------------------------------------------------------------------- asset sync
def sync_tree(src: Path, dst: Path, label: str) -> int:
    if not src.exists():
        print(f"  [skip] {label}: {src} not found")
        return 0
    dst.mkdir(parents=True, exist_ok=True)
    n = 0
    for f in sorted(src.glob("*.png")):
        target = dst / f.name
        if not target.exists() or target.read_bytes() != f.read_bytes():
            shutil.copy2(f, target)
            n += 1
    print(f"  synced {label}: {n} updated, {len(list(dst.glob('*.png')))} total")
    return n


def main() -> None:
    print(f"Building Soul HUD sprites -> {UI_OUT}")
    for role in ROLES:
        finish(build_socket(role), 72, 72, UI_OUT / f"socket_{role}.png")
    for kind in ("empty", *GEMS.keys()):
        finish(build_gem(kind), 22, 22, UI_OUT / f"gem_{kind}.png")
    finish(build_bar_frame(), BAR_W, BAR_H, UI_OUT / "bar_frame.png")
    finish(build_bar_gloss(), BAR_W, BAR_H, UI_OUT / "bar_gloss_overlay.png")
    finish(build_buff_ring(), 36, 36, UI_OUT / "buff_ring_gold.png")
    print(f"  wrote {len(list(UI_OUT.glob('*.png')))} sprites")

    sync_tree(ADDON.parent / "crystalsocket" / "assets", ADDON / "assets" / "crystals", "crystalsocket icons")
    sync_tree(REPO / "assets" / "status_icons", ADDON / "assets" / "status_icons", "custom status icons")

    catalog_src = REPO / "assets" / "status_catalog.lua"
    if catalog_src.exists():
        shutil.copy2(catalog_src, ADDON / "status_catalog.lua")
        print("  synced status_catalog.lua")
    print("Done.")


if __name__ == "__main__":
    main()
