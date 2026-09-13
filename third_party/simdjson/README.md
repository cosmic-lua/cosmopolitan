# simdjson buildability spike (POC, not a binding)

Answers one question: does simdjson build under cosmocc and run as a
cosmopolitan fat binary at all? Nothing here is wired into the make
graph, `tool/net/`, or `definitions.lua` -- there is no `cosmo.*`
binding yet. `poc/` is a standalone repro, not a build target.

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

## Reproducing

```sh
cd third_party/simdjson/poc
./fetch-poc.sh          # downloads simdjson.h/.cpp (pinned by sha256), applies the patch
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

Not proven / left for real integration work:
- **binding shape**: a thin `extern "C"` shim over the on-demand API
  returning cosmic's `value|nil, err` tuple, exceptions caught at the
  boundary, registered as a new `tool/net/lsimdjson.cc` (a `.cc` file
  alongside the existing `.c` bindings -- BUILD.mk needs a C++ rule
  added, there isn't one for `tool/net/*.c` today), plus the matching
  `definitions.lua` `@param`/`@return` annotations the coverage ratchet
  requires
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
