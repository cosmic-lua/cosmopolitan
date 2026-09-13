# simdjson buildability spike (POC, not a binding)

Answers two questions with two separate repros under `poc/`, neither
wired into the real make graph, `tool/net/`, or `definitions.lua` --
there is no `cosmo.*` binding yet:

1. does simdjson build under cosmocc and run as a cosmopolitan fat
   binary at all? (`poc.cpp`/`dispatch.cpp`, the packaged `cosmocc` SDK)
2. can a Lua script actually call into it? (`lsimdjson.cc`/`main.cc`,
   this repo's own make graph + the real, unmodified `third_party/lua`
   core)

## Result: yes, with one small header patch

simdjson 4.6.1's single-header amalgamation (`singleheader/simdjson.h`
+ `singleheader/simdjson.cpp`, ~9MB/~3MB of preprocessor-expanded
source) compiles clean under both `x86_64-linux-cosmo-g++` and
`aarch64-linux-cosmo-g++` (`-std=c++17 -O2`) and links via `apelink`
into a real dual-arch fat APE binary that runs.

One patch was needed: `poc/iterator-include.patch` adds a bare
`#include <iterator>` before `simdjson::internal::structure_analyzer`
(around line 11964), which uses `std::inserter` without including its
header. This never surfaces compiling `simdjson.cpp` itself, because
earlier code in that same translation unit happens to drag in
`<iterator>` transitively first -- it only surfaces in a second
translation unit that includes `simdjson.h` on its own (any real
binding's `.cc` file would do exactly this), and only because
cosmopolitan links against LLVM libc++, which does not backfill
transitive standard-header includes the way upstream's libstdc++-based
CI does. Same class of thing D21 (carried tl patches) exists for.

## Reproducing: does it build (packaged cosmocc SDK)

```sh
cd third_party/simdjson/poc
./fetch-poc.sh          # downloads simdjson.h/.cpp/.cc (pinned by sha256), applies the patch
export PATH=/path/to/.cosmocc/<version>/bin:$PATH
cosmoc++ -std=c++17 -O2 -c simdjson.cpp -o simdjson.o
cosmoc++ -std=c++17 -O2 -c poc.cpp -o poc.o
cosmoc++ -std=c++17 -O2 poc.o simdjson.o -o poc
echo '{"name":"cosmic"}' | ./poc     # -> name = cosmic

# confirm SIMD runtime dispatch works inside the APE sandbox
cosmoc++ -std=c++17 -O2 dispatch.cpp simdjson.o -o dispatch
./dispatch    # -> active implementation: haswell (Intel/AMD AVX2) on a modern x86_64 host
```

`poc.cpp` uses simdjson's non-throwing on-demand API
(`doc["field"].get(out)` returning an `error_code`, no exceptions) --
that's the shape a real binding would use to keep the "never throw
across the C boundary" contract from the C++ side, catching only what
simdjson itself can still throw (e.g. `padded_string::load`'s file-IO
path) at the wrapper's outermost frame.

## Reproducing: can Lua call it (this repo's own make graph)

`lsimdjson.cc` wraps simdjson's DOM API (not on-demand -- the DOM tree
needs to survive being walked recursively into Lua tables, which
on-demand's forward-only iterator doesn't support) as one Lua-callable
C function, `simdjson_decode(str) -> table|scalar, nil` or `nil, err`.
`main.cc` is a minimal stand-in for `tool/lua/lua`'s real entry point:
it embeds the actual, unmodified `third_party/lua/*.c` core (via
`third_party/lua/lua.a`, which this tree already builds) and registers
`simdjson_decode` as a global before running a script.
`third_party/simdjson/poc/BUILD.mk` (included from the top-level
`Makefile`) wires `simdjson.cc` + `lsimdjson.cc` + `main.cc` into one
target using this repo's normal C++ package conventions (the same
shape as `test/ctl/BUILD.mk`), linked against `THIRD_PARTY_LUA` +
`THIRD_PARTY_LIBCXX`/`LIBCXXABI`/`LIBUNWIND`:

```sh
cd third_party/simdjson/poc && ./fetch-poc.sh && cd ../../..
make -j$(nproc) o//third_party/simdjson/poc/poc.dbg
o/third_party/simdjson/poc/poc.dbg third_party/simdjson/poc/demo.lua
```

`demo.lua` decodes a JSON document with nested objects/arrays/a null/a
bool, asserts the whole shape came through correctly (JSON `null` ->
Lua `nil`, matching `cosmo.DecodeJson`'s no-sentinel default), and
exercises the parse-error path -> `nil, err`. Output:

```
name = cosmic-lua
tags = lua, teal, cosmopolitan
meta.simd = true
error path ok: TAPE_ERROR: The JSON document has an improper structure: ...
ALL OK
```

This is the real Lua core (not a toy re-implementation) linked against
real simdjson, both built by this repo's actual toolchain invocations
-- the only things cut short of a real binding are where it lives
(`third_party/simdjson/poc/` instead of `tool/net/`), how it's
registered (a hand-rolled `main.cc` instead of `tool/lua/cosmo/lua.main.c`
+ `lcosmo.c`'s real registration table), and the missing
`definitions.lua` entry the coverage ratchet would require.

## What this does and doesn't prove

Proven:
- the C++17 template/SIMD-dispatch code builds under cosmocc's GCC
  14.1.0 + LLVM libc++ toolchain for both architectures cosmopolitan
  ships, not just one
- simdjson's own runtime CPU-feature dispatch (separate from
  cosmopolitan's own ISA-level fat-binary mechanism) correctly detects
  and selects an implementation (haswell/AVX2 here) when running inside
  an APE binary
- a trivial on-demand parse round-trips correctly
- **a Lua script can call into it**: `simdjson_decode()` round-trips
  nested objects/arrays/strings/numbers/bools/null into real Lua
  tables/values, and the parse-error path returns `nil, err` with no
  C++ exception escaping into Lua -- built and run via this repo's own
  `make` graph, linked against the real `third_party/lua.a`
- a `.cc` binding file compiles cleanly in-tree alongside the existing
  all-C `tool/net/`-style build, once given its own `BUILD.mk` package
  (modeled on `test/ctl/BUILD.mk`) pulling in `THIRD_PARTY_LIBCXX` /
  `LIBCXXABI` / `LIBUNWIND` -- the C/C++ boundary itself isn't the
  obstacle a real binding would hit

Not proven / left for real integration work:
- **wired as a real `cosmo.*` binding**: living in `tool/net/`
  alongside `ljson.c` (not `third_party/simdjson/poc/`), registered
  through `tool/lua/lcosmo.c`'s real table (not a hand-rolled `main.cc`
  standing in for `tool/lua/cosmo/lua.main.c`), with matching
  `definitions.lua` `@param`/`@return` annotations the coverage ratchet
  requires, and a decision on whether `tool/net/BUILD.mk`-style
  packages should gain a C++ pattern rule or whether this stays a
  separate package the way `poc/BUILD.mk` does it here
- **decide push vs. replace**: whether this augments `cosmo.DecodeJson`
  for large-payload paths or replaces it outright is a real tradeoff --
  worth a decision record (D24-style, on whichever side ends up owning
  the contract) -- the existing parser is a small, dependency-free,
  exception-free C recursive descent parser; simdjson is a
  multi-megabyte C++ dependency that only wins on throughput for
  large-enough documents
- **size cost, for real**: a rough baseline-vs-with-simdjson delta on
  this spike's throwaway dual-arch binary was ~600KB -> ~1.3MB (+~700KB
  across both architectures combined, `-O2`, unstripped, no LTO, whole
  translation unit linked in rather than only the symbols a real
  binding would touch) -- indicative only, not a number to cite as the
  real cost
- **perf win, for real**: no benchmark was run; the whole point of
  landing this as a binding would be `cosmic`'s `_perf` JSON scenarios
  showing a decode/encode win worth the size and dependency cost, per
  the `optimize` skill's loop -- this spike is upstream of that, purely
  "does it build"
- **exceptions story**: only confirmed exceptions are unused on the
  non-throwing on-demand path used here; did not check whether
  `-fno-exceptions` is viable for the whole translation unit (some
  simdjson surfaces, e.g. `padded_string::load`, throw by design)
- **MODE=rel / stripped / LTO sizing**, and whether cosmopolitan's
  existing ISA-level dispatch tooling should subsume or coexist with
  simdjson's own internal CPU dispatch, are both unexamined
