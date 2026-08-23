#ifndef COSMOPOLITAN_THIRD_PARTY_SQLITE3_TCLSQLITE_H_
#define COSMOPOLITAN_THIRD_PARTY_SQLITE3_TCLSQLITE_H_
/* Placeholder for the Tcl test harness header, which this tree does not
   carry. third_party/sqlite3/sqlite3.c includes it under #ifdef
   SQLITE_TEST, which is never defined here, so no compiler ever reads it.
   build/bootstrap/mkdeps scans includes textually and does not evaluate
   #ifdef, so the path must still resolve against HDRS/SRCS/INCS or the
   whole o/$(MODE)/depend graph fails to build and every object loses its
   header prerequisites. Contents are deliberately empty. */
#endif /* COSMOPOLITAN_THIRD_PARTY_SQLITE3_TCLSQLITE_H_ */
