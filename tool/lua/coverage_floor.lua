-- Per-file function coverage floor for the Lua binding sources,
-- measured by tool/lua/coverage.lua from --ftrace traces of the
-- tests tool/lua/BUILD.mk enrols. Rewrite with COVERAGE_BASELINE=1;
-- never lower a covered count by hand.
return {
  ["third_party/lua/cosmo/lunix.c"] = { defined = 258, covered = 132 },
  ["tool/lua/lcosmo.c"] = { defined = 9, covered = 9 },
  ["tool/net/largon2.c"] = { defined = 4, covered = 4 },
  ["tool/net/lcov.c"] = { defined = 9, covered = 9 },
  ["tool/net/lfetch.c"] = { defined = 13, covered = 13 },
  ["tool/net/lfuncs.c"] = { defined = 66, covered = 64 },
  ["tool/net/lgetopt.c"] = { defined = 3, covered = 3 },
  ["tool/net/ljson.c"] = { defined = 3, covered = 2 },
  ["tool/net/llua.c"] = { defined = 11, covered = 11 },
  ["tool/net/lpath.c"] = { defined = 9, covered = 9 },
  ["tool/net/lre.c"] = { defined = 9, covered = 9 },
  ["tool/net/lsqlite3.c"] = { defined = 104, covered = 36 },
  ["tool/net/lzip.c"] = { defined = 39, covered = 37 },
}
