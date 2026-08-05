# Bundled font

`SarasaGothicSC-Regular.ttf` is a size-optimized subset of Sarasa Gothic SC.
It retains Latin, Greek, Cyrillic, common symbols, CJK punctuation, Japanese
kana, CJK Extension A, the basic CJK unified ideographs, compatibility
ideographs, and full-width forms. System fallback fonts render characters
outside that set.

The checked-in subset was produced with FontTools:

```bash
pyftsubset SarasaGothicSC-Regular.full.ttf \
  --output-file=assets/fonts/SarasaGothicSC-Regular.ttf \
  --unicodes='U+0000-024F,U+0370-052F,U+2000-206F,U+20A0-20CF,U+2100-214F,U+2190-22FF,U+2460-26FF,U+2E80-2FFF,U+3000-303F,U+3040-30FF,U+31C0-33FF,U+3400-4DBF,U+4E00-9FFF,U+F900-FAFF,U+FE10-FE1F,U+FE30-FE4F,U+FF00-FFEF' \
  --layout-features='*' \
  --no-hinting
```

The original font and this modified subset are distributed under the SIL Open
Font License 1.1. See `OFL-Sarasa-Gothic.txt`.
