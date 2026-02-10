/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2024 Will Maier                                                    │
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
#include "libc/testlib/testlib.h"
#include "net/https/https.h"
#include "third_party/mbedtls/x509_crt.h"

// Test that GetSslRoots returns a non-NULL certificate chain.
// The embedded certificates in /zip/usr/share/ssl/root should always
// be available, so the chain should have at least one certificate.
TEST(GetSslRoots, testReturnsNonNull) {
  mbedtls_x509_crt *roots = GetSslRoots();
  ASSERT_NE(NULL, roots);
}

// Test that the returned chain contains at least one parsed certificate.
// The raw_len field is non-zero for a valid parsed certificate.
TEST(GetSslRoots, testContainsCertificates) {
  mbedtls_x509_crt *roots = GetSslRoots();
  ASSERT_NE(NULL, roots);
  // A valid parsed cert has non-zero raw.len
  EXPECT_GT(roots->raw.len, 0u);
}

// Test that GetSslRoots is idempotent (singleton pattern).
// Multiple calls should return the same pointer.
TEST(GetSslRoots, testIsSingleton) {
  mbedtls_x509_crt *roots1 = GetSslRoots();
  mbedtls_x509_crt *roots2 = GetSslRoots();
  ASSERT_EQ(roots1, roots2);
}

// Test that the certificate chain has valid structure.
// Walk the chain and verify each cert has non-zero raw data.
TEST(GetSslRoots, testChainStructure) {
  mbedtls_x509_crt *roots = GetSslRoots();
  ASSERT_NE(NULL, roots);
  int count = 0;
  for (mbedtls_x509_crt *cert = roots; cert != NULL; cert = cert->next) {
    if (cert->raw.len > 0) {
      count++;
      // Each cert should have a non-empty subject
      EXPECT_GT(cert->subject_raw.len, 0u);
    }
  }
  // We expect at least a few root certificates from the embedded bundle
  EXPECT_GT(count, 0);
}
