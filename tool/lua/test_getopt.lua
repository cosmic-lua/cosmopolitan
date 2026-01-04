local getopt = require("cosmo.getopt")

-- Test module exists
assert(getopt, "getopt module should exist")
assert(type(getopt.parse) == "function", "getopt.parse should be a function")

-- Test short options only
local opts, args, unknown = getopt.parse({"-h", "-v", "-o", "out.txt", "file.txt"}, "hvo:", {})
assert(opts.h == true, "opts.h should be true")
assert(opts.v == true, "opts.v should be true")
assert(opts.o == "out.txt", "opts.o should be 'out.txt'")
assert(args[1] == "file.txt", "first remaining arg should be 'file.txt'")
assert(#args == 1, "should have exactly 1 remaining arg")
assert(#unknown == 0, "should have no unknown options")

-- Test long options
opts, args, unknown = getopt.parse({"--help", "--output=foo.txt", "input.txt"}, "ho:", {
  {"help", "none", "h"},
  {"output", "required", "o"},
})
assert(opts.help == true, "opts.help should be true")
assert(opts.h == true, "opts.h should also be true (from --help)")
assert(opts.output == "foo.txt", "opts.output should be 'foo.txt'")
assert(opts.o == "foo.txt", "opts.o should also be 'foo.txt'")
assert(args[1] == "input.txt", "remaining arg should be 'input.txt'")
assert(#unknown == 0, "should have no unknown options")

-- Test long option with separate argument
opts, args, unknown = getopt.parse({"--output", "bar.txt"}, "o:", {
  {"output", "required", "o"},
})
assert(opts.output == "bar.txt", "opts.output should be 'bar.txt'")
assert(opts.o == "bar.txt", "opts.o should be 'bar.txt'")
assert(#unknown == 0, "should have no unknown options")

-- Test combined short options
opts, args, unknown = getopt.parse({"-hv", "file.txt"}, "hv", {})
assert(opts.h == true, "opts.h should be true")
assert(opts.v == true, "opts.v should be true")
assert(args[1] == "file.txt", "remaining arg should be 'file.txt'")
assert(#unknown == 0, "should have no unknown options")

-- Test -- terminator
opts, args, unknown = getopt.parse({"-h", "--", "-v", "file.txt"}, "hv", {})
assert(opts.h == true, "opts.h should be true")
assert(opts.v == nil, "-v after -- should not be parsed as option")
assert(args[1] == "-v", "first remaining should be '-v'")
assert(args[2] == "file.txt", "second remaining should be 'file.txt'")
assert(#unknown == 0, "should have no unknown options")

-- Test empty args
opts, args, unknown = getopt.parse({}, "hv", {})
assert(next(opts) == nil, "opts should be empty")
assert(#args == 0, "args should be empty")
assert(#unknown == 0, "should have no unknown options")

-- Test no longopts argument
opts, args, unknown = getopt.parse({"-h"}, "h")
assert(opts.h == true, "opts.h should be true without longopts arg")
assert(#unknown == 0, "should have no unknown options")

-- Test unknown short option
opts, args, unknown = getopt.parse({"-h", "-x", "-v"}, "hv", {})
assert(opts.h == true, "opts.h should be true")
assert(opts.v == true, "opts.v should be true")
assert(opts.x == nil, "opts.x should be nil (unknown)")
assert(#unknown == 1, "should have 1 unknown option")
assert(unknown[1] == "x", "unknown[1] should be 'x'")

-- Test unknown long option
opts, args, unknown = getopt.parse({"--help", "--foo", "--verbose"}, "hv", {
  {"help", "none", "h"},
  {"verbose", "none", "v"},
})
assert(opts.help == true, "opts.help should be true")
assert(opts.verbose == true, "opts.verbose should be true")
assert(#unknown == 1, "should have 1 unknown option")

-- Test multiple unknown options
opts, args, unknown = getopt.parse({"-x", "-y", "-z"}, "h", {})
assert(#unknown == 3, "should have 3 unknown options")

-- Test repeated short options
opts, args, unknown = getopt.parse({"-e", "foo", "-e", "bar", "-e", "spam"}, "e:", {})
assert(type(opts.e) == "table", "repeated option should create a table")
assert(#opts.e == 3, "should have 3 values for -e")
assert(opts.e[1] == "foo", "first -e value should be 'foo'")
assert(opts.e[2] == "bar", "second -e value should be 'bar'")
assert(opts.e[3] == "spam", "third -e value should be 'spam'")

-- Test repeated long options
opts, args, unknown = getopt.parse({"--include", "a.h", "--include", "b.h"}, "I:", {
  {"include", "required", "I"},
})
assert(type(opts.include) == "table", "repeated long option should create a table")
assert(#opts.include == 2, "should have 2 values for --include")
assert(opts.include[1] == "a.h", "first --include should be 'a.h'")
assert(opts.include[2] == "b.h", "second --include should be 'b.h'")
assert(type(opts.I) == "table", "short option should also be a table")
assert(opts.I[1] == "a.h", "short option should have same values")

-- Test mix of single and repeated options
opts, args, unknown = getopt.parse({"-v", "-e", "foo", "-o", "out", "-e", "bar"}, "ve:o:", {})
assert(opts.v == true, "single option should be boolean")
assert(type(opts.e) == "table", "repeated option should be table")
assert(opts.e[1] == "foo" and opts.e[2] == "bar", "repeated values should be correct")
assert(opts.o == "out", "single option with arg should be string")

print("PASS")
