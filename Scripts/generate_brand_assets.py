#!/usr/bin/env python3
"""Generate QuotaBeacon and provider raster assets from pinned project sources."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "AIQuotaMonitor" / "Resources" / "Assets.xcassets"
SOURCES = ROOT / "BrandAssets" / "Sources"
APP_ICON_SET = CATALOG / "AppIcon.appiconset"
STATUS_SET = CATALOG / "QuotaBeaconStatus.imageset"
HEADER_SET = CATALOG / "QuotaBeaconMark.imageset"

PROVIDERS = {
    "ProviderClaude": {
        "source": "claude-mark-source.png",
        "polarity": "dark",
        "background": (206, 103, 76, 255),
        "foreground": (255, 248, 241, 255),
        "scale": 0.72,
    },
    "ProviderCodex": {
        "source": "codex-openai-mark-source.png",
        "polarity": "dark",
        "background": (22, 25, 31, 255),
        "foreground": (247, 249, 255, 255),
        "scale": 0.68,
    },
    "ProviderGrok": {
        "source": "grok-xai-mark-source.png",
        "polarity": "light",
        "background": (7, 9, 13, 255),
        "foreground": (247, 248, 251, 255),
        "scale": 0.78,
    },
    "ProviderGemini": {
        "source": "gemini-mark-source.png",
        "polarity": "dark",
        "background": (18, 25, 52, 255),
        "foreground": "gemini-gradient",
        "scale": 0.68,
    },
    "ProviderZAI": {
        "source": "zai-mark-source.png",
        "polarity": "light",
        "background": (9, 14, 20, 255),
        "foreground": (247, 250, 252, 255),
        "scale": 0.76,
    },
}


def write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def center_square(image: Image.Image) -> Image.Image:
    side = min(image.size)
    left = (image.width - side) // 2
    top = (image.height - side) // 2
    return image.crop((left, top, left + side, top + side))


def render_app_icon() -> Image.Image:
    source = center_square(Image.open(SOURCES / "quotabeacon-generated-master.png").convert("RGBA"))
    source = source.resize((1024, 1024), Image.Resampling.LANCZOS)
    mask = Image.new("L", source.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((42, 42, 982, 982), radius=218, fill=255)
    result = Image.new("RGBA", source.size, (0, 0, 0, 0))
    result.paste(source, mask=mask)
    return result


def mark_mask(path: Path, polarity: str, target_scale: float, size: int = 512) -> Image.Image:
    source = center_square(Image.open(path).convert("RGBA"))
    grayscale = source.convert("L")
    mask = ImageChops.invert(grayscale) if polarity == "dark" else grayscale
    mask = ImageChops.multiply(mask, source.getchannel("A"))
    bounds = mask.getbbox()
    if bounds is None:
        raise ValueError(f"empty provider mark: {path}")
    mark = mask.crop(bounds)
    target = max(1, round(size * target_scale))
    mark.thumbnail((target, target), Image.Resampling.LANCZOS)
    result = Image.new("L", (size, size), 0)
    result.paste(mark, ((size - mark.width) // 2, (size - mark.height) // 2))
    return result


def gradient(size: int, start: tuple[int, int, int], end: tuple[int, int, int]) -> Image.Image:
    image = Image.new("RGBA", (size, size))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            amount = (x + y) / (2 * max(1, size - 1))
            pixels[x, y] = tuple(
                round(first + (second - first) * amount)
                for first, second in zip(start, end)
            ) + (255,)
    return image


def render_provider_badge(name: str, spec: dict, size: int = 512) -> Image.Image:
    del name
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shape = Image.new("L", (size, size), 0)
    inset = round(size * 0.035)
    radius = round(size * 0.25)
    ImageDraw.Draw(shape).rounded_rectangle(
        (inset, inset, size - inset, size - inset),
        radius=radius,
        fill=255,
    )
    background = Image.new("RGBA", (size, size), spec["background"])
    canvas.paste(background, mask=shape)

    mask = mark_mask(
        SOURCES / spec["source"],
        spec["polarity"],
        spec["scale"],
        size,
    )
    if spec["foreground"] == "gemini-gradient":
        foreground = gradient(size, (79, 188, 255), (154, 105, 255))
    else:
        foreground = Image.new("RGBA", (size, size), spec["foreground"])
    canvas.paste(foreground, mask=mask)

    border = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle(
        (inset, inset, size - inset - 1, size - inset - 1),
        radius=radius,
        outline=(255, 255, 255, 38),
        width=max(1, round(size * 0.012)),
    )
    return Image.alpha_composite(canvas, border)


def render_status_mark(pixel_size: int) -> Image.Image:
    scale = 10
    size = pixel_size * scale
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    ink = (0, 0, 0, 255)
    stroke = max(scale, round(size * 0.075))

    # Quota arc and reset ticks.
    inset = round(size * 0.10)
    draw.arc((inset, inset, size - inset, size - inset), 202, 338, fill=ink, width=stroke)
    tick = round(size * 0.055)
    for x, y in ((0.22, 0.39), (0.50, 0.16), (0.78, 0.39)):
        px, py = round(size * x), round(size * y)
        draw.rounded_rectangle((px - tick, py - tick, px + tick, py + tick), radius=tick, fill=ink)

    # Harbor beacon with two compact light beams.
    draw.polygon(
        [(round(size * 0.25), round(size * 0.43)), (round(size * 0.43), round(size * 0.49)), (round(size * 0.43), round(size * 0.39))],
        fill=ink,
    )
    draw.polygon(
        [(round(size * 0.75), round(size * 0.43)), (round(size * 0.57), round(size * 0.49)), (round(size * 0.57), round(size * 0.39))],
        fill=ink,
    )
    draw.rounded_rectangle(
        (round(size * 0.42), round(size * 0.36), round(size * 0.58), round(size * 0.52)),
        radius=round(size * 0.025),
        fill=ink,
    )
    draw.polygon(
        [(round(size * 0.39), round(size * 0.36)), (round(size * 0.50), round(size * 0.28)), (round(size * 0.61), round(size * 0.36))],
        fill=ink,
    )
    draw.polygon(
        [(round(size * 0.42), round(size * 0.80)), (round(size * 0.58), round(size * 0.80)), (round(size * 0.55), round(size * 0.51)), (round(size * 0.45), round(size * 0.51))],
        fill=ink,
    )
    draw.rounded_rectangle(
        (round(size * 0.35), round(size * 0.78), round(size * 0.65), round(size * 0.88)),
        radius=round(size * 0.025),
        fill=ink,
    )
    return image.resize((pixel_size, pixel_size), Image.Resampling.LANCZOS)


def write_imageset(name: str, base: Image.Image) -> None:
    image_set = CATALOG / f"{name}.imageset"
    image_set.mkdir(parents=True, exist_ok=True)
    files = [(64, "1x", f"{name}.png"), (128, "2x", f"{name}@2x.png")]
    for pixels, _, filename in files:
        base.resize((pixels, pixels), Image.Resampling.LANCZOS).save(image_set / filename)
    write_json(
        image_set / "Contents.json",
        {
            "images": [
                {"filename": filename, "idiom": "mac", "scale": scale}
                for _, scale, filename in files
            ],
            "info": {"author": "xcode", "version": 1},
        },
    )


def main() -> None:
    APP_ICON_SET.mkdir(parents=True, exist_ok=True)
    STATUS_SET.mkdir(parents=True, exist_ok=True)
    HEADER_SET.mkdir(parents=True, exist_ok=True)

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
                {"filename": filename, "idiom": "mac", "scale": scale, "size": logical_size}
                for logical_size, scale, _, filename in icon_specs
            ],
            "info": {"author": "xcode", "version": 1},
        },
    )

    write_imageset("QuotaBeaconMark", base)
    for name, spec in PROVIDERS.items():
        write_imageset(name, render_provider_badge(name, spec))

    status_files = [(18, "1x", "QuotaBeaconStatus.png"), (36, "2x", "QuotaBeaconStatus@2x.png")]
    for pixels, _, filename in status_files:
        render_status_mark(pixels).save(STATUS_SET / filename)
    write_json(
        STATUS_SET / "Contents.json",
        {
            "images": [
                {"filename": filename, "idiom": "mac", "scale": scale}
                for _, scale, filename in status_files
            ],
            "info": {"author": "xcode", "version": 1},
            "properties": {"template-rendering-intent": "template"},
        },
    )
    write_json(CATALOG / "Contents.json", {"info": {"author": "xcode", "version": 1}})


if __name__ == "__main__":
    main()
