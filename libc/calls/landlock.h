#ifndef COSMOPOLITAN_LIBC_CALLS_LANDLOCK_H_
#define COSMOPOLITAN_LIBC_CALLS_LANDLOCK_H_

#define LANDLOCK_CREATE_RULESET_VERSION 0x0001ul

#define LANDLOCK_ACCESS_FS_EXECUTE     0x0001ul
#define LANDLOCK_ACCESS_FS_WRITE_FILE  0x0002ul
#define LANDLOCK_ACCESS_FS_READ_FILE   0x0004ul
#define LANDLOCK_ACCESS_FS_READ_DIR    0x0008ul
#define LANDLOCK_ACCESS_FS_REMOVE_DIR  0x0010ul
#define LANDLOCK_ACCESS_FS_REMOVE_FILE 0x0020ul
#define LANDLOCK_ACCESS_FS_MAKE_CHAR   0x0040ul
#define LANDLOCK_ACCESS_FS_MAKE_DIR    0x0080ul
#define LANDLOCK_ACCESS_FS_MAKE_REG    0x0100ul
#define LANDLOCK_ACCESS_FS_MAKE_SOCK   0x0200ul
#define LANDLOCK_ACCESS_FS_MAKE_FIFO   0x0400ul
#define LANDLOCK_ACCESS_FS_MAKE_BLOCK  0x0800ul
#define LANDLOCK_ACCESS_FS_MAKE_SYM    0x1000ul

/**
 * Allow renaming or linking file to a different directory.
 *
 * @see https://lore.kernel.org/r/20220329125117.1393824-8-mic@digikod.net
 * @see https://docs.kernel.org/userspace-api/landlock.html
 * @note ABI 2+
 */
#define LANDLOCK_ACCESS_FS_REFER 0x2000ul

/**
 * Control file truncation.
 *
 * @see
 * https://lore.kernel.org/all/20221018182216.301684-1-gnoack3000@gmail.com/
 * @see https://docs.kernel.org/userspace-api/landlock.html
 * @note ABI 3+
 */
#define LANDLOCK_ACCESS_FS_TRUNCATE 0x4000ul

/**
 * Control ioctl() on character and block devices.
 *
 * @see https://docs.kernel.org/userspace-api/landlock.html
 * @note ABI 5+
 */
#define LANDLOCK_ACCESS_FS_IOCTL_DEV 0x8000ul

/**
 * Control connecting to a pathname UNIX domain socket.
 *
 * @see https://docs.kernel.org/userspace-api/landlock.html
 * @note ABI 9+
 */
#define LANDLOCK_ACCESS_FS_RESOLVE_UNIX 0x10000ul

/**
 * Control binding a TCP socket to a local port.
 *
 * @see https://docs.kernel.org/userspace-api/landlock.html
 * @note ABI 4+
 */
#define LANDLOCK_ACCESS_NET_BIND_TCP 0x0001ul

/**
 * Control connecting an active TCP socket to a remote port.
 *
 * @see https://docs.kernel.org/userspace-api/landlock.html
 * @note ABI 4+
 */
#define LANDLOCK_ACCESS_NET_CONNECT_TCP 0x0002ul

/**
 * Restrict connecting to an abstract UNIX socket outside the domain.
 *
 * Set in landlock_ruleset_attr::scoped.
 *
 * @see https://docs.kernel.org/userspace-api/landlock.html
 * @note ABI 6+
 */
#define LANDLOCK_SCOPE_ABSTRACT_UNIX_SOCKET 0x0001ul

/**
 * Restrict sending a signal to a process outside the domain.
 *
 * Set in landlock_ruleset_attr::scoped.
 *
 * @see https://docs.kernel.org/userspace-api/landlock.html
 * @note ABI 6+
 */
#define LANDLOCK_SCOPE_SIGNAL 0x0002ul

/**
 * Disable audit logging of denials from the thread creating the domain
 * and its children, for as long as they run the same executable.
 *
 * Passed to landlock_restrict_self().
 *
 * @see https://docs.kernel.org/userspace-api/landlock.html
 * @note ABI 7+
 */
#define LANDLOCK_RESTRICT_SELF_LOG_SAME_EXEC_OFF 0x0001ul

/**
 * Enable audit logging of denials after an execve() within the domain.
 *
 * Passed to landlock_restrict_self().
 *
 * @see https://docs.kernel.org/userspace-api/landlock.html
 * @note ABI 7+
 */
#define LANDLOCK_RESTRICT_SELF_LOG_NEW_EXEC_ON 0x0002ul

/**
 * Disable audit logging of denials from nested domains created by the
 * caller or its descendants.
 *
 * Passed to landlock_restrict_self(). Unlike LOG_SAME_EXEC_OFF this
 * affects only future subdomains, so it is usable with a ruleset_fd of
 * -1 to mute subdomain logs without creating a domain.
 *
 * @see https://docs.kernel.org/userspace-api/landlock.html
 * @note ABI 7+
 */
#define LANDLOCK_RESTRICT_SELF_LOG_SUBDOMAINS_OFF 0x0004ul

/**
 * Apply the domain and its logging configuration atomically to every
 * thread of the calling process, overriding whatever sibling threads
 * had before. Enables no_new_privs on the siblings too when the caller
 * has it.
 *
 * Passed to landlock_restrict_self().
 *
 * @see https://docs.kernel.org/userspace-api/landlock.html
 * @note ABI 8+
 */
#define LANDLOCK_RESTRICT_SELF_TSYNC 0x0008ul

COSMOPOLITAN_C_START_

enum landlock_rule_type {
  LANDLOCK_RULE_PATH_BENEATH = 1,
  /** @note ABI 4+ */
  LANDLOCK_RULE_NET_PORT = 2,
};

struct landlock_ruleset_attr {
  uint64_t handled_access_fs;
  /** @note ABI 4+; kernels below 6.7 reject a size that includes it */
  uint64_t handled_access_net;
  /** @note ABI 6+; kernels below 6.12 reject a size that includes it */
  uint64_t scoped;
};

/**
 * Size of the landlock_ruleset_attr prefix ending with `member`.
 *
 * The kernel infers which ABI a create_ruleset request needs from the
 * size it is handed, and answers E2BIG for a size covering fields it
 * does not know. So pass the shortest prefix covering what was set:
 * handled_access_fs for an ABI 1 request, handled_access_net for an
 * ABI 4 one, scoped for an ABI 6 one. Never sizeof the struct, which
 * grows with each ABI.
 */
#define LANDLOCK_RULESET_ATTR_SIZE(member)          \
  (offsetof(struct landlock_ruleset_attr, member) + \
   sizeof(((struct landlock_ruleset_attr *)0)->member))

struct thatispacked landlock_path_beneath_attr {
  uint64_t allowed_access;
  int32_t parent_fd;
};

/** @note ABI 4+ */
struct landlock_net_port_attr {
  uint64_t allowed_access;
  uint64_t port;
};

int landlock_restrict_self(int, uint32_t);
int landlock_add_rule(int, enum landlock_rule_type, const void *, uint32_t);
int landlock_create_ruleset(const struct landlock_ruleset_attr *, size_t,
                            uint32_t);

COSMOPOLITAN_C_END_
#endif /* COSMOPOLITAN_LIBC_CALLS_LANDLOCK_H_ */
