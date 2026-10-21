#!/usr/bin/env python3
"""Contrast-check the Flexoki Claude Code themes.

Claude Code hard-codes dimColor:true on Select-option descriptions (the text
under each choice in AskUserQuestion), layered on top of an explicit truecolor
foreground. There is no setting to turn that off, so any token that can carry
description text has to clear AA *after* the terminal's faint rendering.

Two dim models are checked, because terminals differ:
  mul-linear  fg_linear * 0.5           (WezTerm and most GPU terminals)
  mul-srgb    fg_srgb   * 0.5           (pessimistic floor)

Exit 1 if any text-bearing token falls below its floor.

  python3 check-contrast.py                 # check both shipped themes
  python3 check-contrast.py --all           # show every token, not just text ones
"""
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).parent

# Tokens that can end up rendering dimmed body text. These carry the AA floor.
# 'success' and 'suggestion' are the AskUserQuestion option-description colors
# (selected / focused respectively) — the original bug.
TEXT_TOKENS = {
    "text": 4.5,
    "inactive": 4.5,
    "subtle": 3.0,        # least-prominent tier; kept below inactive on purpose
    "suggestion": 4.5,
    "success": 4.4,
    "warning": 4.5,
    "error": 3.0,         # nearly always bold or undimmed in practice
}

# Background each theme is designed against. These are the ACTUAL backgrounds
# of WezTerm's builtin flexoki-dark / flexoki-light schemes, read out of
# wezterm.color.get_builtin_schemes() — not Flexoki's nominal black (#100f0f).
# The dark scheme sits on base-950, one step up the ramp, which costs about
# 0.7 of contrast ratio versus black. Measure against what renders.
BACKGROUNDS = {"dark": "#1c1b1a", "light": "#fffcf0"}


def hex_to_rgb(h):
    h = h.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def srgb_to_linear(v):
    v /= 255
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def linear_to_srgb(v):
    v = 12.92 * v if v <= 0.0031308 else 1.055 * (v ** (1 / 2.4)) - 0.055
    return max(0, min(255, round(v * 255)))


def luminance(rgb):
    r, g, b = (srgb_to_linear(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    hi, lo = sorted((luminance(a), luminance(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def dim_linear(rgb):
    return tuple(linear_to_srgb(srgb_to_linear(c) * 0.5) for c in rgb)


def dim_srgb(rgb):
    return tuple(round(c * 0.5) for c in rgb)


def check(path, show_all=False):
    theme = json.loads(path.read_text())
    base = theme.get("base", "dark")
    bg = hex_to_rgb(BACKGROUNDS[base])
    overrides = theme["overrides"]

    print(f"\n{theme['name']}  ({path.name}, base={base}, bg={BACKGROUNDS[base]})")
    print(f"  {'token':<28}{'hex':<10}{'plain':>8}{'dim-lin':>9}{'dim-srgb':>10}  floor")
    failures = []

    items = overrides.items() if show_all else (
        (k, overrides[k]) for k in TEXT_TOKENS if k in overrides
    )
    for token, value in sorted(items):
        rgb = hex_to_rgb(value)
        plain = contrast(rgb, bg)
        d_lin = contrast(dim_linear(rgb), bg)
        d_srgb = contrast(dim_srgb(rgb), bg)
        floor = TEXT_TOKENS.get(token)

        # On a light background, dimming darkens the foreground and contrast
        # only goes up — the dim columns are informational, not gating.
        gating = min(d_lin, plain) if base == "dark" else plain
        mark = ""
        if floor is not None:
            if gating + 1e-9 < floor:
                mark = "  FAIL"
                failures.append((token, value, gating, floor))
            else:
                mark = "  ok"

        floor_s = f"{floor:.1f}" if floor else "-"
        print(f"  {token:<28}{value:<10}{plain:8.2f}{d_lin:9.2f}{d_srgb:10.2f}  "
              f"{floor_s:>5}{mark}")

    return failures


def main():
    show_all = "--all" in sys.argv
    all_failures = []
    for name in ("flexoki-dark.json", "flexoki-light.json"):
        path = HERE / name
        if not path.exists():
            print(f"missing: {path}", file=sys.stderr)
            return 1
        all_failures += check(path, show_all)

    if all_failures:
        print("\nFAILURES:")
        for token, value, got, floor in all_failures:
            print(f"  {token} = {value}: {got:.2f} < {floor:.1f}")
        return 1
    print("\nAll text-bearing tokens clear their floor.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
