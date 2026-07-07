-- Tests for lfuncs data-dependent throwers converted to nil,err returns
-- (issue #151, item 3): DecodeHex, Inflate, GetCryptoHash, and base32 no
-- longer raise on recoverable, data-dependent failures.
local cosmo = require("cosmo")

-- DecodeHex: valid decode
assert(cosmo.DecodeHex("6162") == "ab", "DecodeHex valid")
-- odd length -> nil, err (previously raised)
local h, herr = cosmo.DecodeHex("abc")
assert(h == nil and type(herr) == "string", "DecodeHex odd length -> nil,err")
assert(select("#", cosmo.DecodeHex("abc")) == 2, "DecodeHex returns two values")
-- non-hex character -> nil, err
local h2, h2err = cosmo.DecodeHex("zz")
assert(h2 == nil and type(h2err) == "string", "DecodeHex non-hex -> nil,err")

-- Inflate: round-trip, then corrupt/truncated input (issue #153: the
-- deprecated Compress/Uncompress pair is gone; Deflate/Inflate are the
-- one compression API, and Inflate never throws on bad data)
local comp = cosmo.Deflate("hello world, hello world")
assert(cosmo.Inflate(comp) == "hello world, hello world",
  "Deflate/Inflate round-trip")
local u, uerr = cosmo.Inflate("not valid compressed data")
assert(u == nil and type(uerr) == "string", "Inflate corrupt -> nil,err")
assert(select("#", cosmo.Inflate("xx")) == 2, "Inflate returns two values")
assert(cosmo.Compress == nil and cosmo.Uncompress == nil,
  "deprecated Compress/Uncompress are deleted")

-- GetCryptoHash: valid digest, then unknown hash name
local dg = cosmo.GetCryptoHash("SHA256", "abc")
assert(type(dg) == "string" and #dg == 32, "SHA256 digest is 32 bytes")
local g, gerr = cosmo.GetCryptoHash("NOPEHASH", "abc")
assert(g == nil and type(gerr) == "string", "unknown hash -> nil,err")
assert(gerr:find("NOPEHASH"), "error names the bad hash: " .. tostring(gerr))

-- base32: round-trip, then an alphabet whose length is not a power of 2
local b = cosmo.EncodeBase32("hello")
assert(cosmo.DecodeBase32(b) == "hello", "base32 round-trip")
local e, eerr = cosmo.EncodeBase32("hello", "abc")
assert(e == nil and type(eerr) == "string",
  "EncodeBase32 bad alphabet -> nil,err")
local d, derr = cosmo.DecodeBase32("hello", "abc")
assert(d == nil and type(derr) == "string",
  "DecodeBase32 bad alphabet -> nil,err")

-- a wrong *type* is still a programmer error (raises), not a nil,err return
-- (a table does not coerce to a string, unlike a number)
assert(not pcall(function() cosmo.DecodeHex({}) end),
  "DecodeHex on a non-string still raises")

print("test_lfuncs_errors: PASS")
