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

-- BLOB and TEXT both arrive at the Lua value boundary as a plain Lua
-- string, so a value's bytes alone can't tell them apart when a BLOB
-- and a TEXT column (or UDF argument) hold identical bytes.
-- ctx:value_type(n) (UDF arguments) and stmt:column_type(n) (column
-- reads) answer that question by reporting SQLite's own runtime type
-- name -- "integer", "real", "text", "blob", or "null", the same
-- vocabulary SQLite's typeof() SQL function uses -- without changing
-- the shape of any existing value-getting call.

local sqlite3 = require("cosmo.lsqlite3")

local function fresh_db()
  local db = assert(sqlite3.open_memory())
  assert(db:exec("CREATE TABLE t(id INTEGER PRIMARY KEY, data BLOB)")
    == sqlite3.OK)
  return db
end

-- ===== UDF: value_type(n) tells a BLOB argument from TEXT holding the
-- ===== same bytes, and leaves the argument's own value unchanged =====
do
  local db = fresh_db()
  local seen = {}
  assert(db:create_function("probe", 1, function(ctx, v)
    seen[#seen + 1] = ctx:value_type(1)
    ctx:result(v)
  end) == true)

  local stmt = assert(db:prepare("SELECT probe(?)"))
  assert(stmt:bind_blob(1, "AB") == sqlite3.OK)
  assert(stmt:step() == sqlite3.ROW)
  assert(stmt:get_value(0) == "AB", "blob argument's value is unchanged")
  stmt:finalize()

  stmt = assert(db:prepare("SELECT probe(?)"))
  assert(stmt:bind(1, "AB") == sqlite3.OK)
  assert(stmt:step() == sqlite3.ROW)
  assert(stmt:get_value(0) == "AB", "text argument's value is unchanged")
  stmt:finalize()

  assert(seen[1] == "blob", seen[1])
  assert(seen[2] == "text", seen[2])
  db:close()
end

-- ===== UDF: value_type(n) across every SQLite runtime type =====
do
  local db = fresh_db()
  local seen
  assert(db:create_function("probe_type", 1, function(ctx, v)
    seen = ctx:value_type(1)
    ctx:result_null()
  end) == true)

  local cases = {
    {bind = function(s) return s:bind(1, 7) end, want = "integer"},
    {bind = function(s) return s:bind(1, 1.5) end, want = "real"},
    {bind = function(s) return s:bind(1, "hi") end, want = "text"},
    {bind = function(s) return s:bind_blob(1, "hi") end, want = "blob"},
    {bind = function(s) return s:bind(1, nil) end, want = "null"},
  }
  for _, c in ipairs(cases) do
    local stmt = assert(db:prepare("SELECT probe_type(?)"))
    assert(c.bind(stmt) == sqlite3.OK)
    assert(stmt:step() == sqlite3.ROW)
    assert(seen == c.want, c.want .. " got " .. tostring(seen))
    stmt:finalize()
  end
  db:close()
end

-- ===== UDF: value_type(n) argument index is bounds-checked =====
-- (a Lua error raised inside a UDF becomes the statement's error result,
-- not a Lua error raised out of step() -- same as any other UDF error)
do
  local db = fresh_db()
  assert(db:create_function("bad_index", 1, function(ctx, v)
    ctx:value_type(2) -- only one argument was passed
  end) == true)
  local stmt = assert(db:prepare("SELECT bad_index(1)"))
  assert(stmt:step() == sqlite3.ERROR, "out-of-range value_type index should error")
  assert(db:errmsg():find("out of range"), db:errmsg())
  stmt:finalize()
  db:close()
end

-- ===== column reads: column_type(n) tells a BLOB column from TEXT
-- ===== holding the same bytes, distinct from the declared get_type() =====
do
  local db = fresh_db()

  local ins = assert(db:prepare("INSERT INTO t(id, data) VALUES(?, ?)"))
  assert(ins:bind(1, 1) == sqlite3.OK)
  assert(ins:bind_blob(2, "AB") == sqlite3.OK)
  assert(ins:step() == sqlite3.DONE)
  ins:finalize()

  ins = assert(db:prepare("INSERT INTO t(id, data) VALUES(?, ?)"))
  assert(ins:bind(1, 2) == sqlite3.OK)
  assert(ins:bind(2, "AB") == sqlite3.OK)
  assert(ins:step() == sqlite3.DONE)
  ins:finalize()

  local sel = assert(db:prepare("SELECT data FROM t ORDER BY id"))

  assert(sel:step() == sqlite3.ROW)
  assert(sel:column_type(0) == "blob", sel:column_type(0))
  assert(sel:get_type(0) == "BLOB", tostring(sel:get_type(0)))
  assert(sel:get_value(0) == "AB", "blob column's value is unchanged")

  assert(sel:step() == sqlite3.ROW)
  assert(sel:column_type(0) == "text", sel:column_type(0))
  assert(sel:get_type(0) == "BLOB", tostring(sel:get_type(0)))
  assert(sel:get_value(0) == "AB", "text column's value is unchanged")

  sel:finalize()
  db:close()
end

-- ===== column reads: column_type(n) across every SQLite runtime type,
-- ===== including a computed expression with no declared column =====
do
  local db = fresh_db()
  local sel = assert(db:prepare(
    "SELECT 7, 1.5, 'hi', X'6869', NULL"))
  assert(sel:step() == sqlite3.ROW)
  assert(sel:column_type(0) == "integer", sel:column_type(0))
  assert(sel:column_type(1) == "real", sel:column_type(1))
  assert(sel:column_type(2) == "text", sel:column_type(2))
  assert(sel:column_type(3) == "blob", sel:column_type(3))
  assert(sel:column_type(4) == "null", sel:column_type(4))
  sel:finalize()
  db:close()
end

-- ===== column reads: column_type(n) index is bounds-checked =====
do
  local db = fresh_db()
  local sel = assert(db:prepare("SELECT 1"))
  assert(sel:step() == sqlite3.ROW)
  local ok, err = pcall(sel.column_type, sel, 1)
  assert(not ok, "out-of-range column_type index should error")
  sel:finalize()
  db:close()
end
