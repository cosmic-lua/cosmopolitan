-- Tests for Slurp/Barf (issue #151, item 6): the error string names the path,
-- and Barf takes an options table {mode, append, offset} instead of the old
-- positional flags footgun (where an explicit 0 was needed to avoid O_TRUNC).
local cosmo = require("cosmo")
local unix = require("cosmo.unix")

local dir = assert(unix.mkdtemp((os.getenv("TMPDIR") or "/tmp") .. "/barf_XXXXXX"))
local path = dir .. "/f.txt"

-- basic write + read round-trip
assert(cosmo.Barf(path, "abc123") == true, "Barf returns true")
assert(cosmo.Slurp(path) == "abc123", "Slurp round-trips")

-- the default truncates (replaces the whole file), it does not append
assert(cosmo.Barf(path, "xy"))
assert(cosmo.Slurp(path) == "xy", "default Barf truncates")

-- append option
assert(cosmo.Barf(path, "AB"))
assert(cosmo.Barf(path, "CD", { append = true }))
assert(cosmo.Slurp(path) == "ABCD", "append option appends")

-- offset overwrites a slice in place (1-indexed) without truncating
assert(cosmo.Barf(path, "abc123"))
assert(cosmo.Barf(path, "XX", { offset = 3 }))
assert(cosmo.Slurp(path, 1, 6) == "abXX23", "offset overwrites a slice in place")

-- append + offset together is a programmer error (raises)
assert(not pcall(function()
  cosmo.Barf(path, "z", { append = true, offset = 2 })
end), "append with offset raises")

-- the error string names the path: Slurp of a missing file
local miss = dir .. "/nope.txt"
local d, err, errno = cosmo.Slurp(miss)
assert(d == nil, "Slurp of a missing file returns nil")
assert(type(err) == "string" and err:find(miss, 1, true),
  "error string contains the path: " .. tostring(err))
assert(err:find("open") and err:find("ENOENT"),
  "error names the call and errno: " .. err)
assert(errno == unix.ENOENT, "third value is the integer errno")
assert(select("#", cosmo.Slurp(miss)) == 3, "three return values")

-- Barf's error names the path too (writing to a directory fails with EISDIR)
local bd, berr, berrno = cosmo.Barf(dir, "data")
assert(bd == nil, "Barf to a directory returns nil")
assert(type(berr) == "string" and berr:find(dir, 1, true),
  "Barf error contains the path: " .. tostring(berr))
assert(math.type(berrno) == "integer", "Barf error errno is an integer")

unix.unlink(path)
unix.rmdir(dir)
print("test_slurp_barf: PASS")
