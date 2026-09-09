# fcitx5-sexp-calc
#   make install  ... symlink sexp_calc.lua into ~/.local/share/fcitx5/lua/imeapi/extensions/
#   make restart  ... restart fcitx5 to load it (the IM falls back to the plain keyboard; Ctrl+Space switches back)
#   make test     ... Lua unit tests
#   make e2e      ... end-to-end test over DBus (fcitx5 must be running; needs python-gobject)

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
	@echo "Run 'make restart' to load it"

uninstall:
	rm -f $(EXT_DIR)/sexp_calc.lua

restart:
	systemctl --user restart $(UNIT)

status:
	@ls -l $(EXT_DIR)/sexp_calc.lua 2>/dev/null || echo "not installed"
	@systemctl --user is-active $(UNIT)
