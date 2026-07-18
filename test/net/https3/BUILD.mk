#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += TEST_NET_HTTPS3

TEST_NET_HTTPS3_SRCS := $(wildcard test/net/https3/*.c)
TEST_NET_HTTPS3_SRCS_TEST = $(filter %_test.c,$(TEST_NET_HTTPS3_SRCS))
TEST_NET_HTTPS3_BINS = $(TEST_NET_HTTPS3_COMS) $(TEST_NET_HTTPS3_COMS:%=%.dbg)

TEST_NET_HTTPS3_OBJS =						\
	$(TEST_NET_HTTPS3_SRCS:%.c=o/$(MODE)/%.o)

TEST_NET_HTTPS3_COMS =						\
	$(TEST_NET_HTTPS3_SRCS:%.c=o/$(MODE)/%)

TEST_NET_HTTPS3_TESTS =						\
	$(TEST_NET_HTTPS3_SRCS_TEST:%.c=o/$(MODE)/%.ok)

TEST_NET_HTTPS3_CHECKS =					\
	$(TEST_NET_HTTPS3_SRCS_TEST:%.c=o/$(MODE)/%.runs)

TEST_NET_HTTPS3_DIRECTDEPS =					\
	LIBC_LOG						\
	LIBC_TESTLIB						\
	NET_HTTPS3						\
	THIRD_PARTY_MBEDTLS3					\

TEST_NET_HTTPS3_DEPS :=						\
	$(call uniq,$(foreach x,$(TEST_NET_HTTPS3_DIRECTDEPS),$($(x))))

o/$(MODE)/test/net/https3/https3.pkg:				\
		$(TEST_NET_HTTPS3_OBJS)				\
		$(foreach x,$(TEST_NET_HTTPS3_DIRECTDEPS),$($(x)_A).pkg)

o/$(MODE)/test/net/https3/%.dbg:				\
		$(TEST_NET_HTTPS3_DEPS)				\
		o/$(MODE)/test/net/https3/%.o			\
		$(LIBC_TESTMAIN)				\
		$(CRT)						\
		$(APE_NO_MODIFY_SELF)
	@$(APELINK)

.PHONY: o/$(MODE)/test/net/https3
o/$(MODE)/test/net/https3:					\
		$(TEST_NET_HTTPS3_BINS)				\
		$(TEST_NET_HTTPS3_CHECKS)
