-- sexp_calc.lua : S-expression calculator for fcitx5 QuickPhrase (fcitx5-lua extension)
-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 Yusuke Furukawa
--
-- This file is the fcitx5 adapter. The evaluator itself lives in sexp_core.lua,
-- which must sit in the same directory.
--
-- Usage:
--   1. Open QuickPhrase (default hotkeys: Super+` or Super+;)
--   2. Type an S-expression such as "(+ 1 2)"
--   3. As soon as the parentheses balance, the expression is evaluated and the
--      result "3" is committed
--
-- Location (Linux and fcitx5-macos):
--   ~/.local/share/fcitx5/lua/imeapi/extensions/sexp_calc.lua
--   ~/.local/share/fcitx5/lua/imeapi/extensions/sexp_core.lua
--   The imeapi addon of fcitx5-lua loads extensions/*.lua at startup, so fcitx5
--   has to be restarted after editing:
--     Linux (XDG autostart on a systemd user session):
--       systemctl --user restart app-org.fcitx.Fcitx5@autostart.service
--     macOS: choose "Restart" from the Fcitx5 menu bar icon
--
-- Configuration:
--   AUTO_COMMIT = true  ... commit the result as soon as the parentheses balance (default)
--   AUTO_COMMIT = false ... show the result as a candidate; Space or 1 commits it

local fcitx = require("fcitx")

local AUTO_COMMIT = true

local Action = fcitx.QuickPhraseAction

-- Load sexp_core.lua from the directory this file was loaded from. fcitx5-lua
-- loads extensions with loadfile(), so the chunk source is "@/path/to/sexp_calc.lua".
local function script_dir()
  local source = debug.getinfo(1, "S").source or ""
  return source:match("^@(.*)[/\\][^/\\]*$") or "."
end
local core = dofile(script_dir() .. "/sexp_core.lua")

local function error_hint(result, message)
  -- DoNothing: a display-only candidate that does nothing when selected.
  -- NoneSelection: keep the digit keys from acting as candidate selectors.
  result[#result + 1] = { "!", "Error: " .. message, Action.DoNothing }
  result[#result + 1] = { "", "", Action.NoneSelection }
end

-- Must be a global function: fcitx5-lua calls it by name
function sexp_calc_quickphrase_handler(input)
  if input:sub(1, 1) ~= "(" then
    return nil -- not an S-expression: leave it to the other providers
  end
  -- Break: suppress candidates from the built-in phrase dictionary and the spell checker
  local result = { { "", "", Action.Break } }
  local depth = core.paren_depth(input)
  if depth > 0 then
    -- Incomplete input. Show nothing: with a candidate present, Space would
    -- select it instead of typing a space.
    return result
  end
  if depth < 0 then
    error_hint(result, "unexpected )")
    return result
  end
  local ok, value = pcall(core.evaluate_string, input)
  if ok then
    local text = core.format_value(value)
    result[#result + 1] = { text, text, AUTO_COMMIT and Action.AutoCommit or Action.Commit }
  else
    local message = tostring(value):gsub("^.-:%d+: ", "")
    error_hint(result, message)
  end
  return result
end

-- Keep the handler id so it could be removed with fcitx.removeQuickPhraseHandler
sexp_calc_quickphrase_handler_id = fcitx.addQuickPhraseHandler("sexp_calc_quickphrase_handler")
fcitx.log("sexp_calc: loaded (AUTO_COMMIT=" .. tostring(AUTO_COMMIT) .. ")")

-- Exported for the tests and docs/make_demo.py
sexp_calc = core
