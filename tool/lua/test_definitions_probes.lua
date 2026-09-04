-- Bounded ftrace companion to test_definitions_conformance.lua's binding
-- probes.
--
-- test_definitions_conformance.lua calls ~75 pure-function bindings and
-- checks each return against tool/net/definitions.lua's annotations, but
-- that checking is done by repeatedly re-parsing definitions.lua's ~330 KB
-- of text (declared_returns() walks it fresh per probed name), and that
-- parsing -- not the binding calls themselves -- is what makes the whole
-- script's --ftrace trace unbounded: measured 2026-09-02, just 19 calls to
-- declared_returns() alone produced 11.5M FUN lines, ten times over
-- tool/lua/coverage.lua's TRACE_LINE_CAP. So test_definitions_conformance.lua
-- stays in coverage.lua's SKIP table, and with it test_definitions_coverage.lua
-- and test_definitions_help.lua, which parse definitions.lua just as heavily
-- and call no bindings at all -- there is nothing to split out of either.
--
-- This file exists so the 75 probed bindings are not therefore invisible to
-- the function coverage floor: it makes the exact same calls
-- test_definitions_conformance.lua does (success and forced-failure alike,
-- so both branches' functions are reached), with no definitions.lua parsing
-- at all. Measured the same day, the same 75 calls produced under 66,000 FUN
-- lines -- comfortably bounded, so this file is not in SKIP and coverage.lua
-- traces it like any other enrolled test.
--
-- This is not a second correctness check: it asserts only what does not
-- require reading definitions.lua (that a forced failure lands in a
-- nil/false slot, mirroring the same assertions test_definitions_conformance.lua
-- already makes independently of parsing). Annotation-type conformance stays
-- test_definitions_conformance.lua's job alone. When a probe is added there,
-- mirror the call here too -- same name, same args -- so the floor keeps
-- seeing it; this file's job is coverage, not verification, so nothing here
-- should come to depend on tool/net/definitions.lua.

local cosmo = require("cosmo")
local path = require("cosmo.path")
local unix = require("cosmo.unix")
local getopt = require("cosmo.getopt")
local argon2 = require("cosmo.argon2")
local re = require("cosmo.re")

-- === success shapes, one call each =======================================

cosmo.EncodeJson({ foo = "bar" })
cosmo.DecodeJson('{"x":1}')
cosmo.EncodeLua({ 1, 2, 3 })
cosmo.EncodeBase64("\x00\xff binary")
cosmo.DecodeBase64("aGVsbG8=")
cosmo.EncodeHex("\x00\xff")
cosmo.FormatIp(0x7f000001)
cosmo.ParseIp("127.0.0.1")
cosmo.Crc32(0, "hello")
cosmo.GetCryptoHash("SHA256", "payload")
cosmo.GetHostIsa()
cosmo.GetHostOs()
cosmo.CategorizeIp(0x7f000001)
path.basename("/a/b/c.tl")
path.dirname("/a/b/c.tl")
path.join("a", "b")
unix.getpid()
unix.getpgrp()
unix.clock_gettime()

cosmo.Crc32c(0, "hello")
cosmo.DecodeLatin1("abc")
cosmo.EncodeLatin1("abc")
cosmo.EscapeFragment("a b")
cosmo.EscapeHost("ex ample.com")
cosmo.EscapeHtml("<b>")
cosmo.EscapeIp(0x7f000001)
cosmo.EscapeLiteral("a\"b")
cosmo.EscapeParam("a b")
cosmo.EscapePass("a b")
cosmo.EscapePath("a b")
cosmo.EscapeSegment("a b")
cosmo.EscapeUser("a b")
cosmo.UnescapeParam("a%20b")
cosmo.FormatHttpDateTime(0)
cosmo.GetHttpReason(200)
cosmo.GetMonospaceWidth("abc")
cosmo.HasControlCodes("abc")
cosmo.is_main()
cosmo.IsAcceptableHost("example.com")
cosmo.IsAcceptablePath("/a/b")
cosmo.IsAcceptablePort("80")
cosmo.IsBase64("aGk=")
cosmo.IsLoopbackIp(0x7f000001)
cosmo.IsPrivateIp(0x0a000001)
cosmo.IsPublicIp(0x08080808)
cosmo.IsReasonablePath("/a/b")
cosmo.IsValidPercentEncoding("a%20b")
cosmo.jsonarray({ 1, 2 })
cosmo.ParseParams("a=1&b=2")
cosmo.ParseUrl("http://x/y")
cosmo.EncodeUrl({ scheme = "http", host = "x", path = "/y" })
cosmo.Rand64()
cosmo.Sha256("x")
cosmo.UuidV4()
cosmo.UuidV7()
path.exists("tool")
path.isdir("tool")
path.isfile("tool/net/definitions.lua")
path.islink("tool")

-- === two-slot: a forced failure alongside the success call ===============

local dhv, dherr = cosmo.DecodeHex("zz")
assert(dhv == nil and type(dherr) == "string",
  "DecodeHex of non-hex must be nil, string")
cosmo.DecodeHex("00ff")

local rxbad, rxerr = re.compile("[")
assert(rxbad == nil and type(rxerr) == "string",
  "re.compile of a bad pattern must be nil, string")
local rx = re.compile("a(b)c")

local sr = re.search("a(b)c", "abc")
assert(sr.match == "abc" and type(sr.captures) == "table", "re.search must match")
re.search("[", "x")

local rss = rx:search("abc")
assert(rss.match == "abc" and type(rss.captures) == "table",
  "re.Regex:search must match")
local rsm = rx:match("abc")
assert(rsm.match == "abc" and type(rsm.captures) == "table",
  "re.Regex:match must match")
rx:find("abc")

-- getopt.parse raises on a malformed call, so unlike re.compile/re.search
-- above it has no nil+error slot to force; only its success path is
-- probed, matching test_definitions_conformance.lua.
getopt.parse({ "prog", "-h" }, "h")

cosmo.GetRandomBytes(8)
cosmo.Strftime("%Y", 0)

cosmo.ParseHost("example.com:80")

local b32, b32err = cosmo.EncodeBase32("hi", "abc")
assert(b32 == nil and type(b32err) == "string",
  "EncodeBase32 with a bad alphabet must be nil, string")
cosmo.EncodeBase32("hi")
local d32, d32err = cosmo.DecodeBase32("NBUQ", "abc")
assert(d32 == nil and type(d32err) == "string",
  "DecodeBase32 with a bad alphabet must be nil, string")
cosmo.DecodeBase32("NBUQ====")

local ah, aherr = argon2.hash_encoded("pw", "s",
  { t_cost = 1, m_cost = 8, parallelism = 1 })
assert(ah == nil and type(aherr) == "string",
  "argon2.hash_encoded with too short a salt must be nil, string")
local encoded = argon2.hash_encoded("pw", "saltsalt",
  { t_cost = 1, m_cost = 8, parallelism = 1 })
local av, averr = argon2.verify("not-encoded", "pw")
assert(av == false and type(averr) == "string",
  "argon2.verify of a malformed hash must be false, string")
argon2.verify(encoded, "pw")

-- compress round-trip, both directions
local deflated = cosmo.Deflate(("ratchet"):rep(64))
local inflated = cosmo.Inflate(deflated)
assert(inflated == ("ratchet"):rep(64), "Deflate/Inflate round-trip broke")

-- === failure shapes ========================================================

local v, err = cosmo.DecodeJson("{truncated")
assert(v == nil and type(err) == "string",
  "DecodeJson failure must be nil, string")

local hv, herr = cosmo.GetCryptoHash("NOT-A-HASH", "payload")
assert(hv == nil and type(herr) == "string",
  "GetCryptoHash failure must be nil, string")

assert(not pcall(path.join), "join() must raise")
assert(not pcall(path.join, nil), "join(nil) must raise")
assert(not pcall(path.join, nil, nil), "join(nil, nil) must raise")
assert(path.join("") == "", "join('') stays the empty string")
assert(path.join("a", nil) == "a", "interior nil still skipped")

assert(not pcall(unix.clock_gettime, -1),
  "clock_gettime of an invalid clock id must raise")

local dv, derr = cosmo.Deflate("x", { level = 99 })
assert(dv == nil and type(derr) == "string",
  "Deflate with an out-of-range level must be nil, string")

local iv, ierr = cosmo.Inflate("not-deflate-data")
assert(iv == nil and type(ierr) == "string",
  "Inflate of non-deflate bytes must be nil, string")

local cyclic = {}
cyclic.self = cyclic
local jv, jerr = cosmo.EncodeJson(cyclic)
assert(jv == nil and type(jerr) == "string",
  "EncodeJson of a cyclic table must be nil, string")

local lv, lerr = cosmo.EncodeLua({ 1 }, { nan = "bogus" })
assert(lv == nil and type(lerr) == "string",
  "EncodeLua with an invalid nan option must be nil, string")

local pv, perr = cosmo.ParseIp("not.an.ip.addr")
assert(pv == -1 or (pv == nil and type(perr) == "string"),
  "ParseIp failure shape changed: " .. tostring(pv) .. ", " .. tostring(perr))

print("PASS")
