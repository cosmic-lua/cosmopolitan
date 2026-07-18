-- Regression gate for the GetCryptoHash binding contract.
--
-- The contract (annotated in tool/net/definitions.lua, frozen by
-- cosmic's typed wrappers) is: every algorithm in the annotation
-- resolves case-insensitively, BLAKE2B256 included, and digests/HMACs
-- match the published known-answer vectors. The Mbed TLS 3.6 cutover
-- (#183) silently broke lowercase names and dropped BLAKE2B256; this
-- test exists so any future crypto-backend change that drifts the
-- contract fails here, before a release is cut and cosmic pins it.

local cosmo = require("cosmo")

local function hex(s)
  return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

-- NIST FIPS 180 / RFC 1321 / RFC 7693 "abc" digest vectors, keyed by
-- the exact algorithm set promised in definitions.lua
local digest_vectors = {
  md5 = "900150983cd24fb0d6963f7d28e17f72",
  sha1 = "a9993e364706816aba3e25717850c26c9cd0d89d",
  sha224 = "23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7",
  sha256 = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  sha384 = "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed"
    .. "8086072ba1e7cc2358baeca134c825a7",
  sha512 = "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
    .. "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
  blake2b256 = "bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319",
}

-- every algorithm must resolve in lowercase AND uppercase
for algo, expected in pairs(digest_vectors) do
  for _, name in ipairs({algo, algo:upper()}) do
    local d, err = cosmo.GetCryptoHash(name, "abc")
    assert(d, "GetCryptoHash(" .. name .. ") failed: " .. tostring(err))
    assert(hex(d) == expected,
      "GetCryptoHash(" .. name .. ", 'abc') mismatch: " .. hex(d))
  end
end

-- the dedicated Sha256 binding and the md path must agree
assert(hex(cosmo.Sha256("abc")) == digest_vectors.sha256,
  "Sha256('abc') disagrees with the known-answer vector")

-- unknown names return nil, error (never throw)
local d, err = cosmo.GetCryptoHash("nosuchhash", "abc")
assert(d == nil and type(err) == "string" and err:find("nosuchhash"),
  "unknown hash should return nil plus an error naming it")

-- HMAC known answers: RFC 2202 (md5, sha1) and RFC 4231 (sha256) case 2
local hmac_vectors = {
  md5 = "750c783e6ab0b503eaa86e310a5db738",
  sha1 = "effcdf6ae5eb2fa2d27416d5f184df9c259a7c79",
  sha256 = "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
}
for algo, expected in pairs(hmac_vectors) do
  for _, name in ipairs({algo, algo:upper()}) do
    local tag, herr = cosmo.GetCryptoHash(name, "what do ya want for nothing?", "Jefe")
    assert(tag, "hmac(" .. name .. ") failed: " .. tostring(herr))
    assert(hex(tag) == expected, "hmac(" .. name .. ") mismatch: " .. hex(tag))
  end
end

-- BLAKE2B256 HMAC must equal the generic RFC 2104 construction with
-- the 128-byte block size the 2.26 fork's md layer used, for both
-- short keys and keys longer than a block (which get pre-hashed)
local function hmac_reference(algo, key, msg, block)
  if #key > block then
    key = assert(cosmo.GetCryptoHash(algo, key))
  end
  local ipad, opad = {}, {}
  for i = 1, block do
    local b = i <= #key and key:byte(i) or 0
    ipad[i] = string.char(b ~ 0x36)
    opad[i] = string.char(b ~ 0x5c)
  end
  local inner = assert(cosmo.GetCryptoHash(algo, table.concat(ipad) .. msg))
  return assert(cosmo.GetCryptoHash(algo, table.concat(opad) .. inner))
end
for _, key in ipairs({"Jefe", string.rep("k", 200)}) do
  local tag = assert(cosmo.GetCryptoHash("blake2b256", "message", key))
  local want = hmac_reference("blake2b256", key, "message", 128)
  assert(tag == want,
    "hmac(blake2b256) with " .. #key .. "-byte key diverges from the "
    .. "rfc 2104 construction at block size 128")
end

print("test_crypto_hash: ok")
