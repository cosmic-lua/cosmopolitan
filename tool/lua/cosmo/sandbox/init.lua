-- cosmo.sandbox: Linux process-isolation primitives.
--
-- This module re-exports thin wrappers around the Cosmopolitan `unix.*`
-- isolation syscalls and will progressively surface higher-level helpers
-- (e.g. `cosmo.sandbox.netns`, `cosmo.sandbox.proxy`) as they land.
--
-- The whole library is Linux-only; calling any primitive on a non-Linux
-- host returns nil,"ENOSYS",unix.ENOSYS so callers can degrade cleanly.
--
-- Status: unix.* wrappers are the stable API tier; everything under
-- cosmo.sandbox.* is experimental and may change shape between
-- cosmopolitan releases.

local unix = require "unix"

local M = {
  _VERSION = "0.0.1",
}

-- True when the primitives in this module can do real work.
function M.is_supported()
  local u = unix.uname and unix.uname() or nil
  if u and u.sysname and u.sysname ~= "Linux" then
    return false
  end
  -- Presence of CLONE_NEWNET is our compile-time indicator that the
  -- namespace bindings are linked in.
  return unix.CLONE_NEWNET ~= nil
end

return M
