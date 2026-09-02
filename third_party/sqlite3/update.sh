#!/bin/sh
# updates third_party/sqlite3 to a new upstream sqlite release.
#
#   usage: third_party/sqlite3/update.sh 2022 3400000 <sha256-amalgamation> <sha256-src>
#
# the first two arguments are the year directory and release number used
# by sqlite.org download urls, e.g. 3.40.0 was published in 2022 as
# sqlite-amalgamation-3400000.zip. two archives are fetched:
#
#   sqlite-amalgamation-$N.zip   sqlite3.c sqlite3.h sqlite3ext.h shell.c
#   sqlite-src-$N.zip            ext/misc/zipfile.c (linked into the
#                                library for the lua zipfile() binding)
#
# both are verified by sha256 before use. after replacing the pristine
# sources, three mechanical steps keep them buildable in this hermetic
# monorepo:
#
#   1. include paths of vendored dependencies are rewritten to full repo
#      paths, because the dependency scanner (build/bootstrap/mkdeps)
#      requires quoted includes to name files listed in HDRS/SRCS/INCS
#   2. quoted includes of files that are never compiled in this repo
#      (windows sdk, tcl test harness, autoconf config header) are
#      replaced with #error so enabling them without vendoring the
#      headers fails loudly
#   3. every registered extension whose unit is vendored from shell.c's
#      inlined copy (extensions.c's registry, minus SRC_TREE_UNITS) is
#      re-extracted from the new shell.c -- see extract_shell_unit()
#      below and third_party/sqlite3/README.cosmo's EXTRACTED UNITS
#      section for the rule
#
# any further deviation must be checked into patches/ as a numbered
# patch so version bumps stay mechanical. after running, update
# README.cosmo (version + sha256s), rebuild, and run:
#
#   make -j o//tool/lua/test
#   make -j o//third_party/sqlite3
set -e
Y=${1:?year directory required, e.g. 2022}
N=${2:?release number required, e.g. 3400000 for 3.40.0}
SHA_AMALG=${3:?sha256 of sqlite-amalgamation-$N.zip required}
SHA_SRC=${4:?sha256 of sqlite-src-$N.zip required}
DIR=third_party/sqlite3
AMALG_URL="https://www.sqlite.org/$Y/sqlite-amalgamation-$N.zip"
SRC_URL="https://www.sqlite.org/$Y/sqlite-src-$N.zip"

rewrite_includes() {
  # vendored dependencies get full repo paths
  sed -i \
    -e 's!^#include "sqlite3.h"!#include "third_party/sqlite3/sqlite3.h"!' \
    -e 's!^# include "linenoise.h"!# include "third_party/linenoise/linenoise.h"!' \
    -e 's!^#include <zlib.h>!#include "third_party/zlib/zlib.h"!' \
    "$DIR/shell.c"
  sed -i \
    -e 's!^#include "sqlite3.h"!#include "third_party/sqlite3/sqlite3.h"!' \
    "$DIR/sqlite3ext.h"
  sed -i \
    -e 's!^#include "sqlite3ext.h"!#include "third_party/sqlite3/sqlite3ext.h"!' \
    -e 's!^#include <zlib.h>!#include "third_party/zlib/zlib.h"!' \
    "$DIR/zipfile.c"
  # quoted includes of files never compiled here (all behind guards that
  # are false in this build) become #error so they fail loudly if a
  # future configuration flips one on
  for f in "$DIR/sqlite3.c" "$DIR/shell.c"; do
    sed -i \
      -e 's!^\( *#\+ *\)include "mingw.h"!\1error "cosmo: mingw.h is not vendored"!' \
      -e 's!^\( *#\+ *\)include "_mingw.h"!\1error "cosmo: _mingw.h is not vendored"!' \
      -e 's!^\( *#\+ *\)include "sqlite_cfg.h"!\1error "cosmo: sqlite_cfg.h is not vendored"!' \
      -e 's!^\( *#\+ *\)include "windows.h"!\1error "cosmo: windows.h is not vendored"!' \
      -e 's!^\( *#\+ *\)include "sqlite_tcl.h"!\1error "cosmo: sqlite_tcl.h is not vendored"!' \
      -e 's!^\( *#\+ *\)include "tcl.h"!\1error "cosmo: tcl.h is not vendored"!' \
      -e 's!^\( *#\+ *\)include "sqlite3rtree.h"!\1error "cosmo: sqlite3rtree.h is not vendored"!' \
      -e 's!^\( *#\+ *\)include "sqlite3userauth.h"!\1error "cosmo: sqlite3userauth.h is not vendored"!' \
      -e 's!^\( *#\+ *\)include "test_windirent.c"!\1error "cosmo: test_windirent.c is not vendored"!' \
      "$f"
  done
}

# Units whose source is the sqlite source tree, not shell.c's inlined
# copy -- mirrors tool/lua/test_sqlite_extensions.lua's FROM_SRC_TREE.
SRC_TREE_UNITS=" zipfile "

# Extension names from third_party/sqlite3/extensions.c's kSqliteExtensions
# registry, in file order: rows look like {"name", sqlite3_name_init},
registry_names() {
  sed -n 's/^ *{"\([a-z][a-z0-9_]*\)", *sqlite3_[a-z0-9_]*_init},$/\1/p' \
    "$DIR/extensions.c"
}

# Re-extracts third_party/sqlite3/<name>.c from shell.c's inlined
# ext/misc/<name>.c section, by the rule
# tool/lua/test_sqlite_extensions.lua checks each unit against: the
# bytes between the Begin/End markers, with the commented-out
# sqlite3ext.h include rewritten to the repo path and any
# commented-out typedef (the shell inliner comments out redeclarations
# that would collide with its own) restored.
extract_shell_unit() {
  name=$1
  unit="$DIR/$name.c"
  sed -n "/Begin ext\\/misc\\/$name\\.c /,/End ext\\/misc\\/$name\\.c /{
    /Begin ext\\/misc\\/$name\\.c /d
    /End ext\\/misc\\/$name\\.c /d
    p
  }" "$DIR/shell.c" >"$unit.new"
  [ -s "$unit.new" ] || {
    echo "update.sh: no shell.c section for ext/misc/$name.c" >&2
    exit 1
  }
  n=$(grep -c '^/\* #include "sqlite3ext.h" \*/$' "$unit.new" || true)
  [ "$n" = 1 ] || {
    echo "update.sh: expected exactly one inlined sqlite3ext.h include" \
      "in ext/misc/$name.c, got $n" >&2
    exit 1
  }
  sed -i \
    -e 's!^/\* #include "sqlite3ext.h" \*/$!#include "third_party/sqlite3/sqlite3ext.h"!' \
    -e 's!^/\* \(typedef[^;]*;\) \*/$!\1!' \
    "$unit.new"
  mv "$unit.new" "$unit"
}

extract_shell_units() {
  for name in $(registry_names); do
    case "$SRC_TREE_UNITS" in
    *" $name "*) continue ;;
    esac
    extract_shell_unit "$name"
  done
}

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
echo "fetching $AMALG_URL" >&2
curl -fsSL -o "$T/amalg.zip" "$AMALG_URL"
echo "$SHA_AMALG  $T/amalg.zip" | sha256sum -c -
echo "fetching $SRC_URL" >&2
curl -fsSL -o "$T/src.zip" "$SRC_URL"
echo "$SHA_SRC  $T/src.zip" | sha256sum -c -
unzip -q "$T/amalg.zip" -d "$T"
unzip -q "$T/src.zip" "sqlite-src-$N/ext/misc/zipfile.c" -d "$T"
for f in sqlite3.c sqlite3.h sqlite3ext.h shell.c; do
  cp "$T/sqlite-amalgamation-$N/$f" "$DIR/$f"
done
cp "$T/sqlite-src-$N/ext/misc/zipfile.c" "$DIR/zipfile.c"
rewrite_includes
for p in "$DIR"/patches/*.patch; do
  [ -e "$p" ] || continue
  echo "applying $p" >&2
  patch -p1 <"$p"
done
extract_shell_units
echo "done; now update $DIR/README.cosmo and rebuild" >&2
