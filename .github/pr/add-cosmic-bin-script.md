# bin: add cosmic bootstrap script

Adds a shell script that downloads and executes cosmic-lua from GitHub releases, and simplifies the Makefile bootstrap target to use it.

- bin/cosmic - bootstrap script that downloads cosmic-lua on first run and executes it with arguments
- Makefile - simplified bootstrap target to delegate to bin/cosmic script

The script automatically downloads the cosmic-lua binary from the GitHub release URL (home-2026-01-05-a64eed2) on first run, caches it in the bin directory, and executes it with any provided arguments. The Makefile bootstrap target now simply runs bin/cosmic to trigger the download, creates the bin/lua symlink, and updates PATH.

## Validation

- [x] Script created with proper permissions
- [x] Script includes error handling (set -e)
- [x] Downloads from newer release URL
- [x] Caches binary for subsequent runs
- [x] Makefile bootstrap simplified to use bin/cosmic
