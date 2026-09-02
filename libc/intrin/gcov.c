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
#ifdef MODE_COV
#include "libc/calls/syscall-sysv.internal.h"
#include "libc/dce.h"
#include "libc/intrin/kprintf.h"
#include "libc/intrin/promises.h"
#include "libc/str/str.h"
#include "libc/sysv/consts/at.h"
#include "libc/sysv/consts/o.h"

/**
 * @fileoverview The gcov runtime for MODE=cov.
 *
 * An object compiled with -fprofile-arcs -ftest-coverage carries a
 * struct gcov_info describing its arc counters, a constructor that
 * hands it to __gcov_init(), and a destructor that calls
 * __gcov_exit(). The cosmocc toolchain ships no libgcov, and in every
 * other mode libc/intrin/gcov.S satisfies those symbols with weak
 * no-ops, so nothing is ever written. Here __gcov_exit() writes each
 * object's counters to the .gcda path gcc embedded in it, in the
 * format the host gcov reads.
 *
 * Layout and encoding follow GCC 14.1 (libgcc/libgcov.h and
 * gcc/gcov-io.h): gcov_info holds version, next, stamp, checksum,
 * filename, one merge slot per counter kind, n_functions and the
 * function table; every number in the file is a native-endian int32,
 * a counter is two int32 words low first, and a record's length is a
 * byte count. The file is written whole each time, never merged with
 * what a previous process left: counts are those of one process.
 *
 * The writer opens with raw Linux flag values, so it dumps on Linux
 * and stays silent elsewhere. A process that pledged away wpath or
 * cpath cannot create the file, and on Linux the attempt would be
 * killed with SIGSYS rather than refused, so such a process dumps
 * nothing: its counts are dropped, and its exit status is its own.
 *
 * gcc's __gcov_fork and __gcov_exec* wrappers are deliberately absent:
 * the instrumented objects are compiled with -fno-builtin on those
 * names (COVERAGE_CFLAGS, build/config.mk), so they never reference
 * them, and an object that did would fail to link rather than fork
 * through a stub.
 */

#define GCOV_COUNTERS 9  // counter kinds in GCC 14.1's gcov-counter.def

#define GCOV_DATA_MAGIC         0x67636461u  // "gcda"
#define GCOV_TAG_FUNCTION       0x01000000u
#define GCOV_TAG_COUNTER_BASE   0x01a10000u
#define GCOV_TAG_OBJECT_SUMMARY 0xa1000000u
#define GCOV_TAG_FOR_COUNTER(t) (GCOV_TAG_COUNTER_BASE + ((unsigned)(t) << 17))

typedef unsigned gcov_unsigned_t;
typedef long long gcov_type;

struct gcov_ctr_info {
  gcov_unsigned_t num;
  gcov_type *values;
};

struct gcov_fn_info {
  const struct gcov_info *key;
  gcov_unsigned_t ident;
  gcov_unsigned_t lineno_checksum;
  gcov_unsigned_t cfg_checksum;
  struct gcov_ctr_info ctrs[1];  // one per non-null merge slot
};

typedef void (*gcov_merge_fn)(gcov_type *, gcov_unsigned_t);

struct gcov_info {
  gcov_unsigned_t version;
  struct gcov_info *next;
  gcov_unsigned_t stamp;
  gcov_unsigned_t checksum;
  const char *filename;
  gcov_merge_fn merge[GCOV_COUNTERS];
  gcov_unsigned_t n_functions;
  const struct gcov_fn_info *const *functions;
};

static struct gcov_info *__gcov_list;

struct GcovFile {
  int fd;
  bool failed;
  unsigned len;
  char buf[2048];
};

static void __gcov_flush(struct GcovFile *f) {
  unsigned off = 0;
  while (!f->failed && off < f->len) {
    long rc = sys_write(f->fd, f->buf + off, f->len - off);
    if (rc <= 0) {
      f->failed = true;
    } else {
      off += rc;
    }
  }
  f->len = 0;
}

static void __gcov_put32(struct GcovFile *f, gcov_unsigned_t word) {
  if (f->len + sizeof(word) > sizeof(f->buf))
    __gcov_flush(f);
  memcpy(f->buf + f->len, &word, sizeof(word));
  f->len += sizeof(word);
}

static void __gcov_put64(struct GcovFile *f, gcov_type count) {
  __gcov_put32(f, (gcov_unsigned_t)count);
  __gcov_put32(f, (gcov_unsigned_t)((unsigned long long)count >> 32));
}

static gcov_type __gcov_max_counter(const struct gcov_info *info) {
  gcov_type max = 0;
  for (unsigned i = 0; i < info->n_functions; ++i) {
    const struct gcov_fn_info *fn = info->functions[i];
    if (!fn || fn->key != info)
      continue;
    const struct gcov_ctr_info *ctr = fn->ctrs;
    for (unsigned t = 0; t < GCOV_COUNTERS; ++t) {
      if (!info->merge[t])
        continue;
      for (unsigned j = 0; j < ctr->num; ++j)
        if (ctr->values[j] > max)
          max = ctr->values[j];
      ++ctr;
    }
  }
  return max;
}

static void __gcov_write(const struct gcov_info *info) {
  struct GcovFile f = {0};
  f.fd = __sys_openat(AT_FDCWD, info->filename,
                      O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (f.fd < 0) {
    kprintf("gcov: %s: open failed: %d\n", info->filename, -f.fd);
    return;
  }
  __gcov_put32(&f, GCOV_DATA_MAGIC);
  __gcov_put32(&f, info->version);
  __gcov_put32(&f, info->stamp);
  __gcov_put32(&f, info->checksum);
  __gcov_put32(&f, GCOV_TAG_OBJECT_SUMMARY);
  __gcov_put32(&f, 2 * sizeof(gcov_unsigned_t));
  __gcov_put32(&f, 1);  // runs
  __gcov_put32(&f, (gcov_unsigned_t)__gcov_max_counter(info));  // sum_max
  for (unsigned i = 0; i < info->n_functions; ++i) {
    const struct gcov_fn_info *fn = info->functions[i];
    __gcov_put32(&f, GCOV_TAG_FUNCTION);
    if (!fn || fn->key != info) {
      __gcov_put32(&f, 0);
      continue;
    }
    __gcov_put32(&f, 3 * sizeof(gcov_unsigned_t));
    __gcov_put32(&f, fn->ident);
    __gcov_put32(&f, fn->lineno_checksum);
    __gcov_put32(&f, fn->cfg_checksum);
    const struct gcov_ctr_info *ctr = fn->ctrs;
    for (unsigned t = 0; t < GCOV_COUNTERS; ++t) {
      if (!info->merge[t])
        continue;
      __gcov_put32(&f, GCOV_TAG_FOR_COUNTER(t));
      __gcov_put32(&f, ctr->num * 2 * sizeof(gcov_unsigned_t));
      for (unsigned j = 0; j < ctr->num; ++j)
        __gcov_put64(&f, ctr->values[j]);
      ++ctr;
    }
  }
  __gcov_flush(&f);
  if (f.failed)
    kprintf("gcov: %s: write failed\n", info->filename);
  sys_close(f.fd);
}

/**
 * Registers an instrumented object; gcc calls this from its
 * constructor with the object's counter table.
 */
void __gcov_init(struct gcov_info *info) {
  if (!info->version || !info->n_functions)
    return;
  info->next = __gcov_list;
  __gcov_list = info;
}

/**
 * Writes every registered object's counters to its .gcda file; gcc
 * calls this from its destructor, so it runs once at exit().
 */
void __gcov_exit(void) {
  struct gcov_info *info = __gcov_list;
  __gcov_list = 0;
  if (!IsLinux())
    return;
  if (!PLEDGED(WPATH) || !PLEDGED(CPATH))
    return;
  for (; info; info = info->next)
    __gcov_write(info);
}

/**
 * Referenced from every gcov_info's merge table; the writer never
 * merges, so it has nothing to do.
 */
void __gcov_merge_add(gcov_type *counters, gcov_unsigned_t n) {
}

#endif /* MODE_COV */
