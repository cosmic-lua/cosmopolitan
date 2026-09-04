/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2022 Justine Alexandra Roberts Tunney                              │
│                                                                              │
│ Permission to use, copy, modify, and/or distribute this software for         │
│ any purpose with or without fee is hereby granted, provided that the         │
│ above copyright notice and this permission notice appear in all copies.      │
│                                                                              │
│ THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL                │
│ WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED                │
│ WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE             │
│ AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL         │
│ DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR        │
│ PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER               │
│ TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR             │
│ PERFORMANCE OF THIS SOFTWARE.                                                │
╚─────────────────────────────────────────────────────────────────────────────*/
#include "libc/assert.h"
#include "libc/fmt/itoa.h"
#include "libc/serialize.h"
#include "libc/intrin/likely.h"
#include "libc/log/log.h"
#include "libc/log/rop.internal.h"
#include "libc/math.h"
#include "libc/mem/alg.h"
#include "libc/mem/gc.h"
#include "libc/mem/mem.h"
#include "libc/runtime/runtime.h"
#include "libc/runtime/stack.h"
#include "libc/stdio/append.h"
#include "libc/str/str.h"
#include "libc/sysv/consts/auxv.h"
#include "net/http/escape.h"
#include "third_party/double-conversion/wrapper.h"
#include "third_party/lua/cosmo/cosmo.h"
#include "third_party/lua/lauxlib.h"
#include "third_party/lua/ltable.h"
#include "third_party/lua/lua.h"
#include "third_party/lua/cosmo/cosmo.h"
#include "third_party/lua/cosmo/visitor.h"

static int Serialize(lua_State *, char **, int, struct Serializer *, int);

static int SerializeNull(lua_State *L, char **buf) {
  RETURN_ON_ERROR(appendw(buf, READ32LE("null")));
  return 0;
OnError:
  return -1;
}

static int SerializeBoolean(lua_State *L, char **buf, int idx) {
  RETURN_ON_ERROR(appendw(
      buf, lua_toboolean(L, idx) ? READ32LE("true") : READ64LE("false\0\0")));
  return 0;
OnError:
  return -1;
}

static int SerializeNumber(lua_State *L, char **buf, int idx,
                           struct Serializer *z) {
  double x;
  char *s;
  char ibuf[128];
  if (lua_isinteger(L, idx)) {
    RETURN_ON_ERROR(appendd(
        buf, ibuf, FormatInt64(ibuf, luaL_checkinteger(L, idx)) - ibuf));
  } else {
    x = lua_tonumber(L, idx);
    if (UNLIKELY(!isfinite(x))) {
      if (!z->conf.nannull) {
        z->reason = isnan(x) ? "cannot encode NaN" : "cannot encode Infinity";
        goto OnError;
      }
      RETURN_ON_ERROR(appendw(buf, READ32LE("null")));
    } else {
      // a float always encodes carrying a `.` or an exponent. the
      // shortest spelling of an integral double below 1e21 is a bare
      // digit string, which the decoder reads back as an integer --
      // losing the number's type, and above ~1e17 its value too.
      s = DoubleToJson(ibuf, x);
      RETURN_ON_ERROR(appends(buf, s));
      if (!strpbrk(s, ".eE")) {
        RETURN_ON_ERROR(appends(buf, ".0"));
      }
    }
  }
  return 0;
OnError:
  return -1;
}

static int SerializeString(lua_State *L, char **buf, int idx,
                           struct Serializer *z) {
  size_t m;
  const char *s;
  s = lua_tolstring(L, idx, &m);
  if (JsStringLiteralSpan(s, m) == m) {
    // the escaper would pass every byte through verbatim (the common
    // case for keys and clean values), so append the string directly
    // instead of paying the escape pass into z->strbuf plus a second
    // copy out of it. output bytes are identical by construction.
    RETURN_ON_ERROR(appendw(buf, '"'));
    RETURN_ON_ERROR(appendd(buf, s, m));
    RETURN_ON_ERROR(appendw(buf, '"'));
    return 0;
  }
  if (!(s = EscapeJsStringLiteral(&z->strbuf, &z->strbuflen, s, m, &m))) {
    goto OnError;
  }
  RETURN_ON_ERROR(appendw(buf, '"'));
  RETURN_ON_ERROR(appendd(buf, s, m));
  RETURN_ON_ERROR(appendw(buf, '"'));
  return 0;
OnError:
  return -1;
}

static int SerializeArray(lua_State *L, char **buf, struct Serializer *z,
                          int depth, size_t tbllen) {
  size_t i;
  RETURN_ON_ERROR(appendw(buf, '['));
  for (i = 1; i <= tbllen; i++) {
    lua_rawgeti(L, -1, i);  // +2
    if (i > 1) RETURN_ON_ERROR(appendw(buf, ','));
    RETURN_ON_ERROR(Serialize(L, buf, -1, z, depth + 1));
    lua_pop(L, 1);
  }
  RETURN_ON_ERROR(appendw(buf, ']'));
  return 0;
OnError:
  return -1;
}

static int SerializeObject(lua_State *L, char **buf, struct Serializer *z,
                           int depth, bool multi) {
  bool comma = false;
  RETURN_ON_ERROR(SerializeObjectStart(buf, z, depth, multi));
  lua_pushnil(L);            // +2
  while (lua_next(L, -2)) {  // +3
    if (lua_type(L, -2) == LUA_TSTRING) {
      if (comma) {
        RETURN_ON_ERROR(appendw(buf, ','));
        if (multi) {
          RETURN_ON_ERROR(SerializeObjectIndent(buf, z, depth + 1));
        }
      } else {
        comma = true;
      }
      RETURN_ON_ERROR(SerializeString(L, buf, -2, z));
      RETURN_ON_ERROR(appendw(buf, z->conf.pretty ? READ16LE(": ") : ':'));
      RETURN_ON_ERROR(Serialize(L, buf, -1, z, depth + 1));
      lua_pop(L, 1);
    } else {
      z->reason = "json objects must only use string keys";
      goto OnError;
    }
  }
  RETURN_ON_ERROR(SerializeObjectEnd(buf, z, depth, multi));
  return 0;
OnError:
  return -1;
}

struct JsonEntry {
  size_t off;  // into the entry buffer
  size_t len;  // excluding any terminator; entries contain no NULs
};

static int CompareJsonEntries(const void *p1, const void *p2, void *arg) {
  // Escaped entry bytes never contain NUL (a NUL in a key or value is
  // emitted as the six characters of its \u escape), so unsigned memcmp
  // with a shorter-prefix-first tiebreak orders exactly like the
  // bytewise strcmp this replaces.
  const struct JsonEntry *a = p1;
  const struct JsonEntry *b = p2;
  const char *base = arg;
  size_t n = a->len < b->len ? a->len : b->len;
  int r = memcmp(base + a->off, base + b->off, n);
  if (r)
    return r;
  return (a->len > b->len) - (a->len < b->len);
}

static int SerializeSorted(lua_State *L, char **buf, struct Serializer *z,
                           int depth, bool multi) {
  // Serialize each `"key":value` entry into one contiguous buffer and
  // record its offset and length as it is written, then sort the
  // records. This produces byte-for-byte the same output as sorting
  // NUL-terminated entry pointers, without the two extra full passes
  // over the entry bytes that terminators cost (the strlen walk that
  // rebuilt pointers, and appends()'s strlen at emission).
  int i, n = 0;
  size_t cap = 0;
  char *ent = 0;
  struct JsonEntry *ents = 0;
  void *grown;
  lua_pushnil(L);
  while (lua_next(L, -2)) {
    if (lua_type(L, -2) == LUA_TSTRING) {
      if ((size_t)n == cap) {
        cap = cap ? cap * 2 : 8;
        if (!(grown = realloc(ents, cap * sizeof(*ents)))) {
          z->reason = "out of memory";
          goto OnError;
        }
        ents = grown;
      }
      ents[n].off = appendz(ent).i;
      RETURN_ON_ERROR(SerializeString(L, &ent, -2, z));
      RETURN_ON_ERROR(appendw(&ent, z->conf.pretty ? READ16LE(": ") : ':'));
      RETURN_ON_ERROR(Serialize(L, &ent, -1, z, depth + 1));
      ents[n].len = appendz(ent).i - ents[n].off;
      ++n;
      lua_pop(L, 1);
    } else {
      z->reason = "json objects must only use string keys";
      goto OnError;
    }
  }
  if (n) {
    qsort_r(ents, n, sizeof(*ents), CompareJsonEntries, ent);
  }
  RETURN_ON_ERROR(SerializeObjectStart(buf, z, depth, multi));
  for (i = 0; i < n; ++i) {
    if (i) {
      RETURN_ON_ERROR(appendw(buf, ','));
      if (multi) {
        RETURN_ON_ERROR(SerializeObjectIndent(buf, z, depth + 1));
      }
    }
    RETURN_ON_ERROR(appendd(buf, ent + ents[i].off, ents[i].len));
  }
  RETURN_ON_ERROR(SerializeObjectEnd(buf, z, depth, multi));
  free(ents);
  free(ent);
  return 0;
OnError:
  free(ents);
  free(ent);
  return -1;
}

// The true extent of an array-shaped table: the largest positive
// integer key present, found by looking at every key. lua_rawlen only
// returns *a* border, so a sparse table like {1,[3]=2} can report
// length 1 and silently truncate — the count is what makes holes a
// detectable condition instead of border-dependent data loss. The
// table's parts are read directly rather than through a lua_next walk
// (an API call plus key/value stack traffic per key): integer keys in
// [1, realasize] live only in the array part, every other key is a
// hash node, so the two scans see exactly the keys lua_next yields.
// Returns -1 (sparse, conf.sparsenull unset) or 0 with *out_len set.
static int MeasureArray(lua_State *L, struct Serializer *z,
                        lua_Unsigned *out_len) {
  lua_Integer k;
  lua_Unsigned max = 0, cnt = 0;
  unsigned int i, asize;
  // for a table, lua_topointer returns its GC object, the Table itself
  const Table *t = lua_topointer(L, -1);
  asize = t->asize;
  for (i = 0; i < asize; i++) {
    if (!tagisempty(*getArrTag(t, i))) {
      ++cnt;
      max = i + 1;
    }
  }
  if (!isdummy(t)) {
    for (i = 0; i < sizenode(t); i++) {
      const Node *nd = gnode(t, i);
      if (!isempty(gval(nd)) && keyisinteger(nd) &&
          (k = keyival(nd)) >= 1) {
        ++cnt;
        if ((lua_Unsigned)k > max) max = k;
      }
    }
  }
  if (cnt < max && !z->conf.sparsenull) {
    z->reason = "sparse array (pass sparsenull=true to encode holes as null)";
    return -1;
  }
  // sparsenull emits one null per hole up to the largest index, so a
  // single stray huge key ({[1]=1,[2^40]=2}) would make the encode
  // effectively unbounded. Holes may not outnumber elements 8:1 (small
  // arrays are exempt: below 64 the worst case is 63 nulls). Ratio, not
  // an absolute cap, so a dense-ish array of any size still encodes
  // while hostile or corrupt indices fail loudly.
  if (max > 64 && max / 8 > cnt) {
    z->reason = "array too sparse to encode holes as null "
                "(largest index exceeds 8x the element count)";
    return -1;
  }
  *out_len = max;
  return 0;
}

static int SerializeTable(lua_State *L, char **buf, int idx,
                          struct Serializer *z, int depth) {
  int rc;
  bool multi;
  bool isarray;
  lua_Unsigned n;
  if (UNLIKELY(GetStackPointer() < z->bsp)) {
    z->reason = "out of stack";
    return -1;
  }
  RETURN_ON_ERROR(rc = LuaPushVisit(&z->visited, lua_topointer(L, idx)));
  if (!rc) {
    lua_pushvalue(L, idx);  // +1
    isarray = false;
    if ((n = lua_rawlen(L, -1)) > 0) {
      isarray = true;
    } else if (z->arraymt && lua_getmetatable(L, -1)) {
      // the json parser marks arrays with the shared json.array
      // metatable so an empty `[]` won't round-trip as `{}`
      isarray = lua_rawequal(L, -1, z->arraymt);
      lua_pop(L, 1);
    }
    if (isarray) {
      RETURN_ON_ERROR(MeasureArray(L, z, &n));
      RETURN_ON_ERROR(SerializeArray(L, buf, z, depth, n));
    } else {
      multi = z->conf.pretty && LuaHasMultipleItems(L);
      if (z->conf.sorted) {
        RETURN_ON_ERROR(SerializeSorted(L, buf, z, depth, multi));
      } else {
        RETURN_ON_ERROR(SerializeObject(L, buf, z, depth, multi));
      }
    }
    LuaPopVisit(&z->visited);
    lua_pop(L, 1);  // table ref
    return 0;
  } else {
    z->reason = "won't serialize cyclic lua table";
    goto OnError;
  }
OnError:
  return -1;
}

static int Serialize(lua_State *L, char **buf, int idx, struct Serializer *z,
                     int depth) {
  if (depth < z->conf.maxdepth) {
    switch (lua_type(L, idx)) {
      case LUA_TNIL:
        return SerializeNull(L, buf);
      case LUA_TBOOLEAN:
        return SerializeBoolean(L, buf, idx);
      case LUA_TSTRING:
        return SerializeString(L, buf, idx, z);
      case LUA_TNUMBER:
        return SerializeNumber(L, buf, idx, z);
      case LUA_TTABLE:
        if (z->nullmt && lua_getmetatable(L, idx)) {
          // a table marked with the json.null sentinel metatable
          // encodes as null, for lossless `{"a":null}` round-trips
          int isnull = lua_rawequal(L, -1, z->nullmt);
          lua_pop(L, 1);
          if (isnull) {
            return SerializeNull(L, buf);
          }
        }
        return SerializeTable(L, buf, idx, z, depth);
      default:
        z->reason = "unsupported lua type";
        return -1;
    }
  } else {
    z->reason = "table has great depth";
    return -1;
  }
}

/**
 * Encodes Lua data structure as JSON.
 *
 * On success, the serialized value is returned in `buf` and the Lua
 * stack should be in the same state when this function was called. On
 * error, values *will* be returned on the Lua stack:
 *
 * - possible junk...
 * - nil (index -2)
 * - error string (index -1)
 *
 * The following error return conditions are implemented:
 *
 * - Value found that isn't nil/bool/number/string/table
 * - Object existed with non-string key
 * - Tables had too much depth
 * - Tables are cyclic
 * - Out of C memory
 *
 * Your `*buf` must initialized to null. If it's allocated, then it must
 * have been allocated by cosmo's append*() library. After this function
 * is called, `*buf` will need to be free()'d.
 *
 * @param L is Lua interpreter state
 * @param buf receives encoded output string
 * @param idx is index of item on Lua stack
 * @return 0 on success, or -1 on error
 */
int LuaEncodeJsonData(lua_State *L, char **buf, int idx,
                      struct EncoderConfig conf) {
  int rc;
  struct Serializer z = {
    .reason = "out of memory",
    .bsp = GetStackBottom() + 4096,
    .conf = conf,
  };
  if (lua_checkstack(L, conf.maxdepth * 3 + LUA_MINSTACK)) {
    // pin the json marker metatables (if they exist) to fixed stack
    // slots so table serialization can identity-compare against them
    // without a registry lookup per table
    idx = lua_absindex(L, idx);
    luaL_getmetatable(L, "json.array");
    z.arraymt = lua_isnil(L, -1) ? 0 : lua_gettop(L);
    luaL_getmetatable(L, "json.null");
    z.nullmt = lua_isnil(L, -1) ? 0 : lua_gettop(L);
    rc = Serialize(L, buf, idx, &z, 0);
    free(z.visited.p);
    free(z.strbuf);
    if (rc == -1) {
      lua_pushnil(L);
      lua_pushstring(L, z.reason);
    } else {
      lua_pop(L, 2);  // the pinned metatable slots
    }
    return rc;
  } else {
    luaL_error(L, "can't set stack depth");
    __builtin_unreachable();
  }
}
