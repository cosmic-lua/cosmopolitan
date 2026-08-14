-- Tests for the data-format contract fixes (issue #153):
--   1. DecodeJson("[]") is marked with the shared json.array metatable
--      instead of leaking a [0]=false data key; cosmo.jsonarray() lets
--      users force array encoding for empty tables they build.
--   2. EncodeJson rejects NaN/Infinity unless opts.nan == "null", and
--      recognizes the cosmo.null sentinel for lossless null round-trips.
--   3. Deflate/Inflate take options tables, interoperate with zlib/gzip
--      framing, stream under a maxsize cap, and never trust an
--      attacker-controlled size.
local cosmo = require("cosmo")

--------------------------------------------------------------------------------
-- 1. empty array round-trip without a phantom key
--------------------------------------------------------------------------------

local t = assert(cosmo.DecodeJson("[]"))
assert(next(t) == nil, "decoded [] must have no keys, found: " ..
  tostring(next(t)))
assert(t[0] == nil, "the [0]=false kludge must be gone")
assert(cosmo.EncodeJson(t) == "[]", "[] must round-trip as []")

-- counting keys and re-serializing agree with an empty table
local n = 0
for _ in pairs(t) do n = n + 1 end
assert(n == 0, "pairs() over decoded [] must see nothing")

-- empty object still round-trips as an object
assert(cosmo.EncodeJson(assert(cosmo.DecodeJson("{}"))) == "{}",
  "{} must round-trip as {}")

-- nonempty arrays stay arrays even after being emptied, since the
-- marker rides on the table rather than on a data key
local a = assert(cosmo.DecodeJson("[1,2]"))
assert(cosmo.EncodeJson(a) == "[1,2]", "nonempty array round-trip")
a[1] = nil
a[2] = nil
assert(cosmo.EncodeJson(a) == "[]", "emptied decoded array stays an array")

-- jsonarray marks user-built tables (the inverse ambiguity)
assert(type(cosmo.jsonarray) == "function", "cosmo.jsonarray should exist")
assert(cosmo.EncodeJson(cosmo.jsonarray({})) == "[]",
  "jsonarray({}) must encode as []")
assert(cosmo.EncodeJson(cosmo.jsonarray()) == "[]",
  "jsonarray() must create a fresh array table")
local m = cosmo.jsonarray({})
m[1] = 7
assert(cosmo.EncodeJson(m) == "[7]", "marked table still encodes elements")
assert(cosmo.EncodeJson({}) == "{}", "unmarked empty table is still {}")

-- old kludge tables are no longer special
assert(cosmo.EncodeJson({[0] = false}) == nil,
  "{[0]=false} is just a table with a non-string key now")

--------------------------------------------------------------------------------
-- 2. NaN/Infinity policy and the null sentinel
--------------------------------------------------------------------------------

local v, err = cosmo.EncodeJson(0 / 0)
assert(v == nil and type(err) == "string", "EncodeJson(NaN) -> nil,err")
assert(err:find("NaN"), "error should name NaN: " .. tostring(err))
v, err = cosmo.EncodeJson(1 / 0)
assert(v == nil and err:find("Infinity"), "EncodeJson(Inf) -> nil,err")
v, err = cosmo.EncodeJson({x = -1 / 0})
assert(v == nil and type(err) == "string", "nested Inf -> nil,err")

assert(cosmo.EncodeJson(0 / 0, {nan = "null"}) == "null",
  'EncodeJson(NaN, {nan="null"}) -> "null"')
assert(cosmo.EncodeJson({1 / 0}, {nan = "null"}) == "[null]",
  "nan option applies to Infinity too")
v, err = cosmo.EncodeJson(1, {nan = "bogus"})
assert(v == nil and type(err) == "string", "bad nan option -> nil,err")

-- finite numbers are unaffected
assert(cosmo.EncodeJson(1.5) == "1.5", "finite doubles still encode")

-- the null sentinel survives object and array contexts
assert(type(cosmo.null) == "table", "cosmo.null sentinel should exist")
assert(cosmo.EncodeJson(cosmo.null) == "null", "cosmo.null encodes as null")
assert(cosmo.EncodeJson({a = cosmo.null}) == '{"a":null}',
  "null sentinel round-trips object values")
assert(cosmo.EncodeJson({1, cosmo.null, 3}) == "[1,null,3]",
  "null sentinel round-trips array elements")

--------------------------------------------------------------------------------
-- 3. Deflate/Inflate modern contract
--------------------------------------------------------------------------------

local data = string.rep("the quick brown fox jumps over the lazy dog ", 64)

-- round-trip without a size argument
local packed = assert(cosmo.Deflate(data))
assert(cosmo.Inflate(packed) == data, "raw round-trip without a size")

-- level option
local best = assert(cosmo.Deflate(data, {level = 9}))
local none = assert(cosmo.Deflate(data, {level = 0}))
assert(#best < #none, "level 9 should beat level 0")
assert(cosmo.Inflate(best) == data, "level 9 round-trip")
v, err = cosmo.Deflate(data, {level = 42})
assert(v == nil and type(err) == "string", "bad level -> nil,err")

-- zlib/gzip interop framings, plus auto header detection
for _, format in ipairs({"zlib", "gzip"}) do
  local blob = assert(cosmo.Deflate(data, {format = format}))
  assert(cosmo.Inflate(blob, {format = format}) == data,
    format .. " round-trip")
  assert(cosmo.Inflate(blob, {format = "auto"}) == data,
    "auto detects " .. format)
end
-- gzip blobs start with the \x1f\x8b magic so gunzip et al can read them
assert(cosmo.Deflate("x", {format = "gzip"}):byte(1) == 0x1f,
  "gzip framing emits the gzip magic")
v, err = cosmo.Deflate(data, {format = "bogus"})
assert(v == nil and type(err) == "string", "bad format -> nil,err")
v, err = cosmo.Inflate(packed, {format = "bogus"})
assert(v == nil and type(err) == "string", "bad inflate format -> nil,err")

-- corrupt input -> nil, err (not a throw)
v, err = cosmo.Inflate("this is not a deflate stream")
assert(v == nil and type(err) == "string", "corrupt input -> nil,err")
assert(select("#", cosmo.Inflate("junk")) == 2, "corrupt returns two values")

-- truncated input -> nil, err
v, err = cosmo.Inflate(packed:sub(1, 5))
assert(v == nil and type(err) == "string", "truncated input -> nil,err")

-- maxsize is a cap, not a trusted allocation size
v, err = cosmo.Inflate(packed, {maxsize = 16})
assert(v == nil and type(err) == "string", "maxsize exceeded -> nil,err")
assert(cosmo.Inflate(packed, {maxsize = #data}) == data,
  "maxsize equal to the decompressed size succeeds")

-- negative and zero sizes rejected
v, err = cosmo.Inflate(packed, {maxsize = -1})
assert(v == nil and type(err) == "string", "negative maxsize -> nil,err")
v, err = cosmo.Inflate(packed, {maxsize = 0})
assert(v == nil and type(err) == "string", "zero maxsize -> nil,err")

-- empty input round-trips
assert(cosmo.Inflate(assert(cosmo.Deflate(""))) == "", "empty round-trip")

--------------------------------------------------------------------------------
-- 4. IsBase64: the strict structural validator complementing the
--    permissive DecodeBase64 (issue #227)
--------------------------------------------------------------------------------

-- valid standard base64, padded and unpadded
assert(cosmo.IsBase64("aGVsbG8="), "padded standard base64")
assert(cosmo.IsBase64("aGVsbG8"), "unpadded input is valid")
assert(cosmo.IsBase64("TQ=="), "two padding chars")
assert(cosmo.IsBase64(""), "empty string is valid")
assert(cosmo.IsBase64("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"),
  "whole standard alphabet")

-- padding rules: only at the end, at most two
assert(not cosmo.IsBase64("TQ==="), "three padding chars rejected")
assert(not cosmo.IsBase64("T=Q"), "padding in the middle rejected")
assert(not cosmo.IsBase64("===="), "padding-only run of four rejected")
assert(cosmo.IsBase64("=="), "bare two-char padding is structurally valid")

-- character-set violations DecodeBase64 would silently skip
assert(not cosmo.IsBase64("aGVs bG8="), "whitespace rejected")
assert(not cosmo.IsBase64("aGVs\nbG8="), "newline rejected")
assert(not cosmo.IsBase64("aGVsbG8=\255"), "high byte rejected")

-- alphabets don't cross: url-safe chars fail standard validation and
-- vice versa, even though DecodeBase64 accepts the union
assert(not cosmo.IsBase64("a-b_c"), "url-safe chars rejected in standard mode")
assert(cosmo.IsBase64("a-b_c", true), "url-safe chars accepted in urlsafe mode")
assert(not cosmo.IsBase64("a+b/c", true), "standard chars rejected in urlsafe mode")
assert(cosmo.IsBase64("a+b/c"), "standard chars accepted in standard mode")

-- validated input decodes to the same bytes the permissive decoder gives
local payload = cosmo.EncodeBase64("The quick brown fox jumps over the lazy dog")
assert(cosmo.IsBase64(payload), "EncodeBase64 output validates")
assert(cosmo.DecodeBase64(payload) ==
  "The quick brown fox jumps over the lazy dog", "gated decode round-trips")

-- sparse arrays: an array with holes errors by default (a hole would
-- otherwise truncate the array or invent a value); sparsenull=true
-- encodes each hole as null. Built key-by-key so no constructor-border
-- ambiguity is involved.
local sparse = {}
sparse[1] = 1
sparse[3] = 3
local sv, serr = cosmo.EncodeJson(sparse)
assert(sv == nil, "sparse array must not encode by default")
assert(serr and serr:find("sparse", 1, true),
  "sparse failure names the condition, got: " .. tostring(serr))
assert(cosmo.EncodeJson(sparse, {sparsenull = true}) == "[1,null,3]",
  "sparsenull encodes holes as null")
assert(cosmo.EncodeJson({1, 2, 3}) == "[1,2,3]",
  "dense arrays are unaffected")

-- sparsenull is bounded by a holes-to-elements ratio: one stray huge
-- index must not turn the encode into an effectively unbounded null
-- stream. Small arrays are exempt (the 64 floor), density matters, not
-- absolute size.
local stray = {}
stray[1] = 1
stray[2 ^ 40] = 2
local bv, berr = cosmo.EncodeJson(stray, {sparsenull = true})
assert(bv == nil, "a stray huge index must fail even with sparsenull")
assert(berr and berr:find("too sparse", 1, true),
  "the failure names the ratio condition, got: " .. tostring(berr))
local smallsparse = {}
smallsparse[1] = 1
smallsparse[60] = 2
assert(cosmo.EncodeJson(smallsparse, {sparsenull = true}),
  "a small sparse array stays under the 64 floor")
local justover = {}
justover[1] = 1
justover[65] = 2  -- max 65 > 64, cnt 2, 65/8 > 2: refused
local jv = cosmo.EncodeJson(justover, {sparsenull = true})
assert(jv == nil, "past the floor, the 8x ratio applies")
local densebig = {}
for i = 1, 100 do densebig[i] = i end
densebig[150] = 150  -- max 150, cnt 101: 150/8 < 101
assert(cosmo.EncodeJson(densebig, {sparsenull = true}),
  "a big mostly-dense array encodes; the cap is a ratio, not a size")
assert(cosmo.EncodeJson(cosmo.jsonarray({})) == "[]",
  "marked empty arrays are unaffected")

-- decode nullval (dkjson-style): a caller-supplied stand-in for JSON
-- null, so nulls survive the decode; with cosmo.null it re-encodes as
-- null, closing the lossless round trip.
local arr = assert(cosmo.DecodeJson("[1,null,2]", {nullval = cosmo.null}))
assert(#arr == 3, "the null element keeps its slot")
assert(arr[2] == cosmo.null, "null decodes to the sentinel")
assert(cosmo.EncodeJson(arr) == "[1,null,2]",
  "null array round-trips losslessly through the sentinel")
local obj = assert(cosmo.DecodeJson('{"a":null,"b":1}', {nullval = cosmo.null}))
assert(obj.a == cosmo.null, "null-valued keys survive the decode")
assert(cosmo.EncodeJson(obj) == '{"a":null,"b":1}',
  "null object round-trips losslessly through the sentinel")
local top, toperr = cosmo.DecodeJson("null", {nullval = cosmo.null})
assert(top == cosmo.null and toperr == nil,
  "top-level null decodes to the sentinel, distinguishable from failure")
local fv = cosmo.DecodeJson("null", {nullval = false})
assert(fv == false, "false is a legal sentinel (only nil means default)")
assert(cosmo.DecodeJson("null") == nil, "default null mapping is still nil")
local hole = assert(cosmo.DecodeJson("[1,null,2]"))
assert(hole[2] == nil, "default decode still leaves a hole")

print("test_data_formats: PASS")
