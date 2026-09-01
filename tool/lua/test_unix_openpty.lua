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
    local old_soft, old_hard = unix.getrlimit(unix.RLIMIT_NOFILE)
    if old_soft then
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

print("all openpty tests passed")
