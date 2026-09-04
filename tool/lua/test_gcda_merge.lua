-- Regression test for the __gcov_write lock (libc/intrin/gcov.c):
-- when N processes race to rewrite the same instrumented object's
-- shared .gcda at exit, the fix's whole-file F_SETLKW lock must make
-- the read-merge-write one critical section, so every process's run
-- is counted and none is dropped.
--
-- This is the exact race make -j puts every instrumented object
-- through: many test processes share one lua.dbg build, and every one
-- of them writes the same .gcda per object at exit. Here N children,
-- each an execve() of this test's own lua.dbg (arg[-1]), stand in for
-- that: forked together, they exit close enough in time to collide on
-- the lock if it did not exist.
--
-- The shared object is tool/net/lfuncs.c as linked into the lua
-- binary: tool/lua/lfuncs3.c #includes it (see tool/lua/BUILD.mk), so
-- gcc's -dumpbase names its .gcda after that translation unit, not
-- lfuncs.c's own directory -- tool/net/lfuncs.o is a separate object
-- for other binaries and is never part of this process at all.
--
-- Run this after gcda.clean like every other cov test, and run it the
-- way the item names -- `make MODE=cov o/cov/tool/lua/test`, with no
-- -j -- so no sibling test process touches this same .gcda while this
-- one runs; the only writers during this test's window are this
-- process itself (if it was not the first cov test to touch lfuncs.c
-- code) and the N children below. That is what makes an exact
-- before/after delta of N meaningful.

local unix = require("cosmo.unix")

local N = 8
local GCDA = "o/cov/tool/lua/lfuncs3.o.gcda"

-- The object-summary record's `runs` word: magic, version, stamp,
-- checksum, tag, len, runs -- seven native-endian int32 words in a
-- row, so `runs` sits at byte offset 24 (__gcov_write, gcov.c).
local function read_runs(path)
  local f = io.open(path, "rb")
  if not f then
    return 0
  end
  local ok = f:seek("set", 24)
  if not ok then
    f:close()
    return 0
  end
  local bytes = f:read(4)
  f:close()
  if not bytes or #bytes < 4 then
    return 0
  end
  return string.unpack("=I4", bytes)
end

local baseline = read_runs(GCDA)

local lua_path = arg[-1]
assert(lua_path, "arg[-1] should be this interpreter's own path")

local pids = {}
for _ = 1, N do
  local pid = assert(unix.fork())
  if pid == 0 then
    local _, xerr = unix.execve(lua_path, {lua_path, "-e", ""})
    io.stderr:write("execve " .. lua_path .. ": " .. tostring(xerr) .. "\n")
    unix.exit(127)
  end
  pids[#pids + 1] = pid
end

for _, pid in ipairs(pids) do
  -- wait's success value is one unix.WaitResult table ({pid=,
  -- wstatus=, rusage=}), not positional values.
  local result = assert(unix.wait(pid))
  assert(unix.WIFEXITED(result.wstatus) and unix.WEXITSTATUS(result.wstatus) == 0,
    "child " .. pid .. " did not exit cleanly: wstatus=" .. tostring(result.wstatus))
end

local after = read_runs(GCDA)
assert(after == baseline + N,
  "runs should be baseline(" .. baseline .. ") + N(" .. N .. ") = " ..
  (baseline + N) .. ", got " .. after ..
  " -- a lost write means the .gcda lock did not hold")

print("PASS")
