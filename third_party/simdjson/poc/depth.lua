-- verifies the fast variant survives deep nesting without a crash and
-- agrees with ljson.c on the depth cap
for _, depth in ipairs({15, 16, 17, 19, 21, 30, 63, 64, 65, 100, 500, 5000}) do
  local json = string.rep("[", depth) .. string.rep("]", depth)
  local r1, e1 = cosmo_decode_json(json)
  local r2, e2 = simdjson_decode_fast(json)
  local r3, e3 = simdjson_decode_fast_mt(json)
  print(string.format("depth %5d ljson=%-5s fast=%-5s fast_mt=%-5s  %s | %s",
    depth, tostring(r1 ~= nil), tostring(r2 ~= nil), tostring(r3 ~= nil),
    tostring(e1), tostring(e2)))
end
-- fast variants agree with ljson on a real document
local doc = '{"a":[1,2.5,"x",true,null,{"b":[]}],"c":{"d":"\\u00e9\\n"}}'
local function dump(v)
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys+1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out+1] = tostring(k) .. "=" .. dump(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end
assert(dump(cosmo_decode_json(doc)) == dump(simdjson_decode_fast(doc)), "mismatch")
local mt = getmetatable(simdjson_decode_fast_mt("[1]"))
assert(mt ~= nil and mt == getmetatable(cosmo_decode_json("[1]")), "array mt")
print("DEPTH+SHAPE OK")
