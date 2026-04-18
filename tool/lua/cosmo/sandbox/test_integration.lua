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
local proxy = require "cosmo.sandbox.proxy"

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
if cosmo.GetHostOs() ~= "LINUX" then
  skip("non-Linux host (%s)", cosmo.GetHostOs())
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

-- handle:alive() against a real child. This runs unprivileged because
-- it only needs fork+waitpid — no namespaces. Must come before the
-- CLONE_NEWNET probe below, which bails out of the whole file on
-- environments that can't unshare.
do
  local Handle = proxy._Handle
  -- A live, unreaped child: alive() must see it.
  local rpipe, wpipe = assert(unix.pipe())
  local pid = assert(unix.fork())
  if pid == 0 then
    unix.close(wpipe)
    -- Block until the parent closes its end, then exit. Using a pipe
    -- read is race-free: no sleep, no signal choreography.
    unix.read(rpipe, 1)
    unix.exit(0)
  end
  unix.close(rpipe)
  local h = setmetatable({pid = pid}, Handle)
  assertf(h:alive() == true, "alive() on running child should be true")
  assertf(h.pid == pid, "alive() must not mutate pid while child lives")
  -- Release the child; poll alive() until it sees the exit.
  unix.close(wpipe)
  local deadline = 200  -- 200 * 10ms = 2s budget
  while deadline > 0 and h:alive() do
    unix.nanosleep(0, 10 * 1000 * 1000)
    deadline = deadline - 1
  end
  assertf(h:alive() == false,
          "alive() should return false after child exits")
  assertf(h.pid == 0,
          "alive() should clear pid to 0 once the child has been reaped")
  log("ok: handle:alive() tracks child liveness and reaps on exit")
end

-- handle:stop() against a cooperative child: the child blocks on a
-- pipe read, and SIGTERM's default action is Terminate, so stop()
-- should reap it cleanly, clear self.pid to 0, and return true. A
-- second stop() must be a no-op — no signal, no wait — because the
-- pid may have been recycled by the kernel.
do
  local Handle = proxy._Handle
  local rpipe, wpipe = assert(unix.pipe())
  local pid = assert(unix.fork())
  if pid == 0 then
    unix.close(wpipe)
    -- Block until the write end closes (never, in this test) or a
    -- signal terminates us. SIGTERM has default-action Terminate.
    unix.read(rpipe, 1)
    unix.exit(0)
  end
  unix.close(rpipe); unix.close(wpipe)
  local h = setmetatable({pid = pid}, Handle)
  assertf(h:stop() == true, "stop() should return true on cooperative child")
  assertf(h.pid == 0, "stop() must clear pid to 0 after reap")
  -- Idempotent: a second stop() must not re-signal, must still return true.
  assertf(h:stop() == true, "second stop() should be a no-op returning true")
  assertf(h.pid == 0, "pid must remain 0 after second stop()")
  log("ok: handle:stop() reaps cooperative child and is idempotent")
end

-- handle:stop() against a SIGTERM-ignoring child: after the timeout
-- elapses, stop() must escalate to SIGKILL and reap the child. The
-- bounded timeout prevents a hostile or stuck worker from wedging the
-- supervisor forever.
do
  local Handle = proxy._Handle
  local rpipe, wpipe = assert(unix.pipe())
  local pid = assert(unix.fork())
  if pid == 0 then
    unix.close(wpipe)
    -- Ignore SIGTERM so only SIGKILL can terminate us. A stray
    -- SIGTERM still interrupts the read() syscall (EINTR), so loop.
    unix.sigaction(unix.SIGTERM, unix.SIG_IGN)
    while true do unix.read(rpipe, 1) end
    unix.exit(0)
  end
  unix.close(rpipe); unix.close(wpipe)
  local h = setmetatable({pid = pid}, Handle)
  -- Short timeout so the test runs quickly. 200ms is well over the
  -- 10ms polling granularity but still short compared to a real user
  -- pressing Ctrl-C.
  local t0 = unix.clock_gettime(unix.CLOCK_MONOTONIC)
  assertf(h:stop(200) == true, "stop(200) should still return true")
  local t1 = unix.clock_gettime(unix.CLOCK_MONOTONIC)
  assertf(h.pid == 0, "pid must be cleared after SIGKILL escalation")
  -- Sanity: the call took at least the timeout (we had to wait) but
  -- not unreasonably long (we didn't wedge).
  assertf(t1 - t0 < 5,
          "stop() with 200ms timeout took %d seconds", t1 - t0)
  log("ok: handle:stop() escalates to SIGKILL after timeout")
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

--------------------------------------------------------------------------------
-- Proxy integration tests
--
-- Topology:
--   parent netns: tiny HTTP server bound on 127.0.0.1:<rand>
--   child  netns: proxy bound on 127.0.0.1:3128, dials parent via setns
--
-- We exercise CONNECT (allowed/denied) and plain HTTP (allowed +
-- header injection / denied). All within the same lua.com binary using
-- forks; nothing is reached over the public internet.

-- Bring up a minimal HTTP/1.1 server in the parent process. It returns
-- 200 with a body that echoes back the request method, path, and any
-- value of an "x-injected" header. Returns the listening port and the
-- pid of the server process.
local function start_test_server()
  local srv = assert(unix.socket(unix.AF_INET, unix.SOCK_STREAM, 0))
  assert(unix.setsockopt(srv, unix.SOL_SOCKET, unix.SO_REUSEADDR, 1))
  assert(unix.bind(srv, LOOPBACK, 0))
  assert(unix.listen(srv, 8))
  local _, port = assert(unix.getsockname(srv))
  local pid = assert(unix.fork())
  if pid == 0 then
    -- Server child.
    while true do
      local cli = unix.accept(srv)
      if cli then
        local req = ""
        while not req:find("\r\n\r\n", 1, true) do
          local c = unix.recv(cli, 4096)
          if not c or c == "" then break end
          req = req .. c
        end
        local method, path = req:match("^(%u+) (%S+) HTTP/1")
        local injected = req:match("\r\n[Xx]%-[Ii]njected:%s*([^\r\n]*)\r\n") or ""
        local body = string.format("method=%s path=%s injected=%s",
                                   method or "?", path or "?", injected)
        local resp = "HTTP/1.1 200 OK\r\nContent-Length: " .. #body ..
                     "\r\nConnection: close\r\n\r\n" .. body
        unix.send(cli, resp)
        unix.shutdown(cli, unix.SHUT_WR)
        unix.close(cli)
      end
    end
  end
  return port, pid, srv
end

-- Drive a single HTTP request through the proxy. Returns the raw
-- response body. `target` semantics:
--
--   method=="CONNECT", target=="host:port"
--     - issue CONNECT, expect 200, then send `tunneled` (a complete
--       inner HTTP request) through the tunnel and read the response.
--     - if `expect_deny` is true, only the 4xx response is read.
--   method!="CONNECT", target=="http://host:port/path"
--     - send a normal proxy GET/POST, read the response.
local function request_through_proxy(proxy_port, method, target, opts)
  opts = opts or {}
  local sk = assert(unix.socket(unix.AF_INET, unix.SOCK_STREAM, 0))
  assert(unix.connect(sk, LOOPBACK, proxy_port))
  if method == "CONNECT" then
    local req = "CONNECT " .. target .. " HTTP/1.1\r\nHost: " ..
                target .. "\r\n\r\n"
    assert(unix.send(sk, req))
    -- Read just the CONNECT response status line + headers.
    local buf = ""
    while not buf:find("\r\n\r\n", 1, true) do
      local c = unix.recv(sk, 4096)
      if not c or c == "" then break end
      buf = buf .. c
    end
    if opts.expect_deny then
      unix.close(sk)
      return buf
    end
    -- Tunnel up: send the inner HTTP request, then read everything.
    if opts.tunneled then
      assert(unix.send(sk, opts.tunneled))
    end
    while true do
      local c = unix.recv(sk, 16384)
      if not c or c == "" then break end
      buf = buf .. c
    end
    unix.close(sk)
    return buf
  end
  local req = method .. " " .. target .. " HTTP/1.1\r\n" ..
              "Host: 127.0.0.1\r\n" ..
              (opts.extra or "") ..
              "\r\n"
  assert(unix.send(sk, req))
  local resp = ""
  while true do
    local c = unix.recv(sk, 16384)
    if not c or c == "" then break end
    resp = resp .. c
  end
  unix.close(sk)
  return resp
end

-- Run the proxy in a forked child whose ONLY job is to listen and
-- serve until parent kills it. Returns proxy_pid.
local function start_proxy(opts, parent_ns_fd)
  local pid = assert(unix.fork())
  if pid == 0 then
    local ok, err = unix.unshare(unix.CLONE_NEWNET)
    if not ok then
      io.stderr:write("proxy: unshare failed: " .. tostring(err) .. "\n")
      unix.exit(1)
    end
    if can_set_flags then assert(netns.bring_up("lo")) end
    opts.upstream_ns_fd = parent_ns_fd
    local p = proxy.new(opts)
    local lfd, lerr = p:listen()
    if not lfd then
      io.stderr:write("proxy: listen failed: " .. tostring(lerr) .. "\n")
      unix.exit(1)
    end
    p:serve_forever()
    unix.exit(0)
  end
  return pid
end

-- The proxy listens INSIDE a fresh netns, so we can't reach it from
-- the parent. Drive everything from a forked client that joins the
-- proxy's netns via setns(). Returns the response string.
local function exercise(proxy_ns_fd, method, target, opts)
  local r, w = assert(unix.pipe())
  local pid = assert(unix.fork())
  if pid == 0 then
    unix.close(r)
    assert(unix.setns(proxy_ns_fd, unix.CLONE_NEWNET))
    local resp = request_through_proxy(3128, method, target, opts)
    unix.write(w, resp)
    unix.close(w)
    unix.exit(0)
  end
  unix.close(w)
  local buf = ""
  while true do
    local c = unix.read(r, 65536)
    if not c or c == "" then break end
    buf = buf .. c
  end
  unix.close(r)
  unix.wait(pid)
  return buf
end

-- The proxy live tests require us to (a) listen inside a child netns,
-- and (b) reach that listener from another process. Easiest cross-
-- namespace plumbing is via /proc/<pid>/ns/net. We can do this without
-- CAP_NET_ADMIN since we don't need to bring lo up — the loopback in
-- the child netns is up by default in modern containers.
do
  local server_port, server_pid, server_sk = start_test_server()
  log("test server: port=%d pid=%d", server_port, server_pid)

  local parent_ns = assert(netns.open())

  -- Spawn the proxy.
  local proxy_pid = start_proxy({
    bind_ip = LOOPBACK,
    bind_port = 3128,
    log_level = "quiet",
    allowed_hosts = {
      ["127.0.0.1:" .. server_port] = {},
    },
  }, parent_ns)

  -- Get an fd on the proxy's netns so we can run client requests there.
  local proxy_ns = assert(netns.open(proxy_pid))

  -- Give the proxy a moment to bind. Tight loop probing /proc.
  local function wait_for_proxy(ns_fd)
    for _ = 1, 200 do
      local pid = assert(unix.fork())
      if pid == 0 then
        if unix.setns(ns_fd, unix.CLONE_NEWNET) then
          local sk = unix.socket(unix.AF_INET, unix.SOCK_STREAM, 0)
          if sk and unix.connect(sk, LOOPBACK, 3128) then
            unix.close(sk); unix.exit(0)
          end
        end
        unix.exit(1)
      end
      local _, ws = unix.wait(pid)
      if unix.WIFEXITED(ws) and unix.WEXITSTATUS(ws) == 0 then
        return true
      end
      unix.nanosleep(0, 20 * 1000 * 1000)  -- 20ms
    end
    return false
  end
  assertf(wait_for_proxy(proxy_ns), "proxy never came up")
  log("ok: proxy is listening")

  -- Test 6: CONNECT to allowlisted host succeeds (200) and tunnels
  -- a real HTTP request.
  do
    local resp = exercise(proxy_ns, "CONNECT",
                          "127.0.0.1:" .. server_port,
                          {tunneled = "GET /tun HTTP/1.1\r\nHost: x\r\n" ..
                                      "Connection: close\r\n\r\n"})
    assertf(resp:find("HTTP/1.1 200 Connection Established", 1, true),
            "CONNECT did not return 200: %q", resp:sub(1, 80))
    assertf(resp:find("path=/tun", 1, true),
            "tunneled body missing: %q", resp:sub(-100))
    log("ok: CONNECT allowed -> 200 + tunnel works")
  end

  -- Test 7: CONNECT to a denied host returns 403.
  do
    local resp = exercise(proxy_ns, "CONNECT", "evil.example.com:443",
                          {expect_deny = true})
    assertf(resp:find("^HTTP/1.1 403 ", 1, false),
            "CONNECT to denied host did not return 403: %q",
            resp:sub(1, 80))
    log("ok: CONNECT denied -> 403")
  end

  -- Test 8: plain HTTP to allowlisted host is forwarded.
  do
    local resp = exercise(proxy_ns, "GET",
                          "http://127.0.0.1:" .. server_port .. "/hello")
    assertf(resp:find("^HTTP/1.1 200 ", 1, false),
            "HTTP GET to allowed did not return 200: %q",
            resp:sub(1, 80))
    assertf(resp:find("path=/hello", 1, true),
            "echo body missing: %q", resp:sub(-100))
    log("ok: HTTP GET allowed -> forwarded, body echoed")
  end

  -- Test 9: plain HTTP to denied host returns 403.
  do
    local resp = exercise(proxy_ns, "GET", "http://evil.example.com/hello")
    assertf(resp:find("^HTTP/1.1 403 ", 1, false),
            "HTTP GET to denied did not return 403: %q",
            resp:sub(1, 80))
    log("ok: HTTP GET denied -> 403")
  end

  -- Test 10: header injection — restart proxy with a header rule.
  do
    unix.kill(proxy_pid, unix.SIGKILL)
    unix.wait(proxy_pid)
    unix.close(proxy_ns)
    -- Drain any zombie proxy workers so they don't get inherited.
    while true do
      local pid = unix.wait(-1, unix.WNOHANG)
      if not pid or pid == 0 then break end
    end

    proxy_pid = start_proxy({
      bind_ip = LOOPBACK,
      bind_port = 3128,
      log_level = "quiet",
      allowed_hosts = {
        ["127.0.0.1:" .. server_port] = {
          type = "header",
          header_name = "x-injected",
          header_value = "secret-token",
        },
      },
    }, parent_ns)
    proxy_ns = assert(netns.open(proxy_pid))
    assertf(wait_for_proxy(proxy_ns), "proxy (test 10) never came up")

    local resp = exercise(proxy_ns, "GET",
                          "http://127.0.0.1:" .. server_port .. "/inj")
    assertf(resp:find("injected=secret%-token"),
            "injected header not visible at server: %q",
            resp:sub(-150))
    log("ok: HTTP header injection reaches upstream")
  end

  -- Cleanup.
  unix.close(proxy_ns)
  unix.close(parent_ns)
  unix.kill(proxy_pid, unix.SIGTERM)
  unix.wait(proxy_pid)
  unix.kill(server_pid, unix.SIGTERM)
  unix.wait(server_pid)
  unix.close(server_sk)
end

print("cosmo.sandbox integration tests passed")
