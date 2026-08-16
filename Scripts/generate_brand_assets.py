#!/usr/bin/env python3
"""Generate the original QuotaBeacon app and menu-bar assets."""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "AIQuotaMonitor" / "Resources" / "Assets.xcassets"
APP_ICON_SET = CATALOG / "AppIcon.appiconset"
STATUS_SET = CATALOG / "QuotaBeaconStatus.imageset"


def write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def rounded_line(
    draw: ImageDraw.ImageDraw,
    points: list[tuple[float, float]],
    fill: tuple[int, int, int, int],
    width: int,
) -> None:
    draw.line(points, fill=fill, width=width, joint="curve")
    radius = width // 2
    for x, y in (points[0], points[-1]):
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=fill)


def render_app_icon() -> Image.Image:
    size = 1024
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((56, 56, 968, 968), radius=220, fill=255)

    gradient = Image.new("RGBA", (size, size))
    pixels = gradient.load()
    for y in range(size):
        for x in range(size):
            t = (x * 0.42 + y * 0.58) / size
            wave = 0.5 + 0.5 * math.sin((x - y) / 310)
            pixels[x, y] = (
                int(16 + 23 * t),
                int(20 + 29 * t),
                int(37 + 73 * t + 8 * wave),
                255,
            )
    canvas.alpha_composite(Image.composite(gradient, Image.new("RGBA", (size, size)), mask))

    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse((248, 210, 776, 738), fill=(73, 108, 255, 90))
    glow = glow.filter(ImageFilter.GaussianBlur(92))
    canvas.alpha_composite(Image.composite(glow, Image.new("RGBA", (size, size)), mask))

    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    # Two independent reset windows orbit a single live usage signal.
    draw.arc((224, 196, 800, 772), 205, 339, fill=(121, 225, 255, 255), width=38)
    draw.arc((286, 258, 738, 710), 24, 158, fill=(145, 136, 255, 255), width=30)
    for x, y, color in (
        (246, 604, (121, 225, 255, 255)),
        (704, 384, (121, 225, 255, 255)),
        (318, 381, (145, 136, 255, 255)),
        (705, 590, (145, 136, 255, 255)),
    ):
        draw.ellipse((x - 19, y - 19, x + 19, y + 19), fill=color)

    rounded_line(
        draw,
        [(314, 512), (411, 512), (463, 422), (527, 620), (584, 477), (710, 477)],
        (248, 250, 255, 255),
        34,
    )
    draw.ellipse((488, 473, 536, 521), fill=(255, 255, 255, 255))

    # Quiet ledger baseline: enough to suggest history without becoming a chart logo.
    rounded_line(draw, [(332, 746), (692, 746)], (207, 216, 255, 150), 16)
    for x in (392, 512, 632):
        draw.ellipse((x - 9, 737, x + 9, 755), fill=(207, 216, 255, 210))

    canvas.alpha_composite(layer)
    highlight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(highlight).arc((82, 76, 942, 936), 205, 326, fill=(255, 255, 255, 40), width=8)
    canvas.alpha_composite(Image.composite(highlight, Image.new("RGBA", (size, size)), mask))
    return canvas


def render_status_mark(pixel_size: int) -> Image.Image:
    scale = 8
    size = pixel_size * scale
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    stroke = max(scale, round(size * 0.075))
    inset = round(size * 0.13)
    draw.arc((inset, inset, size - inset, size - inset), 200, 340, fill=(0, 0, 0, 255), width=stroke)
    draw.arc(
        (inset * 2, inset * 2, size - inset * 2, size - inset * 2),
        20,
        160,
        fill=(0, 0, 0, 255),
        width=stroke,
    )
    rounded_line(
        draw,
        [
            (size * 0.22, size * 0.52),
            (size * 0.39, size * 0.52),
            (size * 0.48, size * 0.34),
            (size * 0.58, size * 0.67),
            (size * 0.69, size * 0.47),
            (size * 0.80, size * 0.47),
        ],
        (0, 0, 0, 255),
        stroke,
    )
    return layer.resize((pixel_size, pixel_size), Image.Resampling.LANCZOS)


def main() -> None:
    APP_ICON_SET.mkdir(parents=True, exist_ok=True)
    STATUS_SET.mkdir(parents=True, exist_ok=True)

    base = render_app_icon()
    icon_specs = [
        ("16x16", "1x", 16, "AppIcon-16.png"),
        ("16x16", "2x", 32, "AppIcon-16@2x.png"),
        ("32x32", "1x", 32, "AppIcon-32.png"),
        ("32x32", "2x", 64, "AppIcon-32@2x.png"),
        ("128x128", "1x", 128, "AppIcon-128.png"),
        ("128x128", "2x", 256, "AppIcon-128@2x.png"),
        ("256x256", "1x", 256, "AppIcon-256.png"),
        ("256x256", "2x", 512, "AppIcon-256@2x.png"),
        ("512x512", "1x", 512, "AppIcon-512.png"),
        ("512x512", "2x", 1024, "AppIcon-512@2x.png"),
    ]
    for _, _, pixels, filename in icon_specs:
        base.resize((pixels, pixels), Image.Resampling.LANCZOS).save(APP_ICON_SET / filename)

    write_json(
        APP_ICON_SET / "Contents.json",
        {
            "images": [
                {"filename": filename, "idiom": "mac", "scale": scale, "size": size}
                for size, scale, _, filename in icon_specs
            ],
            "info": {"author": "xcode", "version": 1},
        },
    )

    status_specs = [(18, "1x", "QuotaBeaconStatus.png"), (36, "2x", "QuotaBeaconStatus@2x.png")]
    for pixels, _, filename in status_specs:
        render_status_mark(pixels).save(STATUS_SET / filename)
    write_json(
        STATUS_SET / "Contents.json",
        {
            "images": [
                {"filename": filename, "idiom": "mac", "scale": scale}
                for _, scale, filename in status_specs
            ],
            "info": {"author": "xcode", "version": 1},
            "properties": {"template-rendering-intent": "template"},
        },
    )
    write_json(CATALOG / "Contents.json", {"info": {"author": "xcode", "version": 1}})


if __name__ == "__main__":
    main()
