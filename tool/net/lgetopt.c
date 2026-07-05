/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2024 Justine Alexandra Roberts Tunney                              │
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
#include "tool/net/lgetopt.h"
#include "libc/str/str.h"
#include "third_party/getopt/long1.h"
#include "third_party/getopt/long2.h"
#include "third_party/lua/lauxlib.h"
#include "third_party/lua/lua.h"

#define MAX_ARGC     10000
#define MAX_LONGOPTS  1000

// Push `nil, <message>` and return 2 from the calling C function.
#define FAIL(...)                     \
  do {                                \
    lua_pushnil(L);                   \
    lua_pushfstring(L, __VA_ARGS__);  \
    return 2;                         \
  } while (0)

static int ParseHasArg(const char *s) {
  if (!strcmp(s, "none"))
    return no_argument;
  if (!strcmp(s, "required"))
    return required_argument;
  if (!strcmp(s, "optional"))
    return optional_argument;
  return -1;
}

// getopt.parse(args, optstring[, longopts])
//     ├─→ {opts={{opt,arg?}...}, args={...}, unknown={...}, missing={...}}
//     └─→ nil, err
//
// Single-shot, re-entrant command-line parser. Unlike the old stateful
// Parser userdata, all state is local to this one call: the underlying
// getopt globals (optind/opterr/optopt/optarg) are reset on entry and the
// whole argv is consumed before returning, so two parse() calls can never
// corrupt one another. The optstring is normalized to getopt's leading-`:`
// protocol so a missing required argument ('missing') is reported
// distinctly from an unrecognized option ('unknown'). 'unknown' entries
// always carry their dashes; 'missing' entries name the bare option.
static int LuaGetoptParse(lua_State *L) {
  size_t olen;
  const char *ostr;
  lua_Integer argc_raw, nlong_raw;
  int argc, nlong, c, longidx = 0;
  int n_opts = 0, n_args = 0, n_unknown = 0, n_missing = 0;
  int T_opts, T_args, T_unknown, T_missing;
  char **argv;
  struct option *longopts;
  char *opts;

  if (!lua_istable(L, 1))
    FAIL("args must be a table");
  if (lua_type(L, 2) != LUA_TSTRING)
    FAIL("optstring must be a string");
  if (!lua_isnoneornil(L, 3) && !lua_istable(L, 3))
    FAIL("longopts must be a table");
  ostr = lua_tolstring(L, 2, &olen);

  // Bounds-check the tables before touching C memory.
  argc_raw = luaL_len(L, 1);
  if (argc_raw < 0 || argc_raw > MAX_ARGC)
    FAIL("args table too large (max %d)", MAX_ARGC);
  argc = (int)argc_raw;

  nlong_raw = lua_isnoneornil(L, 3) ? 0 : luaL_len(L, 3);
  if (nlong_raw < 0 || nlong_raw > MAX_LONGOPTS)
    FAIL("longopts table too large (max %d)", MAX_LONGOPTS);
  nlong = (int)nlong_raw;

  // Validate every longopt entry up front.
  for (int i = 0; i < nlong; i++) {
    lua_rawgeti(L, 3, i + 1);
    if (!lua_istable(L, -1))
      FAIL("longopt[%d] must be a table", i + 1);
    lua_rawgeti(L, -1, 1);
    if (lua_type(L, -1) != LUA_TSTRING)
      FAIL("longopt[%d][1] (name) must be a string", i + 1);
    lua_pop(L, 1);
    lua_rawgeti(L, -1, 2);
    if (lua_type(L, -1) != LUA_TSTRING)
      FAIL("longopt[%d][2] (has_arg) must be a string", i + 1);
    if (ParseHasArg(lua_tostring(L, -1)) == -1)
      FAIL("longopt[%d][2] must be 'none', 'required', or 'optional'", i + 1);
    lua_pop(L, 1);
    lua_rawgeti(L, -1, 3);
    if (!lua_isnoneornil(L, -1) && lua_type(L, -1) != LUA_TSTRING)
      FAIL("longopt[%d][3] (short) must be a string or nil", i + 1);
    lua_pop(L, 1);
    lua_pop(L, 1);  // pop entry
  }

  // Validate that every arg is a string.
  for (int i = 1; i <= argc; i++) {
    lua_rawgeti(L, 1, i);
    if (lua_type(L, -1) != LUA_TSTRING)
      FAIL("args[%d] must be a string", i);
    lua_pop(L, 1);
  }

  // Scratch buffers are GC-managed userdata rather than malloc, so nothing
  // leaks even if a later lua_push raises out-of-memory. The pointers they
  // hold reference strings owned by the args (index 1) and longopts
  // (index 3) tables, which stay on the stack for the whole call and so
  // keep those strings rooted and valid for the parse.
  argv = lua_newuserdatauv(L, (size_t)(argc + 2) * sizeof(*argv), 0);
  longopts = lua_newuserdatauv(L, (size_t)(nlong + 1) * sizeof(*longopts), 0);
  opts = lua_newuserdatauv(L, olen + 2, 0);

  argv[0] = "getopt";
  for (int i = 1; i <= argc; i++) {
    lua_rawgeti(L, 1, i);
    argv[i] = (char *)lua_tostring(L, -1);
    lua_pop(L, 1);
  }
  argv[argc + 1] = NULL;

  for (int i = 0; i < nlong; i++) {
    lua_rawgeti(L, 3, i + 1);
    lua_rawgeti(L, -1, 1);
    longopts[i].name = lua_tostring(L, -1);
    lua_pop(L, 1);
    lua_rawgeti(L, -1, 2);
    longopts[i].has_arg = ParseHasArg(lua_tostring(L, -1));
    lua_pop(L, 1);
    lua_rawgeti(L, -1, 3);
    if (lua_type(L, -1) == LUA_TSTRING) {
      const char *s = lua_tostring(L, -1);
      longopts[i].val = (unsigned char)s[0];
    } else {
      longopts[i].val = 0;
    }
    lua_pop(L, 1);
    longopts[i].flag = NULL;
    lua_pop(L, 1);  // pop entry
  }
  longopts[nlong].name = NULL;
  longopts[nlong].has_arg = 0;
  longopts[nlong].flag = NULL;
  longopts[nlong].val = 0;

  // Normalize to a leading-`:` optstring so getopt returns ':' for a missing
  // required argument and '?' for an unknown option. A leading '+'/'-' mode
  // modifier must stay first; an existing ':' is left as-is.
  {
    size_t k = 0, src = 0;
    if (olen && (ostr[0] == '+' || ostr[0] == '-'))
      opts[k++] = ostr[src++];
    if (!(olen > src && ostr[src] == ':'))
      opts[k++] = ':';
    if (olen > src) {
      memcpy(opts + k, ostr + src, olen - src);
      k += olen - src;
    }
    opts[k] = '\0';
  }

  lua_newtable(L);
  T_opts = lua_gettop(L);
  lua_newtable(L);
  T_args = lua_gettop(L);
  lua_newtable(L);
  T_unknown = lua_gettop(L);
  lua_newtable(L);
  T_missing = lua_gettop(L);

  // Reset getopt's globals for a clean single-shot parse. optreset=1 forces
  // the BSD scanner to re-initialize its internal cursor and permutation
  // bookkeeping, which is what makes back-to-back parse() calls independent.
  optind = 1;
  optreset = 1;
  opterr = 0;
  optarg = NULL;
  optopt = 0;

  while ((c = getopt_long(argc + 1, argv, opts, longopts, &longidx)) != -1) {
    if (c == '?') {
      // Unknown option; record the offending token WITH its dashes.
      if (optopt) {
        char tok[3] = {'-', (char)optopt, '\0'};
        lua_pushstring(L, tok);
      } else {
        lua_pushstring(L, argv[optind - 1]);  // full "--name"
      }
      lua_rawseti(L, T_unknown, ++n_unknown);
    } else if (c == ':') {
      // Missing required argument; record the bare option (no dashes).
      if (optopt) {
        char id[2] = {(char)optopt, '\0'};
        lua_pushstring(L, id);
      } else {
        // long option with no short equivalent: recover its name
        const char *t = argv[optind - 1];
        while (*t == '-') t++;
        lua_pushlstring(L, t, strcspn(t, "="));
      }
      lua_rawseti(L, T_missing, ++n_missing);
    } else {
      // Recognized option: {opt=<name>, arg=<value>?}.
      lua_createtable(L, 0, 2);
      if (c == 0) {
        // long option with no short equivalent
        lua_pushstring(L, longopts[longidx].name);
      } else {
        char s[2] = {(char)c, '\0'};
        lua_pushstring(L, s);
      }
      lua_setfield(L, -2, "opt");
      if (optarg) {
        lua_pushstring(L, optarg);
        lua_setfield(L, -2, "arg");
      }
      lua_rawseti(L, T_opts, ++n_opts);
    }
  }

  // Everything left over is a non-option argument.
  for (int i = optind; i <= argc; i++) {
    lua_pushstring(L, argv[i]);
    lua_rawseti(L, T_args, ++n_args);
  }

  lua_createtable(L, 0, 4);
  lua_pushvalue(L, T_opts);
  lua_setfield(L, -2, "opts");
  lua_pushvalue(L, T_args);
  lua_setfield(L, -2, "args");
  lua_pushvalue(L, T_unknown);
  lua_setfield(L, -2, "unknown");
  lua_pushvalue(L, T_missing);
  lua_setfield(L, -2, "missing");
  return 1;
}

static const luaL_Reg kLuaGetopt[] = {
    {"parse", LuaGetoptParse},
    {0},
};

int LuaGetopt(lua_State *L) {
  luaL_newlib(L, kLuaGetopt);
  return 1;
}
