-- Regression test for unix.setfsuid/unix.setfsgid on a refused change.
--
-- setfsuid(2)/setfsgid(2) can't signal failure through their return
-- value the way most unix.set*id bindings assume: success returns the
-- PREVIOUS fsuid/fsgid, failure returns the CURRENT (unchanged) one,
-- and neither is -1 in ordinary operation. An unprivileged caller
-- asking for an id it doesn't hold must still see an honest failure
-- from the Lua binding, not a false `true`.

local unix = require("cosmo.unix")

local UNPRIV = 65534  -- "nobody"

-- Runs `body` (a function returning a "PASS"/"FAIL:<reason>" string) in
-- a forked child that first drops to an unprivileged uid/gid if it
-- started as root, then reports the result back over a pipe.
local function run_unprivileged(body)
  local r, w = assert(unix.pipe())
  local pid = assert(unix.fork())
  if pid == 0 then
    unix.close(r)
    if unix.getuid() == 0 then
      if not unix.setgid(UNPRIV) or not unix.setuid(UNPRIV) then
        unix.write(w, "SKIP:could not drop to an unprivileged id")
        unix.close(w)
        unix.exit(0)
      end
    end
    local ok, result = pcall(body)
    if not ok then
      result = "FAIL:" .. tostring(result)
    end
    unix.write(w, result)
    unix.close(w)
    unix.exit(0)
  end
  unix.close(w)
  local chunks = {}
  while true do
    local chunk = assert(unix.read(r, 4096))
    if #chunk == 0 then break end
    chunks[#chunks + 1] = chunk
  end
  unix.close(r)
  local _, wstatus = assert(unix.wait(pid))
  assert(unix.WIFEXITED(wstatus), "probe child should exit normally")
  return table.concat(chunks)
end

-- The fsuid/fsgid column is the fourth id on /proc/self/status's
-- Uid:/Gid: line (real, effective, saved, fs). Cross-checking it keeps
-- the test honest about what the kernel actually did, not just what
-- the binding claims.
local function proc_fsid(label)
  local f = assert(io.open("/proc/self/status"))
  local fsid
  for line in f:lines() do
    if line:match("^" .. label .. ":") then
      local nums = {}
      for n in line:gmatch("%d+") do nums[#nums + 1] = tonumber(n) end
      fsid = nums[4]
    end
  end
  f:close()
  return fsid
end

local function check_refused(setter, label, own_id)
  -- An id this process doesn't hold and has no capability to assume:
  -- the kernel must refuse the change, and the binding must say so.
  local ok, err, errno = setter(0)
  if ok ~= nil then
    return "FAIL:setfs" .. label .. "(0) as unprivileged reported ok=" ..
           tostring(ok) .. " instead of failing"
  end
  if errno ~= unix.EPERM then
    return "FAIL:expected errno EPERM, got " .. tostring(errno) ..
           " (" .. tostring(err) .. ")"
  end
  if type(err) ~= "string" or not err:find("setfs" .. label) then
    return "FAIL:error string should name the call, got " .. tostring(err)
  end
  local got = proc_fsid(label == "uid" and "Uid" or "Gid")
  if got ~= own_id then
    return "FAIL:kernel " .. label .. " changed to " .. tostring(got) ..
           " despite the refusal"
  end
  -- The one id this process DOES hold (its own, post-drop) must still
  -- be settable -- the fix must not turn every call into a failure.
  local self_ok, self_err = setter(own_id)
  if self_ok ~= true then
    return "FAIL:setfs" .. label .. "(own id) should still succeed: " ..
           tostring(self_err)
  end
  return "PASS"
end

local uid_result = run_unprivileged(function()
  return check_refused(unix.setfsuid, "uid", unix.getuid())
end)
local gid_result = run_unprivileged(function()
  return check_refused(unix.setfsgid, "gid", unix.getgid())
end)

for _, r in ipairs({{"setfsuid", uid_result}, {"setfsgid", gid_result}}) do
  local name, result = r[1], r[2]
  if result:match("^SKIP:") then
    print("test_setfsid: " .. name .. " " .. result)
  else
    assert(result == "PASS", name .. ": " .. result)
  end
end

print("PASS")
