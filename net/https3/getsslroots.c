/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2021 Justine Alexandra Roberts Tunney                              │
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
#include "libc/calls/calls.h"
#include "libc/calls/struct/dirent.h"
#include "libc/cosmo.h"
#include "libc/limits.h"
#include "libc/mem/mem.h"
#include "libc/runtime/runtime.h"
#include "libc/str/str.h"
#include "libc/sysv/consts/dt.h"
#include "libc/sysv/consts/o.h"
#include "third_party/mbedtls3/include/mbedtls/x509_crt.h"

__static_yoink("ssl_root_support");

#define SSL_ROOT_DIR "/zip/usr/share/ssl/root"

// Common system CA certificate bundle locations
static const char *const kSystemCaPaths[] = {
    "/etc/ssl/certs/ca-certificates.crt",      // Debian/Ubuntu
    "/etc/pki/tls/certs/ca-bundle.crt",        // RHEL/CentOS
    "/etc/ssl/ca-bundle.pem",                  // OpenSUSE
    "/usr/local/share/certs/ca-root-nss.crt",  // FreeBSD
    "/etc/ssl/cert.pem",                       // Alpine/macOS
};

static struct {
  _Atomic(uint32_t) once;
  mbedtls_x509_crt chain;
} g_ssl_roots;

static void FreeSslRoots(void) {
  mbedtls_x509_crt_free(&g_ssl_roots.chain);
}

// Load certificates from a single PEM file
// Returns number of certificates loaded, or 0 on failure
static int LoadCertsFromFile(const char *path) {
  int fd, loaded = 0;
  size_t size;
  uint8_t *data;
  if ((fd = open(path, O_RDONLY)) == -1) {
    return 0;
  }
  size = lseek(fd, 0, SEEK_END);
  if (size > 0 && size < 16 * 1024 * 1024 &&  // sanity limit: 16MB
      (data = calloc(1, size + 1)) != NULL) {
    if (pread(fd, data, size, 0) == (ssize_t)size) {
      int rc = mbedtls_x509_crt_parse(&g_ssl_roots.chain, data, size + 1);
      if (rc >= 0) {
        // rc is number of certs that failed to parse; success if not all failed
        loaded = 1;
      }
    }
    free(data);
  }
  close(fd);
  return loaded;
}

// Load certificates from a directory of PEM files
static void LoadCertsFromDir(const char *dirpath) {
  DIR *dir;
  struct dirent *ent;
  char path[PATH_MAX];
  if (!(dir = opendir(dirpath))) {
    return;
  }
  while ((ent = readdir(dir))) {
    if (ent->d_type != DT_REG && ent->d_type != DT_UNKNOWN) {
      continue;
    }
    strlcpy(path, dirpath, sizeof(path));
    strlcat(path, "/", sizeof(path));
    strlcat(path, ent->d_name, sizeof(path));
    uint8_t *data;
    int fd = open(path, O_RDONLY);
    size_t size = lseek(fd, 0, SEEK_END);
    if ((data = calloc(1, size + 1)) && pread(fd, data, size, 0) == (ssize_t)size) {
      if (mbedtls_x509_crt_parse(&g_ssl_roots.chain, data, size + 1)) {
        // Individual cert parse error is not fatal
      }
    }
    free(data);
    close(fd);
  }
  closedir(dir);
}

static void InitSslRoots(void) {
  const char *env_cert_file;
  size_t i;

  // System CA loading is OPT-IN: only load /etc/ssl/... bundles when
  // SSL_USE_SYSTEM_CERTS is set.  This preserves the pre-fork behaviour of
  // trusting only the embedded pinned root set, and prevents a corporate MITM
  // proxy CA (or any locally-installed CA) from silently joining the trust
  // store without an explicit operator decision.
  //
  // Both env vars are read via secure_getenv() so they are ignored when the
  // process is running setuid/setgid/AT_SECURE, exactly as OpenSSL does for
  // SSL_CERT_FILE in privileged contexts.
  if (secure_getenv("SSL_USE_SYSTEM_CERTS")) {
    // Honour SSL_CERT_FILE to point at a specific bundle (setuid-safe).
    if ((env_cert_file = secure_getenv("SSL_CERT_FILE")) != NULL) {
      LoadCertsFromFile(env_cert_file);
    } else {
      // Otherwise probe the well-known system bundle locations in order.
      for (i = 0; i < sizeof(kSystemCaPaths) / sizeof(kSystemCaPaths[0]); i++) {
        if (LoadCertsFromFile(kSystemCaPaths[i])) {
          break;
        }
      }
    }
  }

  // Always load the embedded pinned root certificates.
  LoadCertsFromDir(SSL_ROOT_DIR);

  // Warn if the trust store is completely empty — all HTTPS verification
  // will fail and this is almost certainly a packaging/deployment error.
  if (!g_ssl_roots.chain.raw.len) {
    tinyprint(2, "warning: GetSslRoots: no SSL root certificates loaded;"
                 " HTTPS verification will fail\n", NULL);
  }

  atexit(FreeSslRoots);
}

/**
 * Returns singleton of SSL roots stored in /zip/usr/share/ssl/root/...
 */
mbedtls_x509_crt *GetSslRoots(void) {
  cosmo_once(&g_ssl_roots.once, InitSslRoots);
  return &g_ssl_roots.chain;
}
