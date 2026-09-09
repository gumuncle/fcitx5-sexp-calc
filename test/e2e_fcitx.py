#!/usr/bin/env python3
"""End-to-end test of QuickPhrase + sexp_calc through fcitx5's DBus frontend.

Creates an input context over DBus, sends the QuickPhrase trigger key and the
keystrokes of an expression, and watches the CommitString signal for the
committed text. Needs neither a GUI nor keyboard focus.

Usage:
  python3 test/e2e_fcitx.py '(+ 1 2)' --expect 3
  python3 test/e2e_fcitx.py '(+ 1 2)' --expect 3 --trigger semicolon --activate-im

  --trigger grave|semicolon : QuickPhrase trigger key (Super+grave / Super+semicolon)
  --activate-im             : press Ctrl+Space first to activate the IM engine (e.g. Mozc)
  --expect TEXT             : expected committed text; exit code 1 on mismatch

Requires python-gobject (gi) and a running fcitx5.
"""
import argparse
import sys
import time

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GLib", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

BUS = "org.fcitx.Fcitx5"
IM_PATH = "/org/freedesktop/portal/inputmethod"
IM_IFACE = "org.fcitx.Fcitx.InputMethod1"
IC_IFACE = "org.fcitx.Fcitx.InputContext1"

KEYSTATE_CTRL = 1 << 2
KEYSTATE_SUPER = 1 << 6
KEYSYM = {"grave": 0x60, "semicolon": 0x3B, "space": 0x20}
# ClientSideUI | Preedit | FormattedPreedit: receive the preedit as signals
CAPABILITY = 0x13


def connect():
    last = None
    for _ in range(60):
        try:
            conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            conn.call_sync(BUS, IM_PATH, IM_IFACE, "Version", None, GLib.VariantType("(u)"),
                           Gio.DBusCallFlags.NONE, 2000, None)
            return conn
        except Exception as e:  # e.g. fcitx5 is still restarting
            last = e
            time.sleep(0.25)
    sys.exit(f"cannot connect to fcitx5: {last}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("text", help="text to type into QuickPhrase, e.g. '(+ 1 2)'")
    ap.add_argument("--trigger", choices=["grave", "semicolon"], default="grave")
    ap.add_argument("--activate-im", action="store_true", help="press Ctrl+Space to activate the IM engine before typing")
    ap.add_argument("--expect", help="expected committed text")
    args = ap.parse_args()

    conn = connect()
    # Pass a display so the IC gets its own focus group; otherwise the real
    # application's IC steals the focus
    res = conn.call_sync(BUS, IM_PATH, IM_IFACE, "CreateInputContext",
                         GLib.Variant("(a(ss))", [[("program", "sexp-calc-e2e"), ("display", "sexp-calc-e2e:0")]]),
                         GLib.VariantType("(oay)"), Gio.DBusCallFlags.NONE, 5000, None)
    ic_path = res.unpack()[0]

    events, commits = [], []

    def on_signal(_conn, _sender, _path, _iface, signal, params):
        value = params.unpack()
        events.append((signal, value))
        if signal == "CommitString":
            commits.append(value[0])

    conn.signal_subscribe(None, IC_IFACE, None, ic_path, None, Gio.DBusSignalFlags.NONE, on_signal)

    def call(method, params=None, reply=None):
        return conn.call_sync(BUS, ic_path, IC_IFACE, method, params, reply, Gio.DBusCallFlags.NONE, 5000, None)

    def pump(seconds=0.12):
        ctx = GLib.MainContext.default()
        end = time.time() + seconds
        while time.time() < end:
            ctx.iteration(False)
            time.sleep(0.005)

    def key(keyval, state=0):
        accepted = call("ProcessKeyEvent", GLib.Variant("(uuubu)", [keyval, 0, state, False, 0]),
                        GLib.VariantType("(b)")).unpack()[0]
        call("ProcessKeyEvent", GLib.Variant("(uuubu)", [keyval, 0, state, True, 0]), GLib.VariantType("(b)"))
        pump()
        return accepted

    def current_im():
        ims = [e[1][1] for e in events if e[0] == "CurrentIM"]
        return ims[-1] if ims else None

    ok = True
    try:
        call("SetCapability", GLib.Variant("(t)", [CAPABILITY]))
        call("FocusIn")
        pump(0.3)
        print(f"IM: {current_im()}")
        if args.activate_im:
            key(KEYSYM["space"], KEYSTATE_CTRL)
            pump(0.4)
            print(f"IM after Ctrl+Space: {current_im()}")
        events.clear()

        accepted = key(KEYSYM[args.trigger], KEYSTATE_SUPER)
        print(f"trigger Super+{args.trigger}: accepted={accepted}")
        for ch in args.text:
            accepted = key(ord(ch))
            preedits = [e[1][0] for e in events if e[0] == "UpdateFormattedPreedit"]
            preedit = "".join(seg[0] for seg in preedits[-1]) if preedits else ""
            print(f"  key {ch!r}: accepted={accepted} preedit={preedit!r} commits={commits}")
            events.clear()
        pump(0.5)
        print(f"RESULT commits={commits}")
        if args.expect is not None and commits != [args.expect]:
            print(f"FAIL: expected {[args.expect]}")
            ok = False
    finally:
        # close QuickPhrase if it is still open, then destroy the IC
        try:
            key(0xFF1B)  # Escape
            call("FocusOut")
            call("DestroyIC")
        except Exception:
            pass
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
