-- Copyright 2022 Justine Alexandra Roberts Tunney
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

local cosmo = require("cosmo")
local unix = require("cosmo.unix")

gotsigusr1 = false
tmpdir = "%s/o/tmp/lunix_test.%d" % {os.getenv('TMPDIR'), unix.getpid()}

function string.starts(String,Start)
   return string.sub(String,1,string.len(Start))==Start
end

function OnSigUsr1(sig)
   gotsigusr1 = true
end

function UnixTest()

   -- strsignal
   assert(unix.strsignal(9) == "SIGKILL")
   assert(unix.strsignal(unix.SIGKILL) == "SIGKILL")

   -- gmtime: success returns one table (tool/net/definitions.lua).
   local bdt = assert(unix.gmtime(1657297063))
   assert(bdt.year == 2022 and bdt.mon == 7 and bdt.mday == 8
     and bdt.hour == 16 and bdt.min == 17 and bdt.sec == 43
     and bdt.gmtoffsec == 0 and bdt.wday == 5 and bdt.yday == 188
     and bdt.dst == 0 and bdt.zone == "UTC")

   -- gmtime's one reachable failure (EOVERFLOW) is a clean nil, string,
   -- errno tuple now -- nothing shares a slot with a BrokenDownTime field.
   local goy, gerr, geno = unix.gmtime(9223372036854775807)
   assert(goy == nil, "gmtime of an unrepresentable timestamp must report nil")
   assert(type(gerr) == "string", "the error must be a string")
   assert(geno == unix.EOVERFLOW, "errno must be EOVERFLOW")

   -- dup
   -- 1. duplicate stderr as lowest available fd
   -- 1. close the newly assigned file descriptor
   fd = assert(unix.dup(2))
   assert(unix.close(fd))

   -- dup2
   -- 1. duplicate stderr as fd 10
   -- 1. close the new file descriptor
   assert(assert(unix.dup(2, 10)) == 10)
   assert(unix.close(10))

   -- fork
   -- basic subprocess creation
   if assert(unix.fork()) == 0 then
      assert(unix.pledge(""))
      unix.exit(42)
   end
   pid, ws = assert(unix.wait())
   assert(unix.WIFEXITED(ws))
   assert(unix.WEXITSTATUS(ws) == 42)

   -- pledge
   -- 1. fork off a process
   -- 2. sandbox the process
   -- 3. then violate its security
   if unix.pledge(nil, nil) then
       reader, writer = assert(unix.pipe())
       if assert(unix.fork()) == 0 then
           assert(unix.dup(writer, 2))
           assert(unix.pledge("stdio"))
           unix.socket()
           unix.exit(0)
       end
       unix.close(writer)
       unix.close(reader)
       pid, ws = assert(unix.wait())
       assert(unix.WIFSIGNALED(ws))
       assert(unix.WTERMSIG(ws) == unix.SIGSYS or  -- Linux
              unix.WTERMSIG(ws) == unix.SIGABRT)   -- OpenBSD
   end

   -- sigaction
   -- 1. install a signal handler for USR1
   -- 2. block USR1
   -- 3. trigger USR1 signal [it gets enqueued]
   -- 4. pause() w/ atomic unblocking of USR1 [now it gets delivered!]
   -- 5. restore old signal mask
   -- 6. restore old sig handler
   oldhand, oldflags, oldmask = assert(unix.sigaction(unix.SIGUSR1, OnSigUsr1))
   oldmask = assert(unix.sigprocmask(unix.SIG_BLOCK, unix.sigset(unix.SIGUSR1)))
   assert(unix.raise(unix.SIGUSR1))
   assert(not gotsigusr1)
   ok, err, errno = unix.sigsuspend(oldmask)
   assert(not ok)
   assert(errno == unix.EINTR)
   assert(gotsigusr1)
   assert(unix.sigprocmask(unix.SIG_SETMASK, oldmask))
   assert(unix.sigaction(unix.SIGUSR1, oldhand, oldflags, oldmask))

   -- open
   -- 1. create file
   -- 2. fill it up
   -- 3. inspect it
   -- 4. mess with it
   fd = assert(unix.open("%s/foo" % {tmpdir}, unix.O_RDWR | unix.O_CREAT | unix.O_TRUNC, 0600))
   assert(assert(unix.fstat(fd)):size() == 0)
   assert(unix.ftruncate(fd, 8192))
   assert(assert(unix.fstat(fd)):size() == 8192)
   assert(unix.write(fd, "hello"))
   assert(unix.lseek(fd, 4096))
   assert(unix.write(fd, "poke"))
   assert(unix.lseek(fd, 8192-4))
   assert(unix.write(fd, "poke"))
   st = assert(unix.fstat(fd))
   assert(st:size() == 8192)
   assert(st:blocks() == 8192/512)
   assert((st:mode() & 0700) == 0600)
   assert(st:uid() == unix.getuid())
   assert(st:gid() == unix.getgid())
   assert(unix.write(fd, "bear", 4))
   assert(unix.read(fd, 10, 0) == "hellbear\x00\x00")
   assert(unix.close(fd))
   fd = assert(unix.open("%s/foo" % {tmpdir}))
   assert(unix.lseek(fd, 4))
   assert(unix.read(fd, 4) == "bear")
   assert(unix.close(fd))
   fd = assert(unix.open("%s/foo" % {tmpdir}, unix.O_RDWR))
   assert(unix.write(fd, "bear"))
   assert(unix.close(fd))
   fd = assert(unix.open("%s/foo" % {tmpdir}))
   assert(unix.read(fd, 8) == "bearbear")
   assert(unix.close(fd))

   -- copy_file_range: kernel-side fd-to-fd copy, offsets advance like
   -- read+write; ENOSYS on platforms without the syscall keeps callers
   -- on their fallback, so both outcomes are legitimate here
   fd = assert(unix.open("%s/cfr_src" % {tmpdir}, unix.O_RDWR | unix.O_CREAT | unix.O_TRUNC, 0600))
   assert(unix.write(fd, "0123456789abcdef"))
   assert(unix.lseek(fd, 0))
   fd2 = assert(unix.open("%s/cfr_dst" % {tmpdir}, unix.O_RDWR | unix.O_CREAT | unix.O_TRUNC, 0600))
   copied, cfrerr, cfrerrno = unix.copy_file_range(fd, fd2, 16)
   if copied then
      -- short copies are legal; drain the rest
      local total = copied
      while total < 16 do
         local n = assert(unix.copy_file_range(fd, fd2, 16 - total))
         assert(n > 0)
         total = total + n
      end
      assert(total == 16)
      -- both offsets advanced: src at EOF now, so another copy reads 0
      assert(unix.copy_file_range(fd, fd2, 16) == 0)
      assert(unix.read(fd2, 16, 0) == "0123456789abcdef")
   else
      assert(cfrerrno == unix.ENOSYS)
   end
   assert(unix.close(fd))
   assert(unix.close(fd2))

   -- getdents
   t = {}
   for name, kind, ino, off in assert(unix.opendir(tmpdir)) do
      table.insert(t, name)
   end
   table.sort(t)
   assert(cosmo.EncodeLua(t) == '{".", "..", "cfr_dst", "cfr_src", "foo"}');

end

function main()
   -- capget: success returns one table (effective/permitted/inheritable
   -- all present, none nil); failure returns nil, error:str, errno:int.
   -- The two branches must not share a positional slot for unrelated
   -- meanings. Runs before pledge() below, since capget isn't in any
   -- promise this test asks for.
   caps = assert(unix.capget())
   assert(type(caps) == "table")
   assert(type(caps.effective) == "number")
   assert(type(caps.permitted) == "number")
   assert(type(caps.inheritable) == "number")
   badcaps, caperr, caperrno = unix.capget(999999)
   assert(badcaps == nil)
   assert(type(caperr) == "string")
   assert(caperrno == unix.ESRCH)

   assert(unix.makedirs(tmpdir))
   unix.unveil(tmpdir, "rwc")
   unix.unveil(nil, nil)
   assert(unix.pledge("stdio rpath wpath cpath proc"))
   ok, err = pcall(UnixTest)
   if ok then
      assert(unix.rmrf(tmpdir))
   else
      print(err)
      error('UnixTest failed (%s)' % {tmpdir})
   end
end

main()
