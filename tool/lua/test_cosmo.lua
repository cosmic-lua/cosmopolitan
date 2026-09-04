local cosmo = require("cosmo")

assert(type(cosmo) == "table", "cosmo should be a table")

-- test a few top-level functions exist
assert(type(cosmo.DecodeJson) == "function", "DecodeJson should be a function")
assert(type(cosmo.EncodeJson) == "function", "EncodeJson should be a function")
assert(type(cosmo.Sha256) == "function", "Sha256 should be a function")

-- test submodules via require("cosmo.xxx")
local unix = require("cosmo.unix")
local path = require("cosmo.path")
local re = require("cosmo.re")
local argon2 = require("cosmo.argon2")
local lsqlite3 = require("cosmo.lsqlite3")
assert(type(unix) == "table", "require('cosmo.unix') should return a table")
assert(type(path) == "table", "require('cosmo.path') should return a table")
assert(type(re) == "table", "require('cosmo.re') should return a table")
assert(type(argon2) == "table", "require('cosmo.argon2') should return a table")
assert(type(lsqlite3) == "table", "require('cosmo.lsqlite3') should return a table")

-- test a function actually works
local json = cosmo.EncodeJson({foo = "bar"})
assert(json == '{"foo":"bar"}', "EncodeJson should produce valid JSON")

local decoded = cosmo.DecodeJson('{"x":1}')
assert(decoded.x == 1, "DecodeJson should parse JSON")

-- test unix.mkdtemp (unix already defined above via require)
local tmpdir = unix.mkdtemp((os.getenv("TMPDIR") or "/tmp") .. "/test_XXXXXX")
assert(tmpdir, "mkdtemp should return a path")
assert(not tmpdir:match("XXXXXX"), "mkdtemp should replace XXXXXX")
local stat = unix.stat(tmpdir)
assert(stat, "mkdtemp should create a directory")
assert(unix.S_ISDIR(stat:mode()), "mkdtemp result should be a directory")
unix.rmdir(tmpdir)

-- test unix.mkstemp
local fd, result = unix.mkstemp((os.getenv("TMPDIR") or "/tmp") .. "/test_XXXXXX")
assert(fd, "mkstemp should return a file descriptor")
assert(result and result.path, "mkstemp should return a table with a path field")
local tmpfile = result.path
assert(not tmpfile:match("XXXXXX"), "mkstemp should replace XXXXXX")
assert(type(fd) == "number" and fd >= 0, "mkstemp fd should be a non-negative integer")
unix.write(fd, "test")
unix.close(fd)
local stat2 = unix.stat(tmpfile)
assert(stat2, "mkstemp should create a file")
assert(unix.S_ISREG(stat2:mode()), "mkstemp result should be a regular file")
unix.unlink(tmpfile)

-- test SO_NOSIGPIPE is exported and accepted as a boolean socket option.
-- The value is 0 on Linux/OpenBSD/Windows (they use MSG_NOSIGNAL instead) and
-- nonzero on macOS/FreeBSD/NetBSD, but the constant must always be registered
-- so downstreams can suppress SIGPIPE on send() portably.
assert(type(unix.SO_NOSIGPIPE) == "number", "unix.SO_NOSIGPIPE should be a number")
local sfd = assert(unix.socket())
-- setsockopt must reach the kernel (accepted as a bool opt by the binding),
-- not be rejected by the binding's type check; the kernel may report
-- ENOPROTOOPT where the option is absent, which is fine.
local ok, err = unix.setsockopt(sfd, unix.SOL_SOCKET, unix.SO_NOSIGPIPE, true)
assert(ok or err, "setsockopt(SO_NOSIGPIPE) should return a status")
unix.close(sfd)

-- getsockopt(SOL_SOCKET, SO_LINGER) must return BOTH values of its
-- documented two-value overload (seconds:int, enabled:bool), in that
-- order. The C binding once pushed both values but returned only 1,
-- silently dropping seconds and shifting enabled into its place.
local lfd = assert(unix.socket(unix.AF_INET, unix.SOCK_STREAM))
assert(unix.setsockopt(lfd, unix.SOL_SOCKET, unix.SO_LINGER, 5, true))
local seconds, enabled, extra = unix.getsockopt(lfd, unix.SOL_SOCKET, unix.SO_LINGER)
assert(seconds == 5, "getsockopt(SO_LINGER) seconds should be 5, got: " .. tostring(seconds))
assert(enabled == true, "getsockopt(SO_LINGER) enabled should be true, got: " .. tostring(enabled))
assert(extra == nil, "getsockopt(SO_LINGER) should return exactly 2 values")
unix.close(lfd)

-- randomness surface: keep exactly GetRandomBytes and Rand64. The rdrand/
-- rdseed/lemur64 fictions (arc4random64 aliases that never touched RDRAND, a
-- deterministic per-run generator) were removed; so were the Curve25519 key
-- footgun and the redundant per-algorithm digests / dead helpers.
assert(type(cosmo.GetRandomBytes) == "function", "GetRandomBytes should exist")
assert(type(cosmo.Rand64) == "function", "Rand64 should exist")
assert(type(cosmo.Rand64()) == "number", "Rand64 should return a number")
for _, gone in ipairs({
  "Rdrand", "Rdseed", "Lemur64", "Curve25519", "Md5", "Sha1", "Sha224",
  "Sha384", "Sha512", "Bsf", "Bsr", "Popcnt", "bin", "hex", "oct", "GetTime",
  "Sleep", "Decimate", "MeasureEntropy", "HighwayHash64", "GetCpuCore",
  "GetCpuCount", "GetCpuNode", "Underlong", "IndentLines",
  "VisualizeControlCodes", "IsValidHttpToken", "IsHeaderRepeatable",
  "ParseHttpDateTime", "Strptime", "Lz4Compress", "Lz4Decompress",
}) do
  assert(cosmo[gone] == nil, "cosmo." .. gone .. " should be removed")
end

-- GetRandomBytes: cap raised well past the old 1..256, exact length, and it
-- returns nil,err on failure instead of aborting the process via CHECK_EQ.
assert(#cosmo.GetRandomBytes() == 16, "GetRandomBytes() defaults to 16 bytes")
assert(#cosmo.GetRandomBytes(1) == 1, "GetRandomBytes(1) length")
assert(#cosmo.GetRandomBytes(4096) == 4096, "GetRandomBytes(4096) length")
local rb_ok, rb_err = pcall(cosmo.GetRandomBytes, 0)
assert(not rb_ok, "GetRandomBytes(0) should be rejected")

-- lsqlite3: the exec/execute, errcode/error_code, errmsg/error_message dual
-- aliases were collapsed to one name each; session/changeset/rebaser was
-- never wired to a real build (SQLITE_ENABLE_SESSION was never defined for
-- lsqlite3.o, and the amalgamation itself no longer defines it either) and
-- its ~600 lines of #ifdef'd bindings were removed outright.
local db = assert(lsqlite3.open_memory())
assert(type(db.exec) == "function", "db:exec should exist")
assert(db.execute == nil, "db:execute alias should be removed")
assert(type(db.errcode) == "function", "db:errcode should exist")
assert(db.error_code == nil, "db:error_code alias should be removed")
assert(db.error_message == nil, "db:error_message alias should be removed")
assert(db.create_session == nil, "db:create_session (session surface) removed")
db:close()

-- cosmo.ResolveIp: literal IPs parse immediately, with or without the
-- optional timeout_ms bound. (The bounded path returning "DNS lookup
-- timed out" at the deadline was verified against a genuinely
-- tarpitted nameserver during development; a hermetic in-suite tarpit
-- would need to own /etc/resolv.conf, which a test must not.)
assert(cosmo.ResolveIp("127.0.0.1") == 0x7f000001, "literal, unbounded")
assert(cosmo.ResolveIp("1.2.3.4", 100) == 0x01020304, "literal, bounded")
assert(cosmo.ResolveIp("255.255.255.255", 0) == 0xffffffff,
       "literal never waits, even with a zero deadline")

-- localhost resolves through the hosts file on the bounded (worker
-- thread) path.
assert(cosmo.ResolveIp("localhost", 30000) == 0x7f000001,
       "localhost via hosts file on the bounded path")

-- A bounded lookup of an unresolvable name returns nil plus a string
-- error: the resolver's own failure or "DNS lookup timed out",
-- whichever the host's DNS environment produces first.
local rip, rerr = cosmo.ResolveIp("cosmo-test-name.invalid", 2000)
assert(rip == nil, "unresolvable name should fail")
assert(type(rerr) == "string", "failure should carry a string error")

-- cosmo.EncodeLua's literal mode refuses a reserved word as a key,
-- because the bare {k=v} spelling it would otherwise emit is source no
-- reader parses. The set is exactly lua's 22 keywords: a key that
-- merely contains or extends one, or differs in case, is an ordinary
-- identifier and encodes.
local keywords = {
  "and", "break", "do", "else", "elseif", "end", "false", "for",
  "function", "goto", "if", "in", "local", "nil", "not", "or",
  "repeat", "return", "then", "true", "until", "while",
}
assert(#keywords == 22, "lua has 22 reserved words")
for _, kw in ipairs(keywords) do
  local ok, why = cosmo.EncodeLua({[kw] = 1},
                                  {sorted = true, literal = true, maxdepth = 32})
  assert(ok == nil, "literal mode should refuse the key " .. kw)
  assert(why == "reserved word as key",
         "wrong refusal for " .. kw .. ": " .. tostring(why))
end
for _, near in ipairs({"ending", "en", "endx", "And", "NIL", "function1",
                       "_end", "end_"}) do
  local ok = cosmo.EncodeLua({[near] = 1},
                             {sorted = true, literal = true, maxdepth = 32})
  assert(type(ok) == "string", "literal mode should accept the key " .. near)
end

print("all tests passed")
