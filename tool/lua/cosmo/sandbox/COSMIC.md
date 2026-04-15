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

## Changes made on the cosmo side (v0.0.3)

Researching cosmic surfaced friction points that were cheaper to fix
here than to paper over in the Teal wrappers. All six landed before
any cosmic code depends on the API; the list below is kept for
reference / changelog purposes. Roughly in order of payoff:

### 1. Unify the error-return shape (HIGH)

`netns.lua` rigorously returns `nil, unix.Errno`. `fs.lua` and
`proxy.lua` wrap the Errno into a string with a context prefix
(`"bind /usr: EACCES [13]"`) and lose the object. The cosmic Teal
wrapper wants `value, string` — but if the lower layer has already
stringified, the wrapper can't:

- programmatically test `err:errno() == unix.EACCES`
- re-contextualize without double-prefixing
- present a consistent format to users

**Recommendation:** change every non-netns helper to return
`nil, unix.Errno`. Callers (examples, cosmic wrappers) add the
context string at their call site, where they actually know what
they were doing. Concrete sites to change:

- `fs.lua:42, 73, 79, 109` (drop `"bind " .. src .. ": "` wraps)
- `proxy.lua:52, 241, 245, 248, 252` (drop the syscall wraps —
  keep the pure-string "eof", "short write", "header block exceeds
  N bytes" because those have no Errno to preserve)

One wrinkle: `fs.lua:42` "missing source: X" catches stat-EBADPATH
before the mount — propagate the `unix.stat` errno instead of
synthesizing a string.

### 2. Promote `is_supported()` → `capabilities()` (MEDIUM)

Today's binary `is_supported()` is true/false. Cosmic's
`sandbox.capabilities()` wants a record:

```lua
{
  linux        = true,    -- cosmo.GetHostOs() == "LINUX"
  user_ns      = true,    -- unshare(CLONE_NEWUSER) works
  mount_ns     = true,    -- unshare(CLONE_NEWNS) works
  net_ns       = true,    -- unshare(CLONE_NEWNET) works
  pivot_root   = true,    -- unix.pivot_root present
  cap_net_admin = true,   -- for veth pair setup
  newuidmap    = false,   -- helper binary in $PATH
}
```

Make it a proper probe (attempt the syscalls in a child, cache the
result), not a table of nils. Keeps `is_supported()` as
`capabilities().linux and capabilities().mount_ns`.

### 3. Extract `cosmo.sandbox.proc` (MEDIUM)

Three primitives are duplicated across every example:

- `unix.sethostname(name)`
- `unix.prctl(PR_SET_NO_NEW_PRIVS, 1)` (fs-jail:132, claude-code:221)
- `unix.setgid(gid); unix.setuid(uid)` (drop-privs sequence)

Pull them into `cosmo.sandbox.proc`:

```lua
proc.set_hostname(name)           → true | nil, unix.Errno
proc.no_new_privs()               → true | nil, unix.Errno
proc.drop_privs(uid, gid)         → true | nil, unix.Errno
proc.become_init(child_pid)       → exit_code | nil, unix.Errno
                                    -- PID-1 reaper loop used in
                                    -- netns-proxy and claude-code
```

The `become_init` one is the biggest win — the PID-1 supervisor
loop (EINTR handling, waitpid, propagate exit status) currently
lives inline in two examples and is the stuff we fixed bugs in
during the review.

### 4. Stabilize the proxy rule shape (LOW)

Today: `{ ["host:port"] = rule_table }` with shorthand
`{ ["host"] = true }` via string keys. This is flexible but
under-specified. Commit to the schema now:

```lua
{
  [host_spec] = {
    methods   = { "GET", "CONNECT" },   -- or nil = any
    auth      = { user = ..., pass = ... },  -- optional
  }
}
```

where `host_spec` is `host`, `host:port`, `*.suffix`, or
`*.suffix:port`. The existing `parse_rule` / `build_index` already
handle most of this; just document it and add tests pinning the
behaviour so the Teal `.d.tl` author doesn't have to reverse-engineer.

### 5. Convert comments to `---` doc-comments (LOW)

cosmic's `cosmic --docs` pipeline extracts `---`-prefixed docstrings
from `.tl` files. Our Lua files use `--` bodies today. The Teal
wrappers will re-document anyway, so this is lowest-priority — but
if the wrappers are mostly 1:1 passthroughs, mirroring the docs
from here saves the wrapper author typing. Worth doing while the
examples are still fresh in someone's head.

### 6. Optional: `proxy.start(opts)` convenience (LOW)

Today the caller forks, then in the parent calls
`proxy.new(opts)`, `proxy.listen()`, `proxy.serve_forever()`. A
one-liner would simplify both examples and the cosmic wrapper:

```lua
local p = proxy.start(opts)  -- forks, returns { pid, port, stop() }
-- parent continues; child runs serve_forever
```

Small code reduction; only worth doing if #3's
`proc.become_init` lands, since the cleanup story gets simpler.

---

### Status

All six changes landed in v0.0.3:

- **#1** (error shape): `fs.bind/bind_ro/tmpfs` and `proxy.dial`
  now return `nil, unix.Errno`. No more string wrapping for syscall
  errors.
- **#2** (capabilities): `cosmo.sandbox.capabilities()` returns a
  fine-grained record; `is_supported()` becomes a convenience over
  it. Result is cached.
- **#3** (proc module): `cosmo.sandbox.proc` now exports
  `set_hostname`, `no_new_privs`, `drop_privs`, and `become_init`.
  Both example supervisors collapse to one `proc.become_init(...)`
  call; claude-code's `drop_privileges` function is gone.
- **#4** (proxy rules): rule schema documented in-source and tested.
  `*.suffix` and `*.suffix:port` wildcard matching implemented with
  tail-anchored matching (apex + substring hosts correctly miss).
- **#5** (`---` docs): all public docstrings in `init`, `fs`,
  `netns`, `proc`, `proxy` use the triple-dash prefix so cosmic's
  `--docs` pipeline can extract them.
- **#6** (`proxy.start`): forks, listens, reports the bound port
  back via a pipe, and returns `{pid, port, stop()}`. Useful as a
  one-liner in cosmic's Jail builder.

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
