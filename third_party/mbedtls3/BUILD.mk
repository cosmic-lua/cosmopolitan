#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_MBEDTLS3

THIRD_PARTY_MBEDTLS3_ARTIFACTS += THIRD_PARTY_MBEDTLS3_A
THIRD_PARTY_MBEDTLS3 = $(THIRD_PARTY_MBEDTLS3_A_DEPS) $(THIRD_PARTY_MBEDTLS3_A)
THIRD_PARTY_MBEDTLS3_A = o/$(MODE)/third_party/mbedtls3/mbedtls3.a
THIRD_PARTY_MBEDTLS3_A_SRCS := $(wildcard third_party/mbedtls3/library/*.c)
THIRD_PARTY_MBEDTLS3_A_HDRS :=						\
	$(wildcard third_party/mbedtls3/library/*.h)			\
	$(wildcard third_party/mbedtls3/include/mbedtls/*.h)		\
	$(wildcard third_party/mbedtls3/include/psa/*.h)
THIRD_PARTY_MBEDTLS3_A_OBJS =						\
	$(THIRD_PARTY_MBEDTLS3_A_SRCS:%.c=o/$(MODE)/%.o)

THIRD_PARTY_MBEDTLS3_A_CHECKS =						\
	$(THIRD_PARTY_MBEDTLS3_A).pkg					\
	$(THIRD_PARTY_MBEDTLS3_A_HDRS:%=o/$(MODE)/%.ok)

THIRD_PARTY_MBEDTLS3_A_DIRECTDEPS =					\
	LIBC_CALLS							\
	LIBC_FMT							\
	LIBC_INTRIN							\
	LIBC_MEM							\
	LIBC_NEXGEN32E							\
	LIBC_RUNTIME							\
	LIBC_SOCK							\
	LIBC_STDIO							\
	LIBC_STR							\
	LIBC_SYSV							\
	THIRD_PARTY_COMPILER_RT						\
	THIRD_PARTY_MUSL						\
	THIRD_PARTY_TZ

THIRD_PARTY_MBEDTLS3_A_DEPS :=						\
	$(call uniq,$(foreach x,$(THIRD_PARTY_MBEDTLS3_A_DIRECTDEPS),$($(x))))

$(THIRD_PARTY_MBEDTLS3_A):						\
		third_party/mbedtls3/library/				\
		$(THIRD_PARTY_MBEDTLS3_A).pkg				\
		$(THIRD_PARTY_MBEDTLS3_A_OBJS)

$(THIRD_PARTY_MBEDTLS3_A).pkg:						\
		$(THIRD_PARTY_MBEDTLS3_A_OBJS)				\
		$(foreach x,$(THIRD_PARTY_MBEDTLS3_A_DIRECTDEPS),$($(x)_A).pkg)

$(THIRD_PARTY_MBEDTLS3_A_OBJS): private					\
			CFLAGS +=					\
				-fdata-sections				\
				-ffunction-sections

THIRD_PARTY_MBEDTLS3_LIBS = $(foreach x,$(THIRD_PARTY_MBEDTLS3_ARTIFACTS),$($(x)))
THIRD_PARTY_MBEDTLS3_SRCS = $(foreach x,$(THIRD_PARTY_MBEDTLS3_ARTIFACTS),$($(x)_SRCS))
THIRD_PARTY_MBEDTLS3_HDRS = $(foreach x,$(THIRD_PARTY_MBEDTLS3_ARTIFACTS),$($(x)_HDRS))
THIRD_PARTY_MBEDTLS3_CHECKS = $(foreach x,$(THIRD_PARTY_MBEDTLS3_ARTIFACTS),$($(x)_CHECKS))
THIRD_PARTY_MBEDTLS3_OBJS = $(foreach x,$(THIRD_PARTY_MBEDTLS3_ARTIFACTS),$($(x)_OBJS))
$(THIRD_PARTY_MBEDTLS3_A_OBJS): third_party/mbedtls3/BUILD.mk

.PHONY: o/$(MODE)/third_party/mbedtls3
o/$(MODE)/third_party/mbedtls3: $(THIRD_PARTY_MBEDTLS3_CHECKS)
