#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘
#
# OVERVIEW
#
#   SQLite Embedded Database
#
# NOTES
#
#   The upstream two-file amalgamation is compiled twice: sqlite3.o
#   with the library define set below (linked into libsqlite3.a for
#   the lua bindings et al) and sqlite3.shell.o with the shell's
#   larger feature set (fts3/4/5, rtree, geopoly, zlib) for the
#   sqlite3 command line shell.
#
#   Please be warned that locks currently do nothing on Windows since
#   figuring out how to polyfill them correctly is a work in progress
#   Further note we currently don't do that thing SQLite does for Mac
#   file locks so your dbase will only be as reliable as Apple wanted
#   it to be when they wrote their POSIX file locking implementation.

PKGS += THIRD_PARTY_SQLITE3

THIRD_PARTY_SQLITE3_ARTIFACTS += THIRD_PARTY_SQLITE3_A
THIRD_PARTY_SQLITE3 = $(THIRD_PARTY_SQLITE3_A_DEPS) $(THIRD_PARTY_SQLITE3_A)
THIRD_PARTY_SQLITE3_A = o/$(MODE)/third_party/sqlite3/libsqlite3.a
THIRD_PARTY_SQLITE3_BINS = $(THIRD_PARTY_SQLITE3_COMS) $(THIRD_PARTY_SQLITE3_COMS:%=%.dbg)

THIRD_PARTY_SQLITE3_A_HDRS =					\
	third_party/sqlite3/qrf.h				\
	third_party/sqlite3/extensions.h			\
	third_party/sqlite3/sqlite3.h				\
	third_party/sqlite3/sqlite3ext.h			\
	third_party/sqlite3/tclsqlite.h

THIRD_PARTY_SQLITE3_A_SRCS =					\
	third_party/sqlite3/sqlite3.c				\
	third_party/sqlite3/zipfile.c				\
	third_party/sqlite3/sqlite3.shell.c			\
	third_party/sqlite3/shell.c

THIRD_PARTY_SQLITE3_A_OBJS =					\
	o/$(MODE)/third_party/sqlite3/sqlite3.o			\
	o/$(MODE)/third_party/sqlite3/zipfile.o

THIRD_PARTY_SQLITE3_SHELL_OBJS =				\
	o/$(MODE)/third_party/sqlite3/sqlite3.shell.o		\
	o/$(MODE)/third_party/sqlite3/shell.o

THIRD_PARTY_SQLITE3_COMS =					\
	o/$(MODE)/third_party/sqlite3/sqlite3

THIRD_PARTY_SQLITE3_A_CHECKS =					\
	$(THIRD_PARTY_SQLITE3_A).pkg				\
	$(THIRD_PARTY_SQLITE3_A_HDRS:%=o/$(MODE)/%.ok)

THIRD_PARTY_SQLITE3_A_DIRECTDEPS =				\
	LIBC_CALLS						\
	LIBC_FMT						\
	LIBC_INTRIN						\
	LIBC_MEM						\
	LIBC_NEXGEN32E						\
	LIBC_PROC						\
	LIBC_RUNTIME						\
	LIBC_STDIO						\
	LIBC_STR						\
	LIBC_SYSTEM						\
	LIBC_SYSV						\
	LIBC_SYSV_CALLS						\
	LIBC_THREAD						\
	LIBC_TINYMATH						\
	THIRD_PARTY_COMPILER_RT					\
	THIRD_PARTY_GDTOA					\
	THIRD_PARTY_LINENOISE					\
	THIRD_PARTY_MUSL					\
	THIRD_PARTY_TZ						\
	THIRD_PARTY_ZLIB					\
	TOOL_ARGS						\

THIRD_PARTY_SQLITE3_A_DEPS :=					\
	$(call uniq,$(foreach x,$(THIRD_PARTY_SQLITE3_A_DIRECTDEPS),$($(x))))

o/$(MODE)/third_party/sqlite3/sqlite3.dbg:			\
		$(THIRD_PARTY_SQLITE3_A_DEPS)			\
		$(THIRD_PARTY_SQLITE3_SHELL_OBJS)		\
		o/$(MODE)/third_party/sqlite3/shell.pkg		\
		$(CRT)						\
		$(APE_NO_MODIFY_SELF)
	@$(APELINK)

$(THIRD_PARTY_SQLITE3_A):					\
		third_party/sqlite3/				\
		$(THIRD_PARTY_SQLITE3_A).pkg			\
		$(THIRD_PARTY_SQLITE3_A_OBJS)

$(THIRD_PARTY_SQLITE3_A).pkg:					\
		$(THIRD_PARTY_SQLITE3_A_OBJS)			\
		$(foreach x,$(THIRD_PARTY_SQLITE3_A_DIRECTDEPS),$($(x)_A).pkg)

o/$(MODE)/third_party/sqlite3/shell.pkg:			\
		$(THIRD_PARTY_SQLITE3_SHELL_OBJS)		\
		$(foreach x,$(THIRD_PARTY_SQLITE3_A_DIRECTDEPS),$($(x)_A).pkg)

# https://www.sqlite.org/compile.html
THIRD_PARTY_SQLITE3_FLAGS =					\
	-DNDEBUG						\
	-DSQLITE_CORE						\
	-DSQLITE_OS_UNIX					\
	-DBUILD_sqlite						\
	-DHAVE_USLEEP						\
	-DHAVE_READLINK						\
	-DHAVE_FCHOWN						\
	-DHAVE_MREMAP						\
	-DHAVE_LSTAT						\
	-DHAVE_GMTIME_R						\
	-DHAVE_FDATASYNC					\
	-DHAVE_STRCHRNUL					\
	-DHAVE_LOCALTIME_R					\
	-DHAVE_MALLOC_USABLE_SIZE				\
	-DSQLITE_THREADSAFE=1					\
	-DSQLITE_MAX_EXPR_DEPTH=0				\
	-DSQLITE_DEFAULT_MEMSTATUS=0				\
	-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1			\
	-DSQLITE_LIKE_DOESNT_MATCH_BLOBS			\
	-DSQLITE_OMIT_UTF16					\
	-DSQLITE_OMIT_TCL_VARIABLE				\
	-DSQLITE_OMIT_LOAD_EXTENSION				\
	-DSQLITE_OMIT_AUTOINIT					\
	-DSQLITE_OMIT_GET_TABLE					\
	-DSQLITE_OMIT_COMPILEOPTION_DIAGS                       \
	-DSQLITE_HAVE_C99_MATH_FUNCS				\
	-DSQLITE_ENABLE_MATH_FUNCTIONS				\
	-DSQLITE_ENABLE_JSON1					\
	-DSQLITE_ENABLE_DESERIALIZE				\
	-DSQLITE_ENABLE_PREUPDATE_HOOK				\
	-DSQLITE_ENABLE_SESSION					\
	-DSQLITE_ENABLE_BATCH_ATOMIC_WRITE			\

ifeq ($(MODE),dbg)
THIRD_PARTY_SQLITE3_CPPFLAGS_DEBUG = -DSQLITE_DEBUG
endif

$(THIRD_PARTY_SQLITE3_A_OBJS): private				\
		CFLAGS +=					\
			$(THIRD_PARTY_SQLITE3_FLAGS)		\
			$(THIRD_PARTY_SQLITE3_CPPFLAGS_DEBUG)	\

$(THIRD_PARTY_SQLITE3_SHELL_OBJS): private			\
		CFLAGS +=					\
			$(THIRD_PARTY_SQLITE3_FLAGS)		\
			$(THIRD_PARTY_SQLITE3_CPPFLAGS_DEBUG)	\
			-DHAVE_READLINE=0			\
			-DHAVE_EDITLINE=0			\
			-DSQLITE_HAVE_ZLIB			\
			-DSQLITE_ENABLE_IOTRACE			\
			-DSQLITE_ENABLE_COLUMN_METADATA		\
			-DSQLITE_ENABLE_EXPLAIN_COMMENTS	\
			-DSQLITE_ENABLE_UNKNOWN_SQL_FUNCTION	\
			-DSQLITE_ENABLE_STMTVTAB		\
			-DSQLITE_ENABLE_DBPAGE_VTAB		\
			-DSQLITE_ENABLE_DBSTAT_VTAB		\
			-DSQLITE_ENABLE_BYTECODE_VTAB		\
			-DSQLITE_ENABLE_OFFSET_SQL_FUNC		\
			-DSQLITE_ENABLE_DESERIALIZE		\
			-DSQLITE_ENABLE_FTS3			\
			-DSQLITE_ENABLE_FTS4			\
			-DSQLITE_ENABLE_FTS5			\
			-DSQLITE_ENABLE_RTREE			\
			-DSQLITE_ENABLE_GEOPOLY			\
			-DHAVE_LINENOISE

o/$(MODE)/third_party/sqlite3/shell.o: private			\
		CFLAGS +=					\
			-DSTACK_FRAME_UNLIMITED

# section splitting lets binaries gc unused sqlite features; dbg mode
# turns it off (ubsan at -O0 would push the amalgamation past the 65535
# elf section limit that fixupobj knows how to process)
ifeq ($(findstring dbg,$(MODE)),)
$(THIRD_PARTY_SQLITE3_A_OBJS)					\
$(THIRD_PARTY_SQLITE3_SHELL_OBJS): private			\
		CFLAGS +=					\
			-fdata-sections				\
			-ffunction-sections
endif

o/$(MODE)/third_party/sqlite3/sqlite3.o: private QUOTA = -C128 -L400
o/$(MODE)/third_party/sqlite3/sqlite3.shell.o: private QUOTA = -C128 -L400
o/$(MODE)/third_party/sqlite3/shell.o: private QUOTA = -C32 -L180

THIRD_PARTY_SQLITE3_LIBS = $(foreach x,$(THIRD_PARTY_SQLITE3_ARTIFACTS),$($(x)))
THIRD_PARTY_SQLITE3_SRCS = $(foreach x,$(THIRD_PARTY_SQLITE3_ARTIFACTS),$($(x)_SRCS))
THIRD_PARTY_SQLITE3_HDRS = $(foreach x,$(THIRD_PARTY_SQLITE3_ARTIFACTS),$($(x)_HDRS))
THIRD_PARTY_SQLITE3_CHECKS = $(foreach x,$(THIRD_PARTY_SQLITE3_ARTIFACTS),$($(x)_CHECKS))
THIRD_PARTY_SQLITE3_OBJS = $(foreach x,$(THIRD_PARTY_SQLITE3_ARTIFACTS),$($(x)_OBJS))

$(THIRD_PARTY_SQLITE3_A_OBJS): third_party/sqlite3/BUILD.mk
$(THIRD_PARTY_SQLITE3_SHELL_OBJS): third_party/sqlite3/BUILD.mk

.PHONY: o/$(MODE)/third_party/sqlite3
o/$(MODE)/third_party/sqlite3:					\
	$(THIRD_PARTY_SQLITE3_BINS)				\
	$(THIRD_PARTY_SQLITE3_CHECKS)
