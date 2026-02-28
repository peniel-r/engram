# Engram

**Engram** is a high-performance CLI tool implementing the **Neurona Knowledge Protocol**. It provides a robust foundation for managing structured knowledge graphs, specifically optimized for Application Lifecycle Management (ALM) and AI-assisted workflows.

Built with **Zig 0.15.2**, Engram offers zero-overhead performance, manual memory control, and sub-10ms graph traversal.

## 🚀 Features

- **ALM First**: Built-in support for requirements, test cases, issues, artifacts and features.
- **EQL (Engram Query Language)**: Powerful structured query syntax for complex filtering.
- **High Performance**: Sub-millisecond cold start and ultra-fast graph traversal.
- **Graph-Aware Knowledge Management**: Create and link Neuronas (knowledge nodes) with 15+ semantic connection types.
- **Offline-First**: Plain-text storage using Markdown and YAML frontmatter.
- **AI-Ready**: Structured metadata and JSON output for seamless LLM integration.
- **Traceability**: Visualize dependency trees and perform impact analysis.
- **Semantic Search**: Five query modes for intelligent search:
  - **Filter Mode**: By type, tags, and connections (default)
  - **EQL Mode**: Structured queries with operators (AND, OR, NOT, parentheses)
  - **Text Mode**: BM25 full-text search with relevance scoring
  - **Vector Mode**: Cosine similarity search with embeddings
  - **Hybrid Mode**: Combined BM25 + vector fusion (0.6/0.4 weights)
  - **Activation Mode**: Neural propagation across graph connections
- **HTML Documentation Viewer**: On-demand markdown-to-HTML conversion with browser rendering (cross-platform).

## 🛠️ Installation

### Prerequisites

- [Zig 0.15.2](https://ziglang.org/download/) or higher.
- [just](https://github.com/casey/just) - Command runner (optional, for using Justfile recipes)

### Installation with Just

If you have [just](https://github.com/casey/just) installed, you can use the provided Justfile:

```bash
just install
```

This will perform the same installation steps as the automated scripts.

### Automated Installation

#### Windows (PowerShell)

```powershell
.\scripts\install.ps1
```

This will:

- Build Engram with ReleaseSafe optimization
- Install to `%APPDATA%\engram`
- Copy the manual and launch scripts
- Add Engram to your User PATH
- Restart your terminal to use `engram` command

#### Unix/Linux/macOS (Bash)

```bash
./scripts/install.sh
```

This will:

- Build Engram with ReleaseSafe optimization
- Install executable to `~/.local/bin`
- Install data files to `~/.local/share/engram`
- Automatically add `~/.local/bin` to PATH in your shell config
- Restart your shell or run `source ~/.bashrc`/`source ~/.zshrc`

### Build from Source

```bash
git clone https://github.com/yourusername/Engram.git
cd Engram
zig build -Doptimize=ReleaseSafe
```

The binary will be available in `zig-out/bin/engram`.

## 📦 Using Engram as a Library

Engram can be used as a Zig library in your own applications. The library provides core types and utilities for working with the Neurona Knowledge Protocol.

### Quick Start

```zig
const Engram = @import("Engram");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a neurona
    var neurona = try Engram.Neurona.init(allocator);
    defer neurona.deinit(allocator);
    
    neurona.id = "concept.001";
    neurona.title = "My Concept";
    neurona.type = .concept;

    // Add connections
    const conn = Engram.Connection{
        .target_id = "concept.002",
        .connection_type = .parent,
        .weight = 90,
    };
    try neurona.addConnection(allocator, conn);
}
```

### Running Examples

```bash
# Basic usage example
zig build example-basic

# ALM integration example  
zig build example-alm

# Custom query example
zig build example-query
```

### Library API

The library provides:
- **Core Types**: `Neurona`, `NeuronaType`, `Connection`, `ConnectionType`, `Context`
- **Utilities**: `Json`, `TextProcessor`, `CortexResolver`

See [docs/LIBRARY_API.md](docs/LIBRARY_API.md) for complete API documentation.

## 📖 Usage

### Initialize a Cortex

```bash
engram init my_project --type alm
```

### Create a Neurona

```bash
engram new requirement "User Authentication" --tag auth
engram new test_case "Login Test" --validates req.auth.user-authentication
```

### Link Neuronas

```bash
engram link issue.auth.001 req.auth.user-authentication blocks
```

Valid connection types: `validates`, `validated_by`, `blocks`, `blocked_by`, `implements`, `implemented_by`, `tested_by`, `tests`, `parent`, `child`, `relates_to`, `prerequisite`, `next`, `related`, `opposes`

### Update Neuronas

```bash
# Update context fields
engram update req.001 --set "context.status=implemented"
engram update req.001 --set "context.priority=1"
engram update req.001 --set "context.assignee=alice"

# Tag management
engram update req.001 --add-tag "security"
engram update req.001 --add-tag "high-priority"
engram update req.001 --remove-tag "draft"

# Multiple updates at once
engram update req.001 --set "context.status=implemented" --set "context.assignee=alice"
```

### Visualize Dependencies

```bash
engram trace req.auth.user-authentication
```

### Impact Analysis

```bash
engram impact req.auth
```

### Link Code Artifacts

```bash
engram link-artifact req.auth zig --file src/auth.zig
```

### Check Status

```bash
engram status
engram status --type issue --filter "state:open AND priority:1"
```

### Release Readiness

```bash
engram release-status
engram release-status --verbose
```

### Project Metrics

```bash
engram metrics
engram metrics --last 7
```

### View Documentation

```bash
# View quick reference in terminal
engram man

# Open full manual in web browser (HTML format)
engram man --html
```

### Query Interface

```bash
# Filter mode (default) - by type, tags, connections
engram query --type issue
engram query --type issue --limit 10

# EQL (Engram Query Language) - Structured queries
engram query "type:issue AND priority:1"
engram query "type:issue AND state:open"
engram query "type:requirement OR type:test_case"
engram query "(type:requirement OR type:issue) AND priority:lte:3"
engram query "type:requirement AND NOT priority:1"
engram query "link(validates, req.auth.login)"
engram query "priority:gte:2"
engram query "type:test_case AND (status:passing OR status:failing)"

# BM25 full-text search
engram query --mode text "authentication"
engram query --mode text "password validation" --limit 5

# Vector similarity search
engram query --mode vector "user login"
engram query --mode vector "performance" --limit 3

# Hybrid search (BM25 + vector fusion)
engram query --mode hybrid "login failure"
engram query --mode hybrid "performance" --limit 5

# Neural activation search
engram query --mode activation "login"
engram query --mode activation "critical" --limit 5

# Natural language queries (auto-detected)
engram query "show me all open issues"
engram query "find tests that are failing"

# JSON output (works with all modes)
engram query --mode text "authentication" --json
engram query --mode hybrid "login" --json --limit 3
```

#### EQL Syntax Reference

EQL supports powerful structured queries with operators:

- **Logical Operators**: `AND`, `OR`, `NOT`, `()` (grouping)
- **Comparison Operators**: `eq` (default), `contains`, `gte`, `lte`, `gt`, `lt`
- **Fields**: `type`, `tag`, `priority`, `title`, `context.*`
- **Link Queries**: `link(type, target_id)`

**Examples**:
```bash
# Simple type filter
engram query "type:issue"

# Complex logical expression
engram query "(type:requirement OR type:issue) AND priority:1"

# Link query
engram query "link(validates, req.auth.login) AND type:test_case"

# With operators
engram query "priority:gte:2 AND priority:lte:4"

# Content search
engram query "title:contains:oauth"
```

## 🤖 AI Agent Integration

Engram is designed from the ground up for AI agent and LLM-powered automation:

### AI Agent Workflow

```bash
# 1. Initialize project and get structure
engram init my_project --type alm
engram status --json > project_state.json

# 2. Query for relevant artifacts
engram query --type requirement --state draft --json
engram query "type:requirement AND NOT link(validates, type:test_case)" --json

# 3. Analyze impact before changes
engram impact src/auth/login.zig --json --down

# 4. Execute operations based on analysis
engram update req.auth --set "context.status=implemented"

# 5. Sync after manual edits
engram sync
```

### Key AI Features

- **Structured JSON Output**: Every command returns parseable JSON for programmatic access
- **LLM-Optimized Metadata**: Token-efficient `_llm` metadata for AI consumption
- **Semantic Search**: Vector embeddings for understanding meaning beyond keywords
- **Natural Language Queries**: Parse plain English queries programmatically
- **Impact Analysis**: Predict effects of changes before making them
- **EQL Query Language**: Structured queries with logical operators (AND, OR, NOT)
- **Tag Management**: Programmatic tag operations via --add-tag and --remove-tag flags

### Core AI Commands

| Command | Purpose |
|---------|---------|
| `engram status --json` | Project overview |
| `engram query --json` | Search/filter artifacts |
| `engram show <id> --json` | Get Neurona details |
| `engram trace <id> --json` | Dependency analysis |
| `engram impact <artifact> --json` | Change impact |
| `engram release-status --json` | Release readiness |
| `engram metrics --json` | Statistics |

### Example Integration

```bash
# Find requirements without tests and generate them
engram query "type:requirement AND state:approved AND NOT link(validates, type:test_case)" --json | \
  ai-generate-tests | \
  jq -r '.[] | "engram new test_case \"\(.title)\" --validates \(.validates)"' | \
  bash

# Analyze code changes and get affected tests
git diff HEAD~1 --name-only | while read file; do
  engram impact "$file" --json --down | \
    jq -r '.affected_items[] | select(.type == "test_case") | .id'
done
```

For comprehensive AI agent documentation, see [docs/AI_AGENTS_GUIDE.md](docs/AI_AGENTS_GUIDE.md).

## 🧪 Development

### Running Tests

Engram maintains a comprehensive test suite with leak detection enabled.

```bash
# Run all tests
zig build test

# Run integration tests (Linux/Git Bash)
bash test_query_integration.sh

# Run integration tests (Windows)
test_query_integration.bat
```

See [QUERY_INTEGRATION_TESTS.md](QUERY_INTEGRATION_TESTS.md) for complete integration test documentation.

### Performance Benchmarks

```bash
zig build bench
```

## 📄 License

This project is licensed under the MIT License - see [LICENSE](LICENSE) file for details.

## 📚 Documentation

- [User Manual](docs/manual.md) - Complete guide for users and developers
- [AI Agents Guide](docs/AI_AGENTS_GUIDE.md) - AI/LLM integration documentation
- [Master Plan](docs/PLAN.md) - Complete project roadmap and architecture

---
*Part of the Neurona Knowledge Protocol ecosystem.*
