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
-- Session/changeset/rebaser support is compiled out (tool/net/BUILD.mk no
-- longer defines SQLITE_ENABLE_SESSION), so strip those #ifdef blocks before
-- scanning: the seslib/reblib/itrlib tables, the dblib session methods, and
-- the CHANGESET_* constants they guard are not part of the shipped surface.
local C_sqlite = (slurp("tool/net/lsqlite3.c")
  :gsub("#ifdef SQLITE_ENABLE_SESSION.-\n#endif\n", ""))
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
--   union    := postfix ('|' postfix)*
--   postfix  := atom ('?' | '[]')*
--   atom     := 'fun' '(' ... ')' (':' labeled-typelist)?
--             | '{' ... '}'                  -- balance-checked table shape
--             | '(' union ')'
--             | '"'str'"' | "'"str"'" | int  -- literal types
--             | dotted-ident ('<' typelist '>')?
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

  local function parse_typelist(s)
    s = parse_union(s)
    if not s then return nil end
    while s:match("^%s*,") do
      s = s:gsub("^%s*,%s*", "")
      s = parse_union(s)
      if not s then return nil end
    end
    return s
  end

  -- A fun(...) return-list entry may carry a `label:` prefix
  -- (`fun(fd: integer): flags: integer`).
  local function parse_labeled_union(s)
    s = s:gsub("^%s+", "")
    local label = s:match("^[%a_][%w_%.]*%s*:%s*")
    if label then
      local rest = parse_union(s:sub(#label + 1))
      if rest then return rest end
    end
    return parse_union(s)
  end

  local function parse_labeled_typelist(s)
    s = parse_labeled_union(s)
    if not s then return nil end
    while s:match("^%s*,") do
      s = s:gsub("^%s*,%s*", "")
      s = parse_labeled_union(s)
      if not s then return nil end
    end
    return s
  end

  -- fun(...) with balanced parens (parameter internals are not typechecked
  -- here); after the closing paren an optional `: <labeled typelist>` or
  -- typed-vararg (`: ...: string`) return annotation.
  local function parse_fun(s)
    local depth = 0
    for k = 4, #s do
      local c = s:sub(k, k)
      if c == "(" then
        depth = depth + 1
      elseif c == ")" then
        depth = depth - 1
        if depth == 0 then
          local rest = s:sub(k + 1)
          local colon = rest:match("^%??%s*:%s*")
          if colon then
            rest = rest:sub(#colon + 1)
            if rest:match("^%.%.%.") then
              rest = rest:sub(4)
              local c2 = rest:match("^:%s*")
              if c2 then return parse_union(rest:sub(#c2 + 1)) end
              return rest
            end
            return parse_labeled_typelist(rest)
          end
          return rest
        end
      end
    end
    return nil -- unbalanced
  end

  local function parse_atom(s)
    if s == "" then return nil end
    if s:match("^fun%(") then return parse_fun(s) end
    if s:match('^"') then
      local lit = s:match('^"[^"]*"')
      return lit and s:sub(#lit + 1) or nil
    end
    if s:match("^'") then
      local lit = s:match("^'[^']*'")
      return lit and s:sub(#lit + 1) or nil
    end
    if s:match("^%(") then
      local rest = parse_union(s:sub(2))
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

  local function parse_postfix(s)
    s = parse_atom(s)
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

  parse_union = function(s)
    s = s:gsub("^%s+", "")
    s = parse_postfix(s)
    if not s then return nil end
    while s:match("^%s*|%s*[^%s]") do
      s = s:gsub("^%s*|%s*", "")
      s = parse_postfix(s)
      if not s then return nil end
    end
    return s
  end

  -- A type region is well-formed iff a full type expression parses off its
  -- head and ends at a clean boundary: end of line, whitespace (a name or
  -- description follows), or `#` (LuaLS description marker). A comma directly
  -- after the first type (`nil, string, integer`) is NOT a clean boundary:
  -- multi-value returns must be one `---@return` line per value.
  local function type_ok(region)
    if region:match("^%.%.%.") then return true end -- bare variadic
    local rest = parse_union(region)
    if not rest then return false end
    return rest == "" or rest:match("^[%s#]") ~= nil
  end

  local lineno = 0
  for line in (D .. "\n"):gmatch("([^\n]*)\n") do
    lineno = lineno + 1
    local region = line:match("^%-%-%-@param%s+[%w_%.]+%??%s+(.+)$") or
      line:match("^%-%-%-@return%s+(.+)$") or
      line:match("^%-%-%-@field%s+[%w_%.]+%??%s+(.+)$") or
      line:match("^%-%-%-@overload%s+(.+)$") or
      line:match("^%s*%-%-%-@type%s+(.+)$")
    if region and not type_ok(region) then
      fail("line " .. lineno .. ": unparseable type expression (one " ..
        "`---@return` line per value; see the grammar in check 9): " .. line)
    end
  end
end

-- ===== annotation quality ratchet (shrink-only allowlists) =====
--
-- The checks above enforce that every binding is annotated at all. These four
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
-- Each QALLOW_* is a RATCHET seeded at today's counts: an entry may only be
-- removed (by improving the annotation), never added. A newly-violating
-- binding, or a stale entry that no longer violates, fails this test.

local QALLOW_PARAM = set({
  "cosmo.EncodeLua",
  "lsqlite3.Context:result_error",
  "lsqlite3.Context:set_aggregate_data",
  "lsqlite3.Statement:get_name",
  "lsqlite3.Statement:get_type",
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
  "lsqlite3.Database:exec",
  "lsqlite3.Database:interrupt",
  "lsqlite3.Database:rollback_hook",
  "lsqlite3.Database:update_hook",
  "lsqlite3.Database:wal_hook",
  "lsqlite3.Statement:reset",
  "repl.start",
  "unix.Dir:rewind",
  "unix.Memory:store",
  "unix.Memory:write",
  "unix.Sigset:add",
  "unix.Sigset:clear",
  "unix.Sigset:fill",
  "unix.Sigset:remove",
  "unix.exit",
  "unix.sched_yield",
  "unix.sync",
  "unix.syslog",
  "unix.verynice",
  "zip.Appender:close",
  "zip.Reader:close",
  "zip.Writer:close",
})

local QALLOW_INLINE = set({
  "cosmo.ParseParams",
  "lsqlite3.VM:nrows",
  "unix.poll",
  "unix.siocgifconf",
  "unix.uname",
})

local QALLOW_BARE = set({
  "lsqlite3.Context:get_aggregate_data",
  "lsqlite3.Context:user_data",
  "lsqlite3.Database:create_aggregate",
  "lsqlite3.Database:create_function",
  "lsqlite3.Statement:bind_names",
  "lsqlite3.Statement:bind_parameter_count",
  "lsqlite3.Statement:data",
  "lsqlite3.Statement:get_name",
  "lsqlite3.Statement:get_named_types",
  "lsqlite3.Statement:get_named_values",
  "lsqlite3.Statement:get_type",
  "lsqlite3.Statement:get_types",
  "lsqlite3.Statement:get_unames",
  "lsqlite3.Statement:get_utypes",
  "lsqlite3.Statement:get_uvalues",
  "lsqlite3.Statement:get_value",
  "lsqlite3.Statement:get_values",
  "lsqlite3.Statement:idata",
  "lsqlite3.Statement:itypes",
  "lsqlite3.Statement:last_insert_rowid",
  "lsqlite3.Statement:type",
  "lsqlite3.config",
  "unix.fcntl",
})

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

local qvio = { param = {}, noreturn = {}, inline = {}, bare = {} }
for _, d in ipairs(qdecls) do
  for p in (d.params .. ","):gmatch("%s*([^,]-)%s*,") do
    p = p:gsub("%s", "")
    if p ~= "" and p ~= "self" and p ~= "..." then
      if not d.block:find("%-%-%-@param%s+" .. p .. "%f[%W]") then
        qvio.param[d.disp] = true
      end
    end
  end
  if not (d.block:find("%-%-%-@return") or d.block:find("%-%-%-@overload")) then
    qvio.noreturn[d.disp] = true
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

assert(#failures == 0,
  "definitions.lua coverage failures (annotate the binding or fix the " ..
  "annotation; only shrink the allowlist):\n  " ..
  table.concat(failures, "\n  "))

local qallowed = count(QALLOW_PARAM) + count(QALLOW_NORETURN) +
  count(QALLOW_INLINE) + count(QALLOW_BARE)
print("definitions coverage: " .. nfns .. " functions, " .. nmethods ..
  " methods, " .. nconsts .. " constants checked across " ..
  #MODULES .. " modules; " .. count(ALLOW) .. " allowlisted")
print("annotation quality: " .. #qdecls .. " declarations checked; " ..
  qallowed .. " quality-allowlisted (shrink-only)")
print("test_definitions_coverage: PASS")
