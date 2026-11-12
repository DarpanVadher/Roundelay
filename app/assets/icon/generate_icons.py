"""Regenerates legacy Android PNGs, the Windows .ico and preview PNGs from the mark geometry
in roundelay-icon.svg. Run from app/: python assets/icon/generate_icons.py (needs Pillow)."""
from PIL import Image, ImageDraw
import os

COBALT, WHITE, SUN = (36, 51, 255, 255), (255, 255, 255, 255), (255, 216, 74, 255)
SS = 4  # supersampling

def tile(size, round_mask=False, full_bleed=False):
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if full_bleed:
        d.rectangle([0, 0, s, s], fill=COBALT)
    elif round_mask:
        d.ellipse([0, 0, s - 1, s - 1], fill=COBALT)
    else:
        d.rounded_rectangle([0, 0, s - 1, s - 1], radius=s * 24 / 108, fill=COBALT)
    u = s / 108 * 1.3  # mark scale (1.3x of the 108 grid)
    c = s / 2
    for r in (24, 13.5):
        d.ellipse([c - r * u, c - r * u, c + r * u, c + r * u], outline=WHITE, width=round(5 * u))
    r = 5 * u
    d.ellipse([c - r, c - r, c + r, c + r], fill=SUN)
    return img.resize((size, size), Image.LANCZOS)

res = "android/app/src/main/res"
for dens, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    tile(px).save(f"{res}/mipmap-{dens}/ic_launcher.png")
    tile(px, True).save(f"{res}/mipmap-{dens}/ic_launcher_round.png")
sizes = [16, 24, 32, 48, 64, 128, 256]
tile(256).save("windows/runner/resources/app_icon.ico", sizes=[(s, s) for s in sizes])
tile(512).save("assets/icon/roundelay-icon-512.png")

# iOS: full-bleed square without alpha (the OS applies the corner mask).
import re
ios = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
for f in os.listdir(ios):
    m = re.match(r"Icon-App-([\d.]+)x[\d.]+@(\d)x\.png", f)
    if m:
        px = round(float(m.group(1)) * int(m.group(2)))
        tile(px, full_bleed=True).convert("RGB").save(f"{ios}/{f}")
# macOS: rounded tile with transparent corners.
mac = "macos/Runner/Assets.xcassets/AppIcon.appiconset"
for f in os.listdir(mac):
    m = re.match(r"app_icon_(\d+)\.png", f)
    if m:
        tile(int(m.group(1))).save(f"{mac}/{f}")
