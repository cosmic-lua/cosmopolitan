-- Known-value correctness tests for EncodeBase64/DecodeBase64.
--
-- test_definitions_conformance.lua calls EncodeBase64/DecodeBase64 once
-- each and only checks the return TYPE matches definitions.lua. This
-- file checks the actual VALUE: the RFC 4648 padding progression
-- (section 10 test vectors) plus a round-trip through arbitrary binary
-- data.

local cosmo = require("cosmo")
local unix = require("cosmo.unix")
local EncodeBase64, DecodeBase64 = cosmo.EncodeBase64, cosmo.DecodeBase64

assert(unix.pledge("stdio"))

local function test(s, b64)
  assert(EncodeBase64(s) == b64)
  assert(DecodeBase64(b64) == s)
  assert(DecodeBase64(EncodeBase64(s)) == s)
end

test("\x69\xb7\x1d\x79\xf8\x00\x04\x20\xc4", "abcdefgABCDE")

-- padding tests
--    https://datatracker.ietf.org/doc/html/rfc4648#section-10
test("", "")
test("r", "cg==")
test("re", "cmU=")
test("red", "cmVk")
test("redb", "cmVkYg==")
test("redbe", "cmVkYmU=")
test("redbea", "cmVkYmVh")
test("redbean", "cmVkYmVhbg==")
