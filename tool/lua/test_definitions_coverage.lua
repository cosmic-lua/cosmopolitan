-- Annotation-coverage ratchet for the unix.* C bindings.
--
-- Every function registered in kLuaUnix[] and every constant registered via
-- LuaSetIntField() in third_party/lua/lunix.c must have a matching declaration
-- in tool/net/definitions.lua, so downstream type generators (e.g. cosmic's
-- gentype) can emit the whole surface instead of hand-maintaining it.
--
-- ALLOW_* below are the symbols that are knowingly not yet annotated. This list
-- is a RATCHET: it may only shrink. Adding a new binding without its annotation
-- fails this test -- annotate the binding, do not append to the allowlist. When
-- you annotate an allowlisted symbol (or drop it from the C), remove it here or
-- the stale-entry check fails.
--
-- Limitation: constants registered dynamically via LoadMagnums() (the IP_/TCP_/
-- SO_/CLOCK_ families) are not covered -- only literal LuaSetIntField() names.

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

print("definitions coverage: " ..
  tostring(#sorted_keys(reg_fns)) .. " functions, " ..
  tostring(#sorted_keys(reg_consts)) .. " constants checked; " ..
  tostring(#sorted_keys(ALLOW_FNS)) .. " fn + " ..
  tostring(#sorted_keys(ALLOW_CONSTS)) .. " const allowlisted")
print("test_definitions_coverage: PASS")
