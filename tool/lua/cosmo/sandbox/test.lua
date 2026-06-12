-- Smoke tests for cosmo.sandbox.
--
-- Verifies the library loads and that the new unix.* primitive
-- bindings + the cosmo.sandbox.{netns,fs,proxy} modules are
-- reachable. Tests that need real privileges live in
-- test_integration.lua; this file must pass unprivileged on any host
-- where lua.com runs.

local sandbox = require "cosmo.sandbox"
local cosmo = require "cosmo"
local unix = require "unix"

local function assertf(cond, fmt, ...)
  if not cond then
    error(string.format(fmt, ...), 2)
  end
end

local IS_LINUX = cosmo.GetHostOs() == "LINUX"

-- Library loads and advertises a version.
assertf(type(sandbox._VERSION) == "string",
        "cosmo.sandbox._VERSION missing")
assertf(sandbox.is_supported() == IS_LINUX,
        "is_supported() = %s on host=%s",
        tostring(sandbox.is_supported()), cosmo.GetHostOs())

-- capabilities() returns a fine-grained record; fields all booleans.
do
  local c = sandbox.capabilities()
  assertf(type(c) == "table", "capabilities() did not return table")
  for _, k in ipairs{"linux", "user_ns", "mount_ns", "net_ns",
                     "uts_ns", "pid_ns", "pivot_root",
                     "cap_net_admin", "landlock",
                     "pledge", "unveil"} do
    assertf(type(c[k]) == "boolean",
            "capabilities().%s = %s (expected boolean)", k, tostring(c[k]))
  end
  assertf(c.linux == IS_LINUX, "capabilities().linux mismatch")
  -- pledge / unveil reflect whether the primitive is both exported and
  -- callable on the host. On a Linux host with unix.pledge exported,
  -- the capability must report true (cosmopolitan implements pledge
  -- via seccomp). If unix.pledge is missing, it must report false.
  if IS_LINUX then
    assertf(c.pledge == (unix.pledge ~= nil),
            "capabilities().pledge = %s, expected %s (unix.pledge=%s)",
            tostring(c.pledge), tostring(unix.pledge ~= nil),
            tostring(unix.pledge))
  end
  -- unveil capability must match a live probe: if unix.unveil(nil, nil)
  -- does not return ENOSYS, the primitive is usable and should report
  -- true; otherwise false.
  do
    local want = false
    if unix.unveil then
      local ok, err = unix.unveil(nil, nil)
      if ok then
        want = true
      elseif err and err:errno() ~= unix.ENOSYS then
        want = true
      end
    end
    assertf(c.unveil == want,
            "capabilities().unveil = %s, expected %s",
            tostring(c.unveil), tostring(want))
  end
  -- Result is cached — second call returns the same table.
  assertf(sandbox.capabilities() == c, "capabilities() not cached")
end

-- CLONE_NEW* constants are present and have the expected Linux values.
assertf(unix.CLONE_NEWNET == 0x40000000, "CLONE_NEWNET wrong")
assertf(unix.CLONE_NEWNS   == 0x00020000, "CLONE_NEWNS wrong")
assertf(unix.CLONE_NEWUTS  == 0x04000000, "CLONE_NEWUTS wrong")
assertf(unix.CLONE_NEWIPC  == 0x08000000, "CLONE_NEWIPC wrong")
assertf(unix.CLONE_NEWUSER == 0x10000000, "CLONE_NEWUSER wrong")
assertf(unix.CLONE_NEWPID  == 0x20000000, "CLONE_NEWPID wrong")
assertf(unix.CLONE_NEWCGROUP == 0x02000000, "CLONE_NEWCGROUP wrong")

-- The bindings are registered.
for _, name in ipairs{"unshare", "setns", "ioctl", "mount", "unmount",
                      "pivot_root", "prctl", "capget", "capset",
                      "landlock_create_ruleset", "landlock_add_rule",
                      "landlock_restrict_self",
                      "gethostname", "sethostname"} do
  assertf(type(unix[name]) == "function", "unix.%s missing", name)
end

-- Landlock access-category constants are present.
for _, name in ipairs{"LANDLOCK_ACCESS_FS_EXECUTE",
                      "LANDLOCK_ACCESS_FS_WRITE_FILE",
                      "LANDLOCK_ACCESS_FS_READ_FILE",
                      "LANDLOCK_ACCESS_FS_READ_DIR",
                      "LANDLOCK_ACCESS_FS_REFER",
                      "LANDLOCK_ACCESS_FS_TRUNCATE",
                      "LANDLOCK_RULE_PATH_BENEATH",
                      "LANDLOCK_CREATE_RULESET_VERSION"} do
  assertf(type(unix[name]) == "number", "unix.%s missing", name)
end

-- CLONE_NEWTIME is registered (ABI-visible even when the kernel
-- doesn't support it — fails at unshare() time, not lookup time).
assertf(unix.CLONE_NEWTIME == 0x00000080, "CLONE_NEWTIME expected 0x80")

-- SIOC/IFF constants are present.
assertf(unix.IFNAMSIZ == 16, "IFNAMSIZ expected 16")
assertf(unix.IFF_UP == 1, "IFF_UP expected 1")
assertf(type(unix.SIOCGIFFLAGS) == "number", "SIOCGIFFLAGS missing")
assertf(type(unix.SIOCSIFFLAGS) == "number", "SIOCSIFFLAGS missing")

-- MS_* mount-flag constants.
assertf(unix.MS_RDONLY == 1, "MS_RDONLY expected 1")
for _, name in ipairs{"MS_BIND", "MS_REC", "MS_PRIVATE", "MS_SLAVE",
                      "MS_REMOUNT",
                      "MS_NOSUID", "MS_NODEV", "MS_NOEXEC"} do
  assertf(type(unix[name]) == "number", "%s missing", name)
end

-- MNT_DETACH and friends.
assertf(unix.MNT_DETACH == 2, "MNT_DETACH expected 2 on Linux")
assertf(type(unix.MNT_FORCE) == "number", "MNT_FORCE missing")
assertf(type(unix.UMOUNT_NOFOLLOW) == "number", "UMOUNT_NOFOLLOW missing")

-- PR_* prctl constants.
assertf(unix.PR_SET_PDEATHSIG == 1, "PR_SET_PDEATHSIG expected 1")
assertf(unix.PR_SET_NO_NEW_PRIVS == 38, "PR_SET_NO_NEW_PRIVS expected 38")
assertf(unix.PR_SET_DUMPABLE == 4, "PR_SET_DUMPABLE expected 4")

-- CAP_* constants (well-known indices).
assertf(unix.CAP_CHOWN          == 0,  "CAP_CHOWN")
assertf(unix.CAP_SETUID         == 7,  "CAP_SETUID")
assertf(unix.CAP_NET_ADMIN      == 12, "CAP_NET_ADMIN")
assertf(unix.CAP_SYS_ADMIN      == 21, "CAP_SYS_ADMIN")
assertf(unix.CAP_NET_BIND_SERVICE == 10, "CAP_NET_BIND_SERVICE")
assertf(type(unix.CAP_LAST_CAP) == "number", "CAP_LAST_CAP missing")

-- capget always works for self, even unprivileged.
do
  local eff, perm, inh = unix.capget()
  assertf(type(eff)  == "number", "capget eff not int")
  assertf(type(perm) == "number", "capget perm not int")
  assertf(type(inh)  == "number", "capget inh not int")
  assertf((eff & ~perm) == 0,
          "effective has bits not in permitted: eff=%x perm=%x", eff, perm)
end

-- capset with the current values (no-op) succeeds.
do
  local eff, perm, inh = assert(unix.capget())
  local ok, err = unix.capset(eff, perm, inh)
  assertf(ok, "capset(self) failed: %s", tostring(err))
end

-- unshare(0) is a no-op; should succeed for any caller (or EPERM in
-- the most hardened sandboxes).
do
  local ok, err = unix.unshare(0)
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

-- ioctl with a bogus fd must fail with EBADF, not crash; arg type
-- dispatch (nil / int / string) must all execute the same code path.
for _, arg in ipairs{ {nil}, {0}, {string.rep("\0", 40)} } do
  local ok, err = unix.ioctl(-1, unix.SIOCGIFFLAGS, arg[1])
  assertf(ok == nil and err:errno() == unix.EBADF,
          "ioctl(-1, ..., %s) wrong", type(arg[1]))
end

-- unmount on a non-mountpoint fails cleanly.
do
  local ok, err = unix.unmount("/does/not/exist", 0)
  assertf(ok == nil, "unmount of bogus path should fail")
  assertf(type(err:errno()) == "number", "unmount errno missing")
end

-- mount of a bogus target fails, doesn't crash.
do
  local ok, err = unix.mount(nil, "/does/not/exist", nil, 0, nil)
  assertf(ok == nil, "mount of bogus target should fail")
  assertf(type(err:errno()) == "number", "mount errno missing")
end

-- prctl(-999) → EINVAL.
do
  local ok, err = unix.prctl(-999, 0)
  assertf(ok == nil, "prctl(-999) should fail")
  assertf(err:errno() == unix.EINVAL,
          "prctl(-999) expected EINVAL, got %s", err:name())
end

-- sethostname round-trip / error-shape contract. Setting the hostname
-- requires CAP_SYS_ADMIN in the current UTS namespace, so an unprivileged
-- test caller must see (nil, unix.Errno) — not a crash, not a nil
-- function, not a naked integer. If the caller *is* privileged, the
-- round-trip with the current hostname must succeed.
if IS_LINUX then
  local host = assert(unix.gethostname())
  local ok, err = unix.sethostname(host)
  if ok then
    assertf(ok == true, "sethostname(host) expected true, got %s", tostring(ok))
  else
    assertf(type(err) == "userdata",
            "sethostname should return Errno userdata on failure, got %s",
            type(err))
    local eno = err:errno()
    assertf(eno == unix.EPERM or eno == unix.EACCES,
            "sethostname unprivileged expected EPERM/EACCES, got %s",
            err:name())
  end
end

--------------------------------------------------------------------------------
-- cosmo.sandbox.netns

do
  local netns = require "cosmo.sandbox.netns"
  local ifr = netns.build_ifreq("lo", unix.IFF_UP)
  assertf(#ifr == unix.IFNAMSIZ + 24,
          "ifreq wrong length %d", #ifr)
  assertf(ifr:sub(1, 2) == "lo", "ifreq name not set")
  assertf(netns.parse_ifreq_flags(ifr) == unix.IFF_UP,
          "ifreq flags round-trip failed")

  -- get_flags on a nonexistent interface returns nil, Errno (NOT
  -- nil, str, errno — we unified the shape in v0.0.2).
  if IS_LINUX then
    local r1, r2, r3 = netns.get_flags("nope0")
    assertf(r1 == nil, "get_flags should fail on nonexistent iface")
    assertf(type(r2) == "userdata",
            "get_flags should return Errno userdata, got %s", type(r2))
    assertf(r3 == nil, "get_flags should return only 2 values now")
  end
end

--------------------------------------------------------------------------------
-- cosmo.sandbox.fs

do
  local fs = require "cosmo.sandbox.fs"
  -- Octal mode constants are decimal, NOT hex literals.
  assertf(fs.MODE_DIR        == 493,  "MODE_DIR (0o755) wrong: %s", fs.MODE_DIR)
  assertf(fs.MODE_DIR_PRIV   == 448,  "MODE_DIR_PRIV (0o700) wrong")
  assertf(fs.MODE_FILE       == 420,  "MODE_FILE (0o644) wrong")
  assertf(fs.MODE_TMP_STICKY == 1023, "MODE_TMP_STICKY (0o1777) wrong")
  -- exists()
  assertf(fs.exists("/"), "exists(/) should be true")
  assertf(not fs.exists("/__definitely_not_a_path__"),
          "exists(bogus) should be false")
  -- Function shape sanity.
  for _, fn in ipairs{"bind", "bind_ro", "tmpfs",
                      "private_root", "pivot_to", "pivot_to_or_exit",
                      "proc"} do
    assertf(type(fs[fn]) == "function", "fs.%s missing", fn)
  end

  -- pivot_to_or_exit enforces the documented failure contract: on
  -- underlying pivot_to failure the child is expected to terminate
  -- rather than keep running in a half-unwound mount namespace. Fork
  -- a child and drive it into a guaranteed-failure path (an
  -- unwritable jail that can't even have `/.old` created), then
  -- check the exit status the parent observes.
  do
    local UNWRITABLE = "/__pivot_to_or_exit_nope__"
    -- Sanity: we shouldn't be able to create this as an unprivileged
    -- caller (fs.pivot_to calls makedirs(jail .. "/.old") first).
    -- Root running these tests would actually succeed at makedirs,
    -- which defeats the point; skip the exit-path check in that case.
    local can_make = unix.makedirs(UNWRITABLE .. "/.old", fs.MODE_DIR_PRIV)
    if can_make then
      -- Clean up and skip: we're privileged enough to create dirs at /.
      unix.rmdir(UNWRITABLE .. "/.old")
      unix.rmdir(UNWRITABLE)
    else
      -- Default exit code is 127.
      local pid = assert(unix.fork())
      if pid == 0 then
        -- Silence the diagnostic the child writes to stderr so the
        -- test output stays clean. pivot_to_or_exit must still exit
        -- with the expected code.
        local devnull = unix.open("/dev/null", unix.O_WRONLY)
        if devnull then unix.dup(devnull, 2); unix.close(devnull) end
        fs.pivot_to_or_exit(UNWRITABLE)
        -- Must not reach here.
        unix.exit(0)
      end
      local _, ws = assert(unix.wait(pid))
      assertf(unix.WIFEXITED(ws),
              "pivot_to_or_exit child did not exit normally")
      assertf(unix.WEXITSTATUS(ws) == 127,
              "pivot_to_or_exit default exit code = %d (expected 127)",
              unix.WEXITSTATUS(ws))

      -- Caller-specified exit code is honoured.
      pid = assert(unix.fork())
      if pid == 0 then
        local devnull = unix.open("/dev/null", unix.O_WRONLY)
        if devnull then unix.dup(devnull, 2); unix.close(devnull) end
        fs.pivot_to_or_exit(UNWRITABLE, 42)
        unix.exit(0)
      end
      _, ws = assert(unix.wait(pid))
      assertf(unix.WIFEXITED(ws),
              "pivot_to_or_exit(_, 42) child did not exit normally")
      assertf(unix.WEXITSTATUS(ws) == 42,
              "pivot_to_or_exit custom exit code = %d (expected 42)",
              unix.WEXITSTATUS(ws))
    end
  end
end

--------------------------------------------------------------------------------
-- cosmo.sandbox.proc

do
  local proc = require "cosmo.sandbox.proc"
  -- Function-shape sanity.
  for _, fn in ipairs{"no_new_privs", "drop_privs",
                      "become_init", "barrier",
                      "setup_userns_maps", "fork_pidns"} do
    assertf(type(proc[fn]) == "function", "proc.%s missing", fn)
  end
  -- DEFAULT_SIGNALS is a sane set.
  assertf(type(proc.DEFAULT_SIGNALS) == "table",
          "proc.DEFAULT_SIGNALS missing")
  assertf(#proc.DEFAULT_SIGNALS == 3,
          "proc.DEFAULT_SIGNALS wrong size")
  -- drop_privs(nil) is a pure no-op. drop_privs(0) is "root without
  -- caps" — calls capset(0,0,0), which is ENOSYS on non-Linux (treated
  -- as success).
  assertf(proc.drop_privs(nil) == true, "drop_privs(nil) should succeed")
  assertf(proc.drop_privs(0)   == true, "drop_privs(0) should succeed")
  -- barrier() builds a pipe-based one-shot; drop_read/drop_write are
  -- idempotent in the same process.
  local b = assert(proc.barrier())
  b:drop_read(); b:drop_read()
  b:drop_write(); b:drop_write()
  -- The barrier carries a named metatable so runtime type errors
  -- and tostring() output are discriminable.
  local bmt = getmetatable(b)
  assertf(type(bmt) == "table", "barrier should have a metatable")
  assertf(bmt.__name == "cosmo.sandbox.proc.Barrier",
          "barrier __name = %s", tostring(bmt.__name))
end

--------------------------------------------------------------------------------
-- cosmo.sandbox.landlock

do
  local ll = require "cosmo.sandbox.landlock"
  -- Convenience flag aggregates.
  assertf(ll.READ == (ll.READ_FILE | ll.READ_DIR), "ll.READ wrong")
  assertf(ll.EXEC == ll.EXECUTE, "ll.EXEC wrong")
  assertf(ll.RW & ll.EXEC ~= 0, "ll.RW should include EXEC")
  -- Function-shape sanity.
  for _, fn in ipairs{"abi", "available", "restrict"} do
    assertf(type(ll[fn]) == "function", "ll.%s missing", fn)
  end
  -- On Linux, abi() returns either an int (≥1) or nil,Errno — either
  -- way it should not crash.
  local a = ll.abi()
  if IS_LINUX then
    assertf(a == nil or type(a) == "number", "ll.abi() wrong type")
  end
end

print("cosmo.sandbox smoke tests passed")
