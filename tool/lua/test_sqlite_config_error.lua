-- Copyright 2026 Justine Alexandra Roberts Tunney
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

local sqlite3 = require("cosmo.lsqlite3")

local function check_error_tuple(rc, errmsg, errcode, label)
  assert(rc == nil, label .. ": expected nil rc, got: " .. tostring(rc))
  assert(type(errmsg) == "string" and #errmsg > 0,
    label .. ": expected a non-empty string error message in slot 2, got: " ..
    tostring(errmsg) .. " (" .. type(errmsg) .. ")")
  assert(type(errcode) == "number",
    label .. ": expected a numeric error code in slot 3, got: " ..
    tostring(errcode) .. " (" .. type(errcode) .. ")")
end

-- an option value outside the four documented CONFIG_* constants must
-- fail with the string error message in slot 2 and the numeric SQLite
-- result code in slot 3 -- the fallible tuple's conventional shape
-- (value|nil, err, errno?), not a bare integer with no message.
local rc, errmsg, errcode = sqlite3.config(999999)
check_error_tuple(rc, errmsg, errcode, "invalid option")

-- a documented, valid option can still fail at the sqlite3_config()
-- level -- e.g. changing the threading mode after SQLite has already
-- initialized (which open_memory() below triggers) is refused by
-- SQLite itself. That environmental failure must carry the same
-- string-message shape, not a bare integer.
sqlite3.open_memory()
rc, errmsg, errcode = sqlite3.config(sqlite3.CONFIG_SINGLETHREAD)
check_error_tuple(rc, errmsg, errcode, "already-initialized")
