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
 * Disassociates parts of the process execution context.
 *
 * This is used, amongst other things, to place the current process into
 * fresh namespaces (network, mount, pid, user, etc.) without having to
 * fork via clone(2). Typical sandbox setup calls unshare(CLONE_NEWNET)
 * from a forked child before exec(), so the new process sees only the
 * resources it was explicitly granted.
 *
 * @param flags is a bitmask of `CLONE_NEW*` flags, e.g. `CLONE_NEWNET |
 *     CLONE_NEWUTS`. See `libc/sysv/consts/clone.h`.
 * @return 0 on success, or -1 w/ errno
 * @raise EPERM if the caller lacks `CAP_SYS_ADMIN` in its user namespace
 *     (or `CAP_SYS_CHROOT` for `CLONE_FS`), or when the kernel forbids
 *     unprivileged user-namespace creation
 * @raise EINVAL if an invalid combination of `flags` was supplied
 * @raise ENOMEM if insufficient memory
 * @raise ENOSPC if a namespace limit was hit
 * @raise EUSERS if the namespace nesting limit was reached
 * @raise ENOSYS on non-Linux hosts
 */
int unshare(int flags) {
  int rc;
  if (!IsLinux()) {
    rc = enosys();
  } else {
    rc = sys_unshare(flags);
  }
  STRACE("unshare(%#x) → %d% m", flags, rc);
  return rc;
}
