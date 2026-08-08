/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2022 Justine Alexandra Roberts Tunney                              │
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
#include "libc/macros.h"
#include "libc/str/str.h"
#include "third_party/lua/lauxlib.h"
#include "third_party/regex/regex.h"

static void LuaSetIntField(lua_State *L, const char *k, lua_Integer v) {
  lua_pushinteger(L, v);
  lua_setfield(L, -2, k);
}

// Returns nil + a formatted regerror() string, per the fork's error
// convention (nil, err:string). Reserved for real regex failures
// (bad pattern at compile time, REG_ESPACE out-of-memory at search
// time); an ordinary no-match is not an error and is reported as a
// bare nil by LuaReSearchImpl.
static int LuaReReturnError(lua_State *L, regex_t *r, int rc) {
  char doc[64];
  regerror(rc, r, doc, sizeof(doc));
  lua_pushnil(L);
  lua_pushstring(L, doc);
  return 2;
}

static regex_t *LuaReCompileImpl(lua_State *L, const char *p, int f) {
  int rc;
  regex_t *r;
  r = lua_newuserdatauv(L, sizeof(regex_t), 0);
  f &= REG_EXTENDED | REG_ICASE | REG_NEWLINE | REG_NOSUB;
  f ^= REG_EXTENDED;
  if ((rc = regcomp(r, p, f)) == REG_OK) {
    // Only a successfully compiled regex gets the re.Regex metatable
    // (and thus the regfree() __gc finalizer). On failure the userdata
    // holds an unusable regex_t, so it must not be freed; leaving it
    // metatable-less lets the collector reclaim the raw memory safely.
    luaL_setmetatable(L, "re.Regex");
    return r;
  } else {
    LuaReReturnError(L, r, rc);
    return NULL;
  }
}

// On a match, returns the whole matched substring plus a table of the
// parenthesized capture groups (empty when the pattern has no groups).
// A no-match is not an error: it returns a single bare nil so the
// idiomatic `if match` works and `select("#", ...) == 1`. A genuine
// regexec() failure (e.g. REG_ESPACE) returns nil, err:string.
static int LuaReSearchImpl(lua_State *L, regex_t *r, const char *s, int f) {
  int rc, i, n;
  regmatch_t *m;
  luaL_Buffer tmp;
  n = 1 + r->re_nsub;
  m = (regmatch_t *)luaL_buffinitsize(L, &tmp, n * sizeof(regmatch_t));
  m->rm_so = 0;
  m->rm_eo = 0;
  rc = regexec(r, s, n, m, f >> 8);
  if (rc == REG_OK) {
    lua_pushlstring(L, s + m[0].rm_so, m[0].rm_eo - m[0].rm_so);
    lua_createtable(L, n - 1, 0);
    for (i = 1; i < n; ++i) {
      if (m[i].rm_so >= 0) {
        lua_pushlstring(L, s + m[i].rm_so, m[i].rm_eo - m[i].rm_so);
      } else {
        lua_pushliteral(L, "");
      }
      lua_rawseti(L, -2, i);
    }
    return 2;
  } else if (rc == REG_NOMATCH) {
    lua_pushnil(L);
    return 1;
  } else {
    return LuaReReturnError(L, r, rc);
  }
}

// Like LuaReSearchImpl, but reports WHERE the match is: absolute
// 1-based inclusive start and end offsets into the original subject,
// then the capture table. The search runs on the tail s + off (off is
// 0-based, already validated <= subject length), which is why the
// offsets regexec() reports are rebased by off before being pushed.
// No-match and error conventions are LuaReSearchImpl's: a bare nil for
// no match, nil + err:string for an engine failure.
static int LuaReFindImpl(lua_State *L, regex_t *r, const char *s, size_t off,
                         int f) {
  int rc, i, n;
  regmatch_t *m;
  luaL_Buffer tmp;
  n = 1 + r->re_nsub;
  m = (regmatch_t *)luaL_buffinitsize(L, &tmp, n * sizeof(regmatch_t));
  m->rm_so = 0;
  m->rm_eo = 0;
  rc = regexec(r, s + off, n, m, f >> 8);
  if (rc == REG_OK) {
    lua_pushinteger(L, off + m[0].rm_so + 1);
    lua_pushinteger(L, off + m[0].rm_eo);
    lua_createtable(L, n - 1, 0);
    for (i = 1; i < n; ++i) {
      if (m[i].rm_so >= 0) {
        lua_pushlstring(L, s + off + m[i].rm_so, m[i].rm_eo - m[i].rm_so);
      } else {
        lua_pushliteral(L, "");
      }
      lua_rawseti(L, -2, i);
    }
    return 3;
  } else if (rc == REG_NOMATCH) {
    lua_pushnil(L);
    return 1;
  } else {
    return LuaReReturnError(L, r, rc);
  }
}

////////////////////////////////////////////////////////////////////////////////
// re

static int LuaReSearch(lua_State *L) {
  int f;
  regex_t *r;
  const char *p, *s;
  p = luaL_checkstring(L, 1);
  s = luaL_checkstring(L, 2);
  f = luaL_optinteger(L, 3, 0);
  if (f & ~(REG_EXTENDED | REG_ICASE | REG_NEWLINE | REG_NOSUB |
            REG_NOTBOL << 8 | REG_NOTEOL << 8)) {
    luaL_argerror(L, 3, "invalid flags");
    __builtin_unreachable();
  }
  if ((r = LuaReCompileImpl(L, p, f))) {
    return LuaReSearchImpl(L, r, s, f);
  } else {
    return 2;
  }
}

static int LuaReCompile(lua_State *L) {
  int f;
  regex_t *r;
  const char *p;
  p = luaL_checkstring(L, 1);
  f = luaL_optinteger(L, 2, 0);
  if (f & ~(REG_EXTENDED | REG_ICASE | REG_NEWLINE | REG_NOSUB)) {
    luaL_argerror(L, 2, "invalid flags");
    __builtin_unreachable();
  }
  if ((r = LuaReCompileImpl(L, p, f))) {
    return 1;
  } else {
    return 2;
  }
}

////////////////////////////////////////////////////////////////////////////////
// re.Regex

static int LuaReRegexSearch(lua_State *L) {
  int f;
  regex_t *r;
  const char *s;
  r = luaL_checkudata(L, 1, "re.Regex");
  s = luaL_checkstring(L, 2);
  f = luaL_optinteger(L, 3, 0);
  if (f & ~(REG_NOTBOL << 8 | REG_NOTEOL << 8)) {
    luaL_argerror(L, 3, "invalid flags");
    __builtin_unreachable();
  }
  return LuaReSearchImpl(L, r, s, f);
}

static int LuaReRegexFind(lua_State *L) {
  int f;
  size_t sn;
  regex_t *r;
  const char *s;
  lua_Integer init;
  r = luaL_checkudata(L, 1, "re.Regex");
  s = luaL_checklstring(L, 2, &sn);
  f = luaL_optinteger(L, 3, 0);
  init = luaL_optinteger(L, 4, 1);
  if (f & ~(REG_NOTBOL << 8 | REG_NOTEOL << 8)) {
    luaL_argerror(L, 3, "invalid flags");
    __builtin_unreachable();
  }
  if (init < 1)
    init = 1;
  if (init > (lua_Integer)sn + 1) {
    lua_pushnil(L);
    return 1;
  }
  return LuaReFindImpl(L, r, s, init - 1, f);
}

static int LuaReRegexGc(lua_State *L) {
  regex_t *r;
  r = luaL_checkudata(L, 1, "re.Regex");
  regfree(r);
  return 0;
}

static const luaL_Reg kLuaRe[] = {
    {"compile", LuaReCompile},  //
    {"search", LuaReSearch},    //
    {NULL, NULL},               //
};

static const luaL_Reg kLuaReRegexMeth[] = {
    {"find", LuaReRegexFind},      //
    {"match", LuaReRegexSearch},   // the charter spelling (match IS search)
    {"search", LuaReRegexSearch},  //
    {NULL, NULL},                  //
};

static const luaL_Reg kLuaReRegexMeta[] = {
    {"__gc", LuaReRegexGc},  //
    {NULL, NULL},            //
};

static void LuaReRegexObj(lua_State *L) {
  luaL_newmetatable(L, "re.Regex");
  luaL_setfuncs(L, kLuaReRegexMeta, 0);
  luaL_newlibtable(L, kLuaReRegexMeth);
  luaL_setfuncs(L, kLuaReRegexMeth, 0);
  lua_setfield(L, -2, "__index");
  lua_pop(L, 1);
}

////////////////////////////////////////////////////////////////////////////////

_Alignas(1) static const struct thatispacked {
  const char s[8];
  char x;
} kReMagnums[] = {
    {"BASIC", REG_EXTENDED},     // compile flag
    {"ICASE", REG_ICASE},        // compile flag
    {"NEWLINE", REG_NEWLINE},    // compile flag
    {"NOSUB", REG_NOSUB},        // compile flag
    {"NOMATCH", REG_NOMATCH},    // error
    {"BADPAT", REG_BADPAT},      // error
    {"ECOLLATE", REG_ECOLLATE},  // error
    {"ECTYPE", REG_ECTYPE},      // error
    {"EESCAPE", REG_EESCAPE},    // error
    {"ESUBREG", REG_ESUBREG},    // error
    {"EBRACK", REG_EBRACK},      // error
    {"EPAREN", REG_EPAREN},      // error
    {"EBRACE", REG_EBRACE},      // error
    {"BADBR", REG_BADBR},        // error
    {"ERANGE", REG_ERANGE},      // error
    {"ESPACE", REG_ESPACE},      // error
    {"BADRPT", REG_BADRPT},      // error
};

int LuaRe(lua_State *L) {
  int i;
  char buf[9];
  luaL_newlib(L, kLuaRe);
  LuaSetIntField(L, "NOTBOL", REG_NOTBOL << 8);  // search flag
  LuaSetIntField(L, "NOTEOL", REG_NOTEOL << 8);  // search flag
  for (i = 0; i < ARRAYLEN(kReMagnums); ++i) {
    memcpy(buf, kReMagnums[i].s, 8);
    buf[8] = 0;
    LuaSetIntField(L, buf, kReMagnums[i].x);
  }
  LuaReRegexObj(L);
  return 1;
}
