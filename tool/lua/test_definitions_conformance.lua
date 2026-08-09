-- Type-truthfulness conformance probe for tool/net/definitions.lua.
--
-- test_definitions_coverage.lua ratchets NAMES (every registered binding
-- is annotated, bidirectionally) and annotation SYNTAX. Nothing verified
-- that the annotated TYPES match runtime behavior — the gap that produced
-- three wrong signatures in cosmic's handcrafted tl.d.tl (cosmic#664).
--
-- This test closes the loop for a curated, growable set of zero-risk
-- bindings (pure functions, no side effects): it parses each probed
-- function's ---@return annotations out of definitions.lua, calls the
-- function with sample inputs, and asserts the Lua type of every actual
-- return matches the declared type positionally. `integer` is checked
-- with math.type, literal-string unions and named aliases (---@alias)
-- are checked by membership, `T?`/`|nil` admit nil. Failure shapes are
-- probed too: a forced failure must produce the declared nil+error pair.
--
-- PROBES below is a RATCHET: it may only grow. If a probe fails, either
-- the C or the annotation is wrong — both are bugs; fix the source of
-- truth, do not delete the probe. If a declared type is not supported by
-- the checker here (fun(...), classes), extend the checker or pick a
-- different binding; do not weaken a check.

local function slurp(path)
  local f = assert(io.open(path, "r"), "cannot open " .. path)
  local s = f:read("*a")
  f:close()
  return s
end

local D = slurp("tool/net/definitions.lua")

-- Semantic types referenced by annotations without an ---@alias
-- declaration in this file. JsonValue is any JSON-representable value.
local BUILTIN = {
  JsonValue = "nil|boolean|number|string|table",
}

-- Parse ---@alias declarations into name -> rhs.
local ALIASES = {}
for name, rhs in pairs(BUILTIN) do
  ALIASES[name] = rhs
end
for name, rhs in D:gmatch("%-%-%-@alias%s+([%w%._]+)%s+([^\n]*)") do
  -- strip trailing description: rhs is the first whitespace-separated
  -- token (alias right-hand sides in this file never contain spaces).
  ALIASES[name] = rhs:match("^(%S+)")
end

-- Parse the ---@return types declared for a module-level cosmo function
-- (or dotted submodule function like path.basename). Returns a list of
-- type strings in positional order.
local function declared_returns(fname)
  local block_end = D:find("\nfunction " .. fname:gsub("%.", "%%.") .. "%(")
  assert(block_end, "no declaration found for " .. fname)
  -- walk back over the contiguous ----comment block above the function
  local block_start = block_end
  while true do
    local prev = D:sub(1, block_start - 1):match("()\n[^\n]*$")
    if not prev then break end
    local line = D:sub(prev + 1, block_start - 1)
    if not line:match("^%-%-%-") then break end
    block_start = prev
  end
  local block = D:sub(block_start, block_end)
  local returns = {}
  for rtype in block:gmatch("%-%-%-@return%s+(%S+)") do
    returns[#returns + 1] = rtype
  end
  assert(#returns > 0, fname .. " has no ---@return annotations")
  return returns
end

-- Check one runtime value against one declared LuaLS type string.
-- Returns true, or nil and a reason.
local function value_matches(v, t, depth)
  depth = (depth or 0) + 1
  assert(depth < 10, "alias cycle while resolving type: " .. t)
  -- optional suffix: T? admits nil
  local base = t:match("^(.*)%?$")
  if base then
    if v == nil then return true end
    return value_matches(v, base, depth)
  end
  -- top-level unions: split on | outside angle brackets (no probed type
  -- nests | inside <>, so a plain split is enough here)
  if t:find("|", 1, true) then
    local reasons = {}
    for part in t:gmatch("[^|]+") do
      local ok, why = value_matches(v, part, depth)
      if ok then return true end
      reasons[#reasons + 1] = why or part
    end
    return nil, "no union member matched: " .. t
  end
  if t == "nil" then
    if v == nil then return true end
    return nil, "expected nil, got " .. type(v)
  end
  if t == "any" then return true end
  if t == "string" then
    if type(v) == "string" then return true end
    return nil, "expected string, got " .. type(v)
  end
  if t == "boolean" then
    if type(v) == "boolean" then return true end
    return nil, "expected boolean, got " .. type(v)
  end
  if t == "integer" then
    if math.type(v) == "integer" then return true end
    return nil, "expected integer, got " .. tostring(math.type(v) or type(v))
  end
  if t == "number" then
    if type(v) == "number" then return true end
    return nil, "expected number, got " .. type(v)
  end
  if t == "table" or t:match("^table<") or t:match("^{") then
    if type(v) == "table" then return true end
    return nil, "expected table, got " .. type(v)
  end
  -- literal string type: "null"
  local lit = t:match('^"(.*)"$')
  if lit then
    if v == lit then return true end
    return nil, 'expected "' .. lit .. '", got ' .. tostring(v)
  end
  -- named alias
  if ALIASES[t] then
    return value_matches(v, ALIASES[t], depth)
  end
  error("unsupported type in conformance checker: '" .. t
    .. "' — extend value_matches or probe a different binding")
end

-- One probe: call fn with args, compare every declared return position
-- against the actual returns. Trailing absent returns are nil, which
-- must still satisfy the declared type (T?, |nil, or nil).
--
-- That allowance is a hole on its own, and it is the hole re's phantom
-- third slot fell through (#247): a slot the C never pushes reads as
-- nil, and nil satisfies the `string?` it was declared as, so the check
-- passes forever on a return value that does not exist. SLOT_SEEN
-- closes it by demanding evidence -- every declared slot must be
-- observed non-nil by SOME probe of that function, or the annotation is
-- describing something no path produces.
local function count_keys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local SLOT_SEEN = {}   -- fname -> { [slot] = true }
local SLOT_COUNT = {}  -- fname -> number of declared slots

local function probe(fname, fn, ...)
  local declared = declared_returns(fname)
  local actual = table.pack(fn(...))
  for i, t in ipairs(declared) do
    local ok, why = value_matches(actual[i], t, 0)
    assert(ok, string.format("%s return #%d: %s (declared '%s', got %s)",
      fname, i, why or "mismatch", t, tostring(actual[i])))
  end
  local seen = SLOT_SEEN[fname]
  if not seen then
    seen = {}
    SLOT_SEEN[fname] = seen
  end
  SLOT_COUNT[fname] = #declared
  for i = 1, #declared do
    if actual[i] ~= nil then
      seen[i] = true
    end
  end
  return table.unpack(actual, 1, actual.n)
end

local cosmo = require("cosmo")
local path = require("cosmo.path")
local unix = require("cosmo.unix")

-- === success shapes ======================================================

probe("cosmo.EncodeJson", cosmo.EncodeJson, { foo = "bar" })
probe("cosmo.DecodeJson", cosmo.DecodeJson, '{"x":1}')
probe("cosmo.EncodeLua", cosmo.EncodeLua, { 1, 2, 3 })
probe("cosmo.EncodeBase64", cosmo.EncodeBase64, "\x00\xff binary")
probe("cosmo.DecodeBase64", cosmo.DecodeBase64, "aGVsbG8=")
probe("cosmo.EncodeHex", cosmo.EncodeHex, "\x00\xff")
probe("cosmo.FormatIp", cosmo.FormatIp, 0x7f000001)
probe("cosmo.ParseIp", cosmo.ParseIp, "127.0.0.1")
probe("cosmo.Crc32", cosmo.Crc32, 0, "hello")
probe("cosmo.GetCryptoHash", cosmo.GetCryptoHash, "SHA256", "payload")
probe("cosmo.GetHostIsa", cosmo.GetHostIsa)
probe("cosmo.GetHostOs", cosmo.GetHostOs)
probe("cosmo.CategorizeIp", cosmo.CategorizeIp, 0x7f000001)
probe("path.basename", path.basename, "/a/b/c.tl")
probe("path.dirname", path.dirname, "/a/b/c.tl")
probe("path.join", path.join, "a", "b")
probe("unix.getpid", unix.getpid)

-- compress round-trip, both directions typed
local deflated = probe("cosmo.Deflate", cosmo.Deflate, ("ratchet"):rep(64))
local inflated = probe("cosmo.Inflate", cosmo.Inflate, deflated)
assert(inflated == ("ratchet"):rep(64), "Deflate/Inflate round-trip broke")

-- === failure shapes ======================================================
-- A forced failure must land in the declared nil+error slots, not throw
-- and not invent extra values.

local v, err = probe("cosmo.DecodeJson", cosmo.DecodeJson, "{truncated")
assert(v == nil and type(err) == "string",
  "DecodeJson failure must be nil, string")

local hv, herr = probe("cosmo.GetCryptoHash", cosmo.GetCryptoHash,
  "NOT-A-HASH", "payload")
assert(hv == nil and type(herr) == "string",
  "GetCryptoHash failure must be nil, string")

-- Every declared error slot needs a probe that fills it, or the
-- slot-observation ratchet at the bottom of this file cannot tell a
-- real one from a phantom.
local dv, derr = probe("cosmo.Deflate", cosmo.Deflate, "x", { level = 99 })
assert(dv == nil and type(derr) == "string",
  "Deflate with an out-of-range level must be nil, string")

local iv, ierr = probe("cosmo.Inflate", cosmo.Inflate, "not-deflate-data")
assert(iv == nil and type(ierr) == "string",
  "Inflate of non-deflate bytes must be nil, string")

local cyclic = {}
cyclic.self = cyclic
local jv, jerr = probe("cosmo.EncodeJson", cosmo.EncodeJson, cyclic)
assert(jv == nil and type(jerr) == "string",
  "EncodeJson of a cyclic table must be nil, string")

local lv, lerr = probe("cosmo.EncodeLua", cosmo.EncodeLua, { 1 },
  { nan = "bogus" })
assert(lv == nil and type(lerr) == "string",
  "EncodeLua with an invalid nan option must be nil, string")

local pv, perr = probe("cosmo.ParseIp", cosmo.ParseIp, "not.an.ip.addr")
-- ParseIp signals failure as -1 or nil,error depending on the C path;
-- the annotation says integer|nil + string? — whichever way it returns,
-- probe() above already enforced the declared types. Pin the honest
-- variant so a silent contract change fails loudly here:
assert(pv == -1 or (pv == nil and type(perr) == "string"),
  "ParseIp failure shape changed: " .. tostring(pv) .. ", " .. tostring(perr))

-- === constants ===========================================================
-- Every ALL-CAPS entry in a module table reaches Lua through LuaSetIntField
-- / LoadMagnums / SC(), and definitions.lua declares them `integer`
-- (test_definitions_coverage.lua's Q5 ratchets that). Downstream renders
-- them as Teal `integer` on the strength of that declaration, so prove it
-- is truthful: a constant arriving as a float would make the generated type
-- a lie, and the bit-op call sites that consume these are exactly where it
-- would surface (whilp/cosmopolitan#142).

local CONST_MODULES = {
  { name = "unix", t = unix },
  { name = "re", t = require("cosmo.re") },
  { name = "lsqlite3", t = require("cosmo.lsqlite3") },
}

-- Annotated but registered under a `#ifdef` the build does not satisfy, so
-- absent at runtime. A RATCHET: an entry may only be removed. Anything else
-- that goes missing is a binding that silently vanished, and fails below.
local CONST_ABSENT = {
  ["unix.WCONTINUED"] = "#ifdef WCONTINUED in third_party/lua/lunix.c",
}

local nconst, nabsent = 0, 0
for _, m in ipairs(CONST_MODULES) do
  local body = assert(D:match("\n" .. m.name .. " = {(.-)\n}"),
    "could not locate the `" .. m.name .. " = {` module table")
  for name in body:gmatch("\n%s*([%u][%w_]*)%s*=") do
    local disp = m.name .. "." .. name
    local v = m.t[name]
    if v == nil then
      assert(CONST_ABSENT[disp], disp ..
        " is annotated but missing at runtime (the C no longer registers " ..
        "it, or it is newly conditional -- fix the binding or, if the " ..
        "condition is deliberate, note it in CONST_ABSENT)")
      nabsent = nabsent + 1
    else
      assert(not CONST_ABSENT[disp], "stale CONST_ABSENT entry (present " ..
        "at runtime now, remove it): " .. disp)
      assert(math.type(v) == "integer", string.format(
        "%s declared integer, got %s (%s)", disp,
        tostring(math.type(v) or type(v)), tostring(v)))
      nconst = nconst + 1
    end
  end
end
print("constants: " .. nconst .. " checked integer across " ..
  #CONST_MODULES .. " modules; " .. nabsent .. " conditionally absent")

-- ===== every declared slot must be observed =====
--
-- A declared return slot that no probe ever fills is either a path this
-- file does not exercise (add the probe) or a value the C never pushes
-- (fix the annotation). Both are actionable; neither is "fine".
--
-- SLOT_UNPROBED is a RATCHET: it may only shrink. Its entries are slots
-- whose path is genuinely out of reach here -- not slots nobody got
-- around to probing. A stale entry fails, same as an unobserved slot.
local SLOT_UNPROBED = {}

local nslots, nslotallow = 0, 0
local unobserved = {}
do
  local names = {}
  for fname in pairs(SLOT_SEEN) do
    names[#names + 1] = fname
  end
  table.sort(names)
  for _, fname in ipairs(names) do
    for i = 1, SLOT_COUNT[fname] do
      local disp = fname .. " #" .. i
      if SLOT_SEEN[fname][i] then
        nslots = nslots + 1
        assert(not SLOT_UNPROBED[disp],
          "stale SLOT_UNPROBED entry (this slot IS observed now, remove " ..
          "it): " .. disp)
      elseif SLOT_UNPROBED[disp] then
        nslotallow = nslotallow + 1
      else
        unobserved[#unobserved + 1] = disp
      end
    end
  end
  assert(#unobserved == 0, "declared return slots no probe ever produced. " ..
    "Either the annotation describes a value the C never pushes (fix the " ..
    "annotation -- this is how re's phantom third return survived) or the " ..
    "path that fills it is unprobed (add the probe):\n  " ..
    table.concat(unobserved, "\n  "))
end
print("return slots: " .. nslots .. " observed non-nil across " ..
  count_keys(SLOT_SEEN) .. " probed functions; " .. nslotallow ..
  " unobserved (shrink-only)")

print("PASS")
