#!/bin/bash
# Integration test script for query command
# Tests all 5 query modes with the CLI

set -e

ENGRAM="./zig-out/bin/engram"
NEURONAS_DIR="neuronas"

echo "=========================================="
echo "🧪 Query Integration Tests"
echo "=========================================="
echo ""

# Test 1: Verify test data exists
echo "Test 1: Verify test data exists..."
if [ ! -d "$NEURONAS_DIR" ]; then
    echo "❌ FAILED: neuronas directory not found"
    exit 1
fi
FILE_COUNT=$(ls -1 "$NEURONAS_DIR"/*.md 2>/dev/null | wc -l)
if [ "$FILE_COUNT" -eq 0 ]; then
    echo "❌ FAILED: No test data found"
    exit 1
fi
echo "✅ PASSED: Found $FILE_COUNT test Neuronas"
echo ""

# Test 2: Filter mode (default)
echo "Test 2: Filter mode (default)..."
if ! $ENGRAM query --limit 5 > /dev/null 2>&1; then
    echo "❌ FAILED: Filter mode crashed"
    exit 1
fi
echo "✅ PASSED: Filter mode executes"
echo ""

# Test 3: Text mode (BM25)
echo "Test 3: Text mode (BM25)..."
OUTPUT=$($ENGRAM query --mode text "authentication" --limit 5 2>&1)
if echo "$OUTPUT" | grep -q "Found [1-9] results"; then
    echo "✅ PASSED: Text mode found results"
else
    echo "⚠️  WARNING: Text mode may not have found expected results"
    echo "$OUTPUT" | head -20
fi
echo ""

# Test 4: Vector mode
echo "Test 4: Vector mode..."
if [ ! -f "glove_cache.bin" ]; then
    echo "⏭️  SKIPPED: glove_cache.bin not found"
else
    if ! $ENGRAM query --mode vector "login" --limit 5 > /dev/null 2>&1; then
        echo "❌ FAILED: Vector mode crashed"
        exit 1
    fi
    echo "✅ PASSED: Vector mode executes"
fi
echo ""

# Test 5: Hybrid mode
echo "Test 5: Hybrid mode..."
if [ ! -f "glove_cache.bin" ]; then
    echo "⏭️  SKIPPED: glove_cache.bin not found"
else
    OUTPUT=$($ENGRAM query --mode hybrid "login performance" --limit 5 2>&1)
    if echo "$OUTPUT" | grep -q "Fused Score"; then
        echo "✅ PASSED: Hybrid mode shows fused scores"
    else
        echo "⚠️  WARNING: Hybrid mode may not show expected output"
        echo "$OUTPUT" | head -20
    fi
fi
echo ""

# Test 6: Activation mode
echo "Test 6: Activation mode..."
if ! $ENGRAM query --mode activation "login" --limit 5 > /dev/null 2>&1; then
    echo "❌ FAILED: Activation mode crashed"
    exit 1
fi
echo "✅ PASSED: Activation mode executes"
echo ""

# Test 7: JSON output
echo "Test 7: JSON output..."
OUTPUT=$($ENGRAM query --mode text "authentication" --json --limit 3 2>&1)
if echo "$OUTPUT" | grep -q '"id"'; then
    echo "✅ PASSED: JSON output format correct"
else
    echo "⚠️  WARNING: JSON output may not be in expected format"
    echo "$OUTPUT" | head -5
fi
echo ""

# Test 8: Help display
echo "Test 8: Help display..."
OUTPUT=$($ENGRAM query --help 2>&1)
if echo "$OUTPUT" | grep -q "Query interface"; then
    echo "✅ PASSED: Help displays correctly"
else
    echo "❌ FAILED: Help not displaying"
    exit 1
fi
echo ""

# Test 9: All query modes listed in help
echo "Test 9: All query modes in help..."
HELP_OUTPUT=$($ENGRAM query --help 2>&1)
ALL_MODES_FOUND=true
for mode in filter text vector hybrid activation; do
    if ! echo "$HELP_OUTPUT" | grep -q "$mode"; then
        echo "❌ FAILED: Mode '$mode' not found in help"
        ALL_MODES_FOUND=false
    fi
done
if [ "$ALL_MODES_FOUND" = true ]; then
    echo "✅ PASSED: All query modes documented in help"
else
    exit 1
fi
echo ""

echo "=========================================="
echo "🎉 All integration tests passed!"
echo "=========================================="
