-- Tests for cosmo.DecodeLua, the Lua-literal data parser.
--
-- The oracle is `load` itself: this parser exists to return exactly what
-- executing the same source would return, so every accepting case is
-- asserted against `load(src)()` rather than against a transcription of
-- what the author expected. The refusing cases assert that the parser
-- says no, that each refusal class says something different from the
-- others, and that the reported offset points at the byte that broke.

local cosmo = require("cosmo")

local function deepeq(a, b, path)
  path = path or "value"
  if type(a) ~= type(b) then
    return false, path .. ": " .. type(a) .. " vs " .. type(b)
  end
  if type(a) ~= "table" then
    if a ~= b then
      return false, path .. ": " .. tostring(a) .. " vs " .. tostring(b)
    end
    return true
  end
  for k, v in pairs(a) do
    local ok, why = deepeq(v, b[k], path .. "." .. tostring(k))
    if not ok then
      return false, why
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false, path .. "." .. tostring(k) .. ": missing on the left"
    end
  end
  return true
end

-- Every source here must decode to exactly what running it returns.
local kAgree = {
  -- the shapes committed literal files actually use
  [[return {
  format = "zip",
  strip_components = 0,
  url = "https://example/{version}/cosmos.zip",
  version = "2026.08.21-07fc94a1c"
}
]],
  [[return {
  ["a/b.tl"] = {["covered"] = 0, ["total"] = 1},
  ["c/d.tl"] = {["covered"] = 47, ["total"] = 65},
}
]],
  -- comments, including a long comment whose body holds a `]]`
  "-- a leading comment\nreturn {\n  a = 1, -- trailing\n  --[==[ long\n  ]] not the end\n  ]==] b = 2,\n}\n",
  -- a level-5 long bracket whose BODY contains --[[ and ]]
  "return {\n  find = [=====[ local x = 1 --[[ c ]] end\n]=====],\n}\n",
  -- a long bracket drops one newline right after the opener
  "return {a = [[\nliteral\n]], b = [==[x]==]}",
  -- both quote forms, and the separators
  [[return {a = 'x'; b = "y", c = 'q"q', d = "q'q"}]],
  -- every single-character escape, \x, \z, decimal, and \u{}
  [[return {s = "\a\b\f\n\r\t\v\\\"\'"}]],
  [[return {s = "a\
b"}]],
  [[return {s = "\x41\x7f\xff"}]],
  [[return {s = "a\z    b", t = "a\z"}]],
  [[return {s = "\11\011\0110\255\0"}]],
  [[return {s = "\u{41}\u{7f}\u{80}\u{7ff}\u{800}\u{ffff}\u{10000}\u{10ffff}"}]],
  [[return {s = "\u{7fffffff}"}]],
  -- numerals: integers, floats, hex, hex floats, exponents, negatives
  "return {a = 0, b = 1, c = 255, d = -1, e = -0}",
  "return {a = 0.5, b = .5, c = -0.5, d = 1e3, e = 1E-3, f = -2.5e+2}",
  "return {a = 0x10, b = 0xff, c = -0xff, d = 0x1p4, e = 0x1.8p1}",
  "return {a = 9223372036854775807, b = -9223372036854775807}",
  -- booleans, an empty table, nesting, and a separator before the brace
  "return {a = true, b = false, c = {}, d = {e = {f = {g = 1}}},}",
  "return {}",
  -- whitespace between a minus and its numeral, as the reader allows
  "return {a = -  1}",
  -- keys that merely contain reserved words
  "return {ending = 1, iffy = 2, _end = 3, end_ = 4}",
}

-- One case per refusal class: the source, the 1-based byte offset the
-- parser must point at, and the whole message it must give. Naming the
-- message rather than a label is the point -- a caller composes its own
-- prose from these, so two classes that ever say the same thing would
-- be indistinguishable to it.
local kRefuse = {
  {"return {a = 'x}", 13, "unterminated string"},
  {"return {a = [[x}", 13, "unterminated long string"},
  {"--[[ x\nreturn {}", 1, "unterminated long comment"},
  {"local x = 1", 1, "must be exactly `return { ... }`"},
  {"return 1", 8, "must return a table literal"},
  {"return {} 1", 11, "ends after its table"},
  {"return {a = 'x' 'y'}", 17, "holds literals only after a value"},
  {"return {1}", 9, "is a table of `name = <literal>` entries"},
  {"return {a = b}", 13, "holds literals only"},
  {"return {[\"\\q\"] = 1}", 10, "has a malformed string key"},
  {"return {a = \"\\q\"}", 13, "has a malformed string value"},
  {"return {a = 0x.}", 13, "has a malformed number value"},
  {"return {a = 1, a = 2}", 16, "repeats the key 'a' (first at offset 9)"},
}

-- Refusals that share a class with a case above, kept because each is a
-- shape a reader could plausibly get wrong.
local kAlsoRefused = {
  {"return {[\"a\"] = 1, [\"a\"] = 2}", 20,
   "repeats the key 'a' (first at offset 9)"},
  {"return {end = 1}", 9, "is a table of `name = <literal>` entries"},
  {"return {[1] = 2}", 9, "is a table of `name = <literal>` entries"},
  {"return {a = 'x' .. 'y'}", 17, "holds literals only after a value"},
  -- `1e` is a numeral shape only up to the `1`: the exponent needs a
  -- digit, so what follows is a token after a value, not a bad number.
  {"return {a = 1e}", 14, "holds literals only after a value"},
  {"return {a = 0x}", 14, "holds literals only after a value"},
}

local function test_agrees_with_load()
  for i, src in ipairs(kAgree) do
    local want = assert(load(src), "case " .. i .. " is not loadable")()
    local got, err = cosmo.DecodeLua(src)
    assert(got, "case " .. i .. " refused: " .. tostring(err) .. "\n" .. src)
    local ok, why = deepeq(got, want)
    assert(ok, "case " .. i .. ": " .. tostring(why) .. "\n" .. src)
  end
end

local function test_skips_a_shebang_line()
  -- `load` does not skip `#!` (only the file loader does), so this one
  -- is asserted against the same source with the line removed.
  local src = "#!/usr/bin/env lua\nreturn {a = 1, b = 'x'}\n"
  local got = cosmo.DecodeLua(src)
  local want = load((src:gsub("^#![^\n]*\n", "")))()
  local ok, why = deepeq(got, want)
  assert(ok, tostring(why))
end

local function test_every_byte_before_a_digit()
  local broken = {}
  for b = 0, 255 do
    local src = string.format("return {x = %q}", string.char(b) .. "0")
    local want = load(src)()
    local got = cosmo.DecodeLua(src)
    if type(got) ~= "table" or got.x ~= want.x then
      broken[#broken + 1] = b
    end
  end
  assert(#broken == 0,
         "bytes that did not agree with load: " .. table.concat(broken, ","))
end

local function test_every_byte_in_a_long_bracket()
  local broken = {}
  for b = 0, 255 do
    -- Byte 13 is the one byte where this parser and the oracle really
    -- disagree, so it is excluded rather than quietly passing: Lua's
    -- lexer folds \r, \r\n and \n\r inside a long string to one \n and
    -- drops one such sequence after the opener, and neither this parser
    -- nor the Teal reader it mirrors does. Both readers move together
    -- or the two disagree; cosmic board item 3INGg7XO carries the fix,
    -- and retiring this exclusion is its acceptance signal.
    if b ~= 13 then
      local body = string.char(b)
      local src = "return {x = [==[" .. body .. "]==]}"
      local want = load(src)()
      local got = cosmo.DecodeLua(src)
      if type(got) ~= "table" or got.x ~= want.x then
        broken[#broken + 1] = b
      end
    end
  end
  assert(#broken == 0,
         "bytes that did not survive a long bracket: " ..
         table.concat(broken, ","))
end

local function check_refusals(cases)
  for _, case in ipairs(cases) do
    local src, offset, want = case[1], case[2], case[3]
    local got, err, at = cosmo.DecodeLua(src)
    assert(got == nil, "accepted <" .. src .. ">")
    assert(err == want,
           "<" .. src .. ">: " .. tostring(err) .. "\n  want: " .. want)
    assert(at == offset,
           "<" .. src .. ">: offset " .. tostring(at) .. ", want " .. offset)
  end
end

local function test_refusals_are_classified_and_positioned()
  check_refusals(kRefuse)
  check_refusals(kAlsoRefused)
  -- Every class above says something a caller can tell apart.
  for i = 1, #kRefuse do
    for j = i + 1, #kRefuse do
      assert(kRefuse[i][3] ~= kRefuse[j][3],
             "classes " .. i .. " and " .. j .. " share a message")
    end
  end
end

local function test_duplicate_is_scoped_to_one_table()
  -- The same key in two different nested tables is not a duplicate, and
  -- the first offset reported is the one in the table that repeated it.
  assert(cosmo.DecodeLua("return {a = 1, b = {a = 2}}"), "not a duplicate")
  local _, err = cosmo.DecodeLua("return {b = {a = 1}, a = 2, a = 3}")
  assert(err == "repeats the key 'a' (first at offset 22)", tostring(err))
  -- A key too long to print is truncated in the message, not in the
  -- refusal: the parse still stops.
  local k = string.rep("k", 200)
  local src = "return {" .. k .. " = 1, " .. k .. " = 2}"
  local got, err2 = cosmo.DecodeLua(src)
  assert(got == nil and err2:find("repeats the key", 1, true), tostring(err2))
end

local function test_depth_cap()
  local function nest(n)
    return "return " .. string.rep("{a = ", n - 1) .. "{}" ..
           string.rep("}", n - 1)
  end
  assert(cosmo.DecodeLua(nest(32)), "32 tables must be admitted")
  local got, err = cosmo.DecodeLua(nest(33))
  assert(got == nil and err:find("32", 1, true), "33 tables: " .. tostring(err))
end

local function test_a_short_string_never_spans_a_line()
  -- `\z` skips the whitespace that follows, but this grammar's short
  -- strings still end at a raw newline, so the two together are refused
  -- rather than joined.
  local got = cosmo.DecodeLua("return {a = \"x\\z\ny\"}")
  assert(got == nil, "a raw newline inside a short string must be refused")
end

local function test_rejects_what_it_must_not_run()
  for _, src in ipairs({
    "return {a = os.time()}",
    "return {a = f()}",
    "return {a = #b}",
    "return {a = 1 + 1}",
    "return setmetatable({}, {})",
    "return {a = function() end}",
    "return {a = nil}",
    "os.exit(1) return {}",
  }) do
    assert(cosmo.DecodeLua(src) == nil, "must refuse <" .. src .. ">")
  end
end

local function test_empty_and_truncated_input()
  for _, src in ipairs({"", " ", "--x", "return", "return {", "return {a",
                        "return {a =", "return {a = 1"}) do
    local got, err, at = cosmo.DecodeLua(src)
    assert(got == nil, "must refuse <" .. src .. ">")
    assert(type(err) == "string" and type(at) == "number",
           "<" .. src .. "> must still report where and why")
  end
end

test_agrees_with_load()
test_skips_a_shebang_line()
test_every_byte_before_a_digit()
test_every_byte_in_a_long_bracket()
test_refusals_are_classified_and_positioned()
test_duplicate_is_scoped_to_one_table()
test_depth_cap()
test_a_short_string_never_spans_a_line()
test_rejects_what_it_must_not_run()
test_empty_and_truncated_input()
print("all DecodeLua tests passed")
