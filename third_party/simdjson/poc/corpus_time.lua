-- per-case timing of the JSONTestSuite corpus: which cases dominate?
local corpus = {}
local seen = {}
local function capture_decode(json)
  if type(json) == "string" and not seen[json] then
    seen[json] = true
    corpus[#corpus + 1] = json
  end
  return "\0stub"
end
local real_assert = assert
_G.assert = function(v, ...) return v end
package.preload["cosmo"] = function()
  return {
    DecodeJson = capture_decode,
    EncodeJson = function() return "\0stub", "\0stub" end,
    EncodeLua = function() return "\0stub" end,
  }
end
package.preload["cosmo.unix"] = function() return {pledge = function() return true end} end
for _, f in ipairs({"pass", "okay", "fail1", "fail2", "fail3", "fail4"}) do
  local ok, e = pcall(dofile, "tool/lua/test_jsontestsuite_" .. f .. ".lua")
  if not ok then error(e) end
end
_G.assert = real_assert
print("cases:", #corpus)
local function time_one(fn, json, iters)
  local t0 = os.clock()
  for _ = 1, iters do fn(json) end
  return (os.clock() - t0) / iters * 1e9
end
local rows = {}
local tot = {ljson = 0, dom = 0}
for _, json in ipairs(corpus) do
  local a = time_one(cosmo_decode_json, json, 200)
  local b = time_one(simdjson_decode, json, 200)
  tot.ljson = tot.ljson + a; tot.dom = tot.dom + b
  rows[#rows + 1] = {json = json, ljson = a, dom = b}
end
table.sort(rows, function(x, y) return x.dom > y.dom end)
print(string.format("total per-pass: ljson=%.0fus dom=%.0fus  dom-speedup=%.2fx", tot.ljson/1e3, tot.dom/1e3, tot.ljson/tot.dom))
print("top 8 by dom time:")
for i = 1, 8 do
  local r = rows[i]
  print(string.format("  %8.0fns ljson %10.0fns dom  len=%-7d %s", r.ljson, r.dom, #r.json, r.json:sub(1, 40):gsub("\n", " ")))
end
local small_l, small_d, n = 0, 0, 0
for _, r in ipairs(rows) do
  if #r.json <= 1024 then small_l = small_l + r.ljson; small_d = small_d + r.dom; n = n + 1 end
end
print(string.format("cases <=1KB (%d): ljson=%.0fus dom=%.0fus dom-speedup=%.2fx  avg ljson=%.0fns avg dom=%.0fns", n, small_l/1e3, small_d/1e3, small_l/small_d, small_l/n, small_d/n))
