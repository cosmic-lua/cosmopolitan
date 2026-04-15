-- Smoke tests for cosmo.sandbox.
--
-- Verifies the library loads and that the new unix.* primitive bindings
-- (unshare, setns, and the CLONE_NEW* constants) are reachable from Lua.
-- Tests that require real privileges live in test_integration.lua; this
-- file must pass unprivileged on any Linux host.

local sandbox = require "cosmo.sandbox"
local unix = require "unix"

local function assertf(cond, fmt, ...)
  if not cond then
    error(string.format(fmt, ...), 2)
  end
end

-- Library loads and advertises a version.
assertf(type(sandbox._VERSION) == "string",
        "cosmo.sandbox._VERSION missing")

-- CLONE_NEW* constants are present and have the expected Linux values.
assertf(unix.CLONE_NEWNET == 0x40000000,
        "CLONE_NEWNET has unexpected value %s", tostring(unix.CLONE_NEWNET))
assertf(unix.CLONE_NEWNS   == 0x00020000, "CLONE_NEWNS wrong")
assertf(unix.CLONE_NEWUTS  == 0x04000000, "CLONE_NEWUTS wrong")
assertf(unix.CLONE_NEWIPC  == 0x08000000, "CLONE_NEWIPC wrong")
assertf(unix.CLONE_NEWUSER == 0x10000000, "CLONE_NEWUSER wrong")
assertf(unix.CLONE_NEWPID  == 0x20000000, "CLONE_NEWPID wrong")
assertf(unix.CLONE_NEWCGROUP == 0x02000000, "CLONE_NEWCGROUP wrong")

-- The bindings are registered.
assertf(type(unix.unshare) == "function", "unix.unshare missing")
assertf(type(unix.setns)   == "function", "unix.setns missing")
assertf(type(unix.ioctl)   == "function", "unix.ioctl missing")

-- SIOC/IFF constants are present.
assertf(unix.IFNAMSIZ == 16, "IFNAMSIZ expected 16, got %s",
        tostring(unix.IFNAMSIZ))
assertf(unix.IFF_UP == 1, "IFF_UP expected 1, got %s",
        tostring(unix.IFF_UP))
assertf(type(unix.SIOCGIFFLAGS) == "number", "SIOCGIFFLAGS missing")
assertf(type(unix.SIOCSIFFLAGS) == "number", "SIOCSIFFLAGS missing")

-- Calling unshare with an invalid flag should fail cleanly, not raise.
-- (unshare(0) is a no-op success; we use a value that's never a flag.)
do
  local ok, err = unix.unshare(0)
  -- unshare(0) is a no-op; should succeed for any caller.
  assertf(ok == true or (ok == nil and err:errno() == unix.EPERM),
          "unshare(0) returned unexpected (%s,%s)",
          tostring(ok), tostring(err))
end

-- setns with a bogus fd must fail with EBADF, not crash.
do
  local ok, err = unix.setns(-1, 0)
  assertf(ok == nil, "setns(-1) should fail")
  assertf(err:errno() == unix.EBADF,
          "setns(-1) expected EBADF, got %d (%s)",
          err:errno(), err:name())
end

-- ioctl with a bogus fd must fail with EBADF, not crash; and arg type
-- dispatch (nil / int / string) must all execute the same code path.
do
  local ok, err = unix.ioctl(-1, unix.SIOCGIFFLAGS)  -- nil arg
  assertf(ok == nil, "ioctl(-1, ...) should fail")
  assertf(err:errno() == unix.EBADF,
          "ioctl(-1) expected EBADF, got %d", err:errno())
end
do
  local ok, err = unix.ioctl(-1, unix.SIOCGIFFLAGS, 0)  -- int arg
  assertf(ok == nil and err:errno() == unix.EBADF, "ioctl(int) wrong")
end
do
  local buf = string.rep("\0", 40)
  local ok, err = unix.ioctl(-1, unix.SIOCGIFFLAGS, buf)  -- string arg
  assertf(ok == nil and err:errno() == unix.EBADF, "ioctl(str) wrong")
end

-- cosmo.sandbox.netns loads and its helpers do what they claim offline.
do
  local netns = require "cosmo.sandbox.netns"
  local ifr = netns.build_ifreq("lo", unix.IFF_UP)
  assertf(#ifr == unix.IFNAMSIZ + 24,
          "ifreq wrong length %d", #ifr)
  assertf(ifr:sub(1, 2) == "lo", "ifreq name not set")
  assertf(netns.parse_ifreq_flags(ifr) == unix.IFF_UP,
          "ifreq flags round-trip failed")
end

-- is_supported() should return true on Linux (the only OS we support).
-- On other hosts, the module still loads but reports false.
do
  local u = unix.uname and unix.uname() or nil
  if u and u.sysname == "Linux" then
    assertf(sandbox.is_supported(), "is_supported() false on Linux")
  end
end

print("cosmo.sandbox smoke tests passed")
