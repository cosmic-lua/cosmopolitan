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
--   * unix       third_party/lua/cosmo/lunix.c      kLuaUnix[] + constants + methods
--   * path       tool/net/lpath.c             kLuaPath[]
--   * re         tool/net/lre.c               kLuaRe[] + constants + methods
--   * argon2     tool/net/largon2.c           largon2[]
--   * lsqlite3   tool/net/lsqlite3.c          sqlitelib[] + constants + methods
--   * getopt     tool/net/lgetopt.c           kLuaGetopt[]
--   * zip        tool/net/lzip.c              kLuaZip[] + Reader/Writer/Appender
--   * cov        tool/net/lcov.c              kLuaCov[]
--   * repl       third_party/lua/cosmo/lreplmod.c   kReplFuncs[]
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

-- The type each constant in a `<mod> = {` table declares, as a caller reads
-- it. Three ways a constant gets one:
--
--   1. an integer literal value                    `DETACH = 26,`
--   2. its own `@type` annotation block            `--- @type integer`
--                                                  `OPEN_URI = nil,`
--   3. the `@type` group heading it sits under -- this file annotates a run
--      of related constants once and lets the rest inherit:
--
--        --- @type integer termios input mode flags (Termios.iflag)
--        BRKINT = nil,
--        ICRNL = nil,     <- inherits `integer` from the heading above
--
-- A heading carries only across bare constant lines: a blank line, any other
-- content, or a `---` block of its own that declares no `@type` detaches the
-- constants below it. Returns name -> declared type string, or nil when the
-- constant ends up with no declaration at all.
local function ann_const_types(mod)
  local body = assert(
    D:match("\n" .. mod .. " = {(.-)\n}"),
    "could not locate the `" .. mod .. " = {` module table")
  local types = {}
  local heading, in_block, block_typed = nil, false, false
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    if line:match("^%s*%-%-%-") then
      if not in_block then
        in_block, block_typed = true, false
      end
      -- Both `---@type` and `--- @type` spellings appear in this file.
      local t = line:match("^%s*%-%-%-%s*@type%s+(%S+)")
      if t then
        heading, block_typed = t, true
      end
    else
      local name, value = line:match("^%s*([%u][%w_]*)%s*=%s*(.-),?%s*$")
      if name then
        if value:match("^%-?%d+$") or value:match("^%-?0[xX]%x+$") then
          types[name] = "integer"
        elseif not (in_block and not block_typed) then
          -- No own block, or one that declares a type: the heading applies.
          types[name] = heading
        end
      else
        -- Anything that is not a constant ends the run the heading covers.
        heading = nil
      end
      in_block = false
    end
  end
  return types
end

-- ===== per-module registered surfaces =====

local C_unix = slurp("third_party/lua/cosmo/lunix.c")
local C_path = slurp("tool/net/lpath.c")
local C_re = slurp("tool/net/lre.c")
local C_argon2 = slurp("tool/net/largon2.c")
-- Session/changeset/rebaser support is compiled out (tool/net/BUILD.mk no
-- longer defines SQLITE_ENABLE_SESSION), so strip those #ifdef blocks before
-- scanning: the seslib/reblib/itrlib tables, the dblib session methods, and
-- the CHANGESET_* constants they guard are not part of the shipped surface.
local C_sqlite = (slurp("tool/net/lsqlite3.c")
  :gsub("#ifdef SQLITE_ENABLE_SESSION.-\n#endif\n", ""))
local C_getopt = slurp("tool/net/lgetopt.c")
local C_zip = slurp("tool/net/lzip.c")
local C_cov = slurp("tool/net/lcov.c")
local C_repl = slurp("third_party/lua/cosmo/lreplmod.c")
local C_cosmo = slurp("tool/lua/lcosmo.c")
-- kCosmoFuncs[] registers names whose implementations live here, so the
-- return-arity scan below needs this source to resolve them.
local C_funcs = slurp("tool/net/lfuncs.c")
local C_redbean = slurp("tool/net/redbean.c")

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
-- (CHANGESET_*/CHANGESETSTART_*/CHANGESETAPPLY_*) are guarded by
-- #ifdef SQLITE_ENABLE_SESSION, which this build no longer defines and which
-- was stripped from C_sqlite above, so they're absent here.
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
    name = "cov",
    fns = reg_table(C_cov, "kLuaCov"),
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

-- 6) class-name lint. Every dotted ---@class must belong to a module exposed
-- by the fork's lua binary. The redbean-only modules (maxmind, finger) were
-- purged from definitions.lua; there is no whitelist for them, so a stray
-- `---@class maxmind.Db` reappearing now fails this lint.
local KNOWN_MODULES = set({
  "cosmo", "unix", "path", "re", "argon2", "lsqlite3", "getopt", "zip", "repl",
})
-- Global helper classes that intentionally have no module prefix.
-- `string` extends the builtin string type.
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
        else
          fail("line " .. lineno .. ": ---@class " .. cls ..
            " has unknown module prefix `" .. mod ..
            "` (known: cosmo unix path re argon2 lsqlite3 getopt zip repl)")
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

-- 8) fallibility dialect: the `---@overload fun(...): nil[, ...]` idiom is
-- banned. A fallible binding must express failure inline with `---@return
-- T|nil value` plus `---@return <errtype>? <name>` lines, so the whole
-- surface speaks ONE dialect. The mixed dialects (this idiom vs the inline
-- `T|nil` one) are why cosmic's generated types silently lost `| nil`.
-- Non-fallible `@overload`s (alternate signatures returning `true`, `0`, a
-- class, `T?, string?`, ...) are unaffected -- only a `nil`-first return is
-- the fallibility idiom. This is a ratchet: the allowlist may only shrink.
local QALLOW_OVERLOAD_NIL = set({})
do
  local lineno = 0
  for line in (D .. "\n"):gmatch("([^\n]*)\n") do
    lineno = lineno + 1
    if line:match("^%s*%-%-%-@overload%s+fun%b()%s*:%s*nil%f[%W]") then
      if not QALLOW_OVERLOAD_NIL[line] then
        fail("line " .. lineno .. ": banned `@overload fun(...): nil` " ..
          "fallibility idiom; express failure with `@return T|nil value` " ..
          "plus `@return <err>? <name>` lines instead: " .. line)
      end
    end
  end
end

-- 9) type-expression syntax: the type region of every `---@param`,
-- `---@return`, `---@field`, `---@overload`, and `---@type` line must parse
-- under the LuaLS type grammar. A tag can be well-formed while its TYPE is
-- syntactically dead -- the #151 dialect rewrite left `---@return nil,|nil
-- string, integer error` on the exec family, which every check above passed
-- and downstream generators turned into unparseable Teal. Parse the grammar
-- here so a malformed type can never ship.
--
-- Grammar (recursive descent; each parse_* returns the text remaining after
-- what it consumed, or nil on syntax error):
--   union    := postfix ('|' postfix)*    -- see the depth rule below
--   postfix  := atom ('?' | '[]')*
--   atom     := 'fun' '(' ... ')' (':' labeled-typelist)?
--             | '{' ... '}'                  -- balance-checked table shape
--             | '(' union ')'
--             | '"'str'"' | "'"str"'" | int  -- literal types
--             | dotted-ident ('<' typelist '>')?
--
-- Depth rule: at bracket depth 0 of the type region -- outside any `()`,
-- `{}`, `<>` -- whitespace is what ENDS the type (a name or description
-- follows it), so a `|` there must sit flush against both members:
-- `integer| cols` is a dangling bar with the slot name after it, not a
-- two-member union, and `integer |nil rows` is the bare type `integer`
-- with `|nil rows` read as its name -- the nil silently dropped. The same
-- rule holds for everything after a fun(...)'s closing paren: `fun() : integer`
-- ends the type at `fun()`, so the return colon must follow the paren
-- directly, as must its optional `?` (`fun() ?: integer` is `fun()` with
-- `?: integer` as its name) and the inner colon of a typed vararg return
-- (`fun(): ... : string` is a bare `...` return with `: string` as its
-- name). A fun return list at depth 0 admits no comma either: whitespace
-- after the first value ends the type, so `fun(): boolean, string` is a
-- return of `boolean,` -- a multi-value return is one `---@return` line per
-- value. The one exception is an `---@overload`, whose fun return list runs
-- to the end of the line with no name after it, so `fun(...): T?, string?`
-- is read whole there (`multi` = true below). Inside a bracketed group the
-- closing bracket delimits instead, whitespace around `|` or before `:` is
-- part of the type (`(integer | string)?`), and a comma separates list
-- entries. This is exactly how cosmic's gentype tokenizes the same text,
-- so the gate refuses what the generator would drop.
-- Every parse_* below takes `grouped` = true when parsing inside a group,
-- and `multi` = true when parsing an @overload line's type at depth 0.
do
  local parse_union

  local function parse_ident(s)
    local id = s:match("^[%a_][%w_]*")
    if not id then return nil end
    s = s:sub(#id + 1)
    while true do
      local seg = s:match("^%.[%a_][%w_]*")
      if not seg then break end
      s = s:sub(#seg + 1)
    end
    return s
  end

  -- Only reached inside a generic application's `<...>`, so always grouped.
  local function parse_typelist(s)
    s = parse_union(s, true)
    if not s then return nil end
    while s:match("^%s*,") do
      s = s:gsub("^%s*,%s*", "")
      s = parse_union(s, true)
      if not s then return nil end
    end
    return s
  end

  -- A fun(...) return-list entry may carry a `label:` prefix
  -- (`fun(fd: integer): flags: integer`).
  local function parse_labeled_union(s, grouped)
    s = s:gsub("^%s+", "")
    local label = s:match("^[%a_][%w_%.]*%s*:%s*")
    if label then
      local rest = parse_union(s:sub(#label + 1), grouped)
      if rest then return rest end
    end
    return parse_union(s, grouped)
  end

  -- A comma continues the list inside a group or on an @overload line; at
  -- depth 0 anywhere else it is left in place for type_ok to refuse.
  local function parse_labeled_typelist(s, grouped, multi)
    s = parse_labeled_union(s, grouped)
    if not s then return nil end
    while (grouped or multi) and s:match("^%s*,") do
      s = s:gsub("^%s*,%s*", "")
      s = parse_labeled_union(s, grouped)
      if not s then return nil end
    end
    return s
  end

  -- fun(...) with balanced parens (parameter internals are not typechecked
  -- here); after the closing paren an optional `: <labeled typelist>` or
  -- typed-vararg (`: ...: string`) return annotation. The return list sits
  -- after the closing paren, so it is at the caller's depth.
  local function parse_fun(s, grouped, multi)
    local depth = 0
    for k = 4, #s do
      local c = s:sub(k, k)
      if c == "(" then
        depth = depth + 1
      elseif c == ")" then
        depth = depth - 1
        if depth == 0 then
          local rest = s:sub(k + 1)
          -- Depth rule: at depth 0 the `?` must follow the `)` directly, and
          -- the colon must follow the `)` (or `)?`) directly; whitespace
          -- there would end the type before the return annotation, so
          -- refuse rather than leave it as the name.
          if not grouped and (rest:match("^%s+%?") or rest:match("^%??%s+:")) then
            return nil
          end
          local colon = rest:match(grouped and "^%??%s*:%s*" or "^%??:%s*")
          if colon then
            rest = rest:sub(#colon + 1)
            if rest:match("^%.%.%.") then
              rest = rest:sub(4)
              -- The same depth rule for the typed vararg's inner colon:
              -- `...:` must be flush, or `: string` becomes the name.
              if not grouped and rest:match("^%s+:") then return nil end
              local c2 = rest:match(grouped and "^%s*:%s*" or "^:%s*")
              if c2 then return parse_union(rest:sub(#c2 + 1), grouped) end
              return rest
            end
            return parse_labeled_typelist(rest, grouped, multi)
          end
          return rest
        end
      end
    end
    return nil -- unbalanced
  end

  local function parse_atom(s, grouped, multi)
    if s == "" then return nil end
    if s:match("^fun%(") then return parse_fun(s, grouped, multi) end
    if s:match('^"') then
      local lit = s:match('^"[^"]*"')
      return lit and s:sub(#lit + 1) or nil
    end
    if s:match("^'") then
      local lit = s:match("^'[^']*'")
      return lit and s:sub(#lit + 1) or nil
    end
    if s:match("^%(") then
      local rest = parse_union(s:sub(2), true)
      if not rest then return nil end
      rest = rest:gsub("^%s+", "")
      if rest:sub(1, 1) ~= ")" then return nil end
      return rest:sub(2)
    end
    if s:match("^{") then
      -- table shape: {T}, {K: V} -- balance-checked only; the inline-shape
      -- quality ratchet (Q3) separately bans `{ field: type }` records.
      local depth = 0
      for k = 1, #s do
        local c = s:sub(k, k)
        if c == "{" then
          depth = depth + 1
        elseif c == "}" then
          depth = depth - 1
          if depth == 0 then return s:sub(k + 1) end
        end
      end
      return nil -- unbalanced
    end
    local lit = s:match("^%-?%d+")
    if lit then return s:sub(#lit + 1) end
    local rest = parse_ident(s)
    if not rest then return nil end
    if rest:match("^<") then -- generic application: table<K, V>
      rest = parse_typelist(rest:sub(2))
      if not rest then return nil end
      rest = rest:gsub("^%s+", "")
      if rest:sub(1, 1) ~= ">" then return nil end
      rest = rest:sub(2)
    end
    return rest
  end

  local function parse_postfix(s, grouped, multi)
    s = parse_atom(s, grouped, multi)
    if not s then return nil end
    while true do
      if s:match("^%?") then
        s = s:sub(2)
      elseif s:match("^%[%]") then
        s = s:sub(3)
      else
        break
      end
    end
    return s
  end

  parse_union = function(s, grouped, multi)
    s = s:gsub("^%s+", "")
    s = parse_postfix(s, grouped, multi)
    if not s then return nil end
    while s:match("^%s*|") do
      -- Depth rule: whitespace around the bar is skipped only inside a
      -- group. At depth 0 only a flush `|` is stripped, so whitespace on
      -- either side of it reaches parse_postfix, which refuses it.
      s = s:gsub(grouped and "^%s*|%s*" or "^|", "")
      s = parse_postfix(s, grouped, multi)
      if not s then return nil end
    end
    return s
  end

  -- A type region is well-formed iff a full type expression parses off its
  -- head and ends at a clean boundary: end of line, whitespace (a name or
  -- description follows), or `#` (LuaLS description marker). A comma directly
  -- after the first type (`nil, string, integer`) is NOT a clean boundary:
  -- multi-value returns must be one `---@return` line per value. `multi`
  -- marks an @overload line, the one place a fun return list keeps its
  -- commas (they are consumed inside the type, never left at the boundary).
  local function type_ok(region, multi)
    if region:match("^%.%.%.") then return true end -- bare variadic
    local rest = parse_union(region, false, multi)
    if not rest then return false end
    return rest == "" or rest:match("^[%s#]") ~= nil
  end

  -- Parser self-check: the classifications the scan below relies on, so a
  -- grammar regression fails here by fixture instead of silently passing
  -- (or failing) real annotations. The dangling-bar shapes are the ones a
  -- whitespace-skipping union loop reads as well-formed two-member unions.
  -- A third field marks the region as an @overload line's (`multi`).
  local TYPE_FIXTURES = {
    { "integer|string", true },
    { "integer|nil rows", true },
    { "(integer | string)?", true },
    { "(true|nil | string)", true },
    { "table<string, integer|nil>", true },
    { "fun(fd: integer): integer|nil", true },
    { "(integer |nil)", true },
    { "fun(): integer", true },
    { "integer| cols", false },
    { "integer |nil rows", false },
    { "integer|", false },
    { "fun(fd: integer): integer| nil", false },
    { "fun() : integer", false },
    { "nil,|nil string", false },
    { "fun()?: integer", true },
    { "fun() ?: integer", false },
    { "fun(): ...: string", true },
    { "fun(): ... : string", false },
    { "fun(): boolean", true },
    { "fun(): boolean, string", false },
    { "fun(): zip.Writer?, string?", true, true },
    { "fun(): zip.Writer?, string?", false },
  }
  for _, fx in ipairs(TYPE_FIXTURES) do
    assert(type_ok(fx[1], fx[3]) == fx[2], "check 9 self-check: `" .. fx[1] ..
      "` must be " .. (fx[2] and "accepted" or "refused") ..
      " by the type grammar")
  end

  local lineno = 0
  for line in (D .. "\n"):gmatch("([^\n]*)\n") do
    lineno = lineno + 1
    local region = line:match("^%-%-%-@param%s+[%w_%.]+%??%s+(.+)$") or
      line:match("^%-%-%-@return%s+(.+)$") or
      line:match("^%-%-%-@field%s+[%w_%.]+%??%s+(.+)$") or
      line:match("^%s*%-%-%-@type%s+(.+)$")
    local multi = false
    if not region then
      region = line:match("^%-%-%-@overload%s+(.+)$")
      multi = region ~= nil
    end
    if region and not type_ok(region, multi) then
      fail("line " .. lineno .. ": unparseable type expression (one " ..
        "`---@return` line per value; see the grammar in check 9): " .. line)
    end
  end
end

-- ===== annotation quality ratchet (shrink-only allowlists) =====
--
-- The checks above enforce that every binding is annotated at all. These five
-- raise the floor on annotation QUALITY, so cosmic's generated Teal keeps
-- improving with zero generator changes as entries are burned down:
--   Q1: every declared parameter of a module function/method has a matching
--       `---@param` (an undocumented param gentype-defaults to `any`).
--   Q2: every function/method has a `---@return` or a `---@overload` (which
--       carries its own return types), otherwise it renders as returning
--       nothing -- allowlist the ones that genuinely do (or aren't annotated
--       yet) in QALLOW_NORETURN.
--   Q3: no inline `{ field: type }` table types in `---@param`/`---@return`/
--       `---@overload` -- name the shape as a `---@class` (e.g.
--       cosmo.EncoderOptions, cosmo.FetchOptions) so it type-checks.
--   Q4: no bare `any`/`table` parameter or return types.
--   Q5: every module-table constant declares `integer`. Constants reach Lua
--       only through LuaSetIntField / LoadMagnums / SC(), so every one of
--       them IS a C int -- but a constant whose integer-ness is left
--       undeclared (or, worse, declared `number`) renders downstream as
--       Teal `number`, and every bit-op call site on it then needs an
--       `as integer` cast (whilp/cosmopolitan#142). Declaring it here is
--       what keeps cosmic's generated `integer` honest.
--   Q6: a block that documents any `---@return` line documents a success
--       slot -- its FIRST `---@return` is the one downstream generators
--       (cosmic's gentype) read as the binding's success type, and this
--       file's dialect spells the failure tail's two slots exactly
--       `---@return string? error` / `---@return unix.Errno? errno`
--       (D24/#151), never anything else. A block whose first line is
--       bare `string?` or `unix.Errno?` has lost its value line and left
--       only the failure tail -- invisible to every OTHER check here,
--       since the tail is still syntactically well-formed and non-empty.
-- Each QALLOW_* is a RATCHET seeded at today's counts: an entry may only be
-- removed (by improving the annotation), never added. A newly-violating
-- binding, or a stale entry that no longer violates, fails this test.

local QALLOW_PARAM = set({
  "cosmo.EncodeLua",
  "lsqlite3.Context:result_error",
  "lsqlite3.Context:set_aggregate_data",
})

local QALLOW_NORETURN = set({
  "cosmo.StreamReader:close",
  "lsqlite3.Context:result",
  "lsqlite3.Context:result_blob",
  "lsqlite3.Context:result_double",
  "lsqlite3.Context:result_error",
  "lsqlite3.Context:result_int",
  "lsqlite3.Context:result_null",
  "lsqlite3.Context:result_number",
  "lsqlite3.Context:result_text",
  "lsqlite3.Context:set_aggregate_data",
  "lsqlite3.Database:busy_handler",
  "lsqlite3.Database:busy_timeout",
  "lsqlite3.Database:close_vm",
  "lsqlite3.Database:commit_hook",
  "lsqlite3.Database:create_collation",
  "lsqlite3.Database:deserialize",
  "lsqlite3.Database:interrupt",
  "lsqlite3.Database:rollback_hook",
  "lsqlite3.Database:update_hook",
  "lsqlite3.Database:wal_hook",
  "repl.start",
  "unix.Dir:rewind",
  "unix.Memory:store",
  "unix.Sigset:add",
  "unix.Sigset:clear",
  "unix.Sigset:fill",
  "unix.Sigset:remove",
  "unix.exit",
  "unix.sched_yield",
  "unix.sync",
  "unix.syslog",
  "unix.verynice",
  "zip.Reader:close",
})

local QALLOW_INLINE = set({
  "cosmo.ParseParams",
  "unix.poll",
})

local QALLOW_BARE = set({
  "lsqlite3.Context:get_aggregate_data",
  "lsqlite3.Context:user_data",
  "lsqlite3.Database:create_aggregate",
  "lsqlite3.Database:create_function",
  "lsqlite3.Statement:bind_names",
  "lsqlite3.config",
  "unix.fcntl",
})

-- Q5: the whole constant surface declares `integer` today, so this list is
-- empty and must stay that way. Do not seed it -- annotate the constant.
local QALLOW_CONSTTYPE = set({})

-- Q6: bindings whose declared success value genuinely IS a bare optional
-- string, with no error/errno slot of its own (a single ---@return line,
-- or -- StreamReader's read family -- a second, differently-named string?
-- slot that is its OWN error message, not a stray copy of the failure
-- tail). None of these can be produced by dropping a value line off a
-- standard `T|nil value / string? error / unix.Errno? errno` block --
-- EXCEPT by type token alone: `string?`/`unix.Errno?` is exactly what a
-- failure tail that lost its value line still reads as, so allowlisting
-- a NAME here cannot tell "genuinely bare" from "just got mutilated".
-- Each entry is keyed instead to the exact TEXT of the `---@return` line
-- its block's real success line was seeded with, and the ratchet below
-- only exempts a block whose first `---@return` line still reads that
-- text. A line count is not enough: StreamReader:read and :read_until
-- both already carry two `string?` lines (their real success line and
-- their `error` line), so a mutation that swaps the real line's text for
-- a fabricated one sharing the same `string?` token -- keeping the count
-- at 2 -- is invisible to a count check but changes the head line's text.
-- Keying to text also still catches the coarser mutations: dropping the
-- real line entirely (count 2 -> 1, and the surviving line's text is the
-- `error` line's, not this one's) or dropping the block's only line
-- (falls out of `qvio.nosuccess` into the Q2 `noreturn` check instead).
local QALLOW_NOSUCCESS = {
  ["cosmo.ParseHost"] =
    "---@return string? port",
  ["cosmo.StreamReader:read"] =
    "---@return string? chunk next chunk of data, or nil on EOF",
  ["cosmo.StreamReader:read_until"] =
    "---@return string? data bytes before the delimiter (or the final " ..
    "remainder), or nil on EOF",
  ["lsqlite3.Database:db_filename"] =
    "---@return string? filename associated with database `name` of " ..
    "connection `db`.",
  ["lsqlite3.Statement:bind_parameter_name"] =
    "---@return string? -- the name of the n-th parameter in prepared " ..
    "statement.",
  ["lsqlite3.VM:bind_parameter_name"] =
    "---@return string? parameter_name nil for a positional (`?`) " ..
    "parameter, which has no name.",
}

-- Collect module function/method declarations paired with the contiguous run
-- of `---` annotation lines that immediately precedes each.
local qdecls = {}
do
  local block = {}
  for line in (D .. "\n"):gmatch("([^\n]*)\n") do
    if line:match("^%s*%-%-%-") then
      block[#block + 1] = line
    else
      local mod, cls, meth = line:match("^function ([%w_]+)%.([%w_]+):([%w_]+)%s*%(")
      local params
      if mod then
        params = line:match("^function [%w_]+%.[%w_]+:[%w_]+%s*%((.-)%)")
      else
        local m2, nm = line:match("^function ([%w_]+)%.([%w_]+)%s*%(")
        if m2 then
          mod, meth, cls = m2, nm, nil
          params = line:match("^function [%w_]+%.[%w_]+%s*%((.-)%)")
        end
      end
      if mod and KNOWN_MODULES[mod] then
        qdecls[#qdecls + 1] = {
          disp = cls and (mod .. "." .. cls .. ":" .. meth) or (mod .. "." .. meth),
          params = params or "",
          block = table.concat(block, "\n"),
          blocklines = block,
        }
      end
      block = {}
    end
  end
end

-- A type region is a "bare" any/table if it starts with the bare word `any`
-- or `table` (but not the parameterized `table<...>`/`table[...]`).
local function qbare(t)
  t = t:gsub("^%s+", "")
  if t:match("^any%f[%W]") then return true end
  if t:match("^table%f[%W]") and not t:match("^table[<%[]") then return true end
  return false
end

-- The type token of a block's FIRST `---@return` line, or nil when the
-- block declares none. Only the head token is read (the same word gentype
-- takes as the slot's type), so a description trailing it doesn't matter.
local function first_return_type(blocklines)
  for _, l in ipairs(blocklines) do
    local t = l:match("^%-%-%-@return%s+(%S+)")
    if t then return t end
  end
  return nil
end

-- Q6 self-check: the shapes first_return_type must and must not flag,
-- exercised directly so a regression here fails by fixture instead of
-- silently passing (or failing) real annotations. Mirrors the localtime
-- mutation: dropping a block's value line leaves exactly the FAIL shapes.
local NOSUCCESS_FIXTURES = {
  -- { blocklines, expected first_return_type, is a lost-success-slot shape }
  { { "---@return unix.BrokenDownTime|nil", "---@return string? error",
      "---@return unix.Errno? errno" }, "unix.BrokenDownTime|nil", false },
  { { "---@return string? error", "---@return unix.Errno? errno" },
    "string?", true },
  { { "---@return string? error" }, "string?", true },
  { { "---@return unix.Errno? errno" }, "unix.Errno?", true },
  { { "---@return string? filename associated with the connection" },
    "string?", true }, -- a bare optional-string SUCCESS value is still
                        -- indistinguishable from the failure tail by type
                        -- alone; real cases like this ride QALLOW_NOSUCCESS
  { { "---@return boolean" }, "boolean", false },
  { { "--- no @return line at all" }, nil, false },
}
for _, fx in ipairs(NOSUCCESS_FIXTURES) do
  local blocklines, want_type, want_flagged = fx[1], fx[2], fx[3]
  local got_type = first_return_type(blocklines)
  assert(got_type == want_type, "Q6 self-check: first_return_type mismatch " ..
    "for " .. table.concat(blocklines, " / "))
  local flagged = got_type == "string?" or got_type == "unix.Errno?"
  assert(flagged == want_flagged, "Q6 self-check: flagged mismatch for " ..
    table.concat(blocklines, " / "))
end

-- The full text of a block's FIRST `---@return` line -- the shape
-- QALLOW_NOSUCCESS keys its exemptions to. first_return_type alone cannot
-- distinguish a genuinely bare success value from a failure tail that
-- lost its value line (both read as `string?`), and a plain line count
-- cannot either: it is blind to a same-count substitution that swaps the
-- real success line's text for a fabricated one sharing its type token.
-- The exact head-line TEXT pins down which line is actually there, so an
-- allowlisted NAME is exempt only when its block's first `---@return`
-- line still reads the text it was seeded with.
local function first_return_line(blocklines)
  for _, l in ipairs(blocklines) do
    if l:match("^%-%-%-@return%f[%s]") then return l end
  end
  return nil
end

-- Shape self-check: exercises all three mutation shapes a real block can
-- suffer, mirroring StreamReader:read/:read_until.
local LINE_FIXTURES = {
  -- { blocklines, expected first_return_line }
  { { "---@return string? chunk next chunk of data, or nil on EOF",
      "---@return string? error error message on failure" },
    "---@return string? chunk next chunk of data, or nil on EOF" },
  { { "---@return string? error error message on failure" },
    "---@return string? error error message on failure" }, -- round-1
    -- mutation: the real value line is gone, only the (renamed) error
    -- line remains -- text differs from the seeded head line above
  { { "---@return string? reason secondary detail on failure " ..
        "(success info lost)",
      "---@return string? error error message on failure" },
    "---@return string? reason secondary detail on failure " ..
      "(success info lost)" }, -- round-2 mutation: the count stays at 2,
    -- but the real value line's text was swapped for a fabricated line
    -- sharing its `string?` token -- still a different head line
  { { "---@return string? port" }, "---@return string? port" },
  { { "--- no @return line at all" }, nil },
}
for _, fx in ipairs(LINE_FIXTURES) do
  local blocklines, want = fx[1], fx[2]
  local got = first_return_line(blocklines)
  assert(got == want, "Q6 shape self-check: first_return_line mismatch for " ..
    table.concat(blocklines, " / "))
end

local qvio = {
  param = {}, noreturn = {}, inline = {}, bare = {}, consttype = {},
  nosuccess = {}, nosuccess_lines = {},
}
for _, d in ipairs(qdecls) do
  for rawp in (d.params .. ","):gmatch("%s*([^,]-)%s*,") do
    local p = rawp:gsub("%s", "")
    if p ~= "" and p ~= "self" and p ~= "..." then
      if not d.block:find("%-%-%-@param%s+" .. p .. "%f[%W]") then
        qvio.param[d.disp] = true
      end
    end
  end
  if not (d.block:find("%-%-%-@return") or d.block:find("%-%-%-@overload")) then
    qvio.noreturn[d.disp] = true
  end
  do
    local rt = first_return_type(d.blocklines)
    if rt == "string?" or rt == "unix.Errno?" then
      qvio.nosuccess[d.disp] = true
      qvio.nosuccess_lines[d.disp] = first_return_line(d.blocklines)
    end
  end
  for _, l in ipairs(d.blocklines) do
    if l:match("%-%-%-@param") or l:match("%-%-%-@return") or
       l:match("%-%-%-@overload") then
      local br = l:match("(%b{})")
      if br and br:find(":") then qvio.inline[d.disp] = true end
    end
    local pt = l:match("%-%-%-@param%s+[%w_]+%??%s+(.+)")
    if pt and qbare(pt) then qvio.bare[d.disp] = true end
    local rt = l:match("%-%-%-@return%s+(.+)")
    if rt and qbare(rt) then qvio.bare[d.disp] = true end
  end
end

for _, m in ipairs(MODULES) do
  if m.consts then
    -- Walk the NAME set, not the type map: an undeclared constant maps to
    -- nil, which pairs() over the type map cannot see, and undeclared is
    -- itself the violation.
    local declared = ann_const_types(m.name)
    for _, name in ipairs(sorted_keys(ann_consts(m.name))) do
      if declared[name] ~= "integer" then
        qvio.consttype[m.name .. "." .. name] = true
      end
    end
  end
end

-- ===== return-arity conformance =====
--
-- An annotation may not declare MORE return values than the C can push.
-- Nothing checked this, and it is how re.Regex:search/:match came to
-- declare a third slot that lre.c never returns (#247): the runtime
-- probe in test_definitions_conformance.lua reads declared slots
-- positionally, and an absent trailing slot is nil, which satisfies the
-- `string?` it was declared as. A phantom slot is invisible from the
-- Lua side and obvious from the C side, so it is checked here.
--
-- The C side is read statically: a binding's registered name maps to its
-- C function through the same luaL_Reg tables the coverage checks above
-- use, and that function's arity is the largest value it can `return`.
-- `return <literal>;` is the common case (there are hundreds); a
-- `return Helper(...)` resolves to Helper's own arity, recursively, so
-- the many SysretErrno/ReturnInteger/ZipError wrappers resolve too. A
-- function whose arity cannot be determined that way is SKIPPED and
-- counted, never silently passed.
--
-- Direction matters: declaring FEWER returns than the C pushes is a
-- narrowing an annotation is allowed to make (a caller simply cannot
-- see the extra), while declaring more advertises a value that does not
-- exist. Only the second is a failure.

-- Helpers that never return to their caller: they longjmp out, so they
-- put nothing on the stack and must not contribute an arity.
local NORETURN_C = set({
  "luaL_error", "luaL_argerror", "lua_error", "luaL_typeerror",
})

-- Blank out string/char literals and comments, preserving length and
-- newlines. Without this the return scan below reads statements out of
-- prose: lunix.c's WARNF("syscall supposed to return 0 / -1 but got %d")
-- parses as an unresolvable `return`, marking SysretBool's arity unknown
-- and silently dropping the whole boolean-syscall family (51 bindings)
-- out of the check.
local function strip_c_literals(src)
  local out, i, n = {}, 1, #src
  while i <= n do
    local c = src:sub(i, i)
    local two = src:sub(i, i + 1)
    if c == '"' or c == "'" then
      local q, j = c, i + 1
      while j <= n do
        local d = src:sub(j, j)
        if d == "\\" then j = j + 2
        elseif d == q or d == "\n" then break
        else j = j + 1 end
      end
      out[#out + 1] = q .. string.rep(" ", j - i - 1) .. src:sub(j, j)
      i = j + 1
    elseif two == "//" then
      local j = src:find("\n", i) or n + 1
      out[#out + 1] = string.rep(" ", j - i)
      i = j
    elseif two == "/*" then
      local j = src:find("*/", i + 2, true)
      j = j and j + 2 or n + 1
      out[#out + 1] = src:sub(i, j - 1):gsub("[^\n]", " ")
      i = j
    else
      local j = src:find("[\"'/]", i + 1) or n + 1
      out[#out + 1] = src:sub(i, j - 1)
      i = j
    end
  end
  return table.concat(out)
end

-- Every C function in the loaded sources, as name -> body text. The body
-- runs to the start of the next function rather than to a matched brace:
-- a brace inside a string literal or comment cannot then throw the scan
-- off, and these files are a flat sequence of functions.
local C_BODIES = {}
do
  local sources = {
    C_unix, C_path, C_re, C_argon2, C_sqlite, C_getopt, C_zip, C_cov,
    C_repl, C_cosmo, C_funcs, C_redbean,
  }
  for _, C in ipairs(sources) do
    C = strip_c_literals(C)
    local starts = {}
    for pos, name in C:gmatch("()\n[%w_]+[%w_ %*]-([%w_]+)%s*%(lua_State%s*%*") do
      starts[#starts + 1] = { pos = pos, name = name }
    end
    for i, f in ipairs(starts) do
      local stop = starts[i + 1] and starts[i + 1].pos or #C
      -- Last definition wins: a forward declaration is a prefix of the
      -- real body's span and carries no returns of its own.
      local body = C:sub(f.pos, stop)
      if not C_BODIES[f.name] or #body > #C_BODIES[f.name] then
        C_BODIES[f.name] = body
      end
    end
  end
end

-- Macros that hide a return, e.g. lgetopt.c's
--
--   #define FAIL(...) do { lua_pushnil(L); lua_pushfstring(...); return 2; }
--
-- Without these the scan below reads a smaller arity than the C really
-- pushes and reports a function that is fine -- which it did for
-- getopt.parse on the first run of this check.
local MACRO_RETURNS = {}
do
  local sources = {
    C_unix, C_path, C_re, C_argon2, C_sqlite, C_getopt, C_zip, C_cov,
    C_repl, C_cosmo, C_funcs, C_redbean,
  }
  for _, C in ipairs(sources) do
    for name, tail in C:gmatch("#define%s+([A-Z_][A-Z_0-9]*)%s*%(([^\n]-)\n") do
      local _ = tail
      -- the macro body runs while lines end in a backslash
      local at = C:find("#define%s+" .. name .. "%s*%(")
      if at then
        local body, i = "", at
        repeat
          local line_end = C:find("\n", i) or #C
          local line = C:sub(i, line_end)
          body = body .. line
          i = line_end + 1
        until not line:match("\\%s*\n$")
        local n = body:match("return%s+(%d+)%s*;")
        if n then
          local v = tonumber(n)
          if not MACRO_RETURNS[name] or v > MACRO_RETURNS[name] then
            MACRO_RETURNS[name] = v
          end
        end
      end
    end
  end
end

-- The largest number of values `fname` can leave on the Lua stack, or
-- nil when that cannot be read off the source.
local arity_memo = {}
local function max_returns(fname, seen)
  if arity_memo[fname] ~= nil then
    if arity_memo[fname] == false then return nil end
    return arity_memo[fname]
  end
  local body = C_BODIES[fname]
  if not body then return nil end
  seen = seen or {}
  if seen[fname] then return nil end   -- recursion: cannot bound it here
  seen[fname] = true
  local best, unknown = nil, false
  for macro, n in pairs(MACRO_RETURNS) do
    if body:find("%f[%w_]" .. macro .. "%s*%(") then
      if not best or n > best then best = n end
    end
  end
  for stmt in body:gmatch("return%s+([^;]+);") do
    local lit = stmt:match("^(%d+)%s*$")
    local call = stmt:match("^([%w_]+)%s*%(")
    if lit then
      local n = tonumber(lit)
      if not best or n > best then best = n end
    elseif call and NORETURN_C[call] then
      -- contributes nothing
    elseif call then
      local n = max_returns(call, seen)
      if n then
        if not best or n > best then best = n end
      else
        unknown = true
      end
    else
      unknown = true                    -- `return n;`, `return top - 1;`, ...
    end
  end
  seen[fname] = nil
  local result = (not unknown) and best or nil
  arity_memo[fname] = result or false
  return result
end

-- Registered name -> C function, from a luaL_Reg table.
local function reg_cfuncs(C, tbl)
  local body = assert(C:match("luaL_Reg%s+" .. tbl .. "%[%]%s*=%s*{(.-)};"))
  local out = {}
  for name, cfn in body:gmatch('{%s*"([%a_][%w_]*)"%s*,%s*([%w_]+)%s*}') do
    if not name:match("^__") then
      out[name] = cfn
    end
  end
  return out
end

-- How many ---@return lines the annotation for `decl` carries. Only a
-- line that STARTS the tag counts; the wrapped prose under one does not.
local function declared_return_count(decl)
  local pat = "\nfunction " .. decl:gsub("[%.%:%-]", "%%%1") .. "%s*%("
  local at = D:find(pat)
  if not at then return nil end
  local head = D:sub(1, at)
  local block = head:match("(\n%-%-%-[^\n]*)$")
  -- walk back over the contiguous --- comment block
  local lines, i = {}, 0
  for line in head:gmatch("([^\n]*)\n") do
    i = i + 1
    lines[i] = line
  end
  local n = 0
  for j = i, 1, -1 do
    local line = lines[j]
    if not line:match("^%-%-%-") then break end
    if line:match("^%-%-%-@return") then n = n + 1 end
  end
  local _ = block
  return n
end

-- Annotations known to over-declare, kept so the check can land before
-- every one is fixed. A RATCHET: it may only shrink, and a stale entry
-- (now clean) fails just like a violation.
local ARITY_ALLOW = set({})

local ARITY_SKIPPED = {}
local arity_checked, arity_vio = 0, {}
do
  local targets = {}
  local function add(decl, C, tbl)
    for name, cfn in pairs(reg_cfuncs(C, tbl)) do
      targets[#targets + 1] = { decl = decl .. name, cfn = cfn }
    end
  end
  add("cosmo.", C_cosmo, "kCosmoFuncs")
  add("unix.", C_unix, "kLuaUnix")
  add("unix.Stat:", C_unix, "kLuaUnixStatMeth")
  add("unix.Statfs:", C_unix, "kLuaUnixStatfsMeth")
  add("unix.Rusage:", C_unix, "kLuaUnixRusageMeth")
  add("unix.Memory:", C_unix, "kLuaUnixMemoryMeth")
  add("unix.Sigset:", C_unix, "kLuaUnixSigsetMeth")
  add("unix.Dir:", C_unix, "kLuaUnixDirMeth")
  add("path.", C_path, "kLuaPath")
  add("re.", C_re, "kLuaRe")
  add("re.Regex:", C_re, "kLuaReRegexMeth")
  add("argon2.", C_argon2, "largon2")
  add("lsqlite3.", C_sqlite, "sqlitelib")
  add("lsqlite3.Database:", C_sqlite, "dblib")
  add("lsqlite3.Statement:", C_sqlite, "vmlib")
  add("lsqlite3.Context:", C_sqlite, "ctxlib")
  add("getopt.", C_getopt, "kLuaGetopt")
  add("zip.", C_zip, "kLuaZip")
  add("zip.Reader:", C_zip, "kLuaZipReaderMethods")
  add("zip.Writer:", C_zip, "kLuaZipWriterMethods")
  add("zip.Appender:", C_zip, "kLuaZipAppenderMethods")
  add("cov.", C_cov, "kLuaCov")
  add("repl.", C_repl, "kReplFuncs")

  for _, t in ipairs(targets) do
    local declared = declared_return_count(t.decl)
    local actual = max_returns(t.cfn)
    if declared and declared > 0 then
      if not actual then
        ARITY_SKIPPED[#ARITY_SKIPPED + 1] = t.decl .. " (" .. t.cfn .. ")"
      else
        arity_checked = arity_checked + 1
        if declared > actual then
          arity_vio[string.format(
            "%s declares %d returns; %s pushes at most %d",
            t.decl, declared, t.cfn, actual)] = true
        end
      end
    end
  end
end

-- Skips are reported, not hidden: a binding whose arity the reader above
-- cannot determine is one this check does not cover.
table.sort(ARITY_SKIPPED)
if os.getenv("ARITY_SKIPS") then
  for _, d in ipairs(ARITY_SKIPPED) do print("  skip: " .. d) end
end

-- 10) type documentation: every `---@class` needs a prose description above
-- it, and every `---@field` needs one after its type. A type declared here is
-- re-exported by downstream generators, so this file is the only source its
-- consumers have for what the type IS -- their editors show these words or
-- nothing. Function docs do not cover it: they describe the calls a type
-- flows through, not the type. Both lists are ratchets: they may only shrink.
local QALLOW_UNDOC_CLASS = set({})
local QALLOW_UNDOC_FIELD = set({})
do
  local dlines = {}
  for line in (D .. "\n"):gmatch("([^\n]*)\n") do dlines[#dlines + 1] = line end

  -- A description is a `---` line carrying prose rather than another tag.
  -- Walk up over the annotation lines a class may already have above it.
  local function described_above(i)
    local j = i - 1
    while j >= 1 and dlines[j]:match("^%-%-%-") do
      local body = dlines[j]:match("^%-%-%-%s*(.*)$")
      if body ~= "" and not body:match("^@") then return true end
      j = j - 1
    end
    return false
  end

  for i, line in ipairs(dlines) do
    local cls = line:match("^%-%-%-@class%s+([%w_.]+)")
    if cls and not described_above(i) then
      if not QALLOW_UNDOC_CLASS[cls] then
        fail("line " .. i .. ": ---@class " .. cls .. " has no description; " ..
          "add a `--- <what it is>` line above it (downstreams re-export " ..
          "this type and inherit its docs)")
      end
    end
    -- `---@field <name> <type>` with nothing after the type.
    local fname = line:match("^%-%-%-@field%s+([%w_]+)%s+%S+%s*$")
    if fname then
      -- attribute it to the class it belongs to, for a stable allowlist key
      local owner = "?"
      for j = i - 1, 1, -1 do
        local c = dlines[j]:match("^%-%-%-@class%s+([%w_.]+)")
        if c then owner = c break end
        if not dlines[j]:match("^%-%-%-") then break end
      end
      local disp = owner .. "." .. fname
      if not QALLOW_UNDOC_FIELD[disp] then
        fail("line " .. i .. ": ---@field " .. disp .. " has no description; " ..
          "describe it after the type")
      end
    end
  end
end

local function ratchet(viol, allow, label)
  for _, disp in ipairs(sorted_keys(viol)) do
    if not allow[disp] then
      fail("annotation quality [" .. label .. "]: " .. disp ..
        " (fix the annotation, or seed the QALLOW list)")
    end
  end
  for _, disp in ipairs(sorted_keys(allow)) do
    if not viol[disp] then
      fail("stale quality allowlist entry [" .. label ..
        "] (now clean, remove it): " .. disp)
    end
  end
end
ratchet(qvio.param, QALLOW_PARAM, "declared param without @param")
ratchet(qvio.noreturn, QALLOW_NORETURN, "no @return/@overload")
ratchet(qvio.inline, QALLOW_INLINE, "inline { } table type")
ratchet(qvio.bare, QALLOW_BARE, "bare any/table type")
ratchet(qvio.consttype, QALLOW_CONSTTYPE, "constant not declared integer")

-- Q6 is not a plain name ratchet: QALLOW_NOSUCCESS exempts a binding only
-- when its block's first `---@return` line still reads the exact text it
-- was seeded with, so a mutation that drops the real success line --
-- StreamReader:read and :read_until dropping their `chunk`/`data` line,
-- leaving only a differently-named `string?` line -- or that swaps its
-- text for a fabricated line sharing the same type token while leaving
-- the line count unchanged, still reports by name even though the name
-- stays in the allowlist.
local function ratchet_nosuccess(viol, lines, allow, label)
  for _, disp in ipairs(sorted_keys(viol)) do
    local want_line = allow[disp]
    if not want_line then
      fail("annotation quality [" .. label .. "]: " .. disp ..
        " (fix the annotation, or seed the QALLOW list)")
    elseif want_line ~= lines[disp] then
      fail("annotation quality [" .. label .. "]: " .. disp ..
        " (allowlisted for a specific @return head line, but its block's " ..
        "first @return line now reads " .. tostring(lines[disp]) .. " -- " ..
        "the success slot may have been lost or swapped; fix the " ..
        "annotation or reseed the QALLOW head line)")
    end
  end
  for _, disp in ipairs(sorted_keys(allow)) do
    if not viol[disp] then
      fail("stale quality allowlist entry [" .. label ..
        "] (now clean, remove it): " .. disp)
    end
  end
end
ratchet_nosuccess(qvio.nosuccess, qvio.nosuccess_lines, QALLOW_NOSUCCESS,
  "first @return is the failure tail (lost success slot)")

ratchet(arity_vio, ARITY_ALLOW, "annotation declares returns the C never pushes")

assert(#failures == 0,
  "definitions.lua coverage failures (annotate the binding or fix the " ..
  "annotation; only shrink the allowlist):\n  " ..
  table.concat(failures, "\n  "))

local qallowed = count(QALLOW_PARAM) + count(QALLOW_NORETURN) +
  count(QALLOW_INLINE) + count(QALLOW_BARE) + count(QALLOW_CONSTTYPE) +
  count(QALLOW_NOSUCCESS)
print("definitions coverage: " .. nfns .. " functions, " .. nmethods ..
  " methods, " .. nconsts .. " constants checked across " ..
  #MODULES .. " modules; " .. count(ALLOW) .. " allowlisted")
print("annotation quality: " .. #qdecls .. " declarations checked; " ..
  qallowed .. " quality-allowlisted (shrink-only)")
print("return arity: " .. arity_checked .. " bindings checked against the C; "
  .. #ARITY_SKIPPED .. " arity not statically readable; " ..
  count(ARITY_ALLOW) .. " allowlisted (shrink-only)")
print("test_definitions_coverage: PASS")
