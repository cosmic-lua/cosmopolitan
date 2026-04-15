# cosmo.sandbox

Linux process-isolation primitives for [Cosmopolitan Lua][cosmo],
plus reusable building blocks (network namespace helpers, an HTTP
CONNECT + plain-HTTP allowlist proxy) and a worked example that uses
them to build a sandbox tool functionally equivalent to the Go
`sandbox` reference design.

[cosmo]: https://github.com/jart/cosmopolitan

> **Status:** the `unix.*` syscall wrappers are stable — they shadow
> the kernel ABI and won't change shape. The `cosmo.sandbox.*`
> higher-level helpers are experimental and may evolve based on usage.

## What it is

This is a **library**, not a monolithic CLI. You compose primitives
to build sandboxes that fit your situation. The included
[`examples/netns-proxy.lua`](examples/netns-proxy.lua) is one
end-to-end assembly — Linux netns + an HTTP CONNECT + plain-HTTP
allowlist proxy as the only network path out — that demonstrates the
full pipeline. You can adapt it, throw it away and write your own, or
use just the proxy/netns pieces from your own program.

## Architecture (the worked example)

```
parent process (original netns)
├── netns-proxy.lua main
│     · saves /proc/self/ns/net fd
│     · forks the wrapper child
│     · forks the proxy child (joins child netns via setns)
│     · waits for either to exit
│     · forwards SIGINT/TERM/HUP, propagates child exit code
│
├── wrapper child (CHILD netns)
│     · unshare(CLONE_NEWNET)
│     · blocks on pipe until proxy is up
│     · execvp(your command)  with HTTP_PROXY=http://127.0.0.1:3128
│
└── proxy child (CHILD netns; listens 127.0.0.1:3128)
      · setns(child_ns_fd)
      · netns.bring_up("lo")          (best-effort)
      · proxy.new{...}:listen():serve_forever()
      · per-connection fork:
          worker setns(parent_ns_fd) → dial upstream → pump
```

The trick of the design is the cross-namespace dial: the proxy
listens inside the child's empty netns (so the sandboxed process can
reach nothing else), but per-connection worker forks `setns()` back
into the parent's netns to talk to the real internet.

## Quick start

```bash
# Build (from the cosmopolitan repo root)
make -j$(nproc) o//tool/lua/lua

# Run a command under the sandbox with a Lua-table config
sudo o//tool/lua/lua tool/lua/cosmo/sandbox/examples/netns-proxy.lua \
    -config tool/lua/cosmo/sandbox/examples/config.example.lua \
    -- curl https://api.github.com/zen
```

Requires Linux + root (or `CAP_SYS_ADMIN` + `CAP_NET_ADMIN`).

## Library layout

| Module                        | Purpose                                         |
| ----------------------------- | ----------------------------------------------- |
| `unix.*` (cosmo)              | Stable syscall wrappers (`unshare`, `setns`, `ioctl`, etc.) |
| `cosmo.sandbox`               | Library entry point + `is_supported()` probe    |
| `cosmo.sandbox.netns`         | Net namespace helpers (loopback, namespace fds) |
| `cosmo.sandbox.proxy`         | HTTP CONNECT + plain-HTTP allowlist proxy       |
| `cosmo.sandbox.examples.*`    | Worked end-to-end programs                      |

## API reference

### New `unix.*` syscall bindings

All are Linux-only; on other hosts they return
`nil, "ENOSYS", unix.ENOSYS`.

#### `unix.unshare(flags) → true | nil, unix.Errno`

Disassociates parts of the caller's execution context. `flags` is a
bitwise OR of `unix.CLONE_NEW*`. Common values:

- `unix.CLONE_NEWNET` — fresh network namespace
- `unix.CLONE_NEWNS` — fresh mount namespace
- `unix.CLONE_NEWPID` — fresh PID namespace (effective on next fork)
- `unix.CLONE_NEWUSER` — fresh user namespace (lets you map UIDs)
- `unix.CLONE_NEWUTS` — fresh hostname/domainname namespace
- `unix.CLONE_NEWIPC`, `unix.CLONE_NEWCGROUP`

```lua
assert(unix.unshare(unix.CLONE_NEWNET))
```

#### `unix.setns(fd[, nstype]) → true | nil, unix.Errno`

Reassociates the calling thread with the namespace referenced by
`fd`, which is typically opened from `/proc/<pid>/ns/<kind>`.
`nstype`, if nonzero, must match one of the `CLONE_NEW*` constants.

```lua
local fd = assert(unix.open("/proc/self/ns/net", unix.O_RDONLY))
-- ... later, in another fork ...
assert(unix.setns(fd, unix.CLONE_NEWNET))
```

#### `unix.ioctl(fd, request[, arg]) → true | str | nil, unix.Errno`

Generic ioctl. Argument dispatch:

| `arg` type | Behaviour                                  |
| ---------- | ------------------------------------------ |
| absent/nil | `ioctl(fd, request, 0)`                    |
| integer    | passed as `(void *)(intptr_t)arg`          |
| string     | copied to a mutable buffer; the (possibly modified) buffer is returned as a new string on success |

For struct-arg ioctls (e.g. `SIOCSIFFLAGS`), use `string.pack` to
build the buffer.

#### `unix.mount(source, target, fstype, flags[, data]) → true | nil, unix.Errno`

Mount a filesystem. `flags` is a bitwise OR of `unix.MS_*` constants.
`source` and `fstype` may be nil (e.g. for `MS_REMOUNT`). `data` is a
filesystem-specific options string.

```lua
-- Private mount namespace (our mounts don't leak out)
assert(unix.unshare(unix.CLONE_NEWNS))
assert(unix.mount("none", "/", nil, unix.MS_REC | unix.MS_PRIVATE, nil))

-- Read-only bind
assert(unix.mount("/etc/project", "/tmp/sandbox/etc",
                  nil, unix.MS_BIND | unix.MS_REC, nil))
assert(unix.mount("none", "/tmp/sandbox/etc", nil,
                  unix.MS_REMOUNT | unix.MS_BIND | unix.MS_RDONLY, nil))

-- A fresh tmpfs
assert(unix.mount("tmpfs", "/tmp/sandbox/tmp", "tmpfs", 0, "size=64m"))
```

#### `unix.unmount(target[, flags]) → true | nil, unix.Errno`

Unmount. BSD-style name (on Linux this is the `umount2` syscall).
Flags: `MNT_FORCE`, `MNT_DETACH`, `MNT_EXPIRE`, `UMOUNT_NOFOLLOW`.

#### `unix.pivot_root(new_root, put_old) → true | nil, unix.Errno`

Replace the root filesystem of the current mount namespace. Typically
paired with `unix.chdir("/")` in the child. Requires a private mount
namespace (use `unix.unshare(unix.CLONE_NEWNS)` first).

#### `unix.prctl(option[, arg2, arg3, arg4, arg5]) → rc | nil, unix.Errno`

Process-control operations. `option` is one of the `unix.PR_*`
constants; remaining arguments are option-specific integers.

Common sandbox-relevant uses:

```lua
-- Child gets SIGTERM when its parent dies
unix.prctl(unix.PR_SET_PDEATHSIG, unix.SIGTERM)

-- Forbid gaining new privileges via setuid binaries
unix.prctl(unix.PR_SET_NO_NEW_PRIVS, 1)

-- Prevent core dumps / PTRACE
unix.prctl(unix.PR_SET_DUMPABLE, 0)

-- Read back
local np = unix.prctl(unix.PR_GET_NO_NEW_PRIVS)  -- 1
```

#### `unix.capget([pid]) → eff, perm, inh | nil, unix.Errno`

Returns the calling thread's (or `pid`'s) capability sets as 64-bit
bitmasks (`Linux _LINUX_CAPABILITY_VERSION_3` ABI). Bit position N
corresponds to `unix.CAP_*` constant N.

```lua
local eff, perm, inh = assert(unix.capget())
if (eff & (1 << unix.CAP_NET_ADMIN)) ~= 0 then
  -- we currently have CAP_NET_ADMIN
end
```

#### `unix.capset(eff, perm, inh[, pid]) → true | nil, unix.Errno`

Sets the calling thread's capability sets. Constraints:

- `effective` ⊆ `permitted`
- `inheritable` ⊆ `permitted ∪ current_inheritable`
- you cannot add bits to `permitted` that aren't already there

```lua
-- Drop everything except CAP_NET_BIND_SERVICE.
local _, perm, inh = assert(unix.capget())
local keep = 1 << unix.CAP_NET_BIND_SERVICE
assert(unix.capset(perm & keep, perm & keep, inh & keep))
```

#### Constants

- Namespaces: `CLONE_NEWNS`, `CLONE_NEWCGROUP`, `CLONE_NEWUTS`,
  `CLONE_NEWIPC`, `CLONE_NEWUSER`, `CLONE_NEWPID`, `CLONE_NEWNET`
- Interfaces: `IFNAMSIZ`, `IFF_UP`, `IFF_LOOPBACK`, `IFF_RUNNING`,
  `IFF_BROADCAST`, `IFF_POINTOPOINT`, `IFF_NOARP`, `IFF_PROMISC`,
  `IFF_MULTICAST`, `IFF_ALLMULTI`, `IFF_DEBUG`, `IFF_NOTRAILERS`,
  `IFF_MASTER`, `IFF_SLAVE`, `IFF_PORTSEL`, `IFF_AUTOMEDIA`,
  `IFF_DYNAMIC`
- Network ioctls: `SIOCGIFFLAGS`, `SIOCSIFFLAGS`, `SIOCGIFADDR`,
  `SIOCSIFADDR`, `SIOCGIFDSTADDR`, `SIOCSIFDSTADDR`,
  `SIOCGIFBRDADDR`, `SIOCSIFBRDADDR`, `SIOCGIFNETMASK`,
  `SIOCSIFNETMASK`, `SIOCGIFMTU`, `SIOCSIFMTU`, `SIOCGIFMETRIC`,
  `SIOCSIFMETRIC`, `SIOCGIFINDEX`, `SIOCGIFNAME`
- Mount flags: `MS_RDONLY`, `MS_NOSUID`, `MS_NODEV`, `MS_NOEXEC`,
  `MS_SYNCHRONOUS`, `MS_REMOUNT`, `MS_MANDLOCK`, `MS_DIRSYNC`,
  `MS_NOATIME`, `MS_NODIRATIME`, `MS_BIND`, `MS_MOVE`, `MS_REC`,
  `MS_SILENT`, `MS_POSIXACL`, `MS_UNBINDABLE`, `MS_PRIVATE`,
  `MS_SLAVE`, `MS_SHARED`, `MS_RELATIME`, `MS_STRICTATIME`,
  `MS_LAZYTIME`
- prctl options: `PR_SET_PDEATHSIG`, `PR_GET_PDEATHSIG`,
  `PR_SET_NO_NEW_PRIVS`, `PR_GET_NO_NEW_PRIVS`, `PR_SET_DUMPABLE`,
  `PR_GET_DUMPABLE`, `PR_SET_KEEPCAPS`, `PR_GET_KEEPCAPS`,
  `PR_SET_NAME`, `PR_GET_NAME`, `PR_SET_CHILD_SUBREAPER`,
  `PR_GET_CHILD_SUBREAPER`, `PR_CAPBSET_READ`, `PR_CAPBSET_DROP`
- Capabilities: `CAP_CHOWN`, `CAP_DAC_OVERRIDE`,
  `CAP_DAC_READ_SEARCH`, `CAP_FOWNER`, `CAP_FSETID`, `CAP_KILL`,
  `CAP_SETGID`, `CAP_SETUID`, `CAP_SETPCAP`, `CAP_LINUX_IMMUTABLE`,
  `CAP_NET_BIND_SERVICE`, `CAP_NET_BROADCAST`, `CAP_NET_ADMIN`,
  `CAP_NET_RAW`, `CAP_IPC_LOCK`, `CAP_IPC_OWNER`, `CAP_SYS_MODULE`,
  `CAP_SYS_RAWIO`, `CAP_SYS_CHROOT`, `CAP_SYS_PTRACE`,
  `CAP_SYS_PACCT`, `CAP_SYS_ADMIN`, `CAP_SYS_BOOT`, `CAP_SYS_NICE`,
  `CAP_SYS_RESOURCE`, `CAP_SYS_TIME`, `CAP_SYS_TTY_CONFIG`,
  `CAP_MKNOD`, `CAP_LEASE`, `CAP_AUDIT_WRITE`, `CAP_AUDIT_CONTROL`,
  `CAP_SETFCAP`, `CAP_MAC_OVERRIDE`, `CAP_MAC_ADMIN`, `CAP_SYSLOG`,
  `CAP_WAKE_ALARM`, `CAP_BLOCK_SUSPEND`, `CAP_AUDIT_READ`,
  `CAP_PERFMON`, `CAP_BPF`, `CAP_CHECKPOINT_RESTORE`,
  `CAP_LAST_CAP`

### `cosmo.sandbox`

```lua
local sandbox = require "cosmo.sandbox"
sandbox._VERSION       -- "0.0.1"
sandbox.is_supported() -- true on Linux with the bindings present
```

### `cosmo.sandbox.netns`

All helpers return `nil, errstr, errno` on failure.

| Function                            | Returns                |
| ----------------------------------- | ---------------------- |
| `netns.build_ifreq(name, flags)`    | `string` (40 bytes)    |
| `netns.parse_ifreq_flags(ifr)`      | `int`                  |
| `netns.control_socket()`            | `fd`                   |
| `netns.get_flags(name)`             | `int`                  |
| `netns.set_flags(name, flags)`      | `true`                 |
| `netns.bring_up(name)`              | `true`                 |
| `netns.bring_down(name)`            | `true`                 |
| `netns.open([pid])`                 | `fd` (defaults to self)|

```lua
local netns = require "cosmo.sandbox.netns"
local parent_ns = assert(netns.open())  -- /proc/self/ns/net
-- ... fork+unshare ...
assert(netns.bring_up("lo"))
```

### `cosmo.sandbox.proxy`

```lua
local proxy = require "cosmo.sandbox.proxy"

local p = proxy.new{
  bind_ip        = cosmo.ParseIp("127.0.0.1"),  -- default
  bind_port      = 3128,                        -- default
  upstream_ns_fd = parent_ns,                   -- nil = current ns
  allowed_hosts  = {
    ["api.github.com:443"]    = {type="bearer", token="ghp_..."},
    ["api.anthropic.com:443"] = {type="header",
                                  header_name="x-api-key",
                                  header_value="sk-..."},
    ["registry.npmjs.org:*"]  = {},
    ["pypi.org"]              = {},
  },
  log_level  = "info",   -- "quiet" | "info" | "debug"
  log_format = "text",   -- "text" | "json"
  log_file   = nil,      -- path; nil = stderr
  on_log     = nil,      -- function(fields) overrides built-in sink
  accept_backlog = 32,
}

assert(p:listen())       -- bind + listen, returns the fd
p:serve_forever()        -- accept loop, fork-per-connection
```

#### Allowlist matching

| Key form              | Meaning                                |
| --------------------- | -------------------------------------- |
| `"host:port"`         | Exact host AND port                    |
| `"host"`              | Any port for `host`                    |
| `"host:*"`            | Explicit any-port for `host`           |

Host matching is case-insensitive.

#### Auth rule types (HTTP only)

Auth injection only applies to plain HTTP requests through the
non-CONNECT path. CONNECT tunnels are end-to-end encrypted and
opaque to the proxy — the rule still gates the connect, but no
header injection happens. The child process is responsible for its
own TLS-level auth (API keys in request headers, etc.).

| `rule.type`  | Other fields                       | Effect                                  |
| ------------ | ---------------------------------- | --------------------------------------- |
| `"bearer"`   | `token`                            | `Authorization: Bearer <token>`         |
| `"basic"`    | `username`, `password`             | `Authorization: Basic <base64(u:p)>`    |
| `"header"`   | `header_name`, `header_value`      | `<header_name>: <header_value>`         |
| (none/empty) | —                                  | no header injected                      |

Hop-by-hop headers (`Connection`, `Proxy-Connection`, `Keep-Alive`,
`TE`, `Trailer`, `Transfer-Encoding`, `Upgrade`) are stripped per
RFC 7230 §6.1.

#### Logging

Default sink writes one line per event to stderr. With
`log_format="json"` you get one JSON object per line:

```json
{"ts":"1747000000.000000000","event":"allow","method":"CONNECT","host":"api.github.com","port":443}
{"ts":"1747000000.000000123","event":"deny","method":"CONNECT","host":"evil.example.com","port":443}
```

Override with `on_log = function(fields) ... end` for fully custom
delivery (e.g. ship to a syslog or to a queue).

#### Methods

| Method                   | Purpose                                   |
| ------------------------ | ----------------------------------------- |
| `p:listen()`             | bind + listen, returns the fd             |
| `p:accept()`             | one accepted client fd                    |
| `p:handle(client_fd)`    | one connection synchronously              |
| `p:serve_forever()`      | accept loop, fork-per-connection         |

## Examples

Two worked end-to-end programs ship under `examples/`:

| Script             | What it demonstrates                                         |
| ------------------ | ------------------------------------------------------------ |
| `netns-proxy.lua`  | Network-isolation sandbox with HTTP CONNECT + plain-HTTP allowlist proxy. End-to-end equivalent of the Go `sandbox` reference design. |
| `fs-jail.lua`      | Filesystem-isolation sandbox: private mount namespace + tmpfs root + read-only bind-mounts of `/usr`/`/lib`/etc. + writable `/tmp` + `pivot_root` + `PR_SET_NO_NEW_PRIVS`. |

The two are independent — combine them by composing your own
top-level script that runs the FS-jail steps first, then the netns
+ proxy steps.

## Example: `examples/netns-proxy.lua`

The reference assembly. Reads a Lua-table config, sets up the netns
+ proxy, executes the user's command in the sandbox, propagates the
child's exit code.

```bash
lua.com netns-proxy.lua -h
```

### Config schema

```lua
return {
  proxy_addr = "127.0.0.1:3128",      -- optional
  allowed_hosts = {
    ["api.github.com:443"] = {type="bearer", token="..."},
    ["pypi.org"]           = {},
  },
  command = {"bash"},                 -- run if no `--` on cmdline
  log_level  = "info",                -- quiet|info|debug
  log_format = "text",                -- text|json
  log_file   = nil,                   -- path or nil for stderr
  env_passthrough = nil,              -- nil = pass all; or list of names
  env_set = {},                       -- extras to set in child
}
```

Saved as `config.lua`, then run with:

```bash
sudo lua.com netns-proxy.lua -config config.lua -- gh api /user
sudo lua.com netns-proxy.lua -config config.lua -- npm install
sudo lua.com netns-proxy.lua -config config.lua -- claude code
```

Exit codes:

| Code | Meaning                                        |
| ---- | ---------------------------------------------- |
| 0    | child exited 0                                 |
| 1    | child failed                                   |
| 2    | permission denied                              |
| 3    | netns setup failed (unshare / lo bring-up)     |
| 4    | proxy setup failed (bind / listen)             |
| 5    | bad usage or config                            |
| 6    | non-Linux host                                 |
| 128+N | child died from signal N                      |

## Example: `examples/fs-jail.lua`

Wraps a command in a private mount namespace whose root is a fresh
tmpfs containing only the read-only-bound paths the user lists.

```bash
sudo lua.com fs-jail.lua -- ls /
# bin etc lib lib64 tmp usr      (no /home, /root, /proc, etc.)

sudo lua.com fs-jail.lua -bind /etc/passwd -bind /home/user/project \
    -- /home/user/project/build.sh
```

What the example does, step by step:

1. `unshare(CLONE_NEWNS)` — fresh mount namespace.
2. Remount `/` as `MS_PRIVATE` so subsequent mounts don't leak.
3. `mount("tmpfs", "/tmp/fs-jail-<pid>", "tmpfs", ...)` — fresh root.
4. For each path: `mount(src, jail/src, MS_BIND|MS_REC)` then a
   `MS_REMOUNT|MS_RDONLY` pass to lock it down.
5. A separate writable tmpfs mounted at `jail/tmp`.
6. `pivot_root(jail, jail/.old)` then `unmount("/.old", MNT_DETACH)`
   so the old root is dropped.
7. `prctl(PR_SET_NO_NEW_PRIVS, 1)` — setuid binaries can't escalate.
8. `execvp(cmd[1], cmd)` — replace this process with the user's
   command, now running in the jail.

This is a useful starting point if you want filesystem isolation
without netns. To get both, write a wrapper script that invokes
`fs-jail.lua` from inside `netns-proxy.lua -- ...` (or just combine
the relevant code paths).

## Tests

Three layers, all wired into `make check` via `tool/lua/BUILD.mk`:

| File                        | Privileges | Coverage                                                     |
| --------------------------- | ---------- | ------------------------------------------------------------ |
| `test.lua`                  | none       | binding presence, constants, `ioctl` arg dispatch, ifreq pack |
| `test_proxy.lua`            | none       | parser + allowlist + auth header + rebuild_request           |
| `test_integration.lua`      | root + CAP_NET_ADMIN | unshare, setns hop, isolation, full proxy CONNECT/HTTP allow+deny+header injection across forked netns |

The integration suite probes for `unshare(CLONE_NEWNET)` and
`SIOCSIFFLAGS` permission up front and **skips cleanly** when
denied, so it does not break unprivileged CI runs.

```bash
# Just the smoke + unit tests (no privileges)
o//tool/lua/lua tool/lua/cosmo/sandbox/test.lua
o//tool/lua/lua tool/lua/cosmo/sandbox/test_proxy.lua

# Integration (needs root)
sudo o//tool/lua/lua tool/lua/cosmo/sandbox/test_integration.lua
```

## Limitations

- **DNS** — there's no resolver in the child netns. HTTP clients
  resolve via the proxy's CONNECT target (the proxy resolves in the
  parent netns), but `ping`, `dig`, etc. won't work. A future
  version could run a tiny DNS forwarder on the child's loopback.
- **HTTPS auth injection** — CONNECT tunnels are end-to-end
  encrypted. To inject auth into HTTPS requests you'd need a MITM
  proxy with a custom CA in the child's trust store. Not in scope.
- **Non-HTTP protocols** — git over SSH, raw TCP, etc. are not
  supported. Could be extended with SOCKS5 in a separate proxy.
- **Capability hardening** — currently requires root. Could use
  user namespaces (`CLONE_NEWUSER`) for unprivileged operation,
  with the usual UID-mapping caveats.
- **HTTP/1.1 features** — keep-alive isn't reused upstream; chunked
  trailers and HTTP/2 aren't supported. The plain-HTTP path is for
  simple GET/POST proxying with auth injection; for anything more
  complex, prefer CONNECT and let the inner protocol handle it.
