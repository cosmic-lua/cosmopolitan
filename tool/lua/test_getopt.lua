local getopt = require("cosmo.getopt")

assert(getopt, "getopt module should exist")
assert(type(getopt.parse) == "function", "getopt.parse should be a function")
assert(getopt.new == nil, "the stateful getopt.new parser should be gone")

-- Collapse r.opts (a list of {opt, arg}) into a name->value map for terse
-- assertions. Repeated options keep only their last value here.
local function tomap(r)
  local m = {}
  for _, o in ipairs(r.opts) do
    m[o.opt] = o.arg or true
  end
  return m
end

-- Short options only
local r = getopt.parse({"-h", "-v", "-o", "out.txt", "file.txt"}, "hvo:")
local m = tomap(r)
assert(m.h == true, "opts.h should be true")
assert(m.v == true, "opts.v should be true")
assert(m.o == "out.txt", "opts.o should be 'out.txt'")
assert(#r.args == 1 and r.args[1] == "file.txt", "one remaining arg 'file.txt'")
assert(#r.unknown == 0, "no unknown options")
assert(#r.missing == 0, "no missing arguments")

-- Long options (long with a short equivalent reports the short letter)
r = getopt.parse({"--help", "--output=foo.txt", "input.txt"}, "ho:", {
  {"help", "none", "h"},
  {"output", "required", "o"},
})
m = tomap(r)
assert(m.h == true, "long --help maps to short 'h'")
assert(m.o == "foo.txt", "long --output=foo.txt maps to short 'o'")
assert(r.args[1] == "input.txt", "remaining arg 'input.txt'")
assert(#r.unknown == 0 and #r.missing == 0)

-- Long option with a separate argument
r = getopt.parse({"--output", "bar.txt"}, "o:", {{"output", "required", "o"}})
assert(tomap(r).o == "bar.txt", "long --output bar.txt")

-- Long-only option (no short equivalent) is reported by its long name
r = getopt.parse({"--verbose"}, "", {{"verbose", "none"}})
assert(tomap(r).verbose == true, "long-only option keeps its name")

-- Combined short options
r = getopt.parse({"-hv", "file.txt"}, "hv")
m = tomap(r)
assert(m.h == true and m.v == true, "combined -hv")
assert(r.args[1] == "file.txt")

-- "--" terminator
r = getopt.parse({"-h", "--", "-v", "file.txt"}, "hv")
m = tomap(r)
assert(m.h == true, "opts.h before -- parsed")
assert(m.v == nil, "-v after -- is not an option")
assert(r.args[1] == "-v" and r.args[2] == "file.txt", "args after -- preserved")

-- Empty args
r = getopt.parse({}, "hv")
assert(#r.opts == 0 and #r.args == 0 and #r.unknown == 0 and #r.missing == 0)

-- No longopts argument
r = getopt.parse({"-h"}, "h")
assert(tomap(r).h == true, "short parse without longopts arg")

-- Unknown short option: recorded with its dash, absent from opts
r = getopt.parse({"-h", "-x", "-v"}, "hv")
m = tomap(r)
assert(m.h == true and m.v == true)
assert(m.x == nil, "unknown -x is not a recognized option")
assert(#r.unknown == 1 and r.unknown[1] == "-x", "unknown carries its dash")
assert(#r.missing == 0)

-- Unknown long option keeps its dashes
r = getopt.parse({"--help", "--foo", "--verbose"}, "hv", {
  {"help", "none", "h"},
  {"verbose", "none", "v"},
})
m = tomap(r)
assert(m.h == true and m.v == true)
assert(#r.unknown == 1 and r.unknown[1] == "--foo", "unknown long keeps '--'")

-- Multiple unknown options
r = getopt.parse({"-x", "-y", "-z"}, "h")
assert(#r.unknown == 3, "three unknown options")
assert(r.unknown[1] == "-x" and r.unknown[2] == "-y" and r.unknown[3] == "-z")

-- Repeated short options preserve order and every value
r = getopt.parse({"-e", "foo", "-e", "bar", "-e", "spam"}, "e:")
local e = {}
for _, o in ipairs(r.opts) do
  if o.opt == "e" then e[#e + 1] = o.arg end
end
assert(#e == 3 and e[1] == "foo" and e[2] == "bar" and e[3] == "spam")

-- Repeated long options
r = getopt.parse({"--include", "a.h", "--include", "b.h"}, "I:", {
  {"include", "required", "I"},
})
local inc = {}
for _, o in ipairs(r.opts) do
  if o.opt == "I" then inc[#inc + 1] = o.arg end
end
assert(#inc == 2 and inc[1] == "a.h" and inc[2] == "b.h")

-- ===== TDD cases from whilp/cosmopolitan#149 item 1 =====

-- (a) The old parser stored the raw optstring pointer for its lifetime without
-- rooting the Lua string; a dynamically built optstring could be collected out
-- from under it, turning "-x val" into an unknown option. Build the optstring
-- via table.concat, hammer the collector, and require a clean parse.
do
  local optstring = table.concat({"x", ":"})  -- "x:", freshly allocated
  collectgarbage()
  collectgarbage()
  local res = getopt.parse({"-x", "val"}, optstring)
  assert(#res.opts == 1, "exactly one option parsed")
  assert(res.opts[1].opt == "x" and res.opts[1].arg == "val",
    "GC of the optstring must not corrupt the parse: expected x=val")
  assert(#res.unknown == 0, "no spurious unknown option")
end

-- (b) The old design shared global optind/opterr across parsers, so two of them
-- corrupted each other. parse() is single-shot; interleaving two argument
-- vectors must produce independent, repeatable results.
do
  local A = {"-a", "1", "-b", "posA"}
  local B = {"-c", "-d", "posB"}
  local a1 = getopt.parse(A, "a:b")
  local b1 = getopt.parse(B, "cd")
  local a2 = getopt.parse(A, "a:b")  -- re-run A after B ran in between
  assert(tomap(a1).a == "1" and tomap(a1).b == true)
  assert(a1.args[1] == "posA")
  assert(tomap(b1).c == true and tomap(b1).d == true)
  assert(b1.args[1] == "posB")
  -- A parsed identically before and after B: no shared-state bleed.
  assert(tomap(a2).a == "1" and tomap(a2).b == true and a2.args[1] == "posA",
    "a re-parse must be independent of the intervening B parse")
end

-- (c) A required argument that is absent belongs in `missing`, not `unknown`.
do
  local res = getopt.parse({"-o"}, "o:")
  assert(#res.missing == 1 and res.missing[1] == "o",
    "'-o' with no argument goes to missing as 'o'")
  assert(#res.unknown == 0, "a missing argument is not an unknown option")
  assert(#res.opts == 0, "the incomplete option is not reported as parsed")
end

-- Malformed input returns nil + error rather than throwing
do
  local res, err = getopt.parse("not a table", "h")
  assert(res == nil and type(err) == "string", "bad args -> nil, err")
  res, err = getopt.parse({1, 2}, "h")
  assert(res == nil and type(err) == "string", "non-string args -> nil, err")
  res, err = getopt.parse({"-h"}, "h", {{"bad", "sometimes"}})
  assert(res == nil and type(err) == "string", "bad has_arg -> nil, err")
end

print("PASS")
