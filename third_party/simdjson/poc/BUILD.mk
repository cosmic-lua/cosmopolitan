#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

# POC only -- not part of any real binary's build. Proves a Lua script
# can call into simdjson end to end, using the real third_party/lua.a
# this tree already builds, plus a standalone simdjson.cc + a thin
# Lua-callable wrapper -- and, for bench.lua, this tree's real
# tool/net/ljson.c linked in alongside it for a same-process perf
# comparison. Run poc/fetch-poc.sh first to materialize
# simdjson.h/simdjson.cc (not vendored -- see ../README.md), then:
#   make -j$(nproc) o//third_party/simdjson/poc/poc.dbg
#   o//third_party/simdjson/poc/poc.dbg third_party/simdjson/poc/demo.lua
#   o//third_party/simdjson/poc/poc.dbg third_party/simdjson/poc/bench.lua

PKGS += THIRD_PARTY_SIMDJSON_POC

THIRD_PARTY_SIMDJSON_POC_HDRS =				\
	third_party/simdjson/poc/simdjson.h

THIRD_PARTY_SIMDJSON_POC_SRCS =				\
	third_party/simdjson/poc/simdjson.cc			\
	third_party/simdjson/poc/lsimdjson.cc			\
	third_party/simdjson/poc/ljson_wrapper.cc		\
	third_party/simdjson/poc/main.cc

THIRD_PARTY_SIMDJSON_POC_C_SRCS =				\
	tool/net/ljson.c

THIRD_PARTY_SIMDJSON_POC_OBJS =				\
	$(THIRD_PARTY_SIMDJSON_POC_SRCS:%.cc=o/$(MODE)/%.o)	\
	$(THIRD_PARTY_SIMDJSON_POC_C_SRCS:%.c=o/$(MODE)/%.o)

THIRD_PARTY_SIMDJSON_POC_DIRECTDEPS =				\
	LIBC_CALLS						\
	LIBC_FMT						\
	LIBC_INTRIN						\
	LIBC_LOG						\
	LIBC_MEM						\
	LIBC_NEXGEN32E						\
	LIBC_STDIO						\
	LIBC_STR						\
	LIBC_SYSV						\
	LIBC_THREAD						\
	THIRD_PARTY_DOUBLECONVERSION				\
	THIRD_PARTY_LIBCXX					\
	THIRD_PARTY_LIBCXXABI					\
	THIRD_PARTY_LIBUNWIND					\
	THIRD_PARTY_LUA

THIRD_PARTY_SIMDJSON_POC_DEPS :=				\
	$(call uniq,$(foreach x,$(THIRD_PARTY_SIMDJSON_POC_DIRECTDEPS),$($(x))))

o/$(MODE)/third_party/simdjson/poc/poc.pkg:			\
		$(THIRD_PARTY_SIMDJSON_POC_OBJS)		\
		$(foreach x,$(THIRD_PARTY_SIMDJSON_POC_DIRECTDEPS),$($(x)_A).pkg)

o/$(MODE)/third_party/simdjson/poc/poc.dbg:			\
		$(THIRD_PARTY_SIMDJSON_POC_DEPS)		\
		$(THIRD_PARTY_SIMDJSON_POC_OBJS)		\
		o/$(MODE)/third_party/simdjson/poc/poc.pkg	\
		$(CRT)						\
		$(APE_NO_MODIFY_SELF)
	@$(APELINK)

$(THIRD_PARTY_SIMDJSON_POC_OBJS): private			\
		OVERRIDE_CXXFLAGS +=				\
			-fexceptions

.PHONY: o/$(MODE)/third_party/simdjson/poc
o/$(MODE)/third_party/simdjson/poc:				\
		o/$(MODE)/third_party/simdjson/poc/poc.dbg
