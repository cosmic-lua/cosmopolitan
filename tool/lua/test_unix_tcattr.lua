-- Copyright 2024 Will Maier
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

-- Tests for unix.tcgetattr() and unix.tcsetattr()

local unix = require("cosmo.unix")

-- Test function existence
assert(type(unix.tcgetattr) == "function", "tcgetattr should be a function")
assert(type(unix.tcsetattr) == "function", "tcsetattr should be a function")

-- Test constants exist
assert(type(unix.TCSANOW) == "number", "TCSANOW should be a number")
assert(type(unix.TCSADRAIN) == "number", "TCSADRAIN should be a number")
assert(type(unix.TCSAFLUSH) == "number", "TCSAFLUSH should be a number")

-- Test termios-related constants
assert(type(unix.ECHO) == "number", "ECHO should be a number")
assert(type(unix.ECHOE) == "number", "ECHOE should be a number")
assert(type(unix.ECHOK) == "number", "ECHOK should be a number")
assert(type(unix.ECHONL) == "number", "ECHONL should be a number")
assert(type(unix.ICANON) == "number", "ICANON should be a number")
assert(type(unix.ISIG) == "number", "ISIG should be a number")
assert(type(unix.OPOST) == "number", "OPOST should be a number")
assert(type(unix.CSIZE) == "number", "CSIZE should be a number")
assert(type(unix.PARENB) == "number", "PARENB should be a number")
assert(type(unix.VMIN) == "number", "VMIN should be a number")
assert(type(unix.VTIME) == "number", "VTIME should be a number")
assert(type(unix.NCCS) == "number", "NCCS should be a number")
assert(unix.NCCS > 0, "NCCS should be positive")

-- Test tcgetattr on a non-terminal fd (should fail with ENOTTY)
local fd = unix.open("/dev/null", unix.O_RDONLY)
assert(fd, "should be able to open /dev/null")
local tio, err = unix.tcgetattr(fd)
assert(tio == nil, "tcgetattr on /dev/null should fail")
assert(err ~= nil, "tcgetattr should return error for non-tty")
unix.close(fd)

-- Test tcsetattr on a non-terminal fd (should fail)
local fd = unix.open("/dev/null", unix.O_RDONLY)
assert(fd, "should be able to open /dev/null")
local ok, err = unix.tcsetattr(fd, unix.TCSANOW, {
  iflag = 0,
  oflag = 0,
  cflag = 0,
  lflag = 0,
})
assert(ok == nil, "tcsetattr on /dev/null should fail")
assert(err ~= nil, "tcsetattr should return error for non-tty")
unix.close(fd)

-- Test tcgetattr on a pty if possible
-- Open a pty master; if openpty or /dev/ptmx is available, test real attrs
local pty_fd = unix.open("/dev/ptmx", unix.O_RDWR)
if pty_fd then
  local tio, err = unix.tcgetattr(pty_fd)
  if tio then
    -- Verify the returned table has the expected fields
    assert(type(tio.iflag) == "number", "iflag should be a number")
    assert(type(tio.oflag) == "number", "oflag should be a number")
    assert(type(tio.cflag) == "number", "cflag should be a number")
    assert(type(tio.lflag) == "number", "lflag should be a number")
    assert(type(tio.cc) == "table", "cc should be a table")
    assert(type(tio.ispeed) == "number", "ispeed should be a number")
    assert(type(tio.ospeed) == "number", "ospeed should be a number")

    -- Verify cc table has NCCS entries
    local cc_count = 0
    for i = 1, unix.NCCS do
      assert(type(tio.cc[i]) == "number", "cc[" .. i .. "] should be a number")
      cc_count = cc_count + 1
    end
    assert(cc_count == unix.NCCS, "cc should have NCCS entries")

    -- Test tcsetattr with the same attributes (round-trip)
    local ok, err = unix.tcsetattr(pty_fd, unix.TCSANOW, tio)
    assert(ok == true, "tcsetattr should succeed on pty: " .. tostring(err))

    -- Verify attributes can be read back
    local tio2, err2 = unix.tcgetattr(pty_fd)
    assert(tio2 ~= nil, "tcgetattr should succeed after tcsetattr: " .. tostring(err2))
    assert(type(tio2.iflag) == "number", "iflag should persist")
    assert(type(tio2.oflag) == "number", "oflag should persist")
    assert(type(tio2.cflag) == "number", "cflag should persist")
    assert(type(tio2.lflag) == "number", "lflag should persist")

    -- Test modifying terminal attributes
    local modified = {
      iflag = tio.iflag,
      oflag = tio.oflag,
      cflag = tio.cflag,
      lflag = tio.lflag & ~unix.ECHO,  -- disable echo
      cc = tio.cc,
      ispeed = tio.ispeed,
      ospeed = tio.ospeed,
    }
    local ok, err = unix.tcsetattr(pty_fd, unix.TCSANOW, modified)
    assert(ok == true, "tcsetattr with modified lflag should succeed: " .. tostring(err))

    local tio3, err3 = unix.tcgetattr(pty_fd)
    assert(tio3 ~= nil, "tcgetattr after modification should succeed: " .. tostring(err3))
    -- Verify ECHO is disabled
    assert(tio3.lflag & unix.ECHO == 0,
      "ECHO should be disabled after tcsetattr")

    -- Test tcsetattr with TCSADRAIN
    local ok, err = unix.tcsetattr(pty_fd, unix.TCSADRAIN, tio)
    assert(ok == true, "tcsetattr with TCSADRAIN should succeed: " .. tostring(err))

    -- Test tcsetattr with TCSAFLUSH
    local ok, err = unix.tcsetattr(pty_fd, unix.TCSAFLUSH, tio)
    assert(ok == true, "tcsetattr with TCSAFLUSH should succeed: " .. tostring(err))

    -- Test tcsetattr with partial table (missing fields default to 0)
    local ok, err = unix.tcsetattr(pty_fd, unix.TCSANOW, {lflag = unix.ICANON})
    assert(ok == true, "tcsetattr with partial table should succeed: " .. tostring(err))
  else
    print("tcgetattr on ptmx failed (may be expected in some environments): " .. tostring(err))
  end
  unix.close(pty_fd)
else
  print("skipping pty tests: could not open /dev/ptmx")
end

-- Test tcgetattr with invalid fd
local tio, err = unix.tcgetattr(999999)
assert(tio == nil, "tcgetattr on invalid fd should fail")
assert(err ~= nil, "tcgetattr should return error for invalid fd")

print("all tcattr tests passed")
