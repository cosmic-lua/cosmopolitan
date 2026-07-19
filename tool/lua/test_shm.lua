-- Tests for unix.mapshared / unix.Memory (shared-memory bounds + futex words).
--
-- Regression coverage for three shm safety fixes:
--   1. reading the *entire* region (bytes == size) must succeed, not throw;
--   2. wait() must reject a word whose high 32 bits are set, since the futex
--      only compares the low 32 bits;
--   3. read() copies under the process-shared lock but builds the Lua string
--      after releasing it (exercised indirectly by the round-trip below).

local unix = require("cosmo.unix")

-- (1) off-by-one: a 64-byte map must allow read(0, 64).
local m = assert(unix.mapshared(64))
assert(#m:read(0, 64) == 64, "reading the full 64-byte region should succeed")

-- round-trip a full-width payload through write + read
local payload = ("ABCDEFGH"):rep(8)  -- exactly 64 bytes
assert(#payload == 64)
m:write(0, payload, 64)
assert(m:read(0, 64) == payload, "full-width write/read should round-trip")

-- partial reads within bounds still work
assert(m:read(0, 1) == "A")
assert(m:read(63, 1) == "H")
assert(#m:read(64, 0) == 0, "zero-length read at the end is empty, not an error")

-- genuine out-of-bounds reads are still rejected
assert(not pcall(function() m:read(1, 64) end),
  "read(1, 64) overruns a 64-byte map and must throw")
assert(not pcall(function() m:read(0, 65) end),
  "read(0, 65) is larger than the map and must throw")
assert(not pcall(function() m:read(65, 0) end),
  "offset past the end must throw")

-- (2) 32-bit futex trap: a word with high bits set must be refused by wait,
-- instead of blocking forever because the low 32 bits happen to match expect.
m:store(0, 0x100000001)  -- 2^32 + 1; low 32 bits are 1
assert(m:load(0) == 0x100000001, "store/load should preserve the full 64 bits")
local ok, err = pcall(function() return m:wait(0, 1) end)
assert(not ok, "wait on a word with nonzero high bits must error, not block")
assert(tostring(err):find("32", 1, true),
  "wait error should mention the 32-bit futex-word contract: " .. tostring(err))

-- a well-formed (int32) word that differs from expect returns promptly
-- (EAGAIN on futex platforms, 0 on polyfill platforms) rather than erroring,
-- confirming the normal path still works after the guard.
m:store(0, 0)
local rc, e = m:wait(0, 12345)  -- 0 != 12345, so this never blocks
assert(rc == 0 or (rc == nil and e ~= nil),
  "an int32 word that differs from expect must not error the guard path")


-- unmap: deterministic release instead of waiting on the GC (filed from
-- cosmic #493). Idempotent; every other method on an unmapped object
-- must raise instead of touching freed memory (the process-shared lock
-- lives inside the mapping, so a stale access would use a freed mutex).
local u = assert(unix.mapshared(64))
u:store(0, 7)
assert(u:load(0) == 7)
assert(u:unmap() == true, "first unmap releases the mapping")
assert(u:unmap() == false, "second unmap is a no-op and says so")
assert(not pcall(function() return u:load(0) end), "load after unmap must error")
assert(not pcall(function() return u:store(0, 1) end), "store after unmap must error")
assert(not pcall(function() return u:read(0, 8) end), "read after unmap must error")
assert(not pcall(function() return u:write(0, "x") end), "write after unmap must error")
assert(not pcall(function() return u:wait(0, 0) end), "wait after unmap must error")
assert(not pcall(function() return u:wake(0) end), "wake after unmap must error")
assert(tostring(u):find("unix.Memory", 1, true), "tostring stays safe after unmap")

print("PASS")
