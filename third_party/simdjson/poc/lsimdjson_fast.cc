// Experimental variant of lsimdjson.cc used to measure hypotheses:
//   simdjson_decode_fast(str)     unpadded in-place parse (no input copy),
//                                 lua_checkstack once + depth 64 (no
//                                 per-level exception guard at 16),
//                                 lua_rawset/lua_rawseti instead of
//                                 lua_settable/lua_seti
//   simdjson_decode_fast_mt(str)  same, plus the json.array metatable on
//                                 every array (what a real binding must
//                                 do, and what ljson.c already pays for)
#include "simdjson.h"

extern "C" {
#include "third_party/lua/lauxlib.h"
#include "third_party/lua/lua.h"
}

#include <cassert>
#include <exception>
#include <stdexcept>

namespace {

constexpr int kMaxDepth = 64;  // ljson.c's DEPTH
int g_raw = 1;

template <typename T>
void Get(simdjson::dom::element el, T &out) {
  auto error = el.get(out);
  assert(!error);
  (void)error;
}

// arraymt: absolute stack index of the json.array metatable, or 0 to skip.
void PushElement(lua_State *L, simdjson::dom::element el, int depth,
                 int arraymt);

void PushObject(lua_State *L, simdjson::dom::element el, int depth,
                int arraymt) {
  simdjson::dom::object obj;
  Get(el, obj);
  lua_createtable(L, 0, (int)obj.size());
  for (auto field : obj) {
    lua_pushlstring(L, field.key.data(), field.key.size());
    PushElement(L, field.value, depth + 1, arraymt);
    if (g_raw) lua_rawset(L, -3); else lua_settable(L, -3);
  }
}

void PushArray(lua_State *L, simdjson::dom::element el, int depth,
               int arraymt) {
  simdjson::dom::array arr;
  Get(el, arr);
  lua_createtable(L, (int)arr.size(), 0);
  if (arraymt) {
    lua_pushvalue(L, arraymt);
    lua_setmetatable(L, -2);
  }
  lua_Integer i = 1;
  for (auto v : arr) {
    PushElement(L, v, depth + 1, arraymt);
    if (g_raw) lua_rawseti(L, -2, i++); else lua_seti(L, -2, i++);
  }
}

void PushElement(lua_State *L, simdjson::dom::element el, int depth,
                 int arraymt) {
  if (depth > kMaxDepth) {
    throw std::runtime_error("maximum depth exceeded");
  }
  switch (el.type()) {
    case simdjson::dom::element_type::OBJECT:
      PushObject(L, el, depth, arraymt);
      return;
    case simdjson::dom::element_type::ARRAY:
      PushArray(L, el, depth, arraymt);
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
      lua_pushnil(L);
      return;
  }
}

// flag bits for Decode
enum { kUnpadded = 1, kRaw = 2, kMt = 4, kChk = 8, kParseOnly = 16 };

int Decode(lua_State *L, int flags) {
  size_t len;
  const char *s = luaL_checklstring(L, 1, &len);
  bool with_mt = flags & kMt;
  g_raw = (flags & kRaw) ? 1 : 0;
  // one C function only has LUA_MINSTACK (20) slots guaranteed; each
  // nesting level parks up to two values (table, key), so reserve the
  // whole depth up front exactly like ljson.c does.
  if ((flags & kChk) && !lua_checkstack(L, kMaxDepth * 2 + LUA_MINSTACK)) {
    lua_pushnil(L);
    lua_pushstring(L, "can't set stack depth");
    return 2;
  }
  int arraymt = 0;
  if (with_mt) {
    luaL_newmetatable(L, "json.array");
    arraymt = lua_gettop(L);
  }
  try {
    thread_local simdjson::dom::parser parser;
    simdjson::dom::element doc;
    auto error = (flags & kUnpadded) ? parser.parse_unpadded(s, len).get(doc)
                                     : parser.parse(s, len).get(doc);
    if (error) {
      lua_pushnil(L);
      lua_pushstring(L, simdjson::error_message(error));
      return 2;
    }
    if (flags & kParseOnly) {
      lua_pushboolean(L, 1);
      return 1;
    }
    PushElement(L, doc, 0, arraymt);
    if (arraymt) lua_remove(L, arraymt);
    return 1;
  } catch (const std::exception &e) {
    lua_settop(L, 1);
    lua_pushnil(L);
    lua_pushstring(L, e.what());
    return 2;
  }
}

}  // namespace

#define V(name, flags) \
  extern "C" int name(lua_State *L) { return Decode(L, flags); }
V(LuaSimdjsonDecodeFast, kUnpadded | kRaw | kChk)
V(LuaSimdjsonDecodeFastMt, kUnpadded | kRaw | kChk | kMt)
V(LuaSimdjsonPaddedRawChk, kRaw | kChk)
V(LuaSimdjsonPaddedSetChk, kChk)
V(LuaSimdjsonPaddedRawNochk, kRaw)
V(LuaSimdjsonUnpaddedRawNochk, kUnpadded | kRaw)
V(LuaSimdjsonParseOnly, kParseOnly)
V(LuaSimdjsonParseOnlyUnpadded, kParseOnly | kUnpadded)
