-- Unit tests for cosmo.sandbox.proxy's pure-Lua bits (allowlist
-- matching, request parsing, auth header construction, header
-- rebuilding). No sockets, no fork, no privileges required — runs
-- everywhere lua.com runs.

local proxy = require "cosmo.sandbox.proxy"
local cosmo = require "cosmo"

local function assertf(cond, fmt, ...)
  if not cond then error(string.format(fmt, ...), 2) end
end

-- parse_rule normalizes various host:port forms.
do
  local h, p = proxy._parse_rule("api.github.com:443")
  assertf(h == "api.github.com" and p == 443, "exact host:port wrong")
  h, p = proxy._parse_rule("api.github.com")
  assertf(h == "api.github.com" and p == nil, "host-only wrong")
  h, p = proxy._parse_rule("api.github.com:*")
  assertf(h == "api.github.com" and p == nil, "wildcard port wrong")
  h, p = proxy._parse_rule("API.GITHUB.COM:443")
  assertf(h == "api.github.com" and p == 443, "case-insensitive failed")
end

-- match: exact, wildcard, miss, case folding.
do
  local idx = proxy._build_index{
    ["api.github.com:443"] = {type = "bearer", token = "x"},
    ["pypi.org"]            = {},
    ["registry.npmjs.org:*"] = {},
  }
  assertf(proxy._match(idx, "api.github.com", 443),
          "exact match failed")
  assertf(not proxy._match(idx, "api.github.com", 80),
          "wrong port should miss")
  assertf(proxy._match(idx, "PYPI.ORG", 443), "case fold failed")
  assertf(proxy._match(idx, "pypi.org", 80),
          "wildcard host should match any port")
  assertf(proxy._match(idx, "registry.npmjs.org", 443),
          "explicit-* match failed")
  assertf(not proxy._match(idx, "evil.com", 443),
          "evil.com should not match")
end

-- auth_header for each rule type.
do
  local n, v = proxy._auth_header{type = "bearer", token = "ghp_x"}
  assertf(n == "Authorization" and v == "Bearer ghp_x", "bearer wrong")
  n, v = proxy._auth_header{type = "basic", username = "u", password = "p"}
  assertf(n == "Authorization", "basic name wrong")
  -- u:p base64 -> dTpw
  assertf(v == "Basic " .. cosmo.EncodeBase64("u:p"), "basic value wrong")
  n, v = proxy._auth_header{type = "header", header_name = "x-api-key",
                            header_value = "sk-ant"}
  assertf(n == "x-api-key" and v == "sk-ant", "header rule wrong")
  assertf(proxy._auth_header(nil) == nil, "nil rule should yield nil")
  assertf(proxy._auth_header{} == nil, "empty rule should yield nil")
end

-- parse_request_line accepts the canonical form.
do
  local m, t, v = proxy._parse_request_line("CONNECT api.github.com:443 HTTP/1.1\r\n")
  assertf(m == "CONNECT", "method wrong")
  assertf(t == "api.github.com:443", "target wrong")
  assertf(v == "HTTP/1.1", "version wrong")
  assertf(proxy._parse_request_line("garbage") == nil,
          "garbage should not parse")
end

-- parse_connect_target requires host:port.
do
  local h, p = proxy._parse_connect_target("api.github.com:443")
  assertf(h == "api.github.com" and p == 443, "connect parse wrong")
  assertf(proxy._parse_connect_target("api.github.com") == nil,
          "connect needs explicit port")
end

-- parse_absolute_uri handles http and https with default ports.
do
  local s, h, p, path = proxy._parse_absolute_uri("http://example.com/foo")
  assertf(s == "http" and h == "example.com" and p == 80 and path == "/foo",
          "http default port wrong")
  s, h, p, path = proxy._parse_absolute_uri("https://api.github.com:8443/v1")
  assertf(s == "https" and h == "api.github.com" and p == 8443 and path == "/v1",
          "explicit port wrong")
  s, h, p, path = proxy._parse_absolute_uri("http://example.com")
  assertf(path == "/", "missing path defaults to /")
end

-- content_length pulls the integer out (case-insensitive).
do
  local hdr = "POST /x HTTP/1.1\r\nhost: a\r\nCONTENT-Length: 17\r\n\r\n"
  assertf(proxy._content_length(hdr) == 17, "content-length parse wrong")
  assertf(proxy._content_length("GET / HTTP/1.1\r\n\r\n") == 0,
          "absent content-length should be 0")
end

-- rebuild_request strips hop-by-hop headers, replaces auth, sets Host.
do
  local hdr = table.concat{
    "GET /api HTTP/1.1\r\n",
    "Host: api.github.com\r\n",
    "User-Agent: x\r\n",
    "Authorization: Bearer OLD\r\n",
    "Connection: keep-alive\r\n",
    "Proxy-Connection: keep-alive\r\n",
    "X-Custom: yes\r\n",
    "\r\n",
  }
  local out = proxy._rebuild_request(
    "GET", "/api", hdr, nil,
    "Authorization", "Bearer NEW", "api.github.com")
  assertf(out:find("\r\nAuthorization: Bearer NEW\r\n", 1, true),
          "injected header missing")
  assertf(not out:find("Bearer OLD", 1, true),
          "old auth not stripped")
  assertf(not out:find("Proxy-Connection", 1, true),
          "Proxy-Connection not stripped")
  assertf(not out:lower():find("\r\nconnection: keep-alive\r\n", 1, true),
          "Connection: keep-alive not stripped")
  assertf(out:find("\r\nConnection: close\r\n", 1, true),
          "Connection: close not added")
  assertf(out:find("\r\nX-Custom: yes\r\n", 1, true),
          "non-hop header dropped")
  assertf(out:find("\r\nHost: api.github.com\r\n", 1, true),
          "Host header missing")
  assertf(out:sub(1, 19) == "GET /api HTTP/1.1\r\n",
          "request line wrong: %q", out:sub(1, 30))
end

-- rebuild_request preserves request body and adds Content-Length.
do
  local hdr = "POST /x HTTP/1.1\r\nHost: api.github.com\r\n\r\n"
  local out = proxy._rebuild_request(
    "POST", "/x", hdr, "hello",
    nil, nil, "api.github.com")
  assertf(out:find("\r\nContent-Length: 5\r\n", 1, true),
          "content-length not added")
  assertf(out:sub(-5) == "hello", "body not appended")
end

-- New() should accept minimal config and not raise.
do
  local p = proxy.new{
    allowed_hosts = {["api.github.com:443"] = {}},
    log_level = "quiet",
  }
  assertf(type(p) == "table", "new() did not return table")
  assertf(p._index, "index not built")
end

print("cosmo.sandbox.proxy unit tests passed")
