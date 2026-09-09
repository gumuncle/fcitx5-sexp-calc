-- sexp_calc.lua : S-expression calculator for fcitx5 QuickPhrase (fcitx5-lua extension)
-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 Yusuke Furukawa
--
-- Usage:
--   1. Open QuickPhrase (default hotkeys: Super+` or Super+;)
--   2. Type an S-expression such as "(+ 1 2)"
--   3. As soon as the parentheses balance, the expression is evaluated and the
--      result "3" is committed
--
-- Location: ~/.local/share/fcitx5/lua/imeapi/extensions/sexp_calc.lua
--   The imeapi addon of fcitx5-lua loads extensions/*.lua at startup.
--   Restart fcitx5 after editing. When fcitx5 is started through XDG autostart on
--   a systemd user session, that is
--   `systemctl --user restart app-org.fcitx.Fcitx5@autostart.service`.
--   `fcitx5-remote -r` did not pick up newly installed addons in testing.
--
-- Configuration:
--   AUTO_COMMIT = true  ... commit the result as soon as the parentheses balance (default)
--   AUTO_COMMIT = false ... show the result as a candidate; Space or 1 commits it
--
-- Supported:
--   + - * / (variadic), mod / remainder / quotient, expt / sqrt / abs,
--   min / max, floor / ceiling / round / truncate, exp / log / sin / cos / tan / atan,
--   gcd / lcm, 1+ / 1-, comparisons = < > <= >=, not, constants pi / e,
--   special forms if / and / or / let
--   Number literals follow Lua's tonumber (10, -3, 1.5, 1e3, 0x10, ...)

local fcitx = require("fcitx")

local AUTO_COMMIT = true

local Action = fcitx.QuickPhraseAction

---------------------------------------------------------------------------
-- Lexer / parser
---------------------------------------------------------------------------
local function tokenize(src)
  local tokens = {}
  local i, n = 1, #src
  while i <= n do
    local c = src:sub(i, i)
    if c:match("%s") then
      i = i + 1
    elseif c == "(" or c == ")" then
      tokens[#tokens + 1] = c
      i = i + 1
    else
      local j = i
      while j <= n and not src:sub(j, j):match("[%s%(%)]") do
        j = j + 1
      end
      tokens[#tokens + 1] = src:sub(i, j - 1)
      i = j
    end
  end
  return tokens
end

-- Returns a number, a symbol (string) or a list (table)
local function parse(tokens)
  local pos = 1
  local function read()
    local t = tokens[pos]
    if t == nil then error("unbalanced parentheses", 0) end
    pos = pos + 1
    if t == "(" then
      local list = {}
      while tokens[pos] ~= ")" do
        if tokens[pos] == nil then error("unbalanced parentheses", 0) end
        list[#list + 1] = read()
      end
      pos = pos + 1
      return list
    elseif t == ")" then
      error("unexpected )", 0)
    else
      local num = tonumber(t)
      if num ~= nil then return num end
      return t
    end
  end
  local ast = read()
  if pos <= #tokens then error("unexpected input after the expression", 0) end
  return ast
end

---------------------------------------------------------------------------
-- Number helpers
---------------------------------------------------------------------------
local INT_LIMIT = 2.0 ^ 62

local function is_int(x) return math.type(x) == "integer" end

local function num(x, fname)
  if type(x) ~= "number" then
    error(fname .. ": expected a number", 0)
  end
  return x
end

-- Integer arithmetic falls back to floating point only when it would overflow
local function arith(a, b, op)
  if is_int(a) and is_int(b) then
    local approx = op(a + 0.0, b + 0.0)
    if math.abs(approx) < INT_LIMIT then return op(a, b) end
    return approx
  end
  return op(a, b)
end

local add = function(x, y) return x + y end
local sub = function(x, y) return x - y end
local mul = function(x, y) return x * y end

local function divide(a, b)
  if b == 0 then error("division by zero", 0) end
  if is_int(a) and is_int(b) and a % b == 0 then return a // b end
  return a / b
end

local function truncate(x)
  if is_int(x) then return x end
  local r = (x >= 0) and math.floor(x) or math.ceil(x)
  return math.tointeger(r) or r
end

local function round_half_up(x)
  if is_int(x) then return x end
  local r
  if x >= 0 then r = math.floor(x + 0.5) else r = -math.floor(-x + 0.5) end
  return math.tointeger(r) or r
end

local function to_int_if_exact(x)
  if is_int(x) then return x end
  return math.tointeger(x) or x
end

---------------------------------------------------------------------------
-- Built-in functions
---------------------------------------------------------------------------
local F = {}

local function fn1(name, f)
  return function(args)
    if #args ~= 1 then error(name .. ": expected exactly one argument", 0) end
    return f(num(args[1], name))
  end
end

local function fn2(name, f)
  return function(args)
    if #args ~= 2 then error(name .. ": expected exactly two arguments", 0) end
    return f(num(args[1], name), num(args[2], name))
  end
end

F["+"] = function(args)
  local acc = 0
  for _, v in ipairs(args) do acc = arith(acc, num(v, "+"), add) end
  return acc
end

F["*"] = function(args)
  local acc = 1
  for _, v in ipairs(args) do acc = arith(acc, num(v, "*"), mul) end
  return acc
end

F["-"] = function(args)
  if #args == 0 then error("-: expected at least one argument", 0) end
  if #args == 1 then return arith(0, num(args[1], "-"), sub) end
  local acc = num(args[1], "-")
  for i = 2, #args do acc = arith(acc, num(args[i], "-"), sub) end
  return acc
end

F["/"] = function(args)
  if #args == 0 then error("/: expected at least one argument", 0) end
  if #args == 1 then return divide(1, num(args[1], "/")) end
  local acc = num(args[1], "/")
  for i = 2, #args do acc = divide(acc, num(args[i], "/")) end
  return acc
end

F["mod"] = fn2("mod", function(a, b)
  if b == 0 then error("mod: division by zero", 0) end
  return a % b
end)
F["modulo"] = F["mod"]
F["%"] = F["mod"]

F["remainder"] = fn2("remainder", function(a, b)
  if b == 0 then error("remainder: division by zero", 0) end
  return math.fmod(a, b)
end)
F["rem"] = F["remainder"]

F["quotient"] = fn2("quotient", function(a, b)
  if b == 0 then error("quotient: division by zero", 0) end
  return truncate(a / b)
end)
F["div"] = F["quotient"]

F["expt"] = fn2("expt", function(a, b)
  local r = a ^ b
  if is_int(a) and is_int(b) and b >= 0 and math.abs(r) < 2.0 ^ 53 then
    return math.tointeger(r) or r
  end
  return r
end)
F["pow"] = F["expt"]
F["^"] = F["expt"]
F["**"] = F["expt"]

F["sqrt"] = fn1("sqrt", function(x)
  if x < 0 then error("sqrt: negative argument", 0) end
  return to_int_if_exact(math.sqrt(x))
end)
F["abs"] = fn1("abs", math.abs)
F["exp"] = fn1("exp", math.exp)
F["log"] = function(args)
  if #args == 1 then
    local x = num(args[1], "log")
    if x <= 0 then error("log: expected a positive number", 0) end
    return math.log(x)
  elseif #args == 2 then
    local x, b = num(args[1], "log"), num(args[2], "log")
    if x <= 0 or b <= 0 then error("log: expected a positive number", 0) end
    return math.log(x, b)
  end
  error("log: expected one or two arguments", 0)
end
F["sin"] = fn1("sin", math.sin)
F["cos"] = fn1("cos", math.cos)
F["tan"] = fn1("tan", math.tan)
F["asin"] = fn1("asin", math.asin)
F["acos"] = fn1("acos", math.acos)
F["atan"] = function(args)
  if #args == 1 then return math.atan(num(args[1], "atan")) end
  if #args == 2 then return math.atan(num(args[1], "atan"), num(args[2], "atan")) end
  error("atan: expected one or two arguments", 0)
end

F["floor"] = fn1("floor", function(x) return to_int_if_exact(math.floor(x)) end)
F["ceiling"] = fn1("ceiling", function(x) return to_int_if_exact(math.ceil(x)) end)
F["ceil"] = F["ceiling"]
F["round"] = fn1("round", round_half_up)
F["truncate"] = fn1("truncate", truncate)
F["square"] = fn1("square", function(x) return arith(x, x, mul) end)
F["1+"] = fn1("1+", function(x) return arith(x, 1, add) end)
F["1-"] = fn1("1-", function(x) return arith(x, 1, sub) end)

local function minmax(name, pick)
  return function(args)
    if #args == 0 then error(name .. ": expected at least one argument", 0) end
    local acc = num(args[1], name)
    for i = 2, #args do
      local v = num(args[i], name)
      if pick(v, acc) then acc = v end
    end
    return acc
  end
end
F["min"] = minmax("min", function(v, acc) return v < acc end)
F["max"] = minmax("max", function(v, acc) return v > acc end)

local function gcd2(a, b)
  a, b = math.abs(a), math.abs(b)
  while b ~= 0 do a, b = b, a % b end
  return a
end
local function int_args(name, args)
  if #args == 0 then error(name .. ": expected at least one argument", 0) end
  local out = {}
  for i, v in ipairs(args) do
    local n = to_int_if_exact(num(v, name))
    if not is_int(n) then error(name .. ": expected an integer", 0) end
    out[i] = n
  end
  return out
end
F["gcd"] = function(args)
  local ns = int_args("gcd", args)
  local acc = ns[1]
  for i = 2, #ns do acc = gcd2(acc, ns[i]) end
  return math.abs(acc)
end
F["lcm"] = function(args)
  local ns = int_args("lcm", args)
  local acc = math.abs(ns[1])
  for i = 2, #ns do
    local n = math.abs(ns[i])
    if acc == 0 or n == 0 then return 0 end
    acc = arith(acc // gcd2(acc, n), n, mul)
  end
  return acc
end

local function compare(name, ok)
  return function(args)
    if #args < 2 then error(name .. ": expected at least two arguments", 0) end
    for i = 1, #args - 1 do
      if not ok(num(args[i], name), num(args[i + 1], name)) then return false end
    end
    return true
  end
end
F["="] = compare("=", function(a, b) return a == b end)
F["<"] = compare("<", function(a, b) return a < b end)
F[">"] = compare(">", function(a, b) return a > b end)
F["<="] = compare("<=", function(a, b) return a <= b end)
F[">="] = compare(">=", function(a, b) return a >= b end)
F["not"] = function(args)
  if #args ~= 1 then error("not: expected exactly one argument", 0) end
  return args[1] == false
end

local CONST = {
  ["pi"] = math.pi,
  ["e"] = math.exp(1),
  ["#t"] = true,
  ["#f"] = false,
  ["true"] = true,
  ["false"] = false,
}

---------------------------------------------------------------------------
-- Evaluation
---------------------------------------------------------------------------
local eval

local SPECIAL = {}

SPECIAL["if"] = function(ast, env)
  if #ast < 3 or #ast > 4 then error("if: expected (if test then [else])", 0) end
  if eval(ast[2], env) ~= false then return eval(ast[3], env) end
  if ast[4] ~= nil then return eval(ast[4], env) end
  return false
end

SPECIAL["and"] = function(ast, env)
  local v = true
  for i = 2, #ast do
    v = eval(ast[i], env)
    if v == false then return false end
  end
  return v
end

SPECIAL["or"] = function(ast, env)
  for i = 2, #ast do
    local v = eval(ast[i], env)
    if v ~= false then return v end
  end
  return false
end

-- (let ((x 1) (y 2)) body...) bindings are evaluated in order (like let*)
SPECIAL["let"] = function(ast, env)
  if #ast < 3 or type(ast[2]) ~= "table" then
    error("let: expected (let ((name value) ...) body)", 0)
  end
  local scope = setmetatable({}, { __index = env })
  for _, binding in ipairs(ast[2]) do
    if type(binding) ~= "table" or #binding ~= 2 or type(binding[1]) ~= "string" then
      error("let: each binding must be (name value)", 0)
    end
    scope[binding[1]] = eval(binding[2], scope)
  end
  local v = false
  for i = 3, #ast do v = eval(ast[i], scope) end
  return v
end
SPECIAL["let*"] = SPECIAL["let"]

eval = function(ast, env)
  local t = type(ast)
  if t == "number" or t == "boolean" then return ast end
  if t == "string" then
    local v = env[ast]
    if v == nil then v = CONST[ast] end
    if v == nil then error("undefined symbol: " .. ast, 0) end
    return v
  end
  if #ast == 0 then error("cannot evaluate empty ()", 0) end
  local head = ast[1]
  if type(head) ~= "string" then error("expected a function name", 0) end
  local special = SPECIAL[head]
  if special then return special(ast, env) end
  local f = F[head]
  if f == nil then error("undefined function: " .. head, 0) end
  local args = {}
  for i = 2, #ast do args[i - 1] = eval(ast[i], env) end
  return f(args)
end

---------------------------------------------------------------------------
-- Formatting the result
---------------------------------------------------------------------------
local function format_value(v)
  if type(v) == "boolean" then return v and "#t" or "#f" end
  if type(v) ~= "number" then return tostring(v) end
  if is_int(v) then return tostring(v) end
  if v ~= v then return "NaN" end
  if v == math.huge then return "+inf" end
  if v == -math.huge then return "-inf" end
  local i = math.tointeger(v)
  if i ~= nil then return tostring(i) end
  return string.format("%.15g", v)
end

local function evaluate_string(src)
  return eval(parse(tokenize(src)), {})
end

---------------------------------------------------------------------------
-- QuickPhrase handler
---------------------------------------------------------------------------
local function paren_depth(s)
  local depth = 0
  for c in s:gmatch("[()]") do
    if c == "(" then
      depth = depth + 1
    else
      depth = depth - 1
      if depth < 0 then return -1 end
    end
  end
  return depth
end

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
  local depth = paren_depth(input)
  if depth > 0 then
    -- Incomplete input. Show nothing: with a candidate present, Space would
    -- select it instead of typing a space.
    return result
  end
  if depth < 0 then
    error_hint(result, "unexpected )")
    return result
  end
  local ok, value = pcall(evaluate_string, input)
  if ok then
    local text = format_value(value)
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

-- Exported for the tests
sexp_calc = {
  tokenize = tokenize,
  parse = parse,
  evaluate_string = evaluate_string,
  format_value = format_value,
  paren_depth = paren_depth,
}
