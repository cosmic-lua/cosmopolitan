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
#include "libc/calls/cap.h"
#include "libc/calls/syscall-sysv.internal.h"
#include "libc/dce.h"
#include "libc/intrin/strace.h"
#include "libc/sysv/errfuns.h"

/**
 * Sets the calling thread's (or `header->pid`'s) capability sets.
 *
 * `header->version` must be set to a supported capability version
 * (typically `_LINUX_CAPABILITY_VERSION_3`). `data` must point to one
 * or two `struct __user_cap_data_struct` slots depending on the
 * version (two for v3).
 *
 * Caps in `permitted` must be a subset of the current permitted set
 * (you cannot add caps you don't have). Inheritable must be a subset
 * of `permitted UNION current_inheritable`. Effective must be a
 * subset of `permitted`.
 *
 * @return 0 on success, or -1 w/ errno
 * @raise EFAULT if a pointer is bad
 * @raise EINVAL if `header->version` is unrecognized
 * @raise EPERM if requested caps exceed what's allowed, or if setting
 *     another process's caps (Linux disallows that since 2.6.25)
 * @raise ENOSYS on non-Linux hosts
 */
int capset(struct __user_cap_header_struct *header,
           const struct __user_cap_data_struct *data) {
  int rc;
  if (!IsLinux()) {
    rc = enosys();
  } else {
    rc = sys_capset(header, data);
  }
  STRACE("capset(%p, %p) → %d% m", header, data, rc);
  return rc;
}
