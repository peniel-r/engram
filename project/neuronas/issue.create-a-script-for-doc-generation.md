---
id: issue.create-a-script-for-doc-generation
title: Create a script for doc generation
tags: [feature]
type: issue
updated: "2026-02-14T14:28:35Z"
context:
  status: in_progress
  priority: 3
---

# Create a script for doc generation

## Problem

We need to add a way for users to read the manual easily without extra tools besides a web browser

## Impact

NA

## Proposed Solution

Create a powershell/bash script that renders the manual.md file to an html and launches it

## Implementation

Created scripts at:
- `scripts/launch-manual.ps1` - Windows PowerShell script
- `scripts/launch-manual.sh` - Unix/Linux/macOS bash script

These scripts:
1. Search for `manual.md` in multiple locations
2. Convert markdown to HTML using marked.js CDN (no Node.js required)
3. Write HTML to temp directory
4. Open in default browser

Updated `src/cli/man.zig` to locate scripts in:
- Production: Same directory as `engram.exe` (C:\bin\)
- Development: Two directories up + scripts/ (C:\git\Engram\scripts\)

## Acceptance Criteria

- ✅ launch-manual.ps1 and launch-manual.sh Exist and are executable
- ✅ Command `engram man --html` launches the manual.html with the default browser
- ✅ Scripts work in both production and development environments
- ✅ No additional dependencies (uses marked.js CDN for markdown conversion)

