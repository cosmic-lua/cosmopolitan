# Lua Bindings Audit - Parameter Issues

## Critical Bug Found: unix.access()

**Location**: `third_party/lua/lunix.c:394-403`

**Issue**: The documentation and implementation have **swapped parameters** for arguments 3 and 4.

### Documentation says:
```lua
unix.access(path:str, how:int[, flags:int[, dirfd:int]])
```

### Implementation does:
```c
faccessat(
    luaL_optinteger(L, 3, AT_FDCWD),  // arg 3 used as dirfd
    luaL_checkstring(L, 1),            // arg 1 as path ✓
    luaL_checkinteger(L, 2),           // arg 2 as mode ✓
    luaL_optinteger(L, 4, 0)           // arg 4 used as flags
)
```

### Correct faccessat signature:
```c
int faccessat(int dirfd, const char *path, int mode, int flags);
```

### Impact:
- Users expecting to pass flags as 3rd argument will actually pass a dirfd
- This will cause EBADF errors when the number is not a valid file descriptor
- Users expecting to pass dirfd as 4th argument will pass flags instead
- Very similar to the readlink bug we just fixed!

### Example of bug:
```lua
-- User tries to use AT_SYMLINK_NOFOLLOW flag
unix.access("file", unix.R_OK, unix.AT_SYMLINK_NOFOLLOW)

-- This actually calls:
faccessat(AT_SYMLINK_NOFOLLOW, "file", R_OK, 0)
-- where AT_SYMLINK_NOFOLLOW (0x100) is used as dirfd → EBADF!
```

### Recommended Fix:
**Option 1**: Swap implementation to match documentation
```c
faccessat(
    luaL_optinteger(L, 4, AT_FDCWD),  // arg 4 as dirfd
    luaL_checkstring(L, 1),            // arg 1 as path
    luaL_checkinteger(L, 2),           // arg 2 as mode
    luaL_optinteger(L, 3, 0)           // arg 3 as flags
)
```

**Option 2**: Update documentation to match implementation (Breaking change!)
```lua
unix.access(path:str, how:int[, dirfd:int[, flags:int]])
```

**Recommendation**: Go with Option 1 - fix the implementation to match docs, as this makes more sense (flags before dirfd, matching the pattern of most other functions).

## Other Functions Reviewed (No Issues Found)

### Functions with dirfd parameters - All correct ✓
- `unix.mkdir()` - dirfd as 3rd param, correct
- `unix.unlink()` - dirfd as 2nd param, correct
- `unix.rmdir()` - dirfd as 2nd param, correct
- `unix.rename()` - olddirfd/newdirfd as 3rd/4th params, correct
- `unix.link()` - olddirfd/newdirfd as 4th/5th params, correct
- `unix.symlink()` - newdirfd as 3rd param, correct
- `unix.chown()` - dirfd as 5th param, correct
- `unix.chmod()` - dirfd as 4th param, correct
- `unix.readlink()` - **FIXED** (was using bufsiz as dirfd)
- `unix.open()` - dirfd as 4th param, correct
- `unix.stat()` - dirfd as 3rd param, correct
- `unix.utimensat()` - dirfd as 6th param, correct

### Functions with size/buffer parameters - All correct ✓
- `unix.read()` - bufsiz as 2nd param, correct
- `unix.write()` - no size param needed (uses string length)
- `unix.readlink()` - **FIXED** (now uses bufsiz correctly)

### Functions with optional flags - All correct ✓
- `unix.fcntl()` - handles various command types correctly
- `unix.dup()` - flags as 3rd param, correct
- `unix.pipe()` - flags as 1st param, correct

## Summary

**Bugs Found**: 2
1. ✅ **FIXED**: `unix.readlink()` - misinterpreted bufsiz as dirfd
2. ❌ **NEEDS FIX**: `unix.access()` - swapped flags and dirfd parameters

**Total Functions Audited**: 40+

## Recommendation

Fix `unix.access()` by swapping the parameter order in the implementation to match the documentation. This is a breaking change but the current behavior is fundamentally broken and likely not being used correctly.
