"""Draws the BGoal mark and every icon/store image from it.

The mark is built from shapes (no font), so the files can be regenerated anywhere:

    pip install pillow
    python tool/brand/make_icons.py          (from the app/ folder)

Output goes to assets/brand/. flutter_launcher_icons and flutter_native_splash
(configured in pubspec.yaml) turn these into the Android and iOS icon sets.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parents[2] / "assets" / "brand"

# Brand colours (also in lib/theme.dart and BRAND.md).
GREEN = (14, 138, 74)        # #0E8A4A  BGoal green
GREEN_DARK = (6, 92, 50)     # #065C32
INK = (8, 28, 18)            # #081C12
LIVE = (255, 59, 59)         # #FF3B3B  live / goal dot
WHITE = (255, 255, 255)

SS = 4  # supersampling factor for smooth edges


def _mark(size: int, color, dot: bool = True, dot_color=LIVE) -> Image.Image:
    """The "B" with a ball in its lower bowl and a live dot, on transparency.

    Drawn in a 1024 grid and scaled, so proportions stay fixed at any size. The dot
    is separated from the B by a transparent gap, so it works on any background.
    """
    s = size * SS / 1024
    dx = -36  # optical centring: the dot makes the right side heavier
    img = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def box(x0, y0, x1, y1):
        return [(x0 + dx) * s, y0 * s, (x1 + dx) * s, y1 * s]

    def circle(cx, cy, r, fill):
        d.ellipse(box(cx - r, cy - r, cx + r, cy + r), fill=fill)

    clear = (0, 0, 0, 0)
    # Stem + upper bowl + lower bowl, as stadium shapes.
    d.rectangle(box(300, 250, 560, 500), fill=color)
    circle(560, 375, 125, color)
    d.rectangle(box(300, 470, 590, 774), fill=color)
    circle(590, 622, 152, color)
    # Upper counter.
    d.rectangle(box(420, 330, 560, 420), fill=clear)
    circle(560, 375, 45, clear)
    # Lower counter: a round hole with a ball inside it.
    circle(575, 622, 92, clear)
    circle(575, 622, 62, color)
    # Pentagon panel on the ball, cut out.
    import math
    pts = []
    for i in range(5):
        a = math.radians(-90 + i * 72)
        pts.append(((575 + dx + 26 * math.cos(a)) * s, (622 + 26 * math.sin(a)) * s))
    d.polygon(pts, fill=clear)
    # Live dot, top right of the upper bowl, with a gap cut out of the B around it.
    if dot:
        circle(735, 268, 92, clear)
        circle(735, 268, 66, dot_color)
    return img.resize((size, size), Image.LANCZOS)


def _gradient(size: int) -> Image.Image:
    """Diagonal green gradient used behind the mark."""
    w, h = size if isinstance(size, tuple) else (size, size)
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = (x / w * 0.35 + y / h * 0.65)
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(GREEN, GREEN_DARK))
    return img


def _scaled_on(canvas: Image.Image, mark: Image.Image, scale: float, offset=(0, 0)):
    m = mark.resize((round(mark.width * scale), round(mark.height * scale)), Image.LANCZOS)
    x = (canvas.width - m.width) // 2 + offset[0]
    y = (canvas.height - m.height) // 2 + offset[1]
    canvas.alpha_composite(m, (x, y)) if canvas.mode == "RGBA" else canvas.paste(m, (x, y), m)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    # iOS / store icon: full-bleed square, no transparency (the OS rounds the corners).
    icon = _gradient(1024)
    mark = _mark(1024, WHITE)
    icon.paste(mark, (0, 0), mark)
    icon.save(OUT / "icon.png")
    icon.resize((512, 512), Image.LANCZOS).save(OUT / "play_store_icon_512.png")

    # Android adaptive icon: the foreground must fit the centre 66% (safe zone).
    fg = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    _scaled_on(fg, _mark(1024, WHITE), 0.72)
    fg.save(OUT / "icon_foreground.png")
    # Android 13+ themed icon: one colour, the system tints it.
    mono = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    _scaled_on(mono, _mark(1024, WHITE, dot_color=WHITE), 0.72)
    mono.save(OUT / "icon_monochrome.png")

    # Splash: white mark on the brand green (flutter_native_splash sets the colour).
    splash = Image.new("RGBA", (1152, 1152), (0, 0, 0, 0))
    _scaled_on(splash, _mark(1024, WHITE), 0.75)
    splash.save(OUT / "splash.png")
    # Android 12+ splash icon is cropped to a circle: keep the mark well inside it.
    splash12 = Image.new("RGBA", (1152, 1152), (0, 0, 0, 0))
    _scaled_on(splash12, _mark(1024, WHITE), 0.62)
    splash12.save(OUT / "splash_android12.png")

    # Android status-bar notification icon: white silhouette, 24dp at each density.
    # tool/setup_platforms.py copies these into android/app/src/main/res/.
    for folder, px in {"mdpi": 24, "hdpi": 36, "xhdpi": 48, "xxhdpi": 72, "xxxhdpi": 96}.items():
        d = OUT / "android" / f"drawable-{folder}"
        d.mkdir(parents=True, exist_ok=True)
        icon_px = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        _scaled_on(icon_px, _mark(px, WHITE, dot_color=WHITE), 1.15)
        icon_px.save(d / "ic_notification.png")

    # Web version (testers add it to their Home Screen): icons in app/web/.
    web = OUT.parents[1] / "web"
    (web / "icons").mkdir(parents=True, exist_ok=True)
    for size in (192, 512):
        icon.resize((size, size), Image.LANCZOS).save(web / "icons" / f"Icon-{size}.png")
        # Maskable: the system may crop to a circle, so keep the mark in the centre 80%.
        masked = _gradient(size).convert("RGBA")
        _scaled_on(masked, _mark(size, WHITE), 0.78)
        masked.convert("RGB").save(web / "icons" / f"Icon-maskable-{size}.png")
    icon.resize((180, 180), Image.LANCZOS).save(web / "icons" / "apple-touch-icon.png")
    icon.resize((48, 48), Image.LANCZOS).save(web / "favicon.png")

    # Small mark for the app's own UI (onboarding, about).
    _mark(512, WHITE).save(OUT / "mark_white.png")
    _mark(512, GREEN).save(OUT / "mark_green.png")

    # Google Play feature graphic, 1024 x 500.
    fg_img = _gradient((1024, 500)).convert("RGBA")
    m = _mark(420, WHITE)
    fg_img.alpha_composite(m, (70, 40))
    d = ImageDraw.Draw(fg_img)
    font_path = Path("C:/Windows/Fonts/bahnschrift.ttf")
    try:
        title = ImageFont.truetype(str(font_path), 132)
        title.set_variation_by_name("Bold")
        sub = ImageFont.truetype(str(font_path), 44)
        sub.set_variation_by_name("SemiBold")
    except (OSError, ValueError):
        title = ImageFont.load_default(132)
        sub = ImageFont.load_default(44)
    d.text((500, 150), "BGoal", font=title, fill=WHITE)
    d.text((506, 300), "Live scores. Goal alerts", font=sub, fill=(214, 240, 224))
    d.text((506, 352), "in seconds.", font=sub, fill=(214, 240, 224))
    fg_img.convert("RGB").save(OUT / "play_feature_graphic.png")

    print("Wrote", ", ".join(sorted(p.name for p in OUT.glob("*.png"))))


if __name__ == "__main__":
    main()
