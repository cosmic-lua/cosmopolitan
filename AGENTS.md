# AGENTS.md

## What this repository is

whilp/cosmopolitan is a fork of
[jart/cosmopolitan](https://github.com/jart/cosmopolitan) slimmed to its
C core. Its primary downstream consumer is
[whilp/cosmic](https://github.com/whilp/cosmic), a batteries-included
Lua/Teal distribution: every release of this repo publishes a `cosmos.zip`
(fat `lua`, `lua-debug`, `zip`, `unzip` binaries) that cosmic pins by
version + sha256 and wraps with its typed standard library.

That relationship drives most work here:

- the `cosmo.*` Lua bindings live in `tool/net/*.c` (ljson, lsqlite3,
  lre, lpath, lfuncs, largon2, lfetch, ...) and `tool/lua/lcosmo.c`
- `tool/net/definitions.lua` is the single source of truth for binding
  annotations; cosmic generates its Teal type declarations from it, and
  the coverage ratchet test here fails if a binding loses or drifts its
  `@param`/`@return` annotations. If you add or change a binding, update
  `definitions.lua` in the same commit.
- the Lua interpreter is `third_party/lua/`; the libc, APE loader, and
  zip filesystem (`libc/`, `ape/`, `libc/zipos/`) are what cosmic's
  binary-startup benchmarks measure.

## Building

Linux + GNU make. The first build downloads the cosmocc toolchain into
`.cosmocc/` (network needed once); after that builds are hermetic.

```bash
make -j$(nproc) o//tool/lua/lua     # single-arch APE lua binary
make -j$(nproc) o//tool/lua/test    # binding tests + annotation ratchet
```

A cold build of the lua target takes a few minutes; an incremental
rebuild after a one-file C edit is ~2 seconds. `o//tool/lua/lua.dbg` is
the same binary as a plain ELF with symbols — Linux `perf record`/`perf
report` work on it directly, and every default-mode binary supports
`--strace` (syscall log) and `--ftrace` (C function call log).

Default mode (`MODE=` empty, -O2 with ftrace hooks and SYSDEBUG) is what
releases ship; build in default mode unless you have a reason not to.

## Performance work

cosmic's benchmark harness is the measurement tool for this repo's hot
paths — its ~25 end-to-end scenarios (JSON, SQLite, fs, startup, spawn,
...) each validate their own output, and its comparison gate is
noise-aware. The loop is documented in cosmic at
`lib/perf/OPTIMIZE.md`, with the C-layer specifics (how to wrap a
locally built `lua` from THIS checkout into a measurable cosmic binary
via `bin/make perf-bin`, and the guardrails) in
`lib/perf/optimize/cosmopolitan.md`. Open, evidence-backed hypotheses
targeting this repo are tracked there too:
`grep -l "layer: cosmopolitan" lib/perf/backlog/*.md`.

Short version, run from a cosmic checkout:

```bash
make -C ~/cosmopolitan -j$(nproc) o//tool/lua/lua
COSMO_LUA=~/cosmopolitan/o/tool/lua/lua bin/make perf-bin
PERF_BIN=o/perf/cosmic-local bin/make perf-baseline
# ...edit C here, rebuild, perf-bin again...
PERF_BIN=o/perf/cosmic-local bin/make perf-compare
```

Always A/B two local builds that differ only by your change; never
judge a change by comparing a local build against the pinned release.
Quote the `perf-compare` lines in your PR.

## Conventions

- keep the fork mergeable with upstream jart/cosmopolitan: surgical
  diffs, no drive-by reformatting or restructuring.
- binding contracts (return shapes, error values, constants) are frozen
  at the C boundary — cosmic's generated types and wrappers depend on
  them. A deliberate contract change needs a matching
  `definitions.lua` update here and a type regen + wrapper fix on the
  cosmic side, landed as its own change, never inside an optimization.
- correctness gates before any PR: `make -j$(nproc) o//tool/lua/test`.
  Changes outside the Lua surface should also build and run the tests
  of the subsystem they touch (`make o//test/libc/...`).

## Releases and the cosmic pin

Every push to master triggers the release workflow: it builds fat
(x86_64+aarch64) `lua`, `lua-debug`, `zip`, and `unzip` binaries, packs
`cosmos.zip`, and publishes a release tagged `YYYY.MM.DD-<short-sha>`.
cosmic consumes it by bumping `3p/cosmos/version.lua` (version +
sha256), regenerating types (`bin/make regen-types`), and running its
full CI plus `perf-compare` against the previous pin.
