#!/usr/bin/env python3
"""
Synthetic Draw-List Rasterizer & Geometric Auditor for SoulspireXI WS Talent UI.

Reads JSON draw lists captured from the LIVE Lua `talent_tree_ui.render()` engine,
audits hitbox overlaps & window-bound clipping, and rasterizes crisp RGBA PNG
previews using only the Python standard library (zero external dependencies).

NOTE: Output PNGs are synthetic draw-list previews rendered from the actual Lua
ImGui draw commands, NOT live FFXI gameplay captures.
"""

import glob
import json
import math
import os
import struct
import sys
import zlib

# Compact 5x7 ASCII bitmap font (32..126)
FONT_5X7 = {
    ' ': [0,0,0,0,0,0,0],
    '!': [4,4,4,4,4,0,4],
    '"': [10,10,0,0,0,0,0],
    '#': [10,31,10,10,31,10,0],
    '$': [4,15,20,14,5,30,4],
    '%': [24,25,2,4,8,19,3],
    '&': [12,18,20,8,21,18,13],
    "'": [4,4,0,0,0,0,0],
    '(': [2,4,8,8,8,4,2],
    ')': [8,4,2,2,2,4,8],
    '*': [0,4,21,14,21,4,0],
    '+': [0,4,4,31,4,4,0],
    ',': [0,0,0,0,0,4,8],
    '-': [0,0,0,31,0,0,0],
    '.': [0,0,0,0,0,12,12],
    '/': [1,1,2,4,8,16,16],
    '0': [14,17,19,21,25,17,14],
    '1': [4,12,4,4,4,4,14],
    '2': [14,17,1,6,8,16,31],
    '3': [14,17,1,6,1,17,14],
    '4': [2,6,10,18,31,2,2],
    '5': [31,16,30,1,1,17,14],
    '6': [6,8,16,30,17,17,14],
    '7': [31,1,2,4,8,8,8],
    '8': [14,17,17,14,17,17,14],
    '9': [14,17,17,15,1,2,12],
    ':': [0,12,12,0,12,12,0],
    ';': [0,12,12,0,12,4,8],
    '<': [2,4,8,16,8,4,2],
    '=': [0,0,31,0,31,0,0],
    '>': [8,4,2,1,2,4,8],
    '?': [14,17,1,2,4,0,4],
    '@': [14,17,23,21,23,16,14],
    'A': [14,17,17,31,17,17,17],
    'B': [30,17,17,30,17,17,30],
    'C': [14,17,16,16,16,17,14],
    'D': [28,18,17,17,17,18,28],
    'E': [31,16,16,30,16,16,31],
    'F': [31,16,16,30,16,16,16],
    'G': [14,17,16,23,17,17,15],
    'H': [17,17,17,31,17,17,17],
    'I': [14,4,4,4,4,4,14],
    'J': [7,2,2,2,2,18,12],
    'K': [17,18,20,24,20,18,17],
    'L': [16,16,16,16,16,16,31],
    'M': [17,27,21,21,17,17,17],
    'N': [17,25,21,19,17,17,17],
    'O': [14,17,17,17,17,17,14],
    'P': [30,17,17,30,16,16,16],
    'Q': [14,17,17,17,21,18,13],
    'R': [30,17,17,30,20,18,17],
    'S': [15,16,16,14,1,1,30],
    'T': [31,4,4,4,4,4,4],
    'U': [17,17,17,17,17,17,14],
    'V': [17,17,17,17,17,10,4],
    'W': [17,17,17,21,21,27,17],
    'X': [17,17,10,4,10,17,17],
    'Y': [17,17,10,4,4,4,4],
    'Z': [31,1,2,4,8,16,31],
    '[': [14,8,8,8,8,8,14],
    ']': [14,2,2,2,2,2,14],
    '_': [0,0,0,0,0,0,31],
    'a': [0,0,14,1,15,17,15],
    'b': [16,16,30,17,17,17,30],
    'c': [0,0,14,16,16,17,14],
    'd': [1,1,15,17,17,17,15],
    'e': [0,0,14,17,31,16,14],
    'f': [6,9,8,28,8,8,8],
    'g': [0,15,17,17,15,1,14],
    'h': [16,16,30,17,17,17,17],
    'i': [4,0,12,4,4,4,14],
    'j': [2,0,6,2,2,18,12],
    'k': [16,16,18,20,24,20,18],
    'l': [12,4,4,4,4,4,14],
    'm': [0,0,26,21,21,21,21],
    'n': [0,0,30,17,17,17,17],
    'o': [0,0,14,17,17,17,14],
    'p': [0,0,30,17,30,16,16],
    'q': [0,0,15,17,15,1,1],
    'r': [0,0,22,25,16,16,16],
    's': [0,0,15,16,14,1,30],
    't': [8,8,28,8,8,9,6],
    'u': [0,0,17,17,17,19,13],
    'v': [0,0,17,17,17,10,4],
    'w': [0,0,17,17,21,21,10],
    'x': [0,0,17,10,4,10,17],
    'y': [0,0,17,17,15,1,14],
    'z': [0,0,31,2,4,8,31],
    '|': [4,4,4,4,4,4,4],
}


class Canvas:
    def __init__(self, w, h):
        self.w = int(w)
        self.h = int(h)
        self.buf = bytearray(self.w * self.h * 4)

    def blend(self, x, y, r, g, b, a):
        if x < 0 or y < 0 or x >= self.w or y >= self.h or a <= 0:
            return
        idx = (y * self.w + x) * 4
        if a >= 255:
            self.buf[idx] = r
            self.buf[idx + 1] = g
            self.buf[idx + 2] = b
            self.buf[idx + 3] = 255
        else:
            inv = 255 - a
            self.buf[idx] = (r * a + self.buf[idx] * inv) // 255
            self.buf[idx + 1] = (g * a + self.buf[idx + 1] * inv) // 255
            self.buf[idx + 2] = (b * a + self.buf[idx + 2] * inv) // 255
            self.buf[idx + 3] = min(255, a + (self.buf[idx + 3] * inv) // 255)

    def rect_fill(self, x1, y1, x2, y2, col):
        r, g, b, a = col
        ix1 = max(0, int(round(min(x1, x2))))
        iy1 = max(0, int(round(min(y1, y2))))
        ix2 = min(self.w, int(round(max(x1, x2))))
        iy2 = min(self.h, int(round(max(y1, y2))))
        if a >= 255:
            row = bytes([r, g, b, 255]) * max(0, ix2 - ix1)
            for y in range(iy1, iy2):
                idx = (y * self.w + ix1) * 4
                self.buf[idx:idx + len(row)] = row
        else:
            for y in range(iy1, iy2):
                for x in range(ix1, ix2):
                    self.blend(x, y, r, g, b, a)

    def rect_grad(self, x1, y1, x2, y2, c1, c2, c3, c4):
        ix1 = max(0, int(round(min(x1, x2))))
        iy1 = max(0, int(round(min(y1, y2))))
        ix2 = min(self.w, int(round(max(x1, x2))))
        iy2 = min(self.h, int(round(max(y1, y2))))
        h = max(1, iy2 - iy1)
        for y in range(iy1, iy2):
            ty = (y - iy1) / h
            r = int((c1[0] + c2[0]) * 0.5 * (1 - ty) + (c3[0] + c4[0]) * 0.5 * ty)
            g = int((c1[1] + c2[1]) * 0.5 * (1 - ty) + (c3[1] + c4[1]) * 0.5 * ty)
            b = int((c1[2] + c2[2]) * 0.5 * (1 - ty) + (c3[2] + c4[2]) * 0.5 * ty)
            a = int((c1[3] + c2[3]) * 0.5 * (1 - ty) + (c3[3] + c4[3]) * 0.5 * ty)
            for x in range(ix1, ix2):
                self.blend(x, y, r, g, b, a)

    def rect(self, x1, y1, x2, y2, col, t=1):
        t = max(1, int(round(t)))
        self.rect_fill(x1, y1, x2, y1 + t, col)
        self.rect_fill(x1, y2 - t, x2, y2, col)
        self.rect_fill(x1, y1, x1 + t, y2, col)
        self.rect_fill(x2 - t, y1, x2, y2, col)

    def line(self, x1, y1, x2, y2, col, t=1):
        r, g, b, a = col
        dx = x2 - x1
        dy = y2 - y1
        steps = max(1, int(math.hypot(dx, dy)))
        rad = max(0, int(round(t * 0.5)))
        for i in range(steps + 1):
            px = int(round(x1 + dx * i / steps))
            py = int(round(y1 + dy * i / steps))
            for oy in range(-rad, rad + 1):
                for ox in range(-rad, rad + 1):
                    self.blend(px + ox, py + oy, r, g, b, a)

    def circle_fill(self, cx, cy, rad, col):
        r, g, b, a = col
        ir = int(math.ceil(rad))
        r2 = rad * rad
        icx, icy = int(round(cx)), int(round(cy))
        for oy in range(-ir, ir + 1):
            for ox in range(-ir, ir + 1):
                if ox * ox + oy * oy <= r2:
                    self.blend(icx + ox, icy + oy, r, g, b, a)

    def circle(self, cx, cy, rad, col, t=1):
        r, g, b, a = col
        ir = int(math.ceil(rad + t))
        r_in = max(0, rad - t) ** 2
        r_out = (rad + t * 0.5) ** 2
        icx, icy = int(round(cx)), int(round(cy))
        for oy in range(-ir, ir + 1):
            for ox in range(-ir, ir + 1):
                d2 = ox * ox + oy * oy
                if r_in <= d2 <= r_out:
                    self.blend(icx + ox, icy + oy, r, g, b, a)

    def poly(self, pts, col, t=1):
        n = len(pts)
        for i in range(n):
            p1 = pts[i]
            p2 = pts[(i + 1) % n]
            self.line(p1[0], p1[1], p2[0], p2[1], col, t)

    def poly_fill(self, pts, col):
        if len(pts) < 3:
            return
        ys = [p[1] for p in pts]
        y_min = max(0, int(math.floor(min(ys))))
        y_max = min(self.h - 1, int(math.ceil(max(ys))))
        r, g, b, a = col
        n = len(pts)
        for y in range(y_min, y_max + 1):
            xs = []
            for i in range(n):
                x1, y1 = pts[i]
                x2, y2 = pts[(i + 1) % n]
                if (y1 <= y < y2) or (y2 <= y < y1):
                    xs.append(x1 + (y - y1) * (x2 - x1) / (y2 - y1))
            xs.sort()
            for j in range(0, len(xs) - 1, 2):
                for x in range(max(0, int(xs[j])), min(self.w, int(xs[j + 1]) + 1)):
                    self.blend(x, y, r, g, b, a)

    def text(self, x, y, text, col):
        r, g, b, a = col
        cx = int(round(x))
        cy = int(round(y)) + 2
        for ch in str(text):
            if ord(ch) > 127:
                # Render common UTF-8 glyphs cleanly
                if ch in ('·', '•'):
                    self.circle_fill(cx + 2, cy + 3, 1.2, col)
                    cx += 6
                    continue
                elif ch in ('★', '✦', '◆'):
                    self.poly_fill([(cx+3, cy), (cx+6, cy+3), (cx+3, cy+6), (cx, cy+3)], col)
                    cx += 7
                    continue
                else:
                    ch = '-'
            glyph = FONT_5X7.get(ch, FONT_5X7.get(ch.upper(), FONT_5X7[' ']))
            for row_i, bits in enumerate(glyph):
                for col_i in range(5):
                    if bits & (1 << (4 - col_i)):
                        self.blend(cx + col_i, cy + row_i, r, g, b, a)
            cx += 6

    def save_png(self, path):
        raw = bytearray()
        stride = self.w * 4
        for y in range(self.h):
            raw.append(0)
            start = y * stride
            raw.extend(self.buf[start:start + stride])

        def chunk(tag, data):
            return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)

        ihdr = struct.pack('>IIBBBBB', self.w, self.h, 8, 6, 0, 0, 0)
        png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', zlib.compress(bytes(raw), 6)) + chunk(b'IEND', b'')
        with open(path, 'wb') as f:
            f.write(png)


def audit_scene(data):
    issues = []
    w, h = data['width'], data['height']
    node_boxes = [hb for hb in data.get('hitboxes', []) if str(hb.get('id', '')).startswith('##node_')]
    # Check pairwise node hitbox overlap
    for i in range(len(node_boxes)):
        a = node_boxes[i]
        for j in range(i + 1, len(node_boxes)):
            b = node_boxes[j]
            if (a['x'] < b['x'] + b['w'] and a['x'] + a['w'] > b['x'] and
                a['y'] < b['y'] + b['h'] and a['y'] + a['h'] > b['y']):
                issues.append(f"NODE_OVERLAP: {a['id']} overlaps {b['id']}")
    # Check out-of-bounds hitboxes & internal ID leaks in text
    for hb in node_boxes:
        if hb['x'] < 0 or hb['y'] < 0 or hb['x'] + hb['w'] > w or hb['y'] + hb['h'] > h:
            issues.append(f"NODE_OOB: {hb['id']} ({hb['x']},{hb['y']},{hb['w']}x{hb['h']}) outside {w}x{h}")
    for cmd in data.get('commands', []):
        if cmd.get('op') == 'text':
            t = cmd.get('text', '')
            if 'OX_' in t or 'ox_' in t:
                issues.append(f"INTERNAL_ID_LEAK: {t}")
    return issues


def render_file(json_path, png_path):
    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    issues = audit_scene(data)
    c = Canvas(data['width'], data['height'])
    for cmd in data['commands']:
        op = cmd['op']
        if op == 'rect_fill':
            c.rect_fill(cmd['x1'], cmd['y1'], cmd['x2'], cmd['y2'], cmd['col'])
        elif op == 'rect_grad':
            c.rect_grad(cmd['x1'], cmd['y1'], cmd['x2'], cmd['y2'], cmd['c1'], cmd['c2'], cmd['c3'], cmd['c4'])
        elif op == 'rect':
            c.rect(cmd['x1'], cmd['y1'], cmd['x2'], cmd['y2'], cmd['col'], cmd.get('t', 1))
        elif op == 'line':
            c.line(cmd['x1'], cmd['y1'], cmd['x2'], cmd['y2'], cmd['col'], cmd.get('t', 1))
        elif op == 'circle_fill':
            c.circle_fill(cmd['cx'], cmd['cy'], cmd['rad'], cmd['col'])
        elif op == 'circle':
            c.circle(cmd['cx'], cmd['cy'], cmd['rad'], cmd['col'], cmd.get('t', 1))
        elif op == 'poly':
            c.poly(cmd['pts'], cmd['col'], cmd.get('t', 1))
        elif op == 'poly_fill':
            c.poly_fill(cmd['pts'], cmd['col'])
        elif op == 'text':
            c.text(cmd['x'], cmd['y'], cmd['text'], cmd['col'])
        elif op == 'image':
            # Framed crest placeholder for embedded PNG asset in synthetic preview
            x1, y1, x2, y2 = cmd['x1'], cmd['y1'], cmd['x2'], cmd['y2']
            c.rect_fill(x1, y1, x2, y2, [28, 38, 68, 240])
            c.rect(x1, y1, x2, y2, [232, 189, 112, 230], 1)
            mx, my = (x1 + x2) * 0.5, (y1 + y2) * 0.5
            rad = min(x2 - x1, y2 - y1) * 0.32
            c.poly_fill([(mx, my - rad), (mx + rad, my), (mx, my + rad), (mx - rad, my)], [168, 85, 247, 230])
            c.poly([(mx, my - rad), (mx + rad, my), (mx, my + rad), (mx - rad, my)], [251, 191, 36, 255], 1)

    # Clear synthetic preview label in bottom-right corner
    wm = 'SYNTHETIC DRAW-LIST PREVIEW (NOT LIVE FFXI)'
    c.text(data['width'] - len(wm) * 6 - 10, data['height'] - 13, wm, [148, 163, 184, 180])
    c.save_png(png_path)
    return issues


def main():
    in_dir = sys.argv[1]
    files = sorted(glob.glob(os.path.join(in_dir, '*.json')))
    total_issues = 0
    for jf in files:
        pf = jf[:-5] + '.png'
        issues = render_file(jf, pf)
        status = 'PASS' if not issues else f'ISSUES({len(issues)})'
        print(f'[RENDER] {os.path.basename(pf)} -> {status}')
        for iss in issues:
            print(f'   ! {iss}')
            total_issues += 1
    if total_issues > 0:
        sys.exit(2)


if __name__ == '__main__':
    main()
