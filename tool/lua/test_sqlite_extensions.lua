-- Agreement ratchet for the SQLite extension registry.
--
-- third_party/sqlite3/extensions.c names every ext/misc extension linked
-- into libsqlite3.a, and the lsqlite3.Extension alias in
-- tool/net/definitions.lua lists the same names as a literal union, which
-- downstream type generators render as an enum. The two are written by
-- hand in two files, so this test holds them together: the alias must be
-- the registry, name for name, in the registry's order. Around that core
-- it checks the rest of what a registry row promises -- the init it names
-- is sqlite3_<name>_init, declared in extensions.h, defined in
-- third_party/sqlite3/<name>.c, and that unit is built into the archive
-- (SRCS and OBJS in third_party/sqlite3/BUILD.mk) -- and, the other way,
-- that no init declared in extensions.h is missing from the registry.
--
-- A unit extracted from shell.c's inlined copy must stay that copy: the
-- bytes between shell.c's Begin/End markers for ext/misc/<name>.c, with
-- the two lines the inliner comments out -- the unit's sqlite3ext.h
-- include, which becomes the repo path, and any typedef that would
-- collide with shell.c's own -- restored. That keeps every extension byte
-- already-vendored and makes an upstream bump that moves shell.c without
-- re-extracting fail here. FROM_SRC_TREE lists the units vendored from
-- the sqlite source tree instead, which have no shell.c section to match.

local function slurp(path)
  local f = assert(io.open(path, "r"), "cannot open " .. path)
  local s = f:read("*a")
  f:close()
  return s
end

local REGISTRY = "third_party/sqlite3/extensions.c"
local HEADER = "third_party/sqlite3/extensions.h"
local DEFS = "tool/net/definitions.lua"
local MK = "third_party/sqlite3/BUILD.mk"
local SHELL = "third_party/sqlite3/shell.c"
local ALIAS = "lsqlite3.Extension"

-- Units whose source is the sqlite source tree, not shell.c.
local FROM_SRC_TREE = {
  zipfile = true,
}

-- Units whose shell.c ext/misc/<stem>.c marker names a different stem than
-- the registry name (shell.c's own source file name, not what we call the
-- extension).
local MARKER_STEM = {
  ieee = "ieee754",
  sha = "sha1",
}

-- ---- the registry -------------------------------------------------------

local C = slurp(REGISTRY)
local body = assert(C:match("kSqliteExtensions%[%]%s*=%s*{(.-)\n};"),
  REGISTRY .. ": cannot find the kSqliteExtensions table")
local names, inits = {}, {}
for name, init in body:gmatch('{%s*"([^"]+)"%s*,%s*([%w_]+)%s*}') do
  names[#names + 1] = name
  inits[#inits + 1] = init
end
assert(#names > 0, REGISTRY .. ": the registry has no rows")
assert(body:match("{%s*0%s*,%s*0%s*}%s*,?%s*$"),
  REGISTRY .. ": the registry must end with a {0, 0} sentinel")

for i, name in ipairs(names) do
  assert(name:match("^[a-z][a-z0-9_]*$"),
    REGISTRY .. ": extension name is not a lowercase identifier: " .. name)
  assert(inits[i] == "sqlite3_" .. name .. "_init", string.format(
    "%s: row %q names init %s, expected sqlite3_%s_init",
    REGISTRY, name, inits[i], name))
  if i > 1 then
    assert(names[i - 1] < name, string.format(
      "%s: rows must be sorted by name (%q before %q)",
      REGISTRY, names[i - 1], name))
  end
end

-- ---- the alias ----------------------------------------------------------

local D = slurp(DEFS)
local rhs = assert(D:match("\n%-%-%-@alias " .. ALIAS:gsub("%.", "%%.")
  .. "%s+([^\n]*)"), DEFS .. ": no ---@alias " .. ALIAS)
rhs = rhs:match("^(%S+)")
local declared = {}
for lit in rhs:gmatch('"([^"]*)"') do
  declared[#declared + 1] = lit
end
local expected = {}
for _, name in ipairs(names) do
  expected[#expected + 1] = '"' .. name .. '"'
end
expected = table.concat(expected, "|")
assert(rhs == expected, string.format(
  "%s: ---@alias %s does not agree with the registry in %s\n  alias:    %s\n"
  .. "  registry: %s", DEFS, ALIAS, REGISTRY, rhs, expected))

-- ---- the declarations ---------------------------------------------------

local H = slurp(HEADER)
local declared_inits = {}
for init in H:gmatch("\nint%s+(sqlite3_[%w_]+_init)%s*%(") do
  declared_inits[init] = true
end
for i, name in ipairs(names) do
  assert(declared_inits[inits[i]], string.format(
    "%s: %s is in the registry but not declared in %s",
    HEADER, inits[i], HEADER))
  declared_inits[inits[i]] = nil
end
do
  local extra = {}
  for init in pairs(declared_inits) do extra[#extra + 1] = init end
  table.sort(extra)
  assert(#extra == 0, HEADER .. ": declared but missing from the registry: "
    .. table.concat(extra, ", "))
end

-- ---- the translation units ----------------------------------------------

local M = slurp(MK)
local srcs = assert(M:match("\nTHIRD_PARTY_SQLITE3_A_SRCS%s*=(.-)\n\n"),
  MK .. ": cannot find THIRD_PARTY_SQLITE3_A_SRCS")
local objs = assert(M:match("\nTHIRD_PARTY_SQLITE3_A_OBJS%s*=(.-)\n\n"),
  MK .. ": cannot find THIRD_PARTY_SQLITE3_A_OBJS")
assert(srcs:find("\tthird_party/sqlite3/extensions.c", 1, true),
  MK .. ": extensions.c is not in THIRD_PARTY_SQLITE3_A_SRCS")
assert(objs:find("\to/$(MODE)/third_party/sqlite3/extensions.o", 1, true),
  MK .. ": extensions.o is not in THIRD_PARTY_SQLITE3_A_OBJS")

local S = slurp(SHELL)
local INCLUDE_INLINED = '/* #include "sqlite3ext.h" */'
local INCLUDE_REPO = '#include "third_party/sqlite3/sqlite3ext.h"'

for i, name in ipairs(names) do
  local unit = "third_party/sqlite3/" .. name .. ".c"
  local src = slurp(unit)
  assert(src:find("\nint " .. inits[i] .. "(", 1, true), string.format(
    "%s: does not define %s", unit, inits[i]))
  assert(srcs:find("\t" .. unit, 1, true),
    MK .. ": " .. unit .. " is not in THIRD_PARTY_SQLITE3_A_SRCS")
  assert(objs:find("\to/$(MODE)/third_party/sqlite3/" .. name .. ".o", 1, true),
    MK .. ": " .. name .. ".o is not in THIRD_PARTY_SQLITE3_A_OBJS")
  if not FROM_SRC_TREE[name] then
    -- shell.c brackets each inlined unit with
    --   /***...*** Begin ext/misc/<name>.c ***...***/
    --   /***...*** End ext/misc/<name>.c ***...***/
    local stem = MARKER_STEM[name] or name
    local marker = "ext/misc/" .. stem .. ".c"
    local pat = marker:gsub("%p", "%%%0")
    local _, b = S:find("\n/%*+ Begin " .. pat .. " %*+/\n")
    assert(b, SHELL .. ": no Begin marker for " .. marker)
    local e = S:find("\n/%*+ End " .. pat .. " %*+/\n", b)
    assert(e, SHELL .. ": no End marker for " .. marker)
    local section = S:sub(b + 1, e)
    local n
    section, n = section:gsub(
      "\n" .. INCLUDE_INLINED:gsub("%p", "%%%0") .. "\n",
      "\n" .. INCLUDE_REPO .. "\n")
    assert(n == 1, string.format(
      "%s: expected exactly one inlined sqlite3ext.h include in %s, got %d",
      SHELL, marker, n))
    section = section:gsub("\n/%* (typedef [^\n/]-;) %*/\n", "\n%1\n")
    assert(src == section, string.format(
      "%s is not shell.c's ext/misc/%s.c section with the inliner's "
      .. "commented-out include and typedefs restored; re-extract it from %s",
      unit, name, SHELL))
  end
end

print(string.format("sqlite extensions: %d in the registry, alias %s agrees",
  #names, ALIAS))
print("PASS")
