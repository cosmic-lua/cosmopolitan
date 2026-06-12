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
#include "libc/mem/mem.h"
#include "libc/str/str.h"
#include "libc/str/tab.h"
#include "net/http/escape.h"

/**
 * Unescapes URL query/form parameter.
 *
 * Decodes percent-encoded sequences (%XX) and unconditionally converts
 * '+' to space (application/x-www-form-urlencoded semantics).
 *
 * The output buffer is NUL-terminated, but the decoded content may
 * contain embedded NUL bytes (e.g. from %00). Callers must use the
 * length returned via `z` rather than strlen() on the result.
 *
 * @param p is input pointer; may be NULL only when n == (size_t)-1
 *     (in which case n is treated as 0). Passing NULL with a positive
 *     n will dereference the NULL pointer.
 * @param n is the number of bytes to decode, or -1 to use strlen(p)
 * @param z if non-NULL receives the decoded output length (excluding
 *     the NUL terminator); always set to 0 on allocation failure
 * @return allocated NUL-terminated buffer, or NULL w/ errno
 */
char *UnescapeParam(const char *p, size_t n, size_t *z) {
  int a, b, c;
  char *r, *q;
  size_t i;
  if (z)
    *z = 0;
  if (n == (size_t)-1)
    n = p ? strlen(p) : 0;
  if ((q = r = malloc(n + 1))) {
    for (i = 0; i < n; i++) {
      c = p[i] & 255;
      if (c == '%' && i + 2 < n &&
          (a = kHexToInt[p[i + 1] & 255]) != -1 &&
          (b = kHexToInt[p[i + 2] & 255]) != -1) {
        *q++ = (a << 4) | b;
        i += 2;
      } else if (c == '+') {
        *q++ = ' ';
      } else {
        *q++ = c;
      }
    }
    if (z)
      *z = q - r;
    *q++ = '\0';
    if ((q = realloc(r, q - r)))
      r = q;
  }
  return r;
}
