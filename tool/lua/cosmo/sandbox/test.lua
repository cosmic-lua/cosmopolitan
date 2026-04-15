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
assertf(type(unix.mount)   == "function", "unix.mount missing")
assertf(type(unix.unmount) == "function", "unix.unmount missing")
assertf(type(unix.pivot_root) == "function", "unix.pivot_root missing")
assertf(type(unix.prctl)   == "function", "unix.prctl missing")
assertf(type(unix.capget)  == "function", "unix.capget missing")
assertf(type(unix.capset)  == "function", "unix.capset missing")

-- SIOC/IFF constants are present.
assertf(unix.IFNAMSIZ == 16, "IFNAMSIZ expected 16, got %s",
        tostring(unix.IFNAMSIZ))
assertf(unix.IFF_UP == 1, "IFF_UP expected 1, got %s",
        tostring(unix.IFF_UP))
assertf(type(unix.SIOCGIFFLAGS) == "number", "SIOCGIFFLAGS missing")
assertf(type(unix.SIOCSIFFLAGS) == "number", "SIOCSIFFLAGS missing")

-- MS_* mount-flag constants.
assertf(unix.MS_RDONLY == 1, "MS_RDONLY expected 1, got %s",
        tostring(unix.MS_RDONLY))
assertf(type(unix.MS_BIND) == "number", "MS_BIND missing")
assertf(type(unix.MS_REC) == "number", "MS_REC missing")
assertf(type(unix.MS_PRIVATE) == "number", "MS_PRIVATE missing")
assertf(type(unix.MS_SLAVE) == "number", "MS_SLAVE missing")

-- PR_* prctl constants.
assertf(unix.PR_SET_PDEATHSIG == 1, "PR_SET_PDEATHSIG expected 1, got %s",
        tostring(unix.PR_SET_PDEATHSIG))
assertf(unix.PR_SET_NO_NEW_PRIVS == 38, "PR_SET_NO_NEW_PRIVS expected 38")
assertf(unix.PR_SET_DUMPABLE == 4, "PR_SET_DUMPABLE expected 4")

-- CAP_* constants (well-known indices).
assertf(unix.CAP_CHOWN          == 0,  "CAP_CHOWN")
assertf(unix.CAP_SETUID         == 7,  "CAP_SETUID")
assertf(unix.CAP_NET_ADMIN      == 12, "CAP_NET_ADMIN")
assertf(unix.CAP_SYS_ADMIN      == 21, "CAP_SYS_ADMIN")
assertf(unix.CAP_NET_BIND_SERVICE == 10, "CAP_NET_BIND_SERVICE")
assertf(type(unix.CAP_LAST_CAP) == "number", "CAP_LAST_CAP missing")

-- capget should always work when called for self, even unprivileged.
do
  local eff, perm, inh = unix.capget()
  assertf(type(eff)  == "number", "capget eff not int")
  assertf(type(perm) == "number", "capget perm not int")
  assertf(type(inh)  == "number", "capget inh not int")
  -- effective is always a subset of permitted.
  assertf((eff & ~perm) == 0,
          "effective has bits not in permitted: eff=%x perm=%x", eff, perm)
end

-- capset with the current values (a no-op) should succeed.
do
  local eff, perm, inh = assert(unix.capget())
  local ok, err = unix.capset(eff, perm, inh)
  assertf(ok, "capset(self) failed: %s", tostring(err))
end

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

-- unmount on a path that isn't a mount point fails cleanly.
do
  local ok, err = unix.unmount("/does/not/exist", 0)
  assertf(ok == nil, "unmount of bogus path should fail")
  assertf(type(err:errno()) == "number", "unmount errno missing")
end

-- mount with nil/nil/nil just defers to the kernel; on a bogus target
-- it must fail, not crash.
do
  local ok, err = unix.mount(nil, "/does/not/exist", nil, 0, nil)
  assertf(ok == nil, "mount of bogus target should fail")
  assertf(type(err:errno()) == "number", "mount errno missing")
end

-- prctl(PR_GET_PDEATHSIG, &buf) is the classic reader; we use the simpler
-- form that returns the value via the syscall's return-in-ax fallback,
-- so instead probe a bogus option.
do
  local ok, err = unix.prctl(-999, 0)
  assertf(ok == nil, "prctl(-999) should fail")
  assertf(err:errno() == unix.EINVAL,
          "prctl(-999) expected EINVAL, got %s", err:name())
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
