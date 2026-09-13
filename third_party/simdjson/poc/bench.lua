-- POC only: times three JSON decoders on identical payloads, in the
-- same process --
--   simdjson_decode()          this spike's DOM-based simdjson wrapper
--   simdjson_decode_ondemand() its on_demand-API sibling (single pass,
--                              no separate DOM tape to build+walk)
--   cosmo_decode_json()        this tree's real, unmodified
--                              tool/net/ljson.c parser, the one
--                              cosmo.DecodeJson calls
-- Rough and reasonable, not this repo's real perf harness (that's
-- cosmic's _perf, which this repo doesn't have and none of these are
-- wired into cosmo.* yet anyway) -- os.clock() process-CPU-time, a
-- handful of payload shapes, warmup + repeated timed loops.

local function make_flat_array(n)
  local parts = {"["}
  for i = 1, n do
    if i > 1 then parts[#parts + 1] = "," end
    parts[#parts + 1] = tostring(i * 3 + 0.5)
  end
  parts[#parts + 1] = "]"
  return table.concat(parts)
end

local function make_object_array(n)
  local parts = {"["}
  for i = 1, n do
    if i > 1 then parts[#parts + 1] = "," end
    parts[#parts + 1] = string.format(
      '{"id":%d,"name":"item-%d","active":%s,"score":%f,"tags":["a","b","c"]}',
      i, i, (i % 2 == 0) and "true" or "false", i * 1.5)
  end
  parts[#parts + 1] = "]"
  return table.concat(parts)
end

local payloads = {
  {name = "tiny object",       json = '{"id":1,"name":"a","active":true}'},
  {name = "flat array (1k)",   json = make_flat_array(1000)},
  {name = "flat array (50k)",  json = make_flat_array(50000)},
  {name = "object array (200)",   json = make_object_array(200)},
  {name = "object array (10000)", json = make_object_array(10000)},
}

local function bench(fn, json, iterations)
  local ok, err = fn(json)
  assert(ok ~= nil, "decode failed: " .. tostring(err))
  -- warmup
  for _ = 1, math.max(3, iterations // 20) do fn(json) end
  local t0 = os.clock()
  for _ = 1, iterations do fn(json) end
  return os.clock() - t0
end

print(string.format("%-20s %10s %10s %10s %10s %9s %9s",
  "payload", "bytes", "dom(s)", "ondmd(s)", "ljson(s)", "dom-spdup", "od-spdup"))
print(string.rep("-", 82))

for _, p in ipairs(payloads) do
  local bytes = #p.json
  -- scale iteration count so each payload runs for a reasonable slice
  -- of wall time regardless of size
  local iterations = math.max(3, math.min(2000, math.floor(20000000 / bytes)))

  local t_dom = bench(simdjson_decode, p.json, iterations)
  local t_ondemand = bench(simdjson_decode_ondemand, p.json, iterations)
  local t_ljson = bench(cosmo_decode_json, p.json, iterations)

  print(string.format("%-20s %10d %10.4f %10.4f %10.4f %8.2fx %8.2fx",
    p.name, bytes, t_dom, t_ondemand, t_ljson,
    t_ljson / t_dom, t_ljson / t_ondemand))
end
