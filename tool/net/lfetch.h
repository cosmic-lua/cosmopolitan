#ifndef COSMOPOLITAN_TOOL_NET_LFETCH_H_
#define COSMOPOLITAN_TOOL_NET_LFETCH_H_
#include "third_party/lua/lauxlib.h"
COSMOPOLITAN_C_START_

int LuaFetch(lua_State *);
int LuaFetchStream(lua_State *);
void LuaInitFetch(void);
void LuaInitFetchReader(lua_State *);

COSMOPOLITAN_C_END_
#endif /* COSMOPOLITAN_TOOL_NET_LFETCH_H_ */
