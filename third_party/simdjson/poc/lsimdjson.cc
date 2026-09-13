// POC only -- not part of the make graph or the cosmo.* binding
// surface. Demonstrates a Lua-callable wrapper around simdjson's
// DOM API: simdjson_decode(str) -> table|string|number|boolean|nil,
// or nil, err on a parse failure. Uses the non-throwing dom::element
// accessors throughout and catches anything simdjson itself can still
// throw (e.g. allocation failure) at this boundary, so nothing crosses
// into Lua as a C++ exception.
#include "simdjson.h"

extern "C" {
#include "third_party/lua/lauxlib.h"
#include "third_party/lua/lua.h"
}

#include <cassert>
#include <exception>

namespace {

// el.get(out) always succeeds here: the caller already switched on
// el.type() to pick which overload to call, so a mismatch would be a
// bug in that dispatch, not a runtime condition -- assert: impossible
// per the switch above, not a real failure the caller can hit.
template <typename T>
void Get(simdjson::dom::element el, T &out) {
  auto error = el.get(out);
  assert(!error);
  (void)error;
}

void PushElement(lua_State *L, simdjson::dom::element el);

void PushObject(lua_State *L, simdjson::dom::element el) {
  lua_newtable(L);
  simdjson::dom::object obj;
  Get(el, obj);
  for (auto field : obj) {
    lua_pushlstring(L, field.key.data(), field.key.size());
    PushElement(L, field.value);
    lua_settable(L, -3);
  }
}

void PushArray(lua_State *L, simdjson::dom::element el) {
  lua_newtable(L);
  simdjson::dom::array arr;
  Get(el, arr);
  lua_Integer i = 1;
  for (auto v : arr) {
    PushElement(L, v);
    lua_seti(L, -2, i++);
  }
}

void PushElement(lua_State *L, simdjson::dom::element el) {
  switch (el.type()) {
    case simdjson::dom::element_type::OBJECT:
      PushObject(L, el);
      return;
    case simdjson::dom::element_type::ARRAY:
      PushArray(L, el);
      return;
    case simdjson::dom::element_type::STRING: {
      std::string_view sv;
      Get(el, sv);
      lua_pushlstring(L, sv.data(), sv.size());
      return;
    }
    case simdjson::dom::element_type::INT64: {
      int64_t v;
      Get(el, v);
      lua_pushinteger(L, (lua_Integer)v);
      return;
    }
    case simdjson::dom::element_type::UINT64: {
      // POC: truncates values above INT64_MAX rather than promoting to
      // a Lua float -- a real binding would follow cosmic/json's lead.
      uint64_t v;
      Get(el, v);
      lua_pushinteger(L, (lua_Integer)v);
      return;
    }
    case simdjson::dom::element_type::DOUBLE: {
      double v;
      Get(el, v);
      lua_pushnumber(L, v);
      return;
    }
    case simdjson::dom::element_type::BOOL: {
      bool v;
      Get(el, v);
      lua_pushboolean(L, v);
      return;
    }
    case simdjson::dom::element_type::NULL_VALUE:
    default:
      // matches cosmo.DecodeJson's no-sentinel default: JSON null
      // decodes to Lua nil.
      lua_pushnil(L);
      return;
  }
}

}  // namespace

extern "C" int LuaSimdjsonDecode(lua_State *L) {
  size_t len;
  const char *s = luaL_checklstring(L, 1, &len);
  try {
    // simdjson's own docs recommend reusing a parser across calls: it
    // keeps its internal capacity buffers instead of reallocating them
    // per parse, which otherwise dominates the cost of small/medium
    // documents. thread_local rather than a Lua-registry-held instance
    // -- a real binding would probably key it off the lua_State -- but
    // safe here since this POC is single-threaded.
    thread_local simdjson::dom::parser parser;
    simdjson::dom::element doc;
    auto error = parser.parse(s, len).get(doc);
    if (error) {
      lua_pushnil(L);
      lua_pushstring(L, simdjson::error_message(error));
      return 2;
    }
    PushElement(L, doc);
    return 1;
  } catch (const std::exception &e) {
    lua_pushnil(L);
    lua_pushstring(L, e.what());
    return 2;
  }
}
