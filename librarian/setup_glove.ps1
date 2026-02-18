#!/usr/bin/env pwsh
# Setup GloVe embeddings for semantic search
# This script downloads GloVe 6B embeddings and prepares them for Engram

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "GloVe Embeddings Setup for Engram" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Configuration
$GloveDir = Join-Path $env:USERPROFILE ".engram\glove"
$GloveFile = "glove.6B.100d.txt"
$GloveZip = "glove.6B.zip"
$GloveUrl = "https://nlp.stanford.edu/data/glove.6B.zip"
$GloveFullPath = Join-Path $GloveDir $GloveFile

# Create directory if it doesn't exist
if (-not (Test-Path $GloveDir)) {
    New-Item -ItemType Directory -Path $GloveDir -Force | Out-Null
}

# Check if already downloaded
if (Test-Path $GloveFullPath) {
    Write-Host "✓ GloVe embeddings already exist at: $GloveFullPath" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "Downloading GloVe 6B embeddings (~860MB)..." -ForegroundColor Yellow
    Write-Host "This may take several minutes depending on your connection." -ForegroundColor Gray
    Write-Host ""
    
    # Download
    $ZipPath = Join-Path $GloveDir $GloveZip
    try {
        Write-Host "Downloading from: $GloveUrl" -ForegroundColor Gray
        Invoke-WebRequest -Uri $GloveUrl -OutFile $ZipPath -UseBasicParsing
        Write-Host "✓ Download complete" -ForegroundColor Green
    } catch {
        Write-Host "✗ Download failed: $_" -ForegroundColor Red
        exit 1
    }
    
    # Extract
    Write-Host ""
    Write-Host "Extracting embeddings..." -ForegroundColor Yellow
    try {
        Expand-Archive -Path $ZipPath -DestinationPath $GloveDir -Force
        Write-Host "✓ Extraction complete" -ForegroundColor Green
    } catch {
        Write-Host "✗ Extraction failed: $_" -ForegroundColor Red
        exit 1
    }
    
    # Cleanup - remove zip and other dimension files
    Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $GloveDir "glove.6B.50d.txt") -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $GloveDir "glove.6B.200d.txt") -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $GloveDir "glove.6B.300d.txt") -Force -ErrorAction SilentlyContinue
    
    Write-Host "✓ GloVe embeddings downloaded and extracted" -ForegroundColor Green
    Write-Host ""
}

# Set environment variable for current session
Write-Host "Setting ENGRAM_GLOVE_PATH environment variable..." -ForegroundColor Yellow
[System.Environment]::SetEnvironmentVariable("ENGRAM_GLOVE_PATH", $GloveFullPath, [System.EnvironmentVariableTarget]::Process)

# Set user-level environment variable (persists across sessions)
try {
    $CurrentValue = [System.Environment]::GetEnvironmentVariable("ENGRAM_GLOVE_PATH", [System.EnvironmentVariableTarget]::User)
    
    if ($CurrentValue -ne $GloveFullPath) {
        [System.Environment]::SetEnvironmentVariable("ENGRAM_GLOVE_PATH", $GloveFullPath, [System.EnvironmentVariableTarget]::User)
        Write-Host "✓ Added ENGRAM_GLOVE_PATH to user environment variables" -ForegroundColor Green
    } else {
        Write-Host "✓ ENGRAM_GLOVE_PATH already set in user environment variables" -ForegroundColor Green
    }
} catch {
    Write-Host "⚠ Warning: Could not set user environment variable (may require elevation)" -ForegroundColor Yellow
    Write-Host "  You can manually set it: [Environment]::SetEnvironmentVariable('ENGRAM_GLOVE_PATH', '$GloveFullPath', 'User')" -ForegroundColor Gray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "GloVe path: $GloveFullPath" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Restart your PowerShell session to load the environment variable" -ForegroundColor Gray
Write-Host "   (Or run: `$env:ENGRAM_GLOVE_PATH = '$GloveFullPath')" -ForegroundColor Gray
Write-Host "2. Run 'engram sync' to rebuild indices with vector search" -ForegroundColor Gray
Write-Host "3. Test semantic search: engram query --mode vector 'sensor'" -ForegroundColor Gray
Write-Host ""
Write-Host "Current session environment variable set. Persisted for future sessions." -ForegroundColor Green
Write-Host ""
