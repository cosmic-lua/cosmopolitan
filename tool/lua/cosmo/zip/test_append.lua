-- Tests for cosmo.zip append mode

local zip = require("cosmo.zip")
local unix = require("cosmo.unix")

local tmpdir = unix.mkdtemp("/tmp/test_zip_append_XXXXXX")
assert(tmpdir, "failed to create temp dir")

--------------------------------------------------------------------------------
-- Test basic append functionality
--------------------------------------------------------------------------------

-- Create initial zip with write mode
local append_zip = tmpdir .. "/test_append.zip"
local writer, err = zip.open(append_zip, "w")
assert(writer, "failed to create zip for append test: " .. tostring(err))

local ok, err = writer:add("original.txt", "original content")
assert(ok, "failed to add original.txt: " .. tostring(err))

ok, err = writer:add("another.txt", "another file")
assert(ok, "failed to add another.txt: " .. tostring(err))

ok, err = writer:close()
assert(ok, "failed to close initial zip: " .. tostring(err))

-- Open in append mode and add new entries
local appender, err = zip.open(append_zip, "a")
assert(appender, "failed to open for append: " .. tostring(err))
assert(tostring(appender):match("zip.Appender"), "should be a zip.Appender")
assert(tostring(appender):match("0 pending"), "should have 0 pending entries")

ok, err = appender:add("appended.txt", "appended content")
assert(ok, "failed to add appended.txt: " .. tostring(err))
assert(tostring(appender):match("1 pending"), "should have 1 pending entry")

ok, err = appender:add("subdir/new.txt", "new file in subdir")
assert(ok, "failed to add subdir/new.txt: " .. tostring(err))

ok, err = appender:close()
assert(ok, "failed to close appender: " .. tostring(err))
assert(tostring(appender):match("closed"), "should be closed")

-- Verify all entries are present (original + appended)
local reader, err = zip.open(append_zip)
assert(reader, "failed to open appended zip: " .. tostring(err))

local entries = reader:list()
assert(#entries == 4, "should have 4 entries after append, got " .. #entries)

local entry_set = {}
for _, name in ipairs(entries) do
  entry_set[name] = true
end
assert(entry_set["original.txt"], "should have original.txt")
assert(entry_set["another.txt"], "should have another.txt")
assert(entry_set["appended.txt"], "should have appended.txt")
assert(entry_set["subdir/new.txt"], "should have subdir/new.txt")

-- Verify content is correct
local orig_content = reader:read("original.txt")
assert(orig_content == "original content", "original content should be preserved")

local appended_content = reader:read("appended.txt")
assert(appended_content == "appended content", "appended content should be correct")

reader:close()

--------------------------------------------------------------------------------
-- Test append mode with max_file_size
--------------------------------------------------------------------------------

local limit_append_zip = tmpdir .. "/test_append_limit.zip"
writer, err = zip.open(limit_append_zip, "w")
assert(writer, "failed to create zip: " .. tostring(err))
writer:add("existing.txt", "existing")
writer:close()

appender, err = zip.open(limit_append_zip, "a", {max_file_size = 50})
assert(appender, "failed to open with limit: " .. tostring(err))

ok, err = appender:add("small.txt", "small content")
assert(ok, "small content should work: " .. tostring(err))

local result, err = appender:add("big.txt", string.rep("x", 100))
assert(result == nil, "content exceeding limit should be rejected")
assert(err:match("max_file_size"), "error should mention max_file_size")

appender:close()

-- Test invalid max_file_size values for append mode
result, err = zip.open(limit_append_zip, "a", {max_file_size = 0})
assert(result == nil, "max_file_size = 0 should error")

result, err = zip.open(limit_append_zip, "a", {max_file_size = -1})
assert(result == nil, "max_file_size = -1 should error")

--------------------------------------------------------------------------------
-- Test append mode fd rejection
--------------------------------------------------------------------------------

local fd_zip = tmpdir .. "/test_fd.zip"
writer = zip.open(fd_zip, "w")
writer:add("test.txt", "test")
writer:close()

local fd = unix.open(fd_zip, unix.O_RDONLY)
assert(fd, "failed to open fd")

result, err = zip.open(fd, "a")
assert(result == nil, "fd mode for append should be rejected")
assert(err:match("file descriptor"), "error should mention file descriptor")

unix.close(fd)

--------------------------------------------------------------------------------
-- Test append to non-existent file (should create new zip)
--------------------------------------------------------------------------------

local new_append_zip = tmpdir .. "/new_append.zip"
appender, err = zip.open(new_append_zip, "a")
assert(appender, "should be able to open non-existent file for append: " .. tostring(err))

ok, err = appender:add("first.txt", "first file")
assert(ok, "should add first entry: " .. tostring(err))

ok, err = appender:close()
assert(ok, "should close appender: " .. tostring(err))

reader = zip.open(new_append_zip)
assert(reader, "should be able to read new zip")
entries = reader:list()
assert(#entries == 1, "should have 1 entry")
assert(reader:read("first.txt") == "first file", "content should match")
reader:close()

--------------------------------------------------------------------------------
-- Test append with no entries (should be no-op)
--------------------------------------------------------------------------------

local noop_zip = tmpdir .. "/noop.zip"
writer = zip.open(noop_zip, "w")
writer:add("keep.txt", "keep this")
writer:close()

appender = zip.open(noop_zip, "a")
assert(appender, "should open for append")
-- Don't add anything
ok, err = appender:close()
assert(ok, "close with no entries should succeed: " .. tostring(err))

reader = zip.open(noop_zip)
entries = reader:list()
assert(#entries == 1, "should still have 1 entry")
assert(reader:read("keep.txt") == "keep this", "original content should be preserved")
reader:close()

--------------------------------------------------------------------------------
-- Test operations on closed appender
--------------------------------------------------------------------------------

appender = zip.open(noop_zip, "a")
appender:close()

result, err = appender:add("test.txt", "content")
assert(result == nil, "add on closed appender should fail")
assert(err:match("closed"), "error should mention closed")

--------------------------------------------------------------------------------
-- Test remove existing entry
--------------------------------------------------------------------------------

local remove_zip = tmpdir .. "/remove_test.zip"
writer = zip.open(remove_zip, "w")
writer:add("keep.txt", "keep this")
writer:add("remove_me.txt", "remove this")
writer:add("also_keep.txt", "also keep")
writer:close()

appender = zip.open(remove_zip, "a")
assert(appender, "should open for append")

ok, err = appender:remove("remove_me.txt")
assert(ok, "remove should succeed: " .. tostring(err))

ok, err = appender:close()
assert(ok, "close after remove should succeed: " .. tostring(err))

reader = zip.open(remove_zip)
entries = reader:list()
assert(#entries == 2, "should have 2 entries after remove, got " .. #entries)

entry_set = {}
for _, name in ipairs(entries) do
  entry_set[name] = true
end
assert(entry_set["keep.txt"], "keep.txt should still exist")
assert(entry_set["also_keep.txt"], "also_keep.txt should still exist")
assert(not entry_set["remove_me.txt"], "remove_me.txt should be gone")

assert(reader:read("keep.txt") == "keep this", "keep.txt content should be preserved")
assert(reader:read("also_keep.txt") == "also keep", "also_keep.txt content should be preserved")
reader:close()

--------------------------------------------------------------------------------
-- Test remove then add same name (replace pattern)
--------------------------------------------------------------------------------

local replace_zip = tmpdir .. "/replace_test.zip"
writer = zip.open(replace_zip, "w")
writer:add("config.txt", "old config")
writer:add("data.txt", "data file")
writer:close()

appender = zip.open(replace_zip, "a")
assert(appender, "should open for append")

ok, err = appender:remove("config.txt")
assert(ok, "remove should succeed: " .. tostring(err))

ok, err = appender:add("config.txt", "new config")
assert(ok, "add after remove should succeed: " .. tostring(err))

ok, err = appender:close()
assert(ok, "close should succeed: " .. tostring(err))

reader = zip.open(replace_zip)
entries = reader:list()
assert(#entries == 2, "should still have 2 entries, got " .. #entries)

local config_content = reader:read("config.txt")
assert(config_content == "new config", "config should have new content, got: " .. tostring(config_content))
assert(reader:read("data.txt") == "data file", "data.txt should be preserved")
reader:close()

--------------------------------------------------------------------------------
-- Test remove pending entry
--------------------------------------------------------------------------------

local remove_pending_zip = tmpdir .. "/remove_pending_test.zip"
writer = zip.open(remove_pending_zip, "w")
writer:add("existing.txt", "existing")
writer:close()

appender = zip.open(remove_pending_zip, "a")
appender:add("new1.txt", "new content 1")
appender:add("new2.txt", "new content 2")

-- Remove a pending entry (not yet written to disk)
ok, err = appender:remove("new1.txt")
assert(ok, "remove pending entry should succeed: " .. tostring(err))

ok, err = appender:close()
assert(ok, "close should succeed: " .. tostring(err))

reader = zip.open(remove_pending_zip)
entries = reader:list()
assert(#entries == 2, "should have 2 entries (existing + new2), got " .. #entries)

entry_set = {}
for _, name in ipairs(entries) do
  entry_set[name] = true
end
assert(entry_set["existing.txt"], "existing.txt should be present")
assert(entry_set["new2.txt"], "new2.txt should be present")
assert(not entry_set["new1.txt"], "new1.txt should be gone")
reader:close()

--------------------------------------------------------------------------------
-- Test remove non-existent entry
--------------------------------------------------------------------------------

appender = zip.open(remove_pending_zip, "a")

result, err = appender:remove("nonexistent.txt")
assert(result == nil, "removing non-existent entry should fail")
assert(err:match("not found"), "error should mention not found")

appender:close()

--------------------------------------------------------------------------------
-- Test remove on closed appender
--------------------------------------------------------------------------------

appender = zip.open(remove_pending_zip, "a")
appender:close()

result, err = appender:remove("test.txt")
assert(result == nil, "remove on closed appender should fail")
assert(err:match("closed"), "error should mention closed")

--------------------------------------------------------------------------------
-- Test remove all entries
--------------------------------------------------------------------------------

local remove_all_zip = tmpdir .. "/remove_all_test.zip"
writer = zip.open(remove_all_zip, "w")
writer:add("a.txt", "aaa")
writer:add("b.txt", "bbb")
writer:close()

appender = zip.open(remove_all_zip, "a")
appender:remove("a.txt")
appender:remove("b.txt")
appender:close()

reader = zip.open(remove_all_zip)
entries = reader:list()
assert(#entries == 0, "should have 0 entries after removing all, got " .. #entries)
reader:close()

--------------------------------------------------------------------------------
-- Test remove directory (recursive prefix removal)
--------------------------------------------------------------------------------

local remove_dir_zip = tmpdir .. "/remove_dir_test.zip"
writer = zip.open(remove_dir_zip, "w")
writer:add("root.txt", "root file")
writer:add("subdir/a.txt", "aaa")
writer:add("subdir/b.txt", "bbb")
writer:add("subdir/nested/c.txt", "ccc")
writer:add("other/d.txt", "ddd")
writer:close()

appender = zip.open(remove_dir_zip, "a")
assert(appender, "should open for append")

-- Remove entire subdir/ directory recursively
ok, err = appender:remove("subdir/")
assert(ok, "directory remove should succeed: " .. tostring(err))

ok, err = appender:close()
assert(ok, "close should succeed: " .. tostring(err))

reader = zip.open(remove_dir_zip)
entries = reader:list()
assert(#entries == 2, "should have 2 entries after dir remove, got " .. #entries)

entry_set = {}
for _, name in ipairs(entries) do
  entry_set[name] = true
end
assert(entry_set["root.txt"], "root.txt should still exist")
assert(entry_set["other/d.txt"], "other/d.txt should still exist")
assert(not entry_set["subdir/a.txt"], "subdir/a.txt should be gone")
assert(not entry_set["subdir/b.txt"], "subdir/b.txt should be gone")
assert(not entry_set["subdir/nested/c.txt"], "subdir/nested/c.txt should be gone")
reader:close()

--------------------------------------------------------------------------------
-- Test remove directory with pending entries
--------------------------------------------------------------------------------

local remove_dir_pending_zip = tmpdir .. "/remove_dir_pending_test.zip"
writer = zip.open(remove_dir_pending_zip, "w")
writer:add("existing.txt", "existing")
writer:add("dir/old.txt", "old file")
writer:close()

appender = zip.open(remove_dir_pending_zip, "a")
appender:add("dir/new1.txt", "new 1")
appender:add("dir/new2.txt", "new 2")
appender:add("other.txt", "other")

-- Remove dir/ should remove existing dir/old.txt AND pending dir/new1.txt, dir/new2.txt
ok, err = appender:remove("dir/")
assert(ok, "directory remove should succeed: " .. tostring(err))

appender:close()

reader = zip.open(remove_dir_pending_zip)
entries = reader:list()
assert(#entries == 2, "should have 2 entries, got " .. #entries)

entry_set = {}
for _, name in ipairs(entries) do
  entry_set[name] = true
end
assert(entry_set["existing.txt"], "existing.txt should be present")
assert(entry_set["other.txt"], "other.txt should be present")
assert(not entry_set["dir/old.txt"], "dir/old.txt should be gone")
assert(not entry_set["dir/new1.txt"], "dir/new1.txt should be gone")
assert(not entry_set["dir/new2.txt"], "dir/new2.txt should be gone")
reader:close()

--------------------------------------------------------------------------------
-- Test remove directory then add new entries in same directory
--------------------------------------------------------------------------------

local replace_dir_zip = tmpdir .. "/replace_dir_test.zip"
writer = zip.open(replace_dir_zip, "w")
writer:add("assets/logo.png", "old logo")
writer:add("assets/style.css", "old style")
writer:add("index.html", "index")
writer:close()

appender = zip.open(replace_dir_zip, "a")
appender:remove("assets/")
appender:add("assets/logo.png", "new logo")
appender:add("assets/app.js", "new script")
appender:close()

reader = zip.open(replace_dir_zip)
entries = reader:list()
assert(#entries == 3, "should have 3 entries, got " .. #entries)

assert(reader:read("index.html") == "index", "index.html should be preserved")
assert(reader:read("assets/logo.png") == "new logo", "logo should have new content")
assert(reader:read("assets/app.js") == "new script", "app.js should exist")

local old_style = reader:read("assets/style.css")
assert(old_style == nil, "style.css should be gone")
reader:close()

--------------------------------------------------------------------------------
-- Test remove non-existent directory
--------------------------------------------------------------------------------

appender = zip.open(replace_dir_zip, "a")
result, err = appender:remove("nonexistent/")
assert(result == nil, "removing non-existent directory should fail")
assert(err:match("not found"), "error should mention not found")
appender:close()

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

os.execute("rm -rf " .. tmpdir)

print("PASS")
