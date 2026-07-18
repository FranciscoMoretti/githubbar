"""PROTOTYPE: five official GitHub Octicons with GitHubBar's open-corner count carve."""

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

W, H = 1860, 1040
BG = (14, 16, 18)
CARD = (29, 32, 35)
BORDER = (64, 70, 76)
SECONDARY = (166, 175, 182)
WHITE = (247, 249, 250)
MENU_BLUE = (12, 124, 180)
MENU_BLUE_LIGHT = (24, 145, 199)
WARNING = (245, 183, 78)
SF = "/System/Library/Fonts/SFNS.ttf"
SF_MONO = "/System/Library/Fonts/SFNSMono.ttf"

def font(size, mono=False, weight="Regular"):
    result = ImageFont.truetype(SF_MONO if mono else SF, size=size)
    result.set_variation_by_name(weight)
    return result


def label(xy, value, size, fill=WHITE, anchor="la", mono=False, weight="Regular"):
    draw.text(xy, value, font=font(size, mono, weight), fill=fill, anchor=anchor)


def octicon_mask(name, size):
    glyph_size = round(size * 16 / 18)
    rendered = Image.open(Path(__file__).with_name(".rendered") / f"{name}.png").convert("RGBA")
    rendered = rendered.getchannel("A").resize((glyph_size, glyph_size), Image.Resampling.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    offset = (size - glyph_size) // 2
    mask.paste(rendered, (offset, offset))
    return mask


def count_mask(size, count):
    scale = size / 18
    value = str(count)
    point_size = 8.9 if len(value) == 1 else 8.0
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).text(
        (size - round(0.15 * scale), size - round(0.05 * scale)),
        value,
        font=font(round(point_size * scale), mono=True, weight="Heavy"),
        fill=255,
        anchor="rs",
    )
    return mask


def carved_mask(name, count, size):
    glyph = octicon_mask(name, size)
    digits = count_mask(size, count)
    bbox = digits.getbbox()
    assert bbox is not None
    scale = size / 18
    overflow = round(3.5 * scale)
    carve = Image.new("L", (size, size), 0)
    ImageDraw.Draw(carve).rounded_rectangle(
        (
            bbox[0] - round(1.35 * scale),
            round(8.8 * scale),
            size + overflow,
            size + overflow,
        ),
        radius=round(2.6 * scale),
        fill=255,
    )
    return ImageChops.lighter(ImageChops.subtract(glyph, carve), digits)


def place_icon(name, count, x, y, size):
    mask = carved_mask(name, count, size)
    canvas.paste(Image.new("RGB", (size, size), WHITE), (x, y), mask)


canvas = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(canvas)
label((62, 46), "More GitHub-native directions", 38)
label(
    (64, 100),
    "Official 16px Octicons, each tested with GitHubBar's same open lower-right count carve.",
    18,
    SECONDARY,
)

variants = [
    ("D", "mark-github", "GitHub mark", "Maximum source recognition", True),
    ("E", "code-review", "Code review", "Review-specific product metaphor", False),
    ("F", "repo", "Repository", "Broad GitHub workspace metaphor", False),
    ("G", "stack", "Stack", "Aggregation and high-volume metaphor", False),
    ("H", "checklist", "Checklist", "Actionable review-work metaphor", False),
]

card_w, card_h = 340, 760
for index, (key, icon_name, title, note, trademark) in enumerate(variants):
    x = 45 + index * 362
    y = 165
    draw.rounded_rectangle(
        (x, y, x + card_w, y + card_h),
        radius=22,
        fill=CARD,
        outline=BORDER,
        width=1,
    )
    label((x + 22, y + 28), f"{key} — {title}", 20)
    label((x + 22, y + 68), note, 13, SECONDARY)
    if trademark:
        label((x + 22, y + 98), "Reference only — cannot ship", 12, WARNING, weight="Semibold")

    start_y = y + 134
    for row, count in enumerate((2, 20)):
        panel_y = start_y + row * 245
        draw.rounded_rectangle(
            (x + 20, panel_y, x + card_w - 20, panel_y + 216),
            radius=14,
            fill=MENU_BLUE,
        )
        place_icon(icon_name, count, x + 116, panel_y + 30, 108)

        strip = (x + 65, panel_y + 158, x + 275, panel_y + 202)
        draw.rounded_rectangle(strip, radius=10, fill=MENU_BLUE_LIGHT)
        draw.ellipse((x + 83, panel_y + 171, x + 99, panel_y + 187), outline=WHITE, width=2)
        draw.rectangle((x + 121, panel_y + 172, x + 137, panel_y + 186), outline=WHITE, width=2)
        place_icon(icon_name, count, x + 174, panel_y + 162, 36)
        label((x + 228, panel_y + 181), "⌁", 20, WHITE, anchor="mm")

    label((x + 20, y + 728), "Large 6×  ·  strip native 2×", 12, (132, 142, 149))

canvas.save(Path(__file__).with_name("github-status-icon-variants.png"))
