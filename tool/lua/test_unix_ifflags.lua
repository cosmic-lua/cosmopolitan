-- Tests for unix.siocgifflags / unix.siocsifflags: the SIOCGIFFLAGS /
-- SIOCSIFFLAGS ifreq ioctls with the struct ifreq ABI in C, so Lua
-- callers pass interface names and flag integers instead of
-- hand-packing kernel structs with string.pack.

local unix = require("unix")

assert(type(unix.siocgifflags) == "function", "siocgifflags should exist")
assert(type(unix.siocsifflags) == "function", "siocsifflags should exist")

-- An over-long interface name (>= IFNAMSIZ = 16 bytes) is rejected up
-- front with EINVAL, before any socket or ioctl work. Deterministic on
-- every host, no interfaces needed.
local longname = string.rep("x", 16)
local flags, err, errno = unix.siocgifflags(longname)
assert(flags == nil, "over-long name must fail")
assert(errno == unix.EINVAL, "expected EINVAL, got: " .. tostring(err))

local ok, serr, serrno = unix.siocsifflags(longname, 0)
assert(ok == nil, "over-long name must fail")
assert(serrno == unix.EINVAL, "expected EINVAL, got: " .. tostring(serr))

-- A name one byte under the limit is length-valid; it reaches the
-- kernel and fails with a device error instead (no such interface).
local maxname = string.rep("x", 15)
flags, err, errno = unix.siocgifflags(maxname)
assert(flags == nil, "nonexistent interface must fail")
assert(errno ~= unix.EINVAL,
       "15-byte name must pass validation, got: " .. tostring(err))

-- The rest needs a live loopback interface ("lo" on Linux, "lo0" on
-- the BSDs/macOS). Skip with a note on hosts that expose neither,
-- rather than failing the suite.
local lo, loerr
for _, name in ipairs({"lo", "lo0"}) do
  lo = name
  flags, loerr = unix.siocgifflags(name)
  if flags then break end
end
if not flags then
  print("skipping loopback assertions: " .. tostring(loerr))
  return
end

assert(math.type(flags) == "integer", "flags should be an integer")
assert(flags & unix.IFF_LOOPBACK ~= 0,
       lo .. " should have IFF_LOOPBACK set, got: " .. flags)

-- Writing the exact flags back is a no-op change. Root (or a userns
-- with CAP_NET_ADMIN) succeeds; unprivileged hosts refuse with
-- EPERM/EACCES. Both are correct binding behavior.
ok, serr, serrno = unix.siocsifflags(lo, flags)
if ok then
  local after = assert(unix.siocgifflags(lo))
  assert(after == flags, "flags should be unchanged after no-op write")
else
  assert(serrno == unix.EPERM or serrno == unix.EACCES,
         "expected EPERM/EACCES, got: " .. tostring(serr))
  print("siocsifflags write skipped (unprivileged): " .. tostring(serr))
end

print("ok test_unix_ifflags")
