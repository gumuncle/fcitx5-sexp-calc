#!/usr/bin/env python3
"""Render docs/demo.gif, an animation of the QuickPhrase calculator flow.

The frames are drawn with Pillow (it is not a screen recording). The results
shown are computed by sexp_calc.lua itself through lua5.5 when available.

    python3 docs/make_demo.py            # writes docs/demo.gif
    python3 docs/make_demo.py --png DIR  # also dumps a few key frames as PNG
"""
import os
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "demo.gif"

W, H = 800, 400   # output size
S = 2             # supersampling factor for crisp text

# (text already on the line, S-expression typed through QuickPhrase)
DEMOS = [("1 + 2 = ", "(+ 1 2)"), ("2 * (3 + 4) = ", "(* 2 (+ 3 4))"), ("sqrt 2 = ", "(sqrt 2)")]
FALLBACK_RESULTS = {"(+ 1 2)": "3", "(* 2 (+ 3 4))": "14", "(sqrt 2)": "1.4142135623731"}

# Colors (Catppuccin Mocha for the editor, light popup like fcitx5's default theme)
OUTER = (17, 17, 27)
TITLE_BG = (24, 24, 37)
WIN_BG = (30, 30, 46)
WIN_BORDER = (49, 50, 68)
TEXT = (205, 214, 244)
DIM = (108, 112, 134)
ACCENT = (137, 180, 250)
CAPTION = (166, 173, 200)
POPUP_BG = (250, 250, 250)
POPUP_BORDER = (190, 190, 190)
POPUP_TEXT = (60, 60, 60)
KEY_BG = (49, 50, 68)
KEY_BORDER = (88, 91, 112)
KEY_TEXT = (205, 214, 244)
LIGHTS = [(243, 139, 168), (249, 226, 175), (166, 227, 161)]

MONO_FONTS = [
    "/usr/share/fonts/TTF/JetBrainsMonoNerdFontMono-Regular.ttf",
    "/usr/share/fonts/TTF/JetBrainsMono-Regular.ttf",
    "/usr/share/fonts/TTF/Hack-Regular.ttf",
    "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
]
SANS_FONTS = [
    "/usr/share/fonts/noto/NotoSans-Regular.ttf",
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
]
SANS_BOLD_FONTS = [
    "/usr/share/fonts/noto/NotoSans-Bold.ttf",
    "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
]


def font(candidates, size):
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size * S)
    return ImageFont.load_default(size * S)


MONO = font(MONO_FONTS, 20)
MONO_SMALL = font(MONO_FONTS, 14)
SANS = font(SANS_FONTS, 15)
SANS_CAPTION = font(SANS_FONTS, 17)
SANS_BOLD = font(SANS_BOLD_FONTS, 14)


def evaluate(expr):
    """Ask the real evaluator for the result; fall back to known values."""
    code = r"""
package.preload["fcitx"] = function()
  return { QuickPhraseAction = { Break = -1, Commit = 0, TypeToBuffer = 1, DigitSelection = 2,
           AlphaSelection = 3, NoneSelection = 4, DoNothing = 5, AutoCommit = 6 },
           addQuickPhraseHandler = function() return 1 end, log = function() end }
end
dofile(os.getenv("SEXP_CALC_LUA"))
io.write(sexp_calc.format_value(sexp_calc.evaluate_string(os.getenv("SEXP_EXPR"))))
"""
    env = dict(os.environ, SEXP_CALC_LUA=str(ROOT / "sexp_calc.lua"), SEXP_EXPR=expr)
    for lua in ("lua5.5", "lua5.4", "lua"):
        try:
            r = subprocess.run([lua, "-e", code], env=env, capture_output=True, text=True, timeout=10)
        except FileNotFoundError:
            continue
        if r.returncode == 0 and r.stdout:
            return r.stdout
    return FALLBACK_RESULTS[expr]


def s(*vals):
    return tuple(v * S for v in vals)


def rounded(d, box, r, **kw):
    d.rounded_rectangle(s(*box), radius=r * S, **kw)


def text(d, xy, string, fnt, fill, anchor="la"):
    d.text(s(*xy), string, font=fnt, fill=fill, anchor=anchor)


def width(d, string, fnt):
    return d.textlength(string, font=fnt) / S


def keycaps(d, x, y, keys):
    """Draw keycaps right-aligned so that the last cap ends at x."""
    caps = []
    for k in keys:
        w = width(d, k, SANS_BOLD) + 16
        caps.append((k, w))
    total = sum(w for _, w in caps) + 6 * (len(caps) - 1)
    cx = x - total
    for k, w in caps:
        rounded(d, (cx, y, cx + w, y + 26), 5, fill=KEY_BG, outline=KEY_BORDER, width=S)
        text(d, (cx + w / 2, y + 13), k, SANS_BOLD, KEY_TEXT, anchor="mm")
        cx += w + 6


def render(doc_lines, label, typed, popup, keycap, caption):
    img = Image.new("RGB", (W * S, H * S), OUTER)
    d = ImageDraw.Draw(img)

    # Window frame with title bar
    rounded(d, (24, 24, 776, 316), 10, fill=TITLE_BG, outline=WIN_BORDER, width=S)
    rounded(d, (25, 58, 775, 315), 10, fill=WIN_BG)
    d.rectangle(s(25, 58, 775, 72), fill=WIN_BG)
    for i, c in enumerate(LIGHTS):
        d.ellipse(s(40 + i * 20, 35, 52 + i * 20, 47), fill=c)
    text(d, (400, 41), "notes.txt", SANS, DIM, anchor="mm")

    # Document body
    x0, y0, lh = 48, 82, 34
    text(d, (x0, y0), "# quick calculations", MONO, DIM)
    for i, line in enumerate(doc_lines):
        text(d, (x0, y0 + lh * (i + 1)), line, MONO, TEXT)
    cy = y0 + lh * (len(doc_lines) + 1)

    text(d, (x0, cy), label, MONO, TEXT)
    ex = x0 + width(d, label, MONO)  # where the S-expression starts
    caret_x = ex
    if typed:
        text(d, (ex, cy), typed, MONO, TEXT)
        tw = width(d, typed, MONO)
        d.line(s(ex, cy + 27, ex + tw, cy + 27), fill=TEXT, width=S)  # preedit underline
        caret_x = ex + tw
    d.rectangle(s(caret_x + 1, cy - 1, caret_x + 3, cy + 25), fill=ACCENT)

    # fcitx5 input panel: shows the QuickPhrase aux text while it is active
    if popup:
        label = "Quick Phrase: "
        pw = width(d, label, SANS) + 24
        px, py = ex, cy + 36
        rounded(d, (px + 2, py + 2, px + pw + 2, py + 32), 6, fill=(0, 0, 0))
        rounded(d, (px, py, px + pw, py + 30), 6, fill=POPUP_BG, outline=POPUP_BORDER, width=S)
        text(d, (px + 12, py + 15), label, SANS, POPUP_TEXT, anchor="lm")

    if keycap:
        keycaps(d, 760, 70, ["Super", "+", "`"])

    text(d, (400, 358), caption, SANS_CAPTION, CAPTION, anchor="mm")
    return img.resize((W, H), Image.LANCZOS)


def build_frames():
    frames = []  # (image, duration_ms)
    doc = []
    for n, (label, expr) in enumerate(DEMOS):
        result = evaluate(expr)
        frames.append((render(doc, label, "", False, False, "Put the cursor in any text field"),
                       900 if n == 0 else 500))
        frames.append((render(doc, label, "", True, True, "Press Super+` to open fcitx5 QuickPhrase"), 1100))
        for i in range(1, len(expr) + 1):
            frames.append((render(doc, label, expr[:i], True, i <= 2,
                                  "Type an S-expression (no candidates until it is complete)"), 100))
        frames.append((render(doc, label, expr, True, False,
                              "Parentheses balanced: the expression is evaluated"), 350))
        doc.append(label + result)
        frames.append((render(doc, "", "", False, False, f"Result {result} is committed, QuickPhrase closes"),
                       1600 if n < len(DEMOS) - 1 else 2600))
    return frames


def save_gif(frames, out):
    imgs = [f for f, _ in frames]
    durs = [ms for _, ms in frames]
    # Shared palette built from a few representative frames
    picks = [imgs[0], imgs[1], imgs[len(imgs) // 2], imgs[-1]]
    sheet = Image.new("RGB", (W * len(picks), H))
    for i, im in enumerate(picks):
        sheet.paste(im, (W * i, 0))
    palette = sheet.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    quantized = [im.quantize(palette=palette, dither=Image.Dither.NONE) for im in imgs]
    quantized[0].save(out, save_all=True, append_images=quantized[1:], duration=durs, loop=0,
                      optimize=True, disposal=1)


def main():
    frames = build_frames()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    save_gif(frames, OUT)
    print(f"wrote {OUT} ({OUT.stat().st_size / 1024:.0f} KiB, {len(frames)} frames, "
          f"{sum(ms for _, ms in frames) / 1000:.1f} s)")
    if "--png" in sys.argv:
        out_dir = Path(sys.argv[sys.argv.index("--png") + 1])
        out_dir.mkdir(parents=True, exist_ok=True)
        picks = {"idle": 0, "trigger": 1, "typing": 5, "balanced": len(DEMOS[0][1]) + 2, "committed": len(DEMOS[0][1]) + 3}
        for name, idx in picks.items():
            frames[idx][0].save(out_dir / f"{name}.png")
        frames[-1][0].save(out_dir / "final.png")
        print(f"preview frames in {out_dir}")


if __name__ == "__main__":
    main()
