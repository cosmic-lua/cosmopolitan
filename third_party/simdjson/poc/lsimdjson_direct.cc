// Experiment: materialize the DOM into Lua tables through Lua's internal
// table API (luaH_set/luaH_setint, luaS_newlstr) instead of the public
// push/settable C API, to measure how much of the "Lua side" cost is API
// overhead versus real table/string work. Tables stay rooted on the Lua
// stack while they fill; scalars and strings are built in a local TValue
// and stored straight into the parent. NOT GC-safe under an emergency
// collection between luaS_newlstr and the store -- measurement only.
#include "simdjson.h"

extern "C" {
#include "third_party/lua/lauxlib.h"
#include "third_party/lua/lgc.h"
#include "third_party/lua/lobject.h"
#include "third_party/lua/lstate.h"
#include "third_party/lua/lstring.h"
#include "third_party/lua/ltable.h"
#include "third_party/lua/lua.h"
}

#include <cassert>
#include <exception>
#include <stdexcept>

namespace {

constexpr int kMaxDepth = 64;

template <typename T>
void Get(simdjson::dom::element el, T &out) {
  auto error = el.get(out);
  assert(!error);
  (void)error;
}

void Build(lua_State *L, TValue *out, simdjson::dom::element el, int depth) {
  if (depth > kMaxDepth) throw std::runtime_error("maximum depth exceeded");
  switch (el.type()) {
    case simdjson::dom::element_type::OBJECT: {
      simdjson::dom::object obj;
      Get(el, obj);
      lua_createtable(L, 0, (int)obj.size());
      Table *t = hvalue(s2v(L->top.p - 1));
      for (auto field : obj) {
        TValue v;
        Build(L, &v, field.value, depth + 1);
        TString *k = luaS_newlstr(L, field.key.data(), field.key.size());
        TValue kv;
        setsvalue(L, &kv, k);
        luaH_set(L, t, &kv, &v);
        luaC_barrierback(L, obj2gco(t), &v);
      }
      sethvalue(L, out, t);
      L->top.p--;
      return;
    }
    case simdjson::dom::element_type::ARRAY: {
      simdjson::dom::array arr;
      Get(el, arr);
      lua_createtable(L, (int)arr.size(), 0);
      Table *t = hvalue(s2v(L->top.p - 1));
      lua_Integer i = 1;
      for (auto e : arr) {
        TValue v;
        Build(L, &v, e, depth + 1);
        luaH_setint(L, t, i++, &v);
        luaC_barrierback(L, obj2gco(t), &v);
      }
      sethvalue(L, out, t);
      L->top.p--;
      return;
    }
    case simdjson::dom::element_type::STRING: {
      std::string_view sv;
      Get(el, sv);
      TString *s = luaS_newlstr(L, sv.data(), sv.size());
      setsvalue(L, out, s);
      return;
    }
    case simdjson::dom::element_type::INT64: {
      int64_t v;
      Get(el, v);
      setivalue(out, (lua_Integer)v);
      return;
    }
    case simdjson::dom::element_type::UINT64: {
      uint64_t v;
      Get(el, v);
      setivalue(out, (lua_Integer)v);
      return;
    }
    case simdjson::dom::element_type::DOUBLE: {
      double v;
      Get(el, v);
      setfltvalue(out, v);
      return;
    }
    case simdjson::dom::element_type::BOOL: {
      bool v;
      Get(el, v);
      if (v) setbtvalue(out); else setbfvalue(out);
      return;
    }
    case simdjson::dom::element_type::NULL_VALUE:
    default:
      setnilvalue(out);
      return;
  }
}

}  // namespace

extern "C" int LuaSimdjsonDecodeDirect(lua_State *L) {
  size_t len;
  const char *s = luaL_checklstring(L, 1, &len);
  if (!lua_checkstack(L, kMaxDepth + LUA_MINSTACK)) {
    lua_pushnil(L);
    lua_pushstring(L, "can't set stack depth");
    return 2;
  }
  try {
    thread_local simdjson::dom::parser parser;
    simdjson::dom::element doc;
    auto error = parser.parse(s, len).get(doc);
    if (error) {
      lua_pushnil(L);
      lua_pushstring(L, simdjson::error_message(error));
      return 2;
    }
    TValue root;
    Build(L, &root, doc, 0);
    setobj2s(L, L->top.p, &root);
    L->top.p++;
    return 1;
  } catch (const std::exception &e) {
    lua_settop(L, 1);
    lua_pushnil(L);
    lua_pushstring(L, e.what());
    return 2;
  }
}
