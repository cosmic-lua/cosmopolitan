---@meta
error("Tried to evaluate definition file.")

---@class string
---@operator mod(any[]): string
---@operator mul(integer): string

-- GLOBALS

--- Array of command line arguments, excluding those parsed by
--- getopt() in the C code, which stops parsing at the first
--- non-hyphenated arg. In some cases you can use the magic --
--- argument to delimit C from Lua arguments.
---
--- For example, if you launch your redbean as follows:
---
---     redbean -v arg1 arg2
---
--- Then your `/.init.lua` file will have the `arg` array like:
---
---     arg[-1] = '/usr/bin/redbean'
---     arg[ 0] = '/zip/.init.lua'
---     arg[ 1] = 'arg1'
---     arg[ 2] = 'arg2'
---
--- If you launch redbean in interpreter mode (rather than web
--- server) mode, then an invocation like this:
---
---     ./redbean -i script.lua arg1 arg2
---
--- Would have an `arg` array like this:
---
---     arg[-1] = './redbean'
---     arg[ 0] = 'script.lua'
---     arg[ 1] = 'arg1'
---     arg[ 2] = 'arg2'
---@type string[]
arg = nil

-- DATATYPES

---@class cosmo.Url
---@field scheme string e.g. `"http"`
---@field user string? the username string, or nil if absent
---@field pass string? the password string, or nil if absent
---@field host string? the hostname string, or nil if `url` was a path
---@field port string? the port string, or nil if absent
---@field path string? the path string, or nil if absent
---@field params string[][]? the URL paramaters e.g. `/?a=b&c` would be
--- represented as the data structure `{{"a", "b"}, {"c"}, ...}`
---@field fragment string? the stuff after the `#` character

---@alias uint32 integer Unsigned 32-bit integer
---@alias uint16 integer Unsigned 16-bit integer
---@alias uint8 integer Unsigned 8-bit integer
---@alias int8 integer Signed 8-bit integer

---@class cosmo.EncoderOptions
---@field useoutput boolean? defaults to `false`. Encodes the result directly to the output buffer and returns `nil` value. This option is ignored if used outside of request handling code.
---@field sorted boolean? defaults to `true`. Lua uses hash tables so the order of object keys is lost in a Lua table. So, by default, we use strcmp to impose a deterministic output order. If you don't care about ordering then setting sorted=false should yield a performance boost in serialization.
---@field pretty boolean? defaults to `false`. Setting this option to true will cause tables with more than one entry to be formatted across multiple lines for readability.
---@field indent string? defaults to " ". This option controls the indentation of pretty formatting. This field is ignored if pretty isn't true.
---@field maxdepth integer? defaults to 64. This option controls the maximum amount of recursion the serializer is allowed to perform. The max is 32767. You might not be able to set it that high if there isn't enough C stack memory. Your serializer checks for this and will return an error rather than crashing.
---@field nan "null"? `EncodeJson` only: encode NaN and Infinity as `null` (the v8 behavior) instead of failing with `nil, error`.

---@class cosmo.DeflateOptions
---@field level integer? compression level `-1`..`9`; defaults to `-1`, the zlib default (currently 6). `0` stores without compressing; higher levels are slower but compress better.
---@field format "raw"|"zlib"|"gzip"? framing of the compressed stream; defaults to `"raw"` (headerless DEFLATE, as used inside ZIP files).

---@class cosmo.InflateOptions
---@field maxsize integer? cap on the decompressed size in bytes; defaults to 64 MiB. Decompression streams into a growing buffer and fails with `nil, error` once the cap is exceeded, so no attacker-controlled length is ever trusted as an allocation size.
---@field format "raw"|"zlib"|"gzip"|"auto"? framing of the compressed stream; defaults to `"raw"`. `"auto"` detects zlib or gzip framing from the stream header (but cannot detect `"raw"`).

---@class cosmo.FetchOptions
---@field headers table<string,string>? request headers to send.
---@field method string? HTTP method, e.g. `"GET"` (default) or `"POST"`.
---@field body string? request payload.
---@field maxredirects integer? maximum number of redirects to follow.
---@field followredirect boolean? whether to follow redirects. Defaults to `true`.
---@field allowprivate boolean? allow requests to private, loopback, and other non-public network addresses (disables the SSRF guard). Applies to every hop of a redirect chain. Defaults to `false`.
---@field keepalive boolean? whether to keep the connection alive.
---@field proxy string? proxy URL to route the request through.
---@field maxresponse integer? limit on response (or per-read buffer) size.
---@field timeout number? request timeout in seconds. `0` or absent keeps the 60-second default; there is no "infinite" option.

-- MODULES

---Please refer to the LuaSQLite3 Documentation.
---
--- For example, you could put the following in your `/.init.lua` file:
---
---     lsqlite3 = require "lsqlite3"
---     db = lsqlite3.open_memory()
---     db:exec[[
---       CREATE TABLE test (
---         id INTEGER PRIMARY KEY,
---         content TEXT
---       );
---       INSERT INTO test (content) VALUES ('Hello World');
---       INSERT INTO test (content) VALUES ('Hello Lua');
---       INSERT INTO test (content) VALUES ('Hello Sqlite3');
---     ]]
---
--- Then, your Lua server pages or OnHttpRequest handler may perform SQL
--- queries by accessing the db global. The performance is good too, at about
--- 400k qps.
---
---     for row in db:nrows("SELECT * FROM test") do
---         Write(row.id.." "..row.content.."<br>")
---     end
---
--- redbean supports a subset of what's defined in the upstream LuaSQLite3
--- project. Most of the unsupported APIs relate to pointers and database
--- notification hooks.

lsqlite3 = {
    -- Error Codes

    --- The `lsqlite3.OK` result code means that the operation was successful
    --- and that there were no errors. Most other result codes indicate an
    --- error.
    OK = 0,
    --- The `lsqlite3.ERROR` result code is a generic error code that is used
    --- when no other more specific error code is available.
    ERROR = 1,
    --- The `lsqlite3.INTERNAL` result code indicates an internal malfunction.
    --- In a working version of SQLite, an application should never see this
    --- result code. If application does encounter this result code, it shows
    --- that there is a bug in the database engine.
    ---
    --- SQLite does not currently generate this result code. However,
    --- application-defined SQL functions or virtual tables, or VFSes, or other
    --- extensions might cause this result code to be returned.
    INTERNAL = 2,
    --- The `lsqlite3.PERM` result code indicates that the requested access mode
    --- for a newly created database could not be provided.
    PERM = 3,
    --- The `lsqlite3.ABORT` result code indicates that an operation was aborted
    --- prior to completion, usually be application request. See also:
    --- `lsqlite3.INTERRUPT`.
    ---
    --- If the callback function to `exec()` returns non-zero, then `exec()`
    --- will return `lsqlite3.ABORT`.
    ---
    --- If a ROLLBACK operation occurs on the same database connection as a
    --- pending read or write, then the pending read or write may fail with an
    --- `lsqlite3.ABORT` error.
    ABORT = 4,
    --- The lsqlite3.BUSY result code indicates that the database file could not
    --- be written (or in some cases read) because of concurrent activity by
    --- some other database connection, usually a database connection in a
    --- separate process.
    ---
    --- For example, if process A is in the middle of a large write transaction
    --- and at the same time process B attempts to start a new write
    --- transaction, process B will get back an `lsqlite3.BUSY` result because
    --- SQLite only supports one writer at a time. Process B will need to wait
    --- for process A to finish its transaction before starting a new
    --- transaction. The `db:busy_timeout()` and `db:busy_handler()` interfaces
    --- are available to process B to help it deal with `lsqlite3.BUSY` errors.
    ---
    --- An `lsqlite3.BUSY` error can occur at any point in a transaction: when
    --- the transaction is first started, during any write or update operations,
    --- or when the transaction commits. To avoid encountering `lsqlite3.BUSY`
    --- errors in the middle of a transaction, the application can use
    --- `BEGIN IMMEDIATE` instead of just `BEGIN` to start a transaction. The
    --- `BEGIN IMMEDIATE` command might itself return `lsqlite3.BUSY`, but if it
    --- succeeds, then SQLite guarantees that no subsequent operations on the same database through the next COMMIT will return `lsqlite3.BUSY`.
    ---
    --- The `lsqlite3.BUSY` result code differs from `lsqlite3.LOCKED` in that
    --- `lsqlite3.BUSY` indicates a conflict with a separate database
    --- connection, probably in a separate process, whereas `lsqlite3.LOCKED`
    --- indicates a conflict within the same database connection (or sometimes
    --- a database connection with a shared cache).
    BUSY = 5,
    --- The `lsqlite3.LOCKED` result code indicates that a write operation could
    --- not continue because of a conflict within the same database connection
    --- or a conflict with a different database connection that uses a shared
    --- cache.
    ---
    --- For example, a DROP TABLE statement cannot be run while another thread
    --- is reading from that table on the same database connection because
    --- dropping the table would delete the table out from under the concurrent
    --- reader.
    ---
    --- The `lsqlite3.LOCKED` result code differs from `lsqlite3.BUSY` in that
    --- `lsqlite3.LOCKED` indicates a conflict on the same database connection
    --- (or on a connection with a shared cache) whereas `lsqlite3.BUSY`
    --- indicates a conflict with a different database connection, probably in
    --- a different process.
    LOCKED = 6,
    --- The `lsqlite3.NOMEM` result code indicates that SQLite was unable to
    --- allocate all the memory it needed to complete the operation. In other
    --- words, an internal call to `sqlite3_malloc()` or `sqlite3_realloc()` has
    --- failed in a case where the memory being allocated was required in order
    --- to continue the operation.
    NOMEM = 7,
    --- The `lsqlite3.READONLY` result code is returned when an attempt is made
    --- to alter some data for which the current database connection does not
    --- have write permission.
    READONLY = 8,
    --- The `lsqlite3.INTERRUPT` result code indicates that an operation was
    --- interrupted by the `sqlite3_interrupt()` interface. See also:
    --- `lsqlite3.ABORT`
    INTERRUPT = 9,
    --- The `lsqlite3.IOERR` result code says that the operation could not
    --- finish because the operating system reported an I/O error.
    ---
    --- A full disk drive will normally give an `lsqlite3.FULL` error rather
    --- than an `lsqlite3.IOERR` error.
    ---
    --- There are many different extended result codes for I/O errors that
    --- identify the specific I/O operation that failed.
    IOERR = 10,
    --- The `lsqlite3.CORRUPT` result code indicates that the database file has
    --- been corrupted. See [How To Corrupt Your Database Files](https://www.sqlite.org/lockingv3.html#how_to_corrupt)
    --- for further discussion on how corruption can occur.
    CORRUPT = 11,
    --- The `lsqlite3.NOTFOUND` result code is exposed in three ways:
    ---
    --- `lsqlite3.NOTFOUND` can be returned by the `sqlite3_file_control()`
    --- interface to indicate that the file control opcode passed as the third
    --- argument was not recognized by the underlying VFS.
    ---
    --- `lsqlite3.NOTFOUND` can also be returned by the xSetSystemCall() method
    --- of an sqlite3_vfs object.
    ---
    --- `lsqlite3.NOTFOUND` an be returned by sqlite3_vtab_rhs_value() to
    --- indicate that the right-hand operand of a constraint is not available
    --- to the xBestIndex method that made the call.
    ---
    --- The `lsqlite3.NOTFOUND` result code is also used internally by the
    --- SQLite implementation, but those internal uses are not exposed to the
    --- application.
    NOTFOUND = 12,
    --- The `lsqlite3.FULL` result code indicates that a write could not
    --- complete because the disk is full. Note that this error can occur when
    --- trying to write information into the main database file, or it can also
    --- occur when writing into temporary disk files.
    ---
    --- Sometimes applications encounter this error even though there is an
    --- abundance of primary disk space because the error occurs when writing
    --- into temporary disk files on a system where temporary files are stored
    --- on a separate partition with much less space that the primary disk.
    FULL = 13,
    --- The `lsqlite3.CANTOPEN` result code indicates that SQLite was unable to
    --- open a file. The file in question might be a primary database file or
    --- one of several temporary disk files.
    CANTOPEN = 14,
    --- The `lsqlite3.PROTOCOL` result code indicates a problem with the file
    --- locking protocol used by SQLite. The `lsqlite3.PROTOCOL` error is
    --- currently only returned when using WAL mode and attempting to start a
    --- new transaction. There is a race condition that can occur when two
    --- separate database connections both try to start a transaction at the
    --- same time in WAL mode. The loser of the race backs off and tries again,
    --- after a brief delay. If the same connection loses the locking race
    --- dozens of times over a span of multiple seconds, it will eventually give
    --- up and return `lsqlite3.PROTOCOL`. The `lsqlite3.PROTOCOL` error should
    --- appear in practice very, very rarely, and only when there are many
    --- separate processes all competing intensely to write to the same
    --- database.
    PROTOCOL = 15,
    --- The `lsqlite3.EMPTY` result code is not currently used.
    EMPTY = 16,
    --- The `lsqlite3.SCHEMA` result code indicates that the database schema has
    --- changed. This result code can be returned from `Statement:step()`. If
    --- the database schema was changed by some other process in between the
    --- time that the statement was prepared and the time the statement was run,
    --- this error can result.
    ---
    --- The statement is automatically re-prepared if the schema changes, up to
    --- `SQLITE_MAX_SCHEMA_RETRY` times (default: 50). The `step()` interface
    --- will only return `lsqlite3.SCHEMA` back to the application if the
    --- failure persists after these many retries.
    SCHEMA = 17,
    --- The `lsqlite3.TOOBIG` error code indicates that a string or BLOB was too
    --- large. The default maximum length of a string or BLOB in SQLite is
    --- 1,000,000,000 bytes. This maximum length can be changed at compile-time
    --- using the `SQLITE_MAX_LENGTH` compile-time option. The `lsqlite3.TOOBIG`
    --- error results when SQLite encounters a string or BLOB that exceeds the
    --- compile-time limit.
    ---
    --- The `lsqlite3.TOOBIG` error code can also result when an oversized SQL
    --- statement is passed into one of the `db:prepare()` interface. The
    --- maximum length of an SQL statement defaults to a much smaller value of
    --- 1,000,000,000 bytes.
    TOOBIG = 18,
    --- The `lsqlite3.CONSTRAINT` error code means that an SQL constraint
    --- violation occurred while trying to process an SQL statement. Additional
    --- information about the failed constraint can be found by consulting the
    --- accompanying error message (returned via `errmsg()`) or by looking at
    --- the extended error code.
    ---
    --- The `lsqlite3.CONSTRAINT` code can also be used as the return value from
    --- the `xBestIndex()` method of a virtual table implementation. When
    --- `xBestIndex()` returns `lsqlite3.CONSTRAINT`, that indicates that the
    --- particular combination of inputs submitted to `xBestIndex()` cannot
    --- result in a usable query plan and should not be given further
    --- consideration.
    CONSTRAINT = 19,
    --- SQLite is normally very forgiving about mismatches between the type of a
    --- value and the declared type of the container in which that value is to
    --- be stored. For example, SQLite allows the application to store a large
    --- BLOB in a column with a declared type of BOOLEAN. But in a few cases,
    --- SQLite is strict about types. The `lsqlite3.MISMATCH` error is returned
    --- in those few cases when the types do not match.
    ---
    --- The rowid of a table must be an integer. Attempt to set the rowid to
    --- anything other than an integer (or a NULL which will be automatically
    --- converted into the next available integer rowid) results in an
    --- `lsqlite3.MISMATCH` error.
    MISMATCH = 20,
    --- The `lsqlite3.MISUSE` return code might be returned if the application
    --- uses any SQLite interface in a way that is undefined or unsupported. For
    --- example, using a prepared statement after that prepared statement has
    --- been finalized might result in an `lsqlite3.MISUSE` error.
    ---
    --- SQLite tries to detect misuse and report the misuse using this result
    --- code. However, there is no guarantee that the detection of misuse will
    --- be successful. Misuse detection is probabilistic. Applications should
    --- never depend on an `lsqlite3.MISUSE` return value.
    ---
    --- If SQLite ever returns `lsqlite3.MISUSE` from any interface, that means
    --- that the application is incorrectly coded and needs to be fixed. Do not
    --- ship an application that sometimes returns `lsqlite3.MISUSE` from a
    --- standard SQLite interface because that application contains potentially
    --- serious bugs.
    MISUSE = 21,
    --- The `lsqlite3.NOLFS` error can be returned on systems that do not
    --- support large files when the database grows to be larger than what the
    --- filesystem can handle. "NOLFS" stands for "NO Large File Support".
    NOLFS = 22,
    --- The `lsqlite3.FORMAT` error code is not currently used by SQLite.
    FORMAT = 24,
    --- The `lsqlite3.RANGE` error indices that the parameter number argument to
    --- one of the `bind` routines or the column number in one of the `column`
    --- routines is out of range.
    RANGE = 25,
    --- When attempting to open a file, the `lsqlite3.NOTADB` error indicates
    --- that the file being opened does not appear to be an SQLite database
    --- file.
    NOTADB = 26,
    --- The `lsqlite3.ROW` result code returned by sqlite3_step() indicates that
    --- another row of output is available.
    ROW = 100,
    --- The `lsqlite3.DONE` result code indicates that an operation has
    --- completed. The `lsqlite3.DONE` result code is most commonly seen as a
    --- return value from `step()` indicating that the SQL statement has run to
    --- completion, but `lsqlite3.DONE` can also be returned by other multi-step
    --- interfaces.
    DONE = 101,

    -- Authorizer Action Codes

    CREATE_INDEX = 1,
    CREATE_TABLE = 2,
    CREATE_TEMP_INDEX = 3,
    CREATE_TEMP_TABLE = 4,
    CREATE_TEMP_TRIGGER = 5,
    CREATE_TEMP_VIEW = 6,
    CREATE_TRIGGER = 7,
    CREATE_VIEW = 8,
    DELETE = 9,
    DROP_INDEX = 10,
    DROP_TABLE = 11,
    DROP_TEMP_INDEX = 12,
    DROP_TEMP_TABLE = 13,
    DROP_TEMP_TRIGGER = 14,
    DROP_TEMP_VIEW = 15,
    DROP_TRIGGER = 16,
    DROP_VIEW = 17,
    INSERT = 18,
    PRAGMA = 19,
    READ = 20,
    SELECT = 21,
    TRANSACTION = 22,
    UPDATE = 23,
    ATTACH = 24,
    DETACH = 25,
    ALTER_TABLE = 26,
    REINDEX = 27,
    ANALYZE = 28,
    CREATE_VTABLE = 29,
    DROP_VTABLE = 30,
    FUNCTION = 31,
    SAVEPOINT = 32,

    -- Open Flags

    ---@type integer
    --- The database is created if it does not already exist.
    OPEN_CREATE = nil,
    ---@type integer
    --- The database is opened with shared cache disabled, overriding the
    --- default shared cache setting provided by sqlite3_enable_shared_cache().
    OPEN_PRIVATECACHE = nil,
    ---@type integer
    --- The new database connection will use the "serialized" threading mode.
    --- This means the multiple threads can safely attempt to use the same
    --- database connection at the same time. (Mutexes will block any actual
    --- concurrency, but in this mode there is no harm in trying.)
    OPEN_FULLMUTEX = nil,
    ---@type integer
    --- The new database connection will use the "multi-thread" threading mode.
    --- This means that separate threads are allowed to use SQLite at the same
    --- time, as long as each thread is using a different database connection.
    OPEN_NOMUTEX = nil,
    ---@type integer
    --- The database will be opened as an in-memory database. The database is
    --- named by the "filename" argument for the purposes of cache-sharing, if
    --- shared cache mode is enabled, but the "filename" is otherwise ignored.
    OPEN_MEMORY = nil,
    ---@type integer
    --- The filename can be interpreted as a URI if this flag is set. See
    --- https://www.sqlite.org/c3ref/open.html
    OPEN_URI = nil,
    ---@type integer
    --- The database is opened for reading and writing if possible, or reading
    --- only if the file is write protected by the operating system. In either
    --- case the database must already exist, otherwise an error is returned.
    OPEN_READWRITE = nil,
    ---@type integer
    --- The database is opened in read-only mode. If the database does not
    --- already exist, an error is returned.
    OPEN_READONLY = nil,
    ---@type integer
    --- The database is opened shared cache enabled, overriding the default
    --- shared cache setting provided by sqlite3_enable_shared_cache(). The use
    --- of shared cache mode is discouraged and hence shared cache capabilities
    --- may be omitted from many builds of SQLite. In such cases, this option is
    --- a no-op.
    OPEN_SHAREDCACHE = nil,

    ---@type integer
    TEXT = nil,
    ---@type integer
    BLOB = nil,
    ---@type integer
    NULL = nil,
    ---@type integer
    FLOAT = nil,
    ---@type integer
    INTEGER = nil,

    -- Config Options

    ---@type integer selects single-threaded mode. See `lsqlite3.config`.
    CONFIG_SINGLETHREAD = nil,
    ---@type integer selects multi-threaded mode. See `lsqlite3.config`.
    CONFIG_MULTITHREAD = nil,
    ---@type integer selects serialized threading mode. See `lsqlite3.config`.
    CONFIG_SERIALIZED = nil,
    ---@type integer installs or removes the global log callback. See `lsqlite3.config`.
    CONFIG_LOG = nil,

    -- Checkpoint Modes

    ---@type integer checkpoint as many frames as possible without waiting
    --- for any database readers or writers to finish. See `db:wal_checkpoint`.
    CHECKPOINT_PASSIVE = nil,
    ---@type integer blocks until there is no writer and all readers are
    --- reading from the most recent database snapshot, then checkpoints all
    --- frames. See `db:wal_checkpoint`.
    CHECKPOINT_FULL = nil,
    ---@type integer same as `lsqlite3.CHECKPOINT_FULL`, but additionally
    --- blocks until all readers are reading from the database file only.
    --- See `db:wal_checkpoint`.
    CHECKPOINT_RESTART = nil,
    ---@type integer same as `lsqlite3.CHECKPOINT_RESTART`, but additionally
    --- truncates the log file before returning. See `db:wal_checkpoint`.
    CHECKPOINT_TRUNCATE = nil,

    -- Session / Changeset Constants

}

--- Opens (or creates if it does not exist) an SQLite database with name filename
--- and returns its handle as userdata (the returned object should be used for all
--- further method calls in connection with this specific database, see Database
--- methods). Example:
---
---     myDB = lsqlite3.open('MyDatabase.sqlite3')  -- open
---     -- do some database calls...
---     myDB:close()  -- close
---
--- In case of an error, the function returns `nil`, an error code and an error message.
---
--- Since `0.9.4`, there is a second optional `flags` argument to `lsqlite3.open`.
--- See https://www.sqlite.org/c3ref/open.html for an explanation of these flags and options.
---
---     local db = lsqlite3.open('foo.db', lsqlite3.OPEN_READWRITE + lsqlite3.OPEN_CREATE + lsqlite3.OPEN_SHAREDCACHE)
---
---@param filename string
---@param flags? integer defaults to `lsqlite3.OPEN_READWRITE + lsqlite3.OPEN_CREATE`
---@return lsqlite3.Database|nil db
---@return integer? errorcode
---@return string? errormsg
---@nodiscard
function lsqlite3.open(filename, flags) end

--- Opens an SQLite database in memory and returns its handle as userdata. In case
--- of an error, the function returns `nil`, an error code and an error message.
--- (In-memory databases are volatile as they are never stored on disk.)
---@return lsqlite3.Database|nil db
---@return integer? errorcode
---@return string? errormsg
---@nodiscard
function lsqlite3.open_memory() end

---@return string version lsqlite3 library version information, in the form 'x.y[.z]'.
---@nodiscard
function lsqlite3.lversion() end

---@return string version SQLite version information, in the form 'x.y[.z[.p]]'.
---@nodiscard
function lsqlite3.version() end

--- Sets global SQLite3 library configuration options.
---
--- `option` may be one of:
---
--- - `lsqlite3.CONFIG_SINGLETHREAD`, `lsqlite3.CONFIG_MULTITHREAD`, or
---   `lsqlite3.CONFIG_SERIALIZED`: selects the global threading mode.
---   Returns `lsqlite3.OK` on success, or `nil` plus a numerical error
---   code on failure.
--- - `lsqlite3.CONFIG_LOG`: installs a Lua callback that is invoked as
---   `func(udata, errcode, message)` for every SQLite3 log event, or
---   removes the current callback when `func` is `nil`. Returns
---   `lsqlite3.OK` followed by the previously installed callback and its
---   user data.
---@param option integer
---@param func function? callback for `lsqlite3.CONFIG_LOG`, or `nil` to remove it
---@param udata any? user data passed to the log callback
---@return integer|nil rc, function? prev_func, any prev_udata
---@return integer? errorcode
function lsqlite3.config(option, func, udata) end

---@class lsqlite3.Context: userdata
--- A callback context is available as a parameter inside the callback functions
--- `db:create_aggregate()` and `db:create_function()`. It can be used to get
--- further information about the state of a query.

---@return any udata the user-definable data field for callback funtions.
---@nodiscard
function lsqlite3.Context:get_aggregate_data() end

--- Set the user-definable data field for callback funtions to `udata`.
function lsqlite3.Context:set_aggregate_data(udata) end

--- Sets the result of a callback function to `res`. The type of the result
--- depends on the type of `res` and is either a number or a string or `nil`.
--- All other values will raise an error message.
---@param res string|number?
function lsqlite3.Context:result(res) end

--- Sets the result of a callback function to the binary string in blob.
---@param blob string
function lsqlite3.Context:result_blob(blob) end

--- Sets the result of a callback function to the value number.
---@param double number
function lsqlite3.Context:result_double(double) end

--- Sets the result of a callback function to the value number. Alias for
--- `lsqlite3.Context:result_double()`.
---@param double number
function lsqlite3.Context:result_number(double) end

--- Sets the result of a callback function to the error value in `err`.
function lsqlite3.Context:result_error(err) end

--- Sets the result of a callback function to the integer `number`
---@param number integer
function lsqlite3.Context:result_int(number) end

--- Sets the result of a callback function to `nil`.
function lsqlite3.Context:result_null() end

--- Sets the result of a callback function to the string in `str`.
---@param str string
function lsqlite3.Context:result_text(str) end

--- Returns the userdata parameter given in the call to install the callback
--- function (see db:create_aggregate() and db:create_function() for details).
---@return any
function lsqlite3.Context:user_data() end

---@class lsqlite3.Database: userdata
--- After opening a database with `lsqlite3.open()` or `lsqlite3.open_memory()`
--- the returned database object should be used for all further method calls in
--- connection with that database.

--- Sets or removes a busy handler for a database.
---@generic Udata
---@param func fun(udata: Udata, tries: integer)? is either a Lua function that implements the busy handler or `nil` to remove a previously set handler. This function returns nothing.
---@param udata? Udata
--- The handler function is called with two parameters: `udata` and the number
--- of (re-)tries for a pending transaction. It should return `nil`, `false` or
--- `0` if the transaction is to be aborted. All other values will result in
--- another attempt to perform the transaction. (See the SQLite documentation
--- for important hints about writing busy handlers.)
function lsqlite3.Database:busy_handler(func, udata) end

--- Sets a busy handler that waits for `milliseconds` if a transaction cannot proceed.
--- Calling this function will remove any busy handler set by `db:busy_handler()`;
--- calling it with an argument less than or equal to `0` will turn off all busy handlers.
---@param milliseconds integer
function lsqlite3.Database:busy_timeout(milliseconds) end

---@return integer # the number of database rows that were changed (or inserted or deleted) by the most recent SQL statement.
---@nodiscard
--- Only changes that are directly specified by INSERT, UPDATE, or DELETE
--- statements are counted. Auxiliary changes caused by triggers are not
--- counted. Use `db:total_changes()` to find the total number of changes.
function lsqlite3.Database:changes() end

--- Closes a database. All SQL statements prepared using `db:prepare()` should
--- have been finalized before this function is called. The function returns
--- `lsqlite3.OK` on success or else a numerical error code.
---@return integer
function lsqlite3.Database:close() end

--- Finalizes all statements that have not been explicitly finalized. If
--- `temponly` is `true`, only internal, temporary statements are finalized.
---@param temponly? boolean
function lsqlite3.Database:close_vm(temponly) end

--- This function installs a `commit_hook` callback handler.
---@generic Udata
---@param func fun(udata: Udata) a Lua function that is invoked by SQLite3 whenever a transaction is committed. This callback receives one argument:
---@param udata Udata argument used when the callback was installed.
---
--- If `func` returns `false` or `nil` the COMMIT is allowed to proceed,
--- otherwise the COMMIT is converted to a ROLLBACK.
---
--- See: `db:rollback_hook` and `db:update_hook`
function lsqlite3.Database:commit_hook(func, udata) end

--- This function creates an aggregate callback function. Aggregates perform an
--- operation over all rows in a query.

---@param name string the name of the aggregate function as given in an SQL statement.
---@param nargs integer the number of arguments this call will provide
---@param step fun(ctx: lsqlite3.Context, ...: string|number|nil) the actual Lua function that gets called once for every row.
--- It should accept a function context (see Methods for callback contexts) plus
--- the same number of parameters as given in `nargs`.
---@param final fun(ctx: lsqlite3.Context) a function that is called once after all rows have been processed.
--- It receives one argument, the function context.
---@param userdata? any If provided, userdata can be any Lua value and would be returned by the `context:user_data()` method.
---
--- The function context can be used inside the two callback functions to
--- communicate with SQLite3. Here is a simple example:
---
---     db:exec[=[
---         CREATE TABLE numbers(num1,num2);
---         INSERT INTO numbers VALUES(1,11);
---         INSERT INTO numbers VALUES(2,22);
---         INSERT INTO numbers VALUES(3,33);
---     ]=]
---     local num_sum=0
---     local function oneRow(context, num)  -- add one column in all rows
---         num_sum = num_sum + num
---     end
---     local function afterLast(context)   -- return sum after last row has been processed
---         context:result_number(num_sum)
---         num_sum = 0
---     end
---     db:create_aggregate("do_the_sums", 1, oneRow, afterLast)
---     for sum in db:urows('SELECT do_the_sums(num1) FROM numbers') do print("Sum of col 1:",sum) end
---     for sum in db:urows('SELECT do_the_sums(num2) FROM numbers') do print("Sum of col 2:",sum) end
---
--- This prints:
---
---     Sum of col 1:   6
---     Sum of col 2:   66
---
---@return boolean success
function lsqlite3.Database:create_aggregate(name, nargs, step, final, userdata) end

--- This creates a collation callback. A collation callback is used to establish
--- a collation order, mostly for string comparisons and sorting purposes.
---@param name string the name of the collation to be created
---@param func fun(s1: string, s2: string): -1|0|1 a function that accepts two string arguments, compares them and returns `0` if both strings are identical, `-1` if the first argument is lower in the collation order than the second and `1` if the first argument is higher in the collation order than the second.
--- A simple example:
---
---    local function collate(s1,s2)
---      s1=s1:lower()
---      s2=s2:lower()
---      if s1==s2 then return 0
---      elseif s1<s2 then return -1
---      else return 1 end
---    end
---    db:exec[=[
---      CREATE TABLE test(id INTEGER PRIMARY KEY,content COLLATE CINSENS);
---      INSERT INTO test VALUES(NULL,'hello world');
---      INSERT INTO test VALUES(NULL,'Buenos dias');
---      INSERT INTO test VALUES(NULL,'HELLO WORLD');
---    ]=]
---    db:create_collation('CINSENS',collate)
---    for row in db:nrows('SELECT * FROM test') do
---      print(row.id, row.content)
---    end
---
function lsqlite3.Database:create_collation(name, func) end

--- This function creates a callback function. Callback function are called by
--- SQLite3 once for every row in a query.
---@param name string the name of the aggregate function as given in an SQL statement.
---@param nargs integer the number of arguments this call will provide
---@param func fun(ctx: lsqlite3.Context, ...) the actual Lua function that gets called once for every row.
--- It should accept a function context (see Methods for callback contexts) plus
--- the same number of parameters as given in `nargs`.
---@param userdata? any If provided, userdata can be any Lua value and would be returned by the `context:user_data()` method.
--- Here is an example:
---
---     db:exec'CREATE TABLE test(col1,col2,col3)'
---     db:exec'INSERT INTO test VALUES(1,2,4)'
---     db:exec'INSERT INTO test VALUES(2,4,9)'
---     db:exec'INSERT INTO test VALUES(3,6,16)'
---     db:create_function('sum_cols',3,function(ctx,a,b,c)
---       ctx:result_number(a+b+c)
---     end))
---     for col1,col2,col3,sum in db:urows('SELECT *,sum_cols(col1,col2,col3) FROM test') do
---       util.printf('%2i+%2i+%2i=%2i\n',col1,col2,col3,sum)
---     end
---
---@return boolean success
function lsqlite3.Database:create_function(name, nargs, func, userdata) end

---@return string? filename associated with database `name` of connection `db`.
---@nodiscard
---@param name string may be `"main"` for the main database file, or the name specified after the AS keyword in an ATTACH statement for an attached database.
--- If there is no attached database name on the database connection, then no value is
--- returned; if database name is a temporary or in-memory database, then an
--- empty string is returned.
function lsqlite3.Database:db_filename(name) end

--- Deserializes data from a string which was created by `db:serialize`.
---@param s string
function lsqlite3.Database:deserialize(s) end

---@return integer error the numerical result code (or extended result code) for the most recent failed call associated with database db.
---@nodiscard
function lsqlite3.Database:errcode() end

---@return string message an error message for the most recent failed call associated with database `db`.
---@nodiscard
function lsqlite3.Database:errmsg() end

---@generic Udata
---@param sql string
---@param func? fun(udata: Udata, cols: integer, values: string[], names: string[]): integer
---@param udata? Udata
function lsqlite3.Database:exec(sql, func, udata) end

--- This function causes any pending database operation to abort and return at
--- the next opportunity.
function lsqlite3.Database:interrupt() end

---@return boolean
---@nodiscard
function lsqlite3.Database:isopen() end

---@return integer rowid the most recent INSERT into the database. If no inserts have ever occurred, `0` is returned.
--- Each row in an SQLite table has a unique 64-bit signed integer key called
--- the rowid. This id is always available as an undeclared column named ROWID,
--- OID, or _ROWID_. If the table has a column of type INTEGER PRIMARY KEY then
--- that column is another alias for the rowid.
---@nodiscard
---
--- If an INSERT occurs within a trigger, then the rowid of the inserted row is
--- returned as long as the trigger is running. Once the trigger terminates, the
--- value returned reverts to the last value inserted before the trigger fired.
function lsqlite3.Database:last_insert_rowid() end

--- Creates an iterator that returns the successive rows selected by the
--- SQL statement given in string `sql`. Each call to the iterator
--- returns a table in which the named fields correspond to the columns
--- in the database. Here is an example:
---
---     db:exec[=[
---         CREATE TABLE numbers(num1,num2);
---         INSERT INTO numbers VALUES(1,11);
---         INSERT INTO numbers VALUES(2,22);
---         INSERT INTO numbers VALUES(3,33);
---     ]=]
---     for a in db:nrows('SELECT * FROM numbers') do table.print(a) end
---
--- This script prints:
---
---     num2: 11
---     num1: 1
---     num2: 22
---     num1: 2
---     num2: 33
---     num1: 3
---
---@param sql string
---@return fun(vm: lsqlite3.VM) iterator, lsqlite3.VM vm
---@nodiscard
function lsqlite3.Database:nrows(sql) end

--- This function compiles the SQL statement in string sql into an internal
--- representation and returns this as userdata. The returned object should be
--- used for all further method calls in connection with this specific SQL
--- statement.
--- See https://lua.sqlite.org/home/doc/tip/doc/lsqlite3.wiki#methods_for_prepared_statements for details.
---@param sql string
---@return lsqlite3.Statement
---@nodiscard
function lsqlite3.Database:prepare(sql) end

--- Returns `true` if the database `name` of connection `db` is read-only,
--- `false` if it is read/write. Returns `nil` plus an error message if
--- `name` is not the name of a database on connection `db`.
---@param name string? defaults to `"main"`
---@return boolean|nil
---@return string? error
---@nodiscard
function lsqlite3.Database:readonly(name) end

--- This function installs a rollback_hook callback handler.
--- See: `db:commit_hook` and `db:update_hook`
---@generic Udata
---@param func fun(udata: Udata) a Lua function that is invoked by SQLite3 whenever a transaction is rolled back. This callback receives one argument: the `udata` argument used when the callback was installed.
---@param udata Udata
function lsqlite3.Database:rollback_hook(func, udata) end

--- Creates an iterator that returns the successive rows selected by the SQL
--- statement given in string `sql`. Each call to the iterator returns a table in
--- which the numerical indices 1 to n correspond to the selected columns 1 to n in
--- the database. Here is an example:
---
---     db:exec[=[
---         CREATE TABLE numbers(num1,num2);
---         INSERT INTO numbers VALUES(1,11);
---         INSERT INTO numbers VALUES(2,22);
---         INSERT INTO numbers VALUES(3,33);
---     ]=]
---     for a in db:rows('SELECT * FROM numbers') do table.print(a) end
---
--- This script prints:
---
---     1: 1
---     2: 11
---     1: 2
---     2: 22
---     1: 3
---     2: 33
---
---@param sql string
---@return fun(vm: lsqlite3.VM): (string|number|nil)[]? iterator, lsqlite3.VM vm
---@nodiscard
function lsqlite3.Database:rows(sql) end

--- Serialize a database to be restored later with `Database:deserialize`.
---@return string? -- `nil` if the database has no tables
---@nodiscard
function lsqlite3.Database:serialize() end

---@return integer # the number of database rows that have been modified by INSERT, UPDATE or DELETE statements since the database was opened.
--- This includes UPDATE, INSERT and DELETE statements executed as part of trigger
--- programs. All changes are counted as soon as the statement that produces them
--- is completed by calling either `stmt:reset()` or `stmt:finalize()`.
---@nodiscard
function lsqlite3.Database:total_changes() end

--- This function installs an update_hook Data Change Notification
--- Callback handler. See: `db:commit_hook` and `db:rollback_hook`
---
---@generic Udata
---@param func fun(udata: Udata, op: integer, db: lsqlite3.Database, name: string, rowid: integer) a Lua function that is invoked by SQLite3
--- whenever a row is updated, inserted or deleted. This callback
--- receives five arguments: the first is the `udata` argument used
--- when the callback was installed; the second is an integer
--- indicating the operation that caused the callback to be invoked
--- (one of `lsqlite3.UPDATE`, `lsqlite3.INSERT`, or
--- `lsqlite3.DELETE`). The third and fourth arguments are the
--- database and table name containing the affected row. The final
--- callback parameter is the rowid of the row. In the case of an
--- update, this is the rowid after the update takes place.
---@param udata Udata
function lsqlite3.Database:update_hook(func, udata) end

--- Creates an iterator that returns the successive rows selected by the SQL
--- statement given in string sql. Each call to the iterator returns the values
--- that correspond to the columns in the currently selected row.
--- Here is an example:
---
---     db:exec[=[
---         CREATE TABLE numbers(num1,num2);
---         INSERT INTO numbers VALUES(1,11);
---         INSERT INTO numbers VALUES(2,22);
---         INSERT INTO numbers VALUES(3,33);
---     ]=]
---     for num1,num2 in db:urows('SELECT * FROM numbers') do print(num1,num2) end
---
--- This script prints:
---
---     1       11
---     2       22
---     3       33
---
---@param sql string
---@return fun(vm: lsqlite3.VM): ...: string|number|nil iterator, lsqlite3.VM vm
---@nodiscard
function lsqlite3.Database:urows(sql) end

---@param mode integer?
---@param name string?
---@return integer|nil nlog, integer nckpt
---@return integer? errno
function lsqlite3.Database:wal_checkpoint(mode, name) end

---@generic Udata
---@param func (fun(udata: Udata, db: lsqlite3.Database, name: string, page_count: integer): integer)?
---@param udata Udata?
function lsqlite3.Database:wal_hook(func, udata) end

---@class lsqlite3.Statement: userdata
--- After creating a prepared statement with `db:prepare()` the returned statement
--- object should be used for all further calls in connection with that statement.

--- Binds `value` to statement parameter `n`. If the type of `value` is
--- string it is bound as text. If the type of value is number, it is
--- bound as an integer or double depending on its subtype using
--- `lua_isinteger`. If `value` is a boolean then it is bound as `0` for
--- `false` or `1` for `true`. If `value` is `nil` or missing, any
--- previous binding is removed.
---
---@return integer `lsqlite3.OK` on success or else a numerical error code,
---@param n integer
---@param value string|number|boolean|nil
function lsqlite3.Statement:bind(n, value) end

--- Binds string `blob` (which can be a binary string) as a blob to
--- statement parameter `n`.
---
---@param n integer
---@param blob string
---@return integer `lsqlite3.OK` on success or else a numerical error code,
function lsqlite3.Statement:bind_blob(n, blob) end

--- Binds the values in `nametable` to statement parameters. If the
--- statement parameters are named (i.e., of the form `":AAA"` or
--- `"$AAA"`) then this function looks for appropriately named fields in
--- nametable; if the statement parameters are not named, it looks for
--- numerical fields 1 to the number of statement parameters.
---
---@return integer `lsqlite3.OK` on success or else a numerical error code,
---@param nametable table
---@return integer
function lsqlite3.Statement:bind_names(nametable) end

---@return any # the largest statement parameter index in prepared the statement.
---@nodiscard
--- When the statement parameters are of the forms `":AAA"` or `"?"`, then they are
--- assigned sequentially increasing numbers beginning with one, so the value
--- returned is the number of parameters. However if the same statement parameter
--- name is used multiple times, each occurrence is given the same number, so the
--- value returned is the number of unique statement parameter names.
---
--- If statement parameters of the form `"?NNN"` are used (where `NNN` is an
--- integer) then there might be gaps in the numbering and the value returned by
--- this interface is the index of the statement parameter with the largest index
--- value.
function lsqlite3.Statement:bind_parameter_count() end

---@param n integer
---@return string? -- the name of the n-th parameter in prepared statement.
--- Statement parameters of the form `":AAA"` or `"@AAA"` or `"$VVV"` have a name
--- which is the string `":AAA"` or `"@AAA"` or `"$VVV"`. In other words, the
--- initial `":"` or `"$"` or `"@"` is included as part of the name. Parameters of
--- the form `"?"` or `"?NNN"` have no name. The first bound parameter has an index
--- of `1`. If the value `n` is out of range or if the `n`-th parameter is nameless,
--- then `nil` is returned.
function lsqlite3.Statement:bind_parameter_name(n) end

--- Binds the given values to statement parameters.
---@param ... string|number|nil
---@return integer `lsqlite3.OK` on success or else a numerical error code,
function lsqlite3.Statement:bind_values(...) end

---@return integer cols the number of columns in the result set returned by the statement or `0` if the statement does not return data (for example an `UPDATE`).
---@nodiscard
function lsqlite3.Statement:columns() end

--- This function frees the prepared statement.
---@return integer # If the statement was executed successfully, or not executed at all, then `lsqlite3.OK` is returned. If execution of the statement failed then an error code is returned.
function lsqlite3.Statement:finalize() end

---@return any # the name of column n in the result set of statement. (The left-most column is number 0.)
---@nodiscard
function lsqlite3.Statement:get_name(n) end

---@return table # the names and types of all columns in the result set of the statement.
---@nodiscard
function lsqlite3.Statement:get_named_types() end

--- Alias for `lsqlite3.Statement:get_named_types()`.
---@return table # the names and types of all columns in the result set of the statement.
---@nodiscard
function lsqlite3.Statement:type() end

---@return table # the names and values of all columns in the current result row of a query.
---@nodiscard
function lsqlite3.Statement:get_named_values() end

--- Alias for `lsqlite3.Statement:get_named_values()`.
---@return table # the names and values of all columns in the current result row of a query.
---@nodiscard
function lsqlite3.Statement:data() end

---@return string[] # the names of all columns in the result set returned by the statement.
---@nodiscard
function lsqlite3.Statement:get_names() end

--- Alias for `lsqlite3.Statement:get_names()`.
---@return string[] # the names of all columns in the result set returned by the statement.
---@nodiscard
function lsqlite3.Statement:inames() end

---@return any # the type of column n in the result set of statement. (The left-most column is number 0.)
---@nodiscard
---@nodiscard
function lsqlite3.Statement:get_type(n) end

---@return any[] # the types of all columns in the result set returned by the statement.
---@nodiscard
function lsqlite3.Statement:get_types() end

--- Alias for `lsqlite3.Statement:get_types()`.
---@return any[] # the types of all columns in the result set returned by the statement.
---@nodiscard
function lsqlite3.Statement:itypes() end

---@return any[] unames the names of all columns in the result set returned by the statement.
---@nodiscard
function lsqlite3.Statement:get_unames() end

---@return any[] utypes the types of all columns in the result set returned by the statement.
---@nodiscard
function lsqlite3.Statement:get_utypes() end

---@return any[] uvalues the values of all columns in the current result row of a query.
---@nodiscard
function lsqlite3.Statement:get_uvalues() end

---@param n any
---@return any value the value of column n in the result set of the statement. (The left-most column is number 0.)
---@nodiscard
function lsqlite3.Statement:get_value(n) end

---@return any[] values the values of all columns in the result set returned by the statement.
---@nodiscard
function lsqlite3.Statement:get_values() end

--- Alias for `lsqlite3.Statement:get_values()`.
---@return any[] values the values of all columns in the result set returned by the statement.
---@nodiscard
function lsqlite3.Statement:idata() end

---@return boolean isopen `true` if `stmt` has not yet been finalized, `false` otherwise.
---@nodiscard
function lsqlite3.Statement:isopen() end

---@return function iterator iterates over the names and values of the result set of the statement. Each iteration returns a table with the names and values for the current row. This is the prepared statement equivalent of `db:nrows()`.
---@nodiscard
function lsqlite3.Statement:nrows() end

--- Returns `true` if the prepared statement makes no direct changes to
--- the content of the database file, `false` otherwise.
---@return boolean
---@nodiscard
function lsqlite3.Statement:readonly() end

--- This function resets the SQL statement, so that it is ready to be re-executed. Any statement variables that had values bound to them using the `stmt:bind*()` functions retain their values.
function lsqlite3.Statement:reset() end

---@return function iterator iterates over the values of the result set of statement `stmt`. Each iteration returns an array with the values for the current row. This is the prepared statement equivalent of `db:rows()`.
---@nodiscard
function lsqlite3.Statement:rows() end

--- This function must be called to evaluate the (next iteration of the) prepared statement.
---@return integer # one of the following values:
--- - `lsqlite3.BUSY`: the engine was unable to acquire the locks needed.
---   If the statement is a COMMIT or occurs outside of an explicit transaction,
---   then you can retry the statement. If the statement is not a COMMIT and occurs
---   within a explicit transaction then you should rollback the transaction before
---   continuing.
--- - `lsqlite3.DONE`: the statement has finished executing successfully.
---   `stmt:step()` should not be called again on this statement without first
---   calling `stmt:reset()` to reset the virtual machine back to the initial state.
--- - `lsqlite3.ROW`: this is returned each time a new row of data is ready for
---    processing by the caller. The values may be accessed using the column access
---    functions. `stmt:step()` can be called again to retrieve the next
---    row of data.
--- - `lsqlite3.ERROR`: a run-time error (such as a constraint violation) has
---    occurred. `stmt:step()` should not be called again. More
---    information may be found by calling `db:errmsg()`. A more specific error
---    code (can be obtained by calling `stmt:reset()`.
--- - `lsqlite3.MISUSE`: the function was called inappropriately, perhaps because
---    the statement has already been finalized or a previous call to `stmt:step()`
---    has returned `lsqlite3.ERROR` or `lsqlite3.DONE`.
---@nodiscard
function lsqlite3.Statement:step() end

---@return function iterator iterates over the values of the result set of the statement.
--- Each iteration returns the values for the current row. This is the prepared
--- statement equivalent of `db:urows()`.
---@nodiscard
function lsqlite3.Statement:urows() end

---@return any row_id the rowid of the most recent `INSERT` into the database corresponding to this statement. See `db:last_insert_rowid()`.
---@nodiscard
function lsqlite3.Statement:last_insert_rowid() end

---@class lsqlite3.VM: userdata

---@param index integer
---@param value string|number|boolean|nil
---@return integer errno
function lsqlite3.VM:bind(index, value) end

---@param index integer
---@param value string
---@return integer errno
function lsqlite3.VM:bind_blob(index, value) end

---@param names string[]
---@return integer errno
function lsqlite3.VM:bind_names(names) end

---@return integer parameter_count
---@nodiscard
function lsqlite3.VM:bind_parameter_count() end

---@param index number
---@return string parameter_name
---@nodiscard
function lsqlite3.VM:bind_parameter_name(index) end

---@param ... string|number|nil
---@return integer errno
function lsqlite3.VM:bind_values(...) end

---@return integer columns the column count
---@nodiscard
function lsqlite3.VM:columns() end

---@return integer errno
function lsqlite3.VM:finalize() end

---@param index integer
---@return string name
---@nodiscard
function lsqlite3.VM:get_name(index) end

---@return string[]
---@nodiscard
function lsqlite3.VM:get_named_types() end

--- Alias for `lsqlite3.VM:get_named_types()`.
---@return string[]
---@nodiscard
function lsqlite3.VM:type() end

---@return (string|number?)[]
---@nodiscard
function lsqlite3.VM:get_named_values() end

--- Alias for `lsqlite3.VM:get_named_values()`.
---@return (string|number?)[]
---@nodiscard
function lsqlite3.VM:data() end

---@return string[]
---@nodiscard
function lsqlite3.VM:get_names() end

--- Alias for `lsqlite3.VM:get_names()`.
---@return string[]
---@nodiscard
function lsqlite3.VM:inames() end

---@param index integer
---@return string
---@nodiscard
function lsqlite3.VM:get_type(index) end

---@return string[]
---@nodiscard
function lsqlite3.VM:get_types() end

--- Alias for `lsqlite3.VM:get_types()`.
---@return string[]
---@nodiscard
function lsqlite3.VM:itypes() end

---@return string ...
---@nodiscard
function lsqlite3.VM:get_unames() end

---@return string ...
---@nodiscard
function lsqlite3.VM:get_utypes() end

---@return string|number? ...
---@nodiscard
function lsqlite3.VM:get_uvalues() end

---@param index integer
---@return string|number?
---@nodiscard
function lsqlite3.VM:get_value(index) end

---@return (string|number?)[]
---@nodiscard
function lsqlite3.VM:get_values() end

--- Alias for `lsqlite3.VM:get_values()`.
---@return (string|number?)[]
---@nodiscard
function lsqlite3.VM:idata() end

---@return boolean
---@nodiscard
function lsqlite3.VM:isopen() end

---@return integer rowid
---@nodiscard
function lsqlite3.VM:last_insert_rowid() end

---@param sql string
---@return fun(self: lsqlite3.VM): { [string]: string|number } iterator, self
---@nodiscard
function lsqlite3.VM:nrows(sql) end

--- Returns `true` if the prepared statement makes no direct changes to
--- the content of the database file, `false` otherwise.
---@return boolean
---@nodiscard
function lsqlite3.VM:readonly() end

---@return integer errno
function lsqlite3.VM:reset() end

---@param sql string
---@return fun(self: lsqlite3.VM): (string|number|nil)[] iterator, self
---@nodiscard
function lsqlite3.VM:rows(sql) end

---@return integer
function lsqlite3.VM:step() end

---@param sql string
---@return fun(self: lsqlite3.VM): ...: string|number|nil iterator, self
---@nodiscard
function lsqlite3.VM:urows(sql) end

--- This module exposes an API for POSIX regular expressions which enable you to
--- validate input, search for substrings, extract pieces of strings, etc.
--- Here's a usage example:
---
---     -- Example IPv4 Address Regular Expression (see also ParseIp)
---     p = assert(re.compile([[^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$]]))
---     local m, caps = p:search(s)
---     if m then
---       print("ok", tonumber(caps[1]), tonumber(caps[2]),
---             tonumber(caps[3]), tonumber(caps[4]))
---     else
---       print("not ok")
---     end
re = {
    --- No match
    NOMATCH = 1,
    --- Invalid regex
    BADPAT = 2,
    --- Unknown collating element
    ECOLLATE = 3,
    --- Unknown character class name
    ECTYPE = 4,
    --- Trailing backslash
    EESCAPE = 5,
    --- Invalid back reference
    ESUBREG = 6,
    --- Missing ]
    EBRACK = 7,
    --- Missing )
    EPAREN = 8,
    --- Missing }
    EBRACE = 9,
    --- Invalid contents of {}
    BADBR = 10,
    --- Invalid character range.
    ERANGE = 11,
    --- Out of memory
    ESPACE = 12,
    --- Repetition not preceded by valid expression
    BADRPT = 13,

    --- Use this flag if you prefer the default POSIX regex syntax.
    --- We use extended regex notation by default. For example, an extended regular
    --- expression for matching an IP address might look like
    --- `([0-9]*)\.([0-9]*)\.([0-9]*)\.([0-9]*)` whereas with basic syntax it would
    --- look like `\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\)`.
    --- This flag may only be used with `re.compile` and `re.search`.
    BASIC = 1,
    --- Use this flag if you prefer the default POSIX regex syntax. We use extended
    ---  regex notation by default. For example, an extended regular expression for
    --- matching an IP address might look like `([0-9]*)\.([0-9]*)\.([0-9]*)\.([0-9]*)`
    --- whereas with basic syntax it would look like `\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\)`.
    --- This flag may only be used with `re.compile` and `re.search`.
    ICASE = 2,
    --- Use this flag to change the handling of NEWLINE (\x0a) characters. When this
    --- flag is set, (1) a NEWLINE shall not be matched by a "." or any form of a
    --- non-matching list, (2) a "^" shall match the zero-length string immediately
    --- after a NEWLINE (regardless of `re.NOTBOL`), and (3) a "$" shall match the
    --- zero-length string immediately before a NEWLINE (regardless of `re.NOTEOL`).
    NEWLINE = 4,
    --- Causes `re.search` to only report success and failure. This is reported via
    --- the API by returning empty string for success. This flag may only be used
    ---` with `re.compile` and `re.search`.
    NOSUB = 8,
    --- The first character of the string pointed to by string is not the beginning
    --- of the line. This flag may only be used with `re.search` and `regex_t*:search`.
    NOTBOL = 0x0100,
    --- The last character of the string pointed to by string is not the end of the
    --- line. This flag may only be used with `re.search` and `regex_t*:search`.
    NOTEOL = 0x0200,
}

---@class re.Regex: userdata
re.Regex = {}

--- Executes precompiled regular expression.
---
--- On a match, returns the whole matched substring plus a table of the
--- parenthesized capture groups (an empty table when the pattern has no groups).
--- A no-match is not an error: it returns a single bare `nil`, so the idiomatic
--- `if match then` works. Only a genuine regex engine failure (e.g. running out
--- of memory) returns `nil, err`. Flags may contain `re.NOTBOL` or `re.NOTEOL`
--- to indicate whether or not text should be considered at the start and/or end
--- of a line.
---
---@param str string
---@param flags? integer defaults to zero and may have any of:
---
--- - `re.NOTBOL`
--- - `re.NOTEOL`
---
--- This has an O(𝑛) cost.
---@return string|nil match the whole matched substring
---@return {string} captures the parenthesized capture groups, in order
---@return string? error
---@nodiscard
function re.Regex:search(str, flags) end

--- Searches for regular expression match in text.
---
--- This is a shorthand notation roughly equivalent to:
---
---     local preg = assert(re.compile(regex))
---     local match, captures = preg:search(text)
---
--- On a match, returns the whole matched substring plus a table of the
--- parenthesized capture groups. A no-match returns a bare `nil`. A bad pattern
--- (compile failure) or a regex engine failure returns `nil, err`.
---
---@param regex string
---@param text string
---@param flags integer? defaults to zero and may have any of:
---
--- - `re.BASIC`
--- - `re.ICASE`
--- - `re.NEWLINE`
--- - `re.NOSUB`
--- - `re.NOTBOL`
--- - `re.NOTEOL`
---
--- This has exponential complexity. Please use `re.compile()` to compile your regular expressions once from `/.init.lua`. This API exists for convenience. This isn't recommended for prod.
---
--- This uses POSIX extended syntax by default.
---@return string|nil match the whole matched substring
---@return {string} captures the parenthesized capture groups, in order
---@return string? error
---@nodiscard
function re.search(regex, text, flags) end

--- Compiles regular expression.
---
---@param regex string
---@param flags integer? defaults to zero and may have any of:
---
--- - `re.BASIC`
--- - `re.ICASE`
--- - `re.NEWLINE`
--- - `re.NOSUB`
---
--- This has an O(2^𝑛) cost. Consider compiling regular expressions once
--- from your `/.init.lua` file.
---
--- If regex is an untrusted user value, then `unix.setrlimit` should be
--- used to impose cpu and memory quotas for security.
---
--- This uses POSIX extended syntax by default.
---@return re.Regex|nil
---@return string? error
---@nodiscard
function re.compile(regex, flags) end

--- The getopt module provides command-line argument parsing using getopt_long.
---
--- This wraps the standard GNU getopt_long(3) function for parsing command-line
--- options with both short (-h) and long (--help) option support.
---
--- NOTE: This module uses process-global getopt state. `getopt.parse` consumes
--- the whole argument vector in a single call, so back-to-back calls are
--- independent, but do not call it concurrently from multiple threads.
getopt = {}

---@class getopt.Option
--- A single recognized option and its argument (nil when the option takes
--- none). For a long option that has a short equivalent, `opt` is that short
--- letter; for a long-only option, `opt` is the long name.
---@field opt string
---@field arg string?

---@class getopt.Result
--- The outcome of a single `getopt.parse` call.
---@field opts getopt.Option[] Recognized options, in the order encountered
---@field args string[] Non-option (positional) arguments
---@field unknown string[] Unrecognized options, each including its dashes
---@field missing string[] Options that required an argument but got none

--- Parse a command-line argument vector in one shot.
---
--- The optstring uses standard getopt format:
--- - A letter means that option takes no argument
--- - A letter followed by : means it requires an argument
--- - A letter followed by :: means it takes an optional argument
---
--- The longopts table contains entries like {"name", "has_arg", "short"}:
--- - name: the long option name (e.g., "help" for --help)
--- - has_arg: "none", "required", or "optional"
--- - short: the equivalent short option character (e.g., "h"), or nil
---
--- The result separates four outcomes. `opts` lists the recognized options in
--- order, each as a {opt, arg} pair. `args` holds the leftover positional
--- arguments. `unknown` holds unrecognized options (always spelled with their
--- dashes, e.g. "-x" or "--nope"). `missing` holds the options that required an
--- argument but were given none (named without dashes, e.g. "o"); this is kept
--- distinct from `unknown` via getopt's leading-`:` protocol.
---
--- Example - Basic usage:
---
---     local r = getopt.parse(arg, "hvo:", {
---       {"help",    "none",     "h"},
---       {"verbose", "none",     "v"},
---       {"output",  "required", "o"},
---     })
---     for _, o in ipairs(r.opts) do
---       if o.opt == "h" then
---         print("Usage: ...")
---       elseif o.opt == "v" then
---         verbose = true
---       elseif o.opt == "o" then
---         output = o.arg
---       end
---     end
---     -- r.args     -- non-option arguments
---     -- r.unknown  -- unrecognized options, with dashes
---     -- r.missing  -- options missing a required argument
---
--- Example - Handling repeated options:
---
---     local r = getopt.parse(arg, "e:")
---     local excludes = {}
---     for _, o in ipairs(r.opts) do
---       if o.opt == "e" then
---         table.insert(excludes, o.arg)
---       end
---     end
---     -- Now excludes contains all -e values: {"foo", "bar", "spam"}
---
---@param args string[] Command-line arguments (typically `arg`)
---@param optstring string Short options string (e.g., "hvo:")
---@param longopts? table[] Long option definitions: {{name, has_arg, short}, ...}
---@return getopt.Result|nil result
---@return string? error
function getopt.parse(args, optstring, longopts) end

--- The path module may be used to manipulate unix paths.
---
--- Note that we use unix paths on Windows. For example, if you have a
--- path like `C:\foo\bar` then it should be `/c/foo/bar` with redbean.
--- It should also be noted the unix module is more permissive when
--- using Windows paths, where translation to win32 is very light.
path = {}

--- Strips final component of path, e.g.
---
---     path      │ dirname
---     ───────────────────
---     .         │ .
---     ..        │ .
---     /         │ /
---     usr       │ .
---     /usr/     │ /
---     /usr/lib  │ /usr
---     /usr/lib/ │ /usr
---@param str string
---@return string
---@nodiscard
function path.dirname(str) end

--- Returns final component of path, e.g.
---
---     path      │ basename
---     ─────────────────────
---     .         │ .
---     ..        │ ..
---     /         │ /
---     usr       │ usr
---     /usr/     │ usr
---     /usr/lib  │ lib
---     /usr/lib/ │ lib
---@param str string
---@return string
---@nodiscard
function path.basename(str) end

---Concatenates path components, e.g.
---
---     x         │ y        │ joined
---     ─────────────────────────────────
---     /         │ /        │ /
---     /usr      │ lib      │ /usr/lib
---     /usr/     │ lib      │ /usr/lib
---     /usr/lib  │ /lib     │ /lib
---
--- You may specify 1+ arguments.
---
--- Specifying no arguments will raise an error. If `nil` arguments are specified,
--- then they're skipped over. If exclusively `nil` arguments are passed, then `nil`
--- is returned. Empty strings behave similarly to `nil`, but unlike `nil` may
--- coerce a trailing slash.
---@param str string?
---@param ... string?
---@return string?
---@nodiscard
function path.join(str, ...) end

---Returns `true` if path exists.
---This function is inclusive of regular files, directories, and special files.
--- Symbolic links are followed are resolved. On error, `false` is returned.
---@param path string
---@return boolean
---@nodiscard
function path.exists(path) end

---Returns `true` if path exists and is regular file.
---Symbolic links are not followed. On error, `false` is returned.
---@param path string
---@return boolean
---@nodiscard
function path.isfile(path) end

---Returns `true` if path exists and is directory.
---Symbolic links are not followed. On error, `false` is returned.
---@param path string
---@return boolean
---@nodiscard
function path.isdir(path) end

---Returns `true` if path exists and is symbolic link.
---Symbolic links are not followed. On error, `false` is returned.
---@param path string
---@return boolean
---@nodiscard
function path.islink(path) end

--- This module implements a password hashing algorithm based on blake2b that won
--- the Password Hashing Competition.
---
--- It can be used to securely store user passwords in your SQLite database, in a
--- way that destroys the password, but can be verified by regenerating the hash
--- again the next time the user logs in. Destroying the password is important,
--- since if your database is compromised, the bad guys won't be able to use
--- rainbow tables to recover the plain text of the passwords.
---
--- Argon2 achieves this security by being expensive to compute. Care should be
--- taken in choosing parameters, since an HTTP endpoint that uses Argon2 can just
--- as easily become a denial of service vector. For example, you may want to
--- consider throttling your login endpoint.
argon2 = {}

---@class argon2.Config
---@field m_cost integer? the memory hardness in kibibytes, which defaults to 4096 (4 mibibytes). It's recommended that this be tuned upwards.
---@field t_cost integer? the number of iterations, which defaults to `3`.
---@field parallelism integer? the parallelism factor, which defaults to `1`.
---@field hash_len integer? the number of desired bytes in hash output, which defaults to 32.
---@field variant string? the Argon2 variant: `"argon2id"` blend of other two methods [default], `"argon2i"` maximize resistance to side-channel attacks, or `"argon2d"` maximize resistance to gpu cracking attacks

--- Hashes password.
---
--- This is consistent with the README of the reference implementation:
---
---     >: assert(argon2.hash_encoded("password", "somesalt", {
---         variant = "argon2i",
---         hash_len = 24,
---         t_cost = 2,
---     }))
---
---
--- `salt` is a nonce value used to hash the string. It is optional: when it is
--- `nil` or omitted, 16 random bytes are generated with a CSPRNG.
---
--- `config.m_cost` is the memory hardness in kibibytes, which defaults
--- to 4096 (4 mibibytes). It's recommended that this be tuned upwards.
---
--- `config.t_cost` is the number of iterations, which defaults to 3.
---
--- `config.parallelism` is the parallelism factor, which defaults to 1.
---
--- `config.hash_len` is the number of desired bytes in hash output,
--- which defaults to 32.
---
--- `config.variant` may be:
---
--- - `"argon2id"` blend of other two methods [default]
--- - `"argon2i"` maximize resistance to side-channel attacks
--- - `"argon2d"` maximize resistance to gpu cracking attacks
---
---@param pass string
---@param salt string? optional; a random 16-byte salt is generated when omitted
---@param config argon2.Config?
---@return string|nil ascii
---@return string? error
---@nodiscard
function argon2.hash_encoded(pass, salt, config) end

--- Verifies a password against an encoded hash, e.g.
---
---     >: argon2.verify(encoded, "password")
---     true
---
--- Returns `true` when the password matches. A plain mismatch returns
--- `false` (with no error). A malformed `encoded` string returns
--- `false, err`.
---
---@param encoded string
---@param pass string
---@return boolean ok
---@return string? err set only when `encoded` is malformed
---@nodiscard
function argon2.verify(encoded, pass) end

--- ### ZIP
---
--- The zip module provides functionality for creating and reading ZIP archives.
--- This module is available as `require("cosmo.zip")`.
---
--- Example - Creating a ZIP archive:
---
---     local zip = require("cosmo.zip")
---     local archive = assert(zip.open("output.zip", "w"))
---     archive:add("hello.txt", "Hello, World!")
---     archive:add("data/config.json", '{"key": "value"}')
---     archive:close()
---
--- Example - Reading a ZIP archive:
---
---     local zip = require("cosmo.zip")
---     local archive = assert(zip.open("input.zip", "r"))
---     local files = archive:list()
---     for _, entry in ipairs(files) do
---       local content = archive:read(entry.name)
---       print(entry.name, entry.size, #content)
---     end
---     archive:close()
---
--- Example - Reading from in-memory data:
---
---     local zip = require("cosmo.zip")
---     local archive = assert(zip.from(Slurp("input.zip")))
---     print(archive:read("hello.txt"))
---     archive:close()
---
zip = {}

---@class zip.OpenOptions
---@field level? integer Compression level 0-9 (for "w" and "a" modes)
---@field max_file_size? integer Maximum file size limit in bytes

--- Opens a ZIP archive for reading, writing, or appending.
---
--- The first argument can be a file path string or a file descriptor integer.
---
---@param path string|integer Path to the ZIP file, or file descriptor
---@param mode? string Open mode: `"r"` for reading (default), `"w"` for writing, `"a"` for appending
---@param options? zip.OpenOptions Optional settings
---@return zip.Reader|zip.Writer|zip.Appender? archive Archive object on success
---@return string? error Error message on failure
---@nodiscard
---@overload fun(path: string|integer, mode: "r", options?: zip.OpenOptions): zip.Reader?, string?
---@overload fun(path: string|integer, mode: "w", options?: zip.OpenOptions): zip.Writer?, string?
---@overload fun(path: string|integer, mode: "a", options?: zip.OpenOptions): zip.Appender?, string?
function zip.open(path, mode, options) end

--- Opens a ZIP archive from in-memory data for reading.
---
---@param data string ZIP file contents as a string
---@param options? zip.OpenOptions Optional settings (only max_file_size applies)
---@return zip.Reader? reader ZIP reader object on success
---@return string? error Error message on failure
---@nodiscard
function zip.from(data, options) end

--- Creates a new ZIP archive for writing. This is equivalent to
--- `zip.open(path, "w", options)`. Any existing file is truncated.
---@param path string|integer Path to the ZIP file, or file descriptor
---@param options? zip.OpenOptions Optional settings
---@return zip.Writer? writer ZIP writer object on success
---@return string? error Error message on failure
---@nodiscard
function zip.create(path, options) end

--- Opens an existing ZIP archive for appending. This is equivalent to
--- `zip.open(path, "a", options)`. Unlike `zip.open` and `zip.create`,
--- a file descriptor is not accepted; the archive must be given as a
--- path.
---@param path string Path to the ZIP file
---@param options? zip.OpenOptions Optional settings
---@return zip.Appender? appender ZIP appender object on success
---@return string? error Error message on failure
---@nodiscard
function zip.append(path, options) end

--- Validates a ZIP entry name without adding it to an archive, applying
--- the same rules that `add` enforces (relative path, no `..` segments,
--- no control characters, etc.).
---@param name string The entry name to validate
---@return boolean? ok `true` if the name is acceptable
---@return string? error Error message describing why the name is invalid
---@nodiscard
function zip.validate_name(name) end

---@class zip.Stat
--- File metadata within a ZIP archive.
---@field size integer Uncompressed file size in bytes
---@field compressed_size integer Compressed file size in bytes
---@field crc32 integer CRC32 checksum of uncompressed data
---@field mtime integer Modification time as Unix timestamp
---@field method integer Compression method (0=stored, 8=deflated)
---@field mode integer Unix file mode/permissions
zip.Stat = {}

---@class zip.Entry
--- Directory entry returned by `zip.Reader:list`.
---@field name string Entry path within the archive
---@field size integer Uncompressed size in bytes
---@field mode integer Unix file mode/permissions
zip.Entry = {}

---@class zip.AddOptions
---@field method? string Compression method: `"store"` or `"deflate"`
---@field mtime? integer Modification time as Unix timestamp
---@field mode? integer Unix file mode (default 0644)

---@class zip.Reader: userdata
--- Reader for extracting files from a ZIP archive.
zip.Reader = {}

--- Lists all files in the ZIP archive, in archive order. Each record
--- carries the entry's name, uncompressed size, and mode, so bulk
--- operations don't need a follow-up `stat` per entry.
---
---@return zip.Entry[] files Array of directory entry records
---@nodiscard
function zip.Reader:list() end

--- Gets metadata for a specific file in the archive.
---
---@param name string The file path within the archive
---@return zip.Stat|nil stat File metadata
---@return string? error `"entry not found: <name>"` when absent
---@nodiscard
function zip.Reader:stat(name) end

--- Reads the contents of a file from the archive.
---
---@param name string The file path within the archive
---@return string|nil content The file contents
---@return string? error Error message on failure
---@nodiscard
function zip.Reader:read(name) end

--- Closes the ZIP reader and releases resources.
function zip.Reader:close() end

---@class zip.Writer: userdata
--- Writer for creating new ZIP archives.
zip.Writer = {}

--- Adds a file to the ZIP archive.
---
---@param name string The path/filename within the ZIP archive
---@param content string The file content to add
---@param options? zip.AddOptions Optional settings for this entry
---@return boolean? success `true` on success
---@return string? error Error message on failure
function zip.Writer:add(name, content, options) end

--- Closes the ZIP archive and writes the central directory.
function zip.Writer:close() end

---@class zip.Appender: userdata
--- Writer for appending files to an existing ZIP archive.
zip.Appender = {}

--- Adds a file to the ZIP archive.
---
---@param name string The path/filename within the ZIP archive
---@param content string The file content to add
---@param options? zip.AddOptions Optional settings for this entry
---@return boolean? success `true` on success
---@return string? error Error message on failure
function zip.Appender:add(name, content, options) end

--- Removes entries by name from the archive.
---
--- If `name` ends with `/`, all entries whose names start with that
--- directory prefix are removed; otherwise the single entry whose name
--- matches exactly is removed. Both entries already present in the
--- archive and entries added via `add` but not yet flushed are matched.
--- The local file data of removed existing entries remains as dead space
--- in the archive; only the central directory reference is removed.
--- Fails with an error if no entry matched or the appender is closed.
---@param name string Entry name, or directory prefix ending in `/`
---@return boolean? success `true` on success
---@return string? error Error message on failure
function zip.Appender:remove(name) end

--- Closes the ZIP archive and writes the updated central directory.
function zip.Appender:close() end

--- The repl module provides programmatic access to the same interactive
--- read-eval-print-loop that the lua binary runs in interactive mode.
repl = {}

--- Starts an interactive read-eval-print-loop (REPL) on standard input
--- and output, with line editing, history, and tab completion. Each
--- input line is evaluated as an expression (printing its results) or
--- as a statement. The loop runs until end of input (Ctrl-D). Takes no
--- arguments and returns nothing.
function repl.start() end

--- The cosmo module is the top-level table returned by
--- `require("cosmo")` in the cosmopolitan lua binary. It exposes the
--- general-purpose functions that redbean historically provided as
--- globals: hashing, encoding, compression, URL and HTTP parsing, an
--- HTTP client, and various system introspection helpers. Submodules
--- (`cosmo.unix`, `cosmo.path`, `cosmo.re`, `cosmo.argon2`,
--- `cosmo.lsqlite3`, `cosmo.getopt`, `cosmo.zip`, `cosmo.repl`) are
--- registered in `package.loaded` and may be required directly, e.g.
--- `require("cosmo.unix")`.
cosmo = {}

---@class cosmo.BarfOptions
---@field mode integer? file mode for a newly created file, defaults to 0644
---@field append boolean? append to the file instead of truncating it (default false)
---@field offset integer? 1-indexed byte offset for overwriting a slice of the file; incompatible with `append`

--- Writes all data to file the easy way.
---
--- This function writes to the local file system. By default it truncates
--- (or creates) the file. Pass `append = true` to append instead, or an
--- `offset` to overwrite a slice in place. On failure it returns nil plus
--- an error string that names the path.
---
---@param filename string
---@param data string
---@param options cosmo.BarfOptions?
---
--- For example:
---
---     assert(Barf('x.txt', 'abc123'))
---     assert(Barf('x.txt', 'XX', {offset = 3}))
---     assert(assert(Slurp('x.txt', 1, 6)) == 'abXX23')
---
---@return true|nil
---@return string? error
---@return integer? errno
function cosmo.Barf(filename, data, options) end

---@param ip uint32
---@return string # a string describing the IP address. This is currently Class A granular. It can tell you if traffic originated from private networks, ARIN, APNIC, DOD, etc.
---@nodiscard
function cosmo.CategorizeIp(ip) end

--- Computes Phil Katz CRC-32 used by zip/zlib/gzip/etc.
---@param initial integer
---@param data string
---@return integer
---@nodiscard
function cosmo.Crc32(initial, data) end

--- Computes 32-bit Castagnoli Cyclic Redundancy Check.
---@param initial integer
---@param data string
---@return integer
---@nodiscard
function cosmo.Crc32c(initial, data) end

--- Turns ASCII into binary using the provided alphabet. The default
--- decoding uses Crockford's base32 alphabet in a permissive way that
--- ignores whitespace and dash (`-`) and stops at the first character
--- outside of the alphabet. Any alphabet that has a power of 2 length
--- (up to 128) may be supplied, which allows alternative base32
--- encodings to be decoded. Returns nil, err if the alphabet length is
--- not a power of 2 in the range 2..128.
---@param ascii string
---@param alphabet string? defaults to Crockford's base32 alphabet
---@return string|nil binary
---@return string? error
---@nodiscard
function cosmo.DecodeBase32(ascii, alphabet) end

--- Decodes binary data encoded as base64.
---
--- This turns ASCII into binary, in a permissive way that ignores
--- characters outside the base64 alphabet, such as whitespace. See
--- `decodebase64.c`.
---
---@param ascii string
---@return string binary
---@nodiscard
function cosmo.DecodeBase64(ascii) end

--- Turns ASCII base-16 hexadecimal byte string into binary string,
--- case-insensitively. Returns nil, err if the string has an odd length
--- or contains a non-hex character.
---@param ascii string
---@return string|nil binary
---@return string? error
function cosmo.DecodeHex(ascii) end

--- Turns JSON string into a Lua data structure.
---
--- This is a generally permissive parser, in the sense that like
--- v8, it permits scalars as top-level values. Therefore we must
--- note that this API can be thought of as special, in the sense
---
---     val = assert(DecodeJson(str))
---
--- will usually do the right thing, except in cases where `false`
--- or `null` are the top-level value. In those cases, it's needed
--- to check the second value too in order to discern from error
---
---     val, err = DecodeJson(str)
---     if not val then
---        if err then
---           print('bad json', err)
---        elseif val == nil then
---           print('val is null')
---        elseif val == false then
---           print('val is false')
---        end
---     end
---
--- This parser supports 64-bit signed integers. If an overflow
--- happens, then the integer is silently coerced to double, as
--- consistent with v8. If a double overflows, it decodes as
--- `Infinity`, which `EncodeJson` refuses to re-encode unless
--- `nan="null"` is given; underflows, like v8, are coerced to `0.0`.
---
--- When objects are parsed, your Lua object can't preserve the
--- original ordering of fields. As such, they'll be sorted by
--- `EncodeJson()` and may not round-trip with original intent.
---
--- Decoded arrays are marked with a shared `json.array` metatable so
--- that an empty `[]` won't round-trip as `{}`. The marker carries no
--- data: `next()` on a decoded `[]` returns nil, and `pairs()` sees
--- only the array elements. Use `jsonarray()` to mark tables you build
--- yourself.
---
--- This parser has perfect conformance with JSONTestSuite.
---
--- This parser validates utf-8 and utf-16.
---@param input string
---@return JsonValue|nil
---@return string? error
---@nodiscard
function cosmo.DecodeJson(input) end

--- Turns ISO-8859-1 string into UTF-8.
---@param iso_8859_1 string
---@return string UTF8
---@nodiscard
function cosmo.DecodeLatin1(iso_8859_1) end

--- Compresses data.
---
---     >: Deflate("hello")
---     "\xcbH\xcd\xc9\xc9\x07\x00"
---     >: Inflate("\xcbH\xcd\xc9\xc9\x07\x00")
---     "hello"
---
--- The default output format is raw DEFLATE that's suitable for embedding
--- into formats like a ZIP file. Pass `{format = "zlib"}` or
--- `{format = "gzip"}` for streams that interoperate with other zlib and
--- gzip tooling; those framings carry their own integrity checks, whereas
--- with `"raw"` it's recommended that, like ZIP, you also store a `Crc32()`
--- checksum separately.
---
--- Returns `nil, error` when an option value is invalid (for example a
--- level outside `-1`..`9` or an unknown format).
---@param uncompressed string
---@param options cosmo.DeflateOptions?
---@return string|nil compressed
---@return string? error
---@nodiscard
function cosmo.Deflate(uncompressed, options) end

--- Turns binary into ASCII using the provided alphabet (Crockford's
--- base32 alphabet by default). Any alphabet that has a power of 2
--- length (up to 128) may be supplied for encoding and decoding, which
--- allows alternative base32 encodings to be produced. Returns nil, err
--- if the alphabet length is not a power of 2 in the range 2..128.
---@param binary string
---@param alphabet string? defaults to Crockford's base32 alphabet
---@return string|nil ascii
---@return string? error
---@nodiscard
function cosmo.EncodeBase32(binary, alphabet) end

--- Turns binary into ASCII. This can be used to create HTML data:
--- URIs that do things like embed a PNG file in a web page. See
--- encodebase64.c.
---@param binary string
---@return string ascii
---@nodiscard
function cosmo.EncodeBase64(binary) end

--- Turns binary into ASCII base-16 hexadecimal lowercase string.
---@param binary string
---@return string ascii
function cosmo.EncodeHex(binary) end

--- Turns Lua data structure into JSON string.
---
--- Since Lua uses tables are both hashmaps and arrays, we use a
--- simple fast algorithm for telling the two apart. Tables with
--- non-zero length (as reported by `#`) are encoded as arrays,
--- and any non-array elements are ignored. For example:
---
---     >: EncodeJson({2})
---     "[2]"
---     >: EncodeJson({[1]=2, ["hi"]=1})
---     "[2]"
---
--- If there are holes in your array, then the serialized array
--- will exclude everything after the first hole. If the beginning
--- of your array is a hole, then an error is returned.
---
---     >: EncodeJson({[1]=1, [3]=3})
---     "[1]"
---     >: EncodeJson({[2]=1, [3]=3})
---     "[]"
---     >: EncodeJson({[2]=1, [3]=3})
---     nil     "json objects must only use string keys"
---
--- If the raw length of a table is reported as zero, then we check
--- whether it carries the shared `json.array` marker metatable. If it
--- does, your table will be serialized as empty array `[]`. The marker
--- is applied by `DecodeJson()` to every decoded array, so empty arrays
--- round-trip; use `jsonarray()` to mark empty tables you build
--- yourself. If raw length is zero and the marker is absent, then your
--- table will be serialized as an iterated object.
---
---     >: EncodeJson({})
---     "{}"
---     >: EncodeJson(jsonarray({}))
---     "[]"
---     >: EncodeJson({["hi"]=1})
---     "{\"hi\":1}"
---     >: EncodeJson({["hi"]=1, [7]=false})
---     nil     "json objects must only use string keys"
---
--- A table carrying the `json.null` sentinel metatable (see the
--- `null` value on this module) is serialized as `null`, which makes
--- lossless `{"a":null}` round-trips possible.
---
--- The following options may be used:
---
--- - `useoutput`: `(bool=false)` encodes the result directly to the output buffer
---   and returns nil value. This option is ignored if used outside of request
---   handling code.
--- - `sorted`: `(bool=true)` Lua uses hash tables so the order of object keys is
---   lost in a Lua table. So, by default, we use strcmp to impose a deterministic
---   output order. If you don't care about ordering then setting `sorted=false`
---   should yield a performance boost in serialization.
--- - `pretty`: `(bool=false)` Setting this option to true will cause tables with
---   more than one entry to be formatted across multiple lines for readability.
--- - `indent`: `(str=" ")` This option controls the indentation of pretty
---    formatting. This field is ignored if pretty isn't `true`.
--- - `maxdepth`: `(int=64)` This option controls the maximum amount of recursion
---   the serializer is allowed to perform. The max is 32767. You might not be able
---   to set it that high if there isn't enough C stack memory. Your serializer
---   checks for this and will return an error rather than crashing.
--- - `nan`: `(str)` The only accepted value is `"null"`, which makes NaN
---   and Infinity serialize as `null` (the v8 behavior) instead of
---   failing the encode.
---
--- This function will return an error if:
---
--- - value is cyclic
--- - value has depth greater than 64
--- - value contains functions, user data, or threads
--- - value is table that blends string / non-string keys
--- - value contains NaN or Infinity and `nan="null"` wasn't given
--- - Your serializer runs out of C heap memory (setrlimit)
---
--- We assume strings in value contain UTF-8. This serializer currently does not
--- produce UTF-8 output. The output format is right now ASCII. Your UTF-8 data
--- will be safely transcoded to `\uXXXX` sequences which are UTF-16. Overlong
--- encodings in your input strings will be canonicalized rather than validated.
---@param value JsonValue
---@param options cosmo.EncoderOptions?
---@return string|nil
---@return string? error
---@nodiscard
---@overload fun(value: JsonValue, options: cosmo.EncoderOptions): true
function cosmo.EncodeJson(value, options) end

--- Turns UTF-8 into ISO-8859-1 string.
---@param utf8 string
---@param flags integer?
---@return string iso_8859_1
---@nodiscard
function cosmo.EncodeLatin1(utf8, flags) end

--- Turns Lua data structure into Lua code string.
---
--- Since Lua uses tables as both hashmaps and arrays, tables will only be
--- serialized as an array with determinate order, if it's an array in the
--- strictest possible sense.
---
--- 1. for all 𝑘=𝑣 in table, 𝑘 is an integer ≥1
--- 2. no holes exist between MIN(𝑘) and MAX(𝑘)
--- 3. if non-empty, MIN(𝑘) is 1
---
--- In all other cases, your table will be serialized as an object which is
--- iterated and displayed as a list of (possibly) sorted entries that have
--- equal signs.
---
---     >: EncodeLua({3, 2})
---     "{3, 2}"
---     >: EncodeLua({[1]=3, [2]=3})
---     "{3, 2}"
---     >: EncodeLua({[1]=3, [3]=3})
---     "{[1]=3, [3]=3}"
---     >: EncodeLua({["hi"]=1, [1]=2})
---     "{[1]=2, hi=1}"
---
--- The following options may be used:
---
--- - `useoutput`: `(bool=false)` encodes the result directly to the output buffer
---   and returns nil value. This option is ignored if used outside of request
---   handling code.
--- - `sorted`: `(bool=true)` Lua uses hash tables so the order of object keys is
---   lost in a Lua table. So, by default, we use strcmp to impose a deterministic
---   output order. If you don't care about ordering then setting `sorted=false`
---   should yield a performance boost in serialization.
--- - `pretty`: `(bool=false)` Setting this option to true will cause tables with
---   more than one entry to be formatted across multiple lines for readability.
--- - `indent`: `(str=" ")` This option controls the indentation of pretty
---    formatting. This field is ignored if pretty isn't `true`.
--- - `maxdepth`: `(int=64)` This option controls the maximum amount of recursion
---   the serializer is allowed to perform. The max is 32767. You might not be able
---   to set it that high if there isn't enough C stack memory. Your serializer
---   checks for this and will return an error rather than crashing.
---
--- If a user data object has a `__repr` or `__tostring` meta method, then that'll
--- be used to encode the Lua code.
---
--- This serializer is designed primarily to describe data. For example, it's used
--- by the REPL where we need to be able to ignore errors when displaying data
--- structures, since showing most things imperfectly is better than crashing.
--- Therefore this isn't the kind of serializer you'd want to use to persist data
--- in prod. Try using the JSON serializer for that purpose.
---
--- Non-encodable value types (e.g. threads, functions) will be represented as a
--- string literal with the type name and pointer address. The string description
--- is of an unspecified format that could most likely change. This encoder detects
--- cyclic tables; however instead of failing, it embeds a string of unspecified
--- layout describing the cycle.
---
--- Integer literals are encoded as decimal. However if the int64 number is ≥256
--- and has a population count of 1 then we switch to representating the number in
--- hexadecimal, for readability. Hex numbers have leading zeroes added in order
--- to visualize whether the number fits in a uint16, uint32, or int64. Also some
--- numbers can only be encoded expressionally. For example, `NaN`s are serialized
--- as `0/0`, and `Infinity` is `math.huge`.
---
---     >: 7000
---     7000
---     >: 0x100
---     0x0100
---     >: 0x10000
---     0x00010000
---     >: 0x100000000
---     0x0000000100000000
---     >: 0/0
---     0/0
---     >: 1.5e+9999
---     math.huge
---     >: -9223372036854775807 - 1
---     -9223372036854775807 - 1
---
--- The only failure return condition currently implemented is when C runs out of heap memory.
---@param options cosmo.EncoderOptions?
---@return string|nil
---@return string? error
---@nodiscard
---@overload fun(value, options: cosmo.EncoderOptions): true
function cosmo.EncodeLua(value, options) end

--- This function is the inverse of ParseUrl. The output will always be correctly
--- formatted. The exception is if illegal characters are supplied in the scheme
--- field, since there's no way of escaping those. Opaque parts are escaped as
--- though they were paths, since many URI parsers won't understand things like
--- an unescaped question mark in path.
---@param url cosmo.Url
---@return string url
---@nodiscard
function cosmo.EncodeUrl(url) end

--- Escapes URL #fragment. The allowed characters are `-/?.~_@:!$&'()*+,;=0-9A-Za-z`
--- and everything else gets `%XX` encoded. Please note that `'&` can still break
--- HTML and that `'()` can still break CSS URLs. This function is charset agnostic
--- and will not canonicalize overlong encodings. It is assumed that a UTF-8 string
--- will be supplied. See `kescapefragment.S`.
---@param str string
---@return string
---@nodiscard
function cosmo.EscapeFragment(str) end

--- Escapes URL host. See `kescapeauthority.S`.
---@param str string
---@return string
---@nodiscard
function cosmo.EscapeHost(str) end

--- Escapes HTML entities: The set of entities is `&><"'` which become `&amp;&gt;&lt;&quot;&#39;`. This function is charset agnostic and will not canonicalize overlong encodings. It is assumed that a UTF-8 string will be supplied. See `escapehtml.c`.
---@param str string
---@return string
---@nodiscard
function cosmo.EscapeHtml(str) end

--- Escapes URL IP-literal. This is the same as `EscapeHost` except
--- colon is permitted, so bracketed IPv6 literals stay intact. See
--- `escapeip.c`.
---@param str string
---@return string
---@nodiscard
function cosmo.EscapeIp(str) end

--- Escapes JavaScript or JSON string literal content. The caller is responsible
--- for adding the surrounding quotation marks. This implementation \uxxxx sequences
--- for all non-ASCII sequences. HTML entities are also encoded, so the output
--- doesn't need `EscapeHtml`. This function assumes UTF-8 input. Overlong
--- encodings are canonicalized. Invalid input sequences are assumed to
--- be ISO-8859-1. The output is UTF-16 since that's what JavaScript uses. For
--- example, some individual codepoints such as emoji characters will encode as
--- multiple `\uxxxx` sequences. Ints that are impossible to encode as UTF-16 are
--- substituted with the `\xFFFD` replacement character.
--- See `escapejsstringliteral.c`.
---@param str string
---@return string
---@nodiscard
function cosmo.EscapeLiteral(str) end

--- Escapes URL parameter name or value. The allowed characters are `-.*_0-9A-Za-z`
--- and everything else gets `%XX` encoded. This function is charset agnostic and
--- will not canonicalize overlong encodings. It is assumed that a UTF-8 string
--- will be supplied. See `kescapeparam.S`.
---@param str string
---@return string
---@nodiscard
function cosmo.EscapeParam(str) end

--- Escapes URL password. See `kescapeauthority.S`.
---@param str string
---@return string
---@nodiscard
function cosmo.EscapePass(str) end

--- Escapes URL path. This is the same as EscapeSegment except slash is allowed.
--- The allowed characters are `-.~_@:!$&'()*+,;=0-9A-Za-z/` and everything else
--- gets `%XX` encoded. Please note that `'&` can still break HTML, so the output
--- may need EscapeHtml too. Also note that `'()` can still break CSS URLs. This
--- function is charset agnostic and will not canonicalize overlong encodings.
--- It is assumed that a UTF-8 string will be supplied. See `kescapepath.S`.
---@param str string
---@return string
---@nodiscard
function cosmo.EscapePath(str) end

--- Escapes URL path segment. This is the same as EscapePath except slash isn't
--- allowed. The allowed characters are `-.~_@:!$&'()*+,;=0-9A-Za-z` and everything
--- else gets `%XX` encoded. Please note that `'&` can still break HTML, so the
--- output may need EscapeHtml too. Also note that `'()` can still break CSS URLs.
--- This function is charset agnostic and will not canonicalize overlong encodings.
--- It is assumed that a UTF-8 string will be supplied. See `kescapesegment.S`.
---@param str string
---@return string
---@nodiscard
function cosmo.EscapeSegment(str) end

--- Escapes URL username. See `kescapeauthority.S`.
---@param str string
---@return string
---@nodiscard
function cosmo.EscapeUser(str) end

--- Sends an HTTP/HTTPS request to the specified URL. If only the URL is provided,
--- then a GET request is sent. If both URL and body parameters are specified, then
--- a POST request is sent. If any other method needs to be specified (for example,
--- PUT or DELETE), then passing a table as the second value allows setting method
--- and body values as well other options:
---
--- - `method` (default: `"GET"`): sets the method to be used for the request.
---   The specified method is converted to uppercase.
--- - `body` (default: `""`): sets the body value to be sent.
--- - `followredirect` (default: `true`): forces temporary and permanent redirects
---    to be followed. This behavior can be disabled by passing `false`.
--- - `maxredirects` (default: `5`): sets the number of allowed redirects to
---   minimize looping due to misconfigured servers. When the number is exceeded,
---   the result of the last redirect is returned.
--- - `keepalive` (default = `false`): configures each request to keep the
---   connection open (unless closed by the server) and reuse for the
---   next request to the same host. This option is disabled when SSL
---   connection is used.
---   When a table is passed, it is used as the socket pool: the mapping
---   of hosts to their sockets is stored in it, so the same table can be
---   passed to the next call. If that table includes the `close` field
---   set to a true value, then the connection is closed after the
---   request is made and the host is removed from the mapping table.
---   When `true` is passed, a process-wide internal pool is used
---   instead; the options table is never modified.
--- - `allowprivate` (default: `false`): allow requests to private,
---   loopback, and other non-public network addresses, which are
---   otherwise blocked to prevent SSRF. The opt-out covers every hop of
---   a redirect chain.
--- - `proxy` (string): HTTP proxy URL, e.g. `"http://proxy:8080"`.
---   Supports Basic authentication: `"http://user:pass@proxy:8080"`.
--- - `maxresponse` (default: `104857600`): maximum response size in bytes.
---   Protects against memory exhaustion from large responses.  Must be >= 0;
---   negative values are rejected.
--- - `timeout` (number, seconds): per-operation socket timeout (read/write/
---   connect).  A value of `0` or absent keeps the 60-second default.  There
---   is no "infinite" option — use a large positive value if needed.  The
---   timeout also bounds the TLS handshake.
---
--- Environment variables:
---
--- - `http_proxy` / `HTTP_PROXY`: default proxy URL when `proxy` option
---   is not specified. Supports same format as the option.
--- - `SSL_CERT_FILE`: path to CA certificate bundle file for TLS verification.
---   Overrides default system CA locations.
--- - `SSL_NO_SYSTEM_CERTS`: if set, skip loading system CA certificates.
---   Only embedded certificates will be used.
---
--- When the redirect is being followed, the same method and body values are being
--- sent in all cases except when 303 status is returned. In that case the method
--- is set to GET and the body is removed before the redirect is followed. The
--- options table is read-only: it is never modified, even across redirects.
---
--- On success, the fourth return value is the effective URL: the URL of
--- the final request after any redirects were followed.
---
--- On failure, returns `nil`, a descriptive error message, and a
--- machine-readable failure kind, one of `"dns"` (name resolution
--- failed), `"connect"` (connection failed or was reset), `"tls"`
--- (handshake or certificate verification failed), `"timeout"`,
--- `"proxy"` (proxy configuration or tunnel failure), `"protocol"`
--- (malformed request or response), `"too_large"` (response exceeded
--- `maxresponse`), or `"blocked"` (refused by SSRF protection or the
--- HTTPS-to-HTTP downgrade guard).
---@param url string
---@param body? string|cosmo.FetchOptions
---@return integer|nil status, table<string,string> headers, string body, string url
---@return string? error
---@return string? kind machine-readable failure kind; see above for values
---@nodiscard
function cosmo.Fetch(url, body) end

--- Sends an HTTP/HTTPS request and returns a streaming reader for the response body.
--- Useful for Server-Sent Events (SSE), large downloads, or processing data incrementally.
---
--- Accepts the same options table as `Fetch()`, including `timeout`, `maxresponse`,
--- `headers`, `method`, `body`, `proxy`, `allowprivate`, `followredirect`,
--- and `maxredirects` (`keepalive` is ignored: streaming connections are
--- always closed). The options table is read-only: it is never modified,
--- even across redirects.
--- Note: `timeout=0` (or absent) retains the 60-second default; there is no
--- "infinite" option.  `maxresponse` limits per-read buffer growth; negative
--- values are rejected.
---
--- On success, the fourth return value is the effective URL after any
--- redirects. On failure, returns `nil`, a descriptive error message,
--- and a machine-readable failure kind with the same values as
--- `Fetch()`.
---@param url string The URL to fetch
---@param options? cosmo.FetchOptions Request options
---@return integer|nil status, table<string,string> headers, cosmo.StreamReader reader, string url
---@return string? error
---@return string? kind machine-readable failure kind; see `Fetch`
---@nodiscard
function cosmo.FetchStream(url, options) end

--- Converts UNIX timestamp to an RFC1123 string that looks like this:
--- `Mon, 29 Mar 2021 15:37:13 GMT`. See `formathttpdatetime.c`.
---@param seconds integer
---@return string
---@nodiscard rfc1123
function cosmo.FormatHttpDateTime(seconds) end

--- Turns integer like `0x01020304` into a string like `"1.2.3.4"`. See also
--- `ParseIp` for the inverse operation.
---@param uint32 integer
---@return string
---@nodiscard
function cosmo.FormatIp(uint32) end

---@param name "MD5"|"SHA1"|"SHA224"|"SHA256"|"SHA384"|"SHA512"|"BLAKE2B256"
---@param payload string
---@param key string? If the key is provided, then HMAC value of the same function is returned.
---@return string|nil # value of the specified cryptographic hash function.
---@return string? error
---@nodiscard
function cosmo.GetCryptoHash(name, payload, key) end

--- Returns string describing host instruction set architecture.
---
--- This can return:
---
--- - `"X86_64"` for Intel and AMD systems
--- - `"AARCH64"` for ARM64, M1, and Raspberry Pi systems
--- - `"POWERPC64"` for OpenPOWER Raptor Computing Systems
---@return "X86_64"|"AARCH64"|"POWERPC64"
---@nodiscard
function cosmo.GetHostIsa() end

---@return "LINUX"|"METAL"|"WINDOWS"|"XNU"|"NETBSD"|"FREEBSD"|"OPENBSD" osname string that describes the host OS.
---@nodiscard
function cosmo.GetHostOs() end

---@param code integer
---@return string reason string describing the HTTP reason phrase. See `gethttpreason.c`.
---@nodiscard
function cosmo.GetHttpReason(code) end

---@param str string|integer monospace display width of string.
--- This is useful for fixed-width formatting. For example, CJK characters
--- typically take up two cells. This function takes into consideration combining
--- characters, which are discounted, as well as control codes and ANSI escape
--- sequences.
---@return integer
---@nodiscard
function cosmo.GetMonospaceWidth(str) end

---@param length integer? number of random bytes to return (1..4194304), defaults to 16
---@return string|nil bytes
---@return string? error
---@nodiscard
function cosmo.GetRandomBytes(length) end

--- Returns `true` if the string contains forbidden control codes.
---
--- `flags` selects which characters are considered forbidden and may be
--- any combination of:
---
--- - `1` (kControlWs): forbid the whitespace controls tab, carriage
---   return, line feed, and vertical tab
--- - `2` (kControlC0): forbid the C0 control codes (0x00..0x1F and
---   0x7F), except the whitespace controls above
--- - `4` (kControlC1): forbid the C1 control codes (0x80..0x9F), which
---   are decoded from UTF-8 before being checked
---
--- If `flags` is zero (the default) then no characters are forbidden
--- and this function returns `false`. Raises an error if `flags` has
--- bits outside the values above.
---@param str string
---@param flags integer?
---@return boolean
---@nodiscard
function cosmo.HasControlCodes(str, flags) end

--- Decompresses data.
---
--- This function performs the inverse of `Deflate()`. The decompressed
--- size need not be known in advance: output streams into a growing
--- buffer, bounded by `options.maxsize` (default 64 MiB). Corrupt or
--- truncated input yields `nil, error` rather than raising. When using
--- the default `"raw"` framing it's recommended that you perform a
--- `Crc32()` check on the output string after this function succeeds.
---
---@param compressed string
---@param options cosmo.InflateOptions?
---@return string|nil uncompressed
---@return string? error
---@nodiscard
function cosmo.Inflate(compressed, options) end

--- Check if the calling script is being run directly (not require'd).
---
--- This function provides a Python-like `if __name__ == "__main__"` idiom
--- for Lua scripts. It returns true when the script is executed directly
--- from the command line, and false when the script is loaded via require().
---
--- Example usage:
---
---     local M = {}
---
---     function M.main(args)
---       print("Hello, " .. (args[1] or "world"))
---     end
---
---     if is_main() then
---       M.main(arg)
---     end
---
---     return M
---
---@return boolean # `true` if the script is run directly, `false` if it was require'd
---@nodiscard
function cosmo.is_main() end

--- Returns `true` if hostname seems legit.
---
--- This validates the host component of a URL, permitting things like
--- `""`, `1.2.3.4`, `localservice`, `hello.example`, and
--- `hi-there.example`, while rejecting things like `::1`, `1.2.3`,
--- `1.2.3.4.5`, `.hi.example`, and `hi..example`. Fully numerical names
--- must be valid IPv4 addresses. There's currently no support for IPv6
--- literals. See `isacceptablehost.c`.
---@param str string
---@return boolean
---@nodiscard
function cosmo.IsAcceptableHost(str) end

---@param str string
---@return boolean # `true` if path doesn't contain ".", ".." or "//" segments See `isacceptablepath.c`
---@nodiscard
function cosmo.IsAcceptablePath(str) end

--- Returns `true` if port string seems legit, i.e. it's either empty or
--- a string of digits that fits in the range 0..65535, e.g. `""`,
--- `"0"`, `"65535"`. Named services like `"https"`, negative values,
--- and numbers greater than 65535 are rejected. See
--- `isacceptableport.c`.
---@param str string
---@return boolean
---@nodiscard
function cosmo.IsAcceptablePort(str) end

---@param uint32 integer
---@return boolean # true if IP address is part of the localhost network (127.0.0.0/8).
---@nodiscard
function cosmo.IsLoopbackIp(uint32) end

---@param uint32 integer
---@return boolean # `true` if IP address is part of a private network (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16).
---@nodiscard
function cosmo.IsPrivateIp(uint32) end

---@param uint32 integer
---@return boolean # `true` if IP address is not a private network (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) and is not localhost (`127.0.0.0/8`).
--- Note: we intentionally regard TEST-NET IPs as public.
---@nodiscard
function cosmo.IsPublicIp(uint32) end

---@param str string
---@return boolean # `true` if path doesn't contain "." or ".." segments See `isreasonablepath.c`
---@nodiscard
function cosmo.IsReasonablePath(str) end

--- Marks a table with the shared `json.array` metatable so `EncodeJson`
--- serializes it as a JSON array even when it's empty. `DecodeJson`
--- applies the same marker to every array it decodes, which is how an
--- empty `[]` round-trips instead of turning into `{}`. Passing no
--- argument creates and returns a fresh marked table.
---
---     >: EncodeJson({})
---     "{}"
---     >: EncodeJson(jsonarray({}))
---     "[]"
---
---@param t JsonValue[]? the table to mark; a new empty table is created when omitted
---@return JsonValue[] t the same table (or the new one), marked as an array
function cosmo.jsonarray(t) end

--- Sentinel value that `EncodeJson` serializes as JSON `null`, enabling
--- lossless `{"a":null}` round-trips (a plain `nil` value would erase
--- the key from the Lua table). It's an empty table carrying the shared
--- `json.null` metatable; any table with that metatable encodes as
--- `null`.
---
---     >: EncodeJson({a = cosmo.null})
---     "{\"a\":null}"
---
---@type JsonValue
cosmo.null = {}

--- Parses a `host[:port]` string, e.g. `"example.com:8080"`.
---
--- Please note a longstanding quirk inherited from redbean: only the
--- port component is currently returned. This function yields the port
--- string (e.g. `"8080"`), or `nil` if no port is present; the host
--- component is parsed but not returned. This function is
--- nil-propagating: passing `nil` returns `nil`. Raises an error if the
--- system runs out of memory.
---@param str string
---@return string? port
---@nodiscard
function cosmo.ParseHost(str) end

--- Converts IPv4 address string to integer, e.g. "1.2.3.4" → 0x01020304.
--- Returns nil, err for invalid inputs (previously it returned the -1
--- sentinel, which `FormatIp` rendered as the broadcast address). See also
--- `FormatIp` for the inverse operation.
---@param ip string
---@return integer|nil ip
---@return string? error
---@nodiscard
function cosmo.ParseIp(ip) end

--- Parses `application/x-www-form-urlencoded` key/value parameters,
--- e.g. `"a=b&c"` becomes `{{"a", "b"}, {"c"}}`. This returns the same
--- data structure as the `params` field of the `Url` object returned by
--- `ParseUrl`. Keys and values are percent-decoded. This function is
--- nil-propagating: passing `nil` returns `nil`. Raises an error if the
--- system runs out of memory.
---@param paramstring string
---@return { [1]: string, [2]: string? }[] params
---@nodiscard
function cosmo.ParseParams(paramstring) end

--- Parses URL.
---
---@return cosmo.Url url An object containing the following fields is returned:
---
--- - `scheme` is a string, e.g. `"http"`
--- - `user` is the username string, or nil if absent
--- - `pass` is the password string, or nil if absent
--- - `host` is the hostname string, or nil if `url` was a path
--- - `port` is the port string, or nil if absent
--- - `path` is the path string, or nil if absent
--- - `params` is the URL paramaters, e.g. `/?a=b&c` would be
---   represented as the data structure `{{"a", "b"}, {"c"}, ...}`
--- - `fragment` is the stuff after the `#` character
---
---@param url string
---@param flags integer? may have:
---
--- - `kUrlPlus` to turn `+` into space
--- - `kUrlLatin1` to transcode ISO-8859-1 input into UTF-8
---
--- This parser is charset agnostic. Percent encoded bytes are
--- decoded for all fields. Returned values might contain things
--- like NUL characters, spaces, control codes, and non-canonical
--- encodings. Absent can be discerned from empty by checking if
--- the pointer is set.
---
--- There's no failure condition for this routine. This is a
--- permissive parser. This doesn't normalize path segments like
--- `.` or `..` so use IsAcceptablePath() to check for those. No
--- restrictions are imposed beyond that which is strictly
--- necessary for parsing. All the data that is provided will be
--- consumed to the one of the fields. Strict conformance is
--- enforced on some fields more than others, like scheme, since
--- it's the most non-deterministically defined field of them all.
---
--- Please note this is a URL parser, not a URI parser. Which
--- means we support everything the URI spec says we should do
--- except for the things we won't do, like tokenizing path
--- segments into an array and then nesting another array beneath
--- each of those for storing semicolon parameters. So this parser
--- won't make SIP easy. What it can do is parse HTTP URLs and most
--- URIs like data:opaque, better in fact than most things which
--- claim to be URI parsers.
---
---@nodiscard
function cosmo.ParseUrl(url, flags) end

---@return integer # nondeterministic pseudorandom non-cryptographic number.
--- This linear congruential generator passes practrand and bigcrush. This
--- generator is safe across `fork()`, threads, and signal handlers.
---@nodiscard
function cosmo.Rand64() end

--- Gets IP address associated with hostname.
---
--- This function first checks if hostname is already an IP address, in which case
--- it returns the result of `ParseIp`. Otherwise, it checks HOSTS.TXT on the local
--- system and returns the first IPv4 address associated with hostname. If no such
--- entry is found, a DNS lookup is performed using the system configured (e.g.
--- `/etc/resolv.conf`) DNS resolution service. If the service returns multiple IN
--- A records then only the first one is returned.
---
--- The returned address is word-encoded in host endian order. For example,
--- 1.2.3.4 is encoded as 0x01020304. The `FormatIp` function may be used to turn
--- this value back into a string.
---
--- If no IP address could be found, then `nil` is returned alongside a string of
--- unspecified format describing the error. Calls to this function may be wrapped
--- in `assert()` if an exception is desired.
---@param hostname string
---@return uint32|nil ip uint32
---@return string? error
---@nodiscard
function cosmo.ResolveIp(hostname) end

--- Computes SHA256 checksum, returning 32 bytes of binary.
---@param str string
---@return string checksum
---@nodiscard
function cosmo.Sha256(str) end

--- Reads all data from file the easy way.
---
--- This function reads file data from local file system. Zip file assets can be
--- accessed using the `/zip/...` prefix.
---
--- `i` and `j` may be used to slice a substring in filename. These parameters are
--- 1-indexed and behave consistently with Lua's `string.sub()` API. For example:
---
---     assert(Barf('x.txt', 'abc123'))
---     assert(assert(Slurp('x.txt', 2, 3)) == 'bc')
---
--- This function is uninterruptible so `unix.EINTR` errors will be ignored. This
--- should only be a concern if you've installed signal handlers. Use the UNIX API
--- if you need to react to it.
---
---@param filename string
---@param i integer?
---@param j integer?
---@return string|nil data
---@return string? error
---@return integer? errno
---@nodiscard
function cosmo.Slurp(filename, i, j) end

--- Formats a timestamp using strftime(3) format specifiers.
---
--- Common format specifiers:
--- - `%Y` four-digit year
--- - `%m` two-digit month (01-12)
--- - `%d` two-digit day (01-31)
--- - `%H` two-digit hour (00-23)
--- - `%M` two-digit minute (00-59)
--- - `%S` two-digit second (00-59)
--- - `%F` equivalent to `%Y-%m-%d`
--- - `%T` equivalent to `%H:%M:%S`
--- - `%a` abbreviated weekday name
--- - `%b` abbreviated month name
---
--- Example:
---
---     Strftime("%Y-%m-%d %H:%M:%S")           -- "2024-12-29 15:30:00"
---     Strftime("%F %T", os.time())            -- "2024-12-29 15:30:00"
---     Strftime("%a, %d %b %Y", 0)             -- "Thu, 01 Jan 1970"
---     Strftime("%F %T", os.time(), true)      -- local time instead of UTC
---
---@param format string strftime format string
---@param timestamp? integer UNIX timestamp (defaults to current time)
---@param localtime? boolean use local time instead of UTC (default false)
---@return string|nil formatted the formatted datetime string
---@return string? error
---@nodiscard
function cosmo.Strftime(format, timestamp, localtime) end

--- Unescapes URL parameter name or value. Decodes `%XX` hex sequences and
--- converts `+` to space (common in application/x-www-form-urlencoded).
--- This is the inverse of EscapeParam.
---@param str string
---@return string
---@nodiscard
function cosmo.UnescapeParam(str) end

--- Generate a uuid_v4
---@return string
function cosmo.UuidV4() end

--- Generate a uuid_v7
---@return string
function cosmo.UuidV7() end

---@class cosmo.StreamReader: userdata
--- Streaming reader for an HTTP response body, returned by
--- `cosmo.FetchStream`. The reader owns the underlying connection. It is
--- closed automatically on garbage collection, but calling `close`
--- promptly is recommended.

--- Reads the next chunk of the response body.
---
--- Returns a non-empty string chunk on success (chunked transfer framing
--- that arrives without payload is consumed internally and never surfaces
--- as an empty chunk). Returns `nil` with no error when the stream ends,
--- including for bodyless responses such as 204 and 304. Returns `nil`
--- plus an error message string if the reader was closed with `close`,
--- the connection failed, or the response was truncated.
---@return string? chunk next chunk of data, or nil on EOF
---@return string? error error message on failure
function cosmo.StreamReader:read() end

--- Closes the reader and releases the connection, buffer, and TLS
--- state. Idempotent: closing an already-closed reader is a no-op.
--- Returns nothing.
function cosmo.StreamReader:close() end

--- This module exposes the low-level System Five system call interface.
--- This module works on all supported platforms, including Windows NT.
unix = {
    --- @type integer
    AF_INET = nil,
    --- @type integer
    AF_UNIX = nil,
    --- @type integer
    AF_UNSPEC = nil,

    --- @type integer Returns maximum length of arguments for new processes.
    ---
    --- This is the character limit when calling `execve()`. It's the sum of
    --- the lengths of `argv` and `envp` including any nul terminators and
    --- pointer arrays. For example to see how much your shell `envp` uses
    ---
    ---     $ echo $(($(env | wc -c) + 1 + ($(env | wc -l) + 1) * 8))
    ---     758
    ---
    --- POSIX mandates this be 4096 or higher. On Linux this it's 128*1024.
    --- On Windows NT it's 32767*2 because CreateProcess lpCommandLine and
    --- environment block are separately constrained to 32,767 characters.
    --- Most other systems define this limit much higher.
    ARG_MAX = nil,

    --- @type integer
    AT_EACCESS = nil,
    --- @type integer
    AT_FDCWD = nil,
    --- @type integer
    AT_SYMLINK_NOFOLLOW = nil,

    --- @type integer Returns default buffer size.
    ---
    --- The UNIX module does not perform any buffering between calls.
    ---
    --- Each time a read or write is performed via the UNIX API your redbean
    --- will allocate a buffer of this size by default. This current default
    --- would be 4096 across platforms.
    BUFSIZ = nil,

    --- @type integer Returns the scheduler frequency.
    ---
    --- This is granularity at which the kernel does work. For example, the
    --- Linux kernel normally operates at 100hz so its CLK_TCK will be 100.
    ---
    --- This value is useful for making sense out of unix.Rusage data.
    CLK_TCK = nil,

    --- @type integer
    CLOCK_REALTIME = nil,
    --- @type integer
    CLOCK_MONOTONIC = nil,
    --- @type integer
    CLOCK_BOOTTIME = nil,
    --- @type integer
    CLOCK_MONOTONIC_RAW = nil,
    --- @type integer
    CLOCK_REALTIME_COARSE = nil,
    --- @type integer
    CLOCK_MONOTONIC_COARSE = nil,
    ---@type integer
    CLOCK_THREAD_CPUTIME_ID = nil,
    --- @type integer
    CLOCK_PROCESS_CPUTIME_ID = nil,
    --- @type integer
    DT_BLK = nil,
    --- @type integer
    DT_CHR = nil,
    --- @type integer
    DT_DIR = nil,
    --- @type integer
    DT_FIFO = nil,
    --- @type integer
    DT_LNK = nil,
    --- @type integer
    DT_REG = nil,
    --- @type integer
    DT_SOCK = nil,
    --- @type integer
    DT_UNKNOWN = nil,

    --- @type integer Argument list too long.
    ---
    --- Raised by `execve`, `sched_setattr`.
    E2BIG = nil,
    --- @type integer Permission denied.
    ---
    --- Raised by `access`, `bind`, `chdir`, `chmod`, `chown`, `chroot`,
    --- `clock_getres`, `connect`, `execve`, `fcntl`, `getpriority`,
    --- `link`, `mkdir`, `mknod`, `mmap`, `mprotect`, `msgctl`, `open`,
    --- `prctl`, `ptrace`, `readlink`, `rename`, `rmdir`, `semget`,
    --- `send`, `setpgid`, `socket`, `stat`, `symlink`, `truncate`,
    --- `unlink`, `uselib`, `utime`, `utimensat`.
    EACCES = nil,
    --- @type integer Address already in use. Raised by `bind`, `connect`, `listen`.
    EADDRINUSE = nil,
    --- @type integer Address not available. Raised by `bind`, `connect`.
    EADDRNOTAVAIL = nil,
    --- @type integer Address family not supported. Raised by `connect`, `socket`, `socketpair`.
    EAFNOSUPPORT = nil,
    --- @type integer
    --- Resource temporarily unavailable (e.g. SO_RCVTIMEO expired, too many
    --- processes, too much memory locked, read or write with O_NONBLOCK
    --- needs polling, etc.).
    ---
    --- Raised by `accept`, `connect`, `fcntl`, `fork`, `getrandom`,
    --- `mincore`, `mlock`, `mmap`, `mremap`, `poll`, `read`, `select`,
    --- `send`, `setresuid`, `setreuid`, `setuid`, `sigwaitinfo`,
    --- `splice`, `tee`, `timer_create`, `timerfd_create`, `tkill`,
    --- `write`,
    EAGAIN = nil,
    --- @type integer Connection already in progress. Raised by `connect`, `send`.
    EALREADY = nil,
    --- @type integer Bad file descriptor; cf. EBADFD.
    ---
    --- Raised by `accept`, `access`, `bind`, `chdir`, `chmod`, `chown`,
    --- `close`, `connect`, `copy_file_range`, `dup`, `fcntl`, `flock`,
    --- `fsync`, `futimesat`, `opendir`, `getpeername`, `getsockname`,
    --- `getsockopt`, `ioctl`, `link`, `listen`, `lseek`, `mkdir`,
    --- `mknod`, `mmap`, `open`, `prctl`, `read`, `readahead`,
    --- `readlink`, `recv`, `rename`, `select`, `send`, `shutdown`,
    --- `splice`, `stat`, `symlink`, `sync`, `sync_file_range`,
    --- `timerfd_create`, `truncate`, `unlink`, `utimensat`, `write`.
    EBADF = nil,
    --- @type integer
    EBADFD = nil,
    --- @type integer
    EBADMSG = nil,
    --- @type integer Device or resource busy.
    ---
    --- Raised by dup, fcntl, msync, prctl, ptrace, rename,
    --- rmdir.
    EBUSY = nil,
    --- @type integer
    ECANCELED = nil,
    --- @type integer No child process.
    ---
    --- Raised by `wait`, `waitpid`, `waitid`, `wait3`, `wait4`.
    ECHILD = nil,
    --- @type integer Connection reset before accept. Raised by `accept`.
    ECONNABORTED = nil,
    --- @type integer System-imposed limit on the number of threads was encountered.
    ---
    --- Raised by connect, listen, recv.
    ECONNREFUSED = nil,
    --- @type integer Connection reset by client. Raised by `send`.

    ECONNRESET = nil,
    --- @type integer Resource deadlock avoided.
    ---
    --- Raised by `fcntl`.
    EDEADLK = nil,
    --- @type integer Destination address required. Raised by `send`, `write`.
    EDESTADDRREQ = nil,
    --- @type integer
    EDOM = nil,
    --- @type integer Disk quota exceeded.
    ---
    --- Raised by link, mkdir, mknod, open, rename, symlink,
    --- write.
    EDQUOT = nil,
    --- @type integer File exists.
    ---
    --- Raised by `link`, `mkdir`, `mknod`, `mmap`, `open`, `rename`,
    --- `rmdir`, `symlink`.
    EEXIST = nil,
    --- @type integer
    EFAULT = nil,
    --- @type integer File too large.
    ---
    --- Raised by `copy_file_range`, `open`, `truncate`, `write`.
    EFBIG = nil,
    --- @type integer Inappropriate file type or format.
    EFTYPE = nil,
    --- @type integer Host is down. Raised by `accept`.
    EHOSTDOWN = nil,
    --- @type integer Host is unreachable. Raised by `accept`.
    EHOSTUNREACH = nil,
    --- @type integer Memory page has hardware error.
    EHWPOISON = nil,
    --- @type integer Identifier removed. Raised by `msgctl`.
    EIDRM = nil,
    --- @type integer
    EILSEQ = nil,
    --- @type integer
    EINPROGRESS = nil,
    --- @type integer The greatest of all errnos; crucial for building real time reliable software.
    ---
    --- Raised by `accept`, `clock_nanosleep`, `close`, `connect`, `dup`, `fcntl`,
    --- `flock`, `getrandom`, `nanosleep`, `open`, `pause`, `poll`, `ptrace`, `read`, `recv`,
    --- `select`, `send`, `sigsuspend`, `sigwaitinfo`, `truncate`, `wait`, `write`.
    EINTR = nil,
    --- @type integer Invalid argument.
    --- Raised by [pretty much everything].
    EINVAL = nil,
    --- @type integer
    --- Raised by `access`, `acct`, `chdir`, `chmod`, `chown`, `chroot`, `close`,
    --- `copy_file_range`, `execve`, `fallocate`, `fsync`, `ioperm`, `link`, `madvise`,
    --- `mbind`, `pciconfig_read`, `ptrace`, `read`, `readlink`, `sendfile`, `statfs`,
    --- `symlink`, `sync_file_range`, `truncate`, `unlink`, `write`.
    EIO = nil,
    --- @type integer Socket is connected. Raised by `connect`, `send`.

    EISCONN = nil,
    --- @type integer Is a directory.
    ---
    --- Raised by `copy_file_range`, `execve`, `open`, `read`, `rename`, `truncate`,
    --- `unlink`.
    EISDIR = nil,
    --- @type integer Too many levels of symbolic links.
    ---
    --- Raised by access, bind, chdir, chmod, chown, chroot, execve, link,
    --- mkdir, mknod, open, readlink, rename, rmdir, stat, symlink,
    --- truncate, unlink, utimensat.
    ELOOP = nil,
    --- @type integer Wrong medium type. Raised by `mount`.
    EMEDIUMTYPE = nil,
    --- @type integer Too many open files.
    ---
    --- Raised by `accept`, `dup`, `execve`, `fanotify_init`, `fcntl`,
    --- `open`, `pipe`, `socket`, `socketpair`, `timerfd_create`.
    EMFILE = nil,
    --- @type integer Too many links;
    ---
    --- Raised by `link`, `mkdir`, `rename`.
    EMLINK = nil,
    --- @type integer Message too long. Raised by `send`.
    EMSGSIZE = nil,
    --- @type integer Multihop attempted.
    EMULTIHOP = nil,
    --- @type integer Filename too long. Cosmopolitan Libc currently defines `PATH_MAX` as
    --- 1024 characters. On UNIX that limit should only apply to system call
    --- wrappers like realpath. On Windows NT it's observed by all system
    --- calls that accept a pathname.
    ---
    --- Raised by `access`, `bind`, `chdir`, `chmod`, `chown`, `chroot`,
    --- `execve`, `gethostname`, `link`, `mkdir`, `mknod`, `open`,
    --- `readlink`, `rename`, `rmdir`, `stat`, `symlink`, `truncate`,
    --- `unlink`, `utimensat`.
    ENAMETOOLONG = nil,
    --- @type integer Network is down. Raised by `accept`.
    ENETDOWN = nil,
    --- @type integer Connection reset by network.
    ENETRESET = nil,
    --- @type integer Host is unreachable. Raised by `accept`, `connect`.
    ENETUNREACH = nil,
    --- @type integer Too many open files in system.
    ---
    --- Raised by `accept`, `execve`, `mmap`, `open`, `pipe`, `socket`,
    --- `socketpair`, `swapon`, `timerfd_create`, `uselib`,
    --- `userfaultfd`.
    ENFILE = nil,
    --- @type integer No buffer space available;
    ---
    --- Raised by `getpeername`, `getsockname`, `send`.
    ENOBUFS = nil,
    --- @type integer No message is available in xsi stream or named pipe is being closed;
    --- no data available; barely in posix; returned by ioctl; very close in
    --- spirit to EPIPE?
    ENODATA = nil,
    --- @type integer No such device.
    ---
    --- Raised by `arch_prctl`, `mmap`, `open`, `prctl`, `timerfd_create`.
    ENODEV = nil,
    --- @type integer No such file or directory.
    ---
    --- Raised by `access`, `bind`, `chdir`, `chmod`, `chown`, `chroot`,
    --- `clock_getres`, `execve`, `opendir`, `link`, `mkdir`, `mknod`,
    --- `open`, `readlink`, `rename`, `rmdir`, `stat`, `swapon`,
    --- `symlink`, `truncate`, `unlink`, `utime`, `utimensat`.
    ENOENT = nil,
    --- @type integer Exec format error. Raised by `execve`, `uselib`.
    ENOEXEC = nil,
    --- @type integer No locks available. Raised by `fcntl`, `flock`.
    ENOLCK = nil,
    --- @type integer Link has been severed.
    ENOLINK = nil,
    --- @type integer No medium found. Raised by `mount`.
    ENOMEDIUM = nil,
    --- @type integer
    ENOMEM = nil,
    --- @type integer Raised by `msgop`.
    ENOMSG = nil,
    --- @type integer
    ENONET = nil,
    --- @type integer Protocol not available. Raised by `getsockopt`, `accept`.
    ENOPROTOOPT = nil,
    --- @type integer No space left on device.
    ---
    --- Raised by `copy_file_range`, `fsync`, `link`, `mkdir`, `mknod`,
    --- `open`, `rename`, `symlink`, `sync_file_range`, `write`.
    ENOSPC = nil,
    --- @type integer Out of streams resources.
    ENOSR = nil,
    --- @type integer Device not a stream.
    ENOSTR = nil,
    --- @type integer System call not available on this platform. On
    ---     Windows this is raised by `chroot`, `setuid`, `setgid`,
    ---     `getsid`, `setsid`, and others we're doing our best to
    ---     document.
    ENOSYS = nil,
    --- @type integer Block device required. Raised by `umount`.
    ENOTBLK = nil,
    --- @type integer Socket is not connected.
    ---
    --- Raised by `getpeername`, `recv`, `send`, `shutdown`.
    ENOTCONN = nil,
    --- @type integer Not a directory. This means that a directory
    ---     component in a supplied path *existed* but wasn't a
    ---     directory. For example, if you try to `open("foo/bar")` and
    ---     `foo` is a regular file, then `ENOTDIR` will be returned.
    ---
    --- Raised by `open`, `access`, `chdir`, `chroot`, `execve`, `link`,
    --- `mkdir`, `mknod`, `opendir`, `readlink`, `rename`, `rmdir`,
    --- `stat`, `symlink`, `truncate`, `unlink`, `utimensat`, `bind`,
    --- `chmod`, `chown`, `fcntl`, `futimesat`.
    ENOTDIR = nil,
    --- @type integer Directory not empty. Raised by `rmdir`.
    ENOTEMPTY = nil,
    --- @type integer
    ENOTRECOVERABLE = nil,
    --- @type integer Not a socket.
    ---
    --- Raised by `accept`, `bind`, `connect`, `getpeername`,
    --- `getsockname`, `getsockopt`, `listen`, `recv`, `send`,
    --- `shutdown`.
    ENOTSOCK = nil,
    --- @type integer Operation not supported.
    ---
    --- Raised by `chmod`, `clock_getres`, `clock_nanosleep`,
    --- `timer_create`.
    ENOTSUP = nil,
    --- @type integer Inappropriate i/o control operation. Raised by `ioctl`.
    ENOTTY = nil,
    --- @type integer No such device or address. Raised by `lseek`, `open`, `prctl`.
    ENXIO = nil,
    --- @type integer Socket operation not supported.
    ---
    --- Raised by accept, listen, mmap, prctl, readv, send,
    --- socketpair.
    EOPNOTSUPP = nil,
    --- @type integer Raised by `copy_file_range`, `fanotify_init`, `lseek`, `mmap`,
    --- `open`, `stat`, `statfs`
    EOVERFLOW = nil,
    --- @type integer
    EOWNERDEAD = nil,
    --- @type integer Operation not permitted.
    ---
    --- Raised by `accept`, `chmod`, `chown`, `chroot`,
    --- `copy_file_range`, `execve`, `fallocate`, `fanotify_init`,
    --- `fcntl`, `futex`, `get_robust_list`, `getdomainname`,
    --- `getgroups`, `gethostname`, `getpriority`, `getrlimit`,
    --- `getsid`, `gettimeofday`, `idle`, `init_module`, `io_submit`,
    --- `ioctl_console`, `ioctl_ficlonerange`, `ioctl_fideduperange`,
    --- `ioperm`, `iopl`, `ioprio_set`, `keyctl`, `kill`, `link`,
    --- `lookup_dcookie`, `madvise`, `mbind`, `membarrier`,
    --- `migrate_pages`, `mkdir`, `mknod`, `mlock`, `mmap`, `mount`,
    --- `move_pages`, `msgctl`, `nice`, `open`, `open_by_handle_at`,
    --- `pciconfig_read`, `perf_event_open`, `pidfd_getfd`,
    --- `pidfd_send_signal`, `pivot_root`, `prctl`, `process_vm_readv`,
    --- `ptrace`, `quotactl`, `reboot`, `rename`, `request_key`,
    --- `rmdir`, `rt_sigqueueinfo`, `sched_setaffinity`,
    --- `sched_setattr`, `sched_setparam`, `sched_setscheduler`,
    --- `seteuid`, `setfsgid`, `setfsuid`, `setgid`, `setns`, `setpgid`,
    --- `setresuid`, `setreuid`, `setsid`, `setuid`, `setup`,
    --- `setxattr`, `sigaltstack`, `spu_create`, `stime`, `swapon`,
    --- `symlink`, `syslog`, `truncate`, `unlink`, `utime`, `utimensat`,
    --- `write`.
    EPERM = nil,
    --- @type integer Protocol family not supported.
    EPFNOSUPPORT = nil,
    --- @type integer Broken pipe.
    --- Returned by `write`, `send`. This happens when you try
    --- to write data to a subprocess via a pipe but the reader end has
    --- already closed, possibly because the process died. Normally i/o
    --- routines only return this if `SIGPIPE` doesn't kill the process.
    --- Unlike default UNIX programs, redbean currently ignores `SIGPIPE` by
    --- default, so this error code is a distinct possibility when pipes or
    --- sockets are being used.
    EPIPE = nil,
    --- @type integer Raised by `accept`, `connect`, `socket`, `socketpair`.
    EPROTO = nil,
    --- @type integer Protocol not supported. Raised by `socket`, `socketpair`.
    EPROTONOSUPPORT = nil,
    --- @type integer Protocol wrong type for socket. Raised by `connect`.
    EPROTOTYPE = nil,
    --- @type integer Result too large.
    ---
    --- Raised by `prctl`.
    ERANGE = nil,
    --- @type integer
    EREMOTE = nil,
    --- @type integer
    ERESTART = nil,
    --- @type integer Operation not possible due to RF-kill.
    ERFKILL = nil,
    --- @type integer Read-only filesystem.
    ---
    --- Raised by access, bind, chmod, chown, link, mkdir, mknod, open,
    --- rename, rmdir, symlink, truncate, unlink, utime, utimensat.
    EROFS = nil,
    --- @type integer Cannot send after transport endpoint shutdown; note that shutdown write is an `EPIPE`.
    ESHUTDOWN = nil,
    --- @type integer Socket type not supported.
    ESOCKTNOSUPPORT = nil,
    --- @type integer Invalid seek.
    ---
    --- Raised by `lseek`, `splice`, `sync_file_range`.
    ESPIPE = nil,
    --- @type integer No such process.
    ---
    --- Raised by `getpriority`, `getrlimit`, `getsid`, `ioprio_set`, `kill`, `setpgid`, `tkill`, `utimensat`.
    ESRCH = nil,
    --- @type integer
    ESTALE = nil,
    --- @type integer Timer expired. Raised by `connect`.
    ETIME = nil,
    --- @type integer Connection timed out. Raised by `connect`.
    ETIMEDOUT = nil,
    --- @type integer Too many references: cannot splice. Raised by `sendmsg`.
    ETOOMANYREFS = nil,
    --- @type integer Won't open executable that's executing in write mode.
    ---
    --- Raised by access, copy_file_range, execve, mmap, open, truncate.
    ETXTBSY = nil,
    --- @type integer
    EUSERS = nil,

    --- @type integer Improper link.
    ---
    --- Raised by copy_file_range, link, rename.
    EXDEV = nil,

    --- @type integer
    FD_CLOEXEC = nil,

    --- @type integer
    F_GETFD = nil,
    --- @type integer
    F_GETFL = nil,
    --- @type integer
    F_GETLK = nil,
    --- @type integer
    F_OK = nil,
    --- @type integer
    F_RDLCK = nil,
    --- @type integer
    F_SETFD = nil,
    --- @type integer
    F_SETFL = nil,
    --- @type integer
    F_SETLK = nil,
    --- @type integer
    F_SETLKW = nil,
    --- @type integer
    F_UNLCK = nil,
    --- @type integer
    F_WRLCK = nil,

    --- @type integer
    IPPROTO_ICMP = nil,
    --- @type integer
    IPPROTO_IP = nil,
    --- @type integer
    IPPROTO_RAW = nil,
    --- @type integer
    IPPROTO_TCP = nil,
    --- @type integer
    IPPROTO_UDP = nil,

    --- @type integer
    IP_ADD_MEMBERSHIP = nil,
    --- @type integer
    IP_DROP_MEMBERSHIP = nil,
    --- @type integer
    IP_HDRINCL = nil,
    --- @type integer
    IP_MTU = nil,
    --- @type integer
    IP_MULTICAST_IF = nil,
    --- @type integer
    IP_MULTICAST_LOOP = nil,
    --- @type integer
    IP_MULTICAST_TTL = nil,
    --- @type integer
    IP_OPTIONS = nil,
    --- @type integer
    IP_PKTINFO = nil,
    --- @type integer
    IP_RECVTOS = nil,
    --- @type integer
    IP_RECVTTL = nil,
    --- @type integer
    IP_TOS = nil,
    --- @type integer
    IP_TTL = nil,

    --- @type integer
    ITIMER_PROF = nil,
    --- @type integer
    ITIMER_REAL = nil,
    --- @type integer
    ITIMER_VIRTUAL = nil,

    --- @type integer
    LOG_ALERT = nil,
    --- @type integer
    LOG_CRIT = nil,
    --- @type integer
    LOG_DEBUG = nil,
    --- @type integer
    LOG_EMERG = nil,
    --- @type integer
    LOG_ERR = nil,
    --- @type integer
    LOG_INFO = nil,
    --- @type integer
    LOG_NOTICE = nil,
    --- @type integer
    LOG_WARNING = nil,

    --- @type integer
    MSG_CTRUNC = nil,
    --- @type integer
    MSG_DONTROUTE = nil,
    --- @type integer
    MSG_DONTWAIT = nil,
    --- @type integer
    MSG_NOSIGNAL = nil,
    --- @type integer
    MSG_OOB = nil,
    --- @type integer
    MSG_PEEK = nil,
    --- @type integer
    MSG_TRUNC = nil,
    --- @type integer
    MSG_WAITALL = nil,

    --- @type integer  Returns maximum length of file path component.
    ---
    --- POSIX requires this be at least 14. Most operating systems define it
    --- as 255. It's a good idea to not exceed 253 since that's the limit on
    --- DNS labels.
    NAME_MAX = nil,

    --- @type integer Returns maximum number of signals supported by underlying system.
    ---
    --- The limit for unix.Sigset is 128 to support FreeBSD, but most
    --- operating systems define this much lower, like 32. This constant
    --- reflects the value chosen by the underlying operating system.
    NSIG = nil,

    --- @type integer open for reading (default)
    O_RDONLY = nil,
    --- @type integer open for writing
    O_WRONLY = nil,
    --- @type integer open for reading and writing
    O_RDWR = nil,

    --- @type integer create file if it doesn't exist
    O_CREAT = nil,
    --- @type integer automatic `ftruncate(fd, 0)` if exists
    O_TRUNC = nil,
    --- @type integer automatic `close()` upon `execve()`
    O_CLOEXEC = nil,
    --- @type integer exclusive access (see below)
    O_EXCL = nil,
    --- @type integer open file for append only
    O_APPEND = nil,
    --- @type integer asks read/write to fail with EAGAIN rather than block
    O_NONBLOCK = nil,
    --- @type integer it's complicated (not supported on Apple and OpenBSD)
    O_DIRECT = nil,
    --- @type integer useful for stat'ing (hint on UNIX but required on NT)
    O_DIRECTORY = nil,
    --- @type integer fail if it's a symlink (zero on Windows)
    O_NOFOLLOW = nil,
    --- @type integer automatically delete file upon close()
    O_UNLINK = nil,
    --- @type integer open a path reference only, without read/write access
    --- (Linux only; fails with EINVAL elsewhere). Usable with landlock
    --- rule paths and *at() calls even when the path itself is unreadable.
    O_PATH = nil,
    --- @type integer it's complicated (zero on non-Linux/Apple)
    O_DSYNC = nil,
    --- @type integer synchronize i/o operations appropriately
    O_SYNC = nil,
    --- @type integer don't record access time (zero on non-Linux)
    O_NOATIME = nil,

    --- @type integer
    O_ACCMODE = nil,
    --- @type integer
    O_NOCTTY = nil,
    --- @type integer
    O_SYNC = nil,

    --- @type integer Returns maximum length of file path.
    ---
    --- This applies to a complete path being passed to system calls.
    ---
    --- POSIX.1 XSI requires this be at least 1024 so that's what most
    --- platforms support. On Windows NT, the limit is technically 260
    --- characters. Your redbean works around that by prefixing `//?/`
    --- to your paths as needed. On Linux this limit will be 4096, but
    --- that won't be the case for functions such as realpath that are
    --- implemented at the C library level; however such functions are
    --- the exception rather than the norm, and report `enametoolong()`,
    --- when exceeding the libc limit.
    PATH_MAX = nil,

    ---@type integer Causes the violating thread to be killed. This is
    --- the default on Linux. It's effectively the same as killing the
    --- process, since redbean has no threads. The termination signal
    --- can't be caught and will be either `SIGSYS` or `SIGABRT`.
    --- Consider enabling stderr logging below so you'll know why your
    --- program failed. Otherwise check the system log.
    PLEDGE_PENALTY_KILL_THREAD = nil,

    ---@type integer Causes the process and all its threads to be killed.
    --- This is always the case on OpenBSD.
    PLEDGE_PENALTY_KILL_PROCESS = nil,

    ---@type integer Causes system calls to just return an `EPERM` error
    --- instead of killing. This is a gentler solution that allows code to
    --- display a friendly warning. Please note this may lead to weird
    --- behaviors if the software being sandboxed is lazy about checking
    --- error results.
    PLEDGE_PENALTY_RETURN_EPERM = nil,

    ---@type integer Enables friendly error message logging letting you
    --- know which promises are needed whenever violations occur. Without
    --- this, violations will be logged to `dmesg` on Linux if the penalty
    --- is to kill the process. You would then need to manually look up
    --- the system call number and then cross reference it with the
    --- cosmopolitan libc `pledge()` documentation. You can also use
    --- `strace -ff` which is easier. This is ignored OpenBSD, which
    --- already has a good system log. Turning on stderr logging (which
    --- uses SECCOMP trapping) also means that the `unix.WTERMSIG()` on
    --- your killed processes will always be `unix.SIGABRT` on both Linux
    --- and OpenBSD. Otherwise, Linux prefers to raise `unix.SIGSYS`.
    PLEDGE_STDERR_LOGGING = nil,

    --- @type integer Returns maximum size at which pipe i/o is guaranteed atomic.
    ---
    --- POSIX requires this be at least 512. Linux is more generous and
    --- allows 4096. On Windows NT this is currently 4096, and it's the
    --- parameter redbean passes to `CreateNamedPipe()`.
    PIPE_BUF = nil,

    --- @type integer
    POLLERR = nil,
    --- @type integer
    POLLHUP = nil,
    --- @type integer
    POLLIN = nil,
    --- @type integer
    POLLNVAL = nil,
    --- @type integer
    POLLOUT = nil,
    --- @type integer
    POLLPRI = nil,
    --- @type integer
    POLLRDBAND = nil,
    --- @type integer
    POLLRDHUP = nil,
    --- @type integer
    POLLRDNORM = nil,
    --- @type integer
    POLLWRBAND = nil,
    --- @type integer
    POLLWRNORM = nil,

    --- @type integer
    RLIMIT_AS = nil,
    --- @type integer
    RLIMIT_CPU = nil,
    --- @type integer
    RLIMIT_FSIZE = nil,
    --- @type integer
    RLIMIT_NOFILE = nil,
    --- @type integer
    RLIMIT_NPROC = nil,
    --- @type integer
    RLIMIT_RSS = nil,

    --- @type integer getpriority/setpriority: target is a process id
    PRIO_PROCESS = nil,
    --- @type integer getpriority/setpriority: target is a process group id
    PRIO_PGRP = nil,
    --- @type integer getpriority/setpriority: target is a user id
    PRIO_USER = nil,

    --- @type integer sysconf: maximum length of arguments to exec()
    SC_ARG_MAX = nil,
    --- @type integer sysconf: maximum simultaneous processes per user id
    SC_CHILD_MAX = nil,
    --- @type integer sysconf: clock ticks per second
    SC_CLK_TCK = nil,
    --- @type integer sysconf: maximum number of open files per process
    SC_OPEN_MAX = nil,
    --- @type integer sysconf: size of a memory page in bytes
    SC_PAGESIZE = nil,
    --- @type integer sysconf: number of processors configured
    SC_NPROCESSORS_CONF = nil,
    --- @type integer sysconf: number of processors currently online
    SC_NPROCESSORS_ONLN = nil,

    --- @type integer termios input mode flags (Termios.iflag)
    BRKINT = nil,
    ICRNL = nil,
    IGNBRK = nil,
    IGNCR = nil,
    IGNPAR = nil,
    INLCR = nil,
    INPCK = nil,
    ISTRIP = nil,
    IXANY = nil,
    IXOFF = nil,
    IXON = nil,
    PARMRK = nil,

    --- @type integer termios output mode flags (Termios.oflag)
    OPOST = nil,
    OCRNL = nil,
    ONLCR = nil,
    ONLRET = nil,
    ONOCR = nil,

    --- @type integer termios control mode flags (Termios.cflag)
    CLOCAL = nil,
    CREAD = nil,
    CS5 = nil,
    CS6 = nil,
    CS7 = nil,
    CS8 = nil,
    CSIZE = nil,
    CSTOPB = nil,
    HUPCL = nil,
    PARENB = nil,
    PARODD = nil,

    --- @type integer termios local mode flags (Termios.lflag)
    ECHO = nil,
    ECHOE = nil,
    ECHOK = nil,
    ECHONL = nil,
    ICANON = nil,
    IEXTEN = nil,
    ISIG = nil,
    NOFLSH = nil,
    TOSTOP = nil,

    --- @type integer termios control-character indices (Termios.cc)
    VEOF = nil,
    VEOL = nil,
    VERASE = nil,
    VINTR = nil,
    VKILL = nil,
    VMIN = nil,
    VQUIT = nil,
    VSTART = nil,
    VSTOP = nil,
    VTIME = nil,
    NCCS = nil,

    --- @type integer tcsetattr() action values
    TCSANOW = nil,
    TCSADRAIN = nil,
    TCSAFLUSH = nil,

    --- @type integer network interface ioctls (siocgifconf/ifreq)
    IFNAMSIZ = nil,
    IFF_ALLMULTI = nil,
    IFF_AUTOMEDIA = nil,
    IFF_BROADCAST = nil,
    IFF_DEBUG = nil,
    IFF_DYNAMIC = nil,
    IFF_LOOPBACK = nil,
    IFF_MASTER = nil,
    IFF_MULTICAST = nil,
    IFF_NOARP = nil,
    IFF_NOTRAILERS = nil,
    IFF_POINTOPOINT = nil,
    IFF_PORTSEL = nil,
    IFF_PROMISC = nil,
    IFF_RUNNING = nil,
    IFF_SLAVE = nil,
    IFF_UP = nil,
    SIOCGIFADDR = nil,
    SIOCGIFBRDADDR = nil,
    SIOCGIFDSTADDR = nil,
    SIOCGIFFLAGS = nil,
    SIOCGIFINDEX = nil,
    SIOCGIFMETRIC = nil,
    SIOCGIFMTU = nil,
    SIOCGIFNAME = nil,
    SIOCGIFNETMASK = nil,
    SIOCSIFADDR = nil,
    SIOCSIFBRDADDR = nil,
    SIOCSIFDSTADDR = nil,
    SIOCSIFFLAGS = nil,
    SIOCSIFMETRIC = nil,
    SIOCSIFMTU = nil,
    SIOCSIFNETMASK = nil,

    --- @type integer unshare()/setns() namespace flags
    CLONE_NEWCGROUP = nil,
    CLONE_NEWIPC = nil,
    CLONE_NEWNET = nil,
    CLONE_NEWNS = nil,
    CLONE_NEWPID = nil,
    CLONE_NEWTIME = nil,
    CLONE_NEWUSER = nil,
    CLONE_NEWUTS = nil,

    --- @type integer landlock access-rights bits (landlock_add_rule)
    LANDLOCK_ACCESS_FS_EXECUTE = nil,
    LANDLOCK_ACCESS_FS_WRITE_FILE = nil,
    LANDLOCK_ACCESS_FS_READ_FILE = nil,
    LANDLOCK_ACCESS_FS_READ_DIR = nil,
    LANDLOCK_ACCESS_FS_REMOVE_DIR = nil,
    LANDLOCK_ACCESS_FS_REMOVE_FILE = nil,
    LANDLOCK_ACCESS_FS_MAKE_CHAR = nil,
    LANDLOCK_ACCESS_FS_MAKE_DIR = nil,
    LANDLOCK_ACCESS_FS_MAKE_REG = nil,
    LANDLOCK_ACCESS_FS_MAKE_SOCK = nil,
    LANDLOCK_ACCESS_FS_MAKE_FIFO = nil,
    LANDLOCK_ACCESS_FS_MAKE_BLOCK = nil,
    LANDLOCK_ACCESS_FS_MAKE_SYM = nil,
    LANDLOCK_ACCESS_FS_REFER = nil,
    LANDLOCK_ACCESS_FS_TRUNCATE = nil,
    LANDLOCK_CREATE_RULESET_VERSION = nil,
    LANDLOCK_RULE_PATH_BENEATH = nil,

    --- @type integer prctl() options
    PR_CAPBSET_DROP = nil,
    PR_CAPBSET_READ = nil,
    PR_GET_CHILD_SUBREAPER = nil,
    PR_GET_DUMPABLE = nil,
    PR_GET_KEEPCAPS = nil,
    PR_GET_NAME = nil,
    PR_GET_NO_NEW_PRIVS = nil,
    PR_GET_PDEATHSIG = nil,
    PR_SET_CHILD_SUBREAPER = nil,
    PR_SET_DUMPABLE = nil,
    PR_SET_KEEPCAPS = nil,
    PR_SET_NAME = nil,
    PR_SET_NO_NEW_PRIVS = nil,
    PR_SET_PDEATHSIG = nil,

    --- @type integer Linux capability bits (prctl PR_CAPBSET_*, capget/capset).
    CAP_AUDIT_CONTROL = nil,
    CAP_AUDIT_READ = nil,
    CAP_AUDIT_WRITE = nil,
    CAP_BLOCK_SUSPEND = nil,
    CAP_BPF = nil,
    CAP_CHECKPOINT_RESTORE = nil,
    CAP_CHOWN = nil,
    CAP_DAC_OVERRIDE = nil,
    CAP_DAC_READ_SEARCH = nil,
    CAP_FOWNER = nil,
    CAP_FSETID = nil,
    CAP_IPC_LOCK = nil,
    CAP_IPC_OWNER = nil,
    CAP_KILL = nil,
    CAP_LAST_CAP = nil,
    CAP_LEASE = nil,
    CAP_LINUX_IMMUTABLE = nil,
    CAP_MAC_ADMIN = nil,
    CAP_MAC_OVERRIDE = nil,
    CAP_MKNOD = nil,
    CAP_NET_ADMIN = nil,
    CAP_NET_BIND_SERVICE = nil,
    CAP_NET_BROADCAST = nil,
    CAP_NET_RAW = nil,
    CAP_PERFMON = nil,
    CAP_SETFCAP = nil,
    CAP_SETGID = nil,
    CAP_SETPCAP = nil,
    CAP_SETUID = nil,
    CAP_SYSLOG = nil,
    CAP_SYS_ADMIN = nil,
    CAP_SYS_BOOT = nil,
    CAP_SYS_CHROOT = nil,
    CAP_SYS_MODULE = nil,
    CAP_SYS_NICE = nil,
    CAP_SYS_PACCT = nil,
    CAP_SYS_PTRACE = nil,
    CAP_SYS_RAWIO = nil,
    CAP_SYS_RESOURCE = nil,
    CAP_SYS_TIME = nil,
    CAP_SYS_TTY_CONFIG = nil,
    CAP_WAKE_ALARM = nil,

    --- @type integer mount()/umount2() flags
    MS_BIND = nil,
    MS_DIRSYNC = nil,
    MS_LAZYTIME = nil,
    MS_MANDLOCK = nil,
    MS_MOVE = nil,
    MS_NOATIME = nil,
    MS_NODEV = nil,
    MS_NODIRATIME = nil,
    MS_NOEXEC = nil,
    MS_NOSUID = nil,
    MS_POSIXACL = nil,
    MS_PRIVATE = nil,
    MS_RDONLY = nil,
    MS_REC = nil,
    MS_RELATIME = nil,
    MS_REMOUNT = nil,
    MS_SHARED = nil,
    MS_SILENT = nil,
    MS_SLAVE = nil,
    MS_STRICTATIME = nil,
    MS_SYNCHRONOUS = nil,
    MS_UNBINDABLE = nil,
    MNT_DETACH = nil,
    MNT_EXPIRE = nil,
    MNT_FORCE = nil,
    UMOUNT_NOFOLLOW = nil,

    --- @type integer statvfs f_flag bits (unix.Statfs / statvfs)
    ST_APPEND = nil,
    ST_IMMUTABLE = nil,
    ST_MANDLOCK = nil,
    ST_NOATIME = nil,
    ST_NODEV = nil,
    ST_NODIRATIME = nil,
    ST_NOEXEC = nil,
    ST_NOSUID = nil,
    ST_RDONLY = nil,
    ST_RELATIME = nil,
    ST_SYNCHRONOUS = nil,
    ST_WRITE = nil,

    --- @type integer
    RUSAGE_BOTH = nil,
    --- @type integer
    RUSAGE_CHILDREN = nil,
    --- @type integer
    RUSAGE_SELF = nil,
    --- @type integer
    RUSAGE_THREAD = nil,

    --- @type integer
    R_OK = nil,

    --- @type integer
    SA_NOCLDSTOP = nil,
    --- @type integer
    SA_NOCLDWAIT = nil,
    --- @type integer
    SA_NODEFER = nil,
    --- @type integer
    SA_RESETHAND = nil,
    --- @type integer
    SA_RESTART = nil,

    --- @type integer
    SEEK_CUR = nil,
    --- @type integer
    SEEK_END = nil,
    --- @type integer
    SEEK_SET = nil,

    ---@type integer sends a tcp half close for reading
    SHUT_RD = nil,
    ---@type integer sends a tcp half close for writing
    SHUT_WR = nil,
    ---@type integer
    SHUT_RDWR = nil,

    --- @type integer Process aborted.
    SIGABRT = nil,
    --- @type integer Sent by setitimer().
    SIGALRM = nil,
    --- @type integer Valid memory access that went beyond underlying end of file.
    SIGBUS = nil,
    --- @type integer Child process exited or terminated and is now a zombie (unless this
    --- is `SIG_IGN` or `SA_NOCLDWAIT`) or child process stopped due to terminal
    --- i/o or profiling/debugging (unless you used `SA_NOCLDSTOP`)
    SIGCHLD = nil,
    --- @type integer Child process resumed from profiling/debugging.
    SIGCONT = nil,
    --- @type integer Illegal math.
    SIGFPE = nil,
    --- @type integer Terminal hangup or daemon reload; auto-broadcasted to process group.
    SIGHUP = nil,
    --- @type integer Illegal instruction.
    SIGILL = nil,
    --- @type integer Terminal CTRL-C keystroke.
    SIGINT = nil,
    --- @type integer Terminate with extreme prejudice.
    SIGKILL = nil,
    --- @type integer Write to closed file descriptor.
    SIGPIPE = nil,
    --- @type integer Profiling timer expired.
    SIGPROF = nil,
    --- @type integer Terminal CTRL-\ keystroke.
    SIGQUIT = nil,
    --- @type integer Invalid memory access.
    SIGSEGV = nil,
    --- @type integer Child process stopped due to profiling/debugging.
    SIGSTOP = nil,
    --- @type integer
    SIGSYS = nil,
    --- @type integer Terminate.
    SIGTERM = nil,
    --- @type integer INT3 instruction.
    SIGTRAP = nil,
    --- @type integer Terminal CTRL-Z keystroke.
    SIGTSTP = nil,
    --- @type integer Terminal input for background process.
    SIGTTIN = nil,
    --- @type integer Terminal input for background process.
    SIGTTOU = nil,
    --- @type integer
    SIGURG = nil,
    --- @type integer Do whatever you want.
    SIGUSR1 = nil,
    --- @type integer Do whatever you want.
    SIGUSR2 = nil,
    --- @type integer Virtual alarm clock.
    SIGVTALRM = nil,
    --- @type integer Terminal resized.
    SIGWINCH = nil,
    --- @type integer CPU time limit exceeded.
    SIGXCPU = nil,
    --- @type integer File size limit exceeded.
    SIGXFSZ = nil,

    --- @type integer
    SIG_BLOCK = nil,
    --- @type integer
    SIG_DFL = nil,
    --- @type integer
    SIG_IGN = nil,
    --- @type integer
    SIG_SETMASK = nil,
    --- @type integer
    SIG_UNBLOCK = nil,

    --- @type integer
    SOCK_CLOEXEC = nil,
    --- @type integer
    SOCK_DGRAM = nil,
    --- @type integer
    SOCK_NONBLOCK = nil,
    --- @type integer
    SOCK_RAW = nil,
    --- @type integer
    SOCK_RDM = nil,
    --- @type integer
    SOCK_SEQPACKET = nil,
    --- @type integer
    SOCK_STREAM = nil,

    --- @type integer
    SOL_IP = nil,
    --- @type integer
    SOL_SOCKET = nil,
    --- @type integer
    SOL_TCP = nil,
    --- @type integer
    SOL_UDP = nil,

    --- @type integer
    SO_ACCEPTCONN = nil,
    --- @type integer
    SO_BROADCAST = nil,
    --- @type integer
    SO_DEBUG = nil,
    --- @type integer
    SO_DONTROUTE = nil,
    --- @type integer
    SO_ERROR = nil,
    --- @type integer
    SO_KEEPALIVE = nil,
    --- @type integer
    SO_LINGER = nil,
    --- @type integer
    SO_NOSIGPIPE = nil,
    --- @type integer
    SO_OOBINLINE = nil,
    --- @type integer
    SO_RCVBUF = nil,
    --- @type integer
    SO_RCVLOWAT = nil,
    --- @type integer
    SO_RCVTIMEO = nil,
    --- @type integer
    SO_REUSEADDR = nil,
    --- @type integer
    SO_REUSEPORT = nil,
    --- @type integer
    SO_SNDBUF = nil,
    --- @type integer
    SO_SNDLOWAT = nil,
    --- @type integer
    SO_SNDTIMEO = nil,
    --- @type integer
    SO_TYPE = nil,

    --- @type integer
    TCP_CORK = nil,
    --- @type integer
    TCP_DEFER_ACCEPT = nil,
    --- @type integer
    TCP_FASTOPEN = nil,
    --- @type integer
    TCP_FASTOPEN_CONNECT = nil,
    --- @type integer
    TCP_KEEPCNT = nil,
    --- @type integer
    TCP_KEEPIDLE = nil,
    --- @type integer
    TCP_KEEPINTVL = nil,
    --- @type integer
    TCP_MAXSEG = nil,
    --- @type integer
    TCP_NODELAY = nil,
    --- @type integer
    TCP_NOTSENT_LOWAT = nil,
    --- @type integer
    TCP_QUICKACK = nil,
    --- @type integer
    TCP_SAVED_SYN = nil,
    --- @type integer
    TCP_SAVE_SYN = nil,
    --- @type integer
    TCP_SYNCNT = nil,
    --- @type integer
    TCP_WINDOW_CLAMP = nil,

    --- @type integer
    UTIME_NOW = nil,
    --- @type integer
    UTIME_OMIT = nil,

    --- @type integer
    WNOHANG = nil,
    --- @type integer
    WUNTRACED = nil,
    --- @type integer Report continued child processes.
    WCONTINUED = nil,

    --- @type integer
    W_OK = nil,

    --- @type integer
    X_OK = nil
}

--- Opens file.
---
--- Returns a file descriptor integer that needs to be closed, e.g.
---
---     fd = assert(unix.open("/etc/passwd", unix.O_RDONLY))
---     print(unix.read(fd))
---     unix.close(fd)
---
--- `flags` should have one of:
---
--- - `O_RDONLY`:     open for reading (default)
--- - `O_WRONLY`:     open for writing
--- - `O_RDWR`:       open for reading and writing
---
--- The following values may also be OR'd into `flags`:
---
---  - `O_CREAT`      create file if it doesn't exist
---  - `O_TRUNC`      automatic ftruncate(fd,0) if exists
---  - `O_CLOEXEC`    automatic close() upon execve()
---  - `O_EXCL`       exclusive access (see below)
---  - `O_APPEND`     open file for append only
---  - `O_NONBLOCK`   asks read/write to fail with EAGAIN rather than block
---  - `O_DIRECTORY`  useful for stat'ing (hint on UNIX but required on NT)
---  - `O_NOFOLLOW`   fail if it's a symlink (zero on Windows)
---  - `O_UNLINK`     automatically delete file upon close()
---  - `O_SYNC`       makes file operations synchronize appropriately
---  - `O_RSYNC`      synchronize read() operations
---  - `O_DSYNC`      synchronize write() operations
---  - `O_DIRECT`     it's complicated (not supported on Apple and OpenBSD)
---  - `O_NOATIME`    don't record access time (zero on non-Linux)
---
---  There are three regular combinations for the above flags:
---
---  - `O_RDONLY`: Opens existing file for reading. If it doesn't exist
---    then nil is returned and errno will be `ENOENT` (or in some other
---    cases `ENOTDIR`).
---
---  - `O_WRONLY|O_CREAT|O_TRUNC`: Creates file. If it already exists,
---    then the existing copy is destroyed and the opened file will
---    start off with a length of zero. This is the behavior of the
---    traditional creat() system call.
---
---  - `O_WRONLY|O_CREAT|O_EXCL`: Create file only if doesn't exist
---    already. If it does exist then `nil` is returned along with
---    `errno` set to `EEXIST`.
---
--- `dirfd` defaults to to `unix.AT_FDCWD` and may optionally be set to
--- a directory file descriptor to which `path` is relative.
---
--- Returns `ENOENT` if `path` doesn't exist.
---
--- Returns `ENOTDIR` if `path` contained a directory component that
--- wasn't a directory
---.
---@param path string
---@param flags integer
---@param mode integer?
---@param dirfd integer?
---@return integer|nil fd
---@return string? error
---@return integer? errno
---@nodiscard
function unix.open(path, flags, mode, dirfd) end

--- Closes file descriptor.
---
--- This function should never be called twice for the same file
--- descriptor, regardless of whether or not an error happened. The file
--- descriptor is always gone after close is called. So it technically
--- always succeeds, but that doesn't mean an error should be ignored.
--- For example, on NFS a close failure could indicate data loss.
---
--- Closing does not mean that scheduled i/o operations have been
--- completed. You'd need to use fsync() or fdatasync() beforehand to
--- ensure that. You shouldn't need to do that normally, because our
--- close implementation guarantees a consistent view, since on systems
--- where it isn't guaranteed (like Windows) close will implicitly sync.
---
--- File descriptors are automatically closed on exit().
---
--- Returns `EBADF` if `fd` wasn't valid.
---
--- Returns `EINTR` possibly maybe.
---
--- Returns `EIO` if an i/o error occurred.
---@param fd integer
---@return true|nil
---@return string? error
---@return integer? errno
function unix.close(fd) end

--- Reads from file descriptor.
---
--- This function returns empty string on end of file. The exception is
--- if `bufsiz` is zero, in which case an empty returned string means
--- the file descriptor works.
---@param fd integer
---@param bufsiz integer?
---@param offset integer?
---@return string|nil data
---@return string? error
---@return integer? errno
function unix.read(fd, bufsiz, offset) end

--- Writes to file descriptor.
---@param fd integer
---@param data string
---@param offset integer?
---@return integer|nil wrotebytes
---@return string? error
---@return integer? errno
function unix.write(fd, data, offset) end

--- Invokes `_Exit(exitcode)` on the process. This will immediately
--- halt the current process. Memory will be freed. File descriptors
--- will be closed. Any open connections it owns will be reset. This
--- function never returns.
---@param exitcode integer?
function unix.exit(exitcode) end

--- Returns raw environment variables.
---
--- This allocates and constructs the C/C++ `environ` variable as a Lua
--- table consisting of string keys and string values.
---
--- This data structure preserves casing. On Windows NT, by convention,
--- environment variable keys are treated in a case-insensitive way. It
--- is the responsibility of the caller to consider this.
---
--- This data structure preserves valueless variables. It's possible on
--- both UNIX and Windows to have an environment variable without an
--- equals, even though it's unusual.
---
--- This data structure preserves duplicates. For example, on Windows,
--- there's some irregular uses of environment variables such as how the
--- command prompt inserts multiple environment variables with empty
--- string as keys, for its internal bookkeeping.
---
---@return string[] environ list of `"KEY=value"` strings
---@nodiscard
function unix.environ() end

--- Sets environment variable.
---
--- This wraps the C `setenv()` function to allow Lua scripts to set
--- environment variables.
---
---@param name string environment variable name
---@param value string value to set
---@param overwrite? boolean if false, won't overwrite existing variables (defaults to true)
---@return true|nil
---@return string? error
---@return integer? errno
function unix.setenv(name, value, overwrite) end

--- Unsets environment variable.
---
--- This wraps the C `unsetenv()` function to allow Lua scripts to remove
--- environment variables.
---
---@param name string environment variable name to unset
---@return true|nil
---@return string? error
---@return integer? errno
function unix.unsetenv(name) end

--- Clears all environment variables.
---
--- This wraps the C `clearenv()` function to allow Lua scripts to remove
--- all environment variables at once.
---
---@return true|nil
---@return string? error
---@return integer? errno
function unix.clearenv() end

--- Gets login name of current user.
---
--- This wraps the C `getlogin()` function to retrieve the login name
--- associated with the current session.
---
---@return string|nil login name
---@return string? error
---@return integer? errno
function unix.getlogin() end

--- Creates a new process mitosis style.
---
--- This system call returns twice. The parent process gets the nonzero
--- pid. The child gets zero.
---
--- Here's a simple usage example of creating subprocesses, where we
--- fork off a child worker from a main process hook callback to do some
--- independent chores, such as sending an HTTP request back to redbean.
---
---    -- as soon as server starts, make a fetch to the server
---    -- then signal redbean to shutdown when fetch is complete
---    local onServerStart = function()
---       if assert(unix.fork()) == 0 then
---          local ok, headers, body = Fetch('http://127.0.0.1:8080/test')
---          unix.kill(unix.getppid(), unix.SIGTERM)
---          unix.exit(0)
---       end
---    end
---    OnServerStart = onServerStart
---
--- We didn't need to use `wait()` here, because (a) we want redbean to go
--- back to what it was doing before as the `Fetch()` completes, and (b)
--- redbean's main process already has a zombie collector. However it's
--- a moot point, since once the fetch is done, the child process then
--- asks redbean to gracefully shutdown by sending SIGTERM its parent.
---
--- This is actually a situation where we *must* use fork, because the
--- purpose of the main redbean process is to call accept() and create
--- workers. So if we programmed redbean to use the main process to send
--- a blocking request to itself instead, then redbean would deadlock
--- and never be able to accept() the client.
---
--- While deadlocking is an extreme example, the truth is that latency
--- issues can crop up for the same reason that just cause jitter
--- instead, and as such, can easily go unnoticed. For example, if you
--- do soemething that takes longer than a few milliseconds from inside
--- your redbean heartbeat, then that's a few milliseconds in which
--- redbean is no longer concurrent, and tail latency is being added to
--- its ability to accept new connections. fork() does a great job at
--- solving this.
---
--- If you're not sure how long something will take, then when in doubt,
--- fork off a process. You can then report its completion to something
--- like SQLite. Redbean makes having lots of processes cheap. On Linux
--- they're about as lightweight as what heavyweight environments call
--- greenlets. You can easily have 10,000 Redbean workers on one PC.
---
--- Here's some benchmarks for fork() performance across platforms:
---
---    Linux 5.4 fork      l:     97,200𝑐    31,395𝑛𝑠  [metal]
---    FreeBSD 12 fork     l:    236,089𝑐    78,841𝑛𝑠  [vmware]
---    Darwin 20.6 fork    l:    295,325𝑐    81,738𝑛𝑠  [metal]
---    NetBSD 9 fork       l:  5,832,027𝑐 1,947,899𝑛𝑠  [vmware]
---    OpenBSD 6.8 fork    l: 13,241,940𝑐 4,422,103𝑛𝑠  [vmware]
---    Windows10 fork      l: 18,802,239𝑐 6,360,271𝑛𝑠  [metal]
---
--- One of the benefits of using `fork()` is it creates an isolation
--- barrier between the different parts of your app. This can lead to
--- enhanced reliability and security. For example, redbean uses fork so
--- it can wipe your ssl keys from memory before handing over control to
--- request handlers that process untrusted input. It also ensures that
--- if your Lua app crashes, it won't take down the server as a whole.
--- Hence it should come as no surprise that `fork()` would go slower on
--- operating systems that have more security features. So depending on
--- your use case, you can choose the operating system that suits you.
---
---@return integer|0|nil childpid
---@return string? error
---@return integer? errno
function unix.fork() end

--- Performs `$PATH` lookup of executable.
---
---     unix = require 'unix'
---     prog = assert(unix.commandv('ls'))
---     unix.execve(prog, {prog, '-hal', '.'}, {'PATH=/bin'})
---     unix.exit(127)
---
--- If `prog` is an absolute path, then it's returned as-is. If `prog`
--- contains slashes then it's not path searched either and will be
--- returned if it exists. On Windows, it's recommended that you install
--- programs from cosmos to c:/bin/ without any .exe or .com suffix, so
--- they can be discovered like they would on UNIX. If you want to find
--- a program like notepad on the $PATH using this function, then you
--- need to specify "notepad.exe" so it includes the extension.
---
---@param prog string
---@return string|nil path
---@return string? error
---@return integer? errno
function unix.commandv(prog) end

--- Exits current process, replacing it with a new instance of the
--- specified program. `prog` needs to be an absolute path, see
--- commandv(). `env` defaults to to the current `environ`. Here's
--- a basic usage example:
---
---     unix.execve("/bin/ls", {"/bin/ls", "-hal"}, {"PATH=/bin"})
---     unix.exit(127)
---
--- `prog` needs to be the resolved pathname of your executable. You
--- can use commandv() to search your `PATH`.
---
--- `args` is a string list table. The first element in `args`
--- should be `prog`. Values are coerced to strings. This parameter
--- defaults to `{prog}`.
---
--- `env` is a string list table. Values are coerced to strings. No
--- ordering requirement is imposed. By convention, each string has its
--- key and value divided by an equals sign without spaces. If this
--- parameter is not specified, it'll default to the C/C++ `environ`
--- variable which is inherited from the shell that launched redbean.
--- It's the responsibility of the user to supply a sanitized environ
--- when spawning untrusted processes.
---
--- `execve()` is normally called after `fork()` returns `0`. If that isn't
--- the case, then your redbean worker will be destroyed.
---
--- This function never returns on success.
---
--- `EAGAIN` is returned if you've enforced a max number of
--- processes using `setrlimit(RLIMIT_NPROC)`.
---
---@param prog string
---@param args string[]
---@param env string[]
---@return nil
---@return string? error
---@return integer? errno
function unix.execve(prog, args, env) end

--- Executes program with PATH search.
---
--- Unlike `execve()`, this function searches for `prog` in the
--- directories listed in the `PATH` environment variable.
---
--- If `argv` is not provided, it defaults to `{prog}`.
---
--- This function never returns on success.
---
---@param prog string
---@param argv? string[]
---@return nil
---@return string? error
---@return integer? errno
function unix.execvp(prog, argv) end

--- Executes program with PATH search and custom environment.
---
--- Like `execvp()` but also allows specifying a custom environment.
---
--- `envp` is a string list table where each string is typically
--- in the form `"KEY=value"`. If not specified, inherits the
--- current environment.
---
--- This function never returns on success.
---
---@param prog string
---@param argv string[]
---@param envp? string[]
---@return nil
---@return string? error
---@return integer? errno
function unix.execvpe(prog, argv, envp) end

--- Executes program from file descriptor.
---
--- This allows executing a program that has already been opened,
--- which can be useful for executing programs that have been
--- verified or for executing APE (Actually Portable Executable)
--- binaries.
---
--- `fd` is an open file descriptor pointing to an executable.
---
--- `argv` is the argument vector passed to the program.
---
--- `envp` is the environment. If not specified, inherits the
--- current environment.
---
--- This function never returns on success.
---
---@param fd integer
---@param argv string[]
---@param envp? string[]
---@return nil
---@return string? error
---@return integer? errno
function unix.fexecve(fd, argv, envp) end

--- Spawns a new process.
---
--- Unlike `fork()` + `execve()`, this uses `posix_spawn()` which
--- can be more efficient on some platforms.
---
--- `prog` must be an explicit path to the executable.
---
--- `argv` is the argument vector passed to the program.
---
--- `envp` is the environment. If not specified, inherits the
--- current environment.
---
--- Returns the child process id on success.
---
---@param prog string
---@param argv string[]
---@param envp? string[]
---@return integer|nil pid
---@return string? error
---@return integer? errno
function unix.spawn(prog, argv, envp) end

--- Spawns a new process with PATH search.
---
--- Like `spawn()` but searches for `prog` in the directories
--- listed in the `PATH` environment variable.
---
--- Returns the child process id on success.
---
---@param prog string
---@param argv string[]
---@param envp? string[]
---@return integer|nil pid
---@return string? error
---@return integer? errno
function unix.spawnp(prog, argv, envp) end

--- Duplicates file descriptor.
---
--- `newfd` may be specified to choose a specific number for the new
--- file descriptor. If it's already open, then the preexisting one will
--- be silently closed. `EINVAL` is returned if `newfd` equals `oldfd`.
---
--- `flags` can have `O_CLOEXEC` which means the returned file
--- descriptors will be automatically closed upon execve().
---
--- `lowest` defaults to zero and defines the lowest numbered file
--- descriptor that's acceptable to use. If `newfd` is specified then
--- `lowest` is ignored. For example, if you wanted to duplicate
--- standard input, then:
---
---     stdin2 = assert(unix.dup(0, nil, unix.O_CLOEXEC, 3))
---
--- Will ensure that, in the rare event standard output or standard
--- error are closed, you won't accidentally duplicate standard input to
--- those numbers.
---
---@param oldfd integer
---@param newfd integer?
---@param flags integer?
---@param lowest integer?
---@return integer|nil newfd
---@return string? error
---@return integer? errno
function unix.dup(oldfd, newfd, flags, lowest) end

--- Creates fifo which enables communication between processes.
---
---@param flags integer? may have any combination (using bitwise OR) of:
---
--- - `O_CLOEXEC`: Automatically close file descriptor upon execve()
---
--- - `O_NONBLOCK`: Request `EAGAIN` be raised rather than blocking
---
--- - `O_DIRECT`: Enable packet mode w/ atomic reads and writes, so long
---   as they're no larger than `PIPE_BUF` (guaranteed to be 512+ bytes)
---   with support limited to Linux, Windows NT, FreeBSD, and NetBSD.
---
--- Returns two file descriptors: one for reading and one for writing.
---
--- Here's an example of how pipe(), fork(), dup(), etc. may be used
--- to serve an HTTP response containing the output of a subprocess.
---
---     local unix = require "unix"
---     ls = assert(unix.commandv("ls"))
---     reader, writer = assert(unix.pipe())
---     if assert(unix.fork()) == 0 then
---        unix.close(1)
---        unix.dup(writer)
---        unix.close(writer)
---        unix.close(reader)
---        unix.execve(ls, {ls, "-Shal"})
---        unix.exit(127)
---     else
---        unix.close(writer)
---        SetHeader('Content-Type', 'text/plain')
---        while true do
---           data, err, errno = unix.read(reader)
---           if data then
---              if data ~= "" then
---                 Write(data)
---              else
---                 break
---              end
---           elseif errno ~= EINTR then
---              Log(kLogWarn, err)
---              break
---           end
---        end
---        assert(unix.close(reader))
---        assert(unix.wait())
---     end
---
---@return integer|nil reader, integer writer
---@return string? error
---@return integer? errno
---@nodiscard
function unix.pipe(flags) end

--- Waits for subprocess to terminate.
---
--- `pid` defaults to `-1` which means any child process. Setting
--- `pid` to `0` is equivalent to `-getpid()`. If `pid < -1` then
--- that means wait for any pid in the process group `-pid`. Then
--- lastly if `pid > 0` then this waits for a specific process id
---
--- Options may have `WNOHANG` which means don't block, check for
--- the existence of processes that are already dead (technically
--- speaking zombies) and if so harvest them immediately.
---
--- Returns the process id of the child that terminated. In other
--- cases, the returned `pid` is nil and `errno` is non-nil.
---
--- The returned `wstatus` contains information about the process
--- exit status. It's a complicated integer and there's functions
--- that can help interpret it. For example:
---
---     -- wait for zombies
---     -- traditional technique for SIGCHLD handlers
---     while true do
---        pid, status, errno = unix.wait(-1, unix.WNOHANG)
---        if pid then
---           if unix.WIFEXITED(status) then
---              print('child', pid, 'exited with',
---                    unix.WEXITSTATUS(status))
---           elseif unix.WIFSIGNALED(status) then
---              print('child', pid, 'crashed with',
---                    unix.strsignal(unix.WTERMSIG(status)))
---           end
---        elseif errno == unix.ECHILD then
---           Log(kLogDebug, 'no more zombies')
---           break
---        else
---           Log(kLogWarn, status)
---           break
---        end
---     end
---
---@param pid? integer
---@param options? integer
---@return integer|nil pid, integer wstatus, unix.Rusage rusage
---@return string? error
---@return integer? errno
function unix.wait(pid, options) end

--- Returns `true` if process exited cleanly.
---@param wstatus integer
---@return boolean
---@nodiscard
function unix.WIFEXITED(wstatus) end

--- Returns code passed to exit() assuming `WIFEXITED(wstatus)` is true.
---@param wstatus integer
---@return integer exitcode uint8
---@nodiscard
function unix.WEXITSTATUS(wstatus) end

--- Returns `true` if process terminated due to a signal.
---@param wstatus integer
---@return boolean
---@nodiscard
function unix.WIFSIGNALED(wstatus) end

--- Returns signal that caused process to terminate assuming
--- `WIFSIGNALED(wstatus)` is `true`.
---@param wstatus integer
---@return integer sig uint8
---@nodiscard
function unix.WTERMSIG(wstatus) end

--- Returns process id of current process.
---
--- This function does not fail.
---@return integer pid
---@nodiscard
function unix.getpid() end

--- Returns process id of parent process.
---
--- This function does not fail.
---@return integer pid
---@nodiscard
function unix.getppid() end

--- Sends signal to process(es).
---
--- The impact of this action can be terminating the process, or
--- interrupting it to request something happen.
---
--- `pid` can be:
---
--- - `pid > 0` signals one process by id
--- - `== 0`    signals all processes in current process group
--- - `-1`      signals all processes possible (except init)
--- - `< -1`    signals all processes in -pid process group
---
--- `sig` can be:
---
--- - `0`       checks both if pid exists and we can signal it
--- - `SIGINT`  sends ctrl-c keyboard interrupt
--- - `SIGQUIT` sends backtrace and exit signal
--- - `SIGTERM` sends shutdown signal
--- - etc.
---
--- Windows NT only supports the kill() signals required by the ANSI C89
--- standard, which are `SIGINT` and `SIGQUIT`. All other signals on the
--- Windows platform that are sent to another process via kill() will be
--- treated like `SIGKILL`.
---@param pid integer
---@param sig integer
---@return true|nil
---@return string? error
---@return integer? errno
function unix.kill(pid, sig) end

--- Sends signal to process group.
---
--- This is similar to `kill()` but sends the signal to all processes
--- in the specified process group.
---
--- `pgrp` is the process group id. If 0, sends to the calling process's
--- process group.
---
--- `sig` can be any signal value (e.g., `SIGTERM`, `SIGKILL`, etc.).
---
---@param pgrp integer
---@param sig integer
---@return true|nil
---@return string? error
---@return integer? errno
function unix.killpg(pgrp, sig) end

--- Triggers signal in current process.
---
--- This is pretty much the same as `kill(getpid(), sig)`.
---@param sig integer
---@return integer|nil rc
---@return string? error
---@return integer? errno
function unix.raise(sig) end

--- Checks if effective user of current process has permission to access file.
---@param path string
---@param how integer can be `R_OK`, `W_OK`, `X_OK`, or `F_OK` to check for read, write, execute, and existence respectively.
---@param flags? integer may have any of:
--- - `AT_SYMLINK_NOFOLLOW`: do not follow symbolic links.
---@param dirfd? integer
---@return true|nil
---@return string? error
---@return integer? errno
function unix.access(path, how, flags, dirfd) end

--- Makes directory.
---
--- `path` is the path of the directory you wish to create.
---
--- `mode` is octal permission bits, e.g. `0755`.
---
--- Fails with `EEXIST` if `path` already exists, whether it be a
--- directory or a file.
---
--- Fails with `ENOENT` if the parent directory of the directory you
--- want to create doesn't exist. For making `a/really/long/path/`
--- consider using makedirs() instead.
---
--- Fails with `ENOTDIR` if a parent directory component existed that
--- wasn't a directory.
---
--- Fails with `EACCES` if the parent directory doesn't grant write
--- permission to the current user.
---
--- Fails with `ENAMETOOLONG` if the path is too long.
---
---@param path string
---@param mode? integer
---@param dirfd? integer
---@return true|nil
---@return string? error
---@return integer? errno
function unix.mkdir(path, mode, dirfd) end

--- Unlike mkdir() this convenience wrapper will automatically create
--- parent parent directories as needed. If the directory already exists
--- then, unlike mkdir() which returns EEXIST, the makedirs() function
--- will return success.
---
--- `path` is the path of the directory you wish to create.
---
--- `mode` is octal permission bits, e.g. `0755`.
---
---@param path string
---@param mode? integer
---@return true|nil
---@return string? error
---@return integer? errno
function unix.makedirs(path, mode) end

--- Creates a temporary directory with a unique name.
---
--- `template` must end with "XXXXXX" which will be replaced with random
--- characters to create a unique directory name.
---
--- Returns the path of the created directory.
---
--- Example:
---
---     local tmpdir = unix.mkdtemp("/tmp/myapp_XXXXXX")
---     -- tmpdir is now something like "/tmp/myapp_a3b2c1"
---
---@param template string template path ending in XXXXXX
---@return string|nil path
---@return string? error
---@return integer? errno
function unix.mkdtemp(template) end

--- Creates a temporary file with a unique name.
---
--- `template` must end with "XXXXXX" which will be replaced with random
--- characters to create a unique filename.
---
--- Returns both the file descriptor and the path of the created file.
--- The file is opened for reading and writing.
---
--- Example:
---
---     local fd, path = unix.mkstemp("/tmp/myapp_XXXXXX")
---     unix.write(fd, "hello")
---     unix.close(fd)
---     unix.unlink(path)
---
---@param template string template path ending in XXXXXX
---@return integer|nil fd, string path
---@return string? error
---@return integer? errno
function unix.mkstemp(template) end

--- Changes current directory to `path`.
---@param path string
---@return true|nil
---@return string? error
---@return integer? errno
function unix.chdir(path) end

--- Removes file at `path`.
---
--- If `path` refers to a symbolic link, the link is removed.
---
--- Returns `EISDIR` if `path` refers to a directory. See `rmdir()`.
---
---@param path string
---@param dirfd? integer
---@return true|nil
---@return string? error
---@return integer? errno
function unix.unlink(path, dirfd) end

--- Removes empty directory at `path`.
---
--- Returns `ENOTDIR` if `path` isn't a directory, or a path component
--- in `path` exists yet wasn't a directory.
---
---@param path string
---@param dirfd? integer
---@return true|nil
---@return string? error
---@return integer? errno
function unix.rmdir(path, dirfd) end

--- Renames file or directory.
---@param oldpath string
---@param newpath string
---@param olddirfd integer
---@param newdirfd integer
---@return true|nil
---@return string? error
---@return integer? errno
---@overload fun(oldpath: string, newpath: string): true
function unix.rename(oldpath, newpath, olddirfd, newdirfd) end

---Creates hard link, so your underlying inode has two names.
---@param existingpath string
---@param newpath string
---@param flags integer
---@param olddirfd integer
---@param newdirfd integer
---@return true|nil
---@return string? error
---@return integer? errno
---@overload fun(existingpath: string, newpath: string, flags?: integer): true
---@overload fun(existingpath: string, newpath: string, flags: integer, olddirfd: integer, newdirfd: integer): true
function unix.link(existingpath, newpath, flags, olddirfd, newdirfd) end

--- Creates symbolic link.
---
--- On Windows NT a symbolic link is called a "reparse point" and can
--- only be created from an administrator account. Your redbean will
--- automatically request the appropriate permissions.
---@param target string
---@param linkpath string
---@param newdirfd? integer
---@return true|nil
---@return string? error
---@return integer? errno
function unix.symlink(target, linkpath, newdirfd) end

--- Reads contents of symbolic link.
---
--- Note that broken links are supported on all platforms. A symbolic
--- link can contain just about anything. It's important to not assume
--- that `content` will be a valid filename.
---
--- On Windows NT, this function transliterates `\` to `/` and
--- furthermore prefixes `//?/` to WIN32 DOS-style absolute paths,
--- thereby assisting with simple absolute filename checks in addition
--- to enabling one to exceed the traditional 260 character limit.
---@param path string
---@param dirfd? integer
---@return string|nil content
---@return string? error
---@return integer? errno
---@nodiscard
function unix.readlink(path, dirfd) end

--- Returns absolute path of filename, with `.` and `..` components
--- removed, and symlinks will be resolved.
---@param path string
---@return string|nil path
---@return string? error
---@return integer? errno
---@nodiscard
function unix.realpath(path) end

--- Changes access and/or modified timestamps on file.
---
--- `path` is a string with the name of the file.
---
--- The `asecs` and `ananos` parameters set the access time. If they're
--- none or nil, the current time will be used.
---
--- The `msecs` and `mnanos` parameters set the modified time. If
--- they're none or nil, the current time will be used.
---
--- The nanosecond parameters (`ananos` and `mnanos`) must be on the
--- interval [0,1000000000) or `unix.EINVAL` is raised. On XNU this is
--- truncated to microsecond precision. On Windows NT, it's truncated to
--- hectonanosecond precision. These nanosecond parameters may also be
--- set to one of the following special values:
---
--- - `unix.UTIME_NOW`: Fill this timestamp with current time. This
--- feature is not available on old versions of Linux, e.g. RHEL5.
---
--- - `unix.UTIME_OMIT`: Do not alter this timestamp. This feature is
--- not available on old versions of Linux, e.g. RHEL5.
---
--- `dirfd` is a file descriptor integer opened with `O_DIRECTORY`
--- that's used for relative path names. It defaults to `unix.AT_FDCWD`.
---
--- `flags` may have have any of the following flags bitwise or'd
---
--- - `AT_SYMLINK_NOFOLLOW`: Do not follow symbolic links. This makes it
--- possible to edit the timestamps on the symbolic link itself,
--- rather than the file it points to.
---
---@param path string
---@param asecs integer
---@param ananos integer
---@param msecs integer
---@param mnanos integer
---@param dirfd? integer
---@param flags? integer
---@return 0|nil
---@return string? error
---@return integer? errno
---@overload fun(path: string): 0
function unix.utimensat(path, asecs, ananos, msecs, mnanos, dirfd, flags) end

--- Changes access and/or modified timestamps on file descriptor.
---
--- `fd` is the file descriptor of a file opened with `unix.open`.
---
--- The `asecs` and `ananos` parameters set the access time. If they're
--- none or nil, the current time will be used.
---
--- The `msecs` and `mnanos` parameters set the modified time. If
--- they're none or nil, the current time will be used.
---
--- The nanosecond parameters (`ananos` and `mnanos`) must be on the
--- interval [0,1000000000) or `unix.EINVAL` is raised. On XNU this is
--- truncated to microsecond precision. On Windows NT, it's truncated to
--- hectonanosecond precision. These nanosecond parameters may also be
--- set to one of the following special values:
---
--- - `unix.UTIME_NOW`: Fill this timestamp with current time.
---
--- - `unix.UTIME_OMIT`: Do not alter this timestamp.
---
--- This system call is currently not available on very old versions of
--- Linux, e.g. RHEL5.
---
---@param fd integer
---@param asecs integer
---@param ananos integer
---@param msecs integer
---@param mnanos integer
---@return 0|nil
---@return string? error
---@return integer? errno
---@overload fun(fd: integer): 0
function unix.futimens(fd, asecs, ananos, msecs, mnanos) end

--- Changes user and group on file.
---
--- Returns `ENOSYS` on Windows NT.
---@param path string
---@param uid integer
---@param gid integer
---@param flags? integer
---@param dirfd? integer
---@return true|nil
---@return string? error
---@return integer? errno
function unix.chown(path, uid, gid, flags, dirfd) end

--- Changes mode bits on file.
---
--- On Windows NT the chmod system call only changes the read-only
--- status of a file.
---@param path string
---@param mode integer
---@param flags? integer
---@param dirfd? integer
---@return true|nil
---@return string? error
---@return integer? errno
function unix.chmod(path, mode, flags, dirfd) end

--- Returns current working directory.
---
--- On Windows NT, this function transliterates `\` to `/` and
--- furthermore prefixes `//?/` to WIN32 DOS-style absolute paths,
--- thereby assisting with simple absolute filename checks in addition
--- to enabling one to exceed the traditional 260 character limit.
---@return string|nil path
---@return string? error
---@return integer? errno
---@nodiscard
function unix.getcwd() end

--- Recursively removes filesystem path.
---
--- Like `unix.makedirs()` this function isn't actually a system call but
--- rather is a Libc convenience wrapper. It's intended to be equivalent
--- to using the UNIX shell's `rm -rf path` command.
---
---@param path string the file or directory path you wish to destroy.
---@return true|nil
---@return string? error
---@return integer? errno
function unix.rmrf(path) end

--- Manipulates file descriptor.
---
--- `cmd` may be one of:
---
--- - `unix.F_GETFD` Returns file descriptor flags.
--- - `unix.F_SETFD` Sets file descriptor flags.
--- - `unix.F_GETFL` Returns file descriptor status flags.
--- - `unix.F_SETFL` Sets file descriptor status flags.
--- - `unix.F_SETLK` Acquires lock on file interval.
--- - `unix.F_SETLKW` Waits for lock on file interval.
--- - `unix.F_GETLK` Acquires information about lock.
---
--- unix.fcntl(fd:int, unix.F_GETFD)
---     ├─→ flags:int
---     └─→ nil, string, integer
---
---   Returns file descriptor flags.
---
---   The returned `flags` may include any of:
---
---   - `unix.FD_CLOEXEC` if `fd` was opened with `unix.O_CLOEXEC`.
---
---   Returns `EBADF` if `fd` isn't open.
---
--- unix.fcntl(fd:int, unix.F_SETFD, flags:int)
---     ├─→ true
---     └─→ nil, string, integer
---
---   Sets file descriptor flags.
---
---   `flags` may include any of:
---
---   - `unix.FD_CLOEXEC` to re-open `fd` with `unix.O_CLOEXEC`.
---
---   Returns `EBADF` if `fd` isn't open.
---
--- unix.fcntl(fd:int, unix.F_GETFL)
---     ├─→ flags:int
---     └─→ nil, string, integer
---
---   Returns file descriptor status flags.
---
---   `flags & unix.O_ACCMODE` includes one of:
---
---   - `O_RDONLY`
---   - `O_WRONLY`
---   - `O_RDWR`
---
---   Examples of values `flags & ~unix.O_ACCMODE` may include:
---
---   - `O_NONBLOCK`
---   - `O_APPEND`
---   - `O_SYNC`
---   - `O_NOATIME` on Linux
---   - `O_DIRECT` on Linux/FreeBSD/NetBSD/Windows
---
---   Examples of values `flags & ~unix.O_ACCMODE` won't include:
---
---   - `O_CREAT`
---   - `O_TRUNC`
---   - `O_EXCL`
---   - `O_NOCTTY`
---
---   Returns `EBADF` if `fd` isn't open.
---
--- unix.fcntl(fd:int, unix.F_SETFL, flags:int)
---     ├─→ true
---     └─→ nil, string, integer
---
---   Changes file descriptor status flags.
---
---   Examples of values `flags` may include:
---
---   - `O_NONBLOCK`
---   - `O_APPEND`
---   - `O_SYNC`
---   - `O_NOATIME` on Linux
---   - `O_DIRECT` on Linux/FreeBSD/NetBSD/Windows
---
---   These values should be ignored:
---
---   - `O_RDONLY`, `O_WRONLY`, `O_RDWR`
---   - `O_CREAT`, `O_TRUNC`, `O_EXCL`
---   - `O_NOCTTY`
---
---   Returns `EBADF` if `fd` isn't open.
---
--- unix.fcntl(fd:int, unix.F_SETLK[, type[, start[, len[, whence]]]])
--- unix.fcntl(fd:int, unix.F_SETLKW[, type[, start[, len[, whence]]]])
---     ├─→ true
---     └─→ nil, string, integer
---
---   Acquires lock on file interval.
---
---   POSIX Advisory Locks allow multiple processes to leave voluntary
---   hints to each other about which portions of a file they're using.
---
---   The command may be:
---
---   - `F_SETLK` to acquire lock if possible
---   - `F_SETLKW` to wait for lock if necessary
---
---   `fd` is file descriptor of open() file.
---
---   `type` may be one of:
---
---   - `F_RDLCK` for read lock (default)
---   - `F_WRLCK` for read/write lock
---   - `F_UNLCK` to unlock
---
---   `start` is 0-indexed byte offset into file. The default is zero.
---
---   `len` is byte length of interval. Zero is the default and it means
---   until the end of the file.
---
---   `whence` may be one of:
---
---   - `SEEK_SET` start from beginning (default)
---   - `SEEK_CUR` start from current position
---   - `SEEK_END` start from end
---
---   Returns `EAGAIN` if lock couldn't be acquired. POSIX says this
---   theoretically could also be `EACCES` but we haven't seen this
---   behavior on any of our supported platforms.
---
---   Returns `EBADF` if `fd` wasn't open.
---
--- unix.fcntl(fd:int, unix.F_GETLK[, type[, start[, len[, whence]]]])
---     ├─→ unix.F_UNLCK
---     ├─→ type, start, len, whence, pid
---     └─→ nil, string, integer
---
---   Acquires information about POSIX advisory lock on file.
---
---   This function accepts the same parameters as fcntl(F_SETLK) and
---   tells you if the lock acquisition would be successful for a given
---   range of bytes. If locking would have succeeded, then F_UNLCK is
---   returned. If the lock would not have succeeded, then information
---   about a conflicting lock is returned.
---
---   Returned `type` may be `F_RDLCK` or `F_WRLCK`.
---
---   Returned `pid` is the process id of the current lock owner.
---
---   This function is currently not supported on Windows.
---
---   Returns `EBADF` if `fd` wasn't open.
---
---@param fd integer
---@param cmd integer
---@param ... any
---@return any|nil ...
---@return string? error
---@return integer? errno
---@overload fun(fd: integer, unix.F_GETFD: integer): flags: integer
---@overload fun(fd: integer, unix.F_SETFD: integer, flags: integer): true
---@overload fun(fd: integer, unix.F_GETFL: integer): flags: integer
---@overload fun(fd: integer, unix.F_SETFL: integer, flags: integer): true
---@overload fun(fd: integer, unix.F_SETLK: integer, type?: integer, start?: integer, len?: integer, whence?: integer): true
---@overload fun(fd: integer, unix.F_SETLKW: integer, type?: integer, start?: integer, len?: integer, whence?: integer): true
---@overload fun(fd: integer, unix.F_GETLK: integer, type?: integer, start?: integer, len?: integer, whence?: integer): unix.F_UNLCK: integer
---@overload fun(fd: integer, unix.F_GETLK: integer, type?: integer, start?: integer, len?: integer, whence?: integer): type: integer, start: integer, len: integer, whence: integer, pid: integer
function unix.fcntl(fd, cmd, ...) end

---Gets session id.
---@param pid integer
---@return integer|nil sid
---@return string? error
---@return integer? errno
---@nodiscard
function unix.getsid(pid) end

--- Gets process group id.
---@return integer|nil pgid
---@return string? error
---@return integer? errno
---@nodiscard
function unix.getpgrp() end

--- Sets process group id. This is the same as `setpgid(0,0)`.
---@return integer|nil pgid
---@return string? error
---@return integer? errno
function unix.setpgrp() end

--- Sets process group id the modern way.
---@param pid integer
---@param pgid integer
---@return true|nil
---@return string? error
---@return integer? errno
function unix.setpgid(pid, pgid) end

--- Gets process group id the modern way.
---@param pid integer
---@return integer|nil pgid
---@return string? error
---@return integer? errno
function unix.getpgid(pid) end

--- Sets session id.
---
--- This function can be used to create daemons.
---
--- Fails with `ENOSYS` on Windows NT.
---@return integer|nil sid
---@return string? error
---@return integer? errno
function unix.setsid() end

--- Daemonizes the current process.
---
--- This function performs the standard Unix daemonization steps:
--- forks, creates a new session, and optionally changes directory
--- and redirects standard file descriptors.
---
--- `nochdir` if true, the current working directory is not changed
--- to `/`. Defaults to false (will change to `/`).
---
--- `noclose` if true, stdin/stdout/stderr are not redirected to
--- `/dev/null`. Defaults to false (will redirect to `/dev/null`).
---
--- This is a convenience wrapper that combines `fork()`, `setsid()`,
--- and related operations.
---
---@param nochdir? boolean
---@param noclose? boolean
---@return true|nil
---@return string? error
---@return integer? errno
function unix.daemon(nochdir, noclose) end

--- Gets real user id.
---
--- On Windows this system call is polyfilled by running `GetUserNameW()`
--- through Knuth's multiplicative hash.
---
--- This function does not fail.
---@return integer uid
---@nodiscard
function unix.getuid() end

--- Sets real group id.
---
--- On Windows this system call is polyfilled as getuid().
---
--- This function does not fail.
---@return integer gid
---@nodiscard
function unix.getgid() end

--- Gets effective user id.
---
--- For example, if your redbean is a setuid binary, then getuid() will
--- return the uid of the user running the program, and geteuid() shall
--- return zero which means root, assuming that's the file owning user.
---
--- On Windows this system call is polyfilled as getuid().
---
--- This function does not fail.
---@return integer uid
---@nodiscard
function unix.geteuid() end

--- Gets effective group id.
---
--- On Windows this system call is polyfilled as getuid().
---
--- This function does not fail.
---@return integer gid
---@nodiscard
function unix.getegid() end

--- Changes root directory.
---
--- Returns `ENOSYS` on Windows NT.
---@param path string
---@return true|nil
---@return string? error
---@return integer? errno
function unix.chroot(path) end

--- Sets user id.
---
--- One use case for this function is dropping root privileges. Should
--- you ever choose to run redbean as root and decide not to use the
--- `-G` and `-U` flags, you can replicate that behavior in the Lua
--- processes you spawn as follows:
---
---    ok, err = unix.setgid(1000)  -- check your /etc/groups
---    if not ok then Log(kLogFatal, tostring(err)) end
---    ok, err = unix.setuid(1000)  -- check your /etc/passwd
---    if not ok then Log(kLogFatal, tostring(err)) end
---
--- If your goal is to relinquish privileges because redbean is a setuid
--- binary, then things are more straightforward:
---
---    ok, err = unix.setgid(unix.getgid())
---    if not ok then Log(kLogFatal, tostring(err)) end
---    ok, err = unix.setuid(unix.getuid())
---    if not ok then Log(kLogFatal, tostring(err)) end
---
--- See also the setresuid() function and be sure to refer to your local
--- system manual about the subtleties of changing user id in a way that
--- isn't restorable.
---
--- Returns `ENOSYS` on Windows NT if `uid` isn't `getuid()`.
---@param uid integer
---@return true|nil
---@return string? error
---@return integer? errno
function unix.setuid(uid) end

---Sets user id for file system ops.
---@param uid integer
---@return true|nil
---@return string? error
---@return integer? errno
function unix.setfsuid(uid) end

---Sets group id for file system ops.
---@param gid integer
---@return true|nil
---@return string? error
---@return integer? errno
function unix.setfsgid(gid) end

---Sets group id.
---
---Returns `ENOSYS` on Windows NT if `gid` isn't `getgid()`.
---@param gid integer
---@return true|nil
---@return string? error
---@return integer? errno
function unix.setgid(gid) end

---Sets real, effective, and saved user ids.
---
---If any of the above parameters are -1, then it's a no-op.
---
---Returns `ENOSYS` on Windows NT.
---Returns `ENOSYS` on Macintosh and NetBSD if `saved` isn't -1.
---@param real integer
---@param effective integer
---@param saved integer
---@return true|nil
---@return string? error
---@return integer? errno
function unix.setresuid(real, effective, saved) end

--- Sets real, effective, and saved group ids.
---
--- If any of the above parameters are -1, then it's a no-op.
---
--- Returns `ENOSYS` on Windows NT.
--- Returns `ENOSYS` on Macintosh and NetBSD if `saved` isn't -1.
---@param real integer
---@param effective integer
---@param saved integer
---@return true|nil
---@return string? error
---@return integer? errno
function unix.setresgid(real, effective, saved) end

--- Sets file permission mask and returns the old one.
---
--- This is used to remove bits from the `mode` parameter of functions
--- like open() and mkdir(). The masks typically used are 027 and 022.
--- Those masks ensure that, even if a file is created with 0666 bits,
--- it'll be turned into 0640 or 0644 so that users other than the owner
--- can't modify it.
---
--- To read the mask without changing it, try doing this:
---
---     mask = unix.umask(027)
---     unix.umask(mask)
---
--- On Windows NT this is a no-op and `mask` is returned.
---
--- This function does not fail.
---@param newmask integer
---@return integer oldmask
function unix.umask(newmask) end

--- Queries a configurable system limit or value.
---
--- `name` selects which value to return, e.g.
---
---     unix.sysconf(unix.SC_NPROCESSORS_ONLN)  -- online cpu count
---     unix.sysconf(unix.SC_PAGESIZE)          -- mmap() page size
---     unix.sysconf(unix.SC_CLK_TCK)           -- clock ticks per second
---
--- Returns `nil` with an `EINVAL` errno when `name` isn't recognized.
---@param name integer
---@return integer|nil value
---@return string? error
---@return integer? errno
---@nodiscard
function unix.sysconf(name) end

--- Returns identity of the current operating system.
---
--- Example:
---
---     local u = assert(unix.uname())
---     print(u.sysname, u.release, u.machine)
---
---@return {|nil sysname: string, nodename: string, release: string, version: string, machine: string, domainname: string } uts
---@return string? error
---@return integer? errno
---@nodiscard
function unix.uname() end

--- Generates a log message, which will be distributed by syslogd.
---
--- `priority` is a bitmask containing the facility value and the level
--- value. If no facility value is ORed into priority, then the default
--- value set by openlog() is used. If set to NULL, the program name is
--- used. Level is one of `LOG_EMERG`, `LOG_ALERT`, `LOG_CRIT`,
--- `LOG_ERR`, `LOG_WARNING`, `LOG_NOTICE`, `LOG_INFO`, `LOG_DEBUG`.
---
--- This function currently works on Linux, Windows, and NetBSD. On
--- WIN32 it uses the ReportEvent() facility.
---@param priority integer
---@param msg string
function unix.syslog(priority, msg) end

--- Returns nanosecond precision timestamp from system, e.g.
---
---    >: unix.clock_gettime()
---    1651137352      774458779
---    >: Benchmark(unix.clock_gettime)
---    126     393     571     1
---
--- `clock` can be any one of of:
---
--- - `CLOCK_REALTIME` returns a wall clock timestamp represented in
---   nanoseconds since the UNIX epoch (~1970). It'll count time in the
---   suspend state. This clock is subject to being smeared by various
---   adjustments made by NTP. These timestamps can have unpredictable
---   discontinuous jumps when clock_settime() is used. Therefore this
---   clock is the default clock for everything, even pthread condition
---   variables. Cosmopoiltan guarantees this clock will never raise
---   `EINVAL` and also guarantees `CLOCK_REALTIME == 0` will always be
---   the case. On Windows this maps to GetSystemTimePreciseAsFileTime().
---   On platforms with vDSOs like Linux, Windows, and MacOS ARM64 this
---   should take about 20 nanoseconds.
---
--- - `CLOCK_MONOTONIC` returns a timestamp with an unspecified epoch,
---   that should be when the system was powered on. These timestamps
---   shouldn't go backwards. Timestamps shouldn't count time spent in
---   the sleep, suspend, and hibernation states. These timestamps won't
---   be impacted by clock_settime(). These timestamps may be impacted by
---   frequency adjustments made by NTP. Cosmopoiltan guarantees this
---   clock will never raise `EINVAL`. MacOS and BSDs use the word
---   "uptime" to describe this clock. On Windows this maps to
---   QueryUnbiasedInterruptTimePrecise().
---
--- - `CLOCK_BOOTTIME` is a monotonic clock returning a timestamp with an
---   unspecified epoch, that should be relative to when the host system
---   was powered on. These timestamps shouldn't go backwards. Timestamps
---   should also include time spent in a sleep, suspend, or hibernation
---   state. These timestamps aren't impacted by clock_settime(), but
---   they may be impacted by frequency adjustments made by NTP. This
---   clock will raise an `EINVAL` error on extremely old Linux distros
---   like RHEL5. MacOS and BSDs use the word "monotonic" to describe
---   this clock. On Windows this maps to QueryInterruptTimePrecise().
---
--- - `CLOCK_MONOTONIC_RAW` returns a timestamp from an unspecified
---   epoch. These timestamps don't count time spent in the sleep,
---   suspend, and hibernation states. Unlike `CLOCK_MONOTONIC` this
---   clock is guaranteed to not be impacted by frequency adjustments or
---   discontinuous jumps caused by clock_settime(). Providing this level
---   of assurances may make this clock slower than the normal monotonic
---   clock. Furthermore this clock may cause `EINVAL` to be raised if
---   running on a host system that doesn't provide those guarantees,
---   e.g. OpenBSD and MacOS on AMD64.
---
--- - `CLOCK_REALTIME_COARSE` is the same as `CLOCK_REALTIME` except
---   it'll go faster if the host OS provides a cheaper way to read the
---   wall time. Please be warned that coarse can be really coarse.
---   Rather than nano precision, you're looking at `CLK_TCK` precision,
---   which can lag as far as 30 milliseconds behind or possibly more.
---   Cosmopolitan may fallback to `CLOCK_REALTIME` if a faster less
---   accurate clock isn't provided by the system. This clock will raise
---   an `EINVAL` error on extremely old Linux distros like RHEL5.
---
--- - `CLOCK_MONOTONIC_COARSE` is the same as `CLOCK_MONOTONIC` except
---   it'll go faster if the host OS provides a cheaper way to read the
---   unbiased time. Please be warned that coarse can be really coarse.
---   Rather than nano precision, you're looking at `CLK_TCK` precision,
---   which can lag as far as 30 milliseconds behind or possibly more.
---   Cosmopolitan may fallback to `CLOCK_REALTIME` if a faster less
---   accurate clock isn't provided by the system. This clock will raise
---   an `EINVAL` error on extremely old Linux distros like RHEL5.
---
--- - `CLOCK_PROCESS_CPUTIME_ID` returns the amount of time this process
---   was actively scheduled. This is similar to getrusage() and clock().
---   Cosmopoiltan guarantees this clock will never raise `EINVAL`.
---
--- - `CLOCK_THREAD_CPUTIME_ID` returns the amount of time this thread
---   was actively scheduled. This is similar to getrusage() and clock().
---   Cosmopoiltan guarantees this clock will never raise `EINVAL`.
---
--- Returns `EINVAL` if clock isn't supported on platform.
---
--- This function only fails if `clock` is invalid.
---
--- This function goes fastest on Linux and Windows.
---@param clock? integer
---@return integer|nil seconds, integer nanos
---@return string? error
---@return integer? errno
---@nodiscard
function unix.clock_gettime(clock) end

--- Sleeps with nanosecond precision.
---
--- Returns `EINTR` if a signal was received while waiting.
---@param seconds integer
---@param nanos integer?
---@return integer|nil remseconds, integer remnanos
---@return string? error
---@return integer? errno
function unix.nanosleep(seconds, nanos) end

--- These functions are used to make programs slower by asking the
--- operating system to flush data to the physical medium.
function unix.sync() end

--- These functions are used to make programs slower by asking the
--- operating system to flush data to the physical medium.
---@param fd integer
---@return true|nil
---@return string? error
---@return integer? errno
function unix.fsync(fd) end

--- These functions are used to make programs slower by asking the
--- operating system to flush data to the physical medium.
---@param fd integer
---@return true|nil
---@return string? error
---@return integer? errno
function unix.fdatasync(fd) end

--- Seeks to file position.
---
--- `whence` can be one of:
---
--- - `SEEK_SET`: Sets the file position to `offset` [default]
--- - `SEEK_CUR`: Sets the file position to `position + offset`
--- - `SEEK_END`: Sets the file position to `filesize + offset`
---
--- Returns the new position relative to the start of the file.
---@param fd integer
---@param offset integer
---@param whence? integer
---@return integer|nil newposbytes
---@return string? error
---@return integer? errno
function unix.lseek(fd, offset, whence) end

--- Reduces or extends underlying physical medium of file.
--- If file was originally larger, content >length is lost.
---@param path string
---@param length? integer defaults to zero (`0`)
---@return true|nil
---@return string? error
---@return integer? errno
function unix.truncate(path, length) end

--- Reduces or extends underlying physical medium of open file.
--- If file was originally larger, content >length is lost.
---@param fd integer
---@param length? integer defaults to zero (`0`)
---@return true|nil
---@return string? error
---@return integer? errno
function unix.ftruncate(fd, length) end

---@param family? integer defaults to `AF_INET` and can be:
---
--- - `AF_INET`: Creates Internet Protocol Version 4 (IPv4) socket.
---
--- - `AF_UNIX`: Creates local UNIX domain socket. On the New Technology
--- this requires Windows 10 and only works with `SOCK_STREAM`.
---
---@param type? integer defaults to `SOCK_STREAM` and can be:
---
--- - `SOCK_STREAM`
--- - `SOCK_DGRAM`
--- - `SOCK_RAW`
--- - `SOCK_RDM`
--- - `SOCK_SEQPACKET`
---
--- You may bitwise OR any of the following into `type`:
---
--- - `SOCK_CLOEXEC`
--- - `SOCK_NONBLOCK`
---
---@param protocol? integer may be any of:
---
--- - `0` to let kernel choose [default]
--- - `IPPROTO_TCP`
--- - `IPPROTO_UDP`
--- - `IPPROTO_RAW`
--- - `IPPROTO_IP`
--- - `IPPROTO_ICMP`
---
---@return integer|nil fd
---@return string? error
---@return integer? errno
---@nodiscard
function unix.socket(family, type, protocol) end

--- Creates bidirectional pipe.
---
---@param family? integer defaults to `AF_UNIX`.
---@param type? integer defaults to `SOCK_STREAM` and can be:
---
--- - `SOCK_STREAM`
--- - `SOCK_DGRAM`
--- - `SOCK_SEQPACKET`
---
--- You may bitwise OR any of the following into `type`:
---
--- - `SOCK_CLOEXEC`
--- - `SOCK_NONBLOCK`
---
---@param protocol? integer defaults to `0`.
---@return integer|nil fd1, integer fd2
---@return string? error
---@return integer? errno
function unix.socketpair(family, type, protocol) end

---  Binds socket.
---
---  `ip` and `port` are in host endian order. For example, if you
---  wanted to listen on `1.2.3.4:31337` you could do any of these
---
---      unix.bind(sock, 0x01020304, 31337)
---      unix.bind(sock, ParseIp('1.2.3.4'), 31337)
---      unix.bind(sock, 1 << 24 | 0 << 16 | 0 << 8 | 1, 31337)
---
---  `ip` and `port` both default to zero. The meaning of bind(0, 0)
---  is to listen on all interfaces with a kernel-assigned ephemeral
---  port number, that can be retrieved and used as follows:
---
---      sock = assert(unix.socket())  -- create ipv4 tcp socket
---      assert(unix.bind(sock))       -- all interfaces ephemeral port
---      ip, port = assert(unix.getsockname(sock))
---      print("listening on ip", FormatIp(ip), "port", port)
---      assert(unix.listen(sock))
---      while true do
---         client, clientip, clientport = assert(unix.accept(sock))
---         print("got client ip", FormatIp(clientip), "port", clientport)
---         unix.close(client)
---      end
---
---  Further note that calling `unix.bind(sock)` is equivalent to not
---  calling bind() at all, since the above behavior is the default.
---@param fd integer
---@param ip? uint32
---@param port? uint16
---@return true|nil
---@return string? error
---@return integer? errno
---@overload fun(fd: integer, unixpath: string): true
function unix.bind(fd, ip, port) end

---Returns list of network adapter addresses.
---@return {|nil name: string, ip: integer, netmask: integer }[] addresses
---@return string? error
---@return integer? errno
---@nodiscard
function unix.siocgifconf() end

--- Tunes networking parameters.
---
--- `level` and `optname` may be one of the following pairs. The ellipses
--- type signature above changes depending on which options are used.
---
--- `optname` is the option feature magic number. The constants for
--- these will be set to `0` if the option isn't supported on the host
--- platform.
---
--- Raises `ENOPROTOOPT` if your `level` / `optname` combination isn't
--- valid, recognized, or supported on the host platform.
---
--- Raises `ENOTSOCK` if `fd` is valid but isn't a socket.
---
--- Raises `EBADF` if `fd` isn't valid.
---
--- unix.getsockopt(fd:int, level:int, optname:int)
---     ├─→ value:int
---     └─→ nil, string, integer
--- unix.setsockopt(fd:int, level:int, optname:int, value:bool)
---     ├─→ true
---     └─→ nil, string, integer
---
--- - `SOL_SOCKET`, `SO_TYPE`
--- - `SOL_SOCKET`, `SO_DEBUG`
--- - `SOL_SOCKET`, `SO_ACCEPTCONN`
--- - `SOL_SOCKET`, `SO_BROADCAST`
--- - `SOL_SOCKET`, `SO_REUSEADDR`
--- - `SOL_SOCKET`, `SO_REUSEPORT`
--- - `SOL_SOCKET`, `SO_KEEPALIVE`
--- - `SOL_SOCKET`, `SO_DONTROUTE`
--- - `SOL_TCP`, `TCP_NODELAY`
--- - `SOL_TCP`, `TCP_CORK`
--- - `SOL_TCP`, `TCP_QUICKACK`
--- - `SOL_TCP`, `TCP_FASTOPEN_CONNECT`
--- - `SOL_TCP`, `TCP_DEFER_ACCEPT`
--- - `SOL_IP`, `IP_HDRINCL`
---
--- unix.getsockopt(fd:int, level:int, optname:int)
---     ├─→ value:int
---     └─→ nil, string, integer
--- unix.setsockopt(fd:int, level:int, optname:int, value:int)
---     ├─→ true
---     └─→ nil, string, integer
---
--- - `SOL_SOCKET`, `SO_SNDBUF`
--- - `SOL_SOCKET`, `SO_RCVBUF`
--- - `SOL_SOCKET`, `SO_RCVLOWAT`
--- - `SOL_SOCKET`, `SO_SNDLOWAT`
--- - `SOL_TCP`, `TCP_KEEPIDLE`
--- - `SOL_TCP`, `TCP_KEEPINTVL`
--- - `SOL_TCP`, `TCP_FASTOPEN`
--- - `SOL_TCP`, `TCP_KEEPCNT`
--- - `SOL_TCP`, `TCP_MAXSEG`
--- - `SOL_TCP`, `TCP_SYNCNT`
--- - `SOL_TCP`, `TCP_NOTSENT_LOWAT`
--- - `SOL_TCP`, `TCP_WINDOW_CLAMP`
--- - `SOL_IP`, `IP_TOS`
--- - `SOL_IP`, `IP_MTU`
--- - `SOL_IP`, `IP_TTL`
---
--- unix.getsockopt(fd:int, level:int, optname:int)
---     ├─→ secs:int, nsecs:int
---     └─→ nil, string, integer
--- unix.setsockopt(fd:int, level:int, optname:int, secs:int[, nanos:int])
---     ├─→ true
---     └─→ nil, string, integer
---
--- - `SOL_SOCKET`, `SO_RCVTIMEO`: If this option is specified then
---   your stream socket will have a read() / recv() timeout. If the
---   specified interval elapses without receiving data, then EAGAIN
---   shall be returned by read. If this option is used on listening
---   sockets, it'll be inherited by accepted sockets. Your redbean
---   already does this for GetClientFd() based on the `-t` flag.
---
--- - `SOL_SOCKET`, `SO_SNDTIMEO`: This is the same as `SO_RCVTIMEO`
---   but it applies to the write() / send() functions.
---
--- unix.getsockopt(fd:int, unix.SOL_SOCKET, unix.SO_LINGER)
---     ├─→ seconds:int, enabled:bool
---     └─→ nil, string, integer
--- unix.setsockopt(fd:int, unix.SOL_SOCKET, unix.SO_LINGER, secs:int, enabled:bool)
---     ├─→ true
---     └─→ nil, string, integer
---
--- This `SO_LINGER` parameter can be used to make close() a blocking
--- call. Normally when the kernel returns immediately when it receives
--- close(). Sometimes it's desirable to have extra assurance on errors
--- happened, even if it comes at the cost of performance.
---
--- unix.setsockopt(serverfd:int, unix.SOL_TCP, unix.TCP_SAVE_SYN, enabled:int)
---     ├─→ true
---     └─→ nil, string, integer
--- unix.getsockopt(clientfd:int, unix.SOL_TCP, unix.TCP_SAVED_SYN)
---     ├─→ syn_packet_bytes:str
---     └─→ nil, string, integer
---
--- This `TCP_SAVED_SYN` option may be used to retrieve the bytes of the
--- TCP SYN packet that the client sent when the connection for `fd` was
--- opened. In order for this to work, `TCP_SAVE_SYN` must have been set
--- earlier on the listening socket. This is Linux-only. You can use the
--- `OnServerListen` hook to enable SYN saving in your Redbean. When the
--- `TCP_SAVE_SYN` option isn't used, this may return empty string.
---@param fd integer
---@param level integer
---@param optname integer
---@return integer|nil value
---@return string? error
---@return integer? errno
---@nodiscard
---@overload fun(fd:integer, unix.SOL_SOCKET: integer, unix.SO_LINGER: integer): seconds: integer, enabled: boolean
---@overload fun(serverfd:integer, unix.SOL_TCP: integer, unix.TCP_SAVE_SYN: integer): syn_packet_bytes: string
function unix.getsockopt(fd, level, optname) end

--- Tunes networking parameters.
---
--- `level` and `optname` may be one of the following pairs. The ellipses
--- type signature above changes depending on which options are used.
---
--- `optname` is the option feature magic number. The constants for
--- these will be set to `0` if the option isn't supported on the host
--- platform.
---
--- Raises `ENOPROTOOPT` if your `level` / `optname` combination isn't
--- valid, recognized, or supported on the host platform.
---
--- Raises `ENOTSOCK` if `fd` is valid but isn't a socket.
---
--- Raises `EBADF` if `fd` isn't valid.
---
--- unix.getsockopt(fd:int, level:int, optname:int)
---     ├─→ value:int
---     └─→ nil, string, integer
--- unix.setsockopt(fd:int, level:int, optname:int, value:bool)
---     ├─→ true
---     └─→ nil, string, integer
---
--- - `SOL_SOCKET`, `SO_TYPE`
--- - `SOL_SOCKET`, `SO_DEBUG`
--- - `SOL_SOCKET`, `SO_ACCEPTCONN`
--- - `SOL_SOCKET`, `SO_BROADCAST`
--- - `SOL_SOCKET`, `SO_REUSEADDR`
--- - `SOL_SOCKET`, `SO_REUSEPORT`
--- - `SOL_SOCKET`, `SO_KEEPALIVE`
--- - `SOL_SOCKET`, `SO_DONTROUTE`
--- - `SOL_TCP`, `TCP_NODELAY`
--- - `SOL_TCP`, `TCP_CORK`
--- - `SOL_TCP`, `TCP_QUICKACK`
--- - `SOL_TCP`, `TCP_FASTOPEN_CONNECT`
--- - `SOL_TCP`, `TCP_DEFER_ACCEPT`
--- - `SOL_IP`, `IP_HDRINCL`
---
--- unix.getsockopt(fd:int, level:int, optname:int)
---     ├─→ value:int
---     └─→ nil, string, integer
--- unix.setsockopt(fd:int, level:int, optname:int, value:int)
---     ├─→ true
---     └─→ nil, string, integer
---
--- - `SOL_SOCKET`, `SO_SNDBUF`
--- - `SOL_SOCKET`, `SO_RCVBUF`
--- - `SOL_SOCKET`, `SO_RCVLOWAT`
--- - `SOL_SOCKET`, `SO_SNDLOWAT`
--- - `SOL_TCP`, `TCP_KEEPIDLE`
--- - `SOL_TCP`, `TCP_KEEPINTVL`
--- - `SOL_TCP`, `TCP_FASTOPEN`
--- - `SOL_TCP`, `TCP_KEEPCNT`
--- - `SOL_TCP`, `TCP_MAXSEG`
--- - `SOL_TCP`, `TCP_SYNCNT`
--- - `SOL_TCP`, `TCP_NOTSENT_LOWAT`
--- - `SOL_TCP`, `TCP_WINDOW_CLAMP`
--- - `SOL_IP`, `IP_TOS`
--- - `SOL_IP`, `IP_MTU`
--- - `SOL_IP`, `IP_TTL`
---
--- unix.getsockopt(fd:int, level:int, optname:int)
---     ├─→ secs:int, nsecs:int
---     └─→ nil, string, integer
--- unix.setsockopt(fd:int, level:int, optname:int, secs:int[, nanos:int])
---     ├─→ true
---     └─→ nil, string, integer
---
--- - `SOL_SOCKET`, `SO_RCVTIMEO`: If this option is specified then
---   your stream socket will have a read() / recv() timeout. If the
---   specified interval elapses without receiving data, then EAGAIN
---   shall be returned by read. If this option is used on listening
---   sockets, it'll be inherited by accepted sockets. Your redbean
---   already does this for GetClientFd() based on the `-t` flag.
---
--- - `SOL_SOCKET`, `SO_SNDTIMEO`: This is the same as `SO_RCVTIMEO`
---   but it applies to the write() / send() functions.
---
--- unix.getsockopt(fd:int, unix.SOL_SOCKET, unix.SO_LINGER)
---     ├─→ seconds:int, enabled:bool
---     └─→ nil, string, integer
--- unix.setsockopt(fd:int, unix.SOL_SOCKET, unix.SO_LINGER, secs:int, enabled:bool)
---     ├─→ true
---     └─→ nil, string, integer
---
--- This `SO_LINGER` parameter can be used to make close() a blocking
--- call. Normally when the kernel returns immediately when it receives
--- close(). Sometimes it's desirable to have extra assurance on errors
--- happened, even if it comes at the cost of performance.
---
--- unix.setsockopt(serverfd:int, unix.SOL_TCP, unix.TCP_SAVE_SYN, enabled:int)
---     ├─→ true
---     └─→ nil, string, integer
--- unix.getsockopt(clientfd:int, unix.SOL_TCP, unix.TCP_SAVED_SYN)
---     ├─→ syn_packet_bytes:str
---     └─→ nil, string, integer
---
--- This `TCP_SAVED_SYN` option may be used to retrieve the bytes of the
--- TCP SYN packet that the client sent when the connection for `fd` was
--- opened. In order for this to work, `TCP_SAVE_SYN` must have been set
--- earlier on the listening socket. This is Linux-only. You can use the
--- `OnServerListen` hook to enable SYN saving in your Redbean. When the
--- `TCP_SAVE_SYN` option isn't used, this may return empty string.
---@param fd integer
---@param level integer
---@param optname integer
---@param value boolean|integer
---@return true|nil
---@return string? error
---@return integer? errno
---@overload fun(fd:integer, unix.SOL_SOCKET: integer, unix.SO_LINGER: integer, secs:integer, enabled:boolean): true
---@overload fun(serverfd:integer, unix.SOL_TCP: integer, unix.TCP_SAVE_SYN: integer, enabled:integer): true
function unix.setsockopt(fd, level, optname, value) end

--- Checks for events on a set of file descriptors.
---
--- The table of file descriptors to poll uses sparse integer keys. Any
--- pairs with non-integer keys will be ignored. Pairs with negative
--- keys are ignored by poll(). The returned table will be a subset of
--- the supplied file descriptors.
---
--- `events` and `revents` may be any combination (using bitwise OR) of:
---
--- - `POLLIN` (events, revents): There is data to read.
--- - `POLLOUT` (events, revents): Writing is now possible, although may
--- still block if available space in a socket or pipe is exceeded
--- (unless `O_NONBLOCK` is set).
--- - `POLLPRI` (events, revents): There is some exceptional condition
--- (for example, out-of-band data on a TCP socket).
--- - `POLLRDHUP` (events, revents): Stream socket peer closed
--- connection, or shut down writing half of connection.
--- - `POLLERR` (revents): Some error condition.
--- - `POLLHUP` (revents): Hang up. When reading from a channel such as
--- a pipe or a stream socket, this event merely indicates that the
--- peer closed its end of the channel.
--- - `POLLNVAL` (revents): Invalid request.
---
---@param fds table<integer,integer> `{[fd:int]=events:int, ...}`
---@param timeoutms integer? the number of milliseconds to block.
--- If this is set to -1 then that means block as long as it takes until there's an
--- event or an interrupt. If the timeout expires, an empty table is returned.
---@return table<integer,integer>|nil `{[fd:int]=revents:int, ...}`
---@return string? error
---@return integer? errno
---@nodiscard
function unix.poll(fds, timeoutms) end

--- Returns hostname of system.
---@return string|nil host
---@return string? error
---@return integer? errno
---@nodiscard
function unix.gethostname() end

--- Sets hostname of system.
---
--- Requires CAP_SYS_ADMIN on Linux (or root on BSDs); returns `EPERM`
--- otherwise. Not supported on Windows, where it returns `ENOSYS`.
---@param name string
---@return true|nil
---@return string? error
---@return integer? errno
function unix.sethostname(name) end

--- Begins listening for incoming connections on a socket.
---@param fd integer
---@param backlog integer?
---@return true|nil
---@return string? error
---@return integer? errno
function unix.listen(fd, backlog) end

--- Accepts new client socket descriptor for a listening tcp socket.
---
--- `flags` may have any combination (using bitwise OR) of:
---
--- - `SOCK_CLOEXEC`
--- - `SOCK_NONBLOCK`
---
---@param serverfd integer
---@param flags integer?
---@return integer|nil clientfd, uint32 ip, uint16 port
---@return string? error
---@return integer? errno
---@nodiscard
---@overload fun(serverfd:integer, flags:integer?):clientfd:integer, unixpath:string
function unix.accept(serverfd, flags) end

---  Connects a TCP socket to a remote host.
---
---  With TCP this is a blocking operation. For a UDP socket it simply
---  remembers the intended address so that `send()` or `write()` may be used
---  rather than `sendto()`.
---@param fd integer
---@param ip uint32
---@param port uint16
---@return true|nil
---@return string? error
---@return integer? errno
---@overload fun(fd:integer, unixpath:string): true
function unix.connect(fd, ip, port) end

--- Retrieves the local address of a socket.
---@param fd integer
---@return uint32|nil ip, uint16 port
---@return string? error
---@return integer? errno
---@nodiscard
---@overload fun(fd: integer): unixpath:string
function unix.getsockname(fd) end

--- Retrieves the remote address of a socket.
---
--- This operation will either fail on `AF_UNIX` sockets or return an
--- empty string.
---
---@param fd integer
---@return uint32|nil ip, uint16 port
---@return string? error
---@return integer? errno
---@nodiscard
---@overload fun(fd: integer): unixpath:string
function unix.getpeername(fd) end

---@param fd integer
---@param bufsiz integer?
---@param flags integer? may have any combination (using bitwise OR) of:
--- - `MSG_WAITALL`
--- - `MSG_DONTROUTE`
--- - `MSG_PEEK`
--- - `MSG_OOB`
---@return string|nil data
---@return string? error
---@return integer? errno
---@nodiscard
function unix.recv(fd, bufsiz, flags) end

---@param fd integer
---@param bufsiz integer?
---@param flags integer? may have any combination (using bitwise OR) of:
--- - `MSG_WAITALL`
--- - `MSG_DONTROUTE`
--- - `MSG_PEEK`
--- - `MSG_OOB`
---@return string|nil data, integer ip, integer port
---@return string? error
---@return integer? errno
---@nodiscard
---@overload fun(fd: integer, bufsiz?: integer, flags?: integer): data: string, unixpath: string
function unix.recvfrom(fd, bufsiz, flags) end

--- This is the same as `write` except it has a `flags` argument
--- that's intended for sockets.
---@param fd integer
---@param data string
---@param flags integer? may have any combination (using bitwise OR) of:
--- - `MSG_NOSIGNAL`: Don't SIGPIPE on EOF
--- - `MSG_OOB`: Send stream data through out of bound channel
--- - `MSG_DONTROUTE`: Don't go through gateway (for diagnostics)
--- - `MSG_MORE`: Manual corking to belay nodelay (0 on non-Linux)
---@param offset integer? byte offset into `data` at which to start sending
---@return integer|nil sent
---@return string? error
---@return integer? errno
function unix.send(fd, data, flags, offset) end

--- This is useful for sending messages over UDP sockets to specific
--- addresses.
---
---@param fd integer
---@param data string
---@param ip uint32
---@param port uint16
---@param flags? integer may have any combination (using bitwise OR) of:
--- - `MSG_OOB`
--- - `MSG_DONTROUTE`
--- - `MSG_NOSIGNAL`
---@return integer|nil sent
---@return string? error
---@return integer? errno
---@overload fun(fd:integer, data:string, unixpath:string, flags?:integer): sent: integer
function unix.sendto(fd, data, ip, port, flags) end

--- Partially closes socket.
---
---@param fd integer
---@param how integer is set to one of:
---
--- - `SHUT_RD`: sends a tcp half close for reading
--- - `SHUT_WR`: sends a tcp half close for writing
--- - `SHUT_RDWR`
---
--- This system call currently has issues on Macintosh, so portable code
--- should log rather than assert failures reported by `shutdown()`.
---
---@return true|nil
---@return string? error
---@return integer? errno
function unix.shutdown(fd, how) end

--- Manipulates bitset of signals blocked by process.
---
---@param how integer can be one of:
---
--- - `SIG_BLOCK`: applies `mask` to set of blocked signals using bitwise OR
--- - `SIG_UNBLOCK`: removes bits in `mask` from set of blocked signals
--- - `SIG_SETMASK`: replaces process signal mask with `mask`
---
--- `mask` is a unix.Sigset() object (see section below).
---
--- For example, to temporarily block `SIGTERM` and `SIGINT` so critical
--- work won't be interrupted, sigprocmask() can be used as follows:
---
---   newmask = unix.Sigset(unix.SIGTERM)
---   oldmask = assert(unix.sigprocmask(unix.SIG_BLOCK, newmask))
---   -- do something...
---   assert(unix.sigprocmask(unix.SIG_SETMASK, oldmask))
---
---@param newmask unix.Sigset
---@return unix.Sigset|nil oldmask
---@return string? error
---@return integer? errno
function unix.sigprocmask(how, newmask) end

---@param sig integer can be one of:
---
--- - `unix.SIGINT`
--- - `unix.SIGQUIT`
--- - `unix.SIGTERM`
--- - etc.
---
---@param handler? function|integer can be:
---
--- - Lua function
--- - `unix.SIG_IGN`
--- - `unix.SIG_DFL`
---
---@param flags? integer can have:
---
--- - `unix.SA_RESTART`: Enables BSD signal handling semantics. Normally
--- i/o entrypoints check for pending signals to deliver. If one gets
--- delivered during an i/o call, the normal behavior is to cancel the
--- i/o operation and return -1 with `EINTR` in errno. If you use the
--- `SA_RESTART` flag then that behavior changes, so that any function
--- that's been annotated with @restartable will not return `EINTR`
--- and will instead resume the i/o operation. This makes coding
--- easier but it can be an anti-pattern if not used carefully, since
--- poor usage can easily result in latency issues. It also requires
--- one to do more work in signal handlers, so special care needs to
--- be given to which C library functions are @asyncsignalsafe.
---
--- - `unix.SA_RESETHAND`: Causes signal handler to be single-shot. This
--- means that, upon entry of delivery to a signal handler, it's reset
--- to the `SIG_DFL` handler automatically. You may use the alias
--- `SA_ONESHOT` for this flag, which means the same thing.
---
--- - `unix.SA_NODEFER`: Disables the reentrancy safety check on your signal
--- handler. Normally that's a good thing, since for instance if your
--- `SIGSEGV` signal handler happens to segfault, you're going to want
--- your process to just crash rather than looping endlessly. But in
--- some cases it's desirable to use `SA_NODEFER` instead, such as at
--- times when you wish to `longjmp()` out of your signal handler and
--- back into your program. This is only safe to do across platforms
--- for non-crashing signals such as `SIGCHLD` and `SIGINT`. Crash
--- handlers should use Xed instead to recover execution, because on
--- Windows a `SIGSEGV` or `SIGTRAP` crash handler might happen on a
--- separate stack and/or a separate thread. You may use the alias
--- `SA_NOMASK` for this flag, which means the same thing.
---
--- - `unix.SA_NOCLDWAIT`: Changes `SIGCHLD` so the zombie is gone and
--- you can't call wait() anymore; similar but may still deliver the
--- SIGCHLD.
---
--- - `unix.SA_NOCLDSTOP`: Lets you set `SIGCHLD` handler that's only
--- notified on exit/termination and not notified on `SIGSTOP`,
--- `SIGTSTP`, `SIGTTIN`, `SIGTTOU`, or `SIGCONT`.
---
--- Example:
---
---     function OnSigUsr1(sig)
---         gotsigusr1 = true
---     end
---     gotsigusr1 = false
---     oldmask = assert(unix.sigprocmask(unix.SIG_BLOCK, unix.Sigset(unix.SIGUSR1)))
---     assert(unix.sigaction(unix.SIGUSR1, OnSigUsr1))
---     assert(unix.raise(unix.SIGUSR1))
---     assert(not gotsigusr1)
---     ok, err, errno = unix.sigsuspend(oldmask)
---     assert(not ok)
---     assert(errno == unix.EINTR)
---     assert(gotsigusr1)
---     assert(unix.sigprocmask(unix.SIG_SETMASK, oldmask))
---
--- When `handler` is a Lua function, it is dispatched *deferred* rather than
--- from the raw signal context: the real signal handler only records the
--- signal and the Lua function is then invoked at the next Lua VM instruction
--- boundary, in normal execution context. This is required because the Lua VM
--- is not async-signal-safe -- running Lua from a true signal handler that
--- interrupted the VM mid-allocation or mid-GC can corrupt the heap. A
--- consequence is that a blocking syscall interrupted by the signal still
--- returns `EINTR` immediately (so `sigsuspend`/poll wakeups are preserved),
--- but the Lua handler body runs a moment later once the VM resumes. Integer
--- handlers (e.g. `unix.SIG_IGN`, `unix.SIG_DFL`, or a raw function pointer)
--- are installed directly and are not deferred.
---
--- It's a good idea to not do too much work in a signal handler.
---
---@param mask? unix.Sigset
---@return function|integer|nil oldhandler, integer flags, unix.Sigset mask
---@return string? error
---@return integer? errno
function unix.sigaction(sig, handler, flags, mask) end

--- Waits for signal to be delivered.
---
--- The signal mask is temporarily replaced with `mask` during this system call.
---@param mask? unix.Sigset specifies which signals should be blocked.
---@return nil
---@return string? error
---@return integer? errno
function unix.sigsuspend(mask) end

--- Returns the set of signals pending delivery to the calling process
--- that are currently blocked.
---@return unix.Sigset|nil mask
---@return string? error
---@return integer? errno
function unix.sigpending() end

--- Causes `SIGALRM` signals to be generated at some point(s) in the
--- future. The `which` parameter should be `ITIMER_REAL`.
---
--- Here's an example of how to create a 400 ms interval timer:
---
---     ticks = 0
---     assert(unix.sigaction(unix.SIGALRM, function(sig)
---        print('tick no. %d' % {ticks})
---        ticks = ticks + 1
---     end))
---     assert(unix.setitimer(unix.ITIMER_REAL, 0, 400e6, 0, 400e6))
---     while true do
---        unix.sigsuspend()
---     end
---
--- Here's how you'd do a single-shot timeout in 1 second:
---
---     unix.sigaction(unix.SIGALRM, MyOnSigAlrm, unix.SA_RESETHAND)
---     unix.setitimer(unix.ITIMER_REAL, 0, 0, 1, 0)
---
---@param which integer
---@param intervalsec integer
---@param intervalns integer needs to be on the interval `[0,1000000000)`
---@param valuesec integer
---@param valuens integer needs to be on the interval `[0,1000000000)`
---@return integer|nil intervalsec, integer intervalns, integer valuesec, integer valuens
---@return string? error
---@return integer? errno
---@overload fun(which: integer): intervalsec: integer, intervalns: integer, valuesec: integer, valuens: integer
function unix.setitimer(which, intervalsec, intervalns, valuesec, valuens) end

--- Turns platform-specific `sig` code into its symbolic name.
---
--- For example:
---
---     >: unix.strsignal(9)
---     "SIGKILL"
---     >: unix.strsignal(unix.SIGKILL)
---     "SIGKILL"
---
--- Please note that signal numbers are normally different across
--- supported platforms, and the constants should be preferred.
---
---@param sig integer
---@return string signalname
---@nodiscard
function unix.strsignal(sig) end

--- Changes resource limit.
---
---@param resource integer may be one of:
---
--- - `RLIMIT_AS` limits the size of the virtual address space. This
--- will work on all platforms. It's emulated on XNU and Windows which
--- means it won't propagate across execve() currently.
---
--- - `RLIMIT_CPU` causes `SIGXCPU` to be sent to the process when the
--- soft limit on CPU time is exceeded, and the process is destroyed
--- when the hard limit is exceeded. It works everywhere but Windows
--- where it should be possible to poll getrusage() with setitimer().
---
--- - `RLIMIT_FSIZE` causes `SIGXFSZ` to sent to the process when the
--- soft limit on file size is exceeded and the process is destroyed
--- when the hard limit is exceeded. It works everywhere but Windows.
---
--- - `RLIMIT_NPROC` limits the number of simultaneous processes and it
--- should work on all platforms except Windows. Please be advised it
--- limits the process, with respect to the activities of the user id
--- as a whole.
---
--- - `RLIMIT_NOFILE` limits the number of open file descriptors and it
--- should work on all platforms except Windows (TODO).
---
--- If a limit isn't supported by the host platform, it'll be set to
--- 127. On most platforms these limits are enforced by the kernel and
--- as such are inherited by subprocesses.
---
---@param soft integer
---@param hard? integer defaults to whatever was specified in `soft`.
---@return true|nil
---@return string? error
---@return integer? errno
function unix.setrlimit(resource, soft, hard) end

--- Returns information about resource limits for current process.
---@param resource integer
---@return integer|nil soft, integer hard
---@return string? error
---@return integer? errno
---@nodiscard
function unix.getrlimit(resource) end

--- Adjusts the nice value (scheduling priority) of the calling process.
---
--- The nice value ranges from -20 (highest priority) to 19 (lowest priority).
--- Only privileged processes can lower the nice value (increase priority).
---
--- `inc` is added to the current nice value. Positive values decrease
--- priority, negative values increase it.
---
--- Returns the new nice value on success. Note that -1 is a valid return
--- value, so errors must be detected by checking the second return value.
---
---@param inc integer
---@return integer|nil priority
---@return string? error
---@return integer? errno
function unix.nice(inc) end

--- Lowers the calling process to the lowest scheduling priority.
---
--- On Linux this additionally requests the idle scheduling policy and a
--- best-effort idle i/o priority. This function does not fail.
function unix.verynice() end

--- Gets the scheduling priority of a process, process group, or user.
---
--- `which` specifies what `who` refers to:
---
--- - `PRIO_PROCESS`: `who` is a process id (0 = calling process)
--- - `PRIO_PGRP`: `who` is a process group id (0 = calling process group)
--- - `PRIO_USER`: `who` is a user id (0 = calling user)
---
--- Returns the priority value (nice value) which ranges from -20 to 19.
--- Note that -1 is a valid return value, so errors must be detected by
--- checking the second return value.
---
---@param which integer
---@param who integer
---@return integer|nil priority
---@return string? error
---@return integer? errno
function unix.getpriority(which, who) end

--- Sets the scheduling priority of a process, process group, or user.
---
--- `which` specifies what `who` refers to:
---
--- - `PRIO_PROCESS`: `who` is a process id (0 = calling process)
--- - `PRIO_PGRP`: `who` is a process group id (0 = calling process group)
--- - `PRIO_USER`: `who` is a user id (0 = calling user)
---
--- `prio` is the new priority value (nice value), ranging from -20
--- (highest priority) to 19 (lowest priority). Only privileged processes
--- can set negative priority values.
---
---@param which integer
---@param who integer
---@param prio integer
---@return true|nil
---@return string? error
---@return integer? errno
function unix.setpriority(which, who, prio) end

--- Returns information about resource usage for current process, e.g.
---
---     >: unix.getrusage()
---     {utime={0, 53644000}, maxrss=44896, minflt=545, oublock=24, nvcsw=9}
---
---@param who? integer defaults to `RUSAGE_SELF` and can be any of:
---
--- - `RUSAGE_SELF`: current process
--- - `RUSAGE_THREAD`: current thread
--- - `RUSAGE_CHILDREN`: not supported on Windows NT
--- - `RUSAGE_BOTH`: not supported on non-Linux
---
---@return unix.Rusage|nil # See `unix.Rusage` for details on returned fields.
---@return string? error
---@return integer? errno
---@nodiscard
function unix.getrusage(who) end

--- Restrict system operations.
---
--- This can be used to sandbox your redbean workers. It allows finer
--- customization compared to the `-S` flag.
---
--- Pledging causes most system calls to become unavailable. On Linux the
--- disabled calls will return EPERM whereas OpenBSD kills the process.
---
--- Using pledge is irreversible. On Linux it causes PR_SET_NO_NEW_PRIVS
--- to be set on your process.
---
--- By default exit and exit_group are always allowed. This is useful
--- for processes that perform pure computation and interface with the
--- parent via shared memory.
---
--- Once pledge is in effect, the chmod functions (if allowed) will not
--- permit the sticky/setuid/setgid bits to change. Linux will EPERM here
--- and OpenBSD should ignore those three bits rather than crashing.
---
--- User and group IDs also can't be changed once pledge is in effect.
--- OpenBSD should ignore the chown functions without crashing. Linux
--- will just EPERM.
---
--- Memory functions won't permit creating executable code after pledge.
--- Restrictions on origin of SYSCALL instructions will become enforced
--- on Linux (cf. msyscall) after pledge too, which means the process
--- gets killed if SYSCALL is used outside the .privileged section. One
--- exception is if the "exec" group is specified, in which case these
--- restrictions need to be loosened.
---
---@param promises? string may include any of the following groups delimited by spaces.
--- This list has been curated to focus on the
--- system calls for which this module provides wrappers. See the
--- Cosmopolitan Libc pledge() documentation for a comprehensive and
--- authoritative list of raw system calls. Having the raw system call
--- list may be useful if you're executing foreign programs.
---
--- ### stdio
---
--- Allows read, write, send, recv, recvfrom, close, clock_getres,
--- clock_gettime, dup, fchdir, fstat, fsync, fdatasync, ftruncate,
--- getdents, getegid, getrandom, geteuid, getgid, getgroups,
--- getitimer, getpgid, getpgrp, getpid, hgetppid, getresgid,
--- getresuid, getrlimit, getsid, gettimeofday, getuid, lseek,
--- madvise, brk, mmap/mprotect (PROT_EXEC isn't allowed), msync,
--- munmap, gethostname, nanosleep, pipe, pipe2, poll, setitimer,
--- shutdown, sigaction, sigsuspend, sigprocmask, socketpair, umask,
--- wait4, getrusage, ioctl(FIONREAD), ioctl(FIONBIO), ioctl(FIOCLEX),
--- ioctl(FIONCLEX), fcntl(F_GETFD), fcntl(F_SETFD), fcntl(F_GETFL),
--- fcntl(F_SETFL).
---
--- ### rpath
---
--- Allows chdir, getcwd, open, stat, fstat, access, readlink, chmod,
--- chmod, fchmod.
---
--- ### wpath
---
--- Allows getcwd, open, stat, fstat, access, readlink, chmod, fchmod.
---
--- ### cpath
---
--- Allows rename, link, symlink, unlink, mkdir, rmdir.
---
--- ### fattr
---
--- Allows chmod, fchmod, utimensat, futimens.
---
--- ### flock
---
--- Allows flock, fcntl(F_GETLK), fcntl(F_SETLK), fcntl(F_SETLKW).
---
--- ### tty
---
--- Allows isatty, tiocgwinsz, tcgets, tcsets, tcsetsw, tcsetsf.
---
--- ### inet
---
--- Allows socket (AF_INET), listen, bind, connect, accept,
--- getpeername, getsockname, setsockopt, getsockopt.
---
--- ### unix
---
--- Allows socket (AF_UNIX), listen, bind, connect, accept,
--- getpeername, getsockname, setsockopt, getsockopt.
---
--- ### dns
---
--- Allows sendto, recvfrom, socket(AF_INET), connect.
---
--- ### recvfd
---
--- Allows recvmsg, recvmmsg.
---
--- ### sendfd
---
--- Allows sendmsg, sendmmsg.
---
--- ### proc
---
--- Allows fork, vfork, clone, kill, tgkill, getpriority, setpriority,
--- setrlimit, setpgid, setsid.
---
--- ### id
---
--- Allows setuid, setreuid, setresuid, setgid, setregid, setresgid,
--- setgroups, setrlimit, getpriority, setpriority.
---
--- ### settime
---
--- Allows settimeofday and clock_adjtime.
---
--- ### unveil
---
--- Allows unveil().
---
--- ### exec
---
--- Allows execve.
---
--- If the executable in question needs a loader, then you will need
--- "rpath prot_exec" too. With APE, security is strongest when you
--- assimilate your binaries beforehand, using the --assimilate flag,
--- or the o//tool/build/assimilate program. On OpenBSD this is
--- mandatory.
---
--- ### prot_exec
---
--- Allows mmap(PROT_EXEC) and mprotect(PROT_EXEC).
---
--- This may be needed to launch non-static non-native executables,
--- such as non-assimilated APE binaries, or programs that link
--- dynamic shared objects, i.e. most Linux distro binaries.
---
---@param execpromises? string only matters if "exec" is specified in `promises`.
--- In that case, this specifies the promises that'll apply once `execve()`
--- happens. If this is `NULL` then the default is used, which is
--- unrestricted. OpenBSD allows child processes to escape the sandbox
--- (so a pledged OpenSSH server process can do things like spawn a root
--- shell). Linux however requires monotonically decreasing privileges.
--- This function will will perform some validation on Linux to make
--- sure that `execpromises` is a subset of `promises`. Your libc
--- wrapper for `execve()` will then apply its SECCOMP BPF filter later.
--- Since Linux has to do this before calling `sys_execve()`, the executed
--- process will be weakened to have execute permissions too.
---
---@param mode integer? if specified should specify one penalty:
---
--- - `unix.PLEDGE_PENALTY_KILL_THREAD` causes the violating thread to
---   be killed. This is the default on Linux. It's effectively the
---   same as killing the process, since redbean has no threads. The
---   termination signal can't be caught and will be either `SIGSYS`
---   or `SIGABRT`. Consider enabling stderr logging below so you'll
---   know why your program failed. Otherwise check the system log.
---
--- - `unix.PLEDGE_PENALTY_KILL_PROCESS` causes the process and all
---   its threads to be killed. This is always the case on OpenBSD.
---
--- - `unix.PLEDGE_PENALTY_RETURN_EPERM` causes system calls to just
---   return an `EPERM` error instead of killing. This is a gentler
---   solution that allows code to display a friendly warning. Please
---   note this may lead to weird behaviors if the software being
---   sandboxed is lazy about checking error results.
---
--- `mode` may optionally bitwise or the following flags:
---
--- - `unix.PLEDGE_STDERR_LOGGING` enables friendly error message
---   logging letting you know which promises are needed whenever
---   violations occur. Without this, violations will be logged to
---   `dmesg` on Linux if the penalty is to kill the process. You
---   would then need to manually look up the system call number and
---   then cross reference it with the cosmopolitan libc pledge()
---   documentation. You can also use `strace -ff` which is easier.
---   This is ignored OpenBSD, which already has a good system log.
---   Turning on stderr logging (which uses SECCOMP trapping) also
---   means that the `unix.WTERMSIG()` on your killed processes will
---   always be `unix.SIGABRT` on both Linux and OpenBSD. Otherwise,
---   Linux prefers to raise `unix.SIGSYS`.
---@return true|nil
---@return string? error
---@return integer? errno
function unix.pledge(promises, execpromises, mode) end

--- Restricts filesystem operations, e.g.
---
---    unix.unveil(".", "r");     -- current dir + children visible
---    unix.unveil("/etc", "r");  -- make /etc readable too
---    unix.unveil(nil, nil);     -- commit and lock policy
---
--- Unveiling restricts a thread's view of the filesystem to a set of
--- allowed paths with specific privileges.
---
--- Once you start using unveil(), the entire file system is considered
--- hidden. You then specify, by repeatedly calling unveil(), which paths
--- should become unhidden. When you're finished, you call `unveil(nil,nil)`
--- which commits your policy, after which further use is forbidden, in
--- the current thread, as well as any threads or processes it spawns.
---
--- There are some differences between unveil() on Linux versus OpenBSD.
---
--- 1. Build your policy and lock it in one go. On OpenBSD, policies take
---  effect immediately and may evolve as you continue to call unveil()
---  but only in a more restrictive direction. On Linux, nothing will
---  happen until you call `unveil(nil,nil)` which commits and locks.
---
--- 2. Try not to overlap directory trees. On OpenBSD, if directory trees
---  overlap, then the most restrictive policy will be used for a given
---  file. On Linux overlapping may result in a less restrictive policy
---  and possibly even undefined behavior.
---
--- 3. OpenBSD and Linux disagree on error codes. On OpenBSD, accessing
---  paths outside of the allowed set raises ENOENT, and accessing ones
---  with incorrect permissions raises EACCES. On Linux, both these
---  cases raise EACCES.
---
--- 4. Unlike OpenBSD, Linux does nothing to conceal the existence of
---  paths. Even with an unveil() policy in place, it's still possible
---  to access the metadata of all files using functions like stat()
---  and open(O_PATH), provided you know the path. A sandboxed process
---  can always, for example, determine how many bytes of data are in
---  /etc/passwd, even if the file isn't readable. But it's still not
---  possible to use opendir() and go fishing for paths which weren't
---  previously known.
---
--- This system call is supported natively on OpenBSD and polyfilled on
--- Linux using the Landlock LSM[1].
---
---@param path string is the file or directory to unveil
---
---@param permissions string is a string consisting of zero or more of the following characters:
---
--- - `r` makes `path` available for read-only path operations,
---   corresponding to the pledge promise "rpath".
---
--- - `w` makes `path` available for write operations, corresponding
---   to the pledge promise "wpath".
---
--- - `x` makes `path` available for execute operations,
---   corresponding to the pledge promises "exec" and "execnative".
---
--- - `c` allows `path` to be created and removed, corresponding to
---   the pledge promise "cpath".
---
---@return true|nil
---@return string? error
---@return integer? errno
---@overload fun(path: nil, permissions: nil): true
function unix.unveil(path, permissions) end

--- Breaks down UNIX timestamp into Zulu Time numbers.
---@param unixts integer
---@return integer|nil year
---@return integer mon 1 ≤ mon ≤ 12
---@return integer mday 1 ≤ mday ≤ 31
---@return integer hour 0 ≤ hour ≤ 23
---@return integer min 0 ≤ min ≤ 59
---@return integer sec 0 ≤ sec ≤ 60
---@return integer gmtoffsec ±93600 seconds
---@return integer wday 0 ≤ wday ≤ 6
---@return integer yday 0 ≤ yday ≤ 365
---@return integer dst 1 if daylight savings, 0 if not, -1 if unknown
---@return string zone
---@return string? error
---@return integer? errno
---@nodiscard
function unix.gmtime(unixts) end

--- Breaks down UNIX timestamp into local time numbers, e.g.
---
---     >: unix.localtime(unix.clock_gettime())
---     2022    4       28      2       14      22      -25200  4       117     1       "PDT"
---
--- This follows the same API as `gmtime()` which has further details.
---
--- Your redbean ships with a subset of the time zone database.
---
--- - `/zip/usr/share/zoneinfo/Honolulu`   Z-10
--- - `/zip/usr/share/zoneinfo/Anchorage`  Z -9
--- - `/zip/usr/share/zoneinfo/GST`        Z -8
--- - `/zip/usr/share/zoneinfo/Boulder`    Z -6
--- - `/zip/usr/share/zoneinfo/Chicago`    Z -5
--- - `/zip/usr/share/zoneinfo/New_York`   Z -4
--- - `/zip/usr/share/zoneinfo/UTC`        Z +0
--- - `/zip/usr/share/zoneinfo/GMT`        Z +0
--- - `/zip/usr/share/zoneinfo/London`     Z +1
--- - `/zip/usr/share/zoneinfo/Berlin`     Z +2
--- - `/zip/usr/share/zoneinfo/Israel`     Z +3
--- - `/zip/usr/share/zoneinfo/India`      Z +5
--- - `/zip/usr/share/zoneinfo/Beijing`    Z +8
--- - `/zip/usr/share/zoneinfo/Japan`      Z +9
--- - `/zip/usr/share/zoneinfo/Sydney`     Z+10
---
--- You can control which timezone is used using the `TZ` environment
--- variable. If your time zone isn't included in the above list, you
--- can simply copy it inside your redbean. The same is also the case
--- for future updates to the database, which can be swapped out when
--- needed, without having to recompile.
---
---@param unixts integer
---@return integer|nil year
---@return integer mon 1 ≤ mon ≤ 12
---@return integer mday 1 ≤ mday ≤ 31
---@return integer hour 0 ≤ hour ≤ 23
---@return integer min 0 ≤ min ≤ 59
---@return integer sec 0 ≤ sec ≤ 60
---@return integer gmtoffsec ±93600 seconds
---@return integer wday 0 ≤ wday ≤ 6
---@return integer yday 0 ≤ yday ≤ 365
---@return integer dst 1 if daylight savings, 0 if not, -1 if unknown
---@return string zone
---@return string? error
---@return integer? errno
function unix.localtime(unixts) end

--- Gets information about file or directory.
---@param path string
---@param flags? integer may have any of:
--- - `AT_SYMLINK_NOFOLLOW`: do not follow symbolic links.
---@param dirfd? integer defaults to `unix.AT_FDCWD` and may optionally be set to a directory file descriptor to which `path` is relative.
---@return unix.Stat|nil
---@return string? error
---@return integer? errno
---@nodiscard
function unix.stat(path, flags, dirfd) end

--- Tests if file mode represents a directory.
---@param mode integer
---@return boolean
function unix.S_ISDIR(mode) end

--- Tests if file mode represents a regular file.
---@param mode integer
---@return boolean
function unix.S_ISREG(mode) end

--- Tests if file mode represents a symbolic link.
---@param mode integer
---@return boolean
function unix.S_ISLNK(mode) end

--- Tests if file mode represents a block device.
---@param mode integer
---@return boolean
function unix.S_ISBLK(mode) end

--- Tests if file mode represents a character device.
---@param mode integer
---@return boolean
function unix.S_ISCHR(mode) end

--- Tests if file mode represents a FIFO/pipe.
---@param mode integer
---@return boolean
function unix.S_ISFIFO(mode) end

--- Tests if file mode represents a socket.
---@param mode integer
---@return boolean
function unix.S_ISSOCK(mode) end

--- Gets information about opened file descriptor.
---
---@param fd integer should be a file descriptor that was opened using `unix.open(path, O_RDONLY|O_DIRECTORY)`.
---
--- `flags` may have any of:
---
--- - `AT_SYMLINK_NOFOLLOW`: do not follow symbolic links.
---
--- `dirfd` defaults to to `unix.AT_FDCWD` and may optionally be set to
--- a directory file descriptor to which `path` is relative.
---
--- A common use for `fstat()` is getting the size of a file. For example:
---
---     fd = assert(unix.open("hello.txt", unix.O_RDONLY))
---     st = assert(unix.fstat(fd))
---     Log(kLogInfo, 'hello.txt is %d bytes in size' % {st:size()})
---     unix.close(fd)
---
---@return unix.Stat|nil
---@return string? error
---@return integer? errno
---@nodiscard
function unix.fstat(fd) end

--- Opens directory for listing its contents.
---
--- For example, to print a simple directory listing:
---
---     Write('<ul>\r\n')
---     for name, kind, ino, off in assert(unix.opendir(dir)) do
---         if name ~= '.' and name ~= '..' then
---            Write('<li>%s\r\n' % {EscapeHtml(name)})
---         end
---     end
---     Write('</ul>\r\n')
---
---@param path string
---@return unix.Dir|nil state
---@return string? error
---@return integer? errno
---@nodiscard
function unix.opendir(path) end

--- Opens directory for listing its contents, via an fd.
---
---@param fd integer should be created by `open(path, O_RDONLY|O_DIRECTORY)`.
--- The returned `unix.Dir` takes ownership of the file descriptor
--- and will close it automatically when garbage collected.
---
---@return unix.Dir|nil state
---@return string? error
---@return integer? errno
---@nodiscard
function unix.fdopendir(fd) end

--- Returns true if file descriptor is a teletypewriter. Otherwise nil
--- with an Errno object holding one of the following values:
---
--- - `ENOTTY` if `fd` is valid but not a teletypewriter
--- - `EBADF` if `fd` isn't a valid file descriptor.
--- - `EPERM` if pledge() is used without `tty` in lenient mode
---
--- No other error numbers are possible.
---
---@param fd integer
---@return true|nil
---@return string? error
---@return integer? errno
---@nodiscard
function unix.isatty(fd) end

---@param fd integer
---@return integer|nil rows, integer cols cellular dimensions of pseudoteletypewriter display.
---@return string? error
---@return integer? errno
---@nodiscard
function unix.tiocgwinsz(fd) end

---@class unix.Termios
---@field iflag integer Input mode flags (e.g. `unix.BRKINT`, `unix.ICRNL`).
---@field oflag integer Output mode flags (e.g. `unix.OPOST`, `unix.ONLCR`).
---@field cflag integer Control mode flags (e.g. `unix.CS8`, `unix.CREAD`).
---@field lflag integer Local mode flags (e.g. `unix.ECHO`, `unix.ICANON`).
---@field cc integer[] Control characters array (indexed 1 to `unix.NCCS`).
---@field ispeed integer Input baud rate.
---@field ospeed integer Output baud rate.

--- Gets terminal attributes.
---
--- Returns a termios table containing the terminal I/O settings for the
--- specified file descriptor. The table contains these fields:
---
--- - `iflag`: Input mode flags (e.g., `unix.ICRNL`, `unix.IXON`)
--- - `oflag`: Output mode flags (e.g., `unix.OPOST`, `unix.ONLCR`)
--- - `cflag`: Control mode flags (e.g., `unix.CS8`, `unix.CREAD`)
--- - `lflag`: Local mode flags (e.g., `unix.ECHO`, `unix.ICANON`)
--- - `cc`: Array of control characters indexed 1 to `unix.NCCS`
--- - `ispeed`: Input baud rate
--- - `ospeed`: Output baud rate
---
--- Example: reading a password without echoing:
---
---     local tio = unix.tcgetattr(0)
---     local old_lflag = tio.lflag
---     tio.lflag = tio.lflag & ~unix.ECHO
---     unix.tcsetattr(0, unix.TCSANOW, tio)
---     local password = io.read()
---     tio.lflag = old_lflag
---     unix.tcsetattr(0, unix.TCSANOW, tio)
---
---@param fd integer
---@return unix.Termios|nil termios
---@return string? error
---@return integer? errno
---@nodiscard
function unix.tcgetattr(fd) end

--- Sets terminal attributes.
---
--- Modifies the terminal I/O settings for the specified file descriptor
--- using the provided termios table. The `action` parameter controls when
--- the changes take effect:
---
--- - `unix.TCSANOW`: Changes occur immediately
--- - `unix.TCSADRAIN`: Changes occur after all output is transmitted
--- - `unix.TCSAFLUSH`: Changes occur after output is transmitted and
---   input is discarded
---
--- The termios table should contain the same fields as returned by
--- `unix.tcgetattr()`. Missing fields default to zero.
---
---@param fd integer
---@param action integer
---@param termios unix.Termios
---@return true|nil
---@return string? error
---@return integer? errno
function unix.tcsetattr(fd, action, termios) end

--- Returns file descriptor of open anonymous file.
---
--- This creates a secure temporary file inside `$TMPDIR`. If it isn't
--- defined, then `/tmp` is used on UNIX and GetTempPath() is used on
--- the New Technology. This resolution of `$TMPDIR` happens once.
---
--- Once close() is called, the returned file is guaranteed to be
--- deleted automatically. On UNIX the file is unlink()'d before this
--- function returns. On the New Technology it happens upon close().
---
--- On the New Technology, temporary files created by this function
--- should have better performance, because `kNtFileAttributeTemporary`
--- asks the kernel to more aggressively cache and reduce i/o ops.
---@return integer|nil fd
---@return string? error
---@return integer? errno
function unix.tmpfd() end

--- Relinquishes scheduled quantum.
function unix.sched_yield() end

--- Disassociates parts of the caller's execution context, placing it
--- into fresh namespace(s) specified by `flags` (bitwise OR of
--- `unix.CLONE_NEW*` constants). Linux-only; returns ENOSYS elsewhere.
---@param flags integer
---@return true|nil
---@return string? error
---@return integer? errno
function unix.unshare(flags) end

--- Reassociates the calling thread with the namespace referenced by
--- `fd` (typically from `/proc/<pid>/ns/*`). `nstype`, if nonzero,
--- must match a `unix.CLONE_NEW*` constant and asserts the kind of
--- namespace. Linux-only; returns ENOSYS elsewhere.
---@param fd integer
---@param nstype integer?
---@return true|nil
---@return string? error
---@return integer? errno
function unix.setns(fd, nstype) end

--- Mounts a filesystem. `flags` is a bitwise OR of `unix.MS_*`
--- constants; `data` is a filesystem-specific options string.
---@param source string?
---@param target string
---@param fstype string?
---@param flags integer?
---@param data string?
---@return true|nil
---@return string? error
---@return integer? errno
function unix.mount(source, target, fstype, flags, data) end

--- Unmounts a filesystem. On Linux this is the `umount2` syscall.
--- `flags` may include `unix.MNT_FORCE`, `unix.MNT_DETACH`,
--- `unix.MNT_EXPIRE`, `unix.UMOUNT_NOFOLLOW`.
---@param target string
---@param flags integer?
---@return true|nil
---@return string? error
---@return integer? errno
function unix.unmount(target, flags) end

--- Moves the root filesystem of the current mount namespace to
--- `put_old` and makes `new_root` the new root. Usually paired with
--- `chdir("/")` in the child. Requires a private mount namespace.
---@param new_root string
---@param put_old string
---@return true|nil
---@return string? error
---@return integer? errno
function unix.pivot_root(new_root, put_old) end

--- Performs an operation on the calling process. `option` is one of
--- the `unix.PR_*` constants; remaining arguments are option-specific.
--- Returns the integer result (0 for most setters).
---@param option integer
---@param arg2 integer?
---@param arg3 integer?
---@param arg4 integer?
---@param arg5 integer?
---@return integer|nil rc
---@return string? error
---@return integer? errno
function unix.prctl(option, arg2, arg3, arg4, arg5) end

--- Returns the calling thread's (or `pid`'s) capability sets as
--- 64-bit bitmasks. Each bit position N corresponds to `unix.CAP_*`
--- constant N. Linux-only.
---@param pid integer?
---@return integer|nil effective, integer permitted, integer inheritable
---@return string? error
---@return integer? errno
function unix.capget(pid) end

--- Sets the calling thread's (or `pid`'s) capability sets. Each
--- argument is a 64-bit bitmask of `1 << unix.CAP_*` bits. Linux-only.
---@param effective integer
---@param permitted integer
---@param inheritable integer
---@param pid integer?
---@return true|nil
---@return string? error
---@return integer? errno
function unix.capset(effective, permitted, inheritable, pid) end

--- Generic device control. When `arg` is nil or absent, the ioctl is
--- invoked with a null pointer. When `arg` is an integer, it's passed
--- by value. When `arg` is a string, a mutable copy of the same size
--- is passed to the kernel and the (possibly-modified) buffer of the
--- same length is returned.
---@param fd integer
---@param request integer
---@param arg (integer | string)?
---@return (true|nil | string) result
---@return string? error
---@return integer? errno
function unix.ioctl(fd, request, arg) end

--- Landlock: create ruleset. With no args, returns the kernel's
--- supported ABI version. With `handled_access_fs`, creates a new
--- ruleset file descriptor that handles the given access categories
--- (bitwise OR of `unix.LANDLOCK_ACCESS_FS_*`). Linux 5.13+.
---@param handled_access_fs integer?
---@param flags integer?
---@return integer|nil fd_or_abi
---@return string? error
---@return integer? errno
function unix.landlock_create_ruleset(handled_access_fs, flags) end

--- Landlock: add a PATH_BENEATH rule granting `allowed` access to the
--- subtree rooted at `parent_fd` (opened with `unix.O_PATH`). `allowed`
--- must be a subset of the ruleset's handled set.
---@param ruleset_fd integer
---@param parent_fd integer
---@param allowed integer
---@param flags integer?
---@return true|nil
---@return string? error
---@return integer? errno
function unix.landlock_add_rule(ruleset_fd, parent_fd, allowed, flags) end

--- Landlock: apply the ruleset to the current thread (and its future
--- children). Caller must set `PR_SET_NO_NEW_PRIVS` first or hold
--- `CAP_SYS_ADMIN`. The restriction is irrevocable.
---@param ruleset_fd integer
---@param flags integer?
---@return true|nil
---@return string? error
---@return integer? errno
function unix.landlock_restrict_self(ruleset_fd, flags) end

--- Creates interprocess shared memory mapping.
---
--- This function allocates special memory that'll be inherited across
--- fork in a shared way. By default all memory in Redbean is "private"
--- memory that's only viewable and editable to the process that owns
--- it. When unix.fork() happens, memory is copied appropriately so
--- that changes to memory made in the child process, don't clobber
--- the memory at those same addresses in the parent process. If you
--- don't want that to happen, and you want the memory to be shared
--- similar to how it would be shared if you were using threads, then
--- you can use this function to achieve just that.
---
--- The memory object this function returns may be accessed using its
--- methods, which support atomics and futexes. It's very low-level.
--- For example, you can use it to implement scalable mutexes:
---
---     mem = unix.mapshared(8000 * 8)
---
---     LOCK = 0 -- pick an arbitrary word index for lock
---
---     -- From Futexes Are Tricky Version 1.1 § Mutex, Take 3;
---     -- Ulrich Drepper, Red Hat Incorporated, June 27, 2004.
---     function Lock()
---         local ok, old = mem:cmpxchg(LOCK, 0, 1)
---         if not ok then
---             if old == 1 then
---                 old = mem:xchg(LOCK, 2)
---             end
---             while old > 0 do
---                 mem:wait(LOCK, 2)
---                 old = mem:xchg(LOCK, 2)
---             end
---         end
---     end
---     function Unlock()
---         old = mem:add(LOCK, -1)
---         if old == 2 then
---             mem:store(LOCK, 0)
---             mem:wake(LOCK, 1)
---         end
---     end
---
--- It's possible to accomplish the same thing as unix.mapshared()
--- using files and unix.fcntl() advisory locks. However this goes
--- significantly faster. For example, that's what SQLite does and
--- we recommend using SQLite for IPC in redbean. But, if your app
--- has thousands of forked processes fighting for a file lock you
--- might need something lower level than file locks, to implement
--- things like throttling. Shared memory is a good way to do that
--- since there's nothing that's faster.
---
---@param size integer
--- The `size` parameter needs to be a multiple of 8. The returned
--- memory is zero initialized. When allocating shared memory, you
--- should try to get as much use out of it as possible, since the
--- overhead of allocating a single shared mapping is 500 words of
--- resident memory and 8000 words of virtual memory. It's because
--- the Cosmopolitan Libc mmap() granularity is 2**16.
---
--- This system call does not fail. An exception is instead thrown
--- if sufficient memory isn't available.
---
---@return unix.Memory
function unix.mapshared(size) end

---@class unix.Memory: userdata
--- Shared memory for inter-process communication.
---
--- Provides atomic operations and wait/wake primitives for synchronization.
--- unix.Memory encapsulates memory that's shared across fork() and
--- this module provides the fundamental synchronization primitives.
---
--- Redbean memory maps may be used in two ways:
---
--- 1. as an array of bytes a.k.a. a string
--- 2. as an array of words a.k.a. integers
---
--- They're aliased, union, or overlapped views of the same memory.
--- For example if you write a string to your memory region, you'll
--- be able to read it back as an integer.
---
--- Reads, writes, and word operations will throw an exception if a
--- memory boundary error or overflow occurs.
unix.Memory = {}

---@param offset integer?
--- The starting byte index from which memory is copied, which defaults to zero.
---
---@param bytes integer?
--- If `bytes` is none or nil, then the nul-terminated string at
--- `offset` is returned. You may specify `bytes` to safely read
--- binary data.
---
--- This operation happens atomically. Each shared mapping has a
--- single lock which is used to synchronize reads and writes to
--- that specific map. To make it scale, create additional maps.
---@return string
---@nodiscard
function unix.Memory:read(offset, bytes) end

--- Writes bytes to memory region.
---
---@param data string
---@param offset integer?
--- `offset` is the starting byte index to which memory is copied,
--- which defaults to zero.
---
---@param bytes integer?
--- If `bytes` is none or nil, then an implicit nil-terminator
--- will be included after your `data` so things like json can
--- be easily serialized to shared memory.
---
--- This operation happens atomically. Each shared mapping has a
--- single lock which is used to synchronize reads and writes to
--- that specific map. To make it scale, create additional maps.
function unix.Memory:write(data, offset, bytes) end

--- Loads word from memory region.
---
--- This operation is atomic and has relaxed barrier semantics.
---@param word_index integer
---@return integer
---@nodiscard
function unix.Memory:load(word_index) end

--- Stores word from memory region.
---
--- This operation is atomic and has relaxed barrier semantics.
---@param word_index integer
---@param value integer
function unix.Memory:store(word_index, value) end

--- Exchanges value.
---
--- This sets word at `word_index` to `value` and returns the value
--- previously held in by the word.
---
--- This operation is atomic and provides the same memory barrier
--- semantics as the aligned x86 LOCK XCHG instruction.
---@param word_index integer
---@param value integer
---@return integer
function unix.Memory:xchg(word_index, value) end

--- Compares and exchanges value.
---
--- This inspects the word at `word_index` and if its value is the same
--- as `old` then it'll be replaced by the value `new`, in which case
--- `true, old` shall be returned. If a different value was held at
--- word, then `false` shall be returned along with the word.
---
--- This operation happens atomically and provides the same memory
--- barrier semantics as the aligned x86 LOCK CMPXCHG instruction.
---@param word_index integer
---@param old integer
---@param new integer
---@return boolean success, integer old
function unix.Memory:cmpxchg(word_index, old, new) end

--- Fetches then adds value.
---
--- This method modifies the word at `word_index` to contain the sum of
--- value and the `value` paremeter. This method then returns the value
--- as it existed before the addition was performed.
---
--- This operation is atomic and provides the same memory barrier
--- semantics as the aligned x86 LOCK XADD instruction.
---@param word_index integer
---@param value integer
---@return integer old
function unix.Memory:fetch_add(word_index, value) end

--- Fetches and bitwise ands value.
---
--- This operation happens atomically and provides the same memory
--- barrier ordering semantics as its x86 implementation.
---@param word_index integer
---@param value integer
---@return integer
function unix.Memory:fetch_and(word_index, value) end

--- Fetches and bitwise ors value.
---
--- This operation happens atomically and provides the same memory
--- barrier ordering semantics as its x86 implementation.
---@param word_index integer
---@param value integer
---@return integer
function unix.Memory:fetch_or(word_index, value) end

--- Fetches and bitwise xors value.
---
--- This operation happens atomically and provides the same memory
--- barrier ordering semantics as its x86 implementation.
---@param word_index integer
---@param value integer
---@return integer
function unix.Memory:fetch_xor(word_index, value) end

--- Waits for word to have a different value.
---
--- This method asks the kernel to suspend the process until either the
--- absolute deadline expires or we're woken up by another process that
--- calls `unix.Memory:wake()`.
---
--- The `expect` parameter is used only upon entry to synchronize the
--- transition to kernelspace. The kernel doesn't actually poll the
--- memory location. It uses `expect` to make sure the process doesn't
--- get added to the wait list unless it's sure that it needs to wait,
--- since the kernel can only control the ordering of wait / wake calls
--- across processes.
---
--- Futex words are 32-bit. Although words are stored as 64-bit integers,
--- wait / wake only ever inspect the low 32 bits, so `expect` must fit in
--- an int32 and the word you wait on must hold only int32 values. If the
--- word at `word_index` has any of its high 32 bits set when you call
--- wait, this method raises an error rather than silently comparing a
--- truncated value (e.g. a stored 2^32+1 must not masquerade as 1).
---
--- The default behavior is to wait until the heat death of the universe
--- if necessary. You may alternatively specify an absolute deadline. If
--- it's less than or equal to the value returned by clock_gettime, then
--- this routine is non-blocking. Otherwise we'll block at most until
--- the current time reaches the absolute deadline.
---
--- Futexes are currently supported on Linux, FreeBSD, OpenBSD. On other
--- platforms this method calls sched_yield() and will either (1) return
--- unix.EINTR if a deadline is specified, otherwise (2) 0 is returned.
--- This means futexes will *work* on Windows, Mac, and NetBSD but they
--- won't be scalable in terms of CPU usage when many processes wait on
--- one process that holds a lock for a long time. In the future we may
--- polyfill futexes in userspace for these platforms to improve things
--- for folks who've adopted this api. If lock scalability is something
--- you need on Windows and MacOS today, then consider fcntl() which is
--- well-supported on all supported platforms but requires using files.
--- Please test your use case though, because it's kind of an edge case
--- to have the scenario above, and chances are this op will work fine.
---
---@return 0|nil
---@return string? error
---@return integer? errno
---
--- `EINTR` if a signal is delivered while waiting on deadline. Callers
--- should use futexes inside a loop that is able to cope with spurious
--- wakeups. We don't actually guarantee the value at word has in fact
--- changed when this returns.
---
--- `EAGAIN` is raised if, upon entry, the word at `word_index` had a
--- different value than what's specified at `expect`.
---
--- `ETIMEDOUT` is raised when the absolute deadline expires.
---
---@param word_index integer
---@param expect integer
---@param abs_deadline integer?
---@param nanos integer?
function unix.Memory:wait(word_index, expect, abs_deadline, nanos) end

--- Wakes other processes waiting on word.
---
--- This method may be used to signal or broadcast to waiters. The
--- `count` specifies the number of processes that should be woken,
--- which defaults to `INT_MAX`.
---
--- The return value is the number of processes that were actually woken
--- as a result of the system call. No failure conditions are defined.
---@param index integer
---@param count integer?
---@return integer woken
function unix.Memory:wake(index, count) end

---@class unix.Dir: userdata
--- Directory handle for reading directory entries.
---
--- `unix.Dir` objects are created by `opendir()` or `fdopendir()`.
unix.Dir = {}

--- Closes directory stream object and associated its file descriptor.
---
--- This is called automatically by the garbage collector.
---
--- This may be called multiple times.
---@return true|nil
---@return string? error
---@return integer? errno
function unix.Dir:close() end

--- Reads entry from directory stream.
---
--- Returns `nil` if there are no more entries.
--- On error, `nil` will be returned and `errno` will be non-nil.
---
--- `kind` can be any of:
---
--- - `DT_REG`: file is a regular file
--- - `DT_DIR`: file is a directory
--- - `DT_BLK`: file is a block device
--- - `DT_LNK`: file is a symbolic link
--- - `DT_CHR`: file is a character device
--- - `DT_FIFO`: file is a named pipe
--- - `DT_SOCK`: file is a named socket
--- - `DT_UNKNOWN`
---
--- Note: This function also serves as the `__call` metamethod, so that
--- `unix.Dir` objects may be used as a for loop iterator.
---
---@return string|nil name, integer kind, integer ino, integer off
---@nodiscard
function unix.Dir:read() end

---@return integer|nil fd file descriptor of open directory object.
---@return string? error
---@return integer? errno
---@nodiscard
--- Returns `EOPNOTSUPP` if using a `/zip/...` path or if using Windows NT.
function unix.Dir:fd() end

---@return integer|nil off current arbitrary offset into stream.
---@return string? error
---@return integer? errno
---@nodiscard
function unix.Dir:tell() end

---Resets stream back to beginning.
function unix.Dir:rewind() end

---@class unix.Rusage: userdata
--- Process resource usage statistics.
---
--- Contains CPU time, memory usage, I/O, and context switch counters.
--- `unix.Rusage` objects are created by `wait()` or `getrusage()`.
unix.Rusage = {}

---@return integer seconds, integer nanos amount of CPU consumed in userspace.
---@nodiscard
---
--- It's always the case that `0 ≤ nanos < 1e9`.
---
--- On Windows NT this is collected from GetProcessTimes().
function unix.Rusage:utime() end

---@return integer seconds, integer nanos amount of CPU consumed in kernelspace.
---@nodiscard
---
--- It's always the case that `0 ≤ nanos < 1e9`.
---
--- On Windows NT this is collected from GetProcessTimes().
function unix.Rusage:stime() end

---@return integer kilobytes amount of physical memory used at peak consumption.
---@nodiscard
---
--- On Windows NT this is collected from
--- `NtProcessMemoryCountersEx::PeakWorkingSetSize / 1024`.
function unix.Rusage:maxrss() end

---@return integer integralkilobytes integral private memory consumption w.r.t. scheduled ticks.
---@nodiscard
---
--- If you chart memory usage over the lifetime of your process, then
--- this would be the space filled in beneath the chart. The frequency
--- of kernel scheduling is defined as `unix.CLK_TCK`.  Each time a tick
--- happens, the kernel samples your process's memory usage, by adding
--- it to this value. You can derive the average consumption from this
--- value by computing how many ticks are in `utime + stime`.
---
--- Currently only available on FreeBSD and NetBSD.
function unix.Rusage:idrss() end

---@return integer integralkilobytes integral shared memory consumption w.r.t. scheduled ticks.
---@nodiscard
---
--- If you chart memory usage over the lifetime of your process, then
--- this would be the space filled in beneath the chart. The frequency
--- of kernel scheduling is defined as unix.CLK_TCK.  Each time a tick
--- happens, the kernel samples your process's memory usage, by adding
--- it to this value. You can derive the average consumption from this
--- value by computing how many ticks are in `utime + stime`.
---
--- Currently only available on FreeBSD and NetBSD.
function unix.Rusage:ixrss() end

---@return integer integralkilobytes integral stack memory consumption w.r.t. scheduled ticks.
---@nodiscard
---
--- If you chart memory usage over the lifetime of your process, then
--- this would be the space filled in beneath the chart. The frequency
--- of kernel scheduling is defined as `unix.CLK_TCK`. Each time a tick
--- happens, the kernel samples your process's memory usage, by adding
--- it to this value. You can derive the average consumption from this
--- value by computing how many ticks are in `utime + stime`.
---
--- This is only applicable to redbean if its built with MODE=tiny,
--- because redbean likes to allocate its own deterministic stack.
---
--- Currently only available on FreeBSD and NetBSD.
function unix.Rusage:isrss() end

---@return integer count number of minor page faults.
---@nodiscard
---
--- This number indicates how many times redbean was preempted by the
--- kernel to `memcpy()` a 4096-byte page. This is one of the tradeoffs
--- `fork()` entails. This number is usually tinier, when your binaries
--- are tinier.
---
--- Not available on Windows NT.
function unix.Rusage:minflt() end

---Returns number of major page faults.
---
---This number indicates how many times redbean was preempted by the
---kernel to perform i/o. For example, you might have used `mmap()` to
---load a large file into memory lazily.
---
---On Windows NT this is `NtProcessMemoryCountersEx::PageFaultCount`.
---@return integer count
---@nodiscard
function unix.Rusage:majflt() end

---@return integer count number of swap operations.
---@nodiscard
---
--- Operating systems like to reserve hard disk space to back their RAM
--- guarantees, like using a gold standard for fiat currency. When your
--- system is under heavy memory load, swap operations may happen while
--- redbean is working. This number keeps track of them.
---
--- Not available on Linux, Windows NT.
function unix.Rusage:nswap() end

---@return integer count number of times filesystem had to perform input.
---@nodiscard
---On Windows NT this is `NtIoCounters::ReadOperationCount`.
function unix.Rusage:inblock() end

---@return integer count number of times filesystem had to perform output.
---@nodiscard
--- On Windows NT this is `NtIoCounters::WriteOperationCount`.
function unix.Rusage:oublock() end

---@return integer count count of ipc messages sent.
---@nodiscard
--- Not available on Linux, Windows NT.
function unix.Rusage:msgsnd() end

---@return integer count count of ipc messages received.
---@nodiscard
--- Not available on Linux, Windows NT.
function unix.Rusage:msgrcv() end

---@return integer count number of signals received.
---@nodiscard
--- Not available on Linux.
function unix.Rusage:nsignals() end

---@return integer count number of voluntary context switches.
---@nodiscard
---
--- This number is a good thing. It means your redbean finished its work
--- quickly enough within a time slice that it was able to give back the
--- remaining time to the system.
function unix.Rusage:nvcsw() end

---@return integer count number of non-consensual context switches.
---
--- This number is a bad thing. It means your redbean was preempted by a
--- higher priority process after failing to finish its work, within the
--- allotted time slice.
function unix.Rusage:nivcsw() end

---@class unix.Stat: userdata
--- File metadata and attributes.
---
--- Contains file size, permissions, ownership, and timestamps.
--- `unix.Stat` objects are created by `stat()` or `fstat()`.
--- Use `unix.S_ISDIR()`, `unix.S_ISREG()`, etc. to check file type from mode.
unix.Stat = {}

---@return integer bytes Size of file in bytes.
---@nodiscard
function unix.Stat:size() end

--- Contains file type and permissions.
---
--- For example, `0010644` is what you might see for a file and
--- `0040755` is what you might see for a directory.
---
--- To determine the file type:
---
--- - `unix.S_ISREG(st:mode())` means regular file
--- - `unix.S_ISDIR(st:mode())` means directory
--- - `unix.S_ISLNK(st:mode())` means symbolic link
--- - `unix.S_ISCHR(st:mode())` means character device
--- - `unix.S_ISBLK(st:mode())` means block device
--- - `unix.S_ISFIFO(st:mode())` means fifo or pipe
--- - `unix.S_ISSOCK(st:mode())` means socket
---
---@return integer mode
---@nodiscard
function unix.Stat:mode() end

---@return integer uid User ID of file owner.
---@nodiscard
function unix.Stat:uid() end

---@return integer gid Group ID of file owner.
---@nodiscard
function unix.Stat:gid() end

--- File birth time.
---
--- This field should be accurate on Apple, Windows, and BSDs. On Linux
--- this is the minimum of atim/mtim/ctim. On Windows NT nanos is only
--- accurate to hectonanoseconds.
---
--- Here's an example of how you might print a file timestamp:
---
---   st = assert(unix.stat('/etc/passwd'))
---   unixts, nanos = st:birthtim()
---   year,mon,mday,hour,min,sec,gmtoffsec = unix.localtime(unixts)
---   Write('%.4d-%.2d-%.2dT%.2d:%.2d:%.2d.%.9d%+.2d%.2d % {
---            year, mon, mday, hour, min, sec, nanos,
---            gmtoffsec / (60 * 60), math.abs(gmtoffsec) % 60})
---@return integer unixts, integer nanos
---@nodiscard
function unix.Stat:birthtim() end

---@return integer unixts, integer nanos Last modified time.
---@nodiscard
function unix.Stat:mtim() end

---@return integer unixts, integer nanos Last access time.
---@nodiscard
---
--- Please note that file systems are sometimes mounted with `noatime`
--- out of concern for i/o performance. Linux also provides `O_NOATIME`
--- as an option for open().
---
--- On Windows NT this is the same as birth time.
function unix.Stat:atim() end

---@return integer unixts, integer nanos  Complicated time.
---@nodiscard
---
--- Means time file status was last changed on UNIX.
---
--- On Windows NT this is the same as birth time.
function unix.Stat:ctim() end

---@return integer count512 Number of 512-byte blocks used by storage medium.
---@nodiscard
--- This provides some indication of how much physical storage a file
--- actually consumes. For example, for small file systems, your system
--- might report this number as being 8, which means 4096 bytes.
function unix.Stat:blocks() end

---@return integer bytes Block size that underlying device uses.
---@nodiscard
---
--- This field might be of assistance in computing optimal i/o sizes.
---
--- Please note this field has no relationship to blocks, as the latter
--- is fixed at a 512 byte size.
function unix.Stat:blksize() end

---@return integer inode Inode number.
---@nodiscard
---
--- This can be used to detect some other process used `rename()` to swap
--- out a file underneath you, so you can do a refresh. redbean does it
--- during each main process heartbeat for its own use cases.
---
--- On Windows NT this is set to `NtByHandleFileInformation::FileIndex`.
function unix.Stat:ino() end

---@return integer dev ID of device containing file.
---@nodiscard
--- On Windows NT this is set to `NtByHandleFileInformation::VolumeSerialNumber`.
function unix.Stat:dev() end

---@return integer rdev Information about device type.
---@nodiscard
--- This value may be set to `0` or `-1` for files that aren't devices,
--- depending on the operating system. `unix.major()` and `unix.minor()`
--- may be used to extract the device numbers.
function unix.Stat:rdev() end

---@return integer nlink Number of hard links to the file.
---@nodiscard
function unix.Stat:nlink() end

---@return integer gen Inode generation number.
---@nodiscard
function unix.Stat:gen() end

---@return integer flags User-defined flags on the file.
---@nodiscard
function unix.Stat:flags() end

--- Extracts the major device number from a device id such as `Stat:rdev()`.
---@param rdev integer
---@return integer major
---@nodiscard
function unix.major(rdev) end

--- Extracts the minor device number from a device id such as `Stat:rdev()`.
---@param rdev integer
---@return integer minor
---@nodiscard
function unix.minor(rdev) end

---@class unix.Statfs: userdata
--- Filesystem statistics returned by `statfs()` and `fstatfs()`.

--- Returns filesystem type identifier.
---@return integer
---@nodiscard
function unix.Statfs:type() end

--- Returns optimal transfer block size.
---@return integer bsize
---@nodiscard
function unix.Statfs:bsize() end

--- Returns total data blocks in filesystem.
---@return integer blocks
---@nodiscard
function unix.Statfs:blocks() end

--- Returns free blocks in filesystem.
---@return integer bfree
---@nodiscard
function unix.Statfs:bfree() end

--- Returns free blocks available to unprivileged user.
---@return integer bavail
---@nodiscard
function unix.Statfs:bavail() end

--- Returns total file nodes in filesystem.
---@return integer files
---@nodiscard
function unix.Statfs:files() end

--- Returns free file nodes in filesystem.
---@return integer ffree
---@nodiscard
function unix.Statfs:ffree() end

--- Returns filesystem ID as two numbers.
---@return integer id0
---@return integer id1
---@nodiscard
function unix.Statfs:fsid() end

--- Returns maximum length of filenames.
---@return integer namelen
---@nodiscard
function unix.Statfs:namelen() end

--- Returns fragment size.
---@return integer frsize
---@nodiscard
function unix.Statfs:frsize() end

--- Returns mount flags.
---@return integer flags
---@nodiscard
function unix.Statfs:flags() end

--- Returns the owner of the mount.
---@return integer owner
---@nodiscard
function unix.Statfs:owner() end

--- Returns the filesystem type name, e.g. "ext4".
---@return string fstypename
---@nodiscard
function unix.Statfs:fstypename() end

--- Gets filesystem statistics for the filesystem that contains `path`.
---@param path string
---@return unix.Statfs|nil
---@return string? error
---@return integer? errno
---@nodiscard
function unix.statfs(path) end

--- Gets filesystem statistics via an open file descriptor.
---@param fd integer
---@return unix.Statfs|nil
---@return string? error
---@return integer? errno
---@nodiscard
function unix.fstatfs(fd) end

---@class unix.Sigset: userdata
--- Signal set for blocking, unblocking, and waiting on signals.
---
--- Used with `unix.sigprocmask()`, `unix.sigaction()`, and `unix.sigsuspend()`.
--- The unix.Sigset class defines a mutable bitset that may currently
--- contain 128 entries. See `unix.NSIG` to find out how many signals
--- your operating system actually supports.
---
--- Constructs new signal bitset object.
---@param sig integer
---@param ... integer
---@return unix.Sigset
---@nodiscard
function unix.Sigset(sig, ...) end

--- Adds signal to bitset.
---@param sig integer
function unix.Sigset:add(sig) end

--- Removes signal from bitset.
---@param sig integer
function unix.Sigset:remove(sig) end

--- Sets all bits in signal bitset to `true`.
function unix.Sigset:fill() end

--- Sets all bits in signal bitset to `false`.
function unix.Sigset:clear() end

---@param sig integer
---@return boolean # `true` if `sig` is member of signal bitset.
---@nodiscard
function unix.Sigset:contains(sig) end

---@return string # Lua code string that recreates object.
---@nodiscard
function unix.Sigset:__repr() end

---@return string # Lua code string that recreates object.
---@nodiscard
function unix.Sigset:__tostring() end
