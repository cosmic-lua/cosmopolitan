// POC only -- registers this tree's real, unmodified
// tool/net/ljson.c DecodeJson as a Lua-callable function, so bench.lua
// can time it in the same process against simdjson_decode() on
// identical payloads. Mirrors tool/lua/lcosmo.c's LuaDecodeJson minus
// opts.nullval support: the default (JSON null -> Lua nil) matches
// simdjson_decode()'s default too, so the comparison stays apples to
// apples.
extern "C" {
#include "third_party/lua/lauxlib.h"
#include "third_party/lua/lua.h"
#include "tool/net/ljson.h"
}

extern "C" int LuaDecodeJsonBench(lua_State *L) {
  size_t n;
  const char *p = luaL_checklstring(L, 1, &n);
  struct DecodeJson r = DecodeJson(L, p, n);
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
  r = DecodeJson(L, r.p, n - (r.p - p));
  if (r.rc) {
    lua_pushnil(L);
    lua_pushstring(L, "junk after expression");
    return 2;
  }
  return 1;
}
