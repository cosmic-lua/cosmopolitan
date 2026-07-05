local cosmo = require("cosmo")

-- Test Strftime function exists
assert(type(cosmo.Strftime) == "function", "Strftime should be a function")

-- Test Strftime with epoch (1970-01-01 00:00:00 UTC)
local s = cosmo.Strftime("%Y-%m-%d %H:%M:%S", 0)
assert(s == "1970-01-01 00:00:00", "epoch should format correctly, got: " .. tostring(s))

-- Test Strftime with a known timestamp
-- 1735500000 = 2024-12-29 18:40:00 UTC
local s = cosmo.Strftime("%Y-%m-%d", 1735500000)
assert(s == "2024-12-29", "date should format correctly, got: " .. tostring(s))

-- Test various format specifiers
local s = cosmo.Strftime("%F", 0)  -- %F = %Y-%m-%d
assert(s == "1970-01-01", "%F should work, got: " .. tostring(s))

local s = cosmo.Strftime("%T", 0)  -- %T = %H:%M:%S
assert(s == "00:00:00", "%T should work, got: " .. tostring(s))

-- Test weekday (epoch was Thursday)
local s = cosmo.Strftime("%a", 0)
assert(s == "Thu", "epoch weekday should be Thu, got: " .. tostring(s))

-- Test Strftime with default timestamp (current time)
local s = cosmo.Strftime("%Y")
assert(s ~= nil, "Strftime with default time should work")
assert(#s == 4, "year should be 4 digits")

print("PASS")
