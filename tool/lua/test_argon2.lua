-- Tests for the argon2 module rework (issue #151, item 5): string variants,
-- optional random salt, verify -> (boolean, err?), and removal of the
-- process-wide config mutators and the untypeable lightuserdata variants.
local argon2 = require("cosmo.argon2")

-- removed surface
assert(argon2.variants == nil, "argon2.variants must be removed")
assert(argon2.t_cost == nil, "argon2.t_cost mutator must be removed")
assert(argon2.m_cost == nil, "argon2.m_cost mutator must be removed")
assert(argon2.parallelism == nil, "argon2.parallelism mutator must be removed")
assert(argon2.hash_len == nil, "argon2.hash_len mutator must be removed")
assert(argon2.variant == nil, "argon2.variant mutator must be removed")

-- hash with an explicit salt + string variant, then round-trip verify
local h = assert(argon2.hash_encoded("password", "somesalt", {
  variant = "argon2id", t_cost = 1, m_cost = 256, hash_len = 16,
}))
assert(h:find("^%$argon2id%$"), "encoded hash should be argon2id: " .. h)
local ok, err = argon2.verify(h, "password")
assert(ok == true and err == nil, "correct password verifies")

-- mismatch: false, no error (a single return value)
local ok2, err2 = argon2.verify(h, "wrong")
assert(ok2 == false, "wrong password -> false")
assert(err2 == nil, "mismatch is not an error")
assert(select("#", argon2.verify(h, "wrong")) == 1, "mismatch returns one value")

-- malformed encoded string: false + error string (not nil + error)
local mok, merr = argon2.verify("not-a-valid-hash", "password")
assert(mok == false, "malformed hash -> ok is false (was nil before)")
assert(type(merr) == "string" and #merr > 0, "malformed hash -> error string")

-- optional salt: nil/omitted generates 16 random bytes; result round-trips
local r1 = assert(argon2.hash_encoded("hunter2", nil, { t_cost = 1, m_cost = 256 }))
assert(argon2.verify(r1, "hunter2") == true, "random-salt hash verifies")
local r2 = assert(argon2.hash_encoded("hunter2", nil, { t_cost = 1, m_cost = 256 }))
assert(r1 ~= r2, "random salt should differ between calls")

-- omitting salt entirely (single-arg form) also works
local r3 = assert(argon2.hash_encoded("hunter2"))
assert(argon2.verify(r3, "hunter2") == true, "default-everything hash verifies")

-- string variants: argon2i and argon2d
local hi = assert(argon2.hash_encoded("p", "saltsalt",
  { variant = "argon2i", t_cost = 1, m_cost = 256 }))
assert(hi:find("^%$argon2i%$"), "argon2i variant")
local hd = assert(argon2.hash_encoded("p", "saltsalt",
  { variant = "argon2d", t_cost = 1, m_cost = 256 }))
assert(hd:find("^%$argon2d%$"), "argon2d variant")

-- default variant is argon2id
local hdef = assert(argon2.hash_encoded("p", "saltsalt",
  { t_cost = 1, m_cost = 256 }))
assert(hdef:find("^%$argon2id%$"), "default variant is argon2id")

-- an unknown variant string is a programmer error (raises)
local raised = not pcall(function()
  argon2.hash_encoded("p", "saltsalt", { variant = "bogus" })
end)
assert(raised, "unknown variant string should raise")

print("test_argon2: PASS")
