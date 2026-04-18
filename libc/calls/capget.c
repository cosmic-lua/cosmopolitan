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
 * Reads the calling thread's (or `header->pid`'s) capability sets.
 *
 * `header->version` must be set by the caller (typically to
 * `_LINUX_CAPABILITY_VERSION_3`); on EINVAL, the kernel sets
 * `header->version` to the version it prefers, so a typical retry
 * loop calls capget twice.
 *
 * `data` must point to one or two `struct __user_cap_data_struct`
 * slots depending on the version (two for v3).
 *
 * @return 0 on success, or -1 w/ errno
 * @raise EFAULT if a pointer is bad
 * @raise EINVAL if `header->version` is unrecognized
 * @raise EPERM if requesting another process's caps without privilege
 * @raise ENOSYS on non-Linux hosts
 */
int capget(struct __user_cap_header_struct *header,
           struct __user_cap_data_struct *data) {
  int rc;
  if (!IsLinux()) {
    rc = enosys();
  } else {
    rc = sys_capget(header, data);
  }
  STRACE("capget(%p, %p) → %d% m", header, data, rc);
  return rc;
}
