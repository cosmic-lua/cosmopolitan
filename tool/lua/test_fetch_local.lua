-- Tests for the Fetch/FetchStream C contract against loopback servers:
--   * SSRF guard blocks private addresses by default; allowprivate=true
--     opts out and covers the whole redirect chain
--   * the caller's options table is read-only (no mutation on redirect,
--     keepalive=true is not replaced by a table)
--   * success returns the effective URL after redirects as a 4th value
--   * failures return nil, message, and a machine-readable kind
--   * streaming: 204 is clean EOF, chunked reads never return ""

local cosmo = require("cosmo")
local unix = require("cosmo.unix")

-- fetch consults http_proxy/HTTP_PROXY; drop them so loopback requests
-- are direct and the SSRF guard is actually exercised
unix.unsetenv("http_proxy")
unix.unsetenv("HTTP_PROXY")

local function check(desc, cond)
  if not cond then
    error("FAILED: " .. desc, 2)
  end
end

--------------------------------------------------------------------------------
-- Loopback HTTP server: forks one child per connection, routes by path
--------------------------------------------------------------------------------

local LOOPBACK = 0x7f000001  -- 127.0.0.1

local function write_all(c, data)
  local off = 1
  while off <= #data do
    local n = assert(unix.write(c, data:sub(off)))
    off = off + n
  end
end

local function respond(c, status, extra, body)
  write_all(c, "HTTP/1.1 " .. status .. "\r\n" ..
               "Connection: close\r\n" ..
               (extra or "") ..
               "Content-Length: " .. #body .. "\r\n\r\n" .. body)
end

-- Serves requests on one connection. Most routes respond once and close;
-- /ka keeps the connection open so keepalive socket reuse can be observed
-- (the body carries a per-connection request counter).
local function handle(c, base)
  local nreq = 0
  local buf = ""
  while true do
    while not buf:find("\r\n\r\n", 1, true) do
      local data = unix.read(c, 4096)
      if not data or data == "" then
        unix.close(c)
        return
      end
      buf = buf .. data
    end
    local headend = buf:find("\r\n\r\n", 1, true)
    local head = buf:sub(1, headend + 1)
    local rest = buf:sub(headend + 4)
    local method, path = head:match("^(%u+) (%S+)")
    local clen = tonumber(head:match("[Cc]ontent%-[Ll]ength:%s*(%d+)") or "0")
    while #rest < clen do
      local data = unix.read(c, 4096)
      if not data or data == "" then
        break
      end
      rest = rest .. data
    end
    buf = rest:sub(clen + 1)
    nreq = nreq + 1
    if path == "/ka" then
      -- keep-alive: no Connection: close, keep serving this connection
      local body = "req=" .. nreq
      write_all(c, "HTTP/1.1 200 OK\r\nContent-Length: " .. #body ..
                   "\r\n\r\n" .. body)
    elseif path == "/ok" then
      respond(c, "200 OK", nil, "hello")
    elseif path == "/redir" then
      -- relative redirect (same origin: headers must be preserved)
      respond(c, "302 Found", "Location: /echo\r\n", "")
    elseif path == "/redirabs" then
      -- absolute redirect (treated as cross-origin: credentials stripped)
      respond(c, "302 Found", "Location: " .. base .. "/echo\r\n", "")
    elseif path == "/303" then
      respond(c, "303 See Other", "Location: /echo\r\n", "")
    elseif path == "/echo" then
      -- reports what the server actually received
      local auth = head:match("[Aa]uthorization:") and "auth" or "noauth"
      respond(c, "200 OK", nil,
              method .. " " .. auth .. " len=" .. tostring(clen))
    elseif path == "/204" then
      write_all(c, "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n")
    elseif path == "/big" then
      respond(c, "200 OK", nil, string.rep("x", 4096))
    elseif path == "/garbage" then
      write_all(c, "NOTHTTP garbage response\r\n\r\n")
    elseif path == "/slow" then
      unix.nanosleep(5, 0)  -- longer than the client timeout
    elseif path == "/chunked" then
      -- chunk framing and payload land in separate packets, so a naive
      -- streaming reader would surface "" chunks
      write_all(c, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
      unix.nanosleep(0, 150000000)
      write_all(c, "2\r\n")
      unix.nanosleep(0, 150000000)
      write_all(c, "hi\r\n")
      unix.nanosleep(0, 150000000)
      write_all(c, "0\r\n\r\n")
    elseif path == "/lines" then
      -- newline-separated body paced so lines straddle arrival
      -- boundaries: one write ends mid-line, one line spans two
      -- writes, adjacent delimiters make an empty line, and the final
      -- line is unterminated
      local body = "alpha\nbravo\n\ncharlie delta\necho"
      write_all(c, "HTTP/1.1 200 OK\r\nConnection: close\r\n" ..
        "Content-Length: " .. #body .. "\r\n\r\n")
      unix.nanosleep(0, 100000000)
      write_all(c, "alpha\nbra")
      unix.nanosleep(0, 100000000)
      write_all(c, "vo\n\ncharlie")
      unix.nanosleep(0, 100000000)
      write_all(c, " delta\necho")
    else
      respond(c, "404 Not Found", nil, "")
    end
    if path ~= "/ka" then
      unix.close(c)
      return
    end
  end
end

-- Starts a server; handler(clientfd, baseurl) runs in a forked child per
-- connection. Returns pid and base URL.
local function start_server(handler)
  local srv = assert(unix.socket(unix.AF_INET, unix.SOCK_STREAM))
  assert(unix.bind(srv, LOOPBACK, 0))
  assert(unix.listen(srv, 16))
  local _, port = assert(unix.getsockname(srv))
  local base = "http://127.0.0.1:" .. port
  local pid = assert(unix.fork())
  if pid == 0 then
    while true do
      local c = unix.accept(srv)
      if c then
        local cpid = unix.fork()
        if cpid == 0 then
          unix.close(srv)
          handler(c, base)
          unix.exit(0)
        end
        unix.close(c)
      end
    end
  end
  unix.close(srv)
  return pid, base, port
end

local server_pid, BASE = start_server(handle)

-- raw server for the TLS test: writes non-TLS bytes as soon as a client
-- connects, so an https:// fetch fails during the handshake
local tls_pid, _, TLS_PORT = start_server(function(c)
  write_all(c, "THIS IS NOT A TLS SERVER\r\n")
  unix.close(c)
end)

local function stop_servers()
  unix.kill(server_pid, unix.SIGKILL)
  unix.kill(tls_pid, unix.SIGKILL)
  unix.wait(server_pid)
  unix.wait(tls_pid)
end

--------------------------------------------------------------------------------
-- 1. SSRF guard: private destinations blocked by default, kind "blocked"
--------------------------------------------------------------------------------
local function test_ssrf_blocked_by_default()
  local status, err, kind = cosmo.Fetch(BASE .. "/ok")
  check("plain Fetch to loopback fails", status == nil)
  check("error mentions SSRF", err:find("SSRF"))
  check("kind is blocked", kind == "blocked")

  local sstatus, serr, skind = cosmo.FetchStream(BASE .. "/ok")
  check("plain FetchStream to loopback fails", sstatus == nil)
  check("stream error mentions SSRF", serr:find("SSRF"))
  check("stream kind is blocked", skind == "blocked")
end

--------------------------------------------------------------------------------
-- 2. allowprivate=true reaches loopback; success returns effective URL
--------------------------------------------------------------------------------
local function test_allowprivate()
  local status, headers, body, url = cosmo.Fetch(BASE .. "/ok",
                                                 {allowprivate = true})
  check("allowprivate fetch succeeds", status == 200)
  check("body", body == "hello")
  check("headers table", type(headers) == "table")
  check("effective url", url == BASE .. "/ok")
end

--------------------------------------------------------------------------------
-- 3. allowprivate covers the whole redirect chain; final URL reported
--------------------------------------------------------------------------------
local function test_redirect_chain_and_final_url()
  local status, _, body, url = cosmo.Fetch(BASE .. "/redir",
                                           {allowprivate = true})
  check("redirected fetch succeeds", status == 200)
  check("redirect landed on /echo", body:find("^GET"))
  check("final url is the redirect target", url == BASE .. "/echo")
end

--------------------------------------------------------------------------------
-- 4. the caller's options table is never modified
--------------------------------------------------------------------------------
local function snapshot_opts()
  return {
    method = "POST",
    body = "postdata",
    allowprivate = true,
    headers = {
      Authorization = "Bearer secret",
      ["X-Custom"] = "42",
    },
  }
end

local function assert_opts_unchanged(desc, opts)
  check(desc .. ": method unchanged", opts.method == "POST")
  check(desc .. ": body unchanged", opts.body == "postdata")
  check(desc .. ": allowprivate unchanged", opts.allowprivate == true)
  check(desc .. ": numredirects not added", opts.numredirects == nil)
  check(desc .. ": maxredirects not added", opts.maxredirects == nil)
  check(desc .. ": followredirect not added", opts.followredirect == nil)
  check(desc .. ": timeout not added", opts.timeout == nil)
  check(desc .. ": maxresponse not added", opts.maxresponse == nil)
  check(desc .. ": Authorization kept",
        opts.headers.Authorization == "Bearer secret")
  check(desc .. ": X-Custom kept", opts.headers["X-Custom"] == "42")
  local n = 0
  for _ in pairs(opts.headers) do
    n = n + 1
  end
  check(desc .. ": no headers added", n == 2)
end

local function test_opts_not_mutated_absolute_redirect()
  -- absolute Location: credentials are stripped from the wire but the
  -- caller's tables must stay intact
  local opts = snapshot_opts()
  local status, _, body = cosmo.Fetch(BASE .. "/redirabs", opts)
  check("absolute redirect succeeds", status == 200)
  check("credentials stripped on the wire", body:find("noauth", 1, true))
  assert_opts_unchanged("Fetch/redirabs", opts)
end

local function test_opts_not_mutated_relative_redirect()
  -- relative Location: same origin, so headers are re-sent
  local opts = snapshot_opts()
  local status, _, body = cosmo.Fetch(BASE .. "/redir", opts)
  check("relative redirect succeeds", status == 200)
  check("credentials kept same-origin", body:find(" auth ", 1, true))
  assert_opts_unchanged("Fetch/redir", opts)
end

local function test_303_drops_body_without_mutating_opts()
  local opts = snapshot_opts()
  local status, _, body = cosmo.Fetch(BASE .. "/303", opts)
  check("303 redirect succeeds", status == 200)
  check("303 switched to GET with empty body",
        body:find("^GET") and body:find("len=0", 1, true))
  assert_opts_unchanged("Fetch/303", opts)
end

local function test_stream_opts_not_mutated()
  local opts = snapshot_opts()
  local status, _, reader = cosmo.FetchStream(BASE .. "/redirabs", opts)
  check("FetchStream redirect succeeds", status == 200)
  local body = ""
  while true do
    local chunk = reader:read()
    if not chunk then
      break
    end
    body = body .. chunk
  end
  reader:close()
  check("stream credentials stripped on the wire",
        body:find("noauth", 1, true))
  assert_opts_unchanged("FetchStream/redirabs", opts)
end

--------------------------------------------------------------------------------
-- 5. keepalive=true is not replaced by a table; connections are reused
--------------------------------------------------------------------------------
local function test_keepalive_true_not_replaced()
  local opts = {allowprivate = true, keepalive = true}
  local status1, _, body1 = cosmo.Fetch(BASE .. "/ka", opts)
  check("first keepalive fetch", status1 == 200 and body1 == "req=1")
  check("keepalive still boolean true", opts.keepalive == true)
  local status2, _, body2 = cosmo.Fetch(BASE .. "/ka", opts)
  check("second keepalive fetch", status2 == 200)
  check("connection was reused", body2 == "req=2")
  check("keepalive still boolean true after reuse", opts.keepalive == true)
end

--------------------------------------------------------------------------------
-- 6. failure kinds
--------------------------------------------------------------------------------
local function test_kind_connect()
  -- grab a port that is not listening by binding and closing it
  local s = assert(unix.socket(unix.AF_INET, unix.SOCK_STREAM))
  assert(unix.bind(s, LOOPBACK, 0))
  local _, deadport = assert(unix.getsockname(s))
  unix.close(s)
  local status, err, kind = cosmo.Fetch("http://127.0.0.1:" .. deadport .. "/",
                                        {allowprivate = true})
  check("refused connect fails", status == nil)
  check("kind is connect, got " .. tostring(kind) ..
        " (" .. tostring(err) .. ")", kind == "connect")
end

local function test_kind_dns()
  local status, err, kind =
      cosmo.Fetch("http://nonexistent-host-for-cosmo-tests.invalid/")
  check("dns failure fails", status == nil)
  check("kind is dns, got " .. tostring(kind) ..
        " (" .. tostring(err) .. ")", kind == "dns")
end

local function test_kind_timeout()
  local status, err, kind = cosmo.Fetch(BASE .. "/slow",
                                        {allowprivate = true, timeout = 1})
  check("slow server times out", status == nil)
  check("kind is timeout, got " .. tostring(kind) ..
        " (" .. tostring(err) .. ")", kind == "timeout")
end

local function test_kind_too_large()
  local status, err, kind = cosmo.Fetch(BASE .. "/big",
                                        {allowprivate = true,
                                         maxresponse = 100})
  check("oversized response fails", status == nil)
  check("kind is too_large, got " .. tostring(kind) ..
        " (" .. tostring(err) .. ")", kind == "too_large")
  -- regression: the configured byte limit must render in the message, not
  -- the literal "%I" left by an unrecognized format conversion
  check("error names the configured limit, got: " .. tostring(err),
        err:match("max 100 bytes") ~= nil)
end

local function test_kind_protocol()
  local status, err, kind = cosmo.Fetch(BASE .. "/garbage",
                                        {allowprivate = true})
  check("non-HTTP response fails", status == nil)
  check("kind is protocol, got " .. tostring(kind) ..
        " (" .. tostring(err) .. ")", kind == "protocol")
end

local function test_kind_proxy()
  local status, err, kind = cosmo.Fetch("http://example.com/",
                                        {proxy = "unix:///nonexistent.sock"})
  check("bad proxy fails", status == nil)
  check("kind is proxy, got " .. tostring(kind) ..
        " (" .. tostring(err) .. ")", kind == "proxy")
end

local function test_kind_tls()
  local status, err, kind = cosmo.Fetch("https://127.0.0.1:" .. TLS_PORT .. "/",
                                        {allowprivate = true, timeout = 5})
  check("non-TLS server fails handshake", status == nil)
  check("kind is tls, got " .. tostring(kind) ..
        " (" .. tostring(err) .. ")", kind == "tls")
end

--------------------------------------------------------------------------------
-- 7. streaming reader edge cases
--------------------------------------------------------------------------------
local function test_stream_basic_and_url()
  local status, headers, reader, url = cosmo.FetchStream(
      BASE .. "/ok", {allowprivate = true})
  check("stream fetch succeeds", status == 200)
  check("stream effective url", url == BASE .. "/ok")
  local body = ""
  while true do
    local chunk = reader:read()
    if not chunk then
      break
    end
    body = body .. chunk
  end
  check("stream body", body == "hello")
  reader:close()
  local afterclose, closeerr = reader:read()
  check("read after close errors",
        afterclose == nil and closeerr == "reader closed")
  check("headers table", type(headers) == "table")
end

local function test_stream_204_clean_eof()
  local status, _, reader = cosmo.FetchStream(BASE .. "/204",
                                              {allowprivate = true})
  check("204 stream fetch succeeds", status == 204)
  local chunk, err = reader:read()
  check("204 body read is clean EOF, got " .. tostring(chunk) .. ", " ..
        tostring(err), chunk == nil and err == nil)
  local chunk2, err2 = reader:read()
  check("204 second read still clean EOF", chunk2 == nil and err2 == nil)
  reader:close()
end

local function test_stream_no_empty_chunks()
  local status, _, reader = cosmo.FetchStream(BASE .. "/chunked",
                                              {allowprivate = true})
  check("chunked stream fetch succeeds", status == 200)
  local body = ""
  while true do
    local chunk, err = reader:read()
    if not chunk then
      check("chunked stream ends cleanly, got error " .. tostring(err),
            err == nil)
      break
    end
    check("no empty chunk surfaced", #chunk > 0)
    body = body .. chunk
  end
  reader:close()
  check("chunked body reassembled", body == "hi")
end

local function test_read_until_lines()
  local status, _, reader = cosmo.FetchStream(BASE .. "/lines",
                                              {allowprivate = true})
  check("lines stream fetch succeeds", status == 200)
  local got = {}
  while true do
    local line, err = reader:read_until("\n")
    if not line then
      check("lines stream ends cleanly, got error " .. tostring(err),
            err == nil)
      break
    end
    got[#got + 1] = line
  end
  check("line count, got " .. #got, #got == 5)
  check("line 1", got[1] == "alpha")
  check("line spanning two writes", got[2] == "bravo")
  check("adjacent delimiters yield an empty line", got[3] == "")
  check("line 4", got[4] == "charlie delta")
  check("unterminated final line yielded once", got[5] == "echo")
  local again, aerr = reader:read_until("\n")
  check("EOF after remainder stays nil", again == nil and aerr == nil)
  reader:close()
  local closed, cerr = reader:read_until("\n")
  check("read_until after close errors",
        closed == nil and cerr == "reader closed")
end

local function test_read_until_multibyte_and_mixing()
  -- multi-byte delimiter spanning the first two server writes
  -- ("alpha\nbra" + "vo\n..."): the scan must see it once the carry
  -- buffer holds both arrivals
  local status, _, reader = cosmo.FetchStream(BASE .. "/lines",
                                              {allowprivate = true})
  check("lines stream fetch succeeds again", status == 200)
  local first = reader:read_until("a\nbrav")
  check("multi-byte delimiter consumed across a write boundary, got " ..
        string.format("%q", tostring(first)), first == "alph")
  -- mixing: read() must drain the carry-over before touching the wire,
  -- so the reassembled tail continues exactly after the delimiter
  local rest = ""
  while true do
    local chunk = reader:read()
    if not chunk then break end
    rest = rest .. chunk
  end
  check("read() after read_until() drains carry-over in order, got " ..
        string.format("%q", rest), rest == "o\n\ncharlie delta\necho")
  reader:close()
end

local function test_read_until_delim_validation()
  local status, _, reader = cosmo.FetchStream(BASE .. "/ok",
                                              {allowprivate = true})
  check("ok stream fetch succeeds", status == 200)
  local ok = pcall(function() return reader:read_until("") end)
  check("empty delimiter is rejected", not ok)
  -- delimiter absent from the body: whole body is the remainder
  local all, rerr = reader:read_until("\n")
  check("delimiter-free body returned whole as remainder, got " ..
        tostring(all) .. " " .. tostring(rerr), all == "hello")
  check("then clean EOF", (reader:read_until("\n")) == nil)
  reader:close()
end

--------------------------------------------------------------------------------
-- Run all tests
--------------------------------------------------------------------------------
print("Running local fetch tests...")

local tests = {
  {"SSRF blocked by default with kind=blocked", test_ssrf_blocked_by_default},
  {"allowprivate reaches loopback + effective url", test_allowprivate},
  {"allowprivate covers redirect chain + final url",
   test_redirect_chain_and_final_url},
  {"opts untouched on absolute redirect",
   test_opts_not_mutated_absolute_redirect},
  {"opts untouched on relative redirect",
   test_opts_not_mutated_relative_redirect},
  {"303 drops body on the wire only", test_303_drops_body_without_mutating_opts},
  {"FetchStream opts untouched on redirect", test_stream_opts_not_mutated},
  {"keepalive=true stays boolean; socket reused",
   test_keepalive_true_not_replaced},
  {"kind=connect on refused port", test_kind_connect},
  {"kind=dns on unresolvable host", test_kind_dns},
  {"kind=too_large on oversized response", test_kind_too_large},
  {"kind=protocol on non-HTTP response", test_kind_protocol},
  {"kind=proxy on bad proxy", test_kind_proxy},
  {"kind=tls on non-TLS server", test_kind_tls},
  {"kind=timeout on stalled server", test_kind_timeout},
  {"stream basic read + effective url", test_stream_basic_and_url},
  {"stream 204 clean EOF", test_stream_204_clean_eof},
  {"stream chunked never returns empty chunks", test_stream_no_empty_chunks},
  {"read_until iterates lines across arrival boundaries",
   test_read_until_lines},
  {"read_until multi-byte delim + read() mixing",
   test_read_until_multibyte_and_mixing},
  {"read_until validates delim; remainder-only body",
   test_read_until_delim_validation},
}

local ok, failure = true, nil
for _, t in ipairs(tests) do
  local passed, err = pcall(t[2])
  if passed then
    print("  [pass] " .. t[1])
  else
    print("  [FAIL] " .. t[1] .. ": " .. tostring(err))
    ok, failure = false, failure or err
  end
end

stop_servers()

if not ok then
  error(failure)
end
print("all local fetch tests passed")
