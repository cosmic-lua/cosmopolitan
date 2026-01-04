# cosmo.getopt - Command-line option parsing for Lua

Iterator-based getopt implementation for parsing command-line options in Lua.

## API

### `getopt.new(args, optstring, longopts) -> parser`

Creates a new option parser.

**Parameters:**
- `args`: Table of command-line arguments (e.g., `{"- h", "-v", "--output", "file.txt"}`)
- `optstring`: String specifying valid short options (e.g., `"hvo:"`)
  - Single character: option without argument (e.g., `h`)
  - Character followed by `:`: option requires argument (e.g., `o:`)
- `longopts` (optional): Table of long option specifications
  - Each entry: `{name, has_arg, short_equivalent}`
  - `name`: Long option name (e.g., `"help"`)
  - `has_arg`: `"none"`, `"required"`, or `"optional"`
  - `short_equivalent`: Single-character string or nil (e.g., `"h"`)

**Returns:** Parser object

### `parser:next() -> opt, arg`

Returns the next option from the command line.

**Returns:**
- `opt`: Option name (short character or long name), or `nil` when done
  - `"?"` for unknown options (arg contains the unknown option)
- `arg`: Option argument (string), or `nil` for flag options

**Example:**
```lua
while true do
  local opt, arg = parser:next()
  if not opt then break end
  -- process opt and arg
end
```

### `parser:remaining() -> table`

Returns remaining non-option arguments after parsing.

### `parser:unknown() -> table`

Returns table of unknown options encountered during parsing.

## Examples

### Basic usage

```lua
local getopt = require("cosmo.getopt")

-- Parse: prog -v -o output.txt input.txt
local parser = getopt.new({"-v", "-o", "output.txt", "input.txt"}, "vo:")

local verbose = false
local output = nil

while true do
  local opt, arg = parser:next()
  if not opt then break end

  if opt == "v" then
    verbose = true
  elseif opt == "o" then
    output = arg
  end
end

local remaining = parser:remaining()
-- remaining = {"input.txt"}
```

### Handling repeated options

```lua
-- Parse: prog -e foo -e bar -e spam
local parser = getopt.new({"-e", "foo", "-e", "bar", "-e", "spam"}, "e:")

local excludes = {}
while true do
  local opt, arg = parser:next()
  if not opt then break end

  if opt == "e" then
    table.insert(excludes, arg)
  end
end
-- excludes = {"foo", "bar", "spam"}
```

### Long options

```lua
-- Parse: prog --help --output=file.txt
local parser = getopt.new({"--help", "--output=file.txt"}, "ho:", {
  {"help", "none", "h"},
  {"output", "required", "o"},
})

while true do
  local opt, arg = parser:next()
  if not opt then break end

  if opt == "help" or opt == "h" then
    print("Usage: ...")
  elseif opt == "output" or opt == "o" then
    print("Output:", arg)
  end
end
```

### Handling unknown options

```lua
local parser = getopt.new({"-v", "-x", "--unknown"}, "v")

while true do
  local opt, arg = parser:next()
  if not opt then break end

  if opt == "?" then
    print("Unknown option:", arg)
  elseif opt == "v" then
    print("Verbose mode")
  end
end

local unknown = parser:unknown()
-- unknown = {"x", "--unknown"}
```

## Notes

- The parser uses global getopt state and is NOT thread-safe
- Unknown options are tracked and available via `parser:unknown()`
- The `--` argument terminates option processing
- Both short options (`-h`) and long options (`--help`) are supported
- Long options can use `=` for arguments (`--output=file`) or space (`--output file`)
- Short options can be combined (`-hv` same as `-h -v`)
