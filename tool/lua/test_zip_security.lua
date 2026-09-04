-- Security validation tests for cosmo.zip

local zip = require("cosmo.zip")
local unix = require("cosmo.unix")

local tmpdir = unix.mkdtemp("/tmp/test_zip_security_XXXXXX")
assert(tmpdir, "failed to create temp dir")

--------------------------------------------------------------------------------
-- Test writer security validations
--------------------------------------------------------------------------------

local sec_zip = tmpdir .. "/security_test.zip"
local writer, err = zip.open(sec_zip, "w")
assert(writer, "failed to create security test zip: " .. tostring(err))

-- Test path traversal rejection
local result, err = writer:add("../escape.txt", "malicious")
assert(result == nil, "path traversal with .. should be rejected")
assert(err:match("unsafe path"), "error should mention unsafe path")

result, err = writer:add("/absolute/path.txt", "malicious")
assert(result == nil, "absolute path should be rejected")
assert(err:match("unsafe path"), "error should mention unsafe path")

result, err = writer:add("foo/../bar.txt", "malicious")
assert(result == nil, "embedded .. should be rejected")

result, err = writer:add("foo/bar/..", "malicious")
assert(result == nil, "trailing .. should be rejected")

-- Test empty name rejection
result, err = writer:add("", "content")
assert(result == nil, "empty name should be rejected")
assert(err:match("empty"), "error should mention empty")

-- Test null byte in name rejection
result, err = writer:add("foo\0bar.txt", "content")
assert(result == nil, "null byte in name should be rejected")
assert(err:match("null"), "error should mention null")

-- Test duplicate entry rejection
local ok, err = writer:add("unique.txt", "first")
assert(ok, "first add should succeed")

result, err = writer:add("unique.txt", "second")
assert(result == nil, "duplicate entry should be rejected")
assert(err:match("duplicate"), "error should mention duplicate")

-- Test invalid mode rejection (symlink)
result, err = writer:add("symlink.txt", "content", {mode = 0120777})
assert(result == nil, "symlink mode should be rejected")
assert(err:match("regular file"), "error should mention regular file")

-- Test invalid mode rejection (directory)
result, err = writer:add("dir.txt", "content", {mode = 0040755})
assert(result == nil, "directory mode should be rejected")

-- Valid paths should still work
ok, err = writer:add("normal.txt", "content")
assert(ok, "normal path should work: " .. tostring(err))

ok, err = writer:add("subdir/file.txt", "content")
assert(ok, "subdir path should work: " .. tostring(err))

ok, err = writer:add("a/b/c/deep.txt", "content")
assert(ok, "deep path should work: " .. tostring(err))

-- Mode with just permissions (no file type) should default to regular file
ok, err = writer:add("perms.txt", "content", {mode = 0644})
assert(ok, "permission-only mode should work: " .. tostring(err))

writer:close()

--------------------------------------------------------------------------------
-- Test configurable max_file_size
--------------------------------------------------------------------------------

-- Test writer max_file_size enforcement
local limit_zip = tmpdir .. "/limit_test.zip"
writer, err = zip.open(limit_zip, "w", {max_file_size = 100})
assert(writer, "failed to create limited zip: " .. tostring(err))

ok, err = writer:add("small.txt", "hello")
assert(ok, "small content should work: " .. tostring(err))

result, err = writer:add("big.txt", string.rep("x", 200))
assert(result == nil, "content exceeding max_file_size should be rejected")
assert(err:match("max_file_size"), "error should mention max_file_size")

writer:close()

-- Test reader max_file_size enforcement
-- First create a zip with a larger file
local reader_limit_zip = tmpdir .. "/reader_limit_test.zip"
writer, err = zip.open(reader_limit_zip, "w")
assert(writer, "failed to create zip: " .. tostring(err))
ok, err = writer:add("big.txt", string.rep("y", 500))
assert(ok, "should add big file: " .. tostring(err))
writer:close()

-- Now try to read with a low limit
local reader, err = zip.open(reader_limit_zip, {max_file_size = 100})
assert(reader, "failed to open zip with limit: " .. tostring(err))

result, err = reader:read("big.txt")
assert(result == nil, "reading file exceeding max_file_size should fail")
assert(err:match("too large"), "error should mention size")

reader:close()

-- Test invalid max_file_size values: nil, err instead of a raise (issue #153)
result, err = zip.open(tmpdir .. "/bad.zip", "w", {max_file_size = 0})
assert(result == nil, "max_file_size = 0 should error")
assert(type(err) == "string", "max_file_size = 0 should return an error string")

result, err = zip.open(tmpdir .. "/bad.zip", "w", {max_file_size = -1})
assert(result == nil, "max_file_size = -1 should error")
assert(type(err) == "string", "max_file_size = -1 should return an error string")

result, err = zip.open(limit_zip, {max_file_size = 0})
assert(result == nil, "max_file_size = 0 on open should error")
assert(type(err) == "string", "max_file_size = 0 on open should return an error string")

--------------------------------------------------------------------------------
-- Test append mode security validations
--------------------------------------------------------------------------------

local append_zip = tmpdir .. "/append_security.zip"
writer = zip.open(append_zip, "w")
writer:add("original.txt", "original content")
writer:add("another.txt", "another file")
writer:close()

local appender, err = zip.open(append_zip, "a")
assert(appender, "failed to open for security tests: " .. tostring(err))

-- Path traversal rejection
result, err = appender:add("../escape.txt", "malicious")
assert(result == nil, "path traversal should be rejected")
assert(err:match("unsafe path"), "error should mention unsafe path")

result, err = appender:add("/absolute/path.txt", "malicious")
assert(result == nil, "absolute path should be rejected")

result, err = appender:add("foo/../bar.txt", "malicious")
assert(result == nil, "embedded .. should be rejected")

-- Empty name rejection
result, err = appender:add("", "content")
assert(result == nil, "empty name should be rejected")
assert(err:match("empty"), "error should mention empty")

-- Null byte rejection
result, err = appender:add("foo\0bar.txt", "content")
assert(result == nil, "null byte should be rejected")
assert(err:match("null"), "error should mention null")

-- Duplicate entry rejection (against existing entries)
result, err = appender:add("original.txt", "duplicate")
assert(result == nil, "duplicate of existing entry should be rejected")
assert(err:match("duplicate"), "error should mention duplicate")

-- Duplicate entry rejection (against newly added entries)
ok, err = appender:add("unique_new.txt", "first")
assert(ok, "first add should succeed: " .. tostring(err))

result, err = appender:add("unique_new.txt", "second")
assert(result == nil, "duplicate of new entry should be rejected")
assert(err:match("duplicate"), "error should mention duplicate")

appender:close()

--------------------------------------------------------------------------------
-- Test name length limits
--------------------------------------------------------------------------------

local name_limit_zip = tmpdir .. "/name_limit_test.zip"
writer = zip.open(name_limit_zip, "w")

-- Name at exactly 65535 bytes should work
local long_name = string.rep("a", 65535)
ok, err = writer:add(long_name, "content")
assert(ok, "65535 byte name should work: " .. tostring(err))

-- Name exceeding 65535 bytes should be rejected
local too_long_name = string.rep("b", 65536)
result, err = writer:add(too_long_name, "content")
assert(result == nil, "65536 byte name should be rejected")
assert(err:match("too long"), "error should mention too long")

writer:close()

--------------------------------------------------------------------------------
-- Test appender realloc safety (exercises internal array growth)
--------------------------------------------------------------------------------

local realloc_zip = tmpdir .. "/realloc_test.zip"
writer = zip.open(realloc_zip, "w")
writer:add("initial.txt", "initial")
writer:close()

appender = zip.open(realloc_zip, "a")

-- Add many entries to trigger multiple reallocs (initial capacity is 16)
for i = 1, 50 do
  ok, err = appender:add("file_" .. i .. ".txt", "content " .. i)
  assert(ok, "add " .. i .. " should succeed: " .. tostring(err))
end

ok, err = appender:close()
assert(ok, "close after many adds should succeed: " .. tostring(err))

-- Verify all entries are present
local reader = zip.open(realloc_zip)
local entries = reader:list()
assert(#entries == 51, "should have 51 entries (1 initial + 50 appended), got " .. #entries)
reader:close()

--------------------------------------------------------------------------------
-- H2 regression: cnt == 0 path (empty central directory, valid archive)
-- Exercises the calloc(cnt, ...) branch where cnt == 0 must not be treated
-- as an allocation failure (malloc(0) / calloc(0,...) may return NULL).
--------------------------------------------------------------------------------

-- Create a zip, remove all entries so the archive on disk has cnt=0, then
-- open it in append mode.  The appender must not error on the NULL return from
-- calloc(0, ...) and must accept new entries correctly.
local empty_cdir_zip = tmpdir .. "/empty_cdir.zip"
writer = zip.open(empty_cdir_zip, "w")
writer:add("will_be_removed.txt", "placeholder")
writer:close()

-- Open for append and immediately remove the only entry (leaving cnt == 0 on
-- the *next* open, after close rewrites the archive with an empty cdir).
appender = zip.open(empty_cdir_zip, "a")
assert(appender, "should open archive for append")
ok, err = appender:remove("will_be_removed.txt")
assert(ok, "remove should succeed: " .. tostring(err))
ok, err = appender:close()
assert(ok, "close after remove-all should succeed: " .. tostring(err))

-- The archive now has cnt == 0.  Opening for append must succeed (not OOM-error
-- on NULL calloc(0,...)) and must be able to add a new entry.
appender, err = zip.open(empty_cdir_zip, "a")
assert(appender, "opening zero-entry archive for append must succeed: " .. tostring(err))
ok, err = appender:add("new_entry.txt", "fresh content")
assert(ok, "adding to formerly-empty archive should succeed: " .. tostring(err))
ok, err = appender:close()
assert(ok, "close on formerly-empty archive should succeed: " .. tostring(err))

reader = zip.open(empty_cdir_zip)
assert(reader, "should open formerly-empty archive for read")
entries = reader:list()
assert(#entries == 1, "should have exactly 1 entry, got " .. #entries)
assert(reader:read("new_entry.txt") == "fresh content", "content must match")
reader:close()

--------------------------------------------------------------------------------
-- Test handling of truncated/corrupted zip files
--------------------------------------------------------------------------------

-- Create a valid zip then truncate it
local truncated_zip = tmpdir .. "/truncated.zip"
writer = zip.open(truncated_zip, "w")
writer:add("test.txt", "test content here")
writer:close()

-- Read original size
local f = io.open(truncated_zip, "rb")
local original = f:read("*a")
f:close()

-- Write truncated version (remove last 10 bytes, breaking the EOCD)
f = io.open(truncated_zip, "wb")
f:write(original:sub(1, #original - 10))
f:close()

-- Opening truncated zip for append should fail gracefully
result, err = zip.open(truncated_zip, "a")
assert(result == nil, "truncated zip should fail to open for append")
assert(err:match("not a zip"), "error should indicate invalid zip")

--------------------------------------------------------------------------------
-- OOB-read guard: zip.from() on inputs shorter than a valid EOCD (22 bytes)
-- must return an error rather than crashing / reading out of bounds.
--------------------------------------------------------------------------------

-- Empty string
result, err = zip.from("")
assert(result == nil, "zip.from('') should fail gracefully")
assert(err, "zip.from('') must return an error message")

-- "PK" signature prefix (2 bytes) - too short for any valid ZIP structure
result, err = zip.from("PK")
assert(result == nil, "zip.from('PK') should be rejected")
assert(err:match("not a zip"), "error should indicate invalid zip")

-- 21 bytes - one byte short of the minimum EOCD record
result, err = zip.from(string.rep("\0", 21))
assert(result == nil, "21-byte input should be rejected as too small")
assert(err, "21-byte input must return an error message")

-- 22 bytes of zeros - minimum size but no valid EOCD magic, so still rejected
result, err = zip.from(string.rep("\0", 22))
assert(result == nil, "22 zero bytes should be rejected (no valid EOCD magic)")
assert(err, "22 zero bytes must return an error message")

-- Verify the size guard works for zip.open() too (via a file smaller than 22 bytes)
local tiny_zip = tmpdir .. "/tiny.zip"
local tf = io.open(tiny_zip, "wb")
tf:write("PK")
tf:close()
result, err = zip.open(tiny_zip)
assert(result == nil, "zip.open() on a 2-byte file should fail")
assert(err:match("not a zip"), "zip.open() error should indicate invalid zip")

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

assert(unix.rmrf(tmpdir))
assert(not unix.stat(tmpdir), "tmpdir should not exist after cleanup")

print("PASS")
