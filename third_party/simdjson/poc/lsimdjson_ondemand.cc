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

#include <exception>
#include <stdexcept>
#include <utility>

namespace {

// See lsimdjson.cc's kMaxDepth for the full story: same crash, same
// fix, measured separately here since this wrapper's own per-level
// API calls (count_fields()/count_elements() included) differ from
// the DOM wrapper's. Empirically: depth 18 succeeds, depth 20 aborts.
constexpr int kMaxDepth = 16;

// Unlike lsimdjson.cc's DOM wrapper -- where a get(out) mismatch after
// switching on element_type() really is impossible, since DOM fully
// validates and materializes the tape during parser.parse() -- on_demand
// is lazy: type() only peeks the leading byte(s), so it can correctly
// say "string" or "number" for input whose actual unescaping/validation
// (which only happens inside get_string()/get_double()/etc.) then fails
// on malformed content. JSONTestSuite's adversarial corpus hits this
// directly (a bad UTF-8 escape typed as a string). An earlier version of
// this file asserted these can't fail; they can, so every result here is
// checked and converted into the wrapper's normal (nil, err) return via
// the same exception the depth guard already uses, rather than aborting.
template <typename T>
T Unwrap(simdjson::simdjson_result<T> &&result) {
  T out;
  auto error = std::move(result).get(out);
  if (error) {
    throw std::runtime_error(simdjson::error_message(error));
  }
  return out;
}

template <typename T>
void PushValue(lua_State *L, T &&val, int depth) {
  if (depth > kMaxDepth) {
    throw std::runtime_error("nesting too deep");
  }
  switch (Unwrap(val.type())) {
    case simdjson::ondemand::json_type::object: {
      auto obj = Unwrap(val.get_object());
      // count_fields() is a documented last-resort: it scans ahead and
      // rewinds, i.e. buys pre-sizing by paying for a second pass --
      // exactly the cost on_demand exists to avoid. Measuring it
      // anyway to see whether pre-sizing still wins on net.
      lua_createtable(L, 0, (int)Unwrap(obj.count_fields()));
      for (auto field_result : obj) {
        auto field = Unwrap(std::move(field_result));
        auto key = Unwrap(field.unescaped_key());
        lua_pushlstring(L, key.data(), key.size());
        PushValue(L, field.value(), depth + 1);
        lua_settable(L, -3);
      }
      return;
    }
    case simdjson::ondemand::json_type::array: {
      auto arr = Unwrap(val.get_array());
      lua_createtable(L, (int)Unwrap(arr.count_elements()), 0);
      lua_Integer i = 1;
      for (auto v_result : arr) {
        PushValue(L, Unwrap(std::move(v_result)), depth + 1);
        lua_seti(L, -2, i++);
      }
      return;
    }
    case simdjson::ondemand::json_type::string: {
      auto sv = Unwrap(val.get_string());
      lua_pushlstring(L, sv.data(), sv.size());
      return;
    }
    case simdjson::ondemand::json_type::number: {
      // POC: always widens to double, unlike the DOM wrapper's
      // int64/uint64 distinction -- fine for a perf comparison, not
      // for a real binding (large integers would lose precision).
      lua_pushnumber(L, Unwrap(val.get_double()));
      return;
    }
    case simdjson::ondemand::json_type::boolean:
      lua_pushboolean(L, Unwrap(val.get_bool()));
      return;
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
    auto doc = Unwrap(parser.iterate(padded));
    // document's own get_object()/get_array() (reached through
    // get_value()) is the supported path for a container at the root;
    // calling document::type() and then document::get_object() directly
    // -- skipping get_value() -- conflicts with the root iterator's own
    // bookkeeping and errors out, so that shortcut (an earlier version
    // of this wrapper tried it) only gets used for the scalar-at-root
    // case get_value() itself can't handle (JSONTestSuite caught this
    // too: a bare top-level `null`/`42`/etc., which ljson.c accepts).
    switch (Unwrap(doc.type())) {
      case simdjson::ondemand::json_type::object:
      case simdjson::ondemand::json_type::array:
        PushValue(L, Unwrap(doc.get_value()), 0);
        break;
      case simdjson::ondemand::json_type::string: {
        auto sv = Unwrap(doc.get_string());
        lua_pushlstring(L, sv.data(), sv.size());
        break;
      }
      case simdjson::ondemand::json_type::number:
        lua_pushnumber(L, Unwrap(doc.get_double()));
        break;
      case simdjson::ondemand::json_type::boolean:
        lua_pushboolean(L, Unwrap(doc.get_bool()));
        break;
      case simdjson::ondemand::json_type::null:
      default:
        lua_pushnil(L);
        break;
    }
    return 1;
  } catch (const std::exception &e) {
    lua_pushnil(L);
    lua_pushstring(L, e.what());
    return 2;
  }
}
