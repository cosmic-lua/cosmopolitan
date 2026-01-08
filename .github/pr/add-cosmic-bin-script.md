# bin: add cosmic bootstrap script

Adds a shell script that downloads and executes cosmic-lua from GitHub releases.

- bin/cosmic - bootstrap script that downloads cosmic-lua on first run and executes it with arguments

The script automatically downloads the cosmic-lua binary from the GitHub release URL on first run, caches it in the bin directory, and executes it with any provided arguments. This allows users to run cosmic-lua without manually downloading the binary.

## Validation

- [x] Script created with proper permissions
- [x] Script includes error handling (set -e)
- [x] Downloads from specified release URL
- [x] Caches binary for subsequent runs
