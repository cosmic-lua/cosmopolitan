/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2025 Will Maier                                                    │
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
#include "libc/mem/gc.h"
#include "libc/mem/mem.h"
#include "libc/str/str.h"
#include "libc/testlib/ezbench.h"
#include "libc/testlib/hyperion.h"
#include "libc/testlib/testlib.h"
#include "net/http/escape.h"

char *unescapeparam(const char *s) {
  char *p;
  size_t n;
  p = UnescapeParam(s, -1, &n);
  ASSERT_EQ(strlen(p), n);
  return p;
}

TEST(UnescapeParam, testBasic) {
  EXPECT_STREQ("abc &<>\"'\1\2",
               gc(unescapeparam("abc%20%26%3C%3E%22%27%01%02")));
}

TEST(UnescapeParam, testPlusAsSpace) {
  EXPECT_STREQ("hello world", gc(unescapeparam("hello+world")));
}

TEST(UnescapeParam, testMixedPlusAndPercent) {
  EXPECT_STREQ("hello world", gc(unescapeparam("hello%20world")));
  EXPECT_STREQ("a b c", gc(unescapeparam("a+b%20c")));
}

TEST(UnescapeParam, testEmpty) {
  EXPECT_STREQ("", gc(unescapeparam("")));
}

TEST(UnescapeParam, testNoEscapes) {
  EXPECT_STREQ("hello", gc(unescapeparam("hello")));
}

TEST(UnescapeParam, testIncompleteEscape) {
  /* incomplete %XX should be preserved */
  EXPECT_STREQ("%2", gc(unescapeparam("%2")));
  EXPECT_STREQ("%", gc(unescapeparam("%")));
  EXPECT_STREQ("a%", gc(unescapeparam("a%")));
  EXPECT_STREQ("a%2", gc(unescapeparam("a%2")));
}

TEST(UnescapeParam, testInvalidHex) {
  /* invalid hex should be preserved */
  EXPECT_STREQ("%XY", gc(unescapeparam("%XY")));
  EXPECT_STREQ("%2G", gc(unescapeparam("%2G")));
}

TEST(UnescapeParam, testUtf8) {
  /* UTF-8 encoded chars */
  EXPECT_STREQ("𐌰", gc(unescapeparam("%F0%90%8C%B0")));
}

TEST(UnescapeParam, testLowerAndUpperHex) {
  EXPECT_STREQ(" ", gc(unescapeparam("%20")));
  EXPECT_STREQ("~", gc(unescapeparam("%7e")));
  EXPECT_STREQ("~", gc(unescapeparam("%7E")));
}

TEST(UnescapeParam, testRoundTrip) {
  /* EscapeParam then UnescapeParam should give original */
  const char *orig = "hello world!";
  char *escaped = EscapeParam(orig, -1, NULL);
  char *result = UnescapeParam(escaped, -1, NULL);
  EXPECT_STREQ(orig, result);
  free(escaped);
  free(result);
}

BENCH(UnescapeParam, bench) {
  char *escaped = EscapeParam(kHyperion, kHyperionSize, 0);
  EZBENCH2("UnescapeParam", donothing,
           free(UnescapeParam(escaped, -1, 0)));
  free(escaped);
}
