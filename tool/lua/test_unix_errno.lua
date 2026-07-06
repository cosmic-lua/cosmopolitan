-- Tests for the unix error convention (issue #151, item 1): a failing system
-- call returns nil, err:string, errno:integer, and the unix.Errno userdata is
-- deleted.
local unix = require("cosmo.unix")

-- a failing open returns exactly (nil, string, integer)
local fd, err, errno = unix.open("/nonexistent/path/xyz", unix.O_RDONLY)
assert(fd == nil, "open of a missing file returns nil")
assert(type(err) == "string",
  "second return is an error string, got: " .. type(err))
assert(errno == unix.ENOENT,
  "third return is the integer errno (ENOENT), got: " .. tostring(errno))
assert(select("#", unix.open("/nonexistent/path/xyz", unix.O_RDONLY)) == 3,
  "a failing call returns exactly three values")

-- the error string is human-readable: "open: ENOENT: No such file or directory"
assert(err:find("open"), "error string mentions the call: " .. err)
assert(err:find("ENOENT"), "error string mentions the errno symbol: " .. err)

-- errno is a plain integer usable directly (no :errno() method needed)
assert(math.type(errno) == "integer", "errno is an integer")
local _, _, e2 = unix.open("/nonexistent/path/xyz", unix.O_RDONLY)
assert(e2 == unix.ENOENT and e2 ~= unix.EINTR,
  "errno distinguishes codes without string parsing")

-- the unix.Errno userdata type is gone entirely
assert(unix.Errno == nil, "unix.Errno must be removed")

-- a successful call is unaffected: a single value, no trailing nils
local dirfd = assert(unix.open("/", unix.O_RDONLY))
assert(math.type(dirfd) == "integer", "successful open returns an fd integer")
assert(unix.close(dirfd) == true, "close returns true on success")

print("test_unix_errno: PASS")
