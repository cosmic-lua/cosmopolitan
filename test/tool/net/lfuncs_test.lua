-- Copyright 2022 Justine Alexandra Roberts Tunney
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

assert(unix.pledge("stdio"))

assert(EncodeHex("\1\2\3\4\255") == "01020304ff")
assert(DecodeHex("01020304ff") == "\1\2\3\4\255")

assert(EncodeBase32("123456") == "64s36d1n6r")
assert(EncodeBase32("12") == "64s0")
assert(EncodeBase32("\33", "01") == "00100001")
assert(EncodeBase32("\33", "0123456789abcdef") == "21")

assert(DecodeBase32("64s36d1n6r") == "123456")
assert(DecodeBase32("64s0") == "12")
assert(DecodeBase32("64 \t\r\ns0") == "12")
assert(DecodeBase32("64s0!64s0") == "12")

assert(EncodeBase32("\1\2\3\4\255", "0123456789abcdef") == "01020304ff")
assert(DecodeBase32("01020304ff", "0123456789abcdef") == "\1\2\3\4\255")

assert(EscapeHtml(nil) == nil)
assert(EscapeHtml("?hello&there<>") == "?hello&amp;there&lt;&gt;")

assert(EscapeParam(nil) == nil)
assert(EscapeParam("?hello&there<>") == "%3Fhello%26there%3C%3E")

assert(UnescapeParam(nil) == nil)
assert(UnescapeParam("%3Fhello%26there%3C%3E") == "?hello&there<>")
assert(UnescapeParam("hello+world") == "hello world")
assert(UnescapeParam("hello%20world") == "hello world")
assert(UnescapeParam(EscapeParam("hello world!")) == "hello world!")

assert(IsValidPercentEncoding(""))
assert(IsValidPercentEncoding("hello world"))
assert(IsValidPercentEncoding("100%25 done"))
assert(IsValidPercentEncoding("%3Fhello%26there%3C%3E"))
assert(IsValidPercentEncoding("%aF%09%ff"))
assert(IsValidPercentEncoding("%252"))
assert(not IsValidPercentEncoding("%"))
assert(not IsValidPercentEncoding("abc%"))
assert(not IsValidPercentEncoding("abc%2"))
assert(not IsValidPercentEncoding("abc%2g"))
assert(not IsValidPercentEncoding("abc%gg"))
assert(not IsValidPercentEncoding("%%25"))
assert(not IsValidPercentEncoding("%2%30"))
assert(not IsValidPercentEncoding("trailing %A"))

assert(DecodeLatin1(nil) == nil)
assert(DecodeLatin1("hello\xff\xc0") == "helloÿÀ")
assert(EncodeLatin1("helloÿÀ") == "hello\xff\xc0")

url = ParseUrl("https://jart:pass@redbean.dev/2.0.html?x&y=z#frag")
assert(url.scheme == "https")
assert(url.user == "jart")
assert(url.pass == "pass")
assert(url.host == "redbean.dev")
assert(not url.port)
assert(url.path == "/2.0.html")
assert(EncodeLua(url.params) == '{{"x"}, {"y", "z"}}')
assert(url.fragment == "frag")

assert(ParseIp("x") == -1)
assert(ParseIp("127.0.0.1") == 0x7f000001)

assert(GetMonospaceWidth('c') == 1)
assert(GetMonospaceWidth(string.byte('c')) == 1)
assert(GetMonospaceWidth(0) == 0)
assert(GetMonospaceWidth(1) == -1)
assert(GetMonospaceWidth(32) == 1)
assert(GetMonospaceWidth(0x3061) == 2)
assert(GetMonospaceWidth("ちち") == 4)

assert(IsPublicIp(0x08080808))
assert(not IsPublicIp(0x0a000000))
assert(not IsPublicIp(0x7f000001))

assert(not IsPrivateIp(0x08080808))
assert(IsPrivateIp(0x0a000000))
assert(not IsPrivateIp(0x7f000001))

assert(not IsLoopbackIp(0x08080808))
assert(not IsLoopbackIp(0x0a000000))
assert(IsLoopbackIp(0x7f000001))

assert(FormatHttpDateTime(1657297063) == "Fri, 08 Jul 2022 16:17:43 GMT")

assert(Crc32(0, "123456789") == 0xcbf43926)
assert(Crc32c(0, "123456789") == 0xe3069283)

assert(assert(Deflate("hello")) == "\xcbH\xcd\xc9\xc9\x07\x00")
assert(assert(Inflate("\xcbH\xcd\xc9\xc9\x07\x00")) == "hello")
assert(assert(Inflate(assert(Deflate("hello", {format = "gzip"})),
                      {format = "gzip"})) == "hello")
assert(not Inflate("garbage that is not a deflate stream"))
-- the deprecated Compress/Uncompress api is gone
assert(Compress == nil)
assert(Uncompress == nil)
