-- Functional tests for the cosmo.cov line-hit coverage collector
-- (tool/net/lcov.c). The assertions mirror what cosmic's
-- cosmic.coverage collector records with its Lua debug hook, because
-- cov exists to replace that hook with identical attribution: chunks
-- keyed by lua_Debug.source, values mapping line number to hit count.

local cov = require("cosmo.cov")

local function load_chunk(source, name)
  local chunk = assert(load(source, name), "load failed for " .. name)
  return chunk
end

-- start/stop bracket collection; counts are per (source, line)
do
  local run = load_chunk("local s = 0\nfor i = 1, 3 do\n  s = s + i\nend\nreturn s\n",
    "@covtest_chunk.lua")
  cov.reset()
  cov.start()
  local v = run()
  cov.stop()
  assert(v == 6, "chunk returned " .. tostring(v))
  local snap = cov.snapshot()
  local hits = snap["@covtest_chunk.lua"]
  assert(hits, "no hits recorded for the loaded chunk")
  assert(hits[1] == 1, "line 1 expected 1 hit, got " .. tostring(hits[1]))
  assert(hits[3] == 3, "loop body expected 3 hits, got " .. tostring(hits[3]))
end

-- running() reflects the calling thread's hook
do
  assert(not cov.running(), "not armed yet")
  cov.start()
  assert(cov.running(), "armed")
  cov.stop()
  assert(not cov.running(), "disarmed")
end

-- stop() leaves a foreign hook alone
do
  local seen = false
  debug.sethook(function() seen = true end, "l")
  cov.stop()
  local hook = debug.gethook()
  assert(hook ~= nil, "stop() removed a hook it did not install")
  debug.sethook()
  assert(not cov.running(), "foreign hook is not this collector's")
  local _ = seen
end

-- lines run after stop() are not counted
do
  local run = load_chunk("local a = 1\n", "@covtest_stopped.lua")
  cov.reset()
  cov.start()
  cov.stop()
  run()
  local snap = cov.snapshot()
  assert(snap["@covtest_stopped.lua"] == nil, "counted while stopped")
end

-- a coroutine created while armed inherits the hook: lua_newthread
-- copies C hooks into new threads (unlike Lua-function hooks, whose
-- per-thread registry entry is not copied), so its lines count into
-- the shared state with no explicit arm
do
  local run = load_chunk("local s = 0\nfor i = 1, 2 do\n  s = s + i\nend\nreturn s\n",
    "@covtest_co.lua")
  cov.reset()
  cov.start()
  local co = coroutine.create(run)
  local ok, v = coroutine.resume(co)
  cov.stop()
  assert(ok and v == 3, "coroutine failed: " .. tostring(v))
  local snap = cov.snapshot()
  local hits = snap["@covtest_co.lua"]
  assert(hits, "no hits recorded inside the coroutine")
  assert(hits[3] == 2, "coroutine loop body expected 2 hits, got " ..
    tostring(hits and hits[3]))
end

-- a coroutine created before start() has no hook to inherit; arm()
-- opts it in explicitly
do
  local run = load_chunk("local b = 2\n", "@covtest_co_pre.lua")
  local unarmed = coroutine.create(run)
  local armed = coroutine.create(run)
  cov.reset()
  cov.start()
  cov.arm(armed)
  assert(coroutine.resume(unarmed), "unarmed coroutine failed")
  cov.stop()
  local snap = cov.snapshot()
  assert(snap["@covtest_co_pre.lua"] == nil,
    "pre-start coroutine counted without arm()")
  cov.start()
  assert(coroutine.resume(armed), "armed coroutine failed")
  cov.stop()
  snap = cov.snapshot()
  local hits = snap["@covtest_co_pre.lua"]
  assert(hits and hits[1] == 1, "arm() did not opt the coroutine in")
end

-- snapshot() returns fresh, independent copies
do
  local run = load_chunk("local c = 3\n", "@covtest_fresh.lua")
  cov.reset()
  cov.start()
  run()
  cov.stop()
  local a = cov.snapshot()
  a["@covtest_fresh.lua"][1] = 999
  local b = cov.snapshot()
  assert(b["@covtest_fresh.lua"][1] == 1,
    "mutating one snapshot leaked into the next")
end

-- reset() discards counts; a still-armed hook keeps counting after
do
  local run = load_chunk("local d = 4\n", "@covtest_reset.lua")
  cov.reset()
  cov.start()
  run()
  cov.reset()
  run()
  cov.stop()
  local snap = cov.snapshot()
  local hits = snap["@covtest_reset.lua"]
  assert(hits and hits[1] == 1,
    "expected exactly the post-reset hit, got " ..
    tostring(hits and hits[1]))
end

-- counts survive across many distinct chunks (hash-table exercise)
do
  cov.reset()
  cov.start()
  for i = 1, 100 do
    load_chunk("local x = " .. i .. "\n", "@covtest_many_" .. i .. ".lua")()
  end
  cov.stop()
  local snap = cov.snapshot()
  for i = 1, 100 do
    local hits = snap["@covtest_many_" .. i .. ".lua"]
    assert(hits and hits[1] == 1, "chunk " .. i .. " miscounted")
  end
end

cov.reset()
print("test_cov: PASS")
