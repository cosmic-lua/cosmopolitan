/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2026 Justine Alexandra Roberts Tunney                              │
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
#include "net/http/escape.h"

// bit 1: A-Za-z0-9, shared by both alphabets
// bit 2: '+' and '/', the standard alphabet's extras (rfc4648 §4)
// bit 4: '-' and '_', the url-safe alphabet's extras (rfc4648 §5)
static const unsigned char kBase64Alpha[256] = {
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  // 0x00
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  // 0x10
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 4, 0, 2,  // 0x20
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0,  // 0x30
    0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,  // 0x40
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 4,  // 0x50
    0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,  // 0x60
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0,  // 0x70
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  // 0x80
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  // 0x90
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  // 0xa0
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  // 0xb0
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  // 0xc0
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  // 0xd0
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  // 0xe0
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  // 0xf0
};

/**
 * Returns true if input is structurally valid base64.
 *
 * Structurally valid means zero or more characters from one alphabet,
 * followed by at most two '=' padding characters, followed by the end
 * of the input. The empty string is valid. Unpadded input is valid, and
 * padding is not required to complete a four-character quantum: this
 * predicate polices the character set and padding position, exactly the
 * strictness DecodeBase64() deliberately omits (it skips bytes outside
 * its alphabet and accepts both alphabets interchangeably), so callers
 * that must reject malformed or cross-alphabet input can gate on this
 * before decoding.
 *
 * @param data is input value
 * @param size if -1 implies strlen
 * @param urlsafe validates the url-safe alphabet `A-Za-z0-9-_`
 *     (rfc4648 §5) when true, the standard alphabet `A-Za-z0-9+/`
 *     (rfc4648 §4) when false
 * @return true if input is valid base64 in the selected alphabet
 */
bool32 IsBase64(const char *data, size_t size, bool32 urlsafe) {
  const char *p, *pe;
  unsigned mask = urlsafe ? 1 | 4 : 1 | 2;
  if (size == -1)
    size = data ? strlen(data) : 0;
  p = data;
  pe = data + size;
  while (p < pe && (kBase64Alpha[*p & 255] & mask))
    ++p;
  if (pe - p > 2)
    return false;
  for (; p < pe; ++p)
    if (*p != '=')
      return false;
  return true;
}
