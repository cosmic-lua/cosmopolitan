#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += TOOL_LUA

TOOL_LUA_FILES := $(wildcard tool/lua/*)
TOOL_LUA_SRCS = $(filter %.c,$(TOOL_LUA_FILES))
TOOL_LUA_HDRS = $(filter %.h,$(TOOL_LUA_FILES))

TOOL_LUA_OBJS =								\
	$(TOOL_LUA_SRCS:%.c=o/$(MODE)/%.o)

TOOL_LUA_BINS =								\
	$(TOOL_LUA_COMS)						\
	$(TOOL_LUA_COMS:%=%.dbg)

TOOL_LUA_COMS =								\
	o/$(MODE)/tool/lua/lua

TOOL_LUA_CHECKS =							\
	$(TOOL_LUA_HDRS:%=o/$(MODE)/%.ok)

################################################################################
# lua standalone with cosmo module

TOOL_LUA_LUA_MODULES =							\
	o/$(MODE)/tool/lua/lcosmo.o					\
	o/$(MODE)/tool/lua/lfuncs3.o					\
	o/$(MODE)/tool/net/lpath.o					\
	o/$(MODE)/tool/net/lre.o					\
	o/$(MODE)/tool/net/ljson.o					\
	o/$(MODE)/tool/net/lsqlite3.o					\
	o/$(MODE)/tool/net/largon2.o					\
	o/$(MODE)/tool/net/lfetch.o					\
	o/$(MODE)/tool/net/lgetopt.o					\
	o/$(MODE)/tool/net/lzip.o

TOOL_LUA_DIRECTDEPS =							\
	DSP_SCALE							\
	LIBC_CALLS							\
	LIBC_FMT							\
	LIBC_INTRIN							\
	LIBC_LOG							\
	LIBC_MEM							\
	LIBC_NEXGEN32E							\
	LIBC_PROC							\
	LIBC_RUNTIME							\
	LIBC_SOCK							\
	LIBC_STDIO							\
	LIBC_STR							\
	LIBC_SYSV							\
	LIBC_SYSV_CALLS							\
	LIBC_THREAD							\
	LIBC_TINYMATH							\
	LIBC_X								\
	NET_HTTP							\
	NET_HTTPS3							\
	THIRD_PARTY_ARGON2						\
	THIRD_PARTY_COMPILER_RT						\
	THIRD_PARTY_GDTOA						\
	THIRD_PARTY_GETOPT						\
	THIRD_PARTY_LINENOISE						\
	THIRD_PARTY_LUA							\
	THIRD_PARTY_LUA_UNIX						\
	THIRD_PARTY_MBEDTLS3						\
	THIRD_PARTY_MUSL						\
	THIRD_PARTY_REGEX						\
	THIRD_PARTY_SQLITE3						\
	THIRD_PARTY_TZ							\
	THIRD_PARTY_ZLIB						\
	TOOL_ARGS

TOOL_LUA_DEPS :=							\
	$(call uniq,$(foreach x,$(TOOL_LUA_DIRECTDEPS),$($(x))))

o/$(MODE)/tool/lua/lua.main.o: third_party/lua/lua.main.c
	@$(COMPILE) -AOBJECTIFY.c $(OBJECTIFY.c) $(OUTPUT_OPTION) -DLUA_COSMO $<

TOOL_LUA_ASSETS =							\
	o/$(MODE)/tool/lua/definitions.lua.zip.o

# definitions.lua is copied to o/$(MODE)/ so needs -C4 to strip o/MODE/tool/lua/
o/$(MODE)/tool/lua/definitions.lua.zip.o: private ZIPOBJ_FLAGS += -C4 -P.lua

# Copy base definitions.lua for embedding to build directory
o/$(MODE)/tool/lua/definitions.lua: tool/net/definitions.lua
	@mkdir -p $(dir $@)
	@cp $< $@

o/$(MODE)/tool/lua/definitions.lua.zip.o: o/$(MODE)/tool/lua/definitions.lua

o/$(MODE)/tool/lua/lua.dbg:						\
		$(TOOL_LUA_DEPS)					\
		$(TOOL_LUA_LUA_MODULES)					\
		o/$(MODE)/tool/lua/lua.main.o				\
		o/$(MODE)/tool/lua/.args.zip.o				\
		$(TOOL_LUA_ASSETS)					\
		$(CRT)							\
		$(APE_NO_MODIFY_SELF)
	@$(APELINK)

$(TOOL_LUA_OBJS): tool/lua/BUILD.mk

o/$(MODE)/tool/lua/test_cosmo.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_cosmo.lua
	$< tool/lua/test_cosmo.lua
	@touch $@

o/$(MODE)/tool/lua/test_strftime.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_strftime.lua
	$< tool/lua/test_strftime.lua
	@touch $@

o/$(MODE)/tool/lua/test_getopt.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_getopt.lua
	$< tool/lua/test_getopt.lua
	@touch $@

o/$(MODE)/tool/lua/test_re.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_re.lua
	$< tool/lua/test_re.lua
	@touch $@

o/$(MODE)/tool/lua/test_argon2.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_argon2.lua
	$< tool/lua/test_argon2.lua
	@touch $@

o/$(MODE)/tool/lua/test_lfuncs_errors.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_lfuncs_errors.lua
	$< tool/lua/test_lfuncs_errors.lua
	@touch $@

o/$(MODE)/tool/lua/test_data_formats.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_data_formats.lua
	$< tool/lua/test_data_formats.lua
	@touch $@

o/$(MODE)/tool/lua/test_sentinels.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_sentinels.lua
	$< tool/lua/test_sentinels.lua
	@touch $@

o/$(MODE)/tool/lua/test_slurp_barf.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_slurp_barf.lua
	$< tool/lua/test_slurp_barf.lua
	@touch $@

o/$(MODE)/tool/lua/test_zip.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_zip.lua
	$< tool/lua/test_zip.lua
	@touch $@

o/$(MODE)/tool/lua/test_zip_append.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_zip_append.lua
	$< tool/lua/test_zip_append.lua
	@touch $@

o/$(MODE)/tool/lua/test_zip_security.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_zip_security.lua
	$< tool/lua/test_zip_security.lua
	@touch $@

o/$(MODE)/tool/lua/test_unix_proc.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_unix_proc.lua
	$< tool/lua/test_unix_proc.lua
	@touch $@

o/$(MODE)/tool/lua/test_unix_errno.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_unix_errno.lua
	$< tool/lua/test_unix_errno.lua
	@touch $@

o/$(MODE)/tool/lua/test_uuid.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_uuid.lua
	$< tool/lua/test_uuid.lua
	@touch $@

o/$(MODE)/tool/lua/test_crypto_hash.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_crypto_hash.lua
	$< tool/lua/test_crypto_hash.lua
	@touch $@

o/$(MODE)/tool/lua/test_signal.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_signal.lua
	$< tool/lua/test_signal.lua
	@touch $@

o/$(MODE)/tool/lua/test_shm.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_shm.lua
	$< tool/lua/test_shm.lua
	@touch $@

o/$(MODE)/tool/lua/test_isatty.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_isatty.lua
	$< tool/lua/test_isatty.lua
	@touch $@

o/$(MODE)/tool/lua/test_fetch_unix_proxy.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_fetch_unix_proxy.lua
	$< tool/lua/test_fetch_unix_proxy.lua
	@touch $@

o/$(MODE)/tool/lua/test_fetch_local.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_fetch_local.lua
	$< tool/lua/test_fetch_local.lua
	@touch $@

o/$(MODE)/tool/lua/test_definitions_coverage.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_definitions_coverage.lua tool/net/definitions.lua tool/lua/lcosmo.c third_party/lua/lunix.c third_party/lua/lreplmod.c tool/net/lpath.c tool/net/lre.c tool/net/largon2.c tool/net/lsqlite3.c tool/net/lgetopt.c tool/net/lzip.c libc/intrin/kipoptnames.S libc/intrin/ktcpoptnames.S libc/intrin/ksockoptnames.S libc/intrin/kclocknames.S
	$< tool/lua/test_definitions_coverage.lua
	@touch $@

o/$(MODE)/tool/lua/test_ssl_roots.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_ssl_roots.lua net/https/sslroots.c $(wildcard usr/share/ssl/root/*.pem)
	$< tool/lua/test_ssl_roots.lua
	@touch $@

TOOL_LUA_TESTS =							\
	o/$(MODE)/tool/lua/test_cosmo.ok				\
	o/$(MODE)/tool/lua/test_getopt.ok				\
	o/$(MODE)/tool/lua/test_re.ok					\
	o/$(MODE)/tool/lua/test_argon2.ok				\
	o/$(MODE)/tool/lua/test_lfuncs_errors.ok			\
	o/$(MODE)/tool/lua/test_data_formats.ok				\
	o/$(MODE)/tool/lua/test_sentinels.ok				\
	o/$(MODE)/tool/lua/test_slurp_barf.ok				\
	o/$(MODE)/tool/lua/test_strftime.ok				\
	o/$(MODE)/tool/lua/test_zip.ok					\
	o/$(MODE)/tool/lua/test_zip_append.ok				\
	o/$(MODE)/tool/lua/test_zip_security.ok				\
	o/$(MODE)/tool/lua/test_unix_proc.ok				\
	o/$(MODE)/tool/lua/test_unix_errno.ok				\
	o/$(MODE)/tool/lua/test_uuid.ok					\
	o/$(MODE)/tool/lua/test_crypto_hash.ok				\
	o/$(MODE)/tool/lua/test_signal.ok				\
	o/$(MODE)/tool/lua/test_shm.ok					\
	o/$(MODE)/tool/lua/test_isatty.ok				\
	o/$(MODE)/tool/lua/test_fetch_unix_proxy.ok			\
	o/$(MODE)/tool/lua/test_fetch_local.ok				\
	o/$(MODE)/tool/lua/test_definitions_coverage.ok			\
	o/$(MODE)/tool/lua/test_ssl_roots.ok

.PHONY: o/$(MODE)/tool/lua
o/$(MODE)/tool/lua:							\
		$(TOOL_LUA_BINS)					\
		$(TOOL_LUA_CHECKS)

.PHONY: o/$(MODE)/tool/lua/test
o/$(MODE)/tool/lua/test:						\
		$(TOOL_LUA_TESTS)
