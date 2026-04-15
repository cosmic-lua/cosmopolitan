#ifndef COSMOPOLITAN_LIBC_CALLS_CAP_H_
#define COSMOPOLITAN_LIBC_CALLS_CAP_H_
COSMOPOLITAN_C_START_

#define _LINUX_CAPABILITY_VERSION_1 0x19980330
#define _LINUX_CAPABILITY_VERSION_2 0x20071026
#define _LINUX_CAPABILITY_VERSION_3 0x20080522
#define _LINUX_CAPABILITY_U32S_3    2

struct __user_cap_header_struct {
  uint32_t version;
  int pid;
};

struct __user_cap_data_struct {
  uint32_t effective;
  uint32_t permitted;
  uint32_t inheritable;
};

int capget(struct __user_cap_header_struct *,
           struct __user_cap_data_struct *) libcesque;
int capset(struct __user_cap_header_struct *,
           const struct __user_cap_data_struct *) libcesque;

COSMOPOLITAN_C_END_
#endif /* COSMOPOLITAN_LIBC_CALLS_CAP_H_ */
