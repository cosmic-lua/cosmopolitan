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

-- Explicit trailing nils must not shift the stack slot the binding
-- reads the Lua handler from: sigaction(sig, fn, nil, nil) has to
-- register and dispatch fn exactly like sigaction(sig, fn) does.
-- Before the fix the nil-valued slots lingered, the registry recorded
-- nil, and the handler never ran (cosmic carried a four-branch call
-- ladder to avoid ever passing them).
do
  local fired = false
  assert(unix.sigaction(unix.SIGUSR2, function() fired = true end, nil, nil))
  assert(unix.raise(unix.SIGUSR2))
  for _ = 1, 1000 do
    if fired then break end
  end
  assert(fired, "a handler passed with explicit trailing nils must dispatch")
  unix.sigaction(unix.SIGUSR2, unix.SIG_DFL)
end

-- unix.sigset is unix.Sigset under a constructor-shaped name; both
-- build the same object, so either may be passed as a mask.
do
  local lower = unix.sigset(unix.SIGUSR1)
  assert(lower:contains(unix.SIGUSR1), "sigset() builds a populated set")
  assert(not lower:contains(unix.SIGUSR2), "and only what was asked for")
  local old = assert(unix.sigprocmask(unix.SIG_BLOCK, lower))
  assert(unix.sigprocmask(unix.SIG_SETMASK, old))
end

-- An uninterrupted nanosleep reports a zero remainder rather than
-- whatever the kernel left in its buffer (POSIX leaves it unspecified
-- on success), so a caller can trust the value without a clock read.
-- The remainder comes back as one table, not two positional integers,
-- so nothing here can be confused with the failure path's error/errno.
do
  local remaining = unix.nanosleep(0, 1000000)
  assert(type(remaining) == "table",
    "a completed sleep returns a remainder table, got " .. type(remaining))
  assert(remaining.seconds == 0 and remaining.nanos == 0,
    "a completed sleep has no remainder, got " .. tostring(remaining.seconds) ..
    "," .. tostring(remaining.nanos))
end

-- An EINTR-interrupted nanosleep must return a tuple where no slot
-- serves two purposes across the success and failure branches: slot 1
-- is nil (never the remainder table success uses), slots 2/3 are
-- always error/errno, and slot 4 -- present only here -- carries the
-- kernel's leftover time as its own table.
do
  local pid = unix.fork()
  if pid == 0 then
    unix.sigaction(unix.SIGALRM, function() end)
    -- one-shot alarm ~50ms out, well inside the 5s sleep below
    assert(unix.setitimer(unix.ITIMER_REAL, 0, 0, 0, 50e6))
    local remaining, err, eno, eintr_remaining = unix.nanosleep(5, 0)
    assert(remaining == nil,
      "an interrupted sleep must not return a remainder in slot 1")
    assert(type(err) == "string", "slot 2 must be the error string")
    assert(eno == unix.EINTR, "slot 3 must be EINTR, got " .. tostring(eno))
    assert(type(eintr_remaining) == "table",
      "slot 4 must be the EINTR remainder table, got " .. type(eintr_remaining))
    assert(type(eintr_remaining.seconds) == "number" and
      type(eintr_remaining.nanos) == "number",
      "the EINTR remainder table must carry numeric seconds/nanos")
    assert(eintr_remaining.seconds >= 0 and eintr_remaining.seconds <= 5,
      "the remaining seconds must be within the requested sleep")
    unix.sigaction(unix.SIGALRM, unix.SIG_DFL)
    unix.exit(0)
  else
    local _, wstatus = unix.wait(pid)
    assert(unix.WIFEXITED(wstatus) and unix.WEXITSTATUS(wstatus) == 0,
      "the EINTR nanosleep child must exit cleanly")
  end
end

-- sigpending takes no argument and has no reachable failure on any
-- platform this project supports (EFAULT needs a pointer this
-- binding never constructs); it must always return a plain Sigset.
assert(unix.sigpending() ~= nil, "sigpending must always succeed")

-- raise()'s only documented failure is an invalid signal number
-- (EINVAL); sig == 0 is a legitimate existence-check call (like
-- kill(pid, 0)) and must not raise.
assert(not pcall(unix.raise, 999),
  "raise of an invalid signal number must raise")
assert(unix.raise(0) == 0, "raise(0) is a valid existence check")

-- sigprocmask's only reachable failure is an invalid `how`;
-- EFAULT needs a pointer this binding never constructs from Lua.
assert(not pcall(unix.sigprocmask, 999, unix.sigset()),
  "sigprocmask of an invalid how must raise")

print("PASS")
