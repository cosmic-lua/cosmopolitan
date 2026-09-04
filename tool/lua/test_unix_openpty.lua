-- Copyright 2026 Will Maier
--
-- Permission to use, copy, modify, and/or distribute this software for
-- any purpose with or without fee is hereby granted, provided that the
-- above copyright notice and this permission notice appear in all copies.
--
-- THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
-- WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
-- WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
-- AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
-- DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR
-- PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
-- TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
-- PERFORMANCE OF THIS SOFTWARE.

-- Pins unix.openpty()'s declared shape: exactly 3 values on success
-- (mfd, sfd, name) and exactly 3 on failure (nil, error, errno) — not
-- 5 distinct fixed slots. Slots 2 and 3 double as the error string and
-- errno on failure, the same way the declared `sfd` and `name` slots
-- carry `mfd`/`sfd`/`name` on success.

local unix = require("cosmo.unix")

assert(type(unix.openpty) == "function", "openpty should be a function")

-- Success shape: openpty() with no fd pressure should return exactly
-- mfd, sfd, name.
local packed = table.pack(unix.openpty())

if packed.n == 3 and packed[1] == nil then
  -- Not supported on this platform (Windows, bare metal): returns
  -- nil, error, errno, per the doc comment. Nothing further to probe.
  print("openpty unsupported here: " .. tostring(packed[2]))
else
  assert(packed.n == 3, "openpty success should return exactly 3 values, got " .. packed.n)
  local mfd, sfd, name = packed[1], packed[2], packed[3]
  assert(type(mfd) == "number", "mfd should be a number")
  assert(type(sfd) == "number", "sfd should be a number")
  assert(type(name) == "string" and #name > 0, "name should be a non-empty string")
  unix.close(mfd)
  unix.close(sfd)

  -- Failure shape: exhaust the process's file descriptor budget so the
  -- next openpty() call fails with EMFILE, and confirm the error
  -- string lands in the slot declared `sfd` and the errno lands in the
  -- slot declared `name` — not in slots of their own.
  if unix.RLIMIT_NOFILE and unix.getrlimit and unix.setrlimit then
    -- getrlimit's success value is one unix.Rlimit table ({soft=, hard=}),
    -- not two positional integers -- slot 2 always means error, on either
    -- branch.
    local old_limit = unix.getrlimit(unix.RLIMIT_NOFILE)
    if old_limit then
      assert(type(old_limit) == "table", "getrlimit success should return a table")
      local old_soft, old_hard = old_limit.soft, old_limit.hard
      assert(unix.setrlimit(unix.RLIMIT_NOFILE, 0, old_hard))
      local fpacked = table.pack(unix.openpty())
      assert(unix.setrlimit(unix.RLIMIT_NOFILE, old_soft, old_hard))

      assert(fpacked.n == 3, "openpty failure should return exactly 3 values, got " .. fpacked.n)
      assert(fpacked[1] == nil, "openpty failure's 1st value should be nil")
      assert(type(fpacked[2]) == "string",
        "openpty failure's 2nd value (declared sfd) should carry the error string, got " ..
        type(fpacked[2]))
      assert(type(fpacked[3]) == "number",
        "openpty failure's 3rd value (declared name) should carry the errno, got " ..
        type(fpacked[3]))
    else
      print("skipping openpty failure-shape probe: could not read RLIMIT_NOFILE")
    end
  else
    print("skipping openpty failure-shape probe: rlimit API unavailable")
  end
end

-- getrlimit's own contract: slot 2 always means error, regardless of
-- branch. Success bundles soft/hard into one unix.Rlimit table (never
-- a bare integer that could be confused with the error string); an
-- invalid resource constant still returns the clean 3-value failure
-- tuple.
if unix.RLIMIT_NOFILE and unix.getrlimit then
  local limit = unix.getrlimit(unix.RLIMIT_NOFILE)
  assert(type(limit) == "table",
    "getrlimit success should return a unix.Rlimit table, got " .. type(limit))
  assert(type(limit.soft) == "number" and type(limit.hard) == "number",
    "unix.Rlimit should carry numeric soft/hard fields")

  local packed = table.pack(unix.getrlimit(-1))
  assert(packed.n == 3, "getrlimit failure should return exactly 3 values, got " .. packed.n)
  assert(packed[1] == nil, "getrlimit failure's 1st value should be nil")
  assert(type(packed[2]) == "string",
    "getrlimit failure's 2nd value should be the error string, got " .. type(packed[2]))
  assert(type(packed[3]) == "number",
    "getrlimit failure's 3rd value should be the errno, got " .. type(packed[3]))
end

-- pipe's own contract: slot 2 always means error, regardless of
-- branch. Success bundles the two positional fds into one unix.Pipe
-- table (never a bare integer that could be confused with the error
-- string, the deviation this test pins); fd exhaustion still returns
-- the clean 3-value failure tuple.
do
  local pipe = assert(unix.pipe())
  assert(type(pipe) == "table",
    "pipe success should return a unix.Pipe table, got " .. type(pipe))
  assert(type(pipe.reader) == "number" and type(pipe.writer) == "number",
    "unix.Pipe should carry numeric reader/writer fields")
  unix.close(pipe.reader)
  unix.close(pipe.writer)

  if unix.RLIMIT_NOFILE and unix.getrlimit and unix.setrlimit then
    local old_limit = unix.getrlimit(unix.RLIMIT_NOFILE)
    if old_limit then
      assert(unix.setrlimit(unix.RLIMIT_NOFILE, 0, old_limit.hard))
      local packed = table.pack(unix.pipe())
      assert(unix.setrlimit(unix.RLIMIT_NOFILE, old_limit.soft, old_limit.hard))

      assert(packed.n == 3, "pipe failure should return exactly 3 values, got " .. packed.n)
      assert(packed[1] == nil, "pipe failure's 1st value should be nil")
      assert(type(packed[2]) == "string",
        "pipe failure's 2nd value should be the error string, got " .. type(packed[2]))
      assert(type(packed[3]) == "number",
        "pipe failure's 3rd value should be the errno, got " .. type(packed[3]))
    else
      print("skipping pipe failure-shape probe: could not read RLIMIT_NOFILE")
    end
  else
    print("skipping pipe failure-shape probe: rlimit API unavailable")
  end
end

print("all openpty tests passed")
