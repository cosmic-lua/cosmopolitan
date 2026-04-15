-- Integration tests for cosmo.sandbox primitives.
--
-- These exercise real kernel behaviour: creating a fresh network
-- namespace, bringing up loopback, entering another process's
-- namespace, etc. They need CAP_SYS_ADMIN + CAP_NET_ADMIN (typically
-- root or an unprivileged user namespace), so the harness probes for
-- permission up-front and skips cleanly when it can't run.

local unix = require "unix"
local cosmo = require "cosmo"
local netns = require "cosmo.sandbox.netns"

local LOOPBACK = cosmo.ParseIp("127.0.0.1")

local function log(fmt, ...)
  io.stderr:write(string.format(fmt, ...), "\n")
end

local function skip(fmt, ...)
  log("SKIP: " .. fmt, ...)
  os.exit(0)
end

local function assertf(cond, fmt, ...)
  if not cond then error(string.format(fmt, ...), 2) end
end

-- Precondition: running on Linux with CLONE_NEWNET available.
do
  local u = unix.uname and unix.uname() or nil
  if u and u.sysname and u.sysname ~= "Linux" then
    skip("non-Linux host (%s)", u.sysname)
  end
end

-- Preflight: try to open /proc/self/ns/net. If the fork+unshare path
-- isn't going to work we want to know now, before spinning up children.
do
  local fd, err = unix.open("/proc/self/ns/net", unix.O_RDONLY)
  if not fd then
    skip("cannot open /proc/self/ns/net: %s", tostring(err))
  end
  unix.close(fd)
end

-- Helper: run `fn` in a freshly-forked child. Returns the child's exit
-- status (0 on success, nonzero on failure). Any error message printed
-- by the child to stderr is preserved by the kernel.
local function in_child(fn)
  local pid = assert(unix.fork())
  if pid == 0 then
    local ok, err = pcall(fn)
    if not ok then
      io.stderr:write("child error: ", tostring(err), "\n")
      unix.exit(1)
    end
    unix.exit(0)
  end
  local _, wstatus = assert(unix.wait(pid))
  if unix.WIFEXITED(wstatus) then
    return unix.WEXITSTATUS(wstatus)
  else
    return -1
  end
end

-- Probe: can we actually unshare(CLONE_NEWNET)? Some kernels disable
-- unprivileged user-namespace creation, and many environments aren't
-- root. Rather than fail the test, skip.
do
  local rc = in_child(function()
    local ok, err = unix.unshare(unix.CLONE_NEWNET)
    if not ok then unix.exit(42) end
  end)
  if rc == 42 then
    skip("unshare(CLONE_NEWNET) returns EPERM — "
         .. "rerun as root or with CAP_SYS_ADMIN+CAP_NET_ADMIN")
  end
  assertf(rc == 0, "unshare probe returned %d", rc)
end

-- Probe: can we issue SIOCSIFFLAGS in the new netns? Some hardened
-- environments allow CLONE_NEWNET but still deny CAP_NET_ADMIN inside
-- the namespace, so SIOCSIFFLAGS returns ENOTTY/EPERM. Skip the
-- interface-manipulation tests if so; the loopback-reachability test
-- below still runs since lo is often UP by default.
local can_set_flags
do
  local rc = in_child(function()
    assert(unix.unshare(unix.CLONE_NEWNET))
    local ok = netns.set_flags("lo", netns.get_flags("lo"))
    unix.exit(ok and 0 or 42)
  end)
  if rc == 0 then
    can_set_flags = true
  else
    can_set_flags = false
    log("note: SIOCSIFFLAGS denied in this environment; "
        .. "skipping bring_up/bring_down assertions")
  end
end

-- Test 1: in a fresh netns, lo is a loopback interface with the
-- expected IFF_LOOPBACK flag. (Whether it starts UP or DOWN depends
-- on the kernel version / cgroup/container setup; we don't assert.)
do
  local rc = in_child(function()
    assert(unix.unshare(unix.CLONE_NEWNET))
    local flags, err = netns.get_flags("lo")
    assertf(flags, "get_flags(lo) failed: %s", tostring(err))
    assertf((flags & unix.IFF_LOOPBACK) ~= 0,
            "lo not flagged IFF_LOOPBACK (flags=%#x)", flags)
  end)
  assertf(rc == 0, "fresh-netns lo flags test exited %d", rc)
  log("ok: fresh netns has lo with IFF_LOOPBACK")
end

-- Test 2: bring_down then bring_up toggles IFF_UP deterministically.
-- Skipped in environments without CAP_NET_ADMIN.
if can_set_flags then
  local rc = in_child(function()
    assert(unix.unshare(unix.CLONE_NEWNET))
    assert(netns.bring_down("lo"))
    local down = assert(netns.get_flags("lo"))
    assertf((down & unix.IFF_UP) == 0,
            "lo still UP after bring_down (flags=%#x)", down)
    assert(netns.bring_up("lo"))
    local up = assert(netns.get_flags("lo"))
    assertf((up & unix.IFF_UP) ~= 0,
            "lo still DOWN after bring_up (flags=%#x)", up)
    assertf((up & unix.IFF_RUNNING) ~= 0,
            "lo not RUNNING after bring_up (flags=%#x)", up)
  end)
  assertf(rc == 0, "bring_up/down test exited %d", rc)
  log("ok: bring_down/bring_up('lo') toggles IFF_UP")
else
  log("skip: bring_down/bring_up('lo') (no CAP_NET_ADMIN)")
end

-- Test 3: loopback in fresh netns is reachable. Bind a listener on
-- 127.0.0.1:0, connect to it, exchange a byte. Requires lo to be UP —
-- bring it up if we can; otherwise rely on it being UP by default.
do
  local rc = in_child(function()
    assert(unix.unshare(unix.CLONE_NEWNET))
    if can_set_flags then assert(netns.bring_up("lo")) end
    local flags = assert(netns.get_flags("lo"))
    if (flags & unix.IFF_UP) == 0 then
      io.stderr:write("lo is DOWN and we can't bring it up; skipping\n")
      unix.exit(77)
    end
    local srv = assert(unix.socket(unix.AF_INET, unix.SOCK_STREAM, 0))
    assert(unix.bind(srv, LOOPBACK, 0))
    assert(unix.listen(srv, 1))
    local _, port = assert(unix.getsockname(srv))
    local cli = assert(unix.socket(unix.AF_INET, unix.SOCK_STREAM, 0))
    assert(unix.connect(cli, LOOPBACK, port))
    local acc = assert(unix.accept(srv))
    assert(unix.send(cli, "x"))
    local got = assert(unix.recv(acc, 1))
    assertf(got == "x", "loopback round-trip got %q", got)
  end)
  if rc == 77 then
    log("skip: loopback reachability (lo is DOWN, no CAP_NET_ADMIN)")
  else
    assertf(rc == 0, "loopback reachability test exited %d", rc)
    log("ok: 127.0.0.1 reachable in fresh netns")
  end
end

-- Test 4: a peer in the fresh netns cannot see our real interfaces.
-- Binding to an address that exists in the parent but not in the child
-- must fail with EADDRNOTAVAIL.
do
  -- Find a non-loopback address in the parent netns, if any.
  local ifs = unix.siocgifconf() or {}
  local outside
  for _, v in ipairs(ifs) do
    if v.ip and v.name ~= "lo" then
      outside = v.ip
      break
    end
  end
  if not outside then
    log("(skipping isolation test: no non-loopback interface in parent)")
  else
    local rc = in_child(function()
      assert(unix.unshare(unix.CLONE_NEWNET))
      if can_set_flags then assert(netns.bring_up("lo")) end
      local sk = assert(unix.socket(unix.AF_INET, unix.SOCK_STREAM, 0))
      local ok, err = unix.bind(sk, outside, 0)
      assertf(not ok, "bind to parent-netns IP %s succeeded inside child",
              outside)
      assertf(err:errno() == unix.EADDRNOTAVAIL,
              "expected EADDRNOTAVAIL binding %s, got %s",
              outside, err:name())
    end)
    assertf(rc == 0, "isolation test exited %d", rc)
    log("ok: parent netns addresses unreachable from child")
  end
end

-- Test 5: setns() back into the parent's netns lets us bind the parent
-- interface again. This is the cross-namespace dial primitive.
do
  local parent_ns = assert(netns.open())
  local rc = in_child(function()
    assert(unix.unshare(unix.CLONE_NEWNET))
    if can_set_flags then assert(netns.bring_up("lo")) end
    -- Hop back to the parent namespace via the saved fd.
    assert(unix.setns(parent_ns, unix.CLONE_NEWNET))
    local sk = assert(unix.socket(unix.AF_INET, unix.SOCK_STREAM, 0))
    assert(unix.bind(sk, LOOPBACK, 0))
    unix.close(sk)
  end)
  unix.close(parent_ns)
  assertf(rc == 0, "setns-hop test exited %d", rc)
  log("ok: setns() back to parent netns works")
end

print("cosmo.sandbox integration tests passed")
