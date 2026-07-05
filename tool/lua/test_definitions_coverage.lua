-- Annotation-coverage ratchet for the Lua surface exposed by the fork's lua
-- binary via require("cosmo") and its submodules.
--
-- Every function, method, and constant registered by the C bindings must have
-- a matching declaration in tool/net/definitions.lua, so downstream type
-- generators (e.g. cosmic's gentype) can emit the whole surface instead of
-- hand-maintaining it. Coverage is enforced in BOTH directions: a registered
-- binding without an annotation fails, and an annotation for a binding that
-- is no longer registered is stale and fails too.
--
-- Covered modules (see MODULES below):
--   * cosmo      tool/lua/lcosmo.c            kCosmoFuncs[]
--   * unix       third_party/lua/lunix.c      kLuaUnix[] + constants + methods
--   * path       tool/net/lpath.c             kLuaPath[]
--   * re         tool/net/lre.c               kLuaRe[] + constants + methods
--   * argon2     tool/net/largon2.c           largon2[]
--   * lsqlite3   tool/net/lsqlite3.c          sqlitelib[] + constants + methods
--   * getopt     tool/net/lgetopt.c           kLuaGetopt[]
--   * zip        tool/net/lzip.c              kLuaZip[] + Reader/Writer/Appender
--   * repl       third_party/lua/lreplmod.c   kReplFuncs[]
--
-- unix constants are registered two ways, both covered here:
--   * literal LuaSetIntField(L, "NAME", ...) calls, and
--   * dynamic LoadMagnums(L, kTable, "PFX_") calls, which register PFX_ + each
--     string in the corresponding libc/intrin/<ktable>.S magnum table (the
--     IP_/TCP_/SO_/CLOCK_ families).
--
-- ALLOW_* below are the symbols that are knowingly not yet annotated. These
-- lists are a RATCHET: they may only shrink. Adding a new binding without its
-- annotation fails this test -- annotate the binding, do not append to the
-- allowlist. When you annotate an allowlisted symbol (or drop it from the C),
-- remove it here or the stale-entry check fails.
--
-- This test also lints annotation SYNTAX:
--   * a LuaLS tag written `--- @tag` (with a space after the dashes) is
--     silently ignored, so the coverage checks above can pass while the
--     annotation does nothing;
--   * class methods must be declared with a module-qualified receiver
--     (`function zip.Appender:add(...)`); a bare `function Appender:add(...)`
--     is invisible to gentype;
--   * every dotted `---@class` name must belong to a known module, so typos
--     like `---@class zpi.Reader` can't silently detach a class.

local function slurp(path)
  local f = assert(io.open(path, "r"), "cannot open " .. path)
  local s = f:read("*a")
  f:close()
  return s
end

local D = slurp("tool/net/definitions.lua")

local function set(list)
  local t = {}
  for _, v in ipairs(list) do t[v] = true end
  return t
end

local function sorted_keys(t)
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = k end
  table.sort(ks)
  return ks
end

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- Extract the entry names of a `static const luaL_Reg <name>[] = { ... };`
-- registration table from C source. Metamethods (__gc, __tostring, __close,
-- __index, __call, __repr, __newindex, ...) are skipped: they aren't part of
-- the scriptable surface.
local function reg_table(C, tbl)
  local body = assert(
    C:match("luaL_Reg%s+" .. tbl .. "%[%]%s*=%s*{(.-)};"),
    "could not locate the " .. tbl .. "[] registration table")
  local names = {}
  for name in body:gmatch('{%s*"([%a_][%w_]*)"%s*,') do
    if not name:match("^__") then
      names[name] = true
    end
  end
  assert(next(names), "registration table " .. tbl .. " parsed empty")
  return names
end

-- Merge the entries of several registration tables.
local function reg_tables(C, tbls)
  local names = {}
  for _, tbl in ipairs(tbls) do
    for name in pairs(reg_table(C, tbl)) do
      names[name] = true
    end
  end
  return names
end

-- Annotated module functions: `function <mod>.<name>(`
local function ann_fns(mod)
  local names = {}
  for name in D:gmatch("\nfunction " .. mod .. "%.([%a_][%w_]*)%s*%(") do
    names[name] = true
  end
  return names
end

-- Annotated class methods: `function <mod>.<Class>:<name>(`, metamethods
-- excluded (an annotated __tostring is fine, it's just not ratcheted).
local function ann_methods(mod, class)
  local names = {}
  for name in D:gmatch("\nfunction " .. mod .. "%." .. class ..
                       ":([%a_][%w_]*)%s*%(") do
    if not name:match("^__") then
      names[name] = true
    end
  end
  return names
end

-- Annotated constants: `NAME = ...` entries inside the `<mod> = {` table.
local function ann_consts(mod)
  local body = assert(
    D:match("\n" .. mod .. " = {(.-)\n}"),
    "could not locate the `" .. mod .. " = {` module table")
  local names = {}
  for name in body:gmatch("\n%s*([%u][%w_]*)%s*=") do
    names[name] = true
  end
  return names
end

-- ===== per-module registered surfaces =====

local C_unix = slurp("third_party/lua/lunix.c")
local C_path = slurp("tool/net/lpath.c")
local C_re = slurp("tool/net/lre.c")
local C_argon2 = slurp("tool/net/largon2.c")
local C_sqlite = slurp("tool/net/lsqlite3.c")
local C_getopt = slurp("tool/net/lgetopt.c")
local C_zip = slurp("tool/net/lzip.c")
local C_repl = slurp("third_party/lua/lreplmod.c")
local C_cosmo = slurp("tool/lua/lcosmo.c")

-- unix constants: literal LuaSetIntField(L, "NAME", ...) calls.
local unix_consts = {}
for name in C_unix:gmatch('LuaSetIntField%(L,%s*"([%u][%w_]*)"') do
  unix_consts[name] = true
end
-- unix constants: dynamic LoadMagnums(L, kTable, "PFX_"). Each call registers
-- PFX_ .. <string> for every entry in the magnum table, which lives in
-- libc/intrin/<lowercased table>.S as `.e SYMBOL,"STRING"` rows.
for tbl, pfx in C_unix:gmatch('LoadMagnums%(L,%s*(k%w+),%s*"([%u_]*)"%)') do
  local S = slurp("libc/intrin/" .. tbl:lower() .. ".S")
  for suffix in S:gmatch('%.e%s+[%u][%w_]*%s*,%s*"([%w_]+)"') do
    unix_consts[pfx .. suffix] = true
  end
end

-- re constants: literal LuaSetIntField calls plus the kReMagnums table rows.
local re_consts = {}
for name in C_re:gmatch('LuaSetIntField%(L,%s*"([%u][%w_]*)"') do
  re_consts[name] = true
end
for name in C_re:gmatch('{"([%u][%w_]*)"%s*,%s*REG_') do
  re_consts[name] = true
end

-- lsqlite3 constants: SC(NAME) rows in sqlite_constants[]. The session rows
-- are guarded by #ifdef SQLITE_ENABLE_SESSION, which this build defines (see
-- tool/net/BUILD.mk), so they're all treated as registered.
local sqlite_consts = {}
for name in C_sqlite:gmatch("SC%(%s*([%u][%w_]*)%s*%)") do
  sqlite_consts[name] = true
end

-- ===== module specs =====
--
-- fns:      registered top-level functions <-> `function <mod>.<name>(`
-- methods:  registered metatable methods   <-> `function <mod>.<Class>:<name>(`
-- consts:   registered constants           <-> `NAME = ...` in the module table
--
-- lsqlite3 registers ONE statement metatable (vmlib) that definitions.lua
-- documents twice, as lsqlite3.Statement (the LuaSQLite3 name) and as
-- lsqlite3.VM (the type used by iterator signatures). Both classes are held
-- to the full vmlib surface so they can't drift apart.

local MODULES = {
  {
    name = "cosmo",
    fns = reg_table(C_cosmo, "kCosmoFuncs"),
  },
  {
    name = "unix",
    fns = reg_table(C_unix, "kLuaUnix"),
    consts = unix_consts,
    methods = {
      { class = "Stat", reg = reg_table(C_unix, "kLuaUnixStatMeth") },
      { class = "Statfs", reg = reg_table(C_unix, "kLuaUnixStatfsMeth") },
      { class = "Rusage", reg = reg_table(C_unix, "kLuaUnixRusageMeth") },
      { class = "Errno", reg = reg_table(C_unix, "kLuaUnixErrnoMeth") },
      { class = "Memory", reg = reg_table(C_unix, "kLuaUnixMemoryMeth") },
      { class = "Sigset", reg = reg_table(C_unix, "kLuaUnixSigsetMeth") },
      { class = "Dir", reg = reg_table(C_unix, "kLuaUnixDirMeth") },
    },
  },
  {
    name = "path",
    fns = reg_table(C_path, "kLuaPath"),
  },
  {
    name = "re",
    fns = reg_table(C_re, "kLuaRe"),
    consts = re_consts,
    methods = {
      { class = "Regex", reg = reg_table(C_re, "kLuaReRegexMeth") },
      { class = "Errno", reg = reg_table(C_re, "kLuaReErrnoMeth") },
    },
  },
  {
    name = "argon2",
    fns = reg_table(C_argon2, "largon2"),
  },
  {
    name = "lsqlite3",
    fns = reg_table(C_sqlite, "sqlitelib"),
    consts = sqlite_consts,
    methods = {
      { class = "Database", reg = reg_table(C_sqlite, "dblib") },
      { class = "Statement", reg = reg_table(C_sqlite, "vmlib") },
      { class = "VM", reg = reg_table(C_sqlite, "vmlib") },
      { class = "Context", reg = reg_table(C_sqlite, "ctxlib") },
      { class = "Session", reg = reg_table(C_sqlite, "seslib") },
      { class = "Rebaser", reg = reg_table(C_sqlite, "reblib") },
      { class = "Iterator", reg = reg_table(C_sqlite, "itrlib") },
    },
  },
  {
    name = "getopt",
    fns = reg_table(C_getopt, "kLuaGetopt"),
  },
  {
    name = "zip",
    fns = reg_table(C_zip, "kLuaZip"),
    methods = {
      { class = "Reader", reg = reg_table(C_zip, "kLuaZipReaderMethods") },
      { class = "Writer", reg = reg_table(C_zip, "kLuaZipWriterMethods") },
      { class = "Appender", reg = reg_table(C_zip, "kLuaZipAppenderMethods") },
    },
  },
  {
    name = "repl",
    fns = reg_table(C_repl, "kReplFuncs"),
  },
}

-- ===== ratchet allowlists (may only shrink) =====
--
-- The whole surface of every module is annotated, so all allowlists are
-- empty. The ratchet is a pure regression check: any binding added to the C
-- without a matching annotation in definitions.lua fails this test.
--
-- Keys are "fn <mod>.<name>", "method <mod>.<Class>:<name>", or
-- "const <mod>.<NAME>".

local ALLOW = set({})

-- ===== checks =====

local failures = {}
local function fail(msg)
  failures[#failures + 1] = msg
end

local nfns, nmethods, nconsts = 0, 0, 0

for _, m in ipairs(MODULES) do
  local mod = m.name

  -- 1) functions, both directions
  local ann = ann_fns(mod)
  nfns = nfns + count(m.fns)
  for _, name in ipairs(sorted_keys(m.fns)) do
    local key = "fn " .. mod .. "." .. name
    if not ann[name] and not ALLOW[key] then
      fail("not annotated: function " .. mod .. "." .. name)
    end
  end
  for _, name in ipairs(sorted_keys(ann)) do
    if not m.fns[name] then
      fail("stale annotation (not registered in C): function " ..
        mod .. "." .. name)
    end
  end

  -- 2) class methods, both directions
  for _, cls in ipairs(m.methods or {}) do
    local mann = ann_methods(mod, cls.class)
    nmethods = nmethods + count(cls.reg)
    for _, name in ipairs(sorted_keys(cls.reg)) do
      local key = "method " .. mod .. "." .. cls.class .. ":" .. name
      if not mann[name] and not ALLOW[key] then
        fail("not annotated: method " .. mod .. "." .. cls.class ..
          ":" .. name)
      end
    end
    for _, name in ipairs(sorted_keys(mann)) do
      if not cls.reg[name] then
        fail("stale annotation (not registered in C): method " ..
          mod .. "." .. cls.class .. ":" .. name)
      end
    end
  end

  -- 3) constants, both directions
  if m.consts then
    local cann = ann_consts(mod)
    nconsts = nconsts + count(m.consts)
    for _, name in ipairs(sorted_keys(m.consts)) do
      local key = "const " .. mod .. "." .. name
      if not cann[name] and not ALLOW[key] then
        fail("not annotated: constant " .. mod .. "." .. name)
      end
    end
    for _, name in ipairs(sorted_keys(cann)) do
      if not m.consts[name] then
        fail("stale annotation (not registered in C): constant " ..
          mod .. "." .. name)
      end
    end
  end
end

-- 4) stale allowlist entries: allowlisted but now annotated or gone from C.
do
  local by_key = {}
  for _, m in ipairs(MODULES) do
    local ann = ann_fns(m.name)
    for name in pairs(m.fns) do
      by_key["fn " .. m.name .. "." .. name] = { reg = true, ann = ann[name] }
    end
    for name in pairs(ann) do
      local k = "fn " .. m.name .. "." .. name
      by_key[k] = by_key[k] or { reg = false, ann = true }
    end
    for _, cls in ipairs(m.methods or {}) do
      local mann = ann_methods(m.name, cls.class)
      for name in pairs(cls.reg) do
        by_key["method " .. m.name .. "." .. cls.class .. ":" .. name] =
          { reg = true, ann = mann[name] }
      end
    end
    if m.consts then
      local cann = ann_consts(m.name)
      for name in pairs(m.consts) do
        by_key["const " .. m.name .. "." .. name] =
          { reg = true, ann = cann[name] }
      end
    end
  end
  for _, key in ipairs(sorted_keys(ALLOW)) do
    local e = by_key[key]
    if not e or not e.reg then
      fail("stale allowlist entry (no longer registered in C): " .. key)
    elseif e.ann then
      fail("stale allowlist entry (now annotated): " .. key)
    end
  end
end

-- 5) malformed annotation syntax: a LuaLS tag must be written `---@tag`, with
-- no space between the comment dashes and the `@`. A stray `--- @tag` is
-- treated as ordinary comment prose, so LuaLS -- and the downstream gentype
-- generator -- silently ignore it: a function's @return/@overload vanishes
-- and it renders as returning nothing (this is exactly how unix.clearenv lost
-- its `boolean, unix.Errno` return). Catch it here so it can't recur.
do
  local lineno = 0
  for line in (D .. "\n"):gmatch("([^\n]*)\n") do
    lineno = lineno + 1
    if line:match("^%-%-%-[ \t]+@%a") then
      fail("line " .. lineno .. " puts a space after `---` so the tag is " ..
        "silently dropped (write `---@tag`, not `--- @tag`): " .. line)
    end
  end
end

-- 6) class-name lint. Modules exposed by the fork's lua binary; classes of
-- redbean-only modules (maxmind, finger) are permitted but not ratcheted.
local KNOWN_MODULES = set({
  "cosmo", "unix", "path", "re", "argon2", "lsqlite3", "getopt", "zip", "repl",
})
local REDBEAN_MODULES = set({ "maxmind", "finger" })
-- Redbean-only global helper classes that intentionally have no module
-- prefix. `string` extends the builtin string type.
local ALLOW_UNQUALIFIED_CLASSES = set({ "string" })

local class_names = {}  -- bare class name -> declared module (for check 7)
do
  local lineno = 0
  for line in (D .. "\n"):gmatch("([^\n]*)\n") do
    lineno = lineno + 1
    local cls = line:match("^%-%-%-@class%s+([%w_.]+)")
    if cls then
      local mod, name = cls:match("^([%w_]+)%.([%w_]+)$")
      if mod then
        if KNOWN_MODULES[mod] then
          class_names[name] = mod
        elseif not REDBEAN_MODULES[mod] then
          fail("line " .. lineno .. ": ---@class " .. cls ..
            " has unknown module prefix `" .. mod ..
            "` (known: cosmo unix path re argon2 lsqlite3 getopt zip repl" ..
            " + redbean-only maxmind finger)")
        end
      elseif not cls:find("%.") then
        if not ALLOW_UNQUALIFIED_CLASSES[cls] then
          fail("line " .. lineno .. ": ---@class " .. cls ..
            " must be module-qualified as `<mod>." .. cls .. "`")
        end
      else
        fail("line " .. lineno .. ": ---@class " .. cls ..
          " is not of the form `<mod>.<Name>`")
      end
    end
  end
end

-- 7) bare method receivers: `function <Name>:<method>(` where <Name> is a
-- class of a known module is invisible to gentype, which only understands
-- module-qualified receivers (`function <mod>.<Name>:<method>(`).
do
  local lineno = 0
  for line in (D .. "\n"):gmatch("([^\n]*)\n") do
    lineno = lineno + 1
    local recv = line:match("^function ([%w_]+):[%w_]+%s*%(")
    if recv and class_names[recv] then
      fail("line " .. lineno .. ": bare method receiver (gentype can't " ..
        "attribute it); write `function " .. class_names[recv] .. "." ..
        recv .. ":...`: " .. line)
    end
  end
end

assert(#failures == 0,
  "definitions.lua coverage failures (annotate the binding or fix the " ..
  "annotation; only shrink the allowlist):\n  " ..
  table.concat(failures, "\n  "))

print("definitions coverage: " .. nfns .. " functions, " .. nmethods ..
  " methods, " .. nconsts .. " constants checked across " ..
  #MODULES .. " modules; " .. count(ALLOW) .. " allowlisted")
print("test_definitions_coverage: PASS")
