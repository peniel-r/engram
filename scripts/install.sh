#!/bin/bash
# Engram Installer for Unix/Linux/macOS
# Installs Engram to ~/.local/bin

set -e  # Exit on error

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Installation directory (XDG compliant)
INSTALL_DIR="$HOME/.local/bin"
DATA_DIR="$HOME/.local/share/engram"

echo "Building Engram..."
if ! zig build -Doptimize=ReleaseSafe; then
    echo "Error: Build failed. Please fix build errors and try again."
    exit 1
fi

# Create installation directory if it doesn't exist
echo "Creating installation directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# Create data directory for manual and scripts
echo "Creating data directory: $DATA_DIR"
mkdir -p "$DATA_DIR"

# Copy executable
echo "Copying executable..."
cp "$PROJECT_ROOT/zig-out/bin/engram" "$INSTALL_DIR/engram"
chmod +x "$INSTALL_DIR/engram"

# Copy manual
echo "Copying manual..."
cp "$PROJECT_ROOT/docs/manual.md" "$DATA_DIR/manual.md"

# Copy launch script
echo "Copying launch script..."
cp "$PROJECT_ROOT/scripts/launch-manual.sh" "$DATA_DIR/launch-manual.sh"
chmod +x "$DATA_DIR/launch-manual.sh"

# Fix the path in launch-manual.sh
# Replace ../docs/manual.md references with manual.md
sed -i.bak 's|../docs/manual.md|manual.md|g' "$DATA_DIR/launch-manual.sh"
rm -f "$DATA_DIR/launch-manual.sh.bak"

# Determine shell config file
SHELL_CONFIG=""
if [[ "$SHELL" == *"zsh"* ]]; then
    if [[ -f "$HOME/.zshrc" ]]; then
        SHELL_CONFIG="$HOME/.zshrc"
    fi
elif [[ "$SHELL" == *"bash"* ]]; then
    if [[ -f "$HOME/.bashrc" ]]; then
        SHELL_CONFIG="$HOME/.bashrc"
    elif [[ -f "$HOME/.bash_profile" ]]; then
        SHELL_CONFIG="$HOME/.bash_profile"
    fi
fi

# Check if INSTALL_DIR is in PATH
echo "Checking PATH configuration..."
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    if [[ -n "$SHELL_CONFIG" ]]; then
        echo "Adding $INSTALL_DIR to PATH in $SHELL_CONFIG"
        echo "" >> "$SHELL_CONFIG"
        echo "# Engram" >> "$SHELL_CONFIG"
        echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> "$SHELL_CONFIG"
        echo "Added to PATH in $SHELL_CONFIG. Please restart your shell or run:"
        echo "  source $SHELL_CONFIG"
    else
        echo "Warning: Could not determine shell config file."
        echo "Please add the following to your shell configuration:"
        echo "  export PATH=\"\$PATH:$INSTALL_DIR\""
    fi
else
    echo "Already in PATH."
fi

echo ""
echo "Engram installed successfully!"
echo "  Executable: $INSTALL_DIR/engram"
echo "  Data: $DATA_DIR"
echo ""
echo "You can now run 'engram --help' (restart your shell if PATH was updated)"