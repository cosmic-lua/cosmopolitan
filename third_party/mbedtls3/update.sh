#!/bin/sh
# updates third_party/mbedtls3 to a new upstream mbedtls release.
#
#   usage: third_party/mbedtls3/update.sh 3.6.7 <sha256>
#
# fetches the upstream release tarball, verifies its sha256, replaces
# library/ include/ LICENSE with the pristine upstream contents, then
# applies two mechanical steps that keep the sources buildable in this
# hermetic monorepo:
#
#   1. include paths are rewritten to full repo paths, because the
#      dependency scanner (build/bootstrap/mkdeps) requires quoted
#      includes to name files listed in HDRS/SRCS/INCS
#   2. includes of un-vendored 3rdparty/test code (everest, p256-m,
#      psa test drivers -- all disabled in the default config) are
#      replaced with #error so enabling them without vendoring them
#      fails loudly
#
# any further deviation must be checked into patches/ as a numbered
# patch so version bumps stay mechanical. after running, update
# README.cosmo (version + sha256), rebuild, and run:
#
#   make -j o//test/net/https3
#   make -j o//tool/lua/test
set -e
V=${1:?version required, e.g. 3.6.7}
SHA=${2:?sha256 of the release tarball required}
DIR=third_party/mbedtls3
URL="https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-$V/mbedtls-$V.tar.bz2"

rewrite_includes() {
  find "$DIR/library" "$DIR/include" \( -name '*.c' -o -name '*.h' \) \
      -exec sed -i \
    -e 's!^#include "everest/everest\.h"!#error "cosmo: 3rdparty/everest is not vendored"!' \
    -e 's!^#include "\.\./3rdparty/p256-m/p256-m_driver_entrypoints\.h"!#error "cosmo: 3rdparty/p256-m is not vendored"!' \
    -e 's!^#include "test/drivers/test_driver\.h"!#error "cosmo: psa test drivers are not vendored"!' \
    -e 's!^#include "mbedtls/!#include "third_party/mbedtls3/include/mbedtls/!' \
    -e 's!^#include "psa/!#include "third_party/mbedtls3/include/psa/!' \
    -e 's!^#include <mbedtls/\([^>]*\)>!#include "third_party/mbedtls3/include/mbedtls/\1"!' \
    -e 's!^#include <psa/\([^>]*\)>!#include "third_party/mbedtls3/include/psa/\1"!' \
    {} +
  # upstream sometimes includes headers it expects from external specs
  # (e.g. psa/error.h and psa/internal_trusted_storage.h from the PSA
  # secure element interface, which is disabled in the default config
  # and not vendored); turn dangling includes into #error so enabling
  # such a feature without vendoring its headers fails loudly
  grep -rl '#include "third_party/mbedtls3/include/' \
      "$DIR/library" "$DIR/include" | while read -r f; do
    grep -o '#include "third_party/mbedtls3/include/[^"]*"' "$f" |
        sed 's/#include "//;s/"$//' | sort -u | while read -r inc; do
      if [ ! -f "$inc" ]; then
        sed -i "s!^#include \"$inc\"!#error \"cosmo: $inc is not vendored\"!" "$f"
      fi
    done
  done
  # same treatment for bare includes of files that do not exist next to
  # the including file (e.g. the "aes_alt.h" hooks for MBEDTLS_*_ALT
  # implementations, which are disabled and not vendored)
  find "$DIR/library" "$DIR/include" \( -name '*.c' -o -name '*.h' \) |
      while read -r f; do
    d=$(dirname "$f")
    grep -o '^#include "[^"/]*"' "$f" |
        sed 's/#include "//;s/"$//' | sort -u | while read -r inc; do
      if [ ! -f "$d/$inc" ]; then
        sed -i "s!^#include \"$inc\"!#error \"cosmo: $inc is not vendored\"!" "$f"
      fi
    done
  done
}

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
echo "fetching $URL" >&2
curl -fsSL -o "$T/mbedtls.tar.bz2" "$URL"
echo "$SHA  $T/mbedtls.tar.bz2" | sha256sum -c -
tar -xjf "$T/mbedtls.tar.bz2" -C "$T"
SRC=$(find "$T" -maxdepth 1 -type d -name "mbedtls-*" | head -n1)
rm -rf "$DIR/library" "$DIR/include"
cp -r "$SRC/library" "$DIR/library"
cp -r "$SRC/include" "$DIR/include"
cp "$SRC/LICENSE" "$DIR/LICENSE"
rm -f "$DIR/library/Makefile" "$DIR/library/CMakeLists.txt" \
      "$DIR/library/.gitignore" "$DIR/include/CMakeLists.txt" \
      "$DIR/include/.gitignore"
rewrite_includes
for p in "$DIR"/patches/*.patch; do
  [ -e "$p" ] || continue
  echo "applying $p" >&2
  patch -p1 <"$p"
done
echo "done; now update $DIR/README.cosmo and rebuild" >&2
