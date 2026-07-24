#!/bin/sh
# Gate for landlock-make's graph-derived sandbox grants (#210).
#
# A sandboxed rule's grants are supposed to be a FUNCTION OF THE
# DECLARED GRAPH: the recipe program, the target's directory, the
# prerequisites, the .PLEDGE-implied paths, the global .UNVEIL base,
# and per-rule declared extras — nothing else.  "A rule needs no hand
# grants" has been a convention held up by downstream review; this
# turns it into a property with a gate.
#
# Two layers, because the interesting half needs a kernel:
#
#   derivation   asserts the grant set make COMPUTES for a rule is
#                exactly the derived set plus declared extras.  Reads
#                make's own --debug=j log, so it runs on any Linux —
#                including hosts where unveil() no-ops.
#
#   enforcement  asserts that set is also a CEILING: a path outside it
#                is denied.  Needs Landlock (Linux >= 5.13).  A positive
#                control runs first (a rule declaring nothing must still
#                build), then a canary probes for real enforcement; when
#                unveil() is a no-op the denials are SKIPPED, loudly,
#                rather than passing vacuously.
#
# usage: test/tool/build/make_sandbox_test.sh [MAKE] [CP] [TOUCH]
#
# The recipe programs are static APE binaries on purpose: a dynamically
# linked host shell can not start under a derived-only grant set (its
# loader and libc are not in the graph), which is why recipes-as-single-
# argv is the shape this derivation is meant to serve.  cp reads (it is
# the read probe); touch writes with a plain open(O_CREAT) and creates
# no directories, so it is the honest probe for "make created the
# target's directory itself".

MAKE=${1:-o//third_party/make/make.dbg}
CP=${2:-o//tool/build/cp.dbg}
TOUCH=${3:-o//tool/build/touch.dbg}

abspath() {
  if ! [ -x "$1" ]; then
    echo "$0: $1 not built" >&2
    echo "$0: make o//third_party/make/make.dbg o//tool/build/cp.dbg \
o//tool/build/touch.dbg" >&2
    exit 1
  fi
  echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
}
MAKE=$(abspath "$MAKE") || exit
CP=$(abspath "$CP") || exit
TOUCH=$(abspath "$TOUCH") || exit

t=${TMPDIR:-/tmp}/make-sandbox-test.$$
trap 'rm -rf "$t"' EXIT INT TERM
rm -rf "$t"
mkdir -p "$t/tree/src" "$t/tree/secret" "$t/tree/base"
echo hello >"$t/tree/src/input.txt"
echo ordered >"$t/tree/src/order.txt"
echo topsecret >"$t/tree/secret/hidden.txt"
echo based >"$t/tree/base/ok.txt"

rc=0
ok() { printf '\033[32mok\033[0m %s\n' "$1"; }
no() { printf '\033[31mfailed\033[0m %s\n' "$1"; rc=1; }
skip() { printf '\033[33mskip\033[0m %s\n' "$1"; }

# Every fixture shares this prologue.  .RECIPEPREFIX keeps recipes free
# of significant tabs; the promises are the smallest set that lets the
# recipe programs run — rpath is what pulls in /proc/filesystems below,
# and fattr is what lets touch's utimes() through (without it seccomp
# answers EPERM, which touch does not read as "create the file").
prologue() {
  cat <<EOF
.RECIPEPREFIX := >
.PLEDGE := stdio rpath wpath cpath fattr proc exec
.SANDBOXED = 1
EOF
}

# Run a fixture and print its grant set, one "perm path" per line,
# sorted, with the volatile bits (temp dir, recipe programs) replaced by
# stable placeholders.  The sandbox commit line carries no path and is
# dropped.
grants() {
  ( cd "$t/tree" && "$MAKE" -f "$1" --debug=j 2>&1 ) |
    sed -n 's/^Unveil \(.*\) with permissions \(.*\)$/\2 \1/p' |
    grep -v '^(null)' |
    sed -e "s|$CP|@CP|g" -e "s|$TOUCH|@TOUCH|g" -e "s|$t|@T|g" |
    sort
}

# Run a fixture for its exit status alone, discarding output.
run() {
  ( cd "$t/tree" && "$MAKE" -f "$1" >/dev/null 2>&1 )
}

check() {
  name=$1 got=$2 want=$3
  if [ "$got" = "$want" ]; then
    ok "$name"
  else
    no "$name"
    printf 'want:\n%s\ngot:\n%s\n' "$want" "$got" >&2
  fi
}

#
# derivation layer
#

# A rule that declares NOTHING gets exactly: the recipe program, its
# target's directory, the .PLEDGE-implied paths, and its prerequisites.
# This is the whole point of #210 — if this set ever grows, a rule is
# getting reach it never declared.
{ prologue; cat <<EOF
out/copy.txt: src/input.txt
> $CP \$< \$@
EOF
} >"$t/derived.mk"
rm -rf "$t/tree/out"
check "derived-only grant set" "$(grants "$t/derived.mk")" \
"r /proc/filesystems
rwc out
rx @CP
rx src/input.txt"

# The target's directory is created BEFORE it is unveiled (#212): unveil
# silently skips a path that does not exist, so on a cold tree the grant
# used to no-op exactly when it was needed.  touch creates no
# directories, so a target several levels below anything that exists can
# only appear if make made the chain itself.
{ prologue; cat <<EOF
deep/a/b/c/stamp:
> $TOUCH \$@
EOF
} >"$t/deep.mk"
rm -rf "$t/tree/deep"
check "deep target dir grant" "$(grants "$t/deep.mk")" \
"r /proc/filesystems
rwc deep/a/b/c
rx @TOUCH"
if [ -f "$t/tree/deep/a/b/c/stamp" ]; then
  ok "target dir is created before it is unveiled"
else
  no "target dir is created before it is unveiled"
fi

# Order-only prerequisites are part of the declared graph and are
# granted; a prerequisite spelled with a trailing slash is a timestamp
# check by convention and is deliberately NOT granted.
{ prologue; cat <<EOF
out/ordered.txt: src/input.txt src/ | src/order.txt
> $CP \$< \$@
EOF
} >"$t/deps.mk"
rm -rf "$t/tree/out"
check "order-only granted, trailing-slash prereq not" \
"$(grants "$t/deps.mk")" \
"r /proc/filesystems
rwc out
rx @CP
rx src/input.txt
rx src/order.txt"

# A target with no directory component derives nothing: dirname would
# be ".", and granting rwc on the whole working tree implicitly is the
# opposite of the point.  Such rules declare their grants by hand.
{ prologue; cat <<EOF
cwdstamp:
> $TOUCH \$@
EOF
} >"$t/cwd.mk"
rm -f "$t/tree/cwdstamp"
check "cwd target derives no directory grant" "$(grants "$t/cwd.mk")" \
"r /proc/filesystems
rx @TOUCH"

# Declared extras — global base and per-rule — are added to the derived
# set, and are the ONLY things added to it.
{ prologue; cat <<EOF
.UNVEIL := r:$t/tree/base
out/extra.txt: src/input.txt
> $CP \$< \$@
out/extra.txt: .UNVEIL := r:$t/tree/secret
EOF
} >"$t/extras.mk"
rm -rf "$t/tree/out"
check "declared extras merge onto the derived set" \
"$(grants "$t/extras.mk")" \
"r /proc/filesystems
r @T/tree/base
r @T/tree/secret
rwc out
rx @CP
rx src/input.txt"

#
# enforcement layer
#

# Positive control, first: a rule that declares NOTHING must still
# build.  Default-deny has to be livable, not merely safe — and this
# has to be established before any denial below is believed, since a
# host where the recipe program cannot start under the derived set at
# all would make every negative check "pass" for the wrong reason.
rm -rf "$t/tree/out"
if run "$t/derived.mk" && [ "$(cat "$t/tree/out/copy.txt" 2>/dev/null)" = hello ]
then
  ok "derived-only rule builds"
  livable=1
else
  no "derived-only rule builds"
  echo "$0: the derived set is not sufficient to run the recipe" >&2
  livable=0
fi

# Negative control: is unveil() real on this host?  A sandboxed rule
# reading a path that is in no grant must fail.  If it succeeds,
# Landlock is absent or stubbed and every denial below would pass
# vacuously.
{ prologue; cat <<EOF
out/canary.txt:
> $CP secret/hidden.txt \$@
EOF
} >"$t/canary.mk"
rm -rf "$t/tree/out"
if [ "$livable" = 0 ]; then
  skip "enforcement layer (derived set is not livable here)"
elif run "$t/canary.mk"; then
  skip "enforcement layer (unveil() does not enforce on this host)"
  echo "$0: Landlock unavailable — derivation checked, denials not" >&2
else
  ok "undeclared path is denied"

  # Declaring it as an extra is the only way through.
  { prologue; cat <<EOF
out/allowed.txt: .UNVEIL := r:$t/tree/secret
out/allowed.txt:
> $CP secret/hidden.txt \$@
EOF
  } >"$t/allowed.mk"
  rm -rf "$t/tree/out"
  if run "$t/allowed.mk" && [ -f "$t/tree/out/allowed.txt" ]; then
    ok "declared extra permits the same path"
  else
    no "declared extra permits the same path"
  fi

  # The global base reaches a rule that declares nothing itself.
  { prologue; cat <<EOF
.UNVEIL := r:$t/tree/base
out/global.txt:
> $CP base/ok.txt \$@
EOF
  } >"$t/global.mk"
  rm -rf "$t/tree/out"
  if run "$t/global.mk" && [ -f "$t/tree/out/global.txt" ]; then
    ok "global base reaches a rule with no grants of its own"
  else
    no "global base reaches a rule with no grants of its own"
  fi

  # The counterpart of the derivation check above: no directory
  # component means no implicit write access to the working tree.
  rm -f "$t/tree/cwdstamp"
  if run "$t/cwd.mk"; then
    no "cwd target write is denied"
  else
    ok "cwd target write is denied"
  fi
fi

exit $rc
