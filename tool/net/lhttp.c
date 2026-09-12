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
#include "tool/net/lhttp.h"
#include "libc/limits.h"
#include "libc/str/str.h"
#include "net/http/http.h"
#include "third_party/lua/lauxlib.h"
#include "third_party/lua/lua.h"
#include <stdlib.h>
#include <string.h>

// cosmo.http: net/http's wire grammar, without a serving loop.
//
// The parser, the chunked-transfer decoder and the extension to
// content-type table are exposed as plain Lua objects that consume
// bytes the caller already has. Nothing here touches a socket, a file
// descriptor or TLS: a Lua server owns the accept loop and the reads,
// and this module owns the grammar.
//
// A Parser wraps one `struct HttpMessage`. State persists across
// `parse` calls, so a fragmented head is resumed rather than rescanned:
// the caller appends what it just read to its own buffer and calls
// `parse` again with the WHOLE buffer, whose earlier bytes the parser
// has already consumed (`r->i` is its cursor into it). Header values
// are `struct HttpSlice` offsets into that same buffer, never copies,
// which is why `message` takes the buffer back to materialize them.
//
// An Unchunker wraps one `struct HttpUnchunker`. Unchunk decodes in
// place and indexes the buffer absolutely across calls, so the
// unchunker owns a growable copy of every byte fed to it and hands
// back the decoded prefix on demand.

#define LUA_HTTP_PARSER    "http.Parser"
#define LUA_HTTP_UNCHUNKER "http.Unchunker"

struct LuaHttpParser {
  struct HttpMessage msg;
  int kind;        // kHttpRequest or kHttpResponse
  int complete;    // a parse() has returned the head's length
  size_t headlen;  // that length, the bound every slice lies within
                   // -- which holds only because the parser refuses a
                   // parse() that would move its cursor backwards:
                   // `complete` closes it to a parse() past a finished
                   // head, `maxlen` to one on a shrinking buffer
  size_t maxlen;   // the longest buffer parse() has accepted for this
                   // head, which the next one may not fall below
};

struct LuaHttpUnchunker {
  struct HttpUnchunker u;
  char *p;      // every byte fed so far, decoded in place
  size_t n;     // how many of them there are
  size_t cap;   // how many p can hold
  int complete; // the terminating chunk has been seen
};

////////////////////////////////////////////////////////////////////////////////
// http.Parser

static struct LuaHttpParser *GetParser(lua_State *L) {
  return luaL_checkudata(L, 1, LUA_HTTP_PARSER);
}

// http.parser(kind) -> http.Parser
// kind is "request" or "response"; anything else is an argument error
static int LuaHttpParserNew(lua_State *L) {
  struct LuaHttpParser *p;
  static const char *const kKinds[] = {"request", "response", 0};
  int kind = luaL_checkoption(L, 1, 0, kKinds) == 0 ? kHttpRequest
                                                    : kHttpResponse;
  p = lua_newuserdatauv(L, sizeof(*p), 0);
  bzero(p, sizeof(*p));
  p->kind = kind;
  luaL_setmetatable(L, LUA_HTTP_PARSER);
  InitHttpMessage(&p->msg, kind);
  return 1;
}

static int LuaHttpParserGc(lua_State *L) {
  struct LuaHttpParser *p = GetParser(L);
  DestroyHttpMessage(&p->msg);
  bzero(&p->msg, sizeof(p->msg));
  return 0;
}

static int LuaHttpParserTostring(lua_State *L) {
  struct LuaHttpParser *p = GetParser(L);
  lua_pushfstring(L, "http.Parser(%s)",
                  p->kind == kHttpRequest ? "request" : "response");
  return 1;
}

// Parser:parse(buf) -> n | 0 | nil, error
static int LuaHttpParserParse(lua_State *L) {
  size_t n;
  int rc;
  const char *buf;
  struct LuaHttpParser *p = GetParser(L);
  buf = luaL_checklstring(L, 2, &n);
  // One parser reads one head: a completed parse fixes `headlen`, which
  // `message` trusts as the bound every slice lies within, and reset()
  // is how the next message on the connection starts.
  //
  // ParseHttpMessage does not stop at a head it has already finished. A
  // head terminated by bare LF-LF returns out of kHttpStateLf1 while
  // still IN that state, so a further parse() on a longer buffer resumes
  // header scanning and writes slices at offsets PAST `headlen`, all
  // while returning 0. message() then passes its n >= headlen guard and
  // reads those offsets past the end of the string it was handed. A
  // further parse() that comes back -1 is the same hazard with a stale
  // `headlen` left behind. Refusing the call is what makes `headlen` a
  // real bound rather than a hopeful one.
  if (p->complete)
    return luaL_error(
        L, "parse already completed a message head; call reset() first");
  // ParseHttpMessage clamps n and c to SHRT_MAX and parses the prefix,
  // which would silently report a head that is not there. Refuse it.
  if (n > SHRT_MAX) {
    lua_pushnil(L);
    lua_pushstring(L, "message too large");
    return 2;
  }
  // The cursor only ever moves forward while the caller's buffer only
  // ever grows: ParseHttpMessage clamps its cursor DOWN to `n` when a
  // call passes fewer bytes than an earlier one
  // (net/http/parsehttpmessage.c, `if (r->i > n) r->i = n`), so a head
  // could then complete at an offset BELOW slices already recorded from
  // the longer buffer. `headlen` would be smaller than the offsets
  // `message` reads, and its `n >= headlen` guard would admit a buffer
  // far shorter than them -- the same out-of-bounds read, reached
  // without ever parsing past a finished head. A buffer equal in length
  // to the last one is normal (a wakeup that produced no new bytes) and
  // rescans nothing; only a shorter one is refused.
  if (n < p->maxlen)
    return luaL_argerror(L, 2,
                         "shorter than a buffer already parsed; a parser "
                         "resumes a growing buffer, never a shrinking one");
  p->maxlen = n;
  // `c` is not a memory bound -- ParseHttpMessage never indexes past `n`
  // with it -- but how large the message may still GROW, clamped to
  // SHRT_MAX. Passing `n` would declare the buffer already full, and an
  // incomplete head would come back as -1 instead of 0, so a fragmented
  // message could never be resumed. SHRT_MAX is the parser's own ceiling:
  // an incomplete head is 0 until it reaches that ceiling, where it is
  // genuinely a bad message.
  rc = ParseHttpMessage(&p->msg, buf, n, SHRT_MAX);
  if (rc == -1) {
    lua_pushnil(L);
    lua_pushstring(L, "bad message");
    return 2;
  }
  if (rc > 0) {
    p->complete = 1;
    p->headlen = rc;
  }
  lua_pushinteger(L, rc);
  return 1;
}

// Whether net/http marks this header name as one a message may
// legitimately carry more than once (Vary, Accept-Encoding, ...). An
// unrecognized name is not repeatable.
static int IsRepeatable(const char *s, size_t n) {
  int h;
  if ((h = GetHttpHeader(s, n)) != -1)
    return kHttpRepeatable[h];
  return 0;
}

// Adds one header to the table at `tidx`, which must be an absolute
// index, in the shape cosmo.Fetch returns (tool/net/lfetch.c's
// LuaPushHeaders): a repeatable name holds an ARRAY of its values in
// arrival order, from its first occurrence on, so a caller reads one
// shape whether the message carried the header once or five times; any
// other name holds a plain string, a later occurrence replacing an
// earlier one. Both bindings emit the same table for the same bytes,
// which is what lets one downstream normalizer serve both.
static void PushHeader(lua_State *L, int tidx, const char *k, size_t kn,
                       const char *v, size_t vn) {
  if (!IsRepeatable(k, kn)) {
    lua_pushlstring(L, k, kn);
    lua_pushlstring(L, v, vn);
    lua_rawset(L, tidx);
    return;
  }
  lua_pushlstring(L, k, kn);
  lua_rawget(L, tidx);
  if (lua_istable(L, -1)) {
    lua_pushlstring(L, v, vn);
    lua_rawseti(L, -2, lua_rawlen(L, -2) + 1);
    lua_pop(L, 1);
  } else {
    lua_pop(L, 1);
    lua_createtable(L, 1, 0);
    lua_pushlstring(L, v, vn);
    lua_rawseti(L, -2, 1);
    lua_pushlstring(L, k, kn);
    lua_pushvalue(L, -2);
    lua_rawset(L, tidx);
    lua_pop(L, 1);
  }
}

// Parser:message(buf) -> http.Message
static int LuaHttpParserMessage(lua_State *L) {
  int i, tidx;
  size_t n, kn, vn;
  const char *buf, *k;
  char method[9];
  int methodlen;
  uint64_t w;
  struct LuaHttpParser *p = GetParser(L);
  buf = luaL_checklstring(L, 2, &n);
  if (!p->complete)
    return luaL_error(L, "parse has not completed a message head yet");
  // Every slice is an offset into the buffer the head was parsed from,
  // so a shorter buffer would read past its end.
  if (n < p->headlen)
    return luaL_argerror(
        L, 2, "shorter than the parsed head; pass the buffer parse() read");
  lua_createtable(L, 0, 6);
  // The method is packed little-endian, one uppercased byte per octet,
  // NUL-padded; the parser caps it at eight characters.
  w = p->msg.method;
  for (methodlen = 0; methodlen < 8; ++methodlen) {
    if (!(w & 255))
      break;
    method[methodlen] = w & 255;
    w >>= 8;
  }
  lua_pushlstring(L, method, methodlen);
  lua_setfield(L, -2, "method");
  lua_pushlstring(L, buf + p->msg.uri.a, p->msg.uri.b - p->msg.uri.a);
  lua_setfield(L, -2, "uri");
  lua_pushinteger(L, p->msg.version);
  lua_setfield(L, -2, "version");
  if (p->kind == kHttpResponse) {
    lua_pushinteger(L, p->msg.status);
    lua_setfield(L, -2, "status");
    lua_pushlstring(L, buf + p->msg.message.a,
                    p->msg.message.b - p->msg.message.a);
    lua_setfield(L, -2, "message");
  }
  lua_createtable(L, 0, 16);
  tidx = lua_absindex(L, -1);
  for (i = 0; i < kHttpHeadersMax; ++i) {
    if (!p->msg.headers[i].a)
      continue;
    k = GetHttpHeaderName(i);
    kn = strlen(k);
    PushHeader(L, tidx, k, kn, buf + p->msg.headers[i].a,
               p->msg.headers[i].b - p->msg.headers[i].a);
  }
  for (i = 0; i < (int)p->msg.xheaders.n; ++i) {
    k = buf + p->msg.xheaders.p[i].k.a;
    kn = p->msg.xheaders.p[i].k.b - p->msg.xheaders.p[i].k.a;
    vn = p->msg.xheaders.p[i].v.b - p->msg.xheaders.p[i].v.a;
    PushHeader(L, tidx, k, kn, buf + p->msg.xheaders.p[i].v.a, vn);
  }
  lua_setfield(L, -2, "headers");
  return 1;
}

// Parser:reset() -> http.Parser
static int LuaHttpParserReset(lua_State *L) {
  struct LuaHttpParser *p = GetParser(L);
  ResetHttpMessage(&p->msg, p->kind);
  p->complete = 0;
  p->headlen = 0;
  p->maxlen = 0;
  lua_pushvalue(L, 1);
  return 1;
}

////////////////////////////////////////////////////////////////////////////////
// http.Unchunker

static struct LuaHttpUnchunker *GetUnchunker(lua_State *L) {
  return luaL_checkudata(L, 1, LUA_HTTP_UNCHUNKER);
}

// http.unchunker() -> http.Unchunker
static int LuaHttpUnchunkerNew(lua_State *L) {
  struct LuaHttpUnchunker *u = lua_newuserdatauv(L, sizeof(*u), 0);
  bzero(u, sizeof(*u));
  luaL_setmetatable(L, LUA_HTTP_UNCHUNKER);
  return 1;
}

static int LuaHttpUnchunkerGc(lua_State *L) {
  struct LuaHttpUnchunker *u = GetUnchunker(L);
  free(u->p);
  u->p = 0;
  u->n = 0;
  u->cap = 0;
  return 0;
}

static int LuaHttpUnchunkerTostring(lua_State *L) {
  struct LuaHttpUnchunker *u = GetUnchunker(L);
  lua_pushfstring(L, "http.Unchunker(%s)", u->complete ? "done" : "feeding");
  return 1;
}

// Unchunker:feed(buf) -> consumed | 0 | nil, error
static int LuaHttpUnchunkerFeed(lua_State *L) {
  char *q;
  ssize_t rc;
  size_t n, want, cap, decoded;
  const char *buf;
  struct LuaHttpUnchunker *u = GetUnchunker(L);
  buf = luaL_checklstring(L, 2, &n);
  if (u->complete)
    return luaL_error(L, "unchunker already reached the terminating chunk");
  // Unchunk indexes this buffer absolutely across calls, so it has to
  // hold every byte ever fed, not just the newest.
  want = u->n + n + 1;
  if (want > u->cap) {
    cap = u->cap ? u->cap : 64;
    while (cap < want)
      cap += cap >> 1;
    if (!(q = realloc(u->p, cap)))
      return luaL_error(L, "out of memory");
    u->p = q;
    u->cap = cap;
  }
  if (n)
    memcpy(u->p + u->n, buf, n);
  u->n += n;
  decoded = 0;
  rc = Unchunk(&u->u, u->p, u->n, &decoded);
  if (rc == -1) {
    lua_pushnil(L);
    lua_pushstring(L, "bad chunk");
    return 2;
  }
  if (rc > 0)
    u->complete = 1;
  lua_pushinteger(L, rc);
  return 1;
}

// Unchunker:body() -> string
static int LuaHttpUnchunkerBody(lua_State *L) {
  struct LuaHttpUnchunker *u = GetUnchunker(L);
  // u->j is Unchunk's write cursor: p[0,j) is decoded payload at every
  // point, and is the whole body once the terminating chunk was seen.
  lua_pushlstring(L, u->p ? u->p : "", u->u.j);
  return 1;
}

// Unchunker:is_done() -> boolean
static int LuaHttpUnchunkerIsDone(lua_State *L) {
  struct LuaHttpUnchunker *u = GetUnchunker(L);
  lua_pushboolean(L, u->complete);
  return 1;
}

////////////////////////////////////////////////////////////////////////////////
// http module

// http.find_content_type(path) -> string | nil
static int LuaHttpFindContentType(lua_State *L) {
  size_t n;
  const char *path, *mime;
  path = luaL_checklstring(L, 1, &n);
  if ((mime = FindContentType(path, n))) {
    lua_pushstring(L, mime);
  } else {
    lua_pushnil(L);
  }
  return 1;
}

static const luaL_Reg kLuaHttpParserMeta[] = {
    {"__gc", LuaHttpParserGc},
    {"__tostring", LuaHttpParserTostring},
    {0},
};

static const luaL_Reg kLuaHttpParserMethods[] = {
    {"parse", LuaHttpParserParse},
    {"message", LuaHttpParserMessage},
    {"reset", LuaHttpParserReset},
    {0},
};

static const luaL_Reg kLuaHttpUnchunkerMeta[] = {
    {"__gc", LuaHttpUnchunkerGc},
    {"__tostring", LuaHttpUnchunkerTostring},
    {0},
};

static const luaL_Reg kLuaHttpUnchunkerMethods[] = {
    {"feed", LuaHttpUnchunkerFeed},
    {"body", LuaHttpUnchunkerBody},
    {"is_done", LuaHttpUnchunkerIsDone},
    {0},
};

static const luaL_Reg kLuaHttp[] = {
    {"parser", LuaHttpParserNew},
    {"unchunker", LuaHttpUnchunkerNew},
    {"find_content_type", LuaHttpFindContentType},
    {0},
};

int LuaHttp(lua_State *L) {
  // create http.Parser metatable
  luaL_newmetatable(L, LUA_HTTP_PARSER);
  luaL_setfuncs(L, kLuaHttpParserMeta, 0);
  luaL_newlibtable(L, kLuaHttpParserMethods);
  luaL_setfuncs(L, kLuaHttpParserMethods, 0);
  lua_setfield(L, -2, "__index");
  lua_pop(L, 1);

  // create http.Unchunker metatable
  luaL_newmetatable(L, LUA_HTTP_UNCHUNKER);
  luaL_setfuncs(L, kLuaHttpUnchunkerMeta, 0);
  luaL_newlibtable(L, kLuaHttpUnchunkerMethods);
  luaL_setfuncs(L, kLuaHttpUnchunkerMethods, 0);
  lua_setfield(L, -2, "__index");
  lua_pop(L, 1);

  // create module table
  luaL_newlib(L, kLuaHttp);
  return 1;
}
