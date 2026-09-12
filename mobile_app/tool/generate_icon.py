"""One-off script to generate the app launcher icon. Not part of the app
build - run manually, output committed as a static asset.
"""
from PIL import Image, ImageDraw, ImageFont

SIZE = 1024
BG = (0, 121, 107)  # teal 800, matches the app's seed color
FG = (255, 255, 255)
ACCENT = (255, 202, 40)  # amber 400, a little "coin" accent

try:
    FONT = ImageFont.truetype("arialbd.ttf", 170)
except OSError:
    FONT = ImageFont.load_default()


def draw_glyph(draw, cx, cy, scale=1.0):
    """The wallet/card + coin glyph, centered at (cx, cy)."""
    card_w, card_h = int(560 * scale), int(380 * scale)
    card_x = cx - card_w // 2 - int(40 * scale)
    card_y = cy - card_h // 2 + int(40 * scale)
    draw.rounded_rectangle(
        [card_x, card_y, card_x + card_w, card_y + card_h],
        radius=int(48 * scale), outline=FG, width=int(28 * scale),
    )
    draw.rounded_rectangle(
        [card_x, card_y + int(90 * scale), card_x + card_w, card_y + int(170 * scale)],
        radius=0, fill=FG,
    )

    coin_r = int(150 * scale)
    coin_cx = card_x + card_w - int(40 * scale)
    coin_cy = card_y - int(10 * scale)
    draw.ellipse(
        [coin_cx - coin_r, coin_cy - coin_r, coin_cx + coin_r, coin_cy + coin_r],
        fill=ACCENT, outline=FG, width=int(16 * scale),
    )
    font = FONT.font_variant(size=int(170 * scale)) if scale != 1.0 else FONT
    draw.text((coin_cx, coin_cy - int(10 * scale)), "$", fill=BG, font=font, anchor="mm")


# Main icon: solid rounded-square background (used for the legacy/fallback
# launcher icon and platforms without adaptive icon support).
main = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(main)
draw.rounded_rectangle([0, 0, SIZE, SIZE], radius=220, fill=BG)
draw_glyph(draw, SIZE // 2, SIZE // 2)
main.save("assets/icon/icon.png")
print("Saved assets/icon/icon.png")

# Adaptive foreground: SAME glyph, transparent background, shrunk to sit
# within Android's ~66% safe zone so the system mask doesn't clip it.
fg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(fg)
draw_glyph(draw, SIZE // 2, SIZE // 2, scale=0.62)
fg.save("assets/icon/icon_foreground.png")
print("Saved assets/icon/icon_foreground.png")
