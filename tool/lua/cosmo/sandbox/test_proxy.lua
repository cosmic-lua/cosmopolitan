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

-- match: suffix wildcards (*.domain.com / *.domain.com:port).
do
  local idx = proxy._build_index{
    ["*.githubusercontent.com"]          = true,
    ["*.anthropic.com:443"]              = {type = "bearer", token = "x"},
    ["api.anthropic.com:443"]            = {type = "bearer", token = "exact"},
  }
  -- *.githubusercontent.com matches any subdomain on any port.
  assertf(proxy._match(idx, "raw.githubusercontent.com", 443),
          "*.x.com should match raw.x.com:443")
  assertf(proxy._match(idx, "objects.githubusercontent.com", 80),
          "*.x.com should match any port")
  -- Tail-matching must be anchored at a dot — "evilxcom" must miss
  -- *.x.com, and "githubusercontent.com" (the apex) must miss the
  -- subdomain pattern.
  assertf(not proxy._match(idx, "githubusercontent.com", 443),
          "apex should not match *.suffix")
  assertf(not proxy._match(idx, "evil-githubusercontent.com", 443),
          "substring should not match *.suffix")
  -- *.anthropic.com:443 is port-restricted.
  assertf(proxy._match(idx, "statsig.anthropic.com", 443),
          "*.x.com:443 should match on port 443")
  assertf(not proxy._match(idx, "statsig.anthropic.com", 80),
          "*.x.com:443 should not match on port 80")
  -- Exact match takes precedence over suffix match.
  local hit = proxy._match(idx, "api.anthropic.com", 443)
  assertf(hit and hit.token == "exact",
          "exact match should win over suffix")
end

-- Rule-table shorthand: `true` means "any method, no auth injection".
do
  local idx = proxy._build_index{["allow.example"] = true}
  local hit = proxy._match(idx, "allow.example", 443)
  assertf(hit == true, "shorthand rule should be passed through as-is")
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

-- parse_headers splits the block, ignores the request line, lowercases
-- the names, preserves the original-case in [1], and yields {orig, lower, value}.
do
  local hdr = "GET / HTTP/1.1\r\nHost: a\r\nX-Foo: bar\r\n\r\n"
  local h = proxy._parse_headers(hdr)
  assertf(#h == 2, "parsed %d headers, expected 2", #h)
  assertf(h[1][1] == "Host" and h[1][2] == "host" and h[1][3] == "a",
          "host header parsed wrong")
  assertf(h[2][1] == "X-Foo" and h[2][2] == "x-foo" and h[2][3] == "bar",
          "x-foo header parsed wrong")
  -- header_get is case-insensitive on the lowercased index.
  assertf(proxy._header_get(h, "host") == "a", "header_get host")
  assertf(proxy._header_get(h, "missing") == nil, "header_get missing")
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

-- Regression: rebuild_request must NOT emit duplicate Content-Length
-- when the original request already had one. This was the bug in
-- proxy.lua v0.0.1.
do
  local hdr = "POST /x HTTP/1.1\r\nHost: api.x\r\nContent-Length: 5\r\n\r\n"
  local out = proxy._rebuild_request("POST", "/x", hdr, "hello",
                                     nil, nil, "api.x")
  local n = 0
  for _ in out:lower():gmatch("\r\ncontent%-length:") do n = n + 1 end
  assertf(n == 1,
          "Content-Length appeared %d times (expected 1):\n%s", n, out)
end

-- Regression: Host header must not be duplicated either; rebuild
-- always emits exactly one Host: line whether or not the original
-- request had one.
do
  for _, hdr in ipairs{
    "GET /a HTTP/1.1\r\nHost: orig.example\r\n\r\n",
    "GET /a HTTP/1.1\r\n\r\n",                   -- no Host in original
  } do
    local out = proxy._rebuild_request("GET", "/a", hdr, nil,
                                       nil, nil, "new.example")
    local n = 0
    for _ in out:lower():gmatch("\r\nhost:") do n = n + 1 end
    assertf(n == 1, "Host appeared %d times:\n%s", n, out)
    assertf(out:find("\r\nHost: new.example\r\n", 1, true),
            "Host not rewritten to upstream")
  end
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

-- Strict mode: default (strict=false) silently tolerates typos so we
-- don't break existing callers.
do
  local ok, p = pcall(proxy.new, {
    log_level = "quiet",
    allowed_hosts = {
      ["api.example:443"] = {type = "Bearer", token = "x"},  -- typo
    },
  })
  assertf(ok, "non-strict mode should accept unknown rule types: %s",
          tostring(p))
  assertf(type(p) == "table", "non-strict should still return proxy")
end

-- Strict mode: unknown rule.type is rejected at construction time.
do
  local ok, err = pcall(proxy.new, {
    log_level = "quiet",
    strict = true,
    allowed_hosts = {
      ["api.example:443"] = {type = "Bearer", token = "x"},  -- capital B
    },
  })
  assertf(not ok, "strict mode should reject unknown rule type")
  assertf(tostring(err):lower():find("bearer", 1, true) or
          tostring(err):lower():find("type", 1, true),
          "strict error should mention the offending type: %s", tostring(err))
end

-- Strict mode: bearer rule missing `token` is rejected.
do
  local ok, err = pcall(proxy.new, {
    log_level = "quiet",
    strict = true,
    allowed_hosts = {["api.example:443"] = {type = "bearer"}},
  })
  assertf(not ok, "strict mode should reject bearer without token")
  assertf(tostring(err):lower():find("token", 1, true),
          "strict error should mention missing token: %s", tostring(err))
end

-- Strict mode: basic rule missing username or password is rejected.
do
  local ok, err = pcall(proxy.new, {
    log_level = "quiet",
    strict = true,
    allowed_hosts = {
      ["api.example:443"] = {type = "basic", username = "u"},  -- no password
    },
  })
  assertf(not ok, "strict mode should reject basic without password")
  assertf(tostring(err):lower():find("password", 1, true),
          "strict error should mention missing password: %s", tostring(err))
end

-- Strict mode: header rule missing header_name/header_value is rejected.
do
  local ok, err = pcall(proxy.new, {
    log_level = "quiet",
    strict = true,
    allowed_hosts = {
      ["api.example:443"] = {type = "header", header_name = "x-api-key"},
    },
  })
  assertf(not ok, "strict mode should reject header without header_value")
  assertf(tostring(err):lower():find("header_value", 1, true),
          "strict error should mention missing header_value: %s", tostring(err))
end

-- Strict mode: valid rules still pass.
do
  local p = proxy.new{
    log_level = "quiet",
    strict = true,
    allowed_hosts = {
      ["api.example:443"]     = {type = "bearer", token = "x"},
      ["basic.example:443"]   = {type = "basic", username = "u", password = "p"},
      ["header.example:443"]  = {type = "header", header_name = "x-k",
                                 header_value = "v"},
      ["pass.example"]        = true,        -- allowed, no auth
      ["bare.example"]        = {},          -- allowed, no auth
      ["*.wild.example:443"]  = {type = "bearer", token = "y"},
    },
  }
  assertf(type(p) == "table", "strict + valid rules should construct cleanly")
end

print("cosmo.sandbox.proxy unit tests passed")
