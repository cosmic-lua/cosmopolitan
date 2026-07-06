-- Tests for the re module's error-convention redesign (issue #151, item 2):
-- captures returned as a table, a no-match reported as a bare nil, errors as
-- strings, and the re.Errno userdata deleted.
local re = require("cosmo.re")

-- compile returns a usable regex object
local rx = assert(re.compile("([0-9]+)-([0-9]+)"))
assert(type(rx) == "userdata", "compiled regex should be userdata")

-- match: whole matched substring + a table of capture groups
local m, caps = rx:search("abc 12-345 xyz")
assert(m == "12-345", "match should be the whole matched substring, got: " ..
  tostring(m))
assert(type(caps) == "table", "captures should be a table, got: " .. type(caps))
assert(caps[1] == "12", "first capture, got: " .. tostring(caps[1]))
assert(caps[2] == "345", "second capture, got: " .. tostring(caps[2]))
assert(caps[3] == nil, "no third capture")

-- no-match: exactly one return value, and it is nil. Today's bug was that a
-- no-match returned a *truthy* re.Errno, so `if err then` treated every
-- non-match as an error.
assert(select("#", rx:search("no digits here")) == 1,
  "no-match must return exactly one value")
assert((rx:search("no digits here")) == nil, "no-match must return nil")

-- captures is an empty table (not nil) when the pattern has no groups
local rx2 = assert(re.compile("foo"))
local m2, caps2 = rx2:search("a foo b")
assert(m2 == "foo", "match without groups")
assert(type(caps2) == "table" and #caps2 == 0,
  "captures is an empty table when the pattern has no groups")

-- an unmatched optional group is represented as "" so captures stays {string}
local opt = assert(re.compile("(a)(b)?"))
local om, ocaps = opt:search("a")
assert(om == "a", "optional-group whole match")
assert(ocaps[1] == "a", "participating group 1")
assert(ocaps[2] == "", "non-participating optional group -> empty string")

-- compile error: nil + string (no re.Errno userdata)
local bad, err = re.compile("(")
assert(bad == nil, "bad pattern compiles to nil")
assert(type(err) == "string", "compile error must be a string, got: " ..
  type(err))
assert(#err > 0, "compile error string is non-empty")

-- module-level re.search convenience obeys the same contract
local sm, scaps = re.search("(a+)(b+)", "xxaaabbyy")
assert(sm == "aaabb", "re.search whole match")
assert(scaps[1] == "aaa" and scaps[2] == "bb", "re.search captures")
assert((re.search("z+", "nothing here")) == nil, "re.search no-match is nil")
assert(select("#", re.search("z+", "nothing here")) == 1,
  "re.search no-match returns a single nil")

-- re.search surfaces a bad pattern as nil, string too
local sb, serr = re.search("(", "whatever")
assert(sb == nil and type(serr) == "string",
  "re.search bad pattern -> nil, string")

-- the re.Errno type is gone entirely
assert(re.Errno == nil, "re.Errno must be removed")

-- flags still work: ICASE compile flag
local ci = assert(re.compile("hello", re.ICASE))
assert(ci:search("XX HELLO XX") == "HELLO", "ICASE flag")

-- NOTBOL search flag: ^ must not match the beginning of the subject
local anchored = assert(re.compile("^abc"))
assert(anchored:search("abc") == "abc", "anchored pattern matches at start")
assert((anchored:search("abc", re.NOTBOL)) == nil,
  "NOTBOL suppresses ^ at the start of the subject")

-- NOSUB compile flag reports success with an empty match string
local ns = assert(re.compile("abc", re.NOSUB))
local nm, ncaps = ns:search("xx abc yy")
assert(nm == "" and type(ncaps) == "table",
  "NOSUB reports a match as an empty string")
assert((ns:search("nope")) == nil, "NOSUB no-match is nil")

print("test_re: PASS")
