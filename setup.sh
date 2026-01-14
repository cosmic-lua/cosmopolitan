#!/bin/sh
set -e

# Detect platform
os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m)

# Normalize architecture names
case "${arch}" in
    x86_64|amd64)
        arch="x86_64"
        ;;
    aarch64)
        arch="arm64"
        ;;
    arm64)
        arch="arm64"
        ;;
    *)
        echo "Error: Unsupported architecture: ${arch}" >&2
        exit 1
        ;;
esac

# Normalize OS names
case "${os}" in
    darwin)
        os="darwin"
        ;;
    linux)
        os="linux"
        ;;
    *)
        echo "Error: Unsupported OS: ${os}" >&2
        exit 1
        ;;
esac

# Construct the platform-specific binary name
platform_binary="home-${os}-${arch}"

# Set the release URL
# TODO: Update this to point to the latest release tag
release_tag="2026-01-14-2b98c8f"
url="https://github.com/whilp/world/releases/download/${release_tag}/${platform_binary}"

# Create temporary directory
tmpdir=$(mktemp -d)
trap 'rm -rf "${tmpdir}"' EXIT

echo "Downloading ${platform_binary} for ${os}/${arch}..." >&2

# Download the platform-specific home binary
if ! curl -fsSL -o "${tmpdir}/home" "${url}"; then
    echo "Error: Failed to download ${platform_binary} from ${url}" >&2
    exit 1
fi

# Make it executable
chmod +x "${tmpdir}/home"

echo "Download complete. Binary is available at: ${tmpdir}/home" >&2

# Execute home with any provided arguments
exec "${tmpdir}/home" "$@"
