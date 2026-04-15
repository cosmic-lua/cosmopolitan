# cosmic.sandbox — recommended high-level interface

> Status: design note. The low-level bits in this directory
> (`cosmo.sandbox.fs`, `.netns`, `.proxy`) will ship into
> `whilp/cosmic` as the implementation layer. This doc recommends
> the public Teal API that wraps them.

## Current state in cosmic

`whilp/cosmic` already has a `cosmic.sandbox` module — a thin
typed wrapper around `unix.pledge` and `unix.unveil`. Two functions,
~80 lines. That's the *whole* module today.

The bits in this directory are a different kind of sandbox: Linux
namespace + bind-mount + egress-proxy jails. They're complementary,
not competing, so the recommendation is to **promote
`cosmic.sandbox` from a module to a namespace**, keep pledge/unveil
under it, and land the new high-level jail API there too.

## Namespace

```
cosmic.sandbox               -- high-level jail builder (this doc)
cosmic.sandbox.pledge        -- moved from today's cosmic.sandbox.pledge
cosmic.sandbox.unveil        -- moved from today's cosmic.sandbox.unveil
cosmic.sandbox.fs            -- bind / tmpfs / pivot primitives
cosmic.sandbox.netns         -- network-namespace + veth setup
cosmic.sandbox.proxy         -- allow-list HTTP/CONNECT proxy
```

The four lower modules are thin Teal wrappers over `cosmo.sandbox.*`
in this repo, matching cosmic's `cosmic.* → cosmo.*` convention.
Top-level `cosmic.sandbox` is new code, written in Teal, that
composes them.

Migration for existing `cosmic.sandbox` callers:

- `sandbox.pledge(...)` → `sandbox.pledge.apply(...)` (or keep
  `sandbox.pledge(...)` as a call-the-namespace convenience)
- `sandbox.unveil(...)` → `sandbox.unveil.apply(...)`

One deprecation-cycle worth of backcompat shims in
`cosmic/sandbox/init.tl` and the rename is cheap.

## High-level API

The examples in `examples/*.lua` each spend ~150 lines building a
jail before `execve`. That's the shape of the problem: setup code
that's almost-but-not-quite identical. The high-level API is a
**declarative jail record**, built once and then `:run()`-ed.

```teal
local sandbox = require("cosmic.sandbox")

local jail <close> = sandbox.new {
  root      = sandbox.tmpdir(),             -- tmpfs jail root
  hostname  = "jailed",

  binds = {
    { src = "/usr",               ro = true },
    { src = "/lib",               ro = true },
    { src = "/lib64",             ro = true, optional = true },
    { src = "/etc/resolv.conf",   ro = true },
    { src = "/home/u/work",       dst = "/work", ro = false },
  },

  tmpfs   = { "/tmp", "/run", { path = "/home", size = "64m" } },
  symlinks = { { src = "/bin",  dst = "/usr/bin"  } },

  net = {
    mode  = "netns",                        -- "host" | "netns" | "none"
    proxy = {
      allow = { "api.anthropic.com", "*.githubusercontent.com" },
      port  = 18080,                        -- 0 = ephemeral
    },
  },

  env = { HOME = "/tmp", PATH = "/usr/bin" },
  cwd = "/work",
  uid = 1000, gid = 1000,
}

local status, err = jail:run({ "/usr/bin/claude", "--help" })
assert(status == 0, err)
```

### Core record

```teal
local record Jail
  root:      string
  hostname:  string
  binds:     { Bind }
  tmpfs:     { string | Tmpfs }
  symlinks:  { Symlink }
  net:       Net
  env:       { string:string }
  cwd:       string
  uid:       number
  gid:       number

  --- Apply the plan to the current process. Irreversible; use spawn
  --- or run for the common fork+exec flow.
  enter:  function(self: Jail):           boolean, string

  --- Fork, apply in the child, exec argv. Returns child pid.
  spawn:  function(self: Jail, argv: {string}): number, string

  --- spawn + wait. Returns exit status.
  run:    function(self: Jail, argv: {string}): number, string

  --- Return the ordered plan without executing it. For --dry-run
  --- and unit tests.
  plan:   function(self: Jail): { Step }

  --- Shallow-merge overrides on top of this jail. Useful for
  --- profile layering.
  extend: function(self: Jail, overrides: Jail): Jail
end
```

### Design decisions

1. **Declarative over imperative.** The caller describes what the
   jail should look like. The library chooses mount ordering,
   pivot-root timing, and proxy bring-up order. This is where the
   current examples duplicate the most logic.

2. **One shape, many shortcuts.** `run()`, `spawn()`, `enter()`
   are all views over the same `Jail` record. No second
   configuration object.

3. **Typed with Teal records.** Misconfiguration is a compile-time
   error: wrong field names, wrong types, missing required fields.
   The examples today pass plain tables and only discover errors
   at mount time.

4. **`value, string` on failure.** Matches cosmic's
   `AGENTS.md` convention. No exceptions from library code. Every
   call reports *which step* failed ("bind /usr → /jail/usr:
   EACCES") so callers don't have to guess.

5. **`<close>` for cleanup.** `Jail` has a `__close` metamethod
   that unmounts everything and `rmrf`'s the jail root. Opt-in by
   declaring the local `<close>`, matching how `cosmic.fs.Dir`
   already works.

6. **`jail:plan()` returns steps as data.** Every operation the
   jail would execute is a `Step` record (`kind = "bind"`,
   `src = ...`, `dst = ...`, `flags = ...`). This is the single
   biggest lever for:
   - `cosmic --dry-run`-style preview output
   - unit tests that don't require root/userns
   - future serialization (`jail:save(path)` / `sandbox.load(path)`)

7. **Preflight.** `sandbox.capabilities()` returns a record of
   what the kernel supports (user-ns, net-ns, newuidmap, pivot
   root, CAP_NET_ADMIN for proxy mode, ...). Callers decide how to
   react; the library never silently degrades.

8. **Profiles are first-class.** Common shapes ship as
   `sandbox.profiles.*`, each a pure function returning a `Jail`
   record the caller can still `:extend{}`:

   ```teal
   local profiles = require("cosmic.sandbox.profiles")

   local jail <close> = profiles.readonly_view({
     view = { "/usr", "/lib", "/etc" },
   }):extend{ cwd = "/usr" }

   profiles.claude_code({
     workdir = "/home/u/project",
     allow   = { "api.anthropic.com", "statsig.anthropic.com" },
   }):run({ "claude", "--help" })
   ```

   The three examples in this directory (`fs-jail`, `netns-proxy`,
   `claude-code`) become three profiles plus thin CLI wrappers.

## Layering and escape hatches

The wrapper modules are all directly importable; callers who need
finer control than the `Jail` builder offers drop down one level:

```teal
local fs_sb    = require("cosmic.sandbox.fs")
local netns    = require("cosmic.sandbox.netns")
local proxy    = require("cosmic.sandbox.proxy")

fs_sb.bind("/usr", "/jail/usr", { ro = true })
local ns = netns.create("jailed")
local p  = proxy.listen { allow = {...}, port = 0 }
```

These are 1:1 with `cosmo.sandbox.*` in this repo, plus Teal types
and the `value, string` error shape. They should live in
`lib/cosmic/sandbox/{fs,netns,proxy}.tl` and stay under 500 lines
each (cosmic's file-size cap).

## What NOT to include

- **No OCI/Docker compatibility.** Different universe. If someone
  needs OCI they already have tools.
- **No cgroup controls in v1.** Memory/CPU limits are useful but
  orthogonal and would double the surface area. Add later as
  `jail.limits = { mem = "1g", cpu = 0.5 }` once the core is stable.
- **No seccomp filter builder.** Pledge covers the common cases on
  Linux already. A seccomp-BPF builder is its own module.
- **No "just exec this in a container" CLI.** That belongs in an
  example/profile, not the library. Keep `cosmic.sandbox` as a
  library; build `cosmic sandbox ...` as a separate CLI subcommand
  that uses it.

## Implementation sketch

| file                           | lines (est.) | contents                                        |
|--------------------------------|-------------:|-------------------------------------------------|
| `sandbox/init.tl`              |          250 | `Jail` record, `new`, `plan`, `enter`, `spawn`, `run`, `extend`, `<close>` |
| `sandbox/fs.tl`                |          150 | thin wrapper over `cosmo.sandbox.fs`            |
| `sandbox/netns.tl`             |          200 | wrapper over `cosmo.sandbox.netns` + veth helpers |
| `sandbox/proxy.tl`             |          250 | wrapper over `cosmo.sandbox.proxy` + Teal types for rules |
| `sandbox/pledge.tl`            |           60 | migrated from today's `cosmic.sandbox`          |
| `sandbox/unveil.tl`            |           60 | migrated from today's `cosmic.sandbox`          |
| `sandbox/profiles.tl`          |          150 | `readonly_view`, `network_firewall`, `claude_code` |
| `sandbox/types.tl`             |          100 | shared records (`Bind`, `Tmpfs`, `Net`, `Step`) |
| `sandbox/init_test.tl`         |          200 | `plan()` table-driven tests (no root required)  |
| `sandbox/*_test.tl`            |       varies | per-module integration tests behind a root-required guard |
| `sandbox/*_example.tl`         |       varies | `Example_*` functions matching this repo's demos |

All `.tl`, all ≤500 lines — fits cosmic's rules.

## Open questions for the implementor

1. **Pledge/unveil under the umbrella vs. top-level?** I lean
   umbrella (`cosmic.sandbox.pledge`). The alternative — keeping
   `cosmic.sandbox = pledge+unveil` and adding `cosmic.jail` — also
   works but splits the mental model.
2. **Should `Jail:run` auto-`<close>`?** Probably yes; `run` is
   one-shot. `spawn` must not, since the caller owns the child.
3. **macOS / BSD story.** These jails are Linux-only. The module
   should return `nil, "unsupported OS"` on non-Linux, same as
   `cosmo.sandbox.is_supported()`. Pledge already works on
   OpenBSD; `cosmic.sandbox.pledge` stays available cross-platform.
4. **Proxy TLS.** Current proxy is HTTP CONNECT only (SNI-based
   allow-listing for HTTPS). Teal types should make this explicit
   so callers don't assume MITM-style interception.

## Acceptance criteria

The high-level interface is done when:

- [ ] The three examples in this repo reduce to <40 lines each
      when rewritten in Teal against `cosmic.sandbox`.
- [ ] `jail:plan()` for each example matches the mount/ns sequence
      the current Lua examples execute (byte-identical steps).
- [ ] `make test` in cosmic stays green with the module added.
- [ ] `cosmic --docs sandbox` returns useful output (the
      existing `docs.tl` pipeline should just work given `---`
      doc comments).
