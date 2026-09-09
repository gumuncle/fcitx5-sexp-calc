# fcitx5-sexp-calc
#   make install  ... symlink sexp_calc.lua and sexp_core.lua into the fcitx5-lua extensions dir
#   make restart  ... restart fcitx5 to load them (Linux: systemd user unit; macOS: prints how)
#   make test     ... Lua unit tests (uses lua5.5, lua5.4 or lua, whichever is found)
#   make e2e      ... end-to-end test over DBus (Linux only; fcitx5 must be running; needs python-gobject)

UNAME    := $(shell uname -s)
LUA      ?= $(shell command -v lua5.5 || command -v lua5.4 || command -v lua)
EXT_DIR  := $(HOME)/.local/share/fcitx5/lua/imeapi/extensions
FILES    := sexp_calc.lua sexp_core.lua
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
	for f in $(FILES); do ln -sfn $(CURDIR)/$$f $(EXT_DIR)/$$f; done
	@ls -l $(addprefix $(EXT_DIR)/,$(FILES))
	@echo "Run 'make restart' to load it"

uninstall:
	rm -f $(addprefix $(EXT_DIR)/,$(FILES))

restart:
ifeq ($(UNAME),Darwin)
	@echo "fcitx5-macos: choose 'Restart' from the Fcitx5 menu bar icon"
else
	systemctl --user restart $(UNIT)
endif

status:
	@ls -l $(addprefix $(EXT_DIR)/,$(FILES)) 2>/dev/null || echo "not installed"
ifeq ($(UNAME),Linux)
	@systemctl --user is-active $(UNIT)
endif
