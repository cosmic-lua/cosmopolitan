/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2024 Justine Alexandra Roberts Tunney                              │
│                                                                              │
│ Permission to use, copy, modify, and/or distribute this software for         │
│ any purpose with or without fee is hereby granted, provided that the         │
│ above copyright notice and this permission notice appear in all copies.      │
│                                                                              │
│ THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL                │
│ WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED                │
│ WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE             │
│ AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL         │
│ DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR        │
│ PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER               │
│ TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR             │
│ PERFORMANCE OF THIS SOFTWARE.                                                │
╚─────────────────────────────────────────────────────────────────────────────*/
#include "dsp/tty/internal.h"
#include "dsp/tty/quant.h"
#include "dsp/tty/tty.h"
#include "libc/mem/gc.h"
#include "libc/mem/mem.h"
#include "libc/str/str.h"
#include "libc/testlib/testlib.h"
#include "net/http/csscolor.h"
#include "net/http/escape.h"

/*
 * Tests that validate terminal ANSI rendering output can be correctly
 * represented in HTML via EscapeHtml and VisualizeControlCodes.
 */

static char vtbuf[256];

////////////////////////////////////////////////////////////////////////////////
// setbg/setfg/setbgfg produce ANSI that HTML-escapes cleanly

TEST(ttyhtml, setbg24_htmlEscape) {
  struct TtyRgb red = {255, 0, 0, 0};
  char *end = setbg24_(vtbuf, red);
  *end = '\0';
  EXPECT_STREQ("\e[48;2;255;0;0m", vtbuf);
  // ANSI escapes contain no HTML-special characters except possibly
  // semicolons, so EscapeHtml should pass them through (minus the ESC)
  char *html = gc(EscapeHtml(vtbuf + 1, end - vtbuf - 1, 0));
  EXPECT_STREQ("[48;2;255;0;0m", html);
}

TEST(ttyhtml, setfg24_htmlEscape) {
  struct TtyRgb green = {0, 128, 0, 0};
  char *end = setfg24_(vtbuf, green);
  *end = '\0';
  EXPECT_STREQ("\e[38;2;0;128;0m", vtbuf);
  char *html = gc(EscapeHtml(vtbuf + 1, end - vtbuf - 1, 0));
  EXPECT_STREQ("[38;2;0;128;0m", html);
}

TEST(ttyhtml, setbgfg24_htmlEscape) {
  struct TtyRgb bg = {0, 0, 255, 0};
  struct TtyRgb fg = {255, 255, 0, 0};
  char *end = setbgfg24_(vtbuf, bg, fg);
  *end = '\0';
  EXPECT_STREQ("\e[48;2;0;0;255;38;2;255;255;0m", vtbuf);
  char *html = gc(EscapeHtml(vtbuf + 1, end - vtbuf - 1, 0));
  EXPECT_STREQ("[48;2;0;0;255;38;2;255;255;0m", html);
}

TEST(ttyhtml, setbg256_htmlEscape) {
  struct TtyRgb c = {0, 0, 0, 196};
  char *end = setbg256_(vtbuf, c);
  *end = '\0';
  EXPECT_STREQ("\e[48;5;196m", vtbuf);
  char *html = gc(EscapeHtml(vtbuf + 1, end - vtbuf - 1, 0));
  EXPECT_STREQ("[48;5;196m", html);
}

TEST(ttyhtml, setfg256_htmlEscape) {
  struct TtyRgb c = {0, 0, 0, 21};
  char *end = setfg256_(vtbuf, c);
  *end = '\0';
  EXPECT_STREQ("\e[38;5;21m", vtbuf);
  char *html = gc(EscapeHtml(vtbuf + 1, end - vtbuf - 1, 0));
  EXPECT_STREQ("[38;5;21m", html);
}

TEST(ttyhtml, setbg16_htmlEscape) {
  struct TtyRgb c = {0, 0, 0, 1};
  char *end = setbg16_(vtbuf, c);
  *end = '\0';
  EXPECT_STREQ("\e[41m", vtbuf);
  char *html = gc(EscapeHtml(vtbuf + 1, end - vtbuf - 1, 0));
  EXPECT_STREQ("[41m", html);
}

TEST(ttyhtml, setfg16_htmlEscape) {
  struct TtyRgb c = {0, 0, 0, 2};
  char *end = setfg16_(vtbuf, c);
  *end = '\0';
  EXPECT_STREQ("\e[32m", vtbuf);
  char *html = gc(EscapeHtml(vtbuf + 1, end - vtbuf - 1, 0));
  EXPECT_STREQ("[32m", html);
}

////////////////////////////////////////////////////////////////////////////////
// ttyraster output HTML-escapes correctly

TEST(ttyhtml, ttyraster_trueColor_htmlEscape) {
  ttyquantsetup(kTtyQuantTrue, kTtyQuantRgb, kTtyBlocksUnicode);
  ttyraster(vtbuf,
            (const struct TtyRgb *)(unsigned[2][2]){
                {DARKRED, GRAY1},
                {DARKRED, DARKRED},
            },
            2, 2,
            (struct TtyRgb){0, 0, 0, 16},
            (struct TtyRgb){0, 0, 0, 16});
  // The ttyraster output contains ESC, [, ;, digits, m, and Unicode
  // block chars, plus a reset \e[0m. None of those (except ESC) are
  // HTML-special, so EscapeHtml leaves them intact.
  size_t n;
  char *html = gc(EscapeHtml(vtbuf, strlen(vtbuf), &n));
  ASSERT_GT(n, 0);
  // Verify no HTML entities are introduced for ANSI parameters
  EXPECT_EQ(NULL, strstr(html, "&amp;"));
  EXPECT_EQ(NULL, strstr(html, "&lt;"));
  EXPECT_EQ(NULL, strstr(html, "&gt;"));
}

TEST(ttyhtml, ttyraster_xterm256_htmlEscape) {
  ttyquantsetup(kTtyQuantXterm256, kTtyQuantRgb, kTtyBlocksUnicode);
  struct TtyRgb kBlack = {0, 0, 0, 16};
  struct TtyRgb kWhite = {255, 255, 255, 231};
  ttyraster(vtbuf,
            (const struct TtyRgb *)(struct TtyRgb[2][2]){
                {kBlack, kWhite},
                {kBlack, kBlack},
            },
            2, 2, kBlack, kBlack);
  size_t n;
  char *html = gc(EscapeHtml(vtbuf, strlen(vtbuf), &n));
  ASSERT_GT(n, 0);
  EXPECT_EQ(NULL, strstr(html, "&amp;"));
  EXPECT_EQ(NULL, strstr(html, "&lt;"));
  EXPECT_EQ(NULL, strstr(html, "&gt;"));
}

////////////////////////////////////////////////////////////////////////////////
// VisualizeControlCodes makes ANSI sequences safe for HTML display

TEST(ttyhtml, visualize_ansiEscape_showsControlPicture) {
  // ESC (0x1B) is a C0 control code; VisualizeControlCodes maps it
  // to the Unicode Control Pictures block (U+241B = ␛)
  char *vis = gc(VisualizeControlCodes("\e[31m", 5, 0));
  // ESC (0x1B) becomes U+241B (␛), rest passes through
  EXPECT_STREQ("␛[31m", vis);
}

TEST(ttyhtml, visualize_resetSequence) {
  char *vis = gc(VisualizeControlCodes("\e[0m", 4, 0));
  EXPECT_STREQ("␛[0m", vis);
}

TEST(ttyhtml, visualize_trueColorSequence) {
  char *vis = gc(VisualizeControlCodes("\e[38;2;255;0;0m", 15, 0));
  EXPECT_STREQ("␛[38;2;255;0;0m", vis);
}

TEST(ttyhtml, visualize_fullRasterOutput) {
  ttyquantsetup(kTtyQuantTrue, kTtyQuantRgb, kTtyBlocksUnicode);
  ttyraster(vtbuf,
            (const struct TtyRgb *)(unsigned[2][2]){
                {DARKRED, DARKRED},
                {DARKRED, DARKRED},
            },
            2, 2,
            (struct TtyRgb){0, 0, 0, 16},
            (struct TtyRgb){0, 0, 0, 16});
  // Visualize makes control codes visible
  char *vis = gc(VisualizeControlCodes(vtbuf, strlen(vtbuf), 0));
  // Should not contain raw ESC bytes
  EXPECT_EQ(NULL, strchr(vis, '\e'));
  // Should contain the visualized ESC (␛)
  EXPECT_NE(NULL, strstr(vis, "␛"));
}

////////////////////////////////////////////////////////////////////////////////
// Combined: VisualizeControlCodes then EscapeHtml produces safe HTML

TEST(ttyhtml, visualizeThenEscape_safeForHtml) {
  struct TtyRgb bg = {139, 0, 0, 0};
  struct TtyRgb fg = {3, 3, 3, 0};
  char *end = setbgfg24_(vtbuf, bg, fg);
  *end = '\0';
  // Step 1: make control codes visible
  char *vis = gc(VisualizeControlCodes(vtbuf, end - vtbuf, 0));
  // Step 2: HTML-escape for safe embedding in <pre> tags
  char *html = gc(EscapeHtml(vis, strlen(vis), 0));
  // Should contain no raw ESC
  EXPECT_EQ(NULL, strchr(html, '\e'));
  // Should be valid for embedding in HTML
  EXPECT_NE(NULL, strstr(html, "␛"));
  // Verify semicolons and digits pass through
  EXPECT_NE(NULL, strstr(html, ";2;139;0;0"));
}

TEST(ttyhtml, visualizeThenEscape_withHtmlChars) {
  // Test with content that contains HTML-sensitive characters
  // embedded alongside ANSI codes
  char buf[128];
  struct TtyRgb red = {255, 0, 0, 0};
  char *p = setfg24_(buf, red);
  memcpy(p, "<b>hi</b>", 9);
  p += 9;
  memcpy(p, "\e[0m", 4);
  p += 4;
  *p = '\0';
  // Visualize: ESC becomes ␛
  char *vis = gc(VisualizeControlCodes(buf, p - buf, 0));
  EXPECT_EQ(NULL, strchr(vis, '\e'));
  // HTML-escape: < > become entities
  char *html = gc(EscapeHtml(vis, strlen(vis), 0));
  EXPECT_NE(NULL, strstr(html, "&lt;b&gt;hi&lt;/b&gt;"));
}

////////////////////////////////////////////////////////////////////////////////
// Edge cases

TEST(ttyhtml, emptyString_htmlEscape) {
  char *html = gc(EscapeHtml("", 0, 0));
  EXPECT_STREQ("", html);
}

TEST(ttyhtml, emptyString_visualize) {
  char *vis = gc(VisualizeControlCodes("", 0, 0));
  EXPECT_STREQ("", vis);
}

TEST(ttyhtml, bareReset_htmlEscape) {
  char *html = gc(EscapeHtml("\e[0m", 4, 0));
  // ESC is not an HTML-special char, passes through raw
  EXPECT_EQ(4, strlen(html));
}

TEST(ttyhtml, multipleResets_visualize) {
  char *vis = gc(VisualizeControlCodes("\e[0m\e[0m\e[0m", 12, 0));
  EXPECT_STREQ("␛[0m␛[0m␛[0m", vis);
}

TEST(ttyhtml, highBrightAnsi16_htmlEscape) {
  // High-intensity ANSI colors (xt >= 8) use base+60 codes
  struct TtyRgb bright_red = {0, 0, 0, 9};  // bright red = 8+1
  char *end = setfg16_(vtbuf, bright_red);
  *end = '\0';
  EXPECT_STREQ("\e[91m", vtbuf);
  char *html = gc(EscapeHtml(vtbuf + 1, end - vtbuf - 1, 0));
  EXPECT_STREQ("[91m", html);
}

TEST(ttyhtml, highBrightBg16_htmlEscape) {
  struct TtyRgb bright_blue = {0, 0, 0, 12};  // bright blue = 8+4
  char *end = setbg16_(vtbuf, bright_blue);
  *end = '\0';
  EXPECT_STREQ("\e[104m", vtbuf);
  char *html = gc(EscapeHtml(vtbuf + 1, end - vtbuf - 1, 0));
  EXPECT_STREQ("[104m", html);
}

TEST(ttyhtml, ttyraster_cp437_htmlEscape) {
  ttyquantsetup(kTtyQuantTrue, kTtyQuantRgb, kTtyBlocksCp437);
  ttyraster(vtbuf,
            (const struct TtyRgb *)(unsigned[2][2]){
                {DARKRED, GRAY1},
                {DARKRED, GRAY1},
            },
            2, 2,
            (struct TtyRgb){0, 0, 0, 16},
            (struct TtyRgb){0, 0, 0, 16});
  size_t n;
  char *html = gc(EscapeHtml(vtbuf, strlen(vtbuf), &n));
  ASSERT_GT(n, 0);
  EXPECT_EQ(NULL, strstr(html, "&amp;"));
  EXPECT_EQ(NULL, strstr(html, "&lt;"));
  EXPECT_EQ(NULL, strstr(html, "&gt;"));
}
