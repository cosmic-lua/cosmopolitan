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
-- This script uses every cosmo.sandbox primitive. Read it as a worked
-- tutorial; copy and adapt for your own app.
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
local fs    = require "cosmo.sandbox.fs"
local proc  = require "cosmo.sandbox.proc"
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
-- Default policy. Edit these tables to retune.

-- Hosts the proxy will allow. `{}` means allowlisted with no header
-- injection (the default — TLS auth is end-to-end).
local DEFAULT_ALLOWED = {
  ["api.anthropic.com:443"]              = {},
  ["api.github.com:443"]                 = {},
  ["github.com:443"]                     = {},
  ["objects.githubusercontent.com:443"]  = {},
  ["codeload.github.com:443"]            = {},
  ["raw.githubusercontent.com:443"]      = {},
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
  "/etc/ssl",
  "/etc/ca-certificates", "/usr/share/ca-certificates",
  "/etc/pki",
  "/etc/nsswitch.conf", "/etc/passwd", "/etc/group",
}

-- Env vars to pass through. Anything else is dropped.
local PASS_ENV = {
  "HOME", "USER", "LOGNAME", "TERM", "LANG", "LC_ALL", "TZ",
  "PATH",
  "ANTHROPIC_API_KEY", "ANTHROPIC_BASE_URL",
  "GH_TOKEN", "GITHUB_TOKEN",
  "EDITOR", "VISUAL",
}

--------------------------------------------------------------------------------
-- FS jail. Built on cosmo.sandbox.fs primitives.
--
-- Order is load-bearing:
--   1. Compute the full bind list (defaults + user -bind + auto-bind
--      for the claude binary's parent dir if it lives outside any
--      already-bound path). Doing this up front avoids
--      "destination already exists" errors when -bind shadows a
--      later auto-bind.
--   2. Mount tmpfs root, then bind everything in.
--   3. Mount writable /tmp last so it doesn't shadow earlier binds.
--   4. pivot_root.

local function plan_binds(opts)
  -- Build {{src=..., ro=true|false}, ...} preserving user order.
  local seen, plan = {}, {}
  local function add(src, ro)
    if not seen[src] and fs.exists(src) then
      seen[src] = true
      plan[#plan + 1] = {src = src, ro = ro}
    end
  end
  for _, p in ipairs(DEFAULT_READONLY) do add(p, true) end
  for _, p in ipairs(opts.bind)        do add(p, true) end

  -- If the claude binary lives outside any already-bound path, bind
  -- its parent directory. Resolve this BEFORE adding the project /
  -- ~/.claude binds (so user -bind never shadows the auto-bind).
  if opts.claude_bin then
    local covered = false
    for _, ent in ipairs(plan) do
      if opts.claude_bin:sub(1, #ent.src) == ent.src then
        covered = true; break
      end
    end
    if not covered then
      local pdir = string.match(opts.claude_bin, "(.+)/[^/]+$")
      if pdir and fs.exists(pdir) then add(pdir, true) end
    end
  end

  return plan
end

local function build_jail(opts, real_home)
  local jail = "/tmp/claude-jail-" .. unix.getpid()
  assert(fs.tmpfs(jail, "128m"))

  for _, ent in ipairs(plan_binds(opts)) do
    local ok, err = fs.bind(ent.src, jail .. ent.src, {ro = ent.ro})
    if not ok then die("ro-bind %s: %s", ent.src, err) end
  end

  -- The project, writable.
  local ok, err = fs.bind(opts.project, jail .. opts.project)
  if not ok then die("project bind: %s", err) end

  -- ~/.claude (writable so Claude can persist its state).
  -- IMPORTANT: do not create it on the host as a side effect — if
  -- the user has no ~/.claude yet, give them an empty one inside the
  -- jail's tmpfs only. Their host home stays clean.
  if real_home then
    local cdir = real_home .. "/.claude"
    if fs.exists(cdir) then
      ok, err = fs.bind(cdir, jail .. cdir)
      if not ok then die("~/.claude bind: %s", err) end
    else
      -- Jail-only directory; gone when the sandbox exits.
      assert(unix.makedirs(jail .. cdir, fs.MODE_DIR_PRIV))
    end
  end

  -- Writable /tmp inside the jail, sticky-bit world-writable.
  ok, err = fs.tmpfs(jail .. "/tmp", "size=512m,mode=1777")
  if not ok then die("tmpfs /tmp: %s", err) end

  -- pivot_root.
  ok, err = fs.pivot_to(jail)
  if not ok then die("pivot_to: %s", err) end
end

--------------------------------------------------------------------------------
-- Environment construction.

local function build_env()
  local out = {}
  local host = unix.environ()
  for _, k in ipairs(PASS_ENV) do
    if host[k] then out[k] = host[k] end
  end
  out.HTTP_PROXY  = "http://127.0.0.1:" .. PROXY_PORT
  out.HTTPS_PROXY = out.HTTP_PROXY
  out.http_proxy  = out.HTTP_PROXY
  out.https_proxy = out.HTTP_PROXY
  out.NO_PROXY    = ""           -- don't exempt loopback
  out.no_proxy    = ""
  local env = {}
  for k, v in pairs(out) do env[#env + 1] = k .. "=" .. v end
  return env
end

--------------------------------------------------------------------------------
-- Main.

local function main(argv)
  if cosmo.GetHostOs() ~= "LINUX" then
    die("Linux only (this is %s)", cosmo.GetHostOs())
  end

  local opts = parse_args(argv)

  local claude_bin = opts.claude_bin
                  or unix.commandv("claude")
                  or unix.commandv("claude-code")
  if not claude_bin then die("can't find `claude` binary on PATH") end
  opts.claude_bin = claude_bin

  -- Capture the invoking user's identity BEFORE we fork.
  local real_uid = tonumber(os.getenv("SUDO_UID")) or unix.getuid()
  local real_gid = tonumber(os.getenv("SUDO_GID")) or unix.getgid()
  local real_home = os.getenv("SUDO_USER")
                    and ("/home/" .. os.getenv("SUDO_USER"))
                    or os.getenv("HOME")

  local parent_ns = assert(netns.open())
  local pipe_r, pipe_w = assert(unix.pipe())

  -- Merge default + user allowlist additions.
  local allowed = {}
  for k, v in pairs(DEFAULT_ALLOWED) do allowed[k] = v end
  for _, h in ipairs(opts.allow)    do allowed[h] = {} end

  -- Fork the WRAPPER (becomes Claude after exec).
  local cmd_pid, ferr = unix.fork()
  if not cmd_pid then die("fork(wrapper): %s", tostring(ferr)) end
  if cmd_pid == 0 then
    unix.close(pipe_w)
    -- Both isolation namespaces in one shot.
    assert(unix.unshare(unix.CLONE_NEWNET | unix.CLONE_NEWNS))
    assert(fs.private_root())
    build_jail(opts, real_home)
    -- Wait for the proxy to come up.
    unix.read(pipe_r, 1)
    unix.close(pipe_r)
    -- Drop privileges last, so build_jail/etc. could use root.
    assert(proc.drop_privs(real_uid, real_gid))
    assert(proc.no_new_privs())
    unix.chdir(opts.project)
    local env = build_env()
    local argv = {claude_bin}
    if opts.args then
      for _, a in ipairs(opts.args) do argv[#argv + 1] = a end
    end
    local _, err = unix.execvpe(claude_bin, argv, env)
    io.stderr:write("execvpe: " .. tostring(err) .. "\n")
    unix.exit(127)
  end

  unix.close(pipe_r)

  local child_ns, cerr = netns.open(cmd_pid)
  if not child_ns then
    unix.kill(cmd_pid, unix.SIGKILL)
    die("open child netns: %s", tostring(cerr))
  end

  -- Fork the PROXY.
  local proxy_pid, pferr = unix.fork()
  if not proxy_pid then
    unix.kill(cmd_pid, unix.SIGKILL)
    die("fork(proxy): %s", tostring(pferr))
  end
  if proxy_pid == 0 then
    assert(unix.setns(child_ns, unix.CLONE_NEWNET))
    netns.bring_up("lo")  -- best-effort; lo is usually UP already
    local p = proxy.new{
      bind_ip        = LOOPBACK,
      bind_port      = PROXY_PORT,
      upstream_ns_fd = parent_ns,
      allowed_hosts  = allowed,
      log_level      = "info",
      log_format     = "json",
    }
    assert(p:listen())
    unix.close(pipe_w)
    -- Drop UID for the proxy too — it doesn't need root, only its
    -- already-bound listening fd.
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

  -- Become PID-1 for the jail: forward SIGINT/SIGTERM/SIGHUP to the
  -- child, reap zombies, propagate the child's exit status, and kill
  -- the proxy if it dies first.
  os.exit(proc.become_init(cmd_pid, {
    sidecars = { proxy_pid },
    on_sidecar_exit = function(_, _)
      io.stderr:write("claude-sandbox: proxy died unexpectedly\n")
    end,
  }))
end

main(arg)
