"""PROTOTYPE: three bottom-right carve treatments for GitHubBar's 18×18 PR icon."""

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

W, H = 1500, 960
BG = (14, 16, 18)
CARD = (30, 33, 36)
BORDER = (67, 73, 78)
SECONDARY = (171, 179, 185)
WHITE = (247, 249, 250)
MENU_BLUE = (10, 123, 178)
SF = "/System/Library/Fonts/SFNS.ttf"
SF_MONO = "/System/Library/Fonts/SFNSMono.ttf"

image = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(image)


def font(size, mono=False, weight="Regular"):
    result = ImageFont.truetype(SF_MONO if mono else SF, size=size)
    result.set_variation_by_name(weight)
    return result


def text(xy, value, size, fill=WHITE, anchor="la", mono=False, weight="Regular"):
    draw.text(xy, value, font=font(size, mono, weight), fill=fill, anchor=anchor)


def pull_request_mask(size):
    """A standard pull-request silhouette using the full square canvas."""
    scale = size / 18
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    p = lambda x, y: (round(x * scale), round(y * scale))
    width = max(1, round(1.45 * scale))
    node_radius = 1.25 * scale

    # Source branch: connected top and bottom nodes.
    d.line([p(4.1, 4.0), p(4.1, 14.0)], fill=255, width=width)
    # Pull-request head: a branch enters from the left and terminates at the lower node.
    d.line([p(8.0, 5.3), p(11.0, 5.3)], fill=255, width=width)
    d.arc(
        [p(9.1, 5.2), p(14.0, 10.1)],
        start=270,
        end=360,
        fill=255,
        width=width,
    )
    d.line([p(13.95, 7.7), p(13.95, 13.8)], fill=255, width=width)
    # Arrowhead pointing into the pull-request branch.
    d.line([p(8.05, 5.3), p(10.15, 3.2)], fill=255, width=width)
    d.line([p(8.05, 5.3), p(10.15, 7.4)], fill=255, width=width)

    for cx, cy in ((4.1, 3.4), (4.1, 14.6), (13.95, 14.6)):
        x, y = p(cx, cy)
        d.ellipse(
            (x - node_radius, y - node_radius, x + node_radius, y + node_radius),
            outline=255,
            width=max(1, round(1.25 * scale)),
        )
    return mask


def count_mask(size, count):
    scale = size / 18
    value = str(count)
    point_size = 8.9 if len(value) == 1 else 8.0
    count_font = font(round(point_size * scale), mono=True, weight="Heavy")
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    # Right/bottom alignment keeps the notch stable when the count grows to two digits.
    d.text(
        (size - round(0.15 * scale), size - round(0.05 * scale)),
        value,
        font=count_font,
        fill=255,
        anchor="rs",
    )
    return mask


def carved_icon(variant, count, x, y, size):
    glyph = pull_request_mask(size)
    digits = count_mask(size, count)
    scale = size / 18
    bbox = digits.getbbox()
    assert bbox is not None

    if variant == "A":
        # A text-shaped clearance preserves the greatest amount of the PR silhouette.
        radius = max(3, round(1.15 * scale) * 2 + 1)
        if radius % 2 == 0:
            radius += 1
        carve = digits.filter(ImageFilter.MaxFilter(radius))
    else:
        carve = Image.new("L", (size, size), 0)
        carve_draw = ImageDraw.Draw(carve)
        left = bbox[0] - round((1.0 if variant == "B" else 1.35) * scale)
        top = bbox[1] - round((0.75 if variant == "B" else 1.05) * scale)
        if variant == "B":
            # A contained pocket: visually explicit, but still part of the square icon.
            right = min(size, bbox[2] + round(0.55 * scale))
            bottom = min(size, bbox[3] + round(0.35 * scale))
            carve_draw.rounded_rectangle(
                (left, top, right, bottom),
                radius=round(1.7 * scale),
                fill=255,
            )
        else:
            # The pocket opens through the outer right/bottom edges, like Graphite's carve.
            overflow = round(3.5 * scale)
            carve_draw.rounded_rectangle(
                (left, top, size + overflow, size + overflow),
                radius=round(2.6 * scale),
                fill=255,
            )

    glyph = ImageChops.subtract(glyph, carve)
    combined = ImageChops.lighter(glyph, digits)
    color = Image.new("RGB", (size, size), WHITE)
    image.paste(color, (x, y), combined)


text((70, 54), "Pull request icon with carved count", 38)
text(
    (72, 108),
    "The PR mark keeps the full 18 × 18 footprint; only its lower-right pixels yield to 2, 20, or 99.",
    18,
    SECONDARY,
)

variants = [
    ("A", "Tight halo", "Only a slim text-shaped clearance is removed behind the count."),
    ("B", "Rounded pocket", "A contained notch separates the count from the PR silhouette."),
    ("C", "Open corner carve", "The lower-right pocket opens through the edges, like Graphite."),
]
card_w, card_h, card_y = 430, 720, 170
for index, (key, name, note) in enumerate(variants):
    card_x = 55 + index * 475
    draw.rounded_rectangle(
        (card_x, card_y, card_x + card_w, card_y + card_h),
        radius=22,
        fill=CARD,
        outline=BORDER,
        width=1,
    )
    text((card_x + 26, card_y + 30), f"{key} — {name}", 22)
    text((card_x + 26, card_y + 72), note, 14, SECONDARY)

    for row, count in enumerate((2, 20, 99)):
        preview_y = card_y + 128 + row * 180
        draw.rounded_rectangle(
            (card_x + 26, preview_y, card_x + 404, preview_y + 154),
            radius=14,
            fill=MENU_BLUE,
        )
        text((card_x + 44, preview_y + 126), str(count), 13, (188, 224, 240))
        carved_icon(key, count, card_x + 156, preview_y + 23, 108)

        # 2× Retina status-item sample: 36 pixels represents the native 18-point canvas.
        strip = (card_x + 288, preview_y + 104, card_x + 388, preview_y + 142)
        draw.rounded_rectangle(strip, radius=8, fill=(23, 139, 190))
        carved_icon(key, count, card_x + 320, preview_y + 105, 36)

    text(
        (card_x + 26, card_y + 688),
        "Large: 6× inspection  ·  Small: native 2× Retina",
        12,
        (132, 142, 149),
    )

image.save(Path(__file__).with_name("status-icon-variants.png"))
