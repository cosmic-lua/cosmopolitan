-- Tests for the re module's error-convention redesign (issue #151, item 2):
-- captures returned as a table, a no-match reported as a bare nil, errors as
-- strings, and the re.Errno userdata deleted.
--
-- re.Regex:search, re.Regex:match (the same C function), and module-level
-- re.search all bundle a match's substring and captures into one
-- re.SearchMatch table (fields "match" and "captures") instead of two
-- positional returns,
-- so no slot ever does double duty between a match's captures and a
-- failure's error string: slot 1 is always the value-or-nil, slot 2 is
-- always absent or the error string.
local re = require("cosmo.re")

-- compile returns a usable regex object
local rx = assert(re.compile("([0-9]+)-([0-9]+)"))
assert(type(rx) == "userdata", "compiled regex should be userdata")

-- match: one re.SearchMatch table with the whole matched substring and a
-- table of capture groups
local r = rx:search("abc 12-345 xyz")
assert(type(r) == "table", "a match must return one table, got " .. type(r))
assert(r.match == "12-345", "match should be the whole matched substring, got: " ..
  tostring(r.match))
assert(type(r.captures) == "table",
  "captures should be a table, got: " .. type(r.captures))
assert(r.captures[1] == "12", "first capture, got: " .. tostring(r.captures[1]))
assert(r.captures[2] == "345", "second capture, got: " .. tostring(r.captures[2]))
assert(r.captures[3] == nil, "no third capture")

-- a match returns exactly one value: nothing rides in slot 2 alongside it,
-- so a caller can never confuse a match's payload with an error string
assert(select("#", rx:search("abc 12-345 xyz")) == 1,
  "a match must return exactly one value")

-- no-match: exactly one return value, and it is nil. Today's bug was that a
-- no-match returned a *truthy* re.Errno, so `if err then` treated every
-- non-match as an error.
assert(select("#", rx:search("no digits here")) == 1,
  "no-match must return exactly one value")
assert((rx:search("no digits here")) == nil, "no-match must return nil")

-- captures is an empty table (not nil) when the pattern has no groups
local rx2 = assert(re.compile("foo"))
local r2 = rx2:search("a foo b")
assert(r2.match == "foo", "match without groups")
assert(type(r2.captures) == "table" and #r2.captures == 0,
  "captures is an empty table when the pattern has no groups")

-- an unmatched optional group is represented as "" so captures stays {string}
local opt = assert(re.compile("(a)(b)?"))
local oresult = opt:search("a")
assert(oresult.match == "a", "optional-group whole match")
assert(oresult.captures[1] == "a", "participating group 1")
assert(oresult.captures[2] == "", "non-participating optional group -> empty string")

-- compile error: nil + string (no re.Errno userdata)
local bad, err = re.compile("(")
assert(bad == nil, "bad pattern compiles to nil")
assert(type(err) == "string", "compile error must be a string, got: " ..
  type(err))
assert(#err > 0, "compile error string is non-empty")

-- module-level re.search convenience obeys the same contract: one
-- re.SearchMatch table on a match
local sr = re.search("(a+)(b+)", "xxaaabbyy")
assert(type(sr) == "table", "re.search must return one table on a match")
assert(sr.match == "aaabb", "re.search whole match")
assert(sr.captures[1] == "aaa" and sr.captures[2] == "bb", "re.search captures")
assert(select("#", re.search("(a+)(b+)", "xxaaabbyy")) == 1,
  "re.search match returns exactly one value")
assert((re.search("z+", "nothing here")) == nil, "re.search no-match is nil")
assert(select("#", re.search("z+", "nothing here")) == 1,
  "re.search no-match returns a single nil")

-- re.search surfaces a bad pattern as nil, string too -- this is the one
-- reachable "engine failure" path for the family: a bad pattern is
-- (re-)compiled on every re.search call, so unlike the already-compiled
-- Regex methods below, a malformed pattern reaches this call every time.
local sb, serr = re.search("(", "whatever")
assert(sb == nil, "re.search bad pattern -> nil in slot 1")
assert(type(serr) == "string", "re.search bad pattern -> string in slot 2")
assert(select("#", re.search("(", "whatever")) == 2,
  "re.search failure returns exactly two values")

-- the re.Errno type is gone entirely
assert(re.Errno == nil, "re.Errno must be removed")

-- flags still work: ICASE compile flag
local ci = assert(re.compile("hello", re.ICASE))
assert(ci:search("XX HELLO XX").match == "HELLO", "ICASE flag")

-- NOTBOL search flag: ^ must not match the beginning of the subject
local anchored = assert(re.compile("^abc"))
assert(anchored:search("abc").match == "abc", "anchored pattern matches at start")
assert((anchored:search("abc", re.NOTBOL)) == nil,
  "NOTBOL suppresses ^ at the start of the subject")

-- NOSUB compile flag reports success with an empty match string
local ns = assert(re.compile("abc", re.NOSUB))
local nr = ns:search("xx abc yy")
assert(nr.match == "" and type(nr.captures) == "table",
  "NOSUB reports a match as an empty string")
assert((ns:search("nope")) == nil, "NOSUB no-match is nil")

-- :find reports absolute 1-based inclusive offsets plus captures,
-- bundled into one re.Match table so slot 2 is never anything but an
-- error string or absent (the same shape as unix.nanosleep's
-- remainder table)
local fx = assert(re.compile("([0-9]+)-([0-9]+)"))
local fm = fx:find("abc 12-345 xyz")
assert(type(fm) == "table", "find match should be a table, got: " .. type(fm))
assert(fm.start == 5 and fm.stop == 10, "find offsets, got: " ..
  tostring(fm.start) .. "," .. tostring(fm.stop))
assert(("abc 12-345 xyz"):sub(fm.start, fm.stop) == "12-345",
  "offsets slice back to the matched text")
assert(fm.captures[1] == "12" and fm.captures[2] == "345", "find captures")

-- :find no-match is a single bare nil, like :search
assert(select("#", fx:find("no digits")) == 1,
  "find no-match returns exactly one value")
assert((fx:find("no digits")) == nil, "find no-match is nil")

-- :find's engine-failure branch shares LuaReReturnError with
-- re.compile's error path (already exercised above: a malformed
-- pattern fails to compile as nil, string), so :find can never reach
-- a live regex_t that then errors out of regexec() for a reason a
-- test can force deterministically; what this capture guarantees is
-- that IF that branch runs, slot 2 holds only a string, never mixed
-- with the integer-offset success shape -- confirmed structurally by
-- fm.start/fm.stop above living on the match table, not in slot 2

-- init advances the search; offsets stay absolute
local m2 = fx:find("1-2 33-44", 0, 4)
assert(m2.start == 5 and m2.stop == 9, "find with init reports absolute offsets, got: " ..
  tostring(m2.start) .. "," .. tostring(m2.stop))

-- iterating by advancing init past each match finds every match
local subject = "a1-2b345-6c7-89d"
local starts = {}
local pos = 1
while true do
  local match = fx:find(subject, 0, pos)
  if not match then break end
  starts[#starts + 1] = subject:sub(match.start, match.stop)
  pos = match.stop + 1
end
assert(#starts == 3 and starts[1] == "1-2" and starts[2] == "345-6" and
  starts[3] == "7-89", "find-driven iteration collects every match")

-- init past the end reports no match; init below 1 is clamped
assert((fx:find("1-2", 0, 99)) == nil, "init past the end is a no-match")
assert((fx:find("1-2", 0, -5)) ~= nil, "negative init clamps to 1")

-- a non-participating optional group is "" through :find too
local om = opt:find("a")
assert(om.start == 1 and om.stop == 1 and om.captures[1] == "a" and
  om.captures[2] == "", "find optional-group captures")

-- ^ anchoring interacts with init the documented way: the tail is the
-- subject, so ^ matches at init unless NOTBOL is passed
local fanch = assert(re.compile("^abc"))
assert(fanch:find("xxabc", 0, 3).start == 3, "^ matches at init by default")
assert((fanch:find("xxabc", re.NOTBOL, 3)) == nil,
  "NOTBOL suppresses ^ at init")

-- :match is :search under the verb the operation performs, so a
-- downstream that reserves `match` tree-wide can name the method
-- directly instead of wrapping it. Same function, same returns: one
-- re.SearchMatch table on a match, sharing no slot with the error string.
local mre = assert(re.compile("(a+)(b+)"))
local mr = mre:match("xxaabbyy")
local sr2 = mre:search("xxaabbyy")
assert(mr.match == sr2.match, "match returns what search returns, got " ..
  tostring(mr.match))
assert(mr.captures[1] == sr2.captures[1] and mr.captures[2] == sr2.captures[2],
  "captures agree")
assert(mre:match("zzz") == nil, "a no-match is a bare nil, as with search")
assert(select("#", mre:match("xxaabbyy")) == 1,
  "match returns exactly one value on a match")

print("test_re: PASS")
