#!/bin/sh
# updates third_party/lua to a new upstream Lua release.
#
#   usage: third_party/lua/update.sh 5.4.9 <sha256-tarball> \
#            <sha256-ltests.c-at-tag> <sha256-ltests.h-at-tag>
#
# fetches https://www.lua.org/ftp/lua-$V.tar.gz, verifies it by sha256, and
# installs its src/*.c and src/*.h -- except six files this fork drops
# entirely and never vendors:
#
#   lctype.c    its lookup table is reimplemented as header-only macros in
#               lctype.h instead (patches/0002-cosmo-behavior.patch)
#   lua.c       cosmo's entry point is the hand-maintained lua.main.c
#   luac.c      cosmo doesn't ship a standalone bytecode compiler binary
#   onelua.c    the single-file amalgamated build cosmo doesn't use
#   ljumptab.h  regenerated as ljumptab.inc, kept and maintained separately
#   lopnames.h  regenerated as lopnames.inc, kept and maintained separately
#
# ltests.c and ltests.h (the internal debugging module behind `make MODE=dbg`
# and lua.h's MODE_DBG hook) are NOT in that tarball -- lua.org's release
# archives are stripped of it -- so they're fetched separately, verbatim,
# from the matching tag in the upstream git mirror, and verified the same
# way. If a future Lua release renames or drops that tag, this step is the
# one to fix; everything else here still comes from the tarball.
#
# two mechanical steps make the vendored sources buildable in this hermetic
# monorepo, applied before patches/ so every further deviation -- system
# library includes swapped for cosmopolitan libc/* headers, behavior
# changes, API doc comments, all of it -- stays a reviewable, regeneratable
# patch instead of being re-derived by hand on every version bump:
#
#   1. every .c file's leading `/* $Id: ... */` license comment is replaced
#      with cosmopolitan's standard file banner (which carries Lua's own
#      copyright notice); every .h file's `/* $Id: ... */` comment is
#      deleted outright, since headers carry no banner here
#   2. quoted includes of sibling Lua headers are rewritten to full repo
#      paths, because the dependency scanner (build/bootstrap/mkdeps)
#      requires quoted includes to name files listed in HDRS/SRCS/INCS
#
# any further deviation must be checked into patches/ as a numbered patch so
# version bumps stay mechanical. after running, update README.cosmo (version
# + sha256), rebuild, and run:
#
#   make -j o//tool/lua/test
set -e
V=${1:?version required, e.g. 5.4.9}
SHA=${2:?sha256 of lua-$V.tar.gz required}
LTESTS_C_SHA=${3:?sha256 of ltests.c at git tag v$V required}
LTESTS_H_SHA=${4:?sha256 of ltests.h at git tag v$V required}
DIR=third_party/lua
URL="https://www.lua.org/ftp/lua-$V.tar.gz"
LTESTS_C_URL="https://raw.githubusercontent.com/lua/lua/v$V/ltests.c"
LTESTS_H_URL="https://raw.githubusercontent.com/lua/lua/v$V/ltests.h"

DROPPED="lctype.c lua.c luac.c onelua.c ljumptab.h lopnames.h"

# every stock Lua header cosmo still vendors; used to rewrite sibling
# #include "x.h" lines to full repo paths. ljumptab.h/lopnames.h are
# deliberately absent -- they are dropped (see above), so a stray include of
# either is left untouched and will fail loudly at compile time.
HEADERS="lapi.h lauxlib.h lcode.h lctype.h ldebug.h ldo.h lfunc.h lgc.h
llex.h llimits.h lmem.h lobject.h lopcodes.h lparser.h lprefix.h lstate.h
lstring.h ltable.h ltests.h ltm.h lua.h luaconf.h lualib.h lundump.h lvm.h
lzio.h"

# non-stock cosmo headers that live under third_party/lua/cosmo/ (moved
# there from third_party/lua/ itself alongside every other non-Lua file).
# patches/ introduces the #include lines that name them -- ltm.h's TMS enum
# moved to tms.h, lstrlib.c's string ops use cosmo.h -- so rewrite_includes
# is run again after patches/ applies, to point those new lines at the
# current location instead of the one they were written against.
COSMO_HEADERS="tms.h cosmo.h"

is_dropped() {
  n=$1
  for d in $DROPPED; do [ "$d" = "$n" ] && return 0; done
  return 1
}

T=$(mktemp -d)
BANNER="$T/banner.txt"
trap 'rm -rf "$T"' EXIT

cat >"$BANNER" <<'BANNEREOF'
/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╚──────────────────────────────────────────────────────────────────────────────╝
│                                                                              │
│  Lua                                                                         │
│  Copyright © 2004-2023 Lua.org, PUC-Rio.                                     │
│                                                                              │
│  Permission is hereby granted, free of charge, to any person obtaining       │
│  a copy of this software and associated documentation files (the             │
│  "Software"), to deal in the Software without restriction, including         │
│  without limitation the rights to use, copy, modify, merge, publish,         │
│  distribute, sublicense, and/or sell copies of the Software, and to          │
│  permit persons to whom the Software is furnished to do so, subject to       │
│  the following conditions:                                                   │
│                                                                              │
│  The above copyright notice and this permission notice shall be              │
│  included in all copies or substantial portions of the Software.             │
│                                                                              │
│  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,             │
│  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF          │
│  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.      │
│  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY        │
│  CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,        │
│  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE           │
│  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                      │
│                                                                              │
╚─────────────────────────────────────────────────────────────────────────────*/
BANNEREOF

# finds the line ending the leading `/* ... */` comment (which upstream
# always opens on line 1), plus the single blank line pristine Lua always
# leaves after it, and prints the line number the caller should keep from.
header_end() {
  f=$1
  end=$(grep -n -m1 '^\*/$' "$f" | cut -d: -f1)
  [ -n "$end" ] || {
    echo "cosmo: no leading comment found in $f" >&2
    exit 1
  }
  next=$((end + 1))
  if [ "$(sed -n "${next}p" "$f")" = "" ]; then
    end=$next
  fi
  echo "$end"
}

replace_c_header() {
  f=$1
  end=$(header_end "$f")
  {
    cat "$BANNER"
    sed -n "$((end + 1)),\$p" "$f"
  } >"$f.tmp"
  mv "$f.tmp" "$f"
}

strip_h_header() {
  f=$1
  end=$(header_end "$f")
  sed -i "1,${end}d" "$f"
}

rewrite_includes() {
  f=$1
  for h in $HEADERS; do
    sed -i "s|^#include \"$h\"|#include \"third_party/lua/$h\"|" "$f"
  done
  rewrite_cosmo_includes "$f"
}

# just the cosmo/-relocated half of the above; safe to re-run after
# patches/ applies (unlike rewrite_includes, it never touches a bare
# sibling include patches/ deliberately left unprefixed, e.g. ltests.c's).
rewrite_cosmo_includes() {
  f=$1
  for h in $COSMO_HEADERS; do
    sed -i "s|^#include \"third_party/lua/$h\"|#include \"third_party/lua/cosmo/$h\"|" "$f"
  done
}

echo "fetching $URL" >&2
curl -fsSL -o "$T/lua.tar.gz" "$URL"
echo "$SHA  $T/lua.tar.gz" | sha256sum -c -
tar xzf "$T/lua.tar.gz" -C "$T"
SRC="$T/lua-$V/src"
[ -d "$SRC" ] || {
  echo "cosmo: $SRC not found in tarball" >&2
  exit 1
}

MANIFEST="$T/manifest.txt"
: >"$MANIFEST"

for f in "$SRC"/*.c; do
  n=$(basename "$f")
  is_dropped "$n" && continue
  cp "$f" "$DIR/$n"
  replace_c_header "$DIR/$n"
  rewrite_includes "$DIR/$n"
  echo "$n" >>"$MANIFEST"
done

for f in "$SRC"/*.h; do
  n=$(basename "$f")
  is_dropped "$n" && continue
  cp "$f" "$DIR/$n"
  strip_h_header "$DIR/$n"
  rewrite_includes "$DIR/$n"
  echo "$n" >>"$MANIFEST"
done

echo "fetching $LTESTS_C_URL" >&2
curl -fsSL -o "$T/ltests.c" "$LTESTS_C_URL"
echo "$LTESTS_C_SHA  $T/ltests.c" | sha256sum -c -
cp "$T/ltests.c" "$DIR/ltests.c"
replace_c_header "$DIR/ltests.c"
rewrite_includes "$DIR/ltests.c"
echo "ltests.c" >>"$MANIFEST"

echo "fetching $LTESTS_H_URL" >&2
curl -fsSL -o "$T/ltests.h" "$LTESTS_H_URL"
echo "$LTESTS_H_SHA  $T/ltests.h" | sha256sum -c -
cp "$T/ltests.h" "$DIR/ltests.h"
strip_h_header "$DIR/ltests.h"
rewrite_includes "$DIR/ltests.h"
echo "ltests.h" >>"$MANIFEST"

for p in "$DIR"/patches/*.patch; do
  [ -e "$p" ] || continue
  echo "applying $p" >&2
  patch -p1 <"$p"
done

# a patch can introduce a fresh #include of a cosmo/-relocated header (see
# COSMO_HEADERS above) that didn't exist at the pre-patch mechanical stage,
# so run that half of the rewrite again now that patches/ has applied.
while read -r n; do
  rewrite_cosmo_includes "$DIR/$n"
done <"$MANIFEST"

echo "done; now update $DIR/README.cosmo and rebuild" >&2
