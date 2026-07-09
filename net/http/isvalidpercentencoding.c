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
#include "libc/str/tab.h"
#include "net/http/escape.h"

/**
 * Returns true if percent-encoded string is well-formed.
 *
 * Checks that every '%' byte begins a valid %XX sequence where both X
 * are hexadecimal digits. Decoders like UnescapeParam() are lenient and
 * pass malformed sequences through unchanged; this predicate lets a
 * caller reject such input up front with a single scan and no
 * allocation.
 *
 * @param p is input bytes; may be NULL only when n == 0
 * @param n is the number of bytes to validate
 * @return true if every '%' begins a valid %XX sequence
 */
bool32 IsValidPercentEncoding(const char *p, size_t n) {
  size_t i = 0;
  while (i < n) {
    if (p[i] == '%') {
      if (i + 2 < n &&                       //
          kHexToInt[p[i + 1] & 255] != -1 && //
          kHexToInt[p[i + 2] & 255] != -1) {
        i += 3;
      } else {
        return false;
      }
    } else {
      ++i;
    }
  }
  return true;
}
