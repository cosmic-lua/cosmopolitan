-- Size-sweep bench: where is the crossover between simdjson and ljson.c,
-- and how much do the wrapper-level changes in lsimdjson_fast.cc buy?
-- Reports the best of 5 timed rounds per cell (min, not mean, to shed
-- noise) as ns per decode and as ljson/x speedup.
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
local function make_flat_array(n)
  local parts = {"["}
  for i = 1, n do
    if i > 1 then parts[#parts + 1] = "," end
    parts[#parts + 1] = tostring(i * 3 + 0.5)
  end
  parts[#parts + 1] = "]"
  return table.concat(parts)
end
local function make_int_array(n)
  local parts = {"["}
  for i = 1, n do
    if i > 1 then parts[#parts + 1] = "," end
    parts[#parts + 1] = tostring(i * 7)
  end
  parts[#parts + 1] = "]"
  return table.concat(parts)
end
local function make_string_array(n)
  local parts = {"["}
  for i = 1, n do
    if i > 1 then parts[#parts + 1] = "," end
    parts[#parts + 1] = string.format('"the quick brown fox %d jumps"', i)
  end
  parts[#parts + 1] = "]"
  return table.concat(parts)
end

local payloads = {
  {name = "scalar true", json = "true"},
  {name = "tiny obj", json = '{"id":1,"name":"a","active":true}'},
  {name = "objarr 1", json = make_object_array(1)},
  {name = "objarr 2", json = make_object_array(2)},
  {name = "objarr 4", json = make_object_array(4)},
  {name = "objarr 8", json = make_object_array(8)},
  {name = "objarr 16", json = make_object_array(16)},
  {name = "objarr 64", json = make_object_array(64)},
  {name = "objarr 200", json = make_object_array(200)},
  {name = "objarr 10000", json = make_object_array(10000)},
  {name = "intarr 8", json = make_int_array(8)},
  {name = "intarr 64", json = make_int_array(64)},
  {name = "intarr 1k", json = make_int_array(1000)},
  {name = "intarr 50k", json = make_int_array(50000)},
  {name = "fltarr 1k", json = make_flat_array(1000)},
  {name = "fltarr 50k", json = make_flat_array(50000)},
  {name = "strarr 1k", json = make_string_array(1000)},
  {name = "strarr 50k", json = make_string_array(50000)},
}

local decoders = {
  {"ljson", cosmo_decode_json},
  {"dom", simdjson_decode},
  {"fast", simdjson_decode_fast},
  {"fast_mt", simdjson_decode_fast_mt},
}

local function bench(fn, json)
  local ok, err = fn(json)
  assert(ok ~= nil, "decode failed: " .. tostring(err))
  local iterations = math.max(5, math.min(20000, math.floor(4000000 / #json)))
  for _ = 1, math.max(3, iterations // 10) do fn(json) end
  local best = math.huge
  for _ = 1, 5 do
    collectgarbage("collect")
    local t0 = os.clock()
    for _ = 1, iterations do fn(json) end
    local dt = os.clock() - t0
    if dt < best then best = dt end
  end
  return best / iterations * 1e9
end

io.write(string.format("%-13s %8s", "payload", "bytes"))
for _, d in ipairs(decoders) do io.write(string.format(" %10s", d[1] .. " ns")) end
for i = 2, #decoders do io.write(string.format(" %8s", decoders[i][1] .. " x")) end
print()
for _, p in ipairs(payloads) do
  local ns = {}
  for i, d in ipairs(decoders) do ns[i] = bench(d[2], p.json) end
  io.write(string.format("%-13s %8d", p.name, #p.json))
  for i = 1, #decoders do io.write(string.format(" %10.0f", ns[i])) end
  for i = 2, #decoders do io.write(string.format(" %7.2fx", ns[1] / ns[i])) end
  print()
end
