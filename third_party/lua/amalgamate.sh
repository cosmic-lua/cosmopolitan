#!/bin/sh
# Lua 5.4 Amalgamation Generator for Cosmopolitan Lua
#
# Generates lua-amalg.c and lua-amalg.h from the Cosmopolitan Lua source
# tree, producing portable C files suitable for vendoring into any project.
#
# Usage: ./amalgamate.sh [output_dir]
#
# The output files are:
#   lua-amalg.h  - Public API header (luaconf.h + lua.h + lauxlib.h + lualib.h)
#   lua-amalg.c  - All Lua core source files in a single translation unit
#
# To use in your project:
#   cc -O2 -c lua-amalg.c
#   cc -o myapp myapp.c lua-amalg.o -lm

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${1:-.}"

AMALG_H="$OUTPUT_DIR/lua-amalg.h"
AMALG_C="$OUTPUT_DIR/lua-amalg.c"

# Core Lua library source files (standard Lua 5.4.6 + cosmopolitan enhancements)
# Excludes: cosmo-only extensions (lunix, lrepl, serialize, visitor, etc.),
#           lnotice (cosmo __notice macro), llock (cosmo REPL threading),
#           ltests (internal test harness), and executable entry points.
CORE_SRCS="
  lapi.c
  lauxlib.c
  lbaselib.c
  lcode.c
  lcorolib.c
  ldblib.c
  ldebug.c
  ldo.c
  ldump.c
  lfunc.c
  lgc.c
  linit.c
  liolib.c
  llex.c
  lmathlib.c
  lmem.c
  loadlib.c
  lobject.c
  lopcodes.c
  loslib.c
  lparser.c
  lstate.c
  lstring.c
  lstrlib.c
  ltable.c
  ltablib.c
  ltm.c
  lundump.c
  lutf8lib.c
  lvm.c
  lzio.c
"

# Internal headers needed by the .c files (topologically sorted by dependencies)
INTERNAL_HDRS="
  tms.h
  llimits.h
  lctype.h
  lobject.h
  lopcodes.h
  lmem.h
  lzio.h
  lstate.h
  lgc.h
  llex.h
  lparser.h
  lcode.h
  ldebug.h
  ldo.h
  lfunc.h
  lstring.h
  ltable.h
  ltm.h
  lundump.h
  lvm.h
  lapi.h
"

# Strip cosmopolitan copyright banners (box-drawing comment blocks)
# These span from "/*-*-" to the next "*/" line
strip_banner() {
  awk '
    /^\/\*-\*-/ { in_banner = 1; next }
    in_banner && /\*\/$/ { in_banner = 0; next }
    !in_banner { print }
  '
}

# Map cosmopolitan includes to standard C includes
decosmopolitan_includes() {
  sed \
    -e 's|#include "libc/assert\.h"|#include <assert.h>|' \
    -e 's|#include "libc/ctype\.h"|#include <ctype.h>|' \
    -e 's|#include "libc/dce\.h"||' \
    -e 's|#include "libc/dlopen/dlfcn\.h"|#include <dlfcn.h>|' \
    -e 's|#include "libc/errno\.h"|#include <errno.h>|' \
    -e 's|#include "libc/fmt/conv\.h"|#include <stdlib.h>|' \
    -e 's|#include "libc/intrin/weaken\.h"||' \
    -e 's|#include "libc/limits\.h"|#include <limits.h>|' \
    -e 's|#include "libc/log/log\.h"||' \
    -e 's|#include "libc/math\.h"|#include <math.h>|' \
    -e 's|#include "libc/mem/gc\.h"||' \
    -e 's|#include "libc/mem/mem\.h"|#include <stdlib.h>|' \
    -e 's|#include "libc/mem/alg\.h"|#include <stdlib.h>|' \
    -e 's|#include "libc/macros\.h"||' \
    -e 's|#include "libc/nt/struct/msg\.h"||' \
    -e 's|#include "libc/runtime/internal\.h"||' \
    -e 's|#include "libc/runtime/runtime\.h"|#include <stdlib.h>|' \
    -e 's|#include "libc/runtime/stack\.h"||' \
    -e 's|#include "libc/stdio/stdio\.h"|#include <stdio.h>|' \
    -e 's|#include "libc/stdio/append\.h"||' \
    -e 's|#include "libc/str/str\.h"|#include <string.h>|' \
    -e 's|#include "libc/str/locale\.h"|#include <locale.h>|' \
    -e 's|#include "libc/str/unicode\.h"||' \
    -e 's|#include "libc/sysv/consts/exit\.h"|#include <stdlib.h>|' \
    -e 's|#include "libc/temp\.h"|#include <stdio.h>|' \
    -e 's|#include "libc/thread/thread\.h"|#include <pthread.h>|' \
    -e 's|#include "libc/time\.h"|#include <time.h>|' \
    -e 's|#include "libc/calls/calls\.h"|#include <unistd.h>|' \
    -e 's|#include "libc/calls/weirdtypes\.h"||' \
    -e 's|#include "libc/calls/struct/sigaction\.h"|#include <signal.h>|' \
    -e 's|#include "libc/x/x\.h"||' \
    -e '/^#include "libc\//d' \
    -e '/^#include "net\//d'
}

# Strip cosmopolitan-specific constructs
decosmopolitan_macros() {
  sed \
    -e '/^__static_yoink/d' \
    -e '/^__notice/d' \
    -e 's/COSMOPOLITAN_C_START_/#ifdef __cplusplus\nextern "C" {\n#endif/' \
    -e 's/COSMOPOLITAN_C_END_/#ifdef __cplusplus\n}\n#endif/' \
    -e '/if (_weaken(__die))/d' \
    -e 's/_Exit([0-9]*)/abort()/g' \
    -e 's/WARNF(.*)/((void)0)/g' \
    -e 's/strlcpy(b, __get_tmpdir(), LUA_TMPNAMBUFSIZE)/strcpy(b, "\/tmp\/")/' \
    -e 's/e = strlcat(b, "lua_XXXXXX", LUA_TMPNAMBUFSIZE) >= LUA_TMPNAMBUFSIZE/e = 0/' | \
  awk '
    # Replace _bsr(x) with portable bit scan reverse
    /return --x \? _bsr\(x\) \+ 1 : 0;/ {
      print "  static const unsigned char log2table[256] = {"
      print "    0,1,2,2,3,3,3,3,4,4,4,4,4,4,4,4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,"
      print "    6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,6,"
      print "    7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,"
      print "    7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,"
      print "    8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,"
      print "    8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,"
      print "    8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,"
      print "    8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8"
      print "  };"
      print "  int l = 0;"
      print "  x--;"
      print "  while (x >= 256) { l += 8; x >>= 8; }"
      print "  return l + log2table[x];"
      next
    }
    { print }
  '
}

# Process a header file: strip cosmo includes, fix include guards, fix macros
process_header() {
  local file="$1"
  local name
  name="$(basename "$file")"

  # Replace cosmo-style include guards with standard ones
  sed \
    -e "s|#ifndef COSMOPOLITAN_THIRD_PARTY_LUA_[A-Z_]*_|#ifndef ${name%%.*}_h|i" \
    -e "s|#define COSMOPOLITAN_THIRD_PARTY_LUA_[A-Z_]*_|#define ${name%%.*}_h|i" \
    -e "s|#endif /\* COSMOPOLITAN_THIRD_PARTY_LUA_[A-Z_]*_ \*/|#endif|i" \
    -e 's|#include "third_party/lua/\([^"]*\)"|#include "\1"|g' \
    "$file" | decosmopolitan_includes | decosmopolitan_macros
}

# Process a source file: strip cosmo includes, redirect lua includes, strip banners
process_source() {
  local file="$1"
  cat "$file" | strip_banner | \
    sed -e 's|#include "third_party/lua/\([^"]*\)"|#include "\1"|g' | \
    decosmopolitan_includes | decosmopolitan_macros
}

# Remove duplicate standard includes (keep first occurrence)
dedup_includes() {
  awk '
    /^#include <[^>]+>/ {
      if (seen[$0]) next
      seen[$0] = 1
    }
    { print }
  '
}

mkdir -p "$OUTPUT_DIR"

########################################
# Generate lua-amalg.h (public API)
########################################
{
  cat <<'HEADER_PREAMBLE'
/*
** Lua 5.4 - Amalgamated Public API Header
** Generated from Cosmopolitan Lua (https://github.com/jart/cosmopolitan)
** Based on Lua 5.4.6 - Copyright (C) 1994-2023 Lua.org, PUC-Rio
** Licensed under the MIT license. See Lua's LICENSE file for details.
**
** This is an auto-generated amalgamated header. Do not edit directly.
** To use: #include "lua-amalg.h" in your C/C++ source files.
*/
#ifndef LUA_AMALG_H
#define LUA_AMALG_H

HEADER_PREAMBLE

  # Baseline standard includes needed by the public API
  cat <<'BASELINE'
#include <stddef.h>
#include <stdarg.h>
#include <limits.h>
#include <stdio.h>
#include <assert.h>

BASELINE

  # Emit lprefix.h content first (system configuration)
  echo "/* === lprefix.h === */"
  process_header "$SCRIPT_DIR/lprefix.h"
  echo ""

  # Emit luaconf.h with IsModeDbg() replaced
  echo "/* === luaconf.h === */"
  process_header "$SCRIPT_DIR/luaconf.h" | \
    sed -e 's/IsModeDbg()/0/' \
        -e 's/unassert(\(.*\))/(void)(0)/'
  echo ""

  # Emit lua.h
  echo "/* === lua.h === */"
  process_header "$SCRIPT_DIR/lua.h" | \
    sed -e '/#include "luaconf\.h"/d' \
        -e '/^#ifdef MODE_DBG/,/^#endif/d'
  echo ""

  # Emit lauxlib.h
  echo "/* === lauxlib.h === */"
  process_header "$SCRIPT_DIR/lauxlib.h" | \
    sed -e '/#include "lua\.h"/d' \
        -e '/#include "luaconf\.h"/d' \
        -e 's/unassert(\(.*\))/(void)(0)/'
  echo ""

  # Emit lualib.h
  echo "/* === lualib.h === */"
  process_header "$SCRIPT_DIR/lualib.h" | \
    sed -e '/#include "lua\.h"/d'
  echo ""

  echo "#endif /* LUA_AMALG_H */"
} | dedup_includes > "$AMALG_H"

########################################
# Generate lua-amalg.c (all sources)
########################################
{
  cat <<'SOURCE_PREAMBLE'
/*
** Lua 5.4 - Amalgamated Source
** Generated from Cosmopolitan Lua (https://github.com/jart/cosmopolitan)
** Based on Lua 5.4.6 - Copyright (C) 1994-2023 Lua.org, PUC-Rio
** Licensed under the MIT license. See Lua's LICENSE file for details.
**
** This is an auto-generated amalgamated source file. Do not edit directly.
** Compile with: cc -O2 -c lua-amalg.c
*/

#define LUA_CORE
#define LUA_LIB
#define lapi_c
#define lauxlib_c
#define lbaselib_c
#define lcode_c
#define lcorolib_c
#define ldblib_c
#define ldebug_c
#define ldo_c
#define ldump_c
#define lfunc_c
#define lgc_c
#define linit_c
#define liolib_c
#define llex_c
#define lmathlib_c
#define lmem_c
#define loadlib_c
#define lobject_c
#define lopcodes_c
#define loslib_c
#define lparser_c
#define lstate_c
#define lstring_c
#define lstrlib_c
#define ltable_c
#define ltablib_c
#define ltm_c
#define lundump_c
#define lutf8lib_c
#define lvm_c
#define lzio_c

SOURCE_PREAMBLE

  echo '#include "lua-amalg.h"'
  echo ""

  # Standard C headers used across all files
  cat <<'STD_INCLUDES'
#include <assert.h>
#include <ctype.h>
#include <errno.h>
#include <float.h>
#include <limits.h>
#include <locale.h>
#include <math.h>
#include <setjmp.h>
#include <signal.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#if defined(LUA_USE_POSIX)
#include <sys/wait.h>
#include <unistd.h>
#include <dlfcn.h>
#endif

STD_INCLUDES

  # Emit all internal headers (strip all #include since everything is inlined)
  for hdr in $INTERNAL_HDRS; do
    echo "/* === $hdr === */"
    process_header "$SCRIPT_DIR/$hdr" | \
      sed -e '/^#include /d'
    echo ""
  done

  # Emit all source files
  # Note: .inc files (ljumptab.inc, lopnames.inc) are #include'd inside
  # function bodies in lvm.c, so we inline their content in-place.
  for src in $CORE_SRCS; do
    echo "/* === $src === */"
    process_source "$SCRIPT_DIR/$src" | \
      sed -e '/^#define [a-z]*_c$/d' \
          -e '/^#define LUA_CORE$/d' \
          -e '/^#define LUA_LIB$/d' \
          -e '/^#include "/d' \
          -e '/^#include </d' | \
      awk -v dir="$SCRIPT_DIR" '
        /^[[:space:]]*#include ".*\.inc"/ {
          # Extract filename from #include "xxx.inc"
          fname = $0
          sub(/.*"/, "", fname)
          sub(/".*/, "", fname)
          sub(/.*\//, "", fname)
          while ((getline line < (dir "/" fname)) > 0)
            print line
          close(dir "/" fname)
          next
        }
        { print }
      '
    echo ""
  done
} | dedup_includes > "$AMALG_C"

echo "Generated $AMALG_H and $AMALG_C"
