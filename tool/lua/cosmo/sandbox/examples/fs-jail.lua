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

local function die(fmt, ...)
  io.stderr:write("fs-jail: " .. string.format(fmt, ...) .. "\n")
  os.exit(1)
end

local function usage()
  io.stderr:write([[
Usage: fs-jail [-bind PATH]... -- COMMAND ARGS...

Runs COMMAND in a private mount namespace whose root is a fresh
tmpfs. Only the bind-mounted paths (default: /usr /lib /lib64 /bin
/etc/resolv.conf, plus any -bind PATH on the command line) are
visible inside the jail. /tmp is a fresh writable tmpfs.

NO_NEW_PRIVS is set in the child so dropped privileges cannot be
regained via setuid binaries. Linux-only; requires CAP_SYS_ADMIN.
]])
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

local function exists(path)
  local st = unix.stat(path)
  return st ~= nil
end

-- Bind-mount `src` onto `dst` (creating dst as a file or directory
-- as needed), then remount as read-only. Idempotent.
local function bind_ro(src, dst)
  local st = unix.stat(src)
  if not st then return false, "source missing: " .. src end
  -- Create the mount point. Linux requires the destination to exist
  -- and be a file for file binds, a directory for directory binds.
  if (st:mode() & 0xf000) == 0x4000 then  -- directory
    unix.makedirs(dst, 0x755)
  else
    unix.makedirs(string.match(dst, "(.+)/[^/]+$") or "/", 0x755)
    local fd = unix.open(dst, unix.O_WRONLY | unix.O_CREAT, 0x644)
    if fd then unix.close(fd) end
  end
  local ok, err = unix.mount(src, dst, nil,
                             unix.MS_BIND | unix.MS_REC, nil)
  if not ok then return false, "bind " .. src .. ": " .. tostring(err) end
  -- Remount read-only.
  ok, err = unix.mount("none", dst, nil,
                       unix.MS_REMOUNT | unix.MS_BIND |
                       unix.MS_RDONLY | unix.MS_REC, nil)
  if not ok then return false, "ro-remount " .. dst .. ": " .. tostring(err) end
  return true
end

local function main(argv)
  local u = unix.uname and unix.uname() or nil
  if u and u.sysname and u.sysname ~= "Linux" then
    die("Linux only (this is %s)", u.sysname)
  end

  local extra_binds, cmd = parse_args(argv)

  -- Build the full list of paths to bind, deduplicated.
  local binds, seen = {}, {}
  for _, p in ipairs(DEFAULT_BINDS) do
    if not seen[p] and exists(p) then
      seen[p] = true; binds[#binds + 1] = p
    end
  end
  for _, p in ipairs(extra_binds) do
    if not seen[p] then
      if not exists(p) then die("-bind %s does not exist", p) end
      seen[p] = true; binds[#binds + 1] = p
    end
  end

  -- Step 1: enter a private mount namespace so our mounts don't leak
  -- back to the parent.
  local ok, err = unix.unshare(unix.CLONE_NEWNS)
  if not ok then die("unshare(CLONE_NEWNS): %s", tostring(err)) end
  -- Mark the existing root as PRIVATE so subsequent mounts under it
  -- don't propagate to the host. (Many distros default to "shared".)
  ok, err = unix.mount("none", "/", nil,
                       unix.MS_REC | unix.MS_PRIVATE, nil)
  if not ok then die("mount-private /: %s", tostring(err)) end

  -- Step 2: build the jail under a fresh tmpfs.
  local jail = "/tmp/fs-jail-" .. unix.getpid()
  unix.makedirs(jail, 0x700)
  ok, err = unix.mount("tmpfs", jail, "tmpfs", 0, "size=64m")
  if not ok then die("tmpfs at %s: %s", jail, tostring(err)) end

  for _, p in ipairs(binds) do
    local ok, err = bind_ro(p, jail .. p)
    if not ok then die("%s", err) end
  end

  -- Writable /tmp inside the jail.
  unix.makedirs(jail .. "/tmp", 0x755)
  ok, err = unix.mount("tmpfs", jail .. "/tmp", "tmpfs", 0, "size=16m")
  if not ok then die("tmpfs /tmp: %s", tostring(err)) end

  -- Step 3: pivot_root into the jail. Save the old root under jail/.old.
  local old = jail .. "/.old"
  unix.makedirs(old, 0x700)
  ok, err = unix.chdir(jail)
  if not ok then die("chdir %s: %s", jail, tostring(err)) end
  ok, err = unix.pivot_root(".", ".old")
  if not ok then die("pivot_root: %s", tostring(err)) end
  ok, err = unix.chdir("/")
  if not ok then die("chdir /: %s", tostring(err)) end
  -- Detach the old root and remove the empty mount point.
  ok, err = unix.unmount("/.old", 2)  -- MNT_DETACH = 2 on Linux
  if not ok then die("unmount /.old: %s", tostring(err)) end
  unix.rmdir("/.old")

  -- Step 4: harden. NO_NEW_PRIVS prevents setuid escalation.
  unix.prctl(unix.PR_SET_NO_NEW_PRIVS, 1)

  -- Step 5: exec the user's command.
  local _, eerr = unix.execvp(cmd[1], cmd)
  die("execvp(%s): %s", cmd[1], tostring(eerr))
end

main(arg)
