/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╚──────────────────────────────────────────────────────────────────────────────╝
│                                                                              │
│  Cosmopolitan Lua REPL Module                                               │
│  Copyright © 2024-2026                                                       │
│                                                                              │
│  Permission is hereby granted, free of charge, to any person obtaining       │
│  a copy of this software and associated documentation files (the             │
│  "Software"), to deal in the Software without restriction, including         │
│  without limitation the rights to use, copy, modify, merge, publish,         │
│  distribute, sublicense, and/or sell copies of the Software, and to          │
│  permit persons to whom the Software is furnished to do so, subject to       │
│  the following conditions:                                                   │
│                                                                              │
│  The above copyright notice and this permission notice shall be              │
│  included in all copies or substantial portions of the Software.             │
│                                                                              │
│  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,             │
│  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF          │
│  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.      │
│  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY        │
│  CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,        │
│  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE           │
│  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                      │
│                                                                              │
╚─────────────────────────────────────────────────────────────────────────────*/
#include "third_party/lua/lreplmod.h"
#include "libc/errno.h"
#include "libc/sock/sock.h"
#include "libc/sock/struct/pollfd.h"
#include "libc/str/str.h"
#include "libc/sysv/consts/poll.h"
#include "third_party/linenoise/linenoise.h"
#include "third_party/lua/lauxlib.h"
#include "third_party/lua/lprefix.h"
#include "third_party/lua/lrepl.h"
#include "third_party/lua/lua.h"
#include "third_party/lua/lualib.h"

/*
** Do the REPL: repeatedly read (load) a line, evaluate (call) it, and
** print any results.
*/
static int LuaRepl(lua_State *L) {
  int status;
  const char *oldprogname = lua_progname;
  lua_progname = NULL;  /* no 'progname' on errors in interactive mode */
  lua_initrepl(L);
  for (;;) {
    if (lua_repl_isterminal)
      linenoiseEnableRawMode(0);
 TryAgain:
    status = lua_loadline(L);
    if (status == -2 && errno == EAGAIN) {
      errno = 0;
      poll(&(struct pollfd){0, POLLIN}, 1, -1);
      goto TryAgain;
    }
    if (lua_repl_isterminal)
      linenoiseDisableRawMode();
    if (status == -1) {
      break;
    } else if (status == -2) {
      lua_pushfstring(L, "read error: %s", strerror(errno));
      lua_report(L, status);
      lua_freerepl();
      lua_progname = oldprogname;
      return 0;
    }
    if (status == LUA_OK)
      status = lua_runchunk(L, 0, LUA_MULTRET);
    if (status == LUA_OK) {
      lua_l_print(L);
    } else {
      lua_report(L, status);
    }
  }
  lua_freerepl();
  lua_settop(L, 0);  /* clear stack */
  lua_progname = oldprogname;
  return 0;
}

static const luaL_Reg kReplFuncs[] = {
    {"start", LuaRepl},
    {NULL, NULL}
};

int luaopen_repl(lua_State *L) {
  luaL_newlib(L, kReplFuncs);
  return 1;
}
