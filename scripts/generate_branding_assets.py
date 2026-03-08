from __future__ import annotations

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
BRAND = ROOT / "assets" / "branding"
STORE = ROOT / "branding" / "store"


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = []
    if bold:
        candidates.extend(
            [
                "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
                "/System/Library/Fonts/Supplemental/Helvetica Bold.ttf",
                "/System/Library/Fonts/Supplemental/Arial.ttf",
            ]
        )
    else:
        candidates.extend(
            [
                "/System/Library/Fonts/Supplemental/Arial.ttf",
                "/System/Library/Fonts/Supplemental/Helvetica.ttf",
            ]
        )
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def vertical_gradient(size: tuple[int, int], top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    width, height = size
    base = Image.new("RGBA", size)
    draw = ImageDraw.Draw(base)
    for y in range(height):
        t = y / max(height - 1, 1)
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        draw.line([(0, y), (width, y)], fill=(r, g, b, 255))
    return base


def draw_symbol(
    canvas: Image.Image,
    *,
    x: int,
    y: int,
    size: int,
    cyan: tuple[int, int, int],
    blue: tuple[int, int, int],
    glow: bool,
) -> None:
    stroke = max(4, size // 38)
    cell = size * 0.19
    gap = size * 0.055
    outer = (x, y, x + size, y + size)

    if glow:
        glow_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        gdraw = ImageDraw.Draw(glow_layer)
        gdraw.rounded_rectangle(outer, radius=size * 0.14, outline=(*cyan, 150), width=stroke + 6)
        glow_blur = glow_layer.filter(ImageFilter.GaussianBlur(radius=max(8, size // 30)))
        canvas.alpha_composite(glow_blur)

    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(outer, radius=size * 0.14, outline=(*cyan, 255), width=stroke)

    grid_origin_x = x + size * 0.11
    grid_origin_y = y + size * 0.11

    positions = [
        (0, 0), (1, 0), (2, 0),
        (0, 1), (1, 1), (2, 1),
        (0, 2),
    ]

    for col, row in positions:
        cx = grid_origin_x + col * (cell + gap)
        cy = grid_origin_y + row * (cell + gap)
        draw.rounded_rectangle(
            (cx, cy, cx + cell, cy + cell),
            radius=cell * 0.22,
            outline=(*blue, 255),
            width=stroke,
        )
        if glow:
            glow_dot = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
            ddraw = ImageDraw.Draw(glow_dot)
            mx = cx + cell * 0.5
            my = cy + cell * 0.5
            r = cell * 0.16
            ddraw.ellipse((mx - r, my - r, mx + r, my + r), fill=(*cyan, 220))
            canvas.alpha_composite(glow_dot.filter(ImageFilter.GaussianBlur(radius=max(4, size // 50))))

    play_w = size * 0.17
    play_h = size * 0.18
    px = x + size * 0.41
    py = y + size * 0.64
    play = [(px, py), (px, py + play_h), (px + play_w, py + play_h * 0.5)]
    draw.polygon(play, outline=(*cyan, 255), fill=None, width=stroke)

    wave_center_x = px + play_w + size * 0.02
    wave_center_y = py + play_h * 0.5
    for i in range(3):
        rr = size * (0.12 + i * 0.09)
        draw.arc(
            (
                wave_center_x - rr,
                wave_center_y - rr,
                wave_center_x + rr,
                wave_center_y + rr,
            ),
            start=-40,
            end=40,
            fill=(*cyan, 255),
            width=stroke,
        )


def create_full_logo(path: Path, size: int, dark_bg: bool, glow: bool, transparent: bool = False) -> None:
    if transparent:
        image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    else:
        if dark_bg:
            image = vertical_gradient((size, size), (4, 12, 31), (9, 25, 55))
        else:
            image = vertical_gradient((size, size), (244, 250, 255), (224, 236, 250))

    draw = ImageDraw.Draw(image)

    if not transparent:
        border_color = (65, 85, 122, 120) if dark_bg else (90, 122, 168, 90)
        pad = int(size * 0.07)
        draw.rounded_rectangle(
            (pad, pad, size - pad, size - pad),
            radius=int(size * 0.1),
            outline=border_color,
            width=max(2, size // 220),
        )

    symbol_size = int(size * 0.46)
    symbol_x = (size - symbol_size) // 2
    symbol_y = int(size * 0.2)

    cyan = (31, 233, 245) if dark_bg else (31, 210, 238)
    blue = (58, 165, 255) if dark_bg else (44, 130, 243)

    draw_symbol(
        image,
        x=symbol_x,
        y=symbol_y,
        size=symbol_size,
        cyan=cyan,
        blue=blue,
        glow=glow,
    )

    title_font = load_font(max(24, size // 10), bold=True)
    subtitle_font = load_font(max(16, size // 18), bold=True)

    title = "DECKPILOT"
    subtitle = "FOR OBS"

    title_bbox = draw.textbbox((0, 0), title, font=title_font)
    sub_bbox = draw.textbbox((0, 0), subtitle, font=subtitle_font)
    title_w = title_bbox[2] - title_bbox[0]
    sub_w = sub_bbox[2] - sub_bbox[0]

    title_x = (size - title_w) // 2
    sub_x = (size - sub_w) // 2

    title_y = int(size * 0.73)
    sub_y = int(size * 0.84)

    title_color = (46, 165, 255, 255) if dark_bg else (31, 112, 207, 255)
    sub_color = (63, 182, 255, 255) if dark_bg else (38, 132, 230, 255)

    draw.text((title_x, title_y), title, fill=title_color, font=title_font)
    draw.text((sub_x, sub_y), subtitle, fill=sub_color, font=subtitle_font)

    image.save(path)


def create_symbol_only(path: Path, size: int, dark: bool, glow: bool) -> None:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw_symbol(
        image,
        x=int(size * 0.14),
        y=int(size * 0.14),
        size=int(size * 0.72),
        cyan=(31, 233, 245) if dark else (26, 181, 234),
        blue=(58, 165, 255) if dark else (41, 125, 230),
        glow=glow,
    )
    image.save(path)


def create_feature_graphic(path: Path) -> None:
    w, h = 1024, 500
    image = vertical_gradient((w, h), (3, 12, 33), (11, 29, 64))
    draw = ImageDraw.Draw(image)

    sym = Image.open(BRAND / "symbol_dark.png").convert("RGBA").resize((220, 220), Image.Resampling.LANCZOS)
    image.alpha_composite(sym, (70, 135))

    title_font = load_font(64, bold=True)
    text_font = load_font(42, bold=False)
    draw.text((340, 160), "DeckPilot for OBS", fill=(39, 186, 255, 255), font=title_font)
    draw.text((340, 255), "Turn your phone into a Stream Deck for OBS", fill=(180, 218, 255, 255), font=text_font)

    image.save(path)


def create_screenshot(path: Path, title: str, subtitle: str) -> None:
    w, h = 1080, 1920
    image = vertical_gradient((w, h), (3, 12, 33), (11, 29, 64))
    draw = ImageDraw.Draw(image)

    sym = Image.open(BRAND / "symbol_dark.png").convert("RGBA").resize((180, 180), Image.Resampling.LANCZOS)
    image.alpha_composite(sym, (450, 230))

    title_font = load_font(64, bold=True)
    sub_font = load_font(38, bold=False)

    tb = draw.textbbox((0, 0), title, font=title_font)
    sb = draw.textbbox((0, 0), subtitle, font=sub_font)
    draw.text(((w - (tb[2] - tb[0])) // 2, 470), title, fill=(46, 165, 255, 255), font=title_font)
    draw.text(((w - (sb[2] - sb[0])) // 2, 560), subtitle, fill=(186, 220, 255, 255), font=sub_font)

    frame = (120, 710, 960, 1720)
    draw.rounded_rectangle(frame, radius=42, outline=(54, 117, 198, 170), width=4)
    draw.rounded_rectangle((140, 740, 940, 1685), radius=26, fill=(8, 26, 54, 220))

    image.save(path)


def ensure_dirs() -> None:
    BRAND.mkdir(parents=True, exist_ok=True)
    STORE.mkdir(parents=True, exist_ok=True)


def main() -> None:
    ensure_dirs()

    create_full_logo(BRAND / "logo_dark.png", size=1024, dark_bg=True, glow=True)
    create_full_logo(BRAND / "logo_light.png", size=1024, dark_bg=False, glow=False, transparent=True)

    create_symbol_only(BRAND / "symbol_dark.png", size=1024, dark=True, glow=True)
    create_symbol_only(BRAND / "symbol_light.png", size=1024, dark=False, glow=False)

    Image.open(BRAND / "symbol_dark.png").resize((432, 432), Image.Resampling.LANCZOS).save(BRAND / "adaptive_foreground.png")
    Image.open(BRAND / "symbol_light.png").resize((128, 128), Image.Resampling.LANCZOS).save(BRAND / "symbol_small.png")

    Image.open(BRAND / "logo_dark.png").resize((512, 512), Image.Resampling.LANCZOS).save(BRAND / "play_store_icon_512.png")
    Image.open(BRAND / "logo_dark.png").resize((640, 640), Image.Resampling.LANCZOS).save(BRAND / "splash_logo_dark.png")
    Image.open(BRAND / "logo_light.png").resize((640, 640), Image.Resampling.LANCZOS).save(BRAND / "splash_logo_light.png")

    create_feature_graphic(STORE / "feature_graphic.png")
    create_screenshot(STORE / "screenshot_1_controller.png", "Fast Scene Control", "Real-time OBS switching from mobile")
    create_screenshot(STORE / "screenshot_2_connection.png", "One-Tap Connect", "Connect with IP, password, or QR code")
    create_screenshot(STORE / "screenshot_3_emergency.png", "Emergency Controls", "Protect your stream with safe actions")


if __name__ == "__main__":
    main()
