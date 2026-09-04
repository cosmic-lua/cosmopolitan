-- Convergence gate for the test rules in tool/lua/BUILD.mk.
--
-- Every test there is a rule of the shape
--
--   o/$(MODE)/tool/lua/<name>.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/<name>.lua
--   	$< tool/lua/<name>.lua
--   	@touch $@
--
-- and the `@touch $@` is what makes the target converge: the test runs,
-- the .ok file is written, and the next `make o//tool/lua/test` sees it
-- up to date. A rule that loses its touch -- a new block pasted between
-- a neighbour's recipe line and its touch, say -- still passes when the
-- test passes, so nothing goes red; the target just never exists, and
-- that one test re-runs on every make forever. This test reads
-- BUILD.mk and asserts that the recipe of every `.ok` rule under
-- o/$(MODE)/tool/lua/ ends with `@touch $@`, naming each rule that does
-- not, so the omission fails the very build that introduces it.
--
-- The parser follows make's own grammar just far enough for this file:
-- a line ending in a backslash continues onto the next; a rule is a
-- logical line at column 0 that opens with the .ok target and a colon;
-- its recipe is the tab-prefixed lines that follow, with blank lines
-- and column-0 comment lines ignored, ending at the first line that is
-- neither. The last recipe line, trailing whitespace dropped, must be
-- exactly `@touch $@`.

local function slurp(path)
  local f = assert(io.open(path, "r"), "cannot open " .. path)
  local s = f:read("*a")
  f:close()
  return s
end

local MK = "tool/lua/BUILD.mk"
local TARGET_PREFIX = "o/$(MODE)/tool/lua/"
local TOUCH = "@touch $@"

-- Physical lines, then logical lines: each carries the number of the
-- physical line it starts on, so a report points at the rule itself.
local physical = {}
for line in (slurp(MK) .. "\n"):gmatch("(.-)\r?\n") do
  physical[#physical + 1] = line
end

local logical = {}
do
  local i = 1
  while i <= #physical do
    local start = i
    local text = physical[i]
    while text:sub(-1) == "\\" and i < #physical do
      i = i + 1
      text = text:sub(1, -2) .. physical[i]
    end
    logical[#logical + 1] = { line = start, text = text }
    i = i + 1
  end
end

local function is_ignored(text)
  return text:match("^%s*$") ~= nil or text:match("^%s*#") ~= nil
end

local function target_of(text)
  if text:sub(1, #TARGET_PREFIX) ~= TARGET_PREFIX then
    return nil
  end
  local name = text:sub(#TARGET_PREFIX + 1):match("^([%w_%-%.]-)%.ok:")
  if name == nil then
    return nil
  end
  return TARGET_PREFIX .. name .. ".ok"
end

local checked = 0
local failures = {}

local i = 1
while i <= #logical do
  local target = target_of(logical[i].text)
  if target == nil then
    i = i + 1
  else
    local where = MK .. ":" .. logical[i].line .. " " .. target
    local last = nil
    i = i + 1
    while i <= #logical do
      local text = logical[i].text
      if text:sub(1, 1) == "\t" then
        last = text
      elseif not is_ignored(text) then
        break
      end
      i = i + 1
    end
    checked = checked + 1
    if last == nil then
      failures[#failures + 1] = where .. ": no recipe"
    else
      local tail = last:sub(2):gsub("%s+$", "")
      if tail ~= TOUCH then
        failures[#failures + 1] = where ..
          ": recipe ends with `" .. tail .. "`, not `" .. TOUCH .. "`"
      end
    end
  end
end

assert(checked > 0, "no " .. TARGET_PREFIX .. "<name>.ok: rules found in " ..
  MK .. " (the parser no longer matches the file's shape)")

assert(#failures == 0,
  "a .ok rule in " .. MK .. " does not end with `" .. TOUCH ..
  "`, so its target never converges (every make re-runs it):\n  " ..
  table.concat(failures, "\n  "))

print("build.mk touch: " .. checked .. " .ok rules in " .. MK ..
  " end with `" .. TOUCH .. "`")
print("test_build_mk_touch: PASS")
