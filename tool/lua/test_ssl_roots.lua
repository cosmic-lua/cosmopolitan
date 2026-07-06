-- The pinned SSL roots ship in two halves that must stay in sync: the PEM
-- files in usr/share/ssl/root/ (compiled into zip assets by a $(wildcard)
-- in net/https/BUILD.mk) and the per-file __static_yoink list in
-- net/https/sslroots.c that actually forces each asset into the link. A
-- PEM added to the directory without its yoink line compiles fine and
-- silently never ships: usertrust.pem sat in the repo unlinked, so any
-- consumer relying on the embedded store (SSL_USE_SYSTEM_CERTS unset)
-- could not verify github.com, whose Sectigo chain anchors at the
-- USERTrust roots. Assert that every repo cert is yoinked AND present in
-- this binary's zip, and that nothing ships that the repo no longer has.

local unix = require("cosmo.unix")

local function pems_in(dir)
  local names = {}
  local d = assert(unix.opendir(dir))
  while true do
    local name = d:read()
    if not name then
      break
    end
    if name:match("%.pem$") then
      names[#names + 1] = name
    end
  end
  d:close()
  table.sort(names)
  return names
end

local repo = pems_in("usr/share/ssl/root")
local zip = pems_in("/zip/usr/share/ssl/root")
assert(#repo > 0, "no PEMs found in usr/share/ssl/root (run from repo root)")

local f = assert(io.open("net/https/sslroots.c"))
local src = f:read("*a")
f:close()

local failures = {}

for _, name in ipairs(repo) do
  if not src:find('__static_yoink("usr/share/ssl/root/' .. name .. '")', 1,
                  true) then
    failures[#failures + 1] = name .. " is in usr/share/ssl/root/ but not " ..
      "yoinked in net/https/sslroots.c (it will compile and silently not ship)"
  end
end

local zipset = {}
for _, name in ipairs(zip) do
  zipset[name] = true
end
for _, name in ipairs(repo) do
  if not zipset[name] then
    failures[#failures + 1] = name .. " is in usr/share/ssl/root/ but " ..
      "missing from this binary's /zip/usr/share/ssl/root/"
  end
end

local reposet = {}
for _, name in ipairs(repo) do
  reposet[name] = true
end
for _, name in ipairs(zip) do
  if not reposet[name] then
    failures[#failures + 1] = name .. " ships in /zip but is gone from " ..
      "usr/share/ssl/root/ (stale embedded root)"
  end
end

assert(#failures == 0,
       "ssl root pinning drift:\n  " .. table.concat(failures, "\n  "))
print("test_ssl_roots: " .. #repo .. " roots in repo, " .. #zip ..
      " embedded: PASS")
