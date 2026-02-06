# Engram Installer for Windows
# Installs Engram to %APPDATA%\engram

# Get the script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# Installation directory
$InstallDir = "$env:APPDATA\engram"

Write-Host "Building Engram..." -ForegroundColor Cyan

# Clean previous build
if (Test-Path "$ProjectRoot\zig-out") {
    Write-Host "Cleaning previous build..." -ForegroundColor Gray
    Remove-Item -Recurse -Force "$ProjectRoot\zig-out"
}

try {
    zig build -Doptimize=ReleaseSafe
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Build failed. Please fix build errors and try again."
        exit 1
    }
} catch {
    Write-Error "Error running zig build: $_"
    exit 1
}

# Create installation directory if it doesn't exist
if (!(Test-Path $InstallDir)) {
    Write-Host "Creating installation directory: $InstallDir" -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
}

# Copy executable
Write-Host "Copying executable..." -ForegroundColor Cyan
Copy-Item "$ProjectRoot\zig-out\bin\engram.exe" "$InstallDir\" -Force

# Copy manual
Write-Host "Copying manual..." -ForegroundColor Cyan
Copy-Item "$ProjectRoot\docs\manual.md" "$InstallDir\" -Force

# Copy launch script and fix path
Write-Host "Copying launch script..." -ForegroundColor Cyan
Copy-Item "$ProjectRoot\scripts\launch-manual.ps1" "$InstallDir\" -Force
(Get-Content "$InstallDir\launch-manual.ps1") -replace '\.\\.\\docs\\manual\\.md', 'manual.md' | Set-Content "$InstallDir\launch-manual.ps1" -Encoding UTF8

# Add to PATH if not already present
Write-Host "Checking PATH configuration..." -ForegroundColor Cyan
$t = [System.EnvironmentVariableTarget]::User
$p = [System.Environment]::GetEnvironmentVariable('Path', $t)
$a = $InstallDir

if (-not ($p.Split(';') -contains $a)) {
    [System.Environment]::SetEnvironmentVariable('Path', "$p;$a", $t)
    Write-Host "Added to User PATH." -ForegroundColor Green
    Write-Host "Please restart your terminal to use 'engram' command." -ForegroundColor Yellow
} else {
    Write-Host "Already in User PATH." -ForegroundColor Green
}

Write-Host "`nEngram installed successfully to: $InstallDir" -ForegroundColor Green
Write-Host "You can now run 'engram --help' from a new terminal." -ForegroundColor Cyan