#!/usr/bin/env python3
"""Subset Sarasa Gothic SC into a web woff2 (GB2312 common chars + ASCII)."""

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
            "--flavor=woff2",
            "--layout-features=*",
            "--no-hinting",
        ],
        check=True,
    )
    print(f"subset done: {args.dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
