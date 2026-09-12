-- Deterministic inputs for the ljson ASCII compatibility probe. This is a
-- generator: expected results come from the runtime under test, never another
-- JSON implementation.
local M = {}

local prefix_lengths = {0, 1, 15, 16, 1023, 1024, 1025}
local plain_lengths = {0, 1, 2, 7, 8, 15, 16, 31, 32, 63, 64, 1023, 1024,
                       1025, 65536}
local contexts = {"top", "array", "value", "key", "null"}
local allowed = {}
for byte = 0x20, 0x7f do
  if byte ~= 0x22 and byte ~= 0x5c then
    allowed[#allowed + 1] = string.char(byte)
  end
end

local function plain(n)
  local out = {}
  for i = 1, n do out[i] = allowed[(i - 1) % #allowed + 1] end
  return table.concat(out)
end

function M.wrap(context, content)
  local quoted = '"' .. content .. '"'
  if context == "top" then return quoted end
  if context == "array" then return "[" .. quoted .. "]" end
  if context == "value" then return '{"v":' .. quoted .. "}" end
  if context == "key" then return "{" .. quoted .. ":1}" end
  if context == "null" then return "[" .. quoted .. ",null]" end
  error("unknown JSON corpus context: " .. tostring(context))
end

-- The iterator yields case id, complete input bytes, and wrapper context.
function M.each()
  return coroutine.wrap(function()
    for _, n in ipairs(plain_lengths) do
      coroutine.yield("ascii/" .. n, M.wrap("top", plain(n)), "top")
    end
    for _, n in ipairs(prefix_lengths) do
      local prefix = plain(n)
      for byte = 0, 255 do
        local c = string.char(byte)
        local middle = math.floor(#prefix / 2)
        local variants = {
          {"begin", c .. prefix},
          {"middle", prefix:sub(1, middle) .. c .. prefix:sub(middle + 1)},
          {"end", prefix .. c},
        }
        for _, variant in ipairs(variants) do
          local position, content = variant[1], variant[2]
          for _, context in ipairs(contexts) do
            coroutine.yield(string.format("byte/%d/%02x/%s/%s", n, byte,
                                          position, context),
                            M.wrap(context, content), context)
          end
        end
      end
    end

    local state = 0x4a534f4e
    local function random(limit)
      state = (1664525 * state + 1013904223) % 4294967296
      return state % limit
    end
    for i = 1, 10000 do
      local input = M.wrap("top", plain(1 + random(96)))
      local op = random(4)
      if op == 0 then
        local at = random(#input + 1)
        input = input:sub(1, at) .. string.char(random(256)) ..
                input:sub(at + 1)
      elseif op == 1 then
        local at = random(#input)
        input = input:sub(1, at) .. input:sub(at + 2)
      elseif op == 2 then
        local at = random(#input)
        input = input:sub(1, at) .. string.char(random(256)) ..
                input:sub(at + 2)
      else
        input = input:sub(1, random(#input + 1))
      end
      assert(#input <= 4096)
      coroutine.yield(string.format("mutate/%05d", i), input, "top")
    end
  end)
end

M.count = #plain_lengths + #prefix_lengths * 256 * 3 * #contexts + 10000
return M
