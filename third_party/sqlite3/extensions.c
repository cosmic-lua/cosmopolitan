#include "third_party/sqlite3/extensions.h"

/*
 * One row per extension linked into libsqlite3.a, sorted by name and
 * NULL-terminated. A row's name is the stem of the translation unit it
 * comes from (third_party/sqlite3/<name>.c) and its init is that unit's
 * sqlite3_<name>_init.
 */
const struct SqliteExtension kSqliteExtensions[] = {
    {"decimal", sqlite3_decimal_init},
    {"fileio", sqlite3_fileio_init},
    {"ieee", sqlite3_ieee_init},
    {"regexp", sqlite3_regexp_init},
    {"series", sqlite3_series_init},
    {"sha", sqlite3_sha_init},
    {"shathree", sqlite3_shathree_init},
    {"zipfile", sqlite3_zipfile_init},
    {0, 0},
};
