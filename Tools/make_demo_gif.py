#!/usr/bin/env python3
"""Render the bilingual Clamshell Awake README demo GIF."""

from __future__ import annotations

import glob
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


WIDTH = 960
HEIGHT = 540
FRAME_COUNT = 56
FRAME_MS = 100
OUTPUT = Path(__file__).resolve().parents[1] / "Assets" / "demo.gif"


def find_font() -> str:
    candidates = [
        "/System/Library/Fonts/PingFang.ttc",
        "/Library/Fonts/Arial Unicode.ttf",
    ]
    candidates.extend(glob.glob("/System/Library/AssetsV2/**/PingFang.ttc", recursive=True))
    candidates.extend([
        "/System/Library/Fonts/Helvetica.ttc",
        "/System/Library/Fonts/HelveticaNeue.ttc",
    ])
    for candidate in candidates:
        if Path(candidate).exists():
            return candidate
    raise RuntimeError("No suitable macOS font found")


FONT_PATH = find_font()


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_PATH, size=size)


def ease(value: float) -> float:
    value = max(0.0, min(1.0, value))
    return value * value * (3 - 2 * value)


def lerp(a: float, b: float, value: float) -> float:
    return a + (b - a) * value


def gradient_background() -> Image.Image:
    image = Image.new("RGB", (WIDTH, HEIGHT), "#071225")
    pixels = image.load()
    start = (7, 18, 37)
    middle = (16, 42, 87)
    end = (13, 90, 107)
    for y in range(HEIGHT):
        for x in range(WIDTH):
            t = (x / WIDTH * 0.72) + (y / HEIGHT * 0.28)
            if t < 0.56:
                local = t / 0.56
                color = tuple(int(lerp(start[i], middle[i], local)) for i in range(3))
            else:
                local = (t - 0.56) / 0.44
                color = tuple(int(lerp(middle[i], end[i], local)) for i in range(3))
            pixels[x, y] = color
    return image


BACKGROUND = gradient_background()


def rounded(draw: ImageDraw.ImageDraw, box, radius: int, fill, outline=None, width: int = 1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def centered_text(draw: ImageDraw.ImageDraw, xy, text: str, face, fill, stroke_width: int = 0):
    box = draw.textbbox((0, 0), text, font=face, stroke_width=stroke_width)
    x = xy[0] - (box[2] - box[0]) / 2
    y = xy[1] - (box[3] - box[1]) / 2 - box[1]
    draw.text((x, y), text, font=face, fill=fill, stroke_width=stroke_width)


def draw_laptop(draw: ImageDraw.ImageDraw, frame: int, enabled: bool):
    close_t = ease((frame - 39) / 12)
    x = 70
    base_y = 390
    screen_top = int(lerp(166, 352, close_t))
    screen_height = max(18, int(lerp(208, 22, close_t)))

    # Soft shadow and screen.
    rounded(draw, (x + 8, screen_top + 12, x + 348, base_y + 22), 24, "#031027")
    rounded(draw, (x, screen_top, x + 340, screen_top + screen_height), 23, "#e6f0ff")
    if screen_height > 42:
        rounded(draw, (x + 14, screen_top + 14, x + 326, screen_top + screen_height - 14), 12, "#0b1d3c")
        available = screen_height - 28
        alpha = min(1.0, available / 180)
        line_color = tuple(int(lerp(40, c, alpha)) for c in (180, 232, 255))
        line_y = screen_top + 40
        for index, width in enumerate((188, 226, 154, 210)):
            if line_y + index * 27 < screen_top + screen_height - 25:
                rounded(
                    draw,
                    (x + 37, line_y + index * 27, x + 37 + width, line_y + 10 + index * 27),
                    5,
                    line_color,
                )
        if close_t < 0.72:
            pulse = 0.55 + 0.45 * math.sin(frame * 0.55) ** 2
            draw.ellipse((x + 280, screen_top + 29, x + 296, screen_top + 45), fill=(74, 222, 128))
            draw.ellipse((x + 276, screen_top + 25, x + 300, screen_top + 49), outline=(74, 222, 128), width=max(1, int(3 * pulse)))

    # Base and hinge.
    draw.polygon(
        [(x - 25, base_y), (x + 365, base_y), (x + 338, base_y + 34), (x + 2, base_y + 34)],
        fill="#f8fafc",
    )
    rounded(draw, (x + 126, base_y + 7, x + 214, base_y + 16), 5, "#93a9c9")

    # Floating process indicator remains alive even after the lid closes.
    pill_y = 446
    rounded(draw, (x + 18, pill_y, x + 322, pill_y + 48), 24, "#08172f", "#2f588e", 2)
    dot_color = "#4ade80" if enabled else "#94a3b8"
    draw.ellipse((x + 42, pill_y + 16, x + 58, pill_y + 32), fill=dot_color)
    phase = frame % 12
    dots = "." * (1 + phase // 4)
    draw.text((x + 70, pill_y + 12), f"codex > agent running{dots}", font=font(17), fill="#dbeafe")


def draw_dashboard(draw: ImageDraw.ImageDraw, frame: int, enabled: bool):
    x, y, w, h = 488, 72, 405, 365
    rounded(draw, (x + 8, y + 12, x + w + 8, y + h + 12), 28, "#061027")
    rounded(draw, (x, y, x + w, y + h), 28, "#f8fafc", "#cbd5e1", 2)

    # Window chrome and language control.
    for offset, color in enumerate(("#ff5f57", "#febc2e", "#28c840")):
        draw.ellipse((x + 20 + offset * 22, y + 18, x + 32 + offset * 22, y + 30), fill=color)
    english = frame >= 47
    rounded(draw, (x + 326, y + 17, x + 380, y + 45), 14, "#e8eef7")
    centered_text(draw, (x + 353, y + 31), "中文" if english else "EN", font(13), "#30527d")

    # Header.
    icon_box = (x + 174, y + 54, x + 230, y + 110)
    rounded(draw, icon_box, 15, "#1d4ed8")
    draw.polygon(
        [(x + 204, y + 63), (x + 187, y + 88), (x + 200, y + 88), (x + 195, y + 102), (x + 218, y + 78), (x + 205, y + 78)],
        fill="#a7f3d0",
    )
    centered_text(draw, (x + w / 2, y + 132), "Clamshell Awake" if english else "合盖工作", font(28), "#0f172a", 1)
    centered_text(
        draw,
        (x + w / 2, y + 163),
        "Keep working with the lid closed" if english else "合上 MacBook，任务继续运行",
        font(15),
        "#64748b",
    )

    # Status card.
    rounded(draw, (x + 28, y + 190, x + w - 28, y + 273), 16, "#eef3f8", "#d4dde8", 2)
    status_color = "#22c55e" if enabled else "#94a3b8"
    draw.ellipse((x + 48, y + 208, x + 62, y + 222), fill=status_color)
    status = (
        "Enabled · Work continues with lid closed"
        if english and enabled
        else "Disabled · Normal system sleep"
        if english
        else "已开启 · 合盖后继续工作"
        if enabled
        else "已关闭 · 系统正常睡眠"
    )
    draw.text((x + 74, y + 204), status, font=font(15), fill="#14213d")
    detail = (
        "10% battery protection · auto brightness restore"
        if english
        else "10% 低电量保护 · 自动恢复屏幕亮度"
    )
    draw.text((x + 48, y + 238), detail, font=font(13), fill="#64748b")

    # Primary action and animated cursor.
    button_y = y + 294
    click_t = ease((frame - 17) / 5) * (1 - ease((frame - 23) / 4))
    inset = int(3 * click_t)
    button_color = "#0f766e" if enabled else "#2563eb"
    rounded(draw, (x + 28 + inset, button_y + inset, x + w - 28 - inset, button_y + 51 - inset), 14, button_color)
    button = (
        "Disable and restore normal sleep"
        if english and enabled
        else "Enable clamshell work mode"
        if english
        else "关闭并恢复正常睡眠"
        if enabled
        else "开启合盖工作模式"
    )
    centered_text(draw, (x + w / 2, button_y + 26), button, font(16), "#ffffff")

    if 8 <= frame <= 30:
        move = ease((frame - 8) / 10)
        cursor_x = int(lerp(x + 355, x + 280, move))
        cursor_y = int(lerp(y + 360, button_y + 20, move))
        draw.polygon(
            [(cursor_x, cursor_y), (cursor_x + 4, cursor_y + 24), (cursor_x + 10, cursor_y + 17), (cursor_x + 18, cursor_y + 18)],
            fill="#ffffff",
            outline="#0f172a",
        )


def draw_caption(draw: ImageDraw.ImageDraw, frame: int):
    if frame < 9:
        title = "Close the lid. Keep the task running."
        subtitle = "合上 MacBook，Codex 和 Claude Code 继续工作"
    elif frame < 26:
        title = "1  Enable clamshell work mode"
        subtitle = "点击开启合盖工作模式"
    elif frame < 39:
        title = "2  Wait for the green status"
        subtitle = "看到绿色状态后再合盖"
    else:
        title = "3  Close the lid safely"
        subtitle = "任务继续运行 · 10% 低电量自动保护"

    centered_text(draw, (WIDTH / 2, 28), title, font(24), "#ffffff", 1)
    centered_text(draw, (WIDTH / 2, 56), subtitle, font(15), "#bfe7ff")


def render(frame: int) -> Image.Image:
    image = BACKGROUND.copy()
    draw = ImageDraw.Draw(image)

    # Ambient circles.
    draw.ellipse((760, -150, 1080, 170), fill="#123c73")
    draw.ellipse((-140, 360, 190, 690), fill="#102f63")

    enabled = frame >= 25
    draw_caption(draw, frame)
    draw_laptop(draw, frame, enabled)
    draw_dashboard(draw, frame, enabled)

    # Compact feature badges.
    badges = [("Native Swift", "#1d4ed8"), ("10% Safety", "#0f766e"), ("No telemetry", "#6d28d9")]
    bx = 500
    for label, color in badges:
        badge_w = int(draw.textlength(label, font=font(12))) + 24
        rounded(draw, (bx, 458, bx + badge_w, 487), 14, color)
        centered_text(draw, (bx + badge_w / 2, 472), label, font(12), "#ffffff")
        bx += badge_w + 10

    centered_text(draw, (700, 514), "github.com/TonT-wilshere/codex-clamshell-keep-awake", font(13), "#b7d9ff")
    return image


def save_gif(frames: list[Image.Image]):
    # Build a shared palette from representative thumbnails to avoid color flicker.
    samples = [frames[index].resize((240, 135)) for index in range(0, FRAME_COUNT, 4)]
    atlas = Image.new("RGB", (240 * len(samples), 135))
    for index, sample in enumerate(samples):
        atlas.paste(sample, (index * 240, 0))
    palette = atlas.quantize(colors=128, method=Image.Quantize.MEDIANCUT)
    quantized = [
        frame.quantize(palette=palette, dither=Image.Dither.FLOYDSTEINBERG)
        for frame in frames
    ]
    quantized[0].save(
        OUTPUT,
        save_all=True,
        append_images=quantized[1:],
        duration=FRAME_MS,
        loop=0,
        optimize=True,
        disposal=2,
    )


def main():
    frames = [render(frame) for frame in range(FRAME_COUNT)]
    save_gif(frames)
    print(f"Wrote {OUTPUT} ({OUTPUT.stat().st_size / 1024 / 1024:.2f} MiB)")


if __name__ == "__main__":
    main()
