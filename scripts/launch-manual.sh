#!/bin/bash
# Engram Manual Launcher for Unix/Linux/macOS
# Renders manual.md to HTML and opens it in the default browser

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Try to find manual.md in multiple locations
MANUAL_PATH=""
for path in \
    "$SCRIPT_DIR/../docs/manual.md" \
    "$HOME/git/Engram/docs/manual.md" \
    "/c/git/Engram/docs/manual.md"
do
    if [ -f "$path" ]; then
        MANUAL_PATH="$path"
        break
    fi
done

# Check if manual.md exists
if [ -z "$MANUAL_PATH" ] || [ ! -f "$MANUAL_PATH" ]; then
    echo "Error: Cannot find manual.md" >&2
    echo "Tried:" >&2
    echo "  - $SCRIPT_DIR/../docs/manual.md" >&2
    echo "  - $HOME/git/Engram/docs/manual.md" >&2
    echo "  - /c/git/Engram/docs/manual.md" >&2
    exit 1
fi

# Path to output HTML (use temp directory so it works from any location)
OUTPUT_PATH="/tmp/engram-manual.html"

# Read markdown content and convert to base64
BASE64=$(base64 -w 0 "$MANUAL_PATH")

# Create HTML with embedded base64 content
cat > "$OUTPUT_PATH" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Engram User Manual</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            line-height: 1.6;
            max-width: 900px;
            margin: 0 auto;
            padding: 20px;
            color: #333;
            background-color: #fff;
        }
        h1, h2, h3, h4, h5, h6 {
            margin-top: 1.5em;
            margin-bottom: 0.5em;
            color: #2c3e50;
            border-bottom: 1px solid #eee;
            padding-bottom: 0.3em;
        }
        h1 {
            border-bottom: 2px solid #3498db;
            padding-bottom: 0.5em;
        }
        code {
            background-color: #f4f4f4;
            padding: 0.2em 0.4em;
            border-radius: 3px;
            font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
            font-size: 0.9em;
        }
        pre {
            background-color: #2d2d2d;
            color: #f8f8f2;
            padding: 1em;
            border-radius: 5px;
            overflow-x: auto;
        }
        pre code {
            background-color: transparent;
            padding: 0;
            color: inherit;
        }
        blockquote {
            border-left: 4px solid #3498db;
            padding-left: 1em;
            margin-left: 0;
            color: #666;
            background-color: #f9f9f9;
            padding: 1em;
        }
        table {
            border-collapse: collapse;
            width: 100%;
            margin: 1em 0;
        }
        th, td {
            border: 1px solid #ddd;
            padding: 8px 12px;
            text-align: left;
        }
        th {
            background-color: #3498db;
            color: white;
            font-weight: bold;
        }
        tr:nth-child(even) {
            background-color: #f9f9f9;
        }
        a {
            color: #3498db;
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
        ul, ol {
            padding-left: 2em;
        }
        li {
            margin: 0.5em 0;
        }
        hr {
            border: none;
            border-top: 2px solid #eee;
            margin: 2em 0;
        }
        .content {
            margin-top: 2em;
        }
    </style>
</head>
<body>
    <div id="manual-content" class="content"></div>
    <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
    <script>
        // Decode base64 to get the markdown content
        const base64Data = "$BASE64";
        const markdown = atob(base64Data);
        const html = marked.parse(markdown);
        document.getElementById('manual-content').innerHTML = html;
    </script>
</body>
</html>
EOF

echo "Manual rendered to: $OUTPUT_PATH"

# Detect OS and open in the default browser
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    open "$OUTPUT_PATH"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    xdg-open "$OUTPUT_PATH"
else
    echo "Error: Unsupported operating system: $OSTYPE" >&2
    exit 1
fi
