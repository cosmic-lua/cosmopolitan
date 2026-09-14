# simdjson buildability spike (POC, not a binding)

Answers four questions with a handful of repros under `poc/`, none
wired into the real make graph, `tool/net/`, or `definitions.lua` --
there is no `cosmo.*` binding yet:

1. does simdjson build under cosmocc and run as a cosmopolitan fat
   binary at all? (`poc.cpp`/`dispatch.cpp`, the packaged `cosmocc` SDK)
2. can a Lua script actually call into it? (`lsimdjson.cc`/`main.cc`,
   this repo's own make graph + the real, unmodified `third_party/lua`
   core)
3. is it actually faster than `ljson.c`? (`bench.lua`; the honest
   answer is "it depends on payload size" -- see "Performance")
4. is it actually correct? (`conformance.lua`, against JSONTestSuite;
   the honest answer is "DOM yes, `on_demand` no" -- see "Conformance",
   which also documents a process-crashing bug this check found and a
   fix for it)

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
`make_object_array`) are not real-world JSON shapes -- see
"Conformance" below for what happens on a corpus of real ones.

## Conformance: JSONTestSuite, and a crash it found

`conformance.lua` reuses this repo's own `tool/lua/test_jsontestsuite_*.lua`
corpus (Nicolas Seriot's JSONTestSuite, already vetted against
`ljson.c`) rather than hand-picked cases: it stubs `cosmo.DecodeJson`
to harvest every JSON literal those six files exercise (336 total),
then actually decodes each one with all three real decoders and
compares accept/reject against `cosmo_decode_json()` (the real
`ljson.c`).

```sh
o/third_party/simdjson/poc/poc.dbg third_party/simdjson/poc/conformance.lua
```

**It immediately found a process-crashing bug.** JSONTestSuite ships
`i_structure_500_nested_arrays.json` -- 500 levels of `[` -- specifically
to probe parsers for exactly this. `ljson.c` has its own `DEPTH` cap
(64) and rejects it cleanly; neither simdjson wrapper had any such
guard, since `PushElement`/`PushValue` recurse once per JSON nesting
level with no limit. The result wasn't a graceful `nil, err` but a
`SIGILL` abort (`unassert((L->top.p <= L->ci->top.p) && "stack
overflow")`) -- Lua's own internal call-depth accounting tripping, not
a native segfault, but just as fatal to the process. Matching
`ljson.c`'s cap number-for-number wasn't enough: each level of this
wrapper's recursion makes several raw Lua C API calls
(`lua_createtable`, `lua_settable`/`lua_seti`, `on_demand`'s
`count_fields()`/`count_elements()`) that `ljson.c`'s leaner native
recursion doesn't pay per level, so the *actual* safe ceiling is much
lower than 64. Measured empirically, one process per depth since a
crash takes the whole process down: DOM survives to depth 19 and aborts
at 21; `on_demand` survives to 18 and aborts at 20. Both wrappers now
guard at a conservative `kMaxDepth = 16` and throw a catchable
exception past it -- verified clean (no crash, no matter how deep,
`nil, "nesting too deep"` past 16 and simdjson's own `DEPTH_ERROR`
past its internal 1024-level limit) from depth 17 up to 5000.

The corpus also caught a real, narrower bug on the way: the
`on_demand` entry point converted the root `document` to a generic
`value` via `.get_value().value()` before dispatching, which
(needlessly, it turns out -- `document` already satisfies the same
`type()`/`get_object()`/etc. interface) breaks on a bare scalar-at-root
document (`" null "`, `" 42 "`). Fixed by handling container-at-root
(object/array, which still needs `get_value()` -- calling
`document::get_object()` directly conflicts with the root iterator's
own bookkeeping) and scalar-at-root (which doesn't) as two explicit
cases. Separately, several `assert(!error)` calls in the `on_demand`
wrapper turned out not to be safe assumptions: DOM fully validates and
unescapes strings while building its tape during `parser.parse()`, so
by the time you read a DOM string it can't fail -- but `on_demand` is
lazy, `type()` only peeks, and the real unescape/validate happens
later inside `get_string()`, where malformed UTF-8 escapes (exactly
what JSONTestSuite's adversarial cases contain) can and do fail. All
of those are now propagated as a catchable exception (a small
`Unwrap()` helper) instead of aborting.

**With all of that fixed, here's the real split** (`strict` = the
`pass`/`fail1-4` files, which encode JSON's actual grammar and where
`ljson.c` is the correct answer to match; `okay` = JSONTestSuite's
`i_`-prefixed bucket, inputs the spec itself leaves
implementation-defined -- lone UTF-16 surrogates in `\u` escapes,
numbers that overflow to `Infinity`, a leading BOM -- where
disagreeing with `ljson.c`'s particular choice isn't a bug):

```
DOM: 0 strict bugs, 27 implementation-defined disagreements (of 336 cases)
on_demand: 37 strict bugs, 24 implementation-defined disagreements (of 336 cases)
```

**DOM is fully conformant** against the strict corpus -- every
disagreement is on genuinely spec-ambiguous input, the same shape of
thing `ljson.c` itself had to make an arbitrary call on. **`on_demand`
is not**: 37 cases where it accepts input `ljson.c` (correctly) rejects
-- `[.123]`, `[NaN]`, `[Infinity]`, `[+1]`, bare `abc`, `{}}`, trailing
garbage after a closing bracket. The common thread in several of these
is `on_demand`'s root/element `type()` apparently misclassifying
certain malformed leading tokens as `json_type::null` without error,
rather than failing as DOM does; this wasn't root-caused further --
that's real simdjson-internals archaeology beyond this spike's scope,
and not something a thin wrapper can easily paper over. **Take this as
a real, load-bearing reason to prefer DOM over `on_demand` for any
actual binding**, not just a curiosity: `on_demand`'s ~10-15%
additional pre-sizing speed cost (see "Performance" above) is not
worth trading away actual conformance.

**And now the answer to "will it still win on real, literal JSON" --
no, not on this corpus:**

```
corpus timing (336 cases x 20 iterations): dom=0.0100s ondemand=0.0349s ljson=0.0035s
  dom-speedup=0.35x ondemand-speedup=0.10x
```

Both simdjson wrappers are *substantially slower* than `ljson.c` here
-- DOM ~3x, `on_demand` ~10x. This is the opposite of `bench.lua`'s
synthetic-payload result, and the reason is the corpus itself:
JSONTestSuite is mostly tiny fragments (`" true "`, `" [1,] "`, a few
bytes each) by design, since it's testing grammar edge cases, not
throughput. `bench.lua`'s synthetic payloads were deliberately larger
and more homogeneous specifically to show where simdjson's SIMD
structural indexing pays for its fixed per-call setup cost; on a
corpus of mostly-tiny documents, that fixed cost is exactly what
`ljson.c`'s minimal-setup recursive descent avoids paying, and it wins
by a wide margin. **Whether simdjson is worth it therefore depends
entirely on the real payload size distribution of whatever calls
`cosmo.DecodeJson`** -- large homogeneous documents (API responses,
data files): likely a real win. Many small ones (config fragments,
frequent small RPC payloads): likely a real loss. This is exactly what
`cosmic`'s `_perf` JSON scenarios, built from real workloads rather
than either of this spike's synthetic extremes, would need to settle.

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
- **once Lua tables are pre-sized, both simdjson wrappers win on
  bench.lua's synthetic payloads**: a same-process comparison against
  this tree's real `tool/net/ljson.c` initially showed simdjson losing
  0.56-0.86x on object/string-heavy payloads -- not DOM's two-pass
  design (an `on_demand` sibling showed the identical loss) but a
  missing optimization in this spike's own binding: `ljson.c`
  pre-sizes every table it creates and both simdjson wrappers were
  calling plain `lua_newtable`. Fixed, simdjson wins 1.06-2.56x across
  every synthetic payload shape tested -- **but loses 3-10x on a real,
  non-synthetic corpus of small documents** (JSONTestSuite, via
  `conformance.lua`); see "Performance" and "Conformance" below, the
  size distribution of real payloads decides which of these numbers
  actually matters
- **JSONTestSuite conformance**: DOM is fully conformant (0 bugs
  against the corpus's strict grammar cases); `on_demand` accepts
  invalid JSON in 37 of 336 cases and is not conformant. Both wrappers
  initially crashed the whole process (`SIGILL`, not a graceful error)
  on adversarially deep nesting, since neither had `ljson.c`'s own
  depth guard; fixed. See "Conformance" below

Not proven / left for real integration work:
- **wired as a real `cosmo.*` binding**: living in `tool/net/`
  alongside `ljson.c` (not `third_party/simdjson/poc/`), registered
  through `tool/lua/lcosmo.c`'s real table (not a hand-rolled `main.cc`
  standing in for `tool/lua/cosmo/lua.main.c`), with matching
  `definitions.lua` `@param`/`@return` annotations the coverage ratchet
  requires, and a decision on whether `tool/net/BUILD.mk`-style
  packages should gain a C++ pattern rule or whether this stays a
  separate package the way `poc/BUILD.mk` does it here
- **decide push vs. replace**: on conformance alone, `on_demand` is
  disqualified from replacing anything (37 real bugs against
  JSONTestSuite) -- this narrows the real question to DOM only. DOM is
  fully conformant and faster on `bench.lua`'s large/homogeneous
  synthetic payloads, but slower (3x) on `conformance.lua`'s
  small-fragment-heavy real corpus. Whether DOM should augment
  `cosmo.DecodeJson` for a large-payload path, or nothing changes at
  all, hinges entirely on the real size distribution `cosmo.DecodeJson`
  actually sees in practice -- worth a decision record (D24-style, on
  whichever side ends up owning the contract) once that's known, not
  before. The existing parser is a small, dependency-free,
  exception-free, fully-conformant C recursive descent parser;
  simdjson is a multi-megabyte C++ dependency that only clearly wins
  on large, homogeneous documents
- **size cost, for real**: a rough baseline-vs-with-simdjson delta on
  this spike's throwaway dual-arch binary was ~600KB -> ~1.3MB (+~700KB
  across both architectures combined, `-O2`, unstripped, no LTO, whole
  translation unit linked in rather than only the symbols a real
  binding would touch) -- indicative only, not a number to cite as the
  real cost
- **perf win, for real**: measured two ways now (large synthetic
  payloads: simdjson wins; JSONTestSuite's small-fragment corpus:
  simdjson loses) and the two disagree, which is itself the finding --
  landing this as a real binding needs `cosmic`'s `_perf` JSON
  scenarios (noise-aware, `MODE=rel`, and specifically the real payload
  size distribution `cosmo.DecodeJson` callers actually produce, not
  either of this spike's synthetic extremes) to settle which one
  matters, per the `optimize` skill's loop
- **`on_demand`'s root cause is still open**: it accepts clearly
  invalid JSON (`[.123]`, `[NaN]`, bare `abc`) in 37 JSONTestSuite
  cases; the common thread looks like `type()` misclassifying certain
  malformed leading tokens as `json_type::null` without erroring,
  but that's not confirmed against simdjson's actual `value_iterator`
  source, and it's moot for now anyway -- see "decide push vs.
  replace" above, `on_demand` is disqualified on conformance
  regardless of whether this particular bug gets root-caused
- **exceptions story**: only confirmed exceptions are unused on the
  non-throwing on-demand path used here; did not check whether
  `-fno-exceptions` is viable for the whole translation unit (some
  simdjson surfaces, e.g. `padded_string::load`, throw by design)
- **MODE=rel / stripped / LTO sizing**, and whether cosmopolitan's
  existing ISA-level dispatch tooling should subsume or coexist with
  simdjson's own internal CPU dispatch, are both unexamined
