#!/usr/bin/env python3
"""
OverlordsXI Custom Status Icon & 57.DAT Builder.

Reads modules/custom/data/custom_status_manifest.json, generates 32x32 FFXI-styled
status icons (exported as PNGs under assets/status_icons/<iconId>.png), and patches
ROM/119/57.DAT with the encoded 32-bit BGRA icons (0x00..0x80 alpha) and English
hover tooltips.
"""

from __future__ import annotations

import argparse
import json
import math
import shutil
import struct
from pathlib import Path

from PIL import Image, ImageDraw

RECORD_SIZE = 6144
TEXT_OFFSET = 0x2C
TEXT_END = 0x280
IMG_HDR_OFFSET = 0x280
PIXEL_OFFSET = 0x2BD
PIXEL_SIZE = 32 * 32 * 4  # 4096 bytes

# Standard 44-byte header template (bytes 0x02..0x2B) from retail rol1 status records
STANDARD_HDR_TAIL = bytes.fromhex(
    "0000"
    "80000000"
    "06000000"
    "00000000"
    "80000000"
    "0000000000000000"
    "0000000000000000"
    "0000000000000000"
)

BITMAP_INFO_HEADER = struct.pack("<IIIHHIIIIII", 40, 32, 32, 1, 32, 0, 0, 0, 0, 0, 32)


def ror1(b: int) -> int:
    return ((b >> 1) | ((b & 1) << 7)) & 0xFF


def encode_ffxi_text(text: str, max_bytes: int) -> bytes:
    raw = text.encode("cp932", errors="replace")[: max_bytes - 1]
    encoded = bytes(ror1(b) for b in raw)
    return encoded.ljust(max_bytes, b"\x00")


def hex_to_rgb(hex_str: str) -> tuple[int, int, int]:
    h = hex_str.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def mix_rgb(c1: tuple[int, int, int], c2: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return (
        int(c1[0] * (1.0 - t) + c2[0] * t),
        int(c1[1] * (1.0 - t) + c2[1] * t),
        int(c1[2] * (1.0 - t) + c2[2] * t),
    )


def draw_motif(draw: ImageDraw.ImageDraw, motif: str, accent: tuple[int, int, int], hi: tuple[int, int, int], s: int = 4) -> None:
    """Draw a high-contrast silhouette glyph on a 32*s x 32*s supersampled canvas."""
    cx, cy = 16 * s, 16 * s

    def p(x: float, y: float) -> tuple[float, float]:
        return (x * s, y * s)

    if motif in ("shield_ward", "spartan_shield", "rune_shield", "blood_shield", "templar_shield", "gear_shield", "radiant_shield"):
        pts = [p(9, 8), p(23, 8), p(23, 17), p(16, 25), p(9, 17)]
        draw.polygon(pts, fill=accent, outline=hi)
        inner = [p(12, 11), p(20, 11), p(20, 16), p(16, 21), p(12, 16)]
        draw.polygon(inner, fill=mix_rgb(accent, (20, 20, 30), 0.45))
        if motif == "spartan_shield":
            draw.line([p(16, 10), p(16, 22)], fill=hi, width=2 * s)
            draw.line([p(11, 15), p(21, 15)], fill=hi, width=2 * s)
        elif motif in ("rune_shield", "radiant_shield", "templar_shield"):
            draw.polygon([p(16, 11), p(19, 15), p(16, 20), p(13, 15)], fill=hi)
        elif motif == "gear_shield":
            draw.ellipse([p(13, 12), p(19, 18)], outline=hi, width=2 * s)

    elif motif in ("sword_surge", "sun_sword", "rapier_arc", "fencing_thrust", "sheathed_blade"):
        draw.line([p(9, 23), p(22, 10)], fill=hi, width=3 * s)
        draw.polygon([p(20, 9), p(24, 8), p(23, 12)], fill=hi)
        draw.line([p(11, 17), p(15, 21)], fill=accent, width=2 * s)
        draw.line([p(8, 24), p(11, 21)], fill=accent, width=3 * s)
        if motif == "sun_sword":
            draw.ellipse([p(19, 8), p(24, 13)], outline=accent, width=s)

    elif motif in ("crossed_blades", "twin_shuriken", "ashura_crest"):
        draw.line([p(9, 23), p(23, 9)], fill=hi, width=2 * s)
        draw.line([p(9, 9), p(23, 23)], fill=accent, width=2 * s)
        draw.ellipse([p(14, 14), p(18, 18)], fill=hi)

    elif motif == "severed_blade":
        draw.line([p(9, 23), p(15, 17)], fill=accent, width=3 * s)
        draw.line([p(18, 14), p(23, 9)], fill=hi, width=3 * s)
        draw.line([p(13, 12), p(20, 19)], fill=(255, 80, 60), width=2 * s)

    elif motif == "shattered_armor":
        pts = [p(9, 9), p(23, 9), p(22, 22), p(16, 25), p(10, 22)]
        draw.polygon(pts, fill=accent, outline=hi)
        draw.line([p(17, 9), p(14, 15), p(18, 18), p(14, 24)], fill=(25, 10, 10), width=2 * s)

    elif motif == "crosshair_expose":
        draw.ellipse([p(9, 9), p(23, 23)], outline=accent, width=2 * s)
        draw.ellipse([p(14, 14), p(18, 18)], fill=hi)
        for a, b in [(p(16, 6), p(16, 12)), (p(16, 20), p(16, 26)), (p(6, 16), p(12, 16)), (p(20, 16), p(26, 16))]:
            draw.line([a, b], fill=hi, width=2 * s)

    elif motif in ("chain_burst", "astral_ring", "cosmic_sigil"):
        draw.ellipse([p(8, 11), p(17, 20)], outline=accent, width=2 * s)
        draw.ellipse([p(15, 11), p(24, 20)], outline=hi, width=2 * s)
        draw.polygon([p(16, 7), p(18, 12), p(16, 15), p(14, 12)], fill=hi)

    elif motif in ("dice_debt", "crown_dice", "card_pip"):
        draw.rounded_rectangle([p(9, 9), p(23, 23)], radius=3 * s, fill=accent, outline=hi, width=s)
        for px, py in [(12.5, 12.5), (19.5, 12.5), (16, 16), (12.5, 19.5), (19.5, 19.5)]:
            draw.ellipse([p(px - 1.3, py - 1.3), p(px + 1.3, py + 1.3)], fill=(20, 20, 25))
        if motif == "crown_dice":
            draw.polygon([p(10, 9), p(13, 5), p(16, 8), p(19, 5), p(22, 9)], fill=hi)

    elif motif in ("heart_cross", "leaf_heart", "rose_waltz"):
        draw.ellipse([p(9, 10), p(16, 17)], fill=accent)
        draw.ellipse([p(16, 10), p(23, 17)], fill=accent)
        draw.polygon([p(9, 14), p(23, 14), p(16, 23)], fill=accent)
        draw.line([p(16, 12), p(16, 19)], fill=hi, width=2 * s)
        draw.line([p(13, 15), p(19, 15)], fill=hi, width=2 * s)

    elif motif in ("light_cross", "chalice_glow", "angel_veil", "sanctuary_halo", "holy_crest"):
        draw.rectangle([p(14, 8), p(18, 24)], fill=hi)
        draw.rectangle([p(10, 12), p(22, 16)], fill=hi)
        draw.ellipse([p(9, 9), p(23, 23)], outline=accent, width=s)

    elif motif in ("lightning_rune", "overcharge_bolt", "azure_bolt", "flame_blade"):
        pts = [p(18, 7), p(11, 16), p(16, 16), p(13, 25), p(21, 15), p(16, 15)]
        draw.polygon(pts, fill=hi, outline=accent)

    elif motif in ("music_note", "double_note", "harp_wave", "sonic_burst", "iron_clef"):
        draw.ellipse([p(10, 18), p(15, 23)], fill=accent, outline=hi)
        draw.line([p(15, 20), p(15, 9)], fill=hi, width=2 * s)
        draw.line([p(15, 9), p(22, 11)], fill=hi, width=2 * s)
        if motif in ("double_note", "harp_wave", "sonic_burst"):
            draw.ellipse([p(18, 17), p(23, 22)], fill=accent, outline=hi)
            draw.line([p(22, 19), p(22, 11)], fill=hi, width=2 * s)

    elif motif in ("lotus_chi", "yin_yang_chi", "lifebinder_drop", "azure_orb", "water_spiral", "moon_sanctuary"):
        draw.ellipse([p(9, 9), p(23, 23)], fill=mix_rgb(accent, (20, 30, 45), 0.35), outline=hi, width=2 * s)
        draw.polygon([p(16, 10), p(21, 17), p(16, 22), p(11, 17)], fill=accent, outline=hi)

    elif motif in ("axe_fury", "wolf_fang", "claw_slash", "roar_wave"):
        draw.polygon([p(10, 9), p(22, 13), p(19, 23), p(13, 18)], fill=accent, outline=hi)
        draw.line([p(10, 22), p(21, 11)], fill=hi, width=2 * s)

    elif motif in ("bow_arrow", "katana_guard"):
        draw.arc([p(9, 8), p(21, 24)], start=270, end=90, fill=accent, width=2 * s)
        draw.line([p(15, 8), p(15, 24)], fill=hi, width=s)
        draw.line([p(9, 16), p(24, 16)], fill=hi, width=2 * s)

    elif motif in ("smoke_cloud", "white_wing", "wyvern_wing", "ribbon_veil"):
        draw.ellipse([p(8, 13), p(16, 21)], fill=accent)
        draw.ellipse([p(13, 10), p(22, 19)], fill=hi)
        draw.ellipse([p(16, 14), p(24, 22)], fill=accent)

    elif motif in ("canopy_leaf", "bark_plate", "dragon_scale", "azure_shell", "diamond_crest", "blood_shield", "dread_helm", "paw_emblem", "beast_link", "rune_burst", "ascendant_star"):
        draw.polygon([p(16, 7), p(24, 16), p(16, 25), p(8, 16)], fill=accent, outline=hi)
        draw.polygon([p(16, 11), p(20, 16), p(16, 21), p(12, 16)], fill=hi)

    else:
        draw.polygon([p(16, 8), p(23, 16), p(16, 24), p(9, 16)], fill=accent, outline=hi)


def render_icon(entry: dict) -> Image.Image:
    theme = entry["visualTheme"]
    role = theme["role"]
    border_rgb = hex_to_rgb(theme["border"])
    accent_rgb = hex_to_rgb(theme["accent"])
    hi_rgb = mix_rgb(accent_rgb, (255, 255, 255), 0.55)

    s = 4
    img = Image.new("RGBA", (32 * s, 32 * s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Outer FFXI-style beveled badge frame
    bg_dark = (28, 10, 14, 240) if role == "debuff" else (12, 16, 28, 240)
    rim_light = mix_rgb(border_rgb, (255, 255, 255), 0.4)
    rim_dark = mix_rgb(border_rgb, (0, 0, 0), 0.5)

    if role == "debuff":
        # Diamond/octagonal beveled debuff frame for instant visual distinction
        draw.rounded_rectangle([2 * s, 2 * s, 30 * s, 30 * s], radius=4 * s, fill=bg_dark, outline=rim_dark, width=2 * s)
        draw.rounded_rectangle([3 * s, 3 * s, 29 * s, 29 * s], radius=3 * s, outline=border_rgb, width=s)
        # Corner crimson ticks
        for cx, cy in [(4 * s, 4 * s), (28 * s, 4 * s), (4 * s, 28 * s), (28 * s, 28 * s)]:
            draw.ellipse([cx - 2 * s, cy - 2 * s, cx + 2 * s, cy + 2 * s], fill=border_rgb)
    else:
        draw.rounded_rectangle([2 * s, 2 * s, 30 * s, 30 * s], radius=5 * s, fill=bg_dark, outline=rim_dark, width=2 * s)
        draw.arc([2 * s, 2 * s, 30 * s, 30 * s], start=135, end=315, fill=rim_light, width=s)
        draw.rounded_rectangle([3 * s, 3 * s, 29 * s, 29 * s], radius=4 * s, outline=border_rgb, width=s)

    draw_motif(draw, theme["motif"], accent_rgb, hi_rgb, s=s)
    return img.resize((32, 32), Image.Resampling.LANCZOS)


def encode_icon_pixels(img: Image.Image) -> bytes:
    """Encode 32x32 RGBA image into bottom-up BGRA with FFXI 0x00..0x80 alpha."""
    rgba = img.convert("RGBA")
    px = rgba.load()
    buf = bytearray()
    for y in range(31, -1, -1):  # bottom-up BMP order
        for x in range(32):
            r, g, b, a = px[x, y]
            ffxi_a = (a * 128 + 127) // 255
            buf.extend((b, g, r, ffxi_a))
    assert len(buf) == PIXEL_SIZE
    return bytes(buf)


def build_record(entry: dict, img: Image.Image) -> bytes:
    icon_id = entry["iconId"]
    tooltip = entry["tooltip"]

    rec = bytearray(RECORD_SIZE)
    # 0x00..0x01: encoded iconId
    rec[0] = ror1(icon_id & 0xFF)
    rec[1] = ror1((icon_id >> 8) & 0xFF)
    rec[2:TEXT_OFFSET] = STANDARD_HDR_TAIL

    # 0x2C..0x280: encoded tooltip
    rec[TEXT_OFFSET:TEXT_END] = encode_ffxi_text(tooltip, TEXT_END - TEXT_OFFSET)

    # 0x280..0x2BD: image header
    tex_name = f"sts_iconox{icon_id:03d}_32".encode("ascii")[:16].ljust(16, b" ")
    rec[IMG_HDR_OFFSET : IMG_HDR_OFFSET + 4] = b"\x39\x10\x00\x00"
    rec[IMG_HDR_OFFSET + 4] = 0x91
    rec[IMG_HDR_OFFSET + 5 : IMG_HDR_OFFSET + 21] = tex_name
    rec[IMG_HDR_OFFSET + 21 : PIXEL_OFFSET] = BITMAP_INFO_HEADER

    # 0x2BD..0x12BD: 32x32 BGRA pixels
    rec[PIXEL_OFFSET : PIXEL_OFFSET + PIXEL_SIZE] = encode_icon_pixels(img)
    rec[RECORD_SIZE - 1] = 0xFF
    return bytes(rec)


def main() -> None:
    parser = argparse.ArgumentParser(description="Build OverlordsXI custom status icons and patch ROM/119/57.DAT.")
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path(r"C:\overlordsxi\modules\custom\data\custom_status_manifest.json"),
        help="Path to custom_status_manifest.json",
    )
    parser.add_argument(
        "--base-dat",
        type=Path,
        default=Path(r"D:\PlayOnline\SquareEnix\FINAL FANTASY XI\ROM\119\57.DAT"),
        help="Path to retail ROM/119/57.DAT used as base when overlay DAT is absent",
    )
    parser.add_argument(
        "--out-dat",
        type=Path,
        default=Path(r"C:\overlordsxi-launcher\dat-overlay\ROM\119\57.DAT"),
        help="Output patched 57.DAT path",
    )
    parser.add_argument(
        "--png-dir",
        type=Path,
        default=Path(r"C:\overlordsxi-launcher\assets\status_icons"),
        help="Output directory for 32x32 PNG icon copies",
    )
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    effects = manifest["effects"]

    args.out_dat.parent.mkdir(parents=True, exist_ok=True)
    args.png_dir.mkdir(parents=True, exist_ok=True)

    backup_dir = Path(__file__).resolve().parent / "backups"
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup_dat = backup_dir / "57.DAT.bak"
    if not backup_dat.exists():
        src = args.out_dat if args.out_dat.exists() else args.base_dat
        shutil.copy2(src, backup_dat)

    dat_bytes = bytearray(backup_dat.read_bytes())
    num_records = len(dat_bytes) // RECORD_SIZE

    for entry in effects:
        icon_id = entry["iconId"]
        if not (1 <= icon_id < 639) or icon_id in (0, 255, 511) or icon_id >= num_records:
            raise ValueError(f"Invalid iconId {icon_id} for effect {entry['effectId']}")

        img = render_icon(entry)
        img.save(args.png_dir / f"{icon_id}.png", format="PNG")

        rec = build_record(entry, img)
        start = icon_id * RECORD_SIZE
        dat_bytes[start : start + RECORD_SIZE] = rec

    args.out_dat.write_bytes(dat_bytes)
    print(f"Patched {len(effects)} status icons & tooltips into {args.out_dat}")
    print(f"Exported {len(effects)} 32x32 PNG icons to {args.png_dir}")
    print(f"Backup preserved at {backup_dat}")


if __name__ == "__main__":
    main()
