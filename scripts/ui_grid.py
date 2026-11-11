#!/usr/bin/env python3
"""Annotate a macOS window screenshot with a point grid and measured gaps.

Usage:
  python3 scripts/ui_grid.py shot.png --scale 2 --out shot-grid.png --json shot.json
  python3 scripts/ui_grid.py shot.png --content-top 44 --bottom-threshold 0.004

The screenshot must be a window-only capture. Points are macOS logical pixels;
on a Retina display the PNG is `scale` times larger. The tool needs Pillow.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFont
except ImportError:  # pragma: no cover - optional developer dependency
    sys.exit("Pillow is required: python3 -m pip install pillow")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--out", type=Path, default=None)
    parser.add_argument("--json", type=Path, default=None)
    parser.add_argument("--scale", type=float, default=2.0)
    parser.add_argument("--grid", type=float, default=8.0, help="minor grid in points")
    parser.add_argument("--major", type=float, default=50.0, help="labelled grid in points")
    parser.add_argument("--content-top", type=float, default=None,
                        help="content origin in points; default auto")
    parser.add_argument("--bottom-threshold", type=float, default=0.004,
                        help="fraction of foreground pixels that ends the content")
    parser.add_argument("--background", default=None,
                        help="background colour as R,G,B; default sample bottom-right")
    parser.add_argument("--no-crop-alpha", action="store_true",
                        help="do not trim transparent shadow from screencapture -l images")
    parser.add_argument("--window", default=None,
                        help="window rectangle in points: x,y,w,h")
    return parser.parse_args()


def font(size: int) -> ImageFont.ImageFont:
    for candidate in ("/System/Library/Fonts/Supplemental/Arial.ttf",
                      "/System/Library/Fonts/Helvetica.ttc"):
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            pass
    return ImageFont.load_default()


def parse_rect(value: str | None) -> tuple[float, float, float, float] | None:
    if not value:
        return None
    parts = [part.strip() for part in value.split(",")]
    if len(parts) != 4:
        raise SystemExit("--window expects x,y,w,h")
    return tuple(float(part) for part in parts)  # type: ignore[return-value]


def foreground_mask(image: Image.Image, background: tuple[int, int, int],
                    threshold: int = 24) -> list[bool]:
    pixels = image.convert("RGB").load()
    width, height = image.size
    mask = [False] * (width * height)
    for y in range(height):
        row = y * width
        for x in range(width):
            red, green, blue = pixels[x, y]
            if (abs(red - background[0]) + abs(green - background[1])
                    + abs(blue - background[2])) > threshold:
                mask[row + x] = True
    return mask


def row_fraction(mask: list[bool], width: int, y: int, x0: int, x1: int) -> float:
    row = y * width
    count = sum(1 for x in range(x0, x1) if mask[row + x])
    return count / max(1, x1 - x0)


def column_fraction(mask: list[bool], width: int, height: int,
                    x: int, y0: int, y1: int) -> float:
    count = sum(1 for y in range(y0, y1) if mask[y * width + x])
    return count / max(1, y1 - y0)


def main() -> None:
    args = parse_args()
    image = Image.open(args.image).convert("RGBA")
    if not args.no_crop_alpha:
        opaque = image.getchannel("A").point(lambda value: 255 if value == 255 else 0)
        bbox = opaque.getbbox()
        if bbox and bbox != (0, 0, *image.size):
            image = image.crop(bbox)
        else:
            corner = image.convert("RGB").getpixel((0, 0))
            if max(corner) < 8:
                difference = ImageChops.difference(
                    image.convert("RGB"), Image.new("RGB", image.size, corner)
                ).convert("L").point(lambda value: 255 if value > 12 else 0)
                window_bbox = difference.getbbox()
                if window_bbox and window_bbox != (0, 0, *image.size):
                    image = image.crop(window_bbox)
    width, height = image.size
    scale = args.scale
    points_width = width / scale
    points_height = height / scale
    background = (30, 30, 30)
    if args.background:
        background = tuple(int(part) for part in args.background.split(","))  # type: ignore[assignment]
    else:
        # The footer can contain a coloured button at the sampled pixel. Use
        # the dominant surface colour in the lower interior instead.
        region = image.convert("RGB").crop(
            (max(2, width // 20), int(height * 0.65), width - 2, height - 2)
        )
        colors = region.getcolors(maxcolors=1_000_000)
        if colors:
            background = max(colors, key=lambda entry: entry[0])[1]
    mask = foreground_mask(image, background)
    content_top = args.content_top if args.content_top is not None else 0.0
    top_px = min(height - 1, max(0, int(content_top * scale)))
    side_px = max(2, int(10 * scale))
    border_px = max(2, int(2 * scale))

    last_y = top_px
    for y in range(height - 1 - border_px, top_px - 1, -1):
        if row_fraction(mask, width, y, side_px, width - side_px) > args.bottom_threshold:
            last_y = y
            break
    last_x = 0
    for x in range(width - 1 - border_px, side_px - 1, -1):
        if column_fraction(mask, width, height, x, top_px, last_y + 1) > args.bottom_threshold:
            last_x = x
            break

    content_bbox = (0.0, content_top, points_width, max(0.0, (last_y + 1) / scale - content_top))
    blank_bottom = max(0.0, points_height - (last_y + 1) / scale)
    blank_right = max(0.0, points_width - (last_x + 1) / scale)

    annotated = image.copy()
    draw = ImageDraw.Draw(annotated, "RGBA")
    minor = max(1.0, args.grid * scale)
    major = max(1.0, args.major * scale)
    label_font = font(max(10, int(10 * scale)))
    small_font = font(max(8, int(8 * scale)))

    x = 0.0
    while x <= width:
        is_major = abs((x / scale) % args.major) < 0.01
        draw.line((x, 0, x, height), fill=(0, 220, 160, 90 if is_major else 24),
                  width=2 if is_major else 1)
        x += major if is_major else minor

    y = 0.0
    while y <= height:
        is_major = abs((y / scale) % args.major) < 0.01
        draw.line((0, y, width, y), fill=(0, 220, 160, 90 if is_major else 24),
                  width=2 if is_major else 1)
        y += major if is_major else minor

    for point in range(0, int(points_height) + 1, int(args.major)):
        y_px = point * scale
        label = f"{point}"
        text_width = draw.textlength(label, font=small_font)
        draw.rectangle((4, y_px + 2, 10 + text_width, y_px + 4 + small_font.size),
                       fill=(0, 0, 0, 150))
        draw.text((7, y_px + 3), label, fill=(180, 255, 230, 255), font=small_font)

    for point in range(0, int(points_width) + 1, int(args.major)):
        x_px = point * scale
        label = f"{point}"
        text_width = draw.textlength(label, font=small_font)
        draw.rectangle((x_px + 2, 2, x_px + 8 + text_width, 6 + small_font.size),
                       fill=(0, 0, 0, 150))
        draw.text((x_px + 5, 3), label, fill=(180, 255, 230, 255), font=small_font)

    bounding = (
        (0, top_px),
        (width - 1, max(top_px, last_y)),
    )
    draw.rectangle(bounding, outline=(255, 190, 70, 230), width=3)
    if last_y + 1 < height:
        draw.rectangle((0, last_y + 1, width - 1, height - 1), fill=(255, 80, 80, 55))
    draw.text((16, max(top_px + 6, last_y - int(22 * scale))),
              f"content ends {last_y / scale:.1f} pt  |  empty bottom {blank_bottom:.1f} pt",
              fill=(255, 220, 120, 255), font=label_font)

    window_rect = parse_rect(args.window)
    if window_rect:
        x0, y0, w, h = window_rect
        draw.rectangle((x0 * scale, y0 * scale, (x0 + w) * scale, (y0 + h) * scale),
                       outline=(80, 220, 255, 230), width=3)

    out = args.out or args.image.with_name(args.image.stem + "-grid.png")
    annotated.convert("RGB").save(out)
    report = {
        "image": str(args.image),
        "annotated": str(out),
        "scale": scale,
        "size_points": [points_width, points_height],
        "background": list(background),
        "content_top_points": content_top,
        "content_bbox_points": list(content_bbox),
        "content_bottom_points": (last_y + 1) / scale,
        "blank_bottom_points": blank_bottom,
        "blank_right_points": blank_right,
        "window_points": list(window_rect) if window_rect else None,
    }
    json_path = args.json or args.image.with_name(args.image.stem + "-grid.json")
    json_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
