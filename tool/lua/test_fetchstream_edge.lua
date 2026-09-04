-- Copyright 2024 Will Maier
--
-- Permission to use, copy, modify, and/or distribute this software for
-- any purpose with or without fee is hereby granted, provided that the
-- above copyright notice and this permission notice appear in all copies.
--
-- THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
-- WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
-- WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
-- AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
-- DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR
-- PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
-- TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
-- PERFORMANCE OF THIS SOFTWARE.

-- Test cases for FetchStream (streaming fetch)
-- Uses local test servers to verify streaming behavior

-- Use FetchStream from redbean globals or cosmo module
local cosmo = require("cosmo")
local FetchStream = FetchStream or cosmo.FetchStream
local ParseIp = ParseIp or cosmo.ParseIp
local unix = unix or require("unix")

-- Helper: Create a simple TCP server
local function create_test_server()
    local sock = assert(unix.socket(unix.AF_INET, unix.SOCK_STREAM, 0))
    assert(unix.setsockopt(sock, unix.SOL_SOCKET, unix.SO_REUSEADDR, 1))
    assert(unix.bind(sock, ParseIp("127.0.0.1"), 0))
    assert(unix.listen(sock, 5))
    local ip, port = unix.getsockname(sock)
    return sock, port
end

-- Helper: Accept one connection, read request headers, then send custom response
local function accept_and_respond(server_sock, response_fn, timeout_ms)
    timeout_ms = timeout_ms or 5000
    unix.setsockopt(server_sock, unix.SOL_SOCKET, unix.SO_RCVTIMEO,
                    timeout_ms // 1000, (timeout_ms % 1000) * 1000)
    local client, err = unix.accept(server_sock)
    if not client then
        return nil, "accept failed: " .. tostring(err)
    end
    local request = ""
    while true do
        local data = unix.read(client, 4096)
        if not data or #data == 0 then break end
        request = request .. data
        if request:find("\r\n\r\n") then break end
    end
    response_fn(client)
    unix.close(client)
    return request
end

-- Test: Basic streaming fetch with Content-Length body
function test_stream_content_length()
    local server, port = create_test_server()
    local body_data = "Hello, streaming world!"
    local response = "HTTP/1.1 200 OK\r\n" ..
                     "Content-Length: " .. #body_data .. "\r\n" ..
                     "Content-Type: text/plain\r\n" ..
                     "Connection: close\r\n" ..
                     "\r\n" ..
                     body_data

    local pid = unix.fork()
    if pid == 0 then
        accept_and_respond(server, function(client)
            unix.write(client, response)
        end)
        unix.close(server)
        os.exit(0)
    end

    unix.close(server)
    local status, headers, reader = FetchStream("http://127.0.0.1:" .. port .. "/test", {
        proxy = "http://127.0.0.1:" .. port
    })

    assert(status == 200, "expected 200, got: " .. tostring(status))
    assert(reader, "expected reader object")
    assert(tostring(reader):find("FetchReader"), "expected FetchReader tostring")

    -- Read all chunks
    local chunks = {}
    while true do
        local chunk, err = reader:read()
        if not chunk then
            if err then error("read error: " .. err) end
            break
        end
        table.insert(chunks, chunk)
    end
    reader:close()

    local full_body = table.concat(chunks)
    assert(full_body == body_data,
           "expected '" .. body_data .. "', got: '" .. full_body .. "'")

    unix.wait(pid)
    print("test_stream_content_length: PASS")
end

-- Test: Streaming fetch with chunked transfer encoding
function test_stream_chunked()
    local server, port = create_test_server()
    local chunk1 = "Hello, "
    local chunk2 = "chunked "
    local chunk3 = "world!"

    local pid = unix.fork()
    if pid == 0 then
        accept_and_respond(server, function(client)
            -- Send headers
            unix.write(client, "HTTP/1.1 200 OK\r\n" ..
                              "Transfer-Encoding: chunked\r\n" ..
                              "Content-Type: text/plain\r\n" ..
                              "Connection: close\r\n" ..
                              "\r\n")
            -- Send chunks with small delays
            unix.write(client, string.format("%x\r\n%s\r\n", #chunk1, chunk1))
            unix.nanosleep(0, 50000000) -- 50ms
            unix.write(client, string.format("%x\r\n%s\r\n", #chunk2, chunk2))
            unix.nanosleep(0, 50000000)
            unix.write(client, string.format("%x\r\n%s\r\n", #chunk3, chunk3))
            -- Final chunk
            unix.write(client, "0\r\n\r\n")
        end)
        unix.close(server)
        os.exit(0)
    end

    unix.close(server)
    local status, headers, reader = FetchStream("http://127.0.0.1:" .. port .. "/chunked", {
        proxy = "http://127.0.0.1:" .. port
    })

    assert(status == 200, "expected 200, got: " .. tostring(status))

    -- Read all chunks
    local chunks = {}
    while true do
        local chunk, err = reader:read()
        if not chunk then
            if err then error("read error: " .. err) end
            break
        end
        if #chunk > 0 then
            table.insert(chunks, chunk)
        end
    end
    reader:close()

    local full_body = table.concat(chunks)
    assert(full_body == "Hello, chunked world!",
           "expected 'Hello, chunked world!', got: '" .. full_body .. "'")

    unix.wait(pid)
    print("test_stream_chunked: PASS")
end

-- Test: Streaming fetch with no Content-Length (read until close)
function test_stream_until_close()
    local server, port = create_test_server()
    local body_data = "streaming until connection close"

    local pid = unix.fork()
    if pid == 0 then
        accept_and_respond(server, function(client)
            unix.write(client, "HTTP/1.1 200 OK\r\n" ..
                              "Content-Type: text/plain\r\n" ..
                              "Connection: close\r\n" ..
                              "\r\n" ..
                              body_data)
            -- Connection close triggers EOF
        end)
        unix.close(server)
        os.exit(0)
    end

    unix.close(server)
    local status, headers, reader = FetchStream("http://127.0.0.1:" .. port .. "/close", {
        proxy = "http://127.0.0.1:" .. port
    })

    assert(status == 200, "expected 200, got: " .. tostring(status))

    local chunks = {}
    while true do
        local chunk, err = reader:read()
        if not chunk then
            if err then error("read error: " .. err) end
            break
        end
        if #chunk > 0 then
            table.insert(chunks, chunk)
        end
    end
    reader:close()

    local full_body = table.concat(chunks)
    assert(full_body == body_data,
           "expected '" .. body_data .. "', got: '" .. full_body .. "'")

    unix.wait(pid)
    print("test_stream_until_close: PASS")
end

-- Test: Reader close is idempotent
function test_reader_close_idempotent()
    local server, port = create_test_server()

    local pid = unix.fork()
    if pid == 0 then
        accept_and_respond(server, function(client)
            unix.write(client, "HTTP/1.1 200 OK\r\n" ..
                              "Content-Length: 2\r\n" ..
                              "Connection: close\r\n" ..
                              "\r\n" ..
                              "OK")
        end)
        unix.close(server)
        os.exit(0)
    end

    unix.close(server)
    local status, headers, reader = FetchStream("http://127.0.0.1:" .. port .. "/test", {
        proxy = "http://127.0.0.1:" .. port
    })

    assert(status == 200)

    -- Read the body
    reader:read()
    -- Close multiple times - should not error
    reader:close()
    reader:close()
    reader:close()

    -- Read after close should return error
    local chunk, err = reader:read()
    assert(chunk == nil, "expected nil after close")
    assert(err, "expected error message after close")

    unix.wait(pid)
    print("test_reader_close_idempotent: PASS")
end

-- Test: FetchStream returns nil on error (same as Fetch)
function test_stream_error_handling()
    local status, err = FetchStream("invalid://bad-scheme")
    assert(status == nil, "expected nil for bad scheme")
    assert(type(err) == "string", "expected error string")
    print("test_stream_error_handling: PASS")
end

-- Test: 204 No Content returns closed reader
function test_stream_no_content()
    local server, port = create_test_server()

    local pid = unix.fork()
    if pid == 0 then
        accept_and_respond(server, function(client)
            unix.write(client, "HTTP/1.1 204 No Content\r\n" ..
                              "Connection: close\r\n" ..
                              "\r\n")
        end)
        unix.close(server)
        os.exit(0)
    end

    unix.close(server)
    local status, headers, reader = FetchStream("http://127.0.0.1:" .. port .. "/no-content", {
        proxy = "http://127.0.0.1:" .. port
    })

    assert(status == 204, "expected 204, got: " .. tostring(status))
    assert(reader, "expected reader object")

    -- Reader should be immediately closed (no body)
    local chunk, err = reader:read()
    assert(chunk == nil, "expected nil from closed reader")
    reader:close()

    unix.wait(pid)
    print("test_stream_no_content: PASS")
end

-- Test: SSE-like streaming (chunked with data: lines)
function test_stream_sse_pattern()
    local server, port = create_test_server()
    local events = {
        "data: {\"type\": \"start\"}\n\n",
        "data: {\"type\": \"delta\", \"text\": \"Hello\"}\n\n",
        "data: {\"type\": \"delta\", \"text\": \" World\"}\n\n",
        "data: {\"type\": \"stop\"}\n\n",
    }

    local pid = unix.fork()
    if pid == 0 then
        accept_and_respond(server, function(client)
            unix.write(client, "HTTP/1.1 200 OK\r\n" ..
                              "Transfer-Encoding: chunked\r\n" ..
                              "Content-Type: text/event-stream\r\n" ..
                              "Connection: close\r\n" ..
                              "\r\n")
            for _, event in ipairs(events) do
                unix.write(client, string.format("%x\r\n%s\r\n", #event, event))
                unix.nanosleep(0, 20000000) -- 20ms between events
            end
            unix.write(client, "0\r\n\r\n")
        end)
        unix.close(server)
        os.exit(0)
    end

    unix.close(server)
    local status, headers, reader = FetchStream("http://127.0.0.1:" .. port .. "/sse", {
        proxy = "http://127.0.0.1:" .. port
    })

    assert(status == 200, "expected 200, got: " .. tostring(status))
    assert(headers["Content-Type"] == "text/event-stream",
           "expected text/event-stream content type")

    -- Read and parse SSE events
    local buffer = ""
    local parsed_events = {}
    while true do
        local chunk, err = reader:read()
        if not chunk then
            if err then error("read error: " .. err) end
            break
        end
        buffer = buffer .. chunk
        -- Parse complete events (separated by \n\n)
        while true do
            local event_end = buffer:find("\n\n")
            if not event_end then break end
            local event = buffer:sub(1, event_end + 1)
            buffer = buffer:sub(event_end + 2)
            if event:match("^data: ") then
                table.insert(parsed_events, event:match("^data: (.-)%s*$"))
            end
        end
    end
    reader:close()

    assert(#parsed_events == 4,
           "expected 4 SSE events, got: " .. #parsed_events)
    assert(parsed_events[1]:find('"start"'),
           "expected start event")
    assert(parsed_events[4]:find('"stop"'),
           "expected stop event")

    unix.wait(pid)
    print("test_stream_sse_pattern: PASS")
end

-- Test: Invalid chunk size (non-hex characters)
function test_stream_chunked_invalid_size()
    local server, port = create_test_server()

    local pid = unix.fork()
    if pid == 0 then
        accept_and_respond(server, function(client)
            unix.write(client, "HTTP/1.1 200 OK\r\n" ..
                              "Transfer-Encoding: chunked\r\n" ..
                              "Connection: close\r\n" ..
                              "\r\n" ..
                              "XYZ\r\n")  -- invalid: non-hex chunk size
        end)
        unix.close(server)
        os.exit(0)
    end

    unix.close(server)
    local status, headers, reader = FetchStream("http://127.0.0.1:" .. port .. "/bad-chunk", {
        proxy = "http://127.0.0.1:" .. port
    })

    assert(status == 200, "expected 200")

    -- Reading should eventually fail due to invalid chunk encoding
    local chunk, err = reader:read()
    -- Either returns nil with error, or empty string, or the invalid data
    -- The key is that we don't crash
    reader:close()

    unix.wait(pid)
    print("test_stream_chunked_invalid_size: PASS")
end

-- Test: Missing CRLF after chunk data
function test_stream_chunked_missing_crlf()
    local server, port = create_test_server()

    local pid = unix.fork()
    if pid == 0 then
        accept_and_respond(server, function(client)
            unix.write(client, "HTTP/1.1 200 OK\r\n" ..
                              "Transfer-Encoding: chunked\r\n" ..
                              "Connection: close\r\n" ..
                              "\r\n" ..
                              "5\r\nHello")  -- missing trailing \r\n
            -- Connection closes immediately
        end)
        unix.close(server)
        os.exit(0)
    end

    unix.close(server)
    local status, headers, reader = FetchStream("http://127.0.0.1:" .. port .. "/missing-crlf", {
        proxy = "http://127.0.0.1:" .. port
    })

    assert(status == 200, "expected 200")

    -- Try to read - may get partial data or error
    local chunks = {}
    while true do
        local chunk, err = reader:read()
        if not chunk then break end
        if #chunk > 0 then table.insert(chunks, chunk) end
    end
    reader:close()

    -- We should have gotten some data or an error, but not crashed
    unix.wait(pid)
    print("test_stream_chunked_missing_crlf: PASS")
end

-- Test: Incomplete terminator (0\r\n without final \r\n)
function test_stream_chunked_incomplete_terminator()
    local server, port = create_test_server()

    local pid = unix.fork()
    if pid == 0 then
        accept_and_respond(server, function(client)
            unix.write(client, "HTTP/1.1 200 OK\r\n" ..
                              "Transfer-Encoding: chunked\r\n" ..
                              "Connection: close\r\n" ..
                              "\r\n" ..
                              "5\r\nHello\r\n" ..
                              "0\r\n")  -- missing final \r\n
            -- Connection closes before final CRLF
        end)
        unix.close(server)
        os.exit(0)
    end

    unix.close(server)
    local status, headers, reader = FetchStream("http://127.0.0.1:" .. port .. "/incomplete", {
        proxy = "http://127.0.0.1:" .. port
    })

    assert(status == 200, "expected 200")

    -- Read until EOF or error
    local chunks = {}
    while true do
        local chunk, err = reader:read()
        if not chunk then break end
        if #chunk > 0 then table.insert(chunks, chunk) end
    end
    reader:close()

    -- Should have received "Hello" even if the terminator was incomplete
    local body = table.concat(chunks)
    assert(body == "Hello" or body == "",
           "expected 'Hello' or empty, got: '" .. body .. "'")

    unix.wait(pid)
    print("test_stream_chunked_incomplete_terminator: PASS")
end

-- Test: Overflow chunk size (exceeds size_t)
function test_stream_chunked_overflow_size()
    local server, port = create_test_server()

    local pid = unix.fork()
    if pid == 0 then
        accept_and_respond(server, function(client)
            unix.write(client, "HTTP/1.1 200 OK\r\n" ..
                              "Transfer-Encoding: chunked\r\n" ..
                              "Connection: close\r\n" ..
                              "\r\n" ..
                              "10000000000000001\r\n")  -- overflow size
        end)
        unix.close(server)
        os.exit(0)
    end

    unix.close(server)
    local status, headers, reader = FetchStream("http://127.0.0.1:" .. port .. "/overflow", {
        proxy = "http://127.0.0.1:" .. port
    })

    assert(status == 200, "expected 200")

    -- Reading should fail with error (not hang or crash)
    local chunk, err = reader:read()
    -- Should get nil with error, or empty result
    reader:close()

    unix.wait(pid)
    print("test_stream_chunked_overflow_size: PASS")
end

-- Test: HTTPS streaming (uses external service)
function test_stream_https()
    -- Test with a real HTTPS endpoint that supports streaming
    local status, headers, reader = FetchStream("https://httpbin.org/stream/3")
    if not status then
        -- Network may not be available, skip test
        print("test_stream_https: SKIP (no network: " .. tostring(headers) .. ")")
        return
    end
    assert(status == 200, "expected 200, got: " .. tostring(status))
    assert(reader, "expected reader object")

    -- Read all chunks
    local chunks = {}
    while true do
        local chunk, err = reader:read()
        if not chunk then
            if err then error("read error: " .. err) end
            break
        end
        if #chunk > 0 then table.insert(chunks, chunk) end
    end
    reader:close()

    local body = table.concat(chunks)
    assert(#body > 0, "expected response body")
    -- httpbin.org/stream/3 returns 3 JSON objects
    local count = 0
    for _ in body:gmatch('"id":') do count = count + 1 end
    assert(count == 3, "expected 3 JSON objects, got: " .. count)

    print("test_stream_https: PASS")
end

local function main()
    local tests = {
        test_stream_content_length,
        test_stream_chunked,
        test_stream_until_close,
        test_reader_close_idempotent,
        test_stream_error_handling,
        test_stream_no_content,
        test_stream_sse_pattern,
        test_stream_chunked_invalid_size,
        test_stream_chunked_missing_crlf,
        test_stream_chunked_incomplete_terminator,
        test_stream_chunked_overflow_size,
        test_stream_https,
    }

    local passed = 0
    local failed = 0

    for _, test in ipairs(tests) do
        local ok, err = pcall(test)
        if ok then
            passed = passed + 1
        else
            failed = failed + 1
            print("FAILED: " .. tostring(err))
        end
    end

    print(string.format("\nResults: %d passed, %d failed", passed, failed))
    if failed > 0 then
        error("Some tests failed")
    end
end

main()
