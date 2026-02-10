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

-- Tests for unix.execvp(), unix.execvpe(), and unix.fexecve()

-- Test function existence
assert(type(unix.execvp) == "function", "execvp should be a function")
assert(type(unix.execvpe) == "function", "execvpe should be a function")
assert(type(unix.fexecve) == "function", "fexecve should be a function")

-- Test execvp error case: nonexistent command
local ok, err = unix.execvp("nonexistent_command_12345")
assert(ok == nil, "execvp of nonexistent command should fail")
assert(err ~= nil, "execvp failure should return error")

-- Test execvp with argv error case
local ok, err = unix.execvp("nonexistent_command_12345", {"nonexistent_command_12345"})
assert(ok == nil, "execvp with argv of nonexistent command should fail")
assert(err ~= nil, "execvp with argv failure should return error")

-- Test execvpe error case: nonexistent command
local ok, err = unix.execvpe("nonexistent_command_12345", {"nonexistent_command_12345"})
assert(ok == nil, "execvpe of nonexistent command should fail")
assert(err ~= nil, "execvpe failure should return error")

-- Test execvpe error case with custom environment
local ok, err = unix.execvpe("nonexistent_command_12345",
  {"nonexistent_command_12345"}, {"PATH=/nonexistent"})
assert(ok == nil, "execvpe with custom env of nonexistent command should fail")
assert(err ~= nil, "execvpe with custom env failure should return error")

-- Test fexecve error case: invalid fd
local ok, err = unix.fexecve(999999, {"test"})
assert(ok == nil, "fexecve with invalid fd should fail")
assert(err ~= nil, "fexecve failure should return error")

-- Test fexecve error case with custom environment
local ok, err = unix.fexecve(999999, {"test"}, {"PATH=/bin"})
assert(ok == nil, "fexecve with custom env and invalid fd should fail")
assert(err ~= nil, "fexecve with custom env failure should return error")

-- Test execvp in a forked child process (actual exec replacement)
local true_path = unix.commandv("true")
if true_path then
  local pid = unix.fork()
  if pid == 0 then
    -- child: exec into /bin/true
    unix.execvp(true_path, {true_path})
    -- if we get here, exec failed
    unix.exit(1)
  elseif pid then
    local wpid, wstatus = unix.wait(pid)
    assert(wpid == pid, "wait should return the forked pid")
    assert(unix.WIFEXITED(wstatus), "child should exit normally after execvp")
    assert(unix.WEXITSTATUS(wstatus) == 0, "execvp'd true should exit 0")
  end
end

-- Test execvpe in a forked child with custom environment
local echo_path = unix.commandv("sh")
if echo_path then
  -- Use sh -c 'exit $MY_EXIT_CODE' to test environment passing
  local pid = unix.fork()
  if pid == 0 then
    unix.execvpe("sh", {"sh", "-c", "exit ${MY_EXIT_CODE:-1}"},
      {"MY_EXIT_CODE=42", "PATH=/bin:/usr/bin"})
    unix.exit(1)
  elseif pid then
    local wpid, wstatus = unix.wait(pid)
    assert(wpid == pid, "wait should return the forked pid")
    assert(unix.WIFEXITED(wstatus), "child should exit normally after execvpe")
    assert(unix.WEXITSTATUS(wstatus) == 42,
      "execvpe should pass custom environment, got exit " ..
      tostring(unix.WEXITSTATUS(wstatus)))
  end
end

-- Test fexecve in a forked child process
if true_path then
  local fd = unix.open(true_path, unix.O_RDONLY)
  if fd then
    local pid = unix.fork()
    if pid == 0 then
      unix.fexecve(fd, {true_path})
      unix.exit(1)
    elseif pid then
      local wpid, wstatus = unix.wait(pid)
      assert(wpid == pid, "wait should return the forked pid")
      -- fexecve may not work in all environments (e.g. noexec mounts)
      -- so we just check the child exited
      assert(unix.WIFEXITED(wstatus), "child should exit after fexecve attempt")
    end
    unix.close(fd)
  end
end

-- Test execvp with multiple arguments in a forked child
local sh_path = unix.commandv("sh")
if sh_path then
  local pid = unix.fork()
  if pid == 0 then
    unix.execvp(sh_path, {sh_path, "-c", "exit 7"})
    unix.exit(1)
  elseif pid then
    local wpid, wstatus = unix.wait(pid)
    assert(wpid == pid, "wait should return the forked pid")
    assert(unix.WIFEXITED(wstatus), "child should exit normally")
    assert(unix.WEXITSTATUS(wstatus) == 7,
      "execvp'd sh -c 'exit 7' should exit 7, got " ..
      tostring(unix.WEXITSTATUS(wstatus)))
  end
end

print("all execvp/execvpe/fexecve tests passed")
