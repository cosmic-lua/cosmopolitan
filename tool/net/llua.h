#ifndef COSMOPOLITAN_TOOL_NET_LLUA_H_
#define COSMOPOLITAN_TOOL_NET_LLUA_H_
#include "third_party/lua/lauxlib.h"
COSMOPOLITAN_C_START_

#define LLUA_ERRMAX 256

struct DecodeLua {
  int rc;
  const char *p;
};

struct DecodeLua DecodeLua(struct lua_State *, const char *, size_t, char *,
                           size_t);

COSMOPOLITAN_C_END_
#endif /* COSMOPOLITAN_TOOL_NET_LLUA_H_ */
