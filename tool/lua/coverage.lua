-- Function coverage floor for the Lua binding sources, ratcheted per file.
--
-- The tests under tool/lua exercise the C bindings in tool/net/l*.c,
-- tool/lua/lcosmo.c and third_party/lua/cosmo/lunix.c. This collector
-- runs every enrolled test under `--ftrace`, which logs each C function
-- entry to stderr, and unions the function names it sees; nm's DWARF
-- listing of the test binary says which functions each binding source
-- defines. Per file, `defined` is that set and `covered` is the part of
-- it the tests reached. tool/lua/coverage_floor.lua holds the committed
-- floor -- one entry per binding file that defines a function -- and
-- the gate fails when a file's covered count drops below it, when a
-- floored file no longer defines a function, or when a binding file
-- that defines functions has no floor entry. A run that exceeds the
-- floor passes; `COVERAGE_BASELINE=1` rewrites the floor to what the
-- run measured.
--
-- What is gated is the per-file covered SET, not a whole-log count:
-- the trace's line count and its distinct-name count move between runs
-- by allocator internals, while the set of binding functions the tests
-- reach is stable. Only the set decides.
--
-- The trace never lands on disk. A test's stderr is read through a
-- pipe and reduced to the FUN names as it streams -- a single test's
-- trace can run to gigabytes, and one uncapped log once filled the
-- disk. A test that exceeds TRACE_LINE_CAP FUN lines is killed and
-- fails the run by name, so a newly enrolled test that cannot finish
-- under ftrace stops the gate loudly instead of stalling it.
--
-- Trace line: `FUN <pid> <tid> <ticks> <depth> <name>`; pid and tid
-- carry ANSI colour, so the name is taken as the last whitespace field.
-- Optimizer clones (`db_do_rows.isra.0`, `lsqlite_checkdb.constprop.0`)
-- are folded onto their function on both sides of the intersection.
--
-- Inlining caveat: this runs on the binary the test target already
-- builds, and in the default mode that binary is compiled at -O2, so a
-- function the optimizer inlines at every call site never enters the
-- trace and can never count as covered. `MODE=dbg` is built at -O0 and
-- has no such hole, but its ftrace pass did not finish within ten
-- minutes against a plain test run of twenty seconds, so the default
-- mode is what the floor is measured on. The floor therefore ratchets what is
-- reachable in the trace, and a fully-inlined function stays out of
-- `covered` by construction.
--
-- SKIP lists the enrolled tests that cannot run under --ftrace, each
-- with the measured reason; it only shrinks. Their .ok rules still run
-- them plainly, so nothing they assert is lost -- only the functions
-- that no other test reaches stay out of the floor.
--
-- Usage, as tool/lua/BUILD.mk invokes it:
--
--   lua.dbg tool/lua/coverage.lua <lua.dbg> <nm> <outdir> <floor> <test.lua>...
--
-- The covered set -- one `<file> <function>` per line, sorted -- is
-- written to <outdir>/coverage.txt for inspection. A test that fails
-- under ftrace fails this run with its exit status and the tail of its
-- own stderr; the .ok rules remain the correctness gate.

local unix = require("cosmo.unix")

local lua_dbg, nm, outdir, floor_path = arg[1], arg[2], arg[3], arg[4]
assert(lua_dbg and nm and outdir and floor_path and arg[5],
  "usage: coverage.lua <lua.dbg> <nm> <outdir> <floor> <test.lua>...")

local TRACE_LINE_CAP = 8000000

-- Every test spawned below inherits this: it tells a test that its own
-- --ftrace trace writes are in flight, for the rare case (pledge tests
-- that revoke stdio) where that fact changes what a child may safely do
-- without weakening what the test asserts. See test_unix_misc.lua.
unix.setenv("COVERAGE_FTRACE", "1", true)

local SKIP = {
  ["tool/lua/test_definitions_conformance.lua"] =
    "pure-Lua source parser; every VM-internal C call is traced, ~28 MB/s " ..
    "of trace with no bound in sight (25 GB written without finishing)",
  ["tool/lua/test_definitions_coverage.lua"] =
    "pure-Lua source parser; every VM-internal C call is traced, ~28 MB/s " ..
    "of trace, past 400 MB in 15 s",
  ["tool/lua/test_definitions_help.lua"] =
    "pure-Lua source parser; every VM-internal C call is traced, ~28 MB/s " ..
    "of trace, past 400 MB in 15 s",
}

local tests, skipped = {}, {}
for i = 5, #arg do
  if SKIP[arg[i]] then
    skipped[#skipped + 1] = arg[i]
  else
    tests[#tests + 1] = arg[i]
  end
end

local BINDING_SOURCES = {
  ["tool/lua/lcosmo.c"] = true,
  ["third_party/lua/cosmo/lunix.c"] = true,
}
local function is_binding_source(path)
  return BINDING_SOURCES[path] or path:match("^tool/net/l[^/]*%.c$") ~= nil
end

-- Runs argv with its fd `fd` piped back here, feeding every line to
-- on_line as it streams; on_line returns true to stop reading, which
-- kills the child. Returns true on a clean exit, nil plus a description
-- of how the child ended otherwise.
local function spawn(argv, fd, on_line)
  io.stdout:flush()
  io.stderr:flush()
  local pipe, perr = unix.pipe()
  if pipe == nil then
    return nil, "pipe: " .. tostring(perr)
  end
  local pid, ferr = unix.fork()
  if pid == nil then
    return nil, "fork: " .. tostring(ferr)
  end
  if pid == 0 then
    unix.close(pipe.reader)
    unix.dup(pipe.writer, fd)
    unix.close(pipe.writer)
    local _, xerr = unix.execve(argv[1], argv)
    io.stderr:write("execve " .. argv[1] .. ": " .. tostring(xerr) .. "\n")
    unix.exit(127)
  end
  unix.close(pipe.writer)
  local rest, killed = "", false
  while true do
    local chunk, rerr, errno = unix.read(pipe.reader, 65536)
    if chunk == nil then
      if errno ~= unix.EINTR then
        unix.close(pipe.reader)
        unix.kill(pid, unix.SIGKILL)
        unix.wait(pid)
        return nil, "read: " .. tostring(rerr)
      end
    elseif chunk == "" then
      break
    else
      chunk = rest .. chunk
      local pos = 1
      while true do
        local nl = chunk:find("\n", pos, true)
        if nl == nil then
          break
        end
        if on_line(chunk:sub(pos, nl - 1)) then
          killed = true
          break
        end
        pos = nl + 1
      end
      if killed then
        unix.kill(pid, unix.SIGKILL)
        repeat
          chunk = unix.read(pipe.reader, 65536)
        until chunk == nil or chunk == ""
        break
      end
      rest = chunk:sub(pos)
    end
  end
  if not killed and rest ~= "" then
    on_line(rest)
  end
  unix.close(pipe.reader)
  local _, wstatus = unix.wait(pid)
  if killed then
    return nil, "killed at " .. TRACE_LINE_CAP .. " FUN lines"
  end
  if unix.WIFEXITED(wstatus) then
    local code = unix.WEXITSTATUS(wstatus)
    if code == 0 then
      return true
    end
    return nil, "exit status " .. code
  elseif unix.WIFSIGNALED(wstatus) then
    return nil, "signal " .. unix.WTERMSIG(wstatus)
  end
  return nil, "wait status " .. tostring(wstatus)
end

local function fold_clone(name)
  while true do
    local base = name:match("^(.+)%.isra%.%d+$")
      or name:match("^(.+)%.constprop%.%d+$")
      or name:match("^(.+)%.part%.%d+$")
      or name:match("^(.+)%.cold%.%d+$")
    if base == nil then
      return name
    end
    name = base
  end
end

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

-- 1. ftrace every test; union the FUN names across the traces.
local reached = {}
local fun_lines, distinct = 0, 0
for _, test in ipairs(tests) do
  local test_lines, tail = 0, {}
  local ok, why = spawn({ lua_dbg, "--ftrace", test }, 2, function(line)
    if line:sub(1, 4) == "FUN " then
      fun_lines = fun_lines + 1
      test_lines = test_lines + 1
      local name = fold_clone(line:match("^.*%s(%S+)%s*$"))
      if not reached[name] then
        reached[name] = true
        distinct = distinct + 1
      end
      return test_lines >= TRACE_LINE_CAP
    end
    tail[#tail + 1] = line
    if #tail > 16 then
      table.remove(tail, 1)
    end
    return false
  end)
  if not ok then
    io.stderr:write("coverage: " .. test .. " failed under --ftrace (" ..
      why .. ")\n")
    if #tail > 0 then
      io.stderr:write("  " .. table.concat(tail, "\n  ") .. "\n")
    end
    os.exit(1)
  end
end

-- 2. nm's DWARF listing: which binding file defines each function.
local root = assert(unix.getcwd()) .. "/"
local function normalize(path)
  if path:sub(1, #root) == root then
    path = path:sub(#root + 1)
  end
  path = path:gsub("^<root>/", "")
  path = path:gsub("^%./", ""):gsub("/%./", "/")
  return path
end

local defined = {}
do
  local ok, why = spawn({ nm, "-l", "--defined-only", lua_dbg }, 1,
    function(line)
      local kind, name, path = line:match("^%x+ ([Tt]) (%S+)\t(.-):%d+$")
      if kind then
        path = normalize(path)
        if is_binding_source(path) then
          defined[path] = defined[path] or {}
          defined[path][fold_clone(name)] = true
        end
      end
      return false
    end)
  if not ok then
    io.stderr:write("coverage: " .. nm .. " failed (" .. why .. ")\n")
    os.exit(1)
  end
end

-- 3. Per file: defined, covered, and the covered set for the record.
local measured = {}
local total_defined, total_covered = 0, 0
local record = {}
for _, file in ipairs(sorted_keys(defined)) do
  local n, m = 0, 0
  for _, name in ipairs(sorted_keys(defined[file])) do
    n = n + 1
    if reached[name] then
      m = m + 1
      record[#record + 1] = file .. " " .. name
    end
  end
  measured[file] = { defined = n, covered = m }
  total_defined = total_defined + n
  total_covered = total_covered + m
end

do
  local f = assert(io.open(outdir .. "/coverage.txt", "w"))
  f:write(table.concat(record, "\n"), "\n")
  f:close()
end

-- 4. The floor: rewrite it, or gate on it.
local function write_floor(path)
  local lines = {
    "-- Per-file function coverage floor for the Lua binding sources,",
    "-- measured by tool/lua/coverage.lua from --ftrace traces of the",
    "-- tests tool/lua/BUILD.mk enrols. Rewrite with COVERAGE_BASELINE=1;",
    "-- never lower a covered count by hand.",
    "return {",
  }
  for _, file in ipairs(sorted_keys(measured)) do
    local e = measured[file]
    lines[#lines + 1] = string.format("  [%q] = { defined = %d, covered = %d },",
      file, e.defined, e.covered)
  end
  lines[#lines + 1] = "}"
  local f = assert(io.open(path, "w"))
  f:write(table.concat(lines, "\n"), "\n")
  f:close()
end

local summary = string.format(
  "coverage: %d tests traced, %d skipped (shrink-only), %d FUN lines, " ..
  "%d distinct functions reached; %d/%d binding functions covered across %d files",
  #tests, #skipped, fun_lines, distinct, total_covered, total_defined,
  #sorted_keys(measured))

if os.getenv("COVERAGE_BASELINE") == "1" then
  write_floor(floor_path)
  print(summary)
  print("coverage: floor rewritten to " .. floor_path)
  os.exit(0)
end

local floor = dofile(floor_path)
local failures = {}

print(string.format("%-32s %8s %8s %6s", "file", "defined", "covered", "floor"))
for _, file in ipairs(sorted_keys(measured)) do
  local e, f = measured[file], floor[file]
  print(string.format("%-32s %8d %8d %6s", file, e.defined, e.covered,
    f and tostring(f.covered) or "-"))
  if f == nil then
    failures[#failures + 1] = file .. ": defines " .. e.defined ..
      " functions but has no floor entry; run COVERAGE_BASELINE=1 to add it"
  elseif e.covered < f.covered then
    local missing = {}
    for _, name in ipairs(sorted_keys(defined[file])) do
      if not reached[name] then
        missing[#missing + 1] = name
      end
    end
    failures[#failures + 1] = string.format(
      "%s: covered %d, floor %d; the tests no longer reach one of: %s",
      file, e.covered, f.covered, table.concat(missing, " "))
  end
end
for _, file in ipairs(sorted_keys(floor)) do
  if measured[file] == nil then
    failures[#failures + 1] = file .. ": floored at " .. floor[file].covered ..
      " but defines no function in " .. lua_dbg ..
      "; run COVERAGE_BASELINE=1 if it was removed on purpose"
  end
end

print(summary)
if #failures > 0 then
  io.stderr:write("coverage: FAIL\n  " .. table.concat(failures, "\n  ") .. "\n")
  os.exit(1)
end
print("test_coverage: PASS")
