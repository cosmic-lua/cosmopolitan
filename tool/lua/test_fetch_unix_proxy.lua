-- Test for unix:// socket proxy support in Fetch and FetchStream
-- Tests error handling (path validation) which is the core security fix
-- Functional proxy tests require forking and may not work in all CI environments

local cosmo = require("cosmo")
local unix = require("cosmo.unix")

local tmpdir = os.getenv("TMPDIR") or "/tmp"
local sockpath = tmpdir .. "/test-proxy-" .. unix.getpid() .. ".sock"

-- Helper for assertions
local function check(desc, cond)
  if not cond then
    error("FAILED: " .. desc)
  end
end

-- Cleanup function
local function cleanup()
  pcall(function() unix.unlink(sockpath) end)
end

--------------------------------------------------------------------------------
-- Test 1: Error - missing socket path
--------------------------------------------------------------------------------
local function test_missing_path()
  local status, headers, body = cosmo.Fetch("http://example.com", {
    proxy = "unix://"
  })
  check("missing path should fail", status == nil)
  check("error mentions socket path", headers:find("socket path"))
end

--------------------------------------------------------------------------------
-- Test 2: Error - socket path too long (SECURITY FIX)
-- This prevents silent truncation which could lead to connecting to
-- unintended sockets
--------------------------------------------------------------------------------
local function test_path_too_long()
  -- sun_path is 108 bytes on Linux
  -- Use unix:/// (three slashes) so the long string is in path, not host
  local long_path = "unix:///" .. string.rep("a", 200)
  local status, headers, body = cosmo.Fetch("http://example.com", {
    proxy = long_path
  })
  check("long path should fail", status == nil)
  check("error mentions too long", headers:find("too long"))
end

--------------------------------------------------------------------------------
-- Test 3: Error - socket doesn't exist
--------------------------------------------------------------------------------
local function test_socket_not_found()
  local status, headers, body = cosmo.Fetch("http://example.com", {
    proxy = "unix:///nonexistent/path/to/socket.sock"
  })
  check("nonexistent socket should fail", status == nil)
  check("error mentions connect failure", headers:find("connect") or headers:find("failed"))
end

--------------------------------------------------------------------------------
-- Test 4: FetchStream error - missing socket path
--------------------------------------------------------------------------------
local function test_stream_missing_path()
  local status, err = cosmo.FetchStream("http://example.com", {
    proxy = "unix://"
  })
  check("FetchStream missing path should fail", status == nil)
  check("error mentions socket path", err:find("socket path"))
end

--------------------------------------------------------------------------------
-- Test 5: FetchStream error - socket path too long (SECURITY FIX)
--------------------------------------------------------------------------------
local function test_stream_path_too_long()
  -- Use unix:/// (three slashes) so the long string is in path, not host
  local long_path = "unix:///" .. string.rep("a", 200)
  local status, err = cosmo.FetchStream("http://example.com", {
    proxy = long_path
  })
  check("FetchStream long path should fail", status == nil)
  check("error mentions too long", err:find("too long"))
end

--------------------------------------------------------------------------------
-- Test 6: FetchStream error - socket doesn't exist
--------------------------------------------------------------------------------
local function test_stream_socket_not_found()
  local status, err = cosmo.FetchStream("http://example.com", {
    proxy = "unix:///nonexistent/path/to/socket.sock"
  })
  check("FetchStream nonexistent socket should fail", status == nil)
  check("error mentions connect failure", err:find("connect") or err:find("failed"))
end

--------------------------------------------------------------------------------
-- Run all tests
--------------------------------------------------------------------------------
print("Running unix socket proxy tests...")

test_missing_path()
print("  [pass] missing path error")

test_path_too_long()
print("  [pass] path too long error (security fix)")

test_socket_not_found()
print("  [pass] socket not found error")

test_stream_missing_path()
print("  [pass] FetchStream missing path error")

test_stream_path_too_long()
print("  [pass] FetchStream path too long error (security fix)")

test_stream_socket_not_found()
print("  [pass] FetchStream socket not found error")

print("all unix socket proxy tests passed")
