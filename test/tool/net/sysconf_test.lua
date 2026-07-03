-- Copyright 2026 Will Maier
--
-- Permission to use, copy, modify, and/or distribute this software for
-- any purpose with or without fee is hereby granted, provided that the
-- above copyright notice and this permission notice appear in all copies.
--
-- THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
-- WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
-- WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
-- AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
-- DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR
-- PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
-- TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
-- PERFORMANCE OF THIS SOFTWARE.

assert(unix.pledge("stdio"))

-- The name constants are exported as integers.
assert(math.type(unix.SC_NPROCESSORS_ONLN) == "integer")
assert(math.type(unix.SC_NPROCESSORS_CONF) == "integer")
assert(math.type(unix.SC_PAGESIZE) == "integer")
assert(math.type(unix.SC_CLK_TCK) == "integer")
assert(math.type(unix.SC_OPEN_MAX) == "integer")
assert(math.type(unix.SC_ARG_MAX) == "integer")
assert(math.type(unix.SC_CHILD_MAX) == "integer")

-- Number of online processors is a positive integer.
local nonln = assert(unix.sysconf(unix.SC_NPROCESSORS_ONLN))
assert(math.type(nonln) == "integer")
assert(nonln >= 1)

-- The machine can never have fewer configured than online CPUs.
local nconf = assert(unix.sysconf(unix.SC_NPROCESSORS_CONF))
assert(nconf >= nonln)

-- Page size is a positive power of two (>= 4096 on supported hosts).
local pagesize = assert(unix.sysconf(unix.SC_PAGESIZE))
assert(math.type(pagesize) == "integer")
assert(pagesize >= 4096)
assert((pagesize & (pagesize - 1)) == 0)

-- Clock ticks per second is positive.
local clktck = assert(unix.sysconf(unix.SC_CLK_TCK))
assert(clktck > 0)

-- An unrecognized name fails with nil, unix.Errno holding EINVAL rather
-- than throwing or returning a bogus value.
local rc, err = unix.sysconf(-1)
assert(rc == nil)
assert(err)
assert(err:errno() == unix.EINVAL)

print("All sysconf tests passed!")
