-- Shape-count gate between the two hand-maintained restatements of the
-- unix.* return shapes and tool/net/definitions.lua (the annotation
-- source of truth).
--
-- Both tool/net/help.txt (redbean's embedded manual) and
-- third_party/lua/cosmo/lunix.c (a comment above each LuaUnix* binding)
-- restate every unix.* binding's return shape as a box-drawn block under
-- its signature line:
--
--   unix.getsid(pid:int)                 // unix.getsid(pid:int)
--       ├─→ sid:int                      //     ├─→ sid:int
--       └─→ nil, error:str, errno:int    //     └─→ nil, error:str, errno:int
--
-- definitions.lua declares the same contract as @return annotations, and
-- only the annotations are read by anything downstream, so both copies
-- drift silently whenever a contract changes shape. This test compares
-- each copy against definitions.lua at the level those changes actually
-- move: whether the call is fallible. Deliberately count-level, not
-- per-slot type -- the parser stays trivial and the drift class is still
-- caught.
--
--   * a shape block is fallible when it carries a FAILURE branch, a line
--     whose first value is `nil` (`└─→ nil, error:str, errno:int`). That
--     is the second line of the usual two-branch block, the last line of
--     a three-branch block whose other lines are alternative success
--     shapes (`unix.accept`), and the ONLY line of a call that never
--     returns on success (`unix.execve`). A block that carries no such
--     branch documents an infallible call.
--   * definitions.lua: a function is fallible when the first `@return`
--     of its annotation block admits nil (`integer|nil`, `nil`, `T?`),
--     the fork's rule that slot 1 admitting nil makes slot 2 the error.
--     No `@return` at all is an infallible call with no result.
--
-- The two sources differ only in the prefix every line carries: two
-- spaces in help.txt, `// ` in lunix.c. Under that prefix a signature
-- line is `unix.<name>(` and a branch line is four more spaces then the
-- arrow. A block may itself sit under further indentation -- lunix.c
-- documents getsockopt/setsockopt per option class inside the C body,
-- and help.txt nests those same blocks under a bullet -- so the
-- signature's own leading whitespace is captured and every line of its
-- block must carry it. Several signatures stacked directly above one
-- block share it, and a branch-indent line opening with `│` continues
-- the branch above it (`unix.uname`'s table wraps). A signature with no
-- block below it
-- documents no shape and is not compared, and neither is `unix.fork`,
-- whose tree-shaped block (`├─┬─→`) lies outside this grammar in both
-- sources. A name a source documents that definitions.lua declares no
-- function for is a mismatch too: the copy is describing a call that no
-- longer exists under that name. Every mismatch is reported with its
-- source file and line; fix the copy (definitions.lua is the source of
-- truth).

local function slurp(path)
  local f = assert(io.open(path, "r"), "cannot open " .. path)
  local s = f:read("*a")
  f:close()
  return s
end

local D = slurp("tool/net/definitions.lua")

local SOURCES = {
  { label = "help.txt", path = "tool/net/help.txt", prefix = "  " },
  { label = "lunix.c", path = "third_party/lua/cosmo/lunix.c", prefix = "// " },
}

local SUCCESS_BRANCH = "├─→"
local FINAL_BRANCH = "└─→"
local CONTINUATION = "│"

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

-- Every documented unix.* shape block in `text`, whose lines all carry
-- `prefix` (no pattern magic in either prefix) under the signature's own
-- indentation: { line, names, branches }, where branches are the text
-- after the arrow, in order.
local function shape_blocks(text, prefix)
  local any_sig = "^( *)" .. prefix .. "unix%.([%a_][%w_]*)%s*%("
  local lines = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
  end
  local blocks = {}
  local i = 1
  while i <= #lines do
    local indent, name = lines[i]:match(any_sig)
    if name then
      local sig = "^" .. indent .. prefix .. "unix%.([%a_][%w_]*)%s*%("
      local branch = "^" .. indent .. prefix .. "    "
      local block = { line = i, names = { name }, branches = {} }
      local j = i + 1
      while lines[j] and lines[j]:match(sig) do
        block.names[#block.names + 1] = lines[j]:match(sig)
        j = j + 1
      end
      while lines[j] do
        local arrow, shape = lines[j]:match(branch .. "(" .. SUCCESS_BRANCH ..
          ")%s*(.-)%s*$")
        if not arrow then
          arrow, shape = lines[j]:match(branch .. "(" .. FINAL_BRANCH ..
            ")%s*(.-)%s*$")
        end
        if arrow then
          block.branches[#block.branches + 1] = { arrow = arrow, shape = shape }
        elseif not (#block.branches > 0 and
                    lines[j]:match(branch .. CONTINUATION)) then
          break
        end
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

local summary = {}
for _, source in ipairs(SOURCES) do
  local blocks = shape_blocks(slurp(source.path), source.prefix)
  assert(#blocks > 50, source.label .. " parsed only " .. #blocks ..
    " unix.* shape blocks; its layout changed under this parser")

  local checked = 0
  for _, block in ipairs(blocks) do
    local where = source.label .. ":" .. block.line
    -- Structure: every branch but the last is ├─→, the last is └─→.
    local fallible = false
    for k, br in ipairs(block.branches) do
      local last = k == #block.branches
      if (br.arrow == FINAL_BRANCH) ~= last then
        fail(where .. " unix." .. block.names[1] ..
          ": malformed shape block (" .. FINAL_BRANCH ..
          " must be the last branch and the only one)")
      end
      if br.shape:match("^nil%f[^%w_]") then
        fallible = true
      end
    end
    local says = fallible and "fallible" or "infallible"
    for _, name in ipairs(block.names) do
      local slot1 = def_slot1(name)
      if slot1 == nil then
        fail(where .. " unix." .. name .. ": documented with a shape " ..
          "block, but definitions.lua declares no `function unix." ..
          name .. "(`")
      else
        checked = checked + 1
        local def_fallible = def_is_fallible(slot1)
        if def_fallible ~= fallible then
          local def_says = def_fallible and "fallible" or "infallible"
          local decl = slot1 == "" and "no @return" or ("@return " .. slot1)
          fail(where .. " unix." .. name .. ": " .. source.label ..
            " declares " .. says .. " (" .. #block.branches .. " branch" ..
            (#block.branches == 1 and "" or "es") ..
            "), definitions.lua declares " .. def_says .. " (" .. decl .. ")")
        end
      end
    end
  end
  summary[#summary + 1] = "definitions help: " .. checked ..
    " unix.* shape blocks in " .. source.label ..
    " agree with definitions.lua on fallibility"
end

assert(#failures == 0,
  "help.txt/lunix.c drift from definitions.lua (fix the shape block; " ..
  "definitions.lua is the source of truth):\n  " ..
  table.concat(failures, "\n  "))

print(table.concat(summary, "\n"))
print("test_definitions_help: PASS")
