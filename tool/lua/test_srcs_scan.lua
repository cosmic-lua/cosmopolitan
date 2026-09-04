-- Dependency-scan gate for the sources behind the lua binary.
--
-- o/$(MODE)/depend -- the header edges make consults before reusing an
-- object -- is what tool/build/mkdeps writes after scanning exactly the
-- files listed in o/$(MODE)/srcs.txt: the root SRCS aggregate, the union
-- of every package's <PKG>_SRCS. The pattern rule compiles any .c, so a
-- source that a package's SRCS filters out while some object list still
-- links it builds fine; it is just never scanned, and every header and
-- .inc it includes can change without its object being rebuilt. This
-- test reads srcs.txt and asserts that every .c under tool/net,
-- tool/lua and third_party/lua/cosmo that this build compiled appears
-- in it, naming each path that does not.
--
-- "Compiled by this build" is read off the output tree: a .c whose
-- o/$(MODE)/<path>.o exists was built by some rule, so it is exactly a
-- file whose edges matter. A .c with no object is skipped, so a source
-- nothing builds cannot fail the gate.
--
-- A source being scanned is not the same as ITS OBJECT carrying edges:
-- mkdeps derives an object's path purely from its source's own path
-- (the source's directory, extension swapped for .o), so a rule that
-- compiles a source into some OTHER directory -- an explicit
-- cross-directory rule, the shape `o/$(MODE)/tool/lua/lua.main.o:
-- third_party/lua/cosmo/lua.main.c` -- lands its edges at the path
-- mkdeps derived from the source, not at the path the rule actually
-- writes. The object tool/lua/lua links has none, and reuses stale
-- content on a header edit, even though the source was scanned fine.
-- The second half of this file catches that: it reads every such
-- explicit rule out of tool/lua/BUILD.mk and asserts its target has a
-- depend block of its own, naming the object path that does not.
--
-- Usage: lua.dbg tool/lua/test_srcs_scan.lua [o/$(MODE)/srcs.txt]
-- Without the argument the path is derived from $MODE, which make
-- exports, so the coverage pass -- which runs every test bare -- checks
-- the same file. The output root is the directory holding srcs.txt.

local unix = require("cosmo.unix")

local DIRS = { "tool/net", "tool/lua", "third_party/lua/cosmo" }

local srcs_path = arg[1] or ("o/" .. (os.getenv("MODE") or "") .. "/srcs.txt")
local outroot = assert(srcs_path:match("^(.*/)[^/]+$"),
  "srcs.txt path must carry its directory: " .. srcs_path)

local function slurp(path)
  local f = assert(io.open(path, "r"), "cannot open " .. path)
  local s = f:read("*a")
  f:close()
  return s
end

-- srcs.txt is one make $(file) write of $(SRCS): whitespace-separated.
local listed = {}
local nlisted = 0
for word in slurp(srcs_path):gmatch("%S+") do
  listed[word] = true
  nlisted = nlisted + 1
end
assert(nlisted > 0, srcs_path .. " lists no sources")

local function exists(path)
  return unix.stat(path) ~= nil
end

local function c_files(dir)
  local d = assert(unix.opendir(dir), "cannot open directory " .. dir)
  local names = {}
  while true do
    local name = d:read()
    if name == nil then
      break
    end
    if name:sub(-2) == ".c" then
      names[#names + 1] = dir .. "/" .. name
    end
  end
  d:close()
  table.sort(names)
  return names
end

local checked = 0
local missing = {}
for _, dir in ipairs(DIRS) do
  for _, src in ipairs(c_files(dir)) do
    local obj = outroot .. src:sub(1, -3) .. ".o"
    if exists(obj) then
      checked = checked + 1
      if not listed[src] then
        missing[#missing + 1] = src
      end
    end
  end
end

assert(checked > 0, "no compiled .c found under " .. outroot ..
  " for " .. table.concat(DIRS, ", ") .. " (run after the lua binary is built)")

assert(#missing == 0,
  "compiled but absent from " .. srcs_path .. ", so mkdeps never scans " ..
  "them and " .. outroot .. "depend carries no edges for their objects " ..
  "(a package's SRCS filters them out; list them in a <PKG>_SRCS):\n  " ..
  table.concat(missing, "\n  "))

print("srcs scan: " .. checked .. " compiled sources under " ..
  table.concat(DIRS, ", ") .. " are listed in " .. srcs_path)

-- Explicit cross-directory compile rules: an object's edges, direct or
-- aliased.
--
-- An explicit rule of the shape `o/$(MODE)/<target>.o: <source>.c`,
-- immediately followed by a tab-indented recipe line, compiles that
-- source under a directory the pattern rule would not have chosen on
-- its own (the source's directory swapped for the target's). Such a
-- rule's target is exactly what mkdeps cannot have derived edges for
-- unless the target path happens to equal the source's own -- so every
-- one found in tool/lua/BUILD.mk must resolve to a depend block, either
-- its own or, when the mkdeps-derived path is already claimed by some
-- other rule compiling the same source with different flags, an
-- explicit alias: a second, recipe-less `<target>.o: <other>.o` line
-- for the same target naming the object whose edges it borrows. A
-- prerequisite-only line with no attached recipe that is not this
-- `.o: .o` alias shape (e.g. a .zip.o's private-flags or ordering
-- declaration) is neither a compile rule nor an alias, and is skipped.

local BUILD_MK = "tool/lua/BUILD.mk"

local physical = {}
for line in (slurp(BUILD_MK) .. "\n"):gmatch("(.-)\r?\n") do
  physical[#physical + 1] = line
end

local MODE_PREFIX = "o/$(MODE)/"
local ESCAPED_PREFIX = MODE_PREFIX:gsub("%p", "%%%1")
local OBJ = "[%w_%./%-]+%.o"

local explicit_rules = {}
local aliases = {} -- target object -> list of objects it borrows edges from
for i = 1, #physical do
  local target, source = physical[i]:match(
    "^" .. ESCAPED_PREFIX .. "(" .. OBJ .. "):%s+([%w_%./%-]+%.c)%s*$")
  if target and physical[i + 1] and physical[i + 1]:sub(1, 1) == "\t" then
    explicit_rules[#explicit_rules + 1] =
      { object = target, source = source, line = i }
  else
    local alias_target, alias_source = physical[i]:match(
      "^" .. ESCAPED_PREFIX .. "(" .. OBJ .. "):%s+" ..
      ESCAPED_PREFIX .. "(" .. OBJ .. ")%s*$")
    if alias_target then
      aliases[alias_target] = aliases[alias_target] or {}
      table.insert(aliases[alias_target], alias_source)
    end
  end
end

assert(#explicit_rules > 0,
  "no explicit `" .. MODE_PREFIX .. "<target>.o: <source>.c` compile rule " ..
  "found in " .. BUILD_MK .. " (the parser no longer matches the file's " ..
  "shape -- if the file truly has none left, this check should retire)")

local depend_path = outroot .. "depend"
local depend = slurp(depend_path)

-- depend is megabytes; a pattern search re-tries its backtracking
-- engine at every byte position, which is fine at native speed but
-- blows well past --ftrace's traced-call cap (coverage.lua). A plain
-- (literal, non-pattern) search stays cheap under that instrumentation,
-- so the target is matched as a literal substring instead: every block
-- opens at the start of a line, so the needle is the object path
-- preceded by a newline and followed by the literal `: ` mkdeps writes.
local function has_depend_block(object)
  local needle = "\n" .. outroot .. object .. ": "
  return depend:find(needle, 1, true) ~= nil
end

-- Resolves one object to true the moment its own block or some alias'
-- (transitively) does; visited guards against an alias cycle.
local function has_edges(object, visited)
  if has_depend_block(object) then
    return true
  end
  visited = visited or {}
  if visited[object] then
    return false
  end
  visited[object] = true
  for _, other in ipairs(aliases[object] or {}) do
    if has_edges(other, visited) then
      return true
    end
  end
  return false
end

local no_edges = {}
for _, rule in ipairs(explicit_rules) do
  if not has_edges(rule.object) then
    no_edges[#no_edges + 1] = outroot .. rule.object .. " (" .. BUILD_MK ..
      ":" .. rule.line .. ", compiled from " .. rule.source .. ")"
  end
end

assert(#no_edges == 0,
  "compiled at a path mkdeps does not derive, with no alias onto an " ..
  "object that has one, so " .. depend_path .. " carries no edges (direct " ..
  "or aliased) for it and a header edit reuses the stale object (compile " ..
  "it at the path mkdeps derives instead, or add a `<target>.o: <other>.o` " ..
  "alias line naming an object that has real edges):\n  " ..
  table.concat(no_edges, "\n  "))

print("srcs scan: " .. #explicit_rules .. " explicit compile rule(s) in " ..
  BUILD_MK .. " resolve to a " .. depend_path .. " block, direct or aliased")
print("test_srcs_scan: PASS")
