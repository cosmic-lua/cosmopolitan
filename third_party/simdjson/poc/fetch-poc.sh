#!/bin/sh
# Fetches the simdjson single-header amalgamation this spike was built
# against, verifies it, and applies iterator-include.patch. Materializes
# both simdjson.cpp (for the standalone cosmocc-only repro: poc.cpp,
# dispatch.cpp) and simdjson.cc (an identical copy, for the make-graph
# Lua-integration repro: BUILD.mk, lsimdjson.cc, main.cc, demo.lua --
# this tree's pattern rules key off the .cc extension). Not wired into
# the make graph itself, and simdjson.h/.cpp/.cc are gitignored here --
# see ../README.md.
set -e
cd "$(dirname "$0")"

VERSION=4.6.1
H_URL=https://raw.githubusercontent.com/simdjson/simdjson/master/singleheader/simdjson.h
CPP_URL=https://raw.githubusercontent.com/simdjson/simdjson/master/singleheader/simdjson.cpp
H_SHA256=4b72b2610c6fb5c54312bfc10a2c9068eac7580e2194c07b47d28654695fae82
CPP_SHA256=f14e397f08ff6dc58e8423647ba04cd91b5c1153a2a700c43aed16410ef955c1

fetch_and_check() {
  url=$1; out=$2; want=$3
  curl -sS -o "$out" "$url"
  got=$(sha256sum "$out" | cut -d' ' -f1)
  if [ "$got" != "$want" ]; then
    echo "checksum mismatch for $out (simdjson $VERSION may have moved on master): got $got want $want" >&2
    exit 1
  fi
}

fetch_and_check "$H_URL" simdjson.h "$H_SHA256"
fetch_and_check "$CPP_URL" simdjson.cpp "$CPP_SHA256"
patch simdjson.h < iterator-include.patch
cp simdjson.cpp simdjson.cc

echo "fetched simdjson $VERSION, applied iterator-include.patch, and staged simdjson.cc for the make-graph repro"
