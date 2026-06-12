# Security & Functional Review: Fork vs. upstream `jart/cosmopolitan`

This document records the findings of a security and functional review of this
fork against its upstream base, along with a recommended remediation plan.

- **Fork base:** `b444b3a6` (upstream `jart/cosmopolitan`, 2025-12-02)
- **Branch reviewed:** `claude/upstream-diff-security-review-p4gl4e`
  (merged up to `master` @ `de0f3e56`)
- **Scope:** ~20k lines of fork-specific changes — a Lua `cosmo.*` standard
  library (fetch / http / zip / getopt / repl), the `cosmo.sandbox`
  namespaces + landlock + HTTP egress proxy framework, new libc syscall
  bindings (capget/capset, unshare, setns, sethostname, pivot_root, landlock),
  and an HTTP fetch client written in C.
- **Primary consumer:** [whilp/cosmic](https://github.com/whilp/cosmic), which
  provides a typed Lua layer over this C implementation.

> All findings below are read-only analysis. No production code has been
> changed by this review; only this `PLAN.md` is added.

## Headline themes

1. **SSRF protection is incomplete in two independent places.** The
   cloud-metadata endpoint `169.254.169.254` (and `0.0.0.0/8`, CGNAT) is
   reachable through both the C `Fetch()` guard and the sandbox HTTP proxy.
2. **The most important sandbox confinement — landlock — is never wired into
   the sandbox examples.** FS confinement currently relies on `pivot_root`
   plus DAC only.
3. **A re-enabled test does not compile**, so the test suite is currently
   broken at HEAD.
4. **An attacker-controlled ZIP64 record count drives an unchecked allocation**
   in the zip appender, producing a heap overflow.

Severity legend: **CRITICAL** / **HIGH** / **MEDIUM** / **LOW** / **INFO**.

## Status / changelog

- **2026-06-12 — H2 (lzip ZIP64 overflow) implemented** on this branch. The
  appender now bounds `cnt` (`cnt < 0 || cnt > cdir_size / kZipCfileHdrMinSize`
  → reject), switches `malloc(cnt * sizeof)` to overflow-safe
  `calloc(cnt, sizeof)`, and handles the `cnt == 0` empty-archive path
  correctly. Builds clean; regression test added to
  `tool/lua/cosmo/zip/test_security.lua`. (Wire-level malicious-ZIP64 fixture
  left as a follow-up — the Lua harness can't easily craft raw binary.)
- **2026-06-12 — H1 (SSRF) implemented** on this branch (commit
  `security: fix SSRF guards...`). The fetch guards in `tool/net/lfetch.c` and
  `tool/net/fetch.inc` now block when `!IsPublicIp(ip)`, and
  `tool/lua/cosmo/sandbox/proxy.lua:dial()` gains a `cosmo.IsPublicIp(ip)`
  guard after `resolve_v4()` (covering both the CONNECT and plain-HTTP paths).
  `169.254.169.254`, `0.0.0.0/8`, and CGNAT are now rejected. Byte-order
  verified consistent (`ParseIp`/`ResolveIp`/`IsPublicIp` all host-order).
  Builds clean (`o/x86_64/tool/lua/lua.dbg`); tests added to
  `test/tool/net/lfetch_test.lua` for the link-local and `0.0.0.0` cases.
- **2026-06-12 — merged `master` up to `de0f3e56`.** PR #122
  ("parsehttpmessage: clamp resume position before capacity check") landed and
  **fully resolves** the parsehttpmessage clamp-ordering finding (see the
  ~~struck-through~~ entry in *Low / Info → libc syscall bindings & HTTP
  parsing*). The fix matches the recommendation exactly (clamp `r->i` to `n`
  before the `r->i < c` capacity test) and adds a `c == n+1` regression test.
  No other findings have been addressed yet.

---

## Critical / High

### H1 — SSRF guards miss the cloud-metadata endpoint (169.254.169.254)

- **Files:** `tool/net/fetch.inc` (~line 430), `tool/net/lfetch.c:892`,
  and `tool/lua/cosmo/sandbox/proxy.lua:374-389` (`dial`).
- **Severity:** HIGH.
- **Status: IMPLEMENTED on this branch (2026-06-12)** via `!IsPublicIp(ip)` in
  the fetch guards and a `cosmo.IsPublicIp(ip)` guard in `proxy.lua:dial()`.
  The description below records the original defect and the fix applied.

The `Fetch()` SSRF guard blocks only:

```c
if (!proxyhost && (IsLoopbackIp(ip) || IsPrivateIp(ip))) {
  ... return LuaNilError(L, "request to private network blocked (SSRF protection)");
}
```

Verified coverage of the helpers:

- `IsPrivateIp` (`libc/intrin/isprivateip.c`) — only `10/8`, `172.16/12`,
  `192.168/16`.
- `IsLoopbackIp` (`libc/intrin/isloopbackip.c`) — only `127/8`.

Therefore the following are **not** blocked and remain reachable:

- `169.254.0.0/16` link-local — including **`169.254.169.254`, the
  AWS/GCP/Azure cloud metadata endpoint** (classic SSRF credential-theft
  target).
- `0.0.0.0/8` (`0.0.0.0` routes to localhost on Linux).
- `100.64.0.0/10` (CGNAT) and other reserved ranges.

The sandbox proxy is worse: `dial()` performs **no internal-IP filtering at
all**, and it dials in the *parent* network namespace
(`unix.setns(upstream_ns_fd, CLONE_NEWNET)`), so the parent's real network —
loopback, link-local, RFC1918 — is reachable if a host is allowlisted or
resolves to an internal IP.

**Fix (clean, in-tree primitive already exists):** cosmopolitan ships
`IsPublicIp()` (`libc/intrin/ispublicip.c`), which correctly excludes
`0.0.0.0/8`, `10/8`, `127/8`, `169.254/16`, `172.16/12`, `192.0.0/24`,
`192.168/16`, `100.64/10`, `198.18/15`, `240/4`, and `255.255.255.255`.

- In `fetch.inc` / `lfetch.c`, replace
  `IsLoopbackIp(ip) || IsPrivateIp(ip)` with `!IsPublicIp(ip)`.
- In `proxy.lua:dial()`, after `resolve_v4()` returns the resolved IP, reject
  it when it is not public (mirror `IsPublicIp` logic, or expose it to Lua).
  Consider an explicit opt-in switch for operators who intentionally allowlist
  internal targets.

This is the single most important fix for the AI-agent sandboxing use case.

### H2 — lzip appender heap overflow from attacker-controlled ZIP64 record count

- **File:** `tool/net/lzip.c:1296`, `:1313`.
- **Severity:** HIGH (CRITICAL if append mode is exposed to untrusted archives).
- **Status: IMPLEMENTED on this branch (2026-06-12)** — `cnt` bounded against
  `cdir_size / kZipCfileHdrMinSize`, allocation switched to `calloc`, `cnt == 0`
  handled. The description below records the original defect.

```c
int64_t cnt = GetZipCdirRecords(eocd);   // full 64-bit ZIP64 field
...
a->existing = malloc(cnt * sizeof(*a->existing));   // unchecked size_t multiply
```

`GetZipCdirRecords` reads `ZIP_CDIR64_RECORDS`, a full 64-bit field from the
ZIP64 EOCD, so `cnt` is fully attacker-controlled and is never bounded against
`cdir_size`. A crafted `cnt` (e.g. ~`2^61`, where `sizeof(*a->existing)` ≈ 72
bytes wraps the product modulo `2^64`) makes `malloc` return a tiny/zero
buffer. The parse loop at `:1324` is bounded only by
`i + kZipCfileHdrMinSize <= cdir_size && got < cnt`, and `cdir_size` can be up
to `MAX_CDIR_SIZE` (256 MB), so it writes millions of `LuaZipCdirEntry`
structs into the undersized allocation — a controllable heap overflow.

The reader path is **not** affected (it copies raw cdir bytes rather than
allocating per-record).

**Fix:**
- Validate `cnt >= 0 && cnt <= cdir_size / kZipCfileHdrMinSize` before the
  allocation.
- Use an overflow-checked allocation (e.g. `calloc(cnt, sizeof(...))` or an
  explicit overflow check).
- Handle `cnt == 0` correctly: `malloc(0)` may return `NULL`, which is
  currently mis-treated as an allocation error for a valid empty archive.

### H3 — Sandbox examples never apply landlock; FS confinement is pivot_root-only

- **Files:** `tool/lua/cosmo/sandbox/examples/claude-code.lua:269-290`,
  `examples/fs-jail.lua`, `examples/netns-proxy.lua`; `landlock.lua` (unused).
- **Severity:** HIGH.

`landlock.lua` is fully implemented but **no example ever calls it**. The
privileged path does `unshare(CLONE_NEWNET|CLONE_NEWNS)` (note: no
`CLONE_NEWUSER`), builds the jail, then drops privileges. The advertised
"jail" therefore relies on `pivot_root` + DAC only, with no landlock FS
enforcement and no syscall filtering. Running as true root (not via sudo)
yields an especially weak jail, since the child remains root inside a mount
namespace it can manipulate.

**Fix:**
- Wire `landlock.restrict{...}` plus `no_new_privs` into the examples before
  `exec`.
- Document the root requirement and the weaker-as-true-root caveat.
- Provide a rootless (user-namespace) composition path using the existing
  `setup_userns_maps`.

### H4 — `fexecve_test.c` does not compile (build break at HEAD)

- **Files:** `test/libc/proc/fexecve_test.c:31`, `test/libc/proc/BUILD.mk:112`.
- **Severity:** HIGH (broken build) + MEDIUM (missing test dependency).

```c
STATIC_YOINK("zipos");     // line 31 — undefined macro

__static_yoink("zipos");   // line 33 — correct
```

`STATIC_YOINK` (uppercase) is defined nowhere in the tree; only
`__static_yoink` exists (`libc/integral/c.inc`). The file is compiled via the
`*_test.c` wildcard in `test/libc/proc/BUILD.mk`, so commit `bbe7b3cf`
("re-enable fexecve_test") re-enabled a test that is a hard compile error
(`error: expected declaration specifiers or '...' before string constant`).

Additionally, `BUILD.mk:112` `fexecve_test.dbg` is missing the
`o/$(MODE)/tool/build/echo.zip.o` dependency, while the re-enabled tests at
`fexecve_test.c:49` and `:67` call `testlib_extract("/zip/echo", "echo",
0111)`. Even after fixing line 31, those two tests will fail at runtime because
`/zip/echo` will not exist in the test binary.

**Fix:**
- Delete `fexecve_test.c:31` (line 33 already yoinks correctly).
- Add `echo.zip.o` to the `fexecve_test.dbg` dependency list (compare
  `posix_spawn_test.dbg`).

---

## Medium

### M1 — `getsslroots.c` trusts `SSL_CERT_FILE` without a setuid guard, and broadens the trust store by default

- **File:** `net/https/getsslroots.c:49-73`, `:110-121`.
- **Severity:** MEDIUM.

Two issues:

1. `getenv("SSL_CERT_FILE")` is honored as a trust-anchor source with no
   `issetugid()` guard. Cosmopolitan provides `secure_getenv()`
   (`libc/runtime/runtime.h`) for exactly this; OpenSSL ignores
   `SSL_CERT_FILE` in setuid contexts. In any privileged / inherited-environment
   scenario an attacker-controlled env var injects a rogue root CA.
2. The trust store is silently **broadened by default**: previously only the
   embedded `/zip/usr/share/ssl/root` certs were trusted; now
   `/etc/ssl/certs/ca-certificates.crt` (etc.) is loaded *in addition*, opt-out
   via `SSL_NO_SYSTEM_CERTS`. Any application that relied on the embedded
   (pinned) root set now also trusts locally installed CAs (e.g. corporate
   MITM proxies).

Also: all upstream error reporting (`perror` / `tinyprint`) was removed, so
root-loading failures are now silent and undiagnosable; and the loader stops
probing after the first bundle that yields ≥1 cert, even if that file was
mostly corrupt.

**Fix:** use `secure_getenv()` for `SSL_CERT_FILE` (and arguably
`SSL_NO_SYSTEM_CERTS`); consider making system-CA loading opt-in; restore a
diagnostic on total load failure.

### M2 — `resettls=true` default leaks/rebuilds redbean's shared server TLS config per `Fetch()`

- **File:** `tool/net/fetch.inc:225-227`.
- **Severity:** MEDIUM.

`resettls` now defaults to `true` and calls `LuaResetFetchTlsState()` before
`TlsInit()`. In **redbean** (which uses the `fetch.inc` path that does not
define `HAVE_LUA_RESET_FETCH_TLS_STATE`), the reset frees `confcli`/`rngcli`
and sets `sslinitialized=false`. Redbean's `TlsInit()` then re-runs
`mbedtls_ssl_config_defaults(...)` / `mbedtls_ssl_setup(...)` and
`LoadCertificates()` on the already-initialized **server** structures without
freeing them first, leaking their buffers/cert chains and reloading every
certificate on each HTTPS `Fetch()`.

**Fix:** scope the reset to once-per-process (post-fork) rather than per-call,
or free the server contexts before re-running `config_defaults`.

### M3 — TLS handshake can hang past the configured timeout (slow-loris)

- **File:** `tool/net/lfetch.c:1011-1024` (and the `fetch.inc` equivalent).
- **Severity:** MEDIUM.

Timeout is implemented only via `SO_RCVTIMEO`/`SO_SNDTIMEO` in `GoodSocket`.
In the handshake loop, an `SO_RCVTIMEO` expiry makes `read()` return `EAGAIN`,
`TlsRecvImpl` returns `MBEDTLS_ERR_SSL_WANT_READ`, and the loop simply re-calls
`mbedtls_ssl_handshake`, re-blocking for another full timeout indefinitely. The
configured timeout therefore does not bound a stalled TLS handshake.
(Subsequent streaming TLS reads do surface `WANT_READ` as an error, so only the
handshake spins.)

**Fix:** track a wall-clock deadline and abort the handshake loop when it is
exceeded.

### M4 — Read-only bind remount may leave writable sub-mounts

- **File:** `tool/lua/cosmo/sandbox/fs.lua:67-82`, `:118-123`.
- **Severity:** MEDIUM.

`private_root()` correctly applies `MS_REC|MS_PRIVATE` to `/`. However `bind()`
performs the read-only remount with
`MS_REMOUNT|MS_BIND|MS_RDONLY|MS_REC`, and on older kernels `MS_REC` on a
remount does **not** recursively re-apply read-only — sub-mounts under a
recursively-bound tree can remain writable, an escape from the intended
read-only guarantee.

**Fix:** walk the mount table and remount each sub-mount read-only, or use
`mount_setattr(AT_RECURSIVE)`.

### M5 — Namespace / listen / control fds are not `O_CLOEXEC` / `SOCK_CLOEXEC`

- **File:** `tool/lua/cosmo/sandbox/proxy.lua:803` (`unix.socket`),
  `tool/lua/cosmo/sandbox/netns.lua:108` (`unix.open(ns, O_RDONLY)`).
- **Severity:** MEDIUM.

None of the namespace, listening, or control fds are opened with
close-on-exec. In the current examples the hygiene happens to be correct purely
by fork/open/close ordering, but it is fragile: any future reordering, or any
`exec` between open and close, would leak the **upstream-namespace fd** to the
sandboxed child — which is a direct escape, since the child could `setns` back
to the parent network namespace. (`landlock.lua:131` already shows the right
pattern with `O_PATH|O_CLOEXEC`.)

**Fix:** open all namespace/listen/control fds with `O_CLOEXEC` /
`SOCK_CLOEXEC` as defense in depth.

### M6 — Plain-HTTP proxy path ignores `resolve_timeout_ms`

- **File:** `tool/lua/cosmo/sandbox/proxy.lua:654`.
- **Severity:** MEDIUM.

```lua
local up, derr = dial(host, port, self._upstream_ns_fd)   -- no resolve timeout
```

The 4th argument (`resolve_timeout_ms`) is omitted on the plain-HTTP path, so
HTTP requests use unbounded DNS resolution even when the operator configured a
timeout (the CONNECT path at `:591` passes it correctly). A hostile/tarpitting
resolver can wedge a per-connection worker.

**Fix:** pass `self._resolve_timeout_ms` here too.

### M7 — No private `/proc` helper and no PID namespace

- **Files:** `tool/lua/cosmo/sandbox/*.lua`, examples.
- **Severity:** MEDIUM.

No example uses `CLONE_NEWPID` (it is probed in `init.lua` but never used), and
the library offers no helper to mount a fresh `/proc`. A consumer who needs
`/proc` (many tools do) will bind the host's, exposing `/proc/PID/root`,
`/proc/PID/environ`, and `/proc/sys` of host processes.

**Fix:** add an `fs.proc()` helper that requires a PID namespace and mounts a
fresh procfs; document the hazard of binding the host `/proc`.

### M8 — lzip path validation misses Windows separators / absolute paths

- **File:** `tool/net/lzip.c:585-602` (`IsUnsafePath`).
- **Severity:** MEDIUM.

`IsUnsafePath` only treats `/` as a separator and only rejects `..` segments
delimited by `/`. On Windows (a supported Cosmopolitan target) `..\evil`,
backslash separators, and drive-absolute paths (`C:\x`) are not rejected.
Impact is limited because the reader does not extract to the filesystem, but a
consumer extracting these names on Windows would be exposed to zip-slip.

**Fix:** also treat `\` as a separator and reject drive-letter / UNC absolute
paths.

---

## Low / Info

### lzip (zip module)

- **LOW — Non-atomic in-place append corrupts archives/APEs on crash.**
  `tool/net/lzip.c:1605-1681` (`LuaZipAppenderClose`) rewrites the file in
  place starting at `data_end` (over the old central directory), then appends
  the new cdir + EOCD and `ftruncate`s — all on the original fd, with no
  temp-file + rename and no `fsync`. A crash/signal/ENOSPC after the old cdir is
  overwritten but before the new EOCD is fully written leaves the archive
  (including an APE executable) permanently corrupt. **Fix:** write to a temp
  copy and atomically rename, or at minimum `fsync` before truncate and
  document the destructive behavior.
- **LOW — `data_end` miscomputation can overwrite valid data / APE prefix.**
  `tool/net/lzip.c:1361-1384`: `max_data_end` is only advanced for entries
  whose local header passes validation; entries that fail are silently skipped.
  If all entries fail, `data_end = 0` and new local files are written at offset
  0, overwriting the APE prefix. The computed `prefix_size` is never used as a
  floor. **Fix:** derive `data_end` from `max(cdir_off, computed end)`, fail
  closed if a kept entry cannot be validated, and use `prefix_size` as a floor.
- **MEDIUM/LOW — OOB read on inputs < 4 bytes passed to `GetZipEocd`.**
  `tool/net/lzip.c:311` (`LuaZipFrom`, reachable from the arbitrary string
  passed to `zip.from()`) and `:228` (`LuaZipOpen`). Only `zsize == 0` is
  rejected; `GetZipEocd` starts at `i = n - 4`, an unsigned underflow when
  `n < 4`, then reads far out of bounds (DoS). **Fix:** require
  `zsize >= kZipCdirHdrMinSize` (22) before calling `GetZipEocd`.
- **LOW — `force_deflate` silently falls back to store** when compression does
  not shrink the data (`tool/net/lzip.c:1047`, `:1464`), so an explicit
  `method="deflate"` is ignored.
- **INFO — CRC/return computed over declared `uncompressed_size` rather than
  `strm.total_out`** (`:544`, `:550`); a legitimate short inflate would read
  uninitialized tail bytes (a malicious mismatch fails CRC first, so no data
  leak in practice). `avail_in`/`avail_out` are 32-bit `uInt`, so sizes
  truncate if a caller raises `max_file_size` above 4 GB (inflate underruns
  rather than overflows).

### HTTP fetch client

- **LOW — `timeout=0` does not mean infinite; negative `maxresponse` disables
  the size cap.** `tool/net/lfetch.c:663-676`, `fetch.inc`. Timeout is applied
  only `if (timeout_sec > 0)`, so `0` silently retains the 60s default;
  `maxresponse` read into a `size_t` wraps for negative Lua integers,
  effectively removing the 100 MB cap. **Fix:** document timeout semantics;
  reject negative `maxresponse`.
- **LOW — Streaming reader returns empty-string chunks** (`lfetch.c:524-528`).
  Chunk framing without payload yields `""` (truthy in Lua), which can spin a
  naive `while c = r:read() do` loop. Worth surfacing to wrapper authors.
- **LOW — OOM longjmp after socket/SSL ctx allocated leaks fd + memory.**
  `lfetch.c:1236-1240`: `lua_pushinteger`/`LuaPushHeaders`/`lua_newuserdata`
  can `longjmp` after `sock`/`sslctx`/`bio`/`inbuf.p` are live but before
  ownership transfers to the userdata. Edge OOM only; the normal error paths
  free everything and `FetchReaderClose` is idempotent (no double-close/UAF).
- **INFO — `Rdrand`/`Rdseed` are `arc4random64` aliases** (`tool/net/lfuncs.c:175-181`).
  Safer than raw hardware RNG, but the names mislead callers wanting true
  hardware entropy.
- **INFO — `unix://` proxy SSRF surface is constrained.** Proxy is taken only
  from `opts.proxy` / `http_proxy` env, never from the fetched URL, so a target
  URL cannot smuggle to an arbitrary unix socket; path is length-checked and
  passed through `IsReasonablePath`.

### libc syscall bindings & HTTP parsing

- **~~LOW — `parsehttpmessage.c` resume clamp is placed one line too late.~~**
  **RESOLVED in `de0f3e56` (PR #122).** Previously the clamp was inside
  `if (r->i < c)`, so when `r->i == n+1` and `c == n+1` the function returned
  `ebadmsg()` one byte prematurely. The fix moves the clamp before the capacity
  comparison exactly as recommended:
  ```c
  if (r->i > n) r->i = n;
  if (r->i < c) return 0;
  ```
  and adds `testResumeWhenCapacityEqualsReceivedPlusOne` covering the
  `c == n+1` case. (The fork's original change already fixed a real upstream
  resume byte-skip / parser-desync bug; this completes it.)
- **LOW — `unix.readlink` silently repurposed arg 2 from `dirfd` to `bufsiz`.**
  `third_party/lua/lunix.c:534-549`: upstream resolved `path` relative to a
  directory fd; the fork hardcodes `AT_FDCWD` and treats arg 2 as a buffer
  size. Existing callers passing a dirfd now mis-size the buffer. A negative
  `bufsiz` wraps to a huge `size_t` and raises a Lua memory error (fails safe).
  **Fix:** clamp `bufsiz` to a sane positive range; document the API break.
- **LOW — `unix.read` negative bufsiz not lower-clamped.**
  `third_party/lua/lunix.c:1693-1696` clamps only the upper bound
  (`MIN(bufsiz, 0x7ffff000)`); a negative value survives and triggers a
  spurious OOM `luaL_error`. Same pattern at lines ~2246/2273. **Fix:**
  `if (bufsiz < 0) bufsiz = 0;`.
- **LOW — `unix.ioctl` string path calls `malloc(0)` on an empty-string arg**
  (surfaces a spurious `ENOMEM`). Guard `len == 0`.
- **LOW — `lgetopt.c:124-135` leaks `argv`/`longopts` on OOM.** They are
  `calloc`'d before `lua_newuserdata`; if that raises an OOM Lua error
  (longjmp) the allocations leak because the owning userdata does not yet
  exist. **Fix:** allocate the userdata first, then the C buffers.
- **LOW — `sethostname.c` ENOSYS documentation is incomplete.**
  `libc/calls/sethostname.c:38,45` documents only "ENOSYS on Windows", but the
  call also returns ENOSYS on macOS/OpenBSD/NetBSD and likely FreeBSD (syscall
  88 is the COMPAT_43 `osethostname`, typically not enabled). **Fix:** document
  ENOSYS on all non-Linux hosts, gate `!IsLinux()`, or implement FreeBSD via
  `sysctl kern.hostname`.
- **LOW/INFO — `unescapeparam.c` `%00` decodes to an embedded NUL**, which is
  undocumented; the Lua binding is NUL-safe (`lua_pushlstring`) but C callers
  using `strlen` get silent truncation. The `'+'` conversion is unconditional
  despite the docstring saying "optionally", and `p == NULL` is only tolerated
  when `n == -1`. The decoder bounds (`i + 2 < n`) and single-pass logic are
  otherwise verified correct.

### Build / packaging

- **LOW — `bin/cosmic` downloads `cosmic-lua` over `curl` with no checksum**
  and `exec`s it. Inconsistent with the SHA-256-pinned
  `build/download-cosmocc.sh`. **Fix:** pin and verify a digest of the
  downloaded binary.
- **LOW — `build/download-cosmocc.sh:11` fallback URL is dead** for fork
  versions: `URL2="https://cosmo.zip/pub/cosmocc/cosmocc-${COSMOCC_VERSION}.zip"`
  with `COSMOCC_VERSION=cosmocc-2025.12.30-...` yields a double `cosmocc-`
  prefix. Fails safe because `sha256sum -c` rejects any mismatch, but the
  redundant-URL resilience is lost. **Fix:** correct or remove the fallback.

---

## Verified clean / positives

The following were specifically checked and found correct, and should **not**
be "fixed":

- **TLS posture in `lfetch.c`:** certificate verification is on by default and
  cannot be silently disabled (`MBEDTLS_SSL_VERIFY_REQUIRED` always set);
  hostname/SNI verification present; SSL errors surfaced via
  `DescribeSslVerifyFailure`; HTTPS→HTTP redirect downgrade refused;
  Authorization/Cookie stripped on cross-origin redirect; redirect count
  bounded (default 5).
- **CRLF header injection** is blocked in both `Fetch()` and the `http.serve`
  helper (`IsValidHttpHeaderValue` / `IsValidHttpToken`).
- **`FetchReaderClose` is idempotent** (guards `r->closed`) — no
  double-close/use-after-free in the GC/close paths.
- **`capget`/`capset` 64-bit mask splitting** is correct
  (`_Static_assert(sizeof(lua_Integer) >= 8)`, proper u32 split).
- **exec/spawn argv handling** NULL-checks before `strdup`, NULL-terminates,
  frees on every error path, and defaults `envp` to `environ`.
- **Syscall wrappers** `capget`/`capset`/`setns`/`unshare`/`sethostname` gate
  with `if (!IsLinux()) rc = enosys();`; syscall numbers verified against the
  (unchanged) upstream table for x86-64 and arm64; non-Linux slots `0xfff` →
  ENOSYS.
- **`fexecve` ELF-from-zip fix** (`IsApeBinary` splitting MZ/APE from `\177ELF`)
  is sound and has **no TOCTOU** — the conversion decision is made on the
  private memfd copy, not the original fd.
- **`unmount.h` include-guard rename** is a real fix: it previously collided
  with `mount.h`'s guard, silently hiding `MNT_*` declarations.
- **Sandbox positives:** `pivot_root` uses `MNT_DETACH` with correct `chdir`
  ordering; `private_root` uses `MS_REC|MS_PRIVATE`; `setgroups`-deny is
  written before `gid_map`; chunked transfer-encoding is rejected (411) and
  Content-Length is reauthored, closing the forwarded-request smuggling
  surface; `Handle:stop`/`alive` guard against PID reuse; `no_new_privs` is set
  before `exec` in the examples that exec directly.
- **Allowlist suffix matching** is safe against the `evil-github.com`-matches-
  `github.com` substring attack (suffixes are stored with a leading `.`).
- **Workflows** use `pull_request` (not `pull_request_target`), so untrusted PR
  code never runs with write tokens/secrets; third-party actions are pinned by
  full commit SHA; `amalgamate.sh` has no shell injection.

---

## Functional gaps to fill for cosmic

1. **Typed definitions for the sandbox.** `cosmo.sandbox.*`, `cosmo.zip`
   (`init.lua`), `cosmo.help`, `cosmo.skill`, and `cosmo.embed` currently have
   **zero LuaLS annotations**, and the sandbox API is entirely absent from
   `tool/net/definitions.lua`. Only `cosmo.http` is annotated. Since cosmic's
   value proposition is *typed* Lua and the sandbox is the most safety-critical
   surface, this is the largest completeness gap.
2. **Sandbox depth:** no seccomp/pledge wiring (pledge/unveil are only
   *probed*, never applied); no cgroup / PID / CPU / memory limits; no
   `setrlimit`; no rootless (user-namespace) composition path despite
   `setup_userns_maps` existing; IPv6 egress unsupported (`AF_INET` /
   `resolve_v4` only — CONNECT to IPv6 fails closed, which is safe but
   undocumented).
3. **Fetch:** no response decompression (gzip/deflate/br returned raw,
   `Accept-Encoding` not auto-handled); no cookie jar across redirects; proxy
   auth is Basic-only.
4. **zip:** no encryption support; only mtime timestamps (2-second DOS
   granularity, 1980+); no extraction helper (so zip-slip protection is the
   caller's responsibility — document it).

---

## Recommended remediation order

1. **PR 1 (quick, high-value):** ~~H1 (`!IsPublicIp` in fetch + sandbox
   proxy)~~ **[done]**, ~~H2 (bound the ZIP64 `cnt`)~~ **[done]**, H4 (delete
   `fexecve_test.c:31`, add the `echo.zip.o` BUILD.mk dep).
2. **PR 2 (sandbox hardening):** H3 (wire landlock + `no_new_privs`), M4
   (recursive RO remount), M5 (CLOEXEC on namespace/listen/control fds), M6
   (resolve timeout on the HTTP path), M7 (`fs.proc()` + PID namespace).
3. **PR 3 (TLS / certs):** M1 (`secure_getenv`, opt-in system CAs, restore
   diagnostics), M2 (`resettls` scope), M3 (handshake deadline).
4. **PR 4 (correctness/robustness):** the lzip atomicity/`data_end`/`GetZipEocd`
   bounds fixes and the various LOW `lunix`/`lgetopt`/`bin/cosmic` items.
   (The `parsehttpmessage` clamp ordering originally listed here was fixed
   separately in PR #122.)
5. **Ongoing:** the cosmic functional gaps, starting with sandbox type
   definitions.
