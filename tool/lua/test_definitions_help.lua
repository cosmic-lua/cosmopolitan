-- Shape-count gate between the two hand-maintained restatements of the
-- unix.* return shapes and tool/net/definitions.lua (the annotation
-- source of truth).
--
-- Both tool/net/help.txt (redbean's embedded manual) and
-- third_party/lua/cosmo/lunix.c (a comment above each LuaUnix* binding)
-- restate every unix.* binding's return shape as a box-drawn block under
-- its signature line, both for plain functions and for
-- unix.<Type>:<method>() methods on the userdata objects (unix.Stat,
-- unix.Rusage, unix.Sigset, unix.Dir, unix.Memory):
--
--   unix.getsid(pid:int)                 // unix.getsid(pid:int)
--       ├─→ sid:int                      //     ├─→ sid:int
--       └─→ nil, error:str, errno:int    //     └─→ nil, error:str, errno:int
--
--   unix.Stat:size()                     // unix.Stat:size()
--       └─→ bytes:int                    //     └─→ bytes:int
--
-- The 2 sandbox.* shape blocks (sandbox.pledge, sandbox.unveil) stay
-- outside this gate: the pattern below matches only `unix.`-prefixed
-- signatures, and sandbox.*'s annotations live under a different table
-- in definitions.lua.
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
-- line is `<callee>(` -- `unix.<name>(` or `unix.<Type>:<method>(`,
-- and in help.txt also the other modules' calls (`DecodeJson(`,
-- `re.search(`, `path.join(`), whose blocks open and close under the
-- same grammar but are not compared -- and a branch line is four more
-- spaces then the arrow. A block may itself sit under further
-- indentation -- lunix.c documents getsockopt/setsockopt per option
-- class inside the C body, and help.txt nests those same blocks under
-- a bullet -- so the signature's own leading whitespace is captured and
-- every line of its block must carry it. Several signatures stacked
-- directly above one block share it, and a branch-indent line opening
-- with `│` continues the branch above it (`unix.uname`'s table wraps).
-- A signature with no block below it documents no shape and is not
-- compared, and neither is `unix.fork`, whose tree-shaped block
-- (`├─┬─→`, then `│`-led lines) is consumed and skipped in both
-- sources.
--
-- A line opening with a shape glyph (`├─→`, `└─→`, `│`, `├─┬─→`) that
-- belongs to no block -- its indent is not the four-space step below
-- the signature above it, or nothing above it opens a block -- is a
-- failure by line, never a skip: a block the parser cannot read would
-- otherwise leave the gate in silence. For the same reason each
-- source's count of names put through the gate (the number the gate
-- prints) is pinned as `floor` in SOURCES; a commit that adds blocks
-- raises it, so a vanished block fails by count.
--
-- A name a source documents that definitions.lua declares no
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
  { label = "help.txt", path = "tool/net/help.txt", prefix = "  ", floor = 179 },
  { label = "lunix.c", path = "third_party/lua/cosmo/lunix.c", prefix = "// ",
    floor = 219 },
}

local SUCCESS_BRANCH = "├─→"
local FINAL_BRANCH = "└─→"
local CONTINUATION = "│"
local TREE_BRANCH = "├─┬─→"
-- Listed one by one: a `[...]` class over these would match their UTF-8
-- bytes, and so `─` and `┬` too.
local GLYPHS = { SUCCESS_BRANCH, FINAL_BRANCH, CONTINUATION, TREE_BRANCH }

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
-- after the arrow, in order. `name` (and so `names`) is `getsid` for a
-- plain function and `Stat:size` for a method, matching how
-- definitions.lua spells the two (`function unix.getsid(`, `function
-- unix.Stat:size(`). A block under any other callee (help.txt's
-- `DecodeJson(`, `re.search(`) is walked by the same grammar so its
-- lines are accounted for, and dropped.
--
-- Second return: every line whose first non-blank content after `prefix`
-- is `uni<letters>.` where the word isn't `unix` -- a mistyped prefix
-- (`unid.`, `unis.`) that a `unix.`-anchored signature pattern would
-- otherwise skip in silence. The trailing `.` (call syntax, not prose)
-- keeps this off unrelated comments that merely start with a `uni`
-- word, such as "uninitialized" in a sentence. Reported as a failure
-- by line, never folded into `blocks`.
--
-- Third return: every line whose first non-blank content after `prefix`
-- is a shape glyph yet lies in no block -- the line above it neither
-- opens a block nor continues one at the indent this line carries.
-- Also a failure by line: such a line is a branch the gate never saw.
local function shape_blocks(text, prefix)
  local any_sig = "^( *)" .. prefix .. "([%a_][%w_.:]*)%s*%("
  local typo_sig = "^ *" .. prefix .. "(uni%a*)%."
  local glyph = "^ *" .. prefix .. " *"
  local lines = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
  end
  -- A signature line's indent and callee; nil for a mistyped `uni...`
  -- callee, which stays a line for the typo report to see.
  local function signature(line)
    local indent, callee = line:match(any_sig)
    local word = callee and callee:match("^(uni%a*)%.")
    if callee and not (word and word ~= "unix") then
      return indent, callee
    end
  end
  local blocks = {}
  local typos = {}
  local orphans = {}
  local i = 1
  while i <= #lines do
    local indent = signature(lines[i])
    if indent then
      local branch = "^" .. indent .. prefix .. "    "
      local block = { line = i, names = {}, branches = {} }
      local tree = false
      local j = i
      while lines[j] do
        local sig_indent, callee = signature(lines[j])
        if sig_indent ~= indent then
          break
        end
        local name = callee:match("^unix%.(.+)$")
        if name then
          block.names[#block.names + 1] = name
        end
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
        elseif lines[j]:match(branch .. TREE_BRANCH) then
          tree = true
        elseif not ((tree or #block.branches > 0) and
                    lines[j]:match(branch .. CONTINUATION)) then
          break
        end
        j = j + 1
      end
      if #block.branches > 0 and #block.names > 0 and not tree then
        blocks[#blocks + 1] = block
      end
      i = j
    else
      local word = lines[i]:match(typo_sig)
      if word and word ~= "unix" then
        typos[#typos + 1] = { line = i, text = lines[i]:match("^%s*(.-)%s*$") }
      else
        for _, g in ipairs(GLYPHS) do
          if lines[i]:match(glyph .. g) then
            orphans[#orphans + 1] =
              { line = i, text = lines[i]:match("^%s*(.-)%s*$") }
            break
          end
        end
      end
      i = i + 1
    end
  end
  return blocks, typos, orphans
end

local failures = {}
local function fail(msg)
  failures[#failures + 1] = msg
end

local summary = {}
for _, source in ipairs(SOURCES) do
  local blocks, typos, orphans =
    shape_blocks(slurp(source.path), source.prefix)

  for _, typo in ipairs(typos) do
    fail(source.label .. ":" .. typo.line .. " \"" .. typo.text ..
      "\": mistyped prefix (reads \"" .. source.prefix .. "uni...\", " ..
      "not \"" .. source.prefix .. "unix.\")")
  end
  for _, orphan in ipairs(orphans) do
    fail(source.label .. ":" .. orphan.line .. " \"" .. orphan.text ..
      "\": shape line in no block (a branch line sits exactly four " ..
      "spaces deeper than its signature; nothing above opens a block " ..
      "at this indent)")
  end

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
  if checked < source.floor then
    fail(source.label .. ": " .. checked .. " unix.* shape blocks reach " ..
      "the gate, below its floor of " .. source.floor .. " (a block " ..
      "left the gate; `floor` in SOURCES moves only with the blocks)")
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
