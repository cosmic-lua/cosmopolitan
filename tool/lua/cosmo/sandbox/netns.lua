-- cosmo.sandbox.netns: network-namespace helpers.
--
-- Thin, composable pieces built on the `unix.*` namespace + ioctl
-- primitives. Each function returns nil,errstr,errno on failure, matching
-- the rest of the cosmo unix-style API.
--
-- Typical flow inside a forked child:
--
--     local netns = require "cosmo.sandbox.netns"
--     assert(unix.unshare(unix.CLONE_NEWNET))
--     assert(netns.bring_up("lo"))
--     -- loopback is now reachable at 127.0.0.1 in this namespace
--
-- Typical flow in the parent (to enter a child's namespace fd-wise):
--
--     local fd = assert(unix.open("/proc/" .. child_pid .. "/ns/net",
--                                 unix.O_RDONLY))
--     assert(unix.setns(fd, unix.CLONE_NEWNET))
--
-- Linux-only.

local unix = require "unix"

local M = {}

-- Build a `struct ifreq` suitable for passing to SIOCSIFFLAGS /
-- SIOCGIFFLAGS. The Linux layout is char name[16] followed by a 24-byte
-- union; we populate ifr_name and ifr_flags at offsets 0 and 16.
--
-- `name` must be a printable interface name (e.g. "lo"), at most
-- IFNAMSIZ-1 bytes. `flags` is an int16 bitmask of IFF_* values.
local function build_ifreq(name, flags)
  assert(type(name) == "string", "interface name must be a string")
  assert(#name < unix.IFNAMSIZ, "interface name too long")
  local name_field = name .. string.rep("\0", unix.IFNAMSIZ - #name)
  local flags_field = string.pack("<i2", flags or 0)
  -- Pad the union to 24 bytes (largest union member).
  return name_field .. flags_field .. string.rep("\0", 24 - #flags_field)
end
M.build_ifreq = build_ifreq

-- Parse the 16-bit flags field out of an ifreq returned by ioctl().
local function parse_ifreq_flags(ifr)
  return (string.unpack("<i2", ifr, unix.IFNAMSIZ + 1))
end
M.parse_ifreq_flags = parse_ifreq_flags

-- Open an AF_INET dgram socket suitable for use as the "fd" argument to
-- the SIOC* interface-configuration ioctls. The caller owns the fd and
-- should close it.
local function control_socket()
  local sk, err = unix.socket(unix.AF_INET, unix.SOCK_DGRAM, 0)
  if not sk then
    return nil, tostring(err), err and err:errno()
  end
  return sk
end
M.control_socket = control_socket

-- Read the current IFF_* flags on `name` in the current net namespace.
--   cosmo.sandbox.netns.get_flags("lo") → flags:int | nil,err,errno
function M.get_flags(name)
  local sk, err, errno = control_socket()
  if not sk then return nil, err, errno end
  local result, ioerr = unix.ioctl(sk, unix.SIOCGIFFLAGS, build_ifreq(name, 0))
  unix.close(sk)
  if not result then
    return nil, tostring(ioerr), ioerr and ioerr:errno()
  end
  return parse_ifreq_flags(result)
end

-- Set the IFF_* flags on `name` in the current net namespace.
--   cosmo.sandbox.netns.set_flags("lo", unix.IFF_UP) → true | nil,err,errno
function M.set_flags(name, flags)
  local sk, err, errno = control_socket()
  if not sk then return nil, err, errno end
  local ok, ioerr = unix.ioctl(sk, unix.SIOCSIFFLAGS,
                               build_ifreq(name, flags))
  unix.close(sk)
  if not ok then
    return nil, tostring(ioerr), ioerr and ioerr:errno()
  end
  return true
end

-- Bring `name` up in the current net namespace (reads flags, sets
-- IFF_UP, writes them back). Idempotent.
--   cosmo.sandbox.netns.bring_up("lo") → true | nil,err,errno
function M.bring_up(name)
  local flags, err, errno = M.get_flags(name)
  if not flags then return nil, err, errno end
  return M.set_flags(name, flags | unix.IFF_UP)
end

-- Bring `name` down.
function M.bring_down(name)
  local flags, err, errno = M.get_flags(name)
  if not flags then return nil, err, errno end
  return M.set_flags(name, flags & ~unix.IFF_UP)
end

-- Open the network namespace of `pid` as a file descriptor. For the
-- current process, use pid == nil (or "self").
--   cosmo.sandbox.netns.open() → fd:int | nil,err,errno
function M.open(pid)
  local tag = pid and tostring(pid) or "self"
  local fd, err = unix.open("/proc/" .. tag .. "/ns/net", unix.O_RDONLY)
  if not fd then
    return nil, tostring(err), err and err:errno()
  end
  return fd
end

return M
