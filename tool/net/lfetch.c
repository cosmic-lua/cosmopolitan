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
#include "third_party/mbedtls/ctr_drbg.h"
#include "third_party/mbedtls/error.h"
#include "third_party/mbedtls/ssl.h"
#include "third_party/mbedtls/x509.h"
#include "third_party/mbedtls/net_sockets.h"
#include "third_party/musl/netdb.h"
#include "net/https/https.h"

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
static int LuaNilError(lua_State *, const char *, ...);
static int LuaNilTlsError(lua_State *, const char *, int);
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

static int LuaNilError(lua_State *L, const char *fmt, ...) {
  char buf[512];
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(buf, sizeof(buf), fmt, ap);
  va_end(ap);
  lua_pushnil(L);
  lua_pushstring(L, buf);
  return 2;
}

static int LuaNilTlsError(lua_State *L, const char *s, int r) {
  char buf[300];
  mbedtls_strerror(r, buf, sizeof(buf));
  return LuaNilError(L, "%s failed: %s", s, buf);
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

  sslinitialized = true;
  pthread_mutex_unlock(&g_ssl_mu);
  return;

fail:
  mbedtls_ctr_drbg_free(&rngcli);
  mbedtls_ssl_config_free(&confcli);
  pthread_mutex_unlock(&g_ssl_mu);
}

// Reset TLS state after fork so child processes get fresh entropy/DRBG
// Called automatically by Fetch() when resettls=true (the default)
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
}

// reader:read() -> string (chunk), or nil on EOF, or nil,err on error
static int LuaFetchReaderRead(lua_State *L) {
  FetchReader *r = CheckFetchReader(L);
  ssize_t rc;

  if (r->closed) {
    lua_pushnil(L);
    lua_pushliteral(L, "reader closed");
    return 2;
  }

  // Check if stream was already completed (return EOF)
  if (r->stream_complete) {
    lua_pushnil(L);
    return 1;
  }

  // For lengthed bodies, check if we already got everything
  if (r->body_state == kHttpClientStateBodyLengthed &&
      r->bytes_read >= r->content_length) {
    lua_pushnil(L);
    return 1;
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
        lua_pushnil(L);
        lua_pushliteral(L, "unchunk error");
        return 2;
      }
      // Unchunk writes decoded data in-place; u.j has decoded byte count.
      // paylen is only set when uc>0 (complete), so use u.j always.
      size_t decoded = r->u.j;
      if (uc > 0) {
        // Chunked encoding complete - mark stream as done
        r->stream_complete = true;
        if (decoded > 0) {
          // Return the decoded data; next read will return EOF
          lua_pushlstring(L, r->buf.p + r->buf_pos, decoded);
          r->bytes_read += decoded;
          r->buf_pos = r->buf.n;
          return 1;
        }
        // No data in final chunk, return EOF immediately
        r->buf_pos = r->buf.n;
        lua_pushnil(L);
        return 1;
      }
      if (decoded > 0) {
        lua_pushlstring(L, r->buf.p + r->buf_pos, decoded);
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
      lua_pushlstring(L, r->buf.p + r->buf_pos, avail);
      r->buf_pos += avail;
      r->bytes_read += avail;
      return 1;
    }
  }

  // Read from socket
  char readbuf[16384];
#ifndef UNSECURE
  if (r->usingssl) {
    rc = mbedtls_ssl_read(r->sslctx, (unsigned char *)readbuf,
                          sizeof(readbuf));
    if (rc == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY || rc == 0) {
      // EOF
      if (r->body_state == kHttpClientStateBody) {
        lua_pushnil(L);
        return 1;
      }
      lua_pushnil(L);
      lua_pushliteral(L, "unexpected EOF");
      return 2;
    }
    if (rc < 0) {
      char errbuf[300];
      mbedtls_strerror(rc, errbuf, sizeof(errbuf));
      lua_pushnil(L);
      lua_pushstring(L, errbuf);
      return 2;
    }
  } else
#endif
  {
    rc = READ(r->sock, readbuf, sizeof(readbuf));
    if (rc == 0) {
      // EOF
      if (r->body_state == kHttpClientStateBody) {
        lua_pushnil(L);
        return 1;
      }
      lua_pushnil(L);
      lua_pushliteral(L, "unexpected EOF");
      return 2;
    }
    if (rc == -1) {
      lua_pushnil(L);
      lua_pushstring(L, strerror(errno));
      return 2;
    }
  }

  // Process the data we read
  if (r->body_state == kHttpClientStateBodyChunked) {
    // Reset i/j for fresh buffer (state machine state in t/m persists)
    r->u.i = 0;
    r->u.j = 0;
    size_t paylen = 0;
    int uc = Unchunk(&r->u, readbuf, rc, &paylen);
    if (uc == -1) {
      lua_pushnil(L);
      lua_pushliteral(L, "unchunk error");
      return 2;
    }
    // Unchunk writes decoded data in-place; u.j has decoded byte count.
    // paylen is only set when uc>0 (complete), so use u.j always.
    size_t decoded = r->u.j;
    if (uc > 0) {
      // Chunked encoding complete (final chunk + trailers received)
      r->stream_complete = true;
      if (decoded > 0) {
        // Return the decoded data; next read will return EOF
        lua_pushlstring(L, readbuf, decoded);
        r->bytes_read += decoded;
        return 1;
      }
      // No data in final chunk, return EOF immediately
      lua_pushnil(L);
      return 1;
    }
    if (decoded > 0) {
      lua_pushlstring(L, readbuf, decoded);
      r->bytes_read += decoded;
      return 1;
    }
    // Got chunk framing but no payload data yet.
    // NOTE: Returns empty string when chunk framing received but no payload data.
    // Callers should handle empty chunks gracefully (e.g., skip if #chunk == 0).
    // This can occur when chunk headers arrive separately from chunk data.
    lua_pushliteral(L, "");
    return 1;
  }

  // Non-chunked body
  size_t len = rc;
  if (r->body_state == kHttpClientStateBodyLengthed) {
    size_t remaining = r->content_length - r->bytes_read;
    if (len > remaining) len = remaining;
  }
  lua_pushlstring(L, readbuf, len);
  r->bytes_read += len;
  if (r->body_state == kHttpClientStateBodyLengthed &&
      r->bytes_read >= r->content_length) {
    r->stream_complete = true;
  }
  return 1;
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

// FetchStream(url, opts) -> status, headers, reader
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
#ifndef UNSECURE
  bool resettls = true;
#endif
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
      return LuaNilError(L, "bad method");
    }
    lua_getfield(L, 2, "followredirect");
    if (lua_isboolean(L, -1))
      followredirect = lua_toboolean(L, -1);
    lua_getfield(L, 2, "maxredirects");
    maxredirects = luaL_optinteger(L, -1, maxredirects);
    lua_getfield(L, 2, "numredirects");
    numredirects = luaL_optinteger(L, -1, numredirects);
    lua_getfield(L, 2, "maxresponse");
    if (lua_isinteger(L, -1))
      maxresponse = lua_tointeger(L, -1);
    lua_getfield(L, 2, "timeout");
    if (lua_isinteger(L, -1)) {
      int timeout_sec = lua_tointeger(L, -1);
      if (timeout_sec > 0) {
        fetchtimeout.tv_sec = timeout_sec;
        fetchtimeout.tv_usec = 0;
      }
    } else if (lua_isnumber(L, -1)) {
      double timeout_val = lua_tonumber(L, -1);
      if (timeout_val > 0) {
        fetchtimeout.tv_sec = (int64_t)timeout_val;
        fetchtimeout.tv_usec =
            (int64_t)((timeout_val - (int64_t)timeout_val) * 1e6);
      }
    }
#ifndef UNSECURE
    lua_getfield(L, 2, "resettls");
    if (lua_isboolean(L, -1))
      resettls = lua_toboolean(L, -1);
#endif
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
            return LuaNilError(L, "invalid header name: %s", key);
          val = lua_tolstring(L, -1, &vallen);
          if (!(hdr = gc(EncodeHttpHeaderValue(val, vallen, 0))))
            return LuaNilError(L, "invalid header %s value encoding", key);
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
        return LuaNilError(L, "bad proxy; string expected");
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
      return LuaNilError(L, "bad scheme");
    }
  }

#ifndef UNSECURE
  if (usingssl && resettls)
    LuaResetFetchTlsState();
  if (usingssl && !sslinitialized)
    TlsInit();
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
        return LuaNilError(L, "bad unix proxy; missing socket path");
      }
      if (proxyurl.path.n >= sizeof(((struct sockaddr_un *)0)->sun_path)) {
        return LuaNilError(L, "bad unix proxy; socket path too long (max %zu)",
                           sizeof(((struct sockaddr_un *)0)->sun_path) - 1);
      }
      if (!IsReasonablePath(proxyurl.path.p, proxyurl.path.n)) {
        return LuaNilError(L, "bad unix proxy; path contains . or .. segments");
      }
      proxysockpath = gc(strndup(proxyurl.path.p, proxyurl.path.n));
      DEBUGF("(ftch) using unix proxy %s", proxysockpath);
    } else if (proxyurl.scheme.n == 4 &&
               !memcasecmp(proxyurl.scheme.p, "http", 4)) {
      if (!proxyurl.host.n)
        return LuaNilError(L, "bad proxy; missing host");
      proxyhost = gc(strndup(proxyurl.host.p, proxyurl.host.n));
      proxyport = proxyurl.port.n
                      ? gc(strndup(proxyurl.port.p, proxyurl.port.n))
                      : "80";
      if (!IsAcceptableHost(proxyhost, -1))
        return LuaNilError(L, "bad proxy; invalid host");
      if (!IsAcceptablePort(proxyport, -1))
        return LuaNilError(L, "bad proxy; invalid port");
      if (proxyurl.user.n) {
        char *creds = gc(xasprintf("%.*s:%.*s",
                                   (int)proxyurl.user.n, proxyurl.user.p,
                                   (int)proxyurl.pass.n, proxyurl.pass.p));
        char *b64 = gc(EncodeBase64(creds, strlen(creds), 0));
        if (b64)
          proxyauthhdr = gc(xasprintf("Proxy-Authorization: Basic %s\r\n", b64));
      }
    } else {
      return LuaNilError(L, "bad proxy scheme; only http:// and unix:// supported");
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
    return LuaNilError(L, "invalid host");
  }
  if (!IsAcceptableHost(host, -1))
    return LuaNilError(L, "invalid host");
  if (!IsAcceptablePort(port, -1))
    return LuaNilError(L, "invalid port");
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
      return LuaNilError(L, "socket(AF_UNIX) failed: %s", strerror(errno));
    if (connect(sock, (struct sockaddr *)&addr_un, sizeof(addr_un)) == -1) {
      close(sock);
      return LuaNilError(L, "connect(%s) failed: %s", proxysockpath,
                         strerror(errno));
    }
  } else {
    const char *connecthost = proxyhost ? proxyhost : host;
    const char *connectport = proxyhost ? proxyport : port;
    if ((rc = getaddrinfo(connecthost, connectport, &hints, &addr)) != 0)
      return LuaNilError(L, "getaddrinfo(%s:%s) error: EAI_%s %s", connecthost,
                         connectport, gai_strerror(rc), strerror(errno));
    ip = ntohl(((struct sockaddr_in *)addr->ai_addr)->sin_addr.s_addr);
    if (!proxyhost && !IsPublicIp(ip)) {
      freeaddrinfo(addr);
      return LuaNilError(L, "request to private network blocked (SSRF protection)");
    }
    if ((sock = GoodSocket(addr->ai_family, addr->ai_socktype,
                           addr->ai_protocol, false, &fetchtimeout)) == -1) {
      freeaddrinfo(addr);
      return LuaNilError(L, "socket error: %s", strerror(errno));
    }
    rc = connect(sock, addr->ai_addr, addr->ai_addrlen);
    freeaddrinfo(addr);
    if (rc == -1) {
      close(sock);
      return LuaNilError(L, "connect error: %s", strerror(errno));
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
        return LuaNilError(L, "proxy CONNECT write error: %s", strerror(errno));
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
          return LuaNilError(L, "proxy CONNECT response too large");
        }
        if (!(newp = realloc(connectbuf.p, connectbuf.c))) {
          DestroyHttpMessage(&connectmsg);
          free(connectbuf.p);
          close(sock);
          return LuaNilError(L, "out of memory");
        }
        connectbuf.p = newp;
      }
      if ((connectrc = READ(sock, connectbuf.p + connectbuf.n,
                            connectbuf.c - connectbuf.n)) <= 0) {
        DestroyHttpMessage(&connectmsg);
        free(connectbuf.p);
        close(sock);
        return LuaNilError(L, "proxy CONNECT read error: %s", strerror(errno));
      }
      connectbuf.n += connectrc;
      rc = ParseHttpMessage(&connectmsg, connectbuf.p, connectbuf.n, SHRT_MAX);
      if (rc == -1) {
        DestroyHttpMessage(&connectmsg);
        free(connectbuf.p);
        close(sock);
        return LuaNilError(L, "proxy CONNECT malformed response");
      }
      if (rc > 0) break;  // complete
    }
    if (connectmsg.status != 200) {
      int status = connectmsg.status;
      DestroyHttpMessage(&connectmsg);
      free(connectbuf.p);
      close(sock);
      return LuaNilError(L, "proxy CONNECT failed: HTTP %d", status);
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
      return LuaNilError(L, "out of memory");
    }
    mbedtls_ssl_init(sslctx);
    if ((ret = mbedtls_ssl_setup(sslctx, &confcli)) != 0) {
      mbedtls_ssl_free(sslctx);
      free(sslctx);
      close(sock);
      return LuaNilTlsError(L, "ssl_setup", ret);
    }
    if (!evadedragnetsurveillance)
      mbedtls_ssl_set_hostname(sslctx, host);
    bio = malloc(sizeof(struct TlsBio));
    if (!bio) {
      mbedtls_ssl_free(sslctx);
      free(sslctx);
      close(sock);
      return LuaNilError(L, "out of memory");
    }
    bio->fd = sock;
    bio->a = 0;
    bio->b = 0;
    bio->c = -1;
    mbedtls_ssl_set_bio(sslctx, bio, TlsSend, 0, TlsRecvImpl);
    while ((ret = mbedtls_ssl_handshake(sslctx))) {
      switch (ret) {
        case MBEDTLS_ERR_SSL_WANT_READ:
          break;
        case MBEDTLS_ERR_X509_CERT_VERIFY_FAILED:
          goto StreamVerifyFailed;
        default:
          free(bio);
          mbedtls_ssl_free(sslctx);
          free(sslctx);
          close(sock);
          return LuaNilTlsError(L, "handshake", ret);
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
        return LuaNilTlsError(L, "write", rc);
      }
    } else
#endif
        if ((rc = WRITE(sock, request + i, requestlen - i)) <= 0) {
      close(sock);
      return LuaNilError(L, "write error: %s", strerror(errno));
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
          return LuaNilTlsError(L, "read", rc);
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
      return LuaNilError(L, "read error: %s", strerror(errno));
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
          // Clean up and follow redirect
          if (msg.status == 303) {
            body = "";
            bodylen = 0;
            method = "GET";
          }
          if (!lua_istable(L, 2)) {
            lua_settop(L, 1);
            lua_createtable(L, 0, 3);
          }
          lua_pushlstring(L, body, bodylen);
          lua_setfield(L, -2, "body");
          lua_pushstring(L, method);
          lua_setfield(L, -2, "method");
          lua_pushinteger(L, numredirects + 1);
          lua_setfield(L, -2, "numredirects");
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
            return LuaNilError(L, "refusing HTTPS to HTTP redirect downgrade");
          }
#endif
          // Strip auth headers on cross-origin redirect
          if (url.host.n && url.scheme.n && lua_istable(L, 2)) {
            lua_getfield(L, 2, "headers");
            if (lua_istable(L, -1)) {
              lua_pushnil(L); lua_setfield(L, -2, "Authorization");
              lua_pushnil(L); lua_setfield(L, -2, "authorization");
              lua_pushnil(L); lua_setfield(L, -2, "Cookie");
              lua_pushnil(L); lua_setfield(L, -2, "cookie");
            }
            lua_pop(L, 1);
          }
          if (url.host.n && url.scheme.n) {
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
          lua_replace(L, -3);
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
    // Push status and headers BEFORE we modify the buffer
    // (header offsets in msg point into inbuf.p)
    lua_pushinteger(L, msg.status);
    LuaPushHeaders(L, &msg, inbuf.p);
    DestroyHttpMessage(&msg);

    FetchReader *reader = lua_newuserdata(L, sizeof(FetchReader));
    memset(reader, 0, sizeof(FetchReader));
    luaL_setmetatable(L, FETCH_READER_MT);

    reader->sock = sock;
    reader->usingssl = usingssl;
    reader->body_state = t;
    reader->content_length = paylen;
    reader->bytes_read = 0;

    // Transfer buffer ownership (may contain body data after headers)
    reader->buf = inbuf;
    reader->buf_pos = hdrsize;  // body starts after headers

    // Initialize unchunker if chunked
    if (t == kHttpClientStateBodyChunked) {
      bzero(&reader->u, sizeof(reader->u));
      // Shift body data to start of buffer for unchunker
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

#ifndef UNSECURE
    if (sslctx) {
      // Transfer ownership of heap-allocated sslctx to reader
      reader->sslctx = sslctx;
      reader->bio = bio;
    }
#endif

    // Stack: ..., status, headers, reader
    // Ownership transferred to reader: inbuf.p, bio, sock, sslctx
    return 3;
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

    // Create a closed reader (no body)
    FetchReader *reader = lua_newuserdata(L, sizeof(FetchReader));
    memset(reader, 0, sizeof(FetchReader));
    luaL_setmetatable(L, FETCH_READER_MT);
    reader->sock = -1;
    reader->closed = true;

    // Stack: ..., status, headers, reader
    return 3;
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
  return LuaNilError(L, "transport error");

#ifndef UNSECURE
StreamVerifyFailed:
  LockInc(&shared->c.sslverifyfailed);
  {
    uint32_t verify_result = sslctx->session_negotiate->verify_result;
    free(bio);
    mbedtls_ssl_free(sslctx);
    free(sslctx);
    close(sock);
    return LuaNilTlsError(L, gc(DescribeSslVerifyFailure(verify_result)), ret);
  }
#endif
#undef ssl
}

void LuaInitFetch(void) {
  // SSL mutex is now statically initialized, nothing else needed here
  // TlsInit() will be called on first HTTPS request
}
