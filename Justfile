set windows-shell := ["powershell.exe", "-NoLogo", "-Command"]

default:
    @just --list

# Install Engram (delegates to platform-specific script)
[linux]
install:
    ./scripts/install.sh

[macos]
install:
    ./scripts/install.sh

[windows]
install:
    powershell -ExecutionPolicy Bypass -File ./scripts/install.ps1

# Build for release (Clean & Build)
[linux]
release-build:
    rm -rf zig-out
    zig build -Doptimize=ReleaseSafe

[macos]
release-build:
    rm -rf zig-out
    zig build -Doptimize=ReleaseSafe

[windows]
release-build:
    powershell -ExecutionPolicy Bypass -Command "if (Test-Path zig-out) { Remove-Item -Recurse -Force zig-out }; zig build -Doptimize=ReleaseSafe"
