/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2026 Will Maier                                                    │
│                                                                              │
│ Permission to use, copy, modify, and/or distribute this software for        │
│ any purpose with or without fee is hereby granted, provided that the        │
│ above copyright notice and this permission notice appear in all copies.     │
│                                                                              │
│ THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL               │
│ WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED               │
│ WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE            │
│ AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL        │
│ DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR       │
│ PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER              │
│ TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR            │
│ PERFORMANCE OF THIS SOFTWARE.                                               │
╚─────────────────────────────────────────────────────────────────────────────*/
#include "tool/net/lcov.h"
#include "third_party/lua/lauxlib.h"
#include "third_party/lua/lua.h"
#include <stdlib.h>
#include <string.h>

// cosmo.cov: a line-hit coverage collector.
//
// A LUA_MASKLINE hook implemented in C, counting executed
// (chunk source, line) pairs. Downstream coverage tooling (cosmic's
// cosmic.coverage module) otherwise pays a Lua-function hook plus a
// debug.getinfo table allocation on every executed line of every
// loaded chunk, a ~2x wall-clock multiplier on an instrumented test
// suite; this hook does the same accounting for tens of nanoseconds
// per line. Attribution is identical to the Lua hook it replaces:
// chunks are keyed by lua_Debug.source (e.g. "@o/cosmic/fs/init.lua")
// and values are per-line hit counts.
//
// Counts are process-global across every thread the hook is armed on.
// Hooks are per-thread, but lua_newthread copies a C hook into new
// threads, so a coroutine created while collection runs inherits it
// automatically — unlike a Lua-function hook, whose per-thread
// registry entry is not copied, which is why Lua-side collectors must
// wrap coroutine.create. arm(thread) opts in a thread that existed
// before start(). snapshot() returns a fresh table each call;
// collection keeps running. The hook allocates outside the Lua heap
// and never raises.

#define COV_BUCKETS 512      // chunk-name hash buckets (power of two)
#define COV_MAX_LINE 1048576 // ignore absurd line numbers, don't alloc for them

struct CovRec {
  struct CovRec *next;  // hash-chain sibling
  char *name;           // chunk source, e.g. "@o/main.lua" (owned copy)
  lua_Integer *counts;  // hit counts indexed by line; slot 0 unused
  int cap;              // counts[] capacity
  unsigned hash;        // hash of name, saved to cheapen chain walks
};

static struct {
  const char *last_src;      // source pointer the hook saw last
  struct CovRec *last_rec;   // its record: consecutive lines in one
                             // chunk cost a pointer compare, not a walk
  struct CovRec *buckets[COV_BUCKETS];
} g_cov;

static unsigned CovHash(const char *s) {
  unsigned h = 5381;
  while (*s) h = h * 33 + (unsigned char)*s++;
  return h;
}

static struct CovRec *CovFind(const char *src) {
  unsigned h = CovHash(src);
  struct CovRec **b = &g_cov.buckets[h & (COV_BUCKETS - 1)];
  struct CovRec *r;
  for (r = *b; r; r = r->next) {
    if (r->hash == h && !strcmp(r->name, src)) {
      return r;
    }
  }
  if (!(r = calloc(1, sizeof(*r)))) return 0;
  if (!(r->name = strdup(src))) {
    free(r);
    return 0;
  }
  r->hash = h;
  r->next = *b;
  *b = r;
  return r;
}

static void CovHook(lua_State *L, lua_Debug *ar) {
  int line;
  const char *src;
  struct CovRec *r;
  if (ar->event != LUA_HOOKLINE) return;
  line = ar->currentline;
  if (line <= 0 || line > COV_MAX_LINE) return;
  if (!lua_getinfo(L, "S", ar)) return;
  if (!(src = ar->source)) return;
  // The pointer compare alone would trust that an interned source
  // string was not collected and its address reused; the strcmp makes
  // the cache exact, and costs a few nanoseconds on typical "@o/…"
  // paths.
  if (src == g_cov.last_src && g_cov.last_rec &&
      !strcmp(src, g_cov.last_rec->name)) {
    r = g_cov.last_rec;
  } else {
    if (!(r = CovFind(src))) return;  // oom: drop the hit, never raise here
    g_cov.last_src = src;
    g_cov.last_rec = r;
  }
  if (line >= r->cap) {
    int ncap = r->cap ? r->cap : 256;
    lua_Integer *n;
    while (ncap <= line) ncap *= 2;
    if (!(n = realloc(r->counts, ncap * sizeof(*n)))) return;
    memset(n + r->cap, 0, (ncap - r->cap) * sizeof(*n));
    r->counts = n;
    r->cap = ncap;
  }
  r->counts[line]++;
}

// cov.start()
//
// Arms line-hit collection on the calling thread. Counting starts
// (or resumes) immediately; counts accumulate into process-global
// state shared with every other armed thread.
static int LuaCovStart(lua_State *L) {
  lua_sethook(L, CovHook, LUA_MASKLINE, 0);
  return 0;
}

// cov.stop()
//
// Disarms collection on the calling thread. A hook installed by
// something else is left alone. Collected counts are kept; use
// reset() to discard them.
static int LuaCovStop(lua_State *L) {
  if (lua_gethook(L) == CovHook) {
    lua_sethook(L, 0, 0, 0);
  }
  return 0;
}

// cov.running() -> boolean
//
// Whether the calling thread's hook is this collector's.
static int LuaCovRunning(lua_State *L) {
  lua_pushboolean(L, lua_gethook(L) == CovHook);
  return 1;
}

// cov.arm(thread)
//
// Arms collection on another thread (a coroutine). A coroutine
// created while collection runs inherits the hook already; this opts
// in one that existed before start().
static int LuaCovArm(lua_State *L) {
  luaL_checktype(L, 1, LUA_TTHREAD);
  lua_sethook(lua_tothread(L, 1), CovHook, LUA_MASKLINE, 0);
  return 0;
}

// cov.snapshot() -> table
//
// A fresh copy of the collected counts: chunk source (as reported by
// lua_Debug.source, e.g. "@o/main.lua") to a table of line -> hits.
// Collection state is unchanged.
static int LuaCovSnapshot(lua_State *L) {
  int i, line, any;
  struct CovRec *r;
  lua_newtable(L);
  for (i = 0; i < COV_BUCKETS; ++i) {
    for (r = g_cov.buckets[i]; r; r = r->next) {
      any = 0;
      lua_newtable(L);
      for (line = 1; line < r->cap; ++line) {
        if (r->counts[line]) {
          lua_pushinteger(L, r->counts[line]);
          lua_rawseti(L, -2, line);
          any = 1;
        }
      }
      if (any) {
        // a record exists only once a line hit landed, but an
        // allocation failure can leave one empty; omitting it keeps
        // snapshots free of zero-hit chunks
        lua_setfield(L, -2, r->name);
      } else {
        lua_pop(L, 1);
      }
    }
  }
  return 1;
}

// cov.reset()
//
// Discards all collected counts. Armed hooks stay armed.
static int LuaCovReset(lua_State *L) {
  int i;
  struct CovRec *r, *next;
  for (i = 0; i < COV_BUCKETS; ++i) {
    for (r = g_cov.buckets[i]; r; r = next) {
      next = r->next;
      free(r->counts);
      free(r->name);
      free(r);
    }
    g_cov.buckets[i] = 0;
  }
  g_cov.last_src = 0;
  g_cov.last_rec = 0;
  return 0;
}

// clang-format off
static const luaL_Reg kLuaCov[] = {
    {"arm", LuaCovArm},
    {"reset", LuaCovReset},
    {"running", LuaCovRunning},
    {"snapshot", LuaCovSnapshot},
    {"start", LuaCovStart},
    {"stop", LuaCovStop},
    {NULL, NULL}
};
// clang-format on

int LuaCov(lua_State *L) {
  luaL_newlib(L, kLuaCov);
  return 1;
}
