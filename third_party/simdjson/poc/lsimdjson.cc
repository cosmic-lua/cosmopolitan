// POC only -- not part of the make graph or the cosmo.* binding
// surface. Demonstrates a Lua-callable wrapper around simdjson's
// DOM API: simdjson_decode(str) -> table|string|number|boolean|nil,
// or nil, err on a parse failure. Uses the non-throwing dom::element
// accessors throughout and catches anything simdjson itself can still
// throw (e.g. allocation failure) at this boundary, so nothing crosses
// into Lua as a C++ exception.
//
// This is the chosen API for any real binding -- see ../README.md's
// "Decision" section: it's fully conformant against JSONTestSuite (0
// bugs), where the on_demand sibling (lsimdjson_ondemand.cc) is not
// (37 bugs) and was rejected on that basis.
#include "simdjson.h"

extern "C" {
#include "third_party/lua/lauxlib.h"
#include "third_party/lua/lua.h"
}

#include <cassert>
#include <exception>
#include <stdexcept>

namespace {

// PushElement recurses once per JSON nesting level, and an adversarial
// document (JSONTestSuite ships exactly this case, i_structure_500_
// nested_arrays.json) can nest deep enough to blow Lua's own internal
// stack -- not a native segfault but an unassert() abort, just as
// fatal to the process. ljson.c guards the same hazard with its own
// DEPTH cap (64) and returns a clean error instead of crashing; this
// needs the same guard, but NOT at 64 -- each level here does several
// raw Lua C API calls (lua_createtable, lua_settable/lua_seti) that
// ljson.c's leaner native recursion doesn't pay per level, so this
// wrapper's actual safe ceiling is lower. Measured empirically (one
// process per depth, since a crash takes the whole process down):
// depth 19 succeeds, depth 21 aborts. 16 leaves real margin below
// that -- rejecting some deeply-nested documents ljson.c would still
// accept, a real (if narrow) conformance gap a non-recursive rewrite
// would close; see ../README.md.
constexpr int kMaxDepth = 16;

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

void PushElement(lua_State *L, simdjson::dom::element el, int depth);

void PushObject(lua_State *L, simdjson::dom::element el, int depth) {
  simdjson::dom::object obj;
  Get(el, obj);
  // DOM's tape already knows the count, so pre-size the table instead
  // of growing/rehashing it one lua_settable at a time.
  lua_createtable(L, 0, (int)obj.size());
  for (auto field : obj) {
    lua_pushlstring(L, field.key.data(), field.key.size());
    PushElement(L, field.value, depth + 1);
    lua_settable(L, -3);
  }
}

void PushArray(lua_State *L, simdjson::dom::element el, int depth) {
  simdjson::dom::array arr;
  Get(el, arr);
  lua_createtable(L, (int)arr.size(), 0);
  lua_Integer i = 1;
  for (auto v : arr) {
    PushElement(L, v, depth + 1);
    lua_seti(L, -2, i++);
  }
}

void PushElement(lua_State *L, simdjson::dom::element el, int depth) {
  if (depth > kMaxDepth) {
    throw std::runtime_error("nesting too deep");
  }
  switch (el.type()) {
    case simdjson::dom::element_type::OBJECT:
      PushObject(L, el, depth);
      return;
    case simdjson::dom::element_type::ARRAY:
      PushArray(L, el, depth);
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
    PushElement(L, doc, 0);
    return 1;
  } catch (const std::exception &e) {
    lua_pushnil(L);
    lua_pushstring(L, e.what());
    return 2;
  }
}
