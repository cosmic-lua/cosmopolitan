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

## Performance: a rough same-process comparison

`bench.lua` times three decoders on identical payloads in the same
process (`os.clock()` process-CPU-time, warmup + a repeated timed loop
sized so each payload runs long enough to be measurable):

- `simdjson_decode()` -- `lsimdjson.cc`, the DOM-based wrapper above
- `simdjson_decode_ondemand()` -- `lsimdjson_ondemand.cc`, an
  `on_demand`-API sibling: forward-only iteration, no separate DOM
  "tape" built and then walked
- `cosmo_decode_json()` -- `ljson_wrapper.cc` registering this tree's
  real, unmodified `tool/net/ljson.c` parser, the one
  `cosmo.DecodeJson` actually calls (minus `opts.nullval` support, to
  keep the comparison to the parsing itself)

```sh
o/third_party/simdjson/poc/poc.dbg third_party/simdjson/poc/bench.lua
```

**First pass, naive table construction** (both simdjson wrappers used
plain `lua_newtable`):

```
payload                   bytes     dom(s)   ondmd(s)   ljson(s) dom-spdup  od-spdup
----------------------------------------------------------------------------------
tiny object                  33     0.0019     0.0018     0.0015     0.76x     0.82x
flat array (1k)            6632     0.0780     0.0687     0.1726     2.21x     2.51x
flat array (50k)         412966     0.1090     0.0972     0.2403     2.21x     2.47x
object array (200)        16413     0.4121     0.4057     0.2316     0.56x     0.57x
object array (10000)     865385     0.4691     0.4826     0.3108     0.66x     0.64x
```

Not the uniform win the SIMD pitch suggests: simdjson wins clearly on
flat numeric arrays (2.2-2.5x) and *loses* on object/string-heavy
payloads (0.56-0.82x), `on_demand` included -- which was the surprise.
The obvious hypothesis was DOM's two-pass design (build the full
indexed tape, then a second pass -- this binding's `PushElement`
recursion -- walks it into Lua tables) losing to `ljson.c`'s
single-pass recursive descent. `on_demand` exists specifically to skip
that separate tape: it iterates the JSON structure forward-only, in
document order, which is exactly the order a recursive
"materialize-into-Lua-tables" walk needs -- no random or backward
access required, so the "DOM was picked because on_demand's iterator
doesn't fit" reasoning an earlier revision of this file gave was
wrong. Yet `on_demand` above is statistically indistinguishable from
DOM on the losing cases. **The two-pass tape was not the bottleneck.**

**Root cause, found by checking what `ljson.c` does differently**:
`tool/net/ljson.c` pre-sizes every table it creates --
`lua_createtable(L, 8, 0)` for arrays, `lua_createtable(L, 0, 8)` for
objects (`tool/net/ljson.c:253,295`) -- while both simdjson wrappers
were calling plain `lua_newtable`, which starts empty and rehashes as
fields are inserted. That rehashing, not parsing architecture, was
what lost to `ljson.c` on payloads with many small objects. Fixed by
pre-sizing too: DOM's `dom::array`/`dom::object` carry an O(1)
`.size()` already (it's baked into the tape), so `PushObject`/
`PushArray` now call `lua_createtable(L, 0, obj.size())` /
`lua_createtable(L, arr.size(), 0)` for free. `on_demand` has no
tape to read a count from -- its `count_fields()`/`count_elements()`
are a documented last resort precisely because they scan ahead and
rewind, i.e. they buy the same pre-sizing by paying for a second pass,
the exact cost `on_demand` exists to avoid. Measured anyway, to see if
it's still worth it on net:

```
payload                   bytes     dom(s)   ondmd(s)   ljson(s) dom-spdup  od-spdup
----------------------------------------------------------------------------------
tiny object                  33     0.0012     0.0011     0.0015     1.30x     1.43x
flat array (1k)            6632     0.0654     0.0675     0.1642     2.51x     2.43x
flat array (50k)         412966     0.0852     0.0862     0.2179     2.56x     2.53x
object array (200)        16413     0.1975     0.2283     0.2428     1.23x     1.06x
object array (10000)     865385     0.2748     0.2889     0.3298     1.20x     1.14x
```

**Both simdjson variants now win everywhere tested.** Pre-sizing
alone took the object-heavy cases from ~0.6x to 1.06-1.30x; DOM keeps
a slightly larger margin than `on_demand` there specifically because
its count is free where `on_demand`'s costs a pass -- a real,
narrower version of the tradeoff the two-pass hypothesis originally
reached for, just not the one that actually explained the first
result.

**Lesson for anyone benchmarking a Lua C binding**: an unsized
`lua_newtable` on the hot path can plausibly cost more than which
JSON parser you picked. Check what the thing you're comparing against
already does before attributing a gap to architecture.

Caveats this still is: `os.clock()` in a handful of runs on one host
is not `cosmic`'s noise-aware `_perf` compare gate; none of this is
compiled `MODE=rel`/stripped/LTO, which is what actually ships; and
the synthetic payloads (`bench.lua`'s `make_flat_array`/
`make_object_array`) are not real-world JSON shapes. Real numbers need
`cosmic`'s `_perf` JSON scenarios once (if) this becomes a real
binding, per the `optimize` skill's loop.

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
- **once Lua tables are pre-sized, both simdjson wrappers win
  everywhere tested**: a same-process comparison against this tree's
  real `tool/net/ljson.c` initially showed simdjson losing
  0.56-0.86x on object/string-heavy payloads -- not DOM's two-pass
  design (an `on_demand` sibling showed the identical loss) but a
  missing optimization in this spike's own binding: `ljson.c`
  pre-sizes every table it creates and both simdjson wrappers were
  calling plain `lua_newtable`. Fixed, simdjson wins 1.06-2.56x across
  every payload shape tested (see "Performance" below)

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
  or replaces it outright is a real tradeoff -- worth a decision record
  (D24-style, on whichever side ends up owning the contract) -- the
  existing parser is a small, dependency-free, exception-free C
  recursive descent parser; simdjson is a multi-megabyte C++
  dependency. The spike's numbers now favor simdjson broadly rather
  than only on large payloads, which makes "replace" a live option,
  not just "augment for the big-document path" -- but see the caveats
  in "Performance" before reading too much into that
- **size cost, for real**: a rough baseline-vs-with-simdjson delta on
  this spike's throwaway dual-arch binary was ~600KB -> ~1.3MB (+~700KB
  across both architectures combined, `-O2`, unstripped, no LTO, whole
  translation unit linked in rather than only the symbols a real
  binding would touch) -- indicative only, not a number to cite as the
  real cost
- **perf win, for real**: a rough same-process comparison was run and,
  once a binding-side bug was fixed, favors simdjson everywhere tested
  (see "Performance" above) -- landing this as a real binding still
  needs `cosmic`'s `_perf` JSON scenarios (noise-aware, `MODE=rel`, the
  payloads that actually show up in practice) to say whether the win
  is real and large enough to justify the size and dependency
  cost, per the `optimize` skill's loop
- **exceptions story**: only confirmed exceptions are unused on the
  non-throwing on-demand path used here; did not check whether
  `-fno-exceptions` is viable for the whole translation unit (some
  simdjson surfaces, e.g. `padded_string::load`, throw by design)
- **MODE=rel / stripped / LTO sizing**, and whether cosmopolitan's
  existing ISA-level dispatch tooling should subsume or coexist with
  simdjson's own internal CPU dispatch, are both unexamined
