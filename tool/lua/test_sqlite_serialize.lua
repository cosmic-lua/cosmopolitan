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

-- an empty in-memory database (no CREATE TABLE at all) must not crash the
-- process. sqlite3_serialize() may hand back either nil or a valid string
-- for a schema this bare; either is acceptable so long as it doesn't segv.
local empty = sqlite3.open_memory()
local edata = empty:serialize()
assert(edata == nil or type(edata) == "string")
if edata ~= nil then
  assert(edata:sub(1, 16) == "SQLite format 3\0")
end

-- a populated database must serialize to a non-empty, well-formed buffer.
local db = assert(sqlite3.open_memory())
assert(db:exec("create table foo(a integer, b text)") == 0)
assert(db:exec("insert into foo values (1, 'hello')") == 0)
assert(db:exec("insert into foo values (2, 'world')") == 0)

local data, err = db:serialize()
assert(type(data) == "string", "expected a string, got: " .. tostring(err))
assert(#data > 0)
-- a plausible size: at least one SQLite page (the smallest page size is 512).
assert(#data >= 512, "implausibly small serialization: " .. #data .. " bytes")
-- every well-formed SQLite file starts with this 16-byte magic header.
assert(data:sub(1, 16) == "SQLite format 3\0")

-- round-trip through deserialize into a fresh database.
local restored = sqlite3.open_memory()
assert(restored:deserialize(data) == nil)

local rows = {}
for row in restored:nrows("select a, b from foo order by a") do
  rows[#rows + 1] = row
end
assert(#rows == 2)
assert(rows[1].a == 1 and rows[1].b == "hello")
assert(rows[2].a == 2 and rows[2].b == "world")
