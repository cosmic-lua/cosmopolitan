--- cosmo.sandbox.fs: filesystem-isolation helpers.
---
--- Composable pieces built on the `unix.*` mount + pivot_root +
--- chroot primitives. The two main consumers are the netns-proxy and
--- claude-code examples, but any caller building a private mount
--- namespace can use them.
---
--- All helpers return `nil, unix.Errno` on failure, matching the
--- rest of cosmo's lunix API. Callers add their own context string
--- at the call site (they know what operation they were doing);
--- programmatic errno checks use `err:errno() == unix.EACCES` and
--- human-readable strings come from `tostring(err)`.
---
--- Linux-only.

local unix = require "unix"

local M = {}

--- Octal mode constants. Lua has no octal literal, so define them once
--- explicitly (instead of accidentally writing `0x755` and getting
--- decimal 1877 / octal 03525).
M.MODE_DIR        = tonumber("755",  8)  -- 0o755 = 493 = rwxr-xr-x
M.MODE_DIR_PRIV   = tonumber("700",  8)  -- 0o700 = 448 = rwx------
M.MODE_FILE       = tonumber("644",  8)  -- 0o644 = 420 = rw-r--r--
M.MODE_TMP_STICKY = tonumber("1777", 8)  -- 0o1777      = sticky+rwxrwxrwx

--- True if `path` exists (any type).
function M.exists(path)
  return unix.stat(path) ~= nil
end

-- Return the parent dir of `path` (or "/" for top-level).
local function parent_dir(path)
  return string.match(path, "(.+)/[^/]+$") or "/"
end

-- Create a mount-point at `dst` matching the type of `src` — a
-- directory if src is a directory, else an empty file. Used internally
-- by bind() to ensure dst exists with the right kind before mounting.
local function ensure_mountpoint(src, dst)
  local st, err = unix.stat(src)
  if not st then return nil, err end
  if (st:mode() & 0xf000) == 0x4000 then
    -- Directory: makedirs is idempotent.
    local ok, err = unix.makedirs(dst, M.MODE_DIR)
    if not ok then return nil, err end
  else
    -- File-like: ensure parent dir, then touch the dst as an empty file.
    local ok, err = unix.makedirs(parent_dir(dst), M.MODE_DIR)
    if not ok then return nil, err end
    if not M.exists(dst) then
      local fd, ferr = unix.open(dst, unix.O_WRONLY | unix.O_CREAT,
                                 M.MODE_FILE)
      if not fd then return nil, ferr end
      unix.close(fd)
    end
  end
  return true
end

--- fs.bind(src, dst[, opts]) → true | nil, err
---
--- Bind-mount `src` onto `dst` (creating dst as a file or directory as
--- needed), optionally remounting read-only. opts.ro = true requests a
--- read-only bind. opts.rec = false disables MS_REC (default true).
function M.bind(src, dst, opts)
  opts = opts or {}
  local rec = opts.rec ~= false
  local ok, err = ensure_mountpoint(src, dst)
  if not ok then return nil, err end
  local flags = unix.MS_BIND | (rec and unix.MS_REC or 0)
  ok, err = unix.mount(src, dst, nil, flags, nil)
  if not ok then return nil, err end
  if opts.ro then
    flags = unix.MS_REMOUNT | unix.MS_BIND | unix.MS_RDONLY
            | (rec and unix.MS_REC or 0)
    ok, err = unix.mount("none", dst, nil, flags, nil)
    if not ok then return nil, err end
  end
  return true
end

--- fs.bind_ro(src, dst) → true | nil, err
---
--- Convenience: read-only recursive bind.
function M.bind_ro(src, dst)
  return M.bind(src, dst, {ro = true})
end

--- fs.tmpfs(dst, size_or_data) → true | nil, err
---
--- Mount a tmpfs at `dst`. `size_or_data` is either a size string
--- ("128m") or a full mount-data string ("size=128m,mode=755").
--- Creates `dst` if missing.
function M.tmpfs(dst, size_or_data)
  local data
  if type(size_or_data) == "string" then
    if size_or_data:find("=") then
      data = size_or_data
    else
      data = "size=" .. size_or_data
    end
  end
  local ok, err = unix.makedirs(dst, M.MODE_DIR)
  if not ok then return nil, err end
  ok, err = unix.mount("tmpfs", dst, "tmpfs", 0, data)
  if not ok then return nil, err end
  return true
end

--- fs.private_root() → true | nil, err
---
--- Mark the existing root mount tree as MS_PRIVATE recursively, so
--- subsequent mounts in this namespace don't propagate to the host.
--- Many distros default to "shared". Call this immediately after
--- unshare(CLONE_NEWNS).
function M.private_root()
  local ok, err = unix.mount("none", "/", nil,
                             unix.MS_REC | unix.MS_PRIVATE, nil)
  if not ok then return nil, err end
  return true
end

--- fs.pivot_to(jail) → true | nil, err
---
--- Pivot the current mount namespace's root into `jail`. Detaches the
--- old root via unmount(MNT_DETACH) and removes the temporary
--- /.old mountpoint. Caller must have already populated `jail` with
--- the desired contents.
function M.pivot_to(jail)
  local old = jail .. "/.old"
  local ok, err = unix.makedirs(old, M.MODE_DIR_PRIV)
  if not ok then return nil, err end
  ok, err = unix.chdir(jail)
  if not ok then return nil, err end
  ok, err = unix.pivot_root(".", ".old")
  if not ok then return nil, err end
  ok, err = unix.chdir("/")
  if not ok then return nil, err end
  ok, err = unix.unmount("/.old", unix.MNT_DETACH)
  if not ok then return nil, err end
  unix.rmdir("/.old")
  return true
end

return M
