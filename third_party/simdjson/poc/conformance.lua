-- POC only: reuses this repo's own tool/lua/test_jsontestsuite_*.lua
-- corpus (Nicolas Seriot's JSONTestSuite, already vetted against
-- ljson.c) to check whether simdjson_decode()/simdjson_decode_ondemand()
-- agree with cosmo_decode_json() (the real, unmodified tool/net/ljson.c
-- parser) on accept/reject for every JSON literal those test files
-- exercise -- and times all three decoders on that same, non-synthetic
-- corpus.
--
-- Harvests the corpus by stubbing cosmo.DecodeJson/EncodeJson/EncodeLua
-- and cosmo.unix.pledge, neutering assert (so a stub return value that
-- fails one of the file's own fine-grained assertions doesn't abort the
-- file before its later cases run -- we only want the JSON literals,
-- not the exact shape each assertion checks), and dofile-ing the real
-- test files unmodified. The stub is never treated as a source of
-- truth for accept/reject: that comes from actually calling the real
-- cosmo_decode_json() on each harvested literal, below.

local corpus = {}
local current_file

local function capture_decode(json)
  corpus[#corpus + 1] = {file = current_file, json = json}
  return "\0stub"  -- a plain string: indexing, #, ==, and concat on it
                   -- are all safe no-ops, so the rest of the file's
                   -- (now-neutered) assertions can't crash mid-expression
end

_G.assert = function(v, ...) return v end
package.preload["cosmo"] = function()
  return {
    DecodeJson = capture_decode,
    EncodeJson = function() return "\0stub", "\0stub" end,
    EncodeLua = function() return "\0stub" end,
  }
end
package.preload["cosmo.unix"] = function()
  return {pledge = function() return true end}
end

local FILES = {
  "tool/lua/test_jsontestsuite_pass.lua",
  "tool/lua/test_jsontestsuite_okay.lua",
  "tool/lua/test_jsontestsuite_fail1.lua",
  "tool/lua/test_jsontestsuite_fail2.lua",
  "tool/lua/test_jsontestsuite_fail3.lua",
  "tool/lua/test_jsontestsuite_fail4.lua",
}

for _, f in ipairs(FILES) do
  current_file = f
  local ok, harvest_err = pcall(dofile, f)
  if not ok then
    error("harvesting " .. f .. " failed: " .. tostring(harvest_err))
  end
end

print(string.format("harvested %d DecodeJson literals from %d files",
  #corpus, #FILES))

-- a decode "succeeded" iff its error slot is nil -- NOT iff its value
-- is non-nil: a bare top-level `null` document decodes to (nil, nil),
-- which is success, not failure. See tool/lua/test_jsontestsuite_pass.lua's
-- very first case.
local function decode_ok(fn, json)
  local _, err = fn(json)
  return err == nil
end

-- tool/lua/test_jsontestsuite_okay.lua is JSONTestSuite's "i_" bucket:
-- inputs the spec leaves implementation-defined (lone UTF-16 surrogates
-- in \u escapes, numbers that overflow to Infinity, a leading BOM).
-- ljson.c's own choice on these isn't "the right answer" simdjson must
-- match -- disagreeing there is informational, not a bug. Disagreeing
-- on tool/lua/test_jsontestsuite_{pass,fail1..4}.lua is a real bug:
-- those files encode JSON's actual grammar (RFC 8259's y_/n_ cases),
-- and ljson.c already passes them.
local function is_strict(file)
  return file ~= "tool/lua/test_jsontestsuite_okay.lua"
end

local strict_mismatches_dom, strict_mismatches_ondemand = 0, 0
local info_mismatches_dom, info_mismatches_ondemand = 0, 0
for idx, case in ipairs(corpus) do
  if os.getenv("SIMDJSON_CONFORMANCE_DEBUG") then
    io.stderr:write(string.format("[%d/%d] %s: %q\n", idx, #corpus, case.file, case.json))
    io.stderr:flush()
  end
  local ljson_ok = decode_ok(cosmo_decode_json, case.json)
  local dom_ok = decode_ok(simdjson_decode, case.json)
  local ondemand_ok = decode_ok(simdjson_decode_ondemand, case.json)
  local strict = is_strict(case.file)
  if dom_ok ~= ljson_ok then
    if strict then strict_mismatches_dom = strict_mismatches_dom + 1
    else info_mismatches_dom = info_mismatches_dom + 1 end
    print(string.format("DOM %s [%s]: ljson_ok=%s dom_ok=%s json=%q",
      strict and "BUG" or "info", case.file, tostring(ljson_ok), tostring(dom_ok), case.json))
  end
  if ondemand_ok ~= ljson_ok then
    if strict then strict_mismatches_ondemand = strict_mismatches_ondemand + 1
    else info_mismatches_ondemand = info_mismatches_ondemand + 1 end
    print(string.format("ONDEMAND %s [%s]: ljson_ok=%s ondemand_ok=%s json=%q",
      strict and "BUG" or "info", case.file, tostring(ljson_ok), tostring(ondemand_ok), case.json))
  end
end

print(string.format(
  "DOM: %d strict bugs, %d implementation-defined disagreements (of %d cases)",
  strict_mismatches_dom, info_mismatches_dom, #corpus))
print(string.format(
  "on_demand: %d strict bugs, %d implementation-defined disagreements (of %d cases)",
  strict_mismatches_ondemand, info_mismatches_ondemand, #corpus))

-- perf, on this same non-synthetic corpus rather than bench.lua's
-- synthetic payloads
local function bench_corpus(fn, iterations)
  for _ = 1, 3 do
    for _, case in ipairs(corpus) do fn(case.json) end
  end
  local t0 = os.clock()
  for _ = 1, iterations do
    for _, case in ipairs(corpus) do fn(case.json) end
  end
  return os.clock() - t0
end

local ITER = 20
local t_dom = bench_corpus(simdjson_decode, ITER)
local t_ondemand = bench_corpus(simdjson_decode_ondemand, ITER)
local t_ljson = bench_corpus(cosmo_decode_json, ITER)

print(string.format(
  "corpus timing (%d cases x %d iterations): dom=%.4fs ondemand=%.4fs " ..
  "ljson=%.4fs  dom-speedup=%.2fx ondemand-speedup=%.2fx",
  #corpus, ITER, t_dom, t_ondemand, t_ljson,
  t_ljson / t_dom, t_ljson / t_ondemand))

if strict_mismatches_dom > 0 or strict_mismatches_ondemand > 0 then
  os.exit(1)
end
print("CONFORMANCE OK (no strict bugs; implementation-defined disagreements are expected -- see output above)")
