-- Annotation-coverage ratchet for the unix.* C bindings.
--
-- Every function registered in kLuaUnix[] and every constant registered in
-- third_party/lua/lunix.c must have a matching declaration in
-- tool/net/definitions.lua, so downstream type generators (e.g. cosmic's
-- gentype) can emit the whole surface instead of hand-maintaining it.
--
-- Constants are registered two ways, both covered here:
--   * literal LuaSetIntField(L, "NAME", ...) calls, and
--   * dynamic LoadMagnums(L, kTable, "PFX_") calls, which register PFX_ + each
--     string in the corresponding libc/intrin/<ktable>.S magnum table (the
--     IP_/TCP_/SO_/CLOCK_ families).
--
-- ALLOW_* below are the symbols that are knowingly not yet annotated. This list
-- is a RATCHET: it may only shrink. Adding a new binding without its annotation
-- fails this test -- annotate the binding, do not append to the allowlist. When
-- you annotate an allowlisted symbol (or drop it from the C), remove it here or
-- the stale-entry check fails.
--
-- This test also lints annotation SYNTAX (check 3): a LuaLS tag written
-- `--- @tag` (with a space after the dashes) is silently ignored, so the
-- coverage checks above can pass while the annotation does nothing.

local function slurp(path)
  local f = assert(io.open(path, "r"), "cannot open " .. path)
  local s = f:read("*a")
  f:close()
  return s
end

local C = slurp("third_party/lua/lunix.c")
local D = slurp("tool/net/definitions.lua")

-- Registered top-level functions: { "name", LuaUnixXxx } inside kLuaUnix[].
local body = assert(C:match("kLuaUnix%[%]%s*=%s*{(.-)\n};"),
  "could not locate the kLuaUnix[] table")
local reg_fns = {}
for name in body:gmatch('{"([%a_][%w_]*)"%s*,%s*LuaUnix') do
  reg_fns[name] = true
end

-- Registered constants: literal LuaSetIntField(L, "NAME", ...).
local reg_consts = {}
for name in C:gmatch('LuaSetIntField%(L,%s*"([%u][%w_]*)"') do
  reg_consts[name] = true
end

-- Registered constants: dynamic LoadMagnums(L, kTable, "PFX_"). Each call
-- registers PFX_ .. <string> for every entry in the magnum table, which lives
-- in libc/intrin/<lowercased table>.S as `.e SYMBOL,"STRING"` rows.
for tbl, pfx in C:gmatch('LoadMagnums%(L,%s*(k%w+),%s*"([%u_]*)"%)') do
  local S = slurp("libc/intrin/" .. tbl:lower() .. ".S")
  for suffix in S:gmatch('%.e%s+[%u][%w_]*%s*,%s*"([%w_]+)"') do
    reg_consts[pfx .. suffix] = true
  end
end

-- Annotated functions: function unix.name(
local ann_fns = {}
for name in D:gmatch("\nfunction unix%.([%a_][%w_]*)%s*%(") do
  ann_fns[name] = true
end

-- Annotated constants: NAME = ... (the `NAME = nil` stubs in the unix table).
local ann_consts = {}
for name in D:gmatch("\n%s*([%u][%w_]*)%s*=") do
  ann_consts[name] = true
end

local function set(list)
  local t = {}
  for _, v in ipairs(list) do t[v] = true end
  return t
end

-- ===== ratchet allowlist (may only shrink) =====
--
-- The whole unix.* surface is now annotated, so both allowlists are empty.
-- The ratchet has become a pure regression check: any new binding added to
-- lunix.c without a matching annotation in definitions.lua fails this test.

local ALLOW_FNS = set({})

local ALLOW_CONSTS = set({})

-- ===== checks =====

local function sorted_keys(t)
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = k end
  table.sort(ks)
  return ks
end

-- 1) New gaps: registered but neither annotated nor allowlisted.
local new_gaps = {}
for name in pairs(reg_fns) do
  if not ann_fns[name] and not ALLOW_FNS[name] then
    new_gaps[#new_gaps + 1] = "function unix." .. name
  end
end
for name in pairs(reg_consts) do
  if not ann_consts[name] and not ALLOW_CONSTS[name] then
    new_gaps[#new_gaps + 1] = "constant unix." .. name
  end
end
table.sort(new_gaps)
assert(#new_gaps == 0,
  "these unix.* bindings are registered in lunix.c but not annotated in\n" ..
  "definitions.lua (annotate them; do not add to the allowlist):\n  " ..
  table.concat(new_gaps, "\n  "))

-- 2) Stale allowlist entries: allowlisted but now annotated or gone from C.
local stale = {}
for _, name in ipairs(sorted_keys(ALLOW_FNS)) do
  if ann_fns[name] then
    stale[#stale + 1] = "function " .. name .. " is now annotated"
  elseif not reg_fns[name] then
    stale[#stale + 1] = "function " .. name .. " is no longer registered"
  end
end
for _, name in ipairs(sorted_keys(ALLOW_CONSTS)) do
  if ann_consts[name] then
    stale[#stale + 1] = "constant " .. name .. " is now annotated"
  elseif not reg_consts[name] then
    stale[#stale + 1] = "constant " .. name .. " is no longer registered"
  end
end
assert(#stale == 0,
  "the annotation-coverage allowlist has stale entries (remove them so the\n" ..
  "ratchet stays tight):\n  " .. table.concat(stale, "\n  "))

-- 3) Malformed annotation syntax: a LuaLS tag must be written `---@tag`, with
-- no space between the comment dashes and the `@`. A stray `--- @tag` is
-- treated as ordinary comment prose, so LuaLS -- and the downstream gentype
-- generator -- silently ignore it: a function's @return/@overload vanishes and
-- it renders as returning nothing (this is exactly how unix.clearenv lost its
-- `boolean, unix.Errno` return). Catch it here so it can't recur.
local malformed = {}
local lineno = 0
for line in (D .. "\n"):gmatch("([^\n]*)\n") do
  lineno = lineno + 1
  if line:match("^%-%-%-[ \t]+@%a") then
    malformed[#malformed + 1] = "line " .. lineno .. ": " .. line
  end
end
assert(#malformed == 0,
  "these annotation lines put a space after `---`, so LuaLS and gentype\n" ..
  "silently drop them (write `---@tag`, not `--- @tag`):\n  " ..
  table.concat(malformed, "\n  "))

print("definitions coverage: " ..
  tostring(#sorted_keys(reg_fns)) .. " functions, " ..
  tostring(#sorted_keys(reg_consts)) .. " constants checked; " ..
  tostring(#sorted_keys(ALLOW_FNS)) .. " fn + " ..
  tostring(#sorted_keys(ALLOW_CONSTS)) .. " const allowlisted")
print("test_definitions_coverage: PASS")
