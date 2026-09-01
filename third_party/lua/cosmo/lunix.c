/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2021 Justine Alexandra Roberts Tunney                              │
│                                                                              │
│ Permission to use, copy, modify, and/or distribute this software for         │
│ any purpose with or without fee is hereby granted, provided that the         │
│ above copyright notice and this permission notice appear in all copies.      │
│                                                                              │
│ THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL                │
│ WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED                │
│ WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE             │
│ AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL         │
│ DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR        │
│ PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER               │
│ TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR             │
│ PERFORMANCE OF THIS SOFTWARE.                                                │
╚─────────────────────────────────────────────────────────────────────────────*/
#include "third_party/lua/cosmo/lunix.h"
#include "libc/assert.h"
#include "libc/atomic.h"
#include "libc/calls/calls.h"
#include "libc/calls/cap.h"
#include "libc/calls/cp.internal.h"
#include "libc/calls/landlock.h"
#include "libc/calls/makedev.h"
#include "libc/calls/mount.h"
#include "libc/calls/pledge.h"
#include "libc/calls/struct/bpf.internal.h"
#include "libc/calls/struct/dirent.h"
#include "libc/calls/struct/flock.h"
#include "libc/calls/struct/itimerval.h"
#include "libc/calls/struct/rlimit.h"
#include "libc/calls/struct/rusage.h"
#include "libc/calls/struct/sigaction.h"
#include "libc/calls/struct/siginfo.h"
#include "libc/calls/struct/sigset.h"
#include "libc/calls/struct/stat.h"
#include "libc/calls/struct/statfs.h"
#include "libc/calls/struct/timespec.h"
#include "libc/calls/struct/timeval.h"
#include "libc/calls/struct/utsname.h"
#include "libc/calls/struct/winsize.h"
#include "libc/calls/ucontext.h"
#include "libc/calls/weirdtypes.h"
#include "libc/dce.h"
#include "libc/errno.h"
#include "libc/fmt/conv.h"
#include "libc/fmt/itoa.h"
#include "libc/fmt/magnumstrs.internal.h"
#include "libc/intrin/atomic.h"
#include "libc/serialize.h"
#include "libc/intrin/strace.h"
#include "libc/limits.h"
#include "libc/log/log.h"
#include "libc/macros.h"
#include "libc/mem/mem.h"
#include "libc/nt/process.h"
#include "libc/nt/runtime.h"
#include "libc/nt/synchronization.h"
#include "libc/runtime/clktck.h"
#include "libc/runtime/runtime.h"
#include "libc/runtime/sysconf.h"
#include "libc/sock/sock.h"
#include "libc/sock/struct/ifconf.h"
#include "libc/sock/struct/linger.h"
#include "libc/sock/struct/pollfd.h"
#include "libc/sock/struct/sockaddr.h"
#include "libc/sock/syslog.h"
#include "libc/stdio/append.h"
#include "libc/stdio/stdio.h"
#include "libc/str/str.h"
#include "libc/temp.h"
#include "libc/sysv/consts/af.h"
#include "libc/sysv/consts/at.h"
#include "libc/sysv/consts/cap.h"
#include "libc/sysv/consts/clock.h"
#include "libc/sysv/consts/clone.h"
#include "libc/sysv/consts/dt.h"
#include "libc/sysv/consts/f.h"
#include "libc/sysv/consts/iff.h"
#include "libc/sysv/consts/ip.h"
#include "libc/sysv/consts/ipproto.h"
#include "libc/sysv/consts/itimer.h"
#include "libc/sysv/consts/limits.h"
#include "libc/sysv/consts/log.h"
#include "libc/sysv/consts/map.h"
#include "libc/sysv/consts/mount.h"
#include "libc/sysv/consts/msg.h"
#include "libc/sysv/consts/nr.h"
#include "libc/sysv/consts/o.h"
#include "libc/sysv/consts/ok.h"
#include "libc/sysv/consts/poll.h"
#include "libc/sysv/consts/pr.h"
#include "libc/sysv/consts/prio.h"
#include "libc/sysv/consts/prot.h"
#include "libc/calls/struct/rlimit.h"
#include "libc/sysv/consts/rusage.h"
#include "libc/sysv/consts/s.h"
#include "libc/sysv/consts/sa.h"
#include "libc/sysv/consts/shut.h"
#include "libc/sysv/consts/sig.h"
#include "libc/sysv/consts/sio.h"
#include "libc/sysv/consts/so.h"
#include "libc/sysv/consts/sock.h"
#include "libc/sysv/consts/sol.h"
#include "libc/sysv/consts/st.h"
#include "libc/sysv/consts/tcp.h"
#include "libc/sysv/consts/termios.h"
#include "libc/sysv/consts/unmount.h"
#include "libc/calls/termios.h"
#include "libc/sysv/consts/utime.h"
#include "libc/proc/posix_spawn.h"
#include "libc/sysv/consts/w.h"
#include "libc/sysv/errfuns.h"
#include "libc/thread/thread.h"
#include "libc/time.h"
#include "libc/x/x.h"
#include "third_party/lua/cosmo/cosmo.h"
#include "third_party/lua/lauxlib.h"
#include "third_party/lua/lgc.h"
#include "third_party/lua/lua.h"
#include "third_party/lua/luaconf.h"
#include "libc/sysv/consts/clock.h"
#include "libc/cosmo.h"
#include "libc/cosmo.h"
#include "libc/cosmotime.h"
#include "tool/net/luacheck.h"

#define DNS_NAME_MAX  253

/**
 * @fileoverview UNIX system calls thinly wrapped for Lua
 * @support Linux, Mac, Windows, FreeBSD, NetBSD, OpenBSD
 */

static lua_State *GL;

static void *LuaRealloc(lua_State *L, void *p, size_t n) {
  void *p2;
  if ((p2 = realloc(p, n))) {
    return p2;
  }
  if (n < 0x100000000000) {
    WARNF("reacting to malloc() failure by running lua garbage collector...");
    luaC_fullgc(L, 1);
    if ((p2 = realloc(p, n)))
      return p2;
  }
  return p;
}

static void *LuaAlloc(lua_State *L, size_t n) {
  return LuaRealloc(L, 0, n);
}

static void *LuaAllocOrDie(lua_State *L, size_t n) {
  void *p;
  if ((p = LuaAlloc(L, n))) {
    return p;
  } else {
    luaL_error(L, "out of memory");
    __builtin_unreachable();
  }
}

static lua_Integer FixLimit(long x) {
  if (0 <= x && x < RLIM_INFINITY) {
    return x;
  } else {
    return -1;
  }
}

static void LuaPushSigset(lua_State *L, sigset_t set) {
  sigset_t *sp = lua_newuserdatauv(L, sizeof(*sp), 1);
  luaL_setmetatable(L, "unix.Sigset");
  *sp = set;
}

static void LuaPushStat(lua_State *L, struct stat *st) {
  struct stat *stp = lua_newuserdatauv(L, sizeof(*stp), 1);
  luaL_setmetatable(L, "unix.Stat");
  *stp = *st;
}

static void LuaPushStatfs(lua_State *L, struct statfs *st) {
  struct statfs *stp = lua_newuserdatauv(L, sizeof(*stp), 1);
  luaL_setmetatable(L, "unix.Statfs");
  *stp = *st;
}

static void LuaPushRusage(lua_State *L, struct rusage *set) {
  struct rusage *sp = lua_newuserdatauv(L, sizeof(*sp), 1);
  luaL_setmetatable(L, "unix.Rusage");
  *sp = *set;
}

static void LuaSetIntField(lua_State *L, const char *k, lua_Integer v) {
  lua_pushinteger(L, v);
  lua_setfield(L, -2, k);
}

static dontinline int ReturnInteger(lua_State *L, lua_Integer x) {
  lua_pushinteger(L, x);
  return 1;
}

static dontinline int ReturnBoolean(lua_State *L, int x) {
  lua_pushboolean(L, !!x);
  return 1;
}

static dontinline int ReturnString(lua_State *L, const char *x) {
  lua_pushstring(L, x);
  return 1;
}

int LuaUnixSysretErrno(lua_State *L, const char *call, int olderr) {
  char msg[256];
  int unixerr;
  unixerr = errno;
  if (!IsTiny() && !(0 < unixerr && unixerr < (!IsWindows() ? 4096 : 65536))) {
    WARNF("errno should not be %d", unixerr);
  }
  // The fork's error convention: nil, err:string, errno:integer. The
  // string reuses the old unix.Errno __tostring formatting, e.g.
  // "open: ENOENT: No such file or directory" (call, symbolic name,
  // description). The integer errno is pushed as a third value so
  // callers can branch on specific codes (EINTR, EAGAIN, ...) without
  // parsing the string.
  strerror_r(unixerr, msg, sizeof(msg));
  lua_pushnil(L);
  lua_pushfstring(L, "%s: %s: %s", call, _strerrno(unixerr), msg);
  lua_pushinteger(L, unixerr);
  errno = olderr;
  return 3;
}

static int SysretBool(lua_State *L, const char *call, int olderr, int rc) {
  if (!IsTiny() && (rc != 0 && rc != -1))
    WARNF("syscall supposed to return 0 / -1 but got %d", rc);
  if (rc != -1) {
    lua_pushboolean(L, true);
    return 1;
  } else {
    return LuaUnixSysretErrno(L, call, olderr);
  }
}

static int SysretInteger(lua_State *L, const char *call, int olderr,
                         int64_t rc) {
  if (rc != -1) {
    if (!IsTiny() && olderr != errno) {
      WARNF("errno unexpectedly changed %d → %d", olderr, errno);
    }
    lua_pushinteger(L, rc);
    return 1;
  } else {
    return LuaUnixSysretErrno(L, call, olderr);
  }
}

static int MakeSockaddr(lua_State *L, int i, struct sockaddr_storage *ss,
                        uint32_t *salen) {
  bzero(ss, sizeof(*ss));
  if (!lua_isinteger(L, i)) {
    ((struct sockaddr_un *)ss)->sun_family = AF_UNIX;
    if (!memccpy(((struct sockaddr_un *)ss)->sun_path, luaL_checkstring(L, i),
                 0, sizeof(((struct sockaddr_un *)ss)->sun_path))) {
      luaL_error(L, "unix path too long");
      __builtin_unreachable();
    }
    *salen = sizeof(struct sockaddr_un);
    return i + 1;
  } else {
    ((struct sockaddr_in *)ss)->sin_family = AF_INET;
    ((struct sockaddr_in *)ss)->sin_addr.s_addr =
        htonl(luaL_optinteger(L, i, 0));
    ((struct sockaddr_in *)ss)->sin_port = htons(luaL_optinteger(L, i + 1, 0));
    *salen = sizeof(struct sockaddr_in);
    return i + 2;
  }
}

static int PushSockaddr(lua_State *L, const struct sockaddr_storage *ss) {
  if (ss->ss_family == AF_INET) {
    lua_pushinteger(L,
                    ntohl(((const struct sockaddr_in *)ss)->sin_addr.s_addr));
    lua_pushinteger(L, ntohs(((const struct sockaddr_in *)ss)->sin_port));
    return 2;
  } else if (ss->ss_family == AF_UNIX) {
    lua_pushstring(L, ((const struct sockaddr_un *)ss)->sun_path);
    return 1;
  } else {
    luaL_error(L, "bad family");
    __builtin_unreachable();
  }
}

static void CheckOptvalsize(lua_State *L, uint32_t want, uint32_t got) {
  if (!IsTiny()) {
    if (want == got) return;
    WARNF("getsockopt optvalsize should be %d but was %d", want, got);
  }
}

static void FreeStringList(char **p) {
  int i;
  if (p) {
    for (i = 0; p[i]; ++i) {
      free(p[i]);
    }
    free(p);
  }
}

static char **ConvertLuaArrayToStringList(lua_State *L, int i) {
  int j, n;
  char **p, *s;
  const char *str;
  luaL_checktype(L, i, LUA_TTABLE);
  lua_len(L, i);
  n = lua_tointeger(L, -1);
  lua_pop(L, 1);
  if ((p = LuaAlloc(L, (n + 1) * sizeof(*p)))) {
    // NUL-terminate every slot up front so FreeStringList() is safe to
    // call on the partially-filled array below: LuaAlloc() doesn't
    // zero memory, and freeing an early failure would otherwise walk
    // uninitialized heap past the converted prefix.
    memset(p, 0, (n + 1) * sizeof(*p));
    for (j = 1; j <= n; ++j) {
      lua_geti(L, i, j);
      if ((str = lua_tostring(L, -1))) {
        s = strdup(str);
      } else {
        s = 0;
      }
      lua_pop(L, 1);
      if (s) {
        p[j - 1] = s;
      } else {
        FreeStringList(p);
        p = 0;
        break;
      }
    }
    if (p)
      p[j - 1] = 0;
  }
  return p;
}

////////////////////////////////////////////////////////////////////////////////
// System Calls

// unix.exit([exitcode:int])
//     └─→ ⊥
static wontreturn int LuaUnixExit(lua_State *L) {
  _Exit(luaL_optinteger(L, 1, 0));
}

static dontinline int LuaUnixGetid(lua_State *L, int f(void)) {
  return ReturnInteger(L, f());
}

static dontinline int LuaUnixGetUnsignedid(lua_State *L, unsigned f(void)) {
  return ReturnInteger(L, f());
}

// unix.getpid()
//     └─→ pid:int
static int LuaUnixGetpid(lua_State *L) {
  return LuaUnixGetid(L, getpid);
}

// unix.getppid()
//     └─→ pid:int
static int LuaUnixGetppid(lua_State *L) {
  return LuaUnixGetid(L, getppid);
}

// unix.getuid()
//     └─→ uid:int
static int LuaUnixGetuid(lua_State *L) {
  return LuaUnixGetUnsignedid(L, getuid);
}

// unix.getgid()
//     └─→ gid:int
static int LuaUnixGetgid(lua_State *L) {
  return LuaUnixGetUnsignedid(L, getgid);
}

// unix.geteuid()
//     └─→ uid:int
static int LuaUnixGeteuid(lua_State *L) {
  return LuaUnixGetUnsignedid(L, geteuid);
}

// unix.getegid()
//     └─→ gid:int
static int LuaUnixGetegid(lua_State *L) {
  return LuaUnixGetUnsignedid(L, getegid);
}

// unix.umask(newmask:int)
//     └─→ oldmask:int
static int LuaUnixUmask(lua_State *L) {
  return ReturnInteger(L, umask(luaL_checkinteger(L, 1)));
}

// unix.access(path:str, how:int[, flags:int[, dirfd:int]])
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixAccess(lua_State *L) {
  int olderr = errno;
  return SysretBool(
      L, "access", olderr,
      faccessat(luaL_optinteger(L, 3, AT_FDCWD), luaL_checkstring(L, 1),
                luaL_checkinteger(L, 2), luaL_optinteger(L, 4, 0)));
}

// unix.mkdir(path:str[, mode:int[, dirfd:int]])
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixMkdir(lua_State *L) {
  int olderr = errno;
  return SysretBool(
      L, "mkdir", olderr,
      mkdirat(luaL_optinteger(L, 3, AT_FDCWD), luaL_checkstring(L, 1),
              luaL_optinteger(L, 2, 0755)));
}

// unix.makedirs(path:str[, mode:int])
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixMakedirs(lua_State *L) {
  int olderr = errno;
  return SysretBool(
      L, "makedirs", olderr,
      makedirs(luaL_checkstring(L, 1), luaL_optinteger(L, 2, 0755)));
}

// unix.rmrf(path:str)
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixRmrf(lua_State *L) {
  int olderr = errno;
  return SysretBool(L, "rmrf", olderr, rmrf(luaL_checkstring(L, 1)));
}

// unix.chdir(path:str)
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixChdir(lua_State *L) {
  int olderr = errno;
  return SysretBool(L, "chdir", olderr, chdir(luaL_checkstring(L, 1)));
}

// unix.unlink(path:str[, dirfd:int])
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixUnlink(lua_State *L) {
  int olderr = errno;
  return SysretBool(
      L, "unlink", olderr,
      unlinkat(luaL_optinteger(L, 2, AT_FDCWD), luaL_checkstring(L, 1), 0));
}

// unix.rmdir(path:str[, dirfd:int])
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixRmdir(lua_State *L) {
  int olderr = errno;
  return SysretBool(L, "rmdir", olderr,
                    unlinkat(luaL_optinteger(L, 2, AT_FDCWD),
                             luaL_checkstring(L, 1), AT_REMOVEDIR));
}

// unix.rename(oldpath:str, newpath:str[, olddirfd:int, newdirfd:int])
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixRename(lua_State *L) {
  int olderr = errno;
  return SysretBool(
      L, "rename", olderr,
      renameat(luaL_optinteger(L, 3, AT_FDCWD), luaL_checkstring(L, 1),
               luaL_optinteger(L, 4, AT_FDCWD), luaL_checkstring(L, 2)));
}

// unix.link(existingpath:str, newpath:str[, flags:int[, olddirfd, newdirfd]])
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixLink(lua_State *L) {
  int olderr = errno;
  return SysretBool(
      L, "link", olderr,
      linkat(luaL_optinteger(L, 4, AT_FDCWD), luaL_checkstring(L, 1),
             luaL_optinteger(L, 5, AT_FDCWD), luaL_checkstring(L, 2),
             luaL_optinteger(L, 3, 0)));
}

// unix.symlink(target:str, linkpath:str[, newdirfd:int])
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixSymlink(lua_State *L) {
  int olderr = errno;
  return SysretBool(
      L, "symlink", olderr,
      symlinkat(luaL_checkstring(L, 1), luaL_optinteger(L, 3, AT_FDCWD),
                luaL_checkstring(L, 2)));
}

// unix.chown(path:str, uid:int, gid:int[, flags:int[, dirfd:int]])
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixChown(lua_State *L) {
  int olderr = errno;
  return SysretBool(
      L, "chown", olderr,
      fchownat(luaL_optinteger(L, 5, AT_FDCWD), luaL_checkstring(L, 1),
               luaL_checkinteger(L, 2), luaL_checkinteger(L, 3),
               luaL_optinteger(L, 4, 0)));
}

// unix.chmod(path:str, mode:int[, flags:int[, dirfd:int]])
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixChmod(lua_State *L) {
  int olderr = errno;
  return SysretBool(
      L, "chmod", olderr,
      fchmodat(luaL_optinteger(L, 4, AT_FDCWD), luaL_checkstring(L, 1),
               luaL_checkinteger(L, 2), luaL_optinteger(L, 3, 0)));
}

// unix.readlink(path:str[, bufsiz:int])
//     ├─→ content:str
//     └─→ nil, error:str, errno:int
//
// Note: this fork changed arg 2 from a dirfd (upstream) to a buffer size;
// AT_FDCWD is always used.  bufsiz is clamped to [1, 0x7ffff000].
static int LuaUnixReadlink(lua_State *L) {
  size_t got;
  ssize_t rc;
  luaL_Buffer lb;
  int olderr = errno;
  lua_Integer bufsiz = luaL_optinteger(L, 2, BUFSIZ);
  if (bufsiz <= 0) bufsiz = BUFSIZ;
  if (bufsiz > 0x7ffff000) bufsiz = 0x7ffff000;
  if ((rc = readlinkat(AT_FDCWD, luaL_checkstring(L, 1),
                       luaL_buffinitsize(L, &lb, bufsiz), bufsiz)) != -1) {
    if ((got = rc) < bufsiz) {
      luaL_pushresultsize(&lb, got);
      return 1;
    } else {
      enametoolong();
    }
  }
  return LuaUnixSysretErrno(L, "readlink", olderr);
}

// unix.getcwd()
//     ├─→ path:str
//     └─→ nil, error:str, errno:int
static int LuaUnixGetcwd(lua_State *L) {
  char *path;
  int olderr = errno;
  if ((path = getcwd(0, 0))) {
    lua_pushstring(L, path);
    free(path);
    return 1;
  } else {
    return LuaUnixSysretErrno(L, "getcwd", olderr);
  }
}

// unix.fork()
//     ├─┬─→ 0
//     │ └─→ childpid:int
//     └─→ nil, error:str, errno:int
static int LuaUnixFork(lua_State *L) {
  int olderr = errno;
  return SysretInteger(L, "fork", olderr, fork());
}

// unix.environ()
//     └─→ {str,...}
static int LuaUnixEnviron(lua_State *L) {
  int i;
  char **e;
  lua_newtable(L);
  if (environ) {
    for (i = 0, e = environ; *e; ++e) {
      lua_pushstring(L, *e);
      lua_rawseti(L, -2, ++i);
    }
  }
  return 1;
}

// unix.setenv(name:str, value:str[, overwrite:bool])
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixSetenv(lua_State *L) {
  int olderr = errno;
  const char *name = luaL_checkstring(L, 1);
  const char *value = luaL_checkstring(L, 2);
  int overwrite = lua_isnoneornil(L, 3) ? 1 : lua_toboolean(L, 3);
  return SysretBool(L, "setenv", olderr, setenv(name, value, overwrite));
}

// unix.unsetenv(name:str)
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixUnsetenv(lua_State *L) {
  int olderr = errno;
  const char *name = luaL_checkstring(L, 1);
  return SysretBool(L, "unsetenv", olderr, unsetenv(name));
}

// unix.clearenv()
//     └─→ true
static int LuaUnixClearenv(lua_State *L) {
  clearenv();
  lua_pushboolean(L, 1);
  return 1;
}

// unix.getlogin()
//     ├─→ str
//     └─→ nil, error:str, errno:int
static int LuaUnixGetlogin(lua_State *L) {
  int olderr = errno;
  char *login = getlogin();
  if (login) {
    lua_pushstring(L, login);
    return 1;
  } else {
    return LuaUnixSysretErrno(L, "getlogin", olderr);
  }
}

// unix.execve(prog:str[, args:List<*>, env:List<*>])
//     └─→ nil, error:str, errno:int
static int LuaUnixExecve(lua_State *L) {
  int olderr;
  const char *prog;
  char **argv, **envp, **freeme1, **freeme2, *ezargs[2];
  olderr = errno;
  prog = luaL_checkstring(L, 1);
  if (!lua_isnoneornil(L, 2)) {
    if ((argv = ConvertLuaArrayToStringList(L, 2))) {
      freeme1 = argv;
      if (!lua_isnoneornil(L, 3)) {
        if ((envp = ConvertLuaArrayToStringList(L, 3))) {
          freeme2 = envp;
        } else {
          FreeStringList(argv);
          return LuaUnixSysretErrno(L, "execve", olderr);
        }
      } else {
        envp = environ;
        freeme2 = 0;
      }
    } else {
      return LuaUnixSysretErrno(L, "execve", olderr);
    }
  } else {
    ezargs[0] = (char *)prog;
    ezargs[1] = 0;
    argv = ezargs;
    envp = environ;
    freeme1 = 0;
    freeme2 = 0;
  }
  execve(prog, argv, envp);
  FreeStringList(freeme1);
  FreeStringList(freeme2);
  return LuaUnixSysretErrno(L, "execve", olderr);
}

// unix.execvp(prog:str[, argv:table])
//     ├─→ ⊥
//     └─→ nil, error:str, errno:int
static int LuaUnixExecvp(lua_State *L) {
  int olderr;
  const char *prog;
  char **argv, **freeme, *ezargs[2];
  olderr = errno;
  prog = luaL_checkstring(L, 1);
  if (!lua_isnoneornil(L, 2)) {
    if ((argv = ConvertLuaArrayToStringList(L, 2))) {
      freeme = argv;
    } else {
      return LuaUnixSysretErrno(L, "execvp", olderr);
    }
  } else {
    ezargs[0] = (char *)prog;
    ezargs[1] = 0;
    argv = ezargs;
    freeme = 0;
  }
  execvp(prog, argv);
  FreeStringList(freeme);
  return LuaUnixSysretErrno(L, "execvp", olderr);
}

// unix.execvpe(prog:str, argv:table[, envp:table])
//     ├─→ ⊥
//     └─→ nil, error:str, errno:int
static int LuaUnixExecvpe(lua_State *L) {
  int olderr;
  const char *prog;
  char **argv, **envp, **freeme1, **freeme2;
  olderr = errno;
  prog = luaL_checkstring(L, 1);
  if ((argv = ConvertLuaArrayToStringList(L, 2))) {
    freeme1 = argv;
    if (!lua_isnoneornil(L, 3)) {
      if ((envp = ConvertLuaArrayToStringList(L, 3))) {
        freeme2 = envp;
      } else {
        FreeStringList(argv);
        return LuaUnixSysretErrno(L, "execvpe", olderr);
      }
    } else {
      envp = environ;
      freeme2 = 0;
    }
  } else {
    return LuaUnixSysretErrno(L, "execvpe", olderr);
  }
  execvpe(prog, argv, envp);
  FreeStringList(freeme1);
  FreeStringList(freeme2);
  return LuaUnixSysretErrno(L, "execvpe", olderr);
}

// unix.fexecve(fd:int, argv:table[, envp:table])
//     ├─→ ⊥
//     └─→ nil, error:str, errno:int
static int LuaUnixFexecve(lua_State *L) {
  int olderr, fd;
  char **argv, **envp, **freeme1, **freeme2;
  olderr = errno;
  fd = luaL_checkinteger(L, 1);
  if ((argv = ConvertLuaArrayToStringList(L, 2))) {
    freeme1 = argv;
    if (!lua_isnoneornil(L, 3)) {
      if ((envp = ConvertLuaArrayToStringList(L, 3))) {
        freeme2 = envp;
      } else {
        FreeStringList(argv);
        return LuaUnixSysretErrno(L, "fexecve", olderr);
      }
    } else {
      envp = environ;
      freeme2 = 0;
    }
  } else {
    return LuaUnixSysretErrno(L, "fexecve", olderr);
  }
  fexecve(fd, argv, envp);
  FreeStringList(freeme1);
  FreeStringList(freeme2);
  return LuaUnixSysretErrno(L, "fexecve", olderr);
}

// unix.spawn(prog:str, argv:table[, envp:table])
//     ├─→ pid:int
//     └─→ nil, error:str, errno:int
static int LuaUnixSpawn(lua_State *L) {
  int olderr, rc;
  pid_t pid;
  const char *prog;
  char **argv, **envp, **freeme1, **freeme2;
  posix_spawn_file_actions_t fa;
  posix_spawnattr_t sa;
  olderr = errno;
  prog = luaL_checkstring(L, 1);
  if ((argv = ConvertLuaArrayToStringList(L, 2))) {
    freeme1 = argv;
    if (!lua_isnoneornil(L, 3)) {
      if ((envp = ConvertLuaArrayToStringList(L, 3))) {
        freeme2 = envp;
      } else {
        FreeStringList(argv);
        return LuaUnixSysretErrno(L, "spawn", olderr);
      }
    } else {
      envp = environ;
      freeme2 = 0;
    }
  } else {
    return LuaUnixSysretErrno(L, "spawn", olderr);
  }
  posix_spawn_file_actions_init(&fa);
  posix_spawnattr_init(&sa);
  posix_spawnattr_setflags(&sa, POSIX_SPAWN_USEVFORK);
  rc = posix_spawn(&pid, prog, &fa, &sa, argv, envp);
  posix_spawnattr_destroy(&sa);
  posix_spawn_file_actions_destroy(&fa);
  FreeStringList(freeme1);
  FreeStringList(freeme2);
  if (rc == 0) {
    lua_pushinteger(L, pid);
    return 1;
  } else {
    errno = rc;
    return LuaUnixSysretErrno(L, "spawn", olderr);
  }
}

// unix.spawnp(prog:str, argv:table[, envp:table])
//     ├─→ pid:int
//     └─→ nil, error:str, errno:int
static int LuaUnixSpawnp(lua_State *L) {
  int olderr, rc;
  pid_t pid;
  const char *prog;
  char **argv, **envp, **freeme1, **freeme2;
  posix_spawn_file_actions_t fa;
  posix_spawnattr_t sa;
  olderr = errno;
  prog = luaL_checkstring(L, 1);
  if ((argv = ConvertLuaArrayToStringList(L, 2))) {
    freeme1 = argv;
    if (!lua_isnoneornil(L, 3)) {
      if ((envp = ConvertLuaArrayToStringList(L, 3))) {
        freeme2 = envp;
      } else {
        FreeStringList(argv);
        return LuaUnixSysretErrno(L, "spawnp", olderr);
      }
    } else {
      envp = environ;
      freeme2 = 0;
    }
  } else {
    return LuaUnixSysretErrno(L, "spawnp", olderr);
  }
  posix_spawn_file_actions_init(&fa);
  posix_spawnattr_init(&sa);
  posix_spawnattr_setflags(&sa, POSIX_SPAWN_USEVFORK);
  rc = posix_spawnp(&pid, prog, &fa, &sa, argv, envp);
  posix_spawnattr_destroy(&sa);
  posix_spawn_file_actions_destroy(&fa);
  FreeStringList(freeme1);
  FreeStringList(freeme2);
  if (rc == 0) {
    lua_pushinteger(L, pid);
    return 1;
  } else {
    errno = rc;
    return LuaUnixSysretErrno(L, "spawnp", olderr);
  }
}

// unix.commandv(prog:str)
//     ├─→ path:str
//     └─→ nil, error:str, errno:int
static int LuaUnixCommandv(lua_State *L) {
  int olderr;
  const char *prog;
  char *pathbuf, *resolved;
  olderr = errno;
  prog = luaL_checkstring(L, 1);
  pathbuf = LuaAllocOrDie(L, PATH_MAX);
  if ((resolved = commandv(prog, pathbuf, PATH_MAX))) {
    lua_pushstring(L, resolved);
    free(pathbuf);
    return 1;
  } else {
    free(pathbuf);
    return LuaUnixSysretErrno(L, "commandv", olderr);
  }
}

// unix.realpath(path:str)
//     ├─→ path:str
//     └─→ nil, error:str, errno:int
static int LuaUnixRealpath(lua_State *L) {
  char *resolved;
  int olderr;
  const char *path;
  olderr = errno;
  path = luaL_checkstring(L, 1);
  if ((resolved = realpath(path, 0))) {
    lua_pushstring(L, resolved);
    free(resolved);
    return 1;
  } else {
    return LuaUnixSysretErrno(L, "realpath", olderr);
  }
}

// unix.syslog(priority:str, msg:str)
static int LuaUnixSyslog(lua_State *L) {
  syslog(luaL_checkinteger(L, 1), "%s", luaL_checkstring(L, 2));
  return 0;
}

// unix.chroot(path:str)
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixChroot(lua_State *L) {
  int olderr = errno;
  return SysretBool(L, "chroot", olderr, chroot(luaL_checkstring(L, 1)));
}

// unix.unshare(flags:int)
//     ├─→ true
//     └─→ nil, error:str, errno:int
//
// Disassociates parts of the caller's execution context, e.g. placing
// it into a fresh network, mount, pid, or user namespace. `flags` is a
// bitwise OR of `unix.CLONE_NEW*` constants. Linux-only; returns ENOSYS
// elsewhere.
static int LuaUnixUnshare(lua_State *L) {
  int olderr = errno;
  return SysretBool(L, "unshare", olderr, unshare(luaL_checkinteger(L, 1)));
}

// unix.setns(fd:int[, nstype:int])
//     ├─→ true
//     └─→ nil, error:str, errno:int
//
// Reassociates the calling thread with the namespace referenced by
// `fd`, which is typically obtained by opening one of the files under
// `/proc/<pid>/ns/`. `nstype`, if nonzero, must match one of the
// `unix.CLONE_NEW*` constants and asserts the kind of namespace.
// Linux-only; returns ENOSYS elsewhere.
static int LuaUnixSetns(lua_State *L) {
  int olderr = errno;
  return SysretBool(L, "setns", olderr,
                    setns(luaL_checkinteger(L, 1),
                          luaL_optinteger(L, 2, 0)));
}

// unix.mount(source:str, target:str, fstype:str, flags:int[, data:str])
//     ├─→ true
//     └─→ nil, error:str, errno:int
//
// Mounts a filesystem. `flags` is a bitwise OR of `unix.MS_*`
// constants. `data` is a filesystem-specific options string (may be
// omitted). Typical uses for sandboxing:
//
//     -- Private mount namespace (so our mounts don't leak out)
//     unix.unshare(unix.CLONE_NEWNS)
//     unix.mount("none", "/", nil, unix.MS_REC | unix.MS_PRIVATE, nil)
//
//     -- Read-only bind of a host directory
//     unix.mount("/etc/project", "/tmp/sandbox/etc",
//                nil, unix.MS_BIND | unix.MS_REC, nil)
//     unix.mount("none", "/tmp/sandbox/etc", nil,
//                unix.MS_REMOUNT | unix.MS_BIND | unix.MS_RDONLY, nil)
//
//     -- A fresh tmpfs
//     unix.mount("tmpfs", "/tmp/sandbox/tmp", "tmpfs", 0, "size=64m")
static int LuaUnixMount(lua_State *L) {
  int olderr = errno;
  const char *source = luaL_optstring(L, 1, NULL);
  const char *target = luaL_checkstring(L, 2);
  const char *fstype = luaL_optstring(L, 3, NULL);
  unsigned long flags = (unsigned long)luaL_optinteger(L, 4, 0);
  const char *data = luaL_optstring(L, 5, NULL);
  return SysretBool(L, "mount", olderr,
                    mount(source, target, fstype, flags, data));
}

// unix.unmount(target:str[, flags:int])
//     ├─→ true
//     └─→ nil, error:str, errno:int
//
// Unmounts a filesystem. The BSD-style name (`unmount`) is used for
// cross-platform compatibility; on Linux this is the `umount2`
// syscall. Flags may include MNT_FORCE, MNT_DETACH, MNT_EXPIRE,
// UMOUNT_NOFOLLOW.
static int LuaUnixUnmount(lua_State *L) {
  int olderr = errno;
  return SysretBool(L, "unmount", olderr,
                    unmount(luaL_checkstring(L, 1),
                            luaL_optinteger(L, 2, 0)));
}

// unix.pivot_root(new_root:str, put_old:str)
//     ├─→ true
//     └─→ nil, error:str, errno:int
//
// Moves the root filesystem of the current mount namespace to
// `put_old` and makes `new_root` the new root. Usually paired with
// `chdir("/")` in the child. Requires a private mount namespace.
static int LuaUnixPivotRoot(lua_State *L) {
  int olderr = errno;
  return SysretBool(L, "pivot_root", olderr,
                    pivot_root(luaL_checkstring(L, 1),
                               luaL_checkstring(L, 2)));
}

// unix.prctl(option:int[, arg2:int[, arg3:int[, arg4:int[, arg5:int]]]])
//     ├─→ rc:int
//     └─→ nil, error:str, errno:int
//
// Performs an operation on the calling process. `option` is one of
// the `unix.PR_*` constants. The remaining arguments are
// option-specific.
//
// For "getter" prctl options that return a value, the return is the
// integer result. For "setter" options it's typically 0 on success.
//
// Common sandbox-relevant uses:
//
//     -- Kill this process when the parent dies
//     unix.prctl(unix.PR_SET_PDEATHSIG, unix.SIGTERM)
//
//     -- Forbid gaining new privileges via setuid binaries
//     unix.prctl(unix.PR_SET_NO_NEW_PRIVS, 1)
//
//     -- Prevent core dumps / PTRACE
//     unix.prctl(unix.PR_SET_DUMPABLE, 0)
static int LuaUnixPrctl(lua_State *L) {
  int olderr = errno;
  int option = luaL_checkinteger(L, 1);
  unsigned long a2 = (unsigned long)luaL_optinteger(L, 2, 0);
  unsigned long a3 = (unsigned long)luaL_optinteger(L, 3, 0);
  unsigned long a4 = (unsigned long)luaL_optinteger(L, 4, 0);
  unsigned long a5 = (unsigned long)luaL_optinteger(L, 5, 0);
  return SysretInteger(L, "prctl", olderr, prctl(option, a2, a3, a4, a5));
}

// unix.capget([pid:int])
//     ├─→ caps:table
//     └─→ nil, error:str, errno:int
//
// Returns the calling thread's (or `pid`'s) capability sets as a table
// with `effective`, `permitted`, and `inheritable` fields, each a
// 64-bit bitmask. Each bit position N in those masks corresponds to
// `unix.CAP_*` constant N. Linux-only.
//
//     local caps = assert(unix.capget())
//     if (caps.effective & (1 << unix.CAP_NET_ADMIN)) ~= 0 then
//       -- we have CAP_NET_ADMIN
//     end
static int LuaUnixCapget(lua_State *L) {
  int olderr = errno;
  struct __user_cap_header_struct hdr;
  struct __user_cap_data_struct data[2];
  /* Capability masks need 64 bits (CAP_LAST_CAP can exceed 32).
     A 32-bit lua_Integer would silently truncate the upper half. */
  _Static_assert(sizeof(lua_Integer) >= 8,
                 "unix.capget/capset need 64-bit lua_Integer");
  hdr.version = _LINUX_CAPABILITY_VERSION_3;
  hdr.pid = luaL_optinteger(L, 1, 0);
  if (capget(&hdr, data) == -1) {
    return LuaUnixSysretErrno(L, "capget", olderr);
  }
  lua_newtable(L);
  lua_pushinteger(L, ((uint64_t)data[1].effective   << 32) | data[0].effective);
  lua_setfield(L, -2, "effective");
  lua_pushinteger(L, ((uint64_t)data[1].permitted   << 32) | data[0].permitted);
  lua_setfield(L, -2, "permitted");
  lua_pushinteger(L, ((uint64_t)data[1].inheritable << 32) | data[0].inheritable);
  lua_setfield(L, -2, "inheritable");
  return 1;
}

// unix.capset(effective:int, permitted:int, inheritable:int[, pid:int])
//     ├─→ true
//     └─→ nil, error:str, errno:int
//
// Sets the calling thread's (or `pid`'s) capability sets. Each
// argument is a 64-bit bitmask of `1 << unix.CAP_*` bits. Note that
// `effective` must be a subset of `permitted`, `inheritable` must be
// a subset of `permitted UNION current_inheritable`, and you cannot
// add bits to `permitted` that aren't already there. Linux-only.
//
//     local caps = assert(unix.capget())
//     -- Drop everything except CAP_NET_BIND_SERVICE.
//     local keep = 1 << unix.CAP_NET_BIND_SERVICE
//     assert(unix.capset(caps.permitted & keep, caps.permitted & keep,
//                         caps.inheritable & keep))
static int LuaUnixCapset(lua_State *L) {
  int olderr = errno;
  struct __user_cap_header_struct hdr;
  struct __user_cap_data_struct data[2];
  uint64_t eff = (uint64_t)luaL_checkinteger(L, 1);
  uint64_t per = (uint64_t)luaL_checkinteger(L, 2);
  uint64_t inh = (uint64_t)luaL_checkinteger(L, 3);
  hdr.version = _LINUX_CAPABILITY_VERSION_3;
  hdr.pid = luaL_optinteger(L, 4, 0);
  data[0].effective   = (uint32_t)(eff & 0xffffffff);
  data[0].permitted   = (uint32_t)(per & 0xffffffff);
  data[0].inheritable = (uint32_t)(inh & 0xffffffff);
  data[1].effective   = (uint32_t)(eff >> 32);
  data[1].permitted   = (uint32_t)(per >> 32);
  data[1].inheritable = (uint32_t)(inh >> 32);
  return SysretBool(L, "capset", olderr, capset(&hdr, data));
}

// unix.landlock_create_ruleset([handled_access_fs:int[, flags:int[, handled_access_net:int[, scoped:int]]]])
//     ├─→ fd:int      -- ruleset fd (close with unix.close)
//     ├─→ abi:int     -- when called with no args, returns ABI version
//     └─→ nil, error:str, errno:int
//
// With no arguments, returns the kernel's supported landlock ABI
// (1 = basic, 2 = REFER, 3 = TRUNCATE, 4 = TCP ports, 5 = IOCTL_DEV,
// 6 = scopes, 7 = audit flags, 8 = TSYNC, 9 = RESOLVE_UNIX, ...). With
// `handled_access_fs`, creates a new ruleset that *handles* (can
// restrict) those access categories — bits are LANDLOCK_ACCESS_FS_*.
// Access categories you don't include are effectively unrestricted.
//
// `handled_access_net` (bits are LANDLOCK_ACCESS_NET_*) additionally
// handles TCP bind/connect and needs ABI 4. `scoped` (bits are
// LANDLOCK_SCOPE_*) additionally confines abstract UNIX sockets and
// signals to the domain, and needs ABI 6.
//
// Each of those widens the request to the layout of the ABI that
// introduced it, and a kernel older than that answers E2BIG. So pass
// only what you mean: with neither, the request is byte-identical to
// an ABI 1 one; with `scoped` alone, it is the ABI 6 layout carrying a
// zero net mask.
//
//     local abi = assert(unix.landlock_create_ruleset())
//     local handled = unix.LANDLOCK_ACCESS_FS_READ_FILE
//                   | unix.LANDLOCK_ACCESS_FS_READ_DIR
//                   | unix.LANDLOCK_ACCESS_FS_WRITE_FILE
//                   | unix.LANDLOCK_ACCESS_FS_EXECUTE
//     local rs = assert(unix.landlock_create_ruleset(handled))
//     -- ... add rules with unix.landlock_add_rule ...
//     assert(unix.prctl(unix.PR_SET_NO_NEW_PRIVS, 1))
//     assert(unix.landlock_restrict_self(rs))
//     unix.close(rs)
static int LuaUnixLandlockCreateRuleset(lua_State *L) {
  int olderr = errno;
  if (lua_isnoneornil(L, 1)) {
    return SysretInteger(L, "landlock_create_ruleset", olderr,
                         landlock_create_ruleset(0, 0,
                             LANDLOCK_CREATE_RULESET_VERSION));
  } else {
    struct landlock_ruleset_attr attr = {
      .handled_access_fs = (uint64_t)luaL_checkinteger(L, 1),
    };
    int flags = luaL_optinteger(L, 2, 0);
    // The size decides which ABI the kernel must understand, so send
    // the shortest prefix covering what the caller asked for: a call
    // without a net mask stays byte-identical to an ABI 1 request.
    size_t size = LANDLOCK_RULESET_ATTR_SIZE(handled_access_fs);
    if (!lua_isnoneornil(L, 3)) {
      attr.handled_access_net = (uint64_t)luaL_checkinteger(L, 3);
      size = LANDLOCK_RULESET_ATTR_SIZE(handled_access_net);
    }
    if (!lua_isnoneornil(L, 4)) {
      attr.scoped = (uint64_t)luaL_checkinteger(L, 4);
      size = LANDLOCK_RULESET_ATTR_SIZE(scoped);
    }
    return SysretInteger(L, "landlock_create_ruleset", olderr,
                         landlock_create_ruleset(&attr, size, flags));
  }
}

// unix.landlock_add_rule(ruleset_fd:int, parent_fd:int, allowed:int[, flags:int])
//     ├─→ true
//     └─→ nil, error:str, errno:int
//
// Adds a LANDLOCK_RULE_PATH_BENEATH rule: access under the path
// referenced by `parent_fd` (opened with O_PATH) is granted for the
// categories in `allowed` (must be a subset of the ruleset's handled
// set). `flags` is reserved and defaults to 0.
//
//     local fd = assert(unix.open("/usr", unix.O_PATH))
//     assert(unix.landlock_add_rule(rs, fd,
//              unix.LANDLOCK_ACCESS_FS_READ_FILE
//            | unix.LANDLOCK_ACCESS_FS_READ_DIR
//            | unix.LANDLOCK_ACCESS_FS_EXECUTE))
//     unix.close(fd)
static int LuaUnixLandlockAddRule(lua_State *L) {
  int olderr = errno;
  int ruleset_fd = luaL_checkinteger(L, 1);
  struct landlock_path_beneath_attr attr = {
    .parent_fd     = luaL_checkinteger(L, 2),
    .allowed_access = (uint64_t)luaL_checkinteger(L, 3),
  };
  int flags = luaL_optinteger(L, 4, 0);
  return SysretBool(L, "landlock_add_rule", olderr,
                    landlock_add_rule(ruleset_fd,
                                      LANDLOCK_RULE_PATH_BENEATH,
                                      &attr, flags));
}

// unix.landlock_add_net_rule(ruleset_fd:int, port:int, allowed:int[, flags:int])
//     ├─→ true
//     └─→ nil, error:str, errno:int
//
// Adds a LANDLOCK_RULE_NET_PORT rule: the TCP operations in `allowed`
// (bits are LANDLOCK_ACCESS_NET_*, and must be a subset of the
// ruleset's handled net set) are granted on `port`, a host-byte-order
// TCP port. Needs ABI 4, so the ruleset must have been created with a
// `handled_access_net` argument. `flags` is reserved and defaults to 0.
//
//     local rs = assert(unix.landlock_create_ruleset(0, 0,
//                         unix.LANDLOCK_ACCESS_NET_CONNECT_TCP))
//     assert(unix.landlock_add_net_rule(rs, 443,
//              unix.LANDLOCK_ACCESS_NET_CONNECT_TCP))
static int LuaUnixLandlockAddNetRule(lua_State *L) {
  int olderr = errno;
  int ruleset_fd = luaL_checkinteger(L, 1);
  struct landlock_net_port_attr attr = {
    .port           = (uint64_t)luaL_checkinteger(L, 2),
    .allowed_access = (uint64_t)luaL_checkinteger(L, 3),
  };
  int flags = luaL_optinteger(L, 4, 0);
  return SysretBool(L, "landlock_add_net_rule", olderr,
                    landlock_add_rule(ruleset_fd, LANDLOCK_RULE_NET_PORT,
                                      &attr, flags));
}

// unix.landlock_restrict_self(ruleset_fd:int[, flags:int])
//     ├─→ true
//     └─→ nil, error:str, errno:int
//
// Apply the ruleset to the current thread (and its future children).
// Callers must set PR_SET_NO_NEW_PRIVS first or have CAP_SYS_ADMIN.
//
// `flags` defaults to 0 and takes LANDLOCK_RESTRICT_SELF_* bits: the
// three audit-logging controls added by ABI 7, and TSYNC (ABI 8),
// which applies the domain to every thread of the process rather than
// the calling one. A kernel that does not know a flag rejects it with
// EINVAL, so gate them on the ABI the argless probe reports.
static int LuaUnixLandlockRestrictSelf(lua_State *L) {
  int olderr = errno;
  int ruleset_fd = luaL_checkinteger(L, 1);
  int flags = luaL_optinteger(L, 2, 0);
  return SysretBool(L, "landlock_restrict_self", olderr,
                    landlock_restrict_self(ruleset_fd, flags));
}

// unix.setrlimit(resource:int, soft:int[, hard:int])
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixSetrlimit(lua_State *L) {
  int olderr = errno;
  int64_t soft = luaL_checkinteger(L, 2);
  return SysretBool(
      L, "setrlimit", olderr,
      setrlimit(luaL_checkinteger(L, 1),
                &(struct rlimit){soft, luaL_optinteger(L, 3, soft)}));
}

// unix.getrlimit(resource:int)
//     ├─→ unix.Rlimit
//     └─→ nil, error:str, errno:int
static int LuaUnixGetrlimit(lua_State *L) {
  int olderr = errno;
  struct rlimit rlim;
  if (!getrlimit(luaL_checkinteger(L, 1), &rlim)) {
    lua_newtable(L);
    lua_pushinteger(L, FixLimit(rlim.rlim_cur));
    lua_setfield(L, -2, "soft");
    lua_pushinteger(L, FixLimit(rlim.rlim_max));
    lua_setfield(L, -2, "hard");
    return 1;
  } else {
    return LuaUnixSysretErrno(L, "getrlimit", olderr);
  }
}

// unix.getrusage([who:int])
//     ├─→ unix.Rusage
//     └─→ nil, error:str, errno:int
static int LuaUnixGetrusage(lua_State *L) {
  struct rusage ru;
  int olderr = errno;
  if (!getrusage(luaL_optinteger(L, 1, RUSAGE_SELF), &ru)) {
    LuaPushRusage(L, &ru);
    return 1;
  } else {
    return LuaUnixSysretErrno(L, "getrusage", olderr);
  }
}

// unix.kill(pid:int, sig:int)
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixKill(lua_State *L) {
  int olderr = errno;
  return SysretBool(L, "kill", olderr,
                    kill(luaL_checkinteger(L, 1), luaL_checkinteger(L, 2)));
}

// unix.killpg(pgrp:int, sig:int)
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixKillpg(lua_State *L) {
  int olderr = errno;
  return SysretBool(L, "killpg", olderr,
                    killpg(luaL_checkinteger(L, 1), luaL_checkinteger(L, 2)));
}

// unix.raise(sig:int)
//     └─→ rc:int
static int LuaUnixRaise(lua_State *L) {
  int olderr = errno;
  int sig = luaL_checkinteger(L, 1);
  if (!(0 <= sig && sig <= NSIG)) {
    errno = olderr;
    return luaL_argerror(
        L, 1, lua_pushfstring(L, "invalid signal number %d", sig));
  }
  lua_pushinteger(L, raise(sig));
  return 1;
}

// unix.wait([pid:int, options:int])
//     ├─→ pid:int, wstatus:int, unix.Rusage
//     └─→ nil, error:str, errno:int
static int LuaUnixWait(lua_State *L) {
  struct rusage ru;
  int pid, wstatus, olderr = errno;
  if ((pid = wait4(luaL_optinteger(L, 1, -1), &wstatus,
                   luaL_optinteger(L, 2, 0), &ru)) != -1) {
    lua_pushinteger(L, pid);
    lua_pushinteger(L, wstatus);
    LuaPushRusage(L, &ru);
    return 3;
  } else {
    return LuaUnixSysretErrno(L, "wait", olderr);
  }
}

// unix.fcntl(fd:int, cmd:int[, ...])
//     ├─→ ...
//     └─→ nil, error:str, errno:int
static int LuaUnixFcntl(lua_State *L) {
  struct flock lock;
  int fd, cmd, olderr = errno;
  fd = luaL_checkinteger(L, 1);
  cmd = luaL_checkinteger(L, 2);
  if (cmd == F_SETLK || cmd == F_SETLKW || cmd == F_GETLK) {
    lock.l_type = luaL_optinteger(L, 3, F_RDLCK);
    lock.l_start = luaL_optinteger(L, 4, 0);
    lock.l_len = luaL_optinteger(L, 5, 0);
    lock.l_whence = luaL_optinteger(L, 6, SEEK_SET);
  }
  if (cmd == F_SETLK || cmd == F_SETLKW) {
    return SysretBool(L, "fcntl(F_SETLK*)", olderr, fcntl(fd, cmd, &lock));
  } else if (cmd == F_GETLK) {
    if (fcntl(fd, cmd, &lock) != -1) {
      if (lock.l_type == F_UNLCK) {
        lua_pushinteger(L, F_UNLCK);
        return 1;
      } else {
        lua_pushinteger(L, lock.l_type);
        lua_pushinteger(L, lock.l_start);
        lua_pushinteger(L, lock.l_len);
        lua_pushinteger(L, lock.l_whence);
        lua_pushinteger(L, lock.l_pid);
        return 5;
      }
    } else {
      return LuaUnixSysretErrno(L, "fcntl(F_GETLK)", olderr);
    }
  } else {
    return SysretBool(L, "fcntl", olderr,
                      fcntl(fd, cmd, luaL_optinteger(L, 3, 0)));
  }
}

// unix.ioctl(fd:int, request:int[, arg:int|str])
//     ├─→ true               -- when arg is absent or an integer
//     ├─→ buf:str            -- when arg is a string (possibly modified in place)
//     └─→ nil, error:str, errno:int
//
// Performs a device-specific control operation on `fd`. The third
// argument is interpreted as follows:
//
//   - absent or nil: `ioctl(fd, request, 0)` is called.
//   - integer:       passed as `(void *)(intptr_t)arg`. Use for ioctls
//                    whose argument is a single scalar.
//   - string:        the bytes are copied into a mutable buffer of the
//                    SAME length as the input string, the ioctl is
//                    invoked with a pointer to that buffer, and the
//                    (possibly-modified) buffer is returned on success.
//                    The returned string is always exactly `#arg` bytes.
//                    Only fixed-size struct ioctls are supported this
//                    way; for ioctls whose kernel response may exceed
//                    the input length (e.g. some SIOCGIF* variants that
//                    write extra entries), pre-size `arg` to the max
//                    length you expect. Variable-length ioctls whose
//                    struct contains an embedded pointer+len (e.g.
//                    SIOCGIFCONF) must be called via a different path.
//
// Typical usage for bringing the loopback interface up in a new net
// namespace:
//
//     local sk = assert(unix.socket(unix.AF_INET, unix.SOCK_DGRAM, 0))
//     local ifr = string.pack("c16i2", "lo", unix.IFF_UP) ..
//                 string.rep("\\0", 24 - 2)
//     assert(unix.ioctl(sk, unix.SIOCSIFFLAGS, ifr))
static int LuaUnixIoctl(lua_State *L) {
  int fd, rc, olderr;
  unsigned long request;
  size_t len;
  const char *src;
  char *buf;
  olderr = errno;
  fd = luaL_checkinteger(L, 1);
  request = (unsigned long)luaL_checkinteger(L, 2);
  switch (lua_type(L, 3)) {
    case LUA_TNONE:
    case LUA_TNIL:
      return SysretBool(L, "ioctl", olderr, ioctl(fd, request, 0));
    case LUA_TNUMBER:
      return SysretBool(L, "ioctl", olderr,
                        ioctl(fd, request,
                              (void *)(intptr_t)luaL_checkinteger(L, 3)));
    case LUA_TSTRING:
      src = luaL_checklstring(L, 3, &len);
      buf = malloc(len ? len : 1);  // avoid malloc(0) on empty-string arg
      if (!buf) {
        errno = ENOMEM;
        return LuaUnixSysretErrno(L, "ioctl", olderr);
      }
      memcpy(buf, src, len);
      rc = ioctl(fd, request, buf);
      if (rc != -1) {
        lua_pushlstring(L, buf, len);
        free(buf);
        return 1;
      } else {
        free(buf);
        return LuaUnixSysretErrno(L, "ioctl", olderr);
      }
    default:
      return luaL_argerror(L, 3, "expected nil, integer, or string");
  }
}

// unix.dup(oldfd:int[, newfd:int[, flags:int[, lowest:int]]])
//     ├─→ newfd:int
//     └─→ nil, error:str, errno:int
static int LuaUnixDup(lua_State *L) {
  int rc, oldfd, newfd, flags, lowno, olderr;
  olderr = errno;
  oldfd = luaL_checkinteger(L, 1);
  newfd = luaL_optinteger(L, 2, -1);
  flags = luaL_optinteger(L, 3, 0);
  lowno = luaL_optinteger(L, 4, 0);
  if (newfd < 0) {
    if (!flags && !lowno) {
      rc = dup(oldfd);
    } else if (!flags) {
      rc = fcntl(oldfd, F_DUPFD, lowno);
    } else if (flags == O_CLOEXEC) {
      rc = fcntl(oldfd, F_DUPFD_CLOEXEC, lowno);
    } else {
      rc = einval();
    }
  } else {
    rc = dup3(oldfd, newfd, flags);
  }
  return SysretInteger(L, "dup", olderr, rc);
}

// unix.pipe([flags:int])
//     ├─→ unix.Pipe
//     └─→ nil, error:str, errno:int
static int LuaUnixPipe(lua_State *L) {
  int pipefd[2], olderr = errno;
  if (!pipe2(pipefd, luaL_optinteger(L, 1, 0))) {
    lua_newtable(L);
    lua_pushinteger(L, pipefd[0]);
    lua_setfield(L, -2, "reader");
    lua_pushinteger(L, pipefd[1]);
    lua_setfield(L, -2, "writer");
    return 1;
  } else {
    return LuaUnixSysretErrno(L, "pipe", olderr);
  }
}

// unix.openpty()
//     ├─→ mfd:int, sfd:int, name:str
//     └─→ nil, error:str, errno:int
static int LuaUnixOpenpty(lua_State *L) {
  int mfd, sfd, olderr = errno;
  // openpty() strcpy()s the subordinate path out of a char[16] field, so
  // the name it writes is at most 16 bytes including the NUL.
  char name[32];
  if (!openpty(&mfd, &sfd, name, 0, 0)) {
    lua_pushinteger(L, mfd);
    lua_pushinteger(L, sfd);
    lua_pushstring(L, name);
    return 3;
  } else {
    return LuaUnixSysretErrno(L, "openpty", olderr);
  }
}

// unix.login_tty(fd:int)
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixLoginTty(lua_State *L) {
  int olderr = errno;
  return SysretBool(L, "login_tty", olderr, login_tty(luaL_checkinteger(L, 1)));
}

// unix.getsid(pid:int)
//     ├─→ sid:int
//     └─→ nil, error:str, errno:int
static int LuaUnixGetsid(lua_State *L) {
  int olderr = errno;
  return SysretInteger(L, "getsid", olderr, getsid(luaL_checkinteger(L, 1)));
}

static dontinline int LuaUnixRc0(lua_State *L, const char *call, int f(void)) {
  int olderr = errno;
  return SysretInteger(L, call, olderr, f());
}

// unix.getpgrp()
//     ├─→ pgid:int
//     └─→ nil, error:str, errno:int
static int LuaUnixGetpgrp(lua_State *L) {
  return LuaUnixRc0(L, "getpgrp", getpgrp);
}

// unix.setpgrp()
//     ├─→ pgid:int
//     └─→ nil, error:str, errno:int
static int LuaUnixSetpgrp(lua_State *L) {
  return LuaUnixRc0(L, "setpgrp", setpgrp);
}

// unix.setsid()
//     ├─→ sid:int
//     └─→ nil, error:str, errno:int
static int LuaUnixSetsid(lua_State *L) {
  return LuaUnixRc0(L, "setsid", setsid);
}

// unix.getpgid(pid:int)
//     ├─→ pgid:int
//     └─→ nil, error:str, errno:int
static int LuaUnixGetpgid(lua_State *L) {
  int olderr = errno;
  return SysretInteger(L, "getpgid", olderr, getpgid(luaL_checkinteger(L, 1)));
}

// unix.setpgid(pid:int, pgid:int)
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixSetpgid(lua_State *L) {
  int olderr = errno;
  return SysretBool(L, "setpgid", olderr,
                    setpgid(luaL_checkinteger(L, 1), luaL_checkinteger(L, 2)));
}

static dontinline int LuaUnixSetid(lua_State *L, const char *call,
                                   int f(unsigned)) {
  int olderr = errno;
  return SysretBool(L, call, olderr, f(luaL_checkinteger(L, 1)));
}

// unix.setuid(uid:int)
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixSetuid(lua_State *L) {
  return LuaUnixSetid(L, "setuid", setuid);
}

// unix.setgid(gid:int)
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixSetgid(lua_State *L) {
  return LuaUnixSetid(L, "setgid", setgid);
}

// setfsuid(2)/setfsgid(2) can't signal failure through their return
// value the way SysretBool assumes: success returns the PREVIOUS
// fsuid/fsgid, failure returns the CURRENT (unchanged) one, and
// neither is -1 in ordinary operation. The established idiom to
// detect a refused change is a second call with -1 (an id no process
// can hold, so it changes nothing) immediately after, which reports
// the value now in effect; if that doesn't match what we asked for,
// the kernel refused the change (typically for lack of
// CAP_SETUID/CAP_SETGID) and we synthesize EPERM so callers get the
// honest nil, err, errno tuple instead of a false true.
static dontinline int LuaUnixSetfsxid(lua_State *L, const char *call,
                                      int f(unsigned)) {
  int olderr = errno;
  unsigned want = luaL_checkinteger(L, 1);
  f(want);
  if ((unsigned)f(-1) != want) {
    errno = EPERM;
    return LuaUnixSysretErrno(L, call, olderr);
  }
  lua_pushboolean(L, true);
  return 1;
}

// unix.setfsuid(fsuid:int)
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixSetfsuid(lua_State *L) {
  return LuaUnixSetfsxid(L, "setfsuid", setfsuid);
}

// unix.setfsgid(fsgid:int)
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixSetfsgid(lua_State *L) {
  return LuaUnixSetfsxid(L, "setfsgid", setfsgid);
}

static dontinline int LuaUnixSetresid(lua_State *L, const char *call,
                                      int f(uint32_t, uint32_t, uint32_t)) {
  int olderr = errno;
  return SysretBool(L, call, olderr,
                    f(luaL_checkinteger(L, 1), luaL_checkinteger(L, 2),
                      luaL_checkinteger(L, 3)));
}

// unix.setresuid(real:int, effective:int, saved:int)
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixSetresuid(lua_State *L) {
  return LuaUnixSetresid(L, "setresuid", setresuid);
}

// unix.setresgid(real:int, effective:int, saved:int)
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixSetresgid(lua_State *L) {
  return LuaUnixSetresid(L, "setresgid", setresgid);
}

// unix.utimensat(path[, asecs, ananos, msecs, mnanos[, dirfd[, flags]]])
//     ├─→ 0
//     └─→ nil, error:str, errno:int
static int LuaUnixUtimensat(lua_State *L) {
  int olderr = errno;
  return SysretInteger(
      L, "utimensat", olderr,
      utimensat(
          luaL_optinteger(L, 6, AT_FDCWD), luaL_checkstring(L, 1),
          (struct timespec[2]){
              {luaL_optinteger(L, 2, 0), luaL_optinteger(L, 3, UTIME_NOW)},
              {luaL_optinteger(L, 4, 0), luaL_optinteger(L, 5, UTIME_NOW)},
          },
          luaL_optinteger(L, 7, 0)));
}

// unix.futimens(fd:int[, asecs, ananos, msecs, mnanos])
//     ├─→ 0
//     └─→ nil, error:str, errno:int
static int LuaUnixFutimens(lua_State *L) {
  int olderr = errno;
  return SysretInteger(
      L, "futimens", olderr,
      futimens(luaL_checkinteger(L, 1),
               (struct timespec[2]){
                   {luaL_optinteger(L, 2, 0), luaL_optinteger(L, 3, UTIME_NOW)},
                   {luaL_optinteger(L, 4, 0), luaL_optinteger(L, 5, UTIME_NOW)},
               }));
}

// unix.clock_gettime([clock:int])
//     ├─→ seconds:int, nanos:int
//     └─→ raises on an invalid or unsupported clock id
static int LuaUnixGettime(lua_State *L) {
  struct timespec ts;
  int olderr = errno;
  int clock = luaL_optinteger(L, 1, CLOCK_REALTIME);
  if (!clock_gettime(clock, &ts)) {
    lua_pushinteger(L, ts.tv_sec);
    lua_pushinteger(L, ts.tv_nsec);
    return 2;
  }
  // The only failure is a clock id this platform cannot serve, which is
  // a bad argument rather than an environmental condition. Raising keeps
  // the success shape two plain integers for every caller.
  errno = olderr;
  return luaL_argerror(
      L, 1, lua_pushfstring(L, "invalid or unsupported clock id %d", clock));
}

// unix.nanosleep(seconds:int[, nanos:int])
//     ├─→ remaining:table
//     └─→ nil, error:str, errno:int[, remaining:table]
//
// The success value and the EINTR remainder used to be two positional
// integers each (remseconds, remnanos), which put the failure path's
// error string in the same slot (2) that a completed sleep's remnanos
// occupied. Bundling both into one {seconds, nanos} table -- like
// unix.capget's caps table -- keeps every slot's meaning fixed: 1 is
// always the value-or-nil, 2/3 are always error/errno, and 4 is the
// EINTR remainder, present on no other path.
static int LuaUnixNanosleep(lua_State *L) {
  int rc, err, olderr = errno;
  struct timespec req, rem = {0};
  req.tv_sec = luaL_checkinteger(L, 1);
  req.tv_nsec = luaL_optinteger(L, 2, 0);
  if (!nanosleep(&req, &rem)) {
    // POSIX leaves rem unspecified on success: the sleep completed,
    // so the remainder is zero by definition (the old code returned
    // whatever the kernel left in the buffer)
    lua_newtable(L);
    lua_pushinteger(L, 0);
    lua_setfield(L, -2, "seconds");
    lua_pushinteger(L, 0);
    lua_setfield(L, -2, "nanos");
    return 1;
  } else {
    // EINTR is the one failure that fills rem; bundle the kernel's
    // remainder into its own table, appended after the errno, so an
    // interrupted sleep can resume without re-deriving it from a
    // clock and without sharing a slot with the error string
    err = errno;
    rc = LuaUnixSysretErrno(L, "nanosleep", olderr);
    if (err == EINTR) {
      lua_newtable(L);
      lua_pushinteger(L, rem.tv_sec);
      lua_setfield(L, -2, "seconds");
      lua_pushinteger(L, rem.tv_nsec);
      lua_setfield(L, -2, "nanos");
      return rc + 1;
    }
    return rc;
  }
}

// unix.sync()
static int LuaUnixSync(lua_State *L) {
  sync();
  return 0;
}

// unix.fsync(fd:int)
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixFsync(lua_State *L) {
  int olderr = errno;
  return SysretBool(L, "fsync", olderr, fsync(luaL_checkinteger(L, 1)));
}

// unix.fdatasync(fd:int)
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixFdatasync(lua_State *L) {
  int olderr = errno;
  return SysretBool(L, "fdatasync", olderr, fdatasync(luaL_checkinteger(L, 1)));
}

// unix.open(path:str[, flags:int[, mode:int[, dirfd:int]]])
//     ├─→ fd:int
//     └─→ nil, error:str, errno:int
static int LuaUnixOpen(lua_State *L) {
  int olderr = errno;
  return SysretInteger(
      L, "open", olderr,
      openat(luaL_optinteger(L, 4, AT_FDCWD), luaL_checkstring(L, 1),
             luaL_optinteger(L, 2, O_RDONLY), luaL_optinteger(L, 3, 0644)));
}

// unix.tmpfd()
//     ├─→ fd:int
//     └─→ nil, error:str, errno:int
static int LuaUnixTmpfd(lua_State *L) {
  int olderr = errno;
  return SysretInteger(L, "tmpfd", olderr, tmpfd());
}

// unix.mkdtemp(template:str)
//     ├─→ path:str
//     └─→ nil, error:str, errno:int
static int LuaUnixMkdtemp(lua_State *L) {
  char *path;
  int olderr = errno;
  const char *template = luaL_checkstring(L, 1);
  size_t len = strlen(template);
  path = malloc(len + 1);
  if (!path) {
    return LuaUnixSysretErrno(L, "mkdtemp", olderr);
  }
  memcpy(path, template, len + 1);
  if (mkdtemp(path)) {
    lua_pushstring(L, path);
    free(path);
    return 1;
  } else {
    free(path);
    return LuaUnixSysretErrno(L, "mkdtemp", olderr);
  }
}

// unix.mkstemp(template:str)
//     ├─→ fd:int, unix.MkstempPath{path:str}
//     └─→ nil, error:str, errno:int
//
// path used to be a second positional string, the same slot (2) the
// failure path uses for its error string. Bundling it into a table --
// like unix.nanosleep's remainder -- keeps slot 2's meaning fixed
// across branches: a unix.MkstempPath on success, the error string on
// failure.
static int LuaUnixMkstemp(lua_State *L) {
  char *path;
  int fd, olderr = errno;
  const char *template = luaL_checkstring(L, 1);
  size_t len = strlen(template);
  path = malloc(len + 1);
  if (!path) {
    return LuaUnixSysretErrno(L, "mkstemp", olderr);
  }
  memcpy(path, template, len + 1);
  if ((fd = mkstemp(path)) != -1) {
    lua_pushinteger(L, fd);
    lua_newtable(L);
    lua_pushstring(L, path);
    lua_setfield(L, -2, "path");
    free(path);
    return 2;
  } else {
    free(path);
    return LuaUnixSysretErrno(L, "mkstemp", olderr);
  }
}

// unix.close(fd:int)
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixClose(lua_State *L) {
  int olderr = errno;
  return SysretBool(L, "close", olderr, close(luaL_checkinteger(L, 1)));
}

// unix.lseek(fd:int, offset:int[, whence:int])
//     ├─→ newposbytes:int
//     └─→ nil, error:str, errno:int
static int LuaUnixLseek(lua_State *L) {
  int olderr = errno;
  return SysretInteger(L, "lseek", olderr,
                       lseek(luaL_checkinteger(L, 1), luaL_checkinteger(L, 2),
                             luaL_optinteger(L, 3, SEEK_SET)));
}

// unix.copy_file_range(infd:int, outfd:int, count:int)
//     ├─→ copied:int
//     └─→ nil, error:str, errno:int
// Copies up to count bytes between file descriptors inside the kernel
// (Linux 4.5+, FreeBSD 13+), never bouncing through userspace. Both
// descriptors' file offsets advance by the bytes copied, exactly as a
// read()+write() pair would, and short copies are normal. On platforms
// without the syscall it fails with ENOSYS; callers keep a read/write
// fallback.
static int LuaUnixCopyFileRange(lua_State *L) {
  int olderr = errno;
  return SysretInteger(L, "copy_file_range", olderr,
                       copy_file_range(luaL_checkinteger(L, 1), 0,
                                       luaL_checkinteger(L, 2), 0,
                                       luaL_checkinteger(L, 3), 0));
}

// unix.truncate(path:str[, length:int])
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixTruncate(lua_State *L) {
  int olderr = errno;
  return SysretBool(L, "truncate", olderr,
                    truncate(luaL_checkstring(L, 1), luaL_optinteger(L, 2, 0)));
}

// unix.ftruncate(fd:int[, length:int])
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixFtruncate(lua_State *L) {
  int olderr = errno;
  return SysretBool(
      L, "ftruncate", olderr,
      ftruncate(luaL_checkinteger(L, 1), luaL_optinteger(L, 2, 0)));
}

// unix.read(fd:int[, bufsiz:str[, offset:int]])
//     ├─→ data:str
//     └─→ nil, error:str, errno:int
static int LuaUnixRead(lua_State *L) {
  char *buf;
  size_t got;
  ssize_t rc;
  int fd, olderr;
  lua_Integer bufsiz, offset;
  olderr = errno;
  fd = luaL_checkinteger(L, 1);
  bufsiz = luaL_optinteger(L, 2, BUFSIZ);
  offset = luaL_optinteger(L, 3, -1);
  if (bufsiz < 0) bufsiz = 0;
  bufsiz = MIN(bufsiz, 0x7ffff000);
  buf = LuaAllocOrDie(L, bufsiz);
  if (offset == -1) {
    rc = read(fd, buf, bufsiz);
  } else {
    rc = pread(fd, buf, bufsiz, offset);
  }
  if (rc != -1) {
    got = rc;
    lua_pushlstring(L, buf, got);
    free(buf);
    return 1;
  } else {
    free(buf);
    return LuaUnixSysretErrno(L, "read", olderr);
  }
}

// unix.write(fd:int, data:str[, offset:int])
//     ├─→ wrotebytes:int
//     └─→ nil, error:str, errno:int
static int LuaUnixWrite(lua_State *L) {
  ssize_t rc;
  size_t size;
  int fd, olderr;
  const char *data;
  lua_Integer offset;
  olderr = errno;
  fd = luaL_checkinteger(L, 1);
  data = luaL_checklstring(L, 2, &size);
  offset = luaL_optinteger(L, 3, -1);
  if (offset == -1) {
    rc = write(fd, data, size);
  } else {
    rc = pwrite(fd, data, size, offset);
  }
  return SysretInteger(L, "write", olderr, rc);
}

// unix.stat(path:str[, flags:int[, dirfd:int]])
//     ├─→ unix.Stat
//     └─→ nil, error:str, errno:int
static int LuaUnixStat(lua_State *L) {
  struct stat st;
  int olderr = errno;
  if (!fstatat(luaL_optinteger(L, 3, AT_FDCWD), luaL_checkstring(L, 1), &st,
               luaL_optinteger(L, 2, 0))) {
    LuaPushStat(L, &st);
    return 1;
  } else {
    return LuaUnixSysretErrno(L, "stat", olderr);
  }
}

// unix.fstat(fd:int)
//     ├─→ unix.Stat
//     └─→ nil, error:str, errno:int
static int LuaUnixFstat(lua_State *L) {
  struct stat st;
  int olderr = errno;
  if (!fstat(luaL_checkinteger(L, 1), &st)) {
    LuaPushStat(L, &st);
    return 1;
  } else {
    return LuaUnixSysretErrno(L, "fstat", olderr);
  }
}

// unix.statfs(path:str)
//     ├─→ unix.Statfs
//     └─→ nil, error:str, errno:int
static int LuaUnixStatfs(lua_State *L) {
  struct statfs f;
  int olderr = errno;
  if (!statfs(luaL_checkstring(L, 1), &f)) {
    LuaPushStatfs(L, &f);
    return 1;
  } else {
    return LuaUnixSysretErrno(L, "statfs", olderr);
  }
}

// unix.fstatfs(fd:int)
//     ├─→ unix.Stat
//     └─→ nil, error:str, errno:int
static int LuaUnixFstatfs(lua_State *L) {
  struct statfs f;
  int olderr = errno;
  if (!fstatfs(luaL_checkinteger(L, 1), &f)) {
    LuaPushStatfs(L, &f);
    return 1;
  } else {
    return LuaUnixSysretErrno(L, "fstatfs", olderr);
  }
}

static bool IsSockoptBool(int l, int x) {
  if (l == SOL_SOCKET) {
    return x == SO_TYPE ||        //
           x == SO_DEBUG ||       //
           x == SO_ERROR ||       //
           x == SO_BROADCAST ||   //
           x == SO_REUSEADDR ||   //
           x == SO_REUSEPORT ||   //
           x == SO_NOSIGPIPE ||   //
           x == SO_KEEPALIVE ||   //
           x == SO_ACCEPTCONN ||  //
           x == SO_DONTROUTE;     //
  } else if (l == SOL_TCP) {
    return x == TCP_NODELAY ||           //
           x == TCP_CORK ||              //
           x == TCP_QUICKACK ||          //
           x == TCP_SAVE_SYN ||          //
           x == TCP_FASTOPEN_CONNECT ||  //
           x == TCP_DEFER_ACCEPT;        //
  } else if (l == SOL_IP) {
    return x == IP_HDRINCL;  //
  } else {
    return false;
  }
}

static bool IsSockoptInt(int l, int x) {
  if (l == SOL_SOCKET) {
    return x == SO_SNDBUF ||    //
           x == SO_RCVBUF ||    //
           x == SO_RCVLOWAT ||  //
           x == SO_SNDLOWAT;    //
  } else if (l == SOL_TCP) {
    return x == TCP_FASTOPEN ||       //
           x == TCP_KEEPCNT ||        //
           x == TCP_MAXSEG ||         //
           x == TCP_SYNCNT ||         //
           x == TCP_NOTSENT_LOWAT ||  //
           x == TCP_WINDOW_CLAMP ||   //
           x == TCP_KEEPIDLE ||       //
           x == TCP_KEEPINTVL;        //
  } else if (l == SOL_IP) {
    return x == IP_TOS ||  //
           x == IP_MTU ||  //
           x == IP_TTL;    //
  } else {
    return false;
  }
}

static bool IsSockoptTimeval(int l, int x) {
  if (l == SOL_SOCKET) {
    return x == SO_RCVTIMEO ||  //
           x == SO_SNDTIMEO;    //
  } else {
    return false;
  }
}

static int LuaUnixSetsockopt(lua_State *L) {
  void *optval;
  struct linger l;
  uint32_t optsize;
  struct timeval tv;
  int fd, level, optname, optint, olderr = errno;
  fd = luaL_checkinteger(L, 1);
  level = luaL_checkinteger(L, 2);
  optname = luaL_checkinteger(L, 3);
  if (level == -1 || optname == 0) {
  NoProtocolOption:
    enoprotoopt();
    return LuaUnixSysretErrno(L, "setsockopt", olderr);
  }
  if (IsSockoptBool(level, optname)) {
    // unix.setsockopt(fd:int, level:int, optname:int, value:bool)
    //     ├─→ true
    //     └─→ nil, error:str, errno:int
    optint = lua_toboolean(L, 4);
    optval = &optint;
    optsize = sizeof(optint);
  } else if (IsSockoptInt(level, optname)) {
    // unix.setsockopt(fd:int, level:int, optname:int, value:int)
    //     ├─→ true
    //     └─→ nil, error:str, errno:int
    optint = luaL_checkinteger(L, 4);
    optval = &optint;
    optsize = sizeof(optint);
  } else if (IsSockoptTimeval(level, optname)) {
    // unix.setsockopt(fd:int, level:int, optname:int, secs:int[, nanos:int])
    //     ├─→ true
    //     └─→ nil, error:str, errno:int
    tv.tv_sec = luaL_checkinteger(L, 4);
    tv.tv_usec = luaL_optinteger(L, 5, 0) / 1000;
    optval = &tv;
    optsize = sizeof(tv);
  } else if (level == SOL_SOCKET && optname == SO_LINGER) {
    // unix.setsockopt(fd:int, level:int, optname:int, secs:int, enabled:bool)
    //     ├─→ true
    //     └─→ nil, error:str, errno:int
    l.l_linger = luaL_checkinteger(L, 4);
    l.l_onoff = lua_toboolean(L, 5);
    optval = &l;
    optsize = sizeof(l);
  } else {
    goto NoProtocolOption;
  }
  return SysretBool(L, "setsockopt", olderr,
                    setsockopt(fd, level, optname, optval, optsize));
}

static int LuaUnixGetsockopt(lua_State *L) {
  char *p;
  uint32_t size;
  struct linger l;
  struct timeval tv;
  int fd, level, optname, optval, olderr = errno;
  fd = luaL_checkinteger(L, 1);
  level = luaL_checkinteger(L, 2);
  optname = luaL_checkinteger(L, 3);
  if (level == -1 || optname == 0) {
  NoProtocolOption:
    enoprotoopt();
    return LuaUnixSysretErrno(L, "setsockopt", olderr);
  }
  if (IsSockoptBool(level, optname) || IsSockoptInt(level, optname)) {
    // unix.getsockopt(fd:int, level:int, optname:int)
    //     ├─→ value:int
    //     └─→ nil, error:str, errno:int
    size = sizeof(optval);
    if (getsockopt(fd, level, optname, &optval, &size) != -1) {
      CheckOptvalsize(L, sizeof(optval), size);
      lua_pushinteger(L, optval);
      return 1;
    }
  } else if (IsSockoptTimeval(level, optname)) {
    // unix.getsockopt(fd:int, level:int, optname:int)
    //     ├─→ secs:int, nsecs:int
    //     └─→ nil, error:str, errno:int
    size = sizeof(tv);
    if (getsockopt(fd, level, optname, &tv, &size) != -1) {
      CheckOptvalsize(L, sizeof(tv), size);
      lua_pushinteger(L, tv.tv_sec);
      lua_pushinteger(L, tv.tv_usec * 1000);
      return 2;
    }
  } else if (level == SOL_SOCKET && optname == SO_LINGER) {
    // unix.getsockopt(fd:int, unix.SOL_SOCKET, unix.SO_LINGER)
    //     ├─→ seconds:int, enabled:bool
    //     └─→ nil, error:str, errno:int
    size = sizeof(l);
    if (getsockopt(fd, level, optname, &l, &size) != -1) {
      CheckOptvalsize(L, sizeof(l), size);
      lua_pushinteger(L, l.l_linger);
      lua_pushboolean(L, !!l.l_onoff);
      return 2;
    }
  } else if (level == SOL_TCP && optname == TCP_SAVED_SYN) {
    // unix.getsockopt(fd:int, unix.SOL_TCP, unix.SO_SAVED_SYN)
    //     ├─→ syn_packet_bytes:str
    //     └─→ nil, error:str, errno:int
    if ((p = malloc((size = 1500)))) {
      if (getsockopt(fd, level, optname, p, &size) != -1) {
        lua_pushlstring(L, p, size);
        free(p);
        return 1;
      }
      free(p);
    }
  } else {
    goto NoProtocolOption;
  }
  return LuaUnixSysretErrno(L, "getsockopt", olderr);
}

// unix.socket([family:int[, type:int[, protocol:int]]])
//     ├─→ fd:int
//     └─→ nil, error:str, errno:int
static int LuaUnixSocket(lua_State *L) {
  int olderr = errno;
  int family = luaL_optinteger(L, 1, AF_INET);
  return SysretInteger(L, "socket", olderr,
                       socket(family, luaL_optinteger(L, 2, SOCK_STREAM),
                              luaL_optinteger(L, 3, 0)));
}

// unix.socketpair([family:int[, type:int[, protocol:int]]])
//     ├─→ fd1:int, fd2:int
//     └─→ nil, error:str, errno:int
static int LuaUnixSocketpair(lua_State *L) {
  int sv[2], olderr = errno;
  if (!socketpair(luaL_optinteger(L, 1, AF_UNIX),
                  luaL_optinteger(L, 2, SOCK_STREAM), luaL_optinteger(L, 3, 0),
                  sv)) {
    lua_pushinteger(L, sv[0]);
    lua_pushinteger(L, sv[1]);
    return 2;
  } else {
    return LuaUnixSysretErrno(L, "socketpair", olderr);
  }
}

// unix.bind(fd:int[, ip:uint32, port:uint16])
// unix.bind(fd:int[, unixpath:str])
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixBind(lua_State *L) {
  uint32_t salen;
  struct sockaddr_storage ss;
  int olderr = errno;
  MakeSockaddr(L, 2, &ss, &salen);
  return SysretBool(
      L, "bind", olderr,
      bind(luaL_checkinteger(L, 1), (struct sockaddr *)&ss, salen));
}

// unix.connect(fd:int, ip:uint32, port:uint16)
// unix.connect(fd:int, unixpath:str)
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixConnect(lua_State *L) {
  uint32_t salen;
  struct sockaddr_storage ss;
  int olderr = errno;
  MakeSockaddr(L, 2, &ss, &salen);
  return SysretBool(
      L, "connect", olderr,
      connect(luaL_checkinteger(L, 1), (struct sockaddr *)&ss, salen));
}

// unix.listen(fd:int[, backlog:int])
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixListen(lua_State *L) {
  int olderr = errno;
  return SysretBool(L, "listen", olderr,
                    listen(luaL_checkinteger(L, 1), luaL_optinteger(L, 2, 10)));
}

static int LuaUnixGetname(lua_State *L, const char *name,
                          int func(int, struct sockaddr *, uint32_t *)) {
  int olderr;
  uint32_t addrsize;
  struct sockaddr_storage ss = {0};
  olderr = errno;
  addrsize = sizeof(ss) - 1;
  if (!func(luaL_checkinteger(L, 1), (struct sockaddr *)&ss, &addrsize)) {
    return PushSockaddr(L, &ss);
  } else {
    return LuaUnixSysretErrno(L, name, olderr);
  }
}

// unix.getsockname(fd:int)
//     ├─→ ip:uint32, port:uint16
//     ├─→ unixpath:str
//     └─→ nil, error:str, errno:int
static int LuaUnixGetsockname(lua_State *L) {
  return LuaUnixGetname(L, "getsockname", getsockname);
}

// unix.getpeername(fd:int)
//     ├─→ ip:uint32, port:uint16
//     ├─→ unixpath:str
//     └─→ nil, error:str, errno:int
static int LuaUnixGetpeername(lua_State *L) {
  return LuaUnixGetname(L, "getpeername", getpeername);
}

// unix.siocgifconf()
//     ├─→ {{name:str,ip:uint32,netmask:uint32}, ...}
//     └─→ nil, error:str, errno:int
static int LuaUnixSiocgifconf(lua_State *L) {
  size_t n;
  char *data;
  int i, fd, olderr;
  struct ifreq *ifr;
  struct ifconf conf;
  olderr = errno;
  data = LuaAllocOrDie(L, (n = 4096));
  if ((fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_IP)) == -1) {
    free(data);
    return LuaUnixSysretErrno(L, "siocgifconf", olderr);
  }
  conf.ifc_buf = data;
  conf.ifc_len = n;
  if (ioctl(fd, SIOCGIFCONF, &conf) == -1) {
    close(fd);
    free(data);
    return LuaUnixSysretErrno(L, "siocgifconf", olderr);
  }
  lua_newtable(L);
  i = 0;
  for (ifr = (struct ifreq *)data; (char *)ifr < data + conf.ifc_len; ++ifr) {
    if (ifr->ifr_addr.sa_family != AF_INET) continue;
    lua_createtable(L, 0, 3);
    lua_pushliteral(L, "name");
    lua_pushstring(L, ifr->ifr_name);
    lua_settable(L, -3);
    lua_pushliteral(L, "ip");
    lua_pushinteger(
        L, ntohl(((struct sockaddr_in *)&ifr->ifr_addr)->sin_addr.s_addr));
    lua_settable(L, -3);
    if (ioctl(fd, SIOCGIFNETMASK, ifr) != -1) {
      lua_pushliteral(L, "netmask");
      lua_pushinteger(
          L, ntohl(((struct sockaddr_in *)&ifr->ifr_addr)->sin_addr.s_addr));
      lua_settable(L, -3);
    }
    lua_rawseti(L, -2, ++i);
  }
  close(fd);
  free(data);
  return 1;
}

// Shared plumbing for the SIOCGIFFLAGS/SIOCSIFFLAGS ifreq ioctls: puts
// the struct ifreq ABI layout in C so Lua callers pass interface names
// and flag integers instead of hand-packing kernel structs.
static int LuaUnixIfreqFlagsIoctl(lua_State *L, const char *call,
                                  unsigned long request, struct ifreq *ifr) {
  size_t len;
  const char *name;
  int rc, fd, olderr = errno;
  name = luaL_checklstring(L, 1, &len);
  if (len >= IFNAMSIZ) {
    einval();
    return LuaUnixSysretErrno(L, call, olderr);
  }
  memcpy(ifr->ifr_name, name, len);
  if ((fd = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, IPPROTO_IP)) == -1) {
    return LuaUnixSysretErrno(L, call, olderr);
  }
  rc = ioctl(fd, request, ifr);
  close(fd);
  if (rc == -1) {
    return LuaUnixSysretErrno(L, call, olderr);
  }
  return 0;
}

// unix.siocgifflags(ifname:str)
//     ├─→ flags:int
//     └─→ nil, error:str, errno:int
static int LuaUnixSiocgifflags(lua_State *L) {
  int rc;
  struct ifreq ifr = {0};
  if ((rc = LuaUnixIfreqFlagsIoctl(L, "siocgifflags", SIOCGIFFLAGS, &ifr))) {
    return rc;
  }
  lua_pushinteger(L, (uint16_t)ifr.ifr_flags);
  return 1;
}

// unix.siocsifflags(ifname:str, flags:int)
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixSiocsifflags(lua_State *L) {
  int rc;
  struct ifreq ifr = {0};
  ifr.ifr_flags = (uint16_t)luaL_checkinteger(L, 2);
  if ((rc = LuaUnixIfreqFlagsIoctl(L, "siocsifflags", SIOCSIFFLAGS, &ifr))) {
    return rc;
  }
  lua_pushboolean(L, true);
  return 1;
}

// sandbox.pledge([promises:str[, execpromises:str[, mode:int]]])
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixPledge(lua_State *L) {
  int olderr = errno;
  __pledge_mode = luaL_optinteger(L, 3, 0);
  return SysretBool(L, "pledge", olderr,
                    pledge(luaL_optstring(L, 1, 0), luaL_optstring(L, 2, 0)));
}

// sandbox.unveil([path:str[, permissions:str]])
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixUnveil(lua_State *L) {
  int olderr = errno;
  return SysretBool(L, "unveil", olderr,
                    unveil(luaL_optstring(L, 1, 0), luaL_optstring(L, 2, 0)));
}

// unix.gethostname()
//     ├─→ host:str
//     └─→ nil, error:str, errno:int
static int LuaUnixGethostname(lua_State *L) {
  int rc, olderr;
  char buf[DNS_NAME_MAX + 1];
  olderr = errno;
  if ((rc = gethostname(buf, sizeof(buf))) != -1) {
    if (strnlen(buf, sizeof(buf)) < sizeof(buf)) {
      lua_pushstring(L, buf);
      return 1;
    } else {
      enomem();
    }
  }
  return LuaUnixSysretErrno(L, "gethostname", olderr);
}

// unix.sethostname(name:str)
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixSethostname(lua_State *L) {
  size_t len;
  int olderr = errno;
  const char *name = luaL_checklstring(L, 1, &len);
  return SysretBool(L, "sethostname", olderr, sethostname(name, len));
}

// unix.accept(serverfd:int[, flags:int])
//     ├─→ clientfd:int, ip:uint32, port:uint16
//     ├─→ clientfd:int, unixpath:str
//     └─→ nil, error:str, errno:int
static int LuaUnixAccept(lua_State *L) {
  uint32_t addrsize;
  struct sockaddr_storage ss;
  int clientfd, serverfd, olderr, flags;
  olderr = errno;
  addrsize = sizeof(ss);
  serverfd = luaL_checkinteger(L, 1);
  flags = luaL_optinteger(L, 2, 0);
  clientfd = accept4(serverfd, (struct sockaddr *)&ss, &addrsize, flags);
  if (clientfd != -1) {
    lua_pushinteger(L, clientfd);
    return 1 + PushSockaddr(L, &ss);
  } else {
    return LuaUnixSysretErrno(L, "accept", olderr);
  }
}

// unix.poll({[fd:int]=events:int, ...}[, timeoutms:int[, mask:unix.Sigset]])
//     ├─→ {[fd:int]=revents:int, ...}
//     └─→ nil, error:str, errno:int
static int LuaUnixPoll(lua_State *L) {
  size_t nfds;
  sigset_t *mask;
  struct timespec ts, *tsp;
  struct pollfd *fds, *fds2;
  int i, events, olderr = errno;
  luaL_checktype(L, 1, LUA_TTABLE);
  if (!lua_isnoneornil(L, 2)) {
    ts = timespec_frommillis(luaL_checkinteger(L, 2));
    tsp = &ts;
  } else {
    tsp = 0;
  }
  if (!lua_isnoneornil(L, 3)) {
    mask = luaL_checkudata(L, 3, "unix.Sigset");
  } else {
    mask = 0;
  }
  lua_pushnil(L);
  for (fds = 0, nfds = 0; lua_next(L, 1);) {
    if (lua_isinteger(L, -2)) {
      if ((fds2 = LuaRealloc(L, fds, (nfds + 1) * sizeof(*fds)))) {
        fds2[nfds].fd = lua_tointeger(L, -2);
        fds2[nfds].events = lua_tointeger(L, -1);
        fds = fds2;
        ++nfds;
      } else {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wuse-after-free"
        free(fds);
#pragma GCC diagnostic pop
        return LuaUnixSysretErrno(L, "poll", olderr);
      }
    } else {
      // ignore non-integer key
    }
    lua_pop(L, 1);
  }
  olderr = errno;
  if ((events = ppoll(fds, nfds, tsp, mask)) != -1) {
    lua_createtable(L, events, 0);
    for (i = 0; i < nfds; ++i) {
      if (fds[i].revents && fds[i].fd >= 0) {
        lua_pushinteger(L, fds[i].revents);
        lua_rawseti(L, -2, fds[i].fd);
      }
    }
    free(fds);
    return 1;
  } else {
    free(fds);
    return LuaUnixSysretErrno(L, "poll", olderr);
  }
}

// unix.recvfrom(fd:int[, bufsiz:int[, flags:int]])
//     ├─→ data:str, ip:uint32, port:uint16
//     ├─→ data:str, unixpath:str
//     └─→ nil, error:str, errno:int
static int LuaUnixRecvfrom(lua_State *L) {
  char *buf;
  size_t got;
  ssize_t rc;
  uint32_t addrsize;
  lua_Integer bufsiz;
  struct sockaddr_storage ss;
  int fd, flags, pushed, olderr = errno;
  addrsize = sizeof(ss);
  fd = luaL_checkinteger(L, 1);
  bufsiz = luaL_optinteger(L, 2, 1500);
  if (bufsiz < 0) bufsiz = 0;
  bufsiz = MIN(bufsiz, 0x7ffff000);
  flags = luaL_optinteger(L, 3, 0);
  buf = LuaAllocOrDie(L, bufsiz);
  if ((rc = recvfrom(fd, buf, bufsiz, flags, (struct sockaddr *)&ss,
                     &addrsize)) != -1) {
    got = rc;
    lua_pushlstring(L, buf, got);
    pushed = 1 + PushSockaddr(L, &ss);
    free(buf);
    return pushed;
  } else {
    free(buf);
    return LuaUnixSysretErrno(L, "recvfrom", olderr);
  }
}

// unix.recv(fd:int[, bufsiz:int[, flags:int]])
//     ├─→ data:str
//     └─→ nil, error:str, errno:int
static int LuaUnixRecv(lua_State *L) {
  char *buf;
  size_t got;
  ssize_t rc;
  lua_Integer bufsiz;
  int fd, flags, olderr = errno;
  fd = luaL_checkinteger(L, 1);
  bufsiz = luaL_optinteger(L, 2, 1500);
  if (bufsiz < 0) bufsiz = 0;
  bufsiz = MIN(bufsiz, 0x7ffff000);
  flags = luaL_optinteger(L, 3, 0);
  buf = LuaAllocOrDie(L, bufsiz);
  rc = recv(fd, buf, bufsiz, flags);
  if (rc != -1) {
    got = rc;
    lua_pushlstring(L, buf, got);
    free(buf);
    return 1;
  } else {
    free(buf);
    return LuaUnixSysretErrno(L, "recv", olderr);
  }
}

// unix.send(fd:int, data:str[, flags:int[, offset:int]])
//     ├─→ sent:int
//     └─→ nil, error:str, errno:int
//
// Sends `data[offset:]` on `fd`. `offset` defaults to 0 and is 0-based
// (unlike most Lua indexes); offsets past `#data` send an empty
// buffer. This lets partial-write loops avoid allocating a new
// substring every iteration:
//
//     local off = 0
//     while off < #data do
//       local n = assert(unix.send(fd, data, 0, off))
//       off = off + n
//     end
static int LuaUnixSend(lua_State *L) {
  size_t size;
  const char *data;
  lua_Integer offset;
  int fd, flags, olderr = errno;
  fd = luaL_checkinteger(L, 1);
  data = luaL_checklstring(L, 2, &size);
  flags = luaL_optinteger(L, 3, 0);
  offset = luaL_optinteger(L, 4, 0);
  if (offset < 0) offset = 0;
  if ((size_t)offset > size) offset = size;
  return SysretInteger(L, "send", olderr,
                       send(fd, data + offset, size - offset, flags));
}

// unix.sendto(fd:int, data:str, ip:uint32, port:uint16[, flags:int])
// unix.sendto(fd:int, data:str, unixpath:str[, flags:int])
//     ├─→ sent:int
//     └─→ nil, error:str, errno:int
static int LuaUnixSendto(lua_State *L) {
  size_t size;
  uint32_t salen;
  const char *data;
  struct sockaddr_storage ss;
  int i, fd, flags, olderr = errno;
  fd = luaL_checkinteger(L, 1);
  data = luaL_checklstring(L, 2, &size);
  i = MakeSockaddr(L, 3, &ss, &salen);
  flags = luaL_optinteger(L, i, 0);
  return SysretInteger(
      L, "sendto", olderr,
      sendto(fd, data, size, flags, (struct sockaddr *)&ss, salen));
}

// unix.shutdown(fd:int, how:int)
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixShutdown(lua_State *L) {
  int olderr = errno;
  return SysretBool(L, "shutdown", olderr,
                    shutdown(luaL_checkinteger(L, 1), luaL_checkinteger(L, 2)));
}

// unix.sigprocmask(how:int, newmask:unix.Sigset)
//     └─→ oldmask:unix.Sigset
static int LuaUnixSigprocmask(lua_State *L) {
  sigset_t oldmask;
  int olderr = errno;
  int how = luaL_checkinteger(L, 1);
  if (how != SIG_BLOCK && how != SIG_UNBLOCK && how != SIG_SETMASK) {
    errno = olderr;
    return luaL_argerror(L, 1, lua_pushfstring(L, "invalid how %d", how));
  }
  sigprocmask(how, luaL_checkudata(L, 2, "unix.Sigset"), &oldmask);
  LuaPushSigset(L, oldmask);
  return 1;
}

// Registry key (its unique address) for the table mapping signal number to
// Lua handler function. Held in the Lua registry rather than a user-visible
// global so scripts can't corrupt the dispatch table out from under us.
static const char kSignalHandlers;

// Deferred signal dispatch state. A real signal handler must not run Lua: the
// VM it interrupts may be mid-malloc or mid-GC, and Lua is not
// async-signal-safe. So LuaUnixOnSignal only records the signal and arms a Lua
// debug hook -- lua_sethook is the one Lua C API that's safe from signal
// context -- and LuaUnixSignalHook runs the Lua handler at the next VM
// instruction boundary, in normal context.
static volatile sig_atomic_t g_sigpending[NSIG + 1];
static lua_Hook g_basehook;
static int g_basehookmask;
static int g_basehookcount;
static int g_basehooksaved;

// Runs between VM instructions after one or more signals fired. Restores the
// hook that was active before we intercepted, then invokes each pending Lua
// handler. Because this is ordinary VM context (not signal context), calling
// back into Lua here is safe.
static void LuaUnixSignalHook(lua_State *L, lua_Debug *ar) {
  (void)ar;
  if (g_basehooksaved) {
    lua_sethook(L, g_basehook, g_basehookmask, g_basehookcount);
  } else {
    lua_sethook(L, NULL, 0, 0);
  }
  lua_rawgetp(L, LUA_REGISTRYINDEX, &kSignalHandlers);
  if (lua_type(L, -1) == LUA_TTABLE) {
    for (int sig = 1; sig <= NSIG; ++sig) {
      if (g_sigpending[sig]) {
        g_sigpending[sig] = 0;
        if (lua_rawgeti(L, -1, sig) == LUA_TFUNCTION) {
          lua_pushinteger(L, sig);
          if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
            ERRORF("(lua) %s failed: %s", strsignal(sig), lua_tostring(L, -1));
            lua_pop(L, 1);  // pop error
          }
        } else {
          lua_pop(L, 1);  // pop non-function
        }
      }
    }
  }
  lua_pop(L, 1);  // pop handler table
}

static void LuaUnixOnSignal(int sig, siginfo_t *si, void *ctx) {
  lua_State *L = GL;
  STRACE("LuaUnixOnSignal(%G)", sig);
  if (sig < 1 || sig > NSIG)
    return;
  g_sigpending[sig] = 1;
  // Defer to LuaUnixSignalHook at the next VM boundary. lua_sethook only
  // writes a handful of lua_State fields and is safe from signal context;
  // actually running the Lua handler here is not.
  lua_sethook(L, LuaUnixSignalHook,
              LUA_MASKCALL | LUA_MASKRET | LUA_MASKLINE | LUA_MASKCOUNT, 1);
}

// unix.sigaction(sig:int[, handler:func|int[, flags:int[, mask:unix.Sigset]]])
//     ├─→ oldhandler:func|int, flags:int, mask:unix.Sigset
//     └─→ nil, error:str, errno:int
static int LuaUnixSigaction(lua_State *L) {
  sigset_t *mask;
  int sig, olderr = errno;
  struct sigaction sa, oldsa, *saptr = &sa;
  sigemptyset(&sa.sa_mask);
  sig = luaL_checkinteger(L, 1);
  if (!(1 <= sig && sig <= NSIG)) {
    luaL_argerror(L, 1, "signal number invalid");
    __builtin_unreachable();
  }
  if (lua_isnoneornil(L, 2)) {
    // if handler/flags/mask aren't passed,
    // then we're quering the current state
    saptr = 0;
  } else if (lua_isinteger(L, 2)) {
    // bypass handling signals using lua code if possible
    sa.sa_sigaction = (void *)luaL_checkinteger(L, 2);
  } else if (lua_isfunction(L, 2)) {
    sa.sa_sigaction = LuaUnixOnSignal;
    // The C handler only records the signal and arms a debug hook, so it no
    // longer runs Lua in signal context; there's no need to mask every other
    // Lua handler. Just avoid re-entering the handler for the same signal.
    sigaddset(&sa.sa_mask, sig);
    // Remember the debug hook that was active before we start intercepting, so
    // LuaUnixSignalHook can restore it. Captured once: this C call is itself a
    // VM boundary, so any previously armed dispatch hook has already fired and
    // lua_gethook returns the genuine base hook rather than our own.
    if (!g_basehooksaved) {
      g_basehook = lua_gethook(L);
      g_basehookmask = lua_gethookmask(L);
      g_basehookcount = lua_gethookcount(L);
      g_basehooksaved = 1;
    }
  } else {
    luaL_argerror(L, 2, "sigaction handler not integer or function");
    __builtin_unreachable();
  }
  if (!lua_isnoneornil(L, 4)) {
    mask = luaL_checkudata(L, 4, "unix.Sigset");
    sigorset(&sa.sa_mask, &sa.sa_mask, mask);
  }
  if (lua_isnoneornil(L, 3)) {
    sa.sa_flags = 0;
  } else {
    sa.sa_flags = lua_tointeger(L, 3);
  }
  // flags and mask are consumed into C values above, so drop every
  // slot past the handler unconditionally. The old code removed only
  // NON-nil slots, so an explicit trailing nil (sigaction(sig, fn,
  // nil, nil)) lingered and shifted the handler's stack position — the
  // registry then recorded nil instead of the Lua handler, which
  // therefore never dispatched.
  lua_settop(L, 2);
  if (!sigaction(sig, saptr, &oldsa)) {
    lua_rawgetp(L, LUA_REGISTRYINDEX, &kSignalHandlers);
    // push the old handler result to stack. if the registry handler
    // table has a real function, then we prefer to return that. if it's
    // absent or a raw integer value, then we're better off returning
    // what the kernel gave us in &oldsa.
    if (lua_rawgeti(L, -1, sig) != LUA_TFUNCTION) {
      lua_pop(L, 1);
      lua_pushinteger(L, (intptr_t)oldsa.sa_handler);
    }
    if (saptr) {
      // update the registry lua table
      if (sa.sa_sigaction == LuaUnixOnSignal) {
        lua_pushvalue(L, -3);
      } else {
        lua_pushnil(L);
      }
      lua_rawseti(L, -3, sig);
    }
    // remove the signal handler table from stack
    lua_remove(L, -2);
    // finish pushing the last 2/3 results
    lua_pushinteger(L, oldsa.sa_flags);
    LuaPushSigset(L, oldsa.sa_mask);
    return 3;
  } else {
    return LuaUnixSysretErrno(L, "sigaction", olderr);
  }
}

// unix.sigsuspend([mask:Sigmask])
//     └─→ nil, error:str, errno:int
static int LuaUnixSigsuspend(lua_State *L) {
  int olderr = errno;
  sigsuspend(!lua_isnoneornil(L, 1) ? luaL_checkudata(L, 1, "unix.Sigset") : 0);
  return LuaUnixSysretErrno(L, "sigsuspend", olderr);
}

// unix.sigpending()
//     └─→ mask:unix.Sigset
static int LuaUnixSigpending(lua_State *L) {
  sigset_t mask;
  sigpending(&mask);
  LuaPushSigset(L, mask);
  return 1;
}

// unix.setitimer(which[, intervalsec, intns, valuesec, valuens])
//     ├─→ previous:table
//     └─→ nil, error:str, errno:int
static int LuaUnixSetitimer(lua_State *L) {
  int which, olderr = errno;
  struct itimerval it, oldit, *itptr;
  which = luaL_checkinteger(L, 1);
  if (!lua_isnoneornil(L, 2)) {
    itptr = &it;
    it.it_interval.tv_sec = luaL_optinteger(L, 2, 0);
    it.it_interval.tv_usec = luaL_optinteger(L, 3, 0) / 1000;
    it.it_value.tv_sec = luaL_optinteger(L, 4, 0);
    it.it_value.tv_usec = luaL_optinteger(L, 5, 0) / 1000;
  } else {
    itptr = 0;
  }
  if (!setitimer(which, itptr, &oldit)) {
    lua_newtable(L);
    lua_pushinteger(L, oldit.it_interval.tv_sec);
    lua_setfield(L, -2, "intervalsec");
    lua_pushinteger(L, oldit.it_interval.tv_usec * 1000);
    lua_setfield(L, -2, "intervalns");
    lua_pushinteger(L, oldit.it_value.tv_sec);
    lua_setfield(L, -2, "valuesec");
    lua_pushinteger(L, oldit.it_value.tv_usec * 1000);
    lua_setfield(L, -2, "valuens");
    return 1;
  } else {
    return LuaUnixSysretErrno(L, "setitimer", olderr);
  }
}

static int LuaUnixStr(lua_State *L, char *f(int)) {
  return ReturnString(L, f(luaL_checkinteger(L, 1)));
}

// unix.strsignal(sig:int)
//     └─→ symbol:str
static int LuaUnixStrsignal(lua_State *L) {
  return LuaUnixStr(L, strsignal);
}

// unix.WIFEXITED(wstatus)
//     └─→ bool
static int LuaUnixWifexited(lua_State *L) {
  return ReturnBoolean(L, !!WIFEXITED(luaL_checkinteger(L, 1)));
}

// unix.WEXITSTATUS(wstatus)
//     └─→ exitcode:uint8
static int LuaUnixWexitstatus(lua_State *L) {
  return ReturnInteger(L, WEXITSTATUS(luaL_checkinteger(L, 1)));
}

// unix.WIFSIGNALED(wstatus)
//     └─→ bool
static int LuaUnixWifsignaled(lua_State *L) {
  return ReturnBoolean(L, !!WIFSIGNALED(luaL_checkinteger(L, 1)));
}

// unix.WTERMSIG(wstatus)
//     └─→ sig:uint8
static int LuaUnixWtermsig(lua_State *L) {
  return ReturnInteger(L, WTERMSIG(luaL_checkinteger(L, 1)));
}

static dontinline int LuaUnixTime(lua_State *L, const char *call,
                                  struct tm *f(const time_t *, struct tm *)) {
  int64_t ts;
  struct tm tm;
  int olderr = errno;
  ts = luaL_checkinteger(L, 1);
  if (f(&ts, &tm)) {
    lua_newtable(L);
    lua_pushinteger(L, tm.tm_year + 1900); lua_setfield(L, -2, "year");
    lua_pushinteger(L, tm.tm_mon + 1);     lua_setfield(L, -2, "mon");
    lua_pushinteger(L, tm.tm_mday);        lua_setfield(L, -2, "mday");
    lua_pushinteger(L, tm.tm_hour);        lua_setfield(L, -2, "hour");
    lua_pushinteger(L, tm.tm_min);         lua_setfield(L, -2, "min");
    lua_pushinteger(L, tm.tm_sec);         lua_setfield(L, -2, "sec");
    lua_pushinteger(L, tm.tm_gmtoff);      lua_setfield(L, -2, "gmtoffsec");
    lua_pushinteger(L, tm.tm_wday);        lua_setfield(L, -2, "wday");
    lua_pushinteger(L, tm.tm_yday);        lua_setfield(L, -2, "yday");
    lua_pushinteger(L, tm.tm_isdst);       lua_setfield(L, -2, "dst");
    lua_pushstring(L, tm.tm_zone);         lua_setfield(L, -2, "zone");
    return 1;
  } else {
    return LuaUnixSysretErrno(L, call, olderr);
  }
}

// unix.gmtime(unixsecs:int)
//     ├─→ bdt:unix.BrokenDownTime
//     └─→ nil, error:str, errno:int
static int LuaUnixGmtime(lua_State *L) {
  return LuaUnixTime(L, "gmtime", gmtime_r);
}

// unix.localtime(unixts:int)
//     ├─→ bdt:unix.BrokenDownTime
//     └─→ nil, error:str, errno:int
static int LuaUnixLocaltime(lua_State *L) {
  return LuaUnixTime(L, "localtime", localtime_r);
}

// unix.major(rdev:int)
//     └─→ major:int
static int LuaUnixMajor(lua_State *L) {
  return ReturnInteger(L, major(luaL_checkinteger(L, 1)));
}

// unix.minor(rdev:int)
//     └─→ minor:int
static int LuaUnixMinor(lua_State *L) {
  return ReturnInteger(L, minor(luaL_checkinteger(L, 1)));
}

// unix.S_ISDIR(mode:int)
//     └─→ bool
static int LuaUnixSisdir(lua_State *L) {
  lua_pushboolean(L, S_ISDIR(luaL_checkinteger(L, 1)));
  return 1;
}

// unix.S_ISCHR(mode:int)
//     └─→ bool
static int LuaUnixSischr(lua_State *L) {
  lua_pushboolean(L, S_ISCHR(luaL_checkinteger(L, 1)));
  return 1;
}

// unix.S_ISBLK(mode:int)
//     └─→ bool
static int LuaUnixSisblk(lua_State *L) {
  lua_pushboolean(L, S_ISBLK(luaL_checkinteger(L, 1)));
  return 1;
}

// unix.S_ISREG(mode:int)
//     └─→ bool
static int LuaUnixSisreg(lua_State *L) {
  lua_pushboolean(L, S_ISREG(luaL_checkinteger(L, 1)));
  return 1;
}

// unix.S_ISFIFO(mode:int)
//     └─→ bool
static int LuaUnixSisfifo(lua_State *L) {
  lua_pushboolean(L, S_ISFIFO(luaL_checkinteger(L, 1)));
  return 1;
}

// unix.S_ISLNK(mode:int)
//     └─→ bool
static int LuaUnixSislnk(lua_State *L) {
  lua_pushboolean(L, S_ISLNK(luaL_checkinteger(L, 1)));
  return 1;
}

// unix.S_ISSOCK(mode:int)
//     └─→ bool
static int LuaUnixSissock(lua_State *L) {
  lua_pushboolean(L, S_ISSOCK(luaL_checkinteger(L, 1)));
  return 1;
}

// unix.isatty(fd:int)
//     ├─→ true
//     ├─→ false
//     └─→ nil, error:str, errno:int
static int LuaUnixIsatty(lua_State *L) {
  int olderr = errno;
  int rc = isatty(luaL_checkinteger(L, 1));
  if (rc == -1) {
    return LuaUnixSysretErrno(L, "isatty", olderr);
  } else {
    lua_pushboolean(L, rc != 0);
    return 1;
  }
}

// unix.tiocgwinsz(fd:int)
//     ├─→ rows:int, cols:int
//     └─→ nil, error:str, errno:int
static int LuaUnixTiocgwinsz(lua_State *L) {
  struct winsize ws;
  int olderr = errno;
  if (!ioctl(luaL_checkinteger(L, 1), TIOCGWINSZ, &ws)) {
    lua_pushinteger(L, ws.ws_row);
    lua_pushinteger(L, ws.ws_col);
    return 2;
  } else {
    return LuaUnixSysretErrno(L, "tiocgwinsz", olderr);
  }
}

// unix.tcgetattr(fd:int)
//     ├─→ termios:table
//     └─→ nil, error:str, errno:int
static int LuaUnixTcgetattr(lua_State *L) {
  struct termios tio;
  int olderr = errno;
  int fd = luaL_checkinteger(L, 1);
  if (tcgetattr(fd, &tio) != -1) {
    lua_newtable(L);
    lua_pushinteger(L, tio.c_iflag);
    lua_setfield(L, -2, "iflag");
    lua_pushinteger(L, tio.c_oflag);
    lua_setfield(L, -2, "oflag");
    lua_pushinteger(L, tio.c_cflag);
    lua_setfield(L, -2, "cflag");
    lua_pushinteger(L, tio.c_lflag);
    lua_setfield(L, -2, "lflag");
    lua_newtable(L);
    for (int i = 0; i < NCCS; i++) {
      lua_pushinteger(L, tio.c_cc[i]);
      lua_rawseti(L, -2, i + 1);
    }
    lua_setfield(L, -2, "cc");
    lua_pushinteger(L, cfgetispeed(&tio));
    lua_setfield(L, -2, "ispeed");
    lua_pushinteger(L, cfgetospeed(&tio));
    lua_setfield(L, -2, "ospeed");
    return 1;
  } else {
    return LuaUnixSysretErrno(L, "tcgetattr", olderr);
  }
}

// unix.tcsetattr(fd:int, action:int, termios:table)
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixTcsetattr(lua_State *L) {
  struct termios tio;
  int olderr = errno;
  int fd = luaL_checkinteger(L, 1);
  int action = luaL_checkinteger(L, 2);
  luaL_checktype(L, 3, LUA_TTABLE);
  memset(&tio, 0, sizeof(tio));
  lua_getfield(L, 3, "iflag");
  tio.c_iflag = luaL_optinteger(L, -1, 0);
  lua_pop(L, 1);
  lua_getfield(L, 3, "oflag");
  tio.c_oflag = luaL_optinteger(L, -1, 0);
  lua_pop(L, 1);
  lua_getfield(L, 3, "cflag");
  tio.c_cflag = luaL_optinteger(L, -1, 0);
  lua_pop(L, 1);
  lua_getfield(L, 3, "lflag");
  tio.c_lflag = luaL_optinteger(L, -1, 0);
  lua_pop(L, 1);
  lua_getfield(L, 3, "cc");
  if (lua_istable(L, -1)) {
    for (int i = 0; i < NCCS; i++) {
      lua_rawgeti(L, -1, i + 1);
      tio.c_cc[i] = luaL_optinteger(L, -1, 0);
      lua_pop(L, 1);
    }
  }
  lua_pop(L, 1);
  lua_getfield(L, 3, "ispeed");
  if (!lua_isnil(L, -1)) {
    cfsetispeed(&tio, luaL_checkinteger(L, -1));
  }
  lua_pop(L, 1);
  lua_getfield(L, 3, "ospeed");
  if (!lua_isnil(L, -1)) {
    cfsetospeed(&tio, luaL_checkinteger(L, -1));
  }
  lua_pop(L, 1);
  if (tcsetattr(fd, action, &tio) != -1) {
    lua_pushboolean(L, 1);
    return 1;
  } else {
    return LuaUnixSysretErrno(L, "tcsetattr", olderr);
  }
}

// unix.sched_yield()
static int LuaUnixSchedYield(lua_State *L) {
  pthread_yield();
  return 0;
}

// unix.daemon([nochdir:bool[, noclose:bool]])
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixDaemon(lua_State *L) {
  int olderr = errno;
  int nochdir = lua_toboolean(L, 1);
  int noclose = lua_toboolean(L, 2);
  int rc = daemon(nochdir, noclose);
  if (rc != -1) {
    lua_pushboolean(L, 1);
    return 1;
  } else {
    return LuaUnixSysretErrno(L, "daemon", olderr);
  }
}

// unix.nice(inc:int)
//     ├─→ priority:int
//     └─→ nil, error:str, errno:int
static int LuaUnixNice(lua_State *L) {
  int olderr = errno;
  int inc = luaL_checkinteger(L, 1);
  errno = 0;
  int rc = nice(inc);
  if (rc == -1 && errno != 0) {
    return LuaUnixSysretErrno(L, "nice", olderr);
  }
  errno = olderr;
  lua_pushinteger(L, rc);
  return 1;
}

// unix.getpriority(which:int, who:int)
//     ├─→ priority:int
//     └─→ nil, error:str, errno:int
//
// which can be:
//   - unix.PRIO_PROCESS (0) - who is process id (0 = calling process)
//   - unix.PRIO_PGRP (1) - who is process group id (0 = calling process group)
//   - unix.PRIO_USER (2) - who is user id (0 = calling user)
static int LuaUnixGetpriority(lua_State *L) {
  int olderr = errno;
  int which = luaL_checkinteger(L, 1);
  int who = luaL_checkinteger(L, 2);
  errno = 0;
  int rc = getpriority(which, who);
  if (rc == -1 && errno != 0) {
    return LuaUnixSysretErrno(L, "getpriority", olderr);
  }
  errno = olderr;
  lua_pushinteger(L, rc);
  return 1;
}

// unix.setpriority(which:int, who:int, prio:int)
//     ├─→ true
//     └─→ nil, error:str, errno:int
//
// which can be:
//   - unix.PRIO_PROCESS (0) - who is process id (0 = calling process)
//   - unix.PRIO_PGRP (1) - who is process group id (0 = calling process group)
//   - unix.PRIO_USER (2) - who is user id (0 = calling user)
static int LuaUnixSetpriority(lua_State *L) {
  int olderr = errno;
  int which = luaL_checkinteger(L, 1);
  int who = luaL_checkinteger(L, 2);
  int prio = luaL_checkinteger(L, 3);
  int rc = setpriority(which, who, prio);
  if (rc != -1) {
    lua_pushboolean(L, 1);
    return 1;
  } else {
    return LuaUnixSysretErrno(L, "setpriority", olderr);
  }
}

// unix.verynice()
static int LuaUnixVerynice(lua_State *L) {
  verynice();
  return 0;
}

////////////////////////////////////////////////////////////////////////////////
// unix.Stat object

static struct stat *GetUnixStat(lua_State *L) {
  return luaL_checkudata(L, 1, "unix.Stat");
}

// unix.Stat:size()
//     └─→ bytes:int
static int LuaUnixStatSize(lua_State *L) {
  return ReturnInteger(L, GetUnixStat(L)->st_size);
}

// unix.Stat:mode()
//     └─→ mode:int
static int LuaUnixStatMode(lua_State *L) {
  return ReturnInteger(L, GetUnixStat(L)->st_mode);
}

// unix.Stat:dev()
//     └─→ dev:int
static int LuaUnixStatDev(lua_State *L) {
  return ReturnInteger(L, GetUnixStat(L)->st_dev);
}

// unix.Stat:ino()
//     └─→ inodeint
static int LuaUnixStatIno(lua_State *L) {
  return ReturnInteger(L, GetUnixStat(L)->st_ino);
}

// unix.Stat:nlink()
//     └─→ count:int
static int LuaUnixStatNlink(lua_State *L) {
  return ReturnInteger(L, GetUnixStat(L)->st_nlink);
}

// unix.Stat:rdev()
//     └─→ rdev:int
static int LuaUnixStatRdev(lua_State *L) {
  return ReturnInteger(L, GetUnixStat(L)->st_rdev);
}

// unix.Stat:uid()
//     └─→ uid:int
static int LuaUnixStatUid(lua_State *L) {
  return ReturnInteger(L, GetUnixStat(L)->st_uid);
}

// unix.Stat:gid()
//     └─→ gid:int
static int LuaUnixStatGid(lua_State *L) {
  return ReturnInteger(L, GetUnixStat(L)->st_gid);
}

// unix.Stat:blocks()
//     └─→ count:int
static int LuaUnixStatBlocks(lua_State *L) {
  return ReturnInteger(L, GetUnixStat(L)->st_blocks);
}

// unix.Stat:blksize()
//     └─→ bytes:int
static int LuaUnixStatBlksize(lua_State *L) {
  return ReturnInteger(L, GetUnixStat(L)->st_blksize);
}

static dontinline int ReturnTimespec(lua_State *L, struct timespec *ts) {
  lua_pushinteger(L, ts->tv_sec);
  lua_pushinteger(L, ts->tv_nsec);
  return 2;
}

// unix.Stat:atim()
//     └─→ unixts:int, nanos:int
static int LuaUnixStatAtim(lua_State *L) {
  return ReturnTimespec(L, &GetUnixStat(L)->st_atim);
}

// unix.Stat:mtim()
//     └─→ unixts:int, nanos:int
static int LuaUnixStatMtim(lua_State *L) {
  return ReturnTimespec(L, &GetUnixStat(L)->st_mtim);
}

// unix.Stat:ctim()
//     └─→ unixts:int, nanos:int
static int LuaUnixStatCtim(lua_State *L) {
  return ReturnTimespec(L, &GetUnixStat(L)->st_ctim);
}

// unix.Stat:birthtim()
//     └─→ unixts:int, nanos:int
static int LuaUnixStatBirthtim(lua_State *L) {
  return ReturnTimespec(L, &GetUnixStat(L)->st_birthtim);
}

// unix.Stat:gen()
//     └─→ gen:int [xnu/bsd]
static int LuaUnixStatGen(lua_State *L) {
  return ReturnInteger(L, GetUnixStat(L)->st_gen);
}

// unix.Stat:flags()
//     └─→ flags:int [xnu/bsd]
static int LuaUnixStatFlags(lua_State *L) {
  return ReturnInteger(L, GetUnixStat(L)->st_flags);
}

static int LuaUnixStatToString(lua_State *L) {
  char ibuf[21];
  luaL_Buffer b;
  struct stat *st;
  st = GetUnixStat(L);
  luaL_buffinit(L, &b);
  luaL_addstring(&b, "unix.Stat({size=");
  FormatInt64(ibuf, st->st_size);
  luaL_addstring(&b, ibuf);
  if (st->st_mode) {
    luaL_addstring(&b, ", mode=");
    FormatOctal32(ibuf, st->st_mode, 1);
    luaL_addstring(&b, ibuf);
  }
  if (st->st_ino) {
    luaL_addstring(&b, ", ino=");
    FormatUint64(ibuf, st->st_ino);
    luaL_addstring(&b, ibuf);
  }
  if (st->st_nlink) {
    luaL_addstring(&b, ", nlink=");
    FormatUint64(ibuf, st->st_nlink);
    luaL_addstring(&b, ibuf);
  }
  if (st->st_uid) {
    luaL_addstring(&b, ", uid=");
    FormatUint32(ibuf, st->st_uid);
    luaL_addstring(&b, ibuf);
  }
  if (st->st_gid) {
    luaL_addstring(&b, ", gid=");
    FormatUint32(ibuf, st->st_gid);
    luaL_addstring(&b, ibuf);
  }
  if (st->st_flags) {
    luaL_addstring(&b, ", flags=");
    FormatUint32(ibuf, st->st_flags);
    luaL_addstring(&b, ibuf);
  }
  if (st->st_dev) {
    luaL_addstring(&b, ", dev=");
    FormatUint64(ibuf, st->st_dev);
    luaL_addstring(&b, ibuf);
  }
  if (st->st_rdev) {
    luaL_addstring(&b, ", rdev=");
    FormatUint64(ibuf, st->st_rdev);
    luaL_addstring(&b, ibuf);
  }
  if (st->st_blksize) {
    luaL_addstring(&b, ", blksize=");
    FormatInt64(ibuf, st->st_blksize);
    luaL_addstring(&b, ibuf);
  }
  if (st->st_blocks) {
    luaL_addstring(&b, ", blocks=");
    FormatInt64(ibuf, st->st_blocks);
    luaL_addstring(&b, ibuf);
  }
  luaL_addstring(&b, "})");
  luaL_pushresult(&b);
  return 1;
}

static const luaL_Reg kLuaUnixStatMeth[] = {
    {"atim", LuaUnixStatAtim},          //
    {"birthtim", LuaUnixStatBirthtim},  //
    {"blksize", LuaUnixStatBlksize},    //
    {"blocks", LuaUnixStatBlocks},      //
    {"ctim", LuaUnixStatCtim},          //
    {"dev", LuaUnixStatDev},            //
    {"gid", LuaUnixStatGid},            //
    {"ino", LuaUnixStatIno},            //
    {"mode", LuaUnixStatMode},          //
    {"mtim", LuaUnixStatMtim},          //
    {"nlink", LuaUnixStatNlink},        //
    {"rdev", LuaUnixStatRdev},          //
    {"size", LuaUnixStatSize},          //
    {"uid", LuaUnixStatUid},            //
    {"flags", LuaUnixStatFlags},        //
    {"gen", LuaUnixStatGen},            //
    {0},                                //
};

static const luaL_Reg kLuaUnixStatMeta[] = {
    {"__tostring", LuaUnixStatToString},  //
    {"__repr", LuaUnixStatToString},      //
    {0},                                  //
};

static void LuaUnixStatObj(lua_State *L) {
  luaL_newmetatable(L, "unix.Stat");
  luaL_setfuncs(L, kLuaUnixStatMeta, 0);
  luaL_newlibtable(L, kLuaUnixStatMeth);
  luaL_setfuncs(L, kLuaUnixStatMeth, 0);
  lua_setfield(L, -2, "__index");
  lua_pop(L, 1);
}

////////////////////////////////////////////////////////////////////////////////
// unix.Statfs object

static struct statfs *GetUnixStatfs(lua_State *L) {
  return luaL_checkudata(L, 1, "unix.Statfs");
}

// unix.Statfs:type()
//     └─→ bytes:int
static int LuaUnixStatfsType(lua_State *L) {
  return ReturnInteger(L, GetUnixStatfs(L)->f_type);
}

// unix.Statfs:bsize()
//     └─→ bsize:int
static int LuaUnixStatfsBsize(lua_State *L) {
  return ReturnInteger(L, GetUnixStatfs(L)->f_bsize);
}

// unix.Statfs:blocks()
//     └─→ blocks:int
static int LuaUnixStatfsBlocks(lua_State *L) {
  return ReturnInteger(L, GetUnixStatfs(L)->f_blocks);
}

// unix.Statfs:bfree()
//     └─→ bfreedeint
static int LuaUnixStatfsBfree(lua_State *L) {
  return ReturnInteger(L, GetUnixStatfs(L)->f_bfree);
}

// unix.Statfs:bavail()
//     └─→ count:int
static int LuaUnixStatfsBavail(lua_State *L) {
  return ReturnInteger(L, GetUnixStatfs(L)->f_bavail);
}

// unix.Statfs:files()
//     └─→ files:int
static int LuaUnixStatfsFiles(lua_State *L) {
  return ReturnInteger(L, GetUnixStatfs(L)->f_files);
}

// unix.Statfs:ffree()
//     └─→ ffree:int
static int LuaUnixStatfsFfree(lua_State *L) {
  return ReturnInteger(L, GetUnixStatfs(L)->f_ffree);
}

// unix.Statfs:fsid()
//     └─→ x:int, y:int
static int LuaUnixStatfsFsid(lua_State *L) {
  struct statfs *f = GetUnixStatfs(L);
  lua_pushinteger(L, f->f_fsid.__val[0]);
  lua_pushinteger(L, f->f_fsid.__val[1]);
  return 2;
}

// unix.Statfs:namelen()
//     └─→ count:int
static int LuaUnixStatfsNamelen(lua_State *L) {
  return ReturnInteger(L, GetUnixStatfs(L)->f_namelen);
}

// unix.Statfs:frsize()
//     └─→ bytes:int
static int LuaUnixStatfsFrsize(lua_State *L) {
  return ReturnInteger(L, GetUnixStatfs(L)->f_frsize);
}

// unix.Statfs:flags()
//     └─→ bytes:int
static int LuaUnixStatfsFlags(lua_State *L) {
  return ReturnInteger(L, GetUnixStatfs(L)->f_flags);
}

// unix.Statfs:owner()
//     └─→ bytes:int
static int LuaUnixStatfsOwner(lua_State *L) {
  return ReturnInteger(L, GetUnixStatfs(L)->f_owner);
}

// unix.Statfs:fstypename()
//     └─→ fstypename:str
static int LuaUnixStatfsFstypename(lua_State *L) {
  return ReturnString(L, GetUnixStatfs(L)->f_fstypename);
}

static int LuaUnixStatfsToString(lua_State *L) {
  char ibuf[21];
  luaL_Buffer b;
  struct statfs *f;
  f = GetUnixStatfs(L);
  luaL_buffinit(L, &b);
  luaL_addstring(&b, "unix.Statfs({type=");
  FormatInt64(ibuf, f->f_type);
  luaL_addstring(&b, ibuf);
  luaL_addstring(&b, ", fstypename=\"");
  luaL_addstring(&b, f->f_fstypename);
  luaL_addstring(&b, "\"");
  if (f->f_bsize) {
    luaL_addstring(&b, ", bsize=");
    FormatInt64(ibuf, f->f_bsize);
    luaL_addstring(&b, ibuf);
  }
  if (f->f_blocks) {
    luaL_addstring(&b, ", blocks=");
    FormatInt64(ibuf, f->f_blocks);
    luaL_addstring(&b, ibuf);
  }
  if (f->f_bfree) {
    luaL_addstring(&b, ", bfree=");
    FormatInt64(ibuf, f->f_bfree);
    luaL_addstring(&b, ibuf);
  }
  if (f->f_bavail) {
    luaL_addstring(&b, ", bavail=");
    FormatInt64(ibuf, f->f_bavail);
    luaL_addstring(&b, ibuf);
  }
  if (f->f_files) {
    luaL_addstring(&b, ", files=");
    FormatInt64(ibuf, f->f_files);
    luaL_addstring(&b, ibuf);
  }
  if (f->f_ffree) {
    luaL_addstring(&b, ", ffree=");
    FormatInt64(ibuf, f->f_ffree);
    luaL_addstring(&b, ibuf);
  }
  if (f->f_fsid.__val[0] || f->f_fsid.__val[1]) {
    luaL_addstring(&b, ", fsid={");
    FormatUint64(ibuf, f->f_fsid.__val[0]);
    luaL_addstring(&b, ibuf);
    luaL_addstring(&b, ", ");
    FormatUint64(ibuf, f->f_fsid.__val[1]);
    luaL_addstring(&b, ibuf);
    luaL_addstring(&b, "}");
  }
  if (f->f_namelen) {
    luaL_addstring(&b, ", namelen=");
    FormatUint64(ibuf, f->f_namelen);
    luaL_addstring(&b, ibuf);
  }
  if (f->f_flags) {
    luaL_addstring(&b, ", flags=");
    FormatHex64(ibuf, f->f_flags, 2);
    luaL_addstring(&b, ibuf);
  }
  if (f->f_owner) {
    luaL_addstring(&b, ", owner=");
    FormatUint32(ibuf, f->f_owner);
    luaL_addstring(&b, ibuf);
  }
  luaL_addstring(&b, "})");
  luaL_pushresult(&b);
  return 1;
}

static const luaL_Reg kLuaUnixStatfsMeth[] = {
    {"type", LuaUnixStatfsType},              //
    {"bsize", LuaUnixStatfsBsize},            //
    {"blocks", LuaUnixStatfsBlocks},          //
    {"bfree", LuaUnixStatfsBfree},            //
    {"bavail", LuaUnixStatfsBavail},          //
    {"files", LuaUnixStatfsFiles},            //
    {"ffree", LuaUnixStatfsFfree},            //
    {"fsid", LuaUnixStatfsFsid},              //
    {"namelen", LuaUnixStatfsNamelen},        //
    {"frsize", LuaUnixStatfsFrsize},          //
    {"flags", LuaUnixStatfsFlags},            //
    {"owner", LuaUnixStatfsOwner},            //
    {"fstypename", LuaUnixStatfsFstypename},  //
    {0},                                      //
};

static const luaL_Reg kLuaUnixStatfsMeta[] = {
    {"__tostring", LuaUnixStatfsToString},  //
    {"__repr", LuaUnixStatfsToString},      //
    {0},                                    //
};

static void LuaUnixStatfsObj(lua_State *L) {
  luaL_newmetatable(L, "unix.Statfs");
  luaL_setfuncs(L, kLuaUnixStatfsMeta, 0);
  luaL_newlibtable(L, kLuaUnixStatfsMeth);
  luaL_setfuncs(L, kLuaUnixStatfsMeth, 0);
  lua_setfield(L, -2, "__index");
  lua_pop(L, 1);
}

////////////////////////////////////////////////////////////////////////////////
// unix.Rusage object

static struct rusage *GetUnixRusage(lua_State *L) {
  return luaL_checkudata(L, 1, "unix.Rusage");
}

static dontinline int ReturnTimeval(lua_State *L, struct timeval *tv) {
  lua_pushinteger(L, tv->tv_sec);
  lua_pushinteger(L, tv->tv_usec * 1000);
  return 2;
}

// unix.Rusage:utime()
//     └─→ unixts:int, nanos:int
static int LuaUnixRusageUtime(lua_State *L) {
  return ReturnTimeval(L, &GetUnixRusage(L)->ru_utime);
}

// unix.Rusage:stime()
//     └─→ unixts:int, nanos:int
static int LuaUnixRusageStime(lua_State *L) {
  return ReturnTimeval(L, &GetUnixRusage(L)->ru_stime);
}

// unix.Rusage:maxrss()
//     └─→ kilobytes:int
static int LuaUnixRusageMaxrss(lua_State *L) {
  return ReturnInteger(L, GetUnixRusage(L)->ru_maxrss);
}

// unix.Rusage:ixrss()
//     └─→ integralkilobytes:int
static int LuaUnixRusageIxrss(lua_State *L) {
  return ReturnInteger(L, GetUnixRusage(L)->ru_ixrss);
}

// unid.Rusage:idrss()
//     └─→ integralkilobytes:int
static int LuaUnixRusageIdrss(lua_State *L) {
  return ReturnInteger(L, GetUnixRusage(L)->ru_idrss);
}

// unis.Rusage:isrss()
//     └─→ integralkilobytes:int
static int LuaUnixRusageIsrss(lua_State *L) {
  return ReturnInteger(L, GetUnixRusage(L)->ru_isrss);
}

// unix.Rusage:minflt()
//     └─→ count:int
static int LuaUnixRusageMinflt(lua_State *L) {
  return ReturnInteger(L, GetUnixRusage(L)->ru_minflt);
}

// unix.Rusage:majflt()
//     └─→ count:int
static int LuaUnixRusageMajflt(lua_State *L) {
  return ReturnInteger(L, GetUnixRusage(L)->ru_majflt);
}

// unix.Rusage:nswap()
//     └─→ count:int
static int LuaUnixRusageNswap(lua_State *L) {
  return ReturnInteger(L, GetUnixRusage(L)->ru_nswap);
}

// unix.Rusage:inblock()
//     └─→ count:int
static int LuaUnixRusageInblock(lua_State *L) {
  return ReturnInteger(L, GetUnixRusage(L)->ru_inblock);
}

// unix.Rusage:oublock()
//     └─→ count:int
static int LuaUnixRusageOublock(lua_State *L) {
  return ReturnInteger(L, GetUnixRusage(L)->ru_oublock);
}

// unix.Rusage:msgsnd()
//     └─→ count:int
static int LuaUnixRusageMsgsnd(lua_State *L) {
  return ReturnInteger(L, GetUnixRusage(L)->ru_msgsnd);
}

// unix.Rusage:msgrcv()
//     └─→ count:int
static int LuaUnixRusageMsgrcv(lua_State *L) {
  return ReturnInteger(L, GetUnixRusage(L)->ru_msgrcv);
}

// unix.Rusage:nsignals()
//     └─→ count:int
static int LuaUnixRusageNsignals(lua_State *L) {
  return ReturnInteger(L, GetUnixRusage(L)->ru_nsignals);
}

// unix.Rusage:nvcsw()
//     └─→ count:int
static int LuaUnixRusageNvcsw(lua_State *L) {
  return ReturnInteger(L, GetUnixRusage(L)->ru_nvcsw);
}

// unix.Rusage:nivcsw()
//     └─→ count:int
static int LuaUnixRusageNivcsw(lua_State *L) {
  return ReturnInteger(L, GetUnixRusage(L)->ru_nivcsw);
}

static int LuaUnixRusageToString(lua_State *L) {
  char *b = 0;
  struct rusage *ru = GetUnixRusage(L);
  appends(&b, "{");
  appendf(&b, "%s={%ld, %ld}", "utime", ru->ru_utime.tv_sec,
          ru->ru_utime.tv_usec * 1000);
  if (ru->ru_stime.tv_sec || ru->ru_stime.tv_usec) {
    appendw(&b, READ16LE(", "));
    appendf(&b, "%s={%ld, %ld}", "stime", ru->ru_stime.tv_sec,
            ru->ru_stime.tv_usec * 1000);
  }
  if (ru->ru_maxrss) appendf(&b, ", %s=%ld", "maxrss", ru->ru_maxrss);
  if (ru->ru_ixrss) appendf(&b, ", %s=%ld", "ixrss", ru->ru_ixrss);
  if (ru->ru_idrss) appendf(&b, ", %s=%ld", "idrss", ru->ru_idrss);
  if (ru->ru_isrss) appendf(&b, ", %s=%ld", "isrss", ru->ru_isrss);
  if (ru->ru_minflt) appendf(&b, ", %s=%ld", "minflt", ru->ru_minflt);
  if (ru->ru_majflt) appendf(&b, ", %s=%ld", "majflt", ru->ru_majflt);
  if (ru->ru_nswap) appendf(&b, ", %s=%ld", "nswap", ru->ru_nswap);
  if (ru->ru_inblock) appendf(&b, ", %s=%ld", "inblock", ru->ru_inblock);
  if (ru->ru_oublock) appendf(&b, ", %s=%ld", "oublock", ru->ru_oublock);
  if (ru->ru_msgsnd) appendf(&b, ", %s=%ld", "msgsnd", ru->ru_msgsnd);
  if (ru->ru_msgrcv) appendf(&b, ", %s=%ld", "msgrcv", ru->ru_msgrcv);
  if (ru->ru_nsignals) appendf(&b, ", %s=%ld", "nsignals", ru->ru_nsignals);
  if (ru->ru_nvcsw) appendf(&b, ", %s=%ld", "nvcsw", ru->ru_nvcsw);
  if (ru->ru_nivcsw) appendf(&b, ", %s=%ld", "nivcsw", ru->ru_nivcsw);
  appendw(&b, '}');
  lua_pushlstring(L, b, appendz(b).i);
  return 1;
}

static const luaL_Reg kLuaUnixRusageMeth[] = {
    {"utime", LuaUnixRusageUtime},        //
    {"stime", LuaUnixRusageStime},        //
    {"maxrss", LuaUnixRusageMaxrss},      //
    {"ixrss", LuaUnixRusageIxrss},        //
    {"idrss", LuaUnixRusageIdrss},        //
    {"isrss", LuaUnixRusageIsrss},        //
    {"minflt", LuaUnixRusageMinflt},      //
    {"majflt", LuaUnixRusageMajflt},      //
    {"nswap", LuaUnixRusageNswap},        //
    {"inblock", LuaUnixRusageInblock},    //
    {"oublock", LuaUnixRusageOublock},    //
    {"msgsnd", LuaUnixRusageMsgsnd},      //
    {"msgrcv", LuaUnixRusageMsgrcv},      //
    {"nsignals", LuaUnixRusageNsignals},  //
    {"nvcsw", LuaUnixRusageNvcsw},        //
    {"nivcsw", LuaUnixRusageNivcsw},      //
    {0},                                  //
};

static const luaL_Reg kLuaUnixRusageMeta[] = {
    {"__repr", LuaUnixRusageToString},      //
    {"__tostring", LuaUnixRusageToString},  //
    {0},                                    //
};

static void LuaUnixRusageObj(lua_State *L) {
  luaL_newmetatable(L, "unix.Rusage");
  luaL_setfuncs(L, kLuaUnixRusageMeta, 0);
  luaL_newlibtable(L, kLuaUnixRusageMeth);
  luaL_setfuncs(L, kLuaUnixRusageMeth, 0);
  lua_setfield(L, -2, "__index");
  lua_pop(L, 1);
}

////////////////////////////////////////////////////////////////////////////////
// unix.Memory object

struct Memory {
  union {
    char *bytes;
    atomic_long *words;
  } u;
  size_t size;
  void *map;
  size_t mapsize;
  pthread_mutex_t *lock;
};

// Fetches the userdata and refuses an already-unmapped region, so no
// method can touch freed memory — or the process-shared lock, which
// lives inside the mapping — after an explicit :unmap().
static struct Memory *GetMemory(lua_State *L) {
  struct Memory *m;
  m = luaL_checkudata(L, 1, "unix.Memory");
  if (!m->u.bytes) {
    luaL_error(L, "unix.Memory already unmapped");
    __builtin_unreachable();
  }
  return m;
}

// unix.Memory:read([offset:int[, bytes:int]])
//     └─→ str
static int LuaUnixMemoryRead(lua_State *L) {
  char *p;
  size_t i, n;
  luaL_Buffer buf;
  struct Memory *m;
  m = GetMemory(L);
  i = luaL_optinteger(L, 2, 0);
  if (lua_isnoneornil(L, 3)) {
    // unix.Memory:read([offset:int])
    // extracts nul-terminated string
    if (i > m->size) {
      luaL_error(L, "out of range");
      __builtin_unreachable();
    }
    n = strnlen(m->u.bytes + i, m->size - i);
  } else {
    // unix.Memory:read(offset:int, bytes:int)
    // read binary data with boundary checking
    n = luaL_checkinteger(L, 3);
    if (i > m->size || n > m->size || i + n > m->size) {
      luaL_error(L, "out of range");
      __builtin_unreachable();
    }
  }
  // Snapshot the bytes under the lock into a Lua-managed scratch buffer,
  // then build the string AFTER releasing the lock. lua_pushlstring /
  // luaL_pushresultsize can raise an out-of-memory error (longjmp); doing
  // that while holding this process-shared mutex would strand the lock
  // across every process mapping the region. luaL_buffinitsize (the only
  // step that can fail here) runs before we take the lock, and its buffer
  // is GC-owned so nothing leaks even if the final push longjmps.
  p = luaL_buffinitsize(L, &buf, n);
  pthread_mutex_lock(m->lock);
  memcpy(p, m->u.bytes + i, n);
  pthread_mutex_unlock(m->lock);
  luaL_pushresultsize(&buf, n);
  return 1;
}

// unix.Memory:write([offset:int,] data:str[, bytes:int])
static int LuaUnixMemoryWrite(lua_State *L) {
  int b;
  const char *s;
  size_t i, n, j;
  struct Memory *m;
  m = GetMemory(L);
  if (!lua_isnumber(L, 2)) {
    // unix.Memory:write(data:str[, bytes:int])
    i = 0;
    s = luaL_checklstring(L, 2, &n);
    b = 3;
  } else {
    // unix.Memory:write(offset:int, data:str[, bytes:int])
    i = luaL_checkinteger(L, 2);
    s = luaL_checklstring(L, 3, &n);
    b = 4;
  }
  if (i > m->size) {
    luaL_error(L, "out of range");
    __builtin_unreachable();
  }
  if (lua_isnoneornil(L, b)) {
    // unix.Memory:write(data:str[, offset:int])
    // writes binary data, plus a nul terminator
    if (i < n && n < m->size) {
      // include lua string's implicit nul so this round trips with
      // unix.Memory:read(offset:int) even when we're overwriting a
      // larger string that was previously inserted
      n += 1;
    } else {
      // there's no room to include the implicit nul-terminator so
      // leave it out which is safe b/c Memory:read() uses strnlen
    }
  } else {
    // unix.Memory:write(data:str, offset:int, bytes:int])
    // writes binary data without including nul-terminator
    j = luaL_checkinteger(L, b);
    if (j > n) {
      luaL_argerror(L, b, "bytes is more than what's in data");
      __builtin_unreachable();
    }
    n = j;
  }
  if (i + n > m->size) {
    luaL_error(L, "out of range");
    __builtin_unreachable();
  }
  pthread_mutex_lock(m->lock);
  memcpy(m->u.bytes + i, s, n);
  pthread_mutex_unlock(m->lock);
  return 0;
}

static atomic_long *GetWord(lua_State *L) {
  size_t i;
  struct Memory *m;
  m = GetMemory(L);
  i = luaL_checkinteger(L, 2);
  if (i >= m->size / sizeof(*m->u.words)) {
    luaL_error(L, "out of range");
    __builtin_unreachable();
  }
  return m->u.words + i;
}

// unix.Memory:load(word_index:int)
//     └─→ int
static int LuaUnixMemoryLoad(lua_State *L) {
  lua_pushinteger(L, atomic_load_explicit(GetWord(L), memory_order_relaxed));
  return 1;
}

// unix.Memory:store(word_index:int, value:int)
static int LuaUnixMemoryStore(lua_State *L) {
  atomic_store_explicit(GetWord(L), luaL_checkinteger(L, 3),
                        memory_order_relaxed);
  return 0;
}

// unix.Memory:xchg(word_index:int, value:int)
//     └─→ int
static int LuaUnixMemoryXchg(lua_State *L) {
  lua_pushinteger(L, atomic_exchange(GetWord(L), luaL_checkinteger(L, 3)));
  return 1;
}

// unix.Memory:cmpxchg(word_index:int, old:int, new:int)
//     └─→ success:bool, old:int
static int LuaUnixMemoryCmpxchg(lua_State *L) {
  long old = luaL_checkinteger(L, 3);
  lua_pushboolean(L, atomic_compare_exchange_strong(GetWord(L), &old,
                                                    luaL_checkinteger(L, 4)));
  lua_pushinteger(L, old);
  return 2;
}

// unix.Memory:add(word_index:int, value:int)
//     └─→ old:int
static int LuaUnixMemoryAdd(lua_State *L) {
  lua_pushinteger(L, atomic_fetch_add(GetWord(L), luaL_checkinteger(L, 3)));
  return 1;
}

// unix.Memory:and(word_index:int, value:int)
//     └─→ old:int
static int LuaUnixMemoryAnd(lua_State *L) {
  lua_pushinteger(L, atomic_fetch_and(GetWord(L), luaL_checkinteger(L, 3)));
  return 1;
}

// unix.Memory:or(word_index:int, value:int)
//     └─→ old:int
static int LuaUnixMemoryOr(lua_State *L) {
  lua_pushinteger(L, atomic_fetch_or(GetWord(L), luaL_checkinteger(L, 3)));
  return 1;
}

// unix.Memory:xor(word_index:int, value:int)
//     └─→ old:int
static int LuaUnixMemoryXor(lua_State *L) {
  lua_pushinteger(L, atomic_fetch_xor(GetWord(L), luaL_checkinteger(L, 3)));
  return 1;
}

// unix.Memory:wait(word_index:int, expect:int[, abs_deadline:int[, nanos:int]])
//     ├─→ 0
//     ├─→ nil, error:str, unix.EINTR
//     ├─→ nil, error:str, unix.EAGAIN
//     └─→ nil, error:str, unix.ETIMEDOUT
static int LuaUnixMemoryWait(lua_State *L) {
  atomic_long *word;
  lua_Integer expect;
  int rc, olderr = errno;
  struct timespec ts, *deadline;
  word = GetWord(L);
  expect = luaL_checkinteger(L, 3);
  if (!(INT32_MIN <= expect && expect <= INT32_MAX)) {
    luaL_argerror(L, 3, "must be an int32_t");
    __builtin_unreachable();
  }
  // Words are stored 64-bit (atomic_long) but the futex only ever inspects
  // the low 32 bits (it casts to atomic_int). A word whose high 32 bits are
  // set therefore can't be compared honestly against `expect`: e.g. a stored
  // value of 2^32+1 would make wait(idx, 1) block as if the word held 1. Rather
  // than silently misbehave, refuse the wait -- futex words are 32-bit.
  {
    long cur = atomic_load_explicit(word, memory_order_relaxed);
    if ((uint64_t)cur >> 32) {
      luaL_error(L, "futex word has nonzero high 32 bits (futex words are "
                    "32-bit; store only int32 values in words you wait on)");
      __builtin_unreachable();
    }
  }
  if (lua_isnoneornil(L, 4)) {
    deadline = 0;  // wait forever
  } else {
    ts.tv_sec = luaL_checkinteger(L, 4);
    ts.tv_nsec = luaL_optinteger(L, 5, 0);
    deadline = &ts;
  }
  BEGIN_CANCELATION_POINT;
  rc = cosmo_futex_wait((atomic_int *)word, expect,
                         PTHREAD_PROCESS_SHARED, CLOCK_REALTIME, deadline);
  END_CANCELATION_POINT;
  if (rc < 0) errno = -rc, rc = -1;
  return SysretInteger(L, "futex_wait", olderr, rc);
}

// unix.Memory:wake(index:int[, count:int])
//     └─→ woken:int
static int LuaUnixMemoryWake(lua_State *L) {
  int count, woken;
  count = luaL_optinteger(L, 3, INT_MAX);
  woken = cosmo_futex_wake((atomic_int *)GetWord(L), count,
                            PTHREAD_PROCESS_SHARED);
  npassert(woken >= 0);
  return ReturnInteger(L, woken);
}

static int LuaUnixMemoryTostring(lua_State *L) {
  char s[128];
  struct Memory *m;
  m = luaL_checkudata(L, 1, "unix.Memory");
  snprintf(s, sizeof(s), "unix.Memory(%zu)", m->size);
  lua_pushstring(L, s);
  return 1;
}

static int LuaUnixMemoryGc(lua_State *L) {
  struct Memory *m;
  m = luaL_checkudata(L, 1, "unix.Memory");
  if (m->u.bytes) {
    npassert(!munmap(m->map, m->mapsize));
    m->u.bytes = 0;
  }
  return 0;
}

// unix.Memory:unmap()
//     └─→ unmapped:bool
//
// Releases the mapping now instead of waiting for the garbage
// collector. Idempotent: returns true when this call released the
// mapping, false when it was already unmapped. After unmap, every
// other method on this object raises an error (see GetMemory) rather
// than touching freed memory.
static int LuaUnixMemoryUnmap(lua_State *L) {
  struct Memory *m;
  m = luaL_checkudata(L, 1, "unix.Memory");
  if (m->u.bytes) {
    npassert(!munmap(m->map, m->mapsize));
    m->u.bytes = 0;
    lua_pushboolean(L, true);
  } else {
    lua_pushboolean(L, false);
  }
  return 1;
}

static const luaL_Reg kLuaUnixMemoryMeth[] = {
    {"read", LuaUnixMemoryRead},        //
    {"write", LuaUnixMemoryWrite},      //
    {"load", LuaUnixMemoryLoad},        //
    {"store", LuaUnixMemoryStore},      //
    {"xchg", LuaUnixMemoryXchg},        //
    {"cmpxchg", LuaUnixMemoryCmpxchg},  //
    {"fetch_add", LuaUnixMemoryAdd},    //
    {"fetch_and", LuaUnixMemoryAnd},    //
    {"fetch_or", LuaUnixMemoryOr},      //
    {"fetch_xor", LuaUnixMemoryXor},    //
    {"wait", LuaUnixMemoryWait},        //
    {"wake", LuaUnixMemoryWake},        //
    {"unmap", LuaUnixMemoryUnmap},      //
    {0},                                //
};

static const luaL_Reg kLuaUnixMemoryMeta[] = {
    {"__tostring", LuaUnixMemoryTostring},  //
    {"__repr", LuaUnixMemoryTostring},      //
    {"__gc", LuaUnixMemoryGc},              //
    {0},                                    //
};

static void LuaUnixMemoryObj(lua_State *L) {
  luaL_newmetatable(L, "unix.Memory");
  luaL_setfuncs(L, kLuaUnixMemoryMeta, 0);
  luaL_newlibtable(L, kLuaUnixMemoryMeth);
  luaL_setfuncs(L, kLuaUnixMemoryMeth, 0);
  lua_setfield(L, -2, "__index");
  lua_pop(L, 1);
}

static int LuaUnixMapshared(lua_State *L) {
  char *p;
  size_t n, c, g;
  struct Memory *m;
  pthread_mutexattr_t mattr;
  n = luaL_checkinteger(L, 1);
  if (!n) {
    luaL_error(L, "can't map empty region");
    __builtin_unreachable();
  }
  if (n % sizeof(long)) {
    luaL_error(L, "size must be multiple of word size");
    __builtin_unreachable();
  }
  if (n >= 0x100000000000) {
    luaL_error(L, "map size too big");
    __builtin_unreachable();
  }
  c = n;
  c += sizeof(*m->lock);
  g = sysconf(_SC_PAGESIZE);
  c = ROUNDUP(c, g);
  if (!(p = _mapshared(c))) {
    luaL_error(L, "out of memory");
    __builtin_unreachable();
  }
  m = lua_newuserdatauv(L, sizeof(*m), 1);
  luaL_setmetatable(L, "unix.Memory");
  m->u.bytes = p + sizeof(*m->lock);
  m->size = n;
  m->map = p;
  m->mapsize = c;
  m->lock = (pthread_mutex_t *)p;
  pthread_mutexattr_init(&mattr);
  pthread_mutexattr_settype(&mattr, PTHREAD_MUTEX_DEFAULT);
  pthread_mutexattr_setpshared(&mattr, PTHREAD_PROCESS_SHARED);
  pthread_mutex_init(m->lock, &mattr);
  pthread_mutexattr_destroy(&mattr);
  return 1;
}

////////////////////////////////////////////////////////////////////////////////
// unix.Sigset object

// unix.sigset(sig:int, ...)
//     └─→ unix.Sigset
static int LuaUnixSigset(lua_State *L) {
  int i, n;
  sigset_t set;
  sigemptyset(&set);
  n = lua_gettop(L);
  for (i = 1; i <= n; ++i) {
    sigaddset(&set, luaL_checkinteger(L, i));
  }
  LuaPushSigset(L, set);
  return 1;
}

// unix.Sigset:add(sig:int)
static int LuaUnixSigsetAdd(lua_State *L) {
  sigset_t *set;
  lua_Integer sig;
  set = luaL_checkudata(L, 1, "unix.Sigset");
  sig = luaL_checkinteger(L, 2);
  sigaddset(set, sig);
  return 0;
}

// unix.Sigset:remove(sig:int)
static int LuaUnixSigsetRemove(lua_State *L) {
  sigset_t *set;
  lua_Integer sig;
  set = luaL_checkudata(L, 1, "unix.Sigset");
  sig = luaL_checkinteger(L, 2);
  sigdelset(set, sig);
  return 0;
}

// unix.Sigset:fill()
static int LuaUnixSigsetFill(lua_State *L) {
  sigset_t *set;
  set = luaL_checkudata(L, 1, "unix.Sigset");
  sigfillset(set);
  return 0;
}

// unix.Sigset:clear()
static int LuaUnixSigsetClear(lua_State *L) {
  sigset_t *set;
  set = luaL_checkudata(L, 1, "unix.Sigset");
  sigemptyset(set);
  return 0;
}

// unix.Sigset:contains(sig:int)
//     └─→ bool
static int LuaUnixSigsetContains(lua_State *L) {
  sigset_t *set;
  lua_Integer sig;
  set = luaL_checkudata(L, 1, "unix.Sigset");
  sig = luaL_checkinteger(L, 2);
  return ReturnBoolean(L, sigismember(set, sig));
}

static int LuaUnixSigsetTostring(lua_State *L) {
  char *b = 0;
  sigset_t *ss;
  int sig, first;
  ss = luaL_checkudata(L, 1, "unix.Sigset");
  appends(&b, "unix.Sigset");
  appendw(&b, '(');
  for (sig = first = 1; sig <= NSIG; ++sig) {
    if (sigismember(ss, sig) == 1) {
      if (!first) {
        appendw(&b, READ16LE(", "));
      } else {
        first = 0;
      }
      appendw(&b, READ64LE("unix.\0\0"));
      appends(&b, strsignal(sig));
    }
  }
  appendw(&b, ')');
  lua_pushlstring(L, b, appendz(b).i);
  free(b);
  return 1;
}

static const luaL_Reg kLuaUnixSigsetMeth[] = {
    {"add", LuaUnixSigsetAdd},            //
    {"fill", LuaUnixSigsetFill},          //
    {"clear", LuaUnixSigsetClear},        //
    {"remove", LuaUnixSigsetRemove},      //
    {"contains", LuaUnixSigsetContains},  //
    {0},                                  //
};

static const luaL_Reg kLuaUnixSigsetMeta[] = {
    {"__tostring", LuaUnixSigsetTostring},  //
    {"__repr", LuaUnixSigsetTostring},      //
    {0},                                    //
};

static void LuaUnixSigsetObj(lua_State *L) {
  luaL_newmetatable(L, "unix.Sigset");
  luaL_setfuncs(L, kLuaUnixSigsetMeta, 0);
  luaL_newlibtable(L, kLuaUnixSigsetMeth);
  luaL_setfuncs(L, kLuaUnixSigsetMeth, 0);
  lua_setfield(L, -2, "__index");
  lua_pop(L, 1);
}

////////////////////////////////////////////////////////////////////////////////
// unix.Dir object

static DIR **GetUnixDirSelf(lua_State *L) {
  return luaL_checkudata(L, 1, "unix.Dir");
}

static DIR *GetDirOrDie(lua_State *L) {
  DIR **dirp;
  dirp = GetUnixDirSelf(L);
  if (*dirp) return *dirp;
  luaL_argerror(L, 1, "unix.UnixDir is closed");
  __builtin_unreachable();
}

// unix.Dir:close()
//     ├─→ true
//     └─→ nil, error:str, errno:int
static int LuaUnixDirClose(lua_State *L) {
  DIR **dirp;
  int rc, olderr;
  dirp = GetUnixDirSelf(L);
  if (*dirp) {
    olderr = errno;
    rc = closedir(*dirp);
    *dirp = 0;
    return SysretBool(L, "closedir", olderr, rc);
  } else {
    lua_pushboolean(L, true);
    return 1;
  }
}

// unix.Dir:read()
//     ├─→ name:str, kind:int, ino:int, off:int
//     ├─→ nil                        (end of directory stream)
//     └─→ nil, error:str, errno:int  (readdir() failure)
static int LuaUnixDirRead(lua_State *L) {
  DIR *dir;
  int olderr;
  struct dirent *ent;
  dir = GetDirOrDie(L);
  olderr = errno;
  // readdir() returns NULL on both end-of-directory and failure; per
  // its own doc comment (libc/stdio/dirstream.c) the two are told
  // apart by zeroing errno beforehand and checking it after.
  errno = 0;
  if ((ent = readdir(dir))) {
    lua_pushlstring(L, ent->d_name, strnlen(ent->d_name, sizeof(ent->d_name)));
    lua_pushinteger(L, ent->d_type);
    lua_pushinteger(L, ent->d_ino);
    lua_pushinteger(L, ent->d_off);
    return 4;
  } else if (errno) {
    return LuaUnixSysretErrno(L, "readdir", olderr);
  } else {
    // end of directory stream condition
    lua_pushnil(L);
    return 1;
  }
}

// unix.Dir:fd()
//     ├─→ fd:int
//     └─→ nil, error:str, errno:int
static int LuaUnixDirFd(lua_State *L) {
  int fd, olderr = errno;
  fd = dirfd(GetDirOrDie(L));
  if (fd != -1) {
    lua_pushinteger(L, fd);
    return 1;
  } else {
    return LuaUnixSysretErrno(L, "dirfd", olderr);
  }
}

// unix.Dir:tell()
//     ├─→ off:int
//     └─→ nil, error:str, errno:int
static int LuaUnixDirTell(lua_State *L) {
  int olderr = errno;
  return SysretInteger(L, "telldir", olderr, telldir(GetDirOrDie(L)));
}

// unix.Dir:rewind()
static int LuaUnixDirRewind(lua_State *L) {
  rewinddir(GetDirOrDie(L));
  return 0;
}

static int ReturnDir(lua_State *L, DIR *dir) {
  DIR **dirp;
  dirp = lua_newuserdatauv(L, sizeof(*dirp), 1);
  luaL_setmetatable(L, "unix.Dir");
  *dirp = dir;
  return 1;
}

// unix.opendir(path:str)
//     ├─→ state:unix.Dir
//     └─→ nil, error:str, errno:int
static int LuaUnixOpendir(lua_State *L) {
  DIR *dir;
  int olderr = errno;
  if ((dir = opendir(luaL_checkstring(L, 1)))) {
    return ReturnDir(L, dir);
  } else {
    return LuaUnixSysretErrno(L, "opendir", olderr);
  }
}

// unix.fdopendir(fd:int)
//     ├─→ state:unix.Dir
//     └─→ nil, error:str, errno:int
static int LuaUnixFdopendir(lua_State *L) {
  DIR *dir;
  int olderr = errno;
  if ((dir = fdopendir(luaL_checkinteger(L, 1)))) {
    return ReturnDir(L, dir);
  } else {
    return LuaUnixSysretErrno(L, "fdopendir", olderr);
  }
}

static const luaL_Reg kLuaUnixDirMeth[] = {
    {"close", LuaUnixDirClose},    //
    {"read", LuaUnixDirRead},      //
    {"fd", LuaUnixDirFd},          //
    {"tell", LuaUnixDirTell},      //
    {"rewind", LuaUnixDirRewind},  //
    {0},                           //
};

static const luaL_Reg kLuaUnixDirMeta[] = {
    {"__call", LuaUnixDirRead},  //
    {"__gc", LuaUnixDirClose},   //
    {0},                         //
};

static void LuaUnixDirObj(lua_State *L) {
  luaL_newmetatable(L, "unix.Dir");
  luaL_setfuncs(L, kLuaUnixDirMeta, 0);
  luaL_newlibtable(L, kLuaUnixDirMeth);
  luaL_setfuncs(L, kLuaUnixDirMeth, 0);
  lua_setfield(L, -2, "__index");
  lua_pop(L, 1);
}

////////////////////////////////////////////////////////////////////////////////
// SYSTEM INFORMATION

// unix.sysconf(name:int)
//     ├─→ value:int
//     └─→ nil, error:str, errno:int
//
// Queries a configurable system limit or value, e.g.
//
//     unix.sysconf(unix.SC_NPROCESSORS_ONLN)  // online cpu count
//     unix.sysconf(unix.SC_PAGESIZE)          // mmap() page size
//     unix.sysconf(unix.SC_CLK_TCK)           // clock ticks per second
//
// Returns `nil, error, errno` with `EINVAL` when `name` isn't recognized.
static int LuaUnixSysconf(lua_State *L) {
  long rc;
  int olderr = errno;
  int name = luaL_checkinteger(L, 1);
  errno = 0;
  rc = sysconf(name);
  if (rc == -1 && errno) {
    return LuaUnixSysretErrno(L, "sysconf", olderr);
  }
  errno = olderr;
  lua_pushinteger(L, rc);
  return 1;
}

// unix.uname()
//     ├─→ {sysname:str, nodename:str, release:str,
//     │    version:str, machine:str, domainname:str}
//     └─→ nil, error:str, errno:int
//
// Returns identity of the current operating system as a table.
static int LuaUnixUname(lua_State *L) {
  struct utsname u;
  int olderr = errno;
  if (uname(&u) == -1) {
    return LuaUnixSysretErrno(L, "uname", olderr);
  }
  lua_newtable(L);
  lua_pushstring(L, u.sysname);
  lua_setfield(L, -2, "sysname");
  lua_pushstring(L, u.nodename);
  lua_setfield(L, -2, "nodename");
  lua_pushstring(L, u.release);
  lua_setfield(L, -2, "release");
  lua_pushstring(L, u.version);
  lua_setfield(L, -2, "version");
  lua_pushstring(L, u.machine);
  lua_setfield(L, -2, "machine");
  lua_pushstring(L, u.domainname);
  lua_setfield(L, -2, "domainname");
  return 1;
}

////////////////////////////////////////////////////////////////////////////////
// UNIX module

static const luaL_Reg kLuaUnix[] = {
    {"S_ISBLK", LuaUnixSisblk},           // is st:mode() a block device?
    {"S_ISCHR", LuaUnixSischr},           // is st:mode() a character device?
    {"S_ISDIR", LuaUnixSisdir},           // is st:mode() a directory?
    {"S_ISFIFO", LuaUnixSisfifo},         // is st:mode() a fifo?
    {"S_ISLNK", LuaUnixSislnk},           // is st:mode() a symbolic link?
    {"S_ISREG", LuaUnixSisreg},           // is st:mode() a regular file?
    {"S_ISSOCK", LuaUnixSissock},         // is st:mode() a socket?
    {"sigset", LuaUnixSigset},            // creates signal bitmask
    {"WEXITSTATUS", LuaUnixWexitstatus},  // gets exit status from wait status
    {"WIFEXITED", LuaUnixWifexited},      // gets exit code from wait status
    {"WIFSIGNALED", LuaUnixWifsignaled},  // determines if died due to signal
    {"WTERMSIG", LuaUnixWtermsig},        // gets the signal code
    {"accept", LuaUnixAccept},            // create client fd for client
    {"access", LuaUnixAccess},            // check my file authorization
    {"bind", LuaUnixBind},                // reserve network interface address
    {"capget", LuaUnixCapget},            // read capability bitmasks
    {"capset", LuaUnixCapset},            // set capability bitmasks
    {"chdir", LuaUnixChdir},              // change directory
    {"chmod", LuaUnixChmod},              // change mode of file
    {"chown", LuaUnixChown},              // change owner of file
    {"chroot", LuaUnixChroot},            // change root directory
    {"clearenv", LuaUnixClearenv},        // clear all environment variables
    {"clock_gettime", LuaUnixGettime},    // get timestamp w/ nano precision
    {"close", LuaUnixClose},              // close file or socket
    {"commandv", LuaUnixCommandv},        // resolve program on $PATH
    {"connect", LuaUnixConnect},          // connect to remote address
    {"daemon", LuaUnixDaemon},            // daemonize process
    {"dup", LuaUnixDup},                  // copy fd to lowest empty slot
    {"environ", LuaUnixEnviron},          // get environment variables
    {"execve", LuaUnixExecve},            // replace process with program
    {"execvp", LuaUnixExecvp},            // exec program using PATH
    {"execvpe", LuaUnixExecvpe},          // exec program using PATH with env
    {"exit", LuaUnixExit},                // exit w/o atexit
    {"fcntl", LuaUnixFcntl},              // manipulate file descriptor
    {"fdatasync", LuaUnixFdatasync},      // flush open file w/o metadata
    {"fdopendir", LuaUnixFdopendir},      // read directory entry list
    {"fexecve", LuaUnixFexecve},          // exec program from fd
    {"fork", LuaUnixFork},                // make child process via mitosis
    {"fstat", LuaUnixFstat},              // get file info from fd
    {"fstatfs", LuaUnixFstatfs},          // get filesystem info from fd
    {"fsync", LuaUnixFsync},              // flush open file
    {"ftruncate", LuaUnixFtruncate},      // shrink or extend file medium
    {"futimens", LuaUnixFutimens},        // change access/modified time
    {"getcwd", LuaUnixGetcwd},            // get current directory
    {"getegid", LuaUnixGetegid},          // get effective group id of process
    {"geteuid", LuaUnixGeteuid},          // get effective user id of process
    {"getgid", LuaUnixGetgid},            // get real group id of process
    {"gethostname", LuaUnixGethostname},  // get hostname of this machine
    {"sethostname", LuaUnixSethostname},  // set hostname of this machine
    {"getlogin", LuaUnixGetlogin},        // get login name of current user
    {"getpeername", LuaUnixGetpeername},  // get address of remote end
    {"getpgid", LuaUnixGetpgid},          // get process group id of pid
    {"getpgrp", LuaUnixGetpgrp},          // get process group id
    {"getpid", LuaUnixGetpid},            // get id of this process
    {"getppid", LuaUnixGetppid},          // get parent process id
    {"getpriority", LuaUnixGetpriority},  // get process priority
    {"getrlimit", LuaUnixGetrlimit},      // query resource limits
    {"getrusage", LuaUnixGetrusage},      // query resource usages
    {"getsid", LuaUnixGetsid},            // get session id of pid
    {"getsockname", LuaUnixGetsockname},  // get address of local end
    {"getsockopt", LuaUnixGetsockopt},    // get socket tunings
    {"getuid", LuaUnixGetuid},            // get real user id of process
    {"gmtime", LuaUnixGmtime},            // destructure unix timestamp
    {"ioctl", LuaUnixIoctl},              // generic device control
    {"isatty", LuaUnixIsatty},            // detects pseudoteletypewriters
    {"kill", LuaUnixKill},                // signal child process
    {"killpg", LuaUnixKillpg},            // signal process group
    {"landlock_add_net_rule", LuaUnixLandlockAddNetRule},     // add a landlock TCP port rule
    {"landlock_add_rule", LuaUnixLandlockAddRule},            // add a landlock rule
    {"landlock_create_ruleset", LuaUnixLandlockCreateRuleset},// create landlock ruleset
    {"landlock_restrict_self", LuaUnixLandlockRestrictSelf},  // apply ruleset to self
    {"link", LuaUnixLink},                // create hard link
    {"listen", LuaUnixListen},            // begin listening for clients
    {"localtime", LuaUnixLocaltime},      // localize unix timestamp
    {"login_tty", LuaUnixLoginTty},     // make fd the controlling tty
    {"lseek", LuaUnixLseek},              // seek in file
    {"major", LuaUnixMajor},              // extract device info
    {"makedirs", LuaUnixMakedirs},        // make directory and parents too
    {"mapshared", LuaUnixMapshared},      // mmap(MAP_SHARED) w/ mutex+atomics
    {"minor", LuaUnixMinor},              // extract device info
    {"mkdir", LuaUnixMkdir},              // make directory
    {"mkdtemp", LuaUnixMkdtemp},          // create temporary directory
    {"mkstemp", LuaUnixMkstemp},          // create temporary file
    {"mount", LuaUnixMount},              // mount filesystem
    {"nanosleep", LuaUnixNanosleep},      // sleep w/ nano precision
    {"nice", LuaUnixNice},                // adjust process priority
    {"open", LuaUnixOpen},                // open file fd at lowest slot
    {"openpty", LuaUnixOpenpty},         // open new pseudoteletypewriter
    {"opendir", LuaUnixOpendir},          // read directory entry list
    {"pipe", LuaUnixPipe},                // create two anon fifo fds
    {"pivot_root", LuaUnixPivotRoot},     // replace root fs of namespace
    {"pledge", LuaUnixPledge},            // enables syscall sandbox
    {"poll", LuaUnixPoll},                // waits for file descriptor events
    {"prctl", LuaUnixPrctl},              // process-control operations
    {"raise", LuaUnixRaise},              // signal this process
    {"read", LuaUnixRead},                // read from file or socket
    {"readlink", LuaUnixReadlink},        // reads symbolic link
    {"realpath", LuaUnixRealpath},        // abspath without dots/symlinks
    {"recv", LuaUnixRecv},                // receive tcp from some address
    {"recvfrom", LuaUnixRecvfrom},        // receive udp from some address
    {"rename", LuaUnixRename},            // rename file or directory
    {"rmdir", LuaUnixRmdir},              // remove empty directory
    {"rmrf", LuaUnixRmrf},                // remove file recursively
    {"sched_yield", LuaUnixSchedYield},   // relinquish scheduled quantum
    {"send", LuaUnixSend},                // send tcp to some address
    {"sendto", LuaUnixSendto},            // send udp to some address
    {"setenv", LuaUnixSetenv},            // set environment variable
    {"setfsgid", LuaUnixSetfsgid},        // set/get group id for fs ops
    {"setfsuid", LuaUnixSetfsuid},        // set/get user id for fs ops
    {"setgid", LuaUnixSetgid},            // set real group id of process
    {"setitimer", LuaUnixSetitimer},      // set alarm clock
    {"setns", LuaUnixSetns},              // enter existing namespace via fd
    {"setpgid", LuaUnixSetpgid},          // set process group id for pid
    {"setpgrp", LuaUnixSetpgrp},          // sets process group id
    {"setpriority", LuaUnixSetpriority},  // set process priority
    {"setresgid", LuaUnixSetresgid},      // sets real/effective/saved gids
    {"setresuid", LuaUnixSetresuid},      // sets real/effective/saved uids
    {"setrlimit", LuaUnixSetrlimit},      // prevent cpu memory bombs
    {"setsid", LuaUnixSetsid},            // create a new session id
    {"setsockopt", LuaUnixSetsockopt},    // tune socket options
    {"setuid", LuaUnixSetuid},            // set real user id of process
    {"shutdown", LuaUnixShutdown},        // make socket half empty or full
    {"sigaction", LuaUnixSigaction},      // install signal handler
    {"sigpending", LuaUnixSigpending},    // get pending signals
    {"sigprocmask", LuaUnixSigprocmask},  // change signal mask
    {"sigsuspend", LuaUnixSigsuspend},    // wait for signal
    {"siocgifconf", LuaUnixSiocgifconf},  // get list of network interfaces
    {"siocgifflags", LuaUnixSiocgifflags},  // get IFF_* flags of interface
    {"siocsifflags", LuaUnixSiocsifflags},  // set IFF_* flags of interface
    {"socket", LuaUnixSocket},            // create network communication fd
    {"socketpair", LuaUnixSocketpair},    // create bidirectional pipe
    {"spawn", LuaUnixSpawn},              // spawn process
    {"spawnp", LuaUnixSpawnp},            // spawn process using PATH
    {"stat", LuaUnixStat},                // get file info from path
    {"statfs", LuaUnixStatfs},            // get filesystem info from path
    {"strsignal", LuaUnixStrsignal},      // turn signal into string
    {"symlink", LuaUnixSymlink},          // create symbolic link
    {"sync", LuaUnixSync},                // flushes files and disks
    {"sysconf", LuaUnixSysconf},          // query system configuration value
    {"syslog", LuaUnixSyslog},            // logs to system log
    {"tcgetattr", LuaUnixTcgetattr},      // get terminal attributes
    {"tcsetattr", LuaUnixTcsetattr},      // set terminal attributes
    {"tiocgwinsz", LuaUnixTiocgwinsz},    // pseudoteletypewriter dimensions
    {"tmpfd", LuaUnixTmpfd},              // create anonymous file
    {"copy_file_range", LuaUnixCopyFileRange},  // kernel-side fd-to-fd copy
    {"truncate", LuaUnixTruncate},        // shrink or extend file medium
    {"umask", LuaUnixUmask},              // set default file mask
    {"uname", LuaUnixUname},              // get operating system identity
    {"unlink", LuaUnixUnlink},            // remove file
    {"unmount", LuaUnixUnmount},          // unmount filesystem
    {"unsetenv", LuaUnixUnsetenv},        // unset environment variable
    {"unshare", LuaUnixUnshare},          // create fresh namespaces
    {"unveil", LuaUnixUnveil},            // filesystem sandboxing
    {"utimensat", LuaUnixUtimensat},      // change access/modified time
    {"verynice", LuaUnixVerynice},        // lowest priority
    {"wait", LuaUnixWait},                // wait for child to change status
    {"write", LuaUnixWrite},              // write to file or socket
    {0},                                  //
};

static void LoadMagnums(lua_State *L, const struct MagnumStr *ms,
                        const char *pfx) {
  int i;
  char b[64], *p;
  p = stpcpy(b, pfx);
  for (i = 0; ms[i].x != MAGNUM_TERMINATOR; ++i) {
    stpcpy(p, MAGNUM_STRING(ms, i));
    LuaSetIntField(L, b, MAGNUM_NUMBER(ms, i));
  }
}

int LuaUnix(lua_State *L) {
  GL = L;
  luaL_newlib(L, kLuaUnix);
  LuaUnixSigsetObj(L);
  LuaUnixRusageObj(L);
  LuaUnixStatfsObj(L);
  LuaUnixMemoryObj(L);
  LuaUnixStatObj(L);
  LuaUnixDirObj(L);
  lua_newtable(L);
  lua_rawsetp(L, LUA_REGISTRYINDEX, &kSignalHandlers);

  LoadMagnums(L, kIpOptnames, "IP_");
  LoadMagnums(L, kTcpOptnames, "TCP_");
  LoadMagnums(L, kSockOptnames, "SO_");
  LoadMagnums(L, kClockNames, "CLOCK_");

  // errno
  LuaSetIntField(L, "EPERM", EPERM);
  LuaSetIntField(L, "ENOENT", ENOENT);
  LuaSetIntField(L, "ESRCH", ESRCH);
  LuaSetIntField(L, "EINTR", EINTR);
  LuaSetIntField(L, "EIO", EIO);
  LuaSetIntField(L, "ENXIO", ENXIO);
  LuaSetIntField(L, "E2BIG", E2BIG);
  LuaSetIntField(L, "ENOEXEC", ENOEXEC);
  LuaSetIntField(L, "EBADF", EBADF);
  LuaSetIntField(L, "ECHILD", ECHILD);
  LuaSetIntField(L, "EAGAIN", EAGAIN);
  LuaSetIntField(L, "ENOMEM", ENOMEM);
  LuaSetIntField(L, "EACCES", EACCES);
  LuaSetIntField(L, "EFAULT", EFAULT);
  LuaSetIntField(L, "ENOTBLK", ENOTBLK);
  LuaSetIntField(L, "EBUSY", EBUSY);
  LuaSetIntField(L, "EEXIST", EEXIST);
  LuaSetIntField(L, "EXDEV", EXDEV);
  LuaSetIntField(L, "ENODEV", ENODEV);
  LuaSetIntField(L, "ENOTDIR", ENOTDIR);
  LuaSetIntField(L, "EISDIR", EISDIR);
  LuaSetIntField(L, "EINVAL", EINVAL);
  LuaSetIntField(L, "ENFILE", ENFILE);
  LuaSetIntField(L, "EMFILE", EMFILE);
  LuaSetIntField(L, "ENOTTY", ENOTTY);
  LuaSetIntField(L, "ETXTBSY", ETXTBSY);
  LuaSetIntField(L, "EFBIG", EFBIG);
  LuaSetIntField(L, "ENOSPC", ENOSPC);
  LuaSetIntField(L, "ESPIPE", ESPIPE);
  LuaSetIntField(L, "EROFS", EROFS);
  LuaSetIntField(L, "EMLINK", EMLINK);
  LuaSetIntField(L, "EPIPE", EPIPE);
  LuaSetIntField(L, "EDOM", EDOM);
  LuaSetIntField(L, "ERANGE", ERANGE);
  LuaSetIntField(L, "EDEADLK", EDEADLK);
  LuaSetIntField(L, "ENAMETOOLONG", ENAMETOOLONG);
  LuaSetIntField(L, "ENOLCK", ENOLCK);
  LuaSetIntField(L, "ENOSYS", ENOSYS);
  LuaSetIntField(L, "ENOTEMPTY", ENOTEMPTY);
  LuaSetIntField(L, "ELOOP", ELOOP);
  LuaSetIntField(L, "ENOMSG", ENOMSG);
  LuaSetIntField(L, "EIDRM", EIDRM);
  LuaSetIntField(L, "ENOTSUP", ENOTSUP);
  LuaSetIntField(L, "ENOSTR", ENOSTR);
  LuaSetIntField(L, "ENODATA", ENODATA);
  LuaSetIntField(L, "ETIME", ETIME);
  LuaSetIntField(L, "ENOSR", ENOSR);
  LuaSetIntField(L, "ENONET", ENONET);
  LuaSetIntField(L, "EREMOTE", EREMOTE);
  LuaSetIntField(L, "ENOLINK", ENOLINK);
  LuaSetIntField(L, "EPROTO", EPROTO);
  LuaSetIntField(L, "EMULTIHOP", EMULTIHOP);
  LuaSetIntField(L, "EBADMSG", EBADMSG);
  LuaSetIntField(L, "EOVERFLOW", EOVERFLOW);
  LuaSetIntField(L, "EBADFD", EBADFD);
  LuaSetIntField(L, "EFTYPE", EFTYPE);
  LuaSetIntField(L, "EILSEQ", EILSEQ);
  LuaSetIntField(L, "ERESTART", ERESTART);
  LuaSetIntField(L, "EUSERS", EUSERS);
  LuaSetIntField(L, "ENOTSOCK", ENOTSOCK);
  LuaSetIntField(L, "EDESTADDRREQ", EDESTADDRREQ);
  LuaSetIntField(L, "EMSGSIZE", EMSGSIZE);
  LuaSetIntField(L, "EPROTOTYPE", EPROTOTYPE);
  LuaSetIntField(L, "ENOPROTOOPT", ENOPROTOOPT);
  LuaSetIntField(L, "EPROTONOSUPPORT", EPROTONOSUPPORT);
  LuaSetIntField(L, "ESOCKTNOSUPPORT", ESOCKTNOSUPPORT);
  LuaSetIntField(L, "EOPNOTSUPP", EOPNOTSUPP);
  LuaSetIntField(L, "EPFNOSUPPORT", EPFNOSUPPORT);
  LuaSetIntField(L, "EAFNOSUPPORT", EAFNOSUPPORT);
  LuaSetIntField(L, "EADDRINUSE", EADDRINUSE);
  LuaSetIntField(L, "EADDRNOTAVAIL", EADDRNOTAVAIL);
  LuaSetIntField(L, "ENETDOWN", ENETDOWN);
  LuaSetIntField(L, "ENETUNREACH", ENETUNREACH);
  LuaSetIntField(L, "ENETRESET", ENETRESET);
  LuaSetIntField(L, "ECONNABORTED", ECONNABORTED);
  LuaSetIntField(L, "ECONNRESET", ECONNRESET);
  LuaSetIntField(L, "ENOBUFS", ENOBUFS);
  LuaSetIntField(L, "EISCONN", EISCONN);
  LuaSetIntField(L, "ENOTCONN", ENOTCONN);
  LuaSetIntField(L, "ESHUTDOWN", ESHUTDOWN);
  LuaSetIntField(L, "ETOOMANYREFS", ETOOMANYREFS);
  LuaSetIntField(L, "ETIMEDOUT", ETIMEDOUT);
  LuaSetIntField(L, "ECONNREFUSED", ECONNREFUSED);
  LuaSetIntField(L, "EHOSTDOWN", EHOSTDOWN);
  LuaSetIntField(L, "EHOSTUNREACH", EHOSTUNREACH);
  LuaSetIntField(L, "EALREADY", EALREADY);
  LuaSetIntField(L, "EINPROGRESS", EINPROGRESS);
  LuaSetIntField(L, "ESTALE", ESTALE);
  LuaSetIntField(L, "EDQUOT", EDQUOT);
  LuaSetIntField(L, "ENOMEDIUM", ENOMEDIUM);
  LuaSetIntField(L, "EMEDIUMTYPE", EMEDIUMTYPE);
  LuaSetIntField(L, "ECANCELED", ECANCELED);
  LuaSetIntField(L, "EOWNERDEAD", EOWNERDEAD);
  LuaSetIntField(L, "ENOTRECOVERABLE", ENOTRECOVERABLE);
  LuaSetIntField(L, "ERFKILL", ERFKILL);
  LuaSetIntField(L, "EHWPOISON", EHWPOISON);

  // signals
  LuaSetIntField(L, "SIGHUP", SIGHUP);
  LuaSetIntField(L, "SIGINT", SIGINT);
  LuaSetIntField(L, "SIGQUIT", SIGQUIT);
  LuaSetIntField(L, "SIGILL", SIGILL);
  LuaSetIntField(L, "SIGTRAP", SIGTRAP);
  LuaSetIntField(L, "SIGABRT", SIGABRT);
  LuaSetIntField(L, "SIGBUS", SIGBUS);
  LuaSetIntField(L, "SIGFPE", SIGFPE);
  LuaSetIntField(L, "SIGKILL", SIGKILL);
  LuaSetIntField(L, "SIGUSR1", SIGUSR1);
  LuaSetIntField(L, "SIGSEGV", SIGSEGV);
  LuaSetIntField(L, "SIGUSR2", SIGUSR2);
  LuaSetIntField(L, "SIGPIPE", SIGPIPE);
  LuaSetIntField(L, "SIGALRM", SIGALRM);
  LuaSetIntField(L, "SIGTERM", SIGTERM);
  LuaSetIntField(L, "SIGCHLD", SIGCHLD);
  LuaSetIntField(L, "SIGCONT", SIGCONT);
  LuaSetIntField(L, "SIGSTOP", SIGSTOP);
  LuaSetIntField(L, "SIGTSTP", SIGTSTP);
  LuaSetIntField(L, "SIGTTIN", SIGTTIN);
  LuaSetIntField(L, "SIGTTOU", SIGTTOU);
  LuaSetIntField(L, "SIGURG", SIGURG);
  LuaSetIntField(L, "SIGXCPU", SIGXCPU);
  LuaSetIntField(L, "SIGXFSZ", SIGXFSZ);
  LuaSetIntField(L, "SIGVTALRM", SIGVTALRM);
  LuaSetIntField(L, "SIGPROF", SIGPROF);
  LuaSetIntField(L, "SIGWINCH", SIGWINCH);
  LuaSetIntField(L, "SIGSYS", SIGSYS);

  // open()
  LuaSetIntField(L, "O_RDONLY", O_RDONLY);
  LuaSetIntField(L, "O_WRONLY", O_WRONLY);
  LuaSetIntField(L, "O_RDWR", O_RDWR);
  LuaSetIntField(L, "O_ACCMODE", O_ACCMODE);
  LuaSetIntField(L, "O_CREAT", O_CREAT);
  LuaSetIntField(L, "O_EXCL", O_EXCL);
  LuaSetIntField(L, "O_NOCTTY", O_NOCTTY);
  LuaSetIntField(L, "O_TRUNC", O_TRUNC);
  LuaSetIntField(L, "O_APPEND", O_APPEND);
  LuaSetIntField(L, "O_NONBLOCK", O_NONBLOCK);
  LuaSetIntField(L, "O_SYNC", O_SYNC);
  LuaSetIntField(L, "O_DSYNC", O_DSYNC);
  LuaSetIntField(L, "O_DIRECT", O_DIRECT);
  LuaSetIntField(L, "O_DIRECTORY", O_DIRECTORY);
  LuaSetIntField(L, "O_NOFOLLOW", O_NOFOLLOW);
  LuaSetIntField(L, "O_NOATIME", O_NOATIME);
  LuaSetIntField(L, "O_CLOEXEC", O_CLOEXEC);
  LuaSetIntField(L, "O_UNLINK", O_UNLINK);
  LuaSetIntField(L, "O_PATH", _O_PATH);

  // seek() whence
  LuaSetIntField(L, "SEEK_SET", SEEK_SET);
  LuaSetIntField(L, "SEEK_CUR", SEEK_CUR);
  LuaSetIntField(L, "SEEK_END", SEEK_END);

  // fcntl() stuff
  LuaSetIntField(L, "F_GETFD", F_GETFD);
  LuaSetIntField(L, "F_SETFD", F_SETFD);
  LuaSetIntField(L, "F_GETFL", F_GETFL);
  LuaSetIntField(L, "F_SETFL", F_SETFL);
  LuaSetIntField(L, "F_UNLCK", F_UNLCK);
  LuaSetIntField(L, "F_RDLCK", F_RDLCK);
  LuaSetIntField(L, "F_WRLCK", F_WRLCK);
  LuaSetIntField(L, "F_SETLK", F_SETLK);
  LuaSetIntField(L, "F_SETLKW", F_SETLKW);
  LuaSetIntField(L, "F_GETLK", F_GETLK);
  LuaSetIntField(L, "FD_CLOEXEC", FD_CLOEXEC);

  // access() mode
  LuaSetIntField(L, "R_OK", R_OK);
  LuaSetIntField(L, "W_OK", W_OK);
  LuaSetIntField(L, "X_OK", X_OK);
  LuaSetIntField(L, "F_OK", F_OK);

  // rlimit() resources
  LuaSetIntField(L, "RLIMIT_AS", RLIMIT_AS);
  LuaSetIntField(L, "RLIMIT_RSS", RLIMIT_RSS);
  LuaSetIntField(L, "RLIMIT_CPU", RLIMIT_CPU);
  LuaSetIntField(L, "RLIMIT_FSIZE", RLIMIT_FSIZE);
  LuaSetIntField(L, "RLIMIT_NPROC", RLIMIT_NPROC);
  LuaSetIntField(L, "RLIMIT_NOFILE", RLIMIT_NOFILE);

  // getpriority()/setpriority() which
  LuaSetIntField(L, "PRIO_PROCESS", PRIO_PROCESS);
  LuaSetIntField(L, "PRIO_PGRP", PRIO_PGRP);
  LuaSetIntField(L, "PRIO_USER", PRIO_USER);

  // sysconf() names
  LuaSetIntField(L, "SC_ARG_MAX", _SC_ARG_MAX);
  LuaSetIntField(L, "SC_CHILD_MAX", _SC_CHILD_MAX);
  LuaSetIntField(L, "SC_CLK_TCK", _SC_CLK_TCK);
  LuaSetIntField(L, "SC_OPEN_MAX", _SC_OPEN_MAX);
  LuaSetIntField(L, "SC_PAGESIZE", _SC_PAGESIZE);
  LuaSetIntField(L, "SC_NPROCESSORS_CONF", _SC_NPROCESSORS_CONF);
  LuaSetIntField(L, "SC_NPROCESSORS_ONLN", _SC_NPROCESSORS_ONLN);

  // wait() options
  LuaSetIntField(L, "WNOHANG", WNOHANG);
  LuaSetIntField(L, "WUNTRACED", WUNTRACED);
#ifdef WCONTINUED
  LuaSetIntField(L, "WCONTINUED", WCONTINUED);
#endif

  // socket() family
  LuaSetIntField(L, "AF_UNSPEC", AF_UNSPEC);
  LuaSetIntField(L, "AF_UNIX", AF_UNIX);
  LuaSetIntField(L, "AF_INET", AF_INET);

  // socket() type
  LuaSetIntField(L, "SOCK_STREAM", SOCK_STREAM);
  LuaSetIntField(L, "SOCK_DGRAM", SOCK_DGRAM);
  LuaSetIntField(L, "SOCK_RAW", SOCK_RAW);
  LuaSetIntField(L, "SOCK_RDM", SOCK_RDM);
  LuaSetIntField(L, "SOCK_SEQPACKET", SOCK_SEQPACKET);
  LuaSetIntField(L, "SOCK_CLOEXEC", SOCK_CLOEXEC);
  LuaSetIntField(L, "SOCK_NONBLOCK", SOCK_NONBLOCK);

  // socket() protocol
  LuaSetIntField(L, "IPPROTO_IP", IPPROTO_IP);
  LuaSetIntField(L, "IPPROTO_ICMP", IPPROTO_ICMP);
  LuaSetIntField(L, "IPPROTO_TCP", IPPROTO_TCP);
  LuaSetIntField(L, "IPPROTO_UDP", IPPROTO_UDP);
  LuaSetIntField(L, "IPPROTO_RAW", IPPROTO_RAW);

  // shutdown() how
  LuaSetIntField(L, "SHUT_RD", SHUT_RD);
  LuaSetIntField(L, "SHUT_WR", SHUT_WR);
  LuaSetIntField(L, "SHUT_RDWR", SHUT_RDWR);

  // recvfrom() / sendto() flags
  LuaSetIntField(L, "MSG_OOB", MSG_OOB);
  LuaSetIntField(L, "MSG_PEEK", MSG_PEEK);
  LuaSetIntField(L, "MSG_DONTROUTE", MSG_DONTROUTE);
  LuaSetIntField(L, "MSG_DONTWAIT", MSG_DONTWAIT);
  LuaSetIntField(L, "MSG_NOSIGNAL", MSG_NOSIGNAL);
  LuaSetIntField(L, "MSG_WAITALL", MSG_WAITALL);
  LuaSetIntField(L, "MSG_TRUNC", MSG_TRUNC);
  LuaSetIntField(L, "MSG_CTRUNC", MSG_CTRUNC);

  // readdir() type
  LuaSetIntField(L, "DT_UNKNOWN", DT_UNKNOWN);
  LuaSetIntField(L, "DT_REG", DT_REG);
  LuaSetIntField(L, "DT_DIR", DT_DIR);
  LuaSetIntField(L, "DT_BLK", DT_BLK);
  LuaSetIntField(L, "DT_LNK", DT_LNK);
  LuaSetIntField(L, "DT_CHR", DT_CHR);
  LuaSetIntField(L, "DT_FIFO", DT_FIFO);
  LuaSetIntField(L, "DT_SOCK", DT_SOCK);

  // poll() flags
  LuaSetIntField(L, "POLLIN", POLLIN);
  LuaSetIntField(L, "POLLPRI", POLLPRI);
  LuaSetIntField(L, "POLLOUT", POLLOUT);
  LuaSetIntField(L, "POLLERR", POLLERR);
  LuaSetIntField(L, "POLLHUP", POLLHUP);
  LuaSetIntField(L, "POLLNVAL", POLLNVAL);
  LuaSetIntField(L, "POLLRDBAND", POLLRDBAND);
  LuaSetIntField(L, "POLLRDNORM", POLLRDNORM);
  LuaSetIntField(L, "POLLWRBAND", POLLWRBAND);
  LuaSetIntField(L, "POLLWRNORM", POLLWRNORM);
  LuaSetIntField(L, "POLLRDHUP", POLLRDHUP);

  // i/o options
  LuaSetIntField(L, "AT_FDCWD", AT_FDCWD);
  LuaSetIntField(L, "AT_EACCESS", AT_EACCESS);
  LuaSetIntField(L, "AT_SYMLINK_NOFOLLOW", AT_SYMLINK_NOFOLLOW);

  // sigprocmask() handlers
  LuaSetIntField(L, "SIG_BLOCK", SIG_BLOCK);
  LuaSetIntField(L, "SIG_UNBLOCK", SIG_UNBLOCK);
  LuaSetIntField(L, "SIG_SETMASK", SIG_SETMASK);

  // sigaction() handlers
  LuaSetIntField(L, "SIG_DFL", (intptr_t)SIG_DFL);
  LuaSetIntField(L, "SIG_IGN", (intptr_t)SIG_IGN);

  // utimensat() magnums
  LuaSetIntField(L, "UTIME_NOW", UTIME_NOW);
  LuaSetIntField(L, "UTIME_OMIT", UTIME_OMIT);

  // setitimer() which
  LuaSetIntField(L, "ITIMER_REAL", ITIMER_REAL);  // portable
  LuaSetIntField(L, "ITIMER_PROF", ITIMER_PROF);
  LuaSetIntField(L, "ITIMER_VIRTUAL", ITIMER_VIRTUAL);

  // syslog() stuff
  LuaSetIntField(L, "LOG_EMERG", LOG_EMERG);
  LuaSetIntField(L, "LOG_ALERT", LOG_ALERT);
  LuaSetIntField(L, "LOG_CRIT", LOG_CRIT);
  LuaSetIntField(L, "LOG_ERR", LOG_ERR);
  LuaSetIntField(L, "LOG_WARNING", LOG_WARNING);
  LuaSetIntField(L, "LOG_NOTICE", LOG_NOTICE);
  LuaSetIntField(L, "LOG_INFO", LOG_INFO);
  LuaSetIntField(L, "LOG_DEBUG", LOG_DEBUG);

  // setsockopt() level
  LuaSetIntField(L, "SOL_IP", SOL_IP);
  LuaSetIntField(L, "SOL_SOCKET", SOL_SOCKET);
  LuaSetIntField(L, "SOL_TCP", SOL_TCP);
  LuaSetIntField(L, "SOL_UDP", SOL_UDP);

  // sigaction() flags
  LuaSetIntField(L, "SA_RESTART", SA_RESTART);
  LuaSetIntField(L, "SA_RESETHAND", SA_RESETHAND);
  LuaSetIntField(L, "SA_NODEFER", SA_NODEFER);
  LuaSetIntField(L, "SA_NOCLDWAIT", SA_NOCLDWAIT);
  LuaSetIntField(L, "SA_NOCLDSTOP", SA_NOCLDSTOP);

  // getrusage() who
  LuaSetIntField(L, "RUSAGE_SELF", RUSAGE_SELF);
  LuaSetIntField(L, "RUSAGE_THREAD", RUSAGE_THREAD);
  LuaSetIntField(L, "RUSAGE_CHILDREN", RUSAGE_CHILDREN);
  LuaSetIntField(L, "RUSAGE_BOTH", RUSAGE_BOTH);

  // more stuff
  LuaSetIntField(L, "ARG_MAX", __get_arg_max());
  LuaSetIntField(L, "BUFSIZ", BUFSIZ);
  LuaSetIntField(L, "CLK_TCK", CLK_TCK);
  LuaSetIntField(L, "NAME_MAX", _NAME_MAX);
  LuaSetIntField(L, "NSIG", _NSIG);
  LuaSetIntField(L, "PATH_MAX", _PATH_MAX);
  LuaSetIntField(L, "PIPE_BUF", PIPE_BUF);

  // pledge() flags
  LuaSetIntField(L, "PLEDGE_PENALTY_KILL_THREAD", PLEDGE_PENALTY_KILL_THREAD);
  LuaSetIntField(L, "PLEDGE_PENALTY_KILL_PROCESS", PLEDGE_PENALTY_KILL_PROCESS);
  LuaSetIntField(L, "PLEDGE_PENALTY_RETURN_EPERM", PLEDGE_PENALTY_RETURN_EPERM);
  LuaSetIntField(L, "PLEDGE_STDERR_LOGGING", PLEDGE_STDERR_LOGGING);

  // unshare()/setns() flags (Linux CLONE_NEW*)
  LuaSetIntField(L, "CLONE_NEWNS", CLONE_NEWNS);
  LuaSetIntField(L, "CLONE_NEWCGROUP", CLONE_NEWCGROUP);
  LuaSetIntField(L, "CLONE_NEWUTS", CLONE_NEWUTS);
  LuaSetIntField(L, "CLONE_NEWIPC", CLONE_NEWIPC);
  LuaSetIntField(L, "CLONE_NEWUSER", CLONE_NEWUSER);
  LuaSetIntField(L, "CLONE_NEWPID", CLONE_NEWPID);
  LuaSetIntField(L, "CLONE_NEWNET", CLONE_NEWNET);
  LuaSetIntField(L, "CLONE_NEWTIME", CLONE_NEWTIME);

  // ifreq.ifr_flags values (IFF_*)
  LuaSetIntField(L, "IFNAMSIZ", IFNAMSIZ);
  LuaSetIntField(L, "IFF_UP", IFF_UP);
  LuaSetIntField(L, "IFF_BROADCAST", IFF_BROADCAST);
  LuaSetIntField(L, "IFF_LOOPBACK", IFF_LOOPBACK);
  LuaSetIntField(L, "IFF_POINTOPOINT", IFF_POINTOPOINT);
  LuaSetIntField(L, "IFF_RUNNING", IFF_RUNNING);
  LuaSetIntField(L, "IFF_NOARP", IFF_NOARP);
  LuaSetIntField(L, "IFF_PROMISC", IFF_PROMISC);
  LuaSetIntField(L, "IFF_MULTICAST", IFF_MULTICAST);
  LuaSetIntField(L, "IFF_ALLMULTI", IFF_ALLMULTI);
  LuaSetIntField(L, "IFF_DEBUG", IFF_DEBUG);
  LuaSetIntField(L, "IFF_NOTRAILERS", IFF_NOTRAILERS);
  LuaSetIntField(L, "IFF_MASTER", IFF_MASTER);
  LuaSetIntField(L, "IFF_SLAVE", IFF_SLAVE);
  LuaSetIntField(L, "IFF_PORTSEL", IFF_PORTSEL);
  LuaSetIntField(L, "IFF_AUTOMEDIA", IFF_AUTOMEDIA);
  LuaSetIntField(L, "IFF_DYNAMIC", IFF_DYNAMIC);

  // mount() flags (Linux MS_*)
  LuaSetIntField(L, "MS_RDONLY", MS_RDONLY);
  LuaSetIntField(L, "MS_NOSUID", MS_NOSUID);
  LuaSetIntField(L, "MS_NODEV", MS_NODEV);
  LuaSetIntField(L, "MS_NOEXEC", MS_NOEXEC);
  LuaSetIntField(L, "MS_SYNCHRONOUS", MS_SYNCHRONOUS);
  LuaSetIntField(L, "MS_REMOUNT", MS_REMOUNT);
  LuaSetIntField(L, "MS_MANDLOCK", MS_MANDLOCK);
  LuaSetIntField(L, "MS_DIRSYNC", MS_DIRSYNC);
  LuaSetIntField(L, "MS_NOATIME", MS_NOATIME);
  LuaSetIntField(L, "MS_NODIRATIME", MS_NODIRATIME);
  LuaSetIntField(L, "MS_BIND", MS_BIND);
  LuaSetIntField(L, "MS_MOVE", MS_MOVE);
  LuaSetIntField(L, "MS_REC", MS_REC);
  LuaSetIntField(L, "MS_SILENT", MS_SILENT);
  LuaSetIntField(L, "MS_POSIXACL", MS_POSIXACL);
  LuaSetIntField(L, "MS_UNBINDABLE", MS_UNBINDABLE);
  LuaSetIntField(L, "MS_PRIVATE", MS_PRIVATE);
  LuaSetIntField(L, "MS_SLAVE", MS_SLAVE);
  LuaSetIntField(L, "MS_SHARED", MS_SHARED);
  LuaSetIntField(L, "MS_RELATIME", MS_RELATIME);
  LuaSetIntField(L, "MS_STRICTATIME", MS_STRICTATIME);
  LuaSetIntField(L, "MS_LAZYTIME", MS_LAZYTIME);

  // unmount() flags (Linux umount2 flags + BSD MNT_*)
  LuaSetIntField(L, "MNT_FORCE", MNT_FORCE);
  LuaSetIntField(L, "MNT_DETACH", MNT_DETACH);
  LuaSetIntField(L, "MNT_EXPIRE", MNT_EXPIRE);
  LuaSetIntField(L, "UMOUNT_NOFOLLOW", UMOUNT_NOFOLLOW);

  // capget()/capset() capability indices (CAP_*)
  LuaSetIntField(L, "CAP_CHOWN", CAP_CHOWN);
  LuaSetIntField(L, "CAP_DAC_OVERRIDE", CAP_DAC_OVERRIDE);
  LuaSetIntField(L, "CAP_DAC_READ_SEARCH", CAP_DAC_READ_SEARCH);
  LuaSetIntField(L, "CAP_FOWNER", CAP_FOWNER);
  LuaSetIntField(L, "CAP_FSETID", CAP_FSETID);
  LuaSetIntField(L, "CAP_KILL", CAP_KILL);
  LuaSetIntField(L, "CAP_SETGID", CAP_SETGID);
  LuaSetIntField(L, "CAP_SETUID", CAP_SETUID);
  LuaSetIntField(L, "CAP_SETPCAP", CAP_SETPCAP);
  LuaSetIntField(L, "CAP_LINUX_IMMUTABLE", CAP_LINUX_IMMUTABLE);
  LuaSetIntField(L, "CAP_NET_BIND_SERVICE", CAP_NET_BIND_SERVICE);
  LuaSetIntField(L, "CAP_NET_BROADCAST", CAP_NET_BROADCAST);
  LuaSetIntField(L, "CAP_NET_ADMIN", CAP_NET_ADMIN);
  LuaSetIntField(L, "CAP_NET_RAW", CAP_NET_RAW);
  LuaSetIntField(L, "CAP_IPC_LOCK", CAP_IPC_LOCK);
  LuaSetIntField(L, "CAP_IPC_OWNER", CAP_IPC_OWNER);
  LuaSetIntField(L, "CAP_SYS_MODULE", CAP_SYS_MODULE);
  LuaSetIntField(L, "CAP_SYS_RAWIO", CAP_SYS_RAWIO);
  LuaSetIntField(L, "CAP_SYS_CHROOT", CAP_SYS_CHROOT);
  LuaSetIntField(L, "CAP_SYS_PTRACE", CAP_SYS_PTRACE);
  LuaSetIntField(L, "CAP_SYS_PACCT", CAP_SYS_PACCT);
  LuaSetIntField(L, "CAP_SYS_ADMIN", CAP_SYS_ADMIN);
  LuaSetIntField(L, "CAP_SYS_BOOT", CAP_SYS_BOOT);
  LuaSetIntField(L, "CAP_SYS_NICE", CAP_SYS_NICE);
  LuaSetIntField(L, "CAP_SYS_RESOURCE", CAP_SYS_RESOURCE);
  LuaSetIntField(L, "CAP_SYS_TIME", CAP_SYS_TIME);
  LuaSetIntField(L, "CAP_SYS_TTY_CONFIG", CAP_SYS_TTY_CONFIG);
  LuaSetIntField(L, "CAP_MKNOD", CAP_MKNOD);
  LuaSetIntField(L, "CAP_LEASE", CAP_LEASE);
  LuaSetIntField(L, "CAP_AUDIT_WRITE", CAP_AUDIT_WRITE);
  LuaSetIntField(L, "CAP_AUDIT_CONTROL", CAP_AUDIT_CONTROL);
  LuaSetIntField(L, "CAP_SETFCAP", CAP_SETFCAP);
  LuaSetIntField(L, "CAP_MAC_OVERRIDE", CAP_MAC_OVERRIDE);
  LuaSetIntField(L, "CAP_MAC_ADMIN", CAP_MAC_ADMIN);
  LuaSetIntField(L, "CAP_SYSLOG", CAP_SYSLOG);
  LuaSetIntField(L, "CAP_WAKE_ALARM", CAP_WAKE_ALARM);
  LuaSetIntField(L, "CAP_BLOCK_SUSPEND", CAP_BLOCK_SUSPEND);
  LuaSetIntField(L, "CAP_AUDIT_READ", CAP_AUDIT_READ);
  LuaSetIntField(L, "CAP_PERFMON", CAP_PERFMON);
  LuaSetIntField(L, "CAP_BPF", CAP_BPF);
  LuaSetIntField(L, "CAP_CHECKPOINT_RESTORE", CAP_CHECKPOINT_RESTORE);
  LuaSetIntField(L, "CAP_LAST_CAP", CAP_LAST_CAP);

  // prctl() options (commonly-used subset)
  LuaSetIntField(L, "PR_SET_PDEATHSIG", PR_SET_PDEATHSIG);
  LuaSetIntField(L, "PR_GET_PDEATHSIG", PR_GET_PDEATHSIG);
  LuaSetIntField(L, "PR_SET_NO_NEW_PRIVS", PR_SET_NO_NEW_PRIVS);
  LuaSetIntField(L, "PR_GET_NO_NEW_PRIVS", PR_GET_NO_NEW_PRIVS);
  LuaSetIntField(L, "PR_SET_DUMPABLE", PR_SET_DUMPABLE);
  LuaSetIntField(L, "PR_GET_DUMPABLE", PR_GET_DUMPABLE);
  LuaSetIntField(L, "PR_SET_KEEPCAPS", PR_SET_KEEPCAPS);
  LuaSetIntField(L, "PR_GET_KEEPCAPS", PR_GET_KEEPCAPS);
  LuaSetIntField(L, "PR_SET_NAME", PR_SET_NAME);
  LuaSetIntField(L, "PR_GET_NAME", PR_GET_NAME);
  LuaSetIntField(L, "PR_SET_CHILD_SUBREAPER", PR_SET_CHILD_SUBREAPER);
  LuaSetIntField(L, "PR_GET_CHILD_SUBREAPER", PR_GET_CHILD_SUBREAPER);
  LuaSetIntField(L, "PR_CAPBSET_READ", PR_CAPBSET_READ);
  LuaSetIntField(L, "PR_CAPBSET_DROP", PR_CAPBSET_DROP);

  // landlock_* rule types and access categories
  LuaSetIntField(L, "LANDLOCK_CREATE_RULESET_VERSION",
                 LANDLOCK_CREATE_RULESET_VERSION);
  LuaSetIntField(L, "LANDLOCK_RULE_PATH_BENEATH",
                 LANDLOCK_RULE_PATH_BENEATH);
  LuaSetIntField(L, "LANDLOCK_ACCESS_FS_EXECUTE",
                 LANDLOCK_ACCESS_FS_EXECUTE);
  LuaSetIntField(L, "LANDLOCK_ACCESS_FS_WRITE_FILE",
                 LANDLOCK_ACCESS_FS_WRITE_FILE);
  LuaSetIntField(L, "LANDLOCK_ACCESS_FS_READ_FILE",
                 LANDLOCK_ACCESS_FS_READ_FILE);
  LuaSetIntField(L, "LANDLOCK_ACCESS_FS_READ_DIR",
                 LANDLOCK_ACCESS_FS_READ_DIR);
  LuaSetIntField(L, "LANDLOCK_ACCESS_FS_REMOVE_DIR",
                 LANDLOCK_ACCESS_FS_REMOVE_DIR);
  LuaSetIntField(L, "LANDLOCK_ACCESS_FS_REMOVE_FILE",
                 LANDLOCK_ACCESS_FS_REMOVE_FILE);
  LuaSetIntField(L, "LANDLOCK_ACCESS_FS_MAKE_CHAR",
                 LANDLOCK_ACCESS_FS_MAKE_CHAR);
  LuaSetIntField(L, "LANDLOCK_ACCESS_FS_MAKE_DIR",
                 LANDLOCK_ACCESS_FS_MAKE_DIR);
  LuaSetIntField(L, "LANDLOCK_ACCESS_FS_MAKE_REG",
                 LANDLOCK_ACCESS_FS_MAKE_REG);
  LuaSetIntField(L, "LANDLOCK_ACCESS_FS_MAKE_SOCK",
                 LANDLOCK_ACCESS_FS_MAKE_SOCK);
  LuaSetIntField(L, "LANDLOCK_ACCESS_FS_MAKE_FIFO",
                 LANDLOCK_ACCESS_FS_MAKE_FIFO);
  LuaSetIntField(L, "LANDLOCK_ACCESS_FS_MAKE_BLOCK",
                 LANDLOCK_ACCESS_FS_MAKE_BLOCK);
  LuaSetIntField(L, "LANDLOCK_ACCESS_FS_MAKE_SYM",
                 LANDLOCK_ACCESS_FS_MAKE_SYM);
  LuaSetIntField(L, "LANDLOCK_ACCESS_FS_REFER",
                 LANDLOCK_ACCESS_FS_REFER);
  LuaSetIntField(L, "LANDLOCK_ACCESS_FS_TRUNCATE",
                 LANDLOCK_ACCESS_FS_TRUNCATE);
  LuaSetIntField(L, "LANDLOCK_RULE_NET_PORT",
                 LANDLOCK_RULE_NET_PORT);
  LuaSetIntField(L, "LANDLOCK_ACCESS_NET_BIND_TCP",
                 LANDLOCK_ACCESS_NET_BIND_TCP);
  LuaSetIntField(L, "LANDLOCK_ACCESS_NET_CONNECT_TCP",
                 LANDLOCK_ACCESS_NET_CONNECT_TCP);
  LuaSetIntField(L, "LANDLOCK_ACCESS_FS_IOCTL_DEV",
                 LANDLOCK_ACCESS_FS_IOCTL_DEV);
  LuaSetIntField(L, "LANDLOCK_ACCESS_FS_RESOLVE_UNIX",
                 LANDLOCK_ACCESS_FS_RESOLVE_UNIX);
  LuaSetIntField(L, "LANDLOCK_SCOPE_ABSTRACT_UNIX_SOCKET",
                 LANDLOCK_SCOPE_ABSTRACT_UNIX_SOCKET);
  LuaSetIntField(L, "LANDLOCK_SCOPE_SIGNAL",
                 LANDLOCK_SCOPE_SIGNAL);
  LuaSetIntField(L, "LANDLOCK_RESTRICT_SELF_LOG_SAME_EXEC_OFF",
                 LANDLOCK_RESTRICT_SELF_LOG_SAME_EXEC_OFF);
  LuaSetIntField(L, "LANDLOCK_RESTRICT_SELF_LOG_NEW_EXEC_ON",
                 LANDLOCK_RESTRICT_SELF_LOG_NEW_EXEC_ON);
  LuaSetIntField(L, "LANDLOCK_RESTRICT_SELF_LOG_SUBDOMAINS_OFF",
                 LANDLOCK_RESTRICT_SELF_LOG_SUBDOMAINS_OFF);
  LuaSetIntField(L, "LANDLOCK_RESTRICT_SELF_TSYNC",
                 LANDLOCK_RESTRICT_SELF_TSYNC);

  // ioctl(SIOC*) requests for network interface manipulation
  LuaSetIntField(L, "SIOCGIFFLAGS", SIOCGIFFLAGS);
  LuaSetIntField(L, "SIOCSIFFLAGS", SIOCSIFFLAGS);
  LuaSetIntField(L, "SIOCGIFADDR", SIOCGIFADDR);
  LuaSetIntField(L, "SIOCSIFADDR", SIOCSIFADDR);
  LuaSetIntField(L, "SIOCGIFDSTADDR", SIOCGIFDSTADDR);
  LuaSetIntField(L, "SIOCSIFDSTADDR", SIOCSIFDSTADDR);
  LuaSetIntField(L, "SIOCGIFBRDADDR", SIOCGIFBRDADDR);
  LuaSetIntField(L, "SIOCSIFBRDADDR", SIOCSIFBRDADDR);
  LuaSetIntField(L, "SIOCGIFNETMASK", SIOCGIFNETMASK);
  LuaSetIntField(L, "SIOCSIFNETMASK", SIOCSIFNETMASK);
  LuaSetIntField(L, "SIOCGIFMTU", SIOCGIFMTU);
  LuaSetIntField(L, "SIOCSIFMTU", SIOCSIFMTU);
  LuaSetIntField(L, "SIOCGIFMETRIC", SIOCGIFMETRIC);
  LuaSetIntField(L, "SIOCSIFMETRIC", SIOCSIFMETRIC);
  LuaSetIntField(L, "SIOCGIFINDEX", SIOCGIFINDEX);
  LuaSetIntField(L, "SIOCGIFNAME", SIOCGIFNAME);

  // statfs::f_flags
  LuaSetIntField(L, "ST_RDONLY", ST_RDONLY);
  LuaSetIntField(L, "ST_NOSUID", ST_NOSUID);
  LuaSetIntField(L, "ST_NODEV", ST_NODEV);
  LuaSetIntField(L, "ST_NOEXEC", ST_NOEXEC);
  LuaSetIntField(L, "ST_SYNCHRONOUS", ST_SYNCHRONOUS);
  LuaSetIntField(L, "ST_NOATIME", ST_NOATIME);
  LuaSetIntField(L, "ST_RELATIME", ST_RELATIME);
  LuaSetIntField(L, "ST_APPEND", ST_APPEND);
  LuaSetIntField(L, "ST_IMMUTABLE", ST_IMMUTABLE);
  LuaSetIntField(L, "ST_MANDLOCK", ST_MANDLOCK);
  LuaSetIntField(L, "ST_NODIRATIME", ST_NODIRATIME);
  LuaSetIntField(L, "ST_WRITE", ST_WRITE);

  // tcsetattr() action
  LuaSetIntField(L, "TCSANOW", TCSANOW);
  LuaSetIntField(L, "TCSADRAIN", TCSADRAIN);
  LuaSetIntField(L, "TCSAFLUSH", TCSAFLUSH);

  // termios c_iflag
  LuaSetIntField(L, "BRKINT", BRKINT);
  LuaSetIntField(L, "ICRNL", ICRNL);
  LuaSetIntField(L, "IGNBRK", IGNBRK);
  LuaSetIntField(L, "IGNCR", IGNCR);
  LuaSetIntField(L, "IGNPAR", IGNPAR);
  LuaSetIntField(L, "INLCR", INLCR);
  LuaSetIntField(L, "INPCK", INPCK);
  LuaSetIntField(L, "ISTRIP", ISTRIP);
  LuaSetIntField(L, "IXANY", IXANY);
  LuaSetIntField(L, "IXOFF", IXOFF);
  LuaSetIntField(L, "IXON", IXON);
  LuaSetIntField(L, "PARMRK", PARMRK);

  // termios c_oflag
  LuaSetIntField(L, "OPOST", OPOST);
  LuaSetIntField(L, "ONLCR", ONLCR);
  LuaSetIntField(L, "OCRNL", OCRNL);
  LuaSetIntField(L, "ONOCR", ONOCR);
  LuaSetIntField(L, "ONLRET", ONLRET);

  // termios c_cflag
  LuaSetIntField(L, "CLOCAL", CLOCAL);
  LuaSetIntField(L, "CREAD", CREAD);
  LuaSetIntField(L, "CS5", CS5);
  LuaSetIntField(L, "CS6", CS6);
  LuaSetIntField(L, "CS7", CS7);
  LuaSetIntField(L, "CS8", CS8);
  LuaSetIntField(L, "CSIZE", CSIZE);
  LuaSetIntField(L, "CSTOPB", CSTOPB);
  LuaSetIntField(L, "HUPCL", HUPCL);
  LuaSetIntField(L, "PARENB", PARENB);
  LuaSetIntField(L, "PARODD", PARODD);

  // termios c_lflag
  LuaSetIntField(L, "ECHO", ECHO);
  LuaSetIntField(L, "ECHOE", ECHOE);
  LuaSetIntField(L, "ECHOK", ECHOK);
  LuaSetIntField(L, "ECHONL", ECHONL);
  LuaSetIntField(L, "ICANON", ICANON);
  LuaSetIntField(L, "IEXTEN", IEXTEN);
  LuaSetIntField(L, "ISIG", ISIG);
  LuaSetIntField(L, "NOFLSH", NOFLSH);
  LuaSetIntField(L, "TOSTOP", TOSTOP);

  // termios c_cc indices
  LuaSetIntField(L, "VEOF", VEOF);
  LuaSetIntField(L, "VEOL", VEOL);
  LuaSetIntField(L, "VERASE", VERASE);
  LuaSetIntField(L, "VINTR", VINTR);
  LuaSetIntField(L, "VKILL", VKILL);
  LuaSetIntField(L, "VMIN", VMIN);
  LuaSetIntField(L, "VQUIT", VQUIT);
  LuaSetIntField(L, "VSTART", VSTART);
  LuaSetIntField(L, "VSTOP", VSTOP);
  LuaSetIntField(L, "VTIME", VTIME);
  LuaSetIntField(L, "NCCS", NCCS);

  return 1;
}
