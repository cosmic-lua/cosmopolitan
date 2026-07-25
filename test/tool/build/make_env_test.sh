#!/bin/sh
# Gate for .ENV, the per-rule environment clamp (#208).
#
# A recipe otherwise inherits whatever the invoking shell happened to
# carry, so hermeticity depends on the caller being unremarkable. .ENV
# names the variables a build rule's child may see; everything else is
# cleared, and make's own protocol set is kept regardless so the
# jobserver handshake and recursion state survive.
#
# The property downstream depends on is "a hostile caller variable does
# not reach a recipe". That is gated in whilp/cosmic, one pin bump away
# from the code that implements it — so a regression here stays green in
# this repo and surfaces there as a mysterious hermeticity failure. This
# is the same gate, next to the implementation.
#
# Unlike the sandbox-grant gate next door, nothing here needs Landlock:
# .ENV filtering is ordinary userspace work in make's parent process,
# and it applies to every build rule whether or not .SANDBOXED is set.
# So this test has no skip path — it either passes or it found a bug.
#
# usage: test/tool/build/make_env_test.sh [MAKE] [ENV]
#
# The probe is examples/env, which prints its environment one NAME=value
# per line. It is a static APE binary run as a bare argv recipe: no
# shell, so nothing between make and the child can add or drop a
# variable and change the answer.

MAKE=${1:-o//third_party/make/make.dbg}
ENVBIN=${2:-o//examples/env.dbg}

abspath() {
  if ! [ -x "$1" ]; then
    echo "$0: $1 not built" >&2
    echo "$0: make o//third_party/make/make.dbg o//examples/env.dbg" >&2
    exit 1
  fi
  echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
}
MAKE=$(abspath "$MAKE") || exit
ENVBIN=$(abspath "$ENVBIN") || exit

t=${TMPDIR:-/tmp}/make-env-test.$$
trap 'rm -rf "$t"' EXIT INT TERM
rm -rf "$t"
mkdir -p "$t/tree"

rc=0
ok() { printf '\033[32mok\033[0m %s\n' "$1"; }
no() { printf '\033[31mfailed\033[0m %s\n' "$1"; rc=1; }

# Every fixture is a phony rule whose whole recipe is the probe.
# .RECIPEPREFIX keeps the recipes free of significant tabs.
prologue() {
  cat <<EOF
.RECIPEPREFIX := >
.PHONY: probe
EOF
}

probe_rule() {
  cat <<EOF
probe:
>@$ENVBIN
EOF
}

# Run a fixture with a deliberately hostile caller environment and print
# the child's environment. CANARY is the variable no clamped recipe may
# ever see; DECLARED and OTHER are what fixtures allow through.
child_env() {
  ( cd "$t/tree" && CANARY=evil DECLARED=ok OTHER=other \
      "$MAKE" -f "$1" probe 2>&1 )
}

# Assert on whole NAME=value lines, so a variable whose value merely
# mentions another name cannot satisfy the check.
has() { printf '%s\n' "$1" | grep -qx "$2"; }

want_present() {
  name=$1 out=$2 var=$3
  if has "$out" "$var"; then
    ok "$name"
  else
    no "$name"
    printf 'expected %s in the child environment\n' "$var" >&2
  fi
}

want_absent() {
  name=$1 out=$2 var=$3
  if has "$out" "$var"; then
    no "$name"
    printf 'leaked %s into the child environment\n' "$var" >&2
  else
    ok "$name"
  fi
}

want_name_present() {
  name=$1 out=$2 var=$3
  if printf '%s\n' "$out" | grep -q "^$var="; then
    ok "$name"
  else
    no "$name"
    printf 'expected %s= in the child environment\n' "$var" >&2
  fi
}

# An unset .ENV changes nothing: recipes see the caller's environment,
# exactly as before the feature existed.
{ prologue; probe_rule; } >"$t/unset.mk"
out=$(child_env "$t/unset.mk")
want_present "unset .ENV passes the caller's environment through" \
  "$out" "CANARY=evil"

# The core property: a declared variable arrives, an undeclared one is
# gone. This is the hostile-caller canary, stated at the C boundary.
{ prologue; cat <<'EOF'
.ENV := DECLARED
EOF
probe_rule; } >"$t/declared.mk"
out=$(child_env "$t/declared.mk")
want_present "a declared variable reaches the recipe" "$out" "DECLARED=ok"
want_absent "an undeclared variable does not" "$out" "CANARY=evil"

# The protocol set rides through any clamp. Breaking this does not show
# up as a missing variable — it breaks the jobserver handshake and
# recursion depth, which fail far from their cause.
want_name_present "MAKEFLAGS survives a restrictive .ENV" "$out" "MAKEFLAGS"
want_name_present "MAKELEVEL survives a restrictive .ENV" "$out" "MAKELEVEL"

# An EMPTY .ENV is not the same as an unset one: it clamps to the
# protocol set alone.
{ prologue; cat <<'EOF'
.ENV :=
EOF
probe_rule; } >"$t/empty.mk"
out=$(child_env "$t/empty.mk")
want_absent "an empty .ENV admits no caller variable" "$out" "CANARY=evil"
want_absent "an empty .ENV admits nothing else either" "$out" "DECLARED=ok"
want_name_present "an empty .ENV still keeps the protocol set" \
  "$out" "MAKEFLAGS"

# A global .ENV reaches a rule that declares none of its own.
{ prologue; cat <<'EOF'
.ENV := DECLARED
EOF
probe_rule; } >"$t/global.mk"
out=$(child_env "$t/global.mk")
want_present "a global .ENV reaches a rule with none of its own" \
  "$out" "DECLARED=ok"
want_absent "and still clamps" "$out" "CANARY=evil"

# Target-specific .ENV REPLACES the global one — deliberately unlike
# .UNVEIL, whose global/pattern/target sets are additive. A rule that
# declares OTHER gets OTHER only, not OTHER plus the global DECLARED.
{ prologue; cat <<'EOF'
.ENV := DECLARED
probe: .ENV := OTHER
EOF
probe_rule; } >"$t/target.mk"
out=$(child_env "$t/target.mk")
want_present "a target .ENV takes effect" "$out" "OTHER=other"
want_absent "a target .ENV replaces the global one rather than adding" \
  "$out" "DECLARED=ok"

# Pattern-specific .ENV resolves too, between target and global.
cat >"$t/pattern.mk" <<EOF
.RECIPEPREFIX := >
.ENV := DECLARED
%.probed: .ENV := OTHER
%.probed:
>@$ENVBIN
EOF
out=$( cd "$t/tree" && CANARY=evil DECLARED=ok OTHER=other \
       "$MAKE" -f "$t/pattern.mk" thing.probed 2>&1 )
want_present "a pattern .ENV takes effect" "$out" "OTHER=other"
want_absent "a pattern .ENV replaces the global one" "$out" "DECLARED=ok"

# $(shell) is parse-time apparatus, not a recipe, and stays unclamped —
# a documented scope boundary worth pinning so it is not narrowed by
# accident.
cat >"$t/shell.mk" <<EOF
.RECIPEPREFIX := >
.ENV := DECLARED
\$(info shell-canary: \$(if \$(findstring CANARY=evil,\$(shell $ENVBIN)),yes,no))
.PHONY: probe
probe:
>@:
EOF
out=$( cd "$t/tree" && CANARY=evil DECLARED=ok OTHER=other \
       "$MAKE" -f "$t/shell.mk" probe 2>&1 )
if printf '%s\n' "$out" | grep -q "shell-canary: yes"; then
  ok "\$(shell) is not clamped by .ENV"
else
  no "\$(shell) is not clamped by .ENV"
  printf 'got:\n%s\n' "$out" >&2
fi

if [ $rc = 0 ]; then
  echo "make_env_test: PASS"
else
  echo "make_env_test: FAIL"
fi

exit $rc
