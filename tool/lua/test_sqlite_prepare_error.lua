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

local db = assert(sqlite3.open_memory())

-- preparing invalid SQL must fail with the string error message in
-- slot 2 and the numeric SQLite result code in slot 3 -- the fallible
-- tuple's conventional shape (value|nil, err, errno?), not a bare
-- integer error code sharing the slot the success path uses for the
-- unparsed SQL tail.
local stmt, errmsg, errcode = db:prepare("NOT VALID SQL")
assert(stmt == nil, "expected nil stmt, got: " .. tostring(stmt))
assert(type(errmsg) == "string" and #errmsg > 0,
  "expected a non-empty string error message in slot 2, got: " ..
  tostring(errmsg) .. " (" .. type(errmsg) .. ")")
assert(type(errcode) == "number",
  "expected a numeric error code in slot 3, got: " ..
  tostring(errcode) .. " (" .. type(errcode) .. ")")

-- the success path is unaffected: slot 2 is still the tail string (the
-- unparsed SQL past the first statement -- empty here, since the whole
-- input is one statement).
local ok_stmt, tail = db:prepare("SELECT 1")
assert(ok_stmt ~= nil, "expected a compiled statement")
assert(tail == "", "expected an empty tail string, got: " .. tostring(tail))
