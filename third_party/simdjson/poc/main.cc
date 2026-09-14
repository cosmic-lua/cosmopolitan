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
extern "C" int LuaSimdjsonDecodeOnDemand(lua_State *L);
extern "C" int LuaDecodeJsonBench(lua_State *L);
extern "C" int LuaSimdjsonDecodeDirect(lua_State *L);
extern "C" int LuaSimdjsonPaddedRawChk(lua_State *L);
extern "C" int LuaSimdjsonPaddedSetChk(lua_State *L);
extern "C" int LuaSimdjsonPaddedRawNochk(lua_State *L);
extern "C" int LuaSimdjsonUnpaddedRawNochk(lua_State *L);
extern "C" int LuaSimdjsonParseOnly(lua_State *L);
extern "C" int LuaSimdjsonParseOnlyUnpadded(lua_State *L);
extern "C" int LuaSimdjsonDecodeFast(lua_State *L);
extern "C" int LuaSimdjsonDecodeFastMt(lua_State *L);

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: %s script.lua\n", argv[0]);
    return 1;
  }
  lua_State *L = luaL_newstate();
  luaL_openlibs(L);
  lua_pushcfunction(L, LuaSimdjsonDecode);
  lua_setglobal(L, "simdjson_decode");
  lua_pushcfunction(L, LuaSimdjsonDecodeOnDemand);
  lua_setglobal(L, "simdjson_decode_ondemand");
  lua_pushcfunction(L, LuaSimdjsonDecodeFast);
  lua_setglobal(L, "simdjson_decode_fast");
  lua_pushcfunction(L, LuaSimdjsonDecodeFastMt);
  lua_setglobal(L, "simdjson_decode_fast_mt");
  lua_pushcfunction(L, LuaSimdjsonPaddedRawChk);
  lua_setglobal(L, "sj_padded_raw_chk");
  lua_pushcfunction(L, LuaSimdjsonPaddedSetChk);
  lua_setglobal(L, "sj_padded_set_chk");
  lua_pushcfunction(L, LuaSimdjsonPaddedRawNochk);
  lua_setglobal(L, "sj_padded_raw_nochk");
  lua_pushcfunction(L, LuaSimdjsonUnpaddedRawNochk);
  lua_setglobal(L, "sj_unpadded_raw_nochk");
  lua_pushcfunction(L, LuaSimdjsonParseOnly);
  lua_setglobal(L, "sj_parse_only");
  lua_pushcfunction(L, LuaSimdjsonParseOnlyUnpadded);
  lua_setglobal(L, "sj_parse_only_unpadded");
  lua_pushcfunction(L, LuaSimdjsonDecodeDirect);
  lua_setglobal(L, "sj_direct");
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
