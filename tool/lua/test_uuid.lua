-- Tests for cosmo.UuidV4 / cosmo.UuidV7.
--
-- These UUIDs are routinely used as unguessable tokens, so the bits that are
-- meant to be random must come from a cryptographic source (arc4random), not
-- from the rdtsc+pid seed of _rand64(). The fork-uniqueness tripwire below is
-- the regression guard: two processes that fork at nearly the same instant
-- share rdtsc+pid entropy, so a predictable generator would hand them
-- overlapping UUID streams. With a CSPRNG the streams stay disjoint.

local cosmo = require("cosmo")
local unix = require("cosmo.unix")

local HEX = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

local function check_format(u, ver)
  assert(type(u) == "string", "uuid must be a string, got " .. type(u))
  assert(#u == 36, "uuid must be 36 chars, got " .. #u .. ": " .. tostring(u))
  assert(u:match(HEX), "uuid must be canonical hyphenated hex: " .. u)
  assert(u:sub(15, 15) == ver, "version nibble should be " .. ver .. ": " .. u)
  assert(u:sub(20, 20):match("[89ab]"),
    "variant nibble should be one of 8/9/a/b: " .. u)
end

check_format(cosmo.UuidV4(), "4")
check_format(cosmo.UuidV7(), "7")

-- Single-process uniqueness sanity for both versions.
for _, gen in ipairs({cosmo.UuidV4, cosmo.UuidV7}) do
  local seen = {}
  for _ = 1, 1000 do
    local u = gen()
    check_format(u, u:sub(15, 15))
    assert(not seen[u], "duplicate uuid within one process: " .. u)
    seen[u] = true
  end
end

-- Fork-uniqueness tripwire: 1000 UUIDs split across parent and child must all
-- be distinct. A seed drawn only from rdtsc+pid would collide here.
local N = 500
local pipe = assert(unix.pipe())
local r, w = pipe.reader, pipe.writer
local pid = assert(unix.fork())
if pid == 0 then
  unix.close(r)
  local buf = {}
  for i = 1, N do buf[i] = cosmo.UuidV4() end
  local s = table.concat(buf)  -- fixed 36-byte records
  local off = 0
  while off < #s do
    local n = assert(unix.write(w, s:sub(off + 1)))
    off = off + n
  end
  unix.close(w)
  unix.exit(0)
else
  unix.close(w)
  local set, total = {}, 0
  for _ = 1, N do
    local u = cosmo.UuidV4()
    assert(not set[u], "duplicate uuid in parent: " .. u)
    set[u] = true
    total = total + 1
  end
  local chunks = {}
  while true do
    local chunk = assert(unix.read(r, 65536))
    if #chunk == 0 then break end
    chunks[#chunks + 1] = chunk
  end
  unix.close(r)
  local data = table.concat(chunks)
  assert(#data == N * 36,
    "expected " .. (N * 36) .. " bytes from child, got " .. #data)
  for i = 1, N do
    local u = data:sub((i - 1) * 36 + 1, i * 36)
    assert(not set[u],
      "child uuid collided with parent (predictable seed?): " .. u)
    set[u] = true
    total = total + 1
  end
  -- wait's success value is one unix.WaitResult table ({pid=, wstatus=,
  -- rusage=}), not positional values -- slot 2 always means error.
  local result = assert(unix.wait(pid))
  assert(result.pid == pid, "wait should reap our child")
  assert(unix.WIFEXITED(result.wstatus) and unix.WEXITSTATUS(result.wstatus) == 0,
    "child should exit 0")
  assert(total == 2 * N,
    "all " .. (2 * N) .. " uuids across parent/child must be distinct, got " ..
    total)
end

print("PASS")
