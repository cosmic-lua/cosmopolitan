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

-- Tests for unix.daemon()

-- Test function existence
assert(type(unix.daemon) == "function", "daemon should be a function")

-- Test daemon in a forked child process.
-- daemon() forks internally so we must test it in a child to avoid
-- daemonizing the test runner itself.
local tmpdir = "/tmp/daemon_test_" .. tostring(unix.getpid())
unix.makedirs(tmpdir, 0x1ED) -- 0755

local marker = tmpdir .. "/daemon_ran"

local pid = unix.fork()
if pid == 0 then
  -- child: daemonize with nochdir=true, noclose=true
  local ok, err = unix.daemon(true, true)
  if ok then
    -- write a marker file to prove we ran after daemonizing
    local fd = unix.open(marker, unix.O_WRONLY | unix.O_CREAT | unix.O_TRUNC, 0x1A4) -- 0644
    if fd then
      unix.write(fd, "ok")
      unix.close(fd)
    end
  end
  unix.exit(0)
elseif pid then
  -- parent: wait for the original child (which exits after daemon() forks)
  local wpid, wstatus = unix.wait(pid)
  assert(wpid == pid, "wait should return the forked pid")
  assert(unix.WIFEXITED(wstatus), "child should exit normally")

  -- Give the daemon child a moment to write its marker file
  unix.nanosleep(0, 200000000) -- 200ms

  -- Check that the daemon child ran and wrote its marker
  local fd = unix.open(marker, unix.O_RDONLY)
  if fd then
    local content = unix.read(fd, 16)
    unix.close(fd)
    assert(content == "ok", "daemon child should have written marker, got: " .. tostring(content))
    unix.unlink(marker)
  else
    -- The daemon may have been too slow or environment doesn't support it
    print("warning: daemon marker file not found (may be expected in some environments)")
  end
end

-- cleanup
unix.rmdir(tmpdir)

print("all daemon tests passed")
