# AGENTS.md

## What this repository is

cosmic-lua/cosmopolitan is a fork of
[jart/cosmopolitan](https://github.com/jart/cosmopolitan) slimmed to its
C core. Its primary downstream consumer is
[cosmic-lua/cosmic](https://github.com/cosmic-lua/cosmic), a batteries-included
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

Default mode (`MODE=` empty, -O2 with ftrace hooks and SYSDEBUG) is
what local development uses; build in it unless you have a reason not
to. The RELEASE `lua` ships as `MODE=rel` (NDEBUG, DWARFLESS, no
ftrace padding), so `--strace`/`--ftrace` live on the released
`lua-debug`, which stays default mode. Relative comparisons between two
default-mode local builds remain representative; rel-vs-rel is the
closer match to what ships.

## Performance work

Performance work on this repo is measured and driven from a cosmic
checkout — its benchmark harness exercises these bindings end to end,
and its `optimize` skill holds the whole loop, including the C-layer
chapter for working from a locally built `lua`. Nothing about that loop
is documented here. The backlog does not live here either: open,
evidence-backed hypotheses targeting this repo are items on cosmic's
work board (the `work` skill in cosmic-lua/cosmic), carrying this repo as
the item's `--repo`. Legacy `perf`-labeled issues here remain readable
evidence a board item may link, never duplicate.

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
- a binding's contract shape follows one rule: an argument-shape
  error — a degenerate input no correct program passes (zero or
  all-nil components, an invalid clock or fd constant, a malformed
  flags value) — raises through `luaL_argerror`/`luaL_error` (PR
  #276, PR #277). A failure a correct caller can meet at runtime —
  bad input DATA or a changed ENVIRONMENT (ENOENT, EINTR, a truncated
  buffer) — returns the fallible tuple `value|nil, err:string,
  errno?`, the error always in slot 2 and nothing else sharing a slot
  (issue #151). When slot 1 of a declared return admits nil, slot 2
  is the error — an annotation that deviates is a bug, and a contract
  change to conform is made deliberately (`definitions.lua` same
  commit, conformance probe same PR), never inside another change.
  Slot 3 defaults to `errno`, but a binding with no syscall in play —
  a parser refusing its input rather than an OS call failing — may
  carry a different, still-documented slot 3 instead:
  `cosmo.DecodeLua`'s is the 1-based byte offset the refusal happened
  at, not `unix.Errno`, kept out of slot 2's message so a caller that
  wants a line number counts newlines up to the offset once, on the
  refusal path, rather than the binding counting them on every parse.
  Such a deviation is a per-binding exception recorded in its
  `definitions.lua` `@return` doc, never a silent drift from the
  archetype.
- **named exception — multi-value success reuses its own slots for
  error info**: a small set of bindings return more than one genuine
  value on success and fall back to the same slot positions for error
  info on failure: `unix.accept` (`clientfd, ip, port` vs. `nil, error,
  errno`) and `cosmo.Fetch`/`cosmo.FetchStream` (`status, headers,
  body|reader, url` vs. `nil, error, kind` — `kind` standing in for
  `errno` as a machine-readable string enum). This is not a slot
  violation: slot 1 still disambiguates the branch exactly as the rule
  above requires, and once a caller has checked it, slot 2 is
  unambiguously the error and slot 3 unambiguously `errno`/`kind` —
  the same discipline as a single-value binding, just with more
  success data ahead of it. `Fetch` and `FetchStream` follow this
  consistently with each other (arity-4 success, arity-3 failure) and
  with the rest of this family; it is accepted as-is, not scheduled
  for normalization.

## Releases and the cosmic pin

Every push to master triggers the release workflow: it builds fat
(x86_64+aarch64) `lua`, `lua-debug`, `zip`, and `unzip` binaries, packs
`cosmos.zip`, and publishes a release tagged `YYYY.MM.DD-<short-sha>`.
cosmic consumes it by bumping `3p/cosmos/cosmos_pin.tl` (version +
sha256), then `bin/cosmic --make fetch && bin/cosmic --make ci` — the
`cosmo.*` Teal types are generated by the build from this repo's
`tool/net/definitions.lua`, so there is no regen step — plus the
compare gate against the previous pin.
