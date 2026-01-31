# Engram Manual Launcher for Windows
# Renders manual.md to HTML and opens it in default browser
# This version does simple markdown-to-HTML conversion in PowerShell

# Get the directory where this script is located
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Try to find manual.md in multiple locations
$ManualPaths = @(
    (Join-Path $ScriptDir "..\docs\manual.md"),
    "C:\git\Engram\docs\manual.md",
    (Join-Path $PSScriptRoot "..\..\..\..\git\Engram\docs\manual.md")
)

$ManualPath = $null
foreach ($path in $ManualPaths) {
    if (Test-Path $path) {
        $ManualPath = $path
        break
    }
}

if (-not $ManualPath) {
    Write-Error "Error: Cannot find manual.md"
    Write-Error "Tried:"
    foreach ($path in $ManualPaths) {
        Write-Error "  - $path"
    }
    exit 1
}

# Path to output HTML
$OutputPath = Join-Path $env:TEMP "engram-manual.html"

if (-not (Test-Path $ManualPath)) {
    Write-Error "Error: Cannot find manual.md at $ManualPath"
    exit 1
}

# Read markdown content
$MarkdownContent = Get-Content $ManualPath -Raw -Encoding UTF8

# Simple markdown-to-HTML conversion (handles CRLF line endings)
function Convert-MarkdownToHtml {
    param([string]$markdown)

    # Normalize line endings to LF
    $text = $markdown -replace "`r`n", "`n"

    # Escape HTML first
    $text = $text -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'

    # Headers (handle both LF and CRLF)
    $text = $text -replace "(?m)^### (.+)$", '<h3>$1</h3>'
    $text = $text -replace "(?m)^## (.+)$", '<h2>$1</h2>'
    $text = $text -replace "(?m)^# (.+)$", '<h1>$1</h1>'

    # Bold
    $text = $text -replace '\*\*(.+?)\*\*', '<strong>$1</strong>'

    # Italic
    $text = $text -replace '\*(.+?)\*', '<em>$1</em>'

    # Inline code
    $text = $text -replace '`([^`]+?)`', '<code>$1</code>'

    # Horizontal rules
    $text = $text -replace '(?m)^---$', '<hr>'

    # Links [text](url)
    $text = $text -replace '\[([^\]]+)\]\(([^\)]+)\)', '<a href="$2">$1</a>'

    # Line breaks
    $text = $text -replace "`n`n", '</p><p>'
    $text = $text -replace "`n", '<br>'

    return $text
}

$HtmlContent = Convert-MarkdownToHtml $MarkdownContent

# Create final HTML document
$FinalHtml = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Engram User Manual</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            line-height: 1.6;
            max-width: 900px;
            margin: 0 auto;
            padding: 20px;
            color: #333;
            background-color: #fff;
        }}
        h1, h2, h3 {{
            margin-top: 1.5em;
            margin-bottom: 0.5em;
            color: #2c3e50;
            border-bottom: 1px solid #eee;
            padding-bottom: 0.3em;
        }}
        h1 {{
            border-bottom: 2px solid #3498db;
            padding-bottom: 0.5em;
        }}
        code {{
            background-color: #f4f4f4;
            padding: 0.2em 0.4em;
            border-radius: 3px;
            font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
            font-size: 0.9em;
        }}
        pre {{
            background-color: #2d2d2d;
            color: #f8f8f2;
            padding: 1em;
            border-radius: 5px;
            overflow-x: auto;
        }}
        blockquote {{
            border-left: 4px solid #3498db;
            padding-left: 1em;
            margin-left: 0;
            color: #666;
            background-color: #f9f9f9;
            padding: 1em;
        }}
        hr {{
            border: none;
            border-top: 2px solid #eee;
            margin: 2em 0;
        }}
        a {{
            color: #3498db;
            text-decoration: none;
        }}
        a:hover {{
            text-decoration: underline;
        }}
        ul, ol {{
            padding-left: 2em;
        }}
        li {{
            margin: 0.5em 0;
        }}
        .content {{
            margin-top: 2em;
        }}
    </style>
</head>
<body>
    <div class="content">
        <p>$HtmlContent</p>
    </div>
</body>
</html>
"@

Set-Content -Path $OutputPath -Value $FinalHtml -Encoding UTF8
Write-Host "Manual rendered to: $OutputPath"
Start-Process $OutputPath
