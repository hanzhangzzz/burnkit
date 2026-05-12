#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shutil
import subprocess
from pathlib import Path

from playwright.sync_api import sync_playwright


ROOT = Path(__file__).resolve().parents[2]
HTML = ROOT / "assets" / "launch" / "c-router-launch.html"
OUT = ROOT / "assets" / "launch" / "c-router-launch.gif"
FRAMES = ROOT / ".tmp" / "c-router-launch-frames"


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True)


def render_frames(duration_ms: int, fps: int, width: int, height: int) -> None:
    if FRAMES.exists():
        shutil.rmtree(FRAMES)
    FRAMES.mkdir(parents=True)

    total_frames = int(duration_ms / 1000 * fps)
    url = HTML.resolve().as_uri()

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch()
        page = browser.new_page(viewport={"width": width, "height": height}, device_scale_factor=1)
        page.goto(url)
        page.wait_for_load_state("networkidle")
        for frame in range(total_frames):
            ms = round(frame * 1000 / fps)
            page.evaluate("ms => window.renderAt(ms)", ms)
            page.screenshot(path=str(FRAMES / f"frame-{frame:04d}.png"), animations="disabled")
        browser.close()


def build_gif(fps: int, output: Path) -> None:
    palette = FRAMES / "palette.png"
    run([
        "ffmpeg",
        "-y",
        "-framerate",
        str(fps),
        "-i",
        str(FRAMES / "frame-%04d.png"),
        "-vf",
        "palettegen=stats_mode=diff",
        str(palette),
    ])
    run([
        "ffmpeg",
        "-y",
        "-framerate",
        str(fps),
        "-i",
        str(FRAMES / "frame-%04d.png"),
        "-i",
        str(palette),
        "-lavfi",
        "paletteuse=dither=bayer:bayer_scale=3",
        "-loop",
        "0",
        str(output),
    ])


def main() -> None:
    parser = argparse.ArgumentParser(description="Render the BurnKit c router launch GIF.")
    parser.add_argument("--duration-ms", type=int, default=16000)
    parser.add_argument("--fps", type=int, default=12)
    parser.add_argument("--width", type=int, default=1000)
    parser.add_argument("--height", type=int, default=560)
    parser.add_argument("--output", type=Path, default=OUT)
    parser.add_argument("--keep-frames", action="store_true")
    args = parser.parse_args()

    render_frames(args.duration_ms, args.fps, args.width, args.height)
    build_gif(args.fps, args.output)

    if not args.keep_frames:
        shutil.rmtree(FRAMES)


if __name__ == "__main__":
    main()
