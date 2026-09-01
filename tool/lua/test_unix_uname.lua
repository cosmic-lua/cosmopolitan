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

local unix = require("cosmo.unix")

assert(unix.pledge("stdio"))

local u = assert(unix.uname())
assert(type(u) == "table")

-- Every documented field is present and a string.
for _, field in ipairs({
  "sysname", "nodename", "release", "version", "machine", "domainname"
}) do
  assert(type(u[field]) == "string", "missing field: " .. field)
end

-- The OS name and hardware type are always populated.
assert(#u.sysname > 0)
assert(#u.machine > 0)

-- Calling it twice yields a stable operating-system name.
local u2 = assert(unix.uname())
assert(u2.sysname == u.sysname)

print("All uname tests passed!")
