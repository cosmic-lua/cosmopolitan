#!/usr/bin/env lua
-- claude-code.lua: a sandbox tailored for Anthropic Claude Code.
--
-- This is what the sandbox.* library is *for* — composing primitives
-- to fit a specific application's needs. Claude Code needs:
--
--   - Network: only api.anthropic.com (Anthropic API), api.github.com
--     and github.com (gh / git integration), and the package
--     registries it uses to install tools you ask it to use.
--   - Filesystem: read-write access to ONE project directory, plus
--     ~/.claude (its config + history), and read-only access to the
--     usual /usr,/lib,/lib64,/bin and the cert store. Nothing else
--     from $HOME — no ~/.ssh, ~/.aws, ~/.gitconfig credentials,
--     other projects, etc.
--   - Hardening: NO_NEW_PRIVS so it can't escalate via setuid bins.
--     Drop the cap bag down to the empty set. Drop UID back to the
--     invoking user (so `sudo lua.com claude-code.lua ...` doesn't
--     give Claude root inside the sandbox).
--
-- This script is ~250 lines and uses every cosmo.sandbox primitive.
-- Read it as a worked tutorial; copy and adapt for your own app.
--
-- Usage:
--
--   sudo lua.com claude-code.lua \
--       -project /home/me/work/widget    -- required
--       [-claude-bin /path/to/claude]    -- defaults to commandv("claude")
--       [-bind PATH]...                  -- extra read-only mounts
--       [-allow HOST[:PORT]]...          -- extra allowlist entries
--       [-- ARGS_TO_CLAUDE...]
--
-- Linux-only. Requires root (or CAP_SYS_ADMIN+CAP_NET_ADMIN).
--
-- Exit codes mirror the wrapped command's.

local unix  = require "unix"
local cosmo = require "cosmo"
local netns = require "cosmo.sandbox.netns"
local proxy = require "cosmo.sandbox.proxy"

local LOOPBACK = cosmo.ParseIp("127.0.0.1")
local PROXY_PORT = 3128

local function die(fmt, ...)
  io.stderr:write("claude-sandbox: " .. string.format(fmt, ...) .. "\n")
  os.exit(1)
end

--------------------------------------------------------------------------------
-- Argv

local function parse_args(argv)
  local opts = {project = nil, claude_bin = nil,
                bind = {}, allow = {}, args = nil}
  local i = 1
  while i <= #argv do
    local a = argv[i]
    if a == "-h" or a == "--help" then
      io.stderr:write([==[
Usage: claude-code -project DIR [-claude-bin PATH]
                   [-bind PATH]... [-allow HOST[:PORT]]...
                   [-- claude-args...]

Runs Claude Code in a sandbox that exposes only the named project
directory, ~/.claude config, and a curated set of system paths
(read-only). Network is restricted to Anthropic + GitHub + common
package registries (extend with -allow).
]==])
      os.exit(0)
    elseif a == "-project" then
      opts.project = argv[i + 1]; i = i + 2
    elseif a == "-claude-bin" then
      opts.claude_bin = argv[i + 1]; i = i + 2
    elseif a == "-bind" then
      opts.bind[#opts.bind + 1] = argv[i + 1]; i = i + 2
    elseif a == "-allow" then
      opts.allow[#opts.allow + 1] = argv[i + 1]; i = i + 2
    elseif a == "--" then
      opts.args = {table.unpack(argv, i + 1)}; break
    else
      die("unknown argument: %s", a)
    end
  end
  if not opts.project then die("-project DIR is required") end
  return opts
end

--------------------------------------------------------------------------------
-- The default policy. Edit these tables to retune.

-- Hosts the proxy will allow. Plain `{}` means allowlisted with no
-- header injection (the default — TLS auth is end-to-end).
local DEFAULT_ALLOWED = {
  ["api.anthropic.com:443"]              = {},
  ["api.github.com:443"]                 = {},
  ["github.com:443"]                     = {},
  ["objects.githubusercontent.com:443"]  = {},
  ["codeload.github.com:443"]            = {},
  ["raw.githubusercontent.com:443"]      = {},
  -- Package managers Claude often uses
  ["registry.npmjs.org:443"]             = {},
  ["pypi.org:443"]                       = {},
  ["files.pythonhosted.org:443"]         = {},
}

-- Read-only paths the sandboxed process can see. Everything else is
-- INVISIBLE inside the sandbox (no ~/.ssh, ~/.aws, /root, sibling
-- projects, etc.).
local DEFAULT_READONLY = {
  "/usr", "/lib", "/lib64", "/bin",
  "/etc/resolv.conf",
  "/etc/ssl",         -- TLS root certs
  "/etc/ca-certificates", "/usr/share/ca-certificates",
  "/etc/pki",         -- Red Hat / Fedora cert dir
  "/etc/nsswitch.conf", "/etc/passwd", "/etc/group",  -- minimal
}

-- Env vars to pass through. Anything else is dropped — the child
-- doesn't see ANTHROPIC_API_KEY unless it's whitelisted here.
local PASS_ENV = {
  "HOME", "USER", "LOGNAME", "TERM", "LANG", "LC_ALL", "TZ",
  "PATH",
  "ANTHROPIC_API_KEY", "ANTHROPIC_BASE_URL",
  "GH_TOKEN", "GITHUB_TOKEN",
  "EDITOR", "VISUAL",
}

--------------------------------------------------------------------------------
-- Filesystem isolation helper.
--
-- Builds a fresh tmpfs root containing the listed read-only binds, a
-- writable bind to the project, a writable bind to ~/.claude, and a
-- writable /tmp. Then pivot_root into it.

local function exists(path)
  return unix.stat(path) ~= nil
end

local function bind(src, dst, readonly)
  local st = unix.stat(src)
  if not st then return false, "missing source: " .. src end
  -- Create dst as a file or directory matching src.
  if (st:mode() & 0xf000) == 0x4000 then
    unix.makedirs(dst, 0x755)
  else
    local parent = string.match(dst, "(.+)/[^/]+$") or "/"
    unix.makedirs(parent, 0x755)
    local fd = unix.open(dst, unix.O_WRONLY | unix.O_CREAT, 0x644)
    if fd then unix.close(fd) end
  end
  local flags = unix.MS_BIND | unix.MS_REC
  local ok, err = unix.mount(src, dst, nil, flags, nil)
  if not ok then return false, "bind " .. src .. ": " .. tostring(err) end
  if readonly then
    ok, err = unix.mount("none", dst, nil,
                         unix.MS_REMOUNT | unix.MS_BIND |
                         unix.MS_RDONLY  | unix.MS_REC, nil)
    if not ok then
      return false, "ro-remount " .. dst .. ": " .. tostring(err)
    end
  end
  return true
end

-- Builds + pivots into the jail. Must be called after
-- unshare(CLONE_NEWNS) + private remount of /.
local function build_jail(opts, real_home)
  local jail = "/tmp/claude-jail-" .. unix.getpid()
  unix.makedirs(jail, 0x700)
  assert(unix.mount("tmpfs", jail, "tmpfs", 0, "size=128m"))

  -- Read-only system paths.
  for _, p in ipairs(DEFAULT_READONLY) do
    if exists(p) then
      local ok, err = bind(p, jail .. p, true)
      if not ok then die("ro-bind %s: %s", p, err) end
    end
  end

  -- Extra read-only paths the user named.
  for _, p in ipairs(opts.bind) do
    if not exists(p) then die("-bind %s: not found", p) end
    local ok, err = bind(p, jail .. p, true)
    if not ok then die("%s", err) end
  end

  -- Make sure the claude binary itself is reachable inside the jail.
  -- If it lives in a path not already covered (e.g. /opt/claude or
  -- somewhere in /tmp during testing), ro-bind its parent.
  if opts.claude_bin then
    local already = false
    for _, p in ipairs(DEFAULT_READONLY) do
      if opts.claude_bin:sub(1, #p) == p then already = true; break end
    end
    if not already then
      local pdir = string.match(opts.claude_bin, "(.+)/[^/]+$")
      if pdir and exists(pdir) then
        local ok, err = bind(pdir, jail .. pdir, true)
        if not ok then die("auto-bind %s: %s", pdir, err) end
      end
    end
  end

  -- The project, writable.
  local proj = opts.project
  local proj_in_jail = jail .. proj
  local ok, err = bind(proj, proj_in_jail, false)
  if not ok then die("project bind %s: %s", proj, err) end

  -- ~/.claude (writable so Claude can persist its state).
  if real_home then
    local cdir = real_home .. "/.claude"
    if not exists(cdir) then unix.makedirs(cdir, 0x700) end
    local ok, err = bind(cdir, jail .. cdir, false)
    if not ok then die("~/.claude bind: %s", err) end
  end

  -- A writable /tmp (separate from the rest of the tmpfs root so
  -- Claude can drop big things in /tmp without filling our 128m).
  unix.makedirs(jail .. "/tmp", 0x1777)
  assert(unix.mount("tmpfs", jail .. "/tmp", "tmpfs", 0, "size=512m"))

  -- pivot_root.
  unix.makedirs(jail .. "/.old", 0x700)
  assert(unix.chdir(jail))
  assert(unix.pivot_root(".", ".old"))
  assert(unix.chdir("/"))
  assert(unix.unmount("/.old", 2))  -- MNT_DETACH
  unix.rmdir("/.old")
end

--------------------------------------------------------------------------------
-- Capability + UID drop.

local function drop_privileges(real_uid, real_gid)
  -- Order matters: prctl(KEEPCAPS) so dropping UID doesn't auto-clear
  -- our caps, then setresgid/setresuid, then drop the caps we don't
  -- want. We're a sandbox runner, not a service that needs caps in
  -- its sandboxed payload — so drop them all.
  if real_uid ~= 0 then
    unix.prctl(unix.PR_SET_KEEPCAPS, 1)
    assert(unix.setresgid(real_gid, real_gid, real_gid))
    assert(unix.setresuid(real_uid, real_uid, real_uid))
  end
  -- Empty cap sets — child runs with no Linux capabilities at all.
  assert(unix.capset(0, 0, 0))
  -- Block setuid escalation.
  assert(unix.prctl(unix.PR_SET_NO_NEW_PRIVS, 1))
end

--------------------------------------------------------------------------------
-- Environment construction.

local function build_env(opts)
  local out = {}
  local host = unix.environ()
  for _, k in ipairs(PASS_ENV) do
    if host[k] then out[k] = host[k] end
  end
  -- Make HOME point inside the jail too if the user has one.
  -- Anthropic-specific: tell Claude where its config lives if needed.
  out.HTTP_PROXY  = "http://127.0.0.1:" .. PROXY_PORT
  out.HTTPS_PROXY = out.HTTP_PROXY
  out.http_proxy  = out.HTTP_PROXY
  out.https_proxy = out.HTTP_PROXY
  out.NO_PROXY    = ""           -- don't exempt loopback
  out.no_proxy    = ""
  -- Flatten to "K=V" array.
  local env = {}
  for k, v in pairs(out) do env[#env + 1] = k .. "=" .. v end
  return env
end

--------------------------------------------------------------------------------
-- Main.

local function main(argv)
  local u = unix.uname and unix.uname() or nil
  if u and u.sysname and u.sysname ~= "Linux" then
    die("Linux only (this is %s)", u.sysname)
  end

  local opts = parse_args(argv)

  -- Resolve the claude binary.
  local claude_bin = opts.claude_bin or unix.commandv("claude")
                                     or unix.commandv("claude-code")
  if not claude_bin then die("can't find `claude` binary on PATH") end

  -- Capture the invoking user's identity BEFORE we fork — we want to
  -- drop privileges to *them* inside the sandbox, not to root.
  local real_uid = tonumber(os.getenv("SUDO_UID")) or unix.getuid()
  local real_gid = tonumber(os.getenv("SUDO_GID")) or unix.getgid()
  local real_home = os.getenv("SUDO_USER")
                    and ("/home/" .. os.getenv("SUDO_USER"))
                    or os.getenv("HOME")

  -- Save the parent netns fd so the proxy can dial through it.
  local parent_ns = assert(netns.open())

  -- Pipe gates the wrapper: it blocks until the proxy is listening.
  local pipe_r, pipe_w = assert(unix.pipe())

  -- Merge default + user allowlist additions.
  local allowed = {}
  for k, v in pairs(DEFAULT_ALLOWED) do allowed[k] = v end
  for _, h in ipairs(opts.allow) do allowed[h] = {} end

  -- Fork the WRAPPER (becomes Claude after exec).
  local cmd_pid = assert(unix.fork())
  if cmd_pid == 0 then
    unix.close(pipe_w)
    -- Both isolation namespaces in one shot.
    assert(unix.unshare(unix.CLONE_NEWNET | unix.CLONE_NEWNS))
    -- Mark / private so our mounts don't leak back.
    assert(unix.mount("none", "/", nil,
                      unix.MS_REC | unix.MS_PRIVATE, nil))
    -- Build the FS jail (mounts + pivot_root).
    build_jail(opts, real_home)
    -- Wait for the proxy to come up.
    unix.read(pipe_r, 1)
    unix.close(pipe_r)
    -- Drop privileges last, so build_jail/etc. could use root.
    drop_privileges(real_uid, real_gid)
    -- Settle in the project dir so `claude` opens there by default.
    unix.chdir(opts.project)
    -- Build env (after drop, so HOME et al. still readable).
    local env = build_env(opts)
    local argv = {claude_bin}
    if opts.args then
      for _, a in ipairs(opts.args) do argv[#argv + 1] = a end
    end
    local _, err = unix.execvpe(claude_bin, argv, env)
    io.stderr:write("execvpe: " .. tostring(err) .. "\n")
    unix.exit(127)
  end

  unix.close(pipe_r)

  -- Open the wrapper's netns so the proxy can join it.
  local child_ns = assert(netns.open(cmd_pid))

  -- Fork the PROXY.
  local proxy_pid = assert(unix.fork())
  if proxy_pid == 0 then
    assert(unix.setns(child_ns, unix.CLONE_NEWNET))
    netns.bring_up("lo")  -- best-effort; lo is usually UP already
    local p = proxy.new{
      bind_ip        = LOOPBACK,
      bind_port      = PROXY_PORT,
      upstream_ns_fd = parent_ns,
      allowed_hosts  = allowed,
      log_level      = "info",
      log_format     = "json",  -- machine-readable for audit
    }
    assert(p:listen())
    unix.close(pipe_w)         -- signal wrapper to exec
    -- Have the proxy also drop to the invoking user — it doesn't
    -- need root either, only its already-bound listening fd.
    if real_uid ~= 0 then
      unix.setresgid(real_gid, real_gid, real_gid)
      unix.setresuid(real_uid, real_uid, real_uid)
    end
    p:serve_forever()
    unix.exit(0)
  end
  unix.close(pipe_w)
  unix.close(child_ns)
  unix.close(parent_ns)

  -- Forward signals; propagate the wrapper's exit code.
  local function forward(sig)
    pcall(unix.kill, cmd_pid, sig)
    pcall(unix.kill, proxy_pid, sig)
  end
  unix.sigaction(unix.SIGINT,  function() forward(unix.SIGINT)  end)
  unix.sigaction(unix.SIGTERM, function() forward(unix.SIGTERM) end)
  unix.sigaction(unix.SIGHUP,  function() forward(unix.SIGHUP)  end)

  while true do
    local pid, ws = unix.wait()
    if pid == cmd_pid then
      pcall(unix.kill, proxy_pid, unix.SIGTERM)
      pcall(unix.wait, proxy_pid)
      if unix.WIFEXITED(ws) then
        os.exit(unix.WEXITSTATUS(ws))
      elseif unix.WIFSIGNALED(ws) then
        os.exit(128 + unix.WTERMSIG(ws))
      else
        os.exit(1)
      end
    elseif pid == proxy_pid then
      io.stderr:write("claude-sandbox: proxy died unexpectedly\n")
      pcall(unix.kill, cmd_pid, unix.SIGTERM)
      pcall(unix.wait, cmd_pid)
      os.exit(1)
    end
  end
end

main(arg)
