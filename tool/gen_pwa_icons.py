#!/usr/bin/env python3
"""Generate maskable PWA icons (192/512) with pure Python - no dependencies."""
import pathlib, struct, zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / 'webapp'
OUT.mkdir(exist_ok=True)

CRIMSON = (184, 72, 60, 255)   # app expense/crimson brand
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)

# 7x7 block glyph for "D"
GLYPH = [
    '0111110',
    '0100010',
    '0100010',
    '0100010',
    '0100010',
    '0100010',
    '0111110',
]

def in_rounded(x, y, n, r):
    if x < r and y < r: return (x-r)**2 + (y-r)**2 <= r*r
    if x > n-r-1 and y < r: return (x-(n-r-1))**2 + (y-r)**2 <= r*r
    if x < r and y > n-r-1: return (x-r)**2 + (y-(n-r-1))**2 <= r*r
    if x > n-r-1 and y > n-r-1: return (x-(n-r-1))**2 + (y-(n-r-1))**2 <= r*r
    return True

def png(n):
    r = int(n * 0.22)
    cell = n / 16
    gx, gy = (n - 7*cell)/2, (n - 7*cell)/2
    rows = []
    for y in range(n):
        row = bytearray([0])
        for x in range(n):
            c = CRIMSON if in_rounded(x, y, n, r) else CLEAR
            gxx = int((x - gx) / cell)
            gyy = int((y - gy) / cell)
            if 0 <= gxx < 7 and 0 <= gyy < 7 and GLYPH[gyy][gxx] == '1':
                c = WHITE
            row.extend(bytes(c))
        rows.append(bytes(row))
    raw = b''.join(rows)
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', n, n, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9))
            + chunk(b'IEND', b''))

for size in (192, 512):
    p = OUT / f'icon-{size}.png'
    p.write_bytes(png(size))
    print(f'wrote {p.relative_to(ROOT)}')
