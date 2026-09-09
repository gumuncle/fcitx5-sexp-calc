# fcitx5-sexp-calc
#   make install  … ~/.local/share/fcitx5/lua/imeapi/extensions/ にシンボリックリンクを張る
#   make restart  … fcitx5 を再起動して反映する (IM の状態が英語に戻るので Ctrl+Space で戻す)
#   make test     … Lua 単体テスト
#   make e2e      … DBus 経由の実機テスト (fcitx5 起動中、python-gobject が必要)

LUA      ?= lua5.5
EXT_DIR  := $(HOME)/.local/share/fcitx5/lua/imeapi/extensions
SRC      := $(abspath sexp_calc.lua)
UNIT     := app-org.fcitx.Fcitx5@autostart.service

.PHONY: all test e2e install uninstall restart status

all: test

test:
	$(LUA) test/test_sexp.lua

e2e:
	python3 test/e2e_fcitx.py '(+ 1 2)' --expect 3
	python3 test/e2e_fcitx.py '(* 2 (+ 3 4))' --expect 14 --activate-im
	python3 test/e2e_fcitx.py '(- 10 4)' --expect 6 --trigger semicolon --activate-im

install:
	mkdir -p $(EXT_DIR)
	ln -sfn $(SRC) $(EXT_DIR)/sexp_calc.lua
	@echo "linked: $(EXT_DIR)/sexp_calc.lua -> $(SRC)"
	@echo "反映するには: make restart"

uninstall:
	rm -f $(EXT_DIR)/sexp_calc.lua

restart:
	systemctl --user restart $(UNIT)

status:
	@ls -l $(EXT_DIR)/sexp_calc.lua 2>/dev/null || echo "not installed"
	@systemctl --user is-active $(UNIT)
