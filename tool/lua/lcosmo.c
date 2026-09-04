/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2024 Will Maier                                                    │
│                                                                              │
│ Permission to use, copy, modify, and/or distribute this software for        │
│ any purpose with or without fee is hereby granted, provided that the        │
│ above copyright notice and this permission notice appear in all copies.     │
│                                                                              │
│ THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL               │
│ WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED               │
│ WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE            │
│ AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL        │
│ DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR       │
│ PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER              │
│ TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR            │
│ PERFORMANCE OF THIS SOFTWARE.                                               │
╚─────────────────────────────────────────────────────────────────────────────*/
#include "third_party/lua/lauxlib.h"
#include "third_party/lua/cosmo/lcosmo.h"
#include "third_party/lua/cosmo/lreplmod.h"
#include "third_party/lua/cosmo/lunix.h"
#include "third_party/lua/cosmo/cosmo.h"
#include "tool/net/lfuncs.h"
#include "tool/net/lpath.h"
#include "tool/net/ljson.h"
#include "tool/net/llua.h"
#include "tool/net/lfetch.h"
#include "tool/net/lgetopt.h"
#include "tool/net/lzip.h"
#include "tool/net/lcov.h"
#include "net/http/http.h"
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <time.h>

char *FormatUnixHttpDateTime(char *s, int64_t t) {
  struct tm tm;
  gmtime_r(&t, &tm);
  FormatHttpDateTime(s, &tm);
  return s;
}

static int LuaDecodeJson(lua_State *L) {
  size_t n;
  const char *p;
  struct DecodeJson r;
  int nullvalidx = 0;
  p = luaL_checklstring(L, 1, &n);
  if (lua_istable(L, 2)) {
    // opts.nullval (dkjson-style): a caller-supplied value pushed for
    // every JSON null, so nulls survive the decode; pinned to a stable
    // stack slot the parse reads from. Extra stack slots below the
    // returned values are discarded by Lua on return.
    lua_getfield(L, 2, "nullval");
    if (!lua_isnil(L, -1)) {
      nullvalidx = lua_gettop(L);
    } else {
      lua_pop(L, 1);
    }
  }
  r = DecodeJsonEx(L, p, n, nullvalidx);
  if (!r.rc) {
    lua_pushnil(L);
    lua_pushstring(L, "unexpected eof");
    return 2;
  }
  if (r.rc == -1) {
    lua_pushnil(L);
    lua_pushstring(L, r.p);
    return 2;
  }
  r = DecodeJsonEx(L, r.p, n - (r.p - p), nullvalidx);
  if (r.rc) {
    lua_pushnil(L);
    lua_pushstring(L, "junk after expression");
    return 2;
  }
  return 1;
}

// Reads a Lua literal file's table without running it. Returns the
// table, or nil plus the refusal and the 1-based byte offset it happened
// at. The offset is what a caller turns into a line number, once, on the
// error path, so no line counting happens while the source is parsed.
static int LuaDecodeLua(lua_State *L) {
  size_t n;
  const char *p;
  struct DecodeLua r;
  char err[LLUA_ERRMAX];
  p = luaL_checklstring(L, 1, &n);
  err[0] = 0;
  r = DecodeLua(L, p, n, err, sizeof(err));
  if (r.rc == -1) {
    lua_pushnil(L);
    lua_pushstring(L, err);
    lua_pushinteger(L, (lua_Integer)(r.p - p) + 1);
    return 3;
  }
  return 1;
}

static int LuaEncodeSmth(lua_State *L, int Encoder(lua_State *, char **, int,
                                                   struct EncoderConfig)) {
  char *p = 0;
  struct EncoderConfig conf = {
      .maxdepth = 64,
      .sorted = 1,
      .pretty = 0,
      .indent = "  ",
  };
  if (lua_istable(L, 2)) {
    lua_settop(L, 2);
    lua_getfield(L, 2, "maxdepth");
    if (!lua_isnoneornil(L, -1)) {
      lua_Integer n = lua_tointeger(L, -1);
      n = n < 0 ? 0 : (n > SHRT_MAX ? SHRT_MAX : n);
      conf.maxdepth = n;
    }
    lua_getfield(L, 2, "sorted");
    if (!lua_isnoneornil(L, -1)) {
      conf.sorted = lua_toboolean(L, -1);
    }
    lua_getfield(L, 2, "nan");
    if (!lua_isnoneornil(L, -1)) {
      const char *nanopt = lua_tostring(L, -1);
      if (nanopt && !strcmp(nanopt, "null")) {
        conf.nannull = true;
      } else {
        lua_pushnil(L);
        lua_pushliteral(L, "invalid nan option (must be \"null\")");
        return 2;
      }
    }
    lua_getfield(L, 2, "sparsenull");
    if (!lua_isnoneornil(L, -1)) {
      conf.sparsenull = lua_toboolean(L, -1);
    }
    lua_getfield(L, 2, "literal");
    if (!lua_isnoneornil(L, -1)) {
      conf.literal = lua_toboolean(L, -1);
    }
    lua_getfield(L, 2, "pretty");
    if (!lua_isnoneornil(L, -1)) {
      conf.pretty = lua_toboolean(L, -1);
      lua_getfield(L, 2, "indent");
      if (!lua_isnoneornil(L, -1)) {
        conf.indent = luaL_checkstring(L, -1);
      }
    }
  }
  lua_settop(L, 1);
  if (Encoder(L, &p, -1, conf) == -1) {
    free(p);
    return 2;
  }
  lua_pushstring(L, p);
  free(p);
  return 1;
}

static int LuaEncodeJson(lua_State *L) {
  return LuaEncodeSmth(L, LuaEncodeJsonData);
}

// jsonarray([t]) - mark t (or a fresh table) with the shared json.array
// metatable so EncodeJson serializes it as an array even when empty
static int LuaJsonArray(lua_State *L) {
  if (lua_isnoneornil(L, 1)) {
    lua_settop(L, 0);
    lua_createtable(L, 0, 0);
  } else {
    luaL_checktype(L, 1, LUA_TTABLE);
    lua_settop(L, 1);
  }
  luaL_setmetatable(L, "json.array");
  return 1;
}

static int LuaEncodeLua(lua_State *L) {
  return LuaEncodeSmth(L, LuaEncodeLuaData);
}

// is_main() - check if calling script is the main script (not require'd)
// Returns true if the caller's source file matches arg[0]
static int LuaIsMain(lua_State *L) {
  lua_Debug ar;
  const char *src;
  const char *arg0;
  char *real_src = NULL;
  char *real_arg = NULL;
  int result = 0;

  // Get caller's source file (level 1 = caller of is_main)
  if (!lua_getstack(L, 1, &ar) || !lua_getinfo(L, "S", &ar)) {
    lua_pushboolean(L, 0);
    return 1;
  }
  src = ar.source;
  if (!src || src[0] != '@') {
    lua_pushboolean(L, 0);
    return 1;
  }
  src++;  // skip '@' prefix

  // Get arg[0]
  if (lua_getglobal(L, "arg") != LUA_TTABLE) {
    lua_pop(L, 1);
    lua_pushboolean(L, 0);
    return 1;
  }
  lua_rawgeti(L, -1, 0);
  arg0 = lua_tostring(L, -1);
  if (!arg0) {
    lua_pop(L, 2);
    lua_pushboolean(L, 0);
    return 1;
  }

  // Compare paths (try direct first, then realpath)
  if (strcmp(src, arg0) == 0) {
    result = 1;
  } else {
    real_src = realpath(src, NULL);
    real_arg = realpath(arg0, NULL);
    if (real_src && real_arg && strcmp(real_src, real_arg) == 0) {
      result = 1;
    }
    free(real_src);
    free(real_arg);
  }

  lua_pop(L, 2);  // pop arg table and arg[0]
  lua_pushboolean(L, result);
  return 1;
}

// clang-format off
static const luaL_Reg kCosmoFuncs[] = {
    {"Barf", LuaBarf},
    {"CategorizeIp", LuaCategorizeIp},
    {"Crc32", LuaCrc32},
    {"Crc32c", LuaCrc32c},
    {"DecodeBase32", LuaDecodeBase32},
    {"DecodeBase64", LuaDecodeBase64},
    {"DecodeHex", LuaDecodeHex},
    {"DecodeJson", LuaDecodeJson},
    {"DecodeLatin1", LuaDecodeLatin1},
    {"DecodeLua", LuaDecodeLua},
    {"Deflate", LuaDeflate},
    {"EncodeBase32", LuaEncodeBase32},
    {"EncodeBase64", LuaEncodeBase64},
    {"EncodeHex", LuaEncodeHex},
    {"EncodeJson", LuaEncodeJson},
    {"EncodeLatin1", LuaEncodeLatin1},
    {"EncodeLua", LuaEncodeLua},
    {"EncodeUrl", LuaEncodeUrl},
    {"EscapeFragment", LuaEscapeFragment},
    {"EscapeHost", LuaEscapeHost},
    {"EscapeHtml", LuaEscapeHtml},
    {"EscapeIp", LuaEscapeIp},
    {"EscapeLiteral", LuaEscapeLiteral},
    {"EscapeParam", LuaEscapeParam},
    {"UnescapeParam", LuaUnescapeParam},
    {"EscapePass", LuaEscapePass},
    {"EscapePath", LuaEscapePath},
    {"EscapeSegment", LuaEscapeSegment},
    {"EscapeUser", LuaEscapeUser},
    {"FormatIp", LuaFormatIp},
    {"GetHostIsa", LuaGetHostIsa},
    {"GetHostOs", LuaGetHostOs},
    {"GetHttpReason", LuaGetHttpReason},
    {"GetMonospaceWidth", LuaGetMonospaceWidth},
    {"GetRandomBytes", LuaGetRandomBytes},
    {"HasControlCodes", LuaHasControlCodes},
    {"Inflate", LuaInflate},
    {"IsAcceptableHost", LuaIsAcceptableHost},
    {"IsAcceptablePath", LuaIsAcceptablePath},
    {"IsAcceptablePort", LuaIsAcceptablePort},
    {"IsBase64", LuaIsBase64},
    {"IsLoopbackIp", LuaIsLoopbackIp},
    {"is_main", LuaIsMain},
    {"IsPrivateIp", LuaIsPrivateIp},
    {"IsPublicIp", LuaIsPublicIp},
    {"IsReasonablePath", LuaIsReasonablePath},
    {"IsValidPercentEncoding", LuaIsValidPercentEncoding},
    {"jsonarray", LuaJsonArray},
    {"ParseHost", LuaParseHost},
    {"ParseIp", LuaParseIp},
    {"ParseParams", LuaParseParams},
    {"ParseUrl", LuaParseUrl},
    {"Rand64", LuaRand64},
    {"ResolveIp", LuaResolveIp},
    {"Slurp", LuaSlurp},
    {"Strftime", LuaStrftime},
    {"UuidV4", LuaUuidV4},
    {"UuidV7", LuaUuidV7},
    {"FormatHttpDateTime", LuaFormatHttpDateTime},
    {"GetCryptoHash", LuaGetCryptoHash},
    {"Sha256", LuaSha256},
    {"Fetch", LuaFetch},
    {"FetchStream", LuaFetchStream},
    {NULL, NULL}
};
// clang-format on

/* Register submodule in package.loaded for direct require() support */
static void register_submodule(lua_State *L, const char *name) {
  /* stack: cosmo, submodule */
  lua_getfield(L, LUA_REGISTRYINDEX, LUA_LOADED_TABLE);
  lua_pushvalue(L, -2);              /* copy submodule */
  lua_setfield(L, -2, name);         /* package.loaded[name] = submodule */
  lua_pop(L, 1);                     /* pop package.loaded */
}

int luaopen_cosmo(lua_State *L) {
  /* initialize fetch SSL state */
  LuaInitFetch();
  LuaInitFetchReader(L);

  luaL_newlib(L, kCosmoFuncs);

  /* shared marker metatables for JSON round-tripping: json.array marks
     tables that encode as arrays even when empty; json.null marks the
     cosmo.null sentinel that encodes as JSON null */
  luaL_newmetatable(L, "json.array");
  lua_pop(L, 1);
  luaL_newmetatable(L, "json.null");
  lua_pop(L, 1);
  lua_createtable(L, 0, 0);
  luaL_setmetatable(L, "json.null");
  lua_setfield(L, -2, "null");

  /* register submodules for direct require("cosmo.xxx") */
  LuaUnix(L);
  register_submodule(L, "cosmo.unix");
  lua_pop(L, 1);

  LuaPath(L);
  register_submodule(L, "cosmo.path");
  lua_pop(L, 1);

  LuaRe(L);
  register_submodule(L, "cosmo.re");
  lua_pop(L, 1);

  luaopen_argon2(L);
  register_submodule(L, "cosmo.argon2");
  lua_pop(L, 1);

  luaopen_lsqlite3(L);
  register_submodule(L, "cosmo.lsqlite3");
  lua_pop(L, 1);

  LuaGetopt(L);
  register_submodule(L, "cosmo.getopt");
  lua_pop(L, 1);

  LuaZip(L);
  register_submodule(L, "cosmo.zip");
  lua_pop(L, 1);

  LuaCov(L);
  register_submodule(L, "cosmo.cov");
  lua_pop(L, 1);

  luaopen_repl(L);
  register_submodule(L, "cosmo.repl");
  lua_pop(L, 1);

  return 1;
}
