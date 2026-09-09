#!/usr/bin/env python3
"""fcitx5 の DBus フロントエンド経由で QuickPhrase + sexp_calc を実機テストする。

fcitx5 に DBus で入力コンテキストを作り、QuickPhrase のトリガーキーと式のキー入力を
送って、CommitString シグナルで確定文字列を観測する。GUI やフォーカスは不要。

使い方:
  python3 test/e2e_fcitx.py '(+ 1 2)' --expect 3
  python3 test/e2e_fcitx.py '(+ 1 2)' --expect 3 --trigger semicolon --activate-im

  --trigger grave|semicolon : QuickPhrase のトリガーキー (Super+grave / Super+semicolon)
  --activate-im             : Ctrl+Space で IM (Mozc) を有効にしてからテストする
  --expect TEXT             : 期待する確定文字列。一致しなければ終了コード 1

必要: python-gobject (gi)、fcitx5 が起動していること。
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
# ClientSideUI | Preedit | FormattedPreedit: プリエディットをシグナルで受け取る
CAPABILITY = 0x13


def connect():
    last = None
    for _ in range(60):
        try:
            conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            conn.call_sync(BUS, IM_PATH, IM_IFACE, "Version", None, GLib.VariantType("(u)"),
                           Gio.DBusCallFlags.NONE, 2000, None)
            return conn
        except Exception as e:  # fcitx5 再起動直後などは少し待つ
            last = e
            time.sleep(0.25)
    sys.exit(f"fcitx5 に接続できません: {last}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("text", help="QuickPhrase に打ち込む文字列 (例: '(+ 1 2)')")
    ap.add_argument("--trigger", choices=["grave", "semicolon"], default="grave")
    ap.add_argument("--activate-im", action="store_true", help="Ctrl+Space で IM を有効にしてから打つ")
    ap.add_argument("--expect", help="期待する確定文字列")
    args = ap.parse_args()

    conn = connect()
    # display を渡して専用のフォーカスグループにしないと、実アプリの IC にフォーカスを奪われる
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
        # QuickPhrase が開いたままなら閉じてから破棄する
        try:
            key(0xFF1B)  # Escape
            call("FocusOut")
            call("DestroyIC")
        except Exception:
            pass
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
