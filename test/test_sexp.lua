-- Mock of the fcitx module provided by fcitx5-lua
package.preload["fcitx"] = function()
  return {
    QuickPhraseAction = { Break=-1, Commit=0, TypeToBuffer=1, DigitSelection=2, AlphaSelection=3, NoneSelection=4, DoNothing=5, AutoCommit=6 },
    addQuickPhraseHandler = function(name) return 1 end,
    log = function(msg) io.stderr:write("[log] " .. msg .. "\n") end,
  }
end
-- Target: ../sexp_calc.lua in this repository by default.
-- Override with the SEXP_CALC_LUA environment variable.
local script_dir = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
local target = os.getenv("SEXP_CALC_LUA") or (script_dir .. "/../sexp_calc.lua")
dofile(target)

local A = { [-1]="Break", [0]="Commit", [1]="TypeToBuffer", [2]="Digit", [3]="Alpha", [4]="NoneSel", [5]="DoNothing", [6]="AutoCommit" }
local function describe(r)
  if r == nil then return "nil" end
  local parts = {}
  for _, c in ipairs(r) do parts[#parts+1] = string.format("[%q|%q|%s]", c[1], c[2], A[c[3]] or tostring(c[3])) end
  return table.concat(parts, " ")
end

local fails = 0
local function expect_commit(input, want)
  local r = sexp_calc_quickphrase_handler(input)
  local got
  for _, c in ipairs(r or {}) do if c[3] == 6 or c[3] == 0 then got = c[1] end end
  local ok = got == want
  if not ok then fails = fails + 1 end
  print((ok and "OK  " or "FAIL") .. "  " .. input .. "  =>  " .. tostring(got) .. (ok and "" or ("   (want " .. tostring(want) .. ")  " .. describe(r))))
end
local function expect_no_candidate(input)
  local r = sexp_calc_quickphrase_handler(input)
  local ok = r ~= nil and #r == 1 and r[1][3] == -1
  if not ok then fails = fails + 1 end
  print((ok and "OK  " or "FAIL") .. "  " .. input .. "  =>  (no candidate, Break only) " .. (ok and "" or describe(r)))
end
local function expect_error(input, pattern)
  local r = sexp_calc_quickphrase_handler(input)
  local msg
  for _, c in ipairs(r or {}) do if c[3] == 5 then msg = c[2] end end
  local ok = msg ~= nil and (pattern == nil or msg:find(pattern, 1, true) ~= nil)
  -- no Commit/AutoCommit must be present
  for _, c in ipairs(r or {}) do if c[3] == 6 or c[3] == 0 then ok = false end end
  if not ok then fails = fails + 1 end
  print((ok and "OK  " or "FAIL") .. "  " .. input .. "  =>  " .. tostring(msg) .. (ok and "" or ("  " .. describe(r))))
end

print("-- basics")
expect_commit("(+ 1 2)", "3")
expect_commit("(+ 1 2 3 4)", "10")
expect_commit("(- 10 3)", "7")
expect_commit("(- 5)", "-5")
expect_commit("(* 2 (+ 3 4))", "14")
expect_commit("(/ 6 3)", "2")
expect_commit("(/ 7 2)", "3.5")
expect_commit("(/ 1 3)", "0.333333333333333")
expect_commit("(/ 2)", "0.5")
expect_commit("(+ 0.1 0.2)", "0.3")
expect_commit("(+ 1.5 -2)", "-0.5")
expect_commit("(* 1.1 1.1)", "1.21")
expect_commit("(+ 1e3 1)", "1001")
expect_commit("(+ 0x10 1)", "17")
print("-- math functions")
expect_commit("(expt 2 10)", "1024")
expect_commit("(expt 2 0.5)", "1.4142135623731")
expect_commit("(expt 2 -1)", "0.5")
expect_commit("(sqrt 16)", "4")
expect_commit("(sqrt 2)", "1.4142135623731")
expect_commit("(abs -3)", "3")
expect_commit("(mod 7 3)", "1")
expect_commit("(mod -7 3)", "2")
expect_commit("(remainder -7 3)", "-1")
expect_commit("(quotient 7 2)", "3")
expect_commit("(quotient -7 2)", "-3")
expect_commit("(min 3 1 2)", "1")
expect_commit("(max 3 1 2)", "3")
expect_commit("(floor 2.7)", "2")
expect_commit("(ceiling 2.1)", "3")
expect_commit("(round 2.5)", "3")
expect_commit("(round -2.5)", "-3")
expect_commit("(round 2.4)", "2")
expect_commit("(truncate -2.7)", "-2")
expect_commit("(gcd 12 18)", "6")
expect_commit("(lcm 4 6)", "12")
expect_commit("(1+ 5)", "6")
expect_commit("(square 12)", "144")
expect_commit("(log 100 10)", "2")
expect_commit("(exp 0)", "1")
expect_commit("(* 2 pi)", "6.28318530717959")
print("-- large numbers")
expect_commit("(* 123456789 987654321)", "121932631112635269")
expect_commit("(* 9999999999 9999999999 9999999999)", "9.999999997e+29")
expect_commit("(expt 2 100)", "1.26765060022823e+30")
print("-- comparison / logic / special forms")
expect_commit("(< 1 2 3)", "#t")
expect_commit("(= 1 1.0)", "#t")
expect_commit("(> 1 2)", "#f")
expect_commit("(if (> 3 2) 10 20)", "10")
expect_commit("(if #f 1)", "#f")
expect_commit("(and 1 2)", "2")
expect_commit("(or #f 5)", "5")
expect_commit("(not #f)", "#t")
expect_commit("(let ((x 3) (y (* x 2))) (+ x y))", "9")
print("-- incomplete input (must not produce candidates)")
expect_no_candidate("(")
expect_no_candidate("(+")
expect_no_candidate("(+ ")
expect_no_candidate("(+ 1")
expect_no_candidate("(+ 1 2")
expect_no_candidate("(+ (* 2 3)")
expect_no_candidate("(+ (* 2 3) 4")
print("-- errors (must not produce a commit candidate)")
expect_error("()", "empty ()")
expect_error("(foo 1)", "undefined function")
expect_error("(+ 1 x)", "undefined symbol")
expect_error("(/ 1 0)", "division by zero")
expect_error("(1 2)", "function name")
expect_error("(+ 1 2))", "unexpected )")
expect_error("(sqrt -1)", "negative")
expect_error("(+ 1 2) 3", "unexpected input")
print("-- not ours (returns nil)")
local r = sexp_calc_quickphrase_handler("hello"); print((r == nil and "OK  " or "FAIL") .. "  hello => " .. describe(r)); if r ~= nil then fails = fails + 1 end
r = sexp_calc_quickphrase_handler("1+2="); print((r == nil and "OK  " or "FAIL") .. "  1+2= => " .. describe(r)); if r ~= nil then fails = fails + 1 end
print("")
print(fails == 0 and "ALL PASSED" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
