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

- **2026-06-12 — build/packaging LOW items (L5) implemented** on this branch.
  (1) `bin/cosmic` now has fail-closed integrity verification: a portable
  `_sha256` wrapper + `verify_file` that deletes the binary and exits non-zero
  on mismatch, with precedence pinned `EXPECTED_SHA256` → sidecar
  `${RELEASE_URL}.sha256` → a loud multi-line stderr WARNING when neither is
  available (the download still runs, but the gap is no longer silent). The
  happy path is preserved (skips straight to `exec` when the binary exists).
  **Maintainer action:** pin the real cosmic-lua SHA-256 in `EXPECTED_SHA256`
  (or publish a sidecar) to activate enforcement on first download.
  (2) `build/download-cosmocc.sh`: removed the dead double-prefixed `URL2`
  fallback (`cosmocc-cosmocc-...`, always 404, and would carry a non-matching
  upstream SHA anyway); URL1 + the fail-closed `sha256sum -c ... || die`
  verification are unchanged. Both scripts pass `sh -n`; no Makefile change.

- **2026-06-12 — small-C LOW items (L4) implemented** on this branch.
  (1) `lgetopt.c` `LuaGetoptNew` now creates the parser userdata first (NULL
  pointers, `LUA_NOREF` refs, metatable set) before `calloc`'ing argv/longopts
  and assigning them in — so an OOM `luaL_error` can't leak the C buffers
  (`__gc` is NULL-safe; no double-free). (2) `sethostname.c` doc corrected to
  state ENOSYS on all non-Linux hosts (Windows/macOS/the BSDs), not just
  Windows (comment-only). (3) `unescapeparam.c` docstring corrected: `'+'`→space
  is unconditional, output may contain embedded NULs (use the returned length,
  not `strlen`), and `p==NULL` is only valid when `n==-1` (decoding behavior
  unchanged). Builds clean; getopt + unescapeparam tests pass.

- **2026-06-12 — lunix LOW items (L3) implemented** on this branch.
  (1) `unix.readlink` arg-2 `bufsiz` is read as `lua_Integer` and clamped to
  `[BUFSIZ, 0x7ffff000]` (non-positive → BUFSIZ), with a comment noting the
  fork's arg-2 dirfd→bufsiz API change; no more huge-alloc OOM on a negative
  value. (2) Negative-size lower-clamp `if (bufsiz < 0) bufsiz = 0;` added to
  all three read-family sites — `unix.read`/`pread` (1700), `recvfrom` (2252),
  `recv` (2280) — before the existing `MIN(.., 0x7ffff000)` upper clamp.
  (3) `unix.ioctl` string path uses `malloc(len ? len : 1)` to avoid a spurious
  ENOMEM on an empty-string arg. Also corrected a pre-existing wrong assertion
  in `readlink_test.lua` (the impl returns `ENAMETOOLONG` on a full buffer, not
  silent truncation) and added bufsiz=0/-1 clamp tests. Builds clean; tests pass.

- **2026-06-12 — fetch-client LOW/INFO items (L2) implemented** on this branch.
  (1) `maxresponse` is now read as a signed `lua_Integer` and rejected with
  `luaL_argerror` when `< 0` in both `lfetch.c` and `fetch.inc` (closes the
  size-cap-disable footgun; test added). (2) `timeout=0` semantics documented
  at the parse sites and in `definitions.lua` (0/absent = default, no infinite
  option — behavior unchanged). (3) `LuaFetchStream` now creates the
  `FetchReader` userdata first, sets `sock=-1` before `setmetatable`, and
  transfers all resources (sock/sslctx/bio/buf) to it before the
  longjmp-capable `lua_pushinteger`/`LuaPushHeaders`, so an OOM longjmp can no
  longer leak the fd/mbedtls ctx/buffer; `FetchReaderClose` verified safe on
  the fully-initialized struct (idempotent, NULL-safe, no fd-0 close).
  (4) INFO: `Rdrand`/`Rdseed` doc now notes they return CSPRNG (arc4random64)
  output, not raw hardware instructions. H1/M2/M3 intact; builds clean
  (`lua.dbg` + `redbean`).

- **2026-06-12 — lzip LOW/INFO items (L1) implemented** on this branch
  (commit `robustness (lzip): ...`). (1) `zip.from()`/`zip.open()` now require
  `zsize >= kZipCdirHdrMinSize` (22) before `GetZipEocd`, fixing the <4-byte
  OOB-read DoS (tests added for `""`, `"PK"`, 21-byte inputs). (2) The appender
  now **fails closed** if any kept entry's local header is unreadable and
  floors `data_end` at `max(max_data_end, cdir_off)`, so it can never write new
  data over valid data or the APE prefix (no-op on well-formed archives).
  (3) `LuaZipAppenderClose` `fsync`s before and after `ftruncate` and documents
  that in-place append is NOT crash-atomic. (4) `force_deflate` now honors an
  explicit `method="deflate"` (emits a deflate stream even if not smaller).
  (5) CRC/length use `strm.total_out` captured before `inflateEnd()` instead of
  the declared size. H2 `cnt` bound untouched. Builds clean; all zip tests pass.

- **2026-06-12 — M3 (TLS handshake deadline) implemented** on this branch.
  Both `lfetch.c` and `fetch.inc` now capture a `CLOCK_MONOTONIC` deadline
  before the handshake loop and, on each `WANT_READ`/`WANT_WRITE` return,
  abort with "TLS handshake timed out" once it elapses — so a slow-loris peer
  can no longer wedge the handshake indefinitely despite the configured
  timeout (previously `SO_RCVTIMEO` expiry just re-blocked for another full
  period). Guarded by `fetchtimeout.tv_sec > 0`, so the no-timeout case is
  unchanged; cleanup on the abort path mirrors the sibling error returns
  (no fd/mbedtls leaks). Builds clean (`lua.dbg` + `redbean`); a real
  slow-loris integration test is a follow-up.
- **2026-06-12 — M2 (`resettls` per-Fetch server-TLS leak) implemented** on
  this branch. redbean now provides its own `LuaResetFetchTlsState()` (defining
  `HAVE_LUA_RESET_FETCH_TLS_STATE` to suppress the broken `fetch.inc` fallback)
  that only reseeds the client DRBG (`ReseedRng(&rngcli, "fetch")`) — it no
  longer frees `confcli` or clears `sslinitialized`, so each HTTPS `Fetch()` no
  longer re-runs `mbedtls_ssl_config_defaults()`/`LoadCertificates()` on the
  shared server structures (which leaked their buffers every call). The
  original post-fork DRBG-reseed fix (commit c055d331, fixing ~25% concurrent
  handshake failures) is preserved; `lfetch.c` is unaffected (already has its
  own impl). Builds clean (`lua.dbg` + `redbean`).
- **2026-06-12 — M1 (getsslroots hardening) implemented** on this branch.
  `SSL_CERT_FILE` and a new `SSL_USE_SYSTEM_CERTS` gate are now read via
  `secure_getenv()` (ignored under setuid/setgid/AT_SECURE), so an
  attacker-controlled inherited environment can't inject a rogue root CA into a
  privileged process. System CA bundles (`/etc/ssl/...`) are now **opt-in**
  (only with `SSL_USE_SYSTEM_CERTS`), restoring the pre-fork "embedded pinned
  roots only" default; the 14 embedded CAs cover the major public roots
  (ISRG/Let's Encrypt, DigiCert, GlobalSign, ...). A `tinyprint` diagnostic
  now fires if the trust store ends up empty. **Behavioral change:** clients
  relying on a system-only CA must now set `SSL_USE_SYSTEM_CERTS=1`. Builds
  clean; `getsslroots_test` passes.
- **2026-06-12 — M7 (`fs.proc()` + PID namespace) implemented** on this branch
  as composable building blocks. `fs.proc(dir)` mounts a hardened private
  procfs (`MS_NOSUID|MS_NODEV|MS_NOEXEC`) and `proc.fork_pidns()` does
  `unshare(CLONE_NEWPID)` + `fork()` so the child is PID 1 of a fresh pid
  namespace (the process that must call `fs.proc()` for it to show only
  sandbox processes). The host-`/proc` leak hazard (`/proc/<pid>/environ`,
  `cmdline`, `root`, `/proc/sys`) is documented. The examples were
  intentionally NOT rewired to compose a PID-ns layer (that changes the
  supervisor topology and interacts with the proxy netns/setns flow — a
  separate focused change). Minor API note: `fork_pidns()` returns `nil` for
  the child and `nil, err` on error, so callers must check the second value.
  Loads/syntax-check; smoke tests pass.
- **2026-06-12 — M6 (proxy HTTP-path resolve timeout) implemented** on this
  branch. The plain-HTTP `dial()` call now passes `self._resolve_timeout_ms`
  (matching the CONNECT path), so a tarpitting resolver can no longer wedge a
  per-connection worker on the HTTP path with unbounded DNS. Proxy unit +
  smoke tests pass.
- **2026-06-12 — M5 (CLOEXEC on namespace/listen/control fds) implemented** on
  this branch. The network-namespace fd (`netns.lua` `unix.open(".../ns/net")`)
  now uses `O_CLOEXEC` — closing the direct escape where a leaked ns fd would
  give the exec'd sandboxed child a `setns()` handle back to the parent net
  namespace. The proxy listening socket, the upstream `dial()` connection
  socket, and the netns control socket all gain `SOCK_CLOEXEC`. Verified that
  every `setns()` use is in-process (before any `exec`), so CLOEXEC — which
  only fires across `exec` — does not break the proxy worker's intended
  upstream-namespace use. `proc.lua` map-writing opens, `fs.lua` mountpoint
  opens, and the `Barrier` pipes are intentionally left as-is (closed in-scope
  / explicitly dropped before exec). Smoke + proxy unit tests pass.
- **2026-06-12 — M4 (recursive RO bind) implemented** on this branch.
  `fs.bind()` now, after the top-level `MS_REMOUNT|MS_BIND|MS_RDONLY`, parses
  `/proc/self/mountinfo` (`submounts_under()`) and RO-remounts every mount
  strictly under `dst`, since `MS_REC` on a remount does not propagate
  `MS_RDONLY` to sub-mounts. The initial bind keeps `MS_REC` so sub-mounts are
  replicated under `dst` first; the walk is guarded by `if rec` and is a no-op
  when there are no sub-mounts. `mount_setattr(2)` + `AT_RECURSIVE` would be
  the atomic single-syscall fix but `unix.mount_setattr` is not exposed by
  lunix.c (a worthwhile future binding). Minor follow-up: only the `\040`
  (space) mountinfo escape is decoded, not tab/newline/backslash (a mismatched
  exotic path would just fail the remount — fail-closed). Loads/syntax-checks;
  smoke tests pass.
- **2026-06-12 — H3 (landlock wiring) implemented** on this branch.
  `claude-code.lua` and `fs-jail.lua` now apply `landlock.restrict{}` after
  `pivot_root` + privilege drop + `no_new_privs` and before `exec`
  (composition order `mounts → pivot_root → drop_privs → no_new_privs →
  landlock → exec`). Rules are derived from the same bind plan the jail uses
  (RO binds → `READ|EXEC`, project/`~/.claude`/`/tmp` → `RW`); verified that
  binds map each path to the same absolute path inside the jail, so the
  `open(O_PATH)` rule resolution is correct post-pivot. Both examples
  **fail closed** if `landlock.available()` is false (refuse to exec rather
  than run with a weaker pivot-root-only jail). `netns-proxy.lua` left
  untouched (no FS jail). Files load/syntax-check; sandbox smoke tests pass.
- **2026-06-12 — H4 (fexecve_test build break) implemented** on this branch.
  Removed the undefined `STATIC_YOINK` line, added the missing
  `echo.zip.o` dep to the `fexecve_test.dbg` link rule, and supplied the
  `O_EXEC`/`memfd_create` definitions the re-enabled test needs (these were
  latent because upstream `#if 0`'d the whole file). The test now builds and
  links. Re-enabling also surfaced one genuinely unreliable subtest,
  `elfIsUnreadable_mayBeExecuted` (fexecve of an execute-only APE returns
  ENOEXEC on Linux — the same reliability limitation behind upstream's
  `#if 0`); it is gated with `if (1) return;` like the file's existing
  `memfd_create` case, leaving the other 25 tests enabled. Suite passes
  (exit 0). **Note:** the underlying fexecve limitation is a real follow-up
  (fix `fexecve` for execute-only images, or leave gated).
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
- **Status: IMPLEMENTED on this branch (2026-06-12)** — `claude-code.lua` and
  `fs-jail.lua` now apply `landlock.restrict{}` (after `no_new_privs`, before
  `exec`) and fail closed when landlock is unavailable. Description below
  records the original defect. (`netns-proxy.lua` has no FS jail; left as-is.)

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
- **Status: IMPLEMENTED on this branch (2026-06-12)** — stray `STATIC_YOINK`
  removed, `echo.zip.o` dep added, `O_EXEC`/`memfd_create` defs supplied, and
  the one unreliable `elfIsUnreadable_mayBeExecuted` subtest gated. Suite
  builds, links, and passes. Description below records the original defect.

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
- **Status: IMPLEMENTED on this branch (2026-06-12)** — `secure_getenv` for
  trust-anchor env vars; system CAs opt-in; empty-store diagnostic restored.

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
- **Status: IMPLEMENTED on this branch (2026-06-12)** — redbean-specific
  reset reseeds only the client DRBG; server TLS state no longer rebuilt
  per Fetch. (Implemented in `tool/net/redbean.c`.)

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
- **Status: IMPLEMENTED on this branch (2026-06-12)** — monotonic handshake
  deadline added to both files; WANT_READ/WANT_WRITE re-block now bounded.

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
- **Status: IMPLEMENTED on this branch (2026-06-12)** — `bind()` now walks
  `/proc/self/mountinfo` and RO-remounts each sub-mount under `dst`.
  Description below records the original defect.

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
- **Status: IMPLEMENTED on this branch (2026-06-12)** — namespace fd now
  `O_CLOEXEC`; listen/upstream/control sockets now `SOCK_CLOEXEC`; in-process
  `setns` use verified unaffected. Description below records the original
  defect.

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
- **Status: IMPLEMENTED on this branch (2026-06-12)** — plain-HTTP `dial()`
  now passes `self._resolve_timeout_ms`.

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

- **LOW — Non-atomic in-place append corrupts archives/APEs on crash.** _[MITIGATED — L1: fsync + documented]_
  `tool/net/lzip.c:1605-1681` (`LuaZipAppenderClose`) rewrites the file in
  place starting at `data_end` (over the old central directory), then appends
  the new cdir + EOCD and `ftruncate`s — all on the original fd, with no
  temp-file + rename and no `fsync`. A crash/signal/ENOSPC after the old cdir is
  overwritten but before the new EOCD is fully written leaves the archive
  (including an APE executable) permanently corrupt. **Fix:** write to a temp
  copy and atomically rename, or at minimum `fsync` before truncate and
  document the destructive behavior.
- **LOW — `data_end` miscomputation can overwrite valid data / APE prefix.** _[FIXED — L1]_
  `tool/net/lzip.c:1361-1384`: `max_data_end` is only advanced for entries
  whose local header passes validation; entries that fail are silently skipped.
  If all entries fail, `data_end = 0` and new local files are written at offset
  0, overwriting the APE prefix. The computed `prefix_size` is never used as a
  floor. **Fix:** derive `data_end` from `max(cdir_off, computed end)`, fail
  closed if a kept entry cannot be validated, and use `prefix_size` as a floor.
- **MEDIUM/LOW — OOB read on inputs < 4 bytes passed to `GetZipEocd`.** _[FIXED — L1]_
  `tool/net/lzip.c:311` (`LuaZipFrom`, reachable from the arbitrary string
  passed to `zip.from()`) and `:228` (`LuaZipOpen`). Only `zsize == 0` is
  rejected; `GetZipEocd` starts at `i = n - 4`, an unsigned underflow when
  `n < 4`, then reads far out of bounds (DoS). **Fix:** require
  `zsize >= kZipCdirHdrMinSize` (22) before calling `GetZipEocd`.
- **LOW — `force_deflate` silently falls back to store** _[FIXED — L1]_ when compression does
  not shrink the data (`tool/net/lzip.c:1047`, `:1464`), so an explicit
  `method="deflate"` is ignored.
- **INFO — CRC/return computed over declared `uncompressed_size` rather than
  `strm.total_out`** _[FIXED — L1]_ (`:544`, `:550`); a legitimate short inflate would read
  uninitialized tail bytes (a malicious mismatch fails CRC first, so no data
  leak in practice). `avail_in`/`avail_out` are 32-bit `uInt`, so sizes
  truncate if a caller raises `max_file_size` above 4 GB (inflate underruns
  rather than overflows).

### HTTP fetch client

- **LOW — `timeout=0` does not mean infinite; negative `maxresponse` disables
  the size cap.** _[FIXED — L2: maxresponse rejected; timeout documented]_ `tool/net/lfetch.c:663-676`, `fetch.inc`. Timeout is applied
  only `if (timeout_sec > 0)`, so `0` silently retains the 60s default;
  `maxresponse` read into a `size_t` wraps for negative Lua integers,
  effectively removing the 100 MB cap. **Fix:** document timeout semantics;
  reject negative `maxresponse`.
- **LOW — Streaming reader returns empty-string chunks** (`lfetch.c:524-528`). _[documented — L2 (behavior left as-is)]_
  Chunk framing without payload yields `""` (truthy in Lua), which can spin a
  naive `while c = r:read() do` loop. Worth surfacing to wrapper authors.
- **LOW — OOM longjmp after socket/SSL ctx allocated leaks fd + memory.** _[FIXED — L2]_
  `lfetch.c:1236-1240`: `lua_pushinteger`/`LuaPushHeaders`/`lua_newuserdata`
  can `longjmp` after `sock`/`sslctx`/`bio`/`inbuf.p` are live but before
  ownership transfers to the userdata. Edge OOM only; the normal error paths
  free everything and `FetchReaderClose` is idempotent (no double-close/UAF).
- **INFO — `Rdrand`/`Rdseed` are `arc4random64` aliases** (`tool/net/lfuncs.c:175-181`). _[documented — L2]_
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
- **LOW — `unix.readlink` silently repurposed arg 2 from `dirfd` to `bufsiz`.** _[FIXED — L3: clamped + documented]_
  `third_party/lua/lunix.c:534-549`: upstream resolved `path` relative to a
  directory fd; the fork hardcodes `AT_FDCWD` and treats arg 2 as a buffer
  size. Existing callers passing a dirfd now mis-size the buffer. A negative
  `bufsiz` wraps to a huge `size_t` and raises a Lua memory error (fails safe).
  **Fix:** clamp `bufsiz` to a sane positive range; document the API break.
- **LOW — `unix.read` negative bufsiz not lower-clamped.** _[FIXED — L3: read/recv/recvfrom]_
  `third_party/lua/lunix.c:1693-1696` clamps only the upper bound
  (`MIN(bufsiz, 0x7ffff000)`); a negative value survives and triggers a
  spurious OOM `luaL_error`. Same pattern at lines ~2246/2273. **Fix:**
  `if (bufsiz < 0) bufsiz = 0;`.
- **LOW — `unix.ioctl` string path calls `malloc(0)` on an empty-string arg** _[FIXED — L3]_
  (surfaces a spurious `ENOMEM`). Guard `len == 0`.
- **LOW — `lgetopt.c:124-135` leaks `argv`/`longopts` on OOM.** _[FIXED — L4]_ They are
  `calloc`'d before `lua_newuserdata`; if that raises an OOM Lua error
  (longjmp) the allocations leak because the owning userdata does not yet
  exist. **Fix:** allocate the userdata first, then the C buffers.
- **LOW — `sethostname.c` ENOSYS documentation is incomplete.** _[FIXED — L4: doc]_
  `libc/calls/sethostname.c:38,45` documents only "ENOSYS on Windows", but the
  call also returns ENOSYS on macOS/OpenBSD/NetBSD and likely FreeBSD (syscall
  88 is the COMPAT_43 `osethostname`, typically not enabled). **Fix:** document
  ENOSYS on all non-Linux hosts, gate `!IsLinux()`, or implement FreeBSD via
  `sysctl kern.hostname`.
- _[documented — L4]_ **LOW/INFO — `unescapeparam.c` `%00` decodes to an embedded NUL**, which is
  undocumented; the Lua binding is NUL-safe (`lua_pushlstring`) but C callers
  using `strlen` get silent truncation. The `'+'` conversion is unconditional
  despite the docstring saying "optionally", and `p == NULL` is only tolerated
  when `n == -1`. The decoder bounds (`i + 2 < n`) and single-pass logic are
  otherwise verified correct.

### Build / packaging

- **LOW — `bin/cosmic` downloads `cosmic-lua` over `curl` with no checksum** _[FIXED — L5: verification added; maintainer must pin hash]_
  and `exec`s it. Inconsistent with the SHA-256-pinned
  `build/download-cosmocc.sh`. **Fix:** pin and verify a digest of the
  downloaded binary.
- **LOW — `build/download-cosmocc.sh:11` fallback URL is dead** for fork _[FIXED — L5: dead fallback removed]_
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
   proxy)~~ **[done]**, ~~H2 (bound the ZIP64 `cnt`)~~ **[done]**, ~~H4 (delete
   `fexecve_test.c:31`, add the `echo.zip.o` BUILD.mk dep)~~ **[done]**.
2. **PR 2 (sandbox hardening):** ~~H3 (wire landlock + `no_new_privs`)~~
   **[done]**, ~~M4 (recursive RO remount)~~ **[done]**, ~~M5 (CLOEXEC on
   namespace/listen/control fds)~~ **[done]**, ~~M6 (resolve timeout on the HTTP
   path)~~ **[done]**, M7 (`fs.proc()` + PID namespace).
3. **PR 3 (TLS / certs):** ~~M1 (`secure_getenv`, opt-in system CAs, restore
   diagnostics)~~ **[done]**, M2 (`resettls` scope), M3 (handshake deadline).
4. **PR 4 (correctness/robustness):** the lzip atomicity/`data_end`/`GetZipEocd`
   bounds fixes and the various LOW `lunix`/`lgetopt`/`bin/cosmic` items.
   (The `parsehttpmessage` clamp ordering originally listed here was fixed
   separately in PR #122.)
5. **Ongoing:** the cosmic functional gaps, starting with sandbox type
   definitions.
