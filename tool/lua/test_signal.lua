-- Stress test for deferred Lua signal dispatch (whilp/cosmopolitan#149 item 4).
--
-- The old unix.sigaction ran the Lua handler with lua_pcall directly inside the
-- real signal handler. A signal landing while the VM was mid-malloc or mid-GC
-- could re-enter the allocator/collector and corrupt the heap, so this exact
-- workload -- a tight table-allocation loop peppered with a 1ms timer signal --
-- crashed intermittently. With deferred dispatch the C handler only sets a flag
-- and arms a debug hook, and the Lua handler runs at the next VM instruction
-- boundary in normal context, so the same workload must run clean.

local unix = require("cosmo.unix")

-- Basic delivery: a handler installed via sigaction runs, exactly once per
-- signal, and receives the signal number.
do
  local seen = {}
  unix.sigaction(unix.SIGUSR1, function(sig) seen[#seen + 1] = sig end)
  unix.raise(unix.SIGUSR1)
  for i = 1, 1000 do local _ = {i} end  -- give the VM boundaries to run the hook
  unix.raise(unix.SIGUSR1)
  for i = 1, 1000 do local _ = {i} end
  assert(#seen == 2, "expected 2 deliveries, got " .. #seen)
  assert(seen[1] == unix.SIGUSR1 and seen[2] == unix.SIGUSR1,
    "handler should receive the signal number")
  -- restore default so it can't fire during later work
  unix.sigaction(unix.SIGUSR1, unix.SIG_DFL)
end

-- The handler table lives in the Lua registry now, not a global, so scripts
-- can't see or corrupt it.
assert(_G.__signal_handlers == nil,
  "the signal handler table must not be exposed as a global")

-- Stress: 1ms ITIMER_REAL firing SIGALRM into a Lua handler while the main
-- thread churns table allocations (and thus GC) for ~2 seconds.
do
  local fired = 0
  unix.sigaction(unix.SIGALRM, function() fired = fired + 1 end)

  local function now()
    local s, ns = unix.clock_gettime()
    return s + ns / 1e9
  end

  -- 1ms initial + 1ms interval => a SIGALRM roughly every millisecond.
  assert(unix.setitimer(unix.ITIMER_REAL, 0, 1e6, 0, 1e6),
    "setitimer(ITIMER_REAL) should arm")

  local deadline = now() + 2.0
  local sink
  local iters = 0
  while now() < deadline do
    -- allocate churn to keep the collector busy; the hazard the old code hit
    -- was a signal landing mid-allocation / mid-collection.
    for _ = 1, 200 do
      sink = {1, 2, 3, {4, 5, {6, 7, 8}}, "x" .. iters}
    end
    iters = iters + 1
  end
  local _ = sink

  -- disarm the timer, then drop the handler
  unix.setitimer(unix.ITIMER_REAL, 0, 0, 0, 0)
  unix.sigaction(unix.SIGALRM, unix.SIG_DFL)

  -- If we got here we didn't crash. The timer should have fired many times
  -- over ~2s of 1ms ticks; require at least a handful to prove signals were
  -- actually being delivered into Lua throughout the churn.
  assert(iters > 0, "the allocation loop should have run")
  assert(fired >= 10,
    "SIGALRM should have been delivered to the Lua handler repeatedly, got " ..
    fired)
end

print("PASS")
