#ifndef COSMOPOLITAN_TOOL_NET_LCRYPTO_H_
#define COSMOPOLITAN_TOOL_NET_LCRYPTO_H_
#include "third_party/lua/lua.h"
COSMOPOLITAN_C_START_

int LuaAeadEncrypt(lua_State *);
int LuaAeadDecrypt(lua_State *);
int LuaHkdf(lua_State *);

COSMOPOLITAN_C_END_
#endif /* COSMOPOLITAN_TOOL_NET_LCRYPTO_H_ */
