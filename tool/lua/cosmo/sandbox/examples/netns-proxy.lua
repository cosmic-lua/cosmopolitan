#!/usr/bin/env lua
-- netns-proxy.lua: a network-namespace sandbox with an HTTP CONNECT
-- + plain-HTTP allowlist proxy as the only network path out.
--
-- This is a worked example reproducing the design of the Go "sandbox"
-- tool, built on top of cosmo.sandbox primitives.
--
-- Topology:
--
--      parent process (original netns)
--      ├── proxy worker (in CHILD netns; listens on 127.0.0.1:3128;
--      │                 dials upstream after setns(parent_ns_fd))
--      └── sandboxed command (in CHILD netns; HTTP_PROXY=http://127.0.0.1:3128;
--                             can ONLY reach 127.0.0.1)
--
-- Usage:
--
--   sudo lua.com netns-proxy.lua -config conf.lua
--   sudo lua.com netns-proxy.lua -config conf.lua -- curl https://api.github.com
--   sudo lua.com netns-proxy.lua -- bash    -- open allowlist (still isolated)
--
-- Linux-only. Requires root or CAP_SYS_ADMIN+CAP_NET_ADMIN.
--
-- Exit codes:
--   0    child exited 0
--   1    child exited nonzero (status mirrored when 1..127)
--   2    permission denied (CAP_SYS_ADMIN missing)
--   3    netns setup failed (unshare / lo bring-up)
--   4    proxy setup failed (bind / listen)
--   5    bad usage / config
--   6    non-Linux host

local unix = require "unix"
local netns = require "cosmo.sandbox.netns"
local proxy = require "cosmo.sandbox.proxy"

local EXIT_OK         = 0
local EXIT_CHILD_FAIL = 1
local EXIT_PERM       = 2
local EXIT_NETNS      = 3
local EXIT_PROXY      = 4
local EXIT_USAGE      = 5
local EXIT_PLATFORM   = 6

local function die(code, fmt, ...)
  io.stderr:write("netns-proxy: " .. string.format(fmt, ...) .. "\n")
  os.exit(code)
end

local function usage()
  io.stderr:write([[
Usage: netns-proxy [-config FILE] [-- COMMAND ARGS...]

Wraps a child command in a fresh Linux network namespace. The only
network path out is an HTTP CONNECT + plain-HTTP allowlist proxy
listening on 127.0.0.1:3128 inside the child namespace.

Options:
  -config FILE   Load a Lua config table from FILE.
  --             Pass everything after this as the command + args
                 to run inside the sandbox. Overrides config.command.
  -h, --help     Show this help.

Config schema (Lua table returned by FILE):
  {
    proxy_addr    = "127.0.0.1:3128",       -- default
    allowed_hosts = {
      ["api.github.com:443"]    = {type="bearer", token="ghp_..."},
      ["api.anthropic.com:443"] = {type="header",
                                    header_name="x-api-key",
                                    header_value="sk-..."},
      ["registry.npmjs.org:*"]  = {},       -- any port
      ["pypi.org"]              = {},
    },
    command = {"npm", "install"},           -- run if no -- on cmdline
    log_level = "info",                     -- quiet|info|debug
    log_format = "text",                    -- text|json
    log_file   = nil,                       -- path or nil for stderr
    env_passthrough = nil,                  -- nil = pass all host env;
                                            -- table = list of names
    env_set = {},                           -- extra env to set
  }
]])
end

--------------------------------------------------------------------------------
-- Argv parsing.

local function parse_args(argv)
  local opts = {config = nil, cmd = nil}
  local i = 1
  while i <= #argv do
    local a = argv[i]
    if a == "-h" or a == "--help" then
      usage()
      os.exit(EXIT_OK)
    elseif a == "-config" or a == "--config" then
      opts.config = argv[i + 1]
      i = i + 2
    elseif a == "--" then
      opts.cmd = {table.unpack(argv, i + 1)}
      break
    else
      die(EXIT_USAGE, "unknown argument: %s", a)
    end
  end
  return opts
end

--------------------------------------------------------------------------------
-- Config loading.

local function load_config(path)
  if not path then return {} end
  local chunk, err = loadfile(path, "t", {})
  if not chunk then
    die(EXIT_USAGE, "cannot load config %q: %s", path, tostring(err))
  end
  local ok, t = pcall(chunk)
  if not ok then
    die(EXIT_USAGE, "config %q raised: %s", path, tostring(t))
  end
  if type(t) ~= "table" then
    die(EXIT_USAGE, "config %q must return a table, got %s",
        path, type(t))
  end
  return t
end

local function parse_proxy_addr(addr)
  if not addr then return nil, 3128 end
  local h, p = addr:match("^(.-):(%d+)$")
  if not h then
    die(EXIT_USAGE, "proxy_addr must be host:port, got %q", addr)
  end
  return h, tonumber(p)
end

--------------------------------------------------------------------------------
-- Environment construction.

local function build_child_env(cfg, proxy_url)
  local out = {}
  local pass = cfg.env_passthrough  -- nil = all
  if pass then
    local set = {}
    for _, name in ipairs(pass) do set[name] = true end
    for k, v in pairs(unix.environ()) do
      if set[k] then out[k] = v end
    end
  else
    for k, v in pairs(unix.environ()) do out[k] = v end
  end
  for k, v in pairs(cfg.env_set or {}) do out[k] = v end
  out.HTTP_PROXY  = proxy_url
  out.HTTPS_PROXY = proxy_url
  out.http_proxy  = proxy_url
  out.https_proxy = proxy_url
  -- Encourage tools NOT to bypass the proxy for loopback (they often
  -- exempt it by default).
  out.NO_PROXY = ""
  out.no_proxy = ""
  -- Re-emit as "K=V" array for execve.
  local env = {}
  for k, v in pairs(out) do env[#env + 1] = k .. "=" .. v end
  return env
end

--------------------------------------------------------------------------------
-- Main.

local function main(argv)
  -- Platform check.
  local u = unix.uname and unix.uname() or nil
  if u and u.sysname and u.sysname ~= "Linux" then
    die(EXIT_PLATFORM, "Linux only (this is %s)", u.sysname)
  end

  local opts = parse_args(argv)
  local cfg = load_config(opts.config)
  local cmd = opts.cmd or cfg.command
  if not cmd or #cmd == 0 then
    die(EXIT_USAGE, "no command given (use `-- cmd args` or set config.command)")
  end

  local proxy_host, proxy_port = parse_proxy_addr(cfg.proxy_addr)
  proxy_host = proxy_host or "127.0.0.1"
  local proxy_url = "http://" .. proxy_host .. ":" .. proxy_port

  -- Save the parent's netns fd so we can pass it to the proxy for
  -- cross-namespace upstream dialing.
  local parent_ns, popen_err = netns.open()
  if not parent_ns then
    die(EXIT_NETNS, "open(/proc/self/ns/net): %s", popen_err)
  end

  -- Pipe used to gate the child: it blocks on read until we close the
  -- write end after the proxy is up.
  local r, w = unix.pipe()
  if not r then
    die(EXIT_NETNS, "pipe: %s", tostring(w))
  end

  -- Fork the sandboxed shell wrapper. It will unshare(CLONE_NEWNET),
  -- wait for the parent to set up the proxy, then exec the user's
  -- command. The parent observes the wrapper's pid in /proc to get
  -- a netns fd.
  local cmd_pid = unix.fork()
  if not cmd_pid then
    die(EXIT_NETNS, "fork: %s", tostring(unix.environ()))
  end
  if cmd_pid == 0 then
    unix.close(w)
    local ok, err = unix.unshare(unix.CLONE_NEWNET)
    if not ok then
      io.stderr:write("netns-proxy: child unshare: " .. tostring(err) .. "\n")
      unix.exit(EXIT_NETNS)
    end
    -- Block until the parent finishes proxy setup.
    local _ = unix.read(r, 1)
    unix.close(r)
    local env = build_child_env(cfg, proxy_url)
    local _, eerr = unix.execvpe(cmd[1], cmd, env)
    io.stderr:write("netns-proxy: execvp(" .. cmd[1] .. "): "
                    .. tostring(eerr) .. "\n")
    unix.exit(127)
  end

  -- Parent: install the child's netns fd so we can spawn the proxy
  -- inside it.
  unix.close(r)
  local child_ns, cerr = netns.open(cmd_pid)
  if not child_ns then
    unix.kill(cmd_pid, unix.SIGKILL)
    die(EXIT_NETNS, "open child netns: %s", cerr)
  end

  -- Fork the proxy. It enters the child's netns via setns(), brings
  -- up loopback if it has CAP_NET_ADMIN, binds, then serves forever.
  local proxy_pid = unix.fork()
  if not proxy_pid then
    unix.kill(cmd_pid, unix.SIGKILL)
    die(EXIT_PROXY, "fork(proxy)")
  end
  if proxy_pid == 0 then
    local ok, err = unix.setns(child_ns, unix.CLONE_NEWNET)
    if not ok then
      io.stderr:write("netns-proxy: proxy setns: " .. tostring(err) .. "\n")
      unix.exit(EXIT_PROXY)
    end
    -- Best-effort lo bring-up. Many environments deny this; loopback
    -- is often UP by default in fresh netns anyway.
    netns.bring_up("lo")
    local p = proxy.new{
      bind_ip = require("cosmo").ParseIp(proxy_host),
      bind_port = proxy_port,
      allowed_hosts = cfg.allowed_hosts or {},
      upstream_ns_fd = parent_ns,
      log_level = cfg.log_level or "info",
      log_format = cfg.log_format or "text",
      log_file = cfg.log_file,
    }
    local lfd, lerr, lerrno = p:listen()
    if not lfd then
      io.stderr:write("netns-proxy: proxy listen: " .. tostring(lerr) .. "\n")
      unix.exit(lerrno == unix.EACCES and EXIT_PERM or EXIT_PROXY)
    end
    -- Signal the wrapper that it's safe to exec.
    unix.close(w)
    p:serve_forever()
    unix.exit(EXIT_OK)
  end

  -- Parent: wait for either the wrapper or the proxy to exit. If the
  -- wrapper exits first (normal path), kill the proxy and propagate
  -- the wrapper's exit status.
  unix.close(w)
  unix.close(child_ns)
  unix.close(parent_ns)

  local function forward(sig)
    pcall(unix.kill, cmd_pid, sig)
    pcall(unix.kill, proxy_pid, sig)
  end
  unix.sigaction(unix.SIGINT,  function() forward(unix.SIGINT)  end)
  unix.sigaction(unix.SIGTERM, function() forward(unix.SIGTERM) end)
  unix.sigaction(unix.SIGHUP,  function() forward(unix.SIGHUP)  end)

  while true do
    local pid, ws = unix.wait()
    if not pid then
      if ws and ws.errno and ws:errno() == unix.EINTR then
        -- got a signal we forwarded; loop and reap
      else
        io.stderr:write("netns-proxy: wait: " .. tostring(ws) .. "\n")
        os.exit(EXIT_CHILD_FAIL)
      end
    elseif pid == cmd_pid then
      pcall(unix.kill, proxy_pid, unix.SIGTERM)
      pcall(unix.wait, proxy_pid)
      if unix.WIFEXITED(ws) then
        os.exit(unix.WEXITSTATUS(ws))
      elseif unix.WIFSIGNALED(ws) then
        os.exit(128 + unix.WTERMSIG(ws))
      else
        os.exit(EXIT_CHILD_FAIL)
      end
    elseif pid == proxy_pid then
      io.stderr:write("netns-proxy: proxy exited unexpectedly\n")
      pcall(unix.kill, cmd_pid, unix.SIGTERM)
      pcall(unix.wait, cmd_pid)
      os.exit(EXIT_PROXY)
    end
  end
end

main(arg)
