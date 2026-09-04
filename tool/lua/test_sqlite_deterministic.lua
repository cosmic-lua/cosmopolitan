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

-- A Lua UDF is volatile to SQLite unless the caller declares it
-- deterministic. SQLite refuses a volatile function in an index on an
-- expression and in a partial index predicate; a deterministic one is
-- accepted there and the index is used.

local sqlite3 = require("cosmo.lsqlite3")

local function twice(ctx, n)
  ctx:result_number(n * 2)
end

local function fresh_db()
  local db = assert(sqlite3.open_memory())
  assert(db:exec([[
    CREATE TABLE t(a INTEGER);
    INSERT INTO t VALUES(1),(2),(3),(4);
  ]]) == sqlite3.OK)
  return db
end

local NONDET = "non%-deterministic functions prohibited"

-- ===== default is volatile: refused in an index on an expression =====
do
  local db = fresh_db()
  assert(db:create_function("twice", 1, twice) == true)
  assert(db:exec("CREATE INDEX i ON t(twice(a))") ~= sqlite3.OK)
  assert(db:errmsg():find(NONDET), db:errmsg())
  assert(db:exec("CREATE INDEX p ON t(a) WHERE twice(a) > 4") ~= sqlite3.OK)
  assert(db:errmsg():find(NONDET), db:errmsg())
  -- still callable as an ordinary function
  local got = {}
  for v in db:urows("SELECT twice(a) FROM t ORDER BY a") do got[#got + 1] = v end
  assert(#got == 4 and got[1] == 2 and got[4] == 8)
  db:close()
end

-- ===== explicit false is the same as the default =====
do
  local db = fresh_db()
  assert(db:create_function("twice", 1, twice, nil, false) == true)
  assert(db:exec("CREATE INDEX i ON t(twice(a))") ~= sqlite3.OK)
  assert(db:errmsg():find(NONDET), db:errmsg())
  db:close()
end

-- ===== deterministic: usable in an index on an expression =====
do
  local db = fresh_db()
  assert(db:create_function("twice", 1, twice, nil, true) == true)
  assert(db:exec("CREATE INDEX i ON t(twice(a))") == sqlite3.OK, db:errmsg())
  assert(db:exec("CREATE INDEX p ON t(a) WHERE twice(a) > 4") == sqlite3.OK,
    db:errmsg())
  -- the planner picks the expression index for a lookup on twice(a)
  local plan = {}
  for row in db:nrows("EXPLAIN QUERY PLAN SELECT a FROM t WHERE twice(a) = 6") do
    plan[#plan + 1] = row.detail
  end
  local uses_index = false
  for _, d in ipairs(plan) do
    if d:find("INDEX i") then uses_index = true end
  end
  assert(uses_index, table.concat(plan, "\n"))
  -- and the answer through the index is right
  local got = {}
  for v in db:urows("SELECT a FROM t WHERE twice(a) = 6") do got[#got + 1] = v end
  assert(#got == 1 and got[1] == 3, tostring(got[1]))
  -- the index survives new rows: the function is called to maintain it
  assert(db:exec("INSERT INTO t VALUES(5)") == sqlite3.OK, db:errmsg())
  got = {}
  for v in db:urows("SELECT a FROM t WHERE twice(a) = 10") do got[#got + 1] = v end
  assert(#got == 1 and got[1] == 5, tostring(got[1]))
  db:close()
end

-- ===== user data slot is unchanged by the flag =====
do
  local db = fresh_db()
  local ud = {tag = "ud"}
  local seen
  assert(db:create_function("peek", 1, function(ctx, n)
    seen = ctx:user_data()
    ctx:result_number(n)
  end, ud, true) == true)
  assert(db:exec("CREATE INDEX i ON t(peek(a))") == sqlite3.OK, db:errmsg())
  for _ in db:urows("SELECT peek(a) FROM t") do end
  assert(seen == ud)
  db:close()
end

-- ===== aggregates take the flag too =====
do
  local db = fresh_db()
  local sum = 0
  local function step(_, n) sum = sum + n end
  local function final(ctx)
    ctx:result_number(sum)
    sum = 0
  end
  assert(db:create_aggregate("mysum", 1, step, final, nil, true) == true)
  local got
  for v in db:urows("SELECT mysum(a) FROM t") do got = v end
  assert(got == 10, tostring(got))
  assert(db:create_aggregate("mysum2", 1, step, final) == true)
  for v in db:urows("SELECT mysum2(a) FROM t") do got = v end
  assert(got == 10, tostring(got))
  db:close()
end

-- ===== anything but a boolean in the flag slot is an argument error =====
do
  local db = fresh_db()
  local ok, err = pcall(db.create_function, db, "bad", 1, twice, nil, "yes")
  assert(not ok and err:find("boolean expected"), tostring(err))
  ok, err = pcall(db.create_function, db, "bad", 1, twice, nil, 1)
  assert(not ok and err:find("boolean expected"), tostring(err))
  ok, err = pcall(db.create_aggregate, db, "bad", 1, twice, twice, nil, "yes")
  assert(not ok and err:find("boolean expected"), tostring(err))
  db:close()
end
