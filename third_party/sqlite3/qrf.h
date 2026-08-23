#ifndef COSMOPOLITAN_THIRD_PARTY_SQLITE3_QRF_H_
#define COSMOPOLITAN_THIRD_PARTY_SQLITE3_QRF_H_
/* Placeholder for the qrf extension header. Its declarations are already
   inlined into third_party/sqlite3/shell.c, which defines SQLITE_QRF_H, so
   the `#ifndef SQLITE_QRF_H` fallback include below them can never fire and
   no compiler ever reads this path. build/bootstrap/mkdeps scans includes
   textually and does not evaluate the preprocessor, so the path must still
   resolve against HDRS/SRCS/INCS or the whole o/$(MODE)/depend graph fails
   to build and every object loses its header prerequisites. Contents are
   deliberately empty: declaring anything here would collide with the
   inlined copy. */
#endif /* COSMOPOLITAN_THIRD_PARTY_SQLITE3_QRF_H_ */
