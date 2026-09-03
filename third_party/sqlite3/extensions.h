#ifndef COSMOPOLITAN_THIRD_PARTY_SQLITE3_EXTENSIONS_H_
#define COSMOPOLITAN_THIRD_PARTY_SQLITE3_EXTENSIONS_H_
#include "third_party/sqlite3/sqlite3.h"
COSMOPOLITAN_C_START_

/*
 * SQLite's own ext/misc extensions, each one a translation unit
 * third_party/sqlite3/<name>.c linked into libsqlite3.a and reachable
 * through its sqlite3_<name>_init entry point. Linking one makes it
 * available, not active: an extension is registered on a connection
 * only when something calls its init on that connection.
 */

int sqlite3_decimal_init(sqlite3 *, char **, const sqlite3_api_routines *);
int sqlite3_fileio_init(sqlite3 *, char **, const sqlite3_api_routines *);
int sqlite3_ieee_init(sqlite3 *, char **, const sqlite3_api_routines *);
int sqlite3_regexp_init(sqlite3 *, char **, const sqlite3_api_routines *);
int sqlite3_series_init(sqlite3 *, char **, const sqlite3_api_routines *);
int sqlite3_sha_init(sqlite3 *, char **, const sqlite3_api_routines *);
int sqlite3_shathree_init(sqlite3 *, char **, const sqlite3_api_routines *);
int sqlite3_sqlar_init(sqlite3 *, char **, const sqlite3_api_routines *);
int sqlite3_stmtrand_init(sqlite3 *, char **, const sqlite3_api_routines *);
int sqlite3_uint_init(sqlite3 *, char **, const sqlite3_api_routines *);
int sqlite3_zipfile_init(sqlite3 *, char **, const sqlite3_api_routines *);

/*
 * The registry: every linked extension by name, sorted by name and
 * terminated by an entry whose name is NULL, so a caller can register
 * one by looking its name up instead of naming its init in C. The
 * lsqlite3.Extension alias in tool/net/definitions.lua lists the same
 * names; tool/lua/test_sqlite_extensions.lua keeps the two in step.
 */
struct SqliteExtension {
  const char *name;
  int (*init)(sqlite3 *, char **, const sqlite3_api_routines *);
};

extern const struct SqliteExtension kSqliteExtensions[];

COSMOPOLITAN_C_END_
#endif /* COSMOPOLITAN_THIRD_PARTY_SQLITE3_EXTENSIONS_H_ */
