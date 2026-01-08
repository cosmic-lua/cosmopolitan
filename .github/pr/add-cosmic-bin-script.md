# bin: add cosmic bootstrap script

Adds a shell script that downloads and executes cosmic-lua from GitHub releases, and updates Claude Code settings to use it directly.

- bin/cosmic - bootstrap script that downloads cosmic-lua on first run and executes it with arguments
- .claude/settings - updated SessionStart hook to run bin/cosmic directly
- Makefile - removed bootstrap target (now handled by Claude Code hook)

The script automatically downloads the cosmic-lua binary from the GitHub release URL (home-2026-01-05-a64eed2) on first run, caches it in the bin directory, and executes it with any provided arguments. The Claude Code SessionStart hook now runs bin/cosmic directly to set up the environment.

## Validation

- [x] Script created with proper permissions
- [x] Script includes error handling (set -e)
- [x] Downloads from newer release URL
- [x] Caches binary for subsequent runs
- [x] Claude Code settings updated to use bin/cosmic
- [x] Makefile bootstrap target removed
