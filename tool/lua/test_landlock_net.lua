-- Tests for the Landlock ABI 4 network surface: the NET access bits,
-- unix.landlock_add_net_rule, and the size gating in
-- unix.landlock_create_ruleset that keeps an fs-only call byte-identical
-- to the ABI 1 request the kernel has always accepted.

local unix = require("unix")

assert(type(unix.landlock_add_net_rule) == "function",
       "landlock_add_net_rule should be a function")

-- Constant values are the kernel uapi's and are frozen at the C
-- boundary; cosmic's generated types carry them downstream.
assert(unix.LANDLOCK_RULE_PATH_BENEATH == 1,
       "PATH_BENEATH should be 1, got: " ..
       tostring(unix.LANDLOCK_RULE_PATH_BENEATH))
assert(unix.LANDLOCK_RULE_NET_PORT == 2,
       "NET_PORT should be 2, got: " .. tostring(unix.LANDLOCK_RULE_NET_PORT))
assert(unix.LANDLOCK_ACCESS_NET_BIND_TCP == 1,
       "BIND_TCP should be 1, got: " ..
       tostring(unix.LANDLOCK_ACCESS_NET_BIND_TCP))
assert(unix.LANDLOCK_ACCESS_NET_CONNECT_TCP == 2,
       "CONNECT_TCP should be 2, got: " ..
       tostring(unix.LANDLOCK_ACCESS_NET_CONNECT_TCP))

-- The rest needs a kernel with Landlock compiled in and enabled. The
-- argless probe is the only way to ask; skip with a note where it says
-- no, rather than failing the suite on a host that cannot answer.
local abi, err = unix.landlock_create_ruleset()
if not abi then
  print("skipping landlock round-trip: " .. tostring(err))
  return
end
assert(math.type(abi) == "integer", "abi should be an integer")
assert(abi >= 1, "abi should be at least 1, got: " .. tostring(abi))

-- An fs-only ruleset still succeeds: the widened struct did not widen
-- the request. This is the size-gating proof — it holds on an ABI 1
-- kernel exactly as it does here.
local fs_rs, fs_err = unix.landlock_create_ruleset(
    unix.LANDLOCK_ACCESS_FS_READ_FILE | unix.LANDLOCK_ACCESS_FS_READ_DIR)
assert(fs_rs, "fs-only ruleset should be created: " .. tostring(fs_err))
unix.close(fs_rs)

local handled_net = unix.LANDLOCK_ACCESS_NET_BIND_TCP
                  | unix.LANDLOCK_ACCESS_NET_CONNECT_TCP

if abi < 4 then
  -- Below ABI 4 the kernel does not know the net field, and the longer
  -- size is exactly what it answers E2BIG to. That refusal is the other
  -- half of the gating contract, so assert it where it applies.
  local rs, nerr, nerrno = unix.landlock_create_ruleset(0, 0, handled_net)
  assert(rs == nil, "net ruleset must fail below ABI 4")
  assert(nerrno == unix.E2BIG,
         "expected E2BIG below ABI 4, got: " .. tostring(nerr))
  print("skipping ABI 4 round-trip: kernel ABI is " .. abi)
  return
end

-- Full create / add-net-rule / restrict round-trip.
local rs, rs_err = unix.landlock_create_ruleset(0, 0, handled_net)
assert(rs, "net ruleset should be created: " .. tostring(rs_err))

-- A port the ruleset does not handle at all is still a valid rule to
-- add; the kernel only checks that `allowed` is a subset of handled.
local ok, add_err = unix.landlock_add_net_rule(
    rs, 65000, unix.LANDLOCK_ACCESS_NET_CONNECT_TCP)
assert(ok, "add_net_rule should succeed: " .. tostring(add_err))

-- Access outside the handled set is rejected, which proves the mask
-- reaches the kernel rather than being silently dropped.
local bad, bad_err, bad_errno = unix.landlock_add_net_rule(
    rs, 65001, unix.LANDLOCK_ACCESS_FS_READ_FILE)
assert(bad == nil, "an fs bit is not a net access right")
assert(bad_errno == unix.EINVAL,
       "expected EINVAL for a non-net access bit, got: " .. tostring(bad_err))

-- Enforcement is irrevocable, so it happens in a child. Connecting to
-- the allowed port must not be refused by Landlock (nothing listens, so
-- the kernel answers ECONNREFUSED); the unlisted port must be EACCES.
local pid = assert(unix.fork())
if pid == 0 then
  local function die(code, msg)
    if msg then
      unix.write(2, "landlock child: " .. msg .. "\n")
    end
    unix.exit(code)
  end
  if not unix.prctl(unix.PR_SET_NO_NEW_PRIVS, 1) then
    die(3, "PR_SET_NO_NEW_PRIVS failed")
  end
  local restricted, rerr = unix.landlock_restrict_self(rs)
  if not restricted then
    die(4, "restrict_self failed: " .. tostring(rerr))
  end
  local loopback = 0x7f000001  -- unix.connect takes a uint32, not a string
  local function connect_to(port)
    local fd = assert(unix.socket(unix.AF_INET, unix.SOCK_STREAM))
    local cok, cerr, cerrno = unix.connect(fd, loopback, port)
    unix.close(fd)
    return cok, cerr, cerrno
  end
  local _, allowed_err, allowed_errno = connect_to(65000)
  if allowed_errno == unix.EACCES then
    die(5, "allowed port was denied: " .. tostring(allowed_err))
  end
  local denied, denied_err, denied_errno = connect_to(65002)
  if denied then
    die(6, "unlisted port should not connect")
  end
  if denied_errno ~= unix.EACCES then
    die(7, "expected EACCES on unlisted port, got: " .. tostring(denied_err))
  end
  die(0)
end

unix.close(rs)
-- wait's success value is one unix.WaitResult table ({pid=, wstatus=,
-- rusage=}), not positional values -- slots 2/3 always mean error/errno.
local result = assert(unix.wait(pid))
assert(unix.WIFEXITED(result.wstatus), "landlock child should exit normally")
assert(unix.WEXITSTATUS(result.wstatus) == 0,
       "landlock child failed with status " .. unix.WEXITSTATUS(result.wstatus))
