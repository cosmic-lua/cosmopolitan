-- isolates the wrapper-level changes and measures the parse-only floor
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
local function make_string_array(n)
  local parts = {"["}
  for i = 1, n do
    if i > 1 then parts[#parts + 1] = "," end
    parts[#parts + 1] = string.format('"the quick brown fox %d jumps"', i)
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
local payloads = {
  {name = "tiny obj", json = '{"id":1,"name":"a","active":true}'},
  {name = "objarr 8", json = make_object_array(8)},
  {name = "objarr 200", json = make_object_array(200)},
  {name = "objarr 10000", json = make_object_array(10000)},
  {name = "strarr 50k", json = make_string_array(50000)},
  {name = "fltarr 50k", json = make_flat_array(50000)},
}
local decoders = {
  {"ljson", cosmo_decode_json},
  {"dom", simdjson_decode},
  {"direct", sj_direct},
  {"pad+raw+chk", sj_padded_raw_chk},
  {"unpad+raw", sj_unpadded_raw_nochk},
  {"parseonly", sj_parse_only},
  {"parseonly-unpad", sj_parse_only_unpadded},
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
for _, d in ipairs(decoders) do io.write(string.format(" %16s", d[1])) end
print()
for _, p in ipairs(payloads) do
  io.write(string.format("%-13s %8d", p.name, #p.json))
  for _, d in ipairs(decoders) do io.write(string.format(" %13.0fns", bench(d[2], p.json))) end
  print()
end
