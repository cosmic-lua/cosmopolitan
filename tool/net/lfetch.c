/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2024 Will Maier                                                    │
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
#include "tool/net/lfetch.h"
#include "libc/calls/calls.h"
#include "libc/calls/struct/timeval.h"
#include "libc/cosmotime.h"
#include "libc/errno.h"
#include "libc/fmt/conv.h"
#include "libc/intrin/atomic.h"
#include "libc/log/check.h"
#include "libc/log/log.h"
#include "libc/mem/gc.h"
#include "libc/mem/mem.h"
#include "libc/runtime/runtime.h"
#include "libc/serialize.h"
#include "libc/sock/goodsocket.internal.h"
#include "libc/sock/sock.h"
#include "libc/sock/struct/sockaddr.h"
#include "libc/stdio/append.h"
#include "libc/str/slice.h"
#include "libc/str/str.h"
#include "libc/sysv/consts/af.h"
#include "libc/sysv/consts/ipproto.h"
#include "libc/sysv/consts/limits.h"
#include "libc/sysv/consts/sock.h"
#include "libc/thread/thread.h"
#include "libc/x/x.h"
#include "libc/x/xasprintf.h"
#include "net/http/escape.h"
#include "net/http/http.h"
#include "net/http/ip.h"
#include "net/http/url.h"
#include "third_party/lua/lauxlib.h"
#include "third_party/lua/lua.h"
#include "third_party/mbedtls3/include/mbedtls/ctr_drbg.h"
#include "third_party/mbedtls3/include/mbedtls/error.h"
#include "third_party/mbedtls3/include/mbedtls/ssl.h"
#include "third_party/mbedtls3/include/mbedtls/x509.h"
#include "third_party/mbedtls3/include/mbedtls/net_sockets.h"
#include "third_party/musl/netdb.h"
#include "net/https3/https3.h"

// Global state for SSL client (config is shared, contexts are per-connection)
static pthread_mutex_t g_ssl_mu = PTHREAD_MUTEX_INITIALIZER;
static mbedtls_ssl_config confcli;
static mbedtls_ctr_drbg_context rngcli;

// TLS I/O structure
struct TlsBio {
  int fd;
  size_t a;
  size_t b;
  int c;
  char buf[1400];
};

// Buffer for response data
struct Buffer {
  size_t n, c;
  char *p;
};

// Shared state structure (minimal version)
struct SharedState {
  struct {
    atomic_int sslhandshakes;
    atomic_int sslverifyfailed;
  } c;
};

static struct SharedState g_shared;
static struct SharedState *shared = &g_shared;

// Configuration
static const char *brand = "cosmo-fetch/1.0";
static struct timeval timeout = {.tv_sec = 60};
static bool sslinitialized;
static bool unsecure;
static bool evadedragnetsurveillance;
static bool logmessages;
static bool logbodies;

// Logging macros are provided by libc/log/log.h

// I/O macros
#define READ read
#define WRITE write

// Forward declarations
static void LuaPushHeaders(lua_State *, struct HttpMessage *, const char *);
static void LogMessage(const char *, const char *, size_t);
static void LogBody(const char *, const char *, size_t);
// DescribeSslVerifyFailure is declared in net/https/https.h
static int TlsSend(void *, const unsigned char *, size_t);
static int TlsRecvImpl(void *, unsigned char *, size_t, uint32_t);
static void TlsInit(void);
static void LockInc(atomic_int *);

// Helper functions
static void LockInc(atomic_int *p) {
  atomic_fetch_add(p, 1);
}

static bool IsRepeatable(const char *s, size_t n) {
  int h;
  if ((h = GetHttpHeader(s, n)) != -1) {
    return kHttpRepeatable[h];
  }
  return false;
}

static void LuaPushHeaders(lua_State *L, struct HttpMessage *msg,
                           const char *buf) {
  size_t i;
  const char *k, *v;
  size_t kn, vn;
  lua_newtable(L);
  for (i = 0; i < kHttpHeadersMax; ++i) {
    if (!msg->headers[i].a)
      continue;
    k = GetHttpHeaderName(i);
    kn = strlen(k);
    v = buf + msg->headers[i].a;
    vn = msg->headers[i].b - msg->headers[i].a;
    if (IsRepeatable(k, kn)) {
      lua_pushlstring(L, k, kn);
      lua_rawget(L, -2);
      if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        lua_newtable(L);
        lua_pushlstring(L, v, vn);
        lua_rawseti(L, -2, 1);
        lua_pushlstring(L, k, kn);
        lua_pushvalue(L, -2);
        lua_rawset(L, -4);
      } else {
        lua_pushlstring(L, v, vn);
        lua_rawseti(L, -2, lua_rawlen(L, -2) + 1);
      }
      lua_pop(L, 1);
    } else {
      lua_pushlstring(L, k, kn);
      lua_pushlstring(L, v, vn);
      lua_rawset(L, -3);
    }
  }
  for (i = 0; i < msg->xheaders.n; ++i) {
    k = buf + msg->xheaders.p[i].k.a;
    kn = msg->xheaders.p[i].k.b - msg->xheaders.p[i].k.a;
    v = buf + msg->xheaders.p[i].v.a;
    vn = msg->xheaders.p[i].v.b - msg->xheaders.p[i].v.a;
    if (IsRepeatable(k, kn)) {
      lua_pushlstring(L, k, kn);
      lua_rawget(L, -2);
      if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        lua_newtable(L);
        lua_pushlstring(L, v, vn);
        lua_rawseti(L, -2, 1);
        lua_pushlstring(L, k, kn);
        lua_pushvalue(L, -2);
        lua_rawset(L, -4);
      } else {
        lua_pushlstring(L, v, vn);
        lua_rawseti(L, -2, lua_rawlen(L, -2) + 1);
      }
      lua_pop(L, 1);
    } else {
      lua_pushlstring(L, k, kn);
      lua_pushlstring(L, v, vn);
      lua_rawset(L, -3);
    }
  }
}

static void LogMessage(const char *prefix, const char *msg, size_t len) {
  // No-op in standalone version
  (void)prefix;
  (void)msg;
  (void)len;
}

static void LogBody(const char *prefix, const char *body, size_t len) {
  // No-op in standalone version
  (void)prefix;
  (void)body;
  (void)len;
}

// DescribeSslVerifyFailure is provided by net/https/describesslverifyfailure.c

static int TlsSend(void *ctx, const unsigned char *buf, size_t len) {
  struct TlsBio *bio = ctx;
  ssize_t rc;
  if ((rc = write(bio->fd, buf, len)) == -1) {
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      return MBEDTLS_ERR_SSL_WANT_WRITE;
    }
    return MBEDTLS_ERR_NET_SEND_FAILED;
  }
  return rc;
}

static int TlsRecvImpl(void *ctx, unsigned char *buf, size_t len,
                       uint32_t timeout_ms) {
  struct TlsBio *bio = ctx;
  ssize_t rc;
  size_t got;

  // Try to satisfy from buffer
  if (bio->c != -1 && bio->a < bio->b) {
    got = bio->b - bio->a;
    if (got > len)
      got = len;
    memcpy(buf, bio->buf + bio->a, got);
    bio->a += got;
    return got;
  }

  // Read from socket
  if ((rc = read(bio->fd, buf, len)) == -1) {
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      return MBEDTLS_ERR_SSL_WANT_READ;
    }
    return MBEDTLS_ERR_NET_RECV_FAILED;
  }
  if (rc == 0) {
    return MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY;
  }
  return rc;
}

static void TlsInit(void) {
  int rc;

  pthread_mutex_lock(&g_ssl_mu);
  if (sslinitialized) {
    pthread_mutex_unlock(&g_ssl_mu);
    return;
  }

  mbedtls_ssl_config_init(&confcli);
  InitializeRng(&rngcli);  // Uses arc4random - fork-safe

  if ((rc = mbedtls_ssl_config_defaults(
           &confcli, MBEDTLS_SSL_IS_CLIENT, MBEDTLS_SSL_TRANSPORT_STREAM,
           MBEDTLS_SSL_PRESET_DEFAULT)) != 0) {
    WARNF("mbedtls_ssl_config_defaults failed: %d", rc);
    goto fail;
  }

  mbedtls_ssl_conf_ca_chain(&confcli, GetSslRoots(), 0);
  mbedtls_ssl_conf_authmode(&confcli, MBEDTLS_SSL_VERIFY_REQUIRED);
  mbedtls_ssl_conf_rng(&confcli, mbedtls_ctr_drbg_random, &rngcli);
  // behavior parity with the previous Mbed TLS 2.26 client, and some
  // TLS 1.2 servers (including redbean's) reject Mbed TLS 3.6's
  // TLS 1.3 hybrid hello; enabling 1.3 is a deliberate follow-up
  mbedtls_ssl_conf_max_tls_version(&confcli, MBEDTLS_SSL_VERSION_TLS1_2);

  sslinitialized = true;
  pthread_mutex_unlock(&g_ssl_mu);
  return;

fail:
  mbedtls_ctr_drbg_free(&rngcli);
  mbedtls_ssl_config_free(&confcli);
  pthread_mutex_unlock(&g_ssl_mu);
}

// Reset TLS state after fork so child processes get fresh entropy/DRBG
// Called automatically by Fetch()/FetchStream() when the pid changes
// lfetch.c needs its own version due to mutex
static void LuaResetFetchTlsState(void) {
  pthread_mutex_lock(&g_ssl_mu);
  if (sslinitialized) {
    mbedtls_ctr_drbg_free(&rngcli);
    mbedtls_ssl_config_free(&confcli);
    sslinitialized = false;
  }
  pthread_mutex_unlock(&g_ssl_mu);
}
#define HAVE_LUA_RESET_FETCH_TLS_STATE

// Include the actual Fetch implementation
#include "tool/net/fetch.inc"

// ============================================================================
// FetchStream: Streaming HTTP fetch that returns a reader object
// ============================================================================

#define FETCH_READER_MT "cosmo.FetchReader"

typedef struct FetchReader {
  int sock;
  bool closed;
  bool usingssl;
  bool stream_complete;     // true when body is fully read (return nil on next read)
  int body_state;           // kHttpClientStateBody/Lengthed/Chunked
  size_t content_length;    // for lengthed bodies
  size_t bytes_read;        // body bytes returned so far
  struct HttpUnchunker u;   // chunked encoding state
  struct Buffer buf;        // read buffer
  size_t buf_pos;           // current read position in buffer (body data)
  struct Buffer line;       // read_until() carry-over of undelivered bytes
  size_t line_pos;          // consumed prefix of the carry-over buffer
#ifndef UNSECURE
  mbedtls_ssl_context *sslctx;  // heap-allocated, owned by reader
  struct TlsBio *bio;
#endif
} FetchReader;

static FetchReader *CheckFetchReader(lua_State *L) {
  return (FetchReader *)luaL_checkudata(L, 1, FETCH_READER_MT);
}

static void FetchReaderClose(FetchReader *r) {
  if (r->closed) return;
  r->closed = true;
#ifndef UNSECURE
  if (r->sslctx) {
    mbedtls_ssl_free(r->sslctx);
    free(r->sslctx);
    r->sslctx = NULL;
  }
  if (r->bio) {
    free(r->bio);
    r->bio = NULL;
  }
#endif
  if (r->sock >= 0) {
    close(r->sock);
    r->sock = -1;
  }
  free(r->buf.p);
  r->buf.p = NULL;
  r->buf.n = 0;
  r->buf.c = 0;
  free(r->line.p);
  r->line.p = NULL;
  r->line.n = 0;
  r->line.c = 0;
  r->line_pos = 0;
}

// Produces the next decoded body span. This is the read() logic of
// old, factored out so read() and read_until() share one copy of the
// buffered-overshoot, unchunk, length-clamp, EOF, and error handling
// (and their exact state transitions and error strings). Returns 1
// with *data/*len set (pointing into r->buf or scratch, valid until
// the next call), 0 on EOF, or -1 with *err set (a string literal, or
// errbuf which the caller provides for formatted messages). Loops
// internally so chunk framing arriving without payload never surfaces
// as an empty span.
static int FetchReaderNext(FetchReader *r, char *scratch, size_t scratchn,
                           char *errbuf, size_t errbufn, const char **data,
                           size_t *len, const char **err) {
  ssize_t rc;

  // Check if stream was already completed (EOF)
  if (r->stream_complete) {
    return 0;
  }

  // For lengthed bodies, check if we already got everything
  if (r->body_state == kHttpClientStateBodyLengthed &&
      r->bytes_read >= r->content_length) {
    return 0;
  }

  // First, serve any data already in the buffer from header overshoot
  if (r->buf_pos < r->buf.n) {
    size_t avail = r->buf.n - r->buf_pos;
    if (r->body_state == kHttpClientStateBodyChunked) {
      // Run unchunker on buffered data
      // Reset i/j for fresh buffer (state machine state in t/m persists)
      r->u.i = 0;
      r->u.j = 0;
      size_t paylen = 0;
      int uc = Unchunk(&r->u, r->buf.p + r->buf_pos, avail, &paylen);
      if (uc == -1) {
        *err = "unchunk error";
        return -1;
      }
      // Unchunk writes decoded data in-place; u.j has decoded byte count.
      // paylen is only set when uc>0 (complete), so use u.j always.
      size_t decoded = r->u.j;
      if (uc > 0) {
        // Chunked encoding complete - mark stream as done
        r->stream_complete = true;
        if (decoded > 0) {
          // Return the decoded data; next call reports EOF
          *data = r->buf.p + r->buf_pos;
          *len = decoded;
          r->bytes_read += decoded;
          r->buf_pos = r->buf.n;
          return 1;
        }
        // No data in final chunk, report EOF immediately
        r->buf_pos = r->buf.n;
        return 0;
      }
      if (decoded > 0) {
        *data = r->buf.p + r->buf_pos;
        *len = decoded;
        r->bytes_read += decoded;
        r->buf_pos = r->buf.n;
        return 1;
      }
      // Need more data - fall through to socket read
      r->buf_pos = r->buf.n;
    } else {
      // Non-chunked: return buffered data directly
      if (r->body_state == kHttpClientStateBodyLengthed) {
        size_t remaining = r->content_length - r->bytes_read;
        if (avail > remaining) avail = remaining;
      }
      *data = r->buf.p + r->buf_pos;
      *len = avail;
      r->buf_pos += avail;
      r->bytes_read += avail;
      return 1;
    }
  }

  // Read from socket. Loops so that chunk framing arriving without any
  // payload (e.g. a chunk-size line in its own packet) never surfaces as
  // an empty span: keep reading until payload, EOF, or error.
  for (;;) {
#ifndef UNSECURE
    if (r->usingssl) {
      rc = mbedtls_ssl_read(r->sslctx, (unsigned char *)scratch, scratchn);
      if (rc == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY || rc == 0) {
        // EOF
        if (r->body_state == kHttpClientStateBody) {
          return 0;
        }
        *err = "unexpected EOF";
        return -1;
      }
      if (rc < 0) {
        mbedtls_strerror(rc, errbuf, errbufn);
        *err = errbuf;
        return -1;
      }
    } else
#endif
    {
      rc = READ(r->sock, scratch, scratchn);
      if (rc == 0) {
        // EOF
        if (r->body_state == kHttpClientStateBody) {
          return 0;
        }
        *err = "unexpected EOF";
        return -1;
      }
      if (rc == -1) {
        *err = strerror(errno);
        return -1;
      }
    }

    // Process the data we read
    if (r->body_state == kHttpClientStateBodyChunked) {
      // Reset i/j for fresh buffer (state machine state in t/m persists)
      r->u.i = 0;
      r->u.j = 0;
      size_t paylen = 0;
      int uc = Unchunk(&r->u, scratch, rc, &paylen);
      if (uc == -1) {
        *err = "unchunk error";
        return -1;
      }
      // Unchunk writes decoded data in-place; u.j has decoded byte count.
      // paylen is only set when uc>0 (complete), so use u.j always.
      size_t decoded = r->u.j;
      if (uc > 0) {
        // Chunked encoding complete (final chunk + trailers received)
        r->stream_complete = true;
        if (decoded > 0) {
          // Return the decoded data; next call reports EOF
          *data = scratch;
          *len = decoded;
          r->bytes_read += decoded;
          return 1;
        }
        // No data in final chunk, report EOF immediately
        return 0;
      }
      if (decoded > 0) {
        *data = scratch;
        *len = decoded;
        r->bytes_read += decoded;
        return 1;
      }
      // Chunk framing but no payload data yet; read more
      continue;
    }

    // Non-chunked body
    size_t n = rc;
    if (r->body_state == kHttpClientStateBodyLengthed) {
      size_t remaining = r->content_length - r->bytes_read;
      if (n > remaining) n = remaining;
    }
    *data = scratch;
    *len = n;
    r->bytes_read += n;
    if (r->body_state == kHttpClientStateBodyLengthed &&
        r->bytes_read >= r->content_length) {
      r->stream_complete = true;
    }
    return 1;
  }
}

// Appends bytes to the read_until() carry-over buffer.
static int FetchReaderCarry(FetchReader *r, const char *p, size_t n) {
  char *q;
  size_t c;
  if (r->line.n + n > r->line.c) {
    c = r->line.c ? r->line.c : 4096;
    while (c < r->line.n + n) c *= 2;
    if (!(q = realloc(r->line.p, c))) return -1;
    r->line.p = q;
    r->line.c = c;
  }
  memcpy(r->line.p + r->line.n, p, n);
  r->line.n += n;
  return 0;
}

// reader:read() -> string (chunk), or nil on EOF, or nil,err on error
static int LuaFetchReaderRead(lua_State *L) {
  FetchReader *r = CheckFetchReader(L);
  const char *data;
  const char *err;
  size_t len;
  int rc;
  char scratch[16384];
  char errbuf[300];

  if (r->closed) {
    lua_pushnil(L);
    lua_pushliteral(L, "reader closed");
    return 2;
  }

  // Drain any carry-over a read_until() left behind first, so mixing
  // the two methods never reorders or drops bytes.
  if (r->line_pos < r->line.n) {
    lua_pushlstring(L, r->line.p + r->line_pos, r->line.n - r->line_pos);
    r->line_pos = 0;
    r->line.n = 0;
    return 1;
  }

  rc = FetchReaderNext(r, scratch, sizeof(scratch), errbuf, sizeof(errbuf),
                       &data, &len, &err);
  if (rc > 0) {
    lua_pushlstring(L, data, len);
    return 1;
  }
  if (rc == 0) {
    lua_pushnil(L);
    return 1;
  }
  lua_pushnil(L);
  lua_pushstring(L, err);
  return 2;
}

// reader:read_until(delim) -> string (bytes before delim, consuming
// it), the unterminated remainder at EOF, nil at EOF, or nil,err on
// error. The delimiter may be multiple bytes and is never included in
// the result. Buffering lives here in C, so consumers iterating lines
// don't pay a Lua-side buffer rebuild per arriving chunk.
static int LuaFetchReaderReadUntil(lua_State *L) {
  FetchReader *r = CheckFetchReader(L);
  const char *data;
  const char *err;
  const char *hit;
  size_t len, dn;
  const char *d;
  int rc;
  char scratch[16384];
  char errbuf[300];

  d = luaL_checklstring(L, 2, &dn);
  luaL_argcheck(L, dn >= 1, 2, "delimiter must be non-empty");

  if (r->closed) {
    lua_pushnil(L);
    lua_pushliteral(L, "reader closed");
    return 2;
  }

  for (;;) {
    // Serve from the carry-over buffer if it holds a delimiter
    if (r->line.n - r->line_pos >= dn &&
        (hit = memmem(r->line.p + r->line_pos, r->line.n - r->line_pos, d,
                      dn))) {
      lua_pushlstring(L, r->line.p + r->line_pos,
                      hit - (r->line.p + r->line_pos));
      r->line_pos = (hit - r->line.p) + dn;
      return 1;
    }

    // Compact the consumed prefix before buffering more
    if (r->line_pos) {
      memmove(r->line.p, r->line.p + r->line_pos, r->line.n - r->line_pos);
      r->line.n -= r->line_pos;
      r->line_pos = 0;
    }

    rc = FetchReaderNext(r, scratch, sizeof(scratch), errbuf, sizeof(errbuf),
                         &data, &len, &err);
    if (rc < 0) {
      // Error takes precedence; the carry-over stays buffered for a
      // later read()/read_until() to drain.
      lua_pushnil(L);
      lua_pushstring(L, err);
      return 2;
    }
    if (rc == 0) {
      // EOF: yield the unterminated remainder once, then nil
      if (r->line.n) {
        lua_pushlstring(L, r->line.p, r->line.n);
        r->line.n = 0;
        return 1;
      }
      lua_pushnil(L);
      return 1;
    }
    if (FetchReaderCarry(r, data, len) == -1) {
      lua_pushnil(L);
      lua_pushliteral(L, "out of memory");
      return 2;
    }
  }
}

// reader:close()
static int LuaFetchReaderCloseMethod(lua_State *L) {
  FetchReader *r = CheckFetchReader(L);
  FetchReaderClose(r);
  return 0;
}

// __gc metamethod
static int LuaFetchReaderGc(lua_State *L) {
  FetchReader *r = (FetchReader *)luaL_checkudata(L, 1, FETCH_READER_MT);
  FetchReaderClose(r);
  return 0;
}

// __tostring metamethod
static int LuaFetchReaderTostring(lua_State *L) {
  FetchReader *r = CheckFetchReader(L);
  if (r->closed) {
    lua_pushliteral(L, "FetchReader(closed)");
  } else {
    lua_pushfstring(L, "FetchReader(%s)", r->usingssl ? "ssl" : "http");
  }
  return 1;
}

static const luaL_Reg kFetchReaderMethods[] = {
    {"read", LuaFetchReaderRead},
    {"read_until", LuaFetchReaderReadUntil},
    {"close", LuaFetchReaderCloseMethod},
    {0},
};

void LuaInitFetchReader(lua_State *L) {
  luaL_newmetatable(L, FETCH_READER_MT);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  lua_pushcfunction(L, LuaFetchReaderGc);
  lua_setfield(L, -2, "__gc");
  lua_pushcfunction(L, LuaFetchReaderTostring);
  lua_setfield(L, -2, "__tostring");
  luaL_setfuncs(L, kFetchReaderMethods, 0);
  lua_pop(L, 1);
}

// FetchStream(url, opts) -> status, headers, reader, url
// Shares all setup with Fetch but returns a reader instead of buffering body.
int LuaFetchStream(lua_State *L) {
#define ssl nope
  ssize_t rc;
  bool usingssl;
  uint32_t ip;
  struct Url url;
  struct Url proxyurl;
  int t, ret, sock = -1, hdridx;
  const char *host, *port;
  const char *proxyhost = 0, *proxyport = 0;
  const char *proxyarg = 0;
  size_t proxyarglen = 0;
  char *proxyauthhdr = 0;
  bool proxyunix = false;
  char *proxysockpath = NULL;
  char *request;
  struct TlsBio *bio;
  mbedtls_ssl_context *sslctx = NULL;
  struct addrinfo *addr;
  struct Buffer inbuf;
  struct HttpMessage msg;
  const char *urlarg, *body, *method;
  char *conlenhdr = "";
  char *headers = 0;
  const char *hosthdr = 0;
  const char *agenthdr = brand;
  const char *key, *val, *hdr;
  size_t keylen, vallen;
  size_t urlarglen, requestlen, paylen, bodylen;
  size_t i, g, hdrsize;
  char canmethod[9] = {0};
  uint64_t imethod;
  int numredirects = 0, maxredirects = 5;
  bool followredirect = true;
  bool allowprivate = false;
  size_t maxresponse = 100 * 1024 * 1024;
  struct timeval fetchtimeout = timeout;   // local copy, may be overridden
  struct addrinfo hints = {.ai_family = AF_INET,
                           .ai_socktype = SOCK_STREAM,
                           .ai_protocol = IPPROTO_TCP,
                           .ai_flags = AI_NUMERICSERV};

  (void)ret;
  (void)usingssl;

  // ---- Parse arguments (same as LuaFetch) ----
  urlarg = luaL_checklstring(L, 1, &urlarglen);
  if (lua_istable(L, 2)) {
    lua_settop(L, 2);
    lua_getfield(L, 2, "body");
    body = luaL_optlstring(L, -1, "", &bodylen);
    lua_getfield(L, 2, "method");
    method = luaL_optstring(L, -1, "GET");
    if ((imethod = ParseHttpMethod(method, -1))) {
      WRITE64LE(canmethod, imethod);
      method = canmethod;
    } else {
      return LuaFetchError(L, "protocol", "bad method");
    }
    lua_getfield(L, 2, "followredirect");
    if (lua_isboolean(L, -1))
      followredirect = lua_toboolean(L, -1);
    lua_getfield(L, 2, "allowprivate");
    if (lua_isboolean(L, -1))
      allowprivate = lua_toboolean(L, -1);
    lua_getfield(L, 2, "maxredirects");
    maxredirects = luaL_optinteger(L, -1, maxredirects);
    lua_getfield(L, 2, "numredirects");
    numredirects = luaL_optinteger(L, -1, numredirects);
    lua_getfield(L, 2, "maxresponse");
    if (lua_isinteger(L, -1)) {
      lua_Integer mr = lua_tointeger(L, -1);
      if (mr < 0)
        return luaL_argerror(L, 2, "maxresponse must be >= 0");
      maxresponse = (size_t)mr;
    }
    lua_getfield(L, 2, "timeout");
    if (lua_isinteger(L, -1)) {
      // timeout=0 (or absent) keeps the default; there is no "infinite" option
      int timeout_sec = lua_tointeger(L, -1);
      if (timeout_sec > 0) {
        fetchtimeout.tv_sec = timeout_sec;
        fetchtimeout.tv_usec = 0;
      }
    } else if (lua_isnumber(L, -1)) {
      // timeout=0.0 (or absent) keeps the default; there is no "infinite" option
      double timeout_val = lua_tonumber(L, -1);
      if (timeout_val > 0) {
        fetchtimeout.tv_sec = (int64_t)timeout_val;
        fetchtimeout.tv_usec =
            (int64_t)((timeout_val - (int64_t)timeout_val) * 1e6);
      }
    }
    // Streaming always disables keepalive
    lua_getfield(L, 2, "headers");
    if (!lua_isnil(L, -1)) {
      if (!lua_istable(L, -1))
        return luaL_argerror(L, 2, "invalid headers value; table expected");
      lua_pushnil(L);
      while (lua_next(L, -2)) {
        if (lua_type(L, -2) == LUA_TSTRING) {
          key = lua_tolstring(L, -2, &keylen);
          if (!IsValidHttpToken(key, keylen))
            return LuaFetchError(L, "protocol", "invalid header name: %s", key);
          val = lua_tolstring(L, -1, &vallen);
          if (!(hdr = gc(EncodeHttpHeaderValue(val, vallen, 0))))
            return LuaFetchError(L, "protocol",
                                 "invalid header %s value encoding", key);
          if ((hdridx = GetHttpHeader(key, keylen)) == -1 ||
              hdridx != kHttpContentLength) {
            if (hdridx == kHttpUserAgent) {
              agenthdr = hdr;
            } else if (hdridx == kHttpHost) {
              hosthdr = hdr;
            } else if (hdridx == kHttpConnection) {
              // Streaming always uses Connection: close; ignore user value
            } else {
              appendd(&headers, key, keylen);
              appendw(&headers, READ16LE(": "));
              appends(&headers, hdr);
              appendw(&headers, READ16LE("\r\n"));
            }
          }
        }
        lua_pop(L, 1);
      }
    }
    if (headers)
      gc(headers);
    lua_getfield(L, 2, "proxy");
    if (!lua_isnil(L, -1)) {
      if (!lua_isstring(L, -1))
        return LuaFetchError(L, "proxy", "bad proxy; string expected");
      proxyarg = lua_tolstring(L, -1, &proxyarglen);
    }
    lua_settop(L, 2);
  } else if (lua_isnoneornil(L, 2)) {
    body = "";
    bodylen = 0;
    method = "GET";
  } else {
    body = luaL_checklstring(L, 2, &bodylen);
    method = "POST";
  }
  imethod = ParseHttpMethod(method, -1);
  if (bodylen > 0 ||
      !(imethod == kHttpGet || imethod == kHttpHead || imethod == kHttpTrace ||
        imethod == kHttpDelete || imethod == kHttpConnect)) {
    conlenhdr = gc(xasprintf("Content-Length: %zu\r\n", bodylen));
  }

  // ---- Parse URL ----
  gc(ParseUrl(urlarg, urlarglen, &url, true));
  gc(url.params.p);

  usingssl = false;
  if (url.scheme.n) {
#ifndef UNSECURE
    if (!unsecure && url.scheme.n == 5 &&
        !memcasecmp(url.scheme.p, "https", 5)) {
      usingssl = true;
    } else
#endif
        if (!(url.scheme.n == 4 && !memcasecmp(url.scheme.p, "http", 4))) {
      return LuaFetchError(L, "protocol", "bad scheme");
    }
  }

#ifndef UNSECURE
  if (usingssl) {
    if (sslinitialized && getpid() != luafetchsslpid)
      LuaResetFetchTlsState();  // forked child needs fresh entropy/DRBG
    if (!sslinitialized)
      TlsInit();
    luafetchsslpid = getpid();
  }
#endif

  // ---- Parse proxy ----
  if (!proxyarg) {
    proxyarg = getenv("http_proxy");
    if (!proxyarg)
      proxyarg = getenv("HTTP_PROXY");
    if (proxyarg)
      proxyarglen = strlen(proxyarg);
  }
  if (proxyarg && proxyarglen) {
    gc(ParseUrl(proxyarg, proxyarglen, &proxyurl, true));
    gc(proxyurl.params.p);
    // Check for unix:// scheme
    if (proxyurl.scheme.n == 4 &&
        !memcasecmp(proxyurl.scheme.p, "unix", 4)) {
      proxyunix = true;
      // Path is in url path, e.g. unix:///tmp/proxy.sock
      if (!proxyurl.path.n) {
        return LuaFetchError(L, "proxy", "bad unix proxy; missing socket path");
      }
      if (proxyurl.path.n >= sizeof(((struct sockaddr_un *)0)->sun_path)) {
        return LuaFetchError(L, "proxy",
                             "bad unix proxy; socket path too long (max %zu)",
                             sizeof(((struct sockaddr_un *)0)->sun_path) - 1);
      }
      if (!IsReasonablePath(proxyurl.path.p, proxyurl.path.n)) {
        return LuaFetchError(L, "proxy",
                             "bad unix proxy; path contains . or .. segments");
      }
      proxysockpath = gc(strndup(proxyurl.path.p, proxyurl.path.n));
      DEBUGF("(ftch) using unix proxy %s", proxysockpath);
    } else if (proxyurl.scheme.n == 4 &&
               !memcasecmp(proxyurl.scheme.p, "http", 4)) {
      if (!proxyurl.host.n)
        return LuaFetchError(L, "proxy", "bad proxy; missing host");
      proxyhost = gc(strndup(proxyurl.host.p, proxyurl.host.n));
      proxyport = proxyurl.port.n
                      ? gc(strndup(proxyurl.port.p, proxyurl.port.n))
                      : "80";
      if (!IsAcceptableHost(proxyhost, -1))
        return LuaFetchError(L, "proxy", "bad proxy; invalid host");
      if (!IsAcceptablePort(proxyport, -1))
        return LuaFetchError(L, "proxy", "bad proxy; invalid port");
      if (proxyurl.user.n) {
        char *creds = gc(xasprintf("%.*s:%.*s",
                                   (int)proxyurl.user.n, proxyurl.user.p,
                                   (int)proxyurl.pass.n, proxyurl.pass.p));
        char *b64 = gc(EncodeBase64(creds, strlen(creds), 0));
        if (b64)
          proxyauthhdr = gc(xasprintf("Proxy-Authorization: Basic %s\r\n", b64));
      }
    } else {
      return LuaFetchError(
          L, "proxy", "bad proxy scheme; only http:// and unix:// supported");
    }
  }

  if (url.host.n) {
    host = gc(strndup(url.host.p, url.host.n));
    if (url.port.n) {
      port = gc(strndup(url.port.p, url.port.n));
#ifndef UNSECURE
    } else if (usingssl) {
      port = "443";
#endif
    } else {
      port = "80";
    }
  } else if ((ip = ParseIp(urlarg, -1)) != -1) {
    host = urlarg;
    port = "80";
  } else {
    return LuaFetchError(L, "protocol", "invalid host");
  }
  if (!IsAcceptableHost(host, -1))
    return LuaFetchError(L, "protocol", "invalid host");
  if (!IsAcceptablePort(port, -1))
    return LuaFetchError(L, "protocol", "invalid port");
  if (!hosthdr)
    hosthdr = gc(xasprintf("%s:%s", host, port));

  url.fragment.p = 0, url.fragment.n = 0;
  url.user.p = 0, url.user.n = 0;
  url.pass.p = 0, url.pass.n = 0;
  if ((!proxyhost && !proxyunix) || usingssl) {
    url.scheme.p = 0, url.scheme.n = 0;
    url.host.p = 0, url.host.n = 0;
    url.port.p = 0, url.port.n = 0;
  }
  if (!url.path.n || url.path.p[0] != '/') {
    void *p = gc(xmalloc(1 + url.path.n));
    mempcpy(mempcpy(p, "/", 1), url.path.p, url.path.n);
    url.path.p = p;
    ++url.path.n;
  }

  // ---- Build HTTP request ----
  request = 0;
  appendf(&request,
          "%s %s HTTP/1.1\r\n"
          "Host: %s\r\n"
          "Connection: close\r\n"
          "User-Agent: %s\r\n"
          "%s%s%s"
          "\r\n",
          method, gc(EncodeUrl(&url, 0)), hosthdr,
          agenthdr, conlenhdr,
          (proxyhost && !usingssl && proxyauthhdr) ? proxyauthhdr : "",
          headers ? headers : "");
  appendd(&request, body, bodylen);
  requestlen = appendz(request).i;
  gc(request);

  // ---- Connect ----
  if (proxyunix) {
    // Connect to proxy via Unix domain socket.
    // Same HTTP proxy semantics as TCP (absolute URLs, CONNECT for HTTPS).
    struct sockaddr_un addr_un = {.sun_family = AF_UNIX};
    strlcpy(addr_un.sun_path, proxysockpath, sizeof(addr_un.sun_path));
    if ((sock = socket(AF_UNIX, SOCK_STREAM, 0)) == -1)
      return LuaFetchError(L, "proxy", "socket(AF_UNIX) failed: %s",
                           strerror(errno));
    if (connect(sock, (struct sockaddr *)&addr_un, sizeof(addr_un)) == -1) {
      close(sock);
      return LuaFetchError(L, "proxy", "connect(%s) failed: %s", proxysockpath,
                           strerror(errno));
    }
  } else {
    const char *connecthost = proxyhost ? proxyhost : host;
    const char *connectport = proxyhost ? proxyport : port;
    if ((rc = getaddrinfo(connecthost, connectport, &hints, &addr)) != 0)
      return LuaFetchError(L, "dns", "getaddrinfo(%s:%s) error: EAI_%s %s",
                           connecthost, connectport, gai_strerror(rc),
                           strerror(errno));
    ip = ntohl(((struct sockaddr_in *)addr->ai_addr)->sin_addr.s_addr);
    // Skip SSRF check for proxy connections (proxy handles target
    // resolution) and when the caller opted out with allowprivate=true
    // (the opt-out covers every hop of a redirect chain).
    if (!proxyhost && !allowprivate && !IsPublicIp(ip)) {
      freeaddrinfo(addr);
      return LuaFetchError(
          L, "blocked", "request to private network blocked (SSRF protection)");
    }
    if ((sock = GoodSocket(addr->ai_family, addr->ai_socktype,
                           addr->ai_protocol, false, &fetchtimeout)) == -1) {
      freeaddrinfo(addr);
      return LuaFetchError(L, "connect", "socket error: %s", strerror(errno));
    }
    rc = connect(sock, addr->ai_addr, addr->ai_addrlen);
    freeaddrinfo(addr);
    if (rc == -1) {
      close(sock);
      return LuaFetchError(
          L,
          (errno == EINPROGRESS || errno == EAGAIN || errno == ETIMEDOUT)
              ? "timeout"
              : "connect",
          "connect error: %s", strerror(errno));
    }
  }

  (void)bio;
#ifndef UNSECURE
  // ---- HTTPS proxy CONNECT tunnel ----
  if (usingssl && (proxyhost || proxyunix)) {
    char *connectreq = 0;
    struct Buffer connectbuf = {0};
    struct HttpMessage connectmsg;
    ssize_t connectrc;
    appendf(&connectreq,
            "CONNECT %s:%s HTTP/1.1\r\n"
            "Host: %s:%s\r\n"
            "User-Agent: %s\r\n"
            "Proxy-Connection: keep-alive\r\n"
            "%s"
            "\r\n",
            host, port, host, port, agenthdr,
            proxyauthhdr ? proxyauthhdr : "");
    size_t connectreqlen = appendz(connectreq).i;
    gc(connectreq);
    for (i = 0; i < connectreqlen; i += connectrc) {
      if ((connectrc = WRITE(sock, connectreq + i, connectreqlen - i)) <= 0) {
        close(sock);
        return LuaFetchError(L, "proxy", "proxy CONNECT write error: %s",
                             strerror(errno));
      }
    }
    // Read and parse proxy CONNECT response properly
    InitHttpMessage(&connectmsg, kHttpResponse);
    for (;;) {
      if (connectbuf.n == connectbuf.c) {
        char *newp;
        connectbuf.c += 256;
        if (connectbuf.c > 8192) {
          DestroyHttpMessage(&connectmsg);
          free(connectbuf.p);
          close(sock);
          return LuaFetchError(L, "proxy", "proxy CONNECT response too large");
        }
        if (!(newp = realloc(connectbuf.p, connectbuf.c))) {
          DestroyHttpMessage(&connectmsg);
          free(connectbuf.p);
          close(sock);
          return LuaFetchError(L, "proxy", "out of memory");
        }
        connectbuf.p = newp;
      }
      if ((connectrc = READ(sock, connectbuf.p + connectbuf.n,
                            connectbuf.c - connectbuf.n)) <= 0) {
        DestroyHttpMessage(&connectmsg);
        free(connectbuf.p);
        close(sock);
        return LuaFetchError(L, "proxy", "proxy CONNECT read error: %s",
                             strerror(errno));
      }
      connectbuf.n += connectrc;
      rc = ParseHttpMessage(&connectmsg, connectbuf.p, connectbuf.n, SHRT_MAX);
      if (rc == -1) {
        DestroyHttpMessage(&connectmsg);
        free(connectbuf.p);
        close(sock);
        return LuaFetchError(L, "proxy", "proxy CONNECT malformed response");
      }
      if (rc > 0) break;  // complete
    }
    if (connectmsg.status != 200) {
      int status = connectmsg.status;
      DestroyHttpMessage(&connectmsg);
      free(connectbuf.p);
      close(sock);
      return LuaFetchError(L, "proxy", "proxy CONNECT failed: HTTP %d", status);
    }
    DestroyHttpMessage(&connectmsg);
    free(connectbuf.p);
  }

  // ---- TLS handshake ----
  bio = NULL;
  if (usingssl) {
    sslctx = malloc(sizeof(*sslctx));
    if (!sslctx) {
      close(sock);
      return LuaFetchError(L, "protocol", "out of memory");
    }
    mbedtls_ssl_init(sslctx);
    if ((ret = mbedtls_ssl_setup(sslctx, &confcli)) != 0) {
      mbedtls_ssl_free(sslctx);
      free(sslctx);
      close(sock);
      return LuaFetchTlsError(L, "tls", "ssl_setup", ret);
    }
    if (!evadedragnetsurveillance)
      mbedtls_ssl_set_hostname(sslctx, host);
    bio = malloc(sizeof(struct TlsBio));
    if (!bio) {
      mbedtls_ssl_free(sslctx);
      free(sslctx);
      close(sock);
      return LuaFetchError(L, "protocol", "out of memory");
    }
    bio->fd = sock;
    bio->a = 0;
    bio->b = 0;
    bio->c = -1;
    mbedtls_ssl_set_bio(sslctx, bio, TlsSend, 0, TlsRecvImpl);
    // Compute handshake deadline from the same timeout used for SO_RCVTIMEO.
    // Uses CLOCK_MONOTONIC so wall-clock jumps don't affect the bound.
    // If no timeout is configured (fetchtimeout.tv_sec == 0), deadline is
    // left as timespec_zero and the check below is skipped (preserving the
    // existing "no timeout" behaviour).
    bool have_handshake_deadline = fetchtimeout.tv_sec > 0;
    struct timespec handshake_deadline = timespec_zero;
    if (have_handshake_deadline) {
      handshake_deadline =
          timespec_add(timespec_mono(), timeval_totimespec(fetchtimeout));
    }
    while ((ret = mbedtls_ssl_handshake(sslctx))) {
      switch (ret) {
        case MBEDTLS_ERR_SSL_WANT_READ:
        case MBEDTLS_ERR_SSL_WANT_WRITE:
          if (have_handshake_deadline &&
              timespec_cmp(timespec_mono(), handshake_deadline) >= 0) {
            free(bio);
            mbedtls_ssl_free(sslctx);
            free(sslctx);
            close(sock);
            return LuaFetchError(L, "timeout", "TLS handshake timed out");
          }
          break;
        case MBEDTLS_ERR_X509_CERT_VERIFY_FAILED:
          goto StreamVerifyFailed;
        default:
          free(bio);
          mbedtls_ssl_free(sslctx);
          free(sslctx);
          close(sock);
          return LuaFetchTlsError(L, "tls", "handshake", ret);
      }
    }
    LockInc(&shared->c.sslhandshakes);
  }
#endif

  // ---- Send request ----
  for (i = 0; i < requestlen; i += rc) {
#ifndef UNSECURE
    if (usingssl) {
      rc = mbedtls_ssl_write(sslctx, (unsigned char *)request + i,
                             requestlen - i);
      if (rc <= 0) {
        if (rc == MBEDTLS_ERR_X509_CERT_VERIFY_FAILED)
          goto StreamVerifyFailed;
        free(bio);
        mbedtls_ssl_free(sslctx);
        free(sslctx);
        close(sock);
        return LuaFetchTlsError(L, "tls", "write", rc);
      }
    } else
#endif
        if ((rc = WRITE(sock, request + i, requestlen - i)) <= 0) {
      close(sock);
      return LuaFetchError(
          L, (errno == EAGAIN || errno == EWOULDBLOCK) ? "timeout" : "connect",
          "write error: %s", strerror(errno));
    }
  }

  // ---- Read headers only ----
  bzero(&inbuf, sizeof(inbuf));
  InitHttpMessage(&msg, kHttpResponse);
  for (hdrsize = paylen = t = 0;;) {
    if (inbuf.n == inbuf.c) {
      char *newp;
      inbuf.c += 1000;
      inbuf.c += inbuf.c >> 1;
      if (inbuf.c > maxresponse) {
        goto StreamCleanupError;
      }
      if (!(newp = realloc(inbuf.p, inbuf.c))) {
        goto StreamCleanupError;
      }
      inbuf.p = newp;
    }
#ifndef UNSECURE
    if (usingssl) {
      if ((rc = mbedtls_ssl_read(sslctx, (unsigned char *)inbuf.p + inbuf.n,
                                 inbuf.c - inbuf.n)) < 0) {
        if (rc == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY) {
          rc = 0;
        } else {
          DestroyHttpMessage(&msg);
          free(inbuf.p);
          free(bio);
          mbedtls_ssl_free(sslctx);
          free(sslctx);
          close(sock);
          if (rc == MBEDTLS_ERR_SSL_WANT_READ)  // SO_RCVTIMEO expired
            return LuaFetchError(L, "timeout", "read timeout");
          return LuaFetchTlsError(L, "tls", "read", rc);
        }
      }
    } else
#endif
        if ((rc = READ(sock, inbuf.p + inbuf.n, inbuf.c - inbuf.n)) == -1) {
      DestroyHttpMessage(&msg);
      free(inbuf.p);
#ifndef UNSECURE
      if (sslctx) { free(bio); mbedtls_ssl_free(sslctx); free(sslctx); }
#endif
      close(sock);
      if (errno == EAGAIN || errno == EWOULDBLOCK)  // SO_RCVTIMEO expired
        return LuaFetchError(L, "timeout", "read timeout");
      return LuaFetchError(L, "connect", "read error: %s", strerror(errno));
    }
    g = rc;
    inbuf.n += g;

    if (!t) {
      // Still parsing headers
      if (!g) {
        goto StreamCleanupError;
      }
      rc = ParseHttpMessage(&msg, inbuf.p, inbuf.n, SHRT_MAX);
      if (rc == -1) {
        goto StreamCleanupError;
      }
      if (rc) {
        hdrsize = rc;
        // Handle 1xx continue
        if (100 <= msg.status && msg.status <= 199) {
          if ((FetchHasHeader(kHttpContentLength) &&
               !FetchHeaderEqualCase(kHttpContentLength, "0")) ||
              (FetchHasHeader(kHttpTransferEncoding) &&
               !FetchHeaderEqualCase(kHttpTransferEncoding, "identity"))) {
            goto StreamCleanupError;
          }
          DestroyHttpMessage(&msg);
          InitHttpMessage(&msg, kHttpResponse);
          memmove(inbuf.p, inbuf.p + hdrsize, inbuf.n - hdrsize);
          inbuf.n -= hdrsize;
          continue;
        }
        // Handle no-body responses
        if (msg.status == 204 || msg.status == 304) {
          // Return status, headers, and a closed reader (no body)
          goto StreamFinishNoBody;
        }
        // Handle redirects before streaming
        if (followredirect && FetchHasHeader(kHttpLocation) &&
            (msg.status == 301 || msg.status == 308 ||
             msg.status == 302 || msg.status == 307 ||
             msg.status == 303) &&
            numredirects < maxredirects) {
          bool crossorigin;
          // Clean up and follow redirect
          if (msg.status == 303) {
            body = "";
            bodylen = 0;
            method = "GET";
          }
          lua_settop(L, 2);  // normalize stack to [url, opts]
          // Parse redirect URL
          gc(ParseUrl(FetchHeaderData(kHttpLocation),
                      FetchHeaderLength(kHttpLocation), &url, true));
          free(url.params.p);
#ifndef UNSECURE
          if (usingssl && url.scheme.n == 4 &&
              !memcasecmp(url.scheme.p, "http", 4)) {
            DestroyHttpMessage(&msg);
            free(inbuf.p);
            if (sslctx) { free(bio); mbedtls_ssl_free(sslctx); free(sslctx); }
            close(sock);
            return LuaFetchError(L, "blocked",
                                 "refusing HTTPS to HTTP redirect downgrade");
          }
#endif
          crossorigin = url.host.n && url.scheme.n;
          // push the redirect target URL (stack slot 3)
          if (crossorigin) {
            lua_pushlstring(L, FetchHeaderData(kHttpLocation),
                            FetchHeaderLength(kHttpLocation));
          } else {
            gc(ParseUrl(urlarg, urlarglen, &url, true));
            free(url.params.p);
            url.fragment.p = 0, url.fragment.n = 0;
            url.user.p = 0, url.user.n = 0;
            url.pass.p = 0, url.pass.n = 0;
            if (FetchHeaderLength(kHttpLocation) > 0 &&
                FetchHeaderData(kHttpLocation)[0] == '/') {
              url.path.n = 0;
            } else {
              while (url.path.n > 0 && url.path.p[url.path.n - 1] != '/')
                --url.path.n;
            }
            url.path.p = gc(xasprintf("%.*s%.*s", url.path.n, url.path.p,
                                      FetchHeaderLength(kHttpLocation),
                                      FetchHeaderData(kHttpLocation)));
            url.path.n = strlen(url.path.p);
            lua_pushstring(L, gc(EncodeUrl(&url, 0)));
          }
          // build a fresh options table (stack slot 4) for the recursive
          // call; the caller's options table is read-only, never modified
          lua_createtable(L, 0, 9);
          lua_pushlstring(L, body, bodylen);
          lua_setfield(L, 4, "body");
          lua_pushstring(L, method);
          lua_setfield(L, 4, "method");
          lua_pushinteger(L, numredirects + 1);
          lua_setfield(L, 4, "numredirects");
          lua_pushinteger(L, maxredirects);
          lua_setfield(L, 4, "maxredirects");
          lua_pushboolean(L, followredirect);
          lua_setfield(L, 4, "followredirect");
          lua_pushboolean(L, allowprivate);
          lua_setfield(L, 4, "allowprivate");
          lua_pushinteger(L, (lua_Integer)maxresponse);
          lua_setfield(L, 4, "maxresponse");
          lua_pushnumber(L, fetchtimeout.tv_sec + fetchtimeout.tv_usec * 1e-6);
          lua_setfield(L, 4, "timeout");
          if (lua_istable(L, 2)) {
            lua_getfield(L, 2, "proxy");
            lua_setfield(L, 4, "proxy");
            lua_getfield(L, 2, "headers");  // stack slot 5
            if (lua_istable(L, 5)) {
              // copy the headers table, stripping Authorization and Cookie
              // on cross-origin redirect to prevent credential leakage;
              // the caller's headers table is left untouched
              lua_createtable(L, 0, 4);  // stack slot 6
              lua_pushnil(L);
              while (lua_next(L, 5)) {
                // stack: 5=orig, 6=copy, 7=key, 8=val
                if (lua_type(L, 7) == LUA_TSTRING) {
                  key = lua_tostring(L, 7);
                  if (!(crossorigin && (!strcasecmp(key, "authorization") ||
                                        !strcasecmp(key, "cookie")))) {
                    lua_pushvalue(L, 7);
                    lua_pushvalue(L, 8);
                    lua_settable(L, 6);
                  }
                }
                lua_pop(L, 1);  // pop the value, keep the key for lua_next
              }
              lua_setfield(L, 4, "headers");
            }
            lua_settop(L, 4);
          }
          lua_replace(L, 2);  // options for the recursive call
          lua_replace(L, 1);  // redirect target URL
          DestroyHttpMessage(&msg);
          free(inbuf.p);
#ifndef UNSECURE
          if (sslctx) { free(bio); mbedtls_ssl_free(sslctx); free(sslctx); }
#endif
          close(sock);
          return LuaFetchStream(L);
        }
        // Determine body transfer mode
        if (FetchHasHeader(kHttpTransferEncoding) &&
            !FetchHeaderEqualCase(kHttpTransferEncoding, "identity")) {
          if (FetchHeaderEqualCase(kHttpTransferEncoding, "chunked")) {
            t = kHttpClientStateBodyChunked;
          } else {
            goto StreamCleanupError;
          }
        } else if (FetchHasHeader(kHttpContentLength)) {
          rc = ParseContentLength(FetchHeaderData(kHttpContentLength),
                                  FetchHeaderLength(kHttpContentLength));
          if (rc == -1)
            goto StreamCleanupError;
          paylen = rc;
          t = kHttpClientStateBodyLengthed;
        } else {
          t = kHttpClientStateBody;
        }
        // Headers parsed - create reader and return
        goto StreamCreateReader;
      }
    } else {
      // We shouldn't reach here - headers loop should break via goto
      goto StreamCleanupError;
    }
  }

StreamCreateReader: {
    // Create the reader userdata FIRST so all resources (sock, ssl, buf) are
    // owned by a GC-managed object before any further allocation-capable Lua
    // call.  If lua_pushinteger / LuaPushHeaders longjmp on OOM, the reader's
    // __gc (FetchReaderClose) will free the fd / mbedtls ctx / buffer rather
    // than leaking them.
    FetchReader *reader = lua_newuserdata(L, sizeof(FetchReader));
    memset(reader, 0, sizeof(FetchReader));
    // Set sock = -1 before luaL_setmetatable so that if the metatable lookup
    // somehow fails and triggers a longjmp the GC won't close fd 0.
    reader->sock = -1;
    luaL_setmetatable(L, FETCH_READER_MT);

    // Transfer all resource ownership to reader NOW, before any Lua alloc call.
    reader->sock = sock;
    reader->usingssl = usingssl;
    reader->body_state = t;
    reader->content_length = paylen;
    reader->bytes_read = 0;

    // Transfer buffer ownership.  Header offsets in msg still point into
    // inbuf.p; LuaPushHeaders below must run before any memmove of inbuf.p.
    reader->buf = inbuf;
    reader->buf_pos = hdrsize;  // body starts after headers

#ifndef UNSECURE
    if (sslctx) {
      // Transfer SSL context ownership to reader.
      reader->sslctx = sslctx;
      reader->bio = bio;
    }
#endif

    // Push status and headers.  These Lua calls may longjmp on OOM, but all
    // resources are now owned by reader's __gc, so nothing leaks.
    // LuaPushHeaders must run before the chunked memmove below (header offsets
    // in msg point into inbuf.p which the memmove would overwrite).
    lua_pushinteger(L, msg.status);
    LuaPushHeaders(L, &msg, inbuf.p);
    DestroyHttpMessage(&msg);

    // Initialize unchunker; shift body data to start of buffer.
    if (t == kHttpClientStateBodyChunked) {
      bzero(&reader->u, sizeof(reader->u));
      if (inbuf.n > hdrsize) {
        size_t body_avail = inbuf.n - hdrsize;
        memmove(inbuf.p, inbuf.p + hdrsize, body_avail);
        reader->buf.n = body_avail;
        reader->buf_pos = 0;
      } else {
        reader->buf.n = 0;
        reader->buf_pos = 0;
      }
    }

    // Stack is now: ..., reader, status, headers
    // Rotate to the expected return order: ..., status, headers, reader
    lua_rotate(L, -3, 2);
    lua_pushlstring(L, urlarg, urlarglen);  // effective URL after redirects

    // Stack: ..., status, headers, reader, url
    // Ownership transferred to reader: inbuf.p, bio, sock, sslctx
    return 4;
  }

StreamFinishNoBody: {
    // Push status and headers before cleanup
    lua_pushinteger(L, msg.status);
    LuaPushHeaders(L, &msg, inbuf.p);
    DestroyHttpMessage(&msg);
    free(inbuf.p);
#ifndef UNSECURE
    if (sslctx) {
      free(bio);
      mbedtls_ssl_free(sslctx);
      free(sslctx);
    }
#endif
    close(sock);

    // Create a completed reader (no body): read() reports clean EOF (nil
    // with no error) rather than a "reader closed" error, since 204/304
    // are successful responses
    FetchReader *reader = lua_newuserdata(L, sizeof(FetchReader));
    memset(reader, 0, sizeof(FetchReader));
    luaL_setmetatable(L, FETCH_READER_MT);
    reader->sock = -1;
    reader->stream_complete = true;
    lua_pushlstring(L, urlarg, urlarglen);  // effective URL after redirects

    // Stack: ..., status, headers, reader, url
    return 4;
  }

StreamCleanupError:
  DestroyHttpMessage(&msg);
  free(inbuf.p);
#ifndef UNSECURE
  if (sslctx) {
    free(bio);
    mbedtls_ssl_free(sslctx);
    free(sslctx);
  }
#endif
  close(sock);
  return LuaFetchError(L, "protocol", "transport error");

#ifndef UNSECURE
StreamVerifyFailed:
  LockInc(&shared->c.sslverifyfailed);
  {
    uint32_t verify_result = mbedtls_ssl_get_verify_result(sslctx);
    free(bio);
    mbedtls_ssl_free(sslctx);
    free(sslctx);
    close(sock);
    return LuaFetchTlsError(L, "tls",
                            gc(DescribeSslVerifyFailure(verify_result)), ret);
  }
#endif
#undef ssl
}

void LuaInitFetch(void) {
  // SSL mutex is now statically initialized, nothing else needed here
  // TlsInit() will be called on first HTTPS request
}
