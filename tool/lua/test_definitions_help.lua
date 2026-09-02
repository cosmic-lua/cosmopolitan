-- Shape-count gate between tool/net/help.txt (redbean's embedded manual)
-- and tool/net/definitions.lua (the annotation source of truth).
--
-- help.txt restates every unix.* binding's return shape as a box-drawn
-- block under its signature line:
--
--   unix.getsid(pid:int)
--       ├─→ sid:int
--       └─→ nil, error:str, errno:int
--
-- definitions.lua declares the same contract as @return annotations, and
-- only the annotations are read by anything downstream, so the manual
-- drifts silently whenever a contract changes shape. This test compares
-- the two at the level those changes actually move: whether the call is
-- fallible. Deliberately count-level, not per-slot type -- the parser
-- stays trivial and the drift class is still caught.
--
--   * help.txt: a block is fallible when it carries a FAILURE branch, a
--     line whose first value is `nil` (`└─→ nil, error:str, errno:int`).
--     That is the second line of the usual two-branch block, the last
--     line of a three-branch block whose other lines are alternative
--     success shapes (`unix.accept`), and the ONLY line of a call that
--     never returns on success (`unix.execve`). A block that carries no
--     such branch documents an infallible call.
--   * definitions.lua: a function is fallible when the first `@return`
--     of its annotation block admits nil (`integer|nil`, `nil`, `T?`),
--     the fork's rule that slot 1 admitting nil makes slot 2 the error.
--     No `@return` at all is an infallible call with no result.
--
-- A signature line is `  unix.<name>(` at two-space indent; several
-- signatures stacked directly above one block share it. A signature
-- with no block below it documents no shape and is not compared. A name
-- help.txt documents that definitions.lua declares no function for is a
-- mismatch too: the manual is describing a call that no longer exists
-- under that name. Every mismatch is reported with its help.txt line;
-- fix the manual (definitions.lua is the source of truth).

local function slurp(path)
  local f = assert(io.open(path, "r"), "cannot open " .. path)
  local s = f:read("*a")
  f:close()
  return s
end

local D = slurp("tool/net/definitions.lua")
local H = slurp("tool/net/help.txt")

local SUCCESS_BRANCH = "├─→"
local FINAL_BRANCH = "└─→"

-- The first `@return` of the `---` block directly above
-- `function unix.<name>(`. Returns the declared slot-1 type, "" when the
-- block declares no return, or nil when definitions.lua declares no such
-- function.
local function def_slot1(name)
  local lines = {}
  local found = false
  for line in (D .. "\n"):gmatch("([^\n]*)\n") do
    if line:match("^function unix%." .. name .. "%s*%(") then
      found = true
      break
    end
    if line:match("^%-%-%-") then
      lines[#lines + 1] = line
    else
      lines = {}
    end
  end
  if not found then
    return nil
  end
  for _, line in ipairs(lines) do
    local t = line:match("^%-%-%-%s*@return%s+(%S+)")
    if t then
      return t
    end
  end
  return ""
end

local function def_is_fallible(slot1)
  return slot1 == "nil" or slot1:match("|nil%f[^%w_]") ~= nil or
    slot1:match("^nil|") ~= nil or slot1:match("%?$") ~= nil
end

-- Every documented unix.* shape block: { line, names, branches }, where
-- branches are the text after the arrow, in order.
local function help_blocks()
  local lines = {}
  for line in (H .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
  end
  local blocks = {}
  local i = 1
  while i <= #lines do
    local name = lines[i]:match("^  unix%.([%a_][%w_]*)%s*%(")
    if name then
      local block = { line = i, names = { name }, branches = {} }
      local j = i + 1
      while lines[j] and lines[j]:match("^  unix%.[%a_][%w_]*%s*%(") do
        block.names[#block.names + 1] = lines[j]:match("^  unix%.([%a_][%w_]*)")
        j = j + 1
      end
      while lines[j] do
        local arrow, shape = lines[j]:match("^      (" .. SUCCESS_BRANCH ..
          ")%s*(.-)%s*$")
        if not arrow then
          arrow, shape = lines[j]:match("^      (" .. FINAL_BRANCH ..
            ")%s*(.-)%s*$")
        end
        if not arrow then
          break
        end
        block.branches[#block.branches + 1] = { arrow = arrow, shape = shape }
        j = j + 1
      end
      if #block.branches > 0 then
        blocks[#blocks + 1] = block
      end
      i = j
    else
      i = i + 1
    end
  end
  return blocks
end

local failures = {}
local function fail(msg)
  failures[#failures + 1] = msg
end

local blocks = help_blocks()
assert(#blocks > 50, "help.txt parsed only " .. #blocks ..
  " unix.* shape blocks; the manual's layout changed under this parser")

local checked = 0
for _, block in ipairs(blocks) do
  local where = "help.txt:" .. block.line
  -- Structure: every branch but the last is ├─→, the last is └─→.
  local help_fallible = false
  for k, branch in ipairs(block.branches) do
    local last = k == #block.branches
    if (branch.arrow == FINAL_BRANCH) ~= last then
      fail(where .. " unix." .. block.names[1] ..
        ": malformed shape block (" .. FINAL_BRANCH ..
        " must be the last branch and the only one)")
    end
    if branch.shape:match("^nil%f[^%w_]") then
      help_fallible = true
    end
  end
  local help_says = help_fallible and "fallible" or "infallible"
  for _, name in ipairs(block.names) do
    local slot1 = def_slot1(name)
    if slot1 == nil then
      fail(where .. " unix." .. name .. ": documented with a shape block, " ..
        "but definitions.lua declares no `function unix." .. name .. "(`")
    else
      checked = checked + 1
      local def_fallible = def_is_fallible(slot1)
      if def_fallible ~= help_fallible then
        local def_says = def_fallible and "fallible" or "infallible"
        local decl = slot1 == "" and "no @return" or ("@return " .. slot1)
        fail(where .. " unix." .. name .. ": help.txt declares " ..
          help_says .. " (" .. #block.branches .. " branch" ..
          (#block.branches == 1 and "" or "es") ..
          "), definitions.lua declares " .. def_says .. " (" .. decl .. ")")
      end
    end
  end
end

assert(#failures == 0,
  "help.txt drifts from definitions.lua (fix the manual's shape block; " ..
  "definitions.lua is the source of truth):\n  " ..
  table.concat(failures, "\n  "))

print("definitions help: " .. checked .. " unix.* shape blocks in " ..
  "help.txt agree with definitions.lua on fallibility")
print("test_definitions_help: PASS")
