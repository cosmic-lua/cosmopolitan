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
print("test_srcs_scan: PASS")
