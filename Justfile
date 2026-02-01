set shell := ["powershell", "-c"]

default:
    @just --list

# Install Engram to %APPDATA%\engram
install:
    @zig build -Doptimize=ReleaseSafe
    @if (!(Test-Path "$env:APPDATA\engram")) { New-Item -ItemType Directory -Force -Path "$env:APPDATA\engram" | Out-Null }
    @Copy-Item zig-out/bin/engram.exe "$env:APPDATA\engram\" -Force
    @Copy-Item docs/manual.md "$env:APPDATA\engram\" -Force
    @Copy-Item scripts/launch-manual.ps1 "$env:APPDATA\engram\" -Force
    @(Get-Content "$env:APPDATA\engram\launch-manual.ps1") -replace '\.\\.\\docs\\manual\\.md', 'manual.md' | Set-Content "$env:APPDATA\engram\launch-manual.ps1" -Encoding UTF8
    @powershell -Command "$t=[System.EnvironmentVariableTarget]::User; $p=[System.Environment]::GetEnvironmentVariable('Path',$t); $a='$env:APPDATA\engram'; if(-not($p.Split(';') -contains $a)){[System.Environment]::SetEnvironmentVariable('Path',$p+';'+$a,$t); Write-Host 'Added to User PATH. Please restart your terminal to use `engram`.'} else {Write-Host 'Already in User PATH.'}"
    @Write-Host "Engram installed to $env:APPDATA\engram"
