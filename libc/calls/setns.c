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
#include "libc/calls/calls.h"
#include "libc/calls/syscall-sysv.internal.h"
#include "libc/dce.h"
#include "libc/intrin/strace.h"
#include "libc/sysv/errfuns.h"

/**
 * Reassociates calling thread with a namespace.
 *
 * The target namespace is identified by a file descriptor obtained from
 * `/proc/[pid]/ns/net` and friends (or from `pidfd_open` +
 * `pidfd_getfd`). A typical pattern for cross-namespace dialing is:
 *
 *     int parent_ns = open("/proc/self/ns/net", O_RDONLY);
 *     unshare(CLONE_NEWNET);          // enter fresh netns
 *     ...                             // create listener in child netns
 *     setns(parent_ns, CLONE_NEWNET); // hop back to dial upstream
 *
 * @param fd refers to a namespace file (e.g. `/proc/<pid>/ns/net`)
 * @param nstype is 0 (accept any) or one of the `CLONE_NEW*` constants
 *     to assert the target is the expected kind of namespace
 * @return 0 on success, or -1 w/ errno
 * @raise EBADF if `fd` is not an open file descriptor
 * @raise EINVAL if `fd` doesn't refer to a namespace, or the expected
 *     `nstype` doesn't match
 * @raise EPERM if the caller is not privileged in the target namespace's
 *     user namespace
 * @raise ENOMEM if insufficient memory
 * @raise ENOSYS on non-Linux hosts
 */
int setns(int fd, int nstype) {
  int rc;
  if (!IsLinux()) {
    rc = enosys();
  } else {
    rc = sys_setns(fd, nstype);
  }
  STRACE("setns(%d, %#x) → %d% m", fd, nstype, rc);
  return rc;
}
