#!/usr/bin/env python3
"""Renders the DMG background PNGs from `dmg-background.svg`.

Requires `cairosvg` (pip install cairosvg). Only needed when the SVG changes; the
generated PNGs are committed so builds need no extra tools. The app icon is an
Icon Composer document (`ClaudeWatch/AppIcon.icon`) compiled by Xcode.
"""
from pathlib import Path

import cairosvg

HERE = Path(__file__).resolve().parent


def main() -> None:
    background = (HERE / "dmg-background.svg").read_bytes()
    cairosvg.svg2png(bytestring=background, write_to=str(HERE / "dmg-background.png"), output_width=660, output_height=400)
    cairosvg.svg2png(bytestring=background, write_to=str(HERE / "dmg-background@2x.png"), output_width=1320, output_height=800)


if __name__ == "__main__":
    main()
