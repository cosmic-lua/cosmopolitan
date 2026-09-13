-- POC only: exercises simdjson_decode(), the Lua-callable wrapper
-- lsimdjson.cc registers around simdjson's DOM parser.
local doc, err = simdjson_decode([[
{
  "name": "cosmic-lua",
  "stars": 4,
  "fork": true,
  "homepage": null,
  "tags": ["lua", "teal", "cosmopolitan"],
  "meta": {"simd": true}
}
]])

assert(doc, err)
assert(doc.name == "cosmic-lua")
assert(doc.stars == 4)
assert(doc.fork == true)
assert(doc.homepage == nil)
assert(#doc.tags == 3 and doc.tags[1] == "lua" and doc.tags[3] == "cosmopolitan")
assert(doc.meta.simd == true)

print("name = " .. doc.name)
print("tags = " .. table.concat(doc.tags, ", "))
print("meta.simd = " .. tostring(doc.meta.simd))

local bad, parse_err = simdjson_decode("{not json")
assert(bad == nil and type(parse_err) == "string")
print("error path ok: " .. parse_err)

print("ALL OK")
