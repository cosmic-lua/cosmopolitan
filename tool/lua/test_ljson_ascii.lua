local cosmo = require("cosmo")
local DecodeJson = cosmo.DecodeJson
local corpus = assert(loadfile("tool/lua/testdata/json_ascii_corpus.lua"))()
local NULL = {}
local ARRAY_MT = getmetatable(assert(DecodeJson("[]")))

local function hex(s)
  return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

local function options(context)
  if context == "null" then return {nullval = NULL} end
end

-- This is a value serializer, not an encoder oracle. It records every Lua
-- return slot, including nil, and every decoded table entry.
local function fingerprint(value, seen)
  local kind = type(value)
  if value == NULL then return "null-sentinel" end
  if kind == "nil" then return "nil" end
  if kind == "boolean" then return value and "bool:true" or "bool:false" end
  if kind == "number" then
    local number_kind = math.type and math.type(value) or "number"
    return number_kind .. ":" .. string.format("%.17g", value)
  end
  if kind == "string" then return "string:" .. hex(value) end
  if kind ~= "table" then return kind .. ":" .. tostring(value) end
  seen = seen or {}
  assert(not seen[value], "JSON decode produced a cyclic table")
  seen[value] = true
  local entries = {}
  for key, item in pairs(value) do
    entries[#entries + 1] = fingerprint(key, seen) .. "=" .. fingerprint(item, seen)
  end
  table.sort(entries)
  seen[value] = nil
  return (getmetatable(value) == ARRAY_MT and "array" or "object") ..
         "{" .. table.concat(entries, ",") .. "}"
end

local function record(input, context)
  local results = table.pack(DecodeJson(input, options(context)))
  local fields = {"input:" .. hex(input), "context:" .. context,
                  "arity:" .. results.n}
  for i = 1, results.n do fields[#fields + 1] = fingerprint(results[i]) end
  return table.concat(fields, ";")
end

if arg[1] == "--emit" then
  for id, input, context in corpus.each() do
    io.write(id, "\t", record(input, context), "\n")
  end
  return
end

local function packed(input, context)
  return table.pack(DecodeJson(input, options(context)))
end

local function succeeds(input, value, context)
  local result = packed(input, context)
  assert(result.n == 1 and result[1] == value, input)
end

local function fails(input, message, context)
  local result = packed(input, context)
  assert(result.n == 2 and result[1] == nil and result[2] == message,
         input .. ": " .. tostring(result[2]))
end

local allowed = {}
for byte = 0x20, 0x7f do
  if byte ~= 0x22 and byte ~= 0x5c then allowed[#allowed + 1] = string.char(byte) end
end
local all_ascii = table.concat(allowed)
succeeds('"' .. all_ascii .. '"', all_ascii)
for _, n in ipairs({0, 1, 2, 7, 8, 15, 16, 31, 32, 63, 64, 1023, 1024, 1025,
                    65536}) do
  local content = all_ascii:rep(math.ceil(n / #all_ascii)):sub(1, n)
  succeeds('"' .. content .. '"', content)
end

succeeds('"\\\"\\\\\\/\\b\\f\\n\\r\\t\\u0041\\x41"',
          '"\\/' .. string.char(8, 12, 10, 13, 9) .. "AA")
succeeds('"\\u0000"', "\0")
succeeds('"\194\128\226\130\172\240\159\152\128"',
          "\194\128\226\130\172\240\159\152\128")
succeeds('"\\ud800"', "\\ud800")
succeeds('"\\ud800\\udf30"', "𐌰")
fails('"\0"', "non-del c0 control code in string")
fails('"\128"', "c1 control code in string")
fails('"\\x00"', "hex escape not printable")
fails('"\\xcj"', "invalid hex escape")
fails('"\\ucjcc"', "invalid unicode escape")
fails('"\192\128"', "overlong ascii")
fails('"\240\128\128\128"', "overlong utf-8 0..0xffff")
fails('"\226\40\161"', "malformed utf-8")
fails('"\237\160\128"', "utf-16 surrogate in utf-8")
fails('"\237\174\128\237\176\128"', "illegal utf-8 character")
fails('"abc', "unexpected eof in string")
fails('"abc\\', "unexpected eof in string")
fails('"\\u12', "invalid unicode escape")
fails('"\194', "malformed utf-8")
fails('"x"z', "junk after expression")
succeeds('"x" \t\r\n ', "x")
for _, n in ipairs({0, 1, 15, 16, 1023, 1024, 1025}) do
  fails('"' .. string.rep("a", n), "unexpected eof in string")
end

local array = assert(DecodeJson('["x"]'))
assert(getmetatable(array) == ARRAY_MT and array[1] == "x")
local object = assert(DecodeJson('{"x":"y","x":"z"}'))
assert(object.x == "z")
local key = assert(DecodeJson('{"x":1}'))
assert(key.x == 1)
local with_null = assert(DecodeJson('["x",null]', {nullval = NULL}))
assert(with_null[1] == "x" and with_null[2] == NULL)
fails('["x",]', "unexpected ']'")
fails('{"x" "y"}', "missing ':'")
fails('{"x":"y",}', "unexpected '}'")
for _ = 1, 3 do
  succeeds('"after failure"', "after failure")
  fails('"unterminated', "unexpected eof in string")
end
do
  local input = '"collect me"'
  local value = assert(DecodeJson(input))
  input = nil
  collectgarbage("collect")
  assert(value == "collect me")
end

local count = 0
for id, input, context in corpus.each() do
  assert(id and context and #input <= 65538)
  count = count + 1
end
assert(count == corpus.count)
collectgarbage("collect")
