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
#include "libc/assert.h"
#include "libc/bsdstdlib.h"
#include "libc/cosmo.h"
#include "libc/runtime/runtime.h"
#include "libc/stdio/rand.h"
#include "third_party/mbedtls3/include/psa/crypto.h"
#include "net/https3/https3.h"
#include "third_party/mbedtls3/include/mbedtls/ctr_drbg.h"

static cosmo_once_t g_psa_once;

static void FreePsaCrypto(void) {
  mbedtls_psa_crypto_free();
}

// TLS 1.3 in Mbed TLS 3.6 uses PSA crypto internally and requires
// psa_crypto_init() before the handshake
static void InitPsaCrypto(void) {
  npassert(psa_crypto_init() == PSA_SUCCESS);
  atexit(FreePsaCrypto);
}

void InitializeRng(mbedtls_ctr_drbg_context *r) {
  unsigned char b[64];
  cosmo_once(&g_psa_once, InitPsaCrypto);
  mbedtls_ctr_drbg_init(r);
  arc4random_buf(b, 64);
  npassert(!mbedtls_ctr_drbg_seed(r, GetEntropy, 0, b, 64));
  mbedtls_platform_zeroize(b, 64);
}
