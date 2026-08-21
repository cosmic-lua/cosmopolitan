-- Tests for the Landlock ABI 5-9 surface: the device-ioctl and
-- pathname-UNIX-socket access bits, the scope bits and the `scoped`
-- argument of unix.landlock_create_ruleset, and the restrict_self
-- audit-logging and TSYNC flags.

local unix = require("unix")

-- Constant values are the kernel uapi's and are frozen at the C
-- boundary; cosmic's generated types carry them downstream.
local function eq(name, want)
  local got = unix[name]
  assert(got == want,
         name .. " should be " .. want .. ", got: " .. tostring(got))
end

eq("LANDLOCK_ACCESS_FS_IOCTL_DEV", 1 << 15)     -- ABI 5
eq("LANDLOCK_SCOPE_ABSTRACT_UNIX_SOCKET", 1)    -- ABI 6
eq("LANDLOCK_SCOPE_SIGNAL", 2)                  -- ABI 6
eq("LANDLOCK_RESTRICT_SELF_LOG_SAME_EXEC_OFF", 1)   -- ABI 7
eq("LANDLOCK_RESTRICT_SELF_LOG_NEW_EXEC_ON", 2)     -- ABI 7
eq("LANDLOCK_RESTRICT_SELF_LOG_SUBDOMAINS_OFF", 4)  -- ABI 7
eq("LANDLOCK_RESTRICT_SELF_TSYNC", 8)           -- ABI 8
eq("LANDLOCK_ACCESS_FS_RESOLVE_UNIX", 1 << 16)  -- ABI 9

-- The rest needs a kernel with Landlock compiled in and enabled. The
-- argless probe is the only way to ask; skip with a note where it says
-- no, rather than failing the suite on a host that cannot answer.
local abi, err = unix.landlock_create_ruleset()
if not abi then
  print("test_landlock_abi: SKIP (no landlock: " .. tostring(err) .. ")")
  return
end

-- Which assertions a run actually reached depends on the host's ABI, and
-- CI logs are the only place anyone can see that. Name the ABI and each
-- branch taken, so a green run says what it proved instead of leaving
-- "passed" to mean either "enforced" or "skipped".
print("test_landlock_abi: kernel landlock abi " .. abi)

-- An fs-only ruleset still succeeds: widening the struct with `scoped`
-- did not widen the request. This is the size-gating proof, and it
-- holds on an ABI 1 kernel exactly as it does here.
local fs_rs, fs_err = unix.landlock_create_ruleset(
    unix.LANDLOCK_ACCESS_FS_READ_FILE | unix.LANDLOCK_ACCESS_FS_READ_DIR)
assert(fs_rs, "fs-only ruleset should be created: " .. tostring(fs_err))
unix.close(fs_rs)

-- A ruleset handling only ABI 5's or ABI 9's fs bit is created with the
-- ABI 1 size, so what is under test is that the bit itself reaches the
-- kernel and is recognised. Gate each on the ABI that introduced it.
if abi >= 5 then
  local ioctl_rs, ioctl_err = unix.landlock_create_ruleset(
      unix.LANDLOCK_ACCESS_FS_IOCTL_DEV)
  assert(ioctl_rs,
         "IOCTL_DEV ruleset should be created: " .. tostring(ioctl_err))
  unix.close(ioctl_rs)
end
if abi >= 9 then
  local unix_rs, unix_err = unix.landlock_create_ruleset(
      unix.LANDLOCK_ACCESS_FS_RESOLVE_UNIX)
  assert(unix_rs,
         "RESOLVE_UNIX ruleset should be created: " .. tostring(unix_err))
  unix.close(unix_rs)
end

local scoped = unix.LANDLOCK_SCOPE_ABSTRACT_UNIX_SOCKET
             | unix.LANDLOCK_SCOPE_SIGNAL

if abi < 6 then
  -- Below ABI 6 the kernel does not know the scoped field, and the
  -- longer size is exactly what it answers E2BIG to. That refusal is
  -- the other half of the gating contract, so assert it where it
  -- applies.
  local rs, serr, serrno = unix.landlock_create_ruleset(0, 0, 0, scoped)
  assert(rs == nil, "a scoped ruleset must fail below ABI 6")
  assert(serrno == unix.E2BIG,
         "expected E2BIG below ABI 6, got: " .. tostring(serr))
  print("test_landlock_abi: PASS (constants, fs-only create, " ..
        "scoped rejected E2BIG; no scope round-trip below ABI 6)")
  return
end

-- `scoped` alone reaches the kernel with a zero net mask: an ABI 6
-- request that handles no fs or net access at all is still valid.
local rs, rs_err = unix.landlock_create_ruleset(0, 0, 0, scoped)
assert(rs, "scoped ruleset should be created: " .. tostring(rs_err))

-- An undefined scope bit is rejected, which proves the mask reaches
-- the kernel rather than being silently dropped.
local bad, bad_err, bad_errno = unix.landlock_create_ruleset(
    0, 0, 0, 1 << 62)
assert(bad == nil, "an undefined scope bit is not a valid scope")
assert(bad_errno == unix.EINVAL,
       "expected EINVAL for an undefined scope bit, got: " ..
       tostring(bad_err))

-- Enforcement is irrevocable, so it happens in a child. Scoping
-- signals confines them to the domain: the child cannot signal its own
-- parent, which is outside it.
local ppid = unix.getpid()
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
  -- The ABI 7 logging flags are accepted from ABI 7 on; below that the
  -- kernel rejects the unknown bit, so ask for them only where they
  -- exist. Muting the domain's own denials keeps this test from
  -- writing audit noise for the denial it deliberately provokes.
  local flags = 0
  if abi >= 7 then
    flags = unix.LANDLOCK_RESTRICT_SELF_LOG_SAME_EXEC_OFF
  end
  local restricted, rerr = unix.landlock_restrict_self(rs, flags)
  if not restricted then
    die(4, "restrict_self failed: " .. tostring(rerr))
  end
  -- Signal 0 is the existence probe: it delivers nothing, and
  -- Landlock's scope check runs before the target is reached, so a
  -- scoped domain answers EPERM for a process outside it.
  local sent, serr, serrno = unix.kill(ppid, 0)
  if sent then
    die(5, "signalling outside the scope should be denied")
  end
  if serrno ~= unix.EPERM then
    die(6, "expected EPERM outside the scope, got: " .. tostring(serr))
  end
  -- Inside the domain the scope does not apply: the child may signal
  -- itself.
  local self_ok, self_err = unix.kill(unix.getpid(), 0)
  if not self_ok then
    die(7, "signalling inside the scope should be allowed: " ..
           tostring(self_err))
  end
  die(0)
end

unix.close(rs)
local _, wstatus = assert(unix.wait(pid))
assert(unix.WIFEXITED(wstatus), "landlock child should exit normally")
assert(unix.WEXITSTATUS(wstatus) == 0,
       "landlock child failed with status " .. unix.WEXITSTATUS(wstatus))

print("test_landlock_abi: PASS (constants, fs-only create, scoped create, " ..
      "undefined scope rejected, signal scope enforced" ..
      (abi >= 5 and "; IOCTL_DEV handled" or "") ..
      (abi >= 7 and "; ABI 7 log flag accepted" or "") ..
      (abi >= 9 and "; RESOLVE_UNIX handled" or "") .. ")")
