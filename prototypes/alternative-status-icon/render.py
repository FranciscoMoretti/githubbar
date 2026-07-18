"""PROTOTYPE: three semantic marks with the same 18×18 open-corner count carve."""

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

W, H = 1500, 900
BG = (14, 16, 18)
CARD = (29, 32, 35)
BORDER = (64, 70, 76)
SECONDARY = (166, 175, 182)
WHITE = (247, 249, 250)
MENU_BLUE = (12, 124, 180)
MENU_BLUE_LIGHT = (24, 145, 199)
SF = "/System/Library/Fonts/SFNS.ttf"
SF_MONO = "/System/Library/Fonts/SFNSMono.ttf"

canvas = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(canvas)


def font(size, mono=False, weight="Regular"):
    result = ImageFont.truetype(SF_MONO if mono else SF, size=size)
    result.set_variation_by_name(weight)
    return result


def label(xy, value, size, fill=WHITE, anchor="la", mono=False, weight="Regular"):
    draw.text(xy, value, font=font(size, mono, weight), fill=fill, anchor=anchor)


def node(d, center, radius, width):
    x, y = center
    d.ellipse((x - radius, y - radius, x + radius, y + radius), outline=255, width=width)


def pull_request_mask(size):
    scale = size / 18
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    p = lambda x, y: (round(x * scale), round(y * scale))
    width = max(1, round(1.45 * scale))
    radius = 1.25 * scale

    d.line([p(4.1, 4.0), p(4.1, 14.0)], fill=255, width=width)
    d.line([p(8.0, 5.3), p(11.0, 5.3)], fill=255, width=width)
    d.arc([p(9.1, 5.2), p(14.0, 10.1)], start=270, end=360, fill=255, width=width)
    d.line([p(13.95, 7.7), p(13.95, 13.8)], fill=255, width=width)
    d.line([p(8.05, 5.3), p(10.15, 3.2)], fill=255, width=width)
    d.line([p(8.05, 5.3), p(10.15, 7.4)], fill=255, width=width)
    for point in (p(4.1, 3.4), p(4.1, 14.6), p(13.95, 14.6)):
        node(d, point, radius, max(1, round(1.25 * scale)))
    return mask


def inbox_mask(size):
    scale = size / 18
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    p = lambda x, y: (round(x * scale), round(y * scale))
    width = max(1, round(1.45 * scale))

    # A compact tray/inbox outline with a central receiving lip.
    d.rounded_rectangle(
        (*p(2.6, 4.0), *p(15.4, 14.6)),
        radius=round(2.0 * scale),
        outline=255,
        width=width,
    )
    d.line([p(2.8, 9.6), p(6.0, 9.6)], fill=255, width=width)
    d.line([p(6.0, 9.6), p(7.25, 11.45)], fill=255, width=width)
    d.line([p(7.25, 11.45), p(10.75, 11.45)], fill=255, width=width)
    d.line([p(10.75, 11.45), p(12.0, 9.6)], fill=255, width=width)
    d.line([p(12.0, 9.6), p(15.2, 9.6)], fill=255, width=width)
    # One incoming line keeps it recognizably an inbox rather than a generic box.
    d.line([p(9.0, 2.7), p(9.0, 7.2)], fill=255, width=width)
    d.line([p(6.9, 5.2), p(9.0, 7.3), p(11.1, 5.2)], fill=255, width=width, joint="curve")
    return mask


def branch_mask(size):
    scale = size / 18
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    p = lambda x, y: (round(x * scale), round(y * scale))
    width = max(1, round(1.45 * scale))
    radius = 1.25 * scale

    d.line([p(4.1, 4.0), p(4.1, 14.0)], fill=255, width=width)
    # A branch leaves the main rail and terminates in a second top node.
    d.line([p(4.1, 10.2), p(5.0, 10.2)], fill=255, width=width)
    d.arc([p(4.0, 3.8), p(13.8, 11.2)], start=0, end=90, fill=255, width=width)
    d.line([p(11.9, 5.6), p(13.9, 4.0)], fill=255, width=width)
    for point in (p(4.1, 3.4), p(4.1, 14.6), p(13.9, 3.4)):
        node(d, point, radius, max(1, round(1.25 * scale)))
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


def icon_mask(kind, count, size):
    glyph = {
        "pull-request": pull_request_mask,
        "inbox": inbox_mask,
        "branch": branch_mask,
    }[kind](size)
    digits = count_mask(size, count)
    scale = size / 18
    bbox = digits.getbbox()
    assert bbox is not None

    # Variant C: the rounded carve opens through both outer edges.
    carve = Image.new("L", (size, size), 0)
    overflow = round(3.5 * scale)
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


def place_icon(kind, count, x, y, size):
    mask = icon_mask(kind, count, size)
    canvas.paste(Image.new("RGB", (size, size), WHITE), (x, y), mask)


label((70, 53), "Which mark best describes GitHubBar?", 38)
label(
    (72, 106),
    "Same 18 × 18 template canvas, same open-corner carve, same counts — only the semantic mark changes.",
    18,
    SECONDARY,
)

variants = [
    ("A", "pull-request", "Pull request", "Literal: the app is made of PRs."),
    ("B", "inbox", "PR inbox", "Purpose-led: one place for incoming and authored work."),
    ("C", "branch", "Code branch", "Broad: code collaboration without a PR-specific shape."),
]

card_w, card_h, card_y = 430, 660, 170
for index, (key, kind, name, note) in enumerate(variants):
    card_x = 55 + index * 475
    draw.rounded_rectangle(
        (card_x, card_y, card_x + card_w, card_y + card_h),
        radius=22,
        fill=CARD,
        outline=BORDER,
        width=1,
    )
    label((card_x + 26, card_y + 30), f"{key} — {name}", 22)
    label((card_x + 26, card_y + 72), note, 14, SECONDARY)

    for row, count in enumerate((2, 20)):
        preview_y = card_y + 124 + row * 210
        draw.rounded_rectangle(
            (card_x + 26, preview_y, card_x + 404, preview_y + 180),
            radius=14,
            fill=MENU_BLUE,
        )
        place_icon(kind, count, card_x + 68, preview_y + 30, 108)

        # Native 2× menu-bar sample, surrounded by generic neighbors for scale.
        strip = (card_x + 218, preview_y + 66, card_x + 388, preview_y + 110)
        draw.rounded_rectangle(strip, radius=10, fill=MENU_BLUE_LIGHT)
        d = ImageDraw.Draw(canvas)
        d.ellipse((card_x + 235, preview_y + 79, card_x + 251, preview_y + 95), outline=WHITE, width=2)
        d.rectangle((card_x + 273, preview_y + 80, card_x + 289, preview_y + 94), outline=WHITE, width=2)
        place_icon(kind, count, card_x + 310, preview_y + 70, 36)
        label((card_x + 44, preview_y + 154), f"Count {count}", 13, (190, 226, 242))

    label(
        (card_x + 26, card_y + 626),
        "Large: 6× inspection  ·  Right: native 2× Retina",
        12,
        (132, 142, 149),
    )

canvas.save(Path(__file__).with_name("alternative-status-icons.png"))
