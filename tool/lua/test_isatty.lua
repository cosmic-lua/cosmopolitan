-- Test for unix.isatty
local unix = require("cosmo.unix")

-- Test 1: isatty on a regular file should return false
-- This demonstrates the semantic bug where it currently returns true
local fd = unix.open("/dev/null", unix.O_RDONLY)
assert(fd, "should be able to open /dev/null")

local result = unix.isatty(fd)
assert(result == false, "isatty on /dev/null should return false, got: " .. tostring(result))

unix.close(fd)

-- Test 2: isatty on stdout (if it's a tty) should return true
-- This triggers the warning: "syscall supposed to return 0 / -1 but got 1"
local result = unix.isatty(1)
-- We can't assert the result because it depends on whether stdout is a tty
-- but if it IS a tty, this will trigger the warning
if result then
  print("stdout is a tty (this should trigger warning in buggy version)")
end

-- Test 3: isatty on an invalid fd returns false, never a failure tuple:
-- libc isatty() collapses EBADF/EPERM/ENOTTY to 0, so the binding has
-- exactly one return shape (bool) and a bad fd is indistinguishable from
-- a valid non-terminal fd.
local result, err = unix.isatty(999999)
assert(result == false, "isatty on a bad fd should return false, got: " .. tostring(result))
assert(err == nil, "isatty should never return an error, got: " .. tostring(err))

print("all isatty tests passed")
