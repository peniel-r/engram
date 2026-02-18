#!/bin/bash
# Setup GloVe embeddings for semantic search
# This script downloads GloVe 6B embeddings and prepares them for Engram

set -e

echo "========================================"
echo "GloVe Embeddings Setup for Engram"
echo "========================================"
echo ""

GLOVE_DIR="$HOME/.engram/glove"
GLOVE_FILE="glove.6B.100d.txt"
GLOVE_URL="https://nlp.stanford.edu/data/glove.6B.zip"

# Create directory
mkdir -p "$GLOVE_DIR"

# Check if already downloaded
if [ -f "$GLOVE_DIR/$GLOVE_FILE" ]; then
    echo "✓ GloVe embeddings already exist at: $GLOVE_DIR/$GLOVE_FILE"
    echo ""
else
    echo "Downloading GloVe 6B embeddings (~860MB)..."
    echo "This may take several minutes depending on your connection."
    echo ""
    
    # Download
    cd "$GLOVE_DIR"
    curl -O "$GLOVE_URL"
    
    # Extract
    echo ""
    echo "Extracting embeddings..."
    unzip -q glove.6B.zip
    rm glove.6B.zip
    
    # Keep only 100d version
    rm -f glove.6B.50d.txt glove.6B.200d.txt glove.6B.300d.txt
    
    echo "✓ GloVe embeddings downloaded and extracted"
    echo ""
fi

# Set environment variable
echo "Setting ENGRAM_GLOVE_PATH environment variable..."
export ENGRAM_GLOVE_PATH="$GLOVE_DIR/$GLOVE_FILE"

# Add to shell profile
SHELL_RC="$HOME/.bashrc"
if [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
fi

if ! grep -q "ENGRAM_GLOVE_PATH" "$SHELL_RC"; then
    echo "" >> "$SHELL_RC"
    echo "# Engram GloVe embeddings path" >> "$SHELL_RC"
    echo "export ENGRAM_GLOVE_PATH=\"$GLOVE_DIR/$GLOVE_FILE\"" >> "$SHELL_RC"
    echo "✓ Added ENGRAM_GLOVE_PATH to $SHELL_RC"
else
    echo "✓ ENGRAM_GLOVE_PATH already in $SHELL_RC"
fi

echo ""
echo "========================================"
echo "Setup Complete!"
echo "========================================"
echo ""
echo "GloVe path: $GLOVE_DIR/$GLOVE_FILE"
echo ""
echo "Next steps:"
echo "1. Restart your terminal or run: source $SHELL_RC"
echo "2. Run 'engram sync' to rebuild indices with vector search"
echo "3. Test semantic search: engram query --mode vector \"sensor\""
echo ""
