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
#include "libc/calls/calls.h"
#include "libc/calls/struct/flock.h"
#include "libc/calls/syscall-sysv.internal.h"
#include "libc/dce.h"
#include "libc/intrin/kprintf.h"
#include "libc/intrin/promises.h"
#include "libc/intrin/weaken.h"
#include "libc/mem/mem.h"
#include "libc/str/str.h"
#include "libc/sysv/consts/at.h"
#include "libc/sysv/consts/f.h"
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
 * byte count.
 *
 * __gcov_write() opens info->filename once, O_RDWR|O_CREAT with no
 * O_TRUNC, and takes a whole-file F_SETLKW write lock on that one fd
 * before touching the file — every instrumented process runs under
 * make -j and every one of them writes the same .gcda per object, so
 * the open-merge-truncate-write sequence below is a critical section
 * and the lock is what makes it one: a second process's F_SETLKW
 * blocks until the first's fd (and so its lock) is closed, so no two
 * processes ever read or write the file at once. Only then does it
 * try to read back whatever is already there and add its counters to
 * the live ones — libgcov-driver.c's read-add-write merge,
 * __gcov_merge_add semantics — so a suite of many short-lived
 * processes accumulates one file's counts across all of them instead
 * of each exit clobbering the last. A single read pass over the
 * locked fd checks that the file's magic, version, stamp and checksum
 * match this object and that every function and counter record has
 * the shape this object's table predicts; every on-disk counter value
 * it reads goes into a scratch buffer, never straight into the live
 * counters. Only once that whole read validates does a second,
 * in-memory pass add the scratch values into the live ones — a pass
 * over already-checked data that cannot itself fail. Any mismatch
 * during the read — no file yet, a foreign header, a length or
 * checksum that does not line up — aborts the merge with the live
 * counters untouched, so the write proceeds as if the file were
 * fresh: nothing is ever applied until the entire file is known good.
 * With the lock held for the whole pass, such a mismatch can only
 * mean a foreign or corrupt file — never another process's write
 * landing mid-read, which the lock now rules out — and the same fd is
 * then truncated to zero, seeked back to the start and rewritten,
 * still under the lock; closing it is what releases the lock.
 *
 * The writer opens with raw Linux flag values, so it dumps on Linux
 * and stays silent elsewhere. A process that pledged away wpath,
 * cpath or flock cannot both create the file and lock it, and on
 * Linux the attempt would be killed with SIGSYS rather than refused,
 * so such a process dumps nothing: its counts are dropped, and its
 * exit status is its own.
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

struct GcovReader {
  int fd;
  bool failed;
  unsigned len;
  unsigned pos;
  char buf[2048];
};

static bool __gcov_refill(struct GcovReader *r) {
  long rc = sys_read(r->fd, r->buf, sizeof(r->buf));
  if (rc <= 0) {
    r->failed = true;
    r->len = r->pos = 0;
    return false;
  }
  r->len = (unsigned)rc;
  r->pos = 0;
  return true;
}

static bool __gcov_get32(struct GcovReader *r, gcov_unsigned_t *out) {
  char tmp[sizeof(gcov_unsigned_t)];
  unsigned need = sizeof(gcov_unsigned_t);
  unsigned got = 0;
  while (got < need) {
    if (r->pos >= r->len && !__gcov_refill(r))
      return false;
    unsigned avail = r->len - r->pos;
    unsigned take = need - got < avail ? need - got : avail;
    memcpy(tmp + got, r->buf + r->pos, take);
    r->pos += take;
    got += take;
  }
  memcpy(out, tmp, sizeof(gcov_unsigned_t));
  return true;
}

/**
 * Counts how many gcov_type counter values info's own tables predict
 * across every valid function and active counter kind — the exact
 * number a matching on-disk file must carry, and so the exact size
 * the merge scratch buffer needs. Depends only on info, never on any
 * file, so it is stable for the whole call regardless of what a
 * concurrent writer does to the path.
 */
static gcov_unsigned_t __gcov_count_values(const struct gcov_info *info) {
  gcov_unsigned_t total = 0;
  for (unsigned i = 0; i < info->n_functions; ++i) {
    const struct gcov_fn_info *fn = info->functions[i];
    if (!fn || fn->key != info)
      continue;
    const struct gcov_ctr_info *ctr = fn->ctrs;
    for (unsigned t = 0; t < GCOV_COUNTERS; ++t) {
      if (!info->merge[t])
        continue;
      total += ctr->num;
      ++ctr;
    }
  }
  return total;
}

/**
 * Reads one whole .gcda file already at fd, the object's own locked
 * file, and checks that it belongs to this object: same magic,
 * version, stamp and checksum, and every function/counter record the
 * same shape info's own table predicts. Every on-disk counter value
 * is written into scratch, in the same order __gcov_apply_scratch()
 * below walks — never into a live ctr->values — so a mismatch
 * discovered anywhere in the file leaves every live counter
 * untouched. scratch must hold at least __gcov_count_values(info)
 * entries. Returns false on any mismatch — a foreign or corrupt file,
 * never a concurrent writer, since the caller holds fd's whole-file
 * lock for the entire read — with *runs and scratch's contents
 * undefined.
 */
static bool __gcov_read_and_validate(const struct gcov_info *info, int fd,
                                     gcov_type *scratch,
                                     gcov_unsigned_t *runs) {
  struct GcovReader r = {0};
  r.fd = fd;
  gcov_unsigned_t magic, version, stamp, checksum, tag, len, sum_max;
  unsigned k = 0;
  if (!__gcov_get32(&r, &magic) || magic != GCOV_DATA_MAGIC)
    return false;
  if (!__gcov_get32(&r, &version) || version != info->version)
    return false;
  if (!__gcov_get32(&r, &stamp) || stamp != info->stamp)
    return false;
  if (!__gcov_get32(&r, &checksum) || checksum != info->checksum)
    return false;
  if (!__gcov_get32(&r, &tag) || tag != GCOV_TAG_OBJECT_SUMMARY)
    return false;
  if (!__gcov_get32(&r, &len) || len != 2 * sizeof(gcov_unsigned_t))
    return false;
  if (!__gcov_get32(&r, runs))
    return false;
  if (!__gcov_get32(&r, &sum_max))
    return false;
  for (unsigned i = 0; i < info->n_functions; ++i) {
    const struct gcov_fn_info *fn = info->functions[i];
    bool valid = fn && fn->key == info;
    if (!__gcov_get32(&r, &tag) || tag != GCOV_TAG_FUNCTION)
      return false;
    if (!__gcov_get32(&r, &len))
      return false;
    if (!valid) {
      if (len != 0)
        return false;
      continue;
    }
    if (len != 3 * sizeof(gcov_unsigned_t))
      return false;
    gcov_unsigned_t ident, lineno_checksum, cfg_checksum;
    if (!__gcov_get32(&r, &ident) || ident != fn->ident)
      return false;
    if (!__gcov_get32(&r, &lineno_checksum) ||
        lineno_checksum != fn->lineno_checksum)
      return false;
    if (!__gcov_get32(&r, &cfg_checksum) || cfg_checksum != fn->cfg_checksum)
      return false;
    const struct gcov_ctr_info *ctr = fn->ctrs;
    for (unsigned t = 0; t < GCOV_COUNTERS; ++t) {
      if (!info->merge[t])
        continue;
      if (!__gcov_get32(&r, &tag) || tag != GCOV_TAG_FOR_COUNTER(t))
        return false;
      if (!__gcov_get32(&r, &len) || len != ctr->num * 2 * sizeof(gcov_unsigned_t))
        return false;
      for (unsigned j = 0; j < ctr->num; ++j) {
        gcov_unsigned_t lo, hi;
        if (!__gcov_get32(&r, &lo) || !__gcov_get32(&r, &hi))
          return false;
        unsigned long long bits = (unsigned long long)lo |
                                   ((unsigned long long)hi << 32);
        scratch[k++] = (gcov_type)bits;
      }
      ++ctr;
    }
  }
  return true;
}

/**
 * Adds every value in scratch into its matching live counter, in the
 * same function/counter-kind/index order __gcov_read_and_validate()
 * above filled it. Only ever called after that whole read validated,
 * over data already fully in memory, so unlike the read this cannot
 * fail partway through: once __gcov_merge() decides to apply, it
 * always applies completely.
 */
static void __gcov_apply_scratch(const struct gcov_info *info,
                                 const gcov_type *scratch) {
  unsigned k = 0;
  for (unsigned i = 0; i < info->n_functions; ++i) {
    const struct gcov_fn_info *fn = info->functions[i];
    if (!fn || fn->key != info)
      continue;
    const struct gcov_ctr_info *ctr = fn->ctrs;
    for (unsigned t = 0; t < GCOV_COUNTERS; ++t) {
      if (!info->merge[t])
        continue;
      for (unsigned j = 0; j < ctr->num; ++j)
        ctr->values[j] += scratch[k++];
      ++ctr;
    }
  }
}

/**
 * Merges whatever is already at fd — the object's own locked file,
 * positioned at its start — into info's live counters: one
 * read-and-validate pass into a scratch buffer, then — only if that
 * pass fully matches — an in-memory apply pass that cannot itself
 * fail. On success *prior_runs holds the run count the file recorded,
 * so the write that follows can report one more; on any failure (an
 * empty file, a mismatch, an allocation failure) the live counters
 * are untouched — never partially applied — and *prior_runs is left
 * at 0. Does not touch fd's lock or lifetime; the caller owns both.
 */
static bool __gcov_merge(const struct gcov_info *info, int fd,
                         gcov_unsigned_t *prior_runs) {
  gcov_unsigned_t total = __gcov_count_values(info);
  gcov_type *scratch = 0;
  if (total) {
    if (!_weaken(malloc))
      return false;
    scratch = _weaken(malloc)((size_t)total * sizeof(gcov_type));
    if (!scratch)
      return false;
  }
  gcov_unsigned_t runs = 0;
  bool ok = __gcov_read_and_validate(info, fd, scratch, &runs);
  if (!ok) {
    if (_weaken(free))
      _weaken(free)(scratch);
    return false;
  }
  __gcov_apply_scratch(info, scratch);
  if (_weaken(free))
    _weaken(free)(scratch);
  *prior_runs = runs;
  return true;
}

/**
 * Writes info's counters to its .gcda, merged with whatever is
 * already there. Opens info->filename once, O_RDWR|O_CREAT with no
 * O_TRUNC, and takes a whole-file F_SETLKW write lock on that fd
 * before reading or writing a byte — every other process racing this
 * one on the same path blocks in its own F_SETLKW until this fd (and
 * so this lock) closes, so the merge-then-rewrite below runs as one
 * critical section no other writer can interleave with. A process
 * that pledged away wpath, cpath or flock cannot safely take that
 * lock and returns before opening anything, exactly like the missing
 * wpath/cpath case in __gcov_exit() below: its counts are dropped.
 */
static void __gcov_write(const struct gcov_info *info) {
  if (!PLEDGED(FLOCK))
    return;
  int fd = __sys_openat(AT_FDCWD, info->filename, O_RDWR | O_CREAT, 0644);
  if (fd < 0) {
    kprintf("gcov: %s: open failed: %d\n", info->filename, -fd);
    return;
  }
  struct flock lock = {0};
  lock.l_type = F_WRLCK;
  lock.l_whence = SEEK_SET;
  if (__sys_fcntl(fd, F_SETLKW, &lock) == -1) {
    kprintf("gcov: %s: lock failed\n", info->filename);
    sys_close(fd);
    return;
  }
  gcov_unsigned_t prior_runs = 0;
  __gcov_merge(info, fd, &prior_runs);
  sys_ftruncate(fd, 0, 0);
  sys_lseek(fd, 0, SEEK_SET, 0);
  struct GcovFile f = {0};
  f.fd = fd;
  __gcov_put32(&f, GCOV_DATA_MAGIC);
  __gcov_put32(&f, info->version);
  __gcov_put32(&f, info->stamp);
  __gcov_put32(&f, info->checksum);
  __gcov_put32(&f, GCOV_TAG_OBJECT_SUMMARY);
  __gcov_put32(&f, 2 * sizeof(gcov_unsigned_t));
  __gcov_put32(&f, prior_runs + 1);  // runs
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
 * Referenced from every gcov_info's merge table so gcc's generated
 * code links; the address is only ever a non-null marker for "this
 * counter kind is active" here, checked via info->merge[t] — the
 * actual merge is __gcov_read_and_validate()/__gcov_apply_scratch()
 * above, which read and add counter records directly rather than
 * calling through this pointer.
 */
void __gcov_merge_add(gcov_type *counters, gcov_unsigned_t n) {
}

#endif /* MODE_COV */
