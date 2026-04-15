-- cosmo.sandbox.proxy: an HTTP CONNECT + plain-HTTP allowlist proxy.
--
-- Designed for the netns-isolated sandbox use case: the proxy listens
-- inside a child network namespace (the only thing the sandboxed
-- process can reach) and dials upstream in a *different* namespace —
-- typically the parent's. Cross-namespace dialing is handled by setns()
-- in per-connection forks, so a slow upstream never blocks others and
-- there is no global namespace-state contention.
--
-- Features (v1):
--   - HTTP/1.1 CONNECT method (HTTPS tunnels — opaque, allowlist only)
--   - HTTP/1.1 GET/POST/HEAD/PUT/DELETE/PATCH forwarding with auth
--     header injection
--   - Allowlist with exact host:port, host (any port), and host:*
--     matching
--   - Per-host auth rules: bearer / basic / arbitrary header
--   - Configurable logging: level (quiet/info/debug), format
--     (text/json), destination (callable / fd / file path)
--
-- Out of scope (v1): keep-alive reuse upstream, HTTP/2, response
-- streaming with chunked trailers, MITM TLS interception.
--
-- Returns nil,errstr,errno on failure for non-fatal API; raises on
-- programmer errors (bad config schema).

local unix = require "unix"
local cosmo = require "cosmo"

local M = {_VERSION = "0.0.1"}

--------------------------------------------------------------------------------
-- Logging

local function ts()
  local s, ns = unix.clock_gettime(unix.CLOCK_REALTIME)
  return string.format("%d.%09d", s, ns)
end

local LEVELS = {quiet = 0, info = 1, debug = 2}

local function make_logger(opts)
  local level = LEVELS[opts.log_level or "info"]
  local format = opts.log_format or "text"
  local sink = opts.on_log
  local out
  if not sink then
    if type(opts.log_file) == "string" then
      local f, err = io.open(opts.log_file, "a")
      if not f then
        return nil, "cannot open log file: " .. tostring(err)
      end
      f:setvbuf("line")
      out = f
    else
      out = io.stderr
    end
  end
  local function emit(ev, fields)
    if sink then
      sink(fields)
      return
    end
    if format == "json" then
      local parts = {}
      parts[#parts + 1] = string.format('{"ts":"%s"', ts())
      parts[#parts + 1] = string.format(',"event":%q', ev)
      for k, v in pairs(fields) do
        if type(v) == "number" then
          parts[#parts + 1] = string.format(',%q:%d', k, v)
        else
          parts[#parts + 1] = string.format(',%q:%q', k, tostring(v))
        end
      end
      parts[#parts + 1] = "}\n"
      out:write(table.concat(parts))
    else
      local kv = {}
      for k, v in pairs(fields) do
        kv[#kv + 1] = string.format("%s=%s", k, tostring(v))
      end
      out:write(string.format("%s %s %s\n", ts(), ev, table.concat(kv, " ")))
    end
  end
  return {
    info  = function(ev, f) if level >= 1 then emit(ev, f or {}) end end,
    debug = function(ev, f) if level >= 2 then emit(ev, f or {}) end end,
    warn  = function(ev, f) if level >= 1 then emit(ev, f or {}) end end,
    deny  = function(ev, f) if level >= 1 then emit(ev, f or {}) end end,
  }
end

--------------------------------------------------------------------------------
-- Allowlist matching

-- Normalize a rule key into ("host", port_or_nil) where port is nil if any.
local function parse_rule(key)
  -- "host:port", "host:*", or "host"
  local h, p = key:match("^(.-):(.-)$")
  if not h then
    return key:lower(), nil
  end
  if p == "*" or p == "" then
    return h:lower(), nil
  end
  return h:lower(), tonumber(p)
end

-- Build a fast lookup index from a {[key]=rule} table.
-- The result maps host -> {[port|"*"] = rule}.
local function build_index(allowed_hosts)
  local idx = {}
  for k, rule in pairs(allowed_hosts or {}) do
    local h, p = parse_rule(k)
    idx[h] = idx[h] or {}
    idx[h][p or "*"] = rule
  end
  return idx
end

-- Look up a (host, port) pair. Port is the integer port for HTTPS
-- (CONNECT) or HTTP. Returns the rule table on a hit, or nil.
local function match(idx, host, port)
  host = host:lower()
  local entry = idx[host]
  if not entry then return nil end
  return entry[port] or entry["*"]
end
M._parse_rule = parse_rule
M._build_index = build_index
M._match = match

--------------------------------------------------------------------------------
-- Auth header construction

local function auth_header(rule)
  if not rule then return nil end
  if rule.type == "bearer" then
    return "Authorization", "Bearer " .. tostring(rule.token)
  elseif rule.type == "basic" then
    local enc = cosmo.EncodeBase64(rule.username .. ":" .. rule.password)
    return "Authorization", "Basic " .. enc
  elseif rule.type == "header" then
    return rule.header_name, rule.header_value
  end
  return nil
end
M._auth_header = auth_header

--------------------------------------------------------------------------------
-- Wire I/O helpers

-- Read until "\r\n\r\n" or EOF. Returns (header_block, leftover_after).
-- Bounds the read to `max` bytes to avoid memory blowups from junk input.
local function read_headers(fd, max)
  max = max or 65536
  local buf = ""
  while #buf < max do
    local chunk, err = unix.recv(fd, math.min(4096, max - #buf))
    if not chunk then return nil, tostring(err) end
    if chunk == "" then return nil, "eof" end
    buf = buf .. chunk
    local i, j = buf:find("\r\n\r\n", 1, true)
    if i then
      return buf:sub(1, j), buf:sub(j + 1)
    end
  end
  return nil, "header block exceeds " .. max .. " bytes"
end
M._read_headers = read_headers

-- Send all bytes (handles short writes).
local function send_all(fd, data)
  local off = 0
  while off < #data do
    local n, err = unix.send(fd, data:sub(off + 1))
    if not n then return nil, tostring(err) end
    if n == 0 then return nil, "short write" end
    off = off + n
  end
  return true
end
M._send_all = send_all

-- Bidirectional byte pump between two TCP fds. Returns when both
-- sides hit EOF or one side errors. Uses unix.poll so the work
-- happens in a single process. shutdown(SHUT_WR) is issued in the
-- appropriate direction so the peer sees a clean half-close.
local function pump(a, b)
  local fds = {[a] = unix.POLLIN, [b] = unix.POLLIN}
  local a_open, b_open = true, true
  while a_open or b_open do
    local ready = unix.poll(fds)
    if not ready then return end
    for fd, ev in pairs(ready) do
      local hup = (ev & (unix.POLLHUP | unix.POLLERR | unix.POLLNVAL)) ~= 0
      local readable = (ev & unix.POLLIN) ~= 0
      if readable then
        local chunk = unix.recv(fd, 16384)
        if not chunk or chunk == "" then
          if fd == a then a_open = false else b_open = false end
          local peer = (fd == a) and b or a
          pcall(unix.shutdown, peer, unix.SHUT_WR)
          fds[fd] = nil
        else
          local peer = (fd == a) and b or a
          if not send_all(peer, chunk) then return end
        end
      elseif hup then
        if fd == a then a_open = false else b_open = false end
        local peer = (fd == a) and b or a
        pcall(unix.shutdown, peer, unix.SHUT_WR)
        fds[fd] = nil
      end
    end
  end
end
M._pump = pump

--------------------------------------------------------------------------------
-- Upstream dialing across namespaces

-- Resolve `host` to an IPv4 integer suitable for unix.connect. Uses
-- cosmo.ResolveIp which goes through the system resolver in the
-- *current* netns (so call this AFTER setns() to the upstream netns).
local function resolve_v4(host)
  -- ParseIp succeeds for literal IPs; ResolveIp does DNS.
  local ip = cosmo.ParseIp(host)
  if ip then return ip end
  return cosmo.ResolveIp(host)
end

-- Open a TCP connection to (host, port) in the namespace identified by
-- `upstream_ns_fd`, falling back to the current namespace if the fd is
-- nil. Returns fd | nil,err.
local function dial(host, port, upstream_ns_fd)
  if upstream_ns_fd then
    local ok, err = unix.setns(upstream_ns_fd, unix.CLONE_NEWNET)
    if not ok then return nil, "setns(parent): " .. tostring(err) end
  end
  local ip, rerr = resolve_v4(host)
  if not ip then return nil, "resolve " .. host .. ": " .. tostring(rerr) end
  local sk, serr = unix.socket(unix.AF_INET, unix.SOCK_STREAM, 0)
  if not sk then return nil, "socket: " .. tostring(serr) end
  local ok, cerr = unix.connect(sk, ip, port)
  if not ok then
    unix.close(sk)
    return nil, "connect " .. host .. ":" .. port .. ": " .. tostring(cerr)
  end
  return sk
end
M._dial = dial

--------------------------------------------------------------------------------
-- HTTP request/response handling

local DENY = "HTTP/1.1 403 Forbidden\r\n" ..
             "Content-Length: 0\r\n" ..
             "Connection: close\r\n\r\n"

local BAD_REQUEST = "HTTP/1.1 400 Bad Request\r\n" ..
                    "Content-Length: 0\r\n" ..
                    "Connection: close\r\n\r\n"

local UPSTREAM_FAIL = "HTTP/1.1 502 Bad Gateway\r\n" ..
                      "Content-Length: 0\r\n" ..
                      "Connection: close\r\n\r\n"

-- Parse an HTTP request line: "METHOD TARGET HTTP/x.y\r\n".
-- Returns method, target, version | nil.
local function parse_request_line(line)
  local m, t, v = line:match("^(%u+) (%S+) (HTTP/%d%.%d)\r\n")
  return m, t, v
end
M._parse_request_line = parse_request_line

-- Parse a CONNECT target "host:port".
local function parse_connect_target(t)
  local h, p = t:match("^([^:]+):(%d+)$")
  if not h then return nil end
  return h, tonumber(p)
end
M._parse_connect_target = parse_connect_target

-- Parse an absolute URI of the form "http://host[:port]/path".
-- HTTP proxies receive these (RFC 7230 §5.3.2) instead of origin-form.
-- Returns scheme, host, port (default 80), path.
local function parse_absolute_uri(t)
  local s, hp, path = t:match("^(https?)://([^/]+)(/.*)$")
  if not s then
    s, hp = t:match("^(https?)://([^/]+)$")
    path = "/"
  end
  if not s then return nil end
  local h, p = hp:match("^([^:]+):(%d+)$")
  if h then
    return s, h, tonumber(p), path
  end
  return s, hp, (s == "https") and 443 or 80, path
end
M._parse_absolute_uri = parse_absolute_uri

-- Iterate over header lines in a header block (does not include the
-- request line). Yields name, value with the name lowercased.
local function each_header(block)
  local lines = {}
  for line in block:gmatch("([^\r\n]+)\r\n") do
    lines[#lines + 1] = line
  end
  table.remove(lines, 1)  -- drop the request line
  return coroutine.wrap(function()
    for _, line in ipairs(lines) do
      local n, v = line:match("^([^:]+):%s*(.*)$")
      if n then coroutine.yield(n:lower(), v, n) end
    end
  end)
end
M._each_header = each_header

-- Construct the forwarded HTTP request: method + origin-form target +
-- HTTP/1.1, with our injected auth header (replacing any existing one
-- of the same name) and Connection: close. Strips proxy-only headers.
local function rebuild_request(method, path, headers, body, inject_name, inject_value, host_hdr)
  local hop_by_hop = {
    ["connection"] = true,
    ["proxy-connection"] = true,
    ["keep-alive"] = true,
    ["te"] = true,
    ["trailer"] = true,
    ["transfer-encoding"] = true,
    ["upgrade"] = true,
  }
  local injected_lower = inject_name and inject_name:lower() or nil
  local out = {string.format("%s %s HTTP/1.1\r\n", method, path)}
  local saw_host = false
  for lname, value, oname in each_header(headers) do
    if hop_by_hop[lname] then
      -- skip
    elseif injected_lower and lname == injected_lower then
      -- replaced below
    elseif lname == "host" then
      saw_host = true
      out[#out + 1] = oname .. ": " .. host_hdr .. "\r\n"
    else
      out[#out + 1] = oname .. ": " .. value .. "\r\n"
    end
  end
  if not saw_host then
    out[#out + 1] = "Host: " .. host_hdr .. "\r\n"
  end
  if inject_name then
    out[#out + 1] = inject_name .. ": " .. inject_value .. "\r\n"
  end
  out[#out + 1] = "Connection: close\r\n"
  if body and #body > 0 then
    out[#out + 1] = "Content-Length: " .. #body .. "\r\n"
  end
  out[#out + 1] = "\r\n"
  if body then out[#out + 1] = body end
  return table.concat(out)
end
M._rebuild_request = rebuild_request

-- Parse Content-Length out of a header block. Returns 0 if absent.
local function content_length(headers)
  for n, v in each_header(headers) do
    if n == "content-length" then return tonumber(v) or 0 end
  end
  return 0
end
M._content_length = content_length

-- Read exactly `n` bytes from `fd`, given an optional already-buffered
-- prefix. Returns the body string.
local function read_body(fd, n, prefix)
  local buf = prefix or ""
  while #buf < n do
    local chunk, err = unix.recv(fd, math.min(16384, n - #buf))
    if not chunk then return nil, tostring(err) end
    if chunk == "" then return nil, "eof in body" end
    buf = buf .. chunk
  end
  return buf:sub(1, n), buf:sub(n + 1)
end
M._read_body = read_body

--------------------------------------------------------------------------------
-- Per-connection handler

-- Handle one accepted client connection. Closes `client_fd` before
-- returning. Designed to be called in a forked worker process so it
-- can call setns() without affecting the parent.
local function handle(self, client_fd)
  local logger = self._logger
  local hdr, leftover = read_headers(client_fd)
  if not hdr then
    logger.warn("malformed", {reason = leftover or "truncated"})
    send_all(client_fd, BAD_REQUEST)
    unix.close(client_fd)
    return
  end
  local first = hdr:match("^([^\r\n]+)\r\n")
  if not first then
    send_all(client_fd, BAD_REQUEST)
    unix.close(client_fd)
    return
  end
  local method, target = parse_request_line(first .. "\r\n")
  if not method then
    send_all(client_fd, BAD_REQUEST)
    unix.close(client_fd)
    return
  end

  if method == "CONNECT" then
    local host, port = parse_connect_target(target)
    if not host then
      send_all(client_fd, BAD_REQUEST)
      unix.close(client_fd)
      return
    end
    local rule = match(self._index, host, port)
    if not rule then
      logger.deny("deny", {method = "CONNECT", host = host, port = port})
      send_all(client_fd, DENY)
      unix.close(client_fd)
      return
    end
    local up, derr = dial(host, port, self._upstream_ns_fd)
    if not up then
      logger.warn("upstream_fail",
                  {method = "CONNECT", host = host, port = port, err = derr})
      send_all(client_fd, UPSTREAM_FAIL)
      unix.close(client_fd)
      return
    end
    logger.info("allow", {method = "CONNECT", host = host, port = port})
    if not send_all(client_fd, "HTTP/1.1 200 Connection Established\r\n\r\n") then
      unix.close(up); unix.close(client_fd); return
    end
    -- If the client already sent payload after the CONNECT line (rare
    -- but possible for racy clients), forward it to upstream first.
    if leftover and #leftover > 0 then
      if not send_all(up, leftover) then
        unix.close(up); unix.close(client_fd); return
      end
    end
    pump(client_fd, up)
    unix.close(up)
    unix.close(client_fd)
    return
  end

  -- Plain HTTP. Target is absolute-form for proxy requests.
  local scheme, host, port, path = parse_absolute_uri(target)
  if not host then
    send_all(client_fd, BAD_REQUEST)
    unix.close(client_fd)
    return
  end
  local rule = match(self._index, host, port)
  if not rule then
    logger.deny("deny",
                {method = method, host = host, port = port, path = path})
    send_all(client_fd, DENY)
    unix.close(client_fd)
    return
  end
  -- Read the request body (Content-Length only; chunked not supported).
  local clen = content_length(hdr)
  local body
  if clen > 0 then
    local b, err = read_body(client_fd, clen, leftover)
    if not b then
      send_all(client_fd, BAD_REQUEST)
      unix.close(client_fd)
      return
    end
    body = b
  end
  local up, derr = dial(host, port, self._upstream_ns_fd)
  if not up then
    logger.warn("upstream_fail",
                {method = method, host = host, port = port, err = derr})
    send_all(client_fd, UPSTREAM_FAIL)
    unix.close(client_fd)
    return
  end
  local injn, injv = auth_header(rule)
  local host_hdr = host
  if (scheme == "http"  and port ~= 80) or
     (scheme == "https" and port ~= 443) then
    host_hdr = host .. ":" .. port
  end
  local req = rebuild_request(method, path, hdr, body, injn, injv, host_hdr)
  if not send_all(up, req) then
    unix.close(up); unix.close(client_fd); return
  end
  logger.info("allow", {method = method, host = host, port = port,
                        path = path,
                        injected = injn ~= nil and injn or false})
  -- Stream the response back. We pump bidirectionally because some
  -- servers may continue reading from the request body even though we
  -- already forwarded it; the simple approach is to pump until EOF on
  -- both sides.
  pump(client_fd, up)
  unix.close(up)
  unix.close(client_fd)
end

--------------------------------------------------------------------------------
-- Public Proxy object

local Proxy = {}
Proxy.__index = Proxy

-- Create a new proxy. `opts` fields:
--
--   bind_ip          uint32 IPv4 (default cosmo.ParseIp("127.0.0.1"))
--   bind_port        uint16 (default 3128)
--   allowed_hosts    table {key = rule}
--   upstream_ns_fd   int (open fd to the netns to dial in; default
--                    nil means dial in the current namespace)
--   on_log           function(fields) — overrides default sink
--   log_level        "quiet"|"info"|"debug"  (default "info")
--   log_format       "text"|"json"           (default "text")
--   log_file         path                    (default stderr)
--   accept_backlog   int                     (default 32)
--
-- Returns the Proxy object.
function M.new(opts)
  opts = opts or {}
  local logger, lerr = make_logger(opts)
  if not logger then error(lerr) end
  return setmetatable({
    _bind_ip = opts.bind_ip or cosmo.ParseIp("127.0.0.1"),
    _bind_port = opts.bind_port or 3128,
    _index = build_index(opts.allowed_hosts or {}),
    _upstream_ns_fd = opts.upstream_ns_fd,
    _logger = logger,
    _backlog = opts.accept_backlog or 32,
    _listen_fd = nil,
  }, Proxy)
end

-- Bind + listen. Returns the listening fd, or nil,err,errno.
function Proxy:listen()
  local fd, err = unix.socket(unix.AF_INET, unix.SOCK_STREAM, 0)
  if not fd then return nil, tostring(err), err and err:errno() end
  unix.setsockopt(fd, unix.SOL_SOCKET, unix.SO_REUSEADDR, 1)
  local ok, berr = unix.bind(fd, self._bind_ip, self._bind_port)
  if not ok then
    unix.close(fd)
    return nil, tostring(berr), berr and berr:errno()
  end
  ok, err = unix.listen(fd, self._backlog)
  if not ok then
    unix.close(fd)
    return nil, tostring(err), err and err:errno()
  end
  -- Refresh bind_port if the caller asked for 0.
  local _, port = unix.getsockname(fd)
  self._bind_port = port
  self._listen_fd = fd
  self._logger.info("listen",
                    {ip = cosmo.FormatIp(self._bind_ip), port = port})
  return fd
end

-- Accept one connection. Returns the client fd | nil,err.
function Proxy:accept()
  return unix.accept(self._listen_fd)
end

-- Handle one accepted fd in this process. Does NOT fork.
function Proxy:handle(client_fd)
  return handle(self, client_fd)
end

-- Run the accept loop forever, forking per connection. Reaps zombies
-- non-blockingly between accepts. The signal-handling story is left
-- to the caller; if no handler is installed, SIGTERM kills us as
-- usual. If you need a custom shutdown, install a SIGTERM handler
-- with unix.sigaction before calling serve_forever and have it
-- exit() the process directly.
function Proxy:serve_forever()
  if not self._listen_fd then assert(self:listen()) end
  local function reap()
    while true do
      local pid = unix.wait(-1, unix.WNOHANG)
      if not pid or pid == 0 then return end
    end
  end
  while true do
    local cli, aerr = self:accept()
    if not cli then
      if aerr and aerr:errno() == unix.EINTR then
        reap()
      else
        self._logger.warn("accept_fail", {err = tostring(aerr)})
      end
    else
      local pid = unix.fork()
      if pid == 0 then
        unix.close(self._listen_fd)
        self:handle(cli)
        unix.exit(0)
      else
        unix.close(cli)
        reap()
      end
    end
  end
end

return M
