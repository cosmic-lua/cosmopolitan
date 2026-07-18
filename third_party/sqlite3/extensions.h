#ifndef COSMOPOLITAN_THIRD_PARTY_SQLITE3_EXTENSIONS_H_
#define COSMOPOLITAN_THIRD_PARTY_SQLITE3_EXTENSIONS_H_
#include "third_party/sqlite3/sqlite3.h"
COSMOPOLITAN_C_START_

int sqlite3_zipfile_init(sqlite3 *, char **, const sqlite3_api_routines *);

COSMOPOLITAN_C_END_
#endif /* COSMOPOLITAN_THIRD_PARTY_SQLITE3_EXTENSIONS_H_ */
