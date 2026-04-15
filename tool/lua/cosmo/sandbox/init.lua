-- cosmo.sandbox: Linux process-isolation primitives.
--
-- This module is the entry point for the Cosmopolitan Lua sandbox
-- library. The pieces it exposes are thin wrappers around `unix.*`
-- syscalls plus higher-level helpers:
--
--     cosmo.sandbox.netns   network namespace helpers
--     cosmo.sandbox.fs      filesystem (bind/tmpfs/pivot) helpers
--     cosmo.sandbox.proxy   HTTP CONNECT + plain-HTTP allowlist proxy
--
-- All helpers and their underlying `unix.*` syscalls return
-- `nil, unix.Errno` on failure (matching the rest of cosmo's lunix
-- conventions). Callers can `:errno()` the Errno object for the
-- integer code or `tostring()` for a human-readable string.
--
-- The whole library is Linux-only. On non-Linux hosts the syscalls
-- return ENOSYS and `is_supported()` returns false.
--
-- Status: `unix.*` wrappers are the stable API tier; everything under
-- `cosmo.sandbox.*` is experimental and may evolve based on usage.

local unix = require "unix"
local cosmo = require "cosmo"

local M = {
  _VERSION = "0.0.2",
}

-- True when the primitives in this module can do real work — i.e.
-- we're running on Linux and the namespace bindings are linked in.
function M.is_supported()
  return cosmo.GetHostOs() == "LINUX" and unix.CLONE_NEWNET ~= nil
end

return M
