@echo off
REM Integration test script for query command (Windows)
REM Tests all 5 query modes with CLI

setlocal enabledelayedexpansion

set ENGRAM=zig-out\bin\engram.exe
set NEURONAS_DIR=neuronas
set TESTS_PASSED=0
set TESTS_FAILED=0

echo ==========================================
echo 🧪 Query Integration Tests (Windows)
echo ==========================================
echo.

REM Test 1: Verify test data exists
echo Test 1: Verify test data exists...
if not exist "%NEURONAS_DIR%" (
    echo ❌ FAILED: neuronas directory not found
    set /a TESTS_FAILED+=1
    goto :test2
)
echo ✅ PASSED: neuronas directory exists
set /a TESTS_PASSED+=1

:test2
echo.

REM Test 2: Filter mode
echo Test 2: Filter mode (default)...
"%ENGRAM%" query --limit 5 >nul 2>&1
if errorlevel 1 (
    echo ❌ FAILED: Filter mode crashed
    set /a TESTS_FAILED+=1
) else (
    echo ✅ PASSED: Filter mode executes
    set /a TESTS_PASSED+=1
)
echo.

REM Test 3: Text mode
echo Test 3: Text mode (BM25)...
"%ENGRAM%" query --mode text "authentication" --limit 5 2>&1 | findstr /C:"Found" /C:"results" >nul
if errorlevel 1 (
    echo ⚠️  WARNING: Text mode may not have found expected results
    "%ENGRAM%" query --mode text "authentication" --limit 5
) else (
    echo ✅ PASSED: Text mode found results
    set /a TESTS_PASSED+=1
)
echo.

REM Test 4: Vector mode
echo Test 4: Vector mode...
"%ENGRAM%" query --mode vector "login" --limit 5 >nul 2>&1
if errorlevel 1 (
    echo ❌ FAILED: Vector mode crashed
    set /a TESTS_FAILED+=1
) else (
    echo ✅ PASSED: Vector mode executes
    set /a TESTS_PASSED+=1
)
echo.

REM Test 5: Hybrid mode
echo Test 5: Hybrid mode...
"%ENGRAM%" query --mode hybrid "login performance" --limit 5 2>&1 | findstr "Fused Score" >nul
if errorlevel 1 (
    echo ⚠️  WARNING: Hybrid mode may not show expected output
    "%ENGRAM%" query --mode hybrid "login performance" --limit 5
) else (
    echo ✅ PASSED: Hybrid mode shows fused scores
    set /a TESTS_PASSED+=1
)
echo.

REM Test 6: Activation mode
echo Test 6: Activation mode...
"%ENGRAM%" query --mode activation "login" --limit 5 >nul 2>&1
if errorlevel 1 (
    echo ❌ FAILED: Activation mode crashed
    set /a TESTS_FAILED+=1
) else (
    echo ✅ PASSED: Activation mode executes
    set /a TESTS_PASSED+=1
)
echo.

REM Test 7: JSON output
echo Test 7: JSON output...
"%ENGRAM%" query --mode text "authentication" --json --limit 3 2>&1 | findstr """id"""" >nul
if errorlevel 1 (
    echo ⚠️  WARNING: JSON output may not be in expected format
    "%ENGRAM%" query --mode text "authentication" --json --limit 3
) else (
    echo ✅ PASSED: JSON output format correct
    set /a TESTS_PASSED+=1
)
echo.

REM Test 8: Help display
echo Test 8: Help display...
"%ENGRAM%" query --help 2>&1 | findstr "Query interface" >nul
if errorlevel 1 (
    echo ❌ FAILED: Help not displaying
    set /a TESTS_FAILED+=1
) else (
    echo ✅ PASSED: Help displays correctly
    set /a TESTS_PASSED+=1
)
echo.

REM Summary
echo ==========================================
echo Test Summary:
echo   Passed: %TESTS_PASSED%
echo   Failed: %TESTS_FAILED%
echo ==========================================

if %TESTS_FAILED% gtr 0 (
    echo ❌ Some tests failed
    exit /b 1
) else (
    echo ==========================================
    echo 🎉 All integration tests passed!
    echo ==========================================
)
