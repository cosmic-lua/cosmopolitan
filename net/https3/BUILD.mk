#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += NET_HTTPS3

NET_HTTPS3_ARTIFACTS += NET_HTTPS3_A
NET_HTTPS3 = $(NET_HTTPS3_A_DEPS) $(NET_HTTPS3_A)
NET_HTTPS3_A = o/$(MODE)/net/https3/https3.a
NET_HTTPS3_A_FILES := $(wildcard net/https3/*)
NET_HTTPS3_A_CERTS := $(wildcard usr/share/ssl/root/*.pem)
NET_HTTPS3_A_HDRS = $(filter %.h,$(NET_HTTPS3_A_FILES))
NET_HTTPS3_A_SRCS = $(filter %.c,$(NET_HTTPS3_A_FILES))

NET_HTTPS3_A_OBJS =				\
	o/$(MODE)/usr/share/ssl/root/.zip.o	\
	$(NET_HTTPS3_A_SRCS:%.c=o/$(MODE)/%.o)	\
	$(NET_HTTPS3_A_CERTS:%=o/$(MODE)/%.zip.o)

NET_HTTPS3_A_CHECKS =				\
	$(NET_HTTPS3_A).pkg			\
	$(NET_HTTPS3_A_HDRS:%=o/$(MODE)/%.ok)

NET_HTTPS3_A_DIRECTDEPS =			\
	LIBC_CALLS				\
	LIBC_FMT				\
	LIBC_INTRIN				\
	LIBC_LOG				\
	LIBC_MEM				\
	LIBC_NEXGEN32E				\
	LIBC_RUNTIME				\
	LIBC_SOCK				\
	LIBC_STDIO				\
	LIBC_STR				\
	LIBC_SYSV				\
	LIBC_THREAD				\
	THIRD_PARTY_COMPILER_RT			\
	THIRD_PARTY_MBEDTLS3			\
	THIRD_PARTY_MUSL			\
	THIRD_PARTY_TZ				\

NET_HTTPS3_A_DEPS :=				\
	$(call uniq,$(foreach x,$(NET_HTTPS3_A_DIRECTDEPS),$($(x))))

$(NET_HTTPS3_A):	net/https3/		\
		$(NET_HTTPS3_A).pkg		\
		$(NET_HTTPS3_A_OBJS)

$(NET_HTTPS3_A).pkg:				\
		$(NET_HTTPS3_A_OBJS)		\
		$(foreach x,$(NET_HTTPS3_A_DIRECTDEPS),$($(x)_A).pkg)

NET_HTTPS3_LIBS = $(foreach x,$(NET_HTTPS3_ARTIFACTS),$($(x)))
NET_HTTPS3_SRCS = $(foreach x,$(NET_HTTPS3_ARTIFACTS),$($(x)_SRCS))
NET_HTTPS3_HDRS = $(foreach x,$(NET_HTTPS3_ARTIFACTS),$($(x)_HDRS))
NET_HTTPS3_OBJS = $(foreach x,$(NET_HTTPS3_ARTIFACTS),$($(x)_OBJS))
NET_HTTPS3_CHECKS = $(foreach x,$(NET_HTTPS3_ARTIFACTS),$($(x)_CHECKS))
$(NET_HTTPS3_A_OBJS): net/https3/BUILD.mk

.PHONY: o/$(MODE)/net/https3
o/$(MODE)/net/https3: $(NET_HTTPS3_CHECKS)
