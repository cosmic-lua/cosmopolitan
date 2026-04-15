--- cosmo.sandbox.proc: process-setup helpers.
---
--- Composable pieces for the "after fork, before exec" portion of a
--- jailed child, plus the PID-1 supervisor loop used by the netns-proxy
--- and claude-code examples. All helpers return `nil, unix.Errno` on
--- failure, matching the rest of the cosmo.sandbox.* library.
---
--- Linux-only.

local unix = require "unix"

local M = {}

--- proc.set_hostname(name) → true | nil, unix.Errno
---
--- Set the UTS-namespace hostname. Typically called immediately after
--- unshare(CLONE_NEWUTS) so the new hostname is visible only inside
--- the jail. Fails with EPERM if the process lacks CAP_SYS_ADMIN in
--- its UTS namespace.
function M.set_hostname(name)
  assert(type(name) == "string", "hostname must be a string")
  local ok, err = unix.sethostname(name)
  if not ok then return nil, err end
  return true
end

--- proc.no_new_privs() → true | nil, unix.Errno
---
--- Set PR_SET_NO_NEW_PRIVS on the current process. Once set:
---   * execve() no longer grants setuid/setgid/file-cap privileges,
---   * the bit is inherited by all children (and cannot be cleared),
---   * seccomp filters can be installed without CAP_SYS_ADMIN.
---
--- Call this before pivot_root / execve in any jail that doesn't
--- explicitly need privilege escalation.
function M.no_new_privs()
  local ok, err = unix.prctl(unix.PR_SET_NO_NEW_PRIVS, 1)
  if not ok then return nil, err end
  return true
end

--- proc.drop_privs(uid, gid) → true | nil, unix.Errno
---
--- Drop to (uid, gid) and clear capabilities. Full dance:
---
---   1. PR_SET_KEEPCAPS — preserve capabilities across setuid, so we
---      can explicitly clear them after switching uid. Without this,
---      the kernel drops caps silently on setuid(non-zero) and we'd
---      have no chance to inspect what was kept.
---   2. setresgid(gid, gid, gid)
---   3. setresuid(uid, uid, uid) — all three (real/effective/saved)
---      so there's no path back.
---   4. capset(0, 0, 0) — clear the effective, permitted, and
---      inheritable capability sets.
---
--- Does nothing if uid == nil (caller wants to stay as current uid).
--- A no-op for uid == 0 (can't "drop to root" meaningfully).
function M.drop_privs(uid, gid)
  if not uid or uid == 0 then return true end
  local ok, err = unix.prctl(unix.PR_SET_KEEPCAPS, 1)
  if not ok then return nil, err end
  ok, err = unix.setresgid(gid, gid, gid)
  if not ok then return nil, err end
  ok, err = unix.setresuid(uid, uid, uid)
  if not ok then return nil, err end
  ok, err = unix.capset(0, 0, 0)
  if not ok then return nil, err end
  return true
end

--- Default signal set forwarded by become_init.
M.DEFAULT_SIGNALS = { "SIGINT", "SIGTERM", "SIGHUP" }

--- proc.become_init(main_pid, opts) → exit_code
---
--- Run a PID-1-style supervisor loop:
---   * forward signals in opts.signals (default: SIGINT/SIGTERM/SIGHUP)
---     to `main_pid` — the user-visible child,
---   * reap zombies with unix.wait() in a loop,
---   * when `main_pid` exits, kill each pid in opts.sidecars and reap
---     them, then return main_pid's exit status,
---   * if any sidecar pid exits unexpectedly first, kill main_pid and
---     return 1.
---
--- EINTR during wait() is handled internally.
---
--- Returns an integer exit code suitable for `os.exit()`:
---   * 0..255         main_pid exited with that status
---   * 128 + signum   main_pid was terminated by signum
---   * 1              unexpected supervisor failure
---
--- opts:
---   sidecars   {pid, ...}   processes to kill+reap when main exits
---   signals    {string|int} signal names/numbers to forward
---   on_sidecar_exit  callable(pid, ws)  — hook for logging
function M.become_init(main_pid, opts)
  opts = opts or {}
  local sidecars = opts.sidecars or {}
  local signals = opts.signals or M.DEFAULT_SIGNALS
  local on_sidecar_exit = opts.on_sidecar_exit

  local function signum(s)
    if type(s) == "number" then return s end
    return unix[s]
  end

  -- Forward our interrupt/terminate signals to the main child.
  local function forward(sig)
    pcall(unix.kill, main_pid, sig)
  end
  for _, s in ipairs(signals) do
    local n = signum(s)
    if n then
      unix.sigaction(n, function() forward(n) end)
    end
  end

  local function kill_and_reap(pid)
    pcall(unix.kill, pid, unix.SIGTERM)
    pcall(unix.wait, pid)
  end

  while true do
    local pid, ws = unix.wait()
    if not pid then
      -- ws is a unix.Errno on failure. EINTR = a forwarded signal
      -- arrived mid-wait; loop and reap.
      if ws and ws:errno() == unix.EINTR then
        -- continue
      else
        return 1
      end
    elseif pid == main_pid then
      for _, s in ipairs(sidecars) do kill_and_reap(s) end
      if unix.WIFEXITED(ws) then
        return unix.WEXITSTATUS(ws)
      elseif unix.WIFSIGNALED(ws) then
        return 128 + unix.WTERMSIG(ws)
      else
        return 1
      end
    else
      -- A sidecar exited. Kill the main child and return non-zero.
      for _, s in ipairs(sidecars) do
        if s == pid then
          if on_sidecar_exit then
            pcall(on_sidecar_exit, pid, ws)
          end
          kill_and_reap(main_pid)
          return 1
        end
      end
      -- Unknown child (spurious reap); keep waiting.
    end
  end
end

return M
