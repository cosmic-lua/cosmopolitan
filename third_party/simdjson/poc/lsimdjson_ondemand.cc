// POC only -- an on_demand-API sibling to lsimdjson.cc's DOM-based
// simdjson_decode(), registered as simdjson_decode_ondemand(), to test
// whether on_demand's forward-only iteration (which needs no separate
// "build the tape, then walk it" second pass) closes the gap DOM shows
// against ljson.c on object/string-heavy payloads in bench.lua. See
// ../README.md's Performance section for the numbers.
#include "simdjson.h"

extern "C" {
#include "third_party/lua/lauxlib.h"
#include "third_party/lua/lua.h"
}

#include <cassert>
#include <exception>
#include <utility>

namespace {

// val.type()/get_*() mismatches are impossible here: the switch below
// picks the getter to match val.type()'s own answer -- assert:
// impossible per that dispatch, not a real failure the caller can hit.
template <typename T>
void PushValue(lua_State *L, T val) {
  simdjson::ondemand::json_type type;
  auto terr = val.type().get(type);
  assert(!terr);
  (void)terr;
  switch (type) {
    case simdjson::ondemand::json_type::object: {
      simdjson::ondemand::object obj;
      auto error = val.get_object().get(obj);
      assert(!error);
      (void)error;
      // count_fields() is a documented last-resort: it scans ahead and
      // rewinds, i.e. buys pre-sizing by paying for a second pass --
      // exactly the cost on_demand exists to avoid. Measuring it
      // anyway to see whether pre-sizing still wins on net.
      size_t nfields = 0;
      auto cerr = obj.count_fields().get(nfields);
      assert(!cerr);
      (void)cerr;
      lua_createtable(L, 0, (int)nfields);
      for (auto field_result : obj) {
        simdjson::ondemand::field field;
        auto ferr = std::move(field_result).get(field);
        assert(!ferr);
        (void)ferr;
        std::string_view key;
        auto kerr = field.unescaped_key().get(key);
        assert(!kerr);
        (void)kerr;
        lua_pushlstring(L, key.data(), key.size());
        PushValue(L, field.value());
        lua_settable(L, -3);
      }
      return;
    }
    case simdjson::ondemand::json_type::array: {
      simdjson::ondemand::array arr;
      auto error = val.get_array().get(arr);
      assert(!error);
      (void)error;
      size_t nelems = 0;
      auto cerr = arr.count_elements().get(nelems);
      assert(!cerr);
      (void)cerr;
      lua_createtable(L, (int)nelems, 0);
      lua_Integer i = 1;
      for (auto v_result : arr) {
        simdjson::ondemand::value v;
        auto verr = std::move(v_result).get(v);
        assert(!verr);
        (void)verr;
        PushValue(L, v);
        lua_seti(L, -2, i++);
      }
      return;
    }
    case simdjson::ondemand::json_type::string: {
      std::string_view sv;
      auto error = val.get_string().get(sv);
      assert(!error);
      (void)error;
      lua_pushlstring(L, sv.data(), sv.size());
      return;
    }
    case simdjson::ondemand::json_type::number: {
      // POC: always widens to double, unlike the DOM wrapper's
      // int64/uint64 distinction -- fine for a perf comparison, not
      // for a real binding (large integers would lose precision).
      double d;
      auto error = val.get_double().get(d);
      assert(!error);
      (void)error;
      lua_pushnumber(L, d);
      return;
    }
    case simdjson::ondemand::json_type::boolean: {
      bool b;
      auto error = val.get_bool().get(b);
      assert(!error);
      (void)error;
      lua_pushboolean(L, b);
      return;
    }
    case simdjson::ondemand::json_type::null:
    default:
      lua_pushnil(L);
      return;
  }
}

}  // namespace

extern "C" int LuaSimdjsonDecodeOnDemand(lua_State *L) {
  size_t len;
  const char *s = luaL_checklstring(L, 1, &len);
  try {
    // thread_local for the same reason as lsimdjson.cc's DOM parser:
    // reused capacity buffers instead of a per-call reallocation.
    thread_local simdjson::ondemand::parser parser;
    // padded_string copies the input -- matches the DOM wrapper's own
    // internal copy in parser.parse(), so the two stay comparable.
    simdjson::padded_string padded(s, len);
    simdjson::ondemand::document doc;
    auto error = parser.iterate(padded).get(doc);
    if (error) {
      lua_pushnil(L);
      lua_pushstring(L, simdjson::error_message(error));
      return 2;
    }
    PushValue(L, doc.get_value().value());
    return 1;
  } catch (const std::exception &e) {
    lua_pushnil(L);
    lua_pushstring(L, e.what());
    return 2;
  }
}
