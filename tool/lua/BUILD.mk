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
	o/$(MODE)/tool/net/llua.o					\
	o/$(MODE)/tool/net/lsqlite3.o					\
	o/$(MODE)/tool/net/largon2.o					\
	o/$(MODE)/tool/net/lfetch.o					\
	o/$(MODE)/tool/net/lgetopt.o					\
	o/$(MODE)/tool/net/lzip.o					\
	o/$(MODE)/tool/net/lcov.o

# lfetch.c is excluded from TOOL_NET_SRCS (see tool/net/BUILD.mk), so
# mkdeps never scans it and o/$(MODE)/depend carries no header edges for
# it; give it the one that matters for incremental builds by hand.
o/$(MODE)/tool/net/lfetch.o:						\
		tool/net/lfetch.c					\
		tool/net/fetch.inc

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

o/$(MODE)/tool/lua/lua.main.o: third_party/lua/cosmo/lua.main.c
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

o/$(MODE)/tool/lua/test_llua.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_llua.lua
	$< tool/lua/test_llua.lua
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

o/$(MODE)/tool/lua/test_cov.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_cov.lua
	$< tool/lua/test_cov.lua
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

o/$(MODE)/tool/lua/test_unix_ifflags.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_unix_ifflags.lua
	$< tool/lua/test_unix_ifflags.lua
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

o/$(MODE)/tool/lua/test_setfsid.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_setfsid.lua
	$< tool/lua/test_setfsid.lua
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

o/$(MODE)/tool/lua/test_fetch_proxy.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_fetch_proxy.lua
	$< tool/lua/test_fetch_proxy.lua
	@touch $@

o/$(MODE)/tool/lua/test_landlock_net.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_landlock_net.lua
	$< tool/lua/test_landlock_net.lua
	@touch $@

o/$(MODE)/tool/lua/test_landlock_abi.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_landlock_abi.lua
	$< tool/lua/test_landlock_abi.lua
	@touch $@

o/$(MODE)/tool/lua/test_definitions_coverage.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_definitions_coverage.lua tool/net/definitions.lua tool/lua/lcosmo.c third_party/lua/cosmo/lunix.c third_party/lua/cosmo/lreplmod.c tool/net/lpath.c tool/net/lre.c tool/net/largon2.c tool/net/lsqlite3.c tool/net/lgetopt.c tool/net/lzip.c tool/net/lcov.c libc/intrin/kipoptnames.S libc/intrin/ktcpoptnames.S libc/intrin/ksockoptnames.S libc/intrin/kclocknames.S
	$< tool/lua/test_definitions_coverage.lua
	@touch $@

o/$(MODE)/tool/lua/test_definitions_conformance.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_definitions_conformance.lua tool/net/definitions.lua
	$< tool/lua/test_definitions_conformance.lua
	@touch $@

o/$(MODE)/tool/lua/test_definitions_help.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_definitions_help.lua tool/net/definitions.lua tool/net/help.txt third_party/lua/cosmo/lunix.c
	$< tool/lua/test_definitions_help.lua
	@touch $@

o/$(MODE)/tool/lua/test_ssl_roots.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_ssl_roots.lua net/https/sslroots.c $(wildcard usr/share/ssl/root/*.pem)
	$< tool/lua/test_ssl_roots.lua
	@touch $@

o/$(MODE)/tool/lua/test_sqlite_readonly.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_sqlite_readonly.lua
	$< tool/lua/test_sqlite_readonly.lua
	@touch $@

o/$(MODE)/tool/lua/test_sqlite_serialize.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_sqlite_serialize.lua
	$< tool/lua/test_sqlite_serialize.lua
	@touch $@

o/$(MODE)/tool/lua/test_sqlite_open_error.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_sqlite_open_error.lua
	$< tool/lua/test_sqlite_open_error.lua
	@touch $@

o/$(MODE)/tool/lua/test_sqlite_config_error.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_sqlite_config_error.lua
	$< tool/lua/test_sqlite_config_error.lua
	@touch $@

o/$(MODE)/tool/lua/test_sqlite_prepare_error.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_sqlite_prepare_error.lua
	$< tool/lua/test_sqlite_prepare_error.lua
	@touch $@

o/$(MODE)/tool/lua/test_sqlite_deterministic.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_sqlite_deterministic.lua
	$< tool/lua/test_sqlite_deterministic.lua
	@touch $@

o/$(MODE)/tool/lua/test_jsonorg_fail.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_jsonorg_fail.lua
	$< tool/lua/test_jsonorg_fail.lua
	@touch $@

o/$(MODE)/tool/lua/test_jsonorg_pass.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_jsonorg_pass.lua
	$< tool/lua/test_jsonorg_pass.lua
	@touch $@

o/$(MODE)/tool/lua/test_jsontestsuite_fail1.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_jsontestsuite_fail1.lua
	$< tool/lua/test_jsontestsuite_fail1.lua
	@touch $@

o/$(MODE)/tool/lua/test_jsontestsuite_fail2.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_jsontestsuite_fail2.lua
	$< tool/lua/test_jsontestsuite_fail2.lua
	@touch $@

o/$(MODE)/tool/lua/test_jsontestsuite_fail3.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_jsontestsuite_fail3.lua
	$< tool/lua/test_jsontestsuite_fail3.lua
	@touch $@

o/$(MODE)/tool/lua/test_jsontestsuite_fail4.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_jsontestsuite_fail4.lua
	$< tool/lua/test_jsontestsuite_fail4.lua
	@touch $@

o/$(MODE)/tool/lua/test_jsontestsuite_okay.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_jsontestsuite_okay.lua
	$< tool/lua/test_jsontestsuite_okay.lua
	@touch $@

o/$(MODE)/tool/lua/test_jsontestsuite_pass.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_jsontestsuite_pass.lua
	$< tool/lua/test_jsontestsuite_pass.lua
	@touch $@

o/$(MODE)/tool/lua/test_ljson.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_ljson.lua
	$< tool/lua/test_ljson.lua
	@touch $@

o/$(MODE)/tool/lua/test_unix_misc.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_unix_misc.lua
	$< tool/lua/test_unix_misc.lua
	@touch $@

o/$(MODE)/tool/lua/test_unix_setenv.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_unix_setenv.lua
	$< tool/lua/test_unix_setenv.lua
	@touch $@

o/$(MODE)/tool/lua/test_unix_unsetenv.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_unix_unsetenv.lua
	$< tool/lua/test_unix_unsetenv.lua
	@touch $@

o/$(MODE)/tool/lua/test_unix_clearenv.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_unix_clearenv.lua
	$< tool/lua/test_unix_clearenv.lua
	@touch $@

o/$(MODE)/tool/lua/test_unix_execvp.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_unix_execvp.lua
	$< tool/lua/test_unix_execvp.lua
	@touch $@

o/$(MODE)/tool/lua/test_unix_daemon.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_unix_daemon.lua
	$< tool/lua/test_unix_daemon.lua
	@touch $@

o/$(MODE)/tool/lua/test_lua_extensions.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_lua_extensions.lua
	$< tool/lua/test_lua_extensions.lua
	@touch $@

o/$(MODE)/tool/lua/test_fetchstream_edge.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_fetchstream_edge.lua
	$< tool/lua/test_fetchstream_edge.lua
	@touch $@

o/$(MODE)/tool/lua/test_encodejson_default.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_encodejson_default.lua
	$< tool/lua/test_encodejson_default.lua
	@touch $@

o/$(MODE)/tool/lua/test_encodelua_default.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_encodelua_default.lua
	$< tool/lua/test_encodelua_default.lua
	@touch $@

o/$(MODE)/tool/lua/test_base64_vectors.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_base64_vectors.lua
	$< tool/lua/test_base64_vectors.lua
	@touch $@

o/$(MODE)/tool/lua/test_lfuncs_values.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_lfuncs_values.lua
	$< tool/lua/test_lfuncs_values.lua
	@touch $@

o/$(MODE)/tool/lua/test_path_values.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_path_values.lua
	$< tool/lua/test_path_values.lua
	@touch $@

o/$(MODE)/tool/lua/test_unix_readlink.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_unix_readlink.lua
	$< tool/lua/test_unix_readlink.lua
	@touch $@

o/$(MODE)/tool/lua/test_slurp_ranges.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_slurp_ranges.lua
	$< tool/lua/test_slurp_ranges.lua
	@touch $@

o/$(MODE)/tool/lua/test_unix_getlogin.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_unix_getlogin.lua
	$< tool/lua/test_unix_getlogin.lua
	@touch $@

o/$(MODE)/tool/lua/test_unix_uname.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_unix_uname.lua
	$< tool/lua/test_unix_uname.lua
	@touch $@

o/$(MODE)/tool/lua/test_unix_tcattr.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_unix_tcattr.lua
	$< tool/lua/test_unix_tcattr.lua
	@touch $@

o/$(MODE)/tool/lua/test_unix_openpty.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_unix_openpty.lua
	$< tool/lua/test_unix_openpty.lua
	@touch $@

o/$(MODE)/tool/lua/test_build_mk_touch.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/test_build_mk_touch.lua tool/lua/BUILD.mk
	$< tool/lua/test_build_mk_touch.lua
	@touch $@

# Function coverage floor: ftrace every enrolled test, intersect the
# reached functions with nm's per-file listing of the binding sources,
# and fail when a file's covered count drops below tool/lua/coverage_floor.lua.
# The enrolled list is TOOL_LUA_TESTS mapped back to its scripts, so a
# test joins the coverage pass by being enrolled; COVERAGE_BASELINE=1
# rewrites the floor.
o/$(MODE)/tool/lua/test_coverage.ok: o/$(MODE)/tool/lua/lua.dbg tool/lua/coverage.lua tool/lua/coverage_floor.lua tool/lua/BUILD.mk $(wildcard tool/lua/test_*.lua)
	$< tool/lua/coverage.lua $< $(TOOLCHAIN)nm o/$(MODE)/tool/lua tool/lua/coverage_floor.lua $(patsubst o/$(MODE)/tool/lua/%.ok,tool/lua/%.lua,$(filter-out %/test_coverage.ok,$(TOOL_LUA_TESTS)))
	@touch $@

TOOL_LUA_TESTS =							\
	o/$(MODE)/tool/lua/test_cosmo.ok				\
	o/$(MODE)/tool/lua/test_getopt.ok				\
	o/$(MODE)/tool/lua/test_re.ok					\
	o/$(MODE)/tool/lua/test_argon2.ok				\
	o/$(MODE)/tool/lua/test_lfuncs_errors.ok			\
	o/$(MODE)/tool/lua/test_data_formats.ok				\
	o/$(MODE)/tool/lua/test_llua.ok					\
	o/$(MODE)/tool/lua/test_sentinels.ok				\
	o/$(MODE)/tool/lua/test_slurp_barf.ok				\
	o/$(MODE)/tool/lua/test_strftime.ok				\
	o/$(MODE)/tool/lua/test_zip.ok					\
	o/$(MODE)/tool/lua/test_cov.ok					\
	o/$(MODE)/tool/lua/test_zip_append.ok				\
	o/$(MODE)/tool/lua/test_zip_security.ok				\
	o/$(MODE)/tool/lua/test_unix_proc.ok				\
	o/$(MODE)/tool/lua/test_unix_errno.ok				\
	o/$(MODE)/tool/lua/test_unix_ifflags.ok				\
	o/$(MODE)/tool/lua/test_unix_misc.ok				\
	o/$(MODE)/tool/lua/test_unix_setenv.ok				\
	o/$(MODE)/tool/lua/test_unix_unsetenv.ok				\
	o/$(MODE)/tool/lua/test_unix_clearenv.ok				\
	o/$(MODE)/tool/lua/test_unix_execvp.ok				\
	o/$(MODE)/tool/lua/test_unix_daemon.ok				\
	o/$(MODE)/tool/lua/test_lua_extensions.ok			\
	o/$(MODE)/tool/lua/test_fetchstream_edge.ok			\
	o/$(MODE)/tool/lua/test_encodejson_default.ok			\
	o/$(MODE)/tool/lua/test_encodelua_default.ok			\
	o/$(MODE)/tool/lua/test_base64_vectors.ok			\
	o/$(MODE)/tool/lua/test_lfuncs_values.ok			\
	o/$(MODE)/tool/lua/test_path_values.ok				\
	o/$(MODE)/tool/lua/test_unix_readlink.ok			\
	o/$(MODE)/tool/lua/test_slurp_ranges.ok				\
	o/$(MODE)/tool/lua/test_unix_getlogin.ok			\
	o/$(MODE)/tool/lua/test_unix_uname.ok				\
	o/$(MODE)/tool/lua/test_unix_tcattr.ok				\
	o/$(MODE)/tool/lua/test_unix_openpty.ok				\
	o/$(MODE)/tool/lua/test_uuid.ok					\
	o/$(MODE)/tool/lua/test_crypto_hash.ok				\
	o/$(MODE)/tool/lua/test_signal.ok				\
	o/$(MODE)/tool/lua/test_setfsid.ok				\
	o/$(MODE)/tool/lua/test_shm.ok					\
	o/$(MODE)/tool/lua/test_isatty.ok				\
	o/$(MODE)/tool/lua/test_fetch_unix_proxy.ok			\
	o/$(MODE)/tool/lua/test_fetch_local.ok				\
	o/$(MODE)/tool/lua/test_fetch_proxy.ok				\
	o/$(MODE)/tool/lua/test_landlock_net.ok				\
	o/$(MODE)/tool/lua/test_landlock_abi.ok				\
	o/$(MODE)/tool/lua/test_definitions_coverage.ok			\
	o/$(MODE)/tool/lua/test_definitions_conformance.ok		\
	o/$(MODE)/tool/lua/test_definitions_help.ok			\
	o/$(MODE)/tool/lua/test_ssl_roots.ok				\
	o/$(MODE)/tool/lua/test_sqlite_readonly.ok			\
	o/$(MODE)/tool/lua/test_sqlite_serialize.ok			\
	o/$(MODE)/tool/lua/test_sqlite_open_error.ok			\
	o/$(MODE)/tool/lua/test_sqlite_config_error.ok			\
	o/$(MODE)/tool/lua/test_sqlite_prepare_error.ok		\
	o/$(MODE)/tool/lua/test_sqlite_deterministic.ok		\
	o/$(MODE)/tool/lua/test_jsonorg_fail.ok				\
	o/$(MODE)/tool/lua/test_jsonorg_pass.ok				\
	o/$(MODE)/tool/lua/test_jsontestsuite_fail1.ok			\
	o/$(MODE)/tool/lua/test_jsontestsuite_fail2.ok			\
	o/$(MODE)/tool/lua/test_jsontestsuite_fail3.ok			\
	o/$(MODE)/tool/lua/test_jsontestsuite_fail4.ok			\
	o/$(MODE)/tool/lua/test_jsontestsuite_okay.ok			\
	o/$(MODE)/tool/lua/test_jsontestsuite_pass.ok			\
	o/$(MODE)/tool/lua/test_ljson.ok				\
	o/$(MODE)/tool/lua/test_build_mk_touch.ok			\
	o/$(MODE)/tool/lua/test_coverage.ok

ifeq ($(MODE),cov)
# Line coverage of the binding sources: gcc instruments these objects
# (COVERAGE_CFLAGS, build/config.mk) and the runtime in
# libc/intrin/gcov.c dumps a .gcda beside each one at exit. Read with
# the host gcov, from the object directory:
#   gcov -o o/cov/tool/net o/cov/tool/net/lsqlite3.o.gcno
$(TOOL_LUA_LUA_MODULES): private				\
		CFLAGS +=					\
			$(COVERAGE_CFLAGS)

# The ftrace function floor is a measurement of the default mode's -O2
# binary (tool/lua/coverage.lua): at -O0 nothing is inlined and a
# single test's trace runs past its line cap, so the pass cannot finish
# here. This mode measures lines with gcov instead.
TOOL_LUA_TESTS := $(filter-out %/test_coverage.ok,$(TOOL_LUA_TESTS))

# The writer never merges: every process that exits rewrites the file
# whole. So a test run starts from no .gcda at all, and every test
# reruns, so what is left afterwards was written by this run.
.PHONY: o/$(MODE)/tool/lua/gcda.clean
o/$(MODE)/tool/lua/gcda.clean:
	find o/$(MODE) -name '*.gcda' -delete
$(TOOL_LUA_TESTS): o/$(MODE)/tool/lua/gcda.clean
endif

.PHONY: o/$(MODE)/tool/lua
o/$(MODE)/tool/lua:							\
		$(TOOL_LUA_BINS)					\
		$(TOOL_LUA_CHECKS)

.PHONY: o/$(MODE)/tool/lua/test
o/$(MODE)/tool/lua/test:						\
		$(TOOL_LUA_TESTS)
