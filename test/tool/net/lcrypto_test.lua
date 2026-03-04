#!/usr/bin/env cosmic
-- tests for AeadEncrypt, AeadDecrypt, and Hkdf

local cosmo = require("cosmo")

-- Helper: make a fresh 32-byte key
local function make_key()
  return cosmo.GetRandomBytes(32)
end

-- AeadEncrypt/AeadDecrypt round-trip
local function test_aead_round_trip()
  local key = make_key()
  local plain = "hello, world"
  local ct = assert(cosmo.AeadEncrypt(key, plain))
  local pt = assert(cosmo.AeadDecrypt(key, ct))
  assert(pt == plain, "round-trip mismatch: got " .. tostring(pt))
end
test_aead_round_trip()

-- Different ciphertext each call (random nonce)
local function test_aead_different_each_call()
  local key = make_key()
  local ct1 = assert(cosmo.AeadEncrypt(key, "same"))
  local ct2 = assert(cosmo.AeadEncrypt(key, "same"))
  assert(ct1 ~= ct2, "two encryptions should differ")
end
test_aead_different_each_call()

-- Wrong key fails
local function test_aead_wrong_key()
  local ct = assert(cosmo.AeadEncrypt(make_key(), "secret"))
  local pt, err = cosmo.AeadDecrypt(make_key(), ct)
  assert(pt == nil, "wrong key should fail")
  assert(err:find("authentication"), "error should mention auth: " .. tostring(err))
end
test_aead_wrong_key()

-- Tampered ciphertext fails
local function test_aead_tampered()
  local key = make_key()
  local ct = assert(cosmo.AeadEncrypt(key, "original"))
  local tampered = ct:sub(1, -2) .. string.char(ct:byte(-1) ~ 0x01)
  local pt, err = cosmo.AeadDecrypt(key, tampered)
  assert(pt == nil, "tampered ciphertext should fail")
end
test_aead_tampered()

-- Too short ciphertext
local function test_aead_too_short()
  local key = make_key()
  local pt, err = cosmo.AeadDecrypt(key, "short")
  assert(pt == nil, "too-short should fail")
  assert(err:find("too short"), "error should mention too short: " .. tostring(err))
end
test_aead_too_short()

-- Empty plaintext
local function test_aead_empty()
  local key = make_key()
  local ct = assert(cosmo.AeadEncrypt(key, ""))
  -- nonce(12) + tag(16) + 0 = 28
  assert(#ct == 28, "empty ciphertext should be 28 bytes, got " .. #ct)
  local pt = assert(cosmo.AeadDecrypt(key, ct))
  assert(pt == "", "empty roundtrip should yield empty")
end
test_aead_empty()

-- AAD: matching AAD decrypts
local function test_aead_with_aad()
  local key = make_key()
  local ct = assert(cosmo.AeadEncrypt(key, "data", "context"))
  local pt = assert(cosmo.AeadDecrypt(key, ct, "context"))
  assert(pt == "data", "AAD round-trip mismatch")
end
test_aead_with_aad()

-- AAD: wrong AAD fails
local function test_aead_wrong_aad()
  local key = make_key()
  local ct = assert(cosmo.AeadEncrypt(key, "data", "correct"))
  local pt, err = cosmo.AeadDecrypt(key, ct, "wrong")
  assert(pt == nil, "wrong AAD should fail")
end
test_aead_wrong_aad()

-- Ciphertext length
local function test_aead_length()
  local key = make_key()
  local ct = assert(cosmo.AeadEncrypt(key, "test"))
  -- nonce(12) + tag(16) + plaintext(4) = 32
  assert(#ct == 32, "ciphertext should be 32 bytes, got " .. #ct)
end
test_aead_length()

-- Hkdf basic
local function test_hkdf_basic()
  local key = cosmo.Hkdf("password", "salt", "info")
  assert(key, "Hkdf should return a key")
  assert(#key == 32, "default output should be 32 bytes, got " .. #key)
end
test_hkdf_basic()

-- Hkdf deterministic
local function test_hkdf_deterministic()
  local k1 = cosmo.Hkdf("password", "salt", "info")
  local k2 = cosmo.Hkdf("password", "salt", "info")
  assert(k1 == k2, "same inputs should produce same output")
end
test_hkdf_deterministic()

-- Hkdf different inputs produce different outputs
local function test_hkdf_different_inputs()
  local k1 = cosmo.Hkdf("password1", "salt", "info")
  local k2 = cosmo.Hkdf("password2", "salt", "info")
  assert(k1 ~= k2, "different passwords should produce different keys")
end
test_hkdf_different_inputs()

-- Hkdf custom length
local function test_hkdf_custom_length()
  local key = cosmo.Hkdf("ikm", "salt", "info", 64)
  assert(#key == 64, "custom length should be 64 bytes, got " .. #key)
end
test_hkdf_custom_length()

-- Hkdf empty salt/info
local function test_hkdf_empty_salt_info()
  local key = cosmo.Hkdf("ikm", "", "")
  assert(key, "empty salt/info should work")
  assert(#key == 32, "should be 32 bytes")
end
test_hkdf_empty_salt_info()

print("all crypto tests passed")
