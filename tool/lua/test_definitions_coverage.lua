-- Annotation-coverage ratchet for the unix.* C bindings.
--
-- Every function registered in kLuaUnix[] and every constant registered via
-- LuaSetIntField() in third_party/lua/lunix.c must have a matching declaration
-- in tool/net/definitions.lua, so downstream type generators (e.g. cosmic's
-- gentype) can emit the whole surface instead of hand-maintaining it.
--
-- ALLOW_* below are the symbols that are knowingly not yet annotated. This list
-- is a RATCHET: it may only shrink. Adding a new binding without its annotation
-- fails this test -- annotate the binding, do not append to the allowlist. When
-- you annotate an allowlisted symbol (or drop it from the C), remove it here or
-- the stale-entry check fails.
--
-- Limitation: constants registered dynamically via LoadMagnums() (the IP_/TCP_/
-- SO_/CLOCK_ families) are not covered -- only literal LuaSetIntField() names.

local function slurp(path)
  local f = assert(io.open(path, "r"), "cannot open " .. path)
  local s = f:read("*a")
  f:close()
  return s
end

local C = slurp("third_party/lua/lunix.c")
local D = slurp("tool/net/definitions.lua")

-- Registered top-level functions: { "name", LuaUnixXxx } inside kLuaUnix[].
local body = assert(C:match("kLuaUnix%[%]%s*=%s*{(.-)\n};"),
  "could not locate the kLuaUnix[] table")
local reg_fns = {}
for name in body:gmatch('{"([%a_][%w_]*)"%s*,%s*LuaUnix') do
  reg_fns[name] = true
end

-- Registered constants: literal LuaSetIntField(L, "NAME", ...).
local reg_consts = {}
for name in C:gmatch('LuaSetIntField%(L,%s*"([%u][%w_]*)"') do
  reg_consts[name] = true
end

-- Annotated functions: function unix.name(
local ann_fns = {}
for name in D:gmatch("\nfunction unix%.([%a_][%w_]*)%s*%(") do
  ann_fns[name] = true
end

-- Annotated constants: NAME = ... (the `NAME = nil` stubs in the unix table).
local ann_consts = {}
for name in D:gmatch("\n%s*([%u][%w_]*)%s*=") do
  ann_consts[name] = true
end

local function set(list)
  local t = {}
  for _, v in ipairs(list) do t[v] = true end
  return t
end

-- ===== ratchet allowlist (may only shrink) =====

local ALLOW_FNS = set({
  "setfsgid", "sigpending", "verynice",})

local ALLOW_CONSTS = set({
  "AT_EACCESS", "CAP_AUDIT_CONTROL", "CAP_AUDIT_READ", "CAP_AUDIT_WRITE",
  "CAP_BLOCK_SUSPEND", "CAP_BPF", "CAP_CHECKPOINT_RESTORE", "CAP_CHOWN",
  "CAP_DAC_OVERRIDE", "CAP_DAC_READ_SEARCH", "CAP_FOWNER", "CAP_FSETID",
  "CAP_IPC_LOCK", "CAP_IPC_OWNER", "CAP_KILL", "CAP_LAST_CAP",
  "CAP_LEASE", "CAP_LINUX_IMMUTABLE", "CAP_MAC_ADMIN", "CAP_MAC_OVERRIDE",
  "CAP_MKNOD", "CAP_NET_ADMIN", "CAP_NET_BIND_SERVICE", "CAP_NET_BROADCAST",
  "CAP_NET_RAW", "CAP_PERFMON", "CAP_SETFCAP", "CAP_SETGID",
  "CAP_SETPCAP", "CAP_SETUID", "CAP_SYSLOG", "CAP_SYS_ADMIN",
  "CAP_SYS_BOOT", "CAP_SYS_CHROOT", "CAP_SYS_MODULE", "CAP_SYS_NICE",
  "CAP_SYS_PACCT", "CAP_SYS_PTRACE", "CAP_SYS_RAWIO", "CAP_SYS_RESOURCE",
  "CAP_SYS_TIME", "CAP_SYS_TTY_CONFIG", "CAP_WAKE_ALARM", "CLONE_NEWCGROUP",
  "CLONE_NEWIPC", "CLONE_NEWTIME", "EFTYPE", "EHWPOISON",
  "EMEDIUMTYPE", "EMULTIHOP", "ENOLINK", "ENOMEDIUM",
  "ENOSR", "ENOSTR", "ERFKILL", "F_GETLK",
  "IFF_ALLMULTI", "IFF_AUTOMEDIA", "IFF_BROADCAST", "IFF_DEBUG",
  "IFF_DYNAMIC", "IFF_LOOPBACK", "IFF_MASTER", "IFF_MULTICAST",
  "IFF_NOARP", "IFF_NOTRAILERS", "IFF_POINTOPOINT", "IFF_PORTSEL",
  "IFF_PROMISC", "IFF_RUNNING", "IFF_SLAVE", "LANDLOCK_CREATE_RULESET_VERSION",
  "LANDLOCK_RULE_PATH_BENEATH", "MNT_DETACH", "MNT_EXPIRE", "MNT_FORCE",
  "MSG_CTRUNC", "MSG_DONTWAIT", "MSG_TRUNC", "MS_BIND",
  "MS_DIRSYNC", "MS_LAZYTIME", "MS_MANDLOCK", "MS_MOVE",
  "MS_NOATIME", "MS_NODEV", "MS_NODIRATIME", "MS_NOEXEC",
  "MS_NOSUID", "MS_POSIXACL", "MS_PRIVATE", "MS_RDONLY",
  "MS_REC", "MS_RELATIME", "MS_REMOUNT", "MS_SHARED",
  "MS_SILENT", "MS_SLAVE", "MS_STRICTATIME", "MS_SYNCHRONOUS",
  "MS_UNBINDABLE", "PR_CAPBSET_DROP", "PR_CAPBSET_READ", "PR_GET_CHILD_SUBREAPER",
  "PR_GET_DUMPABLE", "PR_GET_KEEPCAPS", "PR_GET_NAME", "PR_GET_NO_NEW_PRIVS",
  "PR_GET_PDEATHSIG", "PR_SET_CHILD_SUBREAPER", "PR_SET_DUMPABLE", "PR_SET_NAME",
  "PR_SET_PDEATHSIG", "SIOCGIFADDR", "SIOCGIFBRDADDR", "SIOCGIFDSTADDR",
  "SIOCGIFINDEX", "SIOCGIFMETRIC", "SIOCGIFMTU", "SIOCGIFNAME",
  "SIOCGIFNETMASK", "SIOCSIFADDR", "SIOCSIFBRDADDR", "SIOCSIFDSTADDR",
  "SIOCSIFMETRIC", "SIOCSIFMTU", "SIOCSIFNETMASK", "ST_APPEND",
  "ST_IMMUTABLE", "ST_MANDLOCK", "ST_NOATIME", "ST_NODEV",
  "ST_NODIRATIME", "ST_NOEXEC", "ST_NOSUID", "ST_RDONLY",
  "ST_RELATIME", "ST_SYNCHRONOUS", "ST_WRITE", "UMOUNT_NOFOLLOW",})

-- ===== checks =====

local function sorted_keys(t)
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = k end
  table.sort(ks)
  return ks
end

-- 1) New gaps: registered but neither annotated nor allowlisted.
local new_gaps = {}
for name in pairs(reg_fns) do
  if not ann_fns[name] and not ALLOW_FNS[name] then
    new_gaps[#new_gaps + 1] = "function unix." .. name
  end
end
for name in pairs(reg_consts) do
  if not ann_consts[name] and not ALLOW_CONSTS[name] then
    new_gaps[#new_gaps + 1] = "constant unix." .. name
  end
end
table.sort(new_gaps)
assert(#new_gaps == 0,
  "these unix.* bindings are registered in lunix.c but not annotated in\n" ..
  "definitions.lua (annotate them; do not add to the allowlist):\n  " ..
  table.concat(new_gaps, "\n  "))

-- 2) Stale allowlist entries: allowlisted but now annotated or gone from C.
local stale = {}
for _, name in ipairs(sorted_keys(ALLOW_FNS)) do
  if ann_fns[name] then
    stale[#stale + 1] = "function " .. name .. " is now annotated"
  elseif not reg_fns[name] then
    stale[#stale + 1] = "function " .. name .. " is no longer registered"
  end
end
for _, name in ipairs(sorted_keys(ALLOW_CONSTS)) do
  if ann_consts[name] then
    stale[#stale + 1] = "constant " .. name .. " is now annotated"
  elseif not reg_consts[name] then
    stale[#stale + 1] = "constant " .. name .. " is no longer registered"
  end
end
assert(#stale == 0,
  "the annotation-coverage allowlist has stale entries (remove them so the\n" ..
  "ratchet stays tight):\n  " .. table.concat(stale, "\n  "))

print("definitions coverage: " ..
  tostring(#sorted_keys(reg_fns)) .. " functions, " ..
  tostring(#sorted_keys(reg_consts)) .. " constants checked; " ..
  tostring(#sorted_keys(ALLOW_FNS)) .. " fn + " ..
  tostring(#sorted_keys(ALLOW_CONSTS)) .. " const allowlisted")
print("test_definitions_coverage: PASS")
