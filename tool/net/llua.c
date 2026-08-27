/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2026 Will Maier                                                    │
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
#include "tool/net/llua.h"
#include "libc/assert.h"
#include "libc/ctype.h"
#include "libc/intrin/likely.h"
#include "libc/runtime/stack.h"
#include "libc/stdio/stdio.h"
#include "libc/str/str.h"
#include "libc/str/tab.h"
#include "third_party/lua/lauxlib.h"
#include "third_party/lua/lobject.h"
#include "third_party/lua/lua.h"

// How deep a literal may nest. Matches the Lua-side reader's cap so a
// crafted `{a={a={a=...}}}` earns the same polite refusal here.
#define DEPTH 32

// The largest code point `\u{...}` may name, which is what `utf8.char`
// accepts and what the Lua manual specifies for the escape.
#define MAXCODEPOINT 0x7fffffffL

// Longest numeral read through the stack buffer; longer ones are copied
// through the Lua stack instead, since a numeral has no length limit.
#define NUMBUF 128

// The refusal classes. Each is a distinct message so a caller can tell
// them apart; composing prose around them, with a file name and a line
// counted from the reported offset, is the caller's business.
static const char kErrString[] = "unterminated string";
static const char kErrLongString[] = "unterminated long string";
static const char kErrLongComment[] = "unterminated long comment";
static const char kErrReturn[] = "must be exactly `return { ... }`";
static const char kErrTable[] = "must return a table literal";
static const char kErrTrailing[] = "ends after its table";
static const char kErrDepth[] = "nests deeper than 32 tables";
static const char kErrEntry[] = "is a table of `name = <literal>` entries";
static const char kErrKey[] = "has a malformed string key";
static const char kErrValue[] = "has a malformed string value";
static const char kErrNumValue[] = "has a malformed number value";
static const char kErrLiteral[] = "holds literals only";
static const char kErrAfterValue[] = "holds literals only after a value";

// Lua's reserved words, sorted. They are refused as bare keys, so
// `return { end = 1 }` is a grammar violation rather than an entry.
static const char *const kLuaKeywords[] = {
    "and",   "break",  "do",     "else", "elseif", "end",
    "false", "for",    "function", "goto", "if",   "in",
    "local", "nil",    "not",    "or",   "repeat", "return",
    "then",  "true",   "until",  "while",
};

// What one parse carries: the input, where to write a refusal, and the
// stack floor the recursion may not pass.
struct Ctx {
  lua_State *L;
  const char *s;
  const char *e;
  char *err;
  size_t errsz;
  uintptr_t bsp;
  // Set when a string scan failed lexically (it never closed) rather
  // than on a bad escape, so the caller keeps that message instead of
  // replacing it with a key- or value-shaped one.
  int lexfail;
};

// Record `msg` and report a refusal at `at`.
static struct DecodeLua Fail(struct Ctx *c, const char *at, const char *msg) {
  if (c->errsz) {
    size_t n = strlen(msg);
    if (n >= c->errsz)
      n = c->errsz - 1;
    memcpy(c->err, msg, n);
    c->err[n] = 0;
  }
  return (struct DecodeLua){-1, at};
}

// True when [p,e) opens a long bracket; *level receives its `=` count.
static bool IsLongBracket(const char *p, const char *e, int *level) {
  const char *q = p;
  if (q >= e || *q != '[')
    return false;
  ++q;
  while (q < e && *q == '=')
    ++q;
  if (q >= e || *q != '[')
    return false;
  *level = (int)(q - p - 1);
  return true;
}

// Just past the long bracket that opens at `p`, or NULL when it never
// closes.
static const char *LongBracketEnd(const char *p, const char *e, int level) {
  size_t closelen = (size_t)level + 2;
  const char *q = p + closelen;
  while (q < e) {
    const char *hit = memchr(q, ']', (size_t)(e - q));
    if (!hit)
      return NULL;
    if ((size_t)(e - hit) >= closelen) {
      int i;
      for (i = 1; i <= level; ++i)
        if (hit[i] != '=')
          break;
      if (i > level && hit[level + 1] == ']')
        return hit + closelen;
    }
    q = hit + 1;
  }
  return NULL;
}

// Skip whitespace, `--` line comments and `--[=*[` long comments.
// Returns NULL when a long comment never closes, with *bad at its start.
static const char *SkipTrivia(const char *p, const char *e, const char **bad) {
  for (;;) {
    while (p < e && isspace((unsigned char)*p))
      ++p;
    if (e - p < 2 || p[0] != '-' || p[1] != '-')
      return p;
    int level;
    if (IsLongBracket(p + 2, e, &level)) {
      const char *q = LongBracketEnd(p + 2, e, level);
      if (!q) {
        *bad = p;
        return NULL;
      }
      p = q;
    } else {
      const char *nl = memchr(p, '\n', (size_t)(e - p));
      p = nl ? nl : e;
    }
  }
}

// True when the word `w` of length `n` sits at `p` with no identifier
// character after it.
static bool IsWord(const char *p, const char *e, const char *w, size_t n) {
  if ((size_t)(e - p) < n || memcmp(p, w, n))
    return false;
  if ((size_t)(e - p) == n)
    return true;
  return !(isalnum((unsigned char)p[n]) || p[n] == '_');
}

// True when [p,p+n) is one of Lua's reserved words.
static bool IsKeyword(const char *p, size_t n) {
  int lo = 0, hi = (int)(sizeof(kLuaKeywords) / sizeof(*kLuaKeywords)) - 1;
  while (lo <= hi) {
    int mid = (lo + hi) / 2;
    const char *k = kLuaKeywords[mid];
    size_t kn = strlen(k);
    int cmp = memcmp(p, k, n < kn ? n : kn);
    if (!cmp)
      cmp = n < kn ? -1 : (n > kn ? 1 : 0);
    if (!cmp)
      return true;
    if (cmp < 0)
      hi = mid - 1;
    else
      lo = mid + 1;
  }
  return false;
}

// Push the value of the short string that opens at `p` (its quote), and
// return just past its closing quote.
static struct DecodeLua ScanShortString(struct Ctx *c, const char *p) {
  const char *e = c->e;
  char quote = *p;
  const char *q = p + 1;
  luaL_Buffer b;
  c->lexfail = 0;
  luaL_buffinit(c->L, &b);
  while (q < e && *q != quote) {
    unsigned char ch = (unsigned char)*q;
    if (ch == '\n') {
      c->lexfail = 1;
      return Fail(c, p, kErrString);
    }
    if (ch != '\\') {
      luaL_addchar(&b, (char)ch);
      ++q;
      continue;
    }
    if (++q >= e)
      break;
    unsigned char esc = (unsigned char)*q;
    if (esc == 'a' || esc == 'b' || esc == 'f' || esc == 'n' || esc == 'r' ||
        esc == 't' || esc == 'v' || esc == '\\' || esc == '"' || esc == '\'' ||
        esc == '\n') {
      static const char kFrom[] = "abfnrtv\\\"'\n";
      static const char kTo[] = "\a\b\f\n\r\t\v\\\"'\n";
      const char *at = strchr(kFrom, (char)esc);
      luaL_addchar(&b, kTo[at - kFrom]);
      ++q;
    } else if (esc == 'x') {
      int hi, lo;
      if (e - q < 3 || (hi = kHexToInt[(unsigned char)q[1]]) < 0 ||
          (lo = kHexToInt[(unsigned char)q[2]]) < 0)
        return Fail(c, p, kErrValue);
      luaL_addchar(&b, (char)(hi * 16 + lo));
      q += 3;
    } else if (esc == 'z') {
      // Skips the whitespace that follows, newlines included — that is
      // what the escape is for, and what load accepts. A raw newline
      // not behind \z still ends the string (the check at the top of
      // the scan).
      ++q;
      while (q < e && isspace((unsigned char)*q))
        ++q;
    } else if (esc == 'u') {
      const char *r = q + 1;
      if (r >= e || *r != '{')
        return Fail(c, p, kErrValue);
      ++r;
      const char *ds = r;
      long cp = 0;
      int over = 0;
      while (r < e && kHexToInt[(unsigned char)*r] >= 0) {
        if (cp > MAXCODEPOINT / 16)
          over = 1;
        else
          cp = cp * 16 + kHexToInt[(unsigned char)*r];
        ++r;
      }
      if (r == ds || r >= e || *r != '}' || over || cp > MAXCODEPOINT)
        return Fail(c, p, kErrValue);
      char bf[UTF8BUFFSZ];
      int len = luaO_utf8esc(bf, (unsigned long)cp);
      luaL_addlstring(&b, bf + UTF8BUFFSZ - len, (size_t)len);
      q = r + 1;
    } else if (isdigit(esc)) {
      int n = 0, k = 0;
      while (k < 3 && q < e && isdigit((unsigned char)*q)) {
        n = n * 10 + (*q - '0');
        ++q, ++k;
      }
      if (n > 255)
        return Fail(c, p, kErrValue);
      luaL_addchar(&b, (char)n);
    } else {
      return Fail(c, p, kErrValue);
    }
  }
  if (q >= e) {
    c->lexfail = 1;
    return Fail(c, p, kErrString);
  }
  luaL_pushresult(&b);
  return (struct DecodeLua){1, q + 1};
}

// Push the value of the long bracket string that opens at `p`. It takes
// no escapes, and a newline right after the opening delimiter is Lua's
// to drop.
static struct DecodeLua ScanLongString(struct Ctx *c, const char *p,
                                       int level) {
  const char *end = LongBracketEnd(p, c->e, level);
  if (!end) {
    c->lexfail = 1;
    return Fail(c, p, kErrLongString);
  }
  const char *body = p + level + 2;
  const char *stop = end - (level + 2);
  if (body < stop && *body == '\n')
    ++body;
  lua_pushlstring(c->L, body, (size_t)(stop - body));
  return (struct DecodeLua){1, end};
}

// Just past the numeral at `p`, or NULL when none starts there. The
// shape is Lua's: hex digits with an optional `.` and `[pP]` exponent,
// or decimal digits with an optional `.` and `[eE]` one. A shape is not
// a value -- `0x.` and `1e` scan here and are refused by the conversion.
static const char *NumeralEnd(const char *p, const char *e) {
  const char *q;
  if (e - p >= 2 && p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) {
    q = p + 2;
    while (q < e && isxdigit((unsigned char)*q))
      ++q;
    if (q < e && *q == '.') {
      ++q;
      while (q < e && isxdigit((unsigned char)*q))
        ++q;
    }
    if (q > p + 2) {
      if (q < e && (*q == 'p' || *q == 'P')) {
        const char *x = q + 1;
        if (x < e && (*x == '+' || *x == '-'))
          ++x;
        const char *d = x;
        while (x < e && isdigit((unsigned char)*x))
          ++x;
        if (x > d)
          q = x;
      }
      return q;
    }
  }
  q = p;
  while (q < e && isdigit((unsigned char)*q))
    ++q;
  if (q < e && *q == '.') {
    ++q;
    while (q < e && isdigit((unsigned char)*q))
      ++q;
  }
  if (q == p || (q == p + 1 && *p == '.'))
    return NULL;
  if (q < e && (*q == 'e' || *q == 'E')) {
    const char *x = q + 1;
    if (x < e && (*x == '+' || *x == '-'))
      ++x;
    const char *d = x;
    while (x < e && isdigit((unsigned char)*x))
      ++x;
    if (x > d)
      q = x;
  }
  return q;
}

// Push the number the numeral at `p` denotes, negated when `neg`. The
// text is handed to lua_stringtonumber, which is the same conversion
// `load` performs, so this reader agrees with the runtime it mirrors.
//
// Callers reach here only with a digit at `p`, or a `.` with a digit
// behind it, so the numeral always has a shape: a failure here is the
// CONVERSION refusing a shape it cannot value (`0x.`), never a missing
// numeral. There is no refusal class for the latter because no input
// produces it.
static struct DecodeLua ScanNumber(struct Ctx *c, const char *p, int neg) {
  lua_State *L = c->L;
  const char *end = NumeralEnd(p, c->e);
  unassert(end);
  size_t n = (size_t)(end - p);
  const char *z;
  char buf[NUMBUF];
  if (n < sizeof(buf)) {
    memcpy(buf, p, n);
    buf[n] = 0;
    z = buf;
  } else {
    lua_pushlstring(L, p, n);
    z = lua_tostring(L, -1);
  }
  size_t got = lua_stringtonumber(L, z);
  if (n >= sizeof(buf))
    // Drop the copy `z` pointed into. A conversion that read anything
    // pushed its result above that copy, so the copy is at -2; one that
    // read nothing pushed nothing, so the copy is still on top.
    lua_remove(L, got ? -2 : -1);
  if (got != n + 1) {
    if (got)
      lua_pop(L, 1);
    return Fail(c, p, kErrNumValue);
  }
  if (neg)
    lua_arith(L, LUA_OPUNM);
  return (struct DecodeLua){1, end};
}

static struct DecodeLua ParseTable(struct Ctx *, const char *, int);

// Offset of the first entry naming the key on top of the Lua stack in
// the table that opens at `tbl`, or -1 when it cannot be pinned down.
// Cold: this runs only to compose the duplicate-key refusal, so a table
// pays nothing for it while it parses.
static long FirstKeyAt(struct Ctx *c, const char *tbl) {
  lua_State *L = c->L;
  const char *e = c->e, *bad, *p = tbl + 1;
  size_t keylen;
  const char *key = lua_tolstring(L, -1, &keylen);
  const char *opener = NULL;
  int depth = 0;
  while (p < e) {
    if (!(p = SkipTrivia(p, e, &bad)) || p >= e)
      return -1;
    unsigned char ch = (unsigned char)*p;
    int level;
    if (ch == '{') {
      ++depth, ++p;
    } else if (ch == '}') {
      if (!depth)
        return -1;
      --depth, ++p;
    } else if (ch == '"' || ch == '\'' ||
               (ch == '[' && IsLongBracket(p, e, &level))) {
      struct DecodeLua r = ch == '[' ? ScanLongString(c, p, level)
                                     : ScanShortString(c, p);
      if (r.rc < 0)
        return -1;
      // The `["key"] =` form begins at the `[` this string followed; a
      // string reached any other way is a value, and opens nothing.
      const char *at = opener;
      int match = !depth && at && lua_rawequal(L, -1, -2);
      lua_pop(L, 1);
      p = r.p;
      opener = NULL;
      if (match)
        return (long)(at - c->s);
    } else if (!depth && ch == '[') {
      opener = p++;
    } else if (!depth && (isalpha(ch) || ch == '_')) {
      const char *q = p;
      while (q < e && (isalnum((unsigned char)*q) || *q == '_'))
        ++q;
      if ((size_t)(q - p) == keylen && !memcmp(p, key, keylen)) {
        const char *r = SkipTrivia(q, e, &bad);
        if (r && r < e && *r == '=')
          return (long)(p - c->s);
      }
      p = q;
    } else {
      ++p;
    }
  }
  return -1;
}

// Report a key repeated inside one table, naming it and where it first
// appeared.
static struct DecodeLua Duplicate(struct Ctx *c, const char *tbl,
                                  const char *at) {
  size_t keylen;
  const char *key = lua_tolstring(c->L, -1, &keylen);
  long first = FirstKeyAt(c, tbl);
  if (keylen > 64)
    keylen = 64;
  if (c->errsz) {
    if (first >= 0)
      snprintf(c->err, c->errsz, "repeats the key '%.*s' (first at offset %ld)",
               (int)keylen, key, first + 1);
    else
      snprintf(c->err, c->errsz, "repeats the key '%.*s'", (int)keylen, key);
  }
  return (struct DecodeLua){-1, at};
}

// Parse the table that opens at `p` and leave it on the stack.
static struct DecodeLua ParseTable(struct Ctx *c, const char *p, int depth) {
  lua_State *L = c->L;
  const char *e = c->e, *bad, *tbl = p;
  struct DecodeLua r;
  int level;
  if (depth > DEPTH || UNLIKELY(GetStackPointer() < c->bsp))
    return Fail(c, p, kErrDepth);
  lua_createtable(L, 0, 8);
  int ti = lua_gettop(L);
  ++p;
  for (;;) {
    if (!(p = SkipTrivia(p, e, &bad)))
      return Fail(c, bad, kErrLongComment);
    if (p >= e)
      return Fail(c, p, kErrEntry);
    if (*p == '}')
      return (struct DecodeLua){1, p + 1};
    // key: `name =` or `["name"] =`
    const char *keyat = p;
    unsigned char ch = (unsigned char)*p;
    if (isalpha(ch) || ch == '_') {
      const char *q = p;
      while (q < e && (isalnum((unsigned char)*q) || *q == '_'))
        ++q;
      if (IsKeyword(p, (size_t)(q - p)))
        return Fail(c, p, kErrEntry);
      const char *sep = SkipTrivia(q, e, &bad);
      if (!sep)
        return Fail(c, bad, kErrLongComment);
      if (sep >= e || *sep != '=')
        return Fail(c, p, kErrEntry);
      lua_pushlstring(L, p, (size_t)(q - p));
      p = sep + 1;
    } else if (ch == '[' && !IsLongBracket(p, e, &level)) {
      const char *q = SkipTrivia(p + 1, e, &bad);
      if (!q)
        return Fail(c, bad, kErrLongComment);
      if (q >= e)
        return Fail(c, p, kErrEntry);
      if (*q == '"' || *q == '\'') {
        r = ScanShortString(c, q);
        if (r.rc < 0)
          return c->lexfail ? r : Fail(c, q, kErrKey);
      } else if (*q == '[' && IsLongBracket(q, e, &level)) {
        r = ScanLongString(c, q, level);
        if (r.rc < 0)
          return r;
      } else {
        return Fail(c, p, kErrEntry);
      }
      const char *sep = SkipTrivia(r.p, e, &bad);
      if (!sep)
        return Fail(c, bad, kErrLongComment);
      if (sep >= e || *sep != ']')
        return Fail(c, p, kErrEntry);
      if (!(sep = SkipTrivia(sep + 1, e, &bad)))
        return Fail(c, bad, kErrLongComment);
      if (sep >= e || *sep != '=')
        return Fail(c, p, kErrEntry);
      p = sep + 1;
    } else {
      return Fail(c, p, kErrEntry);
    }
    // value: a nested table, a string, a numeral, `-` before a numeral,
    // or true/false. Nothing else, and nothing computed.
    if (!(p = SkipTrivia(p, e, &bad)))
      return Fail(c, bad, kErrLongComment);
    if (p >= e)
      return Fail(c, p, kErrLiteral);
    ch = (unsigned char)*p;
    if (ch == '{') {
      r = ParseTable(c, p, depth + 1);
      if (r.rc < 0)
        return r;
      p = r.p;
    } else if (ch == '"' || ch == '\'') {
      r = ScanShortString(c, p);
      if (r.rc < 0)
        return c->lexfail ? r : Fail(c, p, kErrValue);
      p = r.p;
    } else if (ch == '[' && IsLongBracket(p, e, &level)) {
      r = ScanLongString(c, p, level);
      if (r.rc < 0)
        return r;
      p = r.p;
    } else if (isdigit(ch) ||
               (ch == '.' && p + 1 < e && isdigit((unsigned char)p[1]))) {
      r = ScanNumber(c, p, 0);
      if (r.rc < 0)
        return r;
      p = r.p;
    } else if (ch == '-') {
      const char *q = SkipTrivia(p + 1, e, &bad);
      if (!q)
        return Fail(c, bad, kErrLongComment);
      if (q >= e || !(isdigit((unsigned char)*q) ||
                      (*q == '.' && q + 1 < e && isdigit((unsigned char)q[1]))))
        return Fail(c, p, kErrLiteral);
      r = ScanNumber(c, q, 1);
      if (r.rc < 0)
        return r;
      p = r.p;
    } else if (IsWord(p, e, "true", 4)) {
      lua_pushboolean(L, 1);
      p += 4;
    } else if (IsWord(p, e, "false", 5)) {
      lua_pushboolean(L, 0);
      p += 5;
    } else {
      return Fail(c, p, kErrLiteral);
    }
    // A key repeated inside one table is refused, not resolved: picking
    // between two values is a policy, and this reader has none.
    lua_pushvalue(L, -2);
    if (lua_rawget(L, ti) != LUA_TNIL) {
      lua_pop(L, 1);
      lua_pop(L, 1);
      return Duplicate(c, tbl, keyat);
    }
    lua_pop(L, 1);
    lua_rawset(L, ti);
    // A value is followed by a separator or the closing brace, and
    // nothing else, so an operator after a literal is refused where it
    // stands rather than read as the next key.
    if (!(p = SkipTrivia(p, e, &bad)))
      return Fail(c, bad, kErrLongComment);
    if (p < e && (*p == ',' || *p == ';'))
      ++p;
    else if (p >= e || *p != '}')
      return Fail(c, p, kErrAfterValue);
  }
}

// Parse `return <table>` and leave the table on the stack.
static struct DecodeLua Parse(struct Ctx *c) {
  const char *p = c->s, *e = c->e, *bad;
  struct DecodeLua r;
  if (e - p >= 2 && p[0] == '#' && p[1] == '!') {
    const char *nl = memchr(p, '\n', (size_t)(e - p));
    p = nl ? nl : e;
  }
  if (!(p = SkipTrivia(p, e, &bad)))
    return Fail(c, bad, kErrLongComment);
  if (!IsWord(p, e, "return", 6))
    return Fail(c, p, kErrReturn);
  if (!(p = SkipTrivia(p + 6, e, &bad)))
    return Fail(c, bad, kErrLongComment);
  if (p >= e || *p != '{')
    return Fail(c, p, kErrTable);
  r = ParseTable(c, p, 1);
  if (r.rc < 0)
    return r;
  if (!(p = SkipTrivia(r.p, e, &bad)))
    return Fail(c, bad, kErrLongComment);
  if (p < e)
    return Fail(c, p, kErrTrailing);
  return (struct DecodeLua){1, p};
}

/**
 * Reads the table a Lua literal file returns, without running it.
 *
 * The grammar is `return { ... }` with `name = <literal>` and
 * `["name"] = <literal>` entries, whose values are nested tables,
 * strings, numerals, an optional `-` before a numeral, or true/false.
 * Comments and long bracket strings are admitted; variables, calls,
 * concatenation and every other expression are refused, so reading a
 * file cannot run one.
 *
 * @param L is Lua interpreter state
 * @param p is input string
 * @param n is byte length of `p` or -1 for automatic strlen()
 * @param err receives the refusal message when `rc < 0`
 * @param errsz is the byte size of `err`, e.g. LLUA_ERRMAX
 * @return r.rc is 1 if the table is pushed on the lua stack
 * @return r.rc is -1 on error
 * @return r.p is the advanced `p` pointer if `rc > 0`
 * @return r.p points at the failing byte of `p` if `rc < 0`
 */
struct DecodeLua DecodeLua(struct lua_State *L, const char *p, size_t n,
                           char *err, size_t errsz) {
  if (n == -1)
    n = p ? strlen(p) : 0;
  struct Ctx c = {L, p, p + n, err, errsz, GetStackBottom() + 4096, 0};
  if (!lua_checkstack(L, DEPTH * 3 + LUA_MINSTACK))
    return Fail(&c, p, "can't set stack depth");
  int top = lua_gettop(L);
  struct DecodeLua r = Parse(&c);
  if (r.rc < 0)
    lua_settop(L, top);
  return r;
}
