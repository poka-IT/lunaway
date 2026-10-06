"""Draws the synthetic photos of the demo mode (assets/demo/).

Invented landscapes in flat colours, each marked as a demo picture, so the
gallery and the photo viewer can be shown and tested without any real
content and without network. Run from app/: python3 tool/demo_photos.py
(needs Pillow).
"""

import random

from PIL import Image, ImageDraw, ImageFont

SCENES = [
    ("#9cc9e8", "#f5d9a8", "#5d8a5a", "#3f6b41"),  # meadow at noon
    ("#f2a65a", "#f7d08a", "#7a6a8f", "#4b3f63"),  # sunset hills
    ("#1d3461", "#2b4c86", "#273c5c", "#16233a"),  # night, moonlit
    ("#a8d5e2", "#e8f1f2", "#6c9a8b", "#2f5d50"),  # lake shore
    ("#c9e4ca", "#87bba2", "#55828b", "#364958"),  # forest edge
    ("#ffd6a5", "#fdffb6", "#caffbf", "#9bb79a"),  # coast in summer
]


def scene(index, width, height):
    sky_top, sky_bottom, hill_far, hill_near = SCENES[index]
    img = Image.new("RGB", (width, height), sky_top)
    draw = ImageDraw.Draw(img)
    top = Image.new("RGB", (1, 1), sky_top).getpixel((0, 0))
    bottom = Image.new("RGB", (1, 1), sky_bottom).getpixel((0, 0))
    for y in range(height):
        t = y / height
        colour = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        draw.line([(0, y), (width, y)], fill=colour)
    rng = random.Random(index)
    # Sun or moon.
    r = height * 0.08
    cx, cy = width * (0.2 + 0.6 * rng.random()), height * 0.22
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill="#fff6d5")
    for colour, base, amp in ((hill_far, 0.58, 0.08), (hill_near, 0.72, 0.06)):
        phase = rng.random() * 6
        points = [(0, height)]
        for x in range(0, width + 1, max(1, width // 60)):
            y = height * (base + amp * __import__("math").sin(x / width * 6 + phase))
            points.append((x, y))
        points.append((width, height))
        draw.polygon(points, fill=colour)
    # A van silhouette.
    vx, vy, s = width * 0.55, height * 0.72, width / 900
    draw.rounded_rectangle([vx, vy - 70 * s, vx + 170 * s, vy], radius=int(12 * s), fill="#f4f1ea")
    draw.rectangle([vx + 18 * s, vy - 58 * s, vx + 70 * s, vy - 34 * s], fill="#9fb3c8")
    for wx in (vx + 40 * s, vx + 130 * s):
        draw.ellipse([wx - 16 * s, vy - 16 * s, wx + 16 * s, vy + 16 * s], fill="#22272e")
    font = ImageFont.truetype("assets/fonts/AtkinsonHyperlegibleNext-Bold.ttf", max(12, int(height * 0.05)))
    label = "Photo de démonstration"
    box = draw.textbbox((0, 0), label, font=font)
    pad = int(height * 0.02)
    x, y = pad * 2, height - (box[3] - box[1]) - pad * 3
    draw.rounded_rectangle([x - pad, y - pad, x + box[2] + pad, y + box[3] + pad], radius=pad, fill="#1d3461")
    draw.text((x, y), label, font=font, fill="#ffffff")
    return img


for i in range(len(SCENES)):
    scene(i, 960, 640).save(f"assets/demo/photo-{i + 1}-large.jpg", quality=72, optimize=True)
    scene(i, 360, 240).save(f"assets/demo/photo-{i + 1}-thumb.jpg", quality=70, optimize=True)
