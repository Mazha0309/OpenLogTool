#!/usr/bin/env python3
"""Subset Sarasa Gothic SC into a web ttf (GB2312 common chars + ASCII).

Output is ttf (not woff2): Flutter Web's FontManifest only accepts ttf/otf,
and CanvasKit/skwasm ignores CSS @font-face. The app loads the subset via
FontLoader at startup (see lib/services/app_fonts.dart).
"""

import argparse, subprocess
from pathlib import Path

COMMON = (
    " !\"#$%&'()*+,-./0123456789:;<=>?@"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`"
    "abcdefghijklmnopqrstuvwxyz{|}~"
    "，。、；：？！“”‘’（）【】《》〈〉—…·％°℃＋－×÷＝＜＞￥★☆①②③④⑤⑥⑦⑧⑨⑩"
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("src", type=Path)
    parser.add_argument("dst", type=Path)
    args = parser.parse_args()
    args.dst.parent.mkdir(parents=True, exist_ok=True)

    # GB2312 level-1 (3755 chars) encoded as unicode range
    # level-1 characters occupy rows 0xB0-0xD7, bytes 0xA1-0xFE in GB2312.
    chars = set(COMMON)
    for row in range(0xB0, 0xD8):
        for col in range(0xA1, 0xFF):
            gb = bytes([row, col])
            try:
                chars.add(gb.decode("gb2312"))
            except UnicodeDecodeError:
                pass
    textfile = args.dst.with_suffix(".txt")
    textfile.write_text("".join(sorted(chars)), encoding="utf-8")
    subprocess.run(
        [
            "pyftsubset",
            str(args.src),
            f"--output-file={args.dst}",
            f"--text-file={textfile}",
            "--layout-features=*",
            "--no-hinting",
        ],
        check=True,
    )
    print(f"subset done: {args.dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
