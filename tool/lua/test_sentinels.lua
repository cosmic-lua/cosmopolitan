-- Tests for sentinel returns converted to nil,err (issue #151, item 4):
-- ParseIp no longer returns the -1 sentinel, and Strftime no longer returns
-- a bare, ambiguous nil.
local cosmo = require("cosmo")

-- ParseIp: a valid address round-trips through FormatIp
local ip = assert(cosmo.ParseIp("1.2.3.4"))
assert(ip == 0x01020304, "ParseIp('1.2.3.4') == 0x01020304, got: " .. tostring(ip))
assert(cosmo.FormatIp(ip) == "1.2.3.4", "round-trips through FormatIp")

-- the broadcast address is a *valid* parse, distinct from the error case
local bcast = assert(cosmo.ParseIp("255.255.255.255"))
assert(cosmo.FormatIp(bcast) == "255.255.255.255", "broadcast parses")

-- invalid input: nil, err (previously -1, which FormatIp rendered as broadcast)
local bad, err = cosmo.ParseIp("nope")
assert(bad == nil and type(err) == "string", "ParseIp invalid -> nil,err")
assert(select("#", cosmo.ParseIp("nope")) == 2, "ParseIp returns two values")
assert(err:find("nope"), "error names the bad input: " .. tostring(err))

-- Strftime: an empty format is an empty string, not nil
assert(cosmo.Strftime("", 0) == "", "empty format -> empty string")

-- a format whose output exceeds the old 256-byte buffer now succeeds instead
-- of silently returning a bare nil
local long = string.rep("%Y-%m-%d ", 60)  -- ~660 bytes of output
local out = cosmo.Strftime(long, 0)
assert(type(out) == "string" and #out > 256,
  "long format grows the buffer, got #" .. #(out or ""))
assert(out:find("1970%-01%-01"), "long format content is correct")

-- an ordinary format still works and is a plain string (not string?)
assert(cosmo.Strftime("%Y-%m-%d", 0) == "1970-01-01", "ordinary format")

print("test_sentinels: PASS")
