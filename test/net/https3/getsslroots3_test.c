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
#include "libc/str/str.h"
#include "libc/testlib/testlib.h"
#include "third_party/mbedtls3/include/mbedtls/ctr_drbg.h"
#include "third_party/mbedtls3/include/mbedtls/version.h"
#include "third_party/mbedtls3/include/mbedtls/x509_crt.h"
#include "net/https3/https3.h"

// this package must link Mbed TLS 3.6, never the 2.26 fork in
// third_party/mbedtls; mixing them corrupts memory silently, so
// check the version of the library actually linked
TEST(Mbedtls3, testLinkedLibraryIsThreeSixLts) {
  ASSERT_GE(mbedtls_version_get_number(), 0x03060000u);
  ASSERT_EQ(MBEDTLS_VERSION_MAJOR, 3);
}

TEST(GetSslRoots3, testReturnsNonNull) {
  mbedtls_x509_crt *roots = GetSslRoots();
  ASSERT_NE(NULL, roots);
}

TEST(GetSslRoots3, testContainsCertificates) {
  mbedtls_x509_crt *roots = GetSslRoots();
  ASSERT_NE(NULL, roots);
  EXPECT_GT(roots->raw.len, 0u);
}

TEST(GetSslRoots3, testIsSingleton) {
  mbedtls_x509_crt *roots1 = GetSslRoots();
  mbedtls_x509_crt *roots2 = GetSslRoots();
  ASSERT_EQ(roots1, roots2);
}

TEST(GetSslRoots3, testChainStructure) {
  mbedtls_x509_crt *roots = GetSslRoots();
  ASSERT_NE(NULL, roots);
  int count = 0;
  for (mbedtls_x509_crt *cert = roots; cert != NULL; cert = cert->next) {
    if (cert->raw.len > 0) {
      count++;
      EXPECT_GT(cert->subject_raw.len, 0u);
    }
  }
  EXPECT_GT(count, 0);
}

TEST(InitializeRng3, testDrbgProducesBytes) {
  mbedtls_ctr_drbg_context rng;
  unsigned char a[32] = {0};
  unsigned char b[32] = {0};
  InitializeRng(&rng);
  ASSERT_EQ(0, mbedtls_ctr_drbg_random(&rng, a, sizeof(a)));
  ASSERT_EQ(0, mbedtls_ctr_drbg_random(&rng, b, sizeof(b)));
  EXPECT_NE(0, memcmp(a, b, sizeof(a)));
  mbedtls_ctr_drbg_free(&rng);
}

TEST(GetTlsError3, testFormatsKnownError) {
  char *s = GetTlsError(MBEDTLS_ERR_X509_CERT_VERIFY_FAILED);
  ASSERT_NE(NULL, s);
  EXPECT_NE(0, strlen(s));
}
