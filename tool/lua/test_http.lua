-- Tests for cosmo.http: the HTTP/1.1 head parser, the chunked-transfer
-- decoder and the extension to content-type lookup.

local http = require("cosmo.http")

assert(type(http.parser) == "function", "http.parser should be a function")
assert(type(http.unchunker) == "function", "http.unchunker should be a function")
assert(type(http.find_content_type) == "function",
  "http.find_content_type should be a function")

--------------------------------------------------------------------------------
-- A whole Chrome-style GET parses in one call
--------------------------------------------------------------------------------

-- The fixture net/http's own parsehttpmessage benchmark uses, byte for
-- byte (test/net/http/parsehttpmessage_test.c, DoStandardChromeRequest).
-- DNT's value carries leading and trailing whitespace the parser trims.
local CHROME = "GET /tool/net/redbean.png HTTP/1.1\r\n" ..
  "Host: 10.10.10.124:8080\r\n" ..
  "Connection: keep-alive\r\n" ..
  "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" ..
  " (KHTML, like Gecko) Chrome/89.0.4389.90 Safari/537.36\r\n" ..
  "DNT:  \t1   \r\n" ..
  "Accept: image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8\r\n" ..
  "Referer: http://10.10.10.124:8080/\r\n" ..
  "Accept-Encoding: gzip, deflate\r\n" ..
  "Accept-Language: en-US,en;q=0.9\r\n" ..
  "\r\n"
assert(#CHROME == 403, "chrome fixture should be 403 bytes, got " .. #CHROME)

local p = http.parser("request")
assert(tostring(p) == "http.Parser(request)", "tostring: " .. tostring(p))
assert(tostring(http.parser("response")) == "http.Parser(response)",
  "tostring: " .. tostring(http.parser("response")))
local n = assert(p:parse(CHROME))
assert(n == #CHROME, "whole head should parse: got " .. tostring(n))

local msg = p:message(CHROME)
assert(msg.method == "GET", "method: " .. tostring(msg.method))
assert(msg.uri == "/tool/net/redbean.png", "uri: " .. tostring(msg.uri))
assert(msg.version == 11, "version: " .. tostring(msg.version))
assert(msg.status == nil, "a request has no status")
assert(msg.headers.Host == "10.10.10.124:8080",
  "Host: " .. tostring(msg.headers.Host))
assert(msg.headers.Connection == "keep-alive",
  "Connection: " .. tostring(msg.headers.Connection))
assert(msg.headers.DNT == "1", "DNT: " .. tostring(msg.headers.DNT))
-- Accept-Language is one of net/http's repeatable names, so it arrives as
-- a one-element array even here, where the request sent it once.
assert(type(msg.headers["Accept-Language"]) == "table" and
  #msg.headers["Accept-Language"] == 1 and
  msg.headers["Accept-Language"][1] == "en-US,en;q=0.9",
  "Accept-Language: " .. tostring(msg.headers["Accept-Language"]))
assert(msg.headers["User-Agent"]:find("Chrome/89", 1, true),
  "User-Agent: " .. tostring(msg.headers["User-Agent"]))
assert(msg.headers.Referer == "http://10.10.10.124:8080/",
  "Referer: " .. tostring(msg.headers.Referer))
assert(msg.headers["Content-Length"] == nil, "absent header should be nil")

--------------------------------------------------------------------------------
-- The same bytes one at a time: 0 until the last byte, then the same n
--------------------------------------------------------------------------------

local drip = http.parser("request")
local last
for i = 1, #CHROME do
  last = assert(drip:parse(CHROME:sub(1, i)))
  if i < #CHROME then
    assert(last == 0, "byte " .. i .. " should need more data, got " ..
      tostring(last))
  end
end
assert(last == #CHROME, "fragmented parse should end at " .. #CHROME ..
  ", got " .. tostring(last))
local dripmsg = drip:message(CHROME)
assert(dripmsg.uri == "/tool/net/redbean.png",
  "fragmented uri: " .. tostring(dripmsg.uri))
assert(dripmsg.headers.Host == "10.10.10.124:8080",
  "fragmented Host: " .. tostring(dripmsg.headers.Host))

--------------------------------------------------------------------------------
-- Two pipelined requests in one buffer, read with reset() between them
--------------------------------------------------------------------------------

local first = "GET /one HTTP/1.1\r\nHost: a\r\n\r\n"
local second = "POST /two HTTP/1.0\r\nHost: b\r\n\r\n"
local both = first .. second

local pipe = http.parser("request")
local n1 = assert(pipe:parse(both))
assert(n1 == #first, "first head length: " .. tostring(n1))
local m1 = pipe:message(both)
assert(m1.method == "GET" and m1.uri == "/one" and m1.version == 11,
  "first message: " .. tostring(m1.method) .. " " .. tostring(m1.uri))
assert(m1.headers.Host == "a", "first Host: " .. tostring(m1.headers.Host))

pipe:reset()
local rest = both:sub(n1 + 1)
local n2 = assert(pipe:parse(rest))
assert(n2 == #second, "second head length: " .. tostring(n2))
local m2 = pipe:message(rest)
assert(m2.method == "POST" and m2.uri == "/two" and m2.version == 10,
  "second message: " .. tostring(m2.method) .. " " .. tostring(m2.uri))
assert(m2.headers.Host == "b", "second Host: " .. tostring(m2.headers.Host))

--------------------------------------------------------------------------------
-- Headers come back in cosmo.Fetch's shape, so one normalizer serves both
--------------------------------------------------------------------------------

-- A repeatable name is an array from its FIRST occurrence, which is what
-- cosmo.Fetch does (tool/net/lfetch.c's LuaPushHeaders): a caller reads
-- one shape whether the message carried the header once or five times.
local one = http.parser("response")
local onebuf = "HTTP/1.1 200 OK\r\nVary: Accept\r\nServer: s\r\n\r\n"
assert(one:parse(onebuf) == #onebuf, "single repeatable head should parse")
local onemsg = one:message(onebuf)
assert(type(onemsg.headers.Vary) == "table",
  "a repeatable header seen once should still be an array, got " ..
  type(onemsg.headers.Vary))
assert(#onemsg.headers.Vary == 1 and onemsg.headers.Vary[1] == "Accept",
  "Vary: " .. table.concat(onemsg.headers.Vary, ","))
assert(onemsg.headers.Server == "s",
  "a non-repeatable header stays a string, got " ..
  type(onemsg.headers.Server))

-- Seen again, the same array grows, in arrival order.
local dup = http.parser("response")
local dupbuf = "HTTP/1.1 200 OK\r\nVary: Accept\r\nVary: Origin\r\n\r\n"
assert(dup:parse(dupbuf) == #dupbuf, "repeated-header head should parse")
local dupmsg = dup:message(dupbuf)
assert(type(dupmsg.headers.Vary) == "table",
  "Vary should be an array, got " .. type(dupmsg.headers.Vary))
assert(#dupmsg.headers.Vary == 2, "Vary should have 2 values, got " ..
  #dupmsg.headers.Vary)
assert(dupmsg.headers.Vary[1] == "Accept" and
  dupmsg.headers.Vary[2] == "Origin",
  "Vary values: " .. table.concat(dupmsg.headers.Vary, ","))

-- A name net/http does not mark repeatable is a plain string even when
-- it repeats, the later value winning -- Fetch's behaviour exactly.
local xdup = http.parser("request")
local xbuf = "GET / HTTP/1.1\r\nX-Once: y\r\nX-Once: z\r\n\r\n"
assert(xdup:parse(xbuf) == #xbuf, "repeated x-header head should parse")
local xmsg = xdup:message(xbuf)
assert(xmsg.headers["X-Once"] == "z",
  "a repeated non-repeatable header should hold the last value, got " ..
  tostring(xmsg.headers["X-Once"]))

-- Set-Cookie is NOT in net/http's kHttpRepeatable table, even though it
-- is a natural-sounding example of a header a message repeats. A caller
-- following the (once wrong) docs would read ipairs() over this and see
-- nothing, silently losing the first cookie -- pin the real shape here
-- so that mistake can't creep back into definitions.lua or lhttp.c.
local cookie = http.parser("response")
local cookiebuf = "HTTP/1.1 200 OK\r\nSet-Cookie: a=1\r\nSet-Cookie: b=2\r\n\r\n"
assert(cookie:parse(cookiebuf) == #cookiebuf,
  "repeated Set-Cookie head should parse")
local cookiemsg = cookie:message(cookiebuf)
assert(cookiemsg.headers["Set-Cookie"] == "b=2",
  "Set-Cookie is not repeatable, so a second occurrence should replace " ..
  "the first, got " .. tostring(cookiemsg.headers["Set-Cookie"]))

--------------------------------------------------------------------------------
-- A malformed head is the fallible tuple, not a throw
--------------------------------------------------------------------------------

local bad = http.parser("request")
local br, berr = bad:parse("GET\x01 / HTTP/1.1\r\n\r\n")
assert(br == nil, "a malformed head should return nil, got " .. tostring(br))
assert(berr == "bad message", "error should be 'bad message', got " ..
  tostring(berr))

--------------------------------------------------------------------------------
-- A response-kind parser reads the status line
--------------------------------------------------------------------------------

local resp = http.parser("response")
local rbuf = "HTTP/1.1 404 Not Found\r\n\r\n"
assert(resp:parse(rbuf) == #rbuf, "response head should parse")
local rmsg = resp:message(rbuf)
assert(rmsg.status == 404, "status: " .. tostring(rmsg.status))
assert(rmsg.message == "Not Found", "message: " .. tostring(rmsg.message))
assert(rmsg.version == 11, "response version: " .. tostring(rmsg.version))

--------------------------------------------------------------------------------
-- Argument-shape errors raise
--------------------------------------------------------------------------------

local ok, err = pcall(http.parser, "neither")
assert(not ok, "an unknown parser kind should raise")
assert(tostring(err):find("neither", 1, true),
  "the raise should name the bad kind: " .. tostring(err))

local early = http.parser("request")
ok, err = pcall(early.message, early, CHROME)
assert(not ok, "message() before a completed parse should raise")
assert(tostring(err):find("parse has not completed", 1, true),
  "unexpected error: " .. tostring(err))

-- A buffer shorter than the head the slices index would read past its end.
local short = http.parser("request")
assert(short:parse(CHROME) == #CHROME)
ok, err = pcall(short.message, short, CHROME:sub(1, 10))
assert(not ok, "message() with a truncated buffer should raise")
assert(tostring(err):find("shorter than the parsed head", 1, true),
  "unexpected error: " .. tostring(err))

--------------------------------------------------------------------------------
-- One parser reads one head: parse() after completion is refused
--------------------------------------------------------------------------------

-- A head terminated by bare LF-LF leaves the underlying parser in the
-- same state it returned out of, so resuming it on a longer buffer
-- scanned on past the completed head and recorded header slices at
-- offsets beyond the head length message() bounds its reads by. Those
-- offsets index past the end of the buffer message() is handed, handing
-- back arbitrary heap bytes as a header name. Refusing the second
-- parse() is what keeps that length a real bound.
local reparse = http.parser("request")
local lfhead = "GET / HTTP/1.1\nHost: a\n\n"
local lfn = assert(reparse:parse(lfhead))
assert(lfn == #lfhead, "a bare-LF head should parse: " .. tostring(lfn))
ok, err = pcall(reparse.parse, reparse,
  lfhead .. string.rep("Q", 300) .. ": v\n")
assert(not ok, "parse() after a completed head should raise")
assert(tostring(err):find("already completed a message head", 1, true),
  "unexpected error: " .. tostring(err))

-- The parser still describes the head that completed, read in bounds.
local lfmsg = reparse:message(lfhead)
assert(lfmsg.method == "GET" and lfmsg.uri == "/",
  "bare-LF head: " .. tostring(lfmsg.method) .. " " .. tostring(lfmsg.uri))
assert(lfmsg.headers.Host == "a", "Host: " .. tostring(lfmsg.headers.Host))
for k, v in pairs(lfmsg.headers) do
  assert(k == "Host", "stray header name, " .. #k .. " bytes: " .. k)
  assert(v == "a", "stray header value: " .. tostring(v))
end

-- The refusal is about completion, not about the line terminator.
local recrlf = http.parser("request")
assert(recrlf:parse(first) == #first, "CRLF head should parse")
ok, err = pcall(recrlf.parse, recrlf, both)
assert(not ok, "parse() after a completed CRLF head should raise")
assert(tostring(err):find("already completed a message head", 1, true),
  "unexpected error: " .. tostring(err))

-- reset() reopens the parser, which is what keeps a keep-alive or
-- pipelined connection working.
assert(recrlf:reset():parse(both) == #first,
  "reset() should reopen the parser")
assert(recrlf:message(both).uri == "/one", "reset() should reparse the head")

--------------------------------------------------------------------------------
-- A buffer that shrinks between parse() calls is refused
--------------------------------------------------------------------------------

-- The underlying parser clamps its cursor down to the buffer length it
-- is handed, so a shorter buffer rewinds it below header offsets already
-- recorded from a longer one. The head then completes at a length that
-- no longer bounds those offsets, and message() -- whose guard is only
-- that the buffer reaches the head length -- reads far past the end of
-- the string it was given, handing back heap bytes as a header value.
local shrink = http.parser("request")
local long = "GET / HTTP/1.1\r\nXXXXXXXXX: " .. string.rep("v", 30000) .. "\r\n"
assert(shrink:parse(long) == 0, "a headerless-terminator head needs more data")
ok, err = pcall(shrink.parse, shrink, long:sub(1, 8))
assert(not ok, "a shorter buffer should be refused")
assert(tostring(err):find("shorter than a buffer already parsed", 1, true),
  "unexpected error: " .. tostring(err))

-- The refusal held, so nothing message() can return outruns its buffer.
local tiny = "GET / HT\r\n"
assert(shrink:parse(long .. "\r\n") == #long + 2,
  "the head still completes on a growing buffer")
ok, err = pcall(shrink.message, shrink, tiny)
assert(not ok, "message() on the short buffer should raise")
assert(tostring(err):find("shorter than the parsed head", 1, true),
  "unexpected error: " .. tostring(err))
local shrinkmsg = shrink:message(long .. "\r\n")
for k, v in pairs(shrinkmsg.headers) do
  assert(#k <= #long + 2, "header name outruns the buffer: " .. #k .. " bytes")
  assert(#v <= #long + 2, "header value outruns the buffer: " .. #v .. " bytes")
end
assert(shrinkmsg.headers.XXXXXXXXX == string.rep("v", 30000),
  "the long header should survive intact")

-- An identical buffer is not a shrink: a wakeup that produced no new
-- bytes reparses nothing and is not an error.
local same = http.parser("request")
local half = first:sub(1, 12)
assert(same:parse(half) == 0, "a partial head needs more data")
assert(same:parse(half) == 0, "the same buffer again is not an error")
assert(same:parse(first) == #first, "the head completes once the rest lands")
assert(same:message(first).uri == "/one",
  "uri: " .. tostring(same:message(first).uri))

-- reset() clears the high-water mark with everything else, so the next
-- message on the connection may be shorter than the last.
local shorter = http.parser("request")
assert(shorter:parse(CHROME) == #CHROME, "the long head parses")
assert(shorter:reset():parse(first) == #first,
  "reset() should allow a shorter next message")

--------------------------------------------------------------------------------
-- A head past SHRT_MAX is refused, never silently clamped
--------------------------------------------------------------------------------

local huge = http.parser("request")
local hbuf = "GET /" .. string.rep("a", 32768) .. " HTTP/1.1\r\n\r\n"
assert(#hbuf > 32767, "the oversize fixture must exceed SHRT_MAX")
local hr, herr = huge:parse(hbuf)
assert(hr == nil, "an oversize buffer should be refused, got " .. tostring(hr))
assert(herr == "message too large", "error should be 'message too large', " ..
  "got " .. tostring(herr))

--------------------------------------------------------------------------------
-- Unchunker: the net/http unchunk fixtures decode to their bodies
--------------------------------------------------------------------------------

local u = http.unchunker()
assert(tostring(u) == "http.Unchunker(feeding)", "tostring: " .. tostring(u))
assert(u:is_done() == false, "a fresh unchunker is not done")
assert(u:body() == "", "a fresh unchunker has no body")
local smallest = "1\r\nX\r\n0\r\n\r\n"
assert(u:feed(smallest) == #smallest, "smallest chunked body should complete")
assert(u:is_done() == true, "unchunker should be done")
assert(tostring(u) == "http.Unchunker(done)", "tostring: " .. tostring(u))
assert(u:body() == "X", "body: " .. tostring(u:body()))

-- testBasicIdea, split across two feeds, with a pipelined tail left over.
local chunked = "7\r\nMozilla\r\n" ..
  "1e\r\nDevelopersDevelopersDevelopers\r\n" ..
  "7\r\nNetwork\r\n" ..
  "0\r\n\r\n"
local tail = "extra guff"
local u2 = http.unchunker()
assert(u2:feed(chunked:sub(1, 20)) == 0, "a partial body needs more data")
assert(u2:is_done() == false, "still feeding")
local consumed = assert(u2:feed(chunked:sub(21) .. tail))
assert(consumed == #chunked, "consumed should stop at the terminating " ..
  "chunk (" .. #chunked .. "), got " .. tostring(consumed))
assert(u2:is_done() == true, "unchunker should be done")
assert(u2:body() == "MozillaDevelopersDevelopersDevelopersNetwork",
  "body: " .. tostring(u2:body()))
assert(#u2:body() == 0x7 + 0x1e + 0x7, "body length: " .. #u2:body())

-- A single trailing pipelined byte is left unconsumed just the same.
local u3 = http.unchunker()
assert(u3:feed(smallest .. "G") == #smallest,
  "the pipelined byte belongs to the next message")
assert(u3:body() == "X", "body: " .. tostring(u3:body()))

-- A chunk whose declared size does not match its bytes is bad input data.
local u4 = http.unchunker()
local cr, cerr = u4:feed("3\r\nX\r\n0\r\n\r\n")
assert(cr == nil, "a bad chunk should return nil, got " .. tostring(cr))
assert(cerr == "bad chunk", "error should be 'bad chunk', got " ..
  tostring(cerr))

-- Feeding a finished unchunker is a caller bug, not a silent no-op.
ok, err = pcall(u3.feed, u3, "more")
assert(not ok, "feeding a finished unchunker should raise")
assert(tostring(err):find("already reached the terminating chunk", 1, true),
  "unexpected error: " .. tostring(err))

--------------------------------------------------------------------------------
-- find_content_type
--------------------------------------------------------------------------------

assert(http.find_content_type("a.html") == "text/html",
  "a.html: " .. tostring(http.find_content_type("a.html")))
assert(http.find_content_type("a.zzz") == nil,
  "a.zzz should be unknown: " .. tostring(http.find_content_type("a.zzz")))

print("test_http: PASS")
