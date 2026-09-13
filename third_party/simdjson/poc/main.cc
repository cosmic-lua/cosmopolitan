// POC only -- minimal embedding of the real, unmodified
// third_party/lua/*.c core plus lsimdjson.cc, to prove a Lua script
// can call into simdjson end to end under cosmocc. Not the real
// tool/lua/lua entry point and not wired into the make graph.
extern "C" {
#include "third_party/lua/lauxlib.h"
#include "third_party/lua/lua.h"
#include "third_party/lua/lualib.h"
}

#include <cstdio>

extern "C" int LuaSimdjsonDecode(lua_State *L);
extern "C" int LuaDecodeJsonBench(lua_State *L);

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: %s script.lua\n", argv[0]);
    return 1;
  }
  lua_State *L = luaL_newstate();
  luaL_openlibs(L);
  lua_pushcfunction(L, LuaSimdjsonDecode);
  lua_setglobal(L, "simdjson_decode");
  lua_pushcfunction(L, LuaDecodeJsonBench);
  lua_setglobal(L, "cosmo_decode_json");
  if (luaL_dofile(L, argv[1]) != LUA_OK) {
    fprintf(stderr, "error: %s\n", lua_tostring(L, -1));
    lua_close(L);
    return 1;
  }
  lua_close(L);
  return 0;
}
