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
--
-- db:register_extension() must tell apart the three outcomes a caller
-- building a fat binary needs to distinguish: it registered the
-- extension just now, the extension was already present (a compile-time
-- feature such as FTS5, or one a prior call already registered), or
-- this build does not carry it at all. Collapsing any two of these
-- into the same return would defeat the whole point of the binding.

local sqlite3 = require("cosmo.lsqlite3")

local function has_module(db, name)
  for row in db:nrows(
      "SELECT name FROM pragma_module_list WHERE name = '" .. name .. "'") do
    if row.name == name then return true end
  end
  return false
end

-- outcome 1: registered -- "regexp" is in the linked registry
-- (third_party/sqlite3/extensions.c) but nothing registers it by
-- default, so a fresh connection does not have it until asked. regexp's
-- init registers SQL FUNCTIONS ("regexp", "regexpi", ...), not a virtual
-- table module, so presence is checked functionally here rather than
-- through pragma_module_list (which only sees modules).
do
  local db = assert(sqlite3.open_memory())
  local ok = pcall(function()
    for _ in db:nrows("SELECT 'abc' REGEXP 'a.c' AS m") do end
  end)
  assert(not ok, "regexp should not work before it is registered")

  local status, errmsg, errcode = db:register_extension("regexp")
  assert(status == "registered",
    "expected 'registered', got: " .. tostring(status) ..
    " " .. tostring(errmsg) .. " " .. tostring(errcode))
  assert(errmsg == nil and errcode == nil)

  -- exercise it, so "registered" really means usable, not just claimed
  for row in db:nrows("SELECT 'abc' REGEXP 'a.c' AS m") do
    assert(row.m == 1, "the regexp module should now work")
  end
  assert(db:close())
end

-- a second call with the SAME name on the SAME connection must report
-- "present", not silently rerun the extension's init -- this is the
-- part that pragma_module_list-based presence detection gets wrong for
-- regexp and series, since neither's init installs a SQL module named
-- after its registry key (regexp installs functions, no module at
-- all; series's module is "generate_series"), so pragma_module_list
-- never shows a "regexp" or "series" row for either to match against.
do
  local db = assert(sqlite3.open_memory())

  local status1 = assert(db:register_extension("regexp"))
  assert(status1 == "registered",
    "first regexp call: expected 'registered', got: " .. tostring(status1))
  local status2, errmsg2, errcode2 = db:register_extension("regexp")
  assert(status2 == "present",
    "second regexp call on the same connection: expected 'present', got: " ..
    tostring(status2))
  assert(errmsg2 == nil and errcode2 == nil)

  assert(db:close())
end

do
  local db = assert(sqlite3.open_memory())

  local status1 = assert(db:register_extension("series"))
  assert(status1 == "registered",
    "first series call: expected 'registered', got: " .. tostring(status1))
  local status2, errmsg2, errcode2 = db:register_extension("series")
  assert(status2 == "present",
    "second series call on the same connection: expected 'present', got: " ..
    tostring(status2))
  assert(errmsg2 == nil and errcode2 == nil)

  -- a fresh connection starts over: tracking is per-connection, not global
  local db2 = assert(sqlite3.open_memory())
  local fresh_status = assert(db2:register_extension("series"))
  assert(fresh_status == "registered",
    "a fresh connection should not inherit another connection's " ..
    "registration, got: " .. tostring(fresh_status))
  assert(db2:close())

  assert(db:close())
end

-- outcome 2a: already present as a compile-time feature -- FTS5 is
-- compiled into libsqlite3.a (SQLITE_ENABLE_FTS5) and auto-registers on
-- every connection at open, without going through the extensions
-- registry or db:register_extension() at all.
do
  local db = assert(sqlite3.open_memory())
  assert(has_module(db, "fts5"),
    "fts5 should already be a module on every connection (compiled in)")
  local status, errmsg, errcode = db:register_extension("fts5")
  assert(status == "present",
    "expected 'present' for fts5, got: " .. tostring(status) ..
    " " .. tostring(errmsg) .. " " .. tostring(errcode))
  assert(errmsg == nil and errcode == nil)
  assert(db:close())
end

-- outcome 2b: already present because the open path's own default
-- registration already put it there -- lsqlite3_open unconditionally
-- calls sqlite3_zipfile_init on every connection (tool/net/lsqlite3.c),
-- so asking for "zipfile" on a freshly opened connection must report
-- "present" immediately, with nothing left for register_extension to do.
do
  local db = assert(sqlite3.open_memory())
  assert(has_module(db, "zipfile"),
    "zipfile should already be registered by the open path")
  local status, errmsg, errcode = db:register_extension("zipfile")
  assert(status == "present",
    "expected 'present' for zipfile, got: " .. tostring(status) ..
    " " .. tostring(errmsg) .. " " .. tostring(errcode))
  assert(errmsg == nil and errcode == nil)
  assert(db:close())
end

-- outcome 3: not available -- a name that is neither an already-present
-- module nor a row in the linked registry must fail loudly, in the
-- fallible tuple's conventional shape (nil, string message, integer
-- code), with lsqlite3.NOTFOUND as the code so a caller can branch on
-- "this build doesn't have it" without string-matching the message.
do
  local db = assert(sqlite3.open_memory())
  local status, errmsg, errcode =
    db:register_extension("no_such_extension_at_all")
  assert(status == nil,
    "expected nil for an unknown extension, got: " .. tostring(status))
  assert(type(errmsg) == "string" and errmsg:find("no_such_extension_at_all", 1, true),
    "expected an error message naming the extension, got: " ..
    tostring(errmsg))
  assert(errcode == sqlite3.NOTFOUND,
    "expected lsqlite3.NOTFOUND, got: " .. tostring(errcode))
  assert(db:close())
end

-- lsqlite3.extensions() enumerates the same registry
-- db:register_extension() draws on, so a caller can discover what this
-- build carries instead of guessing from a version number.
do
  local names = sqlite3.extensions()
  assert(type(names) == "table")
  local set = {}
  for _, n in ipairs(names) do set[n] = true end
  assert(set.regexp, "regexp should be listed")
  assert(set.series, "series should be listed")
  assert(set.zipfile, "zipfile should be listed")
  assert(not set.fts5,
    "fts5 is a compile-time feature, not a registry row")

  -- every listed name is one db:register_extension() actually accepts
  local db = assert(sqlite3.open_memory())
  for _, name in ipairs(names) do
    local status = assert(db:register_extension(name))
    assert(status == "registered" or status == "present",
      name .. ": " .. tostring(status))
  end
  assert(db:close())
end

print("test_sqlite_register_extension: PASS")
