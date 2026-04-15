#!/usr/bin/env lua
-- fs-jail.lua: minimal filesystem-isolation sandbox.
--
-- Demonstrates the FS primitives (CLONE_NEWNS + mount + pivot_root +
-- prctl(PR_SET_NO_NEW_PRIVS)) by building an ephemeral root that
-- contains only what the user's command actually needs.
--
-- The result is a process that:
--   - sees a tmpfs as its root filesystem
--   - has the host's /usr, /lib, /lib64, /bin (and any extra paths
--     given on the command line) bind-mounted read-only
--   - has its own writable /tmp (a fresh tmpfs)
--   - cannot regain dropped privileges via setuid binaries
--   - cannot escape to parent mounts (private mount namespace)
--
-- This is NOT a security boundary on its own — pair with the netns
-- proxy and/or capability dropping for real sandboxing. Its purpose
-- is to demonstrate composing the cosmo.sandbox primitives.
--
-- Usage:
--
--   sudo lua.com fs-jail.lua [-bind PATH]... -- COMMAND ARGS...
--
--   -bind PATH      bind-mount PATH read-only into the jail
--                   (defaults: /usr /lib /lib64 /bin /etc/resolv.conf)
--
-- Linux-only. Requires CAP_SYS_ADMIN (root).

local unix = require "unix"
local cosmo = require "cosmo"
local fs = require "cosmo.sandbox.fs"

local function die(fmt, ...)
  io.stderr:write("fs-jail: " .. string.format(fmt, ...) .. "\n")
  os.exit(1)
end

local function usage()
  io.stderr:write([==[
Usage: fs-jail [-bind PATH]... -- COMMAND ARGS...

Runs COMMAND in a private mount namespace whose root is a fresh
tmpfs. Only the bind-mounted paths (default: /usr /lib /lib64 /bin
/etc/resolv.conf, plus any -bind PATH on the command line) are
visible inside the jail. /tmp is a fresh writable tmpfs.

NO_NEW_PRIVS is set in the child so dropped privileges cannot be
regained via setuid binaries. Linux-only; requires CAP_SYS_ADMIN.
]==])
end

local function parse_args(argv)
  local bindings = {}
  local cmd
  local i = 1
  while i <= #argv do
    local a = argv[i]
    if a == "-h" or a == "--help" then
      usage()
      os.exit(0)
    elseif a == "-bind" or a == "--bind" then
      bindings[#bindings + 1] = argv[i + 1]
      if not bindings[#bindings] then die("-bind needs a path argument") end
      i = i + 2
    elseif a == "--" then
      cmd = {table.unpack(argv, i + 1)}
      break
    else
      die("unknown argument: %s", a)
    end
  end
  if not cmd or #cmd == 0 then
    usage()
    die("no command given (use `-- cmd args`)")
  end
  return bindings, cmd
end

-- Default paths every reasonable program will want.
local DEFAULT_BINDS = {
  "/usr", "/lib", "/lib64", "/bin",
  "/etc/resolv.conf",  -- needed for DNS-using tools
}

local function main(argv)
  if cosmo.GetHostOs() ~= "LINUX" then
    die("Linux only (this is %s)", cosmo.GetHostOs())
  end

  local extra_binds, cmd = parse_args(argv)

  -- Build the full list of paths to bind, deduplicated.
  local binds, seen = {}, {}
  for _, p in ipairs(DEFAULT_BINDS) do
    if not seen[p] and fs.exists(p) then
      seen[p] = true; binds[#binds + 1] = p
    end
  end
  for _, p in ipairs(extra_binds) do
    if not seen[p] then
      if not fs.exists(p) then die("-bind %s does not exist", p) end
      seen[p] = true; binds[#binds + 1] = p
    end
  end

  -- Step 1: enter a private mount namespace so our mounts don't leak
  -- back to the parent.
  local ok, err = unix.unshare(unix.CLONE_NEWNS)
  if not ok then die("unshare(CLONE_NEWNS): %s", tostring(err)) end
  ok, err = fs.private_root()
  if not ok then die("mount-private /: %s", tostring(err)) end

  -- Step 2: build the jail under a fresh tmpfs.
  local jail = "/tmp/fs-jail-" .. unix.getpid()
  ok, err = fs.tmpfs(jail, "64m")
  if not ok then die("%s", err) end

  for _, p in ipairs(binds) do
    local ok, err = fs.bind_ro(p, jail .. p)
    if not ok then die("%s", err) end
  end

  -- Writable /tmp inside the jail (sticky-bit, world-writable).
  ok, err = fs.tmpfs(jail .. "/tmp", "size=16m,mode=1777")
  if not ok then die("%s", err) end

  -- Step 3: pivot_root into the jail.
  ok, err = fs.pivot_to(jail)
  if not ok then die("pivot_to(%s): %s", jail, tostring(err)) end

  -- Step 4: harden. NO_NEW_PRIVS prevents setuid escalation.
  ok, err = unix.prctl(unix.PR_SET_NO_NEW_PRIVS, 1)
  if not ok then die("prctl(NO_NEW_PRIVS): %s", tostring(err)) end

  -- Step 5: exec the user's command.
  local _, eerr = unix.execvp(cmd[1], cmd)
  die("execvp(%s): %s", cmd[1], tostring(eerr))
end

main(arg)
