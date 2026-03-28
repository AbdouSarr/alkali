#!/bin/bash
set -euo pipefail

REPO="abdousarr/alkali"
INSTALL_DIR="/usr/local/bin"
TMP_DIR=$(mktemp -d)

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "Installing Alkali..."

# Check prerequisites
if ! command -v swift &>/dev/null; then
    echo "Error: Swift toolchain not found. Install Xcode or Swift from swift.org."
    exit 1
fi

SWIFT_VERSION=$(swift --version 2>&1 | head -1)
echo "  Swift: $SWIFT_VERSION"

# Clone and build
echo "  Cloning repository..."
git clone --depth 1 --quiet "https://github.com/$REPO.git" "$TMP_DIR/alkali"

echo "  Building (release)..."
cd "$TMP_DIR/alkali"
swift build -c release --disable-sandbox 2>&1 | tail -1

# Install
echo "  Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp ".build/release/alkali" "$INSTALL_DIR/alkali"
chmod +x "$INSTALL_DIR/alkali"

echo ""
echo "Done. Run 'alkali --help' to get started."
echo ""
echo "To set up Claude Code integration:"
echo "  alkali setup --global"
