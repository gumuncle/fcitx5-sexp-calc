# fcitx5-sexp-calc

English | [日本語](README.ja.md)

An S-expression calculator for [fcitx5](https://fcitx-im.org/) QuickPhrase.
Type `(+ 1 2)` and `3` is entered, in any application and with any input method engine.

![Demo: typing (+ 1 2) in QuickPhrase commits 3](docs/demo.gif)

- Engine-independent: works the same whether Mozc, Pinyin or the plain keyboard is active, because it hooks into QuickPhrase rather than the engine
- Two small Lua files running on [fcitx5-lua](https://github.com/fcitx/fcitx5-lua): the evaluator (`sexp_core.lua`) and the fcitx5 adapter (`sexp_calc.lua`)
- The result is committed the moment the parentheses balance, with no extra keystroke

## Requirements

- fcitx5 5.1.x
- fcitx5-lua (Arch Linux / CachyOS: `sudo pacman -S fcitx5-lua`)
- Optional, for the tests: Lua 5.5 (`lua5.5`) and python-gobject

## Install

```sh
make install   # symlinks sexp_calc.lua and sexp_core.lua into ~/.local/share/fcitx5/lua/imeapi/extensions/
make restart   # restarts fcitx5 so the extension gets loaded
```

`make restart` runs `systemctl --user restart app-org.fcitx.Fcitx5@autostart.service`, which is
the unit name when fcitx5 is started through XDG autostart on a systemd user session. Change
`UNIT` in the Makefile if your fcitx5 is started differently. After the restart fcitx5 falls back
to the first input method (usually the plain keyboard), so switch back to your engine with
Ctrl+Space. In testing, `fcitx5-remote -r` did not pick up newly installed addons.

## macOS (fcitx5-macos)

fcitx5 also runs on macOS 13.3 or later through [fcitx5-macos](https://github.com/fcitx-contrib/fcitx5-macos),
and its [plugin repository](https://github.com/fcitx-contrib/fcitx5-plugins) ships both fcitx5-lua and
fcitx5-mozc, so the same setup should work there. This has not been verified on a Mac by the author yet;
reports are welcome.

1. Install fcitx5-macos, open its Plugin Manager and install the `lua` plugin (plus `mozc` or another
   engine if you want one).
2. Run `make install`. fcitx5-macos keeps user data under `~/.local/share/fcitx5`, the same path as Linux.
3. Restart fcitx5 from the Fcitx5 menu bar icon. On macOS `make restart` only prints this reminder.
4. Change the QuickPhrase trigger key in the fcitx5 settings. fcitx5's `Super` is the Command key on
   macOS, and the defaults `Cmd+`` (window cycling) and `Cmd+;` (spell checking in many apps) are
   already taken.

`make test` uses whichever of `lua5.5`, `lua5.4` or `lua` it finds, so Homebrew's `lua` works.
`make e2e` is Linux-only because it talks to fcitx5 over DBus.

## Usage

1. Open QuickPhrase. The default hotkeys are `Super+`` and `Super+;`.
2. Type an S-expression such as `(+ 1 2)`.
3. As soon as the parentheses balance, the expression is evaluated and the result `3` is committed.

- Errors are shown as a hint in the candidate list, e.g. `Error: undefined function: foo`.
  Press Backspace to fix the expression or Esc to cancel.
- No candidates are shown while the expression is incomplete. This is deliberate: as soon as
  QuickPhrase has a candidate, Space selects it instead of typing a space.

## Configuration

`AUTO_COMMIT` at the top of `sexp_calc.lua`. Set it to `false` to show the result as a candidate
instead of committing it immediately; Space or `1` then commits it. Run `make restart` after editing.

## Supported expressions

| Category | Functions |
| --- | --- |
| Arithmetic | `+` `-` `*` `/` (variadic) |
| Integer arithmetic | `mod` (`modulo` `%`) `remainder` (`rem`) `quotient` (`div`) `gcd` `lcm` |
| Powers and roots | `expt` (`pow` `^` `**`) `sqrt` `square` |
| Rounding | `floor` `ceiling` (`ceil`) `round` `truncate` `abs` |
| Exponential, logarithm, trigonometry | `exp` `log` (1 or 2 arguments) `sin` `cos` `tan` `asin` `acos` `atan` (1 or 2 arguments) |
| Misc | `min` `max` `1+` `1-` |
| Comparison and logic | `=` `<` `>` `<=` `>=` `not`, and the special forms `if` `and` `or` `let` (`let*`) |
| Constants | `pi` `e` `#t` `#f` |

Number literals follow Lua's `tonumber` (`10`, `-3`, `1.5`, `1e3`, `0x10`).
Integer operands stay integers; the result becomes floating point only when a division is not
exact or the magnitude exceeds 2^62. `(/ 6 3)` gives `2`, `(/ 7 2)` gives `3.5`, and
`(* 123456789 987654321)` gives `121932631112635269`.

## How it works

The imeapi addon of fcitx5-lua loads `lua/imeapi/extensions/*.lua` at startup. `sexp_calc.lua`
loads the evaluator from `sexp_core.lua` next to it and registers a handler with `fcitx.addQuickPhraseHandler`. The handler receives the current
QuickPhrase input and returns a list of `{commit_text, display_text, action}` entries.

- Only input starting with `(` is handled. `Break` (-1) suppresses the built-in phrase
  dictionary and the spell checker so they do not add candidates.
- Once the parenthesis depth returns to zero the input is evaluated and returned with
  `AutoCommit` (6), which commits the result immediately.
- If evaluation fails, the reason is shown as a `DoNothing` (5) candidate, and `NoneSelection` (4)
  keeps the digit keys from acting as candidate selectors.

## Development

```sh
make test   # Lua unit tests (use LUA=lua5.4 make test to pick another interpreter)
make e2e    # end-to-end test over DBus; fcitx5 must be running
```

`test/e2e_fcitx.py` creates an input context through fcitx5's DBus frontend, sends key events
and watches for `CommitString`. It needs neither a GUI nor keyboard focus. The input context is
created with a private `display` so it gets its own focus group; otherwise the real application's
input context steals the focus.

The demo animation is rendered by `python3 docs/make_demo.py` (requires Pillow). It is drawn,
not screen-recorded; the results it shows are computed by `sexp_calc.lua` itself.

## License

MIT. See [LICENSE](LICENSE).
